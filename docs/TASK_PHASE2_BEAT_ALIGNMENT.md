# TASK: Implement Phase 2 - Beat-Alignment Octave Validation

**Assigned To:** GPT-5 Codex (high)  
**Priority:** HIGH  
**Estimated Time:** 45-60 minutes  
**Status:** 🔴 NOT STARTED

---

## 🎯 Task Objective

Implement a new function `_validate_octave_with_onset_energy()` in `backend/analysis/pipeline_core.py` that validates BPM octave selection by comparing on-beat vs off-beat energy in the onset envelope.

**Goal:** Fix octave errors in BPM detection for tracks like "BLACKBIRD" (121.90 → 93 BPM) and "Islands in the Stream" (107.40 → 71 BPM).

---

## 📋 Requirements

### 1. Create New Function

**Location:** `backend/analysis/pipeline_core.py`  
**Function Name:** `_validate_octave_with_onset_energy`  
**Insert After:** The existing `_score_tempo_alias_candidates()` function (around line 180)

**Function Signature:**
```python
def _validate_octave_with_onset_energy(
    bpm: float,
    onset_env: np.ndarray,
    sr: int,
    hop_length: int
) -> tuple[float, float]:
    """
    Validate BPM octave by comparing on-beat vs off-beat onset energy.
    
    A good BPM will have strong onsets aligned with the beat grid.
    Wrong octaves will have similar energy on-beat and off-beat.
    
    Args:
        bpm: Current BPM estimate
        onset_env: Onset strength envelope
        sr: Sample rate
        hop_length: Hop length used for onset detection
        
    Returns:
        (best_bpm, best_separation): BPM with highest on/off-beat energy separation
    """
```

### 2. Implementation Algorithm

**Core Approach - Comb Filter on Onset Envelope:**

1. **Test Octave Candidates:**
   - Test `bpm * 0.5` (if >= 20.0 BPM)
   - Test `bpm * 1.0` (current)
   - Test `bpm * 2.0` (if <= 280.0 BPM)

2. **For Each Candidate BPM:**
   - Convert BPM to beat interval in frames:
     ```python
     beat_interval_seconds = 60.0 / test_bpm
     beat_interval_frames = int(beat_interval_seconds * sr / hop_length)
     ```
   
   - Sample onset envelope **ON** the beat grid (every `beat_interval_frames`)
   - Sample onset envelope **BETWEEN** beats (at `beat_interval_frames // 2` offset)
   
   - Calculate on-beat energy: Take max in 3-frame window around each beat
   - Calculate off-beat energy: Take mean in 3-frame window between beats
   
   - Compute separation score:
     ```python
     on_mean = np.mean(on_beat_energy)
     off_mean = np.mean(off_beat_energy)
     separation = on_mean / (off_mean + 0.01)  # Add epsilon to avoid division by zero
     ```

3. **Return Best:**
   - Return `(test_bpm, separation)` with highest separation score

### 3. Edge Cases to Handle

- ✅ Empty onset envelope: Skip validation, return `(bpm, 0.0)`
- ✅ Too few frames: Skip if `beat_interval_frames < 2`
- ✅ Out of bounds: Clip frame indices to `[0, num_frames)`
- ✅ Division by zero: Add epsilon (0.01) to denominator

### 4. Integration Point

**Location:** In `perform_audio_analysis()` function, after BPM selection (around line 320-330)

**Find This Section:**
```python
# Existing code that selects BPM
best_alias, scored_aliases = _score_tempo_alias_candidates(
    candidates,
    percussive_bpm,
    onset_bpm,
    plp_bpm,
    spectral_flux_mean=spectral_flux_mean,
)
final_bpm = best_alias["bpm"]
```

