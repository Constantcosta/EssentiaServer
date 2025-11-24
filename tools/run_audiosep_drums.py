"""
Run AudioSep (text-queried source separation) to extract drum parts:
kick, snare, hi-hat, toms, cymbals.

This downloads the AudioSep checkpoint from Hugging Face (niobures/AudioSep)
and runs CPU inference on the given drum stem. Outputs are written back into
the same folder as stereo 44.1 kHz WAVs plus onset JSONs.

Usage:
    . .venv-drums/bin/activate
    python tools/run_audiosep_drums.py --stem stems_output/htdemucs/060_Paramore_Still_Into_You/drums.wav
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Dict

import librosa
import numpy as np
import soundfile as sf
import torch
from huggingface_hub import hf_hub_download


# Paths to vendored AudioSep code
SCRIPT_DIR = Path(__file__).resolve().parent
AUDIOSEP_ROOT = SCRIPT_DIR / "audiosep" / "AudioSep"
sys.path.append(str(AUDIOSEP_ROOT))

# AudioSep imports (after sys.path append)
from models.clap_encoder import CLAP_Encoder  # type: ignore  # noqa: E402
from utils import load_ss_model, parse_yaml  # type: ignore  # noqa: E402


def _select_device(preferred: str | None = None) -> torch.device:
    """
    Choose a device in the order: user choice > MPS > CUDA > CPU.
    """
    if preferred:
        return torch.device(preferred)
    if torch.backends.mps.is_available():
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


def build_audiosep_model(device: torch.device) -> torch.nn.Module:
    """
    Download checkpoints and build the AudioSep LightningModule (pl_model) with
    the CLAP text encoder loaded from the same repo.
    """
    ckpt_path = hf_hub_download(
        "niobures/AudioSep", "models/AudioSep (audo)/audiosep_base_4M_steps.ckpt"
    )
    clap_path = hf_hub_download(
        "niobures/AudioSep", "models/AudioSep (audo)/music_speech_audioset_epoch_15_esc_89.98.pt"
    )

    config_yaml = AUDIOSEP_ROOT / "config" / "audiosep_base.yaml"
    configs = parse_yaml(str(config_yaml))

    query_encoder = CLAP_Encoder(pretrained_path=clap_path).eval()
    pl_model = load_ss_model(
        configs=configs,
        checkpoint_path=ckpt_path,
        query_encoder=query_encoder,
    ).eval()

    pl_model.to(device)
    return pl_model


def separate_one(
    model: torch.nn.Module,
    device: torch.device,
    input_path: str,
    prompt: str,
    out_wav: str,
    out_onsets: str,
    target_sr: int = 44100,
    guide_path: str | None = None,
) -> None:
    """
    Run AudioSep for a single text query, resample to target_sr, stereo-ize,
    and write onset JSON.
    """
    # AudioSep expects mono 32 kHz
    mixture, fs = librosa.load(input_path, sr=32000, mono=True)
    with torch.no_grad():
        if guide_path:
            guide, g_sr = librosa.load(guide_path, sr=32000, mono=True)
            guide_tensor = torch.tensor(guide)[None, :].to(device)
            cond = model.query_encoder.get_query_embed(
                modality="audio", audio=guide_tensor, device=device
            )
        else:
            cond = model.query_encoder.get_query_embed(
                modality="text", text=[prompt], device=device
            )
        input_dict = {
            "mixture": torch.tensor(mixture)[None, None, :].to(device),
            "condition": cond,
        }
        sep = model.ss_model(input_dict)["waveform"]
        sep = sep.squeeze(0).squeeze(0).cpu().numpy()

    # Resample to target_sr and convert to stereo
    sep_rs = librosa.resample(sep, orig_sr=32000, target_sr=target_sr)
    stereo = np.stack([sep_rs, sep_rs], axis=1)
    sf.write(out_wav, stereo, target_sr)

    onset_times = librosa.onset.onset_detect(y=sep_rs, sr=target_sr, units="time", backtrack=True)
    with open(out_onsets, "w") as f:
        json.dump({"prompt": prompt, "onsets_seconds": onset_times.tolist()}, f, indent=2)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract drum parts from a drum stem using AudioSep text queries."
    )
    parser.add_argument(
        "--stem",
        required=True,
        help="Path to drum stem (e.g., stems_output/.../drums.wav). Outputs are written alongside it.",
    )
    parser.add_argument(
        "--device",
        default=None,
        help="Device to use (e.g., mps, cuda, cpu). Default: auto (prefers mps then cuda).",
    )
    parser.add_argument(
        "--no-guides",
        action="store_true",
        help="Ignore prototype drum_* guides and use text prompts only.",
    )
    args = parser.parse_args()

    stem_path = Path(args.stem).resolve()
    out_folder = stem_path.parent

    device = _select_device(args.device)
    print(f"Building AudioSep model on {device}...")
    model = build_audiosep_model(device)

    parts: Dict[str, str] = {
        "kick": "kick drum",
        "snare": "snare drum",
        "hats": "hi-hat cymbal",
        "toms": "tom drums",
        "cymbals": "crash and ride cymbals",
    }
    guides: Dict[str, Path] = {
        "kick": out_folder / "drum_kick.wav",
        "snare": out_folder / "drum_snare.wav",
        "hats": out_folder / "drum_hats.wav",
        "toms": out_folder / "drum_toms.wav",
        "cymbals": out_folder / "drum_cymbals.wav",
    }

    for name, prompt in parts.items():
        out_wav = out_folder / f"{name}.wav"
        out_onsets = out_folder / f"{name}_onsets.json"
        guide_path = guides.get(name)
        guide_str = (
            str(guide_path)
            if (guide_path and guide_path.exists() and not args.no_guides)
            else None
        )
        print(
            f"Separating {name} with prompt [{prompt}] guide {guide_str} -> {out_wav}"
        )
        separate_one(
            model=model,
            device=device,
            input_path=str(stem_path),
            prompt=prompt,
            out_wav=str(out_wav),
            out_onsets=str(out_onsets),
            guide_path=guide_str,
        )


if __name__ == "__main__":
    main()
