# Adaptive Parameter System Implementation

**Date**: 2025-11-18  
**Status**: ✅ IMPLEMENTED - Ready for Testing

---

## Overview

Implemented a comprehensive adaptive parameter system to handle different audio durations (30-second previews vs 3-4 minute full songs) using a **single analysis engine** with duration-aware parameter selection.

## Research-Based Decision

After researching industry standards (Essentia library, librosa, academic papers), the conclusion was clear:

✅ **ONE ENGINE with adaptive parameters** (industry standard)  
❌ NOT separate engines for different durations

**Why**: Essentia, librosa, and music analysis research papers all use adaptive windowing and parameter scaling for different durations. They don't create separate analysis systems.

---

## Implementation Details

### 1. Core Function: `get_adaptive_analysis_params(signal_duration)`

**Location**: `backend/analysis/settings.py`

**Purpose**: Central function that returns optimal analysis parameters based on audio duration

**Threshold**: 45 seconds
- < 45s = Short clip (preview)
- ≥ 45s = Full song

#### Parameters for SHORT CLIPS (< 45s):
```python
{
    'is_short_clip': True,
    'tempo_window': min(signal_duration * 0.8, 30.0),  # 80% of duration, max 30s
    'key_window': min(signal_duration / 5.0, 6.0),     # ~5 windows minimum
    'key_window_hop': min(signal_duration / 10.0, 3.0),
    'confidence_threshold': 0.60,          # Lower = more lenient
    'use_onset_validation': False,         # Skip complex validations
    'use_window_consensus': False,         # Trust direct chroma detection
    'use_extended_alias': False,           # Already disabled
    'intermediate_correction_threshold': 1.50,
}
```

#### Parameters for FULL SONGS (≥ 45s):
```python
{
    'is_short_clip': False,
    'tempo_window': 60.0,
    'key_window': 6.0,
    'key_window_hop': 3.0,
    'confidence_threshold': 0.75,          # Higher = more strict
    'use_onset_validation': True,          # Use all validations
    'use_window_consensus': True,          # Use multi-window consensus
    'use_extended_alias': False,           # Disabled per handover
    'intermediate_correction_threshold': 1.50,
}
```

---

### 2. Files Modified

#### `backend/analysis/settings.py` (+67 lines)
- Added `SHORT_CLIP_THRESHOLD = 45.0`
- Added `get_adaptive_analysis_params(signal_duration)` function
- Updated `__all__` exports

#### `backend/analysis/pipeline_core.py` (+20 lines)
- Calculate signal duration at start
- Get adaptive parameters via `get_adaptive_analysis_params()`
- Log parameter choices for debugging
- Pass `tempo_window_override` to `prepare_analysis_context()`
- Pass `adaptive_params` to `analyze_tempo()` and `detect_global_key()`

#### `backend/analysis/analysis_context.py` (+8 lines)
- Added `tempo_window_override` parameter to `prepare_analysis_context()`
- Use override value instead of fixed `TEMPO_WINDOW_SECONDS` when provided
- Enables dynamic tempo window sizing based on clip duration

#### `backend/analysis/tempo_detection.py` (+25 lines)
- Added `adaptive_params` parameter to `analyze_tempo()`
- Extract `use_onset_validation` and `intermediate_threshold` from params
- Skip onset validation for short clips (not enough data for reliable validation)
- Use adaptive threshold for intermediate corrections
- Log when short-clip mode is active

#### `backend/analysis/key_detection.py` (+15 lines)
- Added `adaptive_params` parameter to `detect_global_key()`
- Extract `use_window_consensus` from params
- Pass flag to `_librosa_key_signature()`
- Log when short-clip mode is active

#### `backend/analysis/key_detection_helpers.py` (+10 lines)
- Added `use_window_consensus` parameter to `_librosa_key_signature()`
- Skip window consensus for short clips (only ~5 windows = unreliable)
- Trust direct chroma-based detection for previews
- Log when skipping window consensus

---

## How It Works

### Before (Single fixed parameters):
```
30s preview → 60s tempo window → uses full clip
             → 6s key windows → only 5 windows → unreliable consensus
             → onset validation → not enough data → wrong corrections
```

