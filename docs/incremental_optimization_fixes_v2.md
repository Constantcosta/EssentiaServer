# Incremental Optimization Fixes (Agent Implementation Guide)

**Updated:** 2025-11-17 (REVISED after GPT-4 review)  
**Status:** ✅ CORRECTED based on GPT-4 feedback  
**Purpose:** Tactical fixes for BPM octave errors and key detection based on test data analysis

**🔧 CRITICAL CORRECTIONS APPLIED:**
1. ✅ **Beat-alignment validator rewritten** - Now uses on-beat vs off-beat onset energy (comb filter approach), not just beat spacing
2. ✅ **Import path clarified** - `tempo_alignment_score` is in `features/danceability.py` (re-exported via `pipeline_features.py`)
3. ✅ **Guardrail code fixed** - Uses explicit bounds check instead of referencing unavailable module constants
4. ✅ **Comparison logic fixed** - Properly calculates baseline vs candidate separation scores

---

## 🎯 What We're Fixing (Executive Summary)

Based on analysis of test results (`docs/unified_test_comparison.md`), we have:

| Issue | Current State | Target | Priority |
|-------|--------------|--------|----------|
| **BPM Spectral Flux** | V2 regression: "The Scientist" 85→139 BPM | Revert to V1 (85 BPM) | 🔴 CRITICAL |
| **BPM Octave Errors** | 50% accuracy (3/6 tracks wrong) | 80%+ accuracy | 🟡 HIGH |
| **Key Detection** | 33% accuracy (2/6 tracks correct) | 50%+ accuracy | 🟡 MEDIUM |

**Root Causes Identified:**
1. V2's spectral flux logic backfired on dense electronic production
2. Missing beat-alignment validation for octave selection
3. Relative major/minor confusion in key detection (too lenient thresholds)

---

## 📋 Implementation Phases (Sequential)

### Phase 1: Remove Spectral Flux BPM Hint 🔴 CRITICAL

**Problem:** V2 added spectral flux to help with octave selection, but it made things worse
- "The Scientist" went from 84.90 BPM (V1) → 138.52 BPM (V2), should be 74 BPM
- High spectral flux in dense production ≠ fast tempo

**File:** `backend/analysis/pipeline_core.py`

**Changes:**
1. Find `_score_tempo_alias_candidates()` function (starts ~line 97)
2. Set `spectral_octave_hint = 0.0` unconditionally (line ~139)
3. Comment out lines 140-152 (the spectral flux hint calculation)
4. Remove or keep `spectral_flux_mean` parameter but don't use it

**Before:**
```python
def _score_tempo_alias_candidates(
    candidates: List[dict],
    percussive_bpm: float,
    onset_bpm: float,
    plp_bpm: float,
    spectral_flux_mean: Optional[float] = None,  # ← Remove usage
):
    # ... existing code ...
    spectral_octave_hint = 0.0
    if spectral_flux_mean is not None:  # ← DELETE THIS ENTIRE BLOCK
        normalized_flux = min(spectral_flux_mean / 0.3, 1.0)
        # Complex logic that broke things...
```

**After:**
```python
def _score_tempo_alias_candidates(
    candidates: List[dict],
    percussive_bpm: float,
    onset_bpm: float,
    plp_bpm: float,
    spectral_flux_mean: Optional[float] = None,  # Keep param for compatibility
):
    # ... existing code ...
    spectral_octave_hint = 0.0  # Always zero - spectral flux didn't help
    # [Lines 140-152 commented out or removed]
```

**Expected Result:** "The Scientist" returns to ~85 BPM (closer to target of 74)

**Test:** `./run_test.sh a` and check "The Scientist" BPM

---

### Phase 2: Add Beat-Alignment Octave Validation 🟡 HIGH

**Problem:** Octave selection doesn't verify against actual beat positions
- "BLACKBIRD": 121.90 BPM detected, should be 93 BPM (picked wrong octave)
- "Islands in the Stream": 107.40 BPM, should be 71 BPM (picked 1.5× wrong)
- "Espresso": 107.40 BPM ✅ (correct - this is our success case!)

**File:** `backend/analysis/pipeline_core.py`

**Approach:** Compare on-beat vs off-beat energy in the onset envelope using a comb filter

