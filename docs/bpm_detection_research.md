# Research Project: BPM / Tempo Detection

**Scope:** Deep-dive into BPM (tempo) detection only: algorithms, evaluation, and a concrete design tailored to EssentiaServer, informed by current MIR practice and online references.

**Last validated against online docs:** 2025‑11‑18  
**Primary external references (tempo-specific):**
- Essentia 2.1‑beta6‑dev algorithms: `RhythmExtractor`, `RhythmExtractor2013`, `BeatTrackerMultiFeature`, `BpmHistogram`, `BpmHistogramDescriptors`  
  https://essentia.upf.edu/algorithms_reference.html
- librosa tempo utilities: `onset_strength`, `beat_track`, `feature.tempo`, `beat.plp`  
  https://librosa.org/doc/latest/
- madmom tempo/beat modules and evaluation tools  
  (e.g. `madmom.features.tempo`, `madmom.evaluation.tempo`)  
  https://madmom.readthedocs.io/en/latest/
- MIREX “Audio Tempo Extraction” task and P‑score definition  
  https://www.music-ir.org/mirex/w/index.php/Audio_Tempo_Extraction

This document replaces the high-level BPM section in `audio_analysis_research_project.md` with a focused, implementable design.

---

## 1. Problem Definition

### 1.1 What “BPM detection” means here

- **Goal:** Estimate a single, perceptually meaningful global tempo (BPM) plus a beat grid for a full track.
- **Output focus for this project:**
  - `bpm` – primary global tempo in beats per minute.
  - `bpm_confidence` – unitless [0, 1] confidence score.
  - `beats` – frame or time positions of beats.
  - Debug fields: per-detector BPMs, alias candidates, scoring breakdown.
- **Out of scope for this doc:**
  - Local tempo curves and expressive tempo trajectories.
  - Swing/groove descriptors (covered elsewhere as “rhythm & movement”).

### 1.2 Perceptual vs notated tempo

MIREX’s Audio Tempo Extraction task and the MIREX wiki emphasize **perceptual tempo**: the tempo humans tap along with, which may differ from the notated or DAW grid tempo (e.g., 70 BPM vs a notated 140 BPM).  

For EssentiaServer:
- We treat Spotify BPM as a **noisy ground truth** for calibration, but design algorithms to recover a perceptual tempo that:
  - Aligns with how a drummer or listener would tap,
  - Respects common usage in music production and DJ tools,
  - Still behaves sensibly on ambiguous tracks (polyrhythms, halftime/doubletime).

---

## 2. Overview of Established Approaches

### 2.1 Essentia

Based on the Essentia 2.1 algorithms reference:
- `RhythmExtractor` / `RhythmExtractor2013`:
  - Compute onset detection functions and novelty curves.
  - Use tempo histogram and beat tracking to estimate:
    - Global BPM, beat positions, and confidence.
  - `RhythmExtractor2013` is a higher-level, “all‑in‑one” algorithm that wraps onset, periodicity analysis, and beat tracking.
- `BeatTrackerMultiFeature`:
  - Combines multiple features (spectral flux, energy bands, etc.) and beat tracking to estimate beat positions.
- `BpmHistogram` / `BpmHistogramDescriptors`:
  - Analyze periodicities in a novelty curve (e.g., onset energy) and summarize them as histogram descriptors and dominant tempos.

Essentia’s design pattern:
- Build a **novelty curve/onset envelope**, derive a BPM histogram, and combine with beat tracking to pick tempo and beats.

### 2.2 librosa

From the librosa docs (0.11.x):
- `librosa.onset.onset_strength`:
  - Computes an onset strength envelope from either an STFT magnitude or a time-domain signal.
- `librosa.beat.beat_track`:
  - Returns an estimated global tempo and frame indices of beats, using DP/Viterbi‑like tracking on the onset envelope.
- `librosa.feature.tempo`:
  - Estimates global tempo from onset strength or tempogram.
- `librosa.beat.plp` and `librosa.beat.tempo`:
  - Use predominant local pulse (PLP) to infer tempo from onset envelopes.

