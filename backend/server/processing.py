"""Shared analysis execution helpers (process pool, resampling, workers)."""

from __future__ import annotations

import atexit
import concurrent.futures
from concurrent.futures import ProcessPoolExecutor
from io import BytesIO
import logging
import multiprocessing
import os
import signal
import sys
from threading import Lock
import tempfile
from typing import Dict, Optional, Tuple

import librosa
import numpy as np

from backend.analysis.essentia_support import HAS_ESSENTIA, es
from backend.analysis.key_detection import configure_key_detection
from backend.analysis.pipeline import stage_timer, CalibrationHooks
from backend.analysis.pipeline_core import perform_audio_analysis
from backend.analysis.pipeline_chunks import attach_chunk_analysis
from backend.analysis.settings import (
    ANALYSIS_RESAMPLE_TYPE,
    ANALYSIS_SAMPLE_RATE,
    CHUNK_ANALYSIS_ENABLED,
)
from backend.analysis.calibration import (
    apply_calibration_snapshot,
    calibration_snapshot,
)

LOGGER = logging.getLogger(__name__)

# Each process (main + worker pool) must register Essentia availability so the
# key detector emits the additional candidates used during calibration runs.
configure_key_detection(HAS_ESSENTIA, es)

_analysis_executor: Optional[ProcessPoolExecutor] = None
_analysis_executor_lock = Lock()
_calibration_hooks: Optional[CalibrationHooks] = None


def configure_processing(calibration_hooks: CalibrationHooks):
    """Store default calibration hooks for worker processes."""
    global _calibration_hooks
    _calibration_hooks = calibration_hooks


def _set_worker_priority():
    """Set lower priority for worker processes to not starve other apps."""
    try:
        # Set to lower priority (nice value 10 = lower priority than default 0)
        # This prevents analysis workers from interfering with user applications
        os.nice(10)
        LOGGER.debug("✅ Set worker process to lower priority (nice +10)")
    except Exception as exc:
        LOGGER.debug("⚠️ Could not set process priority: %s", exc)


def get_analysis_executor(max_workers: int) -> Optional[ProcessPoolExecutor]:
    """Lazily build a shared process pool when ANALYSIS_WORKERS > 0."""
    if max_workers <= 0:
        return None
    
    # CRITICAL: Detect nested multiprocessing to prevent deadlock
    # If we're already inside a worker process, don't create another pool
    current_process_name = multiprocessing.current_process().name
    if current_process_name != 'MainProcess':
        LOGGER.warning(
            "⚠️ Attempted to create ProcessPool from worker process '%s' - forcing sequential mode to prevent deadlock",
            current_process_name
        )
        return None
    
    global _analysis_executor
    with _analysis_executor_lock:
        if _analysis_executor is None:
            # Use 'spawn' to avoid fork() deadlocks with Flask/DB connections
            # Workers import functions directly, so they get their own clean environment
            ctx = multiprocessing.get_context("spawn")
            _analysis_executor = ProcessPoolExecutor(
                max_workers=max_workers,
                mp_context=ctx,
                initializer=_set_worker_priority  # Set lower priority to not starve system
            )
            LOGGER.info(
                "⚙️ Enabled analysis process pool (%d workers using 'spawn' context, nice +10 priority).",
                max_workers
            )
    return _analysis_executor


def _shutdown_analysis_executor():
    """Clean shutdown of worker pool with timeout."""
    global _analysis_executor
    executor = _analysis_executor
    if executor:
        LOGGER.info("🛑 Shutting down analysis worker pool...")
        try:
            # Give workers 5 seconds to finish, then force kill
            executor.shutdown(wait=True, cancel_futures=True)
            LOGGER.info("✅ Worker pool shutdown complete")
        except Exception as exc:
            LOGGER.warning("⚠️ Error during worker pool shutdown: %s", exc)
        finally:
            _analysis_executor = None


atexit.register(_shutdown_analysis_executor)


# Also register signal handlers for graceful shutdown
def _signal_handler(signum, frame):
    """Handle termination signals to clean up workers."""
    LOGGER.info(f"🚨 Received signal {signum}, shutting down workers...")
    _shutdown_analysis_executor()
    sys.exit(0)


try:
    signal.signal(signal.SIGTERM, _signal_handler)
    signal.signal(signal.SIGINT, _signal_handler)
except Exception:
    pass  # Signal handling may not work in all contexts


def _maybe_resample_for_analysis(y: np.ndarray, sr: int) -> Tuple[np.ndarray, int]:
    """Down-sample waveforms to the configured analysis rate to cut FFT load."""
    target_sr = ANALYSIS_SAMPLE_RATE
    if target_sr <= 0 or sr <= 0 or sr == target_sr:
        return y, sr
    try:
        with stage_timer(f"resample {sr}->{target_sr}"):
            resampled = librosa.resample(
                np.asarray(y, dtype=np.float32),
                orig_sr=sr,
                target_sr=target_sr,
                res_type=ANALYSIS_RESAMPLE_TYPE,
            )
        LOGGER.info(
            "🔁 Resampled waveform %d→%d Hz (%d→%d samples)",
            sr,
            target_sr,
            len(y),
            len(resampled),
        )
        return np.ascontiguousarray(resampled, dtype=np.float32), target_sr
    except Exception as exc:
        LOGGER.warning("⚠️ Global resample %d→%d Hz failed (%s); keeping original SR.", sr, target_sr, exc)
        return y, sr


