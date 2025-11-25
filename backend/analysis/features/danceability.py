"""Danceability estimation (heuristic + Essentia fallback)."""

from __future__ import annotations

import logging
import math
import librosa
import numpy as np

from backend.analysis import settings
from backend.analysis.essentia_support import HAS_ESSENTIA
from backend.analysis.utils import clamp_to_unit

logger = logging.getLogger(__name__)

ENABLE_ESSENTIA_DANCEABILITY = settings.ENABLE_ESSENTIA_DANCEABILITY


def tempo_alignment_score(bpm):
    """Map tempo (and its common aliases) to a 0-1 score emphasizing dance-friendly ranges."""
    if bpm <= 0 or math.isnan(bpm):
        return 0.0
    candidates = {round(bpm, 4)}
    for factor in [0.5, 2.0, 0.25, 4.0]:
        value = bpm * factor
        if 60 <= value <= 180:
            candidates.add(round(value, 4))
    best_score = 0.0
    for candidate in candidates:
        if 118 <= candidate <= 128:
            score = 1.0
        elif 105 <= candidate <= 140:
            score = 0.85
        elif 90 <= candidate <= 105 or 140 <= candidate <= 155:
            score = 0.7
        else:
            score = max(0.2, 1.0 - abs(candidate - 125) / 100)
        best_score = max(best_score, score)
    return best_score


def heuristic_danceability(
    onset_env,
    onset_norm,
    hop_length,
    sr,
    beats,
    percussive_presence,
    pulse_density,
    energy,
    bpm_value,
    signal_duration,
):
    """
    Danceability estimation based on rhythmic and spectral cues.

    Slow songs (<60 BPM) and very fast songs (>180 BPM) are penalized.
    """
    tempogram = librosa.feature.tempogram(onset_envelope=onset_env, sr=sr, hop_length=hop_length)
    tempogram_mean = float(np.mean(tempogram))
    tempogram_std = float(np.std(tempogram))
    tempogram_consistency = 0.0 if tempogram_mean <= 1e-6 else 1.0 - (tempogram_std / tempogram_mean)
    tempogram_consistency = float(np.clip(tempogram_consistency, 0.0, 1.0))

    plp = librosa.beat.plp(onset_envelope=onset_env, sr=sr, hop_length=hop_length)
    pulse_clarity = float(np.max(plp)) if plp.size > 0 else 0.0
    pulse_clarity = float(np.clip(pulse_clarity, 0.0, 1.0))

    onset_mean = float(np.mean(onset_norm)) if onset_norm.size > 0 else 0.0
    onset_std = float(np.std(onset_norm)) if onset_norm.size > 0 else 0.0
    if len(beats) >= 1 and onset_norm.size > 0:
        max_index = onset_norm.shape[0] - 1
        beat_indices = np.clip(beats, 0, max_index)
        beat_samples = onset_norm[beat_indices]
        beat_strength_raw = float(np.mean(beat_samples))
    else:
        beat_strength_raw = pulse_clarity
    if onset_std > 1e-6:
        beat_strength_rel = (beat_strength_raw - onset_mean) / (onset_std * 2.0)
        beat_strength = 0.5 + beat_strength_rel
    else:
        beat_strength = beat_strength_raw
    beat_strength = float(np.clip(0.7 * beat_strength + 0.3 * pulse_clarity, 0.0, 1.0))

    if len(beats) >= 2:
        beat_times = librosa.frames_to_time(beats, sr=sr, hop_length=hop_length)
        beat_intervals = np.diff(beat_times)
        if beat_intervals.size > 0:
            mean_interval = float(np.mean(beat_intervals))
            std_interval = float(np.std(beat_intervals))
            beat_regularity = 1.0 - min(std_interval / (mean_interval + 1e-6), 1.0)
        else:
            beat_regularity = 0.0
    else:
        beat_regularity = tempogram_consistency
    beat_regularity = float(np.clip(beat_regularity, 0.0, 1.0))

    tempo_score = tempo_alignment_score(bpm_value)
    expected_beats = max(signal_duration * bpm_value / 60.0, 1e-3)
    beat_density_ratio = float(len(beats)) / expected_beats if expected_beats > 0 else 0.0
    beat_density = float(np.clip(beat_density_ratio / 1.2, 0.0, 1.0))

    percussive_groove = float(np.clip(percussive_presence * 1.4, 0.0, 1.0))
    rhythmic_structure = float(np.clip(0.6 * beat_regularity + 0.4 * beat_density, 0.0, 1.0))

    danceability_raw = float(
        0.25 * beat_strength +
        0.25 * rhythmic_structure +
        0.35 * tempo_score +
        0.15 * percussive_groove
    )
    danceability = clamp_to_unit(danceability_raw) ** 0.85

    if bpm_value < 60:
        tempo_penalty = bpm_value / 60.0
    elif bpm_value > 180:
        tempo_penalty = max(0.5, 1.0 - (bpm_value - 180) / 120.0)
    else:
        tempo_penalty = 1.0

    danceability *= tempo_penalty

    floor_from_energy = 0.05 * clamp_to_unit(energy)
    floor_from_pulse = 0.05 * clamp_to_unit(pulse_density)
    danceability = float(max(danceability, floor_from_energy, floor_from_pulse))

    components = {
        "pulse_clarity": pulse_clarity,
        "beat_strength": beat_strength,
        "beat_regularity": beat_regularity,
        "tempo_alignment": tempo_score,
        "percussive_groove": percussive_groove,
        "beat_density": beat_density,
        "energy": clamp_to_unit(energy),
        "tempo_penalty": tempo_penalty,
    }
    return danceability, components


def estimate_danceability(
    y_signal,
    sr,
    onset_env,
    onset_norm,
    hop_length,
    beats,
    percussive_presence,
    pulse_density,
    energy,
    bpm_value,
    signal_duration,
):
    """Danceability via Essentia when available, otherwise heuristic fallback."""
    if HAS_ESSENTIA and ENABLE_ESSENTIA_DANCEABILITY:
        try:
            from backend.analysis.essentia_support import es  # Local import to avoid unused when missing

            dance_algo = es.Danceability(sampleRate=sr)  # type: ignore[attr-defined]
            dance_raw, _ = dance_algo(np.ascontiguousarray(y_signal, dtype=np.float32))
            normalized = clamp_to_unit(dance_raw / 3.0)
            logger.info("💃 Essentia danceability: raw %.2f -> %.2f", dance_raw, normalized)
            return normalized
        except Exception as exc:
            logger.warning("⚠️ Essentia danceability failed (%s); falling back to heuristic.", exc)

    danceability, components = heuristic_danceability(
        onset_env,
        onset_norm,
        hop_length,
        sr,
        beats,
        percussive_presence,
        pulse_density,
        energy,
        bpm_value,
        signal_duration,
    )
    logger.info(
        "💃 Heuristic danceability - pulse: %.2f, beat: %.2f, regularity: %.2f, tempo: %.2f, groove: %.2f, density: %.2f, energy: %.2f, penalty: %.2f -> %.2f",
        components["pulse_clarity"],
        components["beat_strength"],
        components["beat_regularity"],
        components["tempo_alignment"],
        components["percussive_groove"],
        components["beat_density"],
        components["energy"],
        components.get("tempo_penalty", 1.0),
        danceability,
    )
    return danceability


__all__ = ["estimate_danceability", "heuristic_danceability", "tempo_alignment_score"]
