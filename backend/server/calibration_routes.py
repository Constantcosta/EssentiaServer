"""Calibration management routes for the analysis server."""

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import Callable, List, Optional

from flask import Flask, jsonify, request


def _discover_calibration_datasets(repo_root: Path) -> List[str]:
    dataset_dir = repo_root / "data" / "calibration"
    if not dataset_dir.exists():
        return []
    return [str(path) for path in sorted(dataset_dir.glob("*.parquet"))]


def _resolve_dataset_paths(repo_root: Path, requested: Optional[List[str]]) -> List[str]:
    if requested:
        resolved = []
        for raw_path in requested:
            path = Path(raw_path)
            if not path.is_absolute():
                path = (repo_root / raw_path).resolve()
            resolved.append(str(path))
        return resolved
    return _discover_calibration_datasets(repo_root)


def register_calibration_routes(
    app: Flask,
    *,
    require_api_key,
    logger,
    repo_root: Path,
    key_calibration_path: Path,
    load_key_calibration: Callable[[], None],
):
    """Attach calibration management endpoints to the Flask app."""

    @app.route("/calibration/key", methods=["POST"])
    @require_api_key
    def refresh_key_calibration():
        """Fit the key calibration map from uploaded datasets without leaving the app."""
        payload = request.get_json(silent=True) or {}
        dataset_paths = _resolve_dataset_paths(repo_root, payload.get("datasets"))
        if not dataset_paths:
            return (
                jsonify(
                    {
                        "error": "no_datasets",
                        "message": "No calibration parquet files found under data/calibration/.",
                    }
                ),
                400,
            )
        notes = payload.get("notes", "")
        try:
            from tools import fit_key_calibration as key_calibration_tools  # type: ignore

            df, artifacts = key_calibration_tools.load_datasets(dataset_paths)
            calibration_entries, metrics = key_calibration_tools.compute_calibration(df)
        except Exception as exc:  # pragma: no cover - troubleshooting aid
            logger.exception("Key calibration fit failed.")
            return jsonify({"error": "calibration_failed", "message": str(exc)}), 500
        output = {
            "generated_at": datetime.utcnow().isoformat(),
            "notes": notes,
            "datasets": dataset_paths,
            "dataset_lineage": {"artifacts": artifacts},
            "sample_count": metrics.get("sample_count"),
            "raw_accuracy": metrics.get("raw_accuracy"),
            "calibrated_accuracy": metrics.get("calibrated_accuracy"),
            "confidence_bins": metrics.get("confidence_bins", []),
            "keys": calibration_entries,
        }
        try:
            with open(key_calibration_path, "w", encoding="utf-8") as handle:
                json.dump(output, handle, indent=2)
        except Exception as exc:  # pragma: no cover
            logger.exception("Failed to write key calibration file.")
            return jsonify({"error": "write_failed", "message": str(exc)}), 500
        load_key_calibration()
        return jsonify(
            {
                "status": "ok",
                "output_path": str(key_calibration_path),
                "datasets": dataset_paths,
                "sample_count": metrics.get("sample_count"),
                "raw_accuracy": metrics.get("raw_accuracy"),
                "calibrated_accuracy": metrics.get("calibrated_accuracy"),
            }
        )

    return app


__all__ = ["register_calibration_routes"]
