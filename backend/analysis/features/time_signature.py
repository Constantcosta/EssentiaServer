"""Beat-driven time signature estimation."""

from __future__ import annotations

import numpy as np
import librosa


def detect_time_signature(beats, sr):
    """Detect time signature (3/4, 4/4, 5/4, etc.) from beat patterns."""
    if len(beats) < 4:
        return "4/4"  # Default if not enough beats

    beat_times = librosa.frames_to_time(beats, sr=sr)
    intervals = np.diff(beat_times)
    if intervals.size == 0:
        return "4/4"

    normalized = intervals / np.mean(intervals)
    pattern_length = min(32, len(normalized))
    autocorr = np.correlate(normalized[:pattern_length], normalized[:pattern_length], mode="full")
    autocorr = autocorr[autocorr.size // 2 :]
    if autocorr.size < 4:
        return "4/4"

    signatures = {
        "3/4": np.array([1, 0.9, 0.8]),
        "4/4": np.array([1, 0.95, 0.85, 0.8]),
        "5/4": np.array([1, 0.9, 0.85, 0.8, 0.75]),
        "6/8": np.array([1, 0.95, 0.9, 0.85, 0.8, 0.75]),
    }
    best_signature = "4/4"
    best_score = -np.inf
    for signature, pattern in signatures.items():
        if len(pattern) > len(autocorr):
            continue
        score = np.dot(pattern, autocorr[: len(pattern)])
        if score > best_score:
            best_score = score
            best_signature = signature
    return best_signature


__all__ = ["detect_time_signature"]
