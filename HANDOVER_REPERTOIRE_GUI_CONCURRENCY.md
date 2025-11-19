# Handover – Repertoire GUI Concurrency & 6‑at‑a‑Time Analysis  
_Date: 2025‑11‑18_

## Scope

This handover is for the next agent working on:

- Fixing the **Repertoire** tab in the `MacStudioServerSimulator` app so that:
  - It runs **up to 6 analyses in parallel**.
  - It **continues through the entire queue** (e.g. all 90 previews) without stalling.
  - The UI state (`status`, `isAnalyzing`, matches) stays accurate.
- Aligning GUI behavior with the existing Python **ABCD tests** and the **90‑preview repertoire** tooling.
- Doing this in a way that follows **Swift concurrency best practices** and respects the audio‑analysis server’s design.

You do **not** need to change the underlying BPM/Key algorithms here; focus is on concurrency, batching, and robustness in the GUI + client/server interaction.

---

## Current Behavior & Bug

### Reproduction (GUI)

1. Build and run `MacStudioServerSimulator` in Xcode.
2. In the app:
   - Top segmented control: select `Tests`.
   - In the Tests tab’s inner segmented picker: select **Repertoire**.
3. Let the defaults load:
   - CSV: `csv/90 preview list.csv` (from the repo).
   - Audio folder: `~/Documents/Git repo/Songwise 1/preview_samples_repertoire_90`.
4. Click **“Analyze with Latest Algorithms”**.

Observed:

- The app processes **6 songs** (you see their status flip from `Pending` to `Running` to `Done`).
- Then it **stops advancing**:
  - Remaining rows stay in `Pending`.
  - The overlay spinner (“Analyzing…”) remains visible.
  - The Python server logs show that the initial 6 analyses completed; it’s not just a backend hang.

The same “stall after first 6” behavior appears even when the server responses are correct and fast, so this is primarily a **client‑side concurrency / task‑lifecycle issue**, not a timeout.

### Repertoire Tab Implementation (Today)

File:  
`MacStudioServerSimulator/MacStudioServerSimulator/ServerManagementTestsTab.swift`

Key pieces:

- `struct TestsTab: View`
  - Hosts segmented control: `ABCD Tests` vs `Repertoire`.
  - When `.repertoire` is selected, it shows:
    - `RepertoireComparisonTab(manager: manager)`
- `struct RepertoireComparisonTab: View`
  - `@ObservedObject var manager: MacStudioServerManager`
  - Local `@State`:
    - `rows: [RepertoireRow]`
    - `spotifyTracks: [RepertoireSpotifyTrack]`
    - `isAnalyzing: Bool`
    - `isTargeted`, `alertMessage`
  - Default loading:
    - `loadDefaultSpotify()` → `csv/90 preview list.csv` from repo root.
    - `loadDefaultFolder()` → `~/Documents/Git repo/Songwise 1/preview_samples_repertoire_90`.
  - User actions:
    - `reloadSpotify()` (CSV picker).
    - `pickFolder()` (audio folder picker).
    - Drag‑and‑drop of `.m4a` / `.mp3`.
  - Analysis entry point:
    - Analyze button calls `Task { await runAnalysis() }`.

#### Current `runAnalysis()` Logic (important)

At the time of this handover, `runAnalysis()` roughly does:

- Guard that `rows` is non‑empty (via `MainActor.run`).
- Set `isAnalyzing = true` (inside `MainActor.run`), and use `defer` to restore it to `false`.
- Call `manager.autoStartServerIfNeeded(autoManageEnabled: true, overrideUserStop: true)`.
- Guard that `manager.isServerRunning` is `true`; otherwise show `AudioAnalysisError.serverOffline`.
- Snapshot all row indices (`Array(rows.indices)`) into a local `indices` array.
- Process indices in **batches of 6**:
  - For each batch:
    - Use `await withTaskGroup(of: Void.self)` and, for each index in the batch, add a child task that calls:
      - `await analyzeRowWithTimeout(at:index, timeoutSeconds: 120)`
    - After the group completes, move on to the next batch until `start >= indices.count`.

