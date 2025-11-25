# Handover – Repertoire Comparison GUI & 90‑Preview Evaluation  
_Date: 2025‑11‑18_

## Scope

This handover is for the next agent working on:

- Evaluating BPM/Key accuracy on the 90‑preview repertoire set.
- Using and extending the MacStudioServerSimulator GUI “Repertoire” view.
- Keeping behavior aligned with the existing ABCD test suite and Test C research.

It assumes you are in the `EssentiaServer` repo at:

`/Users/costasconstantinou/Documents/GitHub/EssentiaServer`

There is a separate SwiftUI test app (`EssentiaTestRunner`) in  
`/Users/costasconstantinou/Documents/Git repo/EssentiaTestRunner`, but the **primary GUI** for this work is the macOS app `MacStudioServerSimulator`.

---

## Key Artifacts

### Data & Audio

- Ground‑truth table for 90 previews:  
  `csv/90 preview list.csv`
  - Columns used: `Song`, `Artist`, `BPM`, `Key`, `Camelot` (optional fallback).
- Audio previews (30‑sec clips, 1:1 with the CSV, ordered):  
  `~/Documents/Git repo/Songwise 1/preview_samples_repertoire_90`
  - Filenames like `001_Savage_Garden_I_Knew_I_Loved_You.m4a`, etc.

### Python Tooling

- Analyze the 90 previews against the current server:
  - `tools/analyze_repertoire_90.py`
    - Sends each file in `preview_samples_repertoire_90` to `/analyze_data`.
    - Uses `X-Force-Reanalyze: 1` and cache namespace `repertoire-90`.
    - Writes a CSV under `csv/test_results_*.csv` with full MIR metrics.
- Compare results vs Spotify ground truth:
  - `analyze_repertoire_90_accuracy.py`
    - Loads `csv/90 preview list.csv` as expected values.
    - Finds the latest `test_results_*.csv` that has `test_type == "repertoire-90"`.
    - Compares BPM with tolerance (+ octave/half‑time checks) and keys with `key_utils.keys_match_fuzzy`.
    - Outputs per‑song detail and a summary of BPM and Key accuracy.

Current accuracy (from the last run before this handover) is **low** (~16% combined BPM+Key correctness), even after fixing CSV matching. Expect a lot of red in the comparison output; this is **by design** at this stage to surface algorithm weaknesses honestly (no per‑song hacks).

---

## MacStudioServerSimulator – Current Behavior

### Overview

The macOS app in `MacStudioServerSimulator` is the main control panel for the local audio‑analysis server. It has:

- Two top‑level tabs: **Tests** and **Logs** (Overview / Cache / Calibration were hidden for this work).
- A header showing server status (`Server Running` / `Server Stopped`) and a `Check Status` button.
- **Automated server management** for the operations we care about here (no manual Start/Stop buttons).

Entry point:
- `backend/ServerManagerApp.swift` → `ServerManagementView()`  
- Main UI: `MacStudioServerSimulator/MacStudioServerSimulator/ServerManagementView.swift`

### Tests Tab – Modes

File: `MacStudioServerSimulator/MacStudioServerSimulator/ServerManagementTestsTab.swift`

The Tests tab now has its own segmented control:

- `ABCD Tests` — existing performance and batch tests (A–D).  
  - Still driven by `ABCDTestRunner`, which shells out to `run_test.sh` and manages its own server process.
- `Repertoire` — **new mode** for 90‑preview comparison against Spotify.

#### Repertoire Mode – What It Does

View: `RepertoireComparisonTab`

- **Default inputs**:
  - Spotify CSV: `repoRoot/csv/90 preview list.csv`
  - Audio folder: `~/Documents/Git repo/Songwise 1/preview_samples_repertoire_90`
- **Import behavior**:
  - “Choose Preview Folder…” opens an `NSOpenPanel` for a directory.
  - Drag & drop of `.m4a` / `.mp3` files or a folder onto the table also imports.
  - Filenames are parsed as `index_artist_title.ext`:
    - Leading numeric index is stripped.
    - First token → artist guess.
    - Remaining tokens → title guess.
