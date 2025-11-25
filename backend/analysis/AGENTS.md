# Backend Analysis Agent Guide

Lightweight map for agents and automation working on the audio analysis stack.

## Module map
- `pipeline_core.py`: orchestrates tempo/key/descriptor extraction; calls the helpers below.
- `features/`: focused helpers (no file should exceed ~300 LOC):
  - `time_signature.py`: beat-derived meter detection.
  - `valence.py`: valence + mood estimation.
  - `loudness.py`: loudness, dynamics, silence ratio.
  - `danceability.py`: tempo-aligned danceability (heuristic + Essentia fallback).
  - `descriptors.py`: spectral/percussive/harmonic descriptors.
  - `common.py`: shared constants + `safe_frame_length`.
- `pipeline_features.py`: compatibility re-exports; prefer importing from `features/`.

## How to work here
- Favor pure, single-purpose functions; no file I/O inside feature helpers.
- Keep new helpers in their own files under `features/`; re-export via `features/__init__.py`.
- If you touch `pipeline_core.py`, prefer injecting new logic via a helper in `features/`.
- Essentia is optional; guard with `HAS_ESSENTIA` and provide a NumPy/librosa fallback.

## Adding a new feature helper
1. Create `backend/analysis/features/<name>.py` with the new function(s).
2. Export it from `features/__init__.py`; leave `pipeline_features.py` untouched for compatibility.
3. Add a unit test in `backend/test_phase1_features.py` or a new pytest module under `tools/tests/`.

## Quick commands
- Run feature smoke test: `python backend/test_phase1_features.py`
- (Optional) Format imports: `python -m isort backend/analysis/features`