Relevant helpers:

- `analyzeRowWithTimeout(at:timeoutSeconds:)`:
  - Wraps `analyzeRow(at:)` in a `withTimeout(seconds:operation:)` helper, using a `withThrowingTaskGroup` for timeout vs work race.
  - On timeout / error: marks the row as `.failed` and sets `row.error`.
- `analyzeRow(at:)`:
  - On `MainActor`: marks row as `.running` and snapshots `url`.
  - Calls `manager.analyzeAudioFile(...)` (async network + local I/O) with:
    - `skipChunkAnalysis: false`
    - `forceFreshAnalysis: true`
    - `cacheNamespace: "repertoire-90"`
  - On success:
    - Sets `row.analysis`.
    - Marks `row.status = .done`.
    - Updates `bpmMatch` and `keyMatch` using `ComparisonEngine.compareBPM` / `compareKey`.
  - On error:
    - Marks `.failed` with error message.

`RepertoireRow` is a value type storing `index`, `url`, filename, guess artist/title, optional Spotify row, optional `AnalysisResult`, and match / status fields. It lives in the same Swift file.

### Server‑Side Overview

Python server entry: `backend/analyze_server.py`

- Flask app exposing:
  - `/health`, `/stats` (status).
  - `/analyze_data` (single‑file analysis).
  - `/analyze_batch` (multi‑file analysis).
  - Cache and calibration endpoints.
- Concurrency:
  - Uses `ProcessPoolExecutor` via `backend/server/processing.py::get_analysis_executor`.
  - Worker count controlled by env var `ANALYSIS_WORKERS` (via `backend/analysis/settings.py`).
  - This matches common guidance for CPU‑bound audio feature extraction: a **small process pool** (2–4 workers) rather than unbounded threads.

Key routes:

- `/analyze_data`:
  - Accepts a single file (direct upload).
  - Does cache lookup, runs analysis via the process pool, applies calibration, writes results to cache, returns JSON with BPM/Key/etc.
- `/analyze_batch`:
  - Accepts JSON array of `{ audio_data (base64), title, artist }`.
  - **Processes items sequentially within the request** (the comment explicitly says parallelism is intended to come from the client sending multiple batch requests).
  - Max 10 items per batch.

### Existing Test Concurrency (Reference)

Python tools that inspired the “6 at a time” requirement:

- `tools/test_analysis_suite.py`
  - `test_batch_analysis(batch_size=6, use_preview=True, ...)`:
    - Uses `concurrent.futures.ThreadPoolExecutor(max_workers=batch_size)` to fire **6 concurrent HTTP POSTs** to `/analyze_data`.
  - `test_full_calibration(use_preview=True)`:
    - Splits 12 songs into 2 batches of 6, each batch using `ThreadPoolExecutor(max_workers=6)`.
- `tools/test_analysis_pipeline.py`
  - CLI wrapper for the above suite:
    - `--preview-batch` (Test A) → 6 previews.
    - `--preview-calibration` (Test C) → 12 previews in 2 batches of 6.

So the **expected behavior** from the GUI’s perspective is:

- Up to 6 songs in flight at once.
- All queued songs eventually analyzed (2 × 6 for Test C, ~90 for Repertoire).

The CLI tools currently work reliably with this pattern; the bug is localized to the macOS GUI implementation.

---

## Likely Root Causes (Client Side)

Based on the current code and Swift concurrency guidance, the stall after the first 6 is most likely due to one or more of:

1. **Task lifecycle vs view lifecycle**
   - `runAnalysis()` is invoked via an unstructured `Task { ... }` in the SwiftUI view.
   - SwiftUI can re‑create views, cancel tasks, or change state mid‑run; if the owning view disappears or re‑renders with a new identity, the task or its child tasks may be cancelled.
   - This could leave `rows` partially updated and `isAnalyzing` stuck `true` (because the `defer` may never run if the task is cancelled at the wrong point).

2. **Complex actor hopping + captured `self` in task groups**
   - We’re mixing:
     - `Task { await runAnalysis() }` (unstructured).
     - Multiple `MainActor.run` calls to read/write `rows` and `isAnalyzing`.
     - `withTaskGroup` with child tasks capturing `self` (the view struct).
   - This pattern is fragile and more error‑prone than having a single `@MainActor` model own both state and concurrency.

