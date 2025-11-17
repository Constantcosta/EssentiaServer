"""Analysis package providing reusable audio-processing utilities."""

from . import settings  # re-export settings module for convenience
from .pipeline import AnalysisTimer, CalibrationHooks, stage_timer  # noqa: F401
from .pipeline_core import perform_audio_analysis  # noqa: F401
from .pipeline_chunks import attach_chunk_analysis, should_run_chunk_analysis  # noqa: F401
from .utils import clamp_to_unit, percentage, safe_float  # noqa: F401

__all__ = [
    "settings",
    "AnalysisTimer",
    "CalibrationHooks",
    "attach_chunk_analysis",
    "perform_audio_analysis",
    "should_run_chunk_analysis",
    "stage_timer",
    "clamp_to_unit",
    "percentage",
    "safe_float",
]
