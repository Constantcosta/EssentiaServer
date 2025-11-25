#!/usr/bin/env python3
"""
Fit a confusion-map calibrator that remaps analyzer key predictions to Spotify keys.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
from collections import Counter, defaultdict
from pathlib import Path
import sys
from typing import Dict, Iterable, List, Optional, Tuple

import numpy as np
import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.append(str(REPO_ROOT))

from tools.dataset_health import describe_dataset_artifact  # noqa: E402
from tools.key_utils import (  # noqa: E402
    canonical_key_id,
    format_canonical_key,
    normalize_key_label,
    parse_canonical_key_id,
)

DEFAULT_OUTPUT = REPO_ROOT / "config" / "key_calibration.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Fit a key confusion calibration map.")
    parser.add_argument(
        "--dataset",
        dest="datasets",
        action="append",
        required=True,
        help="Path(s) to calibration parquet datasets.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Output JSON (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--notes",
        default="",
        help="Optional notes to store in metadata.",
    )
    parser.add_argument(
        "--preview",
        action="store_true",
        help="Print the remapping table instead of writing JSON.",
    )
    return parser.parse_args()


def load_datasets(paths: Iterable[str]) -> Tuple[pd.DataFrame, List[Dict[str, object]]]:
    frames: List[pd.DataFrame] = []
    artifacts: List[Dict[str, object]] = []
    for raw in paths:
        path = Path(raw).expanduser()
        if not path.exists():
            raise FileNotFoundError(f"Dataset not found: {path}")
        frame = pd.read_parquet(path)
        frames.append(frame)
        artifacts.append(describe_dataset_artifact(path, frame))
    if not frames:
        raise RuntimeError("No datasets loaded.")
    return pd.concat(frames, ignore_index=True), artifacts


def safe_confidence(value: object) -> Optional[float]:
    if value is None or (isinstance(value, float) and np.isnan(value)):
        return None
    try:
        numeric = float(value)
    except (TypeError, ValueError):
        return None
    if numeric > 1.0:
        numeric = numeric / 100.0
    numeric = max(0.0, min(1.0, numeric))
    return numeric


def build_confidence_bins(pairs: List[Tuple[float, bool]], bin_size: float = 0.1, min_samples: int = 3):
    bins = []
    if not pairs:
        return bins
    for start in np.arange(0.0, 1.0, bin_size):
        end = round(start + bin_size, 10)
        sample = [flag for value, flag in pairs if start <= value < end]
        if len(sample) < min_samples:
            continue
        accuracy = sum(sample) / len(sample)
        bins.append(
            {
                "min": float(start),
                "max": float(end),
                "samples": len(sample),
                "accuracy": float(accuracy),
            }
        )
    return bins


def compute_calibration(df: pd.DataFrame):
    counts: Dict[str, Counter] = defaultdict(Counter)
    target_labels: Dict[str, Counter] = defaultdict(Counter)
    analyzer_labels: Dict[str, Counter] = defaultdict(Counter)
    confidence_pairs: Dict[str, List[Tuple[float, bool]]] = defaultdict(list)
    overall_conf_pairs: List[Tuple[float, bool]] = []
    records: List[Dict[str, object]] = []

    for _, row in df.iterrows():
        analyzer = normalize_key_label(row.get("analyzer_key"))
        target = normalize_key_label(row.get("spotify_key"))
        if not analyzer or not target:
            continue
        analyzer_id = canonical_key_id(*analyzer)
        target_id = canonical_key_id(*target)
        counts[analyzer_id][target_id] += 1
        analyzer_labels[analyzer_id][row.get("analyzer_key", "")] += 1
        target_labels[target_id][row.get("spotify_key", "")] += 1
        confidence = safe_confidence(row.get("analyzer_key_confidence"))
        is_correct = analyzer_id == target_id
        if confidence is not None:
            confidence_pairs[analyzer_id].append((confidence, is_correct))
            overall_conf_pairs.append((confidence, is_correct))
        records.append(
            {
                "analyzer": analyzer_id,
                "target": target_id,
                "confidence": confidence,
            }
        )
    total_samples = len(records)
    if total_samples == 0:
        raise RuntimeError("No overlapping analyzer/Spotify keys found in dataset(s).")

    calibration_entries = {}
    for analyzer_id, counter in counts.items():
        total = sum(counter.values())
        sorted_targets = sorted(counter.items(), key=lambda kv: kv[1], reverse=True)
        formatted_targets = []
        for target_id, count in sorted_targets:
            canonical = parse_canonical_key_id(target_id) or (None, None)
            if canonical[0] is not None:
                display_label = (
                    target_labels[target_id].most_common(1)[0][0]
                    if target_labels[target_id]
                    else format_canonical_key(*canonical)
                )
            else:
                display_label = target_id
            formatted_targets.append(
                {
                    "canonical": target_id,
                    "label": display_label,
                    "count": int(count),
                    "probability": float(count / total) if total else 0.0,
                }
            )
        analyzer_canonical = parse_canonical_key_id(analyzer_id)
        analyzer_label = (
            analyzer_labels[analyzer_id].most_common(1)[0][0]
            if analyzer_labels[analyzer_id]
            else (
                format_canonical_key(*analyzer_canonical)
                if analyzer_canonical and analyzer_canonical[0] is not None
                else analyzer_id
            )
        )
        entry = {
            "label": analyzer_label,
            "samples": int(total),
            "targets": formatted_targets,
        }
        conf_values = confidence_pairs.get(analyzer_id, [])
        if conf_values:
            entry["mean_raw_confidence"] = float(np.mean([v for v, _ in conf_values]))
        calibration_entries[analyzer_id] = entry

    raw_correct = sum(1 for record in records if record["analyzer"] == record["target"])
    calibrated_correct = 0
    for record in records:
        analyzer_id = record["analyzer"]
        target = record["target"]
        entry = calibration_entries.get(analyzer_id)
        predicted = analyzer_id
        if entry and entry["targets"]:
            predicted = entry["targets"][0]["canonical"]
        if predicted == target:
            calibrated_correct += 1

    global_confidence_bins = build_confidence_bins(overall_conf_pairs)

    meta = {
        "sample_count": total_samples,
        "raw_accuracy": raw_correct / total_samples if total_samples else 0.0,
        "calibrated_accuracy": calibrated_correct / total_samples if total_samples else 0.0,
        "confidence_bins": global_confidence_bins,
    }
    return calibration_entries, meta


def print_preview(calibration_entries: Dict[str, Dict[str, object]], meta: Dict[str, object]) -> None:
    print(
        f"{'Analyzer Key':<18}{'Top Target':<18}{'Prob':>8}{'Samples':>10}"
    )
    print("-" * 54)
    for analyzer_id, entry in sorted(calibration_entries.items()):
        analyzer_label = entry.get("label", analyzer_id)
        targets = entry.get("targets", [])
        if targets:
            top = targets[0]
            print(
                f"{analyzer_label:<18}{top.get('label', top.get('canonical', '')):<18}"
                f"{top.get('probability', 0.0):>8.2f}{entry.get('samples', 0):>10}"
            )
    print()
    print(
        f"Raw accuracy: {meta.get('raw_accuracy', 0.0):.3f} | "
        f"Calibrated accuracy: {meta.get('calibrated_accuracy', 0.0):.3f}"
    )


def main() -> None:
    args = parse_args()
    df, artifacts = load_datasets(args.datasets)
    calibration_entries, metrics = compute_calibration(df)
    output = {
        "generated_at": dt.datetime.utcnow().isoformat(),
        "notes": args.notes,
        "datasets": [entry["path"] for entry in artifacts],
        "dataset_lineage": {"artifacts": artifacts},
        "sample_count": metrics["sample_count"],
        "raw_accuracy": metrics["raw_accuracy"],
        "calibrated_accuracy": metrics["calibrated_accuracy"],
        "confidence_bins": metrics["confidence_bins"],
        "keys": calibration_entries,
    }
    if args.preview:
        print_preview(calibration_entries, metrics)
        return
    output_path = args.output.expanduser()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as handle:
        json.dump(output, handle, indent=2)
    print(f"✅ Saved key calibration to {output_path} ({len(calibration_entries)} analyzer keys)")


if __name__ == "__main__":
    main()
