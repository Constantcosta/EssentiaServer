"""Cache-related HTTP handlers shared by the Flask app."""

from __future__ import annotations

import csv
import json
import logging
from datetime import datetime
from io import StringIO
from pathlib import Path
from typing import Optional

from flask import jsonify, request, send_file

from backend.analysis.reporting import ANALYSIS_TIMER_EXPORT_FIELDS, CHUNK_TIMING_EXPORT_FIELDS
from backend.analysis.utils import percentage, safe_float
from backend.server.database import get_db_connection

logger = logging.getLogger(__name__)

_EXPORT_DIR: Path | None = None


def configure_cache_routes(export_dir: Path):
    global _EXPORT_DIR
    _EXPORT_DIR = export_dir


def _requested_namespace(default: Optional[str]) -> Optional[str]:
    raw = request.args.get("namespace")
    if raw is None:
        return default
    raw = raw.strip()
    if not raw:
        return default
    lowered = raw.lower()
    if lowered in {"all", "*"}:
        return None
    cleaned = "".join(ch for ch in raw if ch.isalnum() or ch in {"-", "_"})
    if not cleaned:
        return default
    return cleaned[:32]


def cache_search():
    query = request.args.get("q", "")
    namespace = _requested_namespace(default="default")
    with get_db_connection() as conn:
        cursor = conn.cursor()
        sql = """
         SELECT id, title, artist, preview_url, bpm, bpm_confidence, key, key_confidence,
             energy, danceability, acousticness, spectral_centroid, analyzed_at,
             analysis_duration, time_signature, valence, mood, loudness,
             dynamic_range, silence_ratio, key_details,
             user_verified, manual_bpm, manual_key, bpm_notes,
                   dynamic_complexity, tonal_strength, spectral_complexity,
                   zero_crossing_rate, spectral_flux,
                   percussive_energy_ratio, harmonic_energy_ratio
            FROM analysis_cache
            WHERE (artist LIKE ? OR title LIKE ?)
        """
        params = [f"%{query}%", f"%{query}%"]
        if namespace is not None:
            sql += " AND cache_namespace = ?"
            params.append(namespace)
        sql += " ORDER BY analyzed_at DESC LIMIT 100"
        cursor.execute(sql, params)
        results = cursor.fetchall()
    songs = [
        {
            "id": r[0],
            "title": r[1],
            "artist": r[2],
            "preview_url": r[3],
            "bpm": r[4],
            "bpm_confidence": r[5],
            "key": r[6],
            "key_confidence": r[7],
            "energy": r[8],
            "danceability": r[9],
            "acousticness": r[10],
            "spectral_centroid": r[11],
            "analyzed_at": r[12],
            "analysis_duration": r[13],
            "time_signature": r[14],
            "valence": r[15],
            "mood": r[16],
            "loudness": r[17],
            "dynamic_range": r[18],
            "silence_ratio": r[19],
            "key_details": json.loads(r[20]) if r[20] else None,
            "user_verified": bool(r[21]),
            "manual_bpm": r[22],
            "manual_key": r[23],
            "bpm_notes": r[24],
            "dynamic_complexity": r[25],
            "tonal_strength": r[26],
            "spectral_complexity": r[27],
            "zero_crossing_rate": r[28],
            "spectral_flux": r[29],
            "percussive_energy_ratio": r[30],
            "harmonic_energy_ratio": r[31],
        }
        for r in results
    ]
    return jsonify(songs)


