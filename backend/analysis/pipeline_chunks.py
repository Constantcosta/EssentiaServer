"""Chunk-level analysis helpers."""

from __future__ import annotations

import logging
import math
import time
from collections import Counter
from typing import Dict, List, Optional, Tuple

import numpy as np

from backend.analysis import settings
from backend.analysis.key_detection import KEY_NAMES
from backend.analysis.pipeline import CalibrationHooks, stage_timer
from backend.analysis.pipeline_chunk_utils import (
    CHUNK_ANALYSIS_ENABLED,
    CHUNK_ANALYSIS_SECONDS,
    CHUNK_BEAT_TARGET,
    MIN_CHUNK_DURATION_SECONDS,
    should_run_chunk_analysis,
)
from backend.analysis.pipeline_core import perform_audio_analysis

logger = logging.getLogger(__name__)

CHUNK_OVERLAP_SECONDS = settings.CHUNK_OVERLAP_SECONDS
MAX_CHUNK_BATCHES = settings.MAX_CHUNK_BATCHES
CONSENSUS_STD_EPS = settings.CONSENSUS_STD_EPS


def _chunk_parameters(sr: int, bpm_hint: Optional[float] = None) -> Dict[str, float]:
    chunk_seconds = max(CHUNK_ANALYSIS_SECONDS, MIN_CHUNK_DURATION_SECONDS)
    if bpm_hint and bpm_hint > 0:
        beat_window = (CHUNK_BEAT_TARGET * 60.0) / bpm_hint
        chunk_seconds = max(
            MIN_CHUNK_DURATION_SECONDS,
            min(CHUNK_ANALYSIS_SECONDS, beat_window),
        )
    chunk_samples = max(int(chunk_seconds * sr), 1)
    overlap_seconds = max(0.0, min(CHUNK_OVERLAP_SECONDS, chunk_seconds * 0.9))
    hop_seconds = chunk_seconds - overlap_seconds
    if hop_seconds <= chunk_seconds * 0.05:
        hop_seconds = chunk_seconds * 0.5
    hop_samples = max(int(hop_seconds * sr), 1)
    min_chunk_samples = max(int(MIN_CHUNK_DURATION_SECONDS * sr), 1)
    return {
        "chunk_seconds": chunk_seconds,
        "chunk_samples": chunk_samples,
        "hop_seconds": hop_seconds,
        "hop_samples": hop_samples,
        "min_chunk_samples": min_chunk_samples,
        "bpm_hint": bpm_hint,
    }