**Add After:**
```python
# NEW: Validate octave with onset energy alignment
if onset_env is not None and len(onset_env) > 0:
    validated_bpm, new_separation = _validate_octave_with_onset_energy(
        final_bpm, onset_env, sr, ANALYSIS_HOP_LENGTH
    )
    
    # If different octave selected, compare separation scores
    if validated_bpm != final_bpm:
        # Calculate current BPM's separation for fair comparison
        _, current_bpm_separation = _validate_octave_with_onset_energy(
            final_bpm, onset_env, sr, ANALYSIS_HOP_LENGTH
        )
        
        # Require 20% improvement to change octave
        improvement = (new_separation - current_bpm_separation) / max(current_bpm_separation, 0.1)
        if improvement > 0.20:
            logger.info(
                f"Octave corrected via onset energy: {final_bpm:.2f} → {validated_bpm:.2f} "
                f"(separation improved {improvement*100:.1f}%)"
            )
            final_bpm = validated_bpm
```

---

## 📁 Files to Modify

### Primary File
- **`backend/analysis/pipeline_core.py`**
  - Add new function `_validate_octave_with_onset_energy()` (~60 lines)
  - Add integration code in `perform_audio_analysis()` (~20 lines)

### Reference Files (READ ONLY - Do Not Modify)
- **`docs/incremental_optimization_fixes_v2.md`** - Full implementation guide
- **`docs/gpt_review_corrections.md`** - Explains why this approach is correct
- **`docs/unified_test_comparison.md`** - Test data showing current failures
- **`docs/AGENT_ONBOARDING.md`** - Full project context

---

## 🧪 Testing Requirements

### 1. Unit Test (Quick Validation)
```bash
.venv/bin/python backend/test_phase1_features.py
```
**Expected:** All tests pass (no regressions)

### 2. Full Test Suite (Validation)
```bash
./run_test.sh a
```
**Expected Results:**

| Track | Current BPM | Target BPM | Expected After Fix |
|-------|-------------|------------|-------------------|
| BLACKBIRD | 121.90 | 93 | ~93 BPM ✅ |
| Islands in the Stream | 107.40 | 71 | ~71 BPM ✅ |
| Espresso | 107.40 | 104 | Stay ~107 ✅ (already correct) |
| The Scientist | (varies) | 74 | No change from Phase 1 |

### 3. Success Criteria
- ✅ "BLACKBIRD" BPM reduces from 121.90 to ~93
- ✅ "Islands in the Stream" BPM reduces from 107.40 to ~71
- ✅ "Espresso" stays at ~107 (no regression)
- ✅ Overall BPM accuracy improves from 50% to 67%+ (4/6 or better)
- ✅ No errors or exceptions during test run

---

## 📊 Context: Why This Approach?

### The Problem
Current BPM detection sometimes picks wrong octaves because it doesn't verify against actual audio signal:
- Beat detector finds beats at multiple levels (downbeats, subdivisions)
- Any octave can match SOME subset of detected beats
- Need to check actual audio energy, not just beat positions

### The Solution (Comb Filter)
**Correct BPM:** Strong onset peaks ON the beat grid, weak energy BETWEEN beats → High separation ratio

**Wrong Octave:** Similar energy on-beat and off-beat → Low separation ratio

**Example:**
```
Correct 90 BPM:  |🔊|  |🔊|  |🔊|  |🔊|   separation = 4.2
Wrong 180 BPM:   |🔊🔊|🔊🔊|🔊🔊|🔊🔊|   separation = 1.8
```

---

## 🚨 Common Pitfalls to Avoid

### ❌ DON'T: Compare beat positions to beat grid
```python
# This doesn't work - all octaves match some beats
for expected_beat in beat_grid:
    if any_detected_beat_is_close:
        score += 1
```

### ✅ DO: Compare onset ENERGY on-beat vs off-beat
```python
# This works - correct tempo has strong on-beat energy
on_mean = np.mean(onset_env[on_beat_indices])
off_mean = np.mean(onset_env[off_beat_indices])
separation = on_mean / (off_mean + 0.01)
```

