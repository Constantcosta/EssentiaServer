# Task Sheet for GPT-5 Codex: BPM Detection Accuracy Improvement

**Date:** November 17, 2025  
**Priority:** HIGH  
**Estimated Time:** 30-45 minutes  
**Branch:** `copilot/improve-slow-code-efficiency`

---

## 🎯 Objective

Improve BPM detection accuracy for specific problem songs without destabilizing currently working tracks.

**Target Files:**
- `/Users/costasconstantinou/Documents/GitHub/EssentiaServer/backend/analysis/pipeline_core.py`

---

## 📊 Current Performance (Baseline)

### ✅ Already Good (Don't Break These!)
| Song | Current BPM | Target | Error | Status |
|------|-------------|--------|-------|--------|
| Islands in the Stream | 107.4 | 102 | +5% | ✅ EXCELLENT |
| Espresso | 107.4 | 104 | +3% | ✅ EXCELLENT |
| Walking in Memphis | 126 | 130 | -3% | ✅ VERY GOOD |
| You're the Voice | 79 | 85 | -7% | ✅ GOOD |

### ❌ Need Improvement
| Song | Current BPM | Target | Error | Issue Type |
|------|-------------|--------|-------|------------|
| **The Scientist** | 111.3 | 74 | **+50%** | 1.5× too high (needs 0.66× correction) |
| **BLACKBIRD** | 76.6 | 93 | **-17%** | Too low (needs 1.2× boost) |
| **Lose Control** | 90.7 | 80 | **+13%** | Slightly high (Spotify reports 160, halved = 80) |
| **Every Little Thing** | 90.7 | 82 | **+11%** | Slightly high |

---

## ⚠️ Critical Constraints

### DO NOT:
1. ❌ Expand `_ALIAS_FACTORS` beyond `(0.5, 1.0, 2.0)` - this caused instability
2. ❌ Modify `_validate_octave_with_onset_energy()` to test more ratios - this broke Espresso/Islands
3. ❌ Add genre detection (too complex for this task)
4. ❌ Change the core beat tracking algorithm (librosa.beat.beat_track)

### DO:
1. ✅ Improve the **scoring** of existing alias candidates in `_score_tempo_alias_candidates()`
2. ✅ Add smarter heuristics for detecting 1.5× errors (like The Scientist)
3. ✅ Use existing signals: `tempo_alignment_score`, onset energy, beat consistency
4. ✅ Test changes with `./run_test.sh b` to verify no regressions

---

## 🔍 Root Cause Analysis

### The Scientist (111 → should be 74)
**Problem:** Initial beat tracker detects 111 BPM, but actual tempo is 74 BPM (111 ÷ 1.5 = 74)

**Current Code Path:**
1. `librosa.beat.beat_track()` returns 111 BPM ✓
2. `_build_tempo_alias_candidates()` generates candidates: 55.5 (0.5×), 111 (1.0×), 222 (2.0×)
3. `_score_tempo_alias_candidates()` scores them - 111 wins
4. `_validate_octave_with_onset_energy()` tests 55.5 and 222, but not ~74
5. **Result:** 111 BPM (wrong)

**What We Need:**
- After scoring aliases, if the winner is in the 100-120 range with LOW energy/danceability, test a 0.66× correction
- The Scientist has energy=0.38 (very low) which is a strong signal it's a slow ballad

### BLACKBIRD (77 → should be 93)
**Problem:** Onset validation is halving the tempo too aggressively

**Current Code Path:**
1. Initial BPM ~153 (doubled)
2. Onset validation halves it to 76.6
3. **Should be:** 93 (so initial was probably 186, needed 0.5× to get 93)

**What We Need:**
- Better scoring in initial alias selection to pick 93 instead of 153
- Or, improve onset validation to recognize when half-tempo is still too low

---

## 💡 Suggested Implementation Approach

### Strategy 1: Post-Processing Check for 1.5× Errors
Add a final check AFTER onset validation:

```python
# Add this after onset validation in perform_audio_analysis()
# Around line 420-430 in pipeline_core.py

# Post-processing: Check for 1.5× errors on slow songs
if final_bpm > 100 and energy < 0.5:  # Slow song with high BPM = suspicious
    test_bpm_66 = final_bpm * 0.66  # Test 2/3 tempo
    if 60 <= test_bpm_66 <= 90:  # Typical ballad range
        # Compare alignment scores
        original_score = tempo_alignment_score(final_bpm)
        test_score = tempo_alignment_score(test_bpm_66)
        if test_score > original_score + 0.10:  # 10% improvement
            logger.info(f"🎵 Slow song correction: {final_bpm:.2f} → {test_bpm_66:.2f}")
            final_bpm = test_bpm_66
```