def compute_chunk_summaries(
    y: np.ndarray,
    sr: int,
    title: str,
    artist: str,
    bpm_hint: Optional[float] = None,
    calibration_hooks: Optional[CalibrationHooks] = None,
) -> Tuple[List[Dict[str, object]], Dict[str, object]]:
    """Split the track into overlapping windows and analyze each chunk for stability."""
    total_duration = len(y) / sr if sr else 0.0
    if not should_run_chunk_analysis(total_duration):
        return [], {"truncated": False, "total_possible": 0}

    params = _chunk_parameters(sr, bpm_hint=bpm_hint)
    summaries: List[Dict[str, object]] = []
    truncated = False
    chunk_index = 0
    total_weight = 0.0
    max_weight = 0.0
    analysis_time = 0.0
    wall_start = time.perf_counter()
    
    # Safeguard: abort chunk analysis if chunks become abnormally slow
    CHUNK_TIMEOUT_SECONDS = 30.0  # Max time per chunk before aborting
    consecutive_slow_chunks = 0
    MAX_SLOW_CHUNKS = 2  # Abort if 2 consecutive chunks exceed expected time

    for start in range(0, len(y), params["hop_samples"]):
        end = min(start + params["chunk_samples"], len(y))
        samples = end - start
        if samples < params["min_chunk_samples"]:
            break

        chunk_index += 1
        if len(summaries) >= MAX_CHUNK_BATCHES:
            truncated = True
            break

        chunk_y = y[start:end]
        chunk_label = f"{title}::chunk#{len(summaries) + 1}"
        chunk_start_time = time.perf_counter()
        with stage_timer(chunk_label):
            chunk_result = perform_audio_analysis(
                chunk_y,
                sr,
                f"{title} (chunk {len(summaries) + 1})",
                artist,
                calibration_hooks=calibration_hooks,
            )
        chunk_elapsed = time.perf_counter() - chunk_start_time
        
        # Safety check: detect abnormally slow chunks
        expected_max_time = max(5.0, params["chunk_seconds"])  # Expected: ~chunk duration or 5s
        if chunk_elapsed > CHUNK_TIMEOUT_SECONDS:
            logger.warning(
                "⚠️ Chunk %d took %.1fs (timeout threshold: %.1fs) — aborting remaining chunks for %s",
                len(summaries) + 1,
                chunk_elapsed,
                CHUNK_TIMEOUT_SECONDS,
                title,
            )
            truncated = True
            break
        elif chunk_elapsed > expected_max_time:
            consecutive_slow_chunks += 1
            if consecutive_slow_chunks >= MAX_SLOW_CHUNKS:
                logger.warning(
                    "⚠️ %d consecutive slow chunks detected (%.1fs avg) — aborting chunk analysis for %s to prevent hang",
                    consecutive_slow_chunks,
                    chunk_elapsed,
                    title,
                )
                truncated = True
                break
        else:
            consecutive_slow_chunks = 0  # Reset counter on normal-speed chunk
        key_details = chunk_result.get("key_details") or {}
        key_index = key_details.get("key_index")
        if key_index is not None:
            try:
                key_index = int(key_index) % 12
            except (TypeError, ValueError):
                key_index = None
        key_mode = key_details.get("mode")
        if not key_mode and isinstance(chunk_result.get("key"), str) and " " in chunk_result["key"]:
            key_mode = chunk_result["key"].split(" ", 1)[1]
        key_detail_conf = key_details.get("confidence")
        try:
            key_detail_conf = float(key_detail_conf) if key_detail_conf is not None else None
        except (TypeError, ValueError):
            key_detail_conf = None

        summary = {
            "index": len(summaries) + 1,
            "start": round(start / sr, 3),
            "end": round(end / sr, 3),
            "duration": round((end - start) / sr, 3),
            "bpm": float(chunk_result["bpm"]),
            "bpm_confidence": float(chunk_result["bpm_confidence"]),
            "key": chunk_result["key"],
            "key_confidence": float(chunk_result["key_confidence"]),
            "key_index": key_index,
            "key_mode": key_mode,
            "key_detail_confidence": key_detail_conf,
            "key_source": key_details.get("key_source"),
            "energy": float(chunk_result["energy"]),
            "danceability": float(chunk_result["danceability"]),
            "acousticness": float(chunk_result["acousticness"]),
            "spectral_centroid": float(chunk_result["spectral_centroid"]),
            "valence": float(chunk_result["valence"])
            if chunk_result.get("valence") is not None
            else None,
            "mood": chunk_result.get("mood"),
            "loudness": float(chunk_result["loudness"])
            if chunk_result.get("loudness") is not None
            else None,
            "dynamic_range": float(chunk_result["dynamic_range"])
            if chunk_result.get("dynamic_range") is not None
            else None,
            "silence_ratio": float(chunk_result["silence_ratio"])
            if chunk_result.get("silence_ratio") is not None
            else None,
            "analysis_duration": float(chunk_result.get("analysis_duration", 0.0)),
        }
        analysis_time += max(0.0, summary["analysis_duration"])
        energy_weight = float(chunk_result.get("energy", 0.0))
        energy_weight = max(0.05, min(1.5, energy_weight))
        summary["energy_weight"] = energy_weight
        total_weight += energy_weight
        max_weight = max(max_weight, energy_weight)
        summaries.append(summary)
    wall_elapsed = time.perf_counter() - wall_start
    avg_analysis = analysis_time / len(summaries) if summaries else 0.0
    overhead_time = max(0.0, wall_elapsed - analysis_time)
    if summaries:
        logger.info(
            "🧩 Chunk timings for %s — %d/%d windows, wall %.2fs, analyzer %.2fs, overhead %.2fs",
            title,
            len(summaries),
            chunk_index,
            wall_elapsed,
            analysis_time,
            overhead_time,
        )
    return summaries, {
        "truncated": truncated or chunk_index > len(summaries),
        "total_possible": chunk_index,
        "chunk_seconds": params["chunk_seconds"],
        "hop_seconds": params["hop_seconds"],
        "bpm_hint": bpm_hint,
        "energy_weight_sum": total_weight,
        "energy_weight_max": max_weight,
        "wall_time": wall_elapsed,
        "analysis_time_sum": analysis_time,
        "analysis_time_avg": avg_analysis,
        "analysis_overhead": overhead_time,
    }