- **Spotify mapping**:
  - When both lists are loaded and `spotifyTracks.count == rows.count`, we assume a **1:1 ordered mapping**:
    - `rows[i].spotify = spotifyTracks[i]` for all i.
  - If counts differ, it falls back to a simple normalized title/artist matcher, but for the intended 90‑preview flow this should be a perfect 1:1 mapping.
- **Analysis button**:
  - “Analyze with Latest Algorithms”:
    1. Calls `manager.autoStartServerIfNeeded(autoManageEnabled: true, overrideUserStop: true)` to ensure the Python server is running.
       - This wraps `startServer()` and uses the same auto‑manage logic as elsewhere in the app.
    2. For each row, calls:
       - `manager.analyzeAudioFile(at: url, skipChunkAnalysis: false, forceFreshAnalysis: true, cacheNamespace: "repertoire-90")`
       - Response is decoded via `MacStudioServerManager.AnalysisResult` (`MacStudioServerSimulator/MacStudioServerSimulator/Services/MacStudioServerManager+AnalysisResult.swift`).
    3. Stores `bpm` and `key` from the JSON response into the row and updates:
       - `bpmMatch` and `keyMatch` using `ComparisonEngine.compareBPM` / `compareKey` (same logic used for ABCD/Test C analysis in `AnalysisComparison.swift`).
  - The button is always enabled when there are rows; if the server cannot be started or contacted you get a clear alert.
- **Table columns**:
  - `#`, `File`, `Artist`, `Title`
  - `Spotify BPM / Key` (from CSV)
  - `Detected BPM / Key` (from analyzer)
  - `BPM Match` (`MetricMatch`: green match / red mismatch / gray unavailable)
  - `Key Match` (same)
  - `Status` (`Pending`, `Running`, `Done`, `Failed`)

Under the hood, this reuses:

- `ComparisonEngine` and `MetricMatch` from `MacStudioServerSimulator/MacStudioServerSimulator/AnalysisComparison.swift`
  - BPM tolerance ±3; treats half‑time/double‑time within tolerance as a “match” (for metrics, even though they’re octave errors logically).
  - Key normalization is enharmonic and mode‑aware (similar semantics to `key_utils.py` on the Python side).

### Server Management Changes

File: `MacStudioServerSimulator/MacStudioServerSimulator/ServerManagementView.swift`

- Header (`ServerStatusHeader`) now only shows:
  - Status indicator (green/red dot, “Server Running/Stopped”, port).
  - Error text if `manager.errorMessage` is non‑nil.
  - A **single button**:
    - `Check Status` → `manager.checkServerStatus()` and `fetchServerStats(silently: true)` when running.
- Manual buttons for **Start Server / Stop / Restart** were intentionally removed from the header.

Automated server control lives in `MacStudioServerManager`:

- `startServer()`, `stopServer()`, `restartServer()` and helpers in  
  `MacStudioServerSimulator/MacStudioServerSimulator/Services/MacStudioServerManager+ServerControl.swift`
- `autoStartServerIfNeeded(autoManageEnabled:overrideUserStop:)` orchestrates:
  - `/health` check.
  - Respecting `userStoppedServer` unless `overrideUserStop == true`.
  - Spawning `analyze_server.py` from `backend/analyze_server.py` with the proper `PYTHONPATH`, env vars, and logs.

The ABCD tests **still** rely on `run_test.sh` in the Python repo to manage the server for those tests. The Repertoire view uses the auto‑managed local server instead.

---

## How to Reproduce Current Results

### CLI Path

1. From `EssentiaServer` root, ensure the virtualenv is ready (see existing docs such as `RUN_TESTS.md` if needed).
2. Start the analyzer server manually if you want CLI control:
   ```bash
   .venv/bin/python backend/analyze_server.py
   ```
3. Run the repertoire analysis:
   ```bash
   .venv/bin/python tools/analyze_repertoire_90.py --csv-auto
   ```
4. Compare vs Spotify:
   ```bash
   python3 analyze_repertoire_90_accuracy.py
   ```
   This prints per‑song comparisons and a summary of BPM / Key accuracy and error types.

### GUI Path (MacStudioServerSimulator)

