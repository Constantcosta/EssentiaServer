# Handover – Repertoire GUI Concurrency (Next Agent)
_Updated: 2025‑11‑19 (post‑inline server change)_

## Current High‑Level Status

You’re inheriting the **Repertoire** tab behavior in `MacStudioServerSimulator` (macOS app) that drives the Python analyzer (`backend/analyze_server.py`) over 90 preview clips.

State as of this handover:

- The GUI uses a **6‑concurrent Swift task group** (`RepertoireAnalysisController.runAnalysisBatches`) to POST each song to `/analyze_data`.
- Each row uses:
  - `requestTimeout = 130s` on the `URLRequest` (matching Python Test C).
  - Filename‑derived title/artist overrides so `/analyze_data` sees the same metadata as the CLI tools.
- The Python analyzer:
  - Still runs as a single Flask process (`analyze_server.py`).
  - **Now processes `/analyze_data` inline** (no internal `ProcessPoolExecutor`) to avoid suspected worker‑pool crashes under 6‑way concurrency.
  - Logs detailed `START` and `DONE/ERROR/TIMEOUT` entries per request.

Behavior in practice:

- The first ~12 songs (sometimes more) now complete reliably in the GUI with populated BPM/Key and no GUI stall.
- In some longer runs, **Python processes disappear from Activity Monitor mid‑run** and no further rows complete, while:
  - The Repertoire table still shows a spinner on a row (e.g. Beatles “Here Comes the Sun” or later).
  - Swift logs remain stuck after the last `[ROW n] Calling manager.analyzeAudioFile…` for the next index.
  - The latest `server.log` tail at the stall moment shows normal analysis logs up to a point, but **no explicit crash, exception, or `/shutdown`**, implying a native‑level death or forced termination.
- In at least one recent run after disabling the internal process pool for `/analyze_data`, the analyzer processed **Sunsets, Here Comes the Sun, About a Girl, and several others successfully** before you stopped to reset context.

Bottom line: 

- The original Swift task‑group bug (“pool never exits”) has been fixed; `[POOL EXIT]` and `[EXIT] runFullAnalysisSession()` now appear when runs complete.
- We’ve greatly improved logging, timeouts, and parity with the CLI harness.
- The remaining problem is intermittent: **the analyzer process sometimes dies silently mid‑run**, leaving the GUI in a spinning state waiting for responses that will never come. This now looks primarily like a backend robustness issue plus a missing GUI‑side “server died” detector.

The rest of this document has two parts:

1. Updated **repro + instrumentation** instructions.  
2. Summary of **code changes and remaining work items**.

---

## How to Reproduce (Current Setup)

### GUI Steps

1. Open `MacStudioServerSimulator.xcworkspace` in Xcode.
2. Build & run the `MacStudioServerSimulator` macOS app.
3. In the app:
   - Top segmented control: select **Tests**.
   - Mode segmented control: **Repertoire** (defaults to this now).
4. Let the defaults load:
   - CSV: `csv/90 preview list.csv` (repo root).
   - Audio folder: `~/Documents/Git repo/Songwise 1/preview_samples_repertoire_90`.
5. Click **“Analyze with Latest Algorithms”**.

Observed (current state):

- A dedicated Python analyzer starts (see console logs and `~/Music/AudioAnalysisCache/server.log`).
- For the first 10–15 songs:
  - Status flows: `Pending → Running → Done`.
  - `Detected BPM / Key` is populated (and comparisons show mismatches/matches as expected).
  - Console shows `[TASK n] Task started/completed` and per‑row logs.
- In “good” runs, analysis continues through many more songs (Sunsets, Here Comes the Sun, About a Girl, etc.).
- In problematic runs:
  - Activity Monitor shows **no `python` processes** even though:
    - The GUI still shows the overlay spinner (“Analyzing…”).
    - At least one row remains stuck in `Running`.
  - The console may or may not show `[POOL EXIT]` / `[EXIT] runFullAnalysisSession()` depending on when the analyzer died.

### Backend / Logs

- Analyzer server entry: `backend/analyze_server.py`.
- Config: `backend/server/app_config.py`:
  - Cache + log directory: `~/Music/AudioAnalysisCache`.
  - Log file: `~/Music/AudioAnalysisCache/server.log`.

Check server log:

```bash
tail -n 120 ~/Music/AudioAnalysisCache/server.log
```

At a normal mid‑run point you should see:

- `🚀 Server build ...` on startup.
- Many `▶️ [req‑xxxxx] START analyze_data title='...'` lines.
- Matching `✅ [req‑xxxxx] DONE analyze_data ...` for completed songs.
- Occasional `❌ Analysis timed out after 120s for '...'` entries when the internal 120s per‑song guard fires.

At a **problem** stall point you’ll see:

