#!/usr/bin/env python3
"""
Proof-of-concept stem probe on a single preview clip.

Loads one .m4a preview (defaults to Paramore - Still Into You),
runs the existing tempo+key detectors end-to-end, then reruns tempo on
the percussive stem and key on the harmonic stem (HPSS).

Outputs base vs stem-derived BPM/Key plus truth comparison so we can
see whether stems improve accuracy before wiring this into the server.
"""

from __future__ import annotations

import argparse
import csv
import re
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
from backend.analysis.settings import ANALYSIS_HOP_LENGTH, get_adaptive_analysis_params
from backend.analysis.analysis_context import prepare_analysis_context
from backend.analysis.tempo_detection import analyze_tempo
from backend.analysis.key_detection import KEY_NAMES, detect_global_key
from backend.analysis.features import tempo_alignment_score
from tools.key_utils import keys_match_fuzzy

ensure_hann_patch()


@dataclass
class TrackTruth:
    title: str
    artist: str
    bpm: float
    key: str
    notes: str = ""


def normalize(text: str) -> str:
    return re.sub(r"[^a-z0-9]", "", text.lower())


def load_truths(csv_path: Path) -> List[TrackTruth]:
    rows: List[TrackTruth] = []
    with csv_path.open(newline="", encoding="utf-8") as handle:
        reader = csv.reader(handle)
        header = next(reader, [])
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


def match_preview_to_truth(preview_path: Path, truths: List[TrackTruth]) -> Optional[TrackTruth]:
    stem = preview_path.stem.rsplit(".", 1)[0]
    tokens = stem.split("_", 2)
    artist = tokens[1] if len(tokens) > 1 else "unknown"
    title = tokens[2] if len(tokens) > 2 else tokens[-1] if tokens else stem
    n_artist = normalize(artist)
    n_title = normalize(title)
    candidates = [t for t in truths if normalize(t.artist) in n_artist or normalize(t.title) in n_title]
    if candidates:
        # Prefer exact title match, then artist partial
        exact_title = [t for t in candidates if normalize(t.title) == n_title]
        if exact_title:
            return exact_title[0]
        return candidates[0]
    # Fallback: loose contains
    for t in truths:
        if n_title in normalize(t.title) or normalize(t.title) in n_title:
            return t
    return None


def run_full_pass(y, sr) -> Dict[str, object]:
    """Run the stock analysis path (tempo + key) on a signal."""
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
    key_input = tempo_result.y_harmonic if tempo_result.y_harmonic.size else y
    key_meta = detect_global_key(key_input, sr, adaptive_params=adaptive)
    key_idx = key_meta.get("key_index", 0) % 12
    mode = key_meta.get("mode", "Major")
    key_label = f"{KEY_NAMES[key_idx]} {mode}"
    return {
        "bpm": float(tempo_result.bpm),
        "bpm_conf": float(tempo_result.bpm_confidence),
        "key": key_label,
        "key_conf": float(key_meta.get("confidence", 0.0) or 0.0),
    }


def periodicity_score(onset_env: np.ndarray, sr: int, hop: int, bpm: float) -> float:
    """Autocorr-based periodicity score for a target BPM on a given onset envelope."""
    if onset_env.size == 0 or bpm <= 0:
        return 0.0
    frames_per_beat = 60.0 * sr / (bpm * hop)
    if frames_per_beat < 2 or frames_per_beat > len(onset_env) * 0.6:
        return 0.0
    max_size = int(min(len(onset_env), frames_per_beat * 8))
    ac = librosa.autocorrelate(onset_env, max_size=max_size)
    if ac.size == 0 or ac.max() <= 0:
        return 0.0
    idx = int(round(frames_per_beat))
    window = ac[max(idx - 2, 0): min(idx + 3, len(ac))]
    strength = float(np.max(window)) if window.size else 0.0
    return float(np.clip(strength / ac.max(), 0.0, 1.0))


