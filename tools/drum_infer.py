"""
Inference script for the trained drum-part separator from drum_train.py.

Usage:
    . .venv-drums/bin/activate
    python tools/drum_infer.py --model runs/drum_sep/best.pt \
        --input stems_output/htdemucs/060_Paramore_Still_Into_You/drums.wav \
        --output-dir stems_output/htdemucs/060_Paramore_Still_Into_You/sep_model

Outputs: kick.wav, snare.wav, hats.wav, toms.wav, cymbals.wav in --output-dir.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
import torchaudio

from drum_train import PARTS, UNet1D, UNetConfig, _select_device


def load_checkpoint(model: torch.nn.Module, path: Path, map_location: str | torch.device) -> None:
    ckpt = torch.load(path, map_location=map_location)
    model.load_state_dict(ckpt["model"])


def separate(model: torch.nn.Module, audio: np.ndarray, sr: int, device: torch.device) -> np.ndarray:
    if audio.ndim > 1:
        audio = np.mean(audio, axis=1)
    mix = torch.tensor(audio, dtype=torch.float32).unsqueeze(0).unsqueeze(0).to(device)
    with torch.no_grad():
        pred = model(mix).cpu().squeeze(0).numpy()  # (parts, T)
    return pred


def main() -> None:
    parser = argparse.ArgumentParser(description="Run trained drum separator inference.")
    parser.add_argument("--model", required=True, help="Path to checkpoint (best.pt from drum_train.py).")
    parser.add_argument("--input", required=True, help="Path to drum mixture WAV.")
    parser.add_argument("--output-dir", required=True, help="Folder to write separated stems.")
    parser.add_argument("--device", default=None, help="Device override (mps/cuda/cpu).")
    args = parser.parse_args()

    device = _select_device(args.device)
    model = UNet1D(UNetConfig()).to(device)
    load_checkpoint(model, Path(args.model), map_location=device)
    model.eval()

    audio, sr = sf.read(args.input)
    pred = separate(model, audio, sr, device)

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    for part, audio_part in zip(PARTS, pred):
        sf.write(out_dir / f"{part}.wav", audio_part, sr)
    print(f"Wrote stems to {out_dir}")


if __name__ == "__main__":
    main()
