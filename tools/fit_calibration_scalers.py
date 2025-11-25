#!/usr/bin/env python3
"""
Fit linear calibration scalers that map analyzer outputs to Spotify reference metrics.

Usage:
    python3 tools/fit_calibration_scalers.py \
        --dataset data/calibration/mac_gui_calibration_20251112_161045.parquet \
        --output config/calibration_scalers.json \
        --feature-set-version v1 \
        --notes "post-ui sweep"
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
import sys
from typing import Dict, Iterable, List, Optional, Tuple

import numpy as np
import pandas as pd
REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.append(str(REPO_ROOT))

from tools.calibration_specs import FEATURE_SPECS, FeatureSpec
from tools.dataset_health import (
    collect_source_metadata,
    describe_dataset_artifact,
    ensure_dataset_health,
)

DEFAULT_OUTPUT = REPO_ROOT / "config" / "calibration_scalers.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Fit linear scalers for analyzer → Spotify metrics.")
    parser.add_argument(
        "--dataset",
        dest="datasets",
        action="append",
        required=True,
        help="Path to a calibration parquet dataset. Repeat for multiple files.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Output JSON path (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--feature-set-version",
        default="v1",
        help="Feature-set label baked into the config.",
    )
    parser.add_argument(
        "--notes",
        default="",
        help="Optional notes stored in the config header.",
    )
    parser.add_argument(
        "--min-samples",
        type=int,
        default=4,
        help="Minimum rows required to fit a scaler.",
    )
    parser.add_argument(
        "--preview",
        action="store_true",
        help="Print summary table before writing the JSON file.",
    )
    return parser.parse_args()


def load_datasets(paths: Iterable[str]) -> Tuple[pd.DataFrame, List[Dict[str, object]]]:
    frames: List[pd.DataFrame] = []
    artifacts: List[Dict[str, object]] = []
    for path in paths:
        expanded = Path(path).expanduser()
        if not expanded.exists():
            raise FileNotFoundError(f"Dataset not found: {expanded}")
        frame = pd.read_parquet(expanded)
        frames.append(frame)
        artifacts.append(describe_dataset_artifact(expanded, frame))
    combined = pd.concat(frames, ignore_index=True)
    return combined, artifacts


def fit_scaler(df: pd.DataFrame, spec: FeatureSpec, min_samples: int) -> Optional[Dict[str, float]]:
    x = pd.to_numeric(df.get(spec.source_col), errors="coerce")
    y = pd.to_numeric(df.get(spec.target_col), errors="coerce")
    mask = x.notna() & y.notna()
    x = x[mask]
    y = y[mask]
    if len(x) < min_samples:
        return None
    x_values = x.astype(float).to_numpy()
    y_values = y.astype(float).to_numpy()
    if spec.percent_scale:
        x_values = x_values / 100.0
        y_values = y_values / 100.0
    slope, intercept = np.polyfit(x_values, y_values, 1)
    predictions = slope * x_values + intercept
    residuals = y_values - predictions
    ss_res = float(np.sum(residuals ** 2))
    ss_tot = float(np.sum((y_values - np.mean(y_values)) ** 2))
    r2 = 1.0 - (ss_res / ss_tot) if ss_tot > 0 else 0.0
    mae_before = float(np.mean(np.abs(x_values - y_values)))
    mae_after = float(np.mean(np.abs(predictions - y_values)))
    return {
        "slope": float(slope),
        "intercept": float(intercept),
        "sample_count": int(len(x_values)),
        "r2": float(r2),
        "mae_before": float(mae_before),
        "mae_after": float(mae_after),
        "percent_scale": spec.percent_scale,
        "clamp": {
            "min": spec.clamp[0] if spec.clamp else None,
            "max": spec.clamp[1] if spec.clamp else None,
        },
        "source_column": spec.source_col,
        "target_column": spec.target_col,
        "description": spec.description,
    }


def build_config(args: argparse.Namespace) -> Dict[str, object]:
    df, artifacts = load_datasets(args.datasets)
    ensure_dataset_health(df)
    feature_results: Dict[str, Dict[str, float]] = {}
    skipped: List[str] = []
    for spec in FEATURE_SPECS:
        stats = fit_scaler(df, spec, args.min_samples)
        if stats:
            feature_results[spec.name] = stats
        else:
            skipped.append(spec.name)
    generated_at = dt.datetime.utcnow().isoformat()
    dataset_lineage = {
        "artifacts": artifacts,
        "analyzer_sources": collect_source_metadata(
            df, "analyzer_source_file", legacy_alias="source_file"
        ),
        "spotify_sources": collect_source_metadata(df, "spotify_source_file"),
    }
    config = {
        "generated_at": generated_at,
        "feature_set_version": args.feature_set_version,
        "notes": args.notes,
        "datasets": [entry["path"] for entry in artifacts],
        "dataset_lineage": dataset_lineage,
        "feature_count": len(feature_results),
        "skipped_features": skipped,
        "features": feature_results,
    }
    return config


def print_summary(config: Dict[str, object]) -> None:
    features = config["features"]
    header = f"{'Feature':<14}{'Slope':>10}{'Intercept':>12}{'Samples':>10}{'R^2':>8}{'MAE→':>10}"
    print(header)
    print("-" * len(header))
    for name, stats in features.items():
        slope = stats["slope"]
        intercept = stats["intercept"]
        samples = stats["sample_count"]
        r2 = stats["r2"]
        mae_after = stats["mae_after"]
        print(f"{name:<14}{slope:>10.4f}{intercept:>12.4f}{samples:>10}{r2:>8.3f}{mae_after:>10.4f}")
    skipped = config.get("skipped_features", [])
    if skipped:
        print(f"\nSkipped (insufficient data): {', '.join(skipped)}")


def main() -> None:
    args = parse_args()
    config = build_config(args)
    if args.preview:
        print_summary(config)
    output_path = args.output.expanduser()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2)
    print(f"✅ Saved calibration scalers to {output_path} ({len(config['features'])} features)")


if __name__ == "__main__":
    main()
