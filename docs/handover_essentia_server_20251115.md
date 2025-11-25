# EssentiaServer – Handover Notes (2025-11-15)

## 1. Mission Snapshot
- Goal: restore Essentia-backed key detection + calibration accuracy so GUI-only operators can run Force Re-analyze sweeps without terminal access.
- Environment: macOS host running `.venv` Python 3.12 + Essentia 2.1b6.dev1389, analyzer served via `backend/analyze_server.py`, GUI controller in `MacStudioServerSimulator`.
- Latest code branch: `copilot/improve-slow-code-efficiency` (includes cache endpoints + HPSS guard).

## 2. Work Completed This Round
1. **Cache persistence & routing** (`backend/analyze_server.py`, `backend/server/cache_*.py`): GUI diagnostics cache panel now hits real endpoints once the server restarts.
2. **HPSS crash fix** (`backend/analysis/pipeline_core.py`): Guarded NumPy arrays so workers stop dying on "truth value of array" errors.
3. **Validation**: `./.venv/bin/python -m compileall backend/analysis/pipeline_core.py backend/analyze_server.py` (passes).
4. **Logs collected** (tail at 2025-11-15 03:40–03:47) for TonalExtractor failures + server shutdown sequence.

## 3. Current Observations
- Server log spammed with `[ WARNING ] No network created...` and repeated `⚠️ Essentia TonalExtractor failed: 'sampleRate' is not a parameter of TonalExtractor`. This points to Essentia being imported but the TonalExtractor constructor signature mismatching (likely still running the Librosa-only workers or the wrong Essentia build).
- Despite Essentia warnings, other analysis continues (danceability, calibration layer) indicating workers stay alive post HPSS fix.
- Last log lines show manual shutdown via `/shutdown` returning HTTP 500 at `03:47:08`.
- Diagnostic health endpoints were hit (`GET /health`, `GET /stats` returning 200) just before shutdown.

## 4. Artifacts & Data
Latest calibration exports (all 13-row GUI deck, still missing Essentia fields):
| Timestamp (UTC) | File | Notes |
| --- | --- | --- |
| 2025-11-15 03:40 | `data/calibration/mac_gui_calibration_20251115_034054.parquet` + `.comparison.csv` | Analyzer build `bad8d9c4…`, accuracy 1/13, Essentia columns absent |
| 2025-11-15 03:33 | `mac_gui_calibration_20251115_033353.parquet` | Similar stats |
| 2025-11-15 03:18 | `mac_gui_calibration_20251115_031840.parquet` | " |
| 2025-11-15 03:09 | `mac_gui_calibration_20251115_030918.parquet` | " |
| 2025-11-15 02:30 | `mac_gui_calibration_20251115_023037.parquet` + `.comparison.csv` | " |
| 2025-11-15 02:15 | `mac_gui_calibration_20251115_021535.parquet` + `.comparison.csv` | " |

*(See `reports/calibration_reviews/` for per-run CSV comparisons.)*

## 5. Known Issues / Blockers
1. **TonalExtractor parameter mismatch** – Workers print `'sampleRate' is not a parameter of TonalExtractor` on every analysis. Either the Essentia module being imported is too old, or our constructor args need to be gated when Essentia is missing. Action: confirm `essentia.__version__` inside worker processes via `tools/verify_essentia_workers.py` and adjust `analysis/key_detection.py` accordingly.
2. **Essentia outputs absent in cache/datasets** – Even after restart, the cached JSON lacks `key_source`, `essentia`, `essentia_edm`. Action: run a Force Re-analyze after ensuring TonalExtractor initializes; verify `analyzer_key_details` per-row.
3. **Diagnostics feedback loop** – Operators need a visible status to know whether analyzer is using `.venv` Python. Currently only logs show this. Consider surfacing active Python path + analyzer SHA in GUI Server tab.
4. **Shutdown HTTP 500** – `/shutdown` returned 500 at 03:47 even though server honored the stop. Low priority unless GUI relies on success status.

## 6. Immediate Next Steps
1. **Verify Essentia build inside workers**
   ```bash
   ./.venv/bin/python tools/verify_essentia_workers.py --verbose
   ```
   - Expect `has_essentia: true` and TonalExtractor constructor success log. If it fails, reinstall Essentia or adjust environment variables.

2. **Inspect running process**
   ```bash
   ps aux | grep analyze_server.py | grep -v grep
   ```
   - Ensure it points to `.venv/bin/python`. If not, rerun `tools/restart_with_venv.sh`.

3. **Run Diagnostics from GUI** – Confirm cache checks hit `/cache/search` (should be green) and Essentia verification passes. Capture screenshot/log for next agent.

4. **Force new calibration sweep**
   - Enable "Force Re-analyze".
   - After run, inspect Parquet:
     ```python
     import json, pandas as pd
     df = pd.read_parquet('data/calibration/mac_gui_calibration_20251115_XXXXXX.parquet')
     details = json.loads(df.loc[0, 'analyzer_key_details'])
     print(details.keys())
     print(details.get('key_source'))
     ```
   - Goal: see `key_source` values like `essentia_dominant`, plus Essentia probability blobs.

5. **Document results** – Append findings to `docs/handover_calibration_next_agent.md` and this handover file (section 4 table).

## 7. Optional Follow-Ups (after Essentia confirmed)
- Re-run `tools/compare_calibration_subset.py` to update accuracy metrics.
- Continue key-detection heuristic tweaks (`analysis/key_detection.py`) now that Essentia data exists.
- Surface analyzer Python path + SHA in GUI Server tab for operator confidence.
- Add automated pre-flight script that runs `verify_essentia_workers.py`, `compare_calibration_subset.py`, cache export smoke test.

## 8. Reference Files & Commands
- Analyzer entrypoint: `backend/analyze_server.py`
- Cache stack: `backend/server/cache_store.py`, `cache_routes.py`, `database.py`
- Analysis core: `backend/analysis/pipeline_core.py`, `pipeline.py`, `key_detection.py`, `essentia_support.py`
- Diagnostics scripts: `tools/verify_python_setup.sh`, `tools/verify_essentia_workers.py`, `tools/export_analysis_timers.py`
- Restart helper: `tools/restart_with_venv.sh`
- Recent validation command: `./.venv/bin/python -m compileall backend/analysis/pipeline_core.py backend/analyze_server.py`

## 9. Contact / Notes
- GUI operator already restarted once; current issue is deeper (TonalExtractor parameter mismatch). Provide them with explicit verification steps above.
- Attach relevant log snippet (2025-11-15 03:40:52–03:47) when sharing this doc so next agent sees exact warning pattern.
