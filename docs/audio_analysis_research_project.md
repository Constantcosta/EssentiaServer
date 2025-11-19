# Research Project: Building a World-Class Audio Analysis Stack

> **Scope:** End-to-end research and architecture plan for a production-quality music/audio analysis system with three phases:
> 1. **Phase 1** – Reliable BPM (tempo) and key detection.
> 2. **Phase 2** – Rich audio-level metadata (loudness, timbre, dynamics, instrumentation, etc.).
> 3. **Phase 3** – High-level musical understanding (sections, chords, lyrics, metronome click, stems).
>
> **Primary ecosystems & references (online):**
> - Essentia 2.1-beta6-dev (UPF MTG) – [algorithms reference & ML models](https://essentia.upf.edu/algorithms_reference.html)
> - librosa 0.11.x – [Python MIR toolkit docs](https://librosa.org/doc/latest/)
> - madmom – [tempo/beat/downbeat DBN models](https://madmom.readthedocs.io/en/latest/)
> - Music Information Retrieval overview – [MIR survey and tasks](https://en.wikipedia.org/wiki/Music_information_retrieval)
> - Evaluation corpora & tasks – MIREX task descriptions and ISMIR proceedings (various years).

This document synthesizes best practices from these online resources and MIR literature, then adapts them into a concrete architecture and code practices suitable for EssentiaServer.

---

## 1. Overall System Architecture

### 1.1 Core principles

- **Deterministic, reproducible analysis**
  - All models and parameters are versioned; analysis is pure given `(audio, config, model_versions)`.
  - No network calls or non-deterministic randomness inside core analysis.
- **Single responsibility per layer**
  - I/O, decoding, resampling, and caching are separate from DSP/MIR feature extraction.
  - Feature extraction is separate from *decision layers* (tempo selection, key estimation, tagging).
- **Feature-first design**
  - Store dense, generic features (STFT, chroma, onsets, tempograms) as intermediate artifacts.
  - Derived features (BPM, key, sections, chords) are computed from these features so they can be recalculated cheaply.
- **Calibrated against external ground truth**
  - Use Spotify Audio Features, public MIR datasets (e.g., GTZAN, Ballroom, GiantSteps, Isophonics) to calibrate and evaluate.
- **Composable phases**
  - Phase 1 (BPM/key) provides beat grid, chroma, and key context used by Phase 2 and 3.
  - Phase 3 never recomputes basic features; instead it consumes Phase 1/2 outputs.

### 1.2 High-level pipeline

1. **Audio ingestion & normalization**
   - Trusted decoders (ffmpeg/libav) → mono/stereo float32.
   - Standard sample rates (e.g. 44.1kHz) and loudness normalization to a streaming-style target (typically around -14 LUFS).
2. **Frame-level feature extraction**
   - STFT, mel-spectrograms, chroma (CENS/CQT/HCQT), spectral flux, onset strength, tempograms.
   - Resample features to musically meaningful rates (e.g., per-beat, per-bar where needed).
3. **Rhythmic layer**
   - Beat and downbeat tracking, tempo trajectory, tempo histogram.
   - BPM selection (with octave correction) and beat grid.
4. **Pitch/harmony layer**
   - Key & mode estimation, chord candidates per frame, tuning estimation.
5. **Timbre/dynamics layer**
   - Loudness (ITU-R BS.1770 / EBU R128), dynamic range, spectral shape, percussive vs harmonic energy.
6. **Structure & content layer**
   - Section segmentation, motif detection, stem separation, lyric/chord alignment.
7. **Serialization & storage layer**
   - Serialized analysis objects (JSON) + binary feature arrays (NumPy/Arrow/Zarr) stored alongside.
   - Clear schema, with versioned `analysis_version` and per-module `algo_version`.

---

## 2. Code Organization & Versioning Strategy

### 2.1 Packages & layers

Target module layout for the analysis stack (some elements already exist in this repo, others are planned for later phases):

- `backend/analysis/io/`
  - Audio loading, format detection, resampling, loudness normalization.
- `backend/analysis/features/`
  - Small, focused modules (matching current AGENT guide): `time_signature.py`, `loudness.py`, `danceability.py`, `valence.py`, `descriptors.py`, plus future helpers like `timbre.py`, `structure.py`, `stems.py`, etc.
- `backend/analysis/models/`
  - Wrappers for external ML models (Essentia SVMs, TensorFlow/PyTorch models).
  - Local copies of model files, with a registry mapping logical names → file paths + versions.
- `backend/analysis/pipeline_core.py`
  - Orchestration, config parsing, and composition of feature + model calls.
  - No heavy DSP here; call helpers in `features/`.
- `backend/analysis/schemas/`
  - Pydantic/dataclasses describing stable output objects (`TempoResult`, `KeyResult`, `StructureResult`, etc.).

### 2.2 Versioning and reproducibility

- **Global analysis version**
  - `analysis_version` (semver) describes the full pipeline configuration.
  - Major changes in algorithm or training data bump MAJOR; threshold tuning bumps MINOR/PATCH.
- **Per-module `algo_version`**
  - Each feature module exports `ALGO_VERSION = "tempo_v3.1"` or similar.
  - Stored in the output so you can reconstruct which code + model produced a result.
- **Model registry**
  - JSON/YAML registry mapping `model_id` → {`framework`, `path`, `checksum`, `training_data_version`}.
  - Inspired by Essentia’s `models.json` and madmom’s model zoo.
- **Config-driven analysis**
  - Use explicit config objects (e.g. `TempoConfig`, `KeyConfig`) rather than implicit globals.
  - Persist config along with results when running calibration or batch analysis.

---

## 3. Phase 1 – BPM and Key Extraction

For detailed, implementation-level designs, see:
- `docs/bpm_detection_research.md` – BPM/tempo detection deep dive.
- `docs/key_detection_research.md` – key detection and calibration deep dive.

### 3.1 BPM (Tempo) – Algorithms & Best Practices

**Online references**
- Essentia tempo & beat algorithms: `RhythmExtractor2013`, `BeatTrackerMultiFeature`.
- madmom DBN-based beat and downbeat trackers (state-of-the-art in many MIREX tasks).
- Librosa tempo & beat: `librosa.beat.beat_track`, `librosa.feature.tempogram`.

#### 3.1.1 Feature pipeline for tempo

1. **Preprocessing**
   - Convert to mono (energy-preserving), normalize peak or loudness.
   - Optional HPF to remove sub-bass (< 40 Hz) that does not contribute to beat perception.
2. **Onset strength envelope**
   - Compute spectral flux or complex-domain onset strength (librosa `onset_strength`).
   - Apply perceptual weighting (mel bands, log amplitude).
   - Smooth with a short window (e.g. 0.1–0.2 s) but keep transients sharp.
3. **Tempogram & autocorrelation**
   - Compute tempogram via STFT of the onset strength or autocorrelation.
   - Convert lag to BPM, restrict to a sensible range (e.g., 40–240 BPM).
4. **Beat picking & dynamic programming**
   - Use dynamic programming / Viterbi (like madmom) to find beat sequences maximizing onset strength and regularity.
   - Combine multiple tempo candidates (global, local) to avoid locking onto noise.
5. **Octave (multiplicative) ambiguity resolution**
   - Evaluate candidate tempos at `T/2`, `T`, `2T` using:
     - Meter consistency (does the 4/4 or 3/4 pattern make sense?).
     - Onset pattern repetitiveness at bar-scale.
     - Alignment with harmonic rhythm (chord/key changes).
   - Use priors: 80–140 BPM for pop, but allow slow ballads (~60–75) and fast EDM (~128–140).

#### 3.1.2 Calibration of BPM

- **Datasets**
  - Ballroom dataset (tempo annotated).
  - GiantSteps tempo dataset.
  - Internal playlist + Spotify tempo as a proxy.
- **Metrics**
  - Standard MIREX tempo accuracy measures: `P1` (exact), `P2` (octave-allowed), and tolerance-based.
  - Error buckets: `|Δ| ≤ 2%`, `2–4%`, `>4%` and separate bucket for octave errors.
- **Practical calibration steps**
  - Sweep thresholds for onset strength, DP penalties, and octave priors.
  - Plot error vs BPM to detect systematic biases (e.g., always halving 140 BPM tracks).
  - Track **regressions** by always comparing new algo outputs vs frozen baseline on fixed test splits.

### 3.2 Key detection – Algorithms & Best Practices

**Online references**
- Essentia key detection algorithms (e.g., the `KeyExtractor` family documented in the algorithms reference).
- Librosa chroma feature documentation (`chroma_cqt`, `chroma_stft`, `chroma_cens`).
- MIR literature: Krumhansl & Kessler key profiles, Temperley’s key models.

#### 3.2.1 Feature pipeline for key

1. **Tuning estimation**
   - Estimate global tuning deviation in cents (e.g. librosa `estimate_tuning`).
   - Retune spectrogram or CQT to align with tempered semitone grid.
2. **Chroma extraction**
   - Use CQT-based chroma (`chroma_cqt`) for better pitch resolution.
   - Apply harmonic-percussive source separation (HPSS) and use primarily harmonic component.
3. **Aggregation over time**
   - Compute long-term chroma histograms (whole track) and sliding-window chroma for modulations.
   - Weight histogram by local energy to downweight silence/noise.
4. **Template matching**
   - Compare aggregated chroma against major/minor templates (Krumhansl–Kessler, Temperley, or learned templates).
   - Compute correlation scores for all 24 keys; choose top candidates.
5. **Mode and local key changes**
   - Distinguish major vs minor using scale degrees (3rd, 6th, 7th prominence).
   - Optionally detect local keys/segments for tracks with modulations, but output a **global key** for compatibility.

#### 3.2.2 Calibration of key

- **Datasets**
  - GiantSteps key dataset.
  - Isophonics annotations (Beatles, Queen) with key and chord labels.
  - Internal playlists + Spotify key (as a noisy ground truth).
- **Metrics**
  - Exact key accuracy.
  - Fifth-relative accuracy (considering a shift by a perfect fifth as near-miss).
  - Relative major/minor (C major vs A minor) as a softer match.
- **Practical calibration steps**
  - Track confusion matrix between predicted/ground-truth keys.
  - Special-case tracks with pervasive modal interchange or deliberate ambiguity.
  - Use HPSS split to evaluate whether percussive bleed is harming chroma.

---

## 4. Phase 2 – Audio-Level Metadata Extraction

Phase 2 builds on reliable tempo/key results and focuses on descriptors that describe **how the music sounds**, not yet its structure or content.

### 4.1 Loudness & dynamics

**Online references**
- ITU-R BS.1770 loudness & true-peak measurement (used by streaming services).
- EBU R128 loudness range (LRA).
- Essentia loudness and dynamic range algorithms.

**Design**
- Implement a BS.1770-compliant loudness meter (or use Essentia’s implementation).
- Compute:
  - Integrated LUFS, short-term and momentary loudness.
  - Loudness range (LRA) to reflect dynamic contrast.
  - Peak vs RMS levels; dynamic range metrics (e.g., crest factor, PLR).
- Store as `LoudnessResult` with time series where useful.

### 4.2 Timbre & spectral shape

**Online references**
- Librosa spectral features: centroid, bandwidth, rolloff, flatness, contrast.
- Essentia spectral descriptors.

**Design**
- Extract per-frame spectral descriptors, then aggregate:
  - Spectral centroid & spread – brightness.
  - Spectral rolloff – edge frequency.
  - Spectral flatness – noisiness.
  - Spectral contrast – presence of clear bands like vocals or guitars.
- Use HPSS to separately characterize harmonic and percussive spectra.

### 4.3 Rhythm & movement descriptors (beyond BPM)

**Online references**
- Danceability research (Spotify-style metrics; various ISMIR papers).
- madmom tempo curve features.

**Design**
- From beat grid and onset patterns compute:
  - Beat strength and regularity.
  - Syncopation / swing via deviation from perfectly even grid.
  - Tempo stability across track sections.
- Combine into interpretable high-level features:
  - `danceability`, `energy`, `rhythmic_complexity`.

### 4.4 Instrumentation & production style

**Online references**
- Essentia music tagging models (e.g., `MusicExtractor` tags, MTG genre/instrument models).
- Open-source tagging models (e.g. models trained on MagnaTagATune, Million Song Dataset, or MTG-Jamendo).

**Design**
- Use supervised tagging models to estimate:
  - Broad genres (rock, pop, EDM, jazz, …).
  - High-level instruments (vocals, guitars, piano, drums, strings, synth).
  - Production traits (acoustic vs electronic, live vs studio, reverb amount).
- Calibrate tags against public tag datasets and internal human labels.

### 4.5 Perceptual features (valence, arousal, mood)

**Online references**
- DEAM dataset (Dynamic Emotion in Music) and related ISMIR work.
- Essentia’s mood and emotion models.

**Design**
- Avoid purely heuristic mood models; use ML models trained on explicit emotion annotations when possible.
- Input features: mel-spectrograms, tempo and key context, dynamics, vocal presence.
- Outputs:
  - Valence (sad ↔ happy) and arousal (calm ↔ energetic).
  - Discrete tags like “sad”, “uplifting”, “tense”.
- Calibrate using mean squared error and rank correlation vs annotated datasets.

---

## 5. Phase 3 – Musical Analysis & High-Level Content

Phase 3 uses all lower-level features to infer musical structure and content that are meaningful to musicians and listeners.

### 5.1 Metronome click track generation

**Inputs:** Beat grid, tempo curve, downbeat positions, time signature.

**Design**
- Generate a beat-aligned time series (`click_events`) where each event has:
  - `time`, `bar_index`, `beat_in_bar`, `intensity` (accent on downbeats).
- Export clicks as:
  - Audio (WAV) using short impulses or noise bursts.
  - MIDI with note-on events (e.g., C3 for beat, C4 for bar).
- Ensure phase alignment with original audio (respecting any resampling delays).

### 5.2 Stem separation

**Online references**
- Spleeter, Demucs, and other open-source source separation models.
- ISMIR papers on source separation (e.g., MUSDB18 benchmark).

**Design**
- Integrate an off-the-shelf separation model (e.g., Demucs v4) in a separate process or microservice.
- Standard stem sets: `vocals`, `drums`, `bass`, `other` (or more when supported).
- Align stems to original audio and store as references.
- Use stems to improve other tasks:
  - Chords from harmonic stem.
  - Drum-specific rhythm features from drum stem.

### 5.3 Section detection (structure segmentation)

**Online references**
- Structural segmentation methods using novelty curves, self-similarity matrices (SSM), and clustering.
- Librosa’s structure segmentation example (SSM + agglomerative clustering).

**Design**
- Compute a mid-level feature representation (e.g., harmonic MFCCs + chroma on beat-synchronous frames).
- Build self-similarity matrix (SSM) over beats.
- Compute novelty curve and apply peak-picking to find boundaries.
- Optionally cluster sections into labels: `intro`, `verse`, `chorus`, `bridge`, `outro` using template-based or learned models.
- Calibrate against datasets with structural annotations (e.g., SALAMI).

### 5.4 Chord recognition

**Online references**
- Chord recognition with chroma features, HMMs, and deep learning (e.g., Chordino, deep-chroma based models).
- Isophonics and Billboard chord datasets.

**Design**
- Inputs: harmonic CQT/chroma, beat grid, key context, stems.
- Model options:
  - Template-based HMM (emission: chroma vs chord templates; transitions: harmonic grammar).
  - Deep models over CQT patches (e.g., CNN or CRNN).
- Output: sequence of `(time_start, time_end, chord_label)` with confidence.
- Calibrate using frame-wise and segment-wise chord accuracy vs annotated datasets.

### 5.5 Lyrics detection & alignment

**Online references**
- Singing voice detection (SVD) models.
- Automatic speech recognition (ASR) specialized for singing (e.g., recent work from ISMIR / Interspeech).

**Design**
- Stage 1: voice activity detection for music (singing vs non-singing).
- Stage 2: lyric transcription with ASR model trained/fine-tuned on singing.
- Stage 3: alignment of text tokens to time via CTC decoding or forced alignment.
- Privacy & licensing:
  - Be explicit about whether you store full lyrics, partial snippets, or only timings for licensed content.

### 5.6 Integrated musical representation

- Combine outputs into a coherent timeline representation:
  - Beats, bars, sections, chords, lyrics lines, structural markers.
- Provide query and visualization capability:
  - “Jump to first chorus”, “show chord chart”, “render click for verses only”.

---

## 6. Data Storage, Schemas, and APIs

### 6.1 Storage formats

- **Raw features**
  - Use compressed NumPy (`.npz`), Arrow, or Zarr for large arrays.
  - Organize by feature family: `tempo_features`, `chroma_features`, `structure_features`.
- **Summaries & results**
  - Store JSON/MsgPack per track with stable schema and version fields.
  - Keep it small and API-friendly (no gigantic arrays inside JSON).

### 6.2 Example schemas

- `TempoResult`
  - `bpm`, `confidence`, `bpm_candidates`, `beat_times`, `downbeat_times`, `algo_version`.
- `KeyResult`
  - `key`, `mode`, `confidence`, `alternative_keys`, `tuning_cents`, `algo_version`.
- `StructureResult`
  - List of segments: `{label, start, end, confidence}`.
- `ChordsResult`
  - List of chords: `{label, start, end, confidence}`.

### 6.3 API design

- Expose layered endpoints:
  - `/analyze/basic` → Phase 1 + 2 core (tempo, key, loudness, energy).
  - `/analyze/full` → Phase 1–3 with structure, stems, chords.
  - `/analyze/features` → low-level features for research/debug.
- Include `analysis_version` and per-module `algo_version` in all responses.

---

## 7. Calibration, Evaluation, and Continuous Improvement

### 7.1 Evaluation datasets

- Public MIR datasets for each task (tempo, key, chords, structure, tags).
- Internal “golden set” of curated tracks with human annotations.
- Spotify-style reference features for broad-scale sanity checks.

### 7.2 Metrics per phase

- **Phase 1**
  - Tempo accuracy (P1/P2), octave error rate.
  - Key accuracy (exact, fifth-relative, relative major/minor).
- **Phase 2**
  - Regression-style metrics (MSE, MAE, rank correlation) for continuous descriptors.
  - Classification metrics (precision/recall/F1) for tags.
- **Phase 3**
  - Segment boundary F-measure for structure.
  - Chord frame and segment accuracy.
  - Word error rate for lyrics; alignment error.

### 7.3 Experiment tracking

- Use experiment tracking tools (Weights & Biases / MLflow / custom DB) for:
  - Model configs, dataset versions, metrics, qualitative notes.
- Define promotion criteria for new algorithms (e.g., “no regression on golden set, >5% improvement on chord accuracy”).

---

## 8. Engineering Practices for Long-Term Maintainability

### 8.1 Code quality & style

- Keep feature helpers small, pure, and fully unit-tested (as per `backend/analysis/AGENTS.md`).
- Avoid hard-coded constants; group them in config objects or module-level dicts.
- Document each algorithm with links to the corresponding paper, dataset, or model card.

### 8.2 Testing strategy

- **Unit tests** for DSP primitives and feature functions.
- **Golden audio tests** comparing JSON summaries against frozen expected outputs (with tolerances).
- **Fuzz tests** for weird audio: silence, noise, clipped audio, extremely long tracks.

### 8.3 Performance & scalability

- Profile end-to-end analysis on representative workloads.
- Batch model inference where possible (e.g., run tagging models on multiple tracks at once).
- Use background workers and job queues for heavy tasks (stems, full structure, lyrics).

### 8.4 Observability & monitoring

- Log `analysis_version`, timing breakdown per module, and failure modes.
- Track distribution of outputs (BPM, key, loudness) over time to detect drifts.

---

## 9. Concrete Next Steps for This Project

1. **Finalize Phase 1**
   - Harden BPM octave selection using beat-grid + harmonic rhythm cues.
   - Replace/augment key detection with Essentia/learned model and calibrate on GiantSteps + internal set.
2. **Systematize calibration**
   - Create unified evaluation scripts for tempo, key, and other features, using public datasets.
   - Add CI jobs that run a small golden set on each merge.
3. **Prototype Phase 2 features**
   - Implement BS.1770 loudness module and stable `LoudnessResult` schema.
   - Start tagging pipeline using Essentia tagging models or open-source CNNs.
4. **Plan Phase 3 roll-out**
   - Start with structure segmentation and chord recognition (highest impact/maturity).
   - Design schemas and endpoints for click track generation and chord charts.

This research plan should serve as a blueprint for evolving EssentiaServer into a state-of-the-art, well-calibrated audio analysis platform grounded in current MIR best practices and online resources.
