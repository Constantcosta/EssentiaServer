#!/usr/bin/env python3
"""Train lightweight calibration models (ridge regression) for analyzer metrics."""
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

from tools.calibration_specs import FEATURE_SPECS
from tools.dataset_health import (
    collect_source_metadata,
    describe_dataset_artifact,
    ensure_dataset_health,
)

DEFAULT_OUTPUT = REPO_ROOT / "models" / "calibration_models.json"
FEATURE_COLUMNS = [
    "analyzer_bpm",
    "analyzer_energy",
    "analyzer_danceability",
    "analyzer_acousticness",
    "analyzer_valence",
    "analyzer_loudness_db",
    "analyzer_spectral_centroid",
    "dynamic_complexity",
    "tonal_strength",
    "spectral_complexity",
    "zero_crossing_rate",
    "spectral_flux",
    "percussive_energy_ratio",
    "harmonic_energy_ratio",
]

TARGET_SPECS = [
    {
        "name": "bpm",
        "target_col": "spotify_bpm",
        "baseline_col": "analyzer_bpm",
        "percent_scale": False,
        "alpha": 5.0,
    },
    {
        "name": "danceability",
        "target_col": "spotify_dance",
        "baseline_col": "analyzer_danceability",
        "percent_scale": True,
        "alpha": 1.0,
    },
    {
        "name": "energy",
        "target_col": "spotify_energy",
        "baseline_col": "analyzer_energy",
        "percent_scale": True,
        "alpha": 1.0,
    },
    {
        "name": "acousticness",
        "target_col": "spotify_acoustic",
        "baseline_col": "analyzer_acousticness",
        "percent_scale": True,
        "alpha": 1.0,
    },
    {
        "name": "valence",
        "target_col": "spotify_happy",
        "baseline_col": "analyzer_valence",
        "percent_scale": True,
        "alpha": 1.0,
    },
    {
        "name": "loudness",
        "target_col": "spotify_loudness_db",
        "baseline_col": "analyzer_loudness_db",
        "percent_scale": False,
        "alpha": 2.0,
    },
]

PERCENT_FEATURES = {
    "analyzer_energy",
    "analyzer_danceability",
    "analyzer_acousticness",
    "analyzer_valence",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train ridge calibration models from calibration datasets.")
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
        help=f"Output JSON path (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--feature-columns",
        nargs="*",
        default=FEATURE_COLUMNS,
        help="Analyzer columns to use as model inputs (default: preset list).",
    )
    parser.add_argument(
        "--feature-set-version",
        default="v1",
        help="Feature set label stored alongside the models.",
    )
    parser.add_argument(
        "--notes",
        default="",
        help="Optional notes stored in the output JSON.",
    )
    parser.add_argument(
        "--preview",
        action="store_true",
        help="Print comparison table before saving the model file.",
    )
    return parser.parse_args()


def load_datasets(paths: Iterable[str]) -> Tuple[pd.DataFrame, List[Dict[str, object]]]:
    frames = []
    artifacts: List[Dict[str, object]] = []
    for raw_path in paths:
        path = Path(raw_path).expanduser()
        if not path.exists():
            raise FileNotFoundError(f"Dataset not found: {path}")
        frame = pd.read_parquet(path)
        frames.append(frame)
        artifacts.append(describe_dataset_artifact(path, frame))
    return pd.concat(frames, ignore_index=True), artifacts


def filter_feature_columns(df: pd.DataFrame, columns: List[str]) -> List[str]:
    selected: List[str] = []
    for column in columns:
        series = df.get(column)
        if series is None:
            continue
        valid = pd.to_numeric(series, errors="coerce").notna().sum()
        if valid >= 8:
            selected.append(column)
    return selected


def prepare_series(series: pd.Series, percent_scale: bool) -> np.ndarray:
    arr = pd.to_numeric(series, errors="coerce").to_numpy(dtype=float)
    if percent_scale:
        arr = arr / 100.0
    return arr


def prepare_features(df: pd.DataFrame, columns: List[str]) -> np.ndarray:
    values = []
    for column in columns:
        series = df.get(column)
        if series is None:
            series = pd.Series([np.nan] * len(df))
        col = pd.to_numeric(series, errors="coerce")
        if column in PERCENT_FEATURES:
            col = col / 100.0
        values.append(col.to_numpy(dtype=float))
    return np.vstack(values).T


