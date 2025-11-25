# Handover for Next Agent – Test C BPM/Key Accuracy

**Date:** 18 November 2025  
**Repo:** `EssentiaServer` + `MacStudioServerSimulator`  
**Primary Goal:** Reach near-100% accuracy on Test C (12 preview clips) for both BPM (P2/octave-aware) and key (root + mode), without song‑specific hacks.

---

## 1. Current Accuracy & Targets

### Test C (12 preview files, previews only)
- **BPM:** 12/12 correct (100% P2, octave-aware).
- **Key:** 10/12 correct (83.3%).
- **Overall:** 22/24 metrics correct (91.7%).

The authoritative analysis script is:
- `analyze_test_c_accuracy.py` – reads the latest `csv/test_results_*.csv` and compares against a curated Spotify-ground-truth table.

From the latest run (`./run_test.sh c` → `csv/test_results_20251118_182030.csv`), the script reports:

- Remaining key errors:
  1. `Green_Forget_You` – ours: **G Major**, expected: **C** (IV vs I).
  2. `___Song_Fomerly_Known_As_` – ours: **F# Major**, expected: **B** (V vs I).

All other tracks, including `Carlton_A_Thousand_Miles`, now match in both BPM and key under the Python harness.

The **GUI** (MacStudioServerSimulator) is now aligned with these expectations for Test C (see section 4).

---

## 2. Key Code Paths (Backend)

### Core analysis pipeline
- `backend/analysis/pipeline_core.py`
  - Entry point for server‑side analysis.
  - Orchestrates:
    - Tempo via `analyze_tempo` in `backend/analysis/tempo_detection.py`.
    - Key via `detect_global_key` in `backend/analysis/key_detection.py`.
    - Audio descriptors, valence, danceability, etc. (not directly relevant to current task).

### Tempo (already at 12/12)
- `backend/analysis/tempo_detection.py`
  - Multi-detector fusion: beat_track, onset-based tempo, PLP.
  - Preview‑specific behavior:
    - Confidence‑weighted mid‑tempo correction (e.g. 95 → ~148 BPM) with tight caps.
    - Onset validation disabled for short clips when unstable.
  - Important params are drawn from `backend/analysis/settings.py` via `get_adaptive_analysis_params`.
- `backend/analysis/calibration.py`
  - Linear BPM calibration with guardrails.
  - For previews:
    - Skips calibration in the 138–152 BPM mid‑tempo band.
    - Enforces ±10 BPM cap on corrections.

Tempo is effectively “done” for Test C. Any changes here should be regression‑checked against both Test C and any other suites the user cares about.

### Key detection (where remaining work is)
- `backend/analysis/key_detection.py`
  - Main key entrypoint: `detect_global_key(y_signal, sr, adaptive_params=None)`.
  - Uses:
    - Librosa chroma + template matching (`_librosa_key_signature`).
    - Optional Essentia KeyExtractor via helpers in `backend/analysis/key_detection_helpers.py`.
    - Windowed key votes with consensus for previews.
  - Key recent logic:
    - Preview‑specific runner promotion with window support and esssential gating.
    - Chroma peak override with special cases for fifth‑related peaks (dominant/subdominant).
    - **Fifth‑reconciliation block for previews**:
      - Searches top template candidates for a perfect 4th/5th alternative that is nearly tied in template score, with strong chroma energy at the tonic.
      - When triggered, switches to that alternative, sets `key_source = "fifth_reconcile"`, and **locks** the root (`locked_root = True`).
    - When `locked_root` is set:
      - Runner interval promotions, Essentia dominant overrides, and chroma peak overrides are prevented from flipping the root back to the dominant.
    - Essentia adds alternative candidates and can apply a tonic override in some cases (configurable via helper thresholds).

