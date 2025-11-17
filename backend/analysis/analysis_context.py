"""Shared analysis context builders used by the audio pipeline."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Optional

import numpy as np

from backend.analysis import settings
from backend.analysis.pipeline_context import build_spectral_context, select_loudest_window

logger = logging.getLogger(__name__)


@dataclass
class AnalysisContext:
    """Precomputed inputs that are reused across tempo/key/descriptor stages."""

    y_trimmed: np.ndarray
    hop_length: int
    descriptor_ctx: Optional[dict]
    stft_magnitude: Optional[np.ndarray]
    tempo_segment: np.ndarray
    tempo_start: int
    tempo_window_meta: dict
    tempo_ctx: Optional[dict]


def prepare_analysis_context(y: np.ndarray, sr: int, tempo_window_override: Optional[float] = None) -> AnalysisContext:
    """Trim silence, build spectral contexts, and select the tempo window."""
    hop_length = settings.ANALYSIS_HOP_LENGTH

    trim_samples = int(0.5 * sr)
    y_trimmed = y[trim_samples:] if len(y) > trim_samples else y

    audio_duration = len(y_trimmed) / sr if sr else 0.0
    tempo_window_seconds = tempo_window_override if tempo_window_override is not None else settings.TEMPO_WINDOW_SECONDS
    skip_full_stft = audio_duration > tempo_window_seconds

    descriptor_ctx = None
    stft_magnitude = None
    if skip_full_stft:
        logger.info(
            "⏭️ Skipping full-track STFT for %.1fs song (> %.0fs threshold)",
            audio_duration,
            tempo_window_seconds,
        )
    else:
        descriptor_ctx = build_spectral_context(y_trimmed, sr, hop_length, settings.ANALYSIS_FFT_SIZE)
        stft_magnitude = descriptor_ctx.get("magnitude") if descriptor_ctx else None

    tempo_segment, tempo_start, tempo_window_meta = select_loudest_window(
        y_trimmed,
        sr,
        tempo_window_seconds,
    )
    if tempo_window_meta.get("full_track"):
        logger.info("🪟 Tempo window: full track (%.2fs)", tempo_window_meta.get("window_seconds", 0.0))
    else:
        logger.info(
            "🪟 Tempo window: %.2fs starting at %.2fs",
            tempo_window_meta.get("window_seconds", 0.0),
            tempo_window_meta.get("start_seconds", 0.0),
        )

    tempo_full_track = bool(tempo_window_meta.get("full_track"))
    tempo_ctx = descriptor_ctx if tempo_full_track else build_spectral_context(
        tempo_segment,
        sr,
        hop_length,
        settings.ANALYSIS_FFT_SIZE,
    )

    return AnalysisContext(
        y_trimmed=y_trimmed,
        hop_length=hop_length,
        descriptor_ctx=descriptor_ctx,
        stft_magnitude=stft_magnitude,
        tempo_segment=tempo_segment,
        tempo_start=tempo_start,
        tempo_window_meta=tempo_window_meta,
        tempo_ctx=tempo_ctx,
    )
