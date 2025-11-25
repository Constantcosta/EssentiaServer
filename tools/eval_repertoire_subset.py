#!/usr/bin/env python3
"""Evaluate the curated repertoire subset against the latest analysis export."""

from __future__ import annotations

import argparse
import math
import re
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
import sys
from typing import Dict, List, Optional

import pandas as pd

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from key_utils import keys_match_fuzzy, normalize_key_label  # type: ignore


REPO_ROOT = SCRIPT_DIR.parents[0]
DEFAULT_SUBSET_CSV = REPO_ROOT / "csv" / "repertoire_subset_google.csv"
DEFAULT_RESULTS_DIR = REPO_ROOT / "csv"


def _safe_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, float):
        if math.isnan(value):
            return ""
        return str(value)
    if pd.isna(value):  # type: ignore[attr-defined]
        return ""
    return str(value).strip()


def _safe_float(value: object) -> Optional[float]:
    if isinstance(value, (float, int)):
        if isinstance(value, float) and math.isnan(value):
            return None
        return float(value)
    text = _safe_text(value)
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def _canonical_key(artist: str, song: str) -> str:
    combo = f"{artist}::{song}".lower()
    return re.sub(r"[^a-z0-9]", "", combo)


@dataclass
class TrackRow:
    csv_index: Optional[int]
    song: str
    artist: str
    spotify_bpm: Optional[float]
    spotify_key: Optional[str]
    google_bpm: Optional[float]
    google_key: Optional[str]
    key_quality: Optional[str]
    match_key: str


@dataclass
class ResultRow:
    song_title: str
    artist: str
    bpm: Optional[float]
    key: Optional[str]
    test_type: str
    match_key: str
    ordinal: Optional[int]


@dataclass
class BpmComparison:
    expected: Optional[float]
    actual: Optional[float]
    verdict: str
    abs_diff: Optional[float]
    detail: str


@dataclass
class KeyComparison:
    expected: Optional[str]
    actual: Optional[str]
    verdict: str
    detail: str


@dataclass
class TrackComparison:
    track: TrackRow
    result: Optional[ResultRow]
    bpm: BpmComparison
    key_spotify: KeyComparison
    key_google: KeyComparison


def load_subset_tracks(csv_path: Path) -> Dict[str, TrackRow]:
    df = pd.read_csv(csv_path)
    tracks: Dict[str, TrackRow] = {}
    for _, row in df.iterrows():
        csv_index = row.get("#")
        idx: Optional[int] = None
        if csv_index is not None and not pd.isna(csv_index):  # type: ignore[arg-type]
            try:
                idx = int(csv_index)
            except (TypeError, ValueError):
                idx = None

        song = _safe_text(row.get("Song"))
        artist = _safe_text(row.get("Artist"))
        spotify_bpm = _safe_float(row.get("BPM"))
        spotify_key = _safe_text(row.get("Key")) or None
        google_bpm = _safe_float(row.get("Google BPM"))
        google_key = _safe_text(row.get("Google Key")) or None
        key_quality = _safe_text(row.get("Key Quality")) or None

        if not song or not artist:
            continue

        match_key = _canonical_key(artist, song)
        if not match_key:
            continue

        if match_key in tracks:
            raise ValueError(
                f"Duplicate track entry detected for artist={artist!r}, song={song!r}"
            )

        tracks[match_key] = TrackRow(
            csv_index=idx,
            song=song,
            artist=artist,
            spotify_bpm=spotify_bpm,
            spotify_key=spotify_key,
            google_bpm=google_bpm,
            google_key=google_key,
            key_quality=key_quality,
            match_key=match_key,
        )

    return tracks


