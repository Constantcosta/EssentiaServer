# Research Project: Key Detection (Global Key & Mode)

**Scope:** Deep‑dive into musical key detection for EssentiaServer, including algorithms, evaluation, and a concrete design aligned with current MIR practice and the existing `backend/analysis/key_detection*.py` implementation.

**Last validated against online docs:** 2025‑11‑18  
**Primary external references (key‑specific):**
- Essentia 2.1‑beta6‑dev `KeyExtractor` (standard & streaming)  
  https://essentia.upf.edu/algorithms_reference.html
- librosa chroma features: `chroma_cqt`, `chroma_stft`, `chroma_cens`  
  https://librosa.org/doc/latest/feature.html
- MIREX “Audio Key Detection” task (evaluation framework & historical systems)  
  https://www.music-ir.org/mirex/w/index.php/Audio_Key_Detection
- Classic template‑based key models (Krumhansl & Kessler, Temperley) and modern HPCP‑based systems (as adopted in Essentia and later MIR work).

This document complements `audio_analysis_research_project.md` and should be the main reference for any changes to key detection logic or calibration.

---

## 1. Problem Definition

### 1.1 Target output for EssentiaServer

We focus on a **global tonal key** per track, plus diagnostics:

- `key_root` – integer in `[0, 11]` indexing pitch classes `["C", "C#", ..., "B"]`.
- `key_name` – string such as `"G#"` or `"F"`.
- `mode` – `"Major"` or `"Minor"` (with potential future extension to modal flavors).
- `confidence` – `[0, 1]` score reflecting how clearly the key is established.
- Optional debug fields:
  - `chroma_profile` – 12‑element aggregate chroma/HPCP profile.
  - `scores` – per‑key template scores.
  - `window_consensus` – section‑level vote summary.
  - `essentia`, `essentia_edm` – external model candidates when Essentia is available.

EssentiaServer’s current `detect_global_key` implementation already returns a dict with these elements; this document formalizes and rationalizes that design.

### 1.2 Global vs local keys and ambiguity

Key detection has inherent ambiguity:
- Tracks may modulate (key changes between sections).
- Rock/EDM often sits between relative major/minor (e.g., C major vs A minor).
- Modal interchange and borrowed chords blur classical tonal boundaries.

MIREX’s Audio Key Detection task assumes:
- A single **reference key** per piece for evaluation.

For EssentiaServer:
- Primary output: **one global key+mode per track**, chosen to best reflect the dominant tonal center for tagging, playlisting, and UI.
- Secondary information: window‑level votes and consistency metrics used to:
  - Improve robustness,
  - Provide debugging for difficult tracks,
  - Potentially support future “local key” features.

---

## 2. Overview of Established Approaches

### 2.1 Template‑based key detection

The classic pipeline used in much MIR literature (and in this repo) is:

1. **Tuning estimation**  
   - Estimate global tuning deviation (e.g., via spectral autocorrelation or functions similar to `librosa.estimate_tuning`).
   - Retune frequency bins/cQT centers so that pitch classes align to the tempered semitone grid.

2. **Pitch‑class representation (chroma/HPCP)**  
   - Compute a 12‑dimensional pitch‑class profile per frame:
     - Chroma or HPCP from a CQT or high‑resolution STFT.
     - Optionally separate harmonic and percussive components and use **only harmonic** energy.

3. **Aggregation over time**  
   - Sum or energy‑weight frame‑level chroma to get a global 12‑bin pitch‑class histogram.
   - Optionally compute windowed chroma to capture **section‑level keys** and vote over windows.

4. **Key templates and correlation**  
   - Use pre‑defined major/minor key profiles (e.g., **Krumhansl & Kessler** vectors) or learned profiles.
   - For each candidate key:
     - “Roll” the chroma profile by the key’s root.
     - Compute correlation or dot‑product with the major/minor template.
   - Choose the key with the maximum score.

5. **Mode decision and post‑processing**  
   - Decide between major/minor using:
     - Template scores.
     - Scale‑degree prominence (3rd/6th).
     - Sectional votes and heuristics (e.g., avoid implausible keys with weak support).

The current `key_detection_helpers.py` implements:
- Krumhansl major/minor profiles (`KRUMHANSL_MAJOR`, `KRUMHANSL_MINOR`).
- Normalized templates and correlation scoring (`_score_chroma_profile`).
- Sliding window consensus to capture section‑level keys (`_windowed_key_consensus`).

### 2.2 Essentia `KeyExtractor`

