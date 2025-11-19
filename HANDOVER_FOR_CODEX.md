# Handover for Codex: Achieve 99% Audio Analysis Accuracy

**Date:** 18 November 2025  
**Current State:** Generalized algorithms, 50% BPM / 16.7% Key accuracy on Test C  
**Goal:** 99% accuracy on both BPM and Key detection using advanced reasoning and implementation

---

## Current Situation

### Test Results (Test C - First 6/12 Files)
- **BPM Accuracy:** 3/6 (50%) - massive octave errors
- **Key Accuracy:** 1/6 (16.7%) - fifth-related and mode errors
- **Status:** All song-specific overfitting removed, code is honest but inadequate

### What Was Done
✅ Removed all hardcoded BPM bypasses (140-150, 105-110 ranges)  
✅ Removed song-specific calibrations ("3am", "Girls 2 Become 1", etc.)  
✅ Implemented research-compliant octave preference priors  
✅ Added ±10 BPM calibration safety cap  
✅ Code now treats ALL audio sources equally  

### The Problem
Current algorithms are **fundamentally limited** for 30-second preview clips:
- Onset-energy separation unreliable on short clips
- Linear calibration trained on full tracks, not previews
- Octave preference priors too weak (+40% insufficient)
- Key detection lacks robust chroma analysis and harmonic context

---

## Objective

**Achieve 99% accuracy** on:
- BPM detection (octave-aware P2 metric)
- Key detection (exact root + mode)

For **any audio source** - no song-specific hacks, no overfitting.

---

## Why Codex?

We need **advanced reasoning and implementation** to:

1. **Redesign octave selection logic** - Current approach fails on 30s clips
2. **Implement ensemble detection** - Weight multiple detectors intelligently
3. **Build confidence-aware calibration** - Only calibrate uncertain detections
4. **Enhance key detection** - Better chroma analysis, harmonic proximity scoring
5. **Create adaptive algorithms** - Adjust parameters based on clip duration/genre
6. **Validate against research** - Implement MIREX-compliant evaluation

Use Codex's advanced capabilities to design and implement production-quality algorithms that work on short clips, full tracks, and everything in between.

---

## Technical Foundation

### Research Documents
- `docs/bpm_detection_research.md` - MIREX standards, P1/P2 metrics, octave handling
- `docs/key_detection_research.md` - MIREX weighted accuracy, circle of fifths, harmonic proximity
- `docs/audio_analysis_research_project.md` - Overall MIR best practices

### Key Algorithms
- **BPM:** Multi-detector (librosa beat_track, feature.tempo, PLP) with alias scoring
- **Key:** Essentia KeyExtractor + chroma-based template matching
- **Calibration:** Linear scaler (slope=0.7365, intercept=31.276) - currently unreliable

### Critical Code
- `backend/analysis/tempo_detection.py` - BPM detection with octave correction
- `backend/analysis/key_detection.py` - Key detection with mode/root extraction
- `backend/analysis/calibration.py` - Post-processing corrections
- `backend/analysis/settings.py` - Adaptive parameters by clip duration

### Test Framework
- `./run_test.sh c` - Runs Test C (12 preview files in 2 batches of 6)
- `analyze_test_c_accuracy.py` - Compares results vs Spotify ground truth
- `csv/test_results_*.csv` - Timestamped output with all metrics

---

## Specific Failures to Fix

### BPM Octave Errors (50% accuracy)
1. **"3am" - Matchbox Twenty:** 215 BPM detected, should be 108 BPM (2× error)
2. **"2 Become 1" - Spice Girls:** 137 BPM detected, should be 144 BPM
3. **"4ever" - The Veronicas:** 137 BPM detected, should be 146 BPM
4. **"A Thousand Miles" - Vanessa Carlton:** 160 BPM detected, should be 95 BPM (~1.7× error)

**Root Cause:** Onset-energy validation unreliable on 30s clips, octave preference priors insufficient

### Key Detection Errors (16.7% accuracy)
1. **"! (The Song Formerly Known As)" - Regurgitator:** F# Minor detected, should be B (mode + fifth error)
2. **"2 Become 1" - Spice Girls:** F# Major detected, should be F#/Gb (enharmonic but wrong mode)
3. **"4ever" - The Veronicas:** F Minor detected, should be F minor ✓ (one of few correct)
4. **"A Thousand Miles" - Vanessa Carlton:** B Major detected, should be B (wrong mode)
5. **"A Whole New World" - ZAYN:** A Major detected, should be D (perfect fifth off)

**Root Cause:** Mode detection weak, fifth-related errors common, chroma analysis insufficient

---

## Required Approach

### 1. Advanced BPM Detection
- Implement **confidence scoring** for each detector
- Weight detectors based on audio characteristics (percussive content, tempo range)
- Use **multiple features** beyond onset strength (spectral flux, energy variance)
- Design **clip-length-aware** octave selection (different logic for 30s vs full tracks)
- Validate using beat-grid alignment, not just energy separation

### 2. Advanced Key Detection  
- Implement **robust chroma analysis** with harmonic product spectrum
- Add **fifth-related disambiguation** using chord progressions
- Build **mode classifier** that analyzes major vs minor characteristics
- Use **template correlation** weighted by harmonic stability
- Consider **multiple time segments** to handle modulations

### 3. Intelligent Calibration
- Only calibrate when **confidence is below threshold**
- Use **different calibration models** for different BPM/key ranges
- Implement **sanity checks** - never calibrate across octaves
- Track **calibration effectiveness** - disable if degrading accuracy

### 4. Validation & Testing
- Implement **MIREX-compliant metrics** (P1/P2 for BPM, weighted accuracy for keys)
- Create **detailed error analysis** - categorize by error type (octave, fifth, mode)
- Test on **external datasets** (GiantSteps, Ballroom, Isophonics)
- Ensure **no regression** on Test A (currently 100% accuracy)

---

## Success Criteria

✅ **99% BPM accuracy** (P2 octave-aware) on Test C  
✅ **99% Key accuracy** (exact root + mode) on Test C  
✅ **Zero octave errors** on 80-140 BPM range  
✅ **Zero systematic errors** (no fifth-related or mode patterns)  
✅ **No song-specific code** - algorithms work on ANY audio  
✅ **Performance acceptable** - <5s analysis time per track  

---

## Resources

**Python Environment:** `.venv` with essentia, librosa, numpy, scipy  
**Server:** `backend/server/essentia_server.py` - handles analysis requests  
**Logs:** `/tmp/essentia_server.log` - detailed debug output  

**Test Commands:**
```bash
./run_test.sh c              # Run Test C
.venv/bin/python analyze_test_c_accuracy.py  # Analyze results
```

**Latest Results:** `csv/test_results_20251117_*.csv`

---

## Next Steps for Codex

1. **Analyze current detector outputs** - Review raw BPM/key values before calibration
2. **Identify patterns in failures** - Why are these specific songs failing?
3. **Design improved algorithms** - Use advanced reasoning to solve octave/mode detection
4. **Implement incrementally** - Test each improvement against Test C
5. **Validate rigorously** - Ensure 99% accuracy without overfitting

Use your advanced implementation capabilities to build production-quality audio analysis that works reliably on any source.

---

**Current Branch:** `copilot/improve-slow-code-efficiency`  
**Previous Agent:** Removed overfitting, achieved honest baseline (75% overall)  
**Codex Mission:** Achieve 99% accuracy through advanced algorithm design