This aligns closely with the current EssentiaServer implementation in `backend/analysis/tempo_detection.py`, which already uses:
- `onset_strength` with HPSS,
- `beat_track` and `feature.tempo` as two detectors,
- PLP‑based tempo as a third detector.

### 2.3 madmom

From the madmom documentation:
- `madmom.features.tempo`:
  - Provides tempo estimation features and models; often used with DBN‑based beat/tempo trackers.
- `madmom.evaluation.tempo`:
  - Implements evaluation metrics compatible with MIREX tempo tasks.

Key ideas borrowed conceptually:
- Use **probabilistic beat tracking** (e.g., DBN) on top of onset features.
- Evaluate tempo with metrics that account for octave ambiguities and multiple dominant tempi (P‑score).

### 2.4 MIREX Audio Tempo Extraction

From the MIREX “Audio Tempo Extraction” task page:
- Aim: Extract **perceptual tempo** from audio.
- Ground truth: Often two perceived tempos with salience weights.
- Algorithms are evaluated using a **P‑score** (0–1), with 1 meaning perfect performance.

For EssentiaServer we approximate this with:
- Single “best” BPM per track, but consider **octave-equivalent** matches during evaluation (see §4.2).

---

## 3. Target Design for EssentiaServer

This design formalizes and slightly generalizes the current implementation in `backend/analysis/tempo_detection.py`.

### 3.1 Inputs and outputs

**Inputs:**
- `y_trimmed` – mono float32 waveform after trimming leading/trailing silence.
- `sr` – sampling rate (e.g., 22050 Hz, configurable).
- `hop_length` – analysis hop length (linked to `settings.ANALYSIS_HOP_LENGTH`).
- `tempo_segment` – central segment for tempo analysis (e.g., first N seconds or a stable mid‑section).
- `tempo_window_meta` – metadata flags, e.g. `full_track: bool`.
- Optional: `stft_magnitude`, HPSS components, analysis context and timers.

**Outputs (TempoResult):**
- `bpm`: float, chosen global tempo.
- `bpm_confidence`: float in [0, 1].
- `onset_env`: onset strength envelope used for detection.
- `beats`: beat positions (frame indices or seconds).
- Diagnostic fields:
  - `tempo_percussive_bpm`, `tempo_onset_bpm`, `tempo_plp_bpm`
  - `best_alias`, `scored_aliases`, `plp_peak`, `tempo_window_meta`

### 3.2 High-level pipeline

1. **Preprocessing & HPSS**
   - Compute harmonic/percussive decomposition on `tempo_segment`.
   - Prefer percussive components for onset detection.
2. **Onset strength**
   - Compute `onset_env` with `librosa.onset.onset_strength`:
     - Use `S=stft_percussive` when available for more stable onset energy.
     - Fall back to `y=tempo_percussive` (time‑domain) otherwise.
3. **Multiple tempo detectors**
   - **Detector A:** `librosa.beat.beat_track(onset_envelope=onset_env, …)` → `tempo_percussive_bpm`, `beats`.
   - **Detector B:** `librosa.feature.tempo(onset_envelope=onset_env, …)` → `tempo_onset_bpm`.
   - **Detector C:** PLP tempo via:
     - `plp_envelope = librosa.beat.plp(onset_envelope=onset_env, …)`
     - `tempo_plp_bpm = librosa.beat.tempo(onset_envelope=plp_envelope, …)`.
4. **Alias candidate generation**
   - Build candidate BPMs by applying alias factors to Detector A/B outputs (see §3.3).
5. **Candidate scoring**
   - Score each candidate using:
     - Detector agreement,
     - PLP consistency,
     - Tempo alignment priors,
     - Optional chunk stability and spectral cues (see §3.4).
6. **Onset‑energy validation**
   - Validate/amend the chosen BPM using on/off‑beat onset energy separation (see §3.5).
7. **Confidence estimation**
   - Derive `bpm_confidence` from the winning candidate’s score, normalized to [0, 1].

---

## 3.3 Alias handling and BPM candidate generation

**Problem:** Tempo detectors often latch on to a correct **beat subdivision** but the wrong octave (e.g., 2× or 0.5× the perceptual tempo), and occasionally non‑octave ratios (e.g., 0.75×).