- No new `START` or `DONE` lines for >10–20 seconds, **and**  
- No `🛑 Server shutdown requested` / `⛔️ Received signal 15 – shutting down analyze_server`, i.e. the server did not log an orderly shutdown.

That combination is your signal that the analyzer likely died without flushing logs or that the process pool (when enabled) deadlocked. We’ve disabled the internal pool for `/analyze_data` to reduce that risk, but the pattern is worth watching.

---

## Key Swift Files & Current Design

### 1. `MacStudioServerSimulator/MacStudioServerSimulator/ServerManagementTestsTab.swift`

Relevant pieces:

- `struct TestsTab: View`
  - Owns:
    - `@ObservedObject var manager: MacStudioServerManager`
    - `@StateObject private var testRunner = ABCDTestRunner()`
    - `@State private var selectedMode: TestsTabMode = .repertoire`  
      → Repertoire is now the default Tests mode.
  - UI:
    - Segmented control: **ABCD Tests** vs **Repertoire**.
    - When `.repertoire` is selected, shows:
      - `RepertoireComparisonTab(manager: manager)`

- `struct RepertoireComparisonTab: View`
  - `@ObservedObject var manager: MacStudioServerManager`
  - `@StateObject private var controller: RepertoireAnalysisController`
    - Created in `init(manager:)` via `StateObject(wrappedValue: RepertoireAnalysisController(manager: manager))`.
  - `.task { await controller.loadDefaultSpotify(); await controller.loadDefaultFolder() }`
  - Analyze button:

    ```swift
    Button {
        controller.startAnalysisFromButton()
    } label: {
        Label("Analyze with Latest Algorithms", systemImage: "play.fill")
    }
    .buttonStyle(.borderedProminent)
    .disabled(controller.rows.isEmpty || controller.isAnalyzing)
    ```

  - Table binds to `controller.rows`, `controller.isAnalyzing` for overlay spinner.

The view now has **no direct concurrency logic**; it delegates all work to `RepertoireAnalysisController`.

---

### 2. `MacStudioServerSimulator/MacStudioServerSimulator/RepertoireAnalysisController.swift`

Core type:

```swift
@MainActor
final class RepertoireAnalysisController: ObservableObject {
    @Published var rows: [RepertoireRow] = []
    @Published var spotifyTracks: [RepertoireSpotifyTrack] = []
    @Published var isAnalyzing = false
    @Published var alertMessage: String?

    private let manager: MacStudioServerManager
    private var analysisTask: Task<Void, Never>?
    private let defaultNamespace = "repertoire-90"
    // Match Python Test C / CLI behavior: each request can run up to ~130s
    // so the GUI doesn't preempt the analyzer before its own 120s guard.
    private let rowTimeoutSeconds: TimeInterval = 130
}
```

#### Entry Point & Lifecycle

- `func startAnalysisFromButton()`

  ```swift
  analysisTask?.cancel()
  analysisTask = Task { [weak self] in
      await self?.runFullAnalysisSession()
  }
  ```

- `private func runFullAnalysisSession() async`
  - Guards:
    - `!isAnalyzing`
    - `!rows.isEmpty`
  - Sets `isAnalyzing = true`, clears `alertMessage`, `defer` resets both `isAnalyzing` and `analysisTask`.
  - **Server lifecycle (per-run)**:
    - Logs “[SERVER] Launching dedicated analyzer for Repertoire run…”.
    - `await manager.startServer()`.
    - If `!manager.isServerRunning`: sets `alertMessage = serverOffline` and returns.
  - Calls `await runAnalysisBatches()`.
  - Then:
    - `await manager.stopServer(userTriggered: false)`
    - Logs `[EXIT] runFullAnalysisSession() complete`.

In current behavior, you often see up to `startServer()` and many pool logs; you may or may not see the final “EXIT” log depending on whether the pool drains.

#### Worker Pool Concurrency

- `private func runAnalysisBatches() async`
  - Implements a **6-concurrent worker pool** over all row indices:

    ```swift
    let indices = Array(rows.indices)
    let maxConcurrent = 6
    var nextIndex = 0
    var inFlight = 0

    await withTaskGroup(of: Void.self) { group in
        func enqueueIfPossible() {
            while nextIndex < indices.count && inFlight < maxConcurrent {
                let idx = indices[nextIndex]
                nextIndex += 1
                inFlight += 1
                group.addTask { [weak self] in
                    await self?.analyzeRowNonisolated(at: idx)
                }
            }
        }

        enqueueIfPossible()
        for await _ in group {
            inFlight -= 1
            enqueueIfPossible()
        }
    }
    ```

  - Logs:
    - `[POOL] Total rows to process: 90, max concurrent: 6`
    - `[POOL] Enqueuing index n (...)`
    - `[POOL] Task completed; inFlight=...`
    - At the end: `[POOL EXIT] All rows processed` (you rarely see this in the hanging runs).