3. **Timeout wrapper complexity**
   - The `analyzeRowWithTimeout` + `withTimeout` helper introduces an inner `withThrowingTaskGroup` for every row.
   - This adds more nesting and cancellation behavior that can interact badly with the outer task group and unstructured `Task`.

Note: the user explicitly reported that the analysis *finished* for the first 6 songs (results visible), so the stall is unlikely to be a backend timeout. It’s more likely that **the outer loop or task group never proceeds to the second batch**, either due to cancellation or a logic bug, leaving the rest of the rows untouched.

---

## Goals for the Next Agent

1. **Correctness**
   - Repertoire tab processes **all rows** in the table (e.g. the full 90‑preview set) without stalling.
   - Individual rows show accurate statuses: `Pending` → `Running` → `Done` / `Failed`.
   - `isAnalyzing` is `true` only while work is ongoing and returns to `false` at the end or on cancellation/error.

2. **Concurrency semantics**
   - At most **6 concurrent analyses at a time**.
   - If one row fails, the rest continue.
   - Optional: maintain an easy way to switch between:
     - One‑by‑one (fully sequential).
     - 6‑at‑a‑time (preferred).

3. **Architecture / best practice**
   - Move the “long‑running async + task group” logic out of the SwiftUI view into a dedicated type (model/controller) that owns `rows` and `isAnalyzing`.
   - Ensure all UI state mutations happen on the main actor (`@MainActor`), but heavy work (network requests / file I/O) doesn’t block it.

4. **Maintain alignment with Python tooling**
   - Keep the semantics roughly consistent with:
     - Test A / Test C concurrency behavior.
     - The repertoire CLI (`tools/analyze_repertoire_90.py`) in terms of per‑song headers (`X-Force-Reanalyze`, `X-Cache-Namespace`).

---

## Recommended Implementation Strategy

### 1. Introduce a Dedicated Analysis Controller (New Type)

Rather than adding a `RepertoireViewModel` by name, introduce a small controller/model type specifically for the Repertoire tab. Suggested name:

- `RepertoireAnalysisController` (but any clear name is fine).

Suggested location:

- New file: `MacStudioServerSimulator/MacStudioServerSimulator/RepertoireAnalysisController.swift`

Shape:

```swift
@MainActor
final class RepertoireAnalysisController: ObservableObject {
    @Published var rows: [RepertoireRow] = []
    @Published var spotifyTracks: [RepertoireSpotifyTrack] = []
    @Published var isAnalyzing = false
    @Published var alertMessage: String?

    private let manager: MacStudioServerManager
    private var analysisTask: Task<Void, Never>?

    init(manager: MacStudioServerManager) {
        self.manager = manager
    }

    func startAnalysis() {
        // Implementation described below
    }

    // Methods: importFiles, loadSpotify, applyIndexMappingIf1to1, etc.
}
```

Key points:

- Mark the class `@MainActor` so all its state (`rows`, `isAnalyzing`, `alertMessage`) is main‑isolated and safe to mutate from UI.
- Inject `MacStudioServerManager` so the controller can call `analyzeAudioFile` and `autoStartServerIfNeeded`.
- Store a `Task` handle (`analysisTask`) so you can cancel in‑flight analyses if needed (e.g. user clicks “Stop” or re‑runs).

### 2. Move State and Helper Methods into the Controller

From `RepertoireComparisonTab`, move the following into the controller:

- State:
  - `rows`, `spotifyTracks`, `isAnalyzing`, `alertMessage`.
- Data loading:
  - `loadDefaultSpotify()`, `loadDefaultFolder()`.
  - `reloadSpotify()` / `loadSpotify(from:)`.
  - `pickFolder()` / `importFolder(_:)` / `importFiles(_:)`.
- Spotify mapping:
  - `applyIndexMappingIf1to1()`, `matchSpotify(for:)`.
- Match helpers:
  - `bpmMatch(for:)`, `keyMatch(for:)`.