def _run_analysis_inline(
    audio_bytes: bytes,
    title: str,
    artist: str,
    load_kwargs: Dict[str, object],
    chunk_enabled: bool,
    use_tempfile: bool,
    temp_suffix: str,
) -> Dict[str, object]:
    """Execute audio analysis in-process."""
    if use_tempfile:
        with tempfile.NamedTemporaryFile(suffix=temp_suffix) as tmp_file:
            tmp_file.write(audio_bytes)
            tmp_file.flush()
            LOGGER.info("💾 Saved to temp file: %s", tmp_file.name)
            y, sr = librosa.load(tmp_file.name, **load_kwargs)
        LOGGER.info("🗑️ Cleaned up temp file")
    else:
        audio_stream = BytesIO(audio_bytes)
        y, sr = librosa.load(audio_stream, **load_kwargs)
    y, sr = _maybe_resample_for_analysis(y, sr)
    LOGGER.info("🔊 Loaded audio: %d samples at %dHz (inline)", len(y), sr)
    hooks = _calibration_hooks
    result = perform_audio_analysis(y, sr, title, artist, calibration_hooks=hooks)
    if chunk_enabled:
        result = attach_chunk_analysis(result, y, sr, title, artist, calibration_hooks=hooks)
    else:
        result.setdefault("chunk_analysis", {"skipped": True})
    return result


def _analysis_worker_job(payload: Dict[str, object]) -> Dict[str, object]:
    """Entry point for process-pool analysis work."""
    apply_calibration_snapshot(payload.get("calibration_snapshot"))
    audio_bytes: bytes = payload["audio_bytes"]  # type: ignore[assignment]
    load_kwargs: Dict[str, object] = payload["load_kwargs"]  # type: ignore[assignment]
    chunk_enabled: bool = bool(payload.get("chunk_enabled"))
    use_tempfile: bool = bool(payload.get("use_tempfile"))
    temp_suffix: str = payload.get("temp_suffix", ".m4a")  # type: ignore[assignment]
    if use_tempfile:
        with tempfile.NamedTemporaryFile(suffix=temp_suffix) as tmp_file:
            tmp_file.write(audio_bytes)
            tmp_file.flush()
            LOGGER.info("💾 Saved to temp file: %s", tmp_file.name)
            y, sr = librosa.load(tmp_file.name, **load_kwargs)
        LOGGER.info("🗑️ Cleaned up temp file")
    else:
        audio_stream = BytesIO(audio_bytes)
        y, sr = librosa.load(audio_stream, **load_kwargs)
    y, sr = _maybe_resample_for_analysis(y, sr)
    LOGGER.info("🔊 Loaded audio: %d samples at %dHz (worker)", len(y), sr)
    hooks = _calibration_hooks
    result = perform_audio_analysis(y, sr, payload.get("title", "Unknown"), payload.get("artist", "Unknown"), calibration_hooks=hooks)
    if chunk_enabled:
        result = attach_chunk_analysis(result, y, sr, payload.get("title", "Unknown"), payload.get("artist", "Unknown"), calibration_hooks=hooks)
    else:
        result.setdefault("chunk_analysis", {"skipped": True})
    return result


def process_audio_bytes(
    audio_bytes: bytes,
    title: str,
    artist: str,
    skip_chunk_analysis: bool,
    load_kwargs: Dict[str, object],
    *,
    use_tempfile: bool = False,
    temp_suffix: str = ".m4a",
    max_workers: int,
    timeout: int = 120,  # 2 minutes max per song
) -> Dict[str, object]:
    """Route an audio buffer through either the process pool or inline analyzer."""
    chunk_enabled = CHUNK_ANALYSIS_ENABLED and not skip_chunk_analysis
    executor = get_analysis_executor(max_workers)
    if executor:
        payload = {
            "audio_bytes": audio_bytes,
            "title": title,
            "artist": artist,
            "load_kwargs": load_kwargs,
            "chunk_enabled": chunk_enabled,
            "use_tempfile": use_tempfile,
            "temp_suffix": temp_suffix,
            "calibration_snapshot": calibration_snapshot(),
        }
        try:
            # Add timeout protection - if analysis takes longer than timeout, raise exception
            future = executor.submit(_analysis_worker_job, payload)
            return future.result(timeout=timeout)
        except concurrent.futures.TimeoutError:
            LOGGER.error("❌ Analysis timed out after %ds for '%s' - %s", timeout, title, artist)
            raise TimeoutError(f"Analysis timed out after {timeout}s for '{title}' by {artist}")
        except Exception as exc:
            LOGGER.exception("⚠️ Process pool analysis failed, falling back inline: %s", exc)

    # Inline path (used for direct uploads like /analyze_data). To avoid
    # requests hanging forever when the underlying analysis stack blocks, wrap
    # the inline call in a one-shot ThreadPoolExecutor and enforce the same
    # timeout that the process-pool path uses.
    if timeout and timeout > 0:
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as thread_pool:
            future = thread_pool.submit(
                _run_analysis_inline,
                audio_bytes,
                title,
                artist,
                load_kwargs,
                chunk_enabled,
                use_tempfile,
                temp_suffix,
            )
            try:
                return future.result(timeout=timeout)
            except concurrent.futures.TimeoutError:
                LOGGER.error(
                    "❌ Inline analysis timed out after %ds for '%s' - %s",
                    timeout,
                    title,
                    artist,
                )
                raise TimeoutError(f"Analysis timed out after {timeout}s for '{title}' by {artist}")

    # Fallback with no extra timeout guard (timeout<=0).
    return _run_analysis_inline(
        audio_bytes,
        title,
        artist,
        load_kwargs,
        chunk_enabled,
        use_tempfile,
        temp_suffix,
    )


__all__ = ["configure_processing", "process_audio_bytes"]