def list_cache():
    limit = request.args.get("limit", 100, type=int)
    offset = request.args.get("offset", 0, type=int)
    namespace = _requested_namespace(default="default")
    with get_db_connection() as conn:
        cursor = conn.cursor()
        sql = """
         SELECT id, title, artist, preview_url, bpm, bpm_confidence, key, key_confidence,
             energy, danceability, acousticness, spectral_centroid, analyzed_at,
             analysis_duration, time_signature, valence, mood, loudness,
             dynamic_range, silence_ratio, key_details,
             user_verified, manual_bpm, manual_key, bpm_notes,
                   dynamic_complexity, tonal_strength, spectral_complexity,
                   zero_crossing_rate, spectral_flux,
                   percussive_energy_ratio, harmonic_energy_ratio
            FROM analysis_cache
        """
        params: list = []
        if namespace is not None:
            sql += " WHERE cache_namespace = ?"
            params.append(namespace)
        sql += " ORDER BY analyzed_at DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])
        cursor.execute(sql, params)
        results = cursor.fetchall()
    songs = [
        {
            "id": r[0],
            "title": r[1],
            "artist": r[2],
            "preview_url": r[3],
            "bpm": r[4],
            "bpm_confidence": r[5],
            "key": r[6],
            "key_confidence": r[7],
            "energy": r[8],
            "danceability": r[9],
            "acousticness": r[10],
            "spectral_centroid": r[11],
            "analyzed_at": r[12],
            "analysis_duration": r[13],
            "time_signature": r[14],
            "valence": r[15],
            "mood": r[16],
            "loudness": r[17],
            "dynamic_range": r[18],
            "silence_ratio": r[19],
            "key_details": json.loads(r[20]) if r[20] else None,
            "user_verified": bool(r[21]),
            "manual_bpm": r[22],
            "manual_key": r[23],
            "bpm_notes": r[24],
            "dynamic_complexity": r[25],
            "tonal_strength": r[26],
            "spectral_complexity": r[27],
            "zero_crossing_rate": r[28],
            "spectral_flux": r[29],
            "percussive_energy_ratio": r[30],
            "harmonic_energy_ratio": r[31],
        }
        for r in results
    ]
    return jsonify(songs)


def delete_cache_entry(cache_id: int):
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("DELETE FROM analysis_cache WHERE id = ?", (cache_id,))
        deleted = cursor.rowcount
    if deleted == 0:
        return jsonify({"error": "not_found", "message": "Cache entry not found"}), 404
    return jsonify({"status": "deleted", "id": cache_id})


def clear_cache():
    namespace = _requested_namespace(default=None)
    with get_db_connection() as conn:
        cursor = conn.cursor()
        if namespace is None:
            cursor.execute("DELETE FROM analysis_cache")
        else:
            cursor.execute("DELETE FROM analysis_cache WHERE cache_namespace = ?", (namespace,))
    return jsonify({"status": "cleared", "namespace": namespace or "all"})


