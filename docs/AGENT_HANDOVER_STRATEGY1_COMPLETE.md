# Agent Handover: Strategy 1 Slow Ballad Detection - COMPLETE ✅

**Date:** November 17, 2025  
**Branch:** copilot/improve-slow-code-efficiency  
**Status:** Strategy 1 implemented successfully, Strategy 2 pending

---

## 🎯 Mission Overview

Fix BPM detection errors for slow ballads and uptempo tracks in the EssentiaServer audio analysis pipeline. This is a continuation of work documented in `AGENT_HANDOVER_BPM_FIX.md`.

### Problem Songs (from original handover):
1. **The Scientist** (Coldplay): 111.33 BPM → Target ~74 BPM ❌ **[FIXED ✅]**
2. **BLACKBIRD** (The Beatles): 76.6 BPM → Target 93 BPM ❌ **[PENDING]**

### Protected Songs (must remain accurate):
- **Islands in the Stream**: 107.40 BPM ✅ **[VERIFIED SAFE]**
- **Espresso**: 107.40 BPM ✅ **[VERIFIED SAFE]**

---

## ✅ Strategy 1: Slow Ballad Detection - IMPLEMENTED

### Root Cause Analysis

The issue was a **chain reaction problem** in the BPM detection pipeline:

1. **Alias scoring** correctly identified 71.8 BPM (×0.5 factor from 143.6)
2. **Onset validation** incorrectly doubled it back to 143.6 BPM (28% separation improvement)
3. Result: 71.8 → 143.6 → 111.33 (after calibration)

The onset validation step was too aggressive for low-energy slow ballads, incorrectly "correcting" the alias scoring back to the doubled tempo.

### Solution Implemented

**File:** `/Users/costasconstantinou/Documents/GitHub/EssentiaServer/backend/analysis/pipeline_core.py`

**Location:** Lines ~409-434 (Phase 2 & 3 of BPM detection)

**Key Changes:**

1. **Early Energy Calculation (Phase 2):** Calculate `energy_rms_early` before onset validation to identify potential slow ballads
   - Uses 90th percentile of RMS in dB: `np.percentile(rms_db, 90)`
   - Normalized to 0-1 range: `np.clip((loud_rms + 60.0) / 60.0, 0.0, 1.0)`

2. **Conditional Onset Validation Skip (Phase 3):**
   ```python
   # Skip onset validation if:
   # - BPM in slow-ish range: 60 <= final_bpm <= 90
   # - Doubling would exceed 105 BPM: final_bpm * 2 > 105
   # - Low energy: energy_rms_early < 0.95
   might_be_slow_ballad = (60 <= final_bpm <= 90 and final_bpm * 2 > 105 and energy_rms_early < 0.95)
   if might_be_slow_ballad:
       logger.info(f"⏭️ Skipping onset validation for potential slow ballad...")
       skip_onset_validation = True
   ```

3. **Preserved Onset Validation:** For non-ballad tracks, onset validation still runs with 25% improvement threshold

### Results

#### The Scientist (Coldplay)
- **Before:** 111.33 BPM (wrong)
- **After (uncalibrated):** 71.78 BPM ✅ (near-perfect, target ~74)
- **After (server calibration):** 84.9 BPM 🟡 (improved but calibration over-corrects)

#### Protected Songs - VERIFIED SAFE ✅
- **Islands in the Stream:** 107.40 BPM (unchanged, perfect)
- **Espresso:** 107.40 BPM (unchanged, perfect)

#### Other Test Songs
- **BLACKBIRD:** 76.59 BPM (still wrong, needs Strategy 2)
- **Every Little Thing She Does Is Magic:** 90.75 BPM (good)
- **Lose Control:** 90.75 BPM (good)

### Test Commands

```bash
# Run full test suite (6 full-length songs)
cd /Users/costasconstantinou/Documents/GitHub/EssentiaServer
./run_test.sh b

# Direct test (uncalibrated, for debugging)
source .venv/bin/activate
python test_ballad_simple.py

# Test files location
Test files/problem chiles/The Scientist.mp3
Test files/problem chiles/BLACKBIRD.mp3
```