def refine_bpm_with_context(base_bpm: float, onset_perc: np.ndarray, onset_harm: np.ndarray, sr: int, hop: int) -> Dict[str, object]:
    """Evaluate half/double candidates using harmonic + percussive periodicity, like a human listener anchoring to harmony."""
    candidates = {}
    for factor in (0.5, 1.0, 1.5, 2.0):
        cand = base_bpm * factor
        per_score = periodicity_score(onset_perc, sr, hop, cand)
        harm_score = periodicity_score(onset_harm, sr, hop, cand)
        align = tempo_alignment_score(cand)
        combo = 0.45 * per_score + 0.45 * harm_score + 0.10 * align
        candidates[cand] = {
            "percussive": per_score,
            "harmonic": harm_score,
            "alignment": align,
            "score": combo,
        }
    best_bpm, best_meta = max(candidates.items(), key=lambda kv: kv[1]["score"])
    base_meta = candidates.get(base_bpm, {"score": 0.0})
    if best_bpm != base_bpm and best_meta["score"] < base_meta["score"] * 1.02:
        # If the “better” candidate is not clearly better, stick with base to avoid false flips.
        best_bpm = base_bpm
        best_meta = base_meta
    return {"best_bpm": best_bpm, "candidates": candidates, "chosen_meta": best_meta}


def compare_truth(label: str, value: str, truth: str) -> str:
    ok, reason = keys_match_fuzzy(value, truth)
    status = "MATCH" if ok else "MISS"
    return f"{label}: {value:<10} vs truth {truth:<10} → {status} ({reason})"


def analyze_preview(path: Path, truth: TrackTruth) -> Dict[str, object]:
    y, sr = librosa.load(path, sr=None)
    y_harm, y_perc = librosa.effects.hpss(y)
    onset_perc = librosa.onset.onset_strength(y=y_perc, sr=sr, hop_length=ANALYSIS_HOP_LENGTH)
    onset_harm = librosa.onset.onset_strength(y=y_harm, sr=sr, hop_length=ANALYSIS_HOP_LENGTH)

    base = run_full_pass(y, sr)
    context = refine_bpm_with_context(base["bpm"], onset_perc, onset_harm, sr, ANALYSIS_HOP_LENGTH)
    refined_bpm = context["best_bpm"]
    return {
        "file": path.name,
        "truth": truth,
        "base": base,
        "refined_bpm": refined_bpm,
        "context": context,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Stem probe on tricky BPM repertoire previews")
    parser.add_argument(
        "--preview-dir",
        type=str,
        default=str(Path.home() / "Documents" / "Git repo" / "Songwise 1" / "preview_samples_repertoire_90"),
        help="Directory containing repertoire previews",
    )
    parser.add_argument(
        "--truth-csv",
        type=str,
        default=str(REPO_ROOT / "csv" / "truth_repertoire_manual.csv"),
        help="Ground truth CSV with Notes column",
    )
    parser.add_argument(
        "--note-keywords",
        type=str,
        default="6/8;dotted;half-time;ambiguous;feel",
        help="Semicolon-separated keywords in Notes to select tricky tracks",
    )
    parser.add_argument(
        "--max-tracks",
        type=int,
        default=6,
        help="Limit number of tracks to probe",
    )
    args = parser.parse_args()

    preview_dir = Path(args.preview_dir).expanduser()
    if not preview_dir.exists():
        raise SystemExit(f"❌ Preview dir not found: {preview_dir}")
    truths = load_truths(Path(args.truth_csv))
    if not truths:
        raise SystemExit("❌ No truths loaded")
    keywords = [kw.strip().lower() for kw in args.note_keywords.split(";") if kw.strip()]

    selected: List[Tuple[Path, TrackTruth]] = []
    for path in sorted(preview_dir.glob("*.m4a")):
        truth = match_preview_to_truth(path, truths)
        if not truth:
            continue
        note_text = truth.notes.lower()
        if keywords and not any(kw in note_text for kw in keywords):
            continue
        selected.append((path, truth))
        if len(selected) >= args.max_tracks:
            break

    if not selected:
        raise SystemExit("⚠️ No previews matched note keywords; try relaxing --note-keywords or increase --max-tracks")

    for path, truth in selected:
        print(f"\n=== {truth.artist} – {truth.title} ===")
        print(f"Notes: {truth.notes or '(none)'}")
        res = analyze_preview(path, truth)
        base = res["base"]
        refined = res["refined_bpm"]

        def bpm_line(label: str, bpm: float) -> str:
            diff = bpm - truth.bpm
            return f"{label}: {bpm:6.2f} (Δ {diff:+.2f} vs {truth.bpm})"

        print("Base BPM   :", bpm_line(" ", base["bpm"]))
        print("Refined BPM:", bpm_line(" ", refined))
        if refined != base["bpm"]:
            print("  ↳ context flip:", res["context"]["candidates"][refined])
        print("Key        :", compare_truth(" ", base["key"], truth.key))


if __name__ == "__main__":
    main()
