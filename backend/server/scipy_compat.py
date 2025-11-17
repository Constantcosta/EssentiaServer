"""Compatibility helpers for SciPy window functions."""

from __future__ import annotations

import numpy as np


def ensure_hann_patch() -> bool:
    """
    Ensure scipy.signal exposes the legacy hann window used by librosa.

    Returns:
        bool: True if the shim is active (or already provided by SciPy).
    """
    try:
        import scipy.signal as _scipy_signal  # type: ignore
    except Exception:
        return False

    if hasattr(_scipy_signal, "hann"):
        return True

    def _hann_wrapper(M, sym=True):
        if M <= 0:
            return np.zeros(0)
        if not sym:
            return np.hanning(M + 1)[:-1]
        return np.hanning(M)

    _scipy_signal.hann = _hann_wrapper  # type: ignore[attr-defined]
    return True


__all__ = ["ensure_hann_patch"]
