#!/usr/bin/env python3
"""
Shared helpers for calibration dataset lineage + health checks.

The instrumentation here is used by the calibration tooling as well as CI so we
keep it centralized to avoid skew between scripts.
"""
from __future__ import annotations

import datetime as dt
import hashlib
from functools import lru_cache
from pathlib import Path
from typing import Dict, Iterable, List, Optional

import pandas as pd

ANALYZER_VALUE_COLUMNS: List[str] = [
    "analyzer_bpm",
    "analyzer_energy",
    "analyzer_danceability",
    "analyzer_acousticness",
    "analyzer_valence",
    "analyzer_loudness_db",
]
SPOTIFY_VALUE_COLUMNS: List[str] = [
    "spotify_bpm",
    "spotify_dance",
    "spotify_energy",
    "spotify_acoustic",
    "spotify_happy",
    "spotify_loudness_db",
]
REQUIRED_KEY_COLUMNS: List[str] = [
    "match_key",
    "title",
    "artist",
    "spotify_song",
    "spotify_artist",
]
DEFAULT_MIN_ROWS = 24
DEFAULT_MAX_NULL_RATIO = 0.35


class DatasetHealthError(RuntimeError):
    """Raised when the calibration dataset fails basic sanity checks."""


def _utc_iso(timestamp: float) -> str:
    return dt.datetime.utcfromtimestamp(timestamp).replace(tzinfo=dt.timezone.utc).isoformat()


@lru_cache()
def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def describe_file(path: Path) -> Dict[str, object]:
    """Return filesystem metadata plus SHA256 for a file path."""
    info: Dict[str, object] = {"path": str(path)}
    if not path.exists():
        info["exists"] = False
        return info
    stat = path.stat()
    info.update(
        {
            "exists": True,
            "size_bytes": stat.st_size,
            "modified_at": _utc_iso(stat.st_mtime),
            "sha256": _sha256(path),
        }
    )
    return info


def describe_dataset_artifact(path: Path, frame: pd.DataFrame) -> Dict[str, object]:
    """Capture lineage metadata for a parquet artifact."""
    info = describe_file(path)
    info["rows"] = int(len(frame))
    info["columns"] = sorted(frame.columns.tolist())
    return info


def collect_source_metadata(df: pd.DataFrame, column_name: str, *, legacy_alias: Optional[str] = None) -> List[Dict[str, object]]:
    """Aggregate per-source row counts and filesystem fingerprints."""
    if column_name not in df.columns and legacy_alias and legacy_alias in df.columns:
        column_name = legacy_alias
    if column_name not in df.columns:
        return []
    series = df[column_name].dropna().astype(str)
    if series.empty:
        return []
    counts = series.value_counts()
    metadata: List[Dict[str, object]] = []
    for path_str, rows in counts.sort_index().items():
        path = Path(path_str).expanduser()
        entry = describe_file(path)
        entry["rows"] = int(rows)
        metadata.append(entry)
    return metadata


def ensure_dataset_health(
    df: pd.DataFrame,
    *,
    min_rows: int = DEFAULT_MIN_ROWS,
    max_null_ratio: float = DEFAULT_MAX_NULL_RATIO,
) -> None:
    """Raise DatasetHealthError if the dataframe looks incomplete or malformed."""
    issues: List[str] = []
    row_count = len(df)
    if row_count < min_rows:
        issues.append(f"dataset only has {row_count} rows (< {min_rows})")

    required_columns = set(REQUIRED_KEY_COLUMNS + ANALYZER_VALUE_COLUMNS + SPOTIFY_VALUE_COLUMNS)
    missing_columns = [col for col in sorted(required_columns) if col not in df.columns]
    if missing_columns:
        issues.append(f"missing columns: {', '.join(missing_columns)}")

    if row_count > 0:
        numeric_columns = [col for col in ANALYZER_VALUE_COLUMNS + SPOTIFY_VALUE_COLUMNS if col in df.columns]
        for column in numeric_columns:
            series = pd.to_numeric(df[column], errors="coerce")
            valid = series.notna().sum()
            null_ratio = 1.0 - (valid / row_count)
            if valid == 0:
                issues.append(f"{column} contains no numeric samples")
            elif null_ratio > max_null_ratio:
                issues.append(f"{column} has {null_ratio:.0%} null values (> {max_null_ratio:.0%})")

    if "match_key" in df.columns:
        unique_matches = df["match_key"].nunique(dropna=True)
        duplicate_rows = row_count - unique_matches
        if duplicate_rows > 0:
            issues.append(f"{duplicate_rows} duplicate match_key rows detected")

    if issues:
        bullet_list = "; ".join(issues)
        raise DatasetHealthError(f"Calibration dataset health check failed: {bullet_list}")


__all__ = [
    "ANALYZER_VALUE_COLUMNS",
    "SPOTIFY_VALUE_COLUMNS",
    "collect_source_metadata",
    "describe_dataset_artifact",
    "describe_file",
    "ensure_dataset_health",
    "DatasetHealthError",
]
