"""
Minimal drum-part separator training scaffold (kick/snare/hats/toms/cymbals).

Assumptions:
- Your dataset root contains many song folders, each with the stems:
    kick.wav, snare.wav, hats.wav, toms.wav, cymbals.wav
- Sample rate is ~44.1k; we resample as needed.
- Mixture for training is created by summing the five parts.

Usage (M-series Mac with MPS):
    . .venv-drums/bin/activate
    PYTORCH_ENABLE_MPS_FALLBACK=1 python tools/drum_train.py \
        --data-root /path/to/drum_multitracks \
        --save-dir runs/drum_sep_small \
        --epochs 50 --batch-size 2 --segment-seconds 6 --device mps

Outputs:
- Checkpoints under --save-dir (best.pt, last.pt), plus a small debug preview WAV.

This is a lightweight 1D U-Net; adjust depth/channels in UNetConfig to scale up/down.
"""

from __future__ import annotations

import argparse
import math
import os
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np
import soundfile as sf
import torch
import torch.nn as nn
import torch.nn.functional as F
import torchaudio
from torch.utils.data import DataLoader, Dataset, random_split


PARTS = ["kick", "snare", "hats", "toms", "cymbals"]


def _select_device(preferred: str | None = None) -> torch.device:
    if preferred:
        return torch.device(preferred)
    if torch.backends.mps.is_available():
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


def _load_audio(path: Path, sr: int) -> np.ndarray:
    audio, file_sr = sf.read(path)
    if audio.ndim > 1:
        audio = np.mean(audio, axis=1)
    if file_sr != sr:
        audio = torchaudio.functional.resample(
            torch.tensor(audio), orig_freq=file_sr, new_freq=sr
        ).numpy()
    return audio.astype(np.float32)


class DrumStemDataset(Dataset):
    def __init__(self, root: Path, sample_rate: int, segment_seconds: float):
        self.root = Path(root)
        self.sample_rate = sample_rate
        self.seg_samples = int(segment_seconds * sample_rate)
        self.items: List[Path] = []
        for song_dir in self.root.rglob("*"):
            if not song_dir.is_dir():
                continue
            if all((song_dir / f"{p}.wav").exists() for p in PARTS):
                self.items.append(song_dir)
        if not self.items:
            raise RuntimeError(
                f"No song folders with required stems {PARTS} found under {self.root}"
            )

    def __len__(self) -> int:
        return len(self.items)

    def __getitem__(self, idx: int) -> Tuple[torch.Tensor, torch.Tensor]:
        song_dir = self.items[idx % len(self.items)]
        stems = []
        min_len = None
        for p in PARTS:
            audio = _load_audio(song_dir / f"{p}.wav", self.sample_rate)
            min_len = len(audio) if min_len is None else min(min_len, len(audio))
            stems.append(audio)
        # Align lengths
        stems = [s[:min_len] for s in stems]
        stems_np = np.stack(stems, axis=0)  # (parts, T)
        mix = np.sum(stems_np, axis=0)

        if len(mix) >= self.seg_samples:
            start = random.randint(0, len(mix) - self.seg_samples)
            end = start + self.seg_samples
            mix_seg = mix[start:end]
            target_seg = stems_np[:, start:end]
        else:
            pad = self.seg_samples - len(mix)
            mix_seg = np.pad(mix, (0, pad))
            target_seg = np.pad(stems_np, ((0, 0), (0, pad)))

        # Simple peak normalization to avoid clipping
        peak = np.max(np.abs(mix_seg)) + 1e-6
        mix_seg = mix_seg / peak
        target_seg = target_seg / peak

        mix_tensor = torch.tensor(mix_seg, dtype=torch.float32).unsqueeze(0)
        target_tensor = torch.tensor(target_seg, dtype=torch.float32)
        return mix_tensor, target_tensor


@dataclass
class UNetConfig:
    channels: List[int] = None
    kernel_size: int = 15
    stride: int = 2
    num_parts: int = len(PARTS)

    def __post_init__(self):
        if self.channels is None:
            self.channels = [32, 64, 128, 256]


