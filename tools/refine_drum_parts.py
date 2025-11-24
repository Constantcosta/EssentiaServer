"""
Refine drum part stems using multi-channel Wiener filtering guided by
prototype stems. This expects the following files in the target folder:

- drums.wav (stereo)
- drum_kick.wav, drum_snare.wav, drum_hats.wav, drum_toms.wav, drum_cymbals.wav (mono guides)

Outputs (stereo, mixture-length) are written back to the same folder:
- kick.wav, snare.wav, hats.wav, toms.wav, cymbals.wav
- kick_onsets.json, snare_onsets.json, hats_onsets.json, toms_onsets.json, cymbals_onsets.json

Run inside the project root with the drums virtualenv activated:
    python tools/refine_drum_parts.py --folder stems_output/htdemucs/060_Paramore_Still_Into_You
"""

from __future__ import annotations

import argparse
import json
import os
from typing import Dict, Tuple

import librosa
import numpy as np
import soundfile as sf


PartName = str


def _load_audio(path: str) -> Tuple[np.ndarray, int]:
    audio, sr = sf.read(path)
    audio = audio.astype(np.float32)
    return audio, sr


def _stft(y: np.ndarray, n_fft: int, hop: int, win: int) -> np.ndarray:
    return librosa.stft(y, n_fft=n_fft, hop_length=hop, win_length=win, window="hann", center=True)


def _istft(S: np.ndarray, hop: int, win: int, length: int) -> np.ndarray:
    return librosa.istft(S, hop_length=hop, win_length=win, length=length)


def _build_band_emphasis(freqs: np.ndarray) -> Dict[PartName, np.ndarray]:
    # Emphasize plausible frequency regions per drum part.
    bands = {}
    kick = (freqs <= 180).astype(np.float32)
    snare = ((freqs >= 140) & (freqs <= 4500)).astype(np.float32)
    hats = (freqs >= 4000).astype(np.float32)
    toms = ((freqs >= 80) & (freqs <= 900)).astype(np.float32)
    cymbals = (freqs >= 6000).astype(np.float32)
    # Blend with neutral weight to avoid hard zeros.
    def mix(mask: np.ndarray) -> np.ndarray:
        return 0.25 + 0.75 * librosa.util.normalize(mask, norm=np.inf)

    bands["kick"] = mix(kick)
    bands["snare"] = mix(snare)
    bands["hats"] = mix(hats)
    bands["toms"] = mix(toms)
    bands["cymbals"] = mix(cymbals)
    return bands


def refine_parts(folder: str) -> None:
    parts = ["kick", "snare", "hats", "toms", "cymbals"]
    guide_files = {
        "kick": "drum_kick.wav",
        "snare": "drum_snare.wav",
        "hats": "drum_hats.wav",
        "toms": "drum_toms.wav",
        "cymbals": "drum_cymbals.wav",
    }

    drums_path = os.path.join(folder, "drums.wav")
    mix, sr = _load_audio(drums_path)
    if mix.ndim == 1:
        mix = np.stack([mix, mix], axis=1)
    mix_len = mix.shape[0]

    guides: Dict[PartName, np.ndarray] = {}
    for name, fname in guide_files.items():
        path = os.path.join(folder, fname)
        guide, g_sr = _load_audio(path)
        if g_sr != sr:
            guide = librosa.resample(guide, orig_sr=g_sr, target_sr=sr)
        if guide.ndim > 1:
            guide = np.mean(guide, axis=1)
        if guide.shape[0] < mix_len:
            guide = np.pad(guide, (0, mix_len - guide.shape[0]))
        elif guide.shape[0] > mix_len:
            guide = guide[:mix_len]
        guides[name] = guide.astype(np.float32)

    n_fft = 4096
    hop = 1024
    win = 4096
    eps = 1e-8
    power = 1.6  # mask sharpness

    mix_stfts = [
        _stft(mix[:, ch], n_fft=n_fft, hop=hop, win=win) for ch in range(mix.shape[1])
    ]
    mix_mag = np.mean([np.abs(S) for S in mix_stfts], axis=0)
    freqs = librosa.fft_frequencies(sr=sr, n_fft=n_fft)
    band_emphasis = _build_band_emphasis(freqs)

    proto_stack = []
    for p in parts:
        g_stft = _stft(guides[p], n_fft=n_fft, hop=hop, win=win)
        mag = np.abs(g_stft) * band_emphasis[p][:, None]
        proto_stack.append(mag)
    proto_stack = np.stack(proto_stack, axis=0)

    # Add a small share of the mixture magnitude to avoid zero masks in sparse regions.
    floor = mix_mag * 0.05
    proto_stack = np.maximum(proto_stack, floor[None, ...])

    mask = proto_stack ** power
    mask_sum = np.sum(mask, axis=0, keepdims=True) + eps
    mask = mask / mask_sum  # shape: (parts, freq, frames)

    estimates: Dict[PartName, np.ndarray] = {}
    for idx, part in enumerate(parts):
        part_stfts = []
        for mix_S in mix_stfts:
            part_stfts.append(mask[idx] * mix_S)
        wav_chans = [
            _istft(S_part, hop=hop, win=win, length=mix_len) for S_part in part_stfts
        ]
        estimates[part] = np.stack(wav_chans, axis=1)

    for part, audio in estimates.items():
        out_path = os.path.join(folder, f"{part}.wav")
        sf.write(out_path, audio, sr)

        mono = audio.mean(axis=1)
        onset_times = librosa.onset.onset_detect(y=mono, sr=sr, units="time", backtrack=True)
        onset_path = os.path.join(folder, f"{part}_onsets.json")
        with open(onset_path, "w") as f:
            json.dump({"part": part, "onsets_seconds": onset_times.tolist()}, f, indent=2)


def main() -> None:
    parser = argparse.ArgumentParser(description="Refine drum part stems using guided Wiener filtering.")
    parser.add_argument(
        "--folder",
        required=True,
        help="Folder containing drums.wav and the drum_* guide files.",
    )
    args = parser.parse_args()
    refine_parts(args.folder)


if __name__ == "__main__":
    main()
