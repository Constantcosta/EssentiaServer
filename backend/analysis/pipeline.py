"""Core analysis building blocks (timers, hooks)."""

from __future__ import annotations

import time
from contextlib import contextmanager
from dataclasses import dataclass
from typing import Callable, Dict
import logging


logger = logging.getLogger(__name__)


class AnalysisTimer:
    """Collect lightweight timing data for expensive analysis stages."""

    def __init__(self):
        self._sections: Dict[str, float] = {}

    @contextmanager
    def track(self, name: str):
        start = time.perf_counter()
        try:
            yield
        finally:
            elapsed = time.perf_counter() - start
            self._sections[name] = self._sections.get(name, 0.0) + elapsed

    def add(self, name: str, duration: float):
        if duration is None:
            return
        try:
            numeric = float(duration)
        except (TypeError, ValueError):
            return
        if numeric < 0:
            return
        self._sections[name] = self._sections.get(name, 0.0) + numeric

    def snapshot(self) -> Dict[str, float]:
        return {key: round(value, 6) for key, value in self._sections.items()}

    def log(self, label: str):
        if not self._sections:
            return
        ordered = sorted(self._sections.items(), key=lambda item: item[1], reverse=True)
        parts = ", ".join(f"{name}: {duration:.3f}s" for name, duration in ordered)
        logger.info("⏱️ %s timings — %s", label, parts)


@contextmanager
def stage_timer(label: str):
    """Log how long a processing stage takes."""
    start = time.perf_counter()
    try:
        yield
    finally:
        elapsed = time.perf_counter() - start
        logger.info("⏱️ %s took %.3fs", label, elapsed)


@dataclass
class CalibrationHooks:
    """Callable hooks that apply calibration layers to analyzer results."""

    apply_scalers: Callable[[Dict[str, object]], Dict[str, object]]
    apply_key: Callable[[Dict[str, object]], Dict[str, object]]
    apply_bpm: Callable[[Dict[str, object]], Dict[str, object]]
    apply_models: Callable[[Dict[str, object]], Dict[str, object]]

    def apply_all(self, result: Dict[str, object]) -> Dict[str, object]:
        output = self.apply_scalers(result)
        output = self.apply_key(output)
        output = self.apply_bpm(output)
        output = self.apply_models(output)
        return output


__all__ = ["AnalysisTimer", "stage_timer", "CalibrationHooks"]
