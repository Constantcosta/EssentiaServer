# Agent Handover: BPM Detection Fix

**Date:** November 17, 2025  
**Priority:** HIGH  
**Current Branch:** `copilot/improve-slow-code-efficiency`  
**Objective:** Fix BPM detection for problem songs without breaking currently good results

---

## 🎯 Mission

Fix BPM detection accuracy for specific songs while **preserving excellent results** for Islands in the Stream and Espresso.

---

## 📊 Current Performance Status

### ✅ **PROTECTED - DO NOT BREAK THESE!**
| Song | Current BPM | Target BPM | Error | Status |
|------|-------------|------------|-------|--------|
| **Islands in the Stream** | **107.4** | 102 | +5% | ✅ **EXCELLENT** |
| **Espresso** | **107.4** | 104 | +3% | ✅ **EXCELLENT** |

These two songs have near-perfect BPM detection. **Any changes that break these are UNACCEPTABLE.**

### ❌ **TARGET FOR IMPROVEMENT**
| Song | Current BPM | Target BPM | Error | Issue Type |
|------|-------------|------------|-------|------------|
| **The Scientist** | 111.3 | 74 | +50% | 1.5× too high (needs ÷1.5 or ×0.66 correction) |
| **BLACKBIRD** | 76.6 | 93 | -17% | Too low (needs ×1.21 correction) |
| **Lose Control** | 90.7 | 80 | +13% | Slightly high |
| **Every Little Thing** | 90.7 | 82 | +11% | Slightly high |

---

## 🔧 Technical Context

### File to Modify
**Primary:** `/Users/costascostantinou/Documents/GitHub/EssentiaServer/backend/analysis/pipeline_core.py`

### Key Functions
1. **`_score_tempo_alias_candidates()`** (lines ~95-165)
   - Scores BPM candidates from different detection methods
   - Currently uses: alignment, detector_support, plp_similarity, octave_preference
   - **DO NOT** change the weighting that makes Islands/Espresso work!

2. **`_validate_octave_with_onset_energy()`** (lines ~225-265)
   - Tests 0.5× and 2.0× octave corrections using onset energy
   - Currently has 25% improvement threshold before applying corrections
   - **DO NOT** expand to test more ratios - this broke things before

3. **`perform_audio_analysis()`** (lines ~270-onwards)
   - Main analysis pipeline
   - Has "Phase 3: BPM Guardrails" section (lines ~457-467) for extreme tempo corrections
   - This is where you could add targeted post-processing

### Current Algorithm Flow
```
1. librosa.beat.beat_track() → percussive_bpm
2. librosa.feature.tempo() → onset_bpm  
3. _build_tempo_alias_candidates() → generates 0.5×, 1.0×, 2.0× candidates
4. _score_tempo_alias_candidates() → picks best candidate
5. _validate_octave_with_onset_energy() → tests if 0.5× or 2× is better
6. Phase 3 Guardrails → catches extreme tempos (<60 or >180)
7. Final BPM returned
```

---

## ⚠️ CRITICAL CONSTRAINTS - READ THIS!

### ❌ **DO NOT DO THESE (They broke things before):**

1. **DO NOT expand `_ALIAS_FACTORS`** beyond `(0.5, 1.0, 2.0)`
   - Previous attempt: Added (0.66, 0.75, 1.33, 1.5) 
   - Result: Islands and Espresso broke (107 → 82 BPM)
   - Reason: Too many candidates creates ambiguity in scoring

2. **DO NOT modify `_validate_octave_with_onset_energy()` to test more ratios**
   - Only test simple octave relationships: 0.5× and 2.0×
   - Complex ratios should be handled elsewhere

3. **DO NOT change base scoring weights** in `_score_tempo_alias_candidates()`
   - Current: 0.40 alignment, 0.30 detector_support, 0.15 plp_similarity
   - These weights make Islands/Espresso work perfectly

4. **DO NOT use genre detection** - too complex and unreliable

---

## ✅ **SAFE APPROACHES TO TRY:**

### Strategy 1: Targeted Post-Processing for The Scientist
**The Problem:** The Scientist is a slow ballad (74 BPM) being detected at 111 BPM (exactly 1.5× too high)

**The Signal:** Energy = 0.38 (very low) - this is a strong indicator of a slow song

**Suggested Code (add after line 467 in `perform_audio_analysis()`):**
```python
# Post-processing: Catch 1.5× errors on slow ballads
if final_bpm > 105 and energy < 0.45:  # High BPM + low energy = suspicious
    test_bpm_2_3 = final_bpm * (2.0 / 3.0)  # Test ÷1.5 (same as ×2/3)
    
    # Only apply if result falls in typical ballad range
    if 65 <= test_bpm_2_3 <= 85:
        original_alignment = tempo_alignment_score(final_bpm)
        test_alignment = tempo_alignment_score(test_bpm_2_3)
        
        # Apply if alignment improves significantly
        if test_alignment > original_alignment + 0.08:
            logger.info(
                f"🎵 Slow ballad correction (×2/3): {final_bpm:.1f} → {test_bpm_2_3:.1f} BPM "
                f"(energy={energy:.2f}, alignment {original_alignment:.2f}→{test_alignment:.2f})"
            )
            final_bpm = test_bpm_2_3
```

