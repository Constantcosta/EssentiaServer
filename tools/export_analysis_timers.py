#!/usr/bin/env python3
"""Export per-stage analysis timers and chunk timings for offline profiling."""

from __future__ import annotations

import argparse
import csv
import json
import sqlite3
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Dict, List

from backend.analysis.reporting import (
    ANALYSIS_TIMER_EXPORT_FIELDS,
    CHUNK_TIMING_EXPORT_FIELDS,
    DB_PATH as DEFAULT_DB_PATH,
    EXPORT_DIR,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--db",
        type=Path,
        default=Path(DEFAULT_DB_PATH),
        help="Path to audio_analysis_cache.db (default: %(default)s)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=EXPORT_DIR / f"analysis_timers_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv",
        help="Destination CSV path (default: exports/analysis_timers_<timestamp>.csv)",
    )
    parser.add_argument(
        "--since",
        type=str,
        default=None,
        help="Filter analyses newer than this ISO date (YYYY-MM-DD or full timestamp).",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Maximum number of rows to export (most recent first).",
    )
    return parser.parse_args()


def _connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def _fmt_float(value, decimals: int = 3) -> str:
    if value is None:
        return ""
    try:
        numeric = float(value)
    except (TypeError, ValueError):
        return ""
    return f"{numeric:.{decimals}f}"


def _fmt_int(value) -> str:
    if value is None:
        return ""
    try:
        return str(int(value))
    except (TypeError, ValueError):
        return ""


def export_timers(args: argparse.Namespace) -> Path:
    if not args.db.exists():
        raise FileNotFoundError(f"Database not found: {args.db}")
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    conn = _connect(args.db)
    query = """
        SELECT title, artist, analyzed_at, analysis_duration,
               analysis_timing, chunk_analysis
        FROM analysis_cache
        WHERE analysis_timing IS NOT NULL
    """
    params: List[object] = []
    conditions: List[str] = []
    if args.since:
        conditions.append("analyzed_at >= ?")
        params.append(args.since)
    if conditions:
        query += " AND " + " AND ".join(conditions)
    query += " ORDER BY analyzed_at DESC"
    if args.limit:
        query += " LIMIT ?"
        params.append(args.limit)

    rows = conn.execute(query, params).fetchall()
    conn.close()

    header = [
        "Title",
        "Artist",
        "Analyzed At",
        "Analysis Duration (s)",
    ]
    header.extend(label for _, label in ANALYSIS_TIMER_EXPORT_FIELDS)
    header.extend(label for _, label in CHUNK_TIMING_EXPORT_FIELDS)
    header.extend(
        [
            "Chunk Window (s)",
            "Chunk Hop (s)",
            "Chunk BPM Weighted Std",
        ]
    )

    stage_totals: Dict[str, List[float]] = defaultdict(list)
    chunk_totals: Dict[str, List[float]] = defaultdict(list)

    with args.output.open("w", encoding="utf-8", newline="") as csv_file:
        writer = csv.writer(csv_file)
        writer.writerow(header)
        for row in rows:
            try:
                timing_payload = json.loads(row["analysis_timing"]) if row["analysis_timing"] else {}
            except json.JSONDecodeError:
                timing_payload = {}
            stage_values = []
            for timer_key, _ in ANALYSIS_TIMER_EXPORT_FIELDS:
                value = timing_payload.get(timer_key)
                if isinstance(value, (int, float)):
                    stage_totals[timer_key].append(float(value))
                stage_values.append(_fmt_float(value))

            chunk_payload = {}
            if row["chunk_analysis"]:
                try:
                    chunk_payload = json.loads(row["chunk_analysis"]) or {}
                except json.JSONDecodeError:
                    chunk_payload = {}
            chunk_meta = {
                "wall_time_seconds": chunk_payload.get("wall_time_seconds") or chunk_payload.get("wall_time"),
                "analysis_time_seconds": chunk_payload.get("analysis_time_seconds") or chunk_payload.get("analysis_time_sum"),
                "analysis_overhead_seconds": chunk_payload.get("analysis_overhead_seconds") or chunk_payload.get("analysis_overhead"),
                "analysis_time_avg_seconds": chunk_payload.get("analysis_time_avg_seconds") or chunk_payload.get("analysis_time_avg"),
                "chunks_evaluated": chunk_payload.get("chunks_evaluated") or len(chunk_payload.get("windows") or []),
            }
            chunk_values = []
            for field_key, _ in CHUNK_TIMING_EXPORT_FIELDS:
                value = chunk_meta.get(field_key)
                if isinstance(value, (int, float)):
                    chunk_totals[field_key].append(float(value))
                chunk_values.append(_fmt_float(value) if field_key != "chunks_evaluated" else _fmt_int(value))

            chunk_window = chunk_payload.get("window_seconds") or chunk_payload.get("effective_window_seconds")
            chunk_hop = chunk_payload.get("hop_seconds") or chunk_payload.get("effective_hop_seconds")
            diagnostics = chunk_payload.get("diagnostics") or {}
            chunk_bpm_std = diagnostics.get("bpm_weighted_std")

            writer.writerow(
                [
                    row["title"],
                    row["artist"],
                    row["analyzed_at"],
                    _fmt_float(row["analysis_duration"]),
                    *stage_values,
                    *chunk_values,
                    _fmt_float(chunk_window),
                    _fmt_float(chunk_hop),
                    _fmt_float(chunk_bpm_std, 4),
                ]
            )

    print(f"Exported {len(rows)} analyses to {args.output}")
    if rows:
        print("Average stage timings (seconds):")
        for key, _ in ANALYSIS_TIMER_EXPORT_FIELDS:
            values = stage_totals.get(key) or []
            avg = sum(values) / len(values) if values else 0.0
            print(f"  - {key}: {avg:.3f}s over {len(values)} tracks")
        print("Average chunk timings:")
        for key, _ in CHUNK_TIMING_EXPORT_FIELDS:
            values = chunk_totals.get(key) or []
            avg = sum(values) / len(values) if values else 0.0
            unit = "count" if key == "chunks_evaluated" else "s"
            print(f"  - {key}: {avg:.3f}{unit} over {len(values)} tracks")
    return args.output


def main() -> None:
    args = parse_args()
    export_timers(args)


if __name__ == "__main__":
    main()
