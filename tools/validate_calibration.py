#!/usr/bin/env python3
"""Validate analyzer calibration against Spotify reference metrics."""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
from collections import Counter
from pathlib import Path
import sys
from typing import Dict, Iterable, List, Optional, Tuple

import numpy as np
import pandas as pd
REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.append(str(REPO_ROOT))

from tools.calibration_specs import FEATURE_SPECS
from tools.key_utils import canonical_key_id, normalize_key_label

DEFAULT_CONFIG = REPO_ROOT / "config" / "calibration_scalers.json"
DEFAULT_REPORT = REPO_ROOT / "reports" / "calibration_metrics.csv"
DEFAULT_KEY_CALIBRATION = REPO_ROOT / "config" / "key_calibration.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compare analyzer metrics against Spotify targets.")
    parser.add_argument(
        "--dataset",
        dest="datasets",
        action="append",
        required=True,
        help="Calibration parquet dataset (repeatable).",
    )
    parser.add_argument(
        "--calibration-config",
        type=Path,
        default=DEFAULT_CONFIG,
        help=f"Calibration JSON path (default: {DEFAULT_CONFIG})",
    )
    parser.add_argument(
        "--report",
        type=Path,
        default=DEFAULT_REPORT,
        help=f"CSV report output (default: {DEFAULT_REPORT})",
    )
    parser.add_argument(
        "--tag",
        default="",
        help="Run tag (e.g., analyzer build SHA).",
    )
    parser.add_argument(
        "--min-samples",
        type=int,
        default=4,
        help="Minimum rows required per feature to compute metrics.",
    )
    parser.add_argument(
        "--preview",
        action="store_true",
        help="Print metrics to stdout before writing the report.",
    )
    parser.add_argument(
        "--max-mae",
        dest="max_mae",
        action="append",
        help="Per-feature calibrated MAE thresholds (e.g., --max-mae energy=0.15).",
    )
    parser.add_argument(
        "--skip-report",
        action="store_true",
        help="Skip writing the CSV report (useful for CI).",
    )
    parser.add_argument(
        "--drift-baseline",
        dest="drift_baselines",
        action="append",
        help="Baseline dataset(s) for Kolmogorov-Smirnov drift checks.",
    )
    parser.add_argument(
        "--drift-columns",
        nargs="*",
        help="Explicit dataset columns to check for drift. Defaults to analyzer feature sources.",
    )
    parser.add_argument(
        "--max-drift",
        type=float,
        default=0.4,
        help="Maximum KS statistic allowed before failing drift checks (default: 0.4).",
    )
    parser.add_argument(
        "--key-calibration-config",
        type=Path,
        default=DEFAULT_KEY_CALIBRATION,
        help=f"Key calibration JSON path (default: {DEFAULT_KEY_CALIBRATION}).",
    )
    parser.add_argument(
        "--min-key-accuracy",
        type=float,
        help="Fail if (calibrated) key accuracy falls below this fraction (0-1).",
    )
    parser.add_argument(
        "--key-report",
        action="store_true",
        help="Print key accuracy summary.",
    )
    return parser.parse_args()


def load_datasets(paths: Iterable[str]) -> Tuple[pd.DataFrame, List[str]]:
    frames: List[pd.DataFrame] = []
    resolved: List[str] = []
    for path in paths:
        expanded = Path(path).expanduser()
        if not expanded.exists():
            raise FileNotFoundError(f"Dataset not found: {expanded}")
        frames.append(pd.read_parquet(expanded))
        resolved.append(str(expanded))
    return pd.concat(frames, ignore_index=True), resolved


