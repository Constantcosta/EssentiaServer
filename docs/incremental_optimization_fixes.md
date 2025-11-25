# Incremental Optimization Fixes (Shareable Overview)

**Updated:** 2025-11-17  
**Purpose:** Hand this doc to agents to apply the small-but-impactful BPM/Key fixes identified from the latest diff table (BLACKBIRD, Every Little Thing, Islands in the Stream, Espresso, Lose Control, The Scientist, etc.).

**Status:** ✅ REVIEWED AND APPROVED by agent (with minor corrections)

---

## What We're Fixing (TL;DR)
- **BPM:** Remove brittle spectral-flux octave bias (V2 regression), add beat-alignment alias scoring, and add guardrails to halve/double tempos when alignment clearly improves. Use two windows (intro + loudest) to reduce intro/chorus bias.
- **Key:** Improve relative major/minor disambiguation by tightening mode-vote thresholds and leaning on window consensus; keep posterior key calibration applied.
- **Dataset hygiene:** Ensure comparisons use the canonical Spotify calibration CSV and regenerate the human review table after code tweaks.

**Priority Order:**
1. **BPM spectral flux removal** (fixes V2 regression on "The Scientist")
2. **BPM beat-alignment scoring** (fixes octave errors on "BLACKBIRD", "Islands in the Stream")
3. **Key mode disambiguation** (attempt to improve 33% → 50%+ accuracy)
4. **BPM two-window consensus** (advanced - defer if first two fixes work well)

---

## Implementation Checklist

### BPM (pipeline_core.py)
- **Remove/limit spectral flux hint:** Zero out (or cap at ±0.03) the `spectral_octave_hint` inside `_score_tempo_alias_candidates(...)`.
- **Beat-alignment alias test:** After alias scoring, evaluate 0.5×/1×/2× candidates with a simple comb-over-onset check: on-beat onset mean vs off-beat mean; pick alias with best separation when scores are close.
- **Octave guardrails:** If selected BPM > 180 and `tempo_alignment_score(bpm/2)` improves by a margin, halve it; if < 70 and doubling improves, double it.
- **Two-window consensus:** Run tempo on (a) first 60s and (b) loudest 60s; merge alias candidates, normalize to the 70–170 “anchor”, and pick the consensus/median.

### Key (key_detection.py)
- **Tighten relative major/minor tie-breaks:** Slightly raise `_MODE_VOTE_THRESHOLD` and `_WINDOW_SUPPORT_PROMOTION` so weak chroma doesn’t flip mode; still allow window-consensus and dominant-interval rescues.
- **Keep calibration:** Ensure `apply_key_calibration` stays in the hooks and that we regenerate `config/key_calibration.json` after code changes.

### Dataset & Reports
- Use `csv/spotify_calibration_master.csv` as ground truth (avoid the marketing “spotify metrics.csv” when reviewing).
- Regenerate the paired dataset + human review CSV after changes:
  ```bash
  python3 tools/build_calibration_dataset.py \
    --analyzer-exports "exports/**/*.csv" \
    --spotify csv/spotify_calibration_master.csv
  ```

---

## Validation Steps (fast loop)
1) **Unit:** `.venv/bin/python backend/test_phase1_features.py`  
2) **12-track regression:** `./run_test.sh a`  
3) **Review diffs:** Open the regenerated human review CSV under `reports/calibration_reviews/` and spot-check the previously wrong tracks (BLACKBIRD, Every Little Thing, Islands in the Stream, Espresso, Lose Control, The Scientist).
4) **Guardrails to watch:** BPM MAE < 4.0; sub/double-time rate < 10% on the 12-track set; key raw ≥ 45% and calibrated ≥ 65% after updating `config/key_calibration.json`.

---

## Quick Reference (files to touch)
- `backend/analysis/pipeline_core.py`: alias scoring, guardrails, two-window tempo flow.
- `backend/analysis/pipeline_features.py`: `tempo_alignment_score` (if you need margin tweaks) or a helper for beat-alignment scoring.
- `backend/analysis/key_detection.py`: mode vote/consensus thresholds and relative-major/minor handling.
- `backend/analysis/calibration.py`: keep key calibration hook intact; reload assets.
- `tools/build_calibration_dataset.py`: regenerate the review CSV after changes.

---

## Sharing Notes
Paste this doc in handoffs or tickets; it’s scoped to the incremental fixes only. For larger roadmap items (valence overhaul, ML classifiers), defer to the onboarding guide and key-analysis plan.