From the Essentia algorithms reference:
- `KeyExtractor`:
  - Standard and streaming variants.
  - Takes audio and returns key, scale (major/minor), and a strength score.
  - Internally uses HPCP‑like pitch class profiles and key profiles similar to Krumhansl/Temperley.

EssentiaServer already wraps this via:
- `_get_essentia_key_extractor`, `_essentia_key_candidate` in `key_detection_helpers.py`.
- `_parse_essentia_key_result` that normalizes Essentia’s `(key, scale, strength)` into:
  - `root` (0–11), `mode` (`"Major"`/`"Minor"`), `score` in [0, 1].

These Essentia candidates are blended with the internal chroma/template method when Essentia is available.

### 2.3 librosa building blocks

librosa does not ship a full key detector, but provides all necessary primitives:

- Chroma feature extractors:
  - `librosa.feature.chroma_cqt`
  - `librosa.feature.chroma_stft`
  - `librosa.feature.chroma_cens`
- Tuning estimation:
  - `librosa.estimate_tuning` (often used before chroma computation).

The current code uses:
- `chroma_cqt` with a fixed hop length and multi‑octave range.
- Summed chroma over time + template correlation (see `_librosa_key_signature` in `key_detection_helpers.py`).

### 2.4 Evaluation frameworks (MIREX)

The MIREX Audio Key Detection task (MIREX wiki):
- Defines the task as identifying the key (major/minor pair) from audio.
- Uses **weighted accuracy** that:
  - Gives full credit for correct keys,
  - Partial credit for musically close errors (e.g., relative major/minor, fifths),
  - No credit for distant keys.

While the exact weighting table is defined in MIREX documents, the practical takeaway:
- Not all key errors are equal; **C→G** is better than **C→F#**.
- Evaluation should reflect harmonic proximity, not only exact matches.

---

## 3. Target Design for EssentiaServer

This section describes the desired architecture, aligned with `detect_global_key` and helpers.

### 3.1 Inputs and outputs

**Inputs:**
- `y_signal` – mono float32 waveform at `KEY_ANALYSIS_SAMPLE_RATE`.
- `sr` – sampling rate for key analysis (may differ from tempo analysis SR).
- Config flags:
  - Whether Essentia is available.
  - Whether to enable window consensus.
  - Any short‑clip vs full‑track specialization.

**Outputs (conceptual `KeyResult`):**
- `key_index`: `int` in `[0, 11]`.
- `key_name`: `str`, from `KEY_NAMES[key_index]`.
- `mode`: `"Major"` or `"Minor"`.
- `confidence`: `[0, 1]` scalar.
- `key_source`: `"librosa"`, `"window_consensus"`, `"runner_interval"`, `"chroma_peak"`, `"essentia"`, `"essentia_edm"`, or `"mode_bias"` (used to trace decision logic).
- Diagnostics:
  - `chroma_profile` (12‑vector),
  - `scores` and `raw_scores`,
  - `window_consensus` with votes, total weights, dominance,
  - Optional `essentia` and `essentia_edm` candidate dicts.

### 3.2 High‑level pipeline

1. **Preprocessing & tuning**
   - Ensure `y_signal` is at a stable key analysis sample rate (`KEY_ANALYSIS_SAMPLE_RATE`).
   - Optionally estimate tuning offset and pass to chroma extractor (e.g., `tuning` argument to `chroma_cqt`).

2. **Chroma extraction**
   - Compute `chroma_cqt` (n_chroma=12, multi‑octave) on the full `y_signal`.
   - Sum across time to form a **global chroma profile** (`chroma_profile`).

3. **Global template matching**
   - Normalize `chroma_profile` and compute scores for all 24 keys:
     - Use cached normalized Krumhansl profiles (`MAJOR_PROFILE`, `MINOR_PROFILE`).
     - For each root, correlate rolled chroma with major and minor profiles.
   - Pick the best key/mode as the initial **fallback**.

4. **Window‑level consensus (section keys)**
   - Slide a window across chroma frames (`KEY_WINDOW_SECONDS`, `KEY_WINDOW_HOP_SECONDS`).
   - For each window: compute a local chroma profile and best key.
   - Accumulate energy‑weighted votes for keys; derive:
     - Dominant key,
     - Runner‑up key weight,
     - Dominance measure (best_weight / total_weight),
     - Full vote list with `"root"`, `"mode"`, `"weight"`.

5. **Combining global and sectional evidence**
   - Compare global fallback key vs window consensus:
     - If window dominance is high (≥ `_WINDOW_SUPPORT_PROMOTION`) and window key differs, consider switching root and/or mode.
     - Use separation between best and runner‑up window weights to avoid flipping on ambiguous songs.