### 3.3.1 Core alias factors

We keep a conservative core set of alias factors (matching the current implementation in `tempo_detection.py`):

```python
_ALIAS_FACTORS = (0.5, 1.0, 2.0)
_MIN_ALIAS_BPM = 20.0
_MAX_ALIAS_BPM = 280.0
```

For each detector BPM (percussive, onset):
- Multiply by each factor.
- Clamp within `[MIN_ALIAS_BPM, MAX_ALIAS_BPM]`.
- Deduplicate by rounding BPM to a small decimal grid.

Result: a small, high‑quality pool of BPM alias candidates that cover the common doubling/halving errors and most perceptual cases.

### 3.3.2 Extended alias factors (research direction)

The separate `BPM_IMPROVEMENT_PLAN.md` shows that naively adding factors such as 0.66×, 0.75×, 1.33×, 1.5× can fix some songs but risks regressions.

Recommended approach (future work):
- Restrict extended factors to targeted scenarios where:
  - The top candidate scores are tightly clustered (low confidence).
  - The track is **not** a slow ballad (protected range, see existing slow‑ballad logic in `pipeline_core.py`).
  - The extended BPM lies in a reasonable tempo band (e.g., 80–140 BPM).
  - The extended candidate’s score passes a minimum quality threshold.

---

## 3.4 Candidate scoring and priors

### 3.4.1 Tempo similarity with detector agreement

We use a soft tempo similarity that implicitly treats 0.5× and 2× as near‑matches:

```python
def _tempo_similarity(candidate_bpm: float, reference_bpm: float) -> float:
    # Exp(−|Δ| / 15) after comparing to 0.5×, 1×, 2× aliases
```

This yields a score in [0, 1] that:
- Peaks when candidate BPM is close to any of {0.5, 1, 2}× reference,
- Decays smoothly as the difference grows.

Each candidate gets:
- `detector_support` – max similarity vs percussive and onset detectors.
- `plp_similarity` – similarity vs PLP tempo if available.

### 3.4.2 Tempo alignment and priors

We combine detector support with:
- `tempo_alignment_score(bpm)` – project‑specific heuristic to prefer tempos aligned with musical grid, energy distribution, and calibration knowledge.
- **Octave preference priors** (implemented in `_score_tempo_alias_candidates`):
  - 80–140 BPM: strong preference (e.g., +0.15).
  - 40–80 or 140–180 BPM: mild preference (e.g., +0.05).
  - Outside these ranges: no extra boost.

This reflects common practice in MIR and streaming services: most pop/rock/EDM sits between 80 and 140 BPM, but we explicitly preserve the ability to represent slow ballads and very fast tracks.

### 3.4.3 Confidence shaping and stability

Additional factors:
- `plp_peak` – strength of the predominant local pulse; used to boost confidence:

```python
confidence_boost = 0.7 + 0.3 * clamp_to_unit(plp_peak)
score = base_score * confidence_boost
```

- `chunk_bpm_std` (optional future hook):
  - Penalize candidates when per‑chunk BPM estimates are inconsistent.
  - Encourages stable tempos across the track and downweights noisy estimates.

The final candidate score is clipped into [0, 1], and the best candidate becomes `best_alias`.

---

## 3.5 Onset-energy validation and octave correction

Even after alias scoring, some tracks can be corrected by examining **on/off‑beat onset energy**.

### 3.5.1 Separation-based validation

We compute a simple separation score:

```python
def _compute_onset_energy_separation(test_bpm, onset_env, sr, hop_length):
    # 1. Estimate beat interval in frames.
    # 2. For each beat index: accumulate on-beat energy from a small window.
    # 3. Accumulate off-beat energy at midpoints between beats.
    # 4. Return on_mean / (off_mean + ε).
```

Higher values mean a clearer distinction between beats and non‑beats.

Validation procedure:
- Evaluate `test_bpms = [bpm, bpm*0.5, bpm*2.0]` (within allowed range).
- Compute separation scores for each.
- If a candidate’s separation is significantly better and passes a minimum threshold, adopt it as the corrected BPM.

### 3.5.2 Special handling for slow ballads