def load_results(rows_csv: Path, test_type: Optional[str]) -> tuple[Dict[str, ResultRow], Dict[int, ResultRow]]:
    df = pd.read_csv(rows_csv)
    if "test_type" not in df.columns:
        raise ValueError(f"CSV {rows_csv} missing 'test_type' column")

    df["test_type"] = df["test_type"].fillna("").astype(str).str.strip()
    if test_type:
        df = df[df["test_type"] == test_type]
        if df.empty:
            raise ValueError(f"No rows with test_type={test_type!r} in {rows_csv}")

    results_by_key: Dict[str, ResultRow] = {}
    results_by_index: Dict[int, ResultRow] = {}
    duplicates: List[str] = []
    for ordinal, (_, row) in enumerate(df.iterrows(), start=1):
        song_title = _safe_text(row.get("song_title"))
        artist = _safe_text(row.get("artist"))
        if not song_title and not artist:
            continue
        match_key = _canonical_key(artist, song_title)
        if not match_key:
            continue

        bpm = _safe_float(row.get("bpm"))
        key = _safe_text(row.get("key")) or None
        record = ResultRow(
            song_title=song_title,
            artist=artist,
            bpm=bpm,
            key=key,
            test_type=_safe_text(row.get("test_type")),
            match_key=match_key,
            ordinal=ordinal,
        )

        if match_key in results_by_key:
            duplicates.append(f"{artist}::{song_title}")
            continue
        results_by_key[match_key] = record
        if ordinal not in results_by_index:
            results_by_index[ordinal] = record

    if duplicates:
        print(
            f"⚠️  Ignored {len(duplicates)} duplicate result rows: {', '.join(duplicates[:5])}"
        )
    return results_by_key, results_by_index


def find_latest_results(csv_dir: Path, test_type: str) -> Optional[Path]:
    candidates = sorted(
        csv_dir.glob("test_results_*.csv"), key=lambda p: p.stat().st_mtime, reverse=True
    )
    for candidate in candidates:
        try:
            df = pd.read_csv(candidate, usecols=["test_type"])
        except Exception:
            continue
        column = df["test_type"].fillna("").astype(str).str.strip()
        if (column == test_type).any():
            return candidate
    return None


def compare_bpm(expected: Optional[float], actual: Optional[float], tolerance: float) -> BpmComparison:
    if expected is None:
        return BpmComparison(expected, actual, "no-reference", None, "reference BPM missing")
    if actual is None:
        return BpmComparison(expected, actual, "missing-result", None, "analysis missing BPM")

    diff = abs(actual - expected)
    if diff <= tolerance:
        return BpmComparison(expected, actual, "exact", diff, f"within ±{tolerance} bpm")

    if abs(actual * 2 - expected) <= tolerance:
        return BpmComparison(expected, actual, "half", diff, "detected half-time tempo")
    if abs(actual / 2 - expected) <= tolerance:
        return BpmComparison(expected, actual, "double", diff, "detected double-time tempo")

    return BpmComparison(expected, actual, "off", diff, f"off by {diff:.2f} bpm")


def classify_key(expected: Optional[str], actual: Optional[str]) -> KeyComparison:
    if not expected:
        return KeyComparison(expected, actual, "no-reference", "reference key missing")
    if not actual:
        return KeyComparison(expected, actual, "missing-result", "analysis missing key")

    match, reason = keys_match_fuzzy(actual, expected)
    if match:
        label = "exact" if reason == "exact" else "enharmonic"
        return KeyComparison(expected, actual, "exact", label)

    expected_norm = normalize_key_label(expected)
    actual_norm = normalize_key_label(actual)
    if not expected_norm or not actual_norm:
        return KeyComparison(expected, actual, "wrong", "unparseable key label")

    exp_root, exp_mode = expected_norm
    act_root, act_mode = actual_norm

    if exp_root == act_root and exp_mode != act_mode:
        return KeyComparison(expected, actual, "acceptable", "same tonic, mode differs")

    interval = (act_root - exp_root) % 12
    if exp_mode != act_mode and interval in {3, 9}:
        return KeyComparison(expected, actual, "acceptable", "relative major/minor")
    if interval in {5, 7}:
        return KeyComparison(expected, actual, "acceptable", "fifth-related")

    return KeyComparison(expected, actual, "wrong", "different tonic/mode")