### Key Learnings

1. **Energy Threshold:** `energy_rms_early < 0.95` is very permissive but necessary
   - For The Scientist: `energy_rms_early = 0.81` but `final_energy = 0.38-0.50`
   - RMS component is only 60% of final energy formula
   - Calibration further affects final energy values

2. **BPM Range Check:** Must check `60 <= final_bpm <= 90` (not >105) because onset validation happens AFTER alias scoring picks the slow tempo

3. **tempo_alignment_score NOT suitable:** This function penalizes slow tempos (<105 BPM) in favor of "dance-friendly" 105-140 BPM range
   - Returns 0.85 for 111 BPM vs 0.49 for 74 BPM
   - Located in: `backend/analysis/features/danceability.py`

4. **Calibration Model Impact:** Server applies calibration (71.78 → 84.9) which may need tuning separately

---

## 🔄 Strategy 2: BLACKBIRD Fix - PENDING

### Problem Analysis

**BLACKBIRD** by The Beatles:
- **Current:** 76.6 BPM
- **Target:** 93 BPM
- **Likely Issue:** Missing ×1.25 or ×1.2 correction factor in alias candidates

### Proposed Approaches (from research)

1. **Expand Alias Factors:** Add 1.2×, 1.25×, 1.33×, 1.5× to `_ALIAS_FACTORS`
   - Current: `(0.5, 1.0, 2.0)`
   - Proposed: `(0.5, 0.67, 0.75, 1.0, 1.2, 1.25, 1.33, 1.5, 2.0)`

2. **Lower Onset Validation Threshold:** Reduce from 25% to 20% for 76→93 correction
   - Risk: May affect other songs

3. **Enhanced Logging:** Add debug output to understand why 93 BPM isn't being selected

### Recommended Next Steps

1. **Add logging** to see what BPM candidates are generated for BLACKBIRD
2. **Test expanding alias factors** to include 1.2× (76.6 × 1.2 ≈ 92)
3. **Verify protected songs** remain safe after changes
4. **Consider onset validation threshold** adjustment if needed

---

## 📁 File Structure

### Modified Files
- **`/backend/analysis/pipeline_core.py`** (lines ~409-434)
  - Added Phase 2: Early energy calculation
  - Modified Phase 3: Conditional onset validation skip
  - Removed old Phase 4: Duplicate ballad detection code

### Supporting Files
- **`/backend/analysis/features/danceability.py`**
  - Contains `tempo_alignment_score()` function
  - Optimized for dance tempos (105-140 BPM)
  
- **`/backend/server/scipy_compat.py`**
  - Compatibility shim for `scipy.signal.hann`
  - Required for librosa beat tracking

- **`/test_ballad_simple.py`** (created for debugging)
  - Direct analysis without server/calibration
  - Useful for seeing uncalibrated results

### Test Files
- **Location:** `/Test files/problem chiles/`
  - The Scientist.mp3 (6.7MB, 275.9s)
  - BLACKBIRD.mp3
  - Islands in the Stream.mp3
  - Espresso - Sabrina Carpenter.mp3
  - Every Little Thing She Does Is Magic.mp3
  - Lose Control - Teddy Swims.mp3

---

## 🔧 Technical Context

### BPM Detection Pipeline Flow

```
1. Onset envelope generation (librosa)
2. Beat tracking (Method 1: percussive) → 143.6 BPM
3. Tempo estimation (Method 2: onset) → 143.6 BPM
4. Alias candidate generation (0.5×, 1.0×, 2.0×)
   → Candidates: 71.8, 143.6, 287.2
5. Alias scoring (tempo_alignment + detector agreement)
   → Winner: 71.8 BPM (score 0.88)
6. [NEW] Early energy check for slow ballad detection
   → energy_rms_early = 0.81
7. [NEW] Skip onset validation if might_be_slow_ballad
   → SKIPPED for The Scientist (60 <= 71.8 <= 90, energy < 0.95)
8. [SKIPPED] Onset validation
9. BPM guardrails check (< 60 or > 180)
10. Final result: 71.8 BPM (uncalibrated)
11. Server calibration applied: → 84.9 BPM
```

