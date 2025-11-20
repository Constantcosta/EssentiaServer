## Handover – Repertoire Key/BPM Subset & GUI Plan  
_Date: 2025‑11‑19_

### 0. Scope & Goals

You are picking up the work to:

- Improve **key** and **tempo/BPM** detection using a curated subset of the 90‑preview repertoire deck.
- Drive experiments via the **Repertoire** tab in `MacStudioServerSimulator` (the macOS GUI).
- Use a color‑coded evaluation list (Google key, Spotify key, Songwise key) as ground truth for “good / kinda / wrong” behavior.

The previous agent has:

- Wired the GUI to a new CSV that includes **Google key** for ~80 non‑ambiguous songs.
- Ensured the GUI loads **only** those subset songs from the original 90‑preview audio folder.
- Added optional GUI support for **Google BPM / Key / Quality** columns to compare multiple systems.

Your job is to:

1. Understand the current wiring (datasets, GUI, backend key/BPM code).
2. Implement the next round of **key** and **BPM** improvements in a data‑driven way.
3. Integrate those improvements into the calibration/validation flow.

---

### 1. Repo & App Entry Points

- Repo root:  
  `/Users/costasconstantinou/Documents/GitHub/EssentiaServer`

- macOS GUI app:  
  `MacStudioServerSimulator/MacStudioServerSimulator.xcodeproj`
  - Main view: `MacStudioServerSimulator/MacStudioServerSimulator/ServerManagementView.swift`
  - Repertoire tab: `MacStudioServerSimulator/MacStudioServerSimulator/ServerManagementTestsTab.swift`
  - Controller: `MacStudioServerSimulator/MacStudioServerSimulator/RepertoireAnalysisController.swift`

- Backend analyzers (Python):
  - Key detection:
    - `backend/analysis/key_detection.py`
    - `backend/analysis/key_detection_helpers.py`
    - Handover doc: `docs/handover_key-algorithm.md`
  - Tempo/BPM:
    - `backend/analysis/tempo_detection.py`
    - Handover doc: `docs/bpm_detection_research.md` (if present) and `docs/2025-11-16_analysis-hanging-fix.md`

You will mostly touch:

- **Swift GUI**: Repertoire tab + controller.
- **Python backend**: key/tempo detectors and their thresholds.
- **Docs/CSV**: calibration / evaluation instructions and subset CSV.

---

### 2. Datasets & File Layout

#### 2.1 Original 90‑preview deck (legacy baseline)

- Ground‑truth table (Spotify):  
  `csv/90 preview list.csv`  
  - Important columns: `#`, `Song`, `Artist`, `BPM`, `Key`, `Camelot`.

- Audio previews (30‑sec clips):  
  `~/Documents/Git repo/Songwise 1/preview_samples_repertoire_90`
  - Filenames: `NNN_Artist_Title.m4a` (e.g. `001_Savage_Garden_I_Knew_I_Loved_You.m4a`).
  - `NNN` is a 1‑based index that matches the `#` column in the CSV.

These are still useful for historical scripts like `analyze_repertoire_90_accuracy.py`, but the **GUI is no longer using all 90 songs** by default.

#### 2.2 New curated subset (color‑coded list)

We now use a curated subset derived from `docs/songs.numbers-Sheet 2.pdf`, which encodes:

- **Google key** (from web search / chord sites).
- **Spotify key**.
- **Songwise key** (current algorithm output at the time).
- Manual color labels (light green = correct, dark green = musically acceptable, red/orange = wrong).

From that sheet we extracted a subset CSV:

- **New default CSV for GUI**:  
  `csv/repertoire_subset_google.csv`

Key points about this file:

- Schema (superset of the original 90‑preview CSV):
  - Original columns:  
    `#,Song,Artist,Popularity,BPM,Genres,...,Key,Time Signature,...,Camelot,ISRC`
  - New columns at the end:
    - `Google BPM` (currently mostly empty; reserved for future use).
    - `Google Key` (filled from the Numbers sheet).
    - `Songwise Key (Sheet)` (Songwise key from the sheet; reference only).
    - `Key Quality` (empty for now; can store “correct / kinda / wrong” later).