def load_calibration_rules(path: Path) -> Tuple[Dict[str, Dict[str, float]], Dict[str, Optional[str]]]:
    expanded = path.expanduser()
    if not expanded.exists():
        return {}, {}
    with open(expanded, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    metadata = {
        "feature_set_version": data.get("feature_set_version"),
        "calibration_generated_at": data.get("generated_at"),
        "calibration_notes": data.get("notes"),
    }
    return data.get("features", {}), metadata


def clamp(value: float, min_val: Optional[float], max_val: Optional[float]) -> float:
    if min_val is not None:
        value = max(min_val, value)
    if max_val is not None:
        value = min(max_val, value)
    return value


def parse_thresholds(values: Optional[List[str]]) -> Dict[str, float]:
    thresholds: Dict[str, float] = {}
    if not values:
        return thresholds
    for item in values:
        if "=" not in item:
            raise ValueError(f"Invalid --max-mae entry (expected feature=value): {item}")
        feature, raw_value = item.split("=", 1)
        feature = feature.strip().lower()
        try:
            thresholds[feature] = float(raw_value)
        except ValueError as exc:
            raise ValueError(f"Invalid numeric value for --max-mae {item}") from exc
    return thresholds


def default_drift_columns() -> List[str]:
    return sorted({spec.source_col for spec in FEATURE_SPECS})


def compute_ks_statistic(sample_a: np.ndarray, sample_b: np.ndarray) -> float:
    merged = np.concatenate([sample_a, sample_b])
    if merged.size == 0:
        return 0.0
    sample_a_sorted = np.sort(sample_a)
    sample_b_sorted = np.sort(sample_b)
    merged_sorted = np.sort(merged)
    cdf_a = np.searchsorted(sample_a_sorted, merged_sorted, side="right") / sample_a_sorted.size
    cdf_b = np.searchsorted(sample_b_sorted, merged_sorted, side="right") / sample_b_sorted.size
    return float(np.max(np.abs(cdf_a - cdf_b)))


def compute_drift(
    current_df: pd.DataFrame,
    baseline_df: pd.DataFrame,
    columns: Iterable[str],
    min_samples: int = 12,
) -> List[Dict[str, object]]:
    results: List[Dict[str, object]] = []
    for column in columns:
        current_series = pd.to_numeric(current_df.get(column), errors="coerce").dropna()
        baseline_series = pd.to_numeric(baseline_df.get(column), errors="coerce").dropna()
        if len(current_series) < min_samples or len(baseline_series) < min_samples:
            continue
        statistic = compute_ks_statistic(current_series.to_numpy(dtype=float), baseline_series.to_numpy(dtype=float))
        results.append(
            {
                "column": column,
                "ks_statistic": statistic,
                "current_samples": int(len(current_series)),
                "baseline_samples": int(len(baseline_series)),
            }
        )
    return results


def print_drift_summary(entries: List[Dict[str, object]]) -> None:
    header = f"{'Column':<28}{'Cur N':>8}{'Base N':>8}{'KS Stat':>10}"
    print(header)
    print("-" * len(header))
    for entry in entries:
        print(
            f"{entry['column']:<28}"
            f"{entry['current_samples']:>8}"
            f"{entry['baseline_samples']:>8}"
            f"{entry['ks_statistic']:>10.3f}"
        )


def load_key_calibration_rules(path: Optional[Path]) -> Dict[str, object]:
    if not path:
        return {}
    expanded = path.expanduser()
    if not expanded.exists():
        return {}
    with open(expanded, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    return data.get("keys", {})


def compute_key_metrics(
    df: pd.DataFrame, calibration_rules: Optional[Dict[str, object]] = None
) -> Optional[Dict[str, object]]:
    if "analyzer_key" not in df.columns or "spotify_key" not in df.columns:
        return None
    records = []
    for row in df.itertuples():
        analyzer = normalize_key_label(getattr(row, "analyzer_key", None))
        target = normalize_key_label(getattr(row, "spotify_key", None))
        if not analyzer or not target:
            continue
        analyzer_id = canonical_key_id(*analyzer)
        target_id = canonical_key_id(*target)
        calibrated_id = None
        if calibration_rules:
            entry = calibration_rules.get(analyzer_id)
            if entry:
                targets = entry.get("targets") or []
                if targets:
                    calibrated_id = targets[0].get("canonical", analyzer_id)
        records.append(
            {
                "analyzer_id": analyzer_id,
                "target_id": target_id,
                "calibrated_id": calibrated_id or analyzer_id,
                "analyzer_root": analyzer[0],
                "target_root": target[0],
                "analyzer_mode": analyzer[1],
                "target_mode": target[1],
            }
        )
    total = len(records)
    if not total:
        return None
    raw_accuracy = sum(1 for r in records if r["analyzer_id"] == r["target_id"]) / total
    calibrated_accuracy = (
        sum(1 for r in records if r["calibrated_id"] == r["target_id"]) / total
        if calibration_rules
        else None
    )
    mode_accuracy = sum(1 for r in records if r["analyzer_mode"] == r["target_mode"]) / total
    offsets = Counter(((r["target_root"] - r["analyzer_root"]) % 12) for r in records)
    confusion_counts = Counter(
        (r["analyzer_id"], r["target_id"])
        for r in records
        if r["analyzer_id"] != r["target_id"]
    )
    return {
        "samples": total,
        "raw_accuracy": raw_accuracy,
        "calibrated_accuracy": calibrated_accuracy,
        "mode_accuracy": mode_accuracy,
        "root_offsets": offsets.most_common(),
        "confusions": confusion_counts.most_common(5),
    }


def print_key_metrics(metrics: Dict[str, object]) -> None:
    print(f"Samples: {metrics['samples']}")
    print(f"Raw accuracy: {metrics['raw_accuracy']:.3f}")
    if metrics.get("calibrated_accuracy") is not None:
        print(f"Calibrated accuracy: {metrics['calibrated_accuracy']:.3f}")
    print(f"Mode accuracy: {metrics['mode_accuracy']:.3f}")
    offsets = metrics.get("root_offsets") or []
    if offsets:
        print("Top root offsets (semitones): " + ", ".join(f"{off}:{cnt}" for off, cnt in offsets[:5]))
    confusions = metrics.get("confusions") or []
    if confusions:
        print("Top key confusions:")
        for (analyzer_id, target_id), count in confusions:
            print(f"  {analyzer_id} → {target_id}: {count}")


def compute_feature_metrics(df: pd.DataFrame, feature_name: str, rules: Dict[str, Dict[str, float]], min_samples: int):
    spec = next((s for s in FEATURE_SPECS if s.name == feature_name), None)
    if spec is None:
        return None
    x = pd.to_numeric(df.get(spec.source_col), errors="coerce")
    y = pd.to_numeric(df.get(spec.target_col), errors="coerce")
    mask = x.notna() & y.notna()
    x = x[mask]
    y = y[mask]
    if len(x) < min_samples:
        return None
    x_vals = x.astype(float).to_numpy()
    y_vals = y.astype(float).to_numpy()
    if spec.percent_scale:
        x_vals = x_vals / 100.0
        y_vals = y_vals / 100.0
    raw_mae = float(np.mean(np.abs(x_vals - y_vals)))
    calibrated_mae = None
    rule = rules.get(feature_name)
    if rule:
        slope = rule.get("slope")
        intercept = rule.get("intercept")
        if slope is not None and intercept is not None:
            preds = (x_vals * slope) + intercept
            clamp_cfg = rule.get("clamp") or {}
            preds = np.array([clamp(val, clamp_cfg.get("min"), clamp_cfg.get("max")) for val in preds])
            calibrated_mae = float(np.mean(np.abs(preds - y_vals)))
    return {
        "feature": feature_name,
        "sample_count": int(len(x_vals)),
        "raw_mae": raw_mae,
        "calibrated_mae": calibrated_mae,
    }


def print_preview(metrics: List[Dict[str, object]]):
    header = f"{'Feature':<14}{'Samples':>10}{'Raw MAE':>12}{'Cal MAE':>12}{'Δ':>10}"
    print(header)
    print("-" * len(header))
    for entry in metrics:
        cal = entry.get("calibrated_mae")
        delta = "" if cal is None else f"{entry['raw_mae'] - cal:+.4f}"
        cal_str = "--" if cal is None else f"{cal:.4f}"
        print(f"{entry['feature']:<14}{entry['sample_count']:>10}{entry['raw_mae']:>12.4f}{cal_str:>12}{delta:>10}")


def append_report(report_path: Path, metadata: Dict[str, str], metrics: List[Dict[str, object]]) -> None:
    fieldnames = [
        "timestamp",
        "datasets",
        "tag",
        "feature_set_version",
        "calibration_generated_at",
        "calibration_notes",
    ]
    for entry in metrics:
        feature = entry["feature"]
        fieldnames.append(f"raw_mae_{feature}")
        fieldnames.append(f"cal_mae_{feature}")
    row = {
        "timestamp": dt.datetime.utcnow().isoformat(),
        "datasets": metadata.get("datasets", ""),
        "tag": metadata.get("tag", ""),
        "feature_set_version": metadata.get("feature_set_version", ""),
        "calibration_generated_at": metadata.get("calibration_generated_at", ""),
        "calibration_notes": metadata.get("calibration_notes", ""),
    }
    for entry in metrics:
        feature = entry["feature"]
        row[f"raw_mae_{feature}"] = f"{entry['raw_mae']:.6f}"
        cal = entry.get("calibrated_mae")
        row[f"cal_mae_{feature}"] = "" if cal is None else f"{cal:.6f}"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    file_exists = report_path.exists()
    with open(report_path, "a", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        if not file_exists:
            writer.writeheader()
        writer.writerow(row)


def main() -> None:
    args = parse_args()
    df, datasets = load_datasets(args.datasets)
    rules, config_meta = load_calibration_rules(args.calibration_config) if args.calibration_config else ({}, {})
    thresholds = parse_thresholds(args.max_mae)
    key_rules = load_key_calibration_rules(args.key_calibration_config) if args.key_calibration_config else {}
    key_report_needed = args.key_report or args.min_key_accuracy is not None
    key_metrics = compute_key_metrics(df, key_rules if key_rules else None) if key_report_needed else None
    drift_results: List[Dict[str, object]] = []
    if args.drift_baselines:
        baseline_df, _ = load_datasets(args.drift_baselines)
        drift_columns = args.drift_columns or default_drift_columns()
        drift_results = compute_drift(df, baseline_df, drift_columns)
    metrics: List[Dict[str, object]] = []
    for spec in FEATURE_SPECS:
        entry = compute_feature_metrics(df, spec.name, rules, args.min_samples)
        if entry:
            metrics.append(entry)
    if not metrics:
        raise RuntimeError("No feature metrics computed (insufficient data).")
    mae_violations: List[Tuple[str, float, float]] = []
    for entry in metrics:
        feature = entry["feature"].lower()
        threshold = thresholds.get(feature)
        if threshold is None:
            continue
        value = entry.get("calibrated_mae") or entry.get("raw_mae")
        if value is not None and value > threshold:
            mae_violations.append((feature, value, threshold))
    drift_violations: List[Dict[str, object]] = []
    if drift_results and args.max_drift is not None:
        drift_violations = [entry for entry in drift_results if entry["ks_statistic"] > args.max_drift]
    if args.preview:
        print_preview(metrics)
        if drift_results:
            print("\nDistribution Drift (KS)")
            print_drift_summary(drift_results)
        if key_metrics:
            print("\nKey Accuracy")
            print_key_metrics(key_metrics)
    elif drift_violations:
        # Always show drift context when we are about to fail CI.
        print("Distribution Drift (KS)")
        print_drift_summary(drift_results)
    elif args.key_report and key_metrics:
        print("\nKey Accuracy")
        print_key_metrics(key_metrics)
    metadata = {
        "datasets": ";".join(datasets),
        "tag": args.tag,
        "feature_set_version": (config_meta or {}).get("feature_set_version", ""),
        "calibration_generated_at": (config_meta or {}).get("calibration_generated_at", ""),
        "calibration_notes": (config_meta or {}).get("calibration_notes", ""),
    }
    if not args.skip_report:
        append_report(args.report, metadata, metrics)
        print(f"✅ Wrote metrics for {len(metrics)} features to {args.report}")
    else:
        print(f"✅ Computed metrics for {len(metrics)} features (report skipped).")
    failure_messages: List[str] = []
    if mae_violations:
        details = ", ".join(f"{feat} {value:.4f} > {threshold:.4f}" for feat, value, threshold in mae_violations)
        failure_messages.append(f"MAE thresholds exceeded: {details}")
    if drift_violations:
        details = ", ".join(
            f"{entry['column']} {entry['ks_statistic']:.3f} (limit {args.max_drift:.3f})" for entry in drift_violations
        )
        failure_messages.append(f"Distribution drift detected: {details}")
    if args.min_key_accuracy is not None:
        if not key_metrics:
            failure_messages.append("Key accuracy threshold set but key metrics unavailable.")
        else:
            baseline_accuracy = (
                key_metrics.get("calibrated_accuracy")
                if key_metrics.get("calibrated_accuracy") is not None and key_rules
                else key_metrics.get("raw_accuracy")
            ) or 0.0
            if baseline_accuracy < args.min_key_accuracy:
                failure_messages.append(
                    f"Key accuracy {baseline_accuracy:.3f} < {args.min_key_accuracy:.3f}"
                )
    if failure_messages:
        raise SystemExit("❌ " + " | ".join(failure_messages))


if __name__ == "__main__":
    main()