### Key Functions

#### `_validate_octave_with_onset_energy(bpm, onset_env, sr, hop_length)`
- **Location:** `pipeline_core.py` line ~170
- **Purpose:** Test ×2 and ×0.5 factors using onset energy separation
- **Threshold:** 25% improvement required
- **Status:** NOW SKIPPED for slow ballads

#### `_compute_onset_energy_separation(test_bpm, onset_env, sr, hop_length)`
- **Location:** `pipeline_core.py` line ~105
- **Purpose:** Calculate on-beat vs off-beat energy ratio
- **Returns:** Separation score (higher = better tempo match)

#### `tempo_alignment_score(bpm)`
- **Location:** `backend/analysis/features/danceability.py` line 19
- **Purpose:** Score tempo for danceability (0-1 range)
- **Bias:** Favors 105-140 BPM range
- **Issue:** Penalizes slow ballads (< 80 BPM)

### Configuration Constants

```python
# pipeline_core.py
_ALIAS_FACTORS = (0.5, 1.0, 2.0)  # TODO: Expand for BLACKBIRD fix
_MIN_ALIAS_BPM = 20.0
_MAX_ALIAS_BPM = 280.0
ANALYSIS_FFT_SIZE = 2048  # from settings
ANALYSIS_HOP_LENGTH = 512  # from settings
TEMPO_WINDOW_SECONDS = 60  # from settings
```

---

## 🧪 Testing & Validation

### Test Suite
```bash
./run_test.sh b  # 6 full-length songs, ~20s runtime
```

### Expected Results (Post-Strategy 1)
```
BLACKBIRD:                     76.59 BPM  ❌ (needs Strategy 2)
Every Little Thing...:         90.75 BPM  ✅
Islands in the Stream:        107.40 BPM  ✅ (protected)
Espresso:                     107.40 BPM  ✅ (protected)
Lose Control:                  90.75 BPM  ✅
The Scientist:                 84.90 BPM  🟡 (71.78 uncalibrated) ✅
```

### Debugging Commands
```bash
# See uncalibrated results
source .venv/bin/activate
python test_ballad_simple.py 2>&1 | grep -E "(BPM alias|Skipping onset|Final BPM)"

# Check server logs (if needed)
tail -100 /tmp/server_output.log

# Test single song via server
curl -X POST "http://127.0.0.1:5050/analyze" \
  -H "Content-Type: application/json" \
  -d '{
    "url": "file:///Users/.../The Scientist.mp3",
    "title": "The Scientist",
    "artist": "Coldplay"
  }' | python3 -m json.tool
```

---

## 📊 Research Findings (from online research)

### Best Practices Applied
1. ✅ **Onset envelope for beat tracking** (librosa standard)
2. ✅ **Harmonic-percussive separation** (improves beat detection)
3. ✅ **Multi-method consensus** (beat_track + tempo + PLP)
4. ✅ **Alias factor testing** (0.5×, 2× for octave errors)
5. ✅ **Energy-based genre detection** (slow ballad identification)

### Best Practices NOT YET Applied
1. ❌ **Extended alias factors** (1.2×, 1.25×, 1.33×, 1.5×) - Needed for BLACKBIRD
2. ❌ **Adaptive thresholds** per genre/energy level
3. ❌ **Multiple tempo windows** (currently uses single 60s window)

---

## 🚨 Critical Notes

### DO NOT MODIFY
- **Onset validation threshold (25%)** - Carefully tuned, protected songs depend on it
- **Alias scoring weights** - Already optimized, changes risk regressions
- **tempo_alignment_score formula** - Used by danceability calculation

### SAFE TO MODIFY
- **`_ALIAS_FACTORS` tuple** - Can expand for BLACKBIRD fix
- **Slow ballad detection thresholds** - Energy/BPM ranges can be tuned
- **Logging verbosity** - Add more debug output as needed

### Known Issues
1. **Calibration model over-correction:** 71.78 → 84.9 BPM for The Scientist
   - Not critical (still much better than 111.33)
   - May need separate calibration tuning later

