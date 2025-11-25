"""Utility helpers for deciding when to run chunk analysis."""

from backend.analysis import settings

CHUNK_ANALYSIS_ENABLED = settings.CHUNK_ANALYSIS_ENABLED
CHUNK_ANALYSIS_SECONDS = settings.CHUNK_ANALYSIS_SECONDS
MIN_CHUNK_DURATION_SECONDS = settings.MIN_CHUNK_DURATION_SECONDS
CHUNK_BEAT_TARGET = settings.CHUNK_BEAT_TARGET


def should_run_chunk_analysis(signal_duration: float) -> bool:
    """Decide whether chunk analysis is worth running for the given track duration."""
    if not CHUNK_ANALYSIS_ENABLED or signal_duration <= 0:
        return False
    min_duration = max(
        CHUNK_ANALYSIS_SECONDS + MIN_CHUNK_DURATION_SECONDS,
        CHUNK_ANALYSIS_SECONDS * 1.5,
    )
    return signal_duration >= min_duration


__all__ = [
    "should_run_chunk_analysis",
    "CHUNK_ANALYSIS_ENABLED",
    "CHUNK_ANALYSIS_SECONDS",
    "MIN_CHUNK_DURATION_SECONDS",
    "CHUNK_BEAT_TARGET",
]