1. Build & run the **MacStudioServerSimulator** macOS app in Xcode.
2. In the window:
   - Ensure the top segmented control is on `Tests`.
   - In the Tests tab, switch the inner mode picker to **Repertoire**.
3. On first load, the app will attempt to:
   - Load `csv/90 preview list.csv` from the repo.
   - Load `preview_samples_repertoire_90` from the Songwise repo path.
   - If either is missing, use the buttons:
     - “Choose Preview Folder…” for the audio folder.
     - “Reload Spotify CSV” if you want to pick a CSV manually.
4. Click **“Analyze with Latest Algorithms”**:
   - The app auto‑starts the analyzer via `autoStartServerIfNeeded`.
   - The table fills in detected BPM/Key and red/green badges for each track.

Use the Logs tab to inspect server logs and verify that the analyzer launched correctly.

---

## Known Issues / Next Steps

1. **Accuracy is low on the 90‑preview set**
   - The latest `analyze_repertoire_90_accuracy.py` run showed:
     - Many BPM values off by 3–10 BPM or more; some clear half/double tempo issues.
     - Many Key mismatches, including fifth‑related and mode errors.
   - The GUI now uses a clean 1:1 mapping, so any mismatch you see is a real algorithm error, not an indexing issue.
   - Next steps for you:
     - Use the Repertoire GUI to visually inspect which songs fail and how (e.g., mis‑mode, fifth‑related, octave BPM).
     - Cross‑reference with `backend/analysis/tempo_detection.py` and `backend/analysis/key_detection.py` and the research docs:
       - `docs/bpm_detection_research.md`
       - `docs/key_detection_research.md`
       - `HANDOVER_PREVIEW_ACCURACY_IMPROVEMENT.md`

2. **Alignment between GUI and Python test scripts**
   - ABCD tests already have a comparison UI (`AnalysisComparison.swift`, `ABCDResultsDashboard.swift`), wired to the 12‑song test CSVs.
   - The Repertoire tab’s comparison logic uses the same `ComparisonEngine`, but operates on:
     - Live analyzer responses instead of CSV.
     - The 90‑preview Spotify CSV instead of the 12‑song test CSVs.
   - If you make changes to comparison semantics (e.g., stricter treatment of double‑time as “mismatch”), keep both paths in sync.

3. **Server auto‑manage edge cases**
   - `autoStartServerIfNeeded(autoManageEnabled: true, overrideUserStop: true)` is used in Repertoire mode so that **clicking Analyze always tries to start the server**, even if the user previously stopped it.
   - If you adjust server startup behavior (e.g., new flags, different Python paths), make sure:
     - `serverScriptURL` in `MacStudioServerManager` stays valid.
     - The Repertoire tab still works from a fresh app launch with no manual server interaction.

4. **Future enhancements**
   - Add a “Save comparison CSV” button from the Repertoire tab, writing out:
     - Filename, guessed title/artist, Spotify BPM/Key, detected BPM/Key, match status, and error reasons.
   - Allow per‑row manual overrides of Spotify mapping if the 1:1 assumption ever changes.
   - Optionally integrate a “Run Python 90‑preview accuracy script” button that shells out to `analyze_repertoire_90_accuracy.py` and shows its summary inline in the GUI.

---

## Quick Pointers for the Next Agent

- If you need to see how Test C expectations are defined (for consistency with the 90‑preview work), look at:
  - `analyze_test_c_accuracy.py`
  - `MacStudioServerSimulator/MacStudioServerSimulator/AnalysisComparison.swift` (`TestCExpectedReference`).
- For any algorithm changes, focus on the backend:
  - Tempo: `backend/analysis/tempo_detection.py`
  - Key: `backend/analysis/key_detection.py`, `backend/analysis/key_detection_helpers.py`
- Use the new Repertoire GUI as a fast manual evaluation harness:
  - You can re‑run analysis for subsets (e.g., only country tracks, only rock tracks) by dragging different folders or subsets into the table.

This should give you enough context to pick up the work: the data, tooling, GUI hooks, and current pain points are all in place. Your main job is to improve the underlying BPM/Key detection so that the Repertoire comparison (and Test C) start turning green.  