- `backend/analysis/key_detection_helpers.py`
  - Constants and utilities:
    - `_WINDOW_SUPPORT_PROMOTION`, `_WINDOW_SUPPORT_PROMOTION_SHORT`
    - `_FIFTH_RECON_CHROMA_RATIO`, `_FIFTH_RECON_SCORE_EPS`, `_FIFTH_RUNNER_SCORE_EPS`
    - `_CHROMA_PEAK_ENERGY_MARGIN`, `_CHROMA_PEAK_SUPPORT_RATIO`, `_CHROMA_PEAK_SUPPORT_GAP`
    - Key parsing and scoring helpers (`_interval_distance`, `_root_support_ratio`, etc.).

These heuristics successfully fixed tonic/dominant issues for `A Thousand Miles` and others, but `Forget You` + `Song Formerly` remain problematic (see section 5).

---

## 3. Test & Tooling Workflow

### CLI test runner (authoritative)
- `run_test.sh`
  - Manages its own server:
    - Kills any previous `analyze_server.py`.
    - Starts `backend/analyze_server.py` in `.venv`.
    - Waits for `/health` to report healthy.
  - Runs tests via:
    - `.venv/bin/python tools/test_analysis_pipeline.py` with `--preview-calibration --csv-auto` for **Test C**.
  - Enforces a per‑test timeout.
  - On success:
    - Finds the newest `csv/test_results_*.csv`.
    - Copies it to:
      - `csv/test_results_latest.csv`
      - `csv/test_results_c_latest.csv` for Test C.
    - Writes a small metadata JSON:
      - `csv/test_results_c_latest.meta.json` with:
        - `csv`, `csv_path`
        - `test_type`
        - `git_commit`, `git_branch`
        - `run_timestamp_utc`
    - Prints machine‑readable lines:
      - `RESULT_CSV=...`
      - `RESULT_META=...`
      - `RESULT_COMMIT=...`

Command you care about:
```bash
./run_test.sh c
```

### Accuracy analysis (Python)
- `analyze_test_c_accuracy.py`
  - Reads the latest `csv/test_results_*.csv` (as of now, effectively `csv/test_results_c_latest.csv`).
  - Expected values table (important):
    - For each preview track: expected BPM and tonic key, e.g.:
      - `Green_Forget_You` → BPM 127, **C**.
      - `___Song_Fomerly_Known_As_` → BPM 115, **B**.
      - `A_Whole_New_World` → BPM 114, **A Major**, etc.
  - Uses `keys_match_fuzzy` from `tools/key_utils.py` to allow enharmonic equivalence while requiring correct tonic + mode.

### Convenience helper
- `tools/latest_results.py`
  - Prints JSON with:
    - Latest timestamped CSV path.
    - Stable aliases (`test_results_c_latest.csv`, etc.).
    - Parsed metadata.
  - Designed for GUI or other tooling that needs to locate the canonical latest results.

---

## 4. GUI Alignment (MacStudioServerSimulator)

The Mac app now runs the **same tests**, against the **same expectations**, as the Python harness.

### Test runner wiring
- `MacStudioServerSimulator/MacStudioServerSimulator/ABCDTestRunner.swift`
  - Finds the EssentiaServer repo root (by searching upward for `run_test.sh` or falling back to `~/Documents/GitHub/EssentiaServer`).
  - For **Test C**:
    - Calls `run_test.sh c` via a `Process`, with:
      - `currentDirectoryURL = projectPath`
      - `PATH` including `.venv/bin`
      - `VIRTUAL_ENV` set to the repo’s `.venv`.
  - Parses console output:
    - Detects `Results saved to <path>` and reads that CSV.
    - Normalizes song titles using `SongTitleNormalizer.clean(_:)`.
    - Maps CSV rows to `AnalysisResult` (song, artist, bpm, key).
  - Stores results per test in `ABCDTestResult`.

### Spotify comparison view
- `MacStudioServerSimulator/MacStudioServerSimulator/SpotifyReferenceData.swift`
  - Loads embedded CSVs:
    - `test_12_preview.csv`
    - `test_12_fullsong.csv`
  - Builds lookup tables by normalized song/artist.
  - These are the raw Spotify BPM/key values (e.g., `A Thousand Miles` key B, etc.).

