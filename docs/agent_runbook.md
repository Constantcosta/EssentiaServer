# Agent Runbook

Quick references for operating and modifying the Mac Studio Audio Analysis Server.

## Operations
- Start (enforces repo venv): `.venv/bin/python backend/analyze_server.py`
- Start with system Python (temporary): `ALLOW_SYSTEM_PYTHON=1 python3 backend/analyze_server.py`
- Stop: `pkill -f analyze_server.py` (or use the GUI stop button).
- Health check: `curl http://127.0.0.1:5050/health`
- View log: `tail -f ~/Music/AudioAnalysisCache/server.log`

## Configuration Overrides
- Port: `MAC_STUDIO_SERVER_PORT=5051`
- Host bind: `MAC_STUDIO_SERVER_HOST=0.0.0.0` (exposes to LAN; keep API keys on)
- Cache directory: `MAC_STUDIO_CACHE_DIR=/tmp/AudioAnalysisCache`
- Database path: `MAC_STUDIO_DB_PATH=/tmp/audio_analysis_cache.db`
- Rate limit: `RATE_LIMIT=120`
- Clear log on boot: `CLEAR_LOG=1`

## Development Guidelines
- Use `ServerConfig` (`backend/server/app_config.py`) to surface new env toggles instead of sprinkling new globals.
- Prefer adding routes via `register_*` helpers; keep auth/rate-limit hooks consistent.
- When modifying calibration behavior, update both the Python hooks and the Swift GUI messaging if user-facing changes occur.
- Multiprocessing: ensure new code paths remain pickle-safe; avoid lambdas/closures in worker payloads.

## Minimal Test Ideas
- Cache hit/miss: call `/analyze` twice on the same URL and assert hit rate increments.
- Direct upload: POST `/analyze_data` with a small WAV/MP3 payload.
- Calibration refresh: hit `/health` to confirm calibration assets are reported as loaded.
- Rate limit: lower `RATE_LIMIT` env var and issue rapid requests to confirm 429 behavior.

