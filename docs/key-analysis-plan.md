# Key Analysis Commercialization Plan

## Objectives
- Lift calibrated key accuracy to ≥65% on the 55-song Spotify reference deck.
- Restore BPM MAE under 4.0 and keep all other feature MAEs within guardrails after calibration.
- Automate dataset hygiene and validation so every analyzer change ships with fresh scalers/models and a regenerated key confusion map.

## Current Baseline (2025-11-13)
- Dataset `data/calibration/calibration_20251113_combo.parquet` contains 54/55 matches; coverage gaps reduce calibration quality.
- Raw key accuracy: 33%, calibrated: 52% (still below 63% “mode baseline”). Confidence bins for 0–0.2 scores deliver <40% precision.
- BPM calibrator regressed (10.8 → 12.2 MAE). Other features remain above spec.

## Workstream A – Dataset & Joining Reliability
1. Harden `_normalize_text` + Spotify dedupe rules (`tools/build_calibration_dataset.py`) so analyzer/Spotify editions always align.
2. Enforce 55/55 coverage via a post-merge assert (`expected == have`) and surface missing `match_key`s early in CI.
3. Rebuild `calibration_20251113_combo_fixed.parquet` from the latest analyzer exports + `spotify_calibration_master.csv` once joins are lossless.
4. Update docs with the audit command and require it in the Mac calibration flow before generating datasets.

## Workstream B – Calibration Assets Refresh
1. Refit linear scalers: `python3 tools/fit_calibration_scalers.py --dataset <fixed parquet> --output config/calibration_scalers.json --feature-set-version v1 --notes <tag>`.
2. Retrain ridge models: `python3 tools/train_calibration_models.py --dataset <fixed parquet> --feature-set-version v1 --notes <tag>` and commit the new `models/calibration_models.json`.
3. Refit key confusion map: `python3 tools/fit_key_calibration.py --dataset <fixed parquet> --output config/key_calibration.json --notes <tag>`.
4. Add CI step to ensure these artifacts exist and were regenerated after any analyzer/calibration change (hash check against latest parquet SHA).

## Workstream C – Validation Gate
1. Run `python3 tools/validate_calibration.py --dataset <fixed parquet> --key-report --key-calibration-config config/key_calibration.json --min-key-accuracy 0.65 --max-mae bpm=4 ...` in both local pre-flight and GitHub Actions.
2. Reject builds if any MAE threshold, KS drift limit, or key-accuracy floor fails. Record every run in `reports/calibration_metrics.csv`.
3. Publish the latest metrics table + key offsets summary in release notes so client teams can track improvements.

## Workstream D – Analyzer Improvements
1. Use chunk diagnostics (window length, BPM weighted std) already in exports to analyze top misfires (`Yeah!`, `Islands in the Stream`, `The Sweet Escape`). Log findings in `reports/key_debug/<song>.md`.
2. Tune chroma templates / Essentia weighting for cases where roots land on dominant/subdominant. Experiment with adaptive template scaling per energy class.
3. Research confidence calibration: fit a lightweight regressor that maps analyzer confidences + chunk variance to calibrated probabilities so ≥0.2 confidence implies ≥0.7 precision.

## Deliverables & Exit Criteria
- `data/calibration/calibration_20251113_combo_fixed.parquet` (55 rows) with lineage metadata committed.
- Updated `config/calibration_scalers.json`, `models/calibration_models.json`, and `config/key_calibration.json` produced from the fixed dataset.
- Green CI run of `tools/validate_calibration.py ... --min-key-accuracy 0.65`.
- Key debug notes for at least the top 5 historic misses.
- Documentation updates pointing new agents to this plan and the required commands.