6. **Essentia fusion (when available)**
   - If Essentia is configured:
     - Obtain standard and EDM `KeyExtractor` candidates via `_essentia_key_candidate`.
     - Use their `score`, root, and mode as additional evidence.
     - Blend them using thresholds (`_EDM_STRICT_SCORE`, `_EDM_RELAXED_SCORE`) and interval‑based overrides (perfect/fourth/fifth relationships).

7. **Chroma peak and mode bias heuristics**
   - **Chroma peak root:** if the strongest chroma bin disagrees with current root and is strongly supported by votes, consider promoting it.
   - **Mode bias:** analyze major vs minor scale‑degree prominence around the root (3rd and 6th intervals) to adjust Major/Minor choice when confidence is low.

8. **Confidence computation**
   - Final `confidence` combines:
     - Template score gap between best and runner‑up keys.
     - Section dominance and support ratios.
     - Essentia strength where applicable.
     - Mode vote and chroma peak support, with caps to avoid overconfidence on ambiguous tracks.

---

## 4. Core Algorithms and Heuristics

### 4.1 Chroma and Krumhansl templates

The existing helpers implement a textbook Krumhansl‑style detector:

- **Krumhansl profiles:**
  - `KRUMHANSL_MAJOR`, `KRUMHANSL_MINOR` represent perceptual weights for scale degrees in major/minor.
  - Normalized profiles (`MAJOR_PROFILE`, `MINOR_PROFILE`) are used for correlation.

- **Scoring:**
  - For each root `r` in `[0, 11]` and mode in `{Major, Minor}`:
    - Roll the chroma profile by `-r`.
    - Compute dot product with the major or minor profile.
  - Keep track of:
    - Best candidate (root, mode, score).
    - Full score map for debugging and alternative keys.

This is essentially what many early MIREX systems and `KeyExtractor`‑like algorithms start from.

### 4.2 Windowed key consensus

To handle modulations and sectional emphasis:

- Divide the track into overlapping windows (e.g., 6 s length, 3 s hop).
- For each window:
  - Summed chroma → local profile → best key via template scoring.
  - Weight the vote by energy in the window.
- Aggregate across windows to obtain:
  - A weighted histogram over keys.
  - Dominance (how strongly one key outweighs others).

The current `_windowed_key_consensus` returns:
- `votes`: list of per‑key weights.
- `best`: dominant key+mode and weight.
- `runner_up_weight`, `total_weight`, `dominance`.

This supports:
- Promoting keys that dominate many sections.
- Avoiding overreliance on short, low‑energy passages or intros/outros.

### 4.3 Essentia fusion

When Essentia is available:

- Use `_get_essentia_key_extractor` to create `KeyExtractor` (and optionally EDM‑tuned variant).
- Resample audio if necessary to the expected SR (`ESSENTIA_KEY_FALLBACK_SR` fallback).
- Parse `(key_label, scale_label, strength)` with `_parse_essentia_key_result`, normalizing to:
  - `root`, `mode`, `score` in [0, 1].

Fusion strategy in `key_detection.py`:
- Record Essentia candidates (`result["essentia"]`, `result["essentia_edm"]`).
- Use helper `_essentia_supports` and interval‑based overrides to:
  - Confirm or rescue keys when internal templates are weak.
  - Give more weight to Essentia for EDM‑like material via separate thresholds.

This hybrid approach leverages Essentia’s tuned models where they are strong, while preserving the internal chroma/template pipeline as a baseline.

### 4.4 Mode and interval heuristics

The repo’s helpers already encode several domain‑driven heuristics:

- **Interval‑based runner promotion:**
  - If a runner‑up candidate is close on the circle of fifths or in relative major/minor space, and:
    - Has strong window or Essentia support, or
    - The current key’s support is weak,
  - Promote the runner when the score gap is small (`_RUNNER_SCORE_MARGIN` and related logic).

- **Mode votes and bias:**
  - Use window‑level votes to derive a mode breakdown for the final root.
  - If the track is clearly skewed to major or minor, and the current mode disagrees, adjust the mode and increase confidence.
  - Use chroma‑based scale‑degree bias around the root to gently correct mode when confidence is low.

These heuristics aim to:
- Reduce confusion between relative major/minor (e.g., C major vs A minor).
- Favor musically plausible alternatives (e.g., perfect fifth relationships).

---

## 5. Evaluation and Calibration

### 5.1 Datasets