def evaluate_tracks(
    subset: Dict[str, TrackRow],
    results_by_key: Dict[str, ResultRow],
    results_by_index: Dict[int, ResultRow],
    bpm_tolerance: float,
) -> List[TrackComparison]:
    comparisons: List[TrackComparison] = []
    for track in subset.values():
        result = results_by_key.get(track.match_key)
        if result is None and track.csv_index is not None:
            result = results_by_index.get(track.csv_index)
        bpm_cmp = compare_bpm(track.spotify_bpm, result.bpm if result else None, bpm_tolerance)
        key_spotify = classify_key(track.spotify_key, result.key if result else None)
        key_google = classify_key(track.google_key, result.key if result else None)
        comparisons.append(
            TrackComparison(
                track=track,
                result=result,
                bpm=bpm_cmp,
                key_spotify=key_spotify,
                key_google=key_google,
            )
        )
    return comparisons


def _key_accuracy(rows: List[KeyComparison]) -> tuple[int, int, int]:
    considered = [r for r in rows if r.verdict != "no-reference"]
    total = len(considered)
    strict = sum(1 for r in considered if r.verdict == "exact")
    musical = sum(1 for r in considered if r.verdict in {"exact", "acceptable"})
    return total, strict, musical


def summarize(comparisons: List[TrackComparison], bpm_tolerance: float) -> None:
    bpm_rows = [c.bpm for c in comparisons if c.bpm.verdict != "no-reference"]
    bpm_counts = Counter(r.verdict for r in bpm_rows)
    bpm_diffs = [r.abs_diff for r in bpm_rows if r.abs_diff is not None]
    mae = sum(bpm_diffs) / len(bpm_diffs) if bpm_diffs else None

    spotify_keys = [c.key_spotify for c in comparisons]
    google_keys = [c.key_google for c in comparisons if c.track.google_key]
    sp_total, sp_strict, sp_musical = _key_accuracy(spotify_keys)
    g_total, g_strict, g_musical = _key_accuracy(google_keys)

    print("\n===== Repertoire Subset Evaluation =====")
    print(f"Tracks evaluated: {len(comparisons)}")
    if mae is not None:
        print(
            f"BPM MAE: {mae:.2f} bpm over {len(bpm_diffs)} tracks (tolerance ±{bpm_tolerance})"
        )
    else:
        print("BPM MAE: insufficient data (missing BPM results)")
    print(
        f"BPM alias counts -> exact: {bpm_counts.get('exact', 0)}, half: {bpm_counts.get('half', 0)}, "
        f"double: {bpm_counts.get('double', 0)}, off: {bpm_counts.get('off', 0)}, "
        f"missing: {bpm_counts.get('missing-result', 0)}"
    )

    if sp_total:
        print(
            f"Spotify key accuracy: strict {sp_strict}/{sp_total}"
            f" ({sp_strict / sp_total * 100:.1f}%), musical {sp_musical}/{sp_total}"
            f" ({sp_musical / sp_total * 100:.1f}%)"
        )
    else:
        print("Spotify key accuracy: no reference keys available")

    if g_total:
        print(
            f"Google key accuracy: strict {g_strict}/{g_total}"
            f" ({g_strict / g_total * 100:.1f}%), musical {g_musical}/{g_total}"
            f" ({g_musical / g_total * 100:.1f}%)"
        )
    else:
        print("Google key accuracy: no Google keys present")

    wrong_keys = [c for c in comparisons if c.key_google.verdict == "wrong"]
    wrong_bpm = [c for c in comparisons if c.bpm.verdict in {"half", "double", "off"}]

    if wrong_bpm:
        print("\nTop BPM issues:")
        for comp in sorted(wrong_bpm, key=lambda c: c.bpm.abs_diff or 0, reverse=True)[:8]:
            track = comp.track
            verdict = comp.bpm.verdict
            diff = comp.bpm.abs_diff or 0
            print(
                f"  • #{track.csv_index or '-'} {track.artist} - {track.song}: {verdict}"
                f" ({comp.bpm.detail}, diff {diff:.2f} bpm)"
            )

    if wrong_keys:
        print("\nKey issues vs Google reference:")
        for comp in wrong_keys[:10]:
            track = comp.track
            print(
                f"  • #{track.csv_index or '-'} {track.artist} - {track.song}:"
                f" expected {track.google_key}, detected {comp.result.key if comp.result else '—'}"
                f" ({comp.key_google.detail})"
            )


