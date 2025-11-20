"""Tempo/BPM detection utilities extracted from the analysis pipeline."""

from __future__ import annotations

import logging
import math
from contextlib import nullcontext
from dataclasses import dataclass
from typing import List, Optional

import librosa
import numpy as np

from backend.analysis import settings
from backend.analysis.features import tempo_alignment_score
from backend.analysis.pipeline_context import harmonic_percussive_components
from backend.analysis.utils import clamp_to_unit

logger = logging.getLogger(__name__)

ANALYSIS_FFT_SIZE = settings.ANALYSIS_FFT_SIZE
ANALYSIS_HOP_LENGTH = settings.ANALYSIS_HOP_LENGTH
TEMPO_WINDOW_SECONDS = settings.TEMPO_WINDOW_SECONDS

_ALIAS_FACTORS = (0.5, 1.0, 2.0)
_MIN_ALIAS_BPM = 20.0
_MAX_ALIAS_BPM = 280.0


@dataclass
class TempoResult:
    bpm: float
    bpm_confidence: float
    onset_env: np.ndarray
    beats: np.ndarray
    y_harmonic: np.ndarray
    y_percussive: np.ndarray
    stft_percussive: Optional[np.ndarray]
    stft_harmonic: Optional[np.ndarray]
    tempo_percussive_bpm: float
    tempo_onset_bpm: float
    tempo_plp_bpm: float
    plp_peak: float
    best_alias: Optional[dict]
    scored_aliases: List[dict]
    tempo_window_meta: dict


def _tempo_similarity(candidate_bpm: float, reference_bpm: float) -> float:
    """Return a soft similarity score between tempos (handles 1/2/2x aliases)."""
    if candidate_bpm <= 0 or reference_bpm <= 0:
        return 0.0
    alias_values = [
        reference_bpm * factor
        for factor in _ALIAS_FACTORS
        if reference_bpm * factor > 0
    ]
    if not alias_values:
        return 0.0
    best_diff = min(abs(candidate_bpm - value) for value in alias_values)
    similarity = math.exp(-best_diff / 15.0)
    return float(max(0.0, min(1.0, similarity)))


def _build_tempo_alias_candidates(percussive_bpm: float, onset_bpm: float) -> List[dict]:
    """Generate deduplicated BPM candidates using alias factors for both detectors."""
    candidate_map: dict[float, dict] = {}
    for detector, bpm_value in (("percussive", percussive_bpm), ("onset", onset_bpm)):
        if bpm_value is None or bpm_value <= 0:
            continue
        for factor in _ALIAS_FACTORS:
            candidate = bpm_value * factor
            if candidate <= 0 or candidate < _MIN_ALIAS_BPM or candidate > _MAX_ALIAS_BPM:
                continue
            key = round(candidate, 3)
            entry = candidate_map.setdefault(
                key,
                {
                    "bpm": float(candidate),
                    "sources": [],
                },
            )
            entry["sources"].append(
                {
                    "detector": detector,
                    "factor": float(factor),
                    "base_bpm": float(bpm_value),
                }
            )
    return list(candidate_map.values())