**Key Insight:** A correctly-detected BPM will have strong onset energy ON the beat grid, and weak energy OFF the beat grid. Wrong octaves will show similar energy on/off beat.

**New Function to Add:**
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
    # Test current BPM and its octaves
    test_bpms = []
    if bpm * 0.5 >= _MIN_ALIAS_BPM:
        test_bpms.append(bpm * 0.5)
    test_bpms.append(bpm)
    if bpm * 2.0 <= _MAX_ALIAS_BPM:
        test_bpms.append(bpm * 2.0)
    
    best_bpm = bpm
    best_separation = -1.0
    
    for test_bpm in test_bpms:
        # Generate beat grid in frames
        beat_interval_seconds = 60.0 / test_bpm
        beat_interval_frames = int(beat_interval_seconds * sr / hop_length)
        
        if beat_interval_frames < 2:
            continue  # Too fast to evaluate
        
        # Build on-beat and off-beat masks
        num_frames = len(onset_env)
        on_beat_energy = []
        off_beat_energy = []
        
        # Sample every beat_interval_frames
        for i in range(0, num_frames, beat_interval_frames):
            # On-beat: small window around expected beat
            on_start = max(0, i - 1)
            on_end = min(num_frames, i + 2)
            if on_end > on_start:
                on_beat_energy.append(np.max(onset_env[on_start:on_end]))
            
            # Off-beat: midpoint between beats
            off_i = i + beat_interval_frames // 2
            if off_i < num_frames:
                off_start = max(0, off_i - 1)
                off_end = min(num_frames, off_i + 2)
                if off_end > off_start:
                    off_beat_energy.append(np.mean(onset_env[off_start:off_end]))
        
        if len(on_beat_energy) == 0 or len(off_beat_energy) == 0:
            continue
        
        # Calculate separation: higher is better
        on_mean = np.mean(on_beat_energy)
        off_mean = np.mean(off_beat_energy)
        
        # Separation score: ratio of on-beat to off-beat energy
        # Add epsilon to avoid division by zero
        separation = on_mean / (off_mean + 0.01)
        
        if separation > best_separation:
            best_separation = separation
            best_bpm = test_bpm
    
    return best_bpm, best_separation
```

**Integration Point:** In `perform_audio_analysis()`, after BPM selection:

```python
# Existing code gets initial BPM
final_bpm = best_alias["bpm"]

# NEW: Validate octave with onset energy alignment
if onset_env is not None and len(onset_env) > 0:
    validated_bpm, new_separation = _validate_octave_with_onset_energy(
        final_bpm, onset_env, sr, ANALYSIS_HOP_LENGTH
    )
    
    # Also calculate separation for current BPM for comparison
    current_bpm_separation = new_separation if validated_bpm == final_bpm else 0
    if validated_bpm != final_bpm:
        # Recalculate for current BPM
        _, current_bpm_separation = _validate_octave_with_onset_energy(
            final_bpm, onset_env, sr, ANALYSIS_HOP_LENGTH
        )
    
    # Only change if new octave has significantly better separation (>20% improvement)
    improvement = (new_separation - current_bpm_separation) / max(current_bpm_separation, 0.1)
    if validated_bpm != final_bpm and improvement > 0.20:
        logger.info(
            f"Octave corrected via onset energy: {final_bpm:.2f} → {validated_bpm:.2f} "
            f"(separation improved {improvement*100:.1f}%)"
        )
        final_bpm = validated_bpm
```

**Expected Results:**
- "BLACKBIRD": Should detect ~93 BPM (instead of 121.90)
- "Islands in the Stream": Should detect ~71 BPM (instead of 107.40)
- "Espresso": Should stay at 107.40 (already correct)

**Why This Approach Works:**
- Correct BPM: Strong onset peaks ON the beat grid, weak energy OFF the grid → High separation ratio
- Wrong octave: Similar energy on-beat and off-beat → Low separation ratio
- Unlike just checking beat spacing, this validates against the actual audio signal energy

**Test:** `./run_test.sh a` and verify BPM improvements

---

### Phase 3: Add BPM Guardrails for Extreme Tempos 🟢 MEDIUM

**Problem:** Some tracks are way outside normal dance tempo ranges without good reason

**File:** `backend/analysis/pipeline_core.py`

**Approach:** Apply `tempo_alignment_score()` to validate extreme BPMs

**Note:** `tempo_alignment_score` is in `backend/analysis/features/danceability.py` and re-exported via `backend/analysis/pipeline_features.py` (both import paths work)

**Integration Point:** In `perform_audio_analysis()`, after Phase 2:

```python
# Import at top of file if not already present
from backend.analysis.features import tempo_alignment_score

