"""Cache helpers shared by API endpoints."""

from __future__ import annotations

import hashlib
import json
import logging
from typing import Dict, Optional

from backend.server.database import get_db_connection

logger = logging.getLogger(__name__)

DEFAULT_CACHE_NAMESPACE = "default"


def get_url_hash(url: str, namespace: str = DEFAULT_CACHE_NAMESPACE) -> str:
    key = f"{namespace}::{url}"
    return hashlib.sha256(key.encode()).hexdigest()


def check_cache(preview_url: str, namespace: str = DEFAULT_CACHE_NAMESPACE) -> Optional[Dict[str, object]]:
    url_hash = get_url_hash(preview_url, namespace=namespace)

    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT bpm, bpm_confidence, key, key_confidence,
                   energy, danceability, acousticness, spectral_centroid,
                   analysis_duration, analyzed_at, time_signature, valence, mood,
             loudness, dynamic_range, silence_ratio, key_details, chunk_analysis, analysis_timing,
                   dynamic_complexity, tonal_strength, spectral_complexity,
             zero_crossing_rate, spectral_flux,
             percussive_energy_ratio, harmonic_energy_ratio
            FROM analysis_cache
            WHERE preview_url_hash = ? AND cache_namespace = ?
            """,
            (url_hash, namespace),
        )
        row = cursor.fetchone()
    if not row:
        logger.info("❌ CACHE MISS for %s...", preview_url[:50])
        return None
    logger.info("✅ CACHE HIT for %s...", preview_url[:50])
    cached = {
        "bpm": row["bpm"],
        "bpm_confidence": row["bpm_confidence"],
        "key": row["key"],
        "key_confidence": row["key_confidence"],
        "energy": row["energy"],
        "danceability": row["danceability"],
        "acousticness": row["acousticness"],
        "spectral_centroid": row["spectral_centroid"],
        "analysis_duration": row["analysis_duration"] or 0.0,
        "cached": True,
        "analyzed_at": row["analyzed_at"],
        "time_signature": row["time_signature"],
        "valence": row["valence"],
        "mood": row["mood"],
        "loudness": row["loudness"],
        "dynamic_range": row["dynamic_range"],
        "silence_ratio": row["silence_ratio"],
    "key_details": None,
        "dynamic_complexity": row["dynamic_complexity"],
        "tonal_strength": row["tonal_strength"],
        "spectral_complexity": row["spectral_complexity"],
        "zero_crossing_rate": row["zero_crossing_rate"],
        "spectral_flux": row["spectral_flux"],
        "percussive_energy_ratio": row["percussive_energy_ratio"],
        "harmonic_energy_ratio": row["harmonic_energy_ratio"],
    }
    details_raw = row["key_details"]
    if details_raw:
        try:
            cached["key_details"] = json.loads(details_raw)
        except json.JSONDecodeError:
            logger.warning("⚠️ Could not decode cached key details JSON.")
    chunk_raw = row["chunk_analysis"]
    if chunk_raw:
        try:
            cached["chunk_analysis"] = json.loads(chunk_raw)
        except json.JSONDecodeError:
            logger.warning("⚠️ Could not decode cached chunk analysis JSON.")
    timing_raw = row["analysis_timing"]
    if timing_raw:
        try:
            cached["analysis_timing"] = json.loads(timing_raw)
        except json.JSONDecodeError:
            logger.warning("⚠️ Could not decode cached analysis timing JSON.")
    return cached


def save_to_cache(
    preview_url: str,
    title: str,
    artist: str,
    analysis_result: Dict[str, object],
    duration: float,
    *,
    namespace: str = DEFAULT_CACHE_NAMESPACE,
):
    url_hash = get_url_hash(preview_url, namespace=namespace)
    chunk_payload = (
        json.dumps(analysis_result.get("chunk_analysis")) if analysis_result.get("chunk_analysis") else None
    )
    timing_payload = (
        json.dumps(analysis_result.get("analysis_timing")) if analysis_result.get("analysis_timing") else None
    )
    key_details_payload = (
        json.dumps(analysis_result.get("key_details")) if analysis_result.get("key_details") else None
    )
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT OR REPLACE INTO analysis_cache (
                preview_url_hash, cache_namespace, title, artist, preview_url,
                bpm, bpm_confidence, key, key_confidence,
                energy, danceability, acousticness, spectral_centroid,
                analysis_duration, time_signature, valence, mood,
                loudness, dynamic_range, silence_ratio, key_details, analysis_timing, chunk_analysis,
                dynamic_complexity, tonal_strength, spectral_complexity,
                zero_crossing_rate, spectral_flux,
                percussive_energy_ratio, harmonic_energy_ratio
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                url_hash,
                namespace,
                title,
                artist,
                preview_url,
                analysis_result["bpm"],
                analysis_result["bpm_confidence"],
                analysis_result["key"],
                analysis_result["key_confidence"],
                analysis_result["energy"],
                analysis_result["danceability"],
                analysis_result["acousticness"],
                analysis_result["spectral_centroid"],
                duration,
                analysis_result.get("time_signature"),
                analysis_result.get("valence"),
                analysis_result.get("mood"),
                analysis_result.get("loudness"),
                analysis_result.get("dynamic_range"),
                analysis_result.get("silence_ratio"),
                key_details_payload,
                timing_payload,
                chunk_payload,
                analysis_result.get("dynamic_complexity"),
                analysis_result.get("tonal_strength"),
                analysis_result.get("spectral_complexity"),
                analysis_result.get("zero_crossing_rate"),
                analysis_result.get("spectral_flux"),
                analysis_result.get("percussive_energy_ratio"),
                analysis_result.get("harmonic_energy_ratio"),
            ),
        )
    logger.info("💾 Cached analysis for '%s' by %s", title, artist)


def update_stats(cache_hit: bool):
    """Update cache statistics."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        if cache_hit:
            cursor.execute(
                """
                UPDATE server_stats
                SET cache_hits = cache_hits + 1,
                    total_analyses = total_analyses + 1,
                    last_updated = CURRENT_TIMESTAMP
                WHERE id = 1
                """
            )
        else:
            cursor.execute(
                """
                UPDATE server_stats
                SET cache_misses = cache_misses + 1,
                    total_analyses = total_analyses + 1,
                    last_updated = CURRENT_TIMESTAMP
                WHERE id = 1
                """
            )


__all__ = ["check_cache", "save_to_cache", "update_stats", "get_url_hash", "DEFAULT_CACHE_NAMESPACE"]
