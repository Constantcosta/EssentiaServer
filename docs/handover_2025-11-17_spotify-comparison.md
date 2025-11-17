# Handover · Spotify Comparison Stabilization (2025-11-17)

## TL;DR
- The Spotify comparison dashboard now loads reference data and exposes a quick "Copy All" export, but **every row still shows `Diff`** and preview-track metrics collapse to a single set of values.
- A lightweight Swift CLI (`tools/run_spotify_parsing_test.sh`) was added to validate song-name normalization and Spotify lookups without rerunning full audio analysis; it passes for the six preview references.
- Next phase is to trace why the analyzer feeds constant BPM/key values (especially for previews) and why `ComparisonEngine` never reports matches even when numbers align.

## Current Context
| Area | Status |
| --- | --- |
| Simulator build | ✅ `xcodebuild -workspace MacStudioServerSimulator.xcworkspace -scheme MacStudioServerSimulator -configuration Debug build` |
| Song normalization | ✅ `SongTitleNormalizer` shared between the GUI and CLI tools; aliases cover all six preview tracks (e.g., `Cyrus_Prisoner__feat__Dua_Lipa_`). |
| Spotify reference data | ✅ `SpotifyReferenceData` now supports a custom resource resolver so it can be reused from scripts outside the app bundle. |
| Quick validation tooling | ✅ `tools/run_spotify_parsing_test.sh [--file csv/<results>.csv]` compiles the normalizer + reference loader and prints match status per preview row within ~1s. |
| Comparison dashboard UX | ✅ "Copy All" button copies tabular results to the clipboard from `TestComparisonView`. |

## Findings So Far
1. **Status column never flips to "Match"**
   - Even when the analyzer's BPM/key should match Spotify (e.g., `4ever` reports `F minor` on both sides), the UI still renders `Diff`.
   - Suspect areas: `ComparisonEngine.compareBPM` tolerances or upstream data—`AnalysisResult` instances may be missing `artist`/`song` details or normalized values differ from Spotify lookups.

2. **Preview rows reuse identical metrics**
   - CSV exports for Test A/C show BPM ~70–85 and Key = `D`/`F minor` for every preview file, indicating the preview pipeline either:
     - Writes placeholder metrics, or
     - Parses only the first row, duplicating it for each subsequent track.
   - The duplicated block in the user's table confirms `Prisoner`, `Forget You`, etc., appear twice with exactly the same analyzer numbers.

3. **Analyzer vs. reference mismatch**
   - Full-song set at the top of the table also shows `Diff` everywhere, but unlike previews the BPM/key values do vary—so the comparison logic may reject matches because of uppercase notes (e.g., `G# Major` vs. `C♯/D♭`). Need to confirm normalization pipeline handles sharps/flats and major/minor suffixes.

## Recent Changes Worth Knowing
- `ABCDTestRunner` now calls `SongTitleNormalizer.clean(_:)` when ingesting console/CSV output, so UI + CLI share the same normalization rules.
- `SongTitleNormalizer.swift` sits alongside the simulator sources and is part of the target (project file updated accordingly).
- `tools/test_spotify_parsing.swift` + shell wrapper compile against the simulator sources, load the latest `csv/test_results_*.csv`, and report which preview rows matched a Spotify entry; pass `--file` to test any historical CSV.
- Clipboard export lives in `TestComparisonView.copyComparisonsToClipboard()`; once the underlying data is correct, QA can easily share results.

## Recommended Next Actions
### 1. Fix analyzer data for previews
- Re-run `run_test.sh a` (6 previews) and inspect the resulting CSV in `csv/`. Confirm whether BPM/key columns are populated per row.
- If values are constant, instrument `backend/analyze_server.py` and `backend/analysis/pipeline_core.py` to log the per-track feature extraction results before they hit the CSV writer.
- Ensure preview jobs respect song-specific metadata; look for caching layers that might reuse the first computation for subsequent inputs.

### 2. Verify comparison logic with known-good data
- Use the CLI script to confirm that canonical titles + artists resolve to Spotify references (already true for the six preview tracks).
- Feed a small handcrafted `AnalysisResult` array into `ComparisonEngine.compareResults` (via a unit test or a Swift playground) where BPM/key exactly match Spotify. If it still returns `Diff`, inspect `compareBPM` tolerances and `normalizeKey()`.
- Pay special attention to enharmonic equivalence (`C♯/D♭` vs. `G# Major`), uppercase vs lowercase, and major/minor suffix handling.

### 3. Surface diagnostics in the UI
- Add a debug column or tooltip showing the normalized values that `ComparisonEngine` compares (e.g., `normalizedAnalyzedKey`, `normalizedSpotifyKey`). That will quickly reveal if mismatches come from normalization rather than genuine analysis errors.
- Optionally color the "Status" column differently when the analyzer lacks BPM/key (currently it still shows `Diff`, which hides the difference between "missing" and "wrong").

### 4. Extend tooling + tests
- Add a Swift unit test target (or lightweight script) that exercises `ComparisonEngine.compareBPM`/`compareKey` with canonical cases—including half/double BPM and enharmonic matches—to prevent regressions.
- Consider a Python-side sanity check in `backend/analyze_server.py` to assert that each row's BPM/key deviates less than a threshold from the previous run; flag if entire batches become constant again.

## Useful Commands
```zsh
# Quick Spotify parsing sanity check (latest csv)
./tools/run_spotify_parsing_test.sh

# Target a specific run
./tools/run_spotify_parsing_test.sh --file csv/test_results_20251117_025126.csv

# Rebuild the simulator after code changes
xcodebuild -workspace MacStudioServerSimulator.xcworkspace \
  -scheme MacStudioServerSimulator -configuration Debug build

# Execute preview test batch (server-managed)
./run_test.sh a
```

## Contacts & Open Questions
- **Unanswered:** Why do preview BPM/key values collapse to a single row? Need logs from `backend/analysis` pipeline.
- **Dependencies:** Matching logic relies on `SpotifyReferenceData`. Any changes to the CSV schema must be mirrored in both the simulator and `tools/test_spotify_parsing.swift`.
- **Next reviewer:** Whoever picks this up should be comfortable touching both SwiftUI (for the dashboard) and the Python analyzer to ensure the data flow is end-to-end consistent.