def _weighted_stat(chunk_summaries: List[Dict[str, object]], field: str, use_median: bool = False):
    values = []
    weights = []
    for chunk in chunk_summaries:
        value = chunk.get(field)
        if value is None:
            continue
        values.append(float(value))
        weights.append(max(0.01, float(chunk.get("energy_weight", chunk.get("energy", 0.5)))))
    if not values:
        return None
    arr = np.array(values, dtype=float)
    weight_arr = np.array(weights, dtype=float)
    total_weight = float(np.sum(weight_arr))
    if total_weight <= 0:
        weight_arr = np.ones_like(arr)
        total_weight = float(len(arr))
    weighted_mean = float(np.sum(arr * weight_arr) / total_weight)
    weighted_var = (
        float(np.sum(weight_arr * (arr - weighted_mean) ** 2) / total_weight)
        if len(arr) > 1
        else 0.0
    )
    weighted_std = float(np.sqrt(weighted_var))
    simple_mean = float(np.mean(arr))
    simple_std = float(np.std(arr)) if len(arr) > 1 else 0.0
    if use_median:
        median_val = float(np.median(arr))
        return {
            "value": median_val,
            "weighted_mean": weighted_mean,
            "weighted_std": weighted_std,
            "weighted_variance": weighted_var,
            "mean": simple_mean,
            "std": simple_std,
            "count": len(arr),
            "weight_sum": total_weight,
        }
    return {
        "value": weighted_mean,
        "weighted_mean": weighted_mean,
        "weighted_std": weighted_std,
        "weighted_variance": weighted_var,
        "mean": simple_mean,
        "std": simple_std,
        "count": len(arr),
        "weight_sum": total_weight,
    }


def _key_mode_label(mode_value: Optional[str]) -> str:
    if mode_value is None:
        return "Major"
    text = str(mode_value).strip().lower()
    if text.startswith("min"):
        return "Minor"
    return "Major"


def _key_entries(chunk_summaries: List[Dict[str, object]]) -> List[Dict[str, float]]:
    entries: List[Dict[str, float]] = []
    for chunk in chunk_summaries:
        root = chunk.get("key_index")
        if root is None:
            continue
        key_mode = _key_mode_label(chunk.get("key_mode"))
        key_confidence = float(chunk.get("key_confidence", 0.0))
        detail_conf = chunk.get("key_detail_confidence")
        if detail_conf is not None:
            try:
                key_confidence = max(key_confidence, float(detail_conf))
            except (TypeError, ValueError):
                key_confidence = key_confidence
        if key_confidence < 0.1:
            continue
        energy_weight = max(0.1, float(chunk.get("energy_weight", chunk.get("energy", 0.5) or 0.5)))
        weight = key_confidence * energy_weight
        entries.append(
            {
                "root": float(int(root) % 12),
                "mode": key_mode,
                "weight": float(weight),
            }
        )
    return entries


