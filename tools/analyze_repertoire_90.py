#!/usr/bin/env python3
"""
Analyze the 90-song repertoire preview set using the Essentia analysis server.

This is similar in spirit to Test C, but operates on an external folder:
    ~/Documents/Git repo/Songwise 1/preview_samples_repertoire_90

Results (BPM, key, and core MIR features) are exported to csv/test_results_*.csv
via the shared test_analysis_utils.save_results_to_csv helper.
"""

from __future__ import annotations

import argparse
import glob
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, List

import requests

from test_analysis_utils import (
    Colors,
    print_error,
    print_header,
    print_info,
    print_success,
    print_warning,
    save_results_to_csv,
)


def build_headers(title: str, artist: str, *, force_reanalyze: bool, cache_namespace: str | None) -> Dict[str, str]:
    headers: Dict[str, str] = {
        "X-Song-Title": title,
        "X-Song-Artist": artist,
        "Content-Type": "application/octet-stream",
    }
    if force_reanalyze:
        headers["X-Force-Reanalyze"] = "1"
    if cache_namespace:
        headers["X-Cache-Namespace"] = cache_namespace
    return headers


def parse_title_artist_from_filename(filename: str, fallback_index: int) -> tuple[str, str]:
    """
    Parse a simple (artist, title) from filenames of the form:
        001_Artist_Title_with_underscores.m4a

    This mirrors the logic used for Test C previews: index, artist token, then the rest as title.
    """
    stem = filename.rsplit(".", 1)[0]
    parts = stem.split("_", 2)
    if len(parts) > 2:
        artist = parts[1] or "Unknown"
        title = parts[2] or f"Repertoire {fallback_index}"
    elif len(parts) == 2:
        artist = parts[1] or "Unknown"
        title = f"Repertoire {fallback_index}"
    else:
        artist = "Unknown"
        title = f"Repertoire {fallback_index}"
    return title, artist


def check_server_health(base_url: str) -> bool:
    print_header("Server Health Check (Repertoire 90)")
    try:
        response = requests.get(f"{base_url}/health", timeout=5)
        if response.status_code == 200:
            data = response.json()
            print_success(f"Server is healthy: {data.get('status', 'unknown')}")
            return True
        print_error(f"Health check failed with status {response.status_code}")
        return False
    except Exception as exc:
        print_error(f"Health check failed: {exc}")
        return False


def analyze_repertoire_folder(
    preview_dir: Path,
    *,
    base_url: str,
    force_reanalyze: bool,
    cache_namespace: str,
) -> List[Dict[str, Any]]:
    print_header("Repertoire 90 Preview Analysis")

    if not preview_dir.exists() or not preview_dir.is_dir():
        print_error(f"Preview directory does not exist: {preview_dir}")
        sys.exit(1)

    files = sorted(glob.glob(str(preview_dir / "*.m4a")))
    if not files:
        print_error(f"No .m4a files found in {preview_dir}")
        sys.exit(1)

    print_info(f"Found {len(files)} preview files in {preview_dir}")

    all_results: List[Dict[str, Any]] = []

    start_time = time.time()
    for idx, filepath in enumerate(files, start=1):
        filename = os.path.basename(filepath)
        title, artist = parse_title_artist_from_filename(filename, fallback_index=idx)

        print_info(f"[{idx:03d}/{len(files)}] Analyzing {filename}")

        song_start = time.time()
        try:
            with open(filepath, "rb") as f:
                audio_data = f.read()

            response = requests.post(
                f"{base_url}/analyze_data",
                data=audio_data,
                headers=build_headers(title, artist, force_reanalyze=force_reanalyze, cache_namespace=cache_namespace),
                timeout=130,
            )
            duration = time.time() - song_start

            result: Dict[str, Any] = {
                "success": response.status_code == 200,
                "status_code": response.status_code,
                "song": title,
                "artist": artist,
                "file_type": "preview",
                "test_type": "repertoire-90",
                "duration": duration,
                "data": response.json() if response.status_code == 200 else None,
                "error": response.text if response.status_code != 200 else "",
            }
        except Exception as exc:
            duration = time.time() - song_start
            result = {
                "success": False,
                "status_code": 0,
                "song": title,
                "artist": artist,
                "file_type": "preview",
                "test_type": "repertoire-90",
                "duration": duration,
                "data": None,
                "error": str(exc),
            }

        all_results.append(result)

        if result["success"] and result["data"]:
            data = result["data"]
            bpm = data.get("bpm", "N/A")
            key = data.get("key", "N/A")
            energy = data.get("energy", "N/A")
            danceability = data.get("danceability", "N/A")
            print_success(
                f"  → {title[:40]:40} | BPM: {bpm:>6} | Key: {key:>8} | "
                f"Energy: {str(energy)[:6]:>6} | Dance: {str(danceability)[:6]:>6}"
            )
        else:
            print_error(f"  → FAILED ({result.get('error', '')[:120]})")

    total_duration = time.time() - start_time
    successes = sum(1 for r in all_results if r["success"])

    print_header("Repertoire 90 Summary")
    if successes == len(all_results):
        print_success(f"All {successes}/{len(all_results)} songs analyzed successfully")
    else:
        print_warning(f"{successes}/{len(all_results)} songs analyzed successfully")
        failures = [r for r in all_results if not r["success"]]
        for r in failures[:10]:
            print_error(f"  - {r['song']}: {r.get('error', '')[:120]}")
        if len(failures) > 10:
            print_error(f"  ... and {len(failures) - 10} more failures")

    print_info(f"Total analysis time: {total_duration:.2f}s")

    return all_results


def main() -> None:
    parser = argparse.ArgumentParser(description="Analyze 90-song repertoire preview set")
    parser.add_argument(
        "--dir",
        type=str,
        help="Directory containing repertoire preview .m4a files "
        "(default: ~/Documents/Git repo/Songwise 1/preview_samples_repertoire_90)",
    )
    parser.add_argument(
        "--url",
        default="http://127.0.0.1:5050",
        help="Analysis server base URL (default: http://127.0.0.1:5050)",
    )
    parser.add_argument(
        "--csv",
        type=str,
        help="Export results to CSV file with given name (saved under csv/)",
    )
    parser.add_argument(
        "--csv-auto",
        action="store_true",
        help="Automatically export results to timestamped CSV file",
    )
    parser.add_argument(
        "--allow-cache",
        action="store_true",
        help="Allow cached analysis responses (default forces re-analysis)",
    )
    parser.add_argument(
        "--cache-namespace",
        default="repertoire-90",
        help="Cache namespace for this run (default: repertoire-90)",
    )

    args = parser.parse_args()

    # Resolve preview directory
    if args.dir:
        preview_dir = Path(args.dir).expanduser()
    else:
        preview_dir = Path.home() / "Documents" / "Git repo" / "Songwise 1" / "preview_samples_repertoire_90"

    # Check server health first
    if not check_server_health(args.url):
        sys.exit(1)

    force_reanalyze = not args.allow_cache
    if force_reanalyze:
        print_info("Cache bypass enabled: forcing re-analysis for every song")
    else:
        print_info("Cache usage enabled: reusing previous analysis results when available")

    results = analyze_repertoire_folder(
        preview_dir,
        base_url=args.url,
        force_reanalyze=force_reanalyze,
        cache_namespace=args.cache_namespace,
    )

    if args.csv or args.csv_auto:
        filename = args.csv if args.csv else None
        save_results_to_csv(results, filename)


if __name__ == "__main__":
    main()