### Strategy 2: Improve Initial Alias Scoring
Enhance `_score_tempo_alias_candidates()` to prefer musically reasonable tempos:

```python
# Add tempo range preferences in scoring
def _score_tempo_alias_candidates(...):
    # ... existing code ...
    
    # Add bonus for tempos in common musical ranges
    if 60 <= candidate_bpm <= 90:  # Ballad range
        base_score += 0.05
    elif 90 <= candidate_bpm <= 140:  # Pop/rock sweet spot
        base_score += 0.10
    elif 140 <= candidate_bpm <= 180:  # Uptempo
        base_score += 0.05
    
    # Penalize extreme tempos
    if candidate_bpm < 50 or candidate_bpm > 200:
        base_score *= 0.7
```

### Strategy 3: Combine Both
Use both strategies for maximum impact while staying conservative.

---

## 🧪 Testing Protocol

### Step 1: Make Changes
Edit `backend/analysis/pipeline_core.py`

### Step 2: Test Impact
```bash
cd /Users/costasconstantinou/Documents/GitHub/EssentiaServer
./run_test.sh b 2>&1 | grep -E "BLACKBIRD|The Scientist|Islands|Espresso"
```

### Step 3: Verify Results
Expected improvements:
- The Scientist: 111 → 70-80 BPM (±10% of 74)
- BLACKBIRD: 77 → 85-100 BPM (closer to 93)
- Islands/Espresso: Should stay ~107 BPM (no regression)

### Step 4: Full Test
```bash
./run_test.sh d  # Test all 12 songs
```

---

## 📋 Acceptance Criteria

### Must Have:
- [ ] The Scientist BPM ≤ 85 (currently 111, target 74)
- [ ] BLACKBIRD BPM ≥ 85 (currently 77, target 93)
- [ ] Islands in the Stream still 105-110 (don't break it!)
- [ ] Espresso still 105-110 (don't break it!)
- [ ] No crashes or errors in test runs

### Nice to Have:
- [ ] Overall BPM accuracy ≥ 75% (9/12 songs within ±10%)
- [ ] Code includes helpful comments explaining the logic
- [ ] Logger messages for debugging when corrections are applied

---

## 📁 Key Code Locations

### Main Function to Edit:
**File:** `backend/analysis/pipeline_core.py`  
**Function:** `perform_audio_analysis()` around line 260-450

**Key sections:**
1. Line ~384: `_score_tempo_alias_candidates()` call
2. Line ~409: `_validate_octave_with_onset_energy()` call  
3. Line ~425: BPM guardrails section
4. **INSERT NEW CODE:** After line ~425, before "2. KEY DETECTION" comment

### Helper Functions Available:
- `tempo_alignment_score(bpm)` - Returns 0-1 score of how well BPM aligns with beat grid
- `_compute_onset_energy_separation(bpm, onset_env, sr, hop_length)` - Returns separation ratio
- `logger.info()` - For debug logging

---

## 🎓 Additional Context

### Why 1.5× Errors Happen:
- Librosa's beat tracker can lock onto strong harmonics or subdivisions
- Slow songs (60-80 BPM) often have strong half-note or triplet patterns at 90-120 BPM
- The Scientist at 74 BPM has prominent eighth-note patterns that create a 111 BPM signal

### Why Simple Octave Doubling Works Well:
- Most tempo errors are 2×, not 1.5× or 1.33×
- That's why expanding alias factors caused chaos - too many possibilities
- Better to have targeted corrections for specific patterns

---

## 🚀 Deliverables

1. **Modified Code:** Updated `pipeline_core.py` with improvements
2. **Test Results:** Output from `./run_test.sh b` showing BPM values
3. **Brief Summary:** 2-3 sentences explaining what you changed and why

---

## ⏱️ Time Budget
- **Analysis:** 5-10 min (review current code)
- **Implementation:** 15-20 min (add post-processing logic)
- **Testing:** 10-15 min (run tests, verify results)
- **Total:** 30-45 minutes

---

## 💬 Questions?

If anything is unclear or you need more context:
- Current working code is in `backend/analysis/pipeline_core.py`
- Test with: `./run_test.sh b` (6 songs, ~20 seconds)
- Full test with: `./run_test.sh d` (12 songs, ~40 seconds)
- All test audio files are in `Test files/problem chiles/`

**Good luck! Focus on The Scientist first (biggest error), then BLACKBIRD if time permits.**
