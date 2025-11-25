"""Audio analysis pipeline (tempo, key, descriptors)."""

from __future__ import annotations

import logging
import os
import time
from pathlib import Path
from typing import Optional

# Ensure numba can cache compiled librosa helpers inside the workspace (sandbox-safe)
_NUMBA_CACHE_ENV = "NUMBA_CACHE_DIR"
if not os.environ.get(_NUMBA_CACHE_ENV):
    try:
        cache_dir = Path(__file__).resolve().parent / ".numba_cache"
        cache_dir.mkdir(parents=True, exist_ok=True)
        os.environ[_NUMBA_CACHE_ENV] = str(cache_dir)
    except OSError:
        # If we cannot create the cache directory, fallback to default behavior.
        pass

import librosa
import numpy as np

from backend.analysis import settings
from backend.analysis.analysis_context import prepare_analysis_context
from backend.analysis.key_detection import KEY_NAMES, detect_global_key
from backend.analysis.pipeline import AnalysisTimer, CalibrationHooks
from backend.analysis.settings import get_adaptive_analysis_params
from backend.analysis.features import (
    calculate_loudness_and_dynamics,
    detect_silence_ratio,
    detect_time_signature,
    estimate_danceability,
    estimate_valence_and_mood,
    extract_additional_descriptors,
    heuristic_danceability,
    tempo_alignment_score,
)
from backend.analysis.tempo_detection import analyze_tempo
from backend.analysis.utils import clamp_to_unit

logger = logging.getLogger(__name__)

ANALYSIS_FFT_SIZE = settings.ANALYSIS_FFT_SIZE
ANALYSIS_HOP_LENGTH = settings.ANALYSIS_HOP_LENGTH
TEMPO_WINDOW_SECONDS = settings.TEMPO_WINDOW_SECONDS

_NOOP_CALIBRATION_HOOKS = CalibrationHooks(
    apply_scalers=lambda result: result,
    apply_key=lambda result: result,
    apply_bpm=lambda result: result,
    apply_models=lambda result: result,
)