def export_per_song(comparisons: List[TrackComparison], target: Path) -> None:
    rows = []
    for comp in comparisons:
        result = comp.result
        rows.append(
            {
                "#": comp.track.csv_index,
                "Song": comp.track.song,
                "Artist": comp.track.artist,
                "Spotify BPM": comp.track.spotify_bpm,
                "Detected BPM": result.bpm if result else None,
                "BPM Verdict": comp.bpm.verdict,
                "BPM Detail": comp.bpm.detail,
                "Spotify Key": comp.track.spotify_key,
                "Google Key": comp.track.google_key,
                "Detected Key": result.key if result else None,
                "Spotify Key Verdict": comp.key_spotify.verdict,
                "Spotify Key Detail": comp.key_spotify.detail,
                "Google Key Verdict": comp.key_google.verdict,
                "Google Key Detail": comp.key_google.detail,
            }
        )

    df = pd.DataFrame(rows)
    df.to_csv(target, index=False)
    print(f"Per-song comparison exported to {target}")


def export_key_quality(comparisons: List[TrackComparison], target: Path) -> None:
    rows = []
    for comp in comparisons:
        if not comp.track.google_key:
            continue
        verdict = comp.key_google.verdict
        if verdict == "exact":
            label = "correct"
        elif verdict == "acceptable":
            label = "kinda"
        elif verdict in {"missing-result", "off", "wrong"}:
            label = "wrong"
        else:
            continue
        rows.append(
            {
                "#": comp.track.csv_index,
                "Song": comp.track.song,
                "Artist": comp.track.artist,
                "Google Key": comp.track.google_key,
                "Detected Key": comp.result.key if comp.result else None,
                "Suggested Key Quality": label,
                "Reason": comp.key_google.detail,
            }
        )

    if not rows:
        print("No Google key rows available for key-quality export")
        return

    df = pd.DataFrame(rows)
    df.to_csv(target, index=False)
    print(f"Key-quality suggestions exported to {target}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Evaluate repertoire subset accuracy")
    parser.add_argument(
        "--subset-csv",
        type=Path,
        default=DEFAULT_SUBSET_CSV,
        help=f"Path to repertoire subset CSV (default: {DEFAULT_SUBSET_CSV})",
    )
    parser.add_argument(
        "--results",
        type=Path,
        help="Specific test_results CSV to use (defaults to latest matching test_type)",
    )
    parser.add_argument(
        "--results-dir",
        type=Path,
        default=DEFAULT_RESULTS_DIR,
        help=f"Directory to search for test_results_*.csv (default: {DEFAULT_RESULTS_DIR})",
    )
    parser.add_argument(
        "--test-type",
        default="repertoire-subset",
        help="test_type value to search for inside the results CSV",
    )
    parser.add_argument(
        "--bpm-tolerance",
        type=float,
        default=3.0,
        help="Tolerance (in BPM) for strict matches (default: 3.0)",
    )
    parser.add_argument(
        "--per-song-csv",
        type=Path,
        help="Optional path to export per-song comparison CSV",
    )
    parser.add_argument(
        "--key-quality-csv",
        type=Path,
        help="Optional path to export suggested key-quality labels",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    subset_path = args.subset_csv.expanduser()
    if not subset_path.exists():
        raise SystemExit(f"Subset CSV not found at {subset_path}")

    subset = load_subset_tracks(subset_path)
    if not subset:
        raise SystemExit("Subset CSV contained no tracks")

    if args.results:
        results_path = args.results.expanduser()
    else:
        results_path = find_latest_results(args.results_dir.expanduser(), args.test_type)
        if not results_path:
            raise SystemExit(
                f"No test_results_*.csv with test_type={args.test_type!r} found under {args.results_dir}"
            )

    results_by_key, results_by_index = load_results(results_path, args.test_type)
    comparisons = evaluate_tracks(subset, results_by_key, results_by_index, args.bpm_tolerance)
    summarize(comparisons, args.bpm_tolerance)

    if args.per_song_csv:
        export_per_song(comparisons, args.per_song_csv.expanduser())
    if args.key_quality_csv:
        export_key_quality(comparisons, args.key_quality_csv.expanduser())


if __name__ == "__main__":
    main()
