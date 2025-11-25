# Calibration Handover – 2025‑11‑15

This note captures the current calibration/key-detection state after the latest macOS GUI sweeps so the next agent can jump straight into debugging.

---

## 1. Current Snapshot

| Dataset | Feature Set | Rows | Exact Key Matches | Mode Mismatches | Notes |
| --- | --- | --- | --- | --- | --- |
| `data/calibration/mac_gui_calibration_20251115_023037.parquet` | `v2` (Mac app Hybrid sweep) | 13 | **1 / 13 (7.7 %)** | **11 / 13 (84.6 %)** | Latest sweep (reports/calibration_reviews/mac_gui_calibration_20251115_023037.csv); still Librosa-only key JSON |
| `data/calibration/mac_gui_calibration_20251115_021535.parquet` | `v2` (Mac app Hybrid sweep) | 13 | **1 / 13 (7.7 %)** | **11 / 13 (84.6 %)** | `reports/calibration_reviews/mac_gui_calibration_20251115_021535.csv`; still Librosa-only key JSON |
| `data/calibration/mac_gui_calibration_20251115_003530.parquet` | `v2` (Mac app Hybrid sweep) | 13 | **1 / 13 (7.7 %)** | **11 / 13 (84.6 %)** | `reports/calibration_reviews/mac_gui_calibration_20251115_003530.csv`; still Librosa-only key JSON |
| `data/calibration/mac_gui_calibration_20251115_001433.parquet` | `v2` | 13 | **1 / 13 (7.7 %)** | **11 / 13 (84.6 %)** | Post-Essentia install, but analyzer still reports Librosa-only key details |
| `data/calibration/mac_gui_calibration_20251115_000107.parquet` | `v2` | 13 | 1 / 13 | 11 / 13 | Same offsets (+5/+7/+9) as earlier run |
| `data/calibration/mac_gui_calibration_20251114_233929.parquet` | `v2` | 13 | 0 / 13 | 8 / 13 | Pre-Env tweaks; used for baseline comparison |

Validation command (run after each sweep):

```bash
python3 tools/compare_calibration_subset.py \
  --dataset data/calibration/<file>.parquet \
  --csv-output reports/calibration_reviews/<tag>.csv
```

CSV summaries live under `reports/calibration_reviews/` for historical tracking.

---

## 2. Key Findings

