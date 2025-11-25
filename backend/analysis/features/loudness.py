"""Loudness, dynamics, and silence utilities."""

from __future__ import annotations

from typing import Optional

import librosa
import numpy as np

from backend.analysis.features.common import safe_frame_length


def calculate_loudness_and_dynamics(y, sr, frame_rms_db: Optional[np.ndarray] = None):
    """Compute average loudness and dynamic range."""
    if len(y) == 0 or sr <= 0:
        return -120.0, 0.0
    if frame_rms_db is None:
        safe_frame_len = safe_frame_length(len(y))
        frame_rms = librosa.feature.rms(y=y, frame_length=safe_frame_len, hop_length=safe_frame_len // 4)[0]
        frame_rms_db = librosa.amplitude_to_db(frame_rms + 1e-12, ref=np.max)
    loudness = float(np.mean(frame_rms_db))
    percentile_95 = float(np.percentile(frame_rms_db, 95))
    percentile_5 = float(np.percentile(frame_rms_db, 5))
    dynamic_range = percentile_95 - percentile_5
    return loudness, dynamic_range


def detect_silence_ratio(y, sr, threshold_db=-40, frame_rms_db: Optional[np.ndarray] = None):
    """Return the fraction of frames considered silent."""
    if len(y) == 0 or sr <= 0:
        return 1.0
    if frame_rms_db is None:
        safe_frame_len = safe_frame_length(len(y))
        frame_rms = librosa.feature.rms(y=y, frame_length=safe_frame_len, hop_length=safe_frame_len // 4)[0]
        frame_rms_db = librosa.amplitude_to_db(frame_rms + 1e-12, ref=np.max)
    silence_ratio = float(np.mean(frame_rms_db < threshold_db))
    return silence_ratio


__all__ = ["calculate_loudness_and_dynamics", "detect_silence_ratio"]