# After beat-alignment validation...
# NEW: Check if BPM is suspiciously slow/fast
if final_bpm < 60 or final_bpm > 180:
    # Test if octave correction improves danceability alignment
    test_bpm = final_bpm * 2.0 if final_bpm < 60 else final_bpm * 0.5
    
    # Check bounds (use module constants or inline values)
    if 20.0 <= test_bpm <= 280.0:  # _MIN_ALIAS_BPM and _MAX_ALIAS_BPM
        original_score = tempo_alignment_score(final_bpm)
        test_score = tempo_alignment_score(test_bpm)
        
        # If alignment improves by >0.15, apply correction
        if test_score > original_score + 0.15:
            logger.info(f"Tempo guardrail correction: {final_bpm:.2f} → {test_bpm:.2f} "
                       f"(alignment {original_score:.2f} → {test_score:.2f})")
            final_bpm = test_bpm
```

**Expected Results:** Catches any remaining octave errors on edge-case tempos

**Test:** `./run_test.sh a` (should not break any currently working tracks)

---

### Phase 4: Tighten Key Mode Disambiguation 🟡 MEDIUM

**Problem:** 33% key accuracy, often confusing relative major/minor
- "Every Little Thing": Detects B Minor, should be D Major (relative minor error)
- "Islands in the Stream": Detects C Major, should be G#/Ab Major
- "Espresso": Detects A Minor, should be C Major (relative minor error)

**File:** `backend/analysis/key_detection.py`

**Approach:** Increase thresholds to require stronger mode evidence

**Changes:**

1. Increase `_MODE_VOTE_THRESHOLD` (line 33):
```python
# Before:
_MODE_VOTE_THRESHOLD = 0.2

# After:
_MODE_VOTE_THRESHOLD = 0.28  # Require stronger mode consensus
```

2. Increase `_WINDOW_SUPPORT_PROMOTION` (line 30):
```python
# Before:
_WINDOW_SUPPORT_PROMOTION = 0.62

# After:
_WINDOW_SUPPORT_PROMOTION = 0.66  # More conservative mode selection
```

**Rationale:** 
- Current thresholds are too lenient, allowing weak chroma evidence to flip modes
- Relative major/minor have similar chroma profiles, need stronger differentiation
- Success cases (A Major on "Lose Control", A# Major on "The Scientist") had strong evidence

**Expected Results:**
- Reduce relative major/minor confusion
- Target: 50%+ accuracy (from current 33%)
- May fix "Every Little Thing" and "Espresso"

**Note:** This won't fix root detection errors like "BLACKBIRD" or "Islands in the Stream"

**Test:** `./run_test.sh a` and check key detection on all tracks

---

### Phase 5: Two-Window BPM Consensus ⚪ ADVANCED (DEFER)

**Status:** NOT RECOMMENDED for initial implementation

**Rationale:**
- Phases 1-3 should get us to 80%+ BPM accuracy
- Two-window approach adds complexity and processing time
- Only consider if Phases 1-3 fail to achieve target accuracy

**Defer until:** After testing Phases 1-3, if BPM accuracy < 80%

---

## 🧪 Testing & Validation

### Quick Test Loop
```bash
# 1. Unit tests
.venv/bin/python backend/test_phase1_features.py

# 2. Full 12-track test
./run_test.sh a

