#!/usr/bin/env python3
"""
Compare analyzer results from a single calibration dataset against Spotify
reference metrics. Useful for quick spot checks on small Mac GUI sweeps.
"""
from __future__ import annotations

import argparse
import csv
from collections import Counter
from pathlib import Path
from typing import Iterable, List, Tuple
import sys

import pandas as pd

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.append(str(REPO_ROOT))

from tools.key_utils import normalize_key_label


def load_dataset(path: Path) -> pd.DataFrame:
    if not path.exists():
        raise FileNotFoundError(path)
    return pd.read_parquet(path)


def apply_filters(df: pd.DataFrame, titles: Iterable[str], artists: Iterable[str]) -> pd.DataFrame:
    filtered = df
    if titles:
        wanted = {title.strip().lower() for title in titles if title.strip()}
        if wanted:
            filtered = filtered[filtered["title"].str.lower().isin(wanted)]
    if artists:
        wanted = {artist.strip().lower() for artist in artists if artist.strip()}
        if wanted:
            filtered = filtered[filtered["artist"].str.lower().isin(wanted)]
    return filtered


def summarize_key_alignment(df: pd.DataFrame) -> Tuple[str, List[dict]]:
    records = []
    for _, row in df.iterrows():
        analyzer = normalize_key_label(row["analyzer_key"])
        spotify = normalize_key_label(row["spotify_key"])
        if analyzer is None or spotify is None:
            continue
        a_root, a_mode = analyzer
        s_root, s_mode = spotify
        offset = (a_root - s_root) % 12
        records.append(
            {
                "title": row["title"],
                "artist": row["artist"],
                "analyzer_key": row["analyzer_key"],
                "spotify_key": row["spotify_key"],
                "offset": offset,
                "mode_match": a_mode == s_mode,
                "match": (offset == 0) and (a_mode == s_mode),
                "analyzer_bpm": row.get("analyzer_bpm"),
                "spotify_bpm": row.get("spotify_bpm"),
                "bpm_delta": _bpm_delta(row.get("analyzer_bpm"), row.get("spotify_bpm")),
            }
        )
    if not records:
        return "No comparable rows with analyzer + Spotify keys.", []
    total = len(records)
    exact = sum(r["match"] for r in records)
    mode_mismatch = sum(not r["mode_match"] for r in records)
    buckets = Counter(r["offset"] for r in records)
    lines = [
        f"Compared rows: {total}",
        f"Exact key matches: {exact} ({exact/total:.1%})",
        f"Mode mismatches: {mode_mismatch} ({mode_mismatch/total:.1%})",
        "",
        "Offset distribution (analyzer_root - spotify_root mod 12):",
    ]
    for offset, count in sorted(buckets.items()):
        pct = count / total * 100
        lines.append(f"  {offset:+2d}: {count} ({pct:.1f}%)")
    lines.append("")
    lines.append("Examples:")
    sample_records = sorted(records, key=lambda r: (r["match"], -buckets[r["offset"]]))[:5]
    for record in sample_records:
        lines.append(
            f"- {record['title']} – {record['artist']}: "
            f"{record['analyzer_key']} → {record['spotify_key']} "
            f"(offset {record['offset']}, mode match={record['mode_match']})"
        )
    return "\n".join(lines), records


def _bpm_delta(analyzer_bpm, spotify_bpm):
    try:
        if analyzer_bpm is None or spotify_bpm is None:
            return None
        return float(analyzer_bpm) - float(spotify_bpm)
    except (TypeError, ValueError):
        return None


def write_comparison_csv(records: List[dict], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "Title",
                "Artist",
                "Analyzer BPM",
                "Spotify BPM",
                "BPM Delta",
                "Analyzer Key",
                "Spotify Key",
                "Key Offset",
                "Mode Match",
                "Exact Match",
            ]
        )
        for record in records:
            writer.writerow(
                [
                    record["title"],
                    record["artist"],
                    record.get("analyzer_bpm"),
                    record.get("spotify_bpm"),
                    record.get("bpm_delta"),
                    record["analyzer_key"],
                    record["spotify_key"],
                    record["offset"],
                    "yes" if record["mode_match"] else "no",
                    "yes" if record["match"] else "no",
                ]
            )


def main() -> None:
    parser = argparse.ArgumentParser(description="Compare a calibration dataset against Spotify reference keys.")
    parser.add_argument("--dataset", required=True, help="Path to the Parquet file produced by the calibration builder.")
    parser.add_argument("--titles", nargs="*", default=[], help="Optional list of exact song titles to include.")
    parser.add_argument("--titles-file", help="Path to a text file (one song title per line).")
    parser.add_argument("--artists", nargs="*", default=[], help="Optional list of artists to filter by.")
    parser.add_argument("--artists-file", help="Path to a text file (one artist per line).")
    parser.add_argument("--csv-output", help="Optional path to write the BPM/key comparison CSV.")
    args = parser.parse_args()

    dataset_path = Path(args.dataset)
    df = load_dataset(dataset_path)

    title_filters: List[str] = list(args.titles)
    artist_filters: List[str] = list(args.artists)
    if args.titles_file:
        title_filters.extend(Path(args.titles_file).read_text(encoding="utf-8").splitlines())
    if args.artists_file:
        artist_filters.extend(Path(args.artists_file).read_text(encoding="utf-8").splitlines())

    filtered = apply_filters(df, title_filters, artist_filters)
    if filtered.empty:
        print("No rows matched the provided filters.")
        return

    summary, records = summarize_key_alignment(filtered)
    print(summary)
    if args.csv_output:
        output_path = Path(args.csv_output)
        if not records:
            if output_path.exists():
                output_path.unlink()
            print("No comparable rows found; CSV not generated.")
        else:
            write_comparison_csv(records, output_path)
            print(f"📄 Wrote comparison CSV to {output_path}")


if __name__ == "__main__":
    main()