- `MacStudioServerSimulator/MacStudioServerSimulator/SongTitleNormalizer.swift`
  - Maps our analysis song identifiers (e.g. `Cyrus_Prisoner__feat__Dua_Lipa_`) to canonical Spotify titles:
    - `"carlton a thousand miles"` → `"A Thousand Miles"`, etc.

- `MacStudioServerSimulator/MacStudioServerSimulator/AnalysisComparison.swift`
  - Defines:
    - `AnalysisResult`
    - `TrackComparison`
    - `ComparisonEngine.compareBPM` (±3 BPM, octave-aware).
    - `ComparisonEngine.compareKey` (enharmonic-aware tuner).
  - **Important for Test C**:
    - In `compareTrack(...)`, for `testType == .testC`, it now overrides Spotify’s raw BPM/key with a curated set that exactly matches `analyze_test_c_accuracy.py`:
      - Implemented via `TestCExpectedReference` (inlined in this file).
      - So GUI “Spotify Key” column == Python script’s expected key.

- `MacStudioServerSimulator/MacStudioServerSimulator/TestComparisonView.swift`
  - Renders the “Spotify Reference Comparison” table.
  - Uses `ComparisonEngine.compareResults` to build `TrackComparison` objects from:
    - The latest `ABCDTestResult` for each test.
    - `SpotifyReferenceData`.
  - The **Test C** button you see now drives:
    - `run_test.sh c` → `csv/test_results_*.csv` → `AnalysisResult` → `TrackComparison` → GUI.

With these changes, the GUI’s All/Matches/Differences tabs should show exactly **two** red rows for Test C (Forget You & Song Formerly), matching the CLI accuracy script.

---

## 5. Remaining Technical Problems (Keys)

The last two key errors share a pattern: our system is favoring a **nearby diatonic key** (IV or V) over the tonic.

1. `Forget You` – CeeLo Green
   - Expected: **C**.
   - Our current prediction: **G Major**.
   - Type: roughly a **subdominant/dominant bias** (relative to C).
   - Likely causes:
     - Strong emphasis on IV/V chords in the preview segment.
     - Template/chroma scoring not decisively favoring the tonic.
     - Window consensus + runner heuristics still comfortable selecting G given the evidence.

2. `! (The Song Formerly Known As)` – Regurgitator
   - Expected: **B**.
   - Our current prediction: **F# Major**.
   - Type: **dominant/tension bias** in a dense, high‑energy rock track.
   - Previous experiments showed:
     - Direct `detect_global_key` sometimes selected B when run in isolation.
     - The full server pipeline was historically flipping toward the dominant; we tightened that for other songs but not this one yet.

Both are “musically plausible” dominant/neighbor keys, but the project goal is strict Spotify tonic alignment, so the system needs stronger tonic‑favoring logic in these ambiguous cases.

---

## 6. Suggested Next Steps for the Next Agent

### 6.1. Deep inspection of the two remaining failures

Use these commands for targeted debugging:

```bash
./run_test.sh c
.venv/bin/python analyze_test_c_accuracy.py

# Song-specific key inspection:
.venv/bin/python - <<'PY'
import librosa, numpy as np
from backend.analysis.key_detection import detect_global_key
from backend.analysis.settings import get_adaptive_analysis_params
from backend.analysis.key_detection_helpers import KEY_NAMES

paths = [
    "Test files/preview_samples/02_Green_Forget_You.m4a",
    "Test files/preview_samples/03_Regurgitator____Song_Fomerly_Known_As_.m4a",
]

for path in paths:
    y, sr = librosa.load(path, sr=None, mono=True)
    params = get_adaptive_analysis_params(len(y)/sr)
    res = detect_global_key(y, sr, adaptive_params=params)
    print(path, "->", KEY_NAMES[res["key_index"]], res["mode"], res["confidence"], res.get("key_source"))
PY
```

