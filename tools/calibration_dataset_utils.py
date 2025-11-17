"""
CLI utility for building the paired calibration dataset described in docs/audio-calibration-plan.md.

It joins analyzer cache exports with Spotify reference metrics, normalizes the song+artist keys,
and writes the merged rows to a Parquet artifact under data/calibration/.
"""
from __future__ import annotations

import argparse
import datetime as dt
import logging
import math
import subprocess
import warnings
from pathlib import Path
from typing import Iterable, List, Optional, Set, Tuple

import pandas as pd
from tools.calibration_normalization import build_match_key, normalize_text

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SPOTIFY_PATH = REPO_ROOT / "csv" / "spotify metrics.csv"
DEFAULT_OUTPUT_DIR = REPO_ROOT / "data" / "calibration"
DEFAULT_HUMAN_REPORT_DIR = REPO_ROOT / "reports" / "calibration_reviews"

logger = logging.getLogger("calibration_builder")

def _configure_logging(verbose: bool) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(level=level, format="%(message)s")


def _detect_git_sha() -> str:
    try:
        sha = (
            subprocess.check_output(
                ["git", "rev-parse", "HEAD"],
                cwd=REPO_ROOT,
                text=True,
                stderr=subprocess.DEVNULL,
            )
            .strip()
        )
        return sha
    except Exception:
        return "UNKNOWN"


def _coerce_numeric(df: pd.DataFrame, columns: Iterable[str]) -> pd.DataFrame:
    for column in columns:
        if column in df.columns:
            df[column] = pd.to_numeric(df[column], errors="coerce")
    return df


def _parse_timecode_to_seconds(value: str) -> Optional[float]:
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return None
    text = str(value).strip()
    if not text:
        return None
    parts = text.split(":")
    try:
        if len(parts) == 2:
            minutes, seconds = parts
            return int(minutes) * 60 + float(seconds)
        if len(parts) == 3:
            hours, minutes, seconds = parts
            return int(hours) * 3600 + int(minutes) * 60 + float(seconds)
    except ValueError:
        return None
    return None


def _resolve_analyzer_paths(paths: List[str]) -> List[Path]:
    resolved: List[Path] = []
    for item in paths:
        base = Path(item)
        if base.is_dir():
            resolved.extend(sorted(base.rglob("*.csv")))
        else:
            matches = list(base.parent.glob(base.name))
            if matches:
                resolved.extend(matches)
            else:
                resolved.append(base)
    if not resolved:
        raise FileNotFoundError("No analyzer export CSV files found for provided paths.")
    return resolved


def _load_analyzer_exports(paths: List[Path]) -> Tuple[pd.DataFrame, Set[str]]:
    frames = []
    column_map = {
        "Title": "title",
        "Artist": "artist",
        "Preview URL": "preview_url",
        "BPM": "analyzer_bpm",
        "BPM Confidence (%)": "analyzer_bpm_confidence",
        "Key": "analyzer_key",
        "Key Confidence (%)": "analyzer_key_confidence",
        "Energy (%)": "analyzer_energy",
        "Danceability (%)": "analyzer_danceability",
        "Acousticness (%)": "analyzer_acousticness",
        "Brightness (Hz)": "analyzer_brightness_hz",
        "Time Signature": "analyzer_time_signature",
        "Valence (%)": "analyzer_valence",
        "Mood": "analyzer_mood",
        "Loudness (dB)": "analyzer_loudness_db",
        "Dynamic Range (dB)": "analyzer_dynamic_range_db",
        "Silence Ratio (%)": "analyzer_silence_ratio",
        "Analysis Duration (s)": "analysis_duration_seconds",
        "Analyzed At": "analyzed_at",
        "Key Details JSON": "analyzer_key_details",
    }

    for path in paths:
        df = pd.read_csv(path)
        df["analyzer_source_file"] = str(path)
        frames.append(df)

    analyzer_df = pd.concat(frames, ignore_index=True)
    analyzer_df = analyzer_df.rename(columns=column_map)
    analyzer_df["analyzed_at"] = pd.to_datetime(analyzer_df.get("analyzed_at"), errors="coerce")
    analyzer_df = _coerce_numeric(
        analyzer_df,
        [
            "analyzer_bpm",
            "analyzer_bpm_confidence",
            "analyzer_energy",
            "analyzer_danceability",
            "analyzer_acousticness",
            "analyzer_valence",
            "analyzer_loudness_db",
            "analyzer_dynamic_range_db",
            "analyzer_silence_ratio",
            "analysis_duration_seconds",
            "analyzer_brightness_hz",
        ],
    )
    analyzer_df["match_key"] = [
        build_match_key(row.title, row.artist)
        for row in analyzer_df[["title", "artist"]].itertuples(index=False, name="row")
    ]
    analyzer_df = analyzer_df[analyzer_df["match_key"] != "::"]
    analyzer_df = analyzer_df.sort_values("analyzed_at", ascending=False)
    analyzer_df = analyzer_df.drop_duplicates(subset=["match_key"], keep="first")
    normalized_artists = {normalize_text(artist) for artist in analyzer_df["artist"]}
    return analyzer_df.reset_index(drop=True), normalized_artists