### ❌ DON'T: Use invalid comparison
```python
# Wrong: multiplying score by ratio doesn't give baseline
original_score = new_score * (validated_bpm / final_bpm)
```

### ✅ DO: Calculate both scores explicitly
```python
# Correct: calculate score for both BPMs independently
_, current_score = validate_octave(current_bpm, ...)
_, new_score = validate_octave(candidate_bpm, ...)
improvement = (new_score - current_score) / current_score
```

---

## 📝 Code Template (Skeleton)

```python
def _validate_octave_with_onset_energy(
    bpm: float,
    onset_env: np.ndarray,
    sr: int,
    hop_length: int
) -> tuple[float, float]:
    """Validate BPM octave by comparing on-beat vs off-beat onset energy."""
    
    # Edge case: empty onset envelope
    if onset_env is None or len(onset_env) == 0:
        return (bpm, 0.0)
    
    # TODO: Generate test BPM candidates (0.5×, 1×, 2×)
    test_bpms = []
    # ... add candidates with bounds checking (20-280 BPM)
    
    best_bpm = bpm
    best_separation = -1.0
    num_frames = len(onset_env)
    
    for test_bpm in test_bpms:
        # TODO: Convert BPM to frame interval
        beat_interval_seconds = 60.0 / test_bpm
        beat_interval_frames = int(beat_interval_seconds * sr / hop_length)
        
        # Edge case: too fast to evaluate
        if beat_interval_frames < 2:
            continue
        
        # TODO: Sample onset envelope on-beat and off-beat
        on_beat_energy = []
        off_beat_energy = []
        
        for i in range(0, num_frames, beat_interval_frames):
            # TODO: Sample on-beat (small window around i)
            # TODO: Sample off-beat (midpoint between beats)
            pass
        
        # Edge case: no samples collected
        if len(on_beat_energy) == 0 or len(off_beat_energy) == 0:
            continue
        
        # TODO: Calculate separation score
        on_mean = np.mean(on_beat_energy)
        off_mean = np.mean(off_beat_energy)
        separation = on_mean / (off_mean + 0.01)
        
        # TODO: Track best
        if separation > best_separation:
            best_separation = separation
            best_bpm = test_bpm
    
    return best_bpm, best_separation
```

---

## 🔗 Related Tasks

**Prerequisite:** None (can be implemented independently)

**Blocks:** None (other phases are independent)

**Related:**
- ✅ Phase 1 (Spectral Flux Removal) - Will be done by GitHub Copilot Agent
- ✅ Phase 3 (Guardrails) - Will be done by GitHub Copilot Agent  
- ✅ Phase 4 (Key Thresholds) - Will be done by GitHub Copilot Agent

---

## 📞 Questions or Issues?

If you encounter any issues:

1. **Check the reference docs:**
   - `docs/incremental_optimization_fixes_v2.md` - Full spec
   - `docs/gpt_review_corrections.md` - Why this approach

2. **Verify test data:**
   - `docs/unified_test_comparison.md` - Expected results
   - `csv/spotify_calibration_master.csv` - Ground truth

3. **Flag for review:**
   - Post implementation code for validation
   - Run tests and share results
   - GitHub Copilot Agent will integrate with other phases

---

## ✅ Deliverables Checklist

Before marking complete:

- [ ] Function `_validate_octave_with_onset_energy()` implemented
- [ ] Integration code added to `perform_audio_analysis()`
- [ ] Edge cases handled (empty arrays, bounds, division by zero)
- [ ] Code includes logging for octave corrections
- [ ] Unit tests pass (`.venv/bin/python backend/test_phase1_features.py`)
- [ ] Full test suite runs (`./run_test.sh a`)
- [ ] Results show BPM improvements on target tracks
- [ ] No regressions on currently working tracks
- [ ] Code reviewed and ready for merge

---

**Task Created:** November 17, 2025  
**Project Manager:** GitHub Copilot Agent  
**Estimated Completion:** 1 hour  
**Next Review:** After implementation and testing