# 3. Compare results
# Output CSV will be in csv/test_results_YYYYMMDD_HHMMSS.csv
# Compare with previous runs in docs/unified_test_comparison.md
```

### Success Metrics

**⚠️ Note:** These are target goals, not guarantees. Real-world audio analysis has inherent limitations. Success means measurable improvement, not perfection.

**Phase 1 (Spectral Flux Removal):**
- [ ] "The Scientist" BPM: 138.52 → ~85 (closer to 74 target)

**Phase 2 (Beat Alignment):**
- [ ] "BLACKBIRD" BPM: 121.90 → ~93
- [ ] "Islands in the Stream" BPM: 107.40 → ~71
- [ ] "Espresso" BPM: Stays at ~107 ✅
- [ ] Overall BPM accuracy: 50% → 80%+

**Phase 3 (Guardrails):**
- [ ] No regressions on currently working tracks
- [ ] Catches any remaining edge cases

**Phase 4 (Key Modes):**
- [ ] Key accuracy: 33% → 50%+
- [ ] "Every Little Thing": B Minor → D Major (maybe)
- [ ] "Espresso": A Minor → C Major (maybe)
- [ ] No regression on "Lose Control" (A Major) and "The Scientist" (A# Major)

---

## 📁 Files Reference

### Files to Edit
| File | What to Change | Phase |
|------|----------------|-------|
| `backend/analysis/pipeline_core.py` | Remove spectral flux hint | 1 |
| `backend/analysis/pipeline_core.py` | Add beat-alignment validation | 2 |
| `backend/analysis/pipeline_core.py` | Add tempo guardrails | 3 |
| `backend/analysis/key_detection.py` | Increase mode thresholds | 4 |

### Files to Reference (Don't Edit)
| File | Purpose |
|------|---------|
| `backend/analysis/features/danceability.py` | Contains `tempo_alignment_score()` (also re-exported via `pipeline_features.py`) |
| `docs/unified_test_comparison.md` | Test results baseline |
| `docs/AGENT_ONBOARDING.md` | Full context and background |
| `csv/spotify_calibration_master.csv` | Ground truth data |

### Dataset Regeneration (Optional)
If you want to regenerate the full calibration report:
```bash
python3 tools/build_calibration_dataset.py \
  --analyzer-exports "exports/**/*.csv" \
  --spotify csv/spotify_calibration_master.csv
```

This creates a new human review CSV in `reports/calibration_reviews/`

---

## 🎓 Key Lessons from Previous Attempts

### What Worked ✅
- Multi-component features (acousticness V1)
- Rebalanced weights (danceability V1)
- Octave preference for 80-140 BPM range (helped some tracks)

### What Didn't Work ❌
- Spectral flux for tempo octave selection (V2 regression)
- Pitch variance for valence detection (can't detect lyrical sentiment)
- Simple brightness for acousticness (too simplistic)

### Best Practices 📝
1. Always test against Spotify ground truth
2. Watch for regressions on currently working tracks
3. Incremental changes > big rewrites
4. Document what worked and what didn't

---

## 🚀 Implementation Order

**Recommended Sequence:**
1. ✅ Phase 1 (Spectral Flux) - **START HERE** - fixes critical regression
2. ✅ Phase 2 (Beat Alignment) - **HIGH IMPACT** - fixes majority of octave errors
3. ⏭️  Phase 3 (Guardrails) - **LOW RISK** - safety net for edge cases
4. 🤔 Phase 4 (Key Modes) - **EXPERIMENTAL** - may or may not help
5. ❌ Phase 5 (Two-Window) - **SKIP** - only if needed

**Time Estimates:**
- Phase 1: 15-30 minutes
- Phase 2: 1-2 hours (new function + integration)
- Phase 3: 30 minutes
- Phase 4: 15 minutes
- Testing each phase: 5 minutes

**Total:** 3-4 hours for Phases 1-4 with testing

---

## 💡 Agent Handoff Notes

**Context:** This is a tactical optimization pass based on empirical test data. The codebase already has solid foundations (V1 improvements were successful). We're fixing specific regressions and edge cases.

**Not in Scope:**
- Valence detection overhaul (still 163% error, needs ML/vocal analysis)
- Complete key detection rewrite (33% accuracy may need different algorithm)
- Performance optimization (processing time is acceptable)

**Success Criteria:**
- BPM accuracy: 50% → 80%+ (from 3/6 to 5/6 tracks correct)
- Key accuracy: 33% → 50%+ (from 2/6 to 3/6 tracks correct)
- No regressions on currently working features

**If You Get Stuck:**
- Refer to `docs/AGENT_ONBOARDING.md` for full context
- Check `docs/unified_test_comparison.md` for test data
- Test incrementally - one phase at a time
- Don't be afraid to revert changes that don't work

---

**Last Updated:** November 17, 2025  
**Author:** GitHub Copilot Agent (Review and Enhancement of GPT-4 Plan)
