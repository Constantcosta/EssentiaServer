# Essentia Server – Agent Orientation

This page gives enough context for a new agent to navigate the codebase, find the primary entry points, and make safe changes quickly.

## Top-Level Layout
- `backend/analyze_server.py` — Flask entry point that wires routes, logging, cache, and calibration.
- `backend/server` — HTTP routes, database/cache helpers, processing orchestration.
- `backend/analysis` — DSP feature extraction, calibration layers, chunk analysis, reporting utilities.
- `MacStudioServerSimulator/` — SwiftUI control panel that starts/stops the Python backend and surfaces logs.
- `tools/` — Helper scripts for diagnosing calibration issues, restarting, and environment setup.

## Request Flow (Happy Path)
1. Client hits `/analyze` or `/analyze_data`.
2. `analysis_routes.py` handles auth/headers, resolves cache namespace, checks cache.
3. If cache miss, downloads audio (or reads body), forwards bytes to `process_audio_bytes` (process pool aware) in `backend/server/processing.py`.
4. `processing.py` loads/optionally resamples audio, calls `perform_audio_analysis` and `attach_chunk_analysis`, and applies calibration hooks.
5. Result is cached (`cache_store.py`), stats updated, response returned.

## Calibration Flow
- Calibration assets load at startup (`analysis.calibration.*`) and are refreshed per-request via `refresh_calibration_assets`.
- Calibration hooks are injected into processing through `configure_processing(DEFAULT_CALIBRATION_HOOKS)` so workers apply the same snapshot.

## Multiprocessing Notes
- `process_audio_bytes` uses a `ProcessPoolExecutor` when `ANALYSIS_WORKERS > 0`, using `spawn` to avoid fork deadlocks.
- Nested pools are prevented by detecting non-main processes; workers fall back to sequential mode to stay safe.

## Configuration (centralized)
- See `backend/server/app_config.py` for environment overrides (PORT, HOST, cache/db paths, rate limit, venv enforcement).
- GUI log viewer and backend logging default to `~/Music/AudioAnalysisCache/server.log`.

## Common Tasks
- **Start server (venv enforced):** `.venv/bin/python backend/analyze_server.py`
- **Force inline analysis (no workers):** `ANALYSIS_WORKERS=0 .venv/bin/python backend/analyze_server.py`
- **Clear log on boot:** `CLEAR_LOG=1 .venv/bin/python backend/analyze_server.py`
- **Export cache:** `python backend/analyze_server.py --clear-log` (or use `/cache/export` route via GUI/HTTP).

## Guardrails for Changes
- Surface new environment toggles through `ServerConfig` (see `backend/server/app_config.py`) instead of scattering globals.
- Avoid new side effects at import time; keep runtime wiring in explicit functions.
- When adjusting calibration, ensure both `analysis.calibration` and `processing.configure_processing` stay in sync.
- If adding new headers/fields to routes, update docs/tests and keep cache key stability in mind.