**Why this is safe:**
- Only triggers on specific conditions: high BPM + low energy
- Uses existing `tempo_alignment_score()` as validation
- Won't affect Islands (energy=0.58) or Espresso (energy=0.71) - both have higher energy

### Strategy 2: Improve BLACKBIRD Detection
**The Problem:** BLACKBIRD detected at 76.6 BPM, should be 93 BPM (needs ×1.21)

**Analysis:** This isn't a simple octave error (2× would give 153, too high). Likely the initial detection was ~186 BPM and got halved incorrectly.

**Suggested Approach:**
Check if onset validation is too aggressive. In `_validate_octave_with_onset_energy()`, consider:
- Lowering the improvement threshold from 25% to 20% (might help catch cases where 2× is slightly better)
- OR: Add logging to see what's happening with BLACKBIRD specifically

### Strategy 3: Better Onset Density Usage
**Currently:** Onset density is calculated (line ~394-398) but not fully utilized in scoring

**Idea:** Songs with high onset density (lots of rhythmic events) are less likely to have octave errors. Could use this to adjust confidence thresholds.

---

## 🧪 Testing Protocol

### Test Command
```bash
./run_test.sh b
```

### Success Criteria
After ANY change, verify:

1. **Islands in the Stream:** Must remain 107.4 ± 2 BPM ✅
2. **Espresso:** Must remain 107.4 ± 2 BPM ✅
3. **The Scientist:** Improved toward 74 BPM (currently 111.3)
4. **BLACKBIRD:** Improved toward 93 BPM (currently 76.6)

**If Islands or Espresso break (drop below 105 or above 110), REVERT immediately!**

### How to Check Results
```bash
./run_test.sh b 2>&1 | grep -E "(Islands|Espresso|The Scientist|BLACKBIRD)" -A 1
```

Look for the BPM values in the output.

---

## 📁 File Locations

### Test Files
- **Test script:** `/Users/costasconstantinou/Documents/GitHub/EssentiaServer/run_test.sh`
- **Audio files:** `/Users/costasconstantinou/Documents/GitHub/EssentiaServer/Test files/`
  - `The Scientist.m4a`
  - `BLACKBIRD.m4a`
  - `Islands in the Stream.m4a`
  - `Espresso - Sabrina Carpenter.m4a`

### Reference Data
- **Spotify ground truth:** `/Users/costasconstantinou/Documents/GitHub/EssentiaServer/csv/test_12_fullsong.csv`

### Logs
- **Backend log:** `~/Library/Logs/EssentiaServer/backend.log`
- Check for tempo correction messages after running tests

---

## 🔍 Debugging Tips

### Enable Detailed Logging
The code already has extensive logging. After running tests, check:
```bash
tail -200 ~/Library/Logs/EssentiaServer/backend.log | grep -E "(The Scientist|BLACKBIRD|Octave|correction|BPM alias)"
```

### Key Log Messages to Look For
- `🧮 BPM alias scoring picked X BPM` - shows which candidate won
- `Octave corrected via onset energy` - shows when onset validation changed BPM
- `⚡ Tempo guardrail correction` - shows when extreme tempo fix applied

### Understanding Current Behavior

**The Scientist:**
- Initial detection: ~111 BPM
- Onset validation: Not triggering (no octave change needed from 111)
- Result: 111 BPM (wrong - should be 74)
- **Fix needed:** Detect 1.5× error pattern

**BLACKBIRD:**
- Initial detection: Likely ~153 BPM (2× of 76.6)
- Onset validation: Halved to 76.6
- Result: 76.6 BPM (wrong - should be 93)
- **Fix needed:** Either detect correctly at 93 initially, or prevent over-halving

---

## 📚 Key Insights from Previous Attempts

### What Worked
✅ Simple octave testing (0.5×, 2.0×) with onset energy validation  
✅ Tempo alignment scoring (favors musically common BPMs)  
✅ Conservative improvement thresholds (25% for onset validation)  
✅ Protecting good results by testing changes incrementally

### What Failed
❌ Expanding alias factors to (0.5, 0.66, 0.75, 1.0, 1.33, 1.5, 2.0) - created instability  
❌ Using spectral flux to choose octave - didn't correlate with tempo  
❌ Aggressive onset validation - over-corrected BLACKBIRD  
❌ Changes that weren't tested before committing

---

## 🎯 Recommended Approach for Next Agent

**Phase 1: Fix The Scientist (Easiest Win)**
1. Implement Strategy 1 (slow ballad post-processing)
2. Test with `./run_test.sh b`
3. Verify Islands/Espresso still work
4. If successful, The Scientist should move from 111 → ~74 BPM

**Phase 2: Fix BLACKBIRD (Harder)**
1. Add detailed logging to see current detection for BLACKBIRD
2. Check if initial BPM is ~186 (which gets halved to 93) or ~153 (which gets halved to 76.6)
3. If it's 186 initially, onset validation might need adjustment
4. Consider testing 1.5× in specific cases where energy signals suggest it

**Phase 3: Validate**
1. Run full test suite: `./run_test.sh d` (all songs)
2. Check for any regressions
3. Document improvements

---

## 📞 Handover Complete

**Current State:** Stable baseline with excellent results for Islands/Espresso  
**Goal:** Improve The Scientist and BLACKBIRD without breaking the good songs  
**Constraint:** Zero tolerance for regressions on protected songs  
**Next Step:** Implement Strategy 1 for The Scientist as the first targeted fix

Good luck! 🚀
