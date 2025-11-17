"""Shared analyzer configuration loaded from environment variables."""

from __future__ import annotations

import os
import multiprocessing


def _truthy(value: str | None) -> bool:
    if value is None:
        return False
    return value.strip().lower() in {"1", "true", "yes", "on", "y"}


ANALYSIS_SAMPLE_RATE = int(os.environ.get("ANALYSIS_SAMPLE_RATE", "12000"))
ANALYSIS_FFT_SIZE = max(256, int(os.environ.get("ANALYSIS_FFT_SIZE", "1024")))
ANALYSIS_HOP_LENGTH = max(64, int(os.environ.get("ANALYSIS_HOP_LENGTH", "512")))
ANALYSIS_RESAMPLE_TYPE = os.environ.get("ANALYSIS_RESAMPLE_TYPE", "kaiser_fast")
_max_analysis_env = float(os.environ.get("MAX_ANALYSIS_SECONDS", "0"))
MAX_ANALYSIS_SECONDS = _max_analysis_env if _max_analysis_env > 0 else None
CHUNK_ANALYSIS_SECONDS = float(os.environ.get("CHUNK_ANALYSIS_SECONDS", "15"))
CHUNK_OVERLAP_SECONDS = float(os.environ.get("CHUNK_OVERLAP_SECONDS", "5"))
MIN_CHUNK_DURATION_SECONDS = float(os.environ.get("MIN_CHUNK_DURATION_SECONDS", "5"))
KEY_ANALYSIS_SAMPLE_RATE = int(os.environ.get("KEY_ANALYSIS_SAMPLE_RATE", "22050"))
MAX_CHUNK_BATCHES = int(os.environ.get("MAX_CHUNK_BATCHES", "16"))
_chunk_env = os.environ.get("CHUNK_ANALYSIS_ENABLED")
if _chunk_env is not None:
    CHUNK_ANALYSIS_ENABLED = _truthy(_chunk_env)
else:
    CHUNK_ANALYSIS_ENABLED = CHUNK_ANALYSIS_SECONDS > 0 and MAX_CHUNK_BATCHES > 0
CHUNK_BEAT_TARGET = float(os.environ.get("CHUNK_BEAT_TARGET", "8"))
CONSENSUS_STD_EPS = 1e-6

# RESOURCE-AWARE WORKER CONFIGURATION
# Default: Use only 1 worker to avoid overwhelming the system
# Max: Cap at 50% of CPU cores (leave room for other apps)
_cpu_count = multiprocessing.cpu_count()
_max_workers_default = max(1, _cpu_count // 2)  # Use 50% of cores
_workers_env = int(os.environ.get("ANALYSIS_WORKERS", "1"))
ANALYSIS_WORKERS = max(0, min(_workers_env, _max_workers_default))
TEMPO_WINDOW_SECONDS = float(os.environ.get("TEMPO_WINDOW_SECONDS", "60"))
ENABLE_TONAL_EXTRACTOR = os.environ.get("ENABLE_TONAL_EXTRACTOR", "false").strip().lower() in {
    "1",
    "true",
    "yes",
    "on",
    "y",
}
ENABLE_ESSENTIA_DANCEABILITY = os.environ.get("ENABLE_ESSENTIA_DANCEABILITY", "false").strip().lower() in {
    "1",
    "true",
    "yes",
    "on",
    "y",
}
ENABLE_ESSENTIA_DESCRIPTORS = os.environ.get("ENABLE_ESSENTIA_DESCRIPTORS", "false").strip().lower() in {
    "1",
    "true",
    "yes",
    "on",
    "y",
}

# SHORT CLIP THRESHOLD (seconds)
SHORT_CLIP_THRESHOLD = 45.0


def get_adaptive_analysis_params(signal_duration: float) -> dict:
    """
    Get adaptive analysis parameters based on audio duration.
    
    For short clips (< 45s, typically previews), we use:
    - Shorter tempo windows proportional to duration
    - Fewer key analysis windows for faster consensus
    - Lower confidence thresholds (less data = less certainty)
    - Disabled complex validations (trust simpler detections)
    
    For full songs (>= 45s), we use:
    - Full-length analysis windows for better accuracy
    - Multi-window consensus for reliability
    - Higher confidence thresholds
    - All validation and correction heuristics
    
    Args:
        signal_duration: Duration of audio signal in seconds
    
    Returns:
        dict: Analysis parameters optimized for the given duration
    """
    is_short_clip = signal_duration < SHORT_CLIP_THRESHOLD
    
    if is_short_clip:
        # Short clip (preview) parameters
        return {
            'is_short_clip': True,
            'tempo_window': min(signal_duration * 0.8, 30.0),  # Use 80% of duration, max 30s
            'key_window': min(signal_duration / 5.0, 6.0),     # Aim for ~5 windows minimum
            'key_window_hop': min(signal_duration / 10.0, 3.0), # Overlap for smoother consensus
            'confidence_threshold': 0.60,  # Lower threshold for less data
            'use_onset_validation': False,  # Skip complex onset-based validations
            'use_window_consensus': False,  # Trust direct chroma detection more
            'use_extended_alias': False,    # Skip extended BPM alias corrections
            'intermediate_correction_threshold': 1.50,  # Higher threshold = less aggressive
        }
    else:
        # Full song parameters
        return {
            'is_short_clip': False,
            'tempo_window': TEMPO_WINDOW_SECONDS,
            'key_window': 6.0,
            'key_window_hop': 3.0,
            'confidence_threshold': 0.75,
            'use_onset_validation': True,
            'use_window_consensus': True,
            'use_extended_alias': False,  # Disabled per handover - was causing errors
            'intermediate_correction_threshold': 1.50,
        }


__all__ = [
    "ANALYSIS_SAMPLE_RATE",
    "ANALYSIS_FFT_SIZE",
    "ANALYSIS_HOP_LENGTH",
    "ANALYSIS_RESAMPLE_TYPE",
    "MAX_ANALYSIS_SECONDS",
    "CHUNK_ANALYSIS_SECONDS",
    "CHUNK_OVERLAP_SECONDS",
    "MIN_CHUNK_DURATION_SECONDS",
    "KEY_ANALYSIS_SAMPLE_RATE",
    "MAX_CHUNK_BATCHES",
    "CHUNK_ANALYSIS_ENABLED",
    "CHUNK_BEAT_TARGET",
    "CONSENSUS_STD_EPS",
    "ANALYSIS_WORKERS",
    "TEMPO_WINDOW_SECONDS",
    "ENABLE_TONAL_EXTRACTOR",
    "ENABLE_ESSENTIA_DANCEABILITY",
    "ENABLE_ESSENTIA_DESCRIPTORS",
    "SHORT_CLIP_THRESHOLD",
    "get_adaptive_analysis_params",
]