Recommended key‑focused evaluation sets:

- **GiantSteps Key dataset:**
  - Widely used EDM key dataset with annotations for global key.
  - Good coverage of electronic dance music and DJ‑style keys.
- **Isophonics annotations:**
  - Beatles, Queen, and related corpora with detailed chord and key annotations.
  - Useful for pop/rock context and modulations.
- **Billboard or other chord/lead‑sheet datasets:**
  - Provide tonal context across genres where chords are annotated.
- Internal “Spotify deck”:
  - The 50–60 track calibration set already used by this project, with Spotify key as a noisy ground truth.

### 5.2 Metrics

Following MIREX and common practice, use:

- **Exact accuracy:**
  - Predicted (root, mode) matches ground truth exactly.

- **Weighted accuracy by harmonic proximity:**
  - Full credit for exact matches.
  - Partial credit for:
    - Fifth‑related keys (e.g., C vs G).
    - Relative major/minor (e.g., C major vs A minor).
    - Parallel major/minor (C major vs C minor) if relevant.

- **Confusion matrices on circle of fifths:**
  - Visualize where predictions land relative to ground truth on the circle of fifths.
  - Helps distinguish systematic shifts (e.g., consistently favoring dominant keys).

For EssentiaServer specifically:
- Track **raw detector accuracy** vs **calibrated output** (after any key calibration maps).
- Ensure calibration doesn’t degrade raw performance, similar to the BPM calibration safeguards.

### 5.3 Experiment protocol

For changes to key detection logic:

- Run:
  - Internal test harnesses that export key predictions for the Spotify calibration deck.
  - Offline evaluation scripts for GiantSteps/Isophonics where available.
- Record:
  - Exact accuracy and weighted accuracy.
  - Error breakdown by:
    - Distance on circle of fifths.
    - Relative/parallel confusion.
    - Genre (if labels are available).

Promotion criteria:
- Improved or equal weighted accuracy on external datasets.
- No regression on the internal Spotify deck beyond a small tolerance.
- Better behavior on historically problematic songs listed in internal key analysis docs.

---

## 6. Implementation Notes and Next Steps

### 6.1 Alignment with existing code

The current key detection stack already contains:

- Template‑based detection with Krumhansl profiles (`key_detection_helpers.py`).
- Windowed key consensus for section‑level robustness.
- Essentia integration for both standard and EDM key extractors.
- A multi‑stage fusion pipeline in `detect_global_key` that:
  - Starts from the chroma/template fallback,
  - Optionally applies window consensus,
  - Uses Essentia and interval heuristics to promote better candidates,
  - Refines mode via votes and chroma bias,
  - Outputs a final key, mode, confidence, and source label.

This document should be treated as the **design reference** for future algorithmic tweaks and calibration strategies.

**Comparison policy:** Whenever analyzer keys are compared against references (Spotify deck, calibration CSVs, Mac GUI), the comparison must be **enharmonic‑insensitive**. Both Python (`tools/key_utils.keys_match_fuzzy`) and Swift (`ComparisonEngine.compareKey`) now parse keys into pitch‑class + mode pairs, trying all slash spellings (e.g., `D#/Eb`) and common accidentals before declaring a diff.

### 6.2 Near‑term improvement ideas

Short‑horizon, low‑risk experiments:

- Tighten thresholds for runner promotion and interval overrides to reduce spurious flips for ambiguous tracks.
- Add an explicit **key_confidence calibration** step:
  - Fit a mapping from internal scores and dominance measures to empirical correctness probabilities, using the calibration deck.
- Extend diagnostics:
  - Export “second‑best” key and its score.
  - Log full window vote histograms for the worst‑performing tracks.

### 6.3 Future research directions

- **Local key segmentation:**
  - Expose window‑level keys as a timeline, not just global consensus.
  - Feed section boundaries (from structure detection) back into key segmentation.

- **Chord‑informed key detection:**
  - Integrate chord recognition (when available) to refine key over time.
  - Use chord histograms and progressions as features for key estimation.

- **Learned key models:**
  - Evaluate CNN/CRNN key classifiers trained on GiantSteps/Isophonics as a complement to template‑based methods.
  - Fuse learned models with the existing pipeline using calibration and reliability thresholds.

---

This key‑only research document is intended as the primary guide for anyone working on `backend/analysis/key_detection.py`, `backend/analysis/key_detection_helpers.py`, or the key calibration scripts. It is designed to stay consistent with established MIR practice and the current codebase while leaving room for more advanced, ML‑driven approaches.***
