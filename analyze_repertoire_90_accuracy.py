#!/usr/bin/env python3
"""
Compare repertoire-90 analysis results against Spotify ground truth.

Inputs:
- csv/90 preview list.csv           (Spotify data for 90 tunes)
- latest csv/test_results_*.csv     (server output with test_type=='repertoire-90')

Outputs:
- Console summary of BPM + key accuracy and error patterns.
- Optional append-only log for CLI iterations.
"""

from __future__ import annotations

import argparse
import datetime as _dt
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


def load_ground_truth(csv_path: Path) -> dict[str, dict]:
    """Load expected BPM/key from 90 preview list.csv."""
    df = pd.read_csv(csv_path)

    ground = []
    for _, row in df.iterrows():
        title = str(row["Song"]).strip()
        artist = str(row["Artist"]).strip()
        key = str(row["Key"]).strip()
        bpm = float(row["BPM"])
        key_cam = str(row.get("Camelot", "")).strip()

        ground_key = key
        if not ground_key and key_cam:
            ground_key = key_cam

        ground.append(
            {
            "bpm": bpm,
            "key": ground_key,
            "title": title,
            "artist": artist,
        }
        )
    return ground


def load_results(csv_path: Path) -> dict[str, dict]:
    """Load repertoire-90 analysis results from latest test_results CSV."""
    df = pd.read_csv(csv_path)
    df = df[df["test_type"] == "repertoire-90"]

    results = []
    for _, row in df.iterrows():
        song = str(row["song_title"]).strip()
        artist = str(row["artist"]).strip()
        bpm = float(row["bpm"])
        key = str(row["key"]).strip()
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
    ground_csv = repo_root / "csv" / "90 preview list.csv"

    if not ground_csv.exists():
        print(f"❌ Ground truth CSV not found at {ground_csv}")
        sys.exit(1)

    results_csv: Path | None = None
    if args.results:
        results_csv = Path(args.results)
        if not results_csv.exists():
            print(f"❌ Results CSV not found at {results_csv}")
            sys.exit(1)
    else:
        # Find most recent repertoire-90 results CSV
        csv_dir = repo_root / "csv"
        candidates = sorted(csv_dir.glob("test_results_*.csv"), key=lambda p: p.stat().st_mtime, reverse=True)
        for p in candidates:
            df = pd.read_csv(p, nrows=5)
            if "test_type" in df.columns and (df["test_type"] == "repertoire-90").any():
                results_csv = p
                break

    if results_csv is None:
        print("❌ No repertoire-90 results CSV found (test_type == 'repertoire-90').")
        sys.exit(1)

    print(f"Reading ground truth from: {ground_csv.name}")
    print(f"Reading repertoire results from: {results_csv.name}")
    print()

    ground = load_ground_truth(ground_csv)
    results = load_results(results_csv)

    total = len(ground)
    bpm_correct = 0
    key_correct = 0

    issues: list[dict] = []

    print("=" * 100)
    print("REPERTOIRE-90 ACCURACY ANALYSIS")
    print("=" * 100)
    print()

    use_index_alignment = len(results) == len(ground)
    if use_index_alignment:
        print("Alignment: index order (90 preview files are 1:1 with ground truth)")
    else:
        print("Alignment: fuzzy by artist/title (counts differ; index order disabled)")
    print()

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
            key_id = f"{artist}::{title}"
            result_entry = None
            if results and isinstance(results, list):
                # Linear search fallback if results came back as a list with different order
                matches = [
                    r
                    for r in results
                    if r["artist"] == artist or r["title"].endswith(title.replace(" ", "_")) or r["title"].replace("_", " ") == title
                ]
                result_entry = matches[0] if matches else None
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
                f"{timestamp} | {results_csv.name} | BPM {bpm_correct}/{total} ({bpm_correct/total*100:.1f}%) | "
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
        print("🎉 100% ACCURACY ACHIEVED ON REPERTOIRE-90! 🎉")
    else:
        print(f"Target: 100% (BPM + Key)")
        print(f"Current: {(bpm_correct + key_correct)/(total * 2)*100:.1f}% ({bpm_correct + key_correct}/{total * 2} correct)")
        print(f"Remaining: {(total * 2) - (bpm_correct + key_correct)} issues to investigate")


if __name__ == "__main__":
    main()
