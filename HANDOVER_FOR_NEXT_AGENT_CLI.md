# Handover – CLI Repertoire Iterations & Backend Tweaks
_Date: 2025-11-20_

## What I did (this session)
- Added a repeatable CLI flow to run the 90-preview repertoire analysis and log accuracy:
  - `tools/run_repertoire_cli.sh` now defaults to **offline** mode (no HTTP server needed), runs analysis, then calls accuracy and appends to `reports/repertoire_iterations.log`.
  - `analyze_repertoire_90_accuracy.py` gained `--results` and `--log/--log-file`, defaults to index-aligned matching, and logs one-line summaries.
- Made `tools/analyze_repertoire_90.py` offline-capable:
  - Injects `REPO_ROOT` into `sys.path`.
  - Adds `--offline` (direct pipeline) and `--offline-workers`.
  - Applies the `hann` shim and calibration hooks inline; uses **tempfile** decoding so `audioread` can read `.m4a`.
- Tempo calibration/detection adjustments for previews:
  - Alias scoring now weights detector agreement/PLP higher on short clips and softens octave priors for >180 BPM.
  - Extended octave validator thresholds tuned for previews; BPM calibration is **skipped for short clips** to avoid 144→137 drift.
- Server bootstrap hardening:
  - `backend/analyze_server.py` disables Flask dotenv/banner noise, redirects stdio to a cache log, and sets `FLASK_SKIP_DOTENV=1`.
  - Sandbox still blocks binding (`Operation not permitted`), so iterations were run offline.

## Iterations run (offline, direct pipeline)
1) Baseline offline harness fixed (decode/tempfile + hann).  
2) Initial accuracy ~16% overall (nan failures fixed).  
3) After temp decode + hann + calibration skip: **BPM 39/90 (43.3%), Key 27/90 (30.0%), Overall 36.7%** → `csv/test_results_20251120_182037.csv`.  
4) Aggressive mid-tempo octave expansion regressed to ~34% overall (csv/test_results_20251120_184301.csv).  
5) Tuned thresholds back (less aggressive): **BPM 36/90 (40.0%), Key 27/90 (30.0%), Overall 35.0%** (same file).  
Logs: `reports/repertoire_iterations.log` (appended each run).

## Key files touched
- `tools/run_repertoire_cli.sh` (offline default runner + logging)
- `tools/analyze_repertoire_90.py` (offline analysis, temp decode, hann shim)
- `analyze_repertoire_90_accuracy.py` (index alignment + logging)
- `backend/analysis/tempo_detection.py` (preview-weighted alias scoring, octave validation tuning)
- `backend/analysis/calibration.py` (skip BPM calibration on short clips)
- `backend/analyze_server.py` (Flask dotenv/banner disabled, stdio redirect)

## Outstanding issues / next steps
- BPM still has ~7 clear octave errors (heart-shaped box, back in black, etc.) and many high/low off-by-40+ cases; need better half/double disambiguation without hurting mid-range.
- Key stuck ~30%: dominant/tonic confusion (fifths) and mode errors remain; revisit short-clip tonic bias and mode vote thresholds in `key_detection.py`.
- Offline runs use `analyse_pipeline` inline; HTTP server could not bind due to sandbox restrictions. If you need GUI integration, start the server outside the sandbox or restore header-based run.
- Recent best CSV: `csv/test_results_20251120_182037.csv` (higher BPM, same key); last run CSV: `csv/test_results_20251120_184301.csv` (slightly lower BPM, same key).

## How to rerun (offline, recommended)
```bash
./tools/run_repertoire_cli.sh
# writes csv/test_results_*.csv and appends to reports/repertoire_iterations.log
```
To target a specific results file for analysis only:
```bash
.venv/bin/python analyze_repertoire_90_accuracy.py --results csv/test_results_20251120_182037.csv --log
```

## Caveats
- Offline analysis uses `use_tempfile=True` to make `audioread` handle `.m4a` previews; keep that if you refactor.
- HTML/GUI paths were not retested; changes are all CLI/backend.
- Calibration is skipped for BPM on short clips—if you re-enable, watch for 144→137 regressions.
