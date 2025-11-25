# Calibration Accuracy Handover – 2025‑11‑12 Export

This document captures the latest comparison between our analyzer export (`exports/cache_export_20251112_225553.csv`) and Spotify’s reference metrics, plus the concrete steps to tighten accuracy and keep regressions in check.

---

## 1. Current Snapshot

| Dataset | Analyzer Rows | Spotify Rows | Matches |
| --- | --- | --- | --- |
| `data/calibration/calibration_20251113_combo.parquet` | 54 | 55 (spotify metrics v1 + spotify 2) | 54 |
| `data/calibration/calibration_20251112_225553.parquet` | 54 | 55 (spotify metrics v1 + spotify 2) | 51 |

Validation results (`python3 tools/validate_calibration.py --dataset data/calibration/calibration_20251113_combo.parquet --tag combo-225553-005306 --preview --key-report --key-calibration-config config/key_calibration.json`):

| Feature | Raw MAE | Calibrated MAE | Threshold |
| --- | --- | --- | --- |
| BPM | 10.78 | **12.23** | 4.0 |
| Danceability | 0.144 | **0.119** | 0.12 |
| Energy | 0.225 | **0.193** | 0.15 |
| Acousticness | 0.288 | **0.192** | 0.12 |
| Valence | 0.237 | **0.203** | 0.15 |
| Loudness | 5.39 | **3.66** | 2.5 |

Calibrated MAEs are still above our guardrails (BPM regressed further), so we need to keep the remediation plan active. For reference, the older `calibration_20251112_225553.parquet` results remain in the history block below.

_Historical snapshot (`python3 tools/validate_calibration.py --dataset data/calibration/calibration_20251112_225553.parquet --tag sweep-225553 --preview`):_

| Feature | Raw MAE | Calibrated MAE | Threshold |
| --- | --- | --- | --- |
| BPM | 10.79 | **10.85** | 4.0 |
| Danceability | 0.149 | **0.162** | 0.12 |
| Energy | 0.226 | **0.214** | 0.15 |
| Acousticness | 0.291 | **0.199** | 0.12 |
| Valence | 0.238 | **0.207** | 0.15 |
| Loudness | 5.29 | **4.13** | 2.5 |

Key accuracy snapshot (`python3 tools/validate_calibration.py --dataset data/calibration/calibration_20251113_combo.parquet --tag combo-225553-005306 --preview --key-report --key-calibration-config config/key_calibration.json`):

- Raw accuracy: **33.3%** (18 / 54), calibrated: **51.9%**, mode baseline: **63.0%**.
- Dominant root offsets are still clustered at 0 (21 samples) and +5 semitones (9 samples), with additional leakage at +7/+8/+10, so the analyzer is routinely reporting the dominant/subdominant instead of the tonic.
- Analyzer confidence has little predictive power (≥12% confidence is still <50% precise), so UI/QA should continue to treat confidence as advisory until we retrain.

---

## 2. Immediate Remediation Plan

1. **Regenerate Linear Scalers**
   ```bash
   python3 tools/fit_calibration_scalers.py \
     --dataset data/calibration/calibration_20251113_combo.parquet \
     --output config/calibration_scalers.json \
     --feature-set-version v1 \
      --notes "combo-225553-005306"
   ```
   Restart the backend so `backend/analyze_server.py` reloads the JSON.

2. **Retrain Ridge Models**
   ```bash
   python3 tools/train_calibration_models.py \
     --dataset data/calibration/calibration_20251113_combo.parquet \
     --feature-set-version v1 \
     --notes "combo-225553-005306" \
     --preview
   ```
   This refreshes `models/calibration_models.json`, which the backend now consumes automatically after the scaler pass.

3. **Re‑validate**
   ```bash
   python3 tools/validate_calibration.py \
     --dataset data/calibration/calibration_20251113_combo.parquet \
     --tag post-refresh \
     --preview \
     --max-mae bpm=4 --max-mae danceability=0.12 \
     --max-mae energy=0.15 --max-mae acousticness=0.12 \
     --max-mae valence=0.15 --max-mae loudness=2.5
   ```
   Inspect `reports/calibration_metrics.csv` to ensure MAEs fall back below thresholds.

---

## 3. Deep-Dive & Robustness Work

