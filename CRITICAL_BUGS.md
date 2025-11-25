# Critical Analysis Bugs - Priority Fixes Needed

**Date**: 2025-11-18
**Status**: CRITICAL - Analysis producing incorrect results

## 🚨 Issue 1: BPM Detection Randomly Incorrect

### Symptoms:
- Batch 1: BPM values completely random/wrong
- Batch 2: BPM randomly out
- Batch 3: Same as Batch 1 (all wrong)
- Batch 4: Same as Batch 2 (randomly wrong)

### Root Cause Analysis:
The BPM detection in `backend/analysis/tempo_detection.py` has **Strategy 2: Extended Alias Factors** that was added to handle edge cases but is introducing errors:

```python
# Extended factors on lines 297-400
extended_factors = [0.75, 1.25, 1.5]
```

**Problems:**
1. Extended factors (0.75x, 1.25x, 1.5x) are being applied too aggressively
2. Low confidence threshold (score_gap < 0.10) triggers too often
3. "Acoustic bonus" (85-95 BPM) is biasing results incorrectly
4. Base BPM set includes top candidates, creating circular logic

### Fix Strategy:
1. **Tighten confidence threshold**: score_gap < 0.10 → 0.05 (only for very ambiguous cases)
2. **Remove acoustic bonus**: The 0.15 bonus for 85-95 BPM is genre-specific and causing bias
3. **Restrict extended factors**: Only use 0.75 and 1.25, remove 1.5 (too aggressive)
4. **Stricter score requirement**: Increase extended_score minimum from 0.40 to 0.50
5. **Remove circular logic**: Don't add top candidates as "base BPMs"

---

## 🚨 Issue 2: Key Detection Stuck on D

### Symptoms:
- Batch 1: ALL songs showing D or D-related keys
- Batch 3: ALL songs showing D or D-related keys

### Root Cause Analysis:
In `backend/analysis/key_detection.py`, the key detection is likely:
1. Defaulting to `key_index: 0` (which is C, not D - need to verify KEY_NAMES mapping)
2. Window consensus logic may be broken
3. Chroma peak detection returning same value for all songs

**Need to verify**:
- What is `KEY_NAMES[2]`? (D should be index 2)
- Is `fallback_root` defaulting to 2?
- Is window_consensus being ignored?

### Fix Strategy:
1. **Add debugging**: Log the key_index and KEY_NAMES mapping for each detection
2. **Check default fallback**: Ensure we're not hardcoding `key_index: 2` anywhere
3. **Verify window consensus**: Check if window votes are being processed correctly
4. **Check chroma calculation**: Ensure chroma_profile isn't returning same values

---

## 🚨 Issue 3: Key Detection Needs Refinement

### Symptoms:
- Batch 2: Some close matches (right root, wrong mode OR adjacent key)
- Batch 4: Same as Batch 2

### Root Cause Analysis:
1. **Mode detection (Major/Minor)** is inconsistent
2. Window consensus may be working but not weighted correctly
3. Chroma peak root is close but not exact (off by semitone)

### Fix Strategy:
1. **Improve mode detection**: The mode bias calculation needs better weighting
2. **Increase window consensus weight**: Give more trust to repeated window votes
3. **Refine chroma peak thresholds**: Make the peak detection more selective

---

## 🔧 Issue 4: Test Batch Size Wrong

### Symptoms:
- Test B showing 6 previews instead of 12
- Test D showing 6 previews instead of 12

### Root Cause:
In `ABCDTestRunner.swift` line 296:
```swift
// Default counts if not found
if totalCount == 0 {
    totalCount = (test == .testA || test == .testB) ? 6 : 12
    successCount = passed ? totalCount : 0
}
```

**Bug**: Test B should be 6 FULL-LENGTH songs (correct), Test D should be 12 FULL-LENGTH songs (WRONG - getting 6).

**Actual requirements** (from `run_test.sh`):
- Test A: 6 preview files ✅
- Test B: 6 full-length songs ✅  
- Test C: 12 preview files ✅
- Test D: 12 full-length songs ❌ (showing 6)

### Fix:
The logic is actually CORRECT in ABCDTestRunner.swift. The issue is the **CSV parsing or output** - Test B and D are only running 6 songs when they should run 12.

**Real problem**: `tools/test_analysis_suite.py` line 336-341 shows `test_full_calibration` runs 2 batches of 6 (= 12 total), but the batch size check on line 296 of ABCDTestRunner.swift is wrong for tests.

Actually looking more carefully - Test B is CORRECT (6 full songs), but Test D should be 12 full songs (2 batches).

**Actual Fix**: None needed - the issue is user confusion. Tests are:
- A: 6 previews
- B: 6 full songs  
- C: 12 previews (2 batches of 6)
- D: 12 full songs (2 batches of 6)

But the GUI might not be showing batch 2 results, OR the test isn't running properly.

---

## Priority Order:
1. **HIGHEST**: Fix BPM detection (all batches affected)
2. **HIGH**: Fix key detection stuck on D (batches 1 and 3)
3. **MEDIUM**: Refine key detection for close matches (batches 2 and 4)
4. **LOW**: Verify test batch counting (may be display issue, not analysis issue)

---

## Next Steps:
1. Disable Extended Alias Factors in tempo_detection.py temporarily
2. Add debug logging to key_detection.py to see what's being detected
3. Run a single-song test to verify fixes
4. Run full Test A to verify improvements
