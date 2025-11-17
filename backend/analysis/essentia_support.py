"""Shared Essentia helpers used across the analysis pipeline."""

from __future__ import annotations

import logging
from typing import Optional

import librosa
import numpy as np

from backend.analysis import settings

logger = logging.getLogger(__name__)

try:
    import essentia.standard as es  # type: ignore
    HAS_ESSENTIA = True
except Exception:  # pragma: no cover - Essentia optional
    es = None
    HAS_ESSENTIA = False

TONAL_FALLBACK_SR = 44100
_tonal_extractor_runtime_enabled = settings.ENABLE_TONAL_EXTRACTOR


def tonal_extractor_allowed() -> bool:
    """Return True when Essentia's TonalExtractor should be used."""
    return HAS_ESSENTIA and _tonal_extractor_runtime_enabled


def disable_tonal_extractor_runtime(exc: Exception) -> None:
    """Permanently disable TonalExtractor for this process after a fatal error."""
    global _tonal_extractor_runtime_enabled
    if not _tonal_extractor_runtime_enabled:
        return
    _tonal_extractor_runtime_enabled = False
    logger.warning(
        "🚫 Disabling Essentia TonalExtractor for this process (%s). Falling back to librosa tonnetz.",
        exc,
    )


def resample_for_tonal_extractor(
    audio32: np.ndarray,
    sr: int,
    target_sr: int = TONAL_FALLBACK_SR,
) -> np.ndarray:
    """Resample audio to the sample rate expected by Essentia's TonalExtractor."""
    if sr == target_sr:
        return audio32
    try:
        resampled = librosa.resample(
            np.asarray(audio32, dtype=np.float32),
            orig_sr=sr,
            target_sr=target_sr,
        )
        return np.ascontiguousarray(resampled.astype(np.float32))
    except Exception as exc:  # pragma: no cover - diagnostic logging only
        logger.warning("⚠️ TonalExtractor resample fallback failed: %s", exc)
        return audio32


def run_tonal_extractor(audio32: np.ndarray, sr: int):
    """Run Essentia's TonalExtractor with a fallback that omits the sampleRate argument."""
    if audio32 is None or audio32.size == 0:
        raise ValueError("Empty audio payload for TonalExtractor.")
    if es is None:
        raise RuntimeError("Essentia TonalExtractor unavailable.")
    last_exc: Optional[Exception] = None
    try:
        extractor = es.TonalExtractor(frameSize=4096, hopSize=2048, sampleRate=sr)
        return extractor(audio32)
    except Exception as exc:
        message = str(exc)
        last_exc = exc
        if "sampleRate" not in message:
            raise
        logger.info("♻️ Essentia TonalExtractor fallback: %s. Retrying without sampleRate.", message)
    tonal_audio = resample_for_tonal_extractor(audio32, sr, TONAL_FALLBACK_SR)
    extractor = es.TonalExtractor(frameSize=4096, hopSize=2048)
    try:
        return extractor(tonal_audio)
    except Exception:
        if last_exc:
            raise last_exc
        raise


__all__ = [
    "HAS_ESSENTIA",
    "es",
    "TONAL_FALLBACK_SR",
    "tonal_extractor_allowed",
    "disable_tonal_extractor_runtime",
    "resample_for_tonal_extractor",
    "run_tonal_extractor",
]
