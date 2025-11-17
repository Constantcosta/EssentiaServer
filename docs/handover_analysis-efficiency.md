## Analysis & Calibration Handover (Agent Briefing)

This note captures the current state of the audio-analysis stack, open issues, and a concrete plan for improving the Essentia/Hybrid pipelines without relying on Spotify at inference time.

---

### 1. System Snapshot

- **Primary entry point**: `backend/analyze_server.py` orchestrates HTTP handlers and delegates audio work to the `backend.analysis` package.
- **Pipeline core**: `backend/analysis/pipeline_core.py` contains `perform_audio_analysis`, tempo/BPM logic, descriptor extraction, and the `analysis_timing` recorder.
- **Chunk consensus**: `backend/analysis/pipeline_chunks.py` runs optional overlapping windows and blends their stats back into the global result.
- **Key detection**: `backend/analysis/key_detection.py` combines Essentia’s `KeyExtractor`, a chroma consensus, and a basic set of heuristics to pick the final `(root, mode)`.
- **Configuration**: `backend/analysis/settings.py` and `backend/analysis/utils.py` centralize env flags (FFT size, HPSS windows, Essentia toggles, chunk behavior, etc.).
- **Calibration utilities**: `backend/analysis/calibration.py` wires scaler/model loading; macOS client sweeps feed into `tools/build_calibration_dataset.py`.
- **Data sources**: `data/calibration/mac_gui_calibration_*.parquet` hold labeled runs (Essentia `v1`, Hybrid `v2`), while Spotify references live in `csv/spotify_calibration_master.csv`.
- **Recent results**:
  - Essentia-only sweep (`~/Library/.../calibration_run_20251114_132425.csv`) → 46 matches vs Spotify, **~54 %** exact keys, median BPM |Δ| ≈ 3.6.
  - Hybrid2 sweep (`data/calibration/mac_gui_calibration_20251114_143020.parquet`, `feature_set_version=v2`, latest export) → 54 rows, **50 %** exact keys, 30 % mode flips, several ±60 BPM tempo aliases.

> _Reminder_: Spotify metrics are **only** for offline calibration dashboards—the analyzer must stand alone.

---

### 2. Pain Points & Observations

| Area | Symptoms | Source Files |
| --- | --- | --- |
| Key accuracy | ±5/±7 semitone offsets and major/minor ambiguity remain common even after refactors; mode mismatch dominates. | `backend/analysis/key_detection.py`, `backend/analysis/pipeline_chunks.py` |
| Tempo aliasing | Seven tracks per sweep still land at half/double time—current ratio check only compares two detectors. | `backend/analysis/pipeline_core.py:120-159` |
| Confidence signals underused | `analysis_timing`, `key_confidence`, chunk diagnostics, tonal strength, and spectral flux are computed but not fed into calibration or decision logic. | `backend/analysis/pipeline_core.py`, `backend/analysis/pipeline_features.py` |
| Chunk consensus limited | Windows only majority-vote string keys; no weighting by interval distance or mode, so modulation/ambiguity is invisible. | `backend/analysis/pipeline_chunks.py:227-279` |
| Feature gating opaque | Operators lack a single doc describing env knobs (FFT size, chunk counts, Essentia toggles), making performance tuning ad-hoc. | `backend/analysis/settings.py`, Makefile/README gaps |

---

### 3. Improvement Plan

#### A. Key Detection Enhancements
1. **Feature Fusion Model**  
   - Collect diagnostics already emitted (window dominance/separation, Essentia score, chroma variance, percussive vs harmonic energy) from `detect_global_key`.  
   - Train a lightweight classifier (`tools/train_key_selector.py` TBD) that predicts the most reliable `(root, mode)` using calibration datasets (no Spotify at runtime).  
   - Replace the current `if dominance >= …` tree with the learned probabilities (fall back to rules when the model file is absent).  
   - Files: `backend/analysis/key_detection.py`, new tool in `tools/`.

2. **Mode Arbitration Heuristic**  
   - Use chroma third/sixth intervals + inferred valence (`pipeline_features.estimate_valence_and_mood`) to flip ambiguous mode choices when confidence < 0.6.  
   - Annotate results with `mode_source` plus `ambiguous=true` when both cues disagree, so downstream consumers can treat them cautiously.  
   - Files: `backend/analysis/key_detection.py`, `backend/analysis/pipeline_core.py`.

3. **Chunk-Aware Voting**  
   - Extend `build_chunk_consensus` to store numeric roots/modes instead of raw strings; compute dispersion (weighted std in semitone space) and feed that back into `merge_chunk_consensus`.  
   - Lower `key_confidence` or flag “modulating” when dispersion > 3 semitones.  
   - Files: `backend/analysis/pipeline_chunks.py`.

#### B. Tempo Robustness
1. **Alias Scoring**  
   - Evaluate BPM candidates at {0.5×, 1×, 2×} of `tempo_percussive_float` and `tempo_onset_float`, scoring each with `tempo_alignment_score`, PLP peak confidence, and chunk BPM variance.  
   - Choose the best-scoring alias rather than only comparing the two detectors’ ratio.  
   - Files: `backend/analysis/pipeline_core.py:120-160`, `backend/analysis/pipeline_features.py:133-182`.

