"""Shared calibration feature metadata for fitting/validation scripts."""
from __future__ import annotations

from dataclasses import dataclass
from typing import List, Optional, Tuple


@dataclass(frozen=True)
class FeatureSpec:
    name: str
    source_col: str
    target_col: str
    percent_scale: bool = False
    clamp: Optional[Tuple[Optional[float], Optional[float]]] = None
    description: str = ""


FEATURE_SPECS: List[FeatureSpec] = [
    FeatureSpec(
        name="bpm",
        source_col="analyzer_bpm",
        target_col="spotify_bpm",
        description="Tempo (beats per minute)",
        clamp=(None, None),
    ),
    FeatureSpec(
        name="danceability",
        source_col="analyzer_danceability",
        target_col="spotify_dance",
        percent_scale=True,
        clamp=(0.0, 1.0),
        description="Danceability classifier (0-1)",
    ),
    FeatureSpec(
        name="energy",
        source_col="analyzer_energy",
        target_col="spotify_energy",
        percent_scale=True,
        clamp=(0.0, 1.0),
        description="Energy estimate (0-1)",
    ),
    FeatureSpec(
        name="acousticness",
        source_col="analyzer_acousticness",
        target_col="spotify_acoustic",
        percent_scale=True,
        clamp=(0.0, 1.0),
        description="Acousticness likelihood (0-1)",
    ),
    FeatureSpec(
        name="valence",
        source_col="analyzer_valence",
        target_col="spotify_happy",
        percent_scale=True,
        clamp=(0.0, 1.0),
        description="Valence / positivity",
    ),
    FeatureSpec(
        name="loudness",
        source_col="analyzer_loudness_db",
        target_col="spotify_loudness_db",
        clamp=(-40.0, 0.0),
        description="Integrated loudness in dBFS (negative values).",
    ),
]

FEATURE_MAP = {spec.name: spec for spec in FEATURE_SPECS}