### After (Adaptive parameters):
```
30s preview → 24s tempo window (80% of 30s)
            → 6s key windows (30/5 = 6s) → direct chroma (no consensus)
            → NO onset validation → trust simpler detection
            → Result: faster, more accurate for limited data

4min song   → 60s tempo window
            → 6s key windows → 40 windows → reliable consensus
            → WITH onset validation → multi-pass corrections
            → Result: sophisticated analysis with validation
```

---

## Expected Results

### For Short Clips (Test A & C):
✅ BPM should be significantly more accurate
- No extended alias confusion
- No onset validation false corrections
- Simpler detection = fewer errors

✅ Key detection should show variety (not all "D")
- No window consensus forcing wrong keys
- Direct chroma detection is more reliable with limited data

### For Full Songs (Test B & D):
✅ Should maintain or improve accuracy
- Extended alias was causing errors on full songs too
- Sophisticated validation still applies
- No regression expected

---

## Testing Plan

### Phase 1: Validate Short Clips
```bash
./run_test.sh a  # 6 previews
```

**Watch for in logs**:
- `🎬 Short clip detected (30.0s) - using adaptive analysis:`
- `🎬 Tempo analysis for short clip: onset_validation=disabled`
- `🎬 Key detection for short clip: window_consensus=disabled`

**Expected**: BPM and key accuracy should improve dramatically

### Phase 2: Validate Full Songs
```bash
./run_test.sh b  # 6 full songs
```

**Expected**: No regression, should maintain or improve accuracy

### Phase 3: Full Test Suite
```bash
./run_test.sh c  # 12 previews
./run_test.sh d  # 12 full songs
```

---

## Debug Logging

The system now logs adaptive parameter choices:

```
🎬 Short clip detected (30.0s) - using adaptive analysis:
   - Tempo window: 24.0s
   - Key window: 6.0s
   - Confidence threshold: 0.60
   - Window consensus: disabled

🎬 Tempo analysis for short clip: onset_validation=disabled, intermediate_threshold=1.50

🎬 Key detection for short clip: window_consensus=disabled

🎬 Skipping window consensus for short clip - using direct chroma detection

⏭️ Skipping onset validation for short clip (adaptive setting)
```

---

## Technical Rationale

### Why 45-second threshold?
- 30-second previews are standard (Spotify, Apple Music)
- Need buffer for trimmed audio
- 45s gives clear separation between "preview" and "partial song"

### Why disable window consensus for short clips?
- 30s clip with 6s windows = only 5 windows
- 5 data points is not enough for reliable consensus
- Window consensus designed for 40+ windows (4-minute songs)
- Direct chroma detection is more accurate with limited data

### Why disable onset validation for short clips?
- Onset validation compares beat spacing across the entire track
- 30s doesn't have enough beats for reliable pattern detection
- Validation requires statistical significance (many samples)
- Short clips: trust the initial detection

### Why scale tempo window?
- 60s window for 30s clip = uses entire clip anyway
- Scaling to 80% of duration is more honest about what we're analyzing
- Prevents confusion in logging and downstream logic

---

## Success Metrics

**Target**: 70%+ match rate with Spotify reference data

**Current**: ~0% on previews (complete failure)

**Expected after implementation**:
- Previews: 60-80% accuracy (BPM ±3, Key exact/adjacent)
- Full songs: 70-85% accuracy (BPM ±5, Key exact/adjacent)

---

## Files Modified Summary

```
modified:   backend/analysis/settings.py
modified:   backend/analysis/pipeline_core.py
modified:   backend/analysis/analysis_context.py
modified:   backend/analysis/tempo_detection.py
modified:   backend/analysis/key_detection.py
modified:   backend/analysis/key_detection_helpers.py
created:    ADAPTIVE_PARAMS_IMPLEMENTATION.md (this file)
```

**Total changes**: ~145 lines added/modified across 6 files

---

## Next Steps

1. ✅ **Implementation**: COMPLETE
2. ⏳ **Testing**: Run Test A (6 previews)
3. ⏳ **Validation**: Run Test B (6 full songs)
4. ⏳ **Full Suite**: Run Tests C & D
5. ⏳ **Analysis**: Compare with Spotify reference data

---

## References

- Essentia library: Uses adaptive parameters for tempo/key detection
- librosa: Provides flexible windowing and parameter configuration
- Academic research: "Tempo estimation for audio recordings" (Alonso et al.)
- Industry practice: Spotify, Apple Music use duration-aware analysis

---

**Status**: ✅ Ready for testing
**Next**: Run `./run_test.sh a` and analyze results
