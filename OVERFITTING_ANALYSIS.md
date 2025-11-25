# Overfitting Analysis - BPM Detection

**Date:** 2025-11-18  
**Branch:** `copilot/improve-slow-code-efficiency`

## Problem Identified

The codebase had **song-specific calibrations** that appeared to achieve 91.7% accuracy (22/24) on Test C, but were actually overfitted to the 12 test songs.

### Hardcoded Bypasses Found:

1. **140-150 BPM calibration bypass** (`calibration.py` lines 141, 501)
   - Skipped linear calibration for this exact range
   - Fixed "Girls 2 Become 1" and "Veronicas 4ever" (both 144 BPM)
   - Would fail on millions of other songs

2. **105-110 BPM skip** (`tempo_detection.py` line 443)
   - Skipped mid-tempo octave correction for this narrow range  
   - Preserved "3am" at 108 BPM
   - Comment said "these are usually correct as-is" (not research-based)

3. **1.40x improvement threshold** (`tempo_detection.py` line 460)
   - Comment explicitly stated: "to avoid false positives like '3am'"
   - Literally tuned for one song

4. **Onset validation disabled for short clips** (`settings.py`)
   - Prevented octave corrections entirely for 30-second previews
   - Masked fundamental detector issues

## Generalization Attempt

Replaced song-specific logic with research-compliant algorithms:

### Changes Made:

1. **Removed all hardcoded BPM range bypasses**
2. **Added octave preference priors** (per research doc §3.4.2):
   - 80-140 BPM: +40% scoring boost
   - 40-80 or 140-180 BPM: +10% boost
   - Outside: -10% penalty

3. **Capped linear calibration** to ±10 BPM max change
   - Prevents calibration from causing octave errors
   - Allows fine-tuning adjustments

4. **Disabled onset validation for short clips**
   - Onset-energy separation unreliable for 30-second clips
   - Trust alias scoring with octave preferences instead

### Results:

**Before (overfitted):**
- Overall: 91.7% (22/24)
- BPM: 100% (12/12)  
- Key: 83.3% (10/12)

**After (generalized):**
- Overall: 75.0% (18/24)
- BPM: 66.7% (8/12)
- Key: 83.3% (10/12)

**Key insight:** The original "100% BPM accuracy" was achieved through song-specific tuning, not robust detection.

## Current Failures (Generalized Code)

### BPM Errors (4):

1. **"Girls 2 Become 1"**: 137.0 (expected 144)
   - Linear scaler reducing correct raw detection
   - Original bypass prevented this

2. **"20_3am"**: 215.3 (expected 108)  
   - Octave error - raw detector gives 2× correct tempo
   - Octave preferences not strong enough
   - Original skip preserved 108 BPM

3. **"Veronicas 4ever"**: 137.0 (expected 144)
   - Same issue as #1

4. **"Carlton A Thousand Miles"**: 159.5 (expected 149)
   - Close - likely calibration fine-tuning issue

### Key Errors (2) - Unchanged:

Same fifth-related errors as before - unrelated to overfitting.

## Root Cause Analysis

The fundamental BPM detector has weaknesses:

1. **Linear calibration scaler** (slope=0.7365, intercept=31.276)
   - Sometimes helps, sometimes hurts
   - Research doc (§4.2) warns: "ensure calibration doesn't degrade a good detector"
   - Currently degrading detection for 140-145 BPM range

2. **Octave selection** 
   - Raw detector sometimes picks wrong octave (108 detected as 215)
   - Onset-energy validation unreliable for 30-second clips
   - Alias scoring octave preferences (+0.15 for 80-145 BPM) too weak

3. **No ground truth validation**
   - Calibration trained on Spotify BPM values
   - But those may be wrong for preview clips vs full songs

## Recommendations

### Option 1: Accept True Baseline (75%)
- Current generalized code is research-compliant
- Will work for millions of songs, not just 12 test songs
- 75% is honest accuracy without overfitting

### Option 2: Improve Fundamental Detector
- Fix linear calibration (retrain on larger dataset)
- Implement better octave selection for short clips
- Use multiple detectors in ensemble
- **Scope:** Significant research project

### Option 3: Intelligent Corrections (Not Song-Specific)
- Keep octave preference priors but strengthen them (±50% boost?)
- Add confidence-based calibration (only calibrate low-confidence detections)
- Use statistical outlier detection instead of hardcoded ranges
- **Scope:** Medium effort, research-aligned

## Conclusion

The original 91.7% accuracy was **artificially inflated** through overfitting. The true baseline for generalized, research-compliant code is **75% accuracy** on 30-second preview clips.

The choice is between:
- **Honest 75%** that works generally
- **Dishonest 92%** that only works on test set
- **Improved detector** requiring significant research

**Recommendation:** Accept 75% baseline or invest in proper detector improvements (Option 2 or 3), not song-specific hacks.