- **Chunk Diagnostics** – The export now includes `Chunk Window (s)`, `Chunk Hop (s)`, and `Chunk BPM Weighted Std`. Filter rows with the largest BPM error to see if instability comes from high chunk variance; adjust `CHUNK_BEAT_TARGET` or other chunk params as needed and re-run exports for `problem songs`.
- **Full 57-Song Sweep** – Use the Mac app’s Calibration tab (now supports folder import + 57 slots) to re-run the full playlist and export a larger calibration dataset. Feed that into both scaler + model scripts for more balanced training data.
- **Iterate Quickly** – After every analyzer tweak, repeat the export → dataset → scalers/models → validation loop before cutting a new build. The Make target below makes it easy to wire into CI:
  ```bash
  make validate-calibration DATASET=data/calibration/calibration_20251113_combo.parquet TAG=$(git rev-parse --short HEAD)
  ```

---

## 4. Toolchain Reference

| Purpose | Command |
| --- | --- |
| Build calibration dataset | `python3 tools/build_calibration_dataset.py --analyzer-export <export>.csv --spotify-metrics "csv/spotify metrics.csv" --spotify-metrics "csv/spotify 2.csv" --output data/calibration/<name>.parquet` |
| Fit linear scalers | `python3 tools/fit_calibration_scalers.py --dataset data/calibration/<name>.parquet --output config/calibration_scalers.json --feature-set-version v1 --notes "tag"` |
| Train ridge models | `python3 tools/train_calibration_models.py --dataset data/calibration/<name>.parquet --feature-set-version v1 --notes "tag" --preview` |
| Fit key calibration | `POST /calibration/key` (auto-discovers `data/calibration/*.parquet`) or `python3 tools/fit_key_calibration.py --dataset …` |
| Validate MAE (CLI) | `python3 tools/validate_calibration.py --dataset data/calibration/<name>.parquet --tag <label> --preview --max-mae ...` |
| Validate MAE (Make target) | `make validate-calibration DATASET=data/calibration/<name>.parquet TAG=<label>` |

All artifacts (`config/calibration_scalers.json`, `models/calibration_models.json`, `reports/calibration_metrics.csv`) are versioned so we can diff them between releases.

---

## 5. Next Steps Checklist

- [ ] Re-run scalers + models on `calibration_20251113_combo.parquet` whenever exports change.
- [ ] Validate (`tools/validate_calibration.py` + `make validate-calibration`) against `calibration_20251113_combo.parquet` and confirm MAEs < thresholds.
- [ ] Re-export the 57-song deck via the Mac app (including the missing “You Oughta Know”, “You’re Still The One”, “You’ll Think Of Me” variants) and repeat the loop for an even richer dataset.
- [ ] Keep the validation commands in CI so future analyzer commits can’t land unless accuracy improves or holds steady.
- [ ] Close the key accuracy gap per §7 before merging analyzer changes that touch chroma, key consensus, or confidence logic.

Once these boxes are checked, we’ll have a tighter feedback loop between analyzer tweaks and Spotify parity, with Metrics history living under `reports/calibration_metrics.csv` for future audits.

## 6. Automation & Lineage Upgrades

- GitHub Actions now runs `tools/validate_calibration.py` (MAE guardrails + KS drift check) on every push/PR via `.github/workflows/calibration-validation.yml`, so regressions fail CI automatically.
- `tools/validate_calibration.py` gained `--skip-report` for CI and `--drift-baseline/--max-drift/--drift-columns` flags so we can gate distribution shifts before they skew MAE.
- `tools/fit_calibration_scalers.py` and `tools/train_calibration_models.py` embed full dataset lineage (parquet SHA256 + analyzer/Spotify source file hashes) plus health checks to ensure we only train on complete datasets.
- `tools/build_calibration_dataset.py` now writes `analyzer_source_file` and `spotify_source_file` columns, powering the lineage metadata and letting us diff exactly which exports fed into each calibration run.
- `tools/fit_key_calibration.py` produces `config/key_calibration.json`, letting the backend remap analyzer keys to Spotify’s canonical labels + calibrated confidences. `tools/validate_calibration.py --key-report --key-calibration-config config/key_calibration.json` surfaces key accuracy alongside MAE so we can guardrail tonality.
- The backend exposes `POST /calibration/key`, so the Mac app can trigger the key-calibration fit without touching the terminal. It auto-discovers `data/calibration/*.parquet` (or honors a JSON `datasets` array), writes `config/key_calibration.json`, hot-reloads it, and returns the raw/calibrated accuracy deltas.
- Analyzer key detection now runs tuned chroma → Krumhansl template scoring with better major/minor separation, and the chunk consensus ignores low-confidence keys. Re-export calibration datasets to capture the improved `analyzer_key` columns before the next sweep.

