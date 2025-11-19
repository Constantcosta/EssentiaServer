#!/usr/bin/env python3
"""
Helper to locate the latest test result CSVs emitted by `run_test.sh`.
Designed for GUI integration: returns a JSON payload with paths to the
stable aliases and the most recent timestamped CSV + metadata.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, Optional

ROOT = Path(__file__).parent.parent
CSV_DIR = ROOT / "csv"


def _latest_timestamped() -> Optional[Path]:
    if not CSV_DIR.exists():
        return None
    files = sorted(CSV_DIR.glob("test_results_*.csv"), key=lambda p: p.stat().st_mtime, reverse=True)
    return files[0] if files else None


def _meta_for(alias: str) -> Optional[Dict]:
    meta_path = CSV_DIR / alias
    if not meta_path.exists():
        return None
    try:
        return json.loads(meta_path.read_text())
    except Exception:
        return None


def main():
    latest = _latest_timestamped()
    payload = {
        "timestamped_csv": str(latest) if latest else None,
        "aliases": {
            "c_latest_csv": str(CSV_DIR / "test_results_c_latest.csv"),
            "latest_csv": str(CSV_DIR / "test_results_latest.csv"),
            "c_latest_meta": str(CSV_DIR / "test_results_c_latest.meta.json"),
            "latest_meta": str(CSV_DIR / "test_results_latest.meta.json"),
        },
        "meta": {
            "c_latest": _meta_for("test_results_c_latest.meta.json"),
            "latest": _meta_for("test_results_latest.meta.json"),
        },
    }
    print(json.dumps(payload, indent=2))


if __name__ == "__main__":
    main()
