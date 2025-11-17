"""Compatibility layer for feature helpers.

The original monolithic `pipeline_features.py` has been split into focused
modules under `backend.analysis.features`. Import from those modules for new
code; this file re-exports existing functions to avoid breaking callers.
"""

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

__all__ = [
    "calculate_loudness_and_dynamics",
    "detect_silence_ratio",
    "detect_time_signature",
    "estimate_danceability",
    "estimate_valence_and_mood",
    "extract_additional_descriptors",
    "heuristic_danceability",
    "tempo_alignment_score",
]