1. **Essentia not active yet (pre-fix)** – Even after installing `essentia==2.1b6.dev1389`, the analyzer process the Mac GUI talks to still logs only Librosa scores. Every row’s `analyzer_key_details` JSON lacks `essentia` / `essentia_edm` entries and `key_source` is `null`, so none of the latest override logic is executing. _Resolved 2025-11-15 by wiring the worker pool – see §6._ However, the three most recent datasets (`mac_gui_calibration_20251115_003530.parquet` @ `2025-11-14T14:35:31Z`, `mac_gui_calibration_20251115_021535.parquet` @ `2025-11-14T16:15:35Z`, and `mac_gui_calibration_20251115_023037.parquet` @ `2025-11-14T16:30:38Z`) all show `essentia=None`, which means the GUI sweeps ran before restarting the analyzer with the patched worker code.
2. **Offsets still dominated by dominant/relative picks** – The latest dataset remains skewed toward +5/+7/+9 semitone deltas (e.g., “Lose Control” reported F# minor vs. Spotify A major; “Espresso” reported A minor vs. Spotify C major). Until Essentia kicks in, we can’t evaluate the new safeguards.
3. **Mode flips rampant** – 11/13 samples are mode mismatches (keys often agree on root but disagree on Major/Minor), so the mode-bias heuristics still have no effect without Essentia’s mode signal.

---

## 3. Immediate Actions for the Next Agent

1. **Ensure the analyzer restarts with Essentia loaded**
   - Launch the Mac app → **Stop Server** → **Start Server** so the Python process reloads.
   - Watch the server log pane; it must say:
     ```
     ✅ Enabled scipy.signal.hann compatibility shim.
     🎚️ Essentia TonalExtractor enabled …
     ```
     If you still see “Essentia TonalExtractor disabled…”, run `python3 -c "import essentia; print(essentia.__version__)"` inside the repo to confirm installation, then check `backend/analyze_server.py` output for import errors.

2. **Re-run the calibration sweep**
   - Mac app → Calibration tab → ensure your 13‑song deck is loaded → **Run Calibration Sweep**.
   - The builder writes `~/Library/.../calibration_run_<timestamp>.csv` and drops the Parquet in `data/calibration/mac_gui_calibration_<timestamp>.parquet`. Note the timestamp for the next comparison.

3. **Generate the comparison report**
   - Run the compare script (command above) for the fresh Parquet and capture the output. The script also writes a CSV under `reports/calibration_reviews/`.
   - Inspect one or two rows in Python to confirm `analyzer_key_details` now includes `essentia` candidates:
     ```python
     import pandas as pd, json
     df = pd.read_parquet("data/calibration/mac_gui_calibration_<ts>.parquet")
     details = json.loads(df.loc[df['title']=="Lose Control",'analyzer_key_details'].iloc[0])
     print(details['essentia'], details['essentia_edm'], details['key_source'])
     ```

4. **Only after Essentia is visible in the JSON**, continue iterating on `backend/analysis/key_detection.py` (dominant overrides, mode rescue, chunk dispersion) and re-run sweeps/compare for each change.

---

## 4. Useful Paths & Commands

| Task | Command / Path |
| --- | --- |
| Install/upgrade Essentia (user site) | `pip3 install 'essentia==2.1b6.dev1389' 'librosa==0.10.1' 'scipy==1.10.1'` |
| Confirm Essentia import | `python3 -c "import essentia; print(essentia.__version__)"` |
| Compare Parquet vs Spotify | `python3 tools/compare_calibration_subset.py --dataset data/calibration/mac_gui_calibration_<ts>.parquet --csv-output reports/calibration_reviews/<tag>.csv` |
| Peek key details | `python3 - <<'PY' ... print(json.loads(df['analyzer_key_details'][0]))` |
| Calibration exports (GUI) | `~/Library/Application Support/MacStudioServerSimulator/CalibrationExports/` |
| Parquet artifacts | `data/calibration/mac_gui_calibration_*.parquet` |
| Comparison reports | `reports/calibration_reviews/*.csv` |

---

## 5. Open Issues & Next Tweaks (after Essentia works)

1. **Dominant Interval Override** – Verify `_apply_dominant_interval_override` is firing by inspecting `key_details['key_source']`. If not, adjust `_DOMINANT_OVERRIDE_SCORE` thresholds or log more context.
2. **Mode Rescue** – Once Essentia reports strong mode confidence, ensure `_mode_rescue_from_candidate` is flipping the 11 problematic tracks; add logging or a debug flag to track rescues.
3. **Calibration Dataset Growth** – Re-stage the full 55-song deck (include missing Teddy Swims entries) and rerun the builder so `tools/train_calibration_models.py` has richer data.
4. **Automation** – Hook the compare script into CI (or the Mac app’s “Compare vs Spotify” button) so each sweep immediately surfaces key accuracy; the GUI already exposes this, but we still rely on manual CLI for now.

Document any further tweaks in this file (append dated sections) so the next agent immediately sees what was tried and what remains.

---

## 6. 2025-11-15 – Worker Pool Essentia Wiring

- **Root cause** – The Mac app launches the analyzer with `ANALYSIS_WORKERS>0`, so every song runs inside a `ProcessPoolExecutor`. Those workers never re-ran `configure_key_detection`, meaning `_HAS_ESSENTIA` stayed `False` even when the main process saw Essentia. Inline CLI tests passed because they ran in-process, but all GUI sweeps silently fell back to Librosa-only candidates.
- **Fix** – `backend/server/processing.py` now imports `backend.analysis.essentia_support` and calls `configure_key_detection(HAS_ESSENTIA, es)` at module import, guaranteeing every spawned worker registers Essentia before touching `detect_global_key`. Added `tools/verify_essentia_workers.py` to exercise a synthetic tone inside a spawned worker so we have a fast sanity check.
- **Verification** – Run:
  ```bash
  python3 tools/verify_essentia_workers.py
  ```
  Expect JSON with `"has_essentia": true`, `key_source` = `essentia`, and `score_sources` containing `essentia_std`. (EDM extractor still logs a warning because this Essentia build lacks `KeyExtractorEDM`, but the standard extractor is what we need for Hybrid v2.)
- **Operational next steps**
  1. `git pull` / rebuild the Mac app bundle if needed, then **Stop Server → Start Server** in the GUI so the updated `processing.py` lands in every worker.
  2. Re-run the 13-song calibration sweep with `force re-analyze` to flush any cached Librosa-only entries.
  3. Inspect `analyzer_key_details` for “Lose Control” / “Espresso” and confirm the JSON now includes `essentia`, `key_source`, and `scores[*].source == "essentia_std"`.
  4. Re-run `tools/compare_calibration_subset.py` and capture the delta vs. Spotify so we can finally tune the dominant-interval + mode-rescue heuristics listed above.
- **Mac app automation** – The macOS controller now polls the repo’s `git rev-parse HEAD` every ~10 s and auto-restarts the local analyzer whenever it detects a new commit. This removes the manual “Stop/Start after pulling from Codex” step—just keep the app open, `git pull`, and the Python server relaunches itself with the fresh code (unless you explicitly stopped it, in which case the watcher stays idle).
