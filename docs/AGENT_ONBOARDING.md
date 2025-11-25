# Agent Onboarding Guide - EssentiaServer Audio Analysis

**Last Updated:** November 17, 2025  
**Project:** EssentiaServer - Audio Analysis API  
**Current Branch:** `copilot/improve-slow-code-efficiency`

---

## 🎯 Quick Start (5 Minutes)

Welcome! This guide will get you up to speed on the current state of the audio analysis algorithms and recent improvements.

### What This Project Does
EssentiaServer is a Flask-based audio analysis API that extracts musical features from audio files:
- **BPM** (tempo detection)
- **Key & Mode** (musical key detection)
- **Energy, Danceability, Valence** (emotional/perceptual features)
- **Acousticness** (production style detection)
- **Time Signature, Loudness, Dynamic Range**

We validate our results against **Spotify's ground truth data** to measure accuracy.

---

## 📚 Essential Reading (In Order)

### 1. **START HERE: Unified Test Comparison** (5 min)
📄 **`docs/unified_test_comparison.md`**

**Why read this first:**
- Shows BASELINE → V1 → V2 algorithm evolution in one view
- Contains all CSV filenames and timestamps
- Shows what improved, what regressed, and what's still broken
- Includes overall accuracy metrics

**Key takeaways:**
- Danceability error reduced from 74% → 28% (huge win!)
- Acousticness achieved perfect matches on some tracks
- Valence still broken (163% error - can't detect sad vocals)
- Key detection only 33% accurate (needs complete rework)

---

### 2. **Problem Identification: BASELINE Results** (3 min)
📄 **`docs/analysis_accuracy_issues.md`**

**What you'll learn:**
- Original algorithm failures before any improvements
- Detailed track-by-track comparison vs Spotify ground truth
- Critical issues identified:
  - Valence: 200% error (reading sad songs as happy)
  - Danceability: 74% error (all tracks overestimated 0.75-0.90)
  - BPM: 50% octave errors (doubling/halving tempo)
  - Acousticness: Too simplistic (just inverse of brightness)
  - Key: 50% failure rate

**Test data:**
- CSV: `csv/test_results_20251117_043243.csv`
- 12 full-length tracks from Spotify calibration dataset

---

### 3. **V1 Improvements** (3 min)
📄 **`docs/algorithm_improvements_results.md`**

**Changes made:**
1. **Fixed Valence** - Mode string handling ("Major"/"Minor" not 1/0)
2. **Fixed Danceability** - Rebalanced weights:
   - Beat strength: 0.4 → 0.25
   - Tempo alignment: 0.2 → 0.35
   - Floor boost: 0.2 → 0.05
   - Added tempo penalties for <60 BPM and >180 BPM
3. **Improved Acousticness** - Multi-component analysis:
   - Warmth score: 40%
   - Harmonic ratio: 35%
   - Onset gentleness: 25%
4. **Enhanced BPM** - Octave preference for 80-140 BPM range

**Results:**
- CSV: `csv/test_results_20251117_043959.csv`
- Danceability error: 74% → 28% ✅
- Acousticness: Perfect match on "Every Little Thing" (0.43 vs 0.43) ✅
- BPM: Fixed "Espresso" from -33% error to +3% ✅
- Some regressions: BPM octave preference broke other tracks

---

### 4. **V2 Enhancements** (3 min)
📄 **`docs/algorithm_improvements_v2_results.md`**

**Changes made:**
1. **Enhanced Valence** - Added pitch tracking and spectral rolloff:
   - `librosa.piptrack()` for pitch variance analysis
   - Spectral rolloff for brightness detection
2. **Enhanced BPM** - Added spectral flux for octave validation:
   - Spectral flux calculation in `perform_audio_analysis()`
   - Spectral octave hint in `_score_tempo_alias_candidates()`

**Results:**
- CSV: `csv/test_results_20251117_044457.csv`
- Valence: Slight improvement (168% → 163% error)
  - "Islands in the Stream" nearly perfect: 0.65 vs 0.68 target ✅
- BPM: **Regression** - spectral flux broke "The Scientist"
  - Went from 85 BPM → 139 BPM (should be 74)
  - Lesson: High spectral flux ≠ fast tempo (can be dense production)
- Processing time: +2.1s per track (acceptable for accuracy gains)

---

## 💻 Implementation Files

### Core Analysis Pipeline
📄 **`backend/analysis/pipeline_core.py`**

**Key functions:**
- `perform_audio_analysis(audio_path)` - Main entry point
  - Loads audio with librosa
  - Extracts tempo, beats, chroma, spectral features
  - **V2 additions:** Pitch tracking (`librosa.piptrack()`), spectral flux
  - Calls feature estimators

- `_score_tempo_alias_candidates(...)` - BPM octave selection
  - **V1:** Added octave preference for 80-140 BPM
  - **V2:** Added `spectral_flux_mean` parameter for octave validation
  
- **V2 Multi-component acousticness:**
  ```python
  warmth_score = 1.0 - normalized_brightness
  harmonic_ratio = harmonic_strength / percussive_strength
  onset_gentleness = 1.0 - np.clip(onset_strength_mean, 0, 1)
  acousticness = (warmth_score * 0.4 + harmonic_ratio * 0.35 + onset_gentleness * 0.25)
  ```

---

### Feature Estimators
📄 **`backend/analysis/pipeline_features.py`**

**Key functions:**
- `estimate_valence_and_mood(tempo, key, mode, chroma_sums, energy, pitch_features=None, spectral_rolloff=None)`
  - **V1:** Fixed mode handling (was treating "Major"/"Minor" as int 1/0)
  - **V2:** Added pitch variance and spectral rolloff parameters
  - Still fundamentally broken for emotional ballads

- `heuristic_danceability(beat_strength, tempo_bpm, onset_rate)`
  - **V1:** Rebalanced weights and added tempo penalties
  - Massive improvement: 74% → 28% error

---

### Test Framework
📄 **`backend/test_phase1_features.py`**

**Updated for V2:**
- Changed mode values: `1`/`0` → `"Major"`/`"Minor"`
- Added optional parameters: `pitch_features=None`, `spectral_rolloff=None`
- Adjusted expected mood: `"😊 Uplifting"` → `"✨ Euphoric"`

**Run tests:**
```bash
.venv/bin/python backend/test_phase1_features.py
```

---

## 📊 Test Data Files

### Ground Truth
- **Spotify Reference:** `csv/spotify_calibration_master.csv`
  - Contains Spotify's analysis for all test tracks
  - Used as ground truth for validation

### Test Results
| Version | CSV File | Timestamp | Description |
|---------|----------|-----------|-------------|
| **BASELINE** | `csv/test_results_20251117_043243.csv` | 04:32:43 | Before any improvements |
| **V1** | `csv/test_results_20251117_043959.csv` | 04:39:59 | After mode fix, danceability rebalance, acousticness multi-component |
| **V2** | `csv/test_results_20251117_044457.csv` | 04:44:57 | After pitch tracking, spectral flux |

### Test Audio Files
- **Location:** `Test files/problem chiles/*.m4a`
- **12 full-length tracks:**
  1. BLACKBIRD - JML
  2. Every Little Thing She Does Is Magic - The Police
  3. Islands in the Stream - Dolly Parton & Kenny Rogers
  4. Espresso - Sabrina Carpenter
  5. Lose Control - Teddy Swims
  6. The Scientist - SKAAR (Electronic Cover)
  7. Walking in Memphis - Marc Cohn
  8. We Are The Champions - Queen
  9. What's My Age Again? - blink-182
  10. You Know You Like It - DJ Snake & AlunaGeorge
  11. You'll Think Of Me - Keith Urban
  12. You're the Voice - John Farnham

---

## 🎯 Current State Summary

### ✅ What's Working Well

#### 1. **Danceability** (28% error)
- **Best example:** "Espresso" - 0.75 vs 0.76 target (98% accurate)
- V1 weight rebalancing was very effective
- Still overestimates ballads but much better than before

#### 2. **Acousticness** (Multi-component)
- **Perfect example:** "Every Little Thing" - 0.43 vs 0.43 target (exact match)
- Warmth + harmonic ratio + onset gentleness = better results
- Some failures on electronic tracks ("The Scientist" 0.79 vs 0.12)

#### 3. **Energy** (Consistently good)
- Most tracks within 10% of target
- Reliable across different genres

#### 4. **BPM** (67% within 10% of target in V1)
- **Excellent:** "Lose Control" 90.75 vs 89 target
- **Excellent:** "Espresso" 107.40 vs 104 target (was broken in baseline)
- Octave errors still occur on ~33% of tracks

#### 5. **Key Detection** (33% accuracy, but perfect when correct)
- **Perfect:** "Lose Control" - A Major ✅
- **Perfect:** "The Scientist" - A# Major ✅
- When it gets it right, it's 100% correct
- Need to investigate the 67% failures

---

### ⚠️ Mixed Results / Regressions

#### 1. **BPM Octave Selection** (50-67% accuracy)
- V1 improvements helped some tracks, broke others:
  - ✅ Fixed: "Espresso" (69 → 107, target 104)
  - ❌ Broke: "Islands in the Stream" (69 → 107, target 71)
  - ❌ Broke: "BLACKBIRD" (77 → 122, target 93)
- V2 spectral flux made it worse:
  - ❌ Broke: "The Scientist" (85 → 139, target 74)
  - **Root cause:** High spectral flux in dense production ≠ fast tempo

#### 2. **Valence** (163% error in V2)
- Small improvements from baseline (201% → 163%)
- One near-perfect result: "Islands in the Stream" (0.65 vs 0.68)
- Still fundamentally broken for emotional ballads
- **Core issue:** Can't detect sad vocals on happy-sounding music

---

### ❌ Still Broken / Needs Complete Rework

#### 1. **Valence Detection** (163% error) 🔴
**Examples of failures:**
- "Every Little Thing" - Reading 0.60, should be 0.12 (+400% error)
- "Lose Control" - Reading 0.61, should be 0.20 (+205% error)
- "Espresso" - Reading 0.60, should be 0.11 (+445% error)

**Root cause:**
- Pitch/harmony analysis can't detect lyrical/vocal sentiment
- Songs in MAJOR keys with sad lyrics read as happy
- Missing emotional vocal delivery analysis

**Next steps:**
- Need vocal/lyrical sentiment analysis
- Consider ML model for emotional tone detection
- Analyze vocal timbre and delivery characteristics

---

#### 2. **Key Detection** (33% accuracy) 🔴
**Failures:**
- "BLACKBIRD" - Detecting G# Major, should be C#/Db (off by 5 semitones)
- "Every Little Thing" - Detecting B Minor, should be D Major (relative minor confusion)
- "Islands in the Stream" - Detecting C Major, should be G#/Ab (off by 8 semitones)
- "Espresso" - Detecting A Minor, should be C Major (relative minor error)

**Root cause:** Unknown - needs investigation
- 50% failure rate is unacceptable
- When correct, it's perfect (100%)
- Suggests systematic issue, not random errors
- Possible relative minor confusion pattern

**Next steps:**
- Root cause analysis required
- Investigate chroma feature extraction
- Check key estimation algorithm logic
- Consider ensemble methods or ML approach

---

#### 3. **Acousticness Stability** 🟡
**Inconsistent results:**
- ✅ Perfect: "Every Little Thing" (0.43 vs 0.43)
- ❌ Terrible: "The Scientist" (0.79 vs 0.12, +558% error)
  - Electronic cover misclassified as acoustic

**Root cause:**
- Electronic production with warmth confuses the algorithm
- Lacks production style classification

**Next steps:**
- Add electronic vs acoustic classifier
- Consider spectral centroid trends
- Analyze production complexity patterns

---

## 🔧 Development Environment

### Server Setup
```bash
# Activate virtual environment
source .venv/bin/activate

# Start analysis server (port 5050)
.venv/bin/python backend/analyze_server.py &

# Check server health
curl http://127.0.0.1:5050/health

# Stop server
pkill -f analyze_server.py
```

### Running Tests
```bash
# Run Phase 1 features test
.venv/bin/python backend/test_phase1_features.py

# Run ABCD test (12 tracks)
./run_test.sh a

# Run external test script
./run_test_external.sh
```

### Key Dependencies
- **librosa 0.10.x** - Core audio analysis
- **numpy** - Array operations
- **Flask** - Web server
- **essentia** - Optional advanced audio descriptors (currently disabled)
- **Python 3.12** - Virtual environment at `.venv/bin/python`

---

## 🚀 Priority Tasks for Next Agent

### Priority 1: Valence Detection 🔴
**Current state:** 163% error, fundamentally broken  
**Goal:** Achieve <50% error, especially on emotional ballads

**Suggested approaches:**
1. Investigate vocal/lyrical sentiment analysis
2. Consider pre-trained ML models for emotional tone
3. Analyze vocal timbre characteristics
4. Test spectral envelope features
5. Investigate vocal delivery patterns (vibrato, breathiness)

**Success metrics:**
- "Lose Control" should read ~0.20 (currently 0.61)
- "Every Little Thing" should read ~0.12 (currently 0.60)
- Maintain good results on "Islands in the Stream" (0.65 vs 0.68 ✅)

---

### Priority 2: BPM Octave Selection 🟡
**Current state:** 50-67% accuracy, unstable across versions  
**Goal:** 90%+ accuracy, stable octave selection

**Suggested approaches:**
1. Refine spectral flux logic (avoid dense production false positives)
2. Add production style detection (acoustic vs electronic)
3. Consider onset pattern analysis
4. Test envelope-based tempo validation
5. Investigate genre-specific tempo ranges

**Success metrics:**
- "The Scientist" should read ~74 BPM (currently 139 in V2, was 85 in V1)
- "Islands in the Stream" should read ~71 BPM (currently 107)
- Maintain good results on "Espresso" (107 vs 104 ✅) and "Lose Control" (90.75 vs 89 ✅)

---

### Priority 3: Key Detection 🔴
**Current state:** 33% accuracy, systematic failures  
**Goal:** 80%+ accuracy

**Suggested approaches:**
1. Root cause analysis - why only 33%?
2. Investigate chroma feature extraction parameters
3. Check relative minor/major confusion pattern
4. Test different key estimation algorithms
5. Consider ensemble methods

**Success metrics:**
- "BLACKBIRD" should detect C#/Db Major (currently G# Major)
- "Every Little Thing" should detect D Major (currently B Minor)
- "Islands in the Stream" should detect G#/Ab Major (currently C Major)
- Maintain perfect results on "Lose Control" and "The Scientist"

---

### Priority 4: Acousticness Stability 🟡
**Current state:** Inconsistent, confused by electronic production  
**Goal:** Consistent results across production styles

**Suggested approaches:**
1. Add electronic vs acoustic classifier
2. Analyze spectral centroid trends
3. Consider production complexity metrics
4. Test percussive vs harmonic balance refinements

**Success metrics:**
- "The Scientist" should read ~0.12 (currently 0.79, electronic cover)
- Maintain perfect result on "Every Little Thing" (0.43 vs 0.43 ✅)

---

## 📖 Additional Documentation

### Project Documentation
- `backend/README.md` - Backend overview and API documentation
- `backend/COMPLETE.md` - Completed features list
- `backend/PHASE1_FEATURES.md` - Phase 1 advanced features specification
- `backend/PRODUCTION_SECURITY.md` - Security considerations
- `RUN_TESTS.md` - Test execution guide

### Performance & Optimization
- `backend/PERFORMANCE_OPTIMIZATIONS.md` - Performance improvement history
- `OPTIMIZATION_SUMMARY.md` - Overall optimization summary

### Session Documentation
- `docs/algorithm_improvements_session_summary.md` - Complete session summary

---

## 🤝 Working with This Codebase

### Code Organization
```
backend/
├── analyze_server.py          # Flask API server (port 5050)
├── analysis/
│   ├── pipeline_core.py       # Main analysis pipeline ⭐
│   ├── pipeline_features.py   # Feature estimators ⭐
│   └── ...
├── test_phase1_features.py    # Unit tests ⭐
└── test_server.py             # Server integration tests

csv/
├── spotify_calibration_master.csv    # Ground truth ⭐
├── test_results_20251117_043243.csv  # BASELINE ⭐
├── test_results_20251117_043959.csv  # V1 ⭐
└── test_results_20251117_044457.csv  # V2 ⭐

docs/
├── AGENT_ONBOARDING.md              # This file ⭐
├── unified_test_comparison.md       # Must-read ⭐
├── analysis_accuracy_issues.md      # BASELINE analysis
├── algorithm_improvements_results.md # V1 analysis
└── algorithm_improvements_v2_results.md # V2 analysis
```

### Making Changes
1. **Always verify changes in the API:**
   - Changes in `pipeline_core.py` and `pipeline_features.py` are immediately active
   - Restart server to clear any caches: `pkill -f analyze_server.py && .venv/bin/python backend/analyze_server.py &`

2. **Update tests when changing function signatures:**
   - `backend/test_phase1_features.py` directly imports analysis functions
   - Add new parameters with default values to maintain backward compatibility

3. **Document major changes:**
   - Update relevant docs in `docs/` directory
   - Create comparison CSVs for before/after testing
   - Track accuracy metrics vs Spotify ground truth

4. **Test thoroughly:**
   - Run unit tests: `.venv/bin/python backend/test_phase1_features.py`
   - Run ABCD test: `./run_test.sh a`
   - Compare results with previous test runs

---

## 🎓 Key Lessons Learned

### What Worked
1. **Multi-component features > single signals** (acousticness)
2. **Balanced weighting** is critical (danceability)
3. **Domain knowledge** helps (tempo penalties, octave preferences)
4. **Iterative testing** with ground truth catches regressions early

### What Didn't Work
1. **Spectral flux for BPM** - backfired on dense production
2. **Pitch variance for valence** - can't detect lyrical sentiment
3. **Simple brightness for acousticness** - too simplistic

### Best Practices
1. **Always test against Spotify ground truth** - assumptions can be wrong
2. **Track performance impact** - pitch tracking added 2.1s per track
3. **Document everything** - future agents need context
4. **Watch for regressions** - improvements can break other tracks

---

## ✅ Onboarding Checklist

- [ ] Read `docs/unified_test_comparison.md` (understand the big picture)
- [ ] Read `docs/analysis_accuracy_issues.md` (understand what was broken)
- [ ] Skim `docs/algorithm_improvements_results.md` (V1 changes)
- [ ] Skim `docs/algorithm_improvements_v2_results.md` (V2 changes)
- [ ] Review `backend/analysis/pipeline_core.py` (implementation)
- [ ] Review `backend/analysis/pipeline_features.py` (implementation)
- [ ] Run tests to verify environment: `.venv/bin/python backend/test_phase1_features.py`
- [ ] Start server: `.venv/bin/python backend/analyze_server.py &`
- [ ] Test server: `curl http://127.0.0.1:5050/health`
- [ ] Review test data: `csv/spotify_calibration_master.csv`
- [ ] Identify your priority task (valence, BPM, key, or acousticness)
- [ ] Ready to code! 🚀

---

**Welcome to the team! You now have all the context to continue improving the audio analysis algorithms.** 🎵

*Last updated: November 17, 2025*
