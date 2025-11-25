# Mac Studio Server Manager (macOS)

## Overview

This target is now a **native macOS control panel** for the Python-based Mac Studio Audio Analysis Server. Build it for “My Mac” and you can start/stop the backend, monitor live statistics, browse the cache, and tail server logs without touching Terminal. Your iOS app (or any HTTP client) continues to analyze audio by calling the `/analyze` endpoints—this app simply keeps the macOS host healthy.

## Features

- **One-click server lifecycle** – launch the bundled `analyze_server.py`, stop it via `/shutdown`, or restart it from the toolbar/keyboard shortcuts.
- **Real-time telemetry** – view total analyses, cache hits/misses, hit rate, and database metadata on the Overview tab.
- **Cache browser** – search cached tracks, inspect BPM/key/confidence values, and delete or clear entries directly.
- **Log tailing** – stream the last 200 lines of `~/Music/AudioAnalysisCache/server.log`, toggle auto-refresh, or copy logs to the clipboard.
- **Desktop-native UI** – AppKit commands, hidden title bar, Finder integration for the database location, and keyboard shortcuts (⌘S / ⇧⌘S / ⌘R).

## Prerequisites

1. **macOS 14+ with Xcode 15+** (the scheme now targets macOS, not iOS).
2. **Python 3** plus the audio stack (`pip3 install -r backend/requirements.txt`).
3. `backend/analyze_server.py` present in the repo (the app launches this script).
4. Optional: run `backend/quickstart.sh` to verify dependencies and port availability before opening Xcode.

## Setup & Run

1. Open the workspace: `open MacStudioServerSimulator.xcworkspace`.
2. In the scheme selector choose **My Mac (Designed for Mac)** or any macOS destination.
3. (First run) Go to *Signing & Capabilities* and pick your Apple ID so Xcode can codesign the macOS binary.
4. Press **⌘R**. The window loads the new `ServerManagementView`.
5. Click **Start Server** – the app now refuses to launch unless `~/Documents/GitHub/EssentiaServer/.venv/bin/python` (or your explicit `MacStudioServerPython` override) exists, so run `.venv/bin/pip install -r requirements-calibration.txt` or `tools/verify_python_setup.sh` first. Once available, the GUI runs `.venv/bin/python backend/analyze_server.py`, waits for it to bind to port 5050, and begins polling `/health`.

### Customizing the script path

If your project lives somewhere else, point the app at the correct script without rebuilding:

```bash
defaults write com.macstudio.serversimulator MacStudioServerScriptPath "/path/to/analyze_server.py"
# Optional: override Python interpreter
defaults write com.macstudio.serversimulator MacStudioServerPython "/usr/local/bin/python3"
```

Remove either key with `defaults delete com.macstudio.serversimulator MacStudioServerScriptPath`.

## Using the App

- **Header controls** report run state, surface errors, and expose Start/Stop/Restart plus a manual refresh. Status automatically updates when the Python process exits.
- **Overview tab** pulls `/stats` and database metadata so you can sanity-check cache growth or open the DB folder in Finder.
- **Cache tab** wraps `/cache`, `/cache/search`, `/cache/{id}`, and `/cache/clear` with search, refresh, delete, and bulk-clear actions.
- **Logs tab** tails `server.log`, optionally auto-refreshes every two seconds, and includes a Copy button for quick sharing.

## Project Structure

```
MacStudioServerSimulator/
├── MacStudioServerSimulator.xcworkspace
├── MacStudioServerSimulator/
│   ├── MacStudioServerSimulator.xcodeproj
│   └── MacStudioServerSimulator/
│       ├── MacStudioServerSimulatorApp.swift   # SwiftUI @main w/ AppKit commands
│       ├── ServerManagementView.swift          # macOS UI (status, cache, logs)
│       ├── ServerTestView.swift                # Legacy analyzer playground (optional)
│       ├── Models/ServerModels.swift           # Codable API models + helpers
│       └── Services/MacStudioServerManager.swift # REST client + local process control
```

## API Surface

The app calls the same REST endpoints your iOS client uses:

- `GET /health` – verify the Python server is alive.
- `GET /stats` – show totals, hit rate, DB path.
- `GET /cache`, `GET /cache/search`, `DELETE /cache/{id}`, `POST /cache/clear` – manage cached analyses.
- `POST /shutdown` – stop the Python process gracefully.
- `POST /analyze`, `POST /analyze_data` – still available via `ServerTestView` or external clients.

## Troubleshooting

| Issue | Fix |
| --- | --- |
| **“Could not find analyze_server.py”** | Update the script path using `defaults write ... MacStudioServerScriptPath`. |
| **Port 5050 already in use** | Stop other instances (`lsof -ti:5050 | xargs kill`) or run `backend/quickstart.sh` to resolve conflicts. |
| **Server exits immediately** | Check `~/Music/AudioAnalysisCache/server.log` from the Logs tab; dependency errors are surfaced there. |
| **API requests fail with auth errors** | Ensure the API key in `MacStudioServerManager` matches the backend’s configuration (see `backend/PRODUCTION_SECURITY.md`). |
| **Still targeting iOS simulators** | Select the **MacStudioServerSimulator** scheme and choose a **My Mac** destination; the deployment target is now macOS 14. |

## Related Documentation

- `backend/README.md` – Python server quick start and API contract.
- `backend/PHASE1_FEATURES.md` – details of the advanced analysis metrics surfaced in the UI.
- `backend/PRODUCTION_SECURITY.md` – API key management and rate limiting.
- `backend/PERFORMANCE_OPTIMIZATIONS.md` – server performance work.

Happy analyzing! 🎧
