#!/usr/bin/env python3
"""
Compare repertoire analysis results against ground truth.

Defaults:
- Ground truth: csv/truth_repertoire_manual.csv (80-track manual set), falling back to csv/90 preview list.csv
- Results: latest csv/test_results_*.csv tagged with test_type (default: repertoire-90)

Outputs:
- Console summary of BPM + key accuracy and error patterns.
- Optional append-only log for CLI iterations.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import re
import sys
from pathlib import Path

import pandas as pd

# Add tools directory to path for key_utils
sys.path.insert(0, str(Path(__file__).parent / "tools"))
from key_utils import keys_match_fuzzy  # type: ignore


def compare_bpm(expected: float, actual: float, tolerance: float = 3.0):
    """Compare BPM with tolerance, checking for octave errors."""
    diff = abs(expected - actual)

    if diff <= tolerance:
        return True, "exact"

    # Check for octave errors (2x or 0.5x)
    half_speed = abs(expected - actual * 2)
    double_speed = abs(expected - actual / 2)

    if half_speed <= tolerance:
        return False, f"half_speed (actual: {actual:.1f}, should be ~{expected})"
    if double_speed <= tolerance:
        return False, f"double_speed (actual: {actual:.1f}, should be ~{expected})"
    return False, f"off (actual: {actual:.1f}, expected: {expected}, diff: {diff:.1f})"


def compare_key(expected: str, actual: str):
    """Compare keys with enharmonic matching using key_utils."""
    match, reason = keys_match_fuzzy(actual, expected)
    if match:
        return True, reason
    return False, f"{reason} (actual: {actual}, expected: {expected})"


def load_ground_truth(csv_path: Path) -> list[dict]:
    """Load expected BPM/key from a ground-truth CSV."""
    try:
        df = pd.read_csv(csv_path, engine="python")
    except pd.errors.ParserError:
        import csv

        ground: list[dict] = []
        with csv_path.open(newline="", encoding="utf-8") as handle:
            reader = csv.reader(handle)
            header = next(reader, None)
            for raw in reader:
                if not raw or all(not str(cell).strip() for cell in raw):
                    continue
                while len(raw) < 4:
                    raw.append("")
                song_raw, artist_raw, bpm_raw, key_raw = raw[:4]
                notes = raw[4] if len(raw) > 4 else ""
                try:
                    bpm = float(bpm_raw)
                except (TypeError, ValueError):
                    continue
                ground.append(
                    {
                        "bpm": bpm,
                        "key": str(key_raw).strip(),
                        "title": str(song_raw).strip(),
                        "artist": str(artist_raw).strip(),
                        "notes": notes.strip(),
                    }
                )
        return ground

    def pick_column(options: list[str]) -> str:
        for name in options:
            if name in df.columns:
                return name
        raise ValueError(f"Missing required columns; tried {options}")

    song_col = pick_column(["Song", "Title", "song_title"])
    artist_col = pick_column(["Artist", "artist"])
    bpm_col = pick_column(["BPM", "Truth BPM", "Expected BPM"])
    key_col = pick_column(["Key", "Truth Key", "Expected Key"])
    camelot_col = next((name for name in ("Camelot", "Camelot Key") if name in df.columns), None)

    ground = []
    for _, row in df.iterrows():
        song_raw = row[song_col]
        artist_raw = row[artist_col]
        bpm_raw = row[bpm_col]
        key_raw = row[key_col]

        if pd.isna(song_raw) or pd.isna(artist_raw) or pd.isna(bpm_raw):
            continue

        try:
            bpm = float(bpm_raw)
        except (TypeError, ValueError):
            continue

        title = str(song_raw).strip()
        artist = str(artist_raw).strip()

        ground_key = ""
        if not pd.isna(key_raw):
            ground_key = str(key_raw).strip()
        if not ground_key and camelot_col:
            camelot_raw = row[camelot_col]
            if not pd.isna(camelot_raw):
                ground_key = str(camelot_raw).strip()

        ground.append(
            {
                "bpm": bpm,
                "key": ground_key,
                "title": title,
                "artist": artist,
            }
        )
    return ground


def load_results(csv_path: Path, test_type: str | None) -> list[dict]:
    """Load repertoire analysis results from a test_results CSV."""
    df = pd.read_csv(csv_path)
    if "test_type" in df.columns and test_type:
        df = df[df["test_type"] == test_type]
    elif test_type and "test_type" not in df.columns:
        print("⚠️ test_type column missing in results; using all rows.")

    results = []
    for _, row in df.iterrows():
        song = str(row["song_title"]).strip()
        artist = str(row["artist"]).strip()
        bpm_raw = row["bpm"]
        key = str(row["key"]).strip()
        if pd.isna(bpm_raw):
            continue
        try:
            bpm = float(bpm_raw)
        except (TypeError, ValueError):
            continue
        results.append(
            {
                "bpm": bpm,
                "key": key,
                "title": song,
                "artist": artist,
            }
        )
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description="Compare repertoire-90 analysis results against Spotify ground truth")
    parser.add_argument(
        "--results",
        type=str,
        default=None,
        help="Path to a test_results CSV to analyze (defaults to latest repertoire-90)",
    )
    parser.add_argument(
        "--truth-csv",
        type=str,
        default=None,
        help="Path to ground truth CSV (default: csv/truth_repertoire_manual.csv, fallback to csv/90 preview list.csv)",
    )
    parser.add_argument(
        "--test-type",
        type=str,
        default="repertoire-90",
        help="test_type value to filter results (set empty to disable filter)",
    )
    parser.add_argument(
        "--log",
        action="store_true",
        help="Append a one-line summary to reports/repertoire_iterations.log",
    )
    parser.add_argument(
        "--log-file",
        type=str,
        default=str(Path("reports") / "repertoire_iterations.log"),
        help="Path to append log output when --log is set",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).parent
    truth_candidates = [
        repo_root / "csv" / "truth_repertoire_manual.csv",
        repo_root / "csv" / "90 preview list.csv",
    ]

    if args.truth_csv:
        ground_csv = Path(args.truth_csv)
        if not ground_csv.is_absolute():
            ground_csv = repo_root / args.truth_csv
    else:
        ground_csv = next((candidate for candidate in truth_candidates if candidate.exists()), truth_candidates[-1])

    if not ground_csv.exists():
        print(f"❌ Ground truth CSV not found at {ground_csv}")
        sys.exit(1)

    test_type = args.test_type or None

    results_csv: Path | None = None
    if args.results:
        results_csv = Path(args.results)
        if not results_csv.exists():
            print(f"❌ Results CSV not found at {results_csv}")
            sys.exit(1)
    else:
        # Find most recent repertoire results CSV
        csv_dir = repo_root / "csv"
        candidates = sorted(csv_dir.glob("test_results_*.csv"), key=lambda p: p.stat().st_mtime, reverse=True)
        for p in candidates:
            try:
                df = pd.read_csv(p, nrows=5)
            except Exception:
                continue
            if "test_type" not in df.columns:
                results_csv = p
                break
            if test_type is None or (df["test_type"] == test_type).any():
                results_csv = p
                break

        if results_csv is None and candidates:
            results_csv = candidates[0]
            print(f"⚠️ No results CSV matched test_type '{test_type or 'any'}'; using latest: {results_csv.name}")

    if results_csv is None:
        target_label = test_type or "any"
        print(f"❌ No results CSV found (test_type == '{target_label}').")
        sys.exit(1)

    print(f"Reading ground truth from: {ground_csv.name}")
    print(f"Reading repertoire results from: {results_csv.name} (test_type={test_type or 'any'})")
    print()

    ground = load_ground_truth(ground_csv)
    results = load_results(results_csv, test_type)

    total = len(ground)
    bpm_correct = 0
    key_correct = 0

    issues: list[dict] = []

    print("=" * 100)
    print(f"REPERTOIRE ACCURACY ANALYSIS (test_type={test_type or 'any'})")
    print("=" * 100)
    print()

    use_index_alignment = len(results) == len(ground)
    if use_index_alignment:
        print("Alignment: index order (result count matches ground truth)")
    else:
        print("Alignment: fuzzy by artist/title (counts differ; index order disabled)")
    print()

    def _norm(value: str) -> str:
        return re.sub(r"[^a-z0-9]", "", value.lower())

    normalized_results = [
        {
            **r,
            "norm_artist": _norm(r["artist"]),
            "norm_title": _norm(r["title"]),
        }
        for r in results
    ]
    results_by_both = {
        (r["norm_artist"], r["norm_title"]): r for r in normalized_results
    }
    results_by_title = {}
    for r in normalized_results:
        results_by_title.setdefault(r["norm_title"], []).append(r)

    # Iterate in ground truth order; if counts match, align by index for deterministic matching
    iterable = enumerate(ground) if use_index_alignment else ((idx, item) for idx, item in enumerate(ground))

    for idx, expected in iterable:
        artist = expected["artist"]
        title = expected["title"]
        if use_index_alignment:
            try:
                result_entry = results[idx]
            except IndexError:
                print(f"⚠️  Missing result for index {idx+1}: {artist} - {title}")
                continue
        else:
            norm_artist = _norm(artist)
            norm_title = _norm(title)
            result_entry = results_by_both.get((norm_artist, norm_title))

            if result_entry is None:
                title_matches = results_by_title.get(norm_title, [])
                if title_matches:
                    result_entry = title_matches[0]
            if result_entry is None and normalized_results:
                for cand in normalized_results:
                    if norm_title and norm_title in cand["norm_title"]:
                        result_entry = cand
                        break

            if result_entry is None:
                print(f"⚠️  {artist} - {title} : NOT FOUND in repertoire results")
                continue

        bpm_match, bpm_reason = compare_bpm(expected["bpm"], result_entry["bpm"])
        key_match, key_reason = compare_key(expected["key"], result_entry["key"])

        if bpm_match:
            bpm_correct += 1
            bpm_status = "✅"
        else:
            bpm_status = "❌"
            issues.append(
                {
                    "song": f"{artist} - {title}",
                    "type": "BPM",
                    "expected": expected["bpm"],
                    "actual": result_entry["bpm"],
                    "reason": bpm_reason,
                }
            )

        if key_match:
            key_correct += 1
            key_status = "✅"
        else:
            key_status = "❌"
            issues.append(
                {
                    "song": f"{artist} - {title}",
                    "type": "Key",
                    "expected": expected["key"],
                    "actual": result_entry["key"],
                    "reason": key_reason,
                }
            )

        print(
            f"{artist[:20]:20} - {title[:30]:30} | "
            f"BPM: {bpm_status} {result_entry['bpm']:6.1f} (exp: {expected['bpm']:3}) | "
            f"Key: {key_status} {result_entry['key']:10} (exp: {expected['key']:10})"
        )
        if not bpm_match:
            print(f"                                           └─ BPM: {bpm_reason}")
        if not key_match:
            print(f"                                           └─ Key: {key_reason}")

    print()
    print("=" * 100)
    print("SUMMARY")
    print("=" * 100)
    print(f"BPM Accuracy:  {bpm_correct}/{total} ({bpm_correct/total*100:.1f}%)")
    print(f"Key Accuracy:  {key_correct}/{total} ({key_correct/total*100:.1f}%)")
    print(f"Overall:       {bpm_correct + key_correct}/{total * 2} ({(bpm_correct + key_correct)/(total * 2)*100:.1f}%)")
    print()

    if args.log:
        log_path = Path(args.log_file)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        timestamp = _dt.datetime.now().isoformat(timespec="seconds")
        with log_path.open("a", encoding="utf-8") as handle:
            handle.write(
                f"{timestamp} | {results_csv.name} | truth={ground_csv.name} | test_type={test_type or 'any'} | "
                f"BPM {bpm_correct}/{total} ({bpm_correct/total*100:.1f}%) | "
                f"Key {key_correct}/{total} ({key_correct/total*100:.1f}%) | Overall {(bpm_correct + key_correct)/(total*2)*100:.1f}% | "
                f"alignment={'index' if use_index_alignment else 'fuzzy'}\n"
            )

    # Group issues
    octave_errors = [i for i in issues if i["type"] == "BPM" and "speed" in i.get("reason", "")]
    other_bpm = [i for i in issues if i["type"] == "BPM" and "speed" not in i.get("reason", "")]
    key_errors = [i for i in issues if i["type"] == "Key"]

    if octave_errors:
        print("OCTAVE ERRORS (Priority 1):")
        for issue in octave_errors:
            print(f"  • {issue['song'][:50]:50} - {issue['reason']}")
        print()

    if other_bpm:
        print("OTHER BPM ERRORS (Priority 2):")
        for issue in other_bpm[:15]:
            print(f"  • {issue['song'][:50]:50} - {issue['reason']}")
        if len(other_bpm) > 15:
            print(f"  • ... and {len(other_bpm) - 15} more")
        print()

    if key_errors:
        print("KEY ERRORS (Priority 3):")
        for issue in key_errors[:20]:
            print(f"  • {issue['song'][:50]:50} - {issue['reason']}")
        if len(key_errors) > 20:
            print(f"  • ... and {len(key_errors) - 20} more")
        print()

    if bpm_correct == total and key_correct == total:
        print("🎉 100% ACCURACY ACHIEVED ON REPERTOIRE SET! 🎉")
    else:
        print(f"Target: 100% (BPM + Key)")
        print(f"Current: {(bpm_correct + key_correct)/(total * 2)*100:.1f}% ({bpm_correct + key_correct}/{total * 2} correct)")
        print(f"Remaining: {(total * 2) - (bpm_correct + key_correct)} issues to investigate")


if __name__ == "__main__":
    main()
