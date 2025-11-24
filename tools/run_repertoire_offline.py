#!/usr/bin/env python3
"""
Offline repertoire harness for future agents.

What it does:
- Runs the repertoire preview set through the analysis pipeline entirely offline
  (no analyzer server), using the same processing code the GUI calls under
  --offline mode.
- Exports a timestamped CSV to csv/test_results_*.csv.
- Immediately scores against the manual truth file (csv/truth_repertoire_manual.csv)
  and appends a one-line summary to reports/repertoire_iterations.log.

How to run (self-contained):
    1) Execute:
           .venv/bin/python tools/run_repertoire_offline.py
       (or python tools/run_repertoire_offline.py if your system Python has deps).
    2) Outputs: csv/test_results_*.csv + appended reports/repertoire_iterations.log.

Optional flags:
    --preview-dir /path/to/previews   (default: ~/Documents/Git repo/Songwise 1/preview_samples_repertoire_90)
    --offline-workers 0               (0 = inline; >0 passes worker count into offline pipeline)
    --truth-csv path/to/truth.csv     (default: csv/truth_repertoire_manual.csv)
    --log-file path/to/log.log        (default: reports/repertoire_iterations.log)

Notes:
- This uses the same algorithms as the GUI/server, just without HTTP. It will be
  slower than the server-backed path because files are processed serially.
- The analysis script already injects REPO_ROOT into sys.path and applies the
  hann shim/tempfile decode for .m4a previews; keep it this way unless you need
  to customize the pipeline.
- The script will prefer .venv/bin/python if present; otherwise your system
  Python must have the project dependencies installed.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Offline repertoire analysis + accuracy scorer")
    parser.add_argument(
        "--preview-dir",
        type=str,
        default=str(Path.home() / "Documents" / "Git repo" / "Songwise 1" / "preview_samples_repertoire_90"),
        help="Directory containing repertoire preview .m4a files",
    )
    parser.add_argument(
        "--offline-workers",
        type=int,
        default=0,
        help="Worker count passed to offline pipeline (0=inline)",
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

    venv_python = repo_root / ".venv" / "bin" / "python"
    python_exec = venv_python if venv_python.exists() else Path(sys.executable)
    analyze_script = repo_root / "tools" / "analyze_repertoire_90.py"
    accuracy_script = repo_root / "analyze_repertoire_90_accuracy.py"

    run_started = time.time()
    print(f"▶️  Running offline analysis via {analyze_script}")
    analyze_cmd = [
        str(python_exec),
        str(analyze_script),
        "--offline",
        "--offline-workers",
        str(args.offline_workers),
        "--dir",
        str(preview_dir),
        "--csv-auto",
    ]
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
    print("✅ Offline run + accuracy completed")


if __name__ == "__main__":
    main()