def _score_tempo_alias_candidates(
    candidates: List[dict],
    percussive_bpm: float,
    onset_bpm: float,
    plp_bpm: float,
    plp_peak: float,
    chunk_bpm_std: Optional[float] = None,
    spectral_flux_mean: Optional[float] = None,
    is_short_clip: bool = False,
) -> tuple[Optional[dict], List[dict]]:
    """
    Score each alias candidate using detector agreement + PLP cues + spectral features.
    """
    scored_candidates: List[dict] = []
    chunk_penalty = 1.0
    if chunk_bpm_std is not None:
        chunk_penalty = max(0.3, 1.0 - min(1.0, chunk_bpm_std / 30.0))

    alignment_weight = 0.40
    detector_weight = 0.30
    plp_weight = 0.15
    if is_short_clip:
        # For previews, bias toward detector agreement and PLP rather than mid-tempo priors
        alignment_weight = 0.25
        detector_weight = 0.35
        plp_weight = 0.20

    for entry in candidates:
        bpm_value = float(entry["bpm"])
        alignment = tempo_alignment_score(bpm_value)
        support_scores = []
        for reference in (percussive_bpm, onset_bpm):
            support_scores.append(_tempo_similarity(bpm_value, reference))
        detector_support = float(max(support_scores) if support_scores else 0.0)
        plp_similarity = _tempo_similarity(bpm_value, plp_bpm) if plp_bpm > 0 else 0.0
        multi_source_bonus = min(len(entry.get("sources", [])) * 0.05, 0.15)

        if is_short_clip:
            if 80 <= bpm_value <= 145:
                octave_preference = 0.10
            elif 45 <= bpm_value < 80 or 145 < bpm_value <= 180:
                octave_preference = 0.04
            elif bpm_value > 180:
                octave_preference = 0.06  # light boost so true fast tempos aren't auto-halved
            else:
                octave_preference = 0.0
        else:
            if 80 <= bpm_value <= 145:
                octave_preference = 0.15
            elif 40 <= bpm_value < 80 or 145 < bpm_value <= 180:
                octave_preference = 0.05
            else:
                octave_preference = 0.0

        spectral_octave_hint = 0.0
        agreement_bonus = 0.0
        alias_penalty = 0.0

        if is_short_clip:
            detector_vals = [v for v in (percussive_bpm, onset_bpm) if v and v > 0]
            if len(detector_vals) >= 2:
                spread = max(detector_vals) - min(detector_vals)
                median_val = sorted(detector_vals)[len(detector_vals) // 2]
                if spread <= 3.0 and abs(bpm_value - median_val) <= 2.0:
                    agreement_bonus = 0.05
            sources = entry.get("sources", [])
            if sources and all(abs(src.get("factor", 1.0) - 1.0) > 0.05 for src in sources):
                alias_penalty = 0.04

        base_score = (
            alignment_weight * alignment +
            detector_weight * detector_support +
            plp_weight * plp_similarity +
            multi_source_bonus +
            octave_preference +
            spectral_octave_hint +
            agreement_bonus -
            alias_penalty
        )
        base_score = float(max(0.0, min(1.0, base_score)))
        confidence_boost = 0.7 + 0.3 * clamp_to_unit(plp_peak)
        score = float(max(0.0, min(1.0, base_score * confidence_boost)))
        score *= chunk_penalty
        scored_entry = {
            "bpm": bpm_value,
            "score": score,
            "confidence": score,
            "alignment": alignment,
            "detector_support": detector_support,
            "plp_similarity": plp_similarity,
            "octave_preference": octave_preference,
            "chunk_penalty": chunk_penalty,
            "sources": entry.get("sources", []),
        }
        scored_candidates.append(scored_entry)
    best_entry = max(scored_candidates, key=lambda item: item["score"], default=None)
    return best_entry, scored_candidates


def _compute_onset_energy_separation(
    test_bpm: float,
    onset_env: np.ndarray,
    sr: int,
    hop_length: int,
) -> Optional[float]:
    """Return on/off-beat onset energy separation for a specific BPM."""
    if test_bpm is None or test_bpm <= 0:
        return None
    num_frames = len(onset_env)
    if num_frames == 0:
        return None
    beat_interval_seconds = 60.0 / test_bpm
    beat_interval_frames = int(beat_interval_seconds * sr / hop_length)
    if beat_interval_frames < 2:
        return None

    on_beat_energy: List[float] = []
    off_beat_energy: List[float] = []
    for i in range(0, num_frames, beat_interval_frames):
        on_start = max(i - 1, 0)
        on_end = min(i + 2, num_frames)
        if on_start >= num_frames or on_start >= on_end:
            continue
        on_slice = onset_env[on_start:on_end]
        on_beat_energy.append(float(np.max(on_slice)))

        midpoint = i + beat_interval_frames // 2
        if midpoint >= num_frames:
            continue
        off_start = max(midpoint - 1, 0)
        off_end = min(midpoint + 2, num_frames)
        if off_start >= num_frames or off_start >= off_end:
            continue
        off_slice = onset_env[off_start:off_end]
        off_beat_energy.append(float(np.mean(off_slice)))

    if not on_beat_energy or not off_beat_energy:
        return None

    on_mean = float(np.mean(on_beat_energy))
    off_mean = float(np.mean(off_beat_energy))
    return on_mean / (off_mean + 0.01)


def _validate_octave_with_onset_energy(
    bpm: float,
    onset_env: np.ndarray,
    sr: int,
    hop_length: int
) -> tuple[float, float]:
    """Validate BPM octave by comparing on-beat vs off-beat onset energy."""
    if onset_env is None or len(onset_env) == 0:
        return bpm, 0.0

    test_bpms: List[float] = [bpm]
    half_bpm = bpm * 0.5
    double_bpm = bpm * 2.0
    if half_bpm >= _MIN_ALIAS_BPM:
        test_bpms.append(half_bpm)
    if double_bpm <= _MAX_ALIAS_BPM:
        test_bpms.append(double_bpm)

    best_bpm = bpm
    best_separation = _compute_onset_energy_separation(bpm, onset_env, sr, hop_length)
    if best_separation is None:
        best_separation = 0.0
    
    # Apply octave preference priors per research doc §3.4.2
    # Favor 80-140 BPM (sweet spot for pop/rock/EDM)
    # Strong boost to overcome noisy onset separation in short clips
    def _octave_preference_boost(test_bpm: float) -> float:
        if 80 <= test_bpm <= 140:
            return 1.40  # +40% boost for sweet spot (strong preference)
        elif 40 <= test_bpm < 80 or 140 < test_bpm <= 180:
            return 1.10  # +10% boost for reasonable range
        return 0.90  # -10% penalty outside normal range
    
    best_score = best_separation * _octave_preference_boost(bpm)
    
    for test_bpm in test_bpms:
        if abs(test_bpm - bpm) < 0.1:
            continue
        separation = _compute_onset_energy_separation(test_bpm, onset_env, sr, hop_length)
        if separation is None:
            continue
        # Apply preference boost and require 10% improvement
        score = separation * _octave_preference_boost(test_bpm)
        if score > best_score * 1.10:
            best_score = score
            best_separation = separation
            best_bpm = test_bpm

    return best_bpm, max(0.0, best_separation)


def _safe_hpss_component(component: Optional[np.ndarray], fallback: np.ndarray) -> np.ndarray:
    """Return an HPSS component that is always a valid numpy array for slicing."""
    if component is None:
        return np.array(fallback, copy=True)
    array = np.asarray(component)
    if array.size == 0:
        return np.array(fallback, copy=True)
    return np.ascontiguousarray(array)


def analyze_tempo(
    y_trimmed: np.ndarray,
    sr: int,
    hop_length: int,
    tempo_segment: np.ndarray,
    tempo_start: int,
    tempo_ctx: Optional[dict],
    descriptor_ctx: Optional[dict],
    stft_magnitude: Optional[np.ndarray],
    tempo_window_meta: dict,
    timer=None,
    adaptive_params: Optional[dict] = None,
) -> TempoResult:
    """Compute tempo/BPM and related diagnostics."""
    # Use adaptive parameters if provided, otherwise use defaults for full songs
    if adaptive_params is None:
        from backend.analysis.settings import get_adaptive_analysis_params
        # Estimate duration from signal length
        signal_duration = len(y_trimmed) / sr if sr > 0 else 0
        adaptive_params = get_adaptive_analysis_params(signal_duration)
    
    is_short_clip = adaptive_params.get('is_short_clip', False)
    use_onset_validation = adaptive_params.get('use_onset_validation', True)
    intermediate_threshold = adaptive_params.get('intermediate_correction_threshold', 1.50)
    
    if is_short_clip:
        logger.debug(
            f"🎬 Tempo analysis for short clip: onset_validation={'enabled' if use_onset_validation else 'disabled'}, "
            f"intermediate_threshold={intermediate_threshold:.2f}"
        )
    
    hpss_components = harmonic_percussive_components(tempo_segment, tempo_ctx, hop_length)
    tempo_harmonic = _safe_hpss_component(hpss_components.get("y_harmonic"), tempo_segment)
    tempo_percussive = _safe_hpss_component(hpss_components.get("y_percussive"), tempo_segment)
    stft_percussive = hpss_components.get("stft_percussive")
    stft_harmonic = hpss_components.get("stft_harmonic")

    segment_len = tempo_segment.size
    embedding_end = tempo_start + segment_len
    y_harmonic = np.array(y_trimmed, copy=True)
    y_harmonic[tempo_start:embedding_end] = tempo_harmonic[: segment_len]
    y_percussive = np.array(y_trimmed, copy=True)
    y_percussive[tempo_start:embedding_end] = tempo_percussive[: segment_len]

    with (timer.track("tempo.onset_env") if timer else nullcontext()):
        if stft_percussive is not None:
            perc_mag = np.abs(stft_percussive)
            onset_env = librosa.onset.onset_strength(S=perc_mag, sr=sr, hop_length=hop_length)
        elif stft_magnitude is not None and stft_magnitude.size > 0 and bool(tempo_window_meta.get("full_track")):
            onset_env = librosa.onset.onset_strength(S=stft_magnitude, sr=sr, hop_length=hop_length)
        else:
            onset_env = librosa.onset.onset_strength(y=tempo_percussive, sr=sr, hop_length=hop_length)

    with (timer.track("tempo.beat_track") if timer else nullcontext()):
        tempo_percussive_bpm, beats = librosa.beat.beat_track(onset_envelope=onset_env, sr=sr, hop_length=hop_length)
    with (timer.track("tempo.tempogram") if timer else nullcontext()):
        tempo_onset_bpm = librosa.feature.tempo(onset_envelope=onset_env, sr=sr, hop_length=hop_length)[0]
    with (timer.track("tempo.plp") if timer else nullcontext()):
        plp_envelope = librosa.beat.plp(onset_envelope=onset_env, sr=sr, hop_length=hop_length)
    plp_peak = float(np.max(plp_envelope)) if plp_envelope.size > 0 else 0.0
    try:
        plp_tempo_arr = librosa.beat.tempo(onset_envelope=plp_envelope, sr=sr, hop_length=hop_length)
        tempo_plp_bpm = float(plp_tempo_arr.flatten()[0]) if np.size(plp_tempo_arr) > 0 else 0.0
    except Exception:
        tempo_plp_bpm = 0.0

    tempo_percussive_float = float(tempo_percussive_bpm.flatten()[0] if isinstance(tempo_percussive_bpm, np.ndarray) else tempo_percussive_bpm)
    tempo_onset_float = float(tempo_onset_bpm.flatten()[0] if isinstance(tempo_onset_bpm, np.ndarray) else tempo_onset_bpm)
    logger.info(
        "🎯 BPM Detection - Method 1 (beat_track): %.1f, Method 2 (onset): %.1f",
        tempo_percussive_float,
        tempo_onset_float,
    )

    spectral_flux_mean = None
    if stft_magnitude is not None and stft_magnitude.shape[1] > 1:
        spectral_diff = np.diff(stft_magnitude, axis=1)
        flux = np.sqrt((spectral_diff**2).sum(axis=0))
        spectral_flux_mean = float(np.mean(flux))

    alias_candidates = _build_tempo_alias_candidates(tempo_percussive_float, tempo_onset_float)
    best_alias, scored_aliases = _score_tempo_alias_candidates(
        alias_candidates,
        tempo_percussive_float,
        tempo_onset_float,
        tempo_plp_bpm,
        plp_peak,
        chunk_bpm_std=None,
        spectral_flux_mean=spectral_flux_mean,
        is_short_clip=is_short_clip,
    )

    if scored_aliases:
        top_5 = sorted(scored_aliases, key=lambda x: x["score"], reverse=True)[:5]
        candidate_summary = ", ".join([f"{c['bpm']:.1f}({c['score']:.2f})" for c in top_5])
        logger.info("🔍 Top BPM candidates [bpm(score)]: %s", candidate_summary)
        # Show detailed breakdown for top 2 to debug tie-breaking
        for idx, c in enumerate(top_5[:2]):
            logger.info(f"  #{idx+1}: {c['bpm']:.1f} BPM → score={c['score']:.4f}, octave_pref={c.get('octave_preference', 0):.2f}, alignment={c.get('alignment', 0):.2f}, detector={c.get('detector_support', 0):.2f}")

    # Strategy 2: Extended Alias Factors - DISABLED (was causing BPM errors)
    # This logic was too aggressive and introduced more errors than it fixed
    # Keeping the code for reference but not executing it
    if False:  # Disabled - remove this block after testing confirms improvement
        extended_candidate = None
        if scored_aliases and len(scored_aliases) >= 2:
            sorted_aliases = sorted(scored_aliases, key=lambda x: x["score"], reverse=True)
            top_score = sorted_aliases[0]["score"]
            second_score = sorted_aliases[1]["score"]
            score_gap = top_score - second_score
            top_bpm = sorted_aliases[0]["bpm"]
            
            logger.debug(f"Extended alias logic disabled (score gap: {score_gap:.3f})")

    tempo = tempo_percussive_float
    bpm_confidence = 0.6

    def _weighted_median(candidates: List[dict]) -> Optional[float]:
        if not candidates:
            return None
        sorted_cands = sorted(candidates, key=lambda x: x["bpm"])
        total = sum(c["score"] for c in sorted_cands)
        if total <= 0:
            return None
        cumulative = 0.0
        for c in sorted_cands:
            cumulative += c["score"]
            if cumulative >= total * 0.5:
                return float(c["bpm"])
        return float(sorted_cands[-1]["bpm"])

    if best_alias is not None:
        tempo = float(best_alias["bpm"])
        bpm_confidence = float(best_alias.get("confidence", best_alias["score"]))

        # De-quantize: if the top bpm is a known lock value or far from the weighted median, favor the median.
        canonical_bpm = {61.5, 94.7, 99.2, 104.5, 107.4, 110.6, 117.8, 126.4, 131.4, 143.6, 161.5}
        alt_tempo = _weighted_median(scored_aliases)
        if alt_tempo is not None:
            top_score = max(c["score"] for c in scored_aliases) if scored_aliases else 0.0
            median_score = sum(c["score"] for c in scored_aliases) / max(len(scored_aliases), 1)
            close_to_top = abs(tempo - alt_tempo) >= 1.5 and bpm_confidence <= top_score * 0.95
            is_canonical_lock = round(tempo, 1) in canonical_bpm
            if is_canonical_lock or close_to_top:
                logger.info(
                    "🧭 De-quantizing BPM: best=%.1f (conf=%.2f) → weighted-median=%.1f (avgScore=%.3f)",
                    tempo,
                    bpm_confidence,
                    alt_tempo,
                    median_score,
                )
                tempo = alt_tempo

        source_labels = [
            f"{src.get('detector')}×{src.get('factor'):.1f}"
            for src in best_alias.get("sources", [])
        ]
        summary = ", ".join(source_labels) if source_labels else "alias scoring"
        logger.info("🧮 BPM alias scoring picked %.1f BPM via %s (score %.2f)", tempo, summary, bpm_confidence)
    else:
        logger.info("⚠️ BPM alias scoring fallback: using beat_track %.1f BPM", tempo)

    final_bpm = float(tempo)

    if stft_magnitude is not None and stft_magnitude.size > 0:
        context_n_fft = descriptor_ctx.get("n_fft", ANALYSIS_FFT_SIZE) if descriptor_ctx else ANALYSIS_FFT_SIZE
        rms_early = librosa.feature.rms(S=stft_magnitude, frame_length=context_n_fft, hop_length=hop_length)[0]
    elif y_trimmed.size > 0:
        safe_frame_len = min(ANALYSIS_FFT_SIZE, y_trimmed.size)
        if safe_frame_len < ANALYSIS_FFT_SIZE:
            safe_frame_len = 2 ** int(np.floor(np.log2(safe_frame_len)))
            safe_frame_len = max(256, safe_frame_len)
        rms_early = librosa.feature.rms(y=y_trimmed, frame_length=safe_frame_len, hop_length=hop_length)[0]
    else:
        rms_early = np.array([0.0])
    rms_db_early = librosa.amplitude_to_db(rms_early + 1e-12, ref=1.0)
    loud_rms_early = float(np.percentile(rms_db_early, 90))
    energy_rms_early = float(np.clip((loud_rms_early + 60.0) / 60.0, 0.0, 1.0))

    # Intermediate tempo correction - TIGHTENED to reduce false positives
    # Only apply for very specific cases (70-80 BPM range with high energy AND strong improvement)
    if 70 <= final_bpm <= 80 and energy_rms_early > 0.65 and onset_env is not None and len(onset_env) > 0:
        intermediate_factors = [1.2, 1.25]
        current_separation = _compute_onset_energy_separation(final_bpm, onset_env, sr, ANALYSIS_HOP_LENGTH) or 0.0
        best_intermediate_bpm = None
        best_intermediate_separation = current_separation

        for factor in intermediate_factors:
            test_bpm = final_bpm * factor
            if test_bpm > _MAX_ALIAS_BPM:
                continue
            test_separation = _compute_onset_energy_separation(test_bpm, onset_env, sr, ANALYSIS_HOP_LENGTH)
            # Use adaptive threshold - higher for short clips to reduce false corrections
            if test_separation is not None and test_separation > best_intermediate_separation * intermediate_threshold:
                best_intermediate_bpm = test_bpm
                best_intermediate_separation = test_separation
                logger.info(
                    "🔍 Intermediate candidate: %.2f BPM (factor %.2f, separation %.3f vs %.3f)",
                    test_bpm,
                    factor,
                    test_separation,
                    current_separation,
                )

        if best_intermediate_bpm is not None:
            logger.info(
                "⬆️ Intermediate tempo correction: %.2f → %.2f BPM (energy=%.2f)",
                final_bpm,
                best_intermediate_bpm,
                energy_rms_early,
            )
            final_bpm = best_intermediate_bpm

    might_be_slow_ballad = (60 <= final_bpm <= 85 and final_bpm * 2 > 105 and energy_rms_early < 0.70)
    skip_onset_validation = not use_onset_validation  # Start with adaptive param setting
    if might_be_slow_ballad:
        skip_onset_validation = True
        logger.info(
            "⏭️ Skipping onset validation for potential slow ballad (BPM=%.1f, ×2=%.1f, energy_rms=%.2f)",
            final_bpm,
            final_bpm * 2,
            energy_rms_early,
        )
    elif not use_onset_validation:
        logger.info(
            "⏭️ Skipping onset validation for short clip (adaptive setting)"
        )
    
    # MID-TEMPO OCTAVE VALIDATION ZONE (85-110 BPM)
    # For tempos in the ambiguous middle range, check if other multiples have stronger beat alignment
    # Apply generalized octave correction based on onset-energy separation
    # Only apply to short clips where full onset validation is disabled
    in_mid_tempo_zone = (85 <= final_bpm <= 110)
    
    if is_short_clip and in_mid_tempo_zone and onset_env is not None and len(onset_env) > 0:
        if bpm_confidence >= 0.90:
            logger.info(
                "⏭️ Mid-tempo check skipped (high confidence %.2f for %.1f BPM)",
                bpm_confidence,
                final_bpm,
            )
        else:
            # Use weighted separation that prefers musically typical mid/high tempos
            def _weighted_separation(test_bpm: float, separation: float) -> float:
                alignment = tempo_alignment_score(test_bpm)
                return separation * (0.7 + 0.3 * alignment)

            current_separation = _compute_onset_energy_separation(final_bpm, onset_env, sr, ANALYSIS_HOP_LENGTH) or 0.0
            best_score = _weighted_separation(final_bpm, current_separation)
            best_factor = None
            best_separation = current_separation

            test_factors = [1.5, 1.55]
            improvement_threshold = 1.20

            for factor in test_factors:
                test_bpm = final_bpm * factor
                if test_bpm > _MAX_ALIAS_BPM or test_bpm > 152.0:
                    continue
                test_separation = _compute_onset_energy_separation(test_bpm, onset_env, sr, ANALYSIS_HOP_LENGTH) or 0.0
                weighted_score = _weighted_separation(test_bpm, test_separation)

                if weighted_score > best_score * improvement_threshold:
                    best_score = weighted_score
                    best_factor = factor
                    best_separation = test_separation

            if best_factor is not None:
                corrected_bpm = final_bpm * best_factor
                logger.info(
                    "🎯 Mid-tempo correction: %.1f → %.1f BPM (×%.2f, separation %.3f → %.3f, weighted improvement %.1fx)",
                    final_bpm,
                    corrected_bpm,
                    best_factor,
                    current_separation,
                    best_separation,
                    best_score / max(_weighted_separation(final_bpm, current_separation), 0.01),
                )
                final_bpm = corrected_bpm
                bpm_confidence *= 0.95  # Slight confidence reduction for correction
            else:
                logger.info(
                    "🔍 Mid-tempo check: keeping %.1f BPM (no factor showed >%.2fx improvement, current sep=%.3f)",
                    final_bpm,
                    improvement_threshold,
                    current_separation,
                )
    
    # EXTENDED OCTAVE VALIDATION FOR SHORT CLIPS (all tempo ranges)
    # Handles both high-tempo (>160 BPM might need ÷2) and low-tempo (<70 BPM might need ×2) errors
    # Only for short clips where standard onset validation is disabled
    if is_short_clip and skip_onset_validation and onset_env is not None and len(onset_env) > 0:
        current_separation = _compute_onset_energy_separation(final_bpm, onset_env, sr, ANALYSIS_HOP_LENGTH) or 0.0
        best_factor = None
        best_separation = current_separation
        best_bpm = final_bpm
        
        # Use different improvement thresholds based on BPM range
        # High/low tempo errors are more critical, so use lower threshold
        high_tempo_threshold = 160.0 if is_short_clip else 170.0
        low_tempo_threshold = 90.0 if is_short_clip else 85.0
        if final_bpm > high_tempo_threshold or final_bpm < low_tempo_threshold:
            improvement_threshold_ext = 1.15
        else:
            improvement_threshold_ext = 1.30  # More conservative for mid-range
        
        # Determine which octave factors to test based on current BPM
        test_factors = []
        
        # High-tempo errors (>threshold BPM) - might be detecting double speed
        if final_bpm > high_tempo_threshold:
            test_factors = [0.5, 0.67, 0.75]  # Try halving and related factors
            logger.info(f"🔍 High-tempo check: {final_bpm:.1f} BPM, testing half-speed factors: {test_factors}")
        
        # Low-tempo errors (<threshold BPM but not in mid-tempo zone) - might be detecting half speed
        elif final_bpm < low_tempo_threshold:
            test_factors = [2.0, 1.5, 1.33]  # Try doubling and related factors
            logger.info(f"🔍 Low-tempo check: {final_bpm:.1f} BPM, testing double-speed factors: {test_factors}")
        
        # No middle range testing - those are usually correct or handled by mid-tempo validator
        else:
            test_factors = []  # Skip extended validator for 70-170 BPM range
        
        # Test each factor
        for factor in test_factors:
            test_bpm = final_bpm * factor
            # Keep results in reasonable BPM range (40-250)
            if test_bpm < 40 or test_bpm > 250:
                continue
            
            test_separation = _compute_onset_energy_separation(test_bpm, onset_env, sr, ANALYSIS_HOP_LENGTH) or 0.0
            
            logger.info(
                f"  Testing factor {factor:.2f}: {final_bpm:.1f} → {test_bpm:.1f} BPM, "
                f"separation {current_separation:.3f} → {test_separation:.3f} "
                f"(ratio: {test_separation / max(current_separation, 0.01):.2f}x, threshold: {improvement_threshold_ext:.2f}x)"
            )
            
            if test_separation > best_separation * improvement_threshold_ext:
                best_separation = test_separation
                best_factor = factor
                best_bpm = test_bpm
        
        if best_factor is not None and best_bpm != final_bpm:
            improvement_ratio = best_separation / max(current_separation, 0.01)
            logger.info(
                "🎯 Extended octave correction: %.1f → %.1f BPM (×%.2f, separation %.3f → %.3f, improvement %.1fx)",
                final_bpm,
                best_bpm,
                best_factor,
                current_separation,
                best_separation,
                improvement_ratio,
            )
            final_bpm = best_bpm
            bpm_confidence *= 0.90  # Confidence reduction for correction
        elif test_factors:
            logger.info(
                "🔍 Extended octave check: keeping %.1f BPM (no factor showed >%.2fx improvement, current sep=%.3f)",
                final_bpm,
                improvement_threshold_ext,
                current_separation,
            )

    if not skip_onset_validation and onset_env is not None and len(onset_env) > 0:
        validated_bpm, separation_ratio = _validate_octave_with_onset_energy(
            final_bpm, onset_env, sr, ANALYSIS_HOP_LENGTH
        )
        if validated_bpm != final_bpm:
            change_factor = validated_bpm / max(final_bpm, 1e-6)
            bpm_confidence *= clamp_to_unit(0.85 + 0.15 * separation_ratio)
            logger.info(
                "✅ Onset validation adjusted BPM %.1f → %.1f (factor %.2f, separation %.3f, conf %.2f)",
                final_bpm,
                validated_bpm,
                change_factor,
                separation_ratio,
                bpm_confidence,
            )
            final_bpm = validated_bpm
        else:
            logger.info(
                "👌 Onset validation kept BPM at %.1f (beat separation: %.3f)",
                final_bpm,
                separation_ratio,
            )

    beat_consistency = None
    if len(beats) > 0:
        beat_strengths = onset_env[beats]
        std_val = float(np.std(beat_strengths))
        mean_val = float(np.mean(beat_strengths))
        beat_consistency = 1.0 - min(std_val / (mean_val + 1e-6), 1.0)
        bpm_confidence = float(0.6 * bpm_confidence + 0.4 * beat_consistency)

    bpm_confidence = float(max(0.0, min(1.0, bpm_confidence)))

    return TempoResult(
        bpm=float(final_bpm),
        bpm_confidence=bpm_confidence,
        onset_env=onset_env,
        beats=beats,
        y_harmonic=y_harmonic,
        y_percussive=y_percussive,
        stft_percussive=stft_percussive,
        stft_harmonic=stft_harmonic,
        tempo_percussive_bpm=tempo_percussive_float,
        tempo_onset_bpm=tempo_onset_float,
        tempo_plp_bpm=tempo_plp_bpm,
        plp_peak=plp_peak,
        best_alias=best_alias,
        scored_aliases=scored_aliases,
        tempo_window_meta=tempo_window_meta,
    )


__all__ = [
    "analyze_tempo",
    "TempoResult",
]
