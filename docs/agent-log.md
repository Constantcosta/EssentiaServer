## Agent Log – Key Detection Calibration (2025-11-14)

### What’s Been Tried
- **Feature toggle confirmation:** Verified we are running Hybrid v2 sweeps via the macOS calibration tab (screenshot provided). Ensured `feature_set_version` metadata reflects `v2`.
- **Key-detection heuristics:** Expanded `backend/analysis/key_detection.py` with:
  - Sliding-window support ratios and chroma-peak promotion so dominant votes override tonic-by-default.
  - Dual Essentia inputs (standard + EDM) recorded in `key_details.scores` with stronger override logic when their confidence beats chroma/window support.
- **Calibration artifacts:** Refit `config/key_calibration.json` using every `mac_gui_calibration_20251114_*.parquet` file (Hybrid v2) to capture the latest confusion map (raw accuracy 39 %, calibrated ~60 %).
- **Parity checks:** Re-ran `tools/compare_calibration_subset.py` against the latest Parquet exports. Results still show the ±5/±7 offsets from the previous sweeps; no observable gains yet, suggesting the detector changes aren’t being exercised or cached data is still serving.

### Findings / Gaps
- Mac GUI export (e.g., `mac_gui_calibration_20251114_212810.parquet`) continues to report the pre-change analyzer keys even after updating the backend, indicating the analyzer process the GUI hits hasn’t reloaded the new code or it’s still pulling cached analyses.
- Calibration datasets only include percent-based confidence columns; richer `key_details` (votes, Essentia candidates) aren’t present in the exported CSV/Parquet, so we can’t validate whether the new heuristics ran.
- Need confirmation that the Mac GUI server was restarted (or binaries rebuilt) after the code changes; otherwise sweeps will keep reflecting the old logic.

### Next Steps
1. **Restart + verify analyzer build** on the Mac Studio server, then rerun the Hybrid v2 calibration sweep (clear the `calibration` namespace before analyzing).
2. **Confirm fresh analysis** by checking `analyzer_source_file` timestamps inside the new Parquet and ensuring `key_details.scores` contain `essentia_std` / `essentia_edm`.
3. **Re-run comparison:** `python3 tools/compare_calibration_subset.py --dataset data/calibration/<new>.parquet --csv-output reports/calibration_reviews/<tag>.csv`.
4. If offsets persist even after a fresh run, instrument `detect_global_key` logging (per-song root/mode decisions, window dominance) for the problem tracks to see which guardrail is preventing overrides. Update log parsing scripts accordingly.
