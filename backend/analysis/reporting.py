"""Shared reporting constants for analysis exports and tooling."""

from __future__ import annotations

import os
from pathlib import Path
from typing import List, Tuple

REPO_ROOT = Path(__file__).resolve().parents[2]
EXPORT_DIR = REPO_ROOT / "exports"
EXPORT_DIR.mkdir(parents=True, exist_ok=True)

HOME_DIR = Path.home()
DB_PATH = str(HOME_DIR / "Music" / "audio_analysis_cache.db")
CACHE_DIR = str(HOME_DIR / "Music" / "AudioAnalysisCache")
os.makedirs(CACHE_DIR, exist_ok=True)

ANALYSIS_TIMER_EXPORT_FIELDS: List[Tuple[str, str]] = [
    ("analysis_total", "Timer Total (s)"),
    ("hpss", "Timer HPSS (s)"),
    ("tempo.onset_env", "Timer Tempo Onset (s)"),
    ("tempo.beat_track", "Timer Tempo Beat Track (s)"),
    ("tempo.tempogram", "Timer Tempo Tempogram (s)"),
    ("key_detection", "Timer Key Detection (s)"),
    ("descriptor_extraction", "Timer Descriptor Extraction (s)"),
    ("spectral_centroid", "Timer Spectral Centroid (s)"),
    ("danceability", "Timer Danceability (s)"),
    ("time_signature", "Timer Time Signature (s)"),
    ("valence_mood", "Timer Valence/Mood (s)"),
    ("global_rms", "Timer Global RMS (s)"),
    ("loudness_dynamics", "Timer Loudness/Dynamics (s)"),
    ("silence_ratio", "Timer Silence Ratio (s)"),
]

CHUNK_TIMING_EXPORT_FIELDS: List[Tuple[str, str]] = [
    ("wall_time_seconds", "Chunk Wall Time (s)"),
    ("analysis_time_seconds", "Chunk Analyzer Time (s)"),
    ("analysis_overhead_seconds", "Chunk Overhead (s)"),
    ("analysis_time_avg_seconds", "Chunk Analyzer Avg (s)"),
    ("chunks_evaluated", "Chunks Evaluated"),
]

__all__ = [
    "ANALYSIS_TIMER_EXPORT_FIELDS",
    "CHUNK_TIMING_EXPORT_FIELDS",
    "DB_PATH",
    "CACHE_DIR",
    "EXPORT_DIR",
    "REPO_ROOT",
]
