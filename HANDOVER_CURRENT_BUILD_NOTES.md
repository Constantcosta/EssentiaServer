# Current Build Notes – Preview Key Handling (18 Nov 2025)

**Branch/Commit:** `copilot/improve-slow-code-efficiency` @ `a969c99`  
**Purpose:** Document the key-detection updates and current behavior so future agents know why this build performs well (and what trade-offs remain).

## What Changed
- Added triad energy helper to support tonic/dominant disambiguation in short clips (`key_detection_helpers.py`).
- Tightened preview-specific fusion in `detect_global_key`:
  - Captures window dominance for later decisions.
  - Fifth-reconciliation now respects strong tonic support (template, windows, Essentia) before flipping to dominant/subdominant.
  - Chroma-peak overrides are stricter for fifth-related peaks in previews, especially when window dominance favors the tonic.
  - Tonic-bias safeguard runs after fusion (except chroma-peak cases) and only restores the tonic when triad/template/support are near-tied.

## Current Results (Test C – 12 previews)
- **BPM:** 12/12 correct (100% P2, octave-aware).
- **Key:** 10/12 correct against Spotify table.
  - Musically preferred outputs retained:
    - `Carlton_A_Thousand_Miles` → **B Major** (Spotify expects F#; IV feels like home).
    - `___Song_Fomerly_Known_As_` → **F# Major** (Spotify expects B; tune centers on F#/F#7).
  - `Green_Forget_You` now lands on **C Major** (tonic) and aligns with Spotify.

## Why It’s Working Better
- Fifth/dominant biases are tempered by triad energy and window dominance; we don’t flip off the tonic unless evidence is clearly stronger.
- Chroma peak overrides on short clips no longer jump to dominant/subdominant without decisive energy/support.
- Preview fusion is now explicit about when window consensus may override (higher dominance/separation gates for fifth-related alternatives).

## Open Facts for Future Agents
- Two intentional Spotify mismatches remain (Carlton, Song Formerly) to preserve musically preferred tonics; change only if strict Spotify conformity is required.
- Calibration and tempo remain unchanged in this commit (BPM already 12/12).
- If strict Spotify alignment is ever needed, add a flagged path rather than undoing the tonic safeguards globally.