def export_cache():
    if _EXPORT_DIR is None:
        raise RuntimeError("Cache export directory not configured.")
    namespace = _requested_namespace(default="default")
    with get_db_connection() as conn:
        cursor = conn.cursor()
        sql = """
         SELECT title, artist, preview_url, bpm, bpm_confidence, key, key_confidence,
                   energy, danceability, acousticness, spectral_centroid, time_signature,
                   valence, mood, loudness, dynamic_range, silence_ratio,
             analysis_duration, analyzed_at, key_details, chunk_analysis, analysis_timing,
                   dynamic_complexity, tonal_strength, spectral_complexity,
                   zero_crossing_rate, spectral_flux,
                   percussive_energy_ratio, harmonic_energy_ratio
            FROM analysis_cache
        """
        params: list = []
        if namespace is not None:
            sql += " WHERE cache_namespace = ?"
            params.append(namespace)
        sql += " ORDER BY analyzed_at DESC"
        cursor.execute(sql, params)
        rows = cursor.fetchall()
    output = StringIO()
    writer = csv.writer(output)
    header = [
        "Title",
        "Artist",
        "Preview URL",
        "BPM",
        "BPM Confidence (%)",
        "Key",
        "Key Confidence (%)",
        "Energy (%)",
        "Danceability (%)",
        "Acousticness (%)",
        "Brightness (Hz)",
        "Time Signature",
        "Valence (%)",
        "Mood",
        "Loudness (dB)",
        "Dynamic Range (dB)",
    "Silence Ratio (%)",
        "Analysis Duration (s)",
        "Analyzed At",
    "Key Details JSON",
        "Dynamic Complexity",
        "Tonal Strength",
        "Spectral Complexity",
        "Zero Crossing Rate",
        "Spectral Flux",
        "Percussive Energy Ratio",
        "Harmonic Energy Ratio",
    ]
    header.extend([label for _, label in ANALYSIS_TIMER_EXPORT_FIELDS])
    header.extend([label for _, label in CHUNK_TIMING_EXPORT_FIELDS])
    header.extend(["Chunk Window (s)", "Chunk Hop (s)", "Chunk BPM Weighted STD"])
    writer.writerow(header)
    for row in rows:
        chunk_meta = {}
        if row["chunk_analysis"]:
            try:
                chunk_data = json.loads(row["chunk_analysis"])
                chunk_meta["chunks_evaluated"] = chunk_data.get("chunks_evaluated") or len(chunk_data.get("windows") or [])
                diagnostics = chunk_data.get("diagnostics") or {}
                chunk_meta["wall_time_seconds"] = chunk_data.get("wall_time_seconds") or chunk_data.get("wall_time")
                chunk_meta["analysis_time_seconds"] = chunk_data.get("analysis_time_seconds") or chunk_data.get("analysis_time_sum")
                chunk_meta["analysis_overhead_seconds"] = chunk_data.get("analysis_overhead_seconds") or chunk_data.get("analysis_overhead")
                chunk_meta["analysis_time_avg_seconds"] = chunk_data.get("analysis_time_avg_seconds") or chunk_data.get("analysis_time_avg")
                chunk_window = chunk_data.get("effective_window_seconds") or chunk_data.get("window_seconds")
                chunk_hop = chunk_data.get("hop_seconds") or chunk_data.get("effective_hop_seconds")
                chunk_bpm_weighted_std = (diagnostics or {}).get("bpm_weighted_std")
            except json.JSONDecodeError:
                chunk_window = chunk_hop = chunk_bpm_weighted_std = None
        else:
            chunk_window = chunk_hop = chunk_bpm_weighted_std = None
        timing_payload = {}
        if row["analysis_timing"]:
            try:
                timing_payload = json.loads(row["analysis_timing"])
            except json.JSONDecodeError:
                timing_payload = {}

        def fmt_pct(value, decimals=1):
            return "" if value is None else round(value, decimals)

        def fmt_float(value, decimals=2):
            val = safe_float(value)
            return "" if val is None else round(val, decimals)

        timer_values = [fmt_float(timing_payload.get(key), 3) for key, _ in ANALYSIS_TIMER_EXPORT_FIELDS]
        chunk_meta_values = []
        for field, _ in CHUNK_TIMING_EXPORT_FIELDS:
            value = chunk_meta.get(field)
            chunk_meta_values.append("" if value is None else (round(value, 3) if isinstance(value, (int, float)) else value))

        writer.writerow(
            [
                row["title"],
                row["artist"],
                row["preview_url"],
                fmt_float(row["bpm"], 3),
                fmt_pct(percentage(row["bpm_confidence"])),
                row["key"],
                fmt_pct(percentage(row["key_confidence"])),
                fmt_pct(percentage(row["energy"])),
                fmt_pct(percentage(row["danceability"], -1.0, 1.0)),
                fmt_pct(percentage(row["acousticness"])),
                fmt_float(row["spectral_centroid"], 1),
                row["time_signature"] or "",
                fmt_pct(percentage(row["valence"])),
                row["mood"] or "",
                fmt_float(row["loudness"], 2),
                fmt_float(row["dynamic_range"], 2),
                fmt_pct(percentage(row["silence_ratio"]), decimals=2),
                fmt_float(row["analysis_duration"], 2),
                row["analyzed_at"],
                row["key_details"] or "",
                fmt_float(row["dynamic_complexity"], 3),
                fmt_float(row["tonal_strength"], 3),
                fmt_float(row["spectral_complexity"], 3),
                fmt_float(row["zero_crossing_rate"], 4),
                fmt_float(row["spectral_flux"], 4),
                fmt_pct(percentage(row["percussive_energy_ratio"])),
                fmt_pct(percentage(row["harmonic_energy_ratio"])),
                *timer_values,
                *chunk_meta_values,
                fmt_float(chunk_window, 2) if chunk_window is not None else "",
                fmt_float(chunk_hop, 2) if chunk_hop is not None else "",
                fmt_float(chunk_bpm_weighted_std, 3) if chunk_bpm_weighted_std is not None else "",
            ]
        )

    csv_data = output.getvalue()
    output.close()
    filename = f"cache_export_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    file_path = (_EXPORT_DIR or Path.cwd()) / filename
    with open(file_path, "w", encoding="utf-8") as handle:
        handle.write(csv_data)
    return send_file(str(file_path), mimetype="text/csv", as_attachment=True, download_name=filename)


__all__ = [
    "cache_search",
    "list_cache",
    "delete_cache_entry",
    "clear_cache",
    "export_cache",
    "configure_cache_routes",
]
