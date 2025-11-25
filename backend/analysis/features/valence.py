"""Valence and mood estimation helpers."""

from __future__ import annotations

import numpy as np

from backend.analysis.utils import clamp_to_unit


def estimate_valence_and_mood(tempo, key, mode, chroma_sums, energy, pitch_features=None, spectral_rolloff=None):
    """
    Estimate valence (happy/sad) and mood from musical features.

    Major keys are generally happier, minor keys are sadder.
    Emotional songs have high pitch variance and specific spectral characteristics.
    """
    key_brightness = {
        0: 0.7,   # C - bright
        1: 0.35,  # C# - dark
        2: 0.65,  # D - bright-ish
        3: 0.3,   # D# - dark
        4: 0.8,   # E - very bright
        5: 0.55,  # F - moderate
        6: 0.25,  # F# - dark
        7: 0.75,  # G - bright
        8: 0.4,   # G# - darker
        9: 0.5,   # A - neutral
        10: 0.6,  # A# - moderate
        11: 0.45, # B - moderate
    }

    is_major = mode == "Major" or mode == 1

    if is_major:
        base_valence = key_brightness.get(key, 0.5)
        mode_factor = 0.65
    else:
        base_valence = key_brightness.get(key, 0.5) * 0.5
        mode_factor = 0.35

    if tempo < 70:
        tempo_factor = -0.2
    elif tempo < 100:
        tempo_factor = 0.0
    elif tempo < 130:
        tempo_factor = 0.2
    elif tempo < 160:
        tempo_factor = 0.1
    else:
        tempo_factor = -0.1

    energy_factor = clamp_to_unit(energy) * 0.1

    chroma_factor = 0.0
    if chroma_sums is not None and chroma_sums.size == 12:
        normalized_chroma = chroma_sums / (np.sum(chroma_sums) + 1e-9)
        entropy = -np.sum(normalized_chroma * np.log(normalized_chroma + 1e-9))
        chroma_factor = clamp_to_unit(entropy / 2.5) * 0.15

    pitch_factor = 0.0
    if pitch_features is not None:
        variance_ratio = pitch_features.get("variance_ratio", 0.0)
        if 0.05 <= variance_ratio <= 0.15:
            pitch_factor = 0.1
        elif variance_ratio > 0.15:
            pitch_factor = -0.15
        else:
            pitch_factor = 0.0

    spectral_factor = 0.0
    if spectral_rolloff is not None:
        normalized_rolloff = (spectral_rolloff - 1000) / 7000
        normalized_rolloff = clamp_to_unit(normalized_rolloff)
        spectral_factor = normalized_rolloff * 0.1

    valence = clamp_to_unit(
        mode_factor +
        base_valence * 0.3 +
        tempo_factor +
        energy_factor +
        chroma_factor +
        pitch_factor +
        spectral_factor
    )

    if valence >= 0.75:
        mood = "✨ Euphoric"
    elif valence >= 0.6:
        mood = "😊 Uplifting"
    elif valence >= 0.45:
        mood = "🙂 Positive"
    elif valence >= 0.3:
        mood = "😌 Calm"
    else:
        mood = "🌧 Melancholic"

    return valence, mood


__all__ = ["estimate_valence_and_mood"]