Inspect:
- `res["key_source"]` – which decision stage produced the final key.
- `res["scores"]` – template scores and Essentia candidates.
- `res["chroma_profile"]` – relative energy for tonic vs neighbors.

Logs to watch:
- `/tmp/essentia_server.log` – contains debug lines from `key_detection.py` (initial fallback, chroma peak, fifth reconciliation, final key).

### 6.2. Heuristic improvements to favor tonic in ambiguous cases

Ideas that are consistent with the current architecture and won’t re‑break other songs:

1. **Tonic bias when consensus is weak but multiple diatonic neighbors are close**
   - When template scores and chroma energy for I, IV, and V are very close:
     - Prefer the tonic if:
       - Its window support is within some margin of the best neighbor.
       - Essentia ranks it highly (even if not top‑1).
   - Implementation sketch:
     - After existing runner/window/chroma logic, inspect a small neighborhood around the chosen root (e.g. ±5 semitones on the circle of fifths).
     - If another root is a diatonic neighbor and better matches tonic heuristics (e.g. mode bias, chord‑tone presence), consider flipping.

2. **Mode‑aware bias for likely tonic in major tracks**
   - Both failing songs are upbeat major tracks where the tonic is strongly implied harmonically but heavily decorated with IV/V.
   - You can:
     - Increase `_MODE_VOTE_THRESHOLD` or adjust `_MODE_VOTE_CONF_GAIN` for major modes in previews where the chroma profile suggests a strong tonic triad.

3. **Additional Essentia‑based tie‑break**
   - For cases where:
     - Internal pipeline picks a key that’s a perfect fourth/fifth from Essentia’s choice.
     - Essentia’s confidence is high.
   - Allow Essentia to override to its tonic if:
     - Window support and chroma for that tonic are not significantly worse than the current pick.
   - This is similar to the existing `_essentia_tonic_override` but can be tuned specifically for Test C‑like previews.

### 6.3. Guardrails against overfitting

Even though Test C is small, keep these safeguards:

- Don’t add track‑name–specific checks or BPM ranges tied to particular songs.
- Keep all heuristics expressed in terms of:
  - Intervals (distance on the circle of fifths).
  - Chroma energy ratios and window supports.
  - Mode bias from chroma.
  - Agreement/disagreement between detectors (librosa templates vs Essentia).
- Run existing tests after any change:

```bash
./run_test.sh c
.venv/bin/python analyze_test_c_accuracy.py
./run_test.sh a
./run_test.sh b
```

And visually spot‑check a few non‑Test‑C tracks if possible.

---

## 7. Quick Reference: Files You’ll Touch Most

Backend key pipeline:
- `backend/analysis/key_detection.py`
- `backend/analysis/key_detection_helpers.py`
- `backend/analysis/settings.py` (preview parameters).

Testing & CLI:
- `run_test.sh`
- `tools/test_analysis_pipeline.py`
- `analyze_test_c_accuracy.py`
- `tools/key_utils.py`
- `tools/latest_results.py`

GUI (Mac app):
- `MacStudioServerSimulator/MacStudioServerSimulator/ABCDTestRunner.swift`
- `MacStudioServerSimulator/MacStudioServerSimulator/AnalysisComparison.swift`
- `MacStudioServerSimulator/MacStudioServerSimulator/SongTitleNormalizer.swift`
- `MacStudioServerSimulator/MacStudioServerSimulator/SpotifyReferenceData.swift`
- `MacStudioServerSimulator/MacStudioServerSimulator/TestComparisonView.swift`

If you’re picking up this work, you should be able to:
1. Run Test C end‑to‑end (CLI + GUI) using the instructions above.
2. Reproduce the two remaining key errors quickly.
3. Iterate on `key_detection.py` (and helpers) with confidence that both the Python analysis script and the Mac GUI will reflect your changes consistently. 