def _key_dispersion(entries: List[Dict[str, float]]) -> Optional[float]:
    total_weight = sum(entry["weight"] for entry in entries if entry["weight"] > 0)
    if total_weight <= 0:
        return None
    angle_factor = 2.0 * math.pi / 12.0
    cos_sum = 0.0
    sin_sum = 0.0
    for entry in entries:
        angle = entry["root"] * angle_factor
        cos_sum += math.cos(angle) * entry["weight"]
        sin_sum += math.sin(angle) * entry["weight"]
    R = math.sqrt(cos_sum ** 2 + sin_sum ** 2) / total_weight
    R = max(min(R, 1.0), 1e-9)
    dispersion = math.sqrt(max(0.0, -2.0 * math.log(R))) * (12.0 / (2.0 * math.pi))
    return dispersion


def build_chunk_consensus(chunk_summaries: List[Dict[str, object]]) -> Dict[str, object]:
    """Compute aggregate stats from chunk windows to stabilize global metrics."""
    if not chunk_summaries:
        return {}

    consensus: Dict[str, object] = {}
    diagnostics: Dict[str, object] = {}

    bpm_stat = _weighted_stat(chunk_summaries, "bpm", use_median=True)
    if bpm_stat:
        consensus["bpm"] = bpm_stat["value"]
        bpm_mean_ref = max(bpm_stat["weighted_mean"], CONSENSUS_STD_EPS)
        bpm_conf = 1.0 - min(1.0, bpm_stat["weighted_std"] / (bpm_mean_ref + CONSENSUS_STD_EPS))
        consensus["bpm_confidence"] = max(0.0, min(1.0, bpm_conf))
        diagnostics["bpm_weighted_std"] = bpm_stat["weighted_std"]
        diagnostics["bpm_weighted_variance"] = bpm_stat["weighted_variance"]
        diagnostics["bpm_std"] = bpm_stat["std"]

    key_entries = _key_entries(chunk_summaries)
    if key_entries:
        total_weight = sum(entry["weight"] for entry in key_entries)
        weight_map: Dict[Tuple[int, str], float] = {}
        for entry in key_entries:
            key = (int(entry["root"]) % 12, _key_mode_label(entry["mode"]))
            weight_map[key] = weight_map.get(key, 0.0) + entry["weight"]
        best_key, best_weight = max(weight_map.items(), key=lambda item: item[1])
        label = f"{KEY_NAMES[best_key[0]]} {best_key[1]}"
        consensus["key"] = label
        weight_sum = total_weight if total_weight > 0 else 1e-9
        key_confidence = min(1.0, best_weight / weight_sum)
        consensus["key_confidence"] = key_confidence
        diagnostics["key_weight_sum"] = total_weight
        diagnostics["key_weighted_counts"] = [
            {
                "root": idx,
                "mode": mode,
                "label": f"{KEY_NAMES[idx]} {mode}",
                "weight": float(weight),
            }
            for (idx, mode), weight in sorted(weight_map.items(), key=lambda item: item[1], reverse=True)
        ]
        diagnostics["key_entry_count"] = len(key_entries)
        dispersion = _key_dispersion(key_entries)
        if dispersion is not None:
            diagnostics["key_dispersion_semitones"] = dispersion
            consensus["key_dispersion_semitones"] = dispersion
            if dispersion > 3.0:
                consensus["key_modulating"] = True
                consensus["key_confidence"] = min(consensus["key_confidence"], 0.45)

    mood_counts = Counter(chunk["mood"] for chunk in chunk_summaries if chunk.get("mood"))
    if mood_counts:
        consensus["mood"] = mood_counts.most_common(1)[0][0]

    for field in [
        "energy",
        "danceability",
        "acousticness",
        "spectral_centroid",
        "valence",
        "dynamic_range",
        "silence_ratio",
        "loudness",
    ]:
        stat = _weighted_stat(chunk_summaries, field)
        if stat:
            consensus[field] = stat["value"]
            diagnostics[f"{field}_weighted_std"] = stat["weighted_std"]
            diagnostics[f"{field}_weighted_variance"] = stat["weighted_variance"]

    consensus["diagnostics"] = diagnostics
    return consensus