The current production code adds a **slow ballad guard**:
- Detect potential slow ballads based on:
  - BPM range (e.g., 60–90 BPM),
  - Energy profile early in the track.
- Skip aggressive octave “corrections” for such tracks to avoid false doubling.

This is consistent with both ESSENTIA/MIREX insights and project experience:
- Slow, low‑energy tracks are especially vulnerable to mis‑doubling.
- For these, we prefer to trust the alias scoring (and PLP) rather than forced doubling.

---

## 4. Evaluation and Calibration

### 4.1 Datasets

Recommended external datasets (tempo‑specific), in addition to internal Spotify‑based calibration:
- **Ballroom**:
  - Classic dataset with manually annotated tempos; widely used in tempo research.
- **GiantSteps Tempo**:
  - Tempo annotations for EDM tracks; useful for high‑tempo, strong beat material.
- Internal “golden set”:
  - Curated subset of production tracks with manually verified BPM (possibly cross‑checked with Spotify).

### 4.2 Metrics

Inspired by MIREX and madmom’s evaluation tools:
- **P1 (exact tempo accuracy)**:
  - Proportion of tracks where predicted tempo is within a small tolerance (e.g., ±4%) of ground truth.
- **P2 (octave‑aware accuracy)**:
  - Similar to P1, but considers octave aliases (0.5× and 2× of ground truth) as correct.
- **Error buckets**:
  - `|Δ| ≤ 2%`, `2–4%`, `>4%`, plus a dedicated **octave error** bucket.

Project‑specific additions:
- Track per‑genre performance (ballads vs EDM vs rock).
- Track calibration vs **raw** detection:
  - Keep both “uncalibrated BPM” and “calibrated BPM” metrics to ensure calibration steps don’t degrade a good detector.

### 4.3 Experiment protocol

For every BPM change:
- Run:
  - Internal test scripts (`./run_test.sh b`, `./run_test.sh d`).
  - An offline evaluation script that:
    - Computes P1/P2 and error buckets on Ballroom/GiantSteps + internal sets.
    - Produces confusion plots of predicted vs reference BPM.
- Compare against:
  - A frozen baseline CSV of prior results,
  - Spotify BPM values used during calibration.

Promotion criteria:
- No regressions on high‑confidence tracks (e.g., GREEN songs in internal dashboards).
- Clear net improvement in P1/P2 on at least one external dataset and the internal golden set.

---

## 5. Implementation Notes and Next Steps

### 5.1 Alignment with existing code

The current `backend/analysis/tempo_detection.py` already implements:
- Multi‑detector tempo estimation using:
  - `beat_track` (percussive onset),
  - `feature.tempo` (onset envelope),
  - PLP‑based tempo.
- Alias candidate generation with `(0.5, 1.0, 2.0)` factors.
- Candidate scoring with detector agreement, PLP, and octave priors.
- Onset‑energy validation with simple 0.5×/2× testing.

This document should be treated as the **design reference** for future modifications to that module and related calibration.

### 5.2 Immediate, low-risk improvements

Without introducing new dependencies, near‑term research tasks:
- Tighten separation thresholds in `_validate_octave_with_onset_energy` to avoid over‑correcting high‑confidence candidates.
- Add robust `bpm_confidence` mapping from candidate scores for better downstream decision‑making (e.g., deciding whether to display BPM to users or flag it as low confidence).
- Introduce optional `chunk_bpm_std` based on per‑window tempo to penalize unstable candidates.

### 5.3 Future research directions

- **Probabilistic beat/tempo models**:
  - Evaluate madmom‑style DBN beat tracking as a reference or optional backend.
- **Tempo curve & expressive timing**:
  - Extend from single BPM to a slow‑varying tempo trajectory, while still exposing a global BPM for compatibility.
- **Joint calibration with other features**:
  - Use key, energy, and danceability to inform priors on plausible BPM ranges (e.g., cross‑feature calibration).

---

This BPM‑only document should be the primary reference for anyone modifying `tempo_detection.py`, the BPM parts of `pipeline_core.py`, or the calibration scripts that transform raw BPM into Spotify‑aligned values.***
