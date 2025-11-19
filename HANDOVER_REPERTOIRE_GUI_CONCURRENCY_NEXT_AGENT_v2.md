# Handover – Repertoire GUI Concurrency (v2 Follow‑up)
_Date: 2025‑11‑19_

This document is a **delta handover** for the next agent, building on:

- `HANDOVER_REPERTOIRE_GUI_CONCURRENCY.md`
- `HANDOVER_REPERTOIRE_GUI_CONCURRENCY_NEXT_AGENT.md`

Read those first for the original architecture and rationale. This file captures the **current state after additional debugging** with Costas and the changes made during that session.

---

## 1. Current Behaviour Snapshot

- App: `MacStudioServerSimulator` → `Tests` tab → `Repertoire`.
- Dataset: `csv/90 preview list.csv` + `preview_samples_repertoire_90` (90 × 30s previews).
- Server:
  - Still `backend/analyze_server.py` on port `5050`.
  - `/analyze_data` path for direct binary uploads.
  - Analysis stack unchanged (librosa + calibration).

As of this handover:

- The Repertoire controller has been switched to **sequential debug mode** (no client‑side concurrency) to prove out correctness:
  - Only **one row at a time** is analyzed.
  - All rows go through `analyzeRowNonisolated(at:)`.
  - The run is expected to complete with `[POOL EXIT] All rows processed` and `[EXIT] runFullAnalysisSession() complete` in Xcode.
- The server now enforces a **hard timeout for each `/analyze_data` request** and logs per‑row client IDs.
- The GUI can **auto‑start the server** when an analysis call is made, so the user shouldn’t need to manually start it before using Repertoire or Quick Analyze.

The remaining user‑visible problem is mostly **perceived** rather than a strict deadlock:

- Some previews (rows ~13–18 and a few later ones) take **60–90s** to analyze or hit the new timeouts, so:
  - Activity Monitor looks idle after the “easy” songs finish.
  - The Repertoire overlay spinner remains while those slow/failed songs are processed.
  - From the user’s perspective, this still feels like “stuck after 12,” even though more rows do progress in the logs.

---

## 2. Swift‑Side Changes (GUI)

### 2.1 RepertoireAnalysisController

File: `MacStudioServerSimulator/MacStudioServerSimulator/RepertoireAnalysisController.swift`

Key points:

- `@MainActor final class RepertoireAnalysisController: ObservableObject`
  - `@Published var rows: [RepertoireRow]`
  - `@Published var isAnalyzing: Bool`
  - `@Published var alertMessage: String?`
  - `private let rowTimeoutSeconds: TimeInterval = 60`
  - `private var analysisTask: Task<Void, Never>?`

- **Entry point:**

  ```swift
  func startAnalysisFromButton() {
      analysisTask?.cancel()
      analysisTask = Task { [weak self] in
          await self?.runFullAnalysisSession()
      }
  }
  ```

- **Server lifecycle (Repertoire‑local):**

  ```swift
  private func runFullAnalysisSession() async {
      // ... guard !isAnalyzing, !rows.isEmpty ...
      isAnalyzing = true
      alertMessage = nil
      defer {
          isAnalyzing = false
          analysisTask = nil
      }

      await manager.startServer()
      guard manager.isServerRunning else {
          alertMessage = AudioAnalysisError.serverOffline.errorDescription ?? "Server offline"
          return
      }

      await runAnalysisBatches()

      await manager.stopServer(userTriggered: false)
  }
  ```

  - Repertoire **explicitly starts and stops** its own dedicated server for the run, independent of the ABCD tests.

- **Sequential debug mode (no concurrency):**

  ```swift
  private func runAnalysisBatches() async {
      print("[BATCH ENTRY] runAnalysisBatches() called")

      let indices = Array(rows.indices)
      print("[POOL] Sequential analysis for \(indices.count) rows (debug mode)")
      for idx in indices {
          print("[SEQ] Starting row index \(idx)")
          await analyzeRowNonisolated(at: idx)
          print("[SEQ] Finished row index \(idx)")
      }

      print("[POOL EXIT] All rows processed")
  }
  ```

  - This is a *temporary* step to eliminate Swift concurrency as a source of hangs.
  - Earlier 6‑at‑a‑time pool logic remains in git history and in the older handover docs but is currently not used.

- **Per‑row analysis off the main actor:**

  ```swift
  private nonisolated func analyzeRowNonisolated(at index: Int) async {
      // 1) Capture row from main actor, mark .running
      let rowData = await MainActor.run { ... }

      let (namespace, timeout) = await MainActor.run { (defaultNamespace, rowTimeoutSeconds) }
      let clientId = "repertoire-row-\(index + 1)"

      do {
          let result = try await self.manager.analyzeAudioFile(
              at: rowData.url,
              skipChunkAnalysis: false,
              forceFreshAnalysis: true,
              cacheNamespace: namespace,
              requestTimeout: timeout,
              titleOverride: rowData.title,
              artistOverride: rowData.artist,
              clientRequestId: clientId
          )
          await MainActor.run {
              rows[index].analysis = result
              rows[index].status = .done
              rows[index].bpmMatch = bpmMatch(for: rows[index])
              rows[index].keyMatch = keyMatch(for: rows[index])
          }
      } catch {
          // Logs URLError.timedOut specially
          await MainActor.run {
              rows[index].status = .failed
              rows[index].error = error.localizedDescription
          }
      }
  }
  ```

  - **Timeout behaviour:** `rowTimeoutSeconds = 60` is passed into `analyzeAudioFile`, which sets `URLRequest.timeoutInterval`.
  - On timeout you see in Xcode:
    - `Task … finished with error [-1001] ... The request timed out.`
    - `[ROW n] ERROR: Network timed out (60.0s)`
    - Row status switches to `.failed`, but the loop continues to the next index.

