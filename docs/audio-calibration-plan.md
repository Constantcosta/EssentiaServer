## Audio Metric Calibration Plan

### Analyzer Runtime Knobs
- See `docs/analysis-config.md` for the authoritative list of env variables the analyzer reads (FFT size, chunk behavior, Essentia toggles, worker counts, etc.).  
- When running GUI sweeps, sync those knobs with the run notes so calibration exports tell us exactly which config generated the dataset.  
- Remember you can skip heavy chunk passes via the `X-Skip-Chunk-Analysis: 1` header during large backfills when stability isn’t the focus.

### 1. Build Paired Dataset
- Export analyzer CSV after every algorithm change (`/cache/export` endpoint).  
- The macOS calibration tab now forces re-analysis via `X-Force-Reanalyze: 1`, so you can leave your problem tracks staged without clearing the cache between builds.  
- Calibration runs now target `X-Cache-Namespace: calibration` and call `/cache/clear?namespace=calibration` before each sweep, so they never touch the main cache; mirror that header/query combo in CLI scripts when reproducing the workflow outside the Mac app.  
- Normalize song + artist names, join with Spotify metrics (`csv/spotify metrics.csv`), and persist merged rows (e.g., `data/calibration/YYYYMMDD.parquet`).  
- Track metadata for each sample: analyzer build SHA, feature set version, Spotify snapshot date, notes on anomalies.

### 2. Baseline Calibration Layer
- Fit per-feature linear scalers using the paired dataset (`y = ax + b`) for BPM, Danceability, Energy, Acousticness, Valence, Loudness.  
- Store coefficients in a JSON config (loaded by both backend and client) so we can update without redeploying the analyzer.  
- Apply calibration immediately after analysis, before caching/exporting results. Log pre/post values for tracing.

#### Current Implementation
- Run `python3 tools/fit_calibration_scalers.py --dataset data/calibration/<latest>.parquet --output config/calibration_scalers.json --feature-set-version v1 --notes "sweep-id"` to train the scalers. The CLI normalizes percent-based columns to 0‑1 before solving `y = ax + b`, reports R²/MAE for each feature, and writes the shared JSON.
- `config/calibration_scalers.json` (tracked in git) currently contains slopes/intercepts for BPM, Danceability, Energy, Acousticness, Valence, and Loudness using the Nov‑12 GUI sweep.
- `backend/analyze_server.py` now loads this file on startup and applies the calibration layer to the in-memory analysis results (and therefore cache/exports) with a single log entry per track showing pre/post values.

### 3. Enrich Feature Extraction
- Enable Essentia high-level descriptors (dynamic complexity, tonal strength, spectral complexity) and expose them in `analysis_result`.  
- Add Madmom/librosa hybrid rhythm extraction: multi-pass beat tracking (harmonic/percussive stems), onset variance, section repetition.  
- Capture additional cues: zero-crossing rate, spectral flux, HPSS energy ratios, silence ratio per section.

#### Current Implementation
- `backend/analyze_server.py` now computes **dynamic complexity**, **tonal strength**, and **spectral complexity** via Essentia (with librosa fallbacks) plus new cues: zero-crossing rate, spectral flux, and harmonic/percussive energy ratios. All values ship in every API response, are cached, show up in `/cache`/`/cache/search`, and export inside the CSV builder so calibration datasets can lean on them.
- The SQLite cache schema/exports include the new columns automatically, so rerunning the Mac app’s **Export Cache** button will surface them without extra work.

### 4. Improve Chunk Consensus
- Use tempo-aware windows (e.g., 8-beat slices) instead of fixed durations; derive hop length from BPM.  
- Weight chunk summaries by local energy so choruses have more influence than quiet verses.  
- Surface chunk diagnostics in exports (effective window length, weighted variance) for debugging.

#### Current Implementation
- Chunk windows now scale with tempo (default 8 beats, clamped between existing min/max durations) and hop sizes follow the same derived window, so fast tracks get shorter slices without sacrificing overlap (`backend/analyze_server.py:_chunk_parameters`).
- Every chunk summary carries an `energy_weight`, and the consensus step computes weighted means/variances (logged via `chunk_analysis.diagnostics`) before blending back into the global metrics.
- `/cache`, `/cache/search`, and `/cache/export` expose the new diagnostics—CSV exports include the effective window/hop plus the BPM weighted std so calibration datasets can factor in window jitter.

### 5. Train Lightweight Models
- With enriched features, train shallow regressors (ridge, gradient boosting) that map feature vectors → Spotify targets.  
- Use k-fold validation on the paired dataset and compare MAE against linear scaling.  
- Keep model weights in versioned artifacts (`models/calibration_v1.json`), and add inference code to the analyzer if they outperform scalers.

#### Current Implementation
- Run `python3 tools/train_calibration_models.py --dataset data/calibration/<file>.parquet --feature-set-version v1 --notes "tag" --preview` to train ridge models using all available analyzer features (including the new Essentia descriptors). The script writes `models/calibration_models.json` with weights, scaling stats, and MAE deltas.
- `backend/analyze_server.py` automatically loads that file on startup (if present) and applies the learned predictions after the linear scaler layer. Missing models simply fall back to the scaler coefficients, so deployments can roll back by deleting/renaming the models file.