def _load_spotify_metrics(path: Path) -> pd.DataFrame:
    column_map = {
        "Song": "spotify_song",
        "Artist": "spotify_artist",
        "Popularity": "spotify_popularity",
        "BPM": "spotify_bpm",
        "Genres": "spotify_genres",
        "Parent Genres": "spotify_parent_genres",
        "Album": "spotify_album",
        "Album Date": "spotify_album_date",
        "Time": "spotify_duration",
        "Dance": "spotify_dance",
        "Energy": "spotify_energy",
        "Acoustic": "spotify_acoustic",
        "Instrumental": "spotify_instrumental",
        "Happy": "spotify_happy",
        "Speech": "spotify_speech",
        "Live": "spotify_live",
        "Loud (Db)": "spotify_loudness_db",
        "Key": "spotify_key",
        "Time Signature": "spotify_time_signature",
        "Added At": "spotify_added_at",
        "Spotify Track Id": "spotify_track_id",
        "Album Label": "spotify_album_label",
        "Camelot": "spotify_camelot",
        "ISRC": "spotify_isrc",
    }

    df = pd.read_csv(path)
    df = df.rename(columns=column_map)
    df["spotify_source_file"] = str(path)
    df["spotify_added_at"] = pd.to_datetime(df.get("spotify_added_at"), errors="coerce")
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", UserWarning)
        df["spotify_album_date"] = pd.to_datetime(
            df.get("spotify_album_date"),
            errors="coerce",
        )
    df["spotify_duration_seconds"] = df["spotify_duration"].map(_parse_timecode_to_seconds)
    df = _coerce_numeric(
        df,
        [
            "spotify_popularity",
            "spotify_bpm",
            "spotify_dance",
            "spotify_energy",
            "spotify_acoustic",
            "spotify_instrumental",
            "spotify_happy",
            "spotify_speech",
            "spotify_live",
            "spotify_loudness_db",
        ],
    )
    df["normalized_title"] = df["spotify_song"].map(normalize_text)
    df["normalized_artist"] = df["spotify_artist"].map(normalize_text)
    df["match_key"] = df["normalized_title"] + "::" + df["normalized_artist"]
    df = df[df["match_key"] != "::"]
    df = df.sort_values("spotify_popularity", ascending=False)
    df = df.drop_duplicates(subset=["match_key"], keep="first")
    df = df.drop(columns=["normalized_title", "normalized_artist"])
    return df.reset_index(drop=True)