2. **scipy.signal.hann compatibility:** Must import `scipy_compat` before librosa
   - Already handled in `analyze_server.py`
   - Test scripts need manual import

---

## 🎯 Next Agent TODO List

### Priority 1: Fix BLACKBIRD (Strategy 2)
1. **Add enhanced logging** to see BPM candidates for BLACKBIRD
   ```python
   logger.info(f"🔍 Alias candidates for debugging: {[c['bpm'] for c in alias_candidates]}")
   ```

2. **Expand alias factors** in `pipeline_core.py` line ~46:
   ```python
   _ALIAS_FACTORS = (0.5, 0.67, 0.75, 1.0, 1.2, 1.25, 1.33, 1.5, 2.0)
   ```

3. **Test BLACKBIRD specifically**:
   ```bash
   # Check what candidates are generated
   source .venv/bin/activate
   python -c "
   import librosa
   from backend.analysis.pipeline_core import perform_audio_analysis
   from backend.server.scipy_compat import ensure_hann_patch
   ensure_hann_patch()
   y, sr = librosa.load('Test files/problem chiles/BLACKBIRD.mp3', sr=22050)
   result = perform_audio_analysis(y, sr, 'BLACKBIRD', 'The Beatles')
   print(f'BPM: {result[\"bpm\"]:.2f}')
   "
   ```

4. **Verify protected songs** still at 107.40 BPM

5. **Run full test suite** to ensure no regressions

### Priority 2: Optional Refinements
- Investigate calibration model (71.78 → 84.9 for The Scientist)
- Add unit tests for slow ballad detection
- Document the fix in OPTIMIZATION_SUMMARY.md

### Priority 3: Future Enhancements
- Consider adaptive thresholds per energy level
- Add tempo confidence scoring
- Implement multiple tempo window analysis

---

## 📝 Git Status

**Branch:** `copilot/improve-slow-code-efficiency`  
**Uncommitted changes:** Yes (Strategy 1 implementation)

**Modified files:**
- `/backend/analysis/pipeline_core.py` (lines ~409-434)

**New files:**
- `/test_ballad_simple.py` (debugging script)
- `/docs/AGENT_HANDOVER_STRATEGY1_COMPLETE.md` (this file)

**Suggested commit message:**
```
Fix slow ballad BPM detection by skipping onset validation

- Add early energy calculation to identify potential slow ballads
- Skip onset validation for low-energy tracks in 60-90 BPM range
- Prevents incorrect ×2 correction of slow ballads
- The Scientist: 111.33 → 71.78 BPM (uncalibrated)
- Protected songs verified safe (Islands, Espresso at 107.40)

Addresses Strategy 1 from AGENT_HANDOVER_BPM_FIX.md
BLACKBIRD fix (Strategy 2) pending
```

---

## 🔗 Related Documentation

- **Original handover:** `docs/AGENT_HANDOVER_BPM_FIX.md`
- **Optimization summary:** `OPTIMIZATION_SUMMARY.md`
- **Test documentation:** `RUN_TESTS.md`
- **Phase 1 features:** `backend/PHASE1_FEATURES.md`

---

## 💡 Quick Start for Next Agent

```bash
# 1. Navigate to repo
cd /Users/costasconstantinou/Documents/GitHub/EssentiaServer

# 2. Activate environment
source .venv/bin/activate

# 3. Run tests to see current state
./run_test.sh b

# 4. Expected results:
#    - The Scientist: ~84.9 BPM (was 111.33) ✅
#    - BLACKBIRD: ~76.6 BPM (should be 93) ❌
#    - Islands: 107.40 BPM ✅
#    - Espresso: 107.40 BPM ✅

# 5. To fix BLACKBIRD, modify:
#    backend/analysis/pipeline_core.py line ~46
#    Change: _ALIAS_FACTORS = (0.5, 1.0, 2.0)
#    To:     _ALIAS_FACTORS = (0.5, 0.67, 0.75, 1.0, 1.2, 1.25, 1.33, 1.5, 2.0)

# 6. Test again
./run_test.sh b
```

---

**End of Handover - Ready for Strategy 2 Implementation**
