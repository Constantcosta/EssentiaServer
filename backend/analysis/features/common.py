"""Shared helpers used across feature extraction modules."""

from __future__ import annotations

import numpy as np

from backend.analysis import settings

ANALYSIS_FFT_SIZE = settings.ANALYSIS_FFT_SIZE


def safe_frame_length(signal_length: int, desired_length: int = ANALYSIS_FFT_SIZE) -> int:
    """Return a frame length that won't exceed the signal length."""
    if signal_length < desired_length:
        safe_length = 2 ** int(np.floor(np.log2(signal_length)))
        safe_length = max(256, min(safe_length, signal_length))
        return safe_length
    return desired_length


__all__ = ["safe_frame_length", "ANALYSIS_FFT_SIZE"]