def merge_chunk_consensus(result: Dict[str, object], consensus: Dict[str, object]) -> Dict[str, object]:
    """Blend the consensus data back into the primary analysis result."""
    if not consensus:
        return result

    consensus_values = {k: v for k, v in consensus.items() if k != "diagnostics"}
    for field in [
        "bpm",
        "energy",
        "danceability",
        "acousticness",
        "spectral_centroid",
        "valence",
        "dynamic_range",
        "silence_ratio",
        "loudness",
    ]:
        if consensus_values.get(field) is not None:
            result[field] = consensus_values[field]

    if consensus_values.get("bpm_confidence") is not None:
        result["bpm_confidence"] = max(result.get("bpm_confidence", 0.0), consensus_values["bpm_confidence"])

    if consensus_values.get("key"):
        result["key"] = consensus_values["key"]
    key_confidence = consensus_values.get("key_confidence")
    key_modulating = bool(consensus_values.get("key_modulating"))
    if key_confidence is not None:
        if key_modulating:
            existing_conf = result.get("key_confidence")
            if existing_conf is None:
                result["key_confidence"] = key_confidence
            else:
                result["key_confidence"] = min(float(existing_conf), float(key_confidence))
            result["key_confidence"] = min(result["key_confidence"], 0.45)
        else:
            result["key_confidence"] = max(result.get("key_confidence", 0.0), key_confidence)
    if consensus_values.get("key_dispersion_semitones") is not None:
        result["key_dispersion_semitones"] = consensus_values["key_dispersion_semitones"]
    if key_modulating:
        result["key_modulating"] = True

    if consensus_values.get("mood"):
        result["mood"] = consensus_values["mood"]

    return result


def attach_chunk_analysis(
    result: Dict[str, object],
    y: np.ndarray,
    sr: int,
    title: str,
    artist: str,
    calibration_hooks: Optional[CalibrationHooks] = None,
) -> Dict[str, object]:
    """Run per-chunk analysis (if eligible) and attach metadata to the result."""
    bpm_hint = float(result.get("bpm")) if result.get("bpm") else None
    chunk_summaries, meta = compute_chunk_summaries(
        y,
        sr,
        title,
        artist,
        bpm_hint=bpm_hint,
        calibration_hooks=calibration_hooks,
    )
    if not chunk_summaries:
        return result

    logger.info("🧩 Chunk analysis: %d windows (~%.1fs each)", len(chunk_summaries), meta["chunk_seconds"])
    consensus = build_chunk_consensus(chunk_summaries)
    result = merge_chunk_consensus(result, consensus)
    consensus_values = {k: v for k, v in consensus.items() if k != "diagnostics"}
    result["chunk_analysis"] = {
        "windows": chunk_summaries,
        "consensus": consensus_values,
        "diagnostics": consensus.get("diagnostics", {}),
        "window_seconds": meta["chunk_seconds"],
        "hop_seconds": meta["hop_seconds"],
        "bpm_hint": meta.get("bpm_hint"),
        "energy_weight_sum": meta.get("energy_weight_sum"),
        "energy_weight_max": meta.get("energy_weight_max"),
        "truncated": meta["truncated"],
        "total_possible": meta.get("total_possible"),
        "wall_time_seconds": meta.get("wall_time"),
        "analysis_time_seconds": meta.get("analysis_time_sum"),
        "analysis_time_avg_seconds": meta.get("analysis_time_avg"),
        "analysis_overhead_seconds": meta.get("analysis_overhead"),
        "chunks_evaluated": len(chunk_summaries),
        "max_chunks": MAX_CHUNK_BATCHES,
    }
    return result


__all__ = [
    "should_run_chunk_analysis",
    "compute_chunk_summaries",
    "attach_chunk_analysis",
    "build_chunk_consensus",
    "merge_chunk_consensus",
]
