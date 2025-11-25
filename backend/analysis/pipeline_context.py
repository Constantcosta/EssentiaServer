"""Shared signal-processing helpers for the audio analysis pipeline."""

from __future__ import annotations

import logging
from typing import Dict, Optional, Tuple

import librosa
import numpy as np

logger = logging.getLogger(__name__)


def build_spectral_context(
    y_signal: np.ndarray,
    sr: int,
    hop_length: int,
    n_fft: int,
) -> Dict[str, object]:
    """Compute and cache STFT artifacts shared across analysis stages."""
    if y_signal.size == 0 or sr <= 0:
        return {}
    
    # Adjust n_fft if signal is too short (prevents librosa warnings)
    effective_n_fft = n_fft
    if y_signal.size < n_fft:
        # Use next power of 2 that's smaller than signal length
        effective_n_fft = 2 ** int(np.floor(np.log2(y_signal.size)))
        effective_n_fft = max(256, effective_n_fft)  # Minimum 256 for reasonable frequency resolution
        if effective_n_fft >= y_signal.size:
            effective_n_fft = 256  # Fallback to minimum
        logger.debug(
            "📏 Short signal (%d samples): reduced n_fft from %d to %d",
            y_signal.size,
            n_fft,
            effective_n_fft,
        )
    
    try:
        stft_matrix = librosa.stft(
            y_signal,
            n_fft=effective_n_fft,
            hop_length=hop_length,
            window="hann",
            center=True,
        )
    except Exception as exc:
        logger.warning("⚠️ Shared STFT build failed: %s", exc)
        return {}
    magnitude = np.abs(stft_matrix)
    return {
        "stft": stft_matrix,
        "magnitude": magnitude,
        "hop_length": hop_length,
        "n_fft": effective_n_fft,  # Return the actual n_fft used
    }


def select_loudest_window(
    y_signal: np.ndarray,
    sr: int,
    window_seconds: float,
) -> Tuple[np.ndarray, int, Dict[str, float]]:
    """Select the highest-energy window for tempo analysis."""
    total_samples = y_signal.size
    full_duration = total_samples / sr if sr else 0.0
    meta = {
        "window_seconds": full_duration,
        "start_seconds": 0.0,
        "end_seconds": full_duration,
        "full_track": True,
    }
    if total_samples == 0 or sr <= 0 or window_seconds <= 0:
        return y_signal, 0, meta
    window_samples = int(window_seconds * sr)
    if window_samples <= 0 or window_samples >= total_samples:
        return y_signal, 0, meta
    
    # CRITICAL FIX: For very long songs (> 2x window), skip expensive convolution
    # and just use the first window segment (typically intro has consistent tempo)
    # The convolution was taking 120+ seconds for 4-minute songs
    if total_samples > (window_samples * 2):
        logger.info("⏭️ Long song (%.1fs): using first %.1fs instead of searching", full_duration, window_seconds)
        meta = {
            "window_seconds": window_seconds,
            "start_seconds": 0.0,
            "end_seconds": window_seconds,
            "full_track": False,
        }
        return np.array(y_signal[:window_samples], dtype=y_signal.dtype, copy=True), 0, meta
    
    energy = np.convolve(
        np.square(y_signal.astype(np.float32)),
        np.ones(window_samples, dtype=np.float32),
        mode="valid",
    )
    if energy.size == 0:
        return y_signal, 0, meta
    start = int(np.argmax(energy))
    end = start + window_samples
    meta = {
        "window_seconds": window_samples / sr,
        "start_seconds": start / sr,
        "end_seconds": end / sr,
        "full_track": False,
    }
    return np.array(y_signal[start:end], dtype=y_signal.dtype, copy=True), start, meta


def harmonic_percussive_components(
    y_signal: np.ndarray,
    spectral_ctx: Optional[Dict[str, object]],
    hop_length: int,
) -> Dict[str, Optional[np.ndarray]]:
    """Return harmonic/percussive decompositions with STFT caches when possible."""
    stft_matrix = spectral_ctx.get("stft") if spectral_ctx else None
    if stft_matrix is None:
        y_harm, y_perc = librosa.effects.hpss(y_signal)
        return {
            "y_harmonic": y_harm,
            "y_percussive": y_perc,
            "stft_harmonic": None,
            "stft_percussive": None,
        }
    try:
        stft_harm, stft_perc = librosa.decompose.hpss(stft_matrix)
        y_harm = librosa.istft(stft_harm, hop_length=hop_length, length=len(y_signal))
        return {
            "y_harmonic": y_harm,
            "y_percussive": None,
            "stft_harmonic": stft_harm,
            "stft_percussive": stft_perc,
        }
    except Exception as exc:
        logger.warning("⚠️ STFT-based HPSS failed (%s); falling back to time-domain HPSS.", exc)
        y_harm, y_perc = librosa.effects.hpss(y_signal)
        return {
            "y_harmonic": y_harm,
            "y_percussive": y_perc,
            "stft_harmonic": None,
            "stft_percussive": None,
        }


__all__ = [
    "build_spectral_context",
    "select_loudest_window",
    "harmonic_percussive_components",
]
