# Handoff: Restore Calibration Workflow and Stability

+Summary: Calibration Swift file was accidentally deleted and rebuilt as a placeholder. All non-MD files are under 500 lines; backend refactors are in place. The new calibration file keeps builds working but does **not** run the original workflow. Goal: restore prior behavior, then improve accuracy/efficiency.*

## What Changed
- Recreated `MacStudioServerSimulator/MacStudioServerSimulator/Services/MacStudioServerManager+Calibration.swift` as a minimal placeholder (writes a CSV of calibration songs, a placeholder dataset file, and a placeholder comparison CSV). No real calibration logic runs.
- Split Swift manager concerns: Python helpers -> `MacStudioServerManager+Python.swift`; calibration songs remain in `MacStudioServerManager+CalibrationSongs.swift`; main manager now ~427 lines.
- Backend refactors: `backend/analyze_server.py` split with admin routes in `backend/server/admin_routes.py`; key detection split into `key_detection.py` + `key_detection_helpers.py`; chunk helpers split; test suite split; calibration dataset builder split into wrapper + `tools/calibration_dataset_utils.py`; normalization helpers in `tools/calibration_normalization.py`. Added `.numba_cache/` ignores.

## Current Status
- Builds should pass, but calibration runs are placeholders. UI buttons still set progress/logs/URLs, but no real dataset/comparison is produced.
- All non-MD files < 500 lines.

## Prior Behavior to Restore (Missing)
- The original calibration workflow triggered Python scripts to build a Parquet dataset and compare against Spotify metrics. That logic is gone from `MacStudioServerManager+Calibration.swift`.
- Any detailed calibration process (progress parsing, log streaming, error mapping) must be reimplemented.

## Files to Focus On
- Placeholder to replace: `MacStudioServerSimulator/MacStudioServerSimulator/Services/MacStudioServerManager+Calibration.swift`
- Swift manager core: `MacStudioServerSimulator/MacStudioServerSimulator/Services/MacStudioServerManager.swift`
- Python helpers: `MacStudioServerSimulator/MacStudioServerSimulator/Services/MacStudioServerManager+Python.swift`
- Calibration songs (intact): `MacStudioServerSimulator/MacStudioServerSimulator/Services/MacStudioServerManager+CalibrationSongs.swift`
- Calibration UI (consumes state): `MacStudioServerSimulator/MacStudioServerSimulator/ServerManagementCalibrationTab.swift`
- Backend admin routes: `backend/server/admin_routes.py`
- Calibration dataset tooling: `tools/calibration_dataset_utils.py`, `tools/calibration_normalization.py`, wrapper `tools/build_calibration_dataset.py`
- Comparison script: `tools/compare_calibration_subset.py`

## Recommended Recovery Plan
1) Restore real calibration run:
   - Implement `runCalibrationSuite(featureSetVersion:notes:)` to call the Python builder (likely `tools/build_calibration_dataset.py` / `calibration_dataset_utils.py`) with the selected feature set and notes. Capture stdout/stderr for `calibrationLog`, update `calibrationProgress`, set `lastCalibrationExportURL` and `lastCalibrationOutputURL` to real artifacts.
   - Use the actual analyzer export CSV and Parquet outputs instead of placeholders.
2) Restore comparison:
   - Implement `compareLatestCalibrationDataset()` to call `tools/compare_calibration_subset.py` (or the intended comparison script) against the latest dataset; store text output in `lastCalibrationComparison` and CSV path in `lastCalibrationComparisonURL`.
3) Verify Swift bindings:
   - Ensure `ServerManagementCalibrationTab` buttons still call the updated methods and that state updates (`isCalibrationRunning`, `calibrationProgress`, `calibrationLog`, error strings, last URLs) are published.
4) Backend sanity check:
   - Run `python backend/analyze_server.py` and hit `/health` and `/diagnostics`.
   - Quick analysis sanity: `python test_ballad_simple.py` or `python test_scientist.py`.
5) Regression tests:
   - Optionally run CLI tests: `python tools/test_analysis_pipeline.py --preview-batch` (server must be running).

## Notes for Accuracy/Efficiency After Restoration
- Audio pipeline already refactored; further tuning should wait until calibration is real.
- Calibration dataset tooling now lives in `tools/calibration_dataset_utils.py` (Parquet write, normalization via `calibration_normalization.py`). Align Swift arguments/paths with this CLI.

## Apology / Caveat
- The original Swift calibration file content is unrecoverable from this repo; reconstruction requires reimplementing the intended workflow. The current placeholder only preserves build and UI wiring.***
