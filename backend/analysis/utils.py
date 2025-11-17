"""Utility helpers shared across analysis modules."""

from __future__ import annotations

import math
from typing import Optional


def clamp_to_unit(value):
    """Clamp any numeric value to [0, 1], treating NaN/inf as 0."""
    if value is None:
        return 0.0
    try:
        val = float(value)
    except (TypeError, ValueError):
        return 0.0
    if not math.isfinite(val):
        return 0.0
    return max(0.0, min(1.0, val))


def safe_float(value) -> Optional[float]:
    try:
        val = float(value)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(val):
        return None
    return val


def percentage(value, min_value=0.0, max_value=1.0):
    val = safe_float(value)
    if val is None or max_value == min_value:
        return None
    clamped = max(min_value, min(max_value, val))
    return (clamped - min_value) / (max_value - min_value) * 100.0


__all__ = ["clamp_to_unit", "safe_float", "percentage"]