- Row indices:
  - Keeps the original `#` indices from the 90‑preview list (1–90).
  - Only rows present in the Numbers sheet are kept (≈80 tracks).
  - Known ambiguous songs (e.g., “About A Girl”, “UFO”, “Heart‑Shaped Box”, “Back In Black”, etc.) are **not included**.

> Regeneration note: the CSV was produced via a one‑off Python script using `pdfplumber` to read `docs/songs.numbers-Sheet 2.pdf` and fuzzy‑match rows to `csv/90 preview list.csv`. If you need to regenerate it, ask for that script or re‑derive it in `tools/`—but for now treat `repertoire_subset_google.csv` as the source of truth.

---

### 3. Current GUI Behavior (Repertoire Tab)

Files:

- `MacStudioServerSimulator/MacStudioServerSimulator/ServerManagementTestsTab.swift`
- `MacStudioServerSimulator/MacStudioServerSimulator/RepertoireAnalysisController.swift`

#### 3.1 Default loading

On Repertoire tab load:

- In `RepertoireComparisonTab.body`:
  - `task { await controller.loadDefaultSpotify(); await controller.loadDefaultFolder() }`

Defaults:

- **CSV**: `repoRoot/csv/repertoire_subset_google.csv`
  - Loaded by `RepertoireAnalysisController.loadDefaultSpotify()`.
  - Parsed by `RepertoireSpotifyParser` into `[RepertoireSpotifyTrack]`.

- **Audio folder**: `~/Documents/Git repo/Songwise 1/preview_samples_repertoire_90`
  - Loaded by `RepertoireAnalysisController.loadDefaultFolder()` → `importFolder(_)`.
  - Still the original 90‑preview folder; we do **not** require a new folder.

#### 3.2 CSV parsing & model

`RepertoireSpotifyTrack` (in `ServerManagementTestsTab.swift`):

- Fields:
  - `csvIndex: Int?` ← the `#` column.
  - `song: String`  ← `Song`
  - `artist: String` ← `Artist`
  - `bpm: Double`   ← `BPM`
  - `key: String`   ← `Key`
  - `googleBpm: Double?` ← `Google BPM` (optional)
  - `googleKey: String?` ← `Google Key` (optional)
  - `keyQuality: String?` ← `Key Quality` (optional color rating)

`RepertoireSpotifyParser.parse(text:)`:

- Reads header row and requires: `#`, `Song`, `Artist`, `BPM`, `Key`.
- Optionally reads: `Google BPM`, `Google Key`, `Key Quality`.
- Produces an array of `RepertoireSpotifyTrack`, preserving `csvIndex`.

#### 3.3 Audio import & subset filtering

`RepertoireAnalysisController.importFolder(_:)`:

- Lists `.m4a` / `.mp3` in the selected folder (default: `preview_samples_repertoire_90`).
- Calls `importFiles(_:)` with the audio files, sorted by `lastPathComponent`.

`RepertoireAnalysisController.importFiles(_:)`:

- Builds `allowedCsvIndexes` from the currently‑loaded CSV:
  - `let allowedCsvIndexes = Set(spotifyTracks.compactMap { $0.csvIndex })`
- For each file:
  - `rowNumber(fromFileName:)` tries to parse the leading integer before the first `_`:
    - `001_Savage_Garden_I_Knew_I_Loved_You.m4a` → `1`
  - Applies two filters:
    1. `excludedRowNumbers` (currently `{64, 73}`) are always skipped.
    2. If `allowedCsvIndexes` is non‑empty and the parsed index is **not** in that set, the file is skipped.

Result:

- You can keep **all 90 audio files** in `preview_samples_repertoire_90`.
- Only files whose numeric prefix appears in `repertoire_subset_google.csv` will produce a `RepertoireRow`.
- This guarantees the GUI operates on the curated subset while reusing the existing folder.

#### 3.4 Table columns (visual comparison)

In `RepertoireComparisonTab.content`, columns are:

- `#`, `File`, `Artist`, `Title`.
- **Spotify BPM / Key** (from `RepertoireRow.spotify`):
  - `sp.bpmText` (whole BPM).
  - `sp.key` (Spotify key label).
- **Google BPM / Key**:
  - `sp.googleBpmText` (if present).
  - `sp.googleKey` (if present).
  - `sp.keyQuality` (tiny caption; ready for “correct / kinda / wrong” labels).
