# Handover – Drum-Part Separation

## Goal
High-quality kick/snare/hats/toms/cymbals stems (similar quality to vocal/instrument separation).

## Available Inputs
- Drum stem from Demucs: `stems_output/htdemucs/060_Paramore_Still_Into_You/drums.wav`
- Prototype drum parts (not good): `drum_kick.wav`, `drum_snare.wav`, `drum_hats.wav`, `drum_toms.wav`, `drum_cymbals.wav` in the same folder.

## Environment for Drum Models
- `.venv-drums` (Python 3.10) created for this purpose. Currently only Cython installed; madmom install failed (Cython/build isolation). No per-drum model installed.

## What to Do
1) Install a Torch-based drum-part separator/transcriber (KSHT + toms/cymbals) in `.venv-drums` using a known checkpoint (Hugging Face/ONNX/MDX variant).
2) Run it on `drums.wav` and save `kick/snare/hats/toms/cymbals.wav` (and onset JSON if available) back into the same folder.
3) If madmom is preferred, process `drums.wav` externally where it builds cleanly, then drop the per-part stems back here.

## Dependencies
- `.venv-drums`: Python 3.10 (no drum model yet). Ready to install Torch + chosen model.
- Main env `.venv` has Demucs; not used for per-drum parts.

## New training scaffold (for true KSHT+toms+cymbals)
- Script: `tools/drum_train.py` (MPS-friendly; 1D U-Net); expects dataset with song folders each containing `kick.wav`, `snare.wav`, `hats.wav`, `toms.wav`, `cymbals.wav` (mixture is sum).
- Train example:  
  `. .venv-drums/bin/activate && PYTORCH_ENABLE_MPS_FALLBACK=1 python tools/drum_train.py --data-root /path/to/drum_multitracks --save-dir runs/drum_sep --epochs 50 --batch-size 2 --segment-seconds 6 --device mps`
- Inference with trained model: `python tools/drum_infer.py --model runs/drum_sep/best.pt --input stems_output/htdemucs/060_Paramore_Still_Into_You/drums.wav --output-dir stems_output/htdemucs/060_Paramore_Still_Into_You/sep_model`
