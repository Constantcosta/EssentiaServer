#!/usr/bin/env python3
"""
Heavy stem extraction prototype for rich metadata workflows.

What it does:
- Runs a Demucs model (default: htdemucs) to split an input audio file into
  drums / bass / vocals / other.
- Further splits the drum stem into crude kick / snare / hats+cymbals / toms
  using band-limited STFT masks (prototype; replace with a drum transcription
  model for higher quality).
- Writes stems to an output directory and prints a quick summary of detected parts.

Requirements (install into your venv):
    pip install demucs torch soundfile librosa

Note: This is accuracy-first and not optimized for speed; Mac Studio-class
hardware can handle Demucs on 30s previews in seconds. Replace the band masks
with a proper drum transcription model to improve per-part separation.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Dict

import numpy as np


def ensure_deps():
    try:
        import demucs  # noqa: F401
        import torch  # noqa: F401
        import librosa  # noqa: F401
        import soundfile  # noqa: F401
    except ImportError as exc:
        raise SystemExit(
            f"❌ Missing dependency: {exc}. Install with `pip install demucs torch librosa soundfile`"
        ) from exc


def load_and_separate(audio_path: Path, model_name: str = "htdemucs", device: str = "auto"):
    import torch
    from demucs import pretrained
    from demucs.apply import apply_model
    from demucs.audio import AudioFile

    if device == "auto":
        dev = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    else:
        dev = torch.device(device)
    model = pretrained.get_model(model_name)
    model.to(dev)
    model.eval()

    wav = AudioFile(str(audio_path)).read(
        streams=0,
        samplerate=model.samplerate,
        channels=model.audio_channels,
    )
    if not isinstance(wav, torch.Tensor):
        wav = torch.tensor(wav)
    wav = wav.to(dev)
    sources = apply_model(
        model,
        wav[None],
        device=dev,
        overlap=0.25,
        shifts=1,
        split=True,
        segment=15,
    )[0]
    sources = sources.detach().cpu().numpy()
    stems = {name: sources[idx] for idx, name in enumerate(model.sources)}
    return stems, int(model.samplerate)


def stft_band_split(drum_wave: np.ndarray, sr: int) -> Dict[str, np.ndarray]:
    """
    Onset-guided drum splitting (kick/snare/toms/hats/cymbals).
    Still a prototype, but uses onsets + band masks to reduce bleed.
    """
    import librosa

    n_fft = 2048
    hop = 512
    S = librosa.stft(drum_wave, n_fft=n_fft, hop_length=hop)
    freqs = librosa.fft_frequencies(sr=sr, n_fft=n_fft)
    mag = np.abs(S)

    bands = {
        "kick": (30, 120),
        "snare": (120, 400),
        "toms": (60, 300),
        "hats": (4000, 12000),
        "cymbals": (8000, sr // 2),
    }

    band_masks = {
        name: (freqs >= lo) & (freqs <= hi) for name, (lo, hi) in bands.items()
    }

    onset_frames = librosa.onset.onset_detect(
        y=drum_wave, sr=sr, hop_length=hop, backtrack=False, pre_max=3, post_max=3, pre_avg=3, post_avg=3
    )
    # Accumulate masks per category around onsets
    cat_masks = {name: np.zeros_like(S, dtype=np.float32) for name in bands}

    for frame in onset_frames:
        energies = {}
        for name, mask in band_masks.items():
            band_energy = float(np.sum(mag[mask, frame] ** 2))
            energies[name] = band_energy
        # pick the dominant band
        label = max(energies.items(), key=lambda kv: kv[1])[0]
        # spread a small window around the onset frame
        for fidx in range(max(0, frame - 2), min(mag.shape[1], frame + 3)):
            cat_masks[label][:, fidx][band_masks[label]] = 1.0

    parts = {}
    for name, mask in cat_masks.items():
        parts[name] = librosa.istft(S * mask, hop_length=hop)
    return parts


def save_wav(path: Path, audio: np.ndarray, sr: int):
    import soundfile as sf

    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(path), audio.T, sr)


def main() -> None:
    ensure_deps()
    parser = argparse.ArgumentParser(description="Heavy stem splitter (Demucs + drum micro-split prototype)")
    parser.add_argument("audio", type=str, help="Input audio file (wav/m4a/mp3)")
    parser.add_argument("--model", type=str, default="htdemucs", help="Demucs model name (default: htdemucs)")
    parser.add_argument("--device", type=str, default="auto", help="cpu|cuda|auto")
    parser.add_argument("--out", type=str, default="stems_output", help="Output directory")
    args = parser.parse_args()

    audio_path = Path(args.audio).expanduser()
    if not audio_path.exists():
        raise SystemExit(f"❌ Input not found: {audio_path}")
    out_dir = Path(args.out).expanduser()

    print(f"🚀 Running Demucs ({args.model}) on {audio_path.name}...")
    stems, sr = load_and_separate(audio_path, model_name=args.model, device=args.device)

    for name, audio in stems.items():
        save_wav(out_dir / f"{audio_path.stem}_{name}.wav", audio, sr)
        print(f"  ✓ saved {name}")

    if "drums" in stems:
        print("🔍 Splitting drums into kick/snare/hats/toms/cymbals (band masks)...")
        drum_parts = stft_band_split(stems["drums"], sr)
        for part, audio in drum_parts.items():
            save_wav(out_dir / f"{audio_path.stem}_drum_{part}.wav", audio, sr)
            print(f"  ✓ saved drum_{part}")

    print(f"✅ Done. Stems in {out_dir}")


if __name__ == "__main__":
    main()