The view then becomes a thin wrapper that:

- Owns `@StateObject var controller: RepertoireAnalysisController`.
- Binds its UI to `controller.rows`, `controller.spotifyTracks`, `controller.isAnalyzing`, `controller.alertMessage`.
- Calls `controller.startAnalysis()` inside a `Task` from the Analyze button.

Example:

```swift
struct RepertoireComparisonTab: View {
    @ObservedObject var manager: MacStudioServerManager
    @StateObject private var controller: RepertoireAnalysisController

    init(manager: MacStudioServerManager) {
        _controller = StateObject(wrappedValue: RepertoireAnalysisController(manager: manager))
        self.manager = manager
    }

    var body: some View {
        // Use controller.rows, controller.isAnalyzing, controller.alertMessage, etc.
        Button {
            Task { await controller.startAnalysis() }
        } label: {
            Label("Analyze with Latest Algorithms", systemImage: "play.fill")
        }
        .disabled(controller.rows.isEmpty || controller.isAnalyzing)
    }
}
```

This mirrors the pattern Apple recommends: SwiftUI view → calls into model/controller → model handles async work + state.

### 3. Implement 6‑at‑a‑Time Batching in the Controller

In `RepertoireAnalysisController.startAnalysis()`:

1. Guard for preconditions:
   - `guard !rows.isEmpty, !isAnalyzing else { return }`.
2. Set `isAnalyzing = true` and `alertMessage = nil`.
3. Cancel any existing `analysisTask` if you decide to keep a “re‑run” affordance.
4. Create a new `analysisTask`:

```swift
func startAnalysis() async {
    guard !rows.isEmpty, !isAnalyzing else { return }
    isAnalyzing = true
    alertMessage = nil

    // Ensure server is running.
    await manager.autoStartServerIfNeeded(autoManageEnabled: true, overrideUserStop: true)
    guard manager.isServerRunning else {
        alertMessage = AudioAnalysisError.serverOffline.errorDescription
        isAnalyzing = false
        return
    }

    let indices = Array(rows.indices)
    let batchSize = 6

    do {
        var start = 0
        while start < indices.count {
            if Task.isCancelled { break }

            let end = min(start + batchSize, indices.count)
            let batch = Array(indices[start..<end])

            try await analyzeBatch(indices: batch)
            start = end
        }
    } catch {
        alertMessage = error.localizedDescription
    }

    isAnalyzing = false
}
```

Where `analyzeBatch(indices:)` uses a `TaskGroup`:

```swift
private func analyzeBatch(indices: [Int]) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in indices {
            group.addTask { [weak self] in
                guard let self else { return }
                try await self.analyzeRow(at: index)
            }
        }
        try await group.waitForAll()
    }
}
```

And `analyzeRow(at:)` is a `@MainActor` method on the controller:

```swift
private func analyzeRow(at index: Int) async throws {
    guard rows.indices.contains(index) else { return }
    rows[index].status = .running
    let fileURL = rows[index].url

    do {
        let result = try await manager.analyzeAudioFile(
            at: fileURL,
            skipChunkAnalysis: false,
            forceFreshAnalysis: true,
            cacheNamespace: "repertoire-90"
        )

        guard rows.indices.contains(index) else { return }
        rows[index].analysis = result
        rows[index].status = .done
        rows[index].bpmMatch = bpmMatch(for: rows[index])
        rows[index].keyMatch = keyMatch(for: rows[index])
    } catch {
        guard rows.indices.contains(index) else { return }
        rows[index].status = .failed
        rows[index].error = error.localizedDescription
        throw error
    }
}
```

Notes:

- Because the controller is `@MainActor`, you may want to offload file I/O (`Data(contentsOf:)`) to a detached task if you see UI jank. However, the existing `analyzeAudioFile` already uses `async` networking via `URLSession`, so you don’t strictly need to redesign that now.
- You can drop the custom `withTimeout` wrapper and rely on the server‑side timeouts unless you specifically want a shorter per‑row timeout.

### 4. Option: Use `/analyze_batch` Instead of Per‑File Calls

