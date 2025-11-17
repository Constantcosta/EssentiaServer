# Calibration & GUI Handoff – 2025-11-16

## TL;DR
- The macOS GUI now **cannot** start the analyzer unless the repo’s `.venv/bin/python` exists; backend/analyze_server.py also refuses to boot outside the venv (unless `ALLOW_SYSTEM_PYTHON=1` is set manually).
- Diagnostics (Essentia workers, phase-1 features, smoke tests, performance suite) pass when run from the GUI-launched server after the enforcement went in.
- The lingering “No module named ‘resampy’” + `librosa.util.exceptions.ParameterError` logs you’re seeing are from **older server launches** (before the guard) that were still running via Homebrew’s Python; new launches emit “🧠 Analyzer running via /…/.venv/bin/python” near the top of `~/Music/AudioAnalysisCache/server.log`.
- HTTP 502 / `invalid.invalid` stack traces are just the diagnostics harness hitting its intentionally bad URL; they are not a runtime bug.

## Current State
| Item | Status |
| --- | --- |
| Virtual environment (`.venv/`) | ✅ Python 3.12.12, Essentia 2.1b6.dev1389, resampy pinned |
| GUI Start/Stop/Auto-manage | ✅ All call the same `startServer()` which now logs and enforces the venv path |
| Backend analyzer entrypoint | ✅ Hard fails if interpreter ≠ `.venv/bin/python` (unless `ALLOW_SYSTEM_PYTHON=1`) |
| Diagnostics suite | ✅ All tests green as of `2025-11-16 04:29` |
| Calibration runs | ⚠️ Last captured logs still show Homebrew-era warnings; rerun after GUI rebuild |

## What I Did
1. **Compiler-level guardrails**
   - Added `resolvePythonExecutableURL()` enforcement + log appends in the Swift server manager so Start/Auto-manage can’t secretly fall back to `/opt/homebrew/.../python`.
   - Created `_ensure_virtualenv_python()` at the top of `backend/analyze_server.py`; it aborts immediately if the interpreter doesn’t match `.venv/bin/python`, with an opt-out env var for manual CLI use.
2. **Operator visibility**
   - Every GUI launch now appends `MacStudioServerSimulator: Launching analyzer via …` to `~/Music/AudioAnalysisCache/server.log`. Check that log first whenever you suspect the wrong interpreter.
   - README now documents the enforcement and the `ALLOW_SYSTEM_PYTHON=1` escape hatch.
3. **Verification**
   - Ran `tools/verify_essentia_workers.py`, phase-1 feature tests, `backend/test_server.py`, and performance benchmarks from the GUI using the enforced venv. All passed; only expected warnings remain (pkg_resources deprecation, fake URL 502).

## Outstanding Issues / Watchlist
- **Legacy logs:** The long block of `No module named 'resampy'` messages you pasted is from servers started *before* the enforcement landed. After rebuilding the GUI and pressing Start, those warnings should disappear; if they persist, tail the log to confirm the interpreter line.
- **Process pool crashes:** Those `Since S.shape[-2] is 513…` exceptions were also triggered in the Homebrew runs (because Librosa fell back to 44.1 kHz). Expect them to vanish with the venv build. If they don’t, capture new logs *after* confirming the interpreter line.
- **Shutdown 500s:** `/shutdown` still returns HTTP 500 because the Flask dev server raises when `werkzeug.server.shutdown` isn’t available. Harmless but noisy; leave for a later cleanup sprint.
- **Diagnostics URL:** `invalid.invalid` is still the placeholder preview URL for smoke tests. It intentionally produces HTTP 502 so we can exercise retries. Ignore unless you actually want to test a real preview (`TEST_ANALYZE_URL`).

## Next Steps for the Incoming Agent
1. **Rebuild & relaunch the macOS GUI** (⌘R). Hit **Stop** to kill any lingering Homebrew processes, then **Start** once; confirm `server.log` shows `.venv/bin/python`.
2. **Re-run the 13-song calibration deck** with “Force re-analyze / bypass cache” enabled. Inspect the new Parquet to verify Essentia fields are populated.
3. If any `resampy` warnings or RMS parameter errors appear in fresh logs, grab the interpreter line + stack traces and investigate Librosa settings in `backend/analysis/pipeline_core.py`.
4. After a clean run, update `docs/handover_calibration_next_agent.md` with the new dataset + status, and rerun `tools/compare_calibration_subset.py` so the reports stay in sync.

Ping me (or check `server.log`) if you see any launch that doesn’t print the venv path; that means someone manually set `ALLOW_SYSTEM_PYTHON=1` or the venv is missing. Otherwise you’re good to resume calibration debugging. Good luck!