### 2.2 Server Auto‑Management for All Callers

File: `MacStudioServerSimulator/MacStudioServerSimulator/Services/MacStudioServerManager+Analysis.swift`

- `analyzeAudioFile` used to immediately throw `serverOffline` if `isServerRunning == false`.
- It now **tries to auto‑start the analyzer** before failing:

  ```swift
  nonisolated func analyzeAudioFile(...) async throws -> AnalysisResult {
      var serverRunning = await MainActor.run { isServerRunning }
      if !serverRunning {
          await autoStartServerIfNeeded(autoManageEnabled: true, overrideUserStop: true)
          serverRunning = await MainActor.run { isServerRunning }
      }
      guard serverRunning else {
          throw AudioAnalysisError.serverOffline
      }
      // ... build POST /analyze_data ...
  }
  ```

- This applies to:
  - Repertoire tab.
  - Quick Analyze.
  - Calibration flows.

Note: Repertoire also calls `manager.startServer()` explicitly in `runFullAnalysisSession`, so you effectively have **two protective layers** ensuring the server is up before analysis.

---

## 3. Python‑Side Changes (/analyze_data)

Files:

- `backend/server/analysis_routes.py`
- `backend/server/processing.py`

### 3.1 Client ID Tagging

- Swift sends `X-Client-Request-Id: repertoire-row-<rowNumber>`.
- `/analyze_data` logs that ID on every important line:

  - START:

    ```text
    ▶️ [req-...] START analyze_data title='...' artist='...' ... client_id=repertoire-row-15
    ```

  - DONE:

    ```text
    ✅ [req-...] DONE analyze_data title='...' ... client_id=repertoire-row-15
    ```

  - TIMEOUT:

    ```text
    ⏱️ [req-...] TIMEOUT analyze_data title='...' ... client_id=repertoire-row-15: Analysis timed out after 60s for '...'
    ```

  - ERROR: similar format with `client_id=...`.

This makes it easy to correlate:

- Repertoire row N ↔ `client_id=repertoire-row-N` in `server.log`.

### 3.2 Hard Timeout for Direct Uploads

- `/analyze_data` now uses:

  ```python
  result = process_audio_bytes(
      audio_data,
      title,
      artist,
      skip_chunk,
      load_kwargs,
      use_tempfile=True,
      temp_suffix=".m4a",
      max_workers=0,
      timeout=60,  # 60s cap for previews
  )
  ```

- In `backend/server/processing.py`, when `max_workers == 0`:
  - `process_audio_bytes` runs `_run_analysis_inline` inside a temporary `ThreadPoolExecutor`.
  - It calls `future.result(timeout=timeout)` and raises `TimeoutError` on expiry.
  - The `TimeoutError` is caught in `/analyze_data` and returned as HTTP 504 with the log line above.

### 3.3 What the latest logs show

Recent `server.log` excerpts show:

- For “problem” mid‑list songs (rows ~13–18, titles like **Shay Tequila**, **Kooks Naive**, **House Don’t Dream It’s Over**, **House Better Be Home Soon**, **Isaak Baby Did A Bad Bad Thing Acoustic 1995**, **Stapleton Tennessee Whiskey**):
  - Multiple `⏱️ TIMEOUT analyze_data ... client_id=repertoire-row-<13..18>` entries.
  - Durations ~78–90s due to time spent inside analysis before the timeout kicks.
- For later songs (rows 19–24 like **West King Of Wishful Thinking**, **Dance the Night**, etc.):
  - Normal `START` + `DONE` with durations ~24s, confirming the server continues processing beyond the “first 12”.

Conclusion: from the server’s perspective, there is no hard “12‑song cap”; the bottleneck is specific slow songs plus timeouts, not a global stall.

---

## 4. How to Reproduce & Inspect (Next Agent)

### 4.1 Running the GUI

1. Open `MacStudioServerSimulator.xcworkspace` in Xcode.
2. Run the `MacStudioServerSimulator` macOS target.
3. In the app:
   - Top segmented control: `Tests`.
   - Mode: `Repertoire`.
4. Let defaults load:
   - CSV: `csv/90 preview list.csv`.
   - Folder: `~/Documents/Git repo/Songwise 1/preview_samples_repertoire_90`.
5. Press **Analyze with Latest Algorithms**.

You’ll see:

- Sequential analysis (`[SEQ] Starting row index n` logs in Xcode).
- Some rows turning `Failed` after ~60s (per‑row timeout).
- The spinner remains until all 90 rows are either `Done` or `Failed` and `[POOL EXIT]` prints.

### 4.2 Inspecting a “stuck” row

From the GUI:

- Note the row number (e.g. row 15).
- Its `client_id` is `repertoire-row-15`.

From the server log:

```bash
rg "client_id=repertoire-row-15" "$HOME/Music/AudioAnalysisCache/server.log"
```

Check whether you see:

- `START` + `DONE` → server finished normally.
- `START` + `TIMEOUT` → server exceeded 60s and aborted.

From Xcode:

- Look for matching `[ROW 14]` / `[ROW 15]` lines and the final `[SEQ] Finished row index 14` etc.

---

## 5. Remaining Issues & Next Steps

### 5.1 What’s fixed / clarified

- The original task‑group pool stalling after 6 is no longer in play; Repertoire is currently sequential.
- The GUI and backend now share:
  - Per‑request timeout (~60s).
  - Explicit TIMEOUT logging with per‑row client IDs.
- Repertoire no longer requires the user to manually start the server:
  - `runFullAnalysisSession` calls `startServer`/`stopServer`.
  - `analyzeAudioFile` also auto‑starts the analyzer if needed.

### 5.2 What still needs work

1. **Performance / robustness of certain previews**
   - Several tracks in the 13–18 range either:
     - Take close to a minute and a half to analyze, or
     - Hit the 60s timeout repeatedly.
   - These songs dominate the perceived runtime and should be profiled:
     - Focus on tempo analysis (`tempo.beat_track`, `tempo.tempogram`, etc.), which shows large portions of the timing budget.
   - Consider preview‑specific tuning (e.g., shorter `MAX_ANALYSIS_SECONDS`, lighter calibration) for GUI runs.

2. **Re‑introducing 6‑at‑a‑time concurrency safely**
   - Once sequential mode is stable and you’re satisfied with timeouts:
     - Re‑implement 6‑way concurrency in `runAnalysisBatches`, but keep it **simple and batch‑oriented** (e.g., batches of 6 using a `TaskGroup`), or
     - Model it closely on `tools/test_analysis_suite.py`’s `ThreadPoolExecutor(max_workers=6)`.
   - Keep the per‑row timeout logic and client IDs as they are.

3. **UI ergonomics**
   - The overlay spinner currently reflects the entire run (`isAnalyzing`), so long‑running or failing songs make it feel “stuck”.
   - You may want to:
     - Show a secondary status line (“Row N of 90”) or
     - Dim the spinner only around the currently running rows while allowing scrolling/editing.

4. **Server auto‑manage policy**
   - Repertoire now both:
     - Starts a fresh server for the run.
     - Uses `autoStartServerIfNeeded` inside `analyzeAudioFile`.
   - Decide whether to:
     - Keep the Repertoire‑specific start/stop (isolated session semantics), or
     - Rely solely on auto‑manage and treat the analyzer as a shared resource.

---

## 6. Suggested Plan for the Next Agent

1. **Run a full sequential Repertoire pass** with Xcode + Logs tab open.
   - Confirm `[POOL EXIT]` and `[EXIT]` always appear.
   - Note which rows hit `TIMEOUT` in `server.log`.
2. **Address slow/timeout songs**
   - Profile those specific previews in isolation via `tools/test_analysis_pipeline.py --preview-batch` or a small custom script hitting `/analyze_data`.
   - Tweak analysis settings (e.g., `MAX_ANALYSIS_SECONDS`, tempo search windows) for preview mode.
3. **Reintroduce controlled concurrency**
   - Replace the sequential loop with a simple “batches of 6” `TaskGroup` as described in the original handovers.
   - Keep per‑row timeouts and client IDs.
   - Watch for any reappearance of “pool never exits”; if it does, the bug is in new concurrency wiring rather than the backend.
4. **Polish UX**
   - Once behaviour is solid, tone down some of the debug logging in both Swift and Python.
   - Update any user‑facing copy (alerts, status text) that still assumes manual server management.

With these steps, you should be able to move from the current sequential, fully‑instrumented “debug mode” back to a production‑ready 6‑at‑a‑time Repertoire analysis that matches the behaviour of the Python Test C harness. 

---

### 2025-11-19 Hotfix (Root cause finally nailed)

- The analyzer process pool was dying mid-run. The GUI kept waiting because the task group never advanced when the workers were gone. Activity Monitor clearly showed Python processes disappearing.
- Fix applied in `RepertoireAnalysisController.runAnalysisBatches`: process rows in batches of 6, **restart the analyzer between batches**, and bail if it fails to come up. Each row also restarts/retries once on timeout.
- Net effect: even if the pool crashes, the next batch forces a fresh analyzer and the run continues instead of hanging after ~row 7/12/14.
- The GUI now uses a restart path that **skips preflight /health checks** when we know the server is down, so the Console no longer fills with `Could not connect to the server` errors between batches. Transient CFNetwork warnings may still appear if the user manually stops the server mid-run, but a normal 90-song pass is now log‑friendly.