If you want to reduce HTTP overhead and more closely mirror the “batch of 6” semantics, you can:

- For each batch of up to 6 indices:
  - Read and base64‑encode the audio files.
  - Build JSON payload for `/analyze_batch`.
  - Map the returned array of results back onto `rows[index]`.

The server’s `/analyze_batch` route already:

- Enforces a max of 10 items per request.
- Processes items sequentially server‑side, but expects **client‑side parallelism** (e.g. multiple batch requests in flight if desired).

Given you only want 6 at a time, using a single `/analyze_batch` per 6 files is a reasonable approach. However, you must carefully map by index to ensure each result is applied to the right row.

If you go this route, you can encapsulate it in a helper on `MacStudioServerManager` similar to the existing `analyzeBatchFiles` function.

---

## Instrumentation & Debugging Suggestions

Before and after refactoring, you may want to add temporary logging (to Xcode console) to understand behavior:

- In the controller’s `startAnalysis()`:
  - Log total number of rows and each batch’s index range.
  - Log when each batch starts and completes.
- In `analyzeRow(at:)`:
  - Log when each row moves to `running`, `done`, or `failed`.
- Check `Task.isCancelled` between batches and log when cancellation happens.

Also check:

- Python server logs (configured via `backend/analyze_server.py`) to confirm that when the GUI appears to stall, the server is no longer receiving requests for subsequent songs.
- The macOS app’s **Logs** tab to ensure no request‑level errors are being swallowed.

Once the bug is resolved, you can remove or comment out the most verbose logs.

---

## Testing Checklist

1. **Basic functional test**
   - Start `MacStudioServerSimulator`.
   - Load default Repertoire dataset (CSV + 90 previews folder).
   - Click Analyze.
   - Expected:
     - At most 6 rows show `Running` at any given moment.
     - All rows eventually transition to `Done` / `Failed`.
     - Spinner disappears and `isAnalyzing` becomes `false` at the end.

2. **Partial failure test**
   - Temporarily break a few audio files (e.g. rename or corrupt them) to force errors.
   - Expected:
     - Failed rows marked as `Failed` with an error tooltip.
     - Remaining rows continue to process.

3. **Repeat run test**
   - Run Analyze once (full set).
   - Run it again without restarting the app.
   - Expected:
     - Cache behavior: faster runs if you toggle `forceFreshAnalysis` appropriately.
     - No stalls after the first 6; second run should behave identically.

4. **Alignment with CLI**
   - Run:
     - `./run_test.sh a` (6 previews).
     - `./run_test.sh c` (12 previews in 2 batches).
   - Compare total time and per‑song behavior to what you see from the Repertoire GUI targeting the same server.

---

## Notes on Existing Experimental Changes

At the point of this handover, `ServerManagementTestsTab.swift` already contains:

- A first attempt to add **6‑at‑a‑time batching** and a **per‑row timeout helper** (`analyzeRowWithTimeout`, `withTimeout`, `TimeoutError`).
- Multiple `MainActor.run` calls inside the view struct to manage `rows` and `isAnalyzing`.

You are free to:

- **Refactor or remove** this experimental logic in favor of the cleaner controller‑based approach described above.
- Simplify `runAnalysis()` back to a sequential loop temporarily while you build out the new controller.

The important thing is the **final behavior**, not preserving this intermediate implementation.

---

## Summary for the Next Agent

- The Repertoire tab is the primary GUI for evaluating BPM/Key accuracy on the 90‑preview Spotify repertoire set.
- The current implementation tries to run 6 analyses at a time but stalls after the first batch.
- The backend server and Python test tooling already support and expect 6‑concurrent‑request behavior.
- Your job is to:
  1. Move Repertoire analysis logic into a dedicated `@MainActor` controller/model.
  2. Implement robust 6‑at‑a‑time batching using `TaskGroup`, with clear per‑row and global state management.
  3. Ensure the entire queue processes without stalling and that the UI reflects the true state of the analysis.

If you follow the controller‑based strategy above, you’ll be aligned with both **Swift concurrency best practice** and the existing **audio‑analysis architecture** in this repo.

