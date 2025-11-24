# Handover – BPM Refinement

## Where to Look
- Context refinement code: `backend/analysis/tempo_detection.py`
- Lab harness: `tools/bpm_context_lab.py`
- Truth probe: `tools/stem_probe.py`

## Current Issues
- Wrong BPMs still: She Loves You (~105/147 vs 153), Don’t Dream It’s Over (~161 vs 81), 2 Become 1 (~143 vs 72), The Gambler (~89 vs 87 feel), Blow Up The Pokies fix suppressed. Baselines (Still Into You, Faint) stable.

## Next Steps
- Loosen/refine gating for 6/8/half-time (allow halving when base >140 or dotted cues are strong; protect mid-tempo halving unless harmonic+drum periodicity clearly better).
- Add meter cues; integrate drum-part cues (once available) to anchor beat/meter.
- Re-run `tools/bpm_context_lab.py`, then rerun the full repertoire online.

## How to Run
```
.venv/bin/python tools/bpm_context_lab.py
```

## Envs
- `.venv` (Python 3.14) has current code; demucs/torch/librosa/soundfile/torchcodec installed; ffmpeg via Homebrew.