def perform_audio_analysis(y, sr, title, artist, calibration_hooks: Optional[CalibrationHooks] = None):
    """
    Shared audio analysis logic for both analyze and analyze_data endpoints.
    Performs BPM, key, and audio feature detection.
    
    Args:
        y: Audio time series (numpy array)
        sr: Sample rate
        title: Song title (for logging)
        artist: Artist name (for logging)
    
    Returns:
        dict: Analysis results with bpm, key, energy, etc.
    """
    start_time = time.time()
    hooks = calibration_hooks or _NOOP_CALIBRATION_HOOKS
    timer = AnalysisTimer()
    
    # Calculate signal duration and get adaptive parameters
    signal_duration = len(y) / sr
    adaptive_params = get_adaptive_analysis_params(signal_duration)
    
    if adaptive_params['is_short_clip']:
        logger.info(
            f"🎬 Short clip detected ({signal_duration:.1f}s) - using adaptive analysis:\n"
            f"   - Tempo window: {adaptive_params['tempo_window']:.1f}s\n"
            f"   - Key window: {adaptive_params['key_window']:.1f}s\n"
            f"   - Confidence threshold: {adaptive_params['confidence_threshold']:.2f}\n"
            f"   - Window consensus: {'enabled' if adaptive_params['use_window_consensus'] else 'disabled'}"
        )
    
    with timer.track("prepare_context"):
        analysis_ctx = prepare_analysis_context(y, sr, tempo_window_override=adaptive_params['tempo_window'])

    y_trimmed = analysis_ctx.y_trimmed
    hop_length = analysis_ctx.hop_length
    descriptor_ctx = analysis_ctx.descriptor_ctx
    stft_magnitude = analysis_ctx.stft_magnitude
    tempo_segment = analysis_ctx.tempo_segment
    tempo_start = analysis_ctx.tempo_start
    tempo_window_meta = analysis_ctx.tempo_window_meta
    tempo_ctx = analysis_ctx.tempo_ctx

    with timer.track("tempo_analysis"):
        tempo_result = analyze_tempo(
            y_trimmed=y_trimmed,
            sr=sr,
            hop_length=hop_length,
            tempo_segment=tempo_segment,
            tempo_start=tempo_start,
            tempo_ctx=tempo_ctx,
            descriptor_ctx=descriptor_ctx,
            stft_magnitude=stft_magnitude,
            tempo_window_meta=tempo_window_meta,
            timer=timer,
            adaptive_params=adaptive_params,
        )

    onset_env = tempo_result.onset_env
    beats = tempo_result.beats
    y_harmonic = tempo_result.y_harmonic
    y_percussive = tempo_result.y_percussive
    stft_percussive = tempo_result.stft_percussive
    stft_harmonic = tempo_result.stft_harmonic
    tempo_percussive_float = tempo_result.tempo_percussive_bpm
    tempo_onset_float = tempo_result.tempo_onset_bpm
    tempo_plp = tempo_result.tempo_plp_bpm
    plp_peak = tempo_result.plp_peak
    best_alias = tempo_result.best_alias
    scored_aliases = tempo_result.scored_aliases
    tempo_window_meta = tempo_result.tempo_window_meta

    final_bpm = tempo_result.bpm
    bpm_confidence = tempo_result.bpm_confidence

    # Phase 4: BPM Guardrails - Check extreme tempos with tempo_alignment_score
    if final_bpm < 60 or final_bpm > 180:
        test_bpm = final_bpm * 2.0 if final_bpm < 60 else final_bpm * 0.5
        # Check bounds (_MIN_ALIAS_BPM=20.0, _MAX_ALIAS_BPM=280.0)
        if 20.0 <= test_bpm <= 280.0:
            original_score = tempo_alignment_score(final_bpm)
            test_score = tempo_alignment_score(test_bpm)
            # If alignment improves by >0.15, apply correction
            if test_score > original_score + 0.15:
                logger.info(
                    f"⚡ Tempo guardrail correction: {final_bpm:.2f} → {test_bpm:.2f} "
                    f"(alignment {original_score:.2f} → {test_score:.2f})"
                )
                final_bpm = test_bpm

    bpm_value = float(final_bpm)
    
    # 2. KEY DETECTION
    key_input = y_harmonic if y_harmonic.size else y
    with timer.track("key_detection"):
        key_analysis = detect_global_key(key_input, sr, adaptive_params=adaptive_params)
    key_idx = key_analysis.get("key_index", 0) % 12
    scale = key_analysis.get("mode", "Major")
    key_confidence = clamp_to_unit(key_analysis.get("confidence"))
    full_key = f"{KEY_NAMES[key_idx]} {scale}"
    chroma_sums = np.array(key_analysis.get("chroma_profile", [0.0] * 12), dtype=float)
    
    # 3. AUDIO FEATURES
    
    # Energy calibration: combine loudness (LUFS-style), percussive drive, and onset density
    if stft_magnitude is not None and stft_magnitude.size > 0:
        # Use the n_fft that was used to create the STFT magnitude spectrogram
        context_n_fft = descriptor_ctx.get("n_fft", ANALYSIS_FFT_SIZE)
        rms = librosa.feature.rms(S=stft_magnitude, frame_length=context_n_fft, hop_length=hop_length)[0]
    elif y_trimmed.size > 0:
        safe_frame_len = min(ANALYSIS_FFT_SIZE, y_trimmed.size)
        if safe_frame_len < ANALYSIS_FFT_SIZE:
            safe_frame_len = 2 ** int(np.floor(np.log2(safe_frame_len)))
            safe_frame_len = max(256, safe_frame_len)
        rms = librosa.feature.rms(y=y_trimmed, frame_length=safe_frame_len, hop_length=hop_length)[0]
    else:
        rms = np.array([0.0])
    rms_db = librosa.amplitude_to_db(rms + 1e-12, ref=1.0)
    loud_rms = float(np.percentile(rms_db, 90))
    energy_rms = float(np.clip((loud_rms + 60.0) / 60.0, 0.0, 1.0))
    
    onset_norm = np.zeros_like(onset_env)
    if onset_env.size > 0:
        onset_norm = onset_env / (np.max(onset_env) + 1e-6)
    pulse_density = float(np.mean(onset_norm)) if onset_norm.size > 0 else 0.0
    
    if stft_percussive is not None:
        percussive_power = float(np.mean(np.abs(stft_percussive) ** 2)) / max(1, ANALYSIS_FFT_SIZE)
    else:
        percussive_power = float(np.mean(y_percussive ** 2)) if y_percussive.size > 0 else 0.0
    if stft_harmonic is not None:
        harmonic_power = float(np.mean(np.abs(stft_harmonic) ** 2)) / max(1, ANALYSIS_FFT_SIZE)
    else:
        harmonic_power = float(np.mean(y_harmonic ** 2)) if y_harmonic.size > 0 else 0.0
    total_power = percussive_power + harmonic_power
    percussive_presence = float(np.clip(percussive_power / (total_power + 1e-9), 0.0, 1.0))
    
    energy = (0.6 * energy_rms) + (0.25 * percussive_presence) + (0.15 * pulse_density)
    energy = clamp_to_unit(energy)
    
    with timer.track("descriptor_extraction"):
        descriptor_features = extract_additional_descriptors(
            y_trimmed,
            sr,
            hop_length,
            onset_env,
            percussive_power,
            harmonic_power,
            y_harmonic,
            y_percussive,
            stft_magnitude=stft_magnitude,
        )
    
    # Spectral centroid (brightness) and acousticness
    with timer.track("spectral_centroid"):
        if stft_magnitude is not None and stft_magnitude.size > 0:
            spectral_centroid = librosa.feature.spectral_centroid(S=stft_magnitude, sr=sr)
        else:
            spectral_centroid = librosa.feature.spectral_centroid(y=y, sr=sr)
    avg_centroid = float(np.mean(spectral_centroid))
    
    # FIX: Better acousticness detection
    # Acoustic instruments have:
    # 1. Lower spectral centroid (warmer sound)
    # 2. Higher harmonic/percussive ratio (more harmonic content)
    # 3. Slower attack times (softer onsets)
    # 4. Less spectral complexity
    
    # Component 1: Spectral warmth (lower centroid = more acoustic)
    centroid_normalized = min(avg_centroid / 4000.0, 1.0)
    warmth_score = 1.0 - centroid_normalized  # Invert: low centroid = warm = acoustic
    
    # Component 2: Harmonic dominance
    total_power = percussive_power + harmonic_power
    if total_power > 0:
        harmonic_ratio = harmonic_power / total_power
    else:
        harmonic_ratio = 0.5
    
    # Component 3: Onset gentleness (acoustic instruments have softer attacks)
    if onset_env.size > 0:
        onset_variance = float(np.std(onset_env))
        onset_mean = float(np.mean(onset_env))
        onset_gentleness = 1.0 - min(onset_variance / (onset_mean + 1e-6), 1.0)
    else:
        onset_gentleness = 0.5
    
    # Combine with proper weighting
    acousticness = clamp_to_unit(
        0.4 * warmth_score +          # Spectral warmth is important
        0.35 * harmonic_ratio +        # Harmonic content matters
        0.25 * onset_gentleness        # Gentle attacks indicate acoustic
    )
    
    with timer.track("danceability"):
        danceability = estimate_danceability(
            y_trimmed,
            sr,
            onset_env,
            onset_norm,
            hop_length,
            beats,
            percussive_presence,
            pulse_density,
            energy,
            bpm_value,
            signal_duration
        )
    danceability = clamp_to_unit(danceability)
    
    # 4. PHASE 1 ADVANCED FEATURES
    
    # Time signature detection
    with timer.track("time_signature"):
        time_signature = detect_time_signature(beats, sr)
    logger.info(f"🎼 Time signature: {time_signature}")
    
    # Valence and mood estimation - now with pitch and spectral features
    with timer.track("valence_mood"):
        # Extract pitch variation for emotional content
        pitch_features = None
        spectral_rolloff_val = None
        try:
            # Pitch tracking on harmonic component
            pitches, magnitudes = librosa.piptrack(
                y=y_harmonic if y_harmonic.size > 0 else y_trimmed,
                sr=sr,
                hop_length=hop_length,
                fmin=librosa.note_to_hz('C2'),
                fmax=librosa.note_to_hz('C7')
            )
            # Get pitch variance (high variance = more expressive/emotional)
            if pitches.size > 0 and magnitudes.size > 0:
                pitch_values = []
                for t in range(pitches.shape[1]):
                    index = magnitudes[:, t].argmax()
                    pitch = pitches[index, t]
                    if pitch > 0:
                        pitch_values.append(pitch)
                if len(pitch_values) > 0:
                    pitch_std = float(np.std(pitch_values))
                    pitch_mean = float(np.mean(pitch_values))
                    pitch_range = float(np.max(pitch_values) - np.min(pitch_values))
                    pitch_features = {
                        'std': pitch_std,
                        'mean': pitch_mean,
                        'range': pitch_range,
                        'variance_ratio': pitch_std / (pitch_mean + 1e-6)
                    }
        except Exception as exc:
            logger.debug("Pitch tracking failed: %s", exc)
        
        # Spectral rolloff (brightness indicator for mood)
        try:
            if stft_magnitude is not None and stft_magnitude.size > 0:
                spectral_rolloff = librosa.feature.spectral_rolloff(S=stft_magnitude, sr=sr)
            else:
                spectral_rolloff = librosa.feature.spectral_rolloff(y=y_trimmed if y_trimmed.size > 0 else y, sr=sr)
            spectral_rolloff_val = float(np.mean(spectral_rolloff))
        except Exception as exc:
            logger.debug("Spectral rolloff failed: %s", exc)
        
        valence, mood = estimate_valence_and_mood(
            bpm_value,
            key_idx,
            scale,
            chroma_sums,
            energy,
            pitch_features=pitch_features,
            spectral_rolloff=spectral_rolloff_val
        )
    logger.info(f"😊 Mood: {mood} (valence: {valence:.2f})")
    
    frame_rms_db_full: Optional[np.ndarray] = None
    if len(y) > 0:
        with timer.track("global_rms"):
            safe_frame_len = min(ANALYSIS_FFT_SIZE, len(y))
            if safe_frame_len < ANALYSIS_FFT_SIZE:
                safe_frame_len = 2 ** int(np.floor(np.log2(safe_frame_len)))
                safe_frame_len = max(256, safe_frame_len)
            full_rms = librosa.feature.rms(
                y=y,
                frame_length=safe_frame_len,
                hop_length=ANALYSIS_HOP_LENGTH,
            )[0]
            frame_rms_db_full = librosa.amplitude_to_db(full_rms + 1e-12, ref=np.max)
    # Loudness and dynamic range
    with timer.track("loudness_dynamics"):
        loudness, dynamic_range = calculate_loudness_and_dynamics(y, sr, frame_rms_db=frame_rms_db_full)
    logger.info(f"🔊 Loudness: {loudness:.1f} dB, Dynamic range: {dynamic_range:.1f} dB")
    
    # Silence detection
    with timer.track("silence_ratio"):
        silence_ratio = detect_silence_ratio(y, sr, frame_rms_db=frame_rms_db_full)
    logger.info(f"🔇 Silence ratio: {silence_ratio:.1%}")
    
    duration = time.time() - start_time
    timer.add("analysis_total", duration)
    
    result = {
        'bpm': bpm_value,
        'bpm_confidence': bpm_confidence,
        'key': full_key,
        'key_confidence': key_confidence,
        'key_details': key_analysis,
        'energy': clamp_to_unit(energy),
        'danceability': clamp_to_unit(danceability),
        'acousticness': acousticness,
        'spectral_centroid': avg_centroid,
        'time_signature': time_signature,
        'valence': valence,
        'mood': mood,
        'loudness': loudness,
        'dynamic_range': dynamic_range,
        'silence_ratio': silence_ratio,
        'analysis_duration': duration,
        'signal_duration': signal_duration,
        'cached': False,
        'tempo_window': tempo_window_meta,
    }
    result['tempo_diagnostics'] = {
        'percussive_bpm': tempo_percussive_float,
        'onset_bpm': tempo_onset_float,
        'plp_bpm': tempo_plp if tempo_plp > 0 else None,
        'plp_peak': plp_peak,
        'selected_candidate': best_alias,
        'candidates': scored_aliases,
    }
    
    result.update(descriptor_features)

    result = hooks.apply_all(result)
    result['analysis_timing'] = timer.snapshot()
    timer.log(f"{title} analysis")
    try:
        logged_bpm = float(result.get('bpm', bpm_value))
    except (TypeError, ValueError):
        logged_bpm = bpm_value
    logger.info(
        f"✅ Analysis complete in {duration:.2f}s - BPM: {logged_bpm:.1f}, Key: {result.get('key', full_key)}, Mood: {result.get('mood', mood)}"
    )
    return result

__all__ = [
    'perform_audio_analysis',
    'detect_time_signature',
    'estimate_valence_and_mood',
    'calculate_loudness_and_dynamics',
    'detect_silence_ratio',
    'tempo_alignment_score',
    'heuristic_danceability',
    'estimate_danceability',
    'extract_additional_descriptors',
]