### 6. Instrumentation & Regression Checks
- Extend the comparison script to compute mean absolute deltas per feature for old vs. new exports; store history in `reports/calibration_metrics.csv`.  
- Add a CLI task (e.g., `make validate-calibration`) that fails when MAE increases beyond a tolerance.  
- Hook validation into CI or a pre-release checklist so every build shows whether accuracy improved or regressed.

#### Current Implementation
- `python3 tools/validate_calibration.py --dataset data/calibration/<file>.parquet --tag <label> [--max-mae feature=value] --preview` computes raw vs. calibrated MAE for every feature in the dataset, appends a row to `reports/calibration_metrics.csv`, and optionally enforces per-feature tolerances.
- `make validate-calibration DATASET=data/calibration/<file>.parquet TAG=<label>` wraps the script with sensible default thresholds (bpm ≤4, dance ≤0.12, energy ≤0.15, acousticness ≤0.10, valence ≤0.15, loudness ≤2.5) and prints the comparison table so we can drop it into CI.
- The first two runs (sweep-20251112 + ci-demo) are already stored in `reports/calibration_metrics.csv`, giving us a seed history to compare against future analyzer builds.

### Calibration Dataset Builder (Initial Implementation)
- CLI **`python3 tools/build_calibration_dataset.py`** joins one or more analyzer cache exports with `csv/spotify metrics.csv`, normalizing `song + artist` keys and deduplicating collisions by latest analysis / highest Spotify popularity.  
- Writes a Parquet artifact under `data/calibration/` (timestamped by default) and stamps every row with `analyzer_build_sha`, `feature_set_version`, `spotify_snapshot_date`, `notes`, and `dataset_created_at`.  
- Important flags: `--analyzer-export` (repeatable), `--spotify-metrics` (override path), `--output` or `--output-dir`, `--feature-set-version`, `--analyzer-build-sha`, `--spotify-snapshot-date`, `--notes`, and `--dry-run`.  
- The builder now asserts that **every** Spotify reference row is present in the analyzer exports; missing coverage raises immediately (use `--allow-missing` only for ad-hoc, partial checks).  
- Important flags: `--analyzer-export` (repeatable), `--spotify-metrics` (repeatable; pass multiple CSV files like `csv/spotify metrics.csv` + `csv/spotify 2.csv`), `--output` or `--output-dir`, `--feature-set-version`, `--analyzer-build-sha`, `--spotify-snapshot-date`, `--notes`, and `--dry-run`.  
- Example:  
  ```bash
  python3 tools/build_calibration_dataset.py \
    --analyzer-export csv/cache_export_20251112_150927.csv \
    --analyzer-export csv/cache_export_20251112_150700.csv \
    --spotify-metrics "csv/spotify metrics.csv" \
    --feature-set-version v0.3 \
    --notes "post-danceability tweak" 
  ```
- A merged list of every calibration reference lives in `csv/spotify_calibration_master.csv` (generated from `spotify metrics.csv` + `spotify 2.csv`) so the Mac app has a single source of truth when staging folders of tracks.

### Mac App Calibration Tab
- The macOS control panel now has a **Calibration** tab: add up to 57 reference songs once (they’re copied into `~/Library/Application Support/MacStudioServerSimulator/CalibrationSongs`) and reuse them for every analyzer build.
- The **Run Calibration Sweep** button will auto-start the local analyzer if needed, analyze each staged song, generate a fresh CSV export, and invoke `tools/build_calibration_dataset.py` against `csv/spotify metrics.csv`.
- Live log output shows analysis status, export path, and builder logs; the latest Parquet artifact is saved under `data/calibration/mac_gui_calibration_*.parquet` and can be opened from the UI.
- Feature-set version + notes fields are persisted via `@AppStorage`, so you can stamp every run (e.g., `v1.1-hotfix`, “tempo-consensus tweak”) without touching Terminal.
- Use the new **Import Folder…** button (macOS only) to point the app at a folder of source tracks; it will import supported audio files (m4a/mp3/wav/aiff/flac/aac/caf) until the 57-slot deck is full.

### Reset & Targeted Mini-Runs
- When you want to re-run calibration with a smaller ad-hoc playlist, clear the Mac app’s sandbox with `python3 tools/reset_calibration_run.py --run-label mini` (add `--include-exports` to archive the generated CSVs as well). The script moves `CalibrationSongs/` + `calibration_songs.json` into `~/Library/Application Support/MacStudioServerSimulator/CalibrationRuns/<timestamp>_<label>/` and recreates empty folders so the UI starts at 0 staged songs on the next launch.
- Relaunch the MacStudioServerSimulator app, drag in the handful of tunes you want to test, and hit **Run Calibration Sweep**. The builder will emit a single Parquet file under `data/calibration/mac_gui_calibration_<timestamp>.parquet` that only contains this run’s songs.
- To compare just that subset against Spotify, run `python3 tools/compare_calibration_subset.py --dataset data/calibration/mac_gui_calibration_<timestamp>.parquet [--titles-file runlist.txt]`. The CLI prints exact-match percentages plus the root-offset histogram and sample mismatches so you can see how the mini-sweep stacks up before touching the larger 54-track dataset.
