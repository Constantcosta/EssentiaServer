#!/usr/bin/env python3
"""Quick diagnostic to ensure Essentia-enabled key detection runs inside worker processes."""

from __future__ import annotations

import argparse
import json
import multiprocessing as mp
from pathlib import Path
import sys
from typing import Any, Dict, Optional

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.append(str(REPO_ROOT))


def _clean_candidate(candidate: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    if not isinstance(candidate, dict):
        return None
    cleaned: Dict[str, Any] = {}
    for key, value in candidate.items():
        if isinstance(value, (np.floating, float)):
            cleaned[key] = float(value)
        elif isinstance(value, (np.integer, int)):
            cleaned[key] = int(value)
        else:
            cleaned[key] = value
    return cleaned


def _worker(queue: mp.Queue, seconds: float, freq: float):
    from backend.server import processing  # noqa: F401 (ensures configure_key_detection runs)
    from backend.analysis.key_detection import detect_global_key

    sr = 22050
    total_samples = max(1, int(sr * max(seconds, 0.5)))
    t = np.linspace(0, seconds, total_samples, endpoint=False, dtype=np.float32)
    y = 0.25 * np.sin(2 * np.pi * freq * t).astype(np.float32)
    result = detect_global_key(y, sr)
    payload = {
        "has_essentia": "essentia" in result,
        "key_source": result.get("key_source"),
        "score_sources": sorted(
            {
                str(entry.get("source"))
                for entry in result.get("scores", [])
                if isinstance(entry, dict) and entry.get("source")
            }
        ),
        "essentia": _clean_candidate(result.get("essentia")),
        "essentia_edm": _clean_candidate(result.get("essentia_edm")),
    }
    queue.put(payload)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=float, default=2.0, help="Duration of the synthetic tone (seconds).")
    parser.add_argument("--freq", type=float, default=440.0, help="Frequency of the synthetic tone (Hz).")
    args = parser.parse_args()

    ctx = mp.get_context("spawn")
    queue: mp.Queue = ctx.Queue()
    proc = ctx.Process(target=_worker, args=(queue, args.seconds, args.freq))
    proc.start()
    try:
        payload = queue.get(timeout=30)
    finally:
        proc.join(timeout=5)
    print(json.dumps(payload, indent=2))
    if not payload.get("has_essentia"):
        print("⚠️ Essentia candidate missing inside worker process.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
