# Handover – Stem Separation (General)

## Assets
- Demucs outputs (htdemucs) for `060_Paramore_Still_Into_You.m4a`:
  - `stems_output/htdemucs/060_Paramore_Still_Into_You/`
  - Stems: `drums.wav`, `bass.wav`, `vocals.wav`, `other.wav`
  - Prototype drum parts (bleedy): `drum_kick.wav`, `drum_snare.wav`, `drum_hats.wav`, `drum_toms.wav`, `drum_cymbals.wav`

## Tools
- `tools/heavy_stem_pipeline.py` (runs Demucs on a single file)
- Demucs CLI (main venv):
  ```
  .venv/bin/python -m demucs -n htdemucs --out stems_output "<path/to/preview.m4a>"
  ```

## Dependencies (main venv `.venv`, Python 3.14)
- demucs, torch, librosa, soundfile, torchcodec
- ffmpeg installed via Homebrew

## Notes
- Prototype drum split uses onset-guided band masks; quality is not production-grade. Use a better drum-part model for per-piece drums (see drum handover).