- **Detected BPM / Key**:
  - From `rows[index].analysis` (backend output).
  - Colored based on `MetricMatch` via `ComparisonEngine.compareBPM` / `compareKey`.

This gives you a per‑song view of:

- Spotify vs Google vs Songwise key/BPM for the curated songs only.

---

### 4. Backend Key & BPM Detection – Where to Work

#### 4.1 Key detection

Core entrypoint:

- `backend/analysis/key_detection.py`
  - Function: `detect_global_key(y_signal: np.ndarray, sr: int, adaptive_params: Optional[dict] = None) -> Dict[str, object]`
  - Uses:
    - Librosa chroma (`_librosa_key_signature`).
    - Sliding‑window consensus with Krumhansl templates.
    - Essentia standard + EDM key extractors (when available).
    - A series of overrides/heuristics:
      - Dominant/tonic reconciliation (`_DOMINANT_INTERVAL_STEPS`, `_FIFTH_RECON_*`).
      - Mode inference (`_mode_bias_from_chroma`, `_MODE_*` thresholds).
      - Window‑vote based mode rescue.

Helper constants & utilities:

- `backend/analysis/key_detection_helpers.py`
  - Thresholds/constants you may tune:
    - `_MODE_BIAS_THRESHOLD`, `_MODE_BIAS_CONF_LIMIT`
    - `_MODE_VOTE_THRESHOLD`, `_MODE_VOTE_CONF_GAIN`
    - `_DOMINANT_INTERVAL_STEPS`, `_DOMINANT_OVERRIDE_SCORE`
    - `_FIFTH_RECON_CHROMA_RATIO`, `_FIFTH_RECON_SCORE_EPS`, `_FIFTH_RUNNER_SCORE_EPS`
    - `_ESSENTIA_TONIC_OVERRIDE_SCORE`, `_ESSENTIA_TONIC_OVERRIDE_CONFIDENCE`
    - `_MODE_RESCUE_SCORE`
  - Functions to leverage:
    - `_score_chroma_profile`, `_windowed_key_consensus`
    - `_root_support_ratio`, `_mode_vote_breakdown`
    - `_essentia_supports`, `_chroma_peak_root`, `_triad_energy`

Related documentation:

- `docs/handover_key-algorithm.md` – prior agent’s summary of the blend between Librosa + Essentia + window consensus.

#### 4.2 BPM / tempo detection

Core entrypoint:

- `backend/analysis/tempo_detection.py`
  - Function: `analyze_tempo(...) -> TempoResult`
  - Pipeline:
    - HPSS (`harmonic_percussive_components`) to isolate percussive content.
    - Onset envelope and tempo estimation via:
      - `librosa.beat.beat_track`
      - `librosa.feature.tempo`
      - `librosa.beat.plp`
    - Alias candidate generation: `_build_tempo_alias_candidates`.
    - Candidate scoring: `_score_tempo_alias_candidates` (considers detector agreement, PLP, octave preferences).
    - Octave validation: `_validate_octave_with_onset_energy` (on‑beat vs off‑beat energy).

Related BPM docs:

- `docs/2025-11-16_analysis-hanging-fix.md`
- `docs/bpm_detection_research.md` (if present).
- External PDF analyzed earlier (BPM comparison between Google/Spotify/Songwise).

---

### 5. Implementation Plan (Next Agent)

This is the concrete plan you should follow.

#### 5.1 Phase 1 – Metrics & Evaluation (subset‑driven)

**Goal:** Turn the color‑coded subset into a reproducible evaluation suite for key + BPM.

Tasks:

1. **Add a dedicated evaluation script** (Python) under `tools/`, e.g. `tools/eval_repertoire_subset.py`:
   - Input:
     - `csv/repertoire_subset_google.csv`
     - Latest `csv/test_results_*.csv` where `test_type == "repertoire-subset"` (you can add a new test_type or reuse `repertoire-90` with a filter).
   - For each song:
     - Join by `Song`/`Artist` (normalized) or by the `#` index.
     - Compare:
       - **Spotify BPM/Key** vs Songwise.
       - **Google Key** vs Songwise.
     - Derive a **key quality label**:
       - Light‑green: exact/enharmonic match.
       - Dark‑green: musically acceptable (same tonic major/minor, relative major/minor, or strong fifth‑related).
       - Red/orange: everything else.
   - Outputs:
     - Aggregate metrics:
       - Strict key accuracy (light‑green only).
     - “Musically acceptable” accuracy (light + dark).
      - BPM MAE + counts of half/double‑time errors.
     - Optionally write a CSV with per‑song classification and reasons.

   ✅ Implemented via `tools/eval_repertoire_subset.py`. Example run:

   ```bash
   python3 tools/eval_repertoire_subset.py --test-type repertoire-90 --results csv/test_results_20251118_211754.csv \
       --per-song-csv reports/repertoire_subset_eval.csv --key-quality-csv reports/repertoire_subset_quality.csv
   ```

   The script canonicalizes `Artist + Song` pairs and also falls back to the `#` index so typos still match.
   It prints strict vs musical key accuracy, BPM MAE + alias counts, and optional per-song exports plus
   suggested `Key Quality` labels for the GUI.

2. **Integrate with GUI runs**:
   - Ensure Repertoire runs use a distinct `test_type` (e.g. `"repertoire-subset"`) in the server output CSVs so your script can find the right rows.
   - You may need to update the backend logging to tag Repertoire requests.

3. **Back‑fill `Key Quality`** (optional but recommended):
   - Use the script above to annotate `Key Quality` in `repertoire_subset_google.csv` with:
     - `correct` / `kinda` / `wrong` (matching your spreadsheet’s color logic).
   - The GUI will automatically display this in the “Google BPM / Key” column.

#### 5.2 Phase 2 – Key detection tightening

**Goal:** Reduce red/orange key errors on the subset, especially dominant/relative confusions, without overfitting.

Focus areas (in `key_detection.py` / `key_detection_helpers.py`):

1. **Explicit “key alias” scoring:**
   - For the best chroma candidate (fallback root/mode), explicitly evaluate:
     - Same tonic, mode flipped (major ↔ minor).
     - Relative major/minor.
     - ±5/±7 semitone fifth neighbors.
   - Use:
     - Template scores (`scores` / `votes` from `_score_chroma_profile`).
     - Window consensus (`_windowed_key_consensus`).
     - Essentia candidates (`_essentia_key_candidate` + `_essentia_supports`).
   - Define a small scoring function that picks the most musically supported key among these aliases, rather than blindly trusting the single best template score.

2. **Mode stability (major/minor):**
   - Average `_mode_bias_from_chroma` over sliding windows instead of relying solely on the global profile.
   - Combine:
     - Global bias.
     - Window mode votes (`_mode_vote_breakdown`).
     - Essentia’s reported mode (`_mode_rescue_from_candidate`).
   - Tune:
     - `_MODE_BIAS_THRESHOLD`, `_MODE_BIAS_CONF_LIMIT`
     - `_MODE_VOTE_THRESHOLD`, `_MODE_RESCUE_SCORE`
   - Validate using your subset metrics: aim to reduce “same tonic, wrong mode” dark‑green→red flips.

3. **Dominant/subdominant override safety:**
   - Review `_DOMINANT_INTERVAL_STEPS`, `_DOMINANT_OVERRIDE_SCORE`, and `_FIFTH_RECON_*`.
   - Ensure:
     - Dominant/subdominant overrides only fire when both chroma and Essentia clearly support the alternate tonic.
     - For short clips (previews), be more conservative with fifth overrides unless window dominance is very high.
   - Check subset songs that currently flip by ±5/±7 semitones and use them as guardrails.

4. **Ambiguous key flagging (optional but useful):**
   - When the top two candidates are related (same tonic / relative / fifth) and their scores are very close:
     - Provide both in `result["scores"]` and set an `result["ambiguous_between"] = ["X Major", "Y Minor"]`.
   - The GUI can later surface this to avoid over‑confident “wrong” labels.

Implementation pattern:

- For each change:
  - Run the Repertoire GUI on the subset and export test results.
  - Run your evaluation script to see strict vs musical accuracy before/after.

#### 5.3 Phase 3 – BPM alias & genre‑aware improvements