def _load_all_spotify_metrics(
    paths: List[Path],
    preferred_artists: Optional[Set[str]] = None,
) -> pd.DataFrame:
    frames = []
    for path in paths:
        if not path.exists():
            raise FileNotFoundError(f"Spotify metrics file not found: {path}")
        frames.append(_load_spotify_metrics(path))
    combined = pd.concat(frames, ignore_index=True)
    combined["_normalized_artist"] = combined["spotify_artist"].map(normalize_text)
    preferred_artists = preferred_artists or set()
    preferred_token_sets = [set(artist.split()) for artist in preferred_artists if artist]

    def _overlap_score(text: str) -> float:
        if not text:
            return 0.0
        if text in preferred_artists:
            return 2.0  # Explicit match: always wins ties regardless of popularity.
        tokens = set(text.split())
        if not tokens or not preferred_token_sets:
            return 0.0
        best = 0.0
        for sample in preferred_token_sets:
            if not sample:
                continue
            overlap = len(tokens & sample) / max(len(sample), 1)
            if overlap > best:
                best = overlap
        return best

    combined["_artist_overlap_score"] = combined["_normalized_artist"].map(_overlap_score)
    combined = combined.sort_values(
        ["_artist_overlap_score", "spotify_popularity"],
        ascending=[False, False],
    )
    combined = combined.drop_duplicates(subset=["match_key"], keep="first")
    combined = combined.drop(columns=["_normalized_artist", "_artist_overlap_score"])
    return combined.reset_index(drop=True)


def _default_output_path(output: Optional[Path], output_dir: Path) -> Path:
    if output:
        return output
    timestamp = dt.datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    return output_dir / f"calibration_{timestamp}.parquet"


def _default_human_report_path(dataset_path: Path) -> Path:
    base_name = f"{dataset_path.stem}_server_vs_spotify.csv"
    return DEFAULT_HUMAN_REPORT_DIR / base_name


