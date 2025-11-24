#!/usr/bin/env python3
"""
Online repertoire harness (server-backed) for faster iterations.

What it does:
- Calls analyze_repertoire_90.py in ONLINE mode (HTTP to analyzer server) to
  process the preview set. This uses the server's worker pool and restart logic,
  so it's faster than offline single-process.
- Exports a timestamped CSV to csv/test_results_*.csv.
- Scores that CSV against the manual truth file (csv/truth_repertoire_manual.csv)
  and appends a one-line summary to reports/repertoire_iterations.log.

How to run (self-contained):
    1) Ensure analyzer server is running (e.g., ./start_server_optimized.sh).
    2) Execute:
           .venv/bin/python tools/run_repertoire_online.py
       (or python tools/run_repertoire_online.py if your system Python has deps).
    3) Outputs: csv/test_results_*.csv + appended reports/repertoire_iterations.log.

Flags:
    --preview-dir /path/to/previews   (default: ~/Documents/Git repo/Songwise 1/preview_samples_repertoire_90)
    --url http://127.0.0.1:5050       (analyzer server base URL)
    --allow-cache                     (reuse cached analyses; default forces re-analysis)
    --truth-csv path/to/truth.csv     (default: csv/truth_repertoire_manual.csv)
    --log-file path/to/log.log        (default: reports/repertoire_iterations.log)

Notes:
- This prefers .venv/bin/python; if absent, falls back to the current Python
  (must have project dependencies installed).
- If the health check to /health fails, start the server first (see start_server_optimized.sh).
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

import json
import urllib.request
import urllib.error


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Online (server-backed) repertoire analysis + accuracy scorer")
    parser.add_argument(
        "--preview-dir",
        type=str,
        default=str(Path.home() / "Documents" / "Git repo" / "Songwise 1" / "preview_samples_repertoire_90"),
        help="Directory containing repertoire preview .m4a files",
    )
    parser.add_argument(
        "--url",
        type=str,
        default="http://127.0.0.1:5050",
        help="Analyzer server base URL",
    )
    parser.add_argument(
        "--allow-cache",
        action="store_true",
        help="Allow cached analysis responses (default: force re-analysis)",
    )
    parser.add_argument(
        "--truth-csv",
        type=str,
        default="csv/truth_repertoire_manual.csv",
        help="Ground truth CSV to score against",
    )
    parser.add_argument(
        "--log-file",
        type=str,
        default="reports/repertoire_iterations.log",
        help="Append accuracy summary here",
    )
    return parser.parse_args()


def health_check(base_url: str) -> bool:
    try:
        with urllib.request.urlopen(f"{base_url}/health", timeout=3) as resp:
            if resp.status != 200:
                return False
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("status") == "healthy"
    except Exception:
        return False


def find_latest_results(csv_dir: Path, since_epoch: float) -> Path | None:
    candidates = [
        p for p in csv_dir.glob("test_results_*.csv")
        if p.is_file() and p.stat().st_mtime >= since_epoch - 1.0
    ]
    if not candidates:
        candidates = list(csv_dir.glob("test_results_*.csv"))
    return max(candidates, key=lambda p: p.stat().st_mtime) if candidates else None


def main() -> None:
    args = parse_args()
    repo_root = Path(__file__).resolve().parent.parent
    csv_dir = repo_root / "csv"

    preview_dir = Path(args.preview_dir).expanduser()
    if not preview_dir.exists():
        raise SystemExit(f"❌ Preview directory not found: {preview_dir}")

    truth_csv = Path(args.truth_csv)
    if not truth_csv.is_absolute():
        truth_csv = repo_root / truth_csv
    if not truth_csv.exists():
        raise SystemExit(f"❌ Truth CSV not found: {truth_csv}")

    log_file = Path(args.log_file)
    if not log_file.is_absolute():
        log_file = repo_root / log_file
    log_file.parent.mkdir(parents=True, exist_ok=True)

    if not health_check(args.url):
        raise SystemExit(f"❌ Analyzer server is not healthy at {args.url}. Start it (e.g., ./start_server_optimized.sh) and retry.")

    venv_python = repo_root / ".venv" / "bin" / "python"
    python_exec = venv_python if venv_python.exists() else Path(sys.executable)
    analyze_script = repo_root / "tools" / "analyze_repertoire_90.py"
    accuracy_script = repo_root / "analyze_repertoire_90_accuracy.py"

    run_started = time.time()
    print(f"▶️  Running online analysis via {analyze_script} against {args.url}")
    analyze_cmd = [
        str(python_exec),
        str(analyze_script),
        "--dir",
        str(preview_dir),
        "--csv-auto",
        "--url",
        args.url,
    ]
    if args.allow_cache:
        analyze_cmd.append("--allow-cache")
    subprocess.run(analyze_cmd, check=True, cwd=repo_root)

    latest_csv = find_latest_results(csv_dir, since_epoch=run_started)
    if latest_csv is None:
        raise SystemExit("❌ No test_results_*.csv found after analysis run.")

    print(f"▶️  Scoring results {latest_csv.name} against {truth_csv.name}")
    accuracy_cmd = [
        str(python_exec),
        str(accuracy_script),
        "--results",
        str(latest_csv),
        "--truth-csv",
        str(truth_csv),
        "--test-type",
        "repertoire-90",
        "--log",
        "--log-file",
        str(log_file),
    ]
    subprocess.run(accuracy_cmd, check=True, cwd=repo_root)
    print("✅ Online run + accuracy completed")


if __name__ == "__main__":
    main()