2. **Chunk Feedback Loop**  
   - When chunk consensus BPM std < threshold, snap the global BPM to that value and reuse its confidence; log when overrides happen to help calibration audits.  
   - Files: `backend/analysis/pipeline_chunks.py`, `backend/analysis/pipeline_core.py`.

#### C. Calibration & Feature Usage
1. **Leverage New Descriptors**  
   - Ensure ridge/scaler models include `dynamic_complexity`, `tonal_strength`, `spectral_flux`, `percussive_energy_ratio`, etc. (currently written to the Parquet but ignored by calibration models).  
   - Update `tools/train_calibration_models.py` to auto-select feature subsets based on `feature_set_version`.  
   - Files: `backend/analysis/calibration.py`, `tools/train_calibration_models.py`, `config/calibration_scalers.json`.

2. **Timer Aggregation**  
   - Finish `tools/export_analysis_timers.py` (or equivalent) so sweeps can dump `analysis_timing` + chunk diagnostics for regression tracking.  
   - Use this to justify enabling/disabling features per release and to catch regressions when refactors land.  
   - Files: `backend/analysis/pipeline.py` (timer class), new tool under `tools/`.

3. **Documentation & Env Guide**  
   - Produce a short operator README covering every env var from `backend/analysis/settings.py`, what it controls, and safe ranges.  
   - Link it from `docs/audio-calibration-plan.md` so calibration agents know which knobs to twist during sweeps.  
   - Files: `docs/audio-calibration-plan.md`, new `docs/analysis-config.md`.

---

### 4. Operational Notes for Next Agents

- **Calibration workflow**: macOS GUI stores staged songs under `~/Library/Application Support/MacStudioServerSimulator/CalibrationSongs` and exports CSVs into `CalibrationExports/`. The builder consumes those plus Spotify CSVs to write Parquet artifacts in `data/calibration/`.
- **Feature-set tagging**: Always set `feature_set_version` (`v1` Essentia-only, `v2` Hybrid) when running the builder; this metadata flows into calibration reports and determines which model file the backend loads.
- **Chunk toggle**: `/analyze_data` honors header `X-Skip-Chunk-Analysis: 1`. Use it for bulk sweeps until chunk consensus reliability improves.
- **GUI comparison**: The Calibration tab now includes a **Compare vs Spotify** button beside the last export; it runs `tools/compare_calibration_subset.py` against the most recent Parquet and shows the formatted output inline plus in the log.
- **Key comparison script**: `python3 tools/compare_calibration_subset.py --dataset data/...parquet` prints the root-offset histogram and sample mismatches; it does **not** influence live inference.
- **Known blockers**:
  - `backend/analysis/key_detection.py` still logs Essentia initialization warnings because the installed build lacks EDM extractor at 12 kHz—safe to ignore but spams logs.
  - Calibration builder expects every reference track; missing songs (e.g., Teddy Swims “Lose Control”) require running the Mac app or allowing skips (`--allow-missing`).

---

### 5. Immediate Next Steps

1. **Implement tempo alias scoring** (`backend/analysis/pipeline_core.py`).  
2. **Enhance chunk key voting** (`backend/analysis/pipeline_chunks.py`).  
3. **Document env knobs + chunk toggle** (`docs/analysis-config.md`, update `docs/audio-calibration-plan.md`).  
4. **Prototype key fusion model** (export training data from `mac_gui_calibration_*.parquet`, commit helper script under `tools/`).  
5. **Run calibration sweeps** for both feature-set versions after each change, logging key/BPM stats via `compare_calibration_subset.py`.  
6. **Share findings** in this doc (append dated entries) so the next agent can see progress without digging through git history.

Please keep this file updated as soon as you land any of the steps above. A concise “what changed, how to validate, what’s next” entry per push will keep the handover loop tight.

---

#### 2025-11-14 – Tempo alias scoring + chunk dispersion
- **What changed:** Added PLP-aware tempo alias scoring + diagnostics in `backend/analysis/pipeline_core.py` (candidates now cover 0.5×/1×/2× detectors) and overhauled chunk consensus in `backend/analysis/pipeline_chunks.py` to track numeric roots, semitone dispersion, and a `key_modulating` flag. Documented the runtime knobs in `docs/analysis-config.md` and linked it from the calibration plan so operators know how to flip Env/headers.
- **How to validate:** Run `python3 -m py_compile backend/analysis/pipeline_core.py backend/analysis/pipeline_chunks.py` for quick syntax smoke, then hit a few calibration tracks (or `tools/compare_calibration_subset.py`) and inspect `tempo_diagnostics` + `chunk_analysis.consensus.key_dispersion_semitones` to confirm alias picks/logs look sane. Expect modulating songs to clamp `key_confidence ≤ 0.45`.
- **What’s next:** Wire chunk BPM variance into the alias scorer + snap-to-consensus flow (Step B2), export the alias diagnostics into calibration dashboards, and start collecting training data for the key fusion model outlined in Section 3A.
