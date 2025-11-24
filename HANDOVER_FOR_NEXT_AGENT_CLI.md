# Handover – Repertoire Iterations & Truth Set (80)
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
- `csv/truth_repertoire_manual.csv` (authoritative 80-track truth set; titles/artists normalized to the repertoire view)
- `csv/80_bpm_complete.csv` (source list used to build the 80-track truth)

## Outstanding issues / next steps
- BPM: still octave/double/half errors plus tempo-lock bands; need stronger half/double resolution (tempogram + onset/beat evidence) without midrange regressions.
- Key: stuck ~30%; dominant/relative confusion; revisit tonic bias/mode votes for previews in `key_detection.py`.
- Accuracy script still points to `csv/90 preview list.csv`; update it (or add a flag) to use `csv/truth_repertoire_manual.csv` for the 80-set comparison.
- Offline runs use `analyse_pipeline` inline; if GUI/server needed, run outside sandbox or re-enable server path.
- Recent best CSV (90-set): `csv/test_results_20251120_182037.csv`; last run: `csv/test_results_20251120_184301.csv`. No runs yet with the 80 truth.

## How to rerun (offline, recommended)
```bash
./tools/run_repertoire_cli.sh
# writes csv/test_results_*.csv and appends to reports/repertoire_iterations.log
```

### Standalone harnesses
- Offline (no server): `.venv/bin/python tools/run_repertoire_offline.py`  
  - Uses the online algorithms but runs them inline; slower but no server needed.
- Online (server-backed, faster): start the analyzer server, then run  
  `.venv/bin/python tools/run_repertoire_online.py`
To target a specific results file for analysis only:
```bash
.venv/bin/python analyze_repertoire_90_accuracy.py --results csv/test_results_20251120_182037.csv --log
```

## Plan for next agent
1) Update accuracy flow for the 80-set: point `analyze_repertoire_90_accuracy.py` (or a new flag) to `csv/truth_repertoire_manual.csv` instead of `csv/90 preview list.csv`.
2) Run offline analysis via `./tools/run_repertoire_cli.sh --offline` and score against the 80 truth; record BPM/Key deltas.
3) Tackle BPM octave/alias fixes in `backend/analysis/tempo_detection.py` (use tempogram stability + onset/beat evidence; penalize lock bands; handle 6/8/dotted cases).
4) Tweak key detection to reduce dominant/relative confusions on previews; then re-run and log.
5) Overhaul repertoire view to consume the new truth file for display/QA (ensure titles/artists match the normalized CSV).

## Quick tips for next agent
- Truth set: `csv/truth_repertoire_manual.csv` (80 entries, normalized titles/artists). Keep punctuation/accents (e.g., “Señorita”, quoted titles with commas, feat. info). It’s staged; do not overwrite.
- Accuracy: add a flag/default in `analyze_repertoire_90_accuracy.py` to read the 80-truth instead of `csv/90 preview list.csv`, then rerun accuracy on fresh offline results.
- Untracked: `csv/test_results_20251120_*.csv` only; no code changes pending besides this doc/truth file.
- BPM work: untouched this round—feel free to iterate on half/double resolution with tempogram/onset evidence; watch 6/8/dotted cases.

## Caveats
- Offline analysis uses `use_tempfile=True` to make `audioread` handle `.m4a` previews; keep that if you refactor.
- HTML/GUI paths were not retested; changes are all CLI/backend.
- Calibration is skipped for BPM on short clips—if you re-enable, watch for 144→137 regressions.
