"""Public surface for high-level audio feature helpers.

Each module in this package focuses on a single responsibility to keep the
analysis codebase agent-friendly and easy to navigate.
"""

from .danceability import estimate_danceability, heuristic_danceability, tempo_alignment_score
from .descriptors import extract_additional_descriptors
from .loudness import calculate_loudness_and_dynamics, detect_silence_ratio
from .time_signature import detect_time_signature
from .valence import estimate_valence_and_mood

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
