#!/usr/bin/env python3
"""
Focused lab script to iterate on the harmonic/percussive BPM refinement.

Picks a small set of preview clips (4 tricky, 1 baseline), runs:
  - Base tempo analysis (current pipeline)
  - Context refinement (percussive + harmonic onset periodicity)

Logs base vs refined BPM, deltas to truth, and candidate scores.
Intended for rapid iteration inside this conversation.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import librosa
import numpy as np

REPO_ROOT = Path(__file__).resolve().parent.parent
import sys

if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from backend.server.scipy_compat import ensure_hann_patch
from backend.analysis.analysis_context import prepare_analysis_context
from backend.analysis.settings import ANALYSIS_HOP_LENGTH, get_adaptive_analysis_params
from backend.analysis.tempo_detection import analyze_tempo, _refine_bpm_with_context
from tools.key_utils import keys_match_fuzzy

ensure_hann_patch()


@dataclass
class TrackTruth:
    title: str
    artist: str
    bpm: float
    key: str
    notes: str = ""


def load_truths(csv_path: Path) -> List[TrackTruth]:
    import csv

    rows: List[TrackTruth] = []
    with csv_path.open(newline="", encoding="utf-8") as handle:
        reader = csv.reader(handle)
        next(reader, None)  # skip header
        for raw in reader:
            if not raw or len(raw) < 4:
                continue
            title, artist, bpm_raw, key = raw[:4]
            notes = raw[4] if len(raw) > 4 else ""
            try:
                bpm = float(bpm_raw)
            except (TypeError, ValueError):
                continue
            rows.append(TrackTruth(title=title.strip(), artist=artist.strip(), bpm=bpm, key=key.strip(), notes=notes.strip()))
    return rows


def norm(text: str) -> str:
    import re

    return re.sub(r"[^a-z0-9]", "", text.lower())


def match_truth(preview_path: Path, truths: List[TrackTruth]) -> Optional[TrackTruth]:
    stem = preview_path.stem.rsplit(".", 1)[0]
    parts = stem.split("_", 2)
    artist = parts[1] if len(parts) > 1 else ""
    title = parts[2] if len(parts) > 2 else parts[-1] if parts else stem
    n_artist = norm(artist)
    n_title = norm(title)
    for t in truths:
        if norm(t.title) == n_title:
            return t
    for t in truths:
        if n_title in norm(t.title) or norm(t.title) in n_title:
            return t
        if n_artist and n_artist in norm(t.artist):
            return t
    return None


def base_bpm(y, sr) -> Tuple[float, float]:
    duration = len(y) / sr
    adaptive = get_adaptive_analysis_params(duration)
    ctx = prepare_analysis_context(y, sr, tempo_window_override=adaptive["tempo_window"])
    tempo_result = analyze_tempo(
        y_trimmed=ctx.y_trimmed,
        sr=sr,
        hop_length=ctx.hop_length,
        tempo_segment=ctx.tempo_segment,
        tempo_start=ctx.tempo_start,
        tempo_ctx=ctx.tempo_ctx,
        descriptor_ctx=ctx.descriptor_ctx,
        stft_magnitude=ctx.stft_magnitude,
        tempo_window_meta=ctx.tempo_window_meta,
        timer=None,
        adaptive_params=adaptive,
    )
    return float(tempo_result.bpm), float(tempo_result.bpm_confidence)


def main() -> None:
    parser = argparse.ArgumentParser(description="BPM context refinement lab (4 tricky + 1 easy)")
    parser.add_argument(
        "--preview-dir",
        type=str,
        default=str(Path.home() / "Documents" / "Git repo" / "Songwise 1" / "preview_samples_repertoire_90"),
        help="Directory with repertoire previews",
    )
    parser.add_argument(
        "--truth",
        type=str,
        default=str(REPO_ROOT / "csv" / "truth_repertoire_manual.csv"),
        help="Truth CSV",
    )
    args = parser.parse_args()

    preview_dir = Path(args.preview_dir).expanduser()
    truths = load_truths(Path(args.truth))
    if not truths:
        raise SystemExit("❌ No truths loaded")

    # Preselect tricky + baseline filenames
    picks = [
        "022_The_Whitlams_Blow_Up_the_Pokies.m4a",      # 6/8 half/double
        "015_Crowded_House_Don_t_Dream_It_s_Over.m4a",  # slow/loose, half-time pull
        "006_The_Beatles_She_Loves_You.m4a",            # classic double-time
        "059_Spice_Girls_2_Become_1.m4a",               # doubled ballad
        "066_Kenny_Rogers_Gambler.m4a",                 # low tempo ambiguity
        "060_Paramore_Still_Into_You.m4a",              # easy baseline
        "002_Linkin_Park_Faint.m4a",                    # easy baseline (alt)
    ]

    for fname in picks:
        fpath = preview_dir / fname
        if not fpath.exists():
            print(f"⚠️ Missing preview: {fname}")
            continue
        truth = match_truth(fpath, truths)
        if not truth:
            print(f"⚠️ No truth match for {fname}")
            continue

        y, sr = librosa.load(fpath, sr=None)
        y_harm, y_perc = librosa.effects.hpss(y)
        onset_perc = librosa.onset.onset_strength(y=y_perc, sr=sr, hop_length=ANALYSIS_HOP_LENGTH)
        onset_harm = librosa.onset.onset_strength(y=y_harm, sr=sr, hop_length=ANALYSIS_HOP_LENGTH)

        base_bpm_val, base_conf = base_bpm(y, sr)
        refined_bpm, context_meta = _refine_bpm_with_context(base_bpm_val, onset_perc, onset_harm, sr, ANALYSIS_HOP_LENGTH)

        def line(label: str, bpm: float) -> str:
            diff = bpm - truth.bpm
            return f"{label}: {bpm:7.2f} (Δ {diff:+5.2f} vs {truth.bpm})"

        print(f"\n=== {truth.artist} – {truth.title} ===")
        print(f"Notes: {truth.notes or '(none)'}")
        print(line("Base", base_bpm_val), f"conf={base_conf:.2f}")
        print(line("Refined", refined_bpm))
        if refined_bpm != base_bpm_val:
            chosen = context_meta.get("chosen", {})
            print(f"  flip meta: {chosen}")
        print(f"Truth key: {truth.key}")
        # quick key sanity (base only)
        print(f"Key match (base): {keys_match_fuzzy(truth.key, truth.key)[0]}")  # placeholder


if __name__ == "__main__":
    main()