**Goal:** Reduce half‑time / double‑time BPM errors on tricky genres (fast rock, slow ballads, neo‑soul).

Focus areas (in `tempo_detection.py`):

1. **Alias candidate scoring tweaks:**
   - `_build_tempo_alias_candidates` and `_score_tempo_alias_candidates` already try 0.5× / 1× / 2×.
   - You can:
     - Adjust the weighting of detector agreement vs PLP vs octave preference.
     - Use the subset (and the larger 90‑song BPM dataset you already have) to tune these weights for minimum octave errors.

2. **Onset‑energy octave validation:**
   - `_validate_octave_with_onset_energy` compares on‑beat vs off‑beat energy at candidate tempos.
   - Consider:
     - Tightening the improvement threshold (currently ~10%) required to switch from the base BPM to its 0.5×/2× aliases.
     - Adding a “BPM ambiguous” flag when 0.5× and 1× scores are nearly tied.

3. **Genre‑hinted priors (future step):**
   - `adaptive_params` can carry a simple `genre_hint` (`rock`, `rnb`, `edm`, `ballad`).
   - You can route that into:
     - Different octave preference curves (e.g., ballads favor slower BPM).
     - Slightly different alias scoring penalties.

Again, validate using your subset + the 90‑song BPM dataset.

#### 5.4 Phase 4 – Calibration & CI integration

**Goal:** Make sure every key/BPM change is measurable and guarded.

Tasks:

1. Extend or create a calibration validation command (Python), e.g.:
   - `python3 tools/validate_calibration.py --dataset data/calibration/... --key-report --key-calibration-config config/key_calibration.json --min-key-accuracy 0.65 ...`
   - Add flags or a separate script to include the **repertoire subset metrics**:
     - Min strict key accuracy (subset).
     - Min “musically acceptable” key accuracy.
     - Max BPM MAE; max half/double‑time errors.

2. Wire this into CI and local pre‑flight:
   - Update `docs/key-analysis-plan.md` and `docs/calibration-handover.md` with the new commands.
   - Ensure every analyzer change is accompanied by a refreshed run and metrics logged to `reports/calibration_metrics.csv`.

---

### 6. How to Run Things

#### 6.1 Run the backend server

From repo root:

- `./start_server_optimized.sh`  
  or use the existing helper scripts noted in `RUN_TESTS.md`.

Verify with:

- `python backend/test_server.py` (optional sanity check).

#### 6.2 Run the MacStudioServerSimulator app

1. Open `MacStudioServerSimulator/MacStudioServerSimulator.xcodeproj` in Xcode.
2. Select the `MacStudioServerSimulator` scheme.
3. Build & run.
4. In the app:
   - Go to the **Tests** tab → **Repertoire** mode.
   - On first load:
     - It will try to load `csv/repertoire_subset_google.csv`.
     - It will try to load `~/Documents/Git repo/Songwise 1/preview_samples_repertoire_90`.
   - Press “Analyze with Latest Algorithms” to send each subset clip to the analyzer.

#### 6.3 Export results & evaluate

1. After a Repertoire run, the backend should write a `csv/test_results_*.csv` including the analyzed BPM/Key for each file (check `RUN_TESTS.md` / existing test harnesses).
2. Run your evaluation script (once created) against `csv/repertoire_subset_google.csv` to compute:
   - Strict key accuracy.
   - Musical key accuracy.
   - BPM MAE and octave errors.

---

### 7. Guardrails & Non‑Goals

- Do **not** hard‑code per‑song fixes in the analyzer.
  - All improvements should arise from general heuristics or learned calibration, validated on the subset.

- Keep `repertoire_subset_google.csv` as the single source of truth for the GUI subset.
  - If you change the song list, update the CSV and rely on `csvIndex` filtering; do not embed special‑case lists in Swift.

- Keep Swift changes focused on:
  - Displaying more information (Google columns, quality labels).
  - Ensuring the right rows are loaded and compared.
  - Avoid coupling the GUI too tightly to specific thresholds or algorithm internals.

If you follow this plan, you’ll have:

- A clean, reproducible subset‑based evaluation loop.
- A GUI that shows Spotify vs Google vs Songwise side by side.
- A safe playground for tuning key/BPM thresholds with real‑world, musically meaningful feedback.