def fit_ridge(X: np.ndarray, y: np.ndarray, alpha: float = 1.0) -> Dict[str, np.ndarray]:
    means = X.mean(axis=0)
    stds = X.std(axis=0)
    stds[stds == 0.0] = 1.0
    X_std = (X - means) / stds
    y_mean = y.mean()
    y_centered = y - y_mean
    XtX = X_std.T @ X_std
    reg = alpha * np.eye(X_std.shape[1])
    beta = np.linalg.solve(XtX + reg, X_std.T @ y_centered)
    return {
        "weights": beta,
        "intercept": y_mean,
        "feature_means": means,
        "feature_stds": stds,
    }


def predict(model: Dict[str, np.ndarray], X: np.ndarray) -> np.ndarray:
    means = model["feature_means"]
    stds = model["feature_stds"]
    stds = np.where(stds == 0.0, 1.0, stds)
    X_std = (X - means) / stds
    return X_std @ model["weights"] + model["intercept"]


def print_preview(rows: List[Dict[str, object]]):
    header = f"{'Target':<14}{'Samples':>10}{'Baseline MAE':>14}{'Model MAE':>12}{'Δ':>10}"
    print(header)
    print("-" * len(header))
    for row in rows:
        delta = row["baseline_mae"] - row["model_mae"]
        print(f"{row['target']:<14}{row['sample_count']:>10}{row['baseline_mae']:>14.4f}{row['model_mae']:>12.4f}{delta:>10.4f}")


def main() -> None:
    args = parse_args()
    df, artifacts = load_datasets(args.datasets)
    ensure_dataset_health(df)
    feature_columns = filter_feature_columns(df, args.feature_columns)
    if not feature_columns:
        raise RuntimeError("No usable feature columns found in dataset.")
    metric_rows = []
    targets_output = {}
    for spec in TARGET_SPECS:
        target_series = df.get(spec["target_col"])
        baseline_series = df.get(spec["baseline_col"])
        if target_series is None or baseline_series is None:
            continue
        feature_matrix = prepare_features(df, feature_columns)
        target_values = prepare_series(target_series, percent_scale=spec["percent_scale"])
        baseline_values = prepare_series(baseline_series, percent_scale=spec["percent_scale"])
        mask = ~np.isnan(target_values)
        for col_idx in range(feature_matrix.shape[1]):
            mask &= ~np.isnan(feature_matrix[:, col_idx])
        mask &= ~np.isnan(baseline_values)
        if mask.sum() < 8:
            continue
        X = feature_matrix[mask]
        y = target_values[mask]
        baseline = baseline_values[mask]
        model = fit_ridge(X, y, alpha=spec["alpha"])
        predictions = predict(model, X)
        baseline_mae = float(np.mean(np.abs(baseline - y)))
        model_mae = float(np.mean(np.abs(predictions - y)))
        targets_output[spec["name"]] = {
            "target_column": spec["target_col"],
            "baseline_column": spec["baseline_col"],
            "percent_scale": spec["percent_scale"],
            "alpha": spec["alpha"],
            "sample_count": int(mask.sum()),
            "baseline_mae": baseline_mae,
            "model_mae": model_mae,
            "weights": model["weights"].tolist(),
            "intercept": float(model["intercept"]),
            "feature_means": model["feature_means"].tolist(),
            "feature_stds": model["feature_stds"].tolist(),
        }
        metric_rows.append(
            {
                "target": spec["name"],
                "sample_count": int(mask.sum()),
                "baseline_mae": baseline_mae,
                "model_mae": model_mae,
            }
        )
    if not targets_output:
        raise RuntimeError("No targets produced (check dataset columns).")
    if args.preview:
        print_preview(metric_rows)
    dataset_lineage = {
        "artifacts": artifacts,
        "analyzer_sources": collect_source_metadata(
            df, "analyzer_source_file", legacy_alias="source_file"
        ),
        "spotify_sources": collect_source_metadata(df, "spotify_source_file"),
    }
    output = {
        "generated_at": dt.datetime.utcnow().isoformat(),
        "feature_set_version": args.feature_set_version,
        "notes": args.notes,
        "datasets": [entry["path"] for entry in artifacts],
        "dataset_lineage": dataset_lineage,
        "feature_columns": feature_columns,
        "model_type": "ridge",
        "targets": targets_output,
    }
    output_path = args.output.expanduser()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as handle:
        json.dump(output, handle, indent=2)
    print(f"✅ Saved calibration models to {output_path}")


if __name__ == "__main__":
    main()