class ConvBlock(nn.Module):
    def __init__(self, in_ch: int, out_ch: int, kernel_size: int):
        super().__init__()
        pad = (kernel_size - 1) // 2
        self.block = nn.Sequential(
            nn.Conv1d(in_ch, out_ch, kernel_size, padding=pad),
            nn.BatchNorm1d(out_ch),
            nn.LeakyReLU(0.2, inplace=True),
            nn.Conv1d(out_ch, out_ch, kernel_size, padding=pad),
            nn.BatchNorm1d(out_ch),
            nn.LeakyReLU(0.2, inplace=True),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.block(x)


class UNet1D(nn.Module):
    def __init__(self, cfg: UNetConfig):
        super().__init__()
        ch = cfg.channels
        k = cfg.kernel_size
        self.downs = nn.ModuleList()
        prev = 1
        for c in ch:
            self.downs.append(nn.Sequential(ConvBlock(prev, c, k), nn.AvgPool1d(2)))
            prev = c
        self.bottleneck = ConvBlock(prev, prev * 2, k)
        prev = prev * 2
        self.ups = nn.ModuleList()
        for c in reversed(ch):
            self.ups.append(
                nn.ModuleList(
                    [
                        nn.Upsample(scale_factor=2, mode="nearest"),
                        ConvBlock(prev + c, c, k),
                    ]
                )
            )
            prev = c
        self.out = nn.Conv1d(prev, cfg.num_parts, 1)

    def forward(self, mix: torch.Tensor) -> torch.Tensor:
        skips = []
        x = mix
        for down in self.downs:
            x = down[0](x)
            skips.append(x)
            x = down[1](x)
        x = self.bottleneck(x)
        for (up, conv), skip in zip(self.ups, reversed(skips)):
            x = up(x)
            # Pad if needed to match skip length (can occur with odd lengths)
            if x.shape[-1] < skip.shape[-1]:
                x = F.pad(x, (0, skip.shape[-1] - x.shape[-1]))
            x = torch.cat([x, skip], dim=1)
            x = conv(x)
        out = self.out(x)
        return out  # (B, num_parts, T)


def save_checkpoint(path: Path, model: nn.Module, optim: torch.optim.Optimizer, epoch: int, loss: float) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    torch.save({"model": model.state_dict(), "optim": optim.state_dict(), "epoch": epoch, "loss": loss}, path)


def preview_audio(save_dir: Path, mix: torch.Tensor, pred: torch.Tensor, sr: int) -> None:
    save_dir.mkdir(parents=True, exist_ok=True)
    mix_np = mix[0].detach().cpu().numpy()
    pred_np = pred[0].detach().cpu().numpy()
    sf.write(save_dir / "preview_mix.wav", mix_np.T if mix_np.ndim > 1 else mix_np, sr)
    for part, audio in zip(PARTS, pred_np):
        sf.write(save_dir / f"preview_{part}.wav", audio, sr)


def train(args: argparse.Namespace) -> None:
    device = _select_device(args.device)
    print(f"Using device: {device}")

    dataset = DrumStemDataset(Path(args.data_root), sample_rate=args.sample_rate, segment_seconds=args.segment_seconds)
    val_size = max(1, int(0.1 * len(dataset)))
    train_size = len(dataset) - val_size
    train_ds, val_ds = random_split(dataset, [train_size, val_size])

    def collate(batch):
        mixes, targets = zip(*batch)
        return torch.stack(mixes, dim=0), torch.stack(targets, dim=0)

    train_loader = DataLoader(train_ds, batch_size=args.batch_size, shuffle=True, num_workers=0, collate_fn=collate)
    val_loader = DataLoader(val_ds, batch_size=args.batch_size, shuffle=False, num_workers=0, collate_fn=collate)

    model = UNet1D(UNetConfig()).to(device)
    optim = torch.optim.Adam(model.parameters(), lr=args.lr)

    best_val = math.inf
    global_step = 0
    for epoch in range(1, args.epochs + 1):
        model.train()
        for mixes, targets in train_loader:
            mixes = mixes.to(device)
            targets = targets.to(device)
            optim.zero_grad()
            pred = model(mixes)
            # L1 loss on all parts
            loss = F.l1_loss(pred, targets)
            loss.backward()
            optim.step()
            global_step += 1
            if global_step % args.log_interval == 0:
                print(f"epoch {epoch} step {global_step} train_loss {loss.item():.4f}")

        # Validation
        model.eval()
        with torch.no_grad():
            val_losses = []
            for mixes, targets in val_loader:
                mixes = mixes.to(device)
                targets = targets.to(device)
                pred = model(mixes)
                vloss = F.l1_loss(pred, targets).item()
                val_losses.append(vloss)
            val_mean = float(np.mean(val_losses)) if val_losses else math.inf
            print(f"epoch {epoch} val_loss {val_mean:.4f}")

            # Save preview and checkpoints
            save_checkpoint(Path(args.save_dir) / "last.pt", model, optim, epoch, val_mean)
            if val_mean < best_val:
                best_val = val_mean
                save_checkpoint(Path(args.save_dir) / "best.pt", model, optim, epoch, val_mean)
                preview_audio(Path(args.save_dir), mixes.cpu(), pred.cpu(), args.sample_rate)
                print(f"New best val {best_val:.4f}; saved previews and checkpoint.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train a drum-part separator (kick/snare/hats/toms/cymbals).")
    parser.add_argument("--data-root", required=True, help="Root folder containing song subfolders with kick/snare/hats/toms/cymbals WAVs.")
    parser.add_argument("--save-dir", default="runs/drum_sep", help="Directory to store checkpoints and previews.")
    parser.add_argument("--sample-rate", type=int, default=44100, help="Target sample rate.")
    parser.add_argument("--segment-seconds", type=float, default=6.0, help="Segment length in seconds.")
    parser.add_argument("--batch-size", type=int, default=2, help="Batch size (keep small on MPS).")
    parser.add_argument("--epochs", type=int, default=50, help="Number of epochs.")
    parser.add_argument("--lr", type=float, default=1e-4, help="Learning rate.")
    parser.add_argument("--device", default=None, help="Device override (e.g., mps, cuda, cpu). Default auto-select.")
    parser.add_argument("--log-interval", type=int, default=10, help="Steps between logging.")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    train(args)