Originally there was a **nested timeout wrapper** around each per‑row call (a `withThrowingTaskGroup` that raced `Task.sleep` vs the network call). This has been **removed**; `analyzeRowNonisolated` now:

- Captures row data on `MainActor`.
- Calls `manager.analyzeAudioFile` directly, with `requestTimeout = rowTimeoutSeconds`.
- Updates the row on `MainActor` and sets BPM/Key match flags.

This fixed the earlier symptom where the outer task group never finished. We now see `[POOL EXIT] All rows processed` and `[EXIT] runFullAnalysisSession()` when runs are healthy.

#### Per-Row Analysis (nonisolated)

- `private nonisolated func analyzeRowNonisolated(at index: Int) async`
Key points of the current implementation:

- `analyzeRowNonisolated`:
  - Captures row data and sets `status = .running` on `MainActor`.
  - Awaits `manager.analyzeAudioFile` with the 130s timeout and filename‑derived title/artist.
  - On success: updates `analysis`, sets `status = .done`, computes BPM/Key matches.
  - On error: logs the error, sets `status = .failed`, and stores `rows[index].error = error.localizedDescription`.

The `runWithTimeout` helper has been **deleted**, removing nested task groups and client‑side racing behavior. Timeouts are now governed by:

- The `URLSession` request timeout (130s).
- The server’s own 120s analysis timeout.

#### Data Loading & Matching

Same as in the original handover, but now centralized in the controller:

- `loadDefaultSpotify()`, `loadDefaultFolder()`, `reloadSpotify()`, `importFolder`, `importFiles`.
- CSV parsing in `RepertoireSpotifyParser`.
- Spotify matching + BPM/key comparison via `ComparisonEngine`.

---

### 3. `MacStudioServerSimulator/MacStudioServerSimulator/Services/MacStudioServerManager+Analysis.swift`

Key points:

- `nonisolated func analyzeAudioFile(at:skipChunkAnalysis:forceFreshAnalysis:cacheNamespace:requestTimeout:titleOverride:artistOverride:)`
  - Builds a `POST /analyze_data` request.
  - Uses either:
    - AVFoundation metadata (`inferredMetadata(for:)`), or
    - `titleOverride` / `artistOverride` provided by Repertoire.
  - Applies:
    - `request.timeoutInterval = requestTimeout ?? 900`.
    - Headers:
      - `X-Song-Title`, `X-Song-Artist`.
      - `X-API-Key`.
      - `X-Skip-Chunk-Analysis` (optional).
      - `X-Force-Reanalyze` (set for Repertoire).
      - `X-Cache-Namespace` = `"repertoire-90"`.
  - Calls `performNetworkRequest` which uses `URLSession.shared.data(for:)` and decodes `MacStudioServerManager.AnalysisResult`.

This function is used by both Quick Analyze and Repertoire; only Repertoire uses the short timeout + title/artist overrides.

---

### 4. `MacStudioServerSimulator/MacStudioServerSimulator/Services/MacStudioServerManager+ServerControl.swift`

Relevant behavior:

- `func startServer() async`
  - Uses `resolvePythonExecutableURL()` (from `MacStudioServerManager+Python.swift`) to find the `.venv/bin/python`.
  - Launches `backend/analyze_server.py` as a subprocess with:
    - `PYTHONPATH` = repo root.
    - `ANALYSIS_WORKERS` = `"6"`.
    - `CLEAR_LOG` = `"1"`.
  - Waits ~1.5s, then calls `checkServerStatus()` (`/health`).

- `func stopServer(userTriggered:) async`
  - Calls `/shutdown` then `pkill` to kill `analyze_server.py` and spawn workers.

`RepertoireAnalysisController` currently uses these per run. ABCD tests manage their own server lifecycle via `run_test.sh`.

---

## Python Test & Tooling Context

These mirror the expected behavior and are useful for validating fixes:

- `tools/test_analysis_pipeline.py`
  - CLI wrapper:
    - `--preview-batch` (Test A): 6 previews.
    - `--preview-calibration` (Test C): 12 previews in 2 batches of 6.
  - Uses `AnalysisTestSuite` (from `test_analysis_suite.py`) which:
    - Spawns up to 6 concurrent HTTP calls using `ThreadPoolExecutor(max_workers=6)`.
    - Uses a 130s timeout per request (`requests.post(timeout=130)`).

- `tools/analyze_repertoire_90.py`
  - CLI tool for the same 90 previews used in the GUI.
  - Sequentially processes all 90 songs (no client-side pool) but demonstrates that the backend can handle the full set in a non-GUI context.

---

## Observations & Likely Issues (Unresolved)

Based on logs + code:

1. **Server is finishing; GUI hangs anyway**
   - Activity Monitor shows no active Python processes while GUI still shows “Analyzing…”.
   - Several rows are `Done`, some remain `Running`.
   - Logs show many `[TASK n] Task completed` / `[POOL] Task completed; inFlight=…`, but we don’t always see `[POOL EXIT] All rows processed` or `[EXIT] runFullAnalysisSession() complete`.

2. **Nested task groups + timeouts**
   - `runAnalysisBatches` uses `withTaskGroup`.
   - Each `analyzeRowNonisolated` uses `runWithTimeout`, which also uses `withThrowingTaskGroup`.
   - This means **two levels of task groups**, plus `URLSession`’s own timeout.
   - It is plausible that:
     - `runWithTimeout` completes in a way that the outer group doesn’t observe (e.g. if cancellation propagates unexpectedly).
     - A task gets stuck in a suspended state where neither the outer nor inner group sees completion, even though the HTTP work is done.

3. **Server-side behavior is not the only factor**
   - Earlier logs showed 120s timeouts and long runtimes for particular songs in `server.log`, but the GUI is still hanging even after we:
     - Shortened the client timeout to 45s.
     - Overrode metadata to avoid AVFoundation surprises.

Net: the **remaining bug is almost certainly in the Swift concurrency wiring**, not the analyzer itself.

---

## Suggestions for the Next Agent

Here’s a concrete sequence I recommend, starting with simplification and then re‑introducing concurrency:

1. **Remove inner `runWithTimeout` temporarily**
   - For debugging, change `analyzeRowNonisolated` to call `manager.analyzeAudioFile` directly (no `runWithTimeout`), still with `requestTimeout: rowTimeoutSeconds`.
   - This leaves only:
     - The `URLRequest.timeoutInterval` on the client.
     - The server’s internal 120s timeout.
   - Run with the 90‑preview set and observe:
     - Do we now see `[POOL EXIT] All rows processed`?
     - Does `runFullAnalysisSession` always log its `[EXIT]` line?

2. **If it still hangs, strip concurrency completely to validate the path**
   - Replace `runAnalysisBatches` with a simple sequential loop:

     ```swift
     for idx in rows.indices {
         await analyzeRowNonisolated(at: idx)
     }
     ```

   - Run on a smaller subset (e.g. first 12 rows) and then on the full 90.
   - If this never hangs, the underlying per‑row path is solid; the bug is purely in task-group usage.

3. **Rebuild 6‑at‑a‑time concurrency with minimal primitives**
   - Instead of nested `withTaskGroup`, consider:
     - A simple queue of indices.
     - 6 `Task.detached` workers that each:
       - Loop pulling the next index under a lock or an `AsyncStream`.
       - Call `analyzeRowNonisolated`.
     - A `TaskGroup` only at the outer “join workers” level.
   - Goal: avoid nested task groups per row.

4. **Simplify server lifecycle for Repertoire**
   - Consider **removing per‑run server start/stop** from `runFullAnalysisSession`:
     - Expect the user to manage the server (or use a top-level Start/Stop).
     - In Repertoire, just:
       - Check `isServerRunning`.
       - If false: show a clear alert and bail.
   - This removes another moving part and makes behavior more like the Python tests (which assume a running server).

5. **Align exactly with Test C semantics for a smaller fixture**
   - Create a “Repertoire 12” mode that uses the same 12 preview files as Test C, but in the Repertoire view.
   - Validate that:
     - 6 at a time.
     - Both batches finish.
     - No GUI hang.
   - If this passes consistently while the 90‑preview run hangs, the bug likely involves specific files or scaling behavior.

6. **When you get a stable fix, simplify logging**
   - The current logs are very verbose (debugging stage).
   - Once you’re confident, keep only:
     - High-level pool logs.
     - Per-row summary lines or errors.
     - Errors propagated to `alertMessage`.

---

## Summary

- The original “stall after first 6” has been replaced by:
  - A more robust controller (`RepertoireAnalysisController`) owning all Repertoire state and concurrency.
  - A 6‑worker pool over all rows.
  - Per-row HTTP timeouts and filename-based metadata, aligning more closely with the Python tests.
- The remaining issue is that **the pool sometimes never reports completion**, even after Python has finished. This is almost certainly due to nested `withTaskGroup` + timeout behavior in Swift, not the backend.
- The recommended path is to **simplify the concurrency** step by step (remove inner timeouts, then task groups) until the hang disappears, then reintroduce the minimum needed structure for “6 at a time,” modeled on the Python Test C behavior.

If you need a minimal repro, start by instrumenting a 12‑song subset and watching for the final `[POOL EXIT]` and `[EXIT] runFullAnalysisSession()` logs; that’s your signal that the controller’s concurrency loop is truly draining. Once that’s solid, scale back to the full 90‑preview repertoire. 