---

## 7. Key Accuracy Recovery Plan

### 7.1 Fix Spotify ↔ Analyzer Joining

1. **Normalize edition tags.** Update `_normalize_text` in `tools/build_calibration_dataset.py` to drop tokens such as `remaster`, `single version`, `taylor s version`, and any parenthetical text at the tail so analyzer rows like “You’ll Think Of Me – Single Version” align with Spotify’s canonical titles.
2. **Prefer artist overlap when deduping Spotify rows.** Instead of sorting purely by popularity in `_load_all_spotify_metrics`, prefer rows whose normalized artist overlaps the analyzer artist before falling back to popularity. This keeps Shania Twain’s “You’re Still The One” when both Shania and Teddy Swims appear in the CSV bundle.
3. **Add coverage checks** so the builder fails fast when analyzer exports contain songs that can’t be matched. A simple post-merge assert on `match_key` counts (expected 55 for this sweep) stops us from training on incomplete datasets.
4. **Quick audit command** (run after every build) to confirm there are zero missing tracks. The builder now raises when analyzer rows fail to match, but this snippet is handy for CI/manual checks:
   ```bash
   python3 - <<'PY'
   import pandas as pd
   df = pd.read_parquet('data/calibration/calibration_20251113_combo.parquet')
   print("Matched rows:", len(df))
   spotify = pd.read_csv('csv/spotify metrics.csv')
   spotify = pd.concat([spotify, pd.read_csv('csv/spotify 2.csv')])
   from tools.build_calibration_dataset import _build_match_key
   expected = { _build_match_key(t, a) for t, a in zip(spotify['Song'], spotify['Artist']) }
   have = set(df['match_key'])
   missing = sorted(expected - have)
   print("Missing:", len(missing))
   assert not missing, f"Missing rows: {missing[:5]}"
   PY
   ```

### 7.2 Rebuild & Calibrate

1. Rebuild the parquet once the join fixes are in (both analyzer exports need to be present so we keep the 55-song sweep):
   ```bash
   python3 tools/build_calibration_dataset.py \
     --analyzer-export exports/cache_export_20251112_225553.csv \
     --analyzer-export "$HOME/Library/Application Support/MacStudioServerSimulator/CalibrationExports/calibration_run_20251113_005306.csv" \
     --spotify-metrics csv/spotify\ metrics.csv \
     --spotify-metrics csv/spotify\ 2.csv \
     --output data/calibration/calibration_20251113_combo_fixed.parquet \
     --notes "combo-225553-005306-fixed"
   ```
2. Fit fresh scalers/models on the fixed dataset (Section 2 commands) and commit the regenerated `config/calibration_scalers.json` + `models/calibration_models.json`.
3. Refit key calibration so the backend can use calibrated probabilities immediately:
   ```bash
   python3 tools/fit_key_calibration.py \
     --dataset data/calibration/calibration_20251113_combo_fixed.parquet \
     --output config/key_calibration.json \
     --notes "key-fix-225553-005306"
   ```
4. Validate both MAE + key accuracy, enforcing `--min-key-accuracy 0.65` to guarantee progress.

### 7.3 Analyzer & Detection Tweaks

- **Chunk consensus audit:** For the songs that still misfire at high confidence (`Yeah!`, `Islands in the Stream`, `The Sweet Escape`, etc.), re-run the analyzer with chunk-debug logging enabled to see if per-chunk keys wobble or if the consensus is biased.
- **Template tuning:** Investigate whether the weighted chroma templates need retuning for high-energy vs acoustic tracks. Capture before/after exports for at least the 10 worst offenders to keep regression history.
- **Confidence calibration:** Once the confusion map improves, revisit how we scale `analyzer_key_confidence` so that ≥20% confidence corresponds to ≥70% precision. This can be another ridge-style calibrator on top of the confusion matrix.

### 7.4 Exit Criteria

- [ ] 55/55 Spotify rows are present in `data/calibration/calibration_20251113_combo_fixed.parquet`.
- [ ] `tools/validate_calibration.py --key-report --min-key-accuracy 0.65` passes with calibrated accuracy ≥65%.
- [ ] `config/key_calibration.json` + scaler/model artifacts regenerated from the fixed dataset and checked in.
- [ ] Analyzer chunk-level investigation logged in `reports/key_debug/<song>.md` for the top 5 historical misses.