def _export_human_report(merged: pd.DataFrame, dataset_path: Path, destination: Optional[Path] = None) -> Path:
    """Write a concise CSV showing analyzer vs Spotify BPM/key for quick reviews."""
    report_path = destination or _default_human_report_path(dataset_path)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_df = pd.DataFrame(
        {
            "Song": merged["title"],
            "Artist": merged["artist"],
            "Server BPM": pd.to_numeric(merged["analyzer_bpm"], errors="coerce").round(2),
            "Spotify BPM": pd.to_numeric(merged["spotify_bpm"], errors="coerce").round(2),
            "Server Key": merged["analyzer_key"],
            "Spotify Key": merged["spotify_key"],
        }
    )
    report_df.to_csv(report_path, index=False)
    return report_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build paired calibration dataset.")
    parser.add_argument(
        "--analyzer-export",
        dest="analyzer_exports",
        action="append",
        required=True,
        help="Path(s) to analyzer cache export CSV files. "
        "Can be provided multiple times or point to a directory.",
    )
    parser.add_argument(
        "--spotify-metrics",
        dest="spotify_metrics",
        action="append",
        type=Path,
        help="Path(s) to Spotify metrics CSV files. When omitted, defaults to csv/spotify metrics.csv.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Exact output parquet path. Overrides --output-dir.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"Directory for parquet outputs (default: {DEFAULT_OUTPUT_DIR})",
    )
    parser.add_argument(
        "--feature-set-version",
        default="v1",
        help="Feature set version label to stamp into metadata (default: v1).",
    )
    parser.add_argument(
        "--analyzer-build-sha",
        help="Override analyzer git SHA. Defaults to current repo HEAD.",
    )
    parser.add_argument(
        "--spotify-snapshot-date",
        help="Override Spotify snapshot date stored in metadata (ISO-8601).",
    )
    parser.add_argument(
        "--notes",
        default="",
        help="Optional notes stored alongside every row.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Load and merge the data but skip writing the parquet artifact.",
    )
    parser.add_argument(
        "--allow-missing",
        action="store_true",
        help="Continue even if some Spotify rows are missing from the analyzer exports.",
    )
    parser.add_argument(
        "--restrict-spotify-to-analyzer",
        action="store_true",
        help="Filter Spotify rows down to analyzer matches so partial sweeps work without --allow-missing.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose logging.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    _configure_logging(args.verbose)

    analyzer_paths = _resolve_analyzer_paths(args.analyzer_exports)
    logger.info(f"📦 Loading {len(analyzer_paths)} analyzer export file(s).")
    analyzer_df, analyzer_artists = _load_analyzer_exports(analyzer_paths)
    logger.info(f"   → {len(analyzer_df):,} unique analyzer rows after normalization.")

    spotify_paths = args.spotify_metrics or [DEFAULT_SPOTIFY_PATH]
    spotify_paths = [path.expanduser() for path in spotify_paths]
    spotify_df = _load_all_spotify_metrics(spotify_paths, preferred_artists=analyzer_artists)
    logger.info(
        f"🎧 Loaded {len(spotify_df):,} Spotify reference rows from {len(spotify_paths)} file(s)."
    )
    if args.restrict_spotify_to_analyzer:
        analyzer_keys = set(analyzer_df["match_key"])
        before = len(spotify_df)
        spotify_df = spotify_df[spotify_df["match_key"].isin(analyzer_keys)].copy()
        logger.info(
            "🔍 Filtered Spotify rows to analyzer matches (%d → %d).",
            before,
            len(spotify_df),
        )
        if spotify_df.empty:
            raise RuntimeError(
                "No overlapping Spotify rows found for analyzer export. "
                "Verify csv/spotify_calibration_master.csv contains these songs."
            )

    merged = analyzer_df.merge(
        spotify_df,
        on="match_key",
        how="inner",
        suffixes=("", ""),
    )
    if merged.empty:
        raise RuntimeError("No matching rows found between analyzer exports and Spotify metrics.")
    matched_keys = set(merged["match_key"])
    missing_spotify = sorted(set(spotify_df["match_key"]) - matched_keys)
    if missing_spotify:
        snippet = ", ".join(missing_spotify[:5])
        message = (
            f"{len(missing_spotify)} Spotify reference row(s) were absent from the analyzer exports."
        )
        if args.allow_missing:
            logger.warning("⚠️ %s Missing examples: %s", message, snippet)
        else:
            raise RuntimeError(f"{message} Missing examples: {snippet}")

    missing_rows = analyzer_df[~analyzer_df["match_key"].isin(matched_keys)]
    if not missing_rows.empty:
        samples = [
            f"{row.title} — {row.artist}"
            for row in missing_rows[["title", "artist"]].itertuples(index=False, name="row")
        ]
        sample_preview = ", ".join(samples[:5])
        raise RuntimeError(
            f"{len(missing_rows)} analyzer rows had no Spotify match after normalization. "
            f"Examples: {sample_preview}"
        )

    analyzer_build_sha = (
        args.analyzer_build_sha if args.analyzer_build_sha else _detect_git_sha()
    )

    if args.spotify_snapshot_date:
        snapshot_date = args.spotify_snapshot_date
    else:
        added_at = spotify_df["spotify_added_at"].dropna()
        snapshot_date = (
            added_at.max().date().isoformat() if not added_at.empty else None
        )

    merged["analyzer_build_sha"] = analyzer_build_sha
    merged["feature_set_version"] = args.feature_set_version
    merged["spotify_snapshot_date"] = snapshot_date
    merged["notes"] = args.notes
    merged["dataset_created_at"] = dt.datetime.utcnow().isoformat()

    unmatched_analyzer = len(analyzer_df) - len(merged)
    match_ratio = len(merged) / len(analyzer_df) if len(analyzer_df) else 0
    logger.info(
        f"✅ Matched {len(merged):,} rows ({match_ratio:.1%}) "
        f"— {unmatched_analyzer:,} analyzer rows had no Spotify match."
    )

    if args.dry_run:
        logger.info("Dry run enabled; skipping Parquet write.")
        return

    output_path = _default_output_path(args.output, args.output_dir)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    merged.to_parquet(output_path, index=False)
    logger.info(f"💾 Wrote {output_path} ({output_path.stat().st_size / 1024:.1f} KiB)")
    report_path = _export_human_report(merged, output_path)
    logger.info(f"📝 Wrote human review CSV ({len(merged)} row(s)): {report_path}")
