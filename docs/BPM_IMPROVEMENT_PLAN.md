# BPM Detection Improvement Plan

**Date:** November 17, 2025  
**Current Status:** Analysis complete - identified specific issues

---

## 📊 Current Performance Analysis

### Songs with Good BPM Detection (±10%)
1. **Walking in Memphis**: 126 vs 130 (-3%) ✅
2. **You're the Voice**: 79 vs 85 (-7%) ✅  
3. **Espresso**: 107 vs 104 (+3%) ✅
4. **Islands in the Stream**: 107 vs 102* (+5%) ✅ *Spotify reports 204 (doubled)

### Songs Needing Improvement

| Song | Our BPM | Target BPM | Error | Issue Type |
|------|---------|------------|-------|------------|
| **The Scientist** | 111 | 74 | +50% | Too high (1.5x) |
| **BLACKBIRD** | 77 | 93 | -17% | Too low |
| **Lose Control** | 91 | 80* | +14% | Slightly high |
| **Every Little Thing** | 91 | 82 | +11% | Slightly high |

*Note: Spotify reports 160 (doubled)

---

## 🎯 Root Causes

### 1. Spotify BPM Doubling Issue
- **Problem:** Spotify often reports slow songs at 2× their actual tempo
- **Examples:** 
  - Islands: Spotify 204, actual ~102
  - Lose Control: Spotify 160, actual ~80
- **Impact:** Our comparison logic needs to handle this

### 2. Octave Selection Errors
- **The Scientist (111 vs 74):** Algorithm is picking 1.5× the correct tempo
  - 111 ÷ 1.5 = 74 ✅
  - Need to test 0.66× and 0.75× ratios, not just 0.5× and 2×
  
- **BLACKBIRD (77 vs 93):** Algorithm went too low
  - 77 × 1.21 = 93.17 ✅
  - Beat-alignment validation may have over-corrected

### 3. Limited Tempo Ratio Testing
**Current:** Only tests 0.5×, 1×, 2×  
**Needed:** Test 0.66×, 0.75×, 1.33×, 1.5× for non-octave errors

---

## 🔧 Improvement Strategy

### Phase A: Expand Tempo Ratio Testing ⚠️ HIGH PRIORITY
**File:** `backend/analysis/pipeline_core.py`

**Current code:**
```python
_ALIAS_FACTORS = (0.5, 1.0, 2.0)
```

**Proposed:**
```python
_ALIAS_FACTORS = (0.5, 0.66, 0.75, 1.0, 1.33, 1.5, 2.0)
```

**Why:**
- The Scientist needs 0.66× (111 → 74)
- Other songs may need 0.75× or 1.33× corrections
- More granular testing = better accuracy

**Risk:** May increase false positives - need good scoring

---

### Phase B: Improve Onset Energy Validation
**File:** `backend/analysis/pipeline_core.py`  
**Function:** `_validate_octave_with_onset_energy()`

**Current Issue:** May be too aggressive in halving tempo

**Proposed Enhancement:**
1. Compare energy separation ratios for ALL candidate tempos
2. Pick the one with the BEST separation (clearest beat alignment)
3. Add confidence threshold - don't change if current is already good

**Pseudocode:**
```python
def _validate_octave_with_onset_energy_v2(current_bpm, onset_env, sr, hop_length):
    candidates = [current_bpm * factor for factor in [0.5, 0.66, 0.75, 1.0, 1.33, 1.5, 2.0]]
    
    best_bpm = current_bpm
    best_separation = _compute_onset_energy_separation(current_bpm, onset_env, sr, hop_length)
    
    for test_bpm in candidates:
        separation = _compute_onset_energy_separation(test_bpm, onset_env, sr, hop_length)
        
        # Only switch if new tempo is SIGNIFICANTLY better
        if separation > best_separation * 1.15:  # 15% improvement threshold
            best_separation = separation
            best_bpm = test_bpm
    
    return best_bpm, best_separation
```

---

### Phase C: Genre/Style Heuristics (FUTURE)
**Observation:** Different genres have typical tempo ranges

| Genre/Style | Typical BPM Range |
|-------------|-------------------|
| Ballads | 60-80 |
| Pop/Rock | 90-130 |
| Dance/EDM | 120-140 |
| Uptempo | 140-180 |

**Implementation:**
1. Analyze spectral characteristics to guess genre
2. Prefer tempo candidates within expected range
3. Weight scoring based on genre probability

**Priority:** LOW (try Phases A & B first)

---

## 📝 Implementation Order

### Step 1: Quick Win - Expand Alias Factors (5 min)
- [ ] Update `_ALIAS_FACTORS` in `pipeline_core.py`
- [ ] Test on "The Scientist" - expect 74 BPM instead of 111

### Step 2: Improve Validation (30 min)
- [ ] Rewrite `_validate_octave_with_onset_energy()` 
- [ ] Add confidence threshold (15% improvement minimum)
- [ ] Test on BLACKBIRD - expect 93 BPM instead of 77

### Step 3: Test & Measure (15 min)
- [ ] Run Test B (6 full songs)
- [ ] Run Test D (12 full songs)
- [ ] Compare before/after accuracy
- [ ] Document improvements in phase_implementation_results.md

---

## 🎓 Expected Outcomes

### Target Accuracy After Phase A+B:
- **The Scientist:** 111 → 74 ✅ (should fix with 0.66× ratio)
- **BLACKBIRD:** 77 → 90-95 (better validation scoring)
- **Lose Control:** 91 → 80 (existing 0.5× should work better)

### Overall Goal:
- **Current:** 2/6 tracks within ±10% (33%)
- **Target:** 5/6 tracks within ±10% (83%)

---

## 🔍 Testing Commands

```bash
# Test individual song
./run_test.sh b

# Full calibration test
./run_test.sh d

# Compare results
diff csv/test_results_BEFORE.csv csv/test_results_AFTER.csv
```

---

## ✅ Success Criteria
- [ ] The Scientist: ≤ ±10% error (target 74 BPM)
- [ ] BLACKBIRD: ≤ ±10% error (target 93 BPM)  
- [ ] No regressions on currently good tracks
- [ ] Overall BPM accuracy ≥ 75% (9/12 tracks within ±10%)

---

**Next Action:** Implement Phase A (expand alias factors) and test immediately
