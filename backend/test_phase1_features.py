#!/usr/bin/env python3
"""
Test Phase 1 advanced audio analysis features
"""

import sys
from pathlib import Path
from typing import Sequence, Tuple

# Ensure repository root is on sys.path so backend.* modules resolve
BACKEND_DIR = Path(__file__).resolve().parent
REPO_ROOT = BACKEND_DIR.parent
sys.path.insert(0, str(REPO_ROOT))

import numpy as np
import librosa
from librosa.util import normalize

from backend.server.scipy_compat import ensure_hann_patch
ensure_hann_patch()

# Import the analysis functions directly from the feature module
from backend.analysis.features import (
    calculate_loudness_and_dynamics,
    detect_silence_ratio,
    detect_time_signature,
    estimate_valence_and_mood,
)

RNG = np.random.default_rng(42)
SR = 22050
CLICK_INTERVAL_SECONDS = 0.5  # 120 BPM click track (4/4 expectation)


def _synthesize_test_audio(duration_seconds: float = 8.0) -> Tuple[np.ndarray, int]:
    """Create a deterministic waveform with both tonal and percussive content."""
    samples = int(SR * duration_seconds)
    t = np.linspace(0, duration_seconds, samples, endpoint=False)
    melodic = 0.4 * np.sin(2 * np.pi * 440 * t)  # A4 bed
    envelope = 0.4 + 0.6 * np.sin(2 * np.pi * 0.25 * t)  # slow dynamics variation
    melodic *= envelope
    beat_times = np.arange(0, duration_seconds, CLICK_INTERVAL_SECONDS)
    clicks = librosa.clicks(times=beat_times, sr=SR, length=samples, click_duration=0.03, click_freq=2000)
    signal = melodic + 0.2 * clicks
    return normalize(signal), SR


def _deterministic_chroma(dominant_index: int) -> np.ndarray:
    chroma = np.full(12, 0.1)
    chroma[dominant_index % 12] = 2.0
    chroma[(dominant_index + 7) % 12] = 0.6  # add a perfect fifth to mimic musical content
    return chroma


def _assert_mood(expectation: str, actual: str):
    assert expectation == actual, f"Expected mood '{expectation}' but received '{actual}'"


def test_phase1_features():
    """Test all Phase 1 features with deterministic synthetic audio."""
    print("=" * 70)
    print("  🧪 Testing Phase 1 Advanced Features")
    print("=" * 70)

    y, sr = _synthesize_test_audio()

    print("\n1. Testing Time Signature Detection")
    print("-" * 70)
    tempo, beats = librosa.beat.beat_track(y=y, sr=sr)
    assert len(beats) >= 8, f"Beat tracker returned insufficient beats ({len(beats)}) for analysis"
    time_sig = detect_time_signature(beats, sr)
    print(f"   ✓ Detected time signature: {time_sig} (tempo estimate {tempo:.1f} BPM)")

    print("\n2. Testing Valence and Mood Estimation")
    print("-" * 70)
    # Updated expectations to match improved algorithm
    # Mode is now a string ("Major" or "Minor") not an integer
    mood_expectations: Sequence[Tuple[str, dict]] = [
        (
            "✨ Euphoric",  # Changed: improved algorithm produces higher valence for major up-tempo
            {"tempo": 112, "key_idx": 0, "mode": "Major", "energy": 0.45, "description": "Major up-tempo"},
        ),
        (
            "😌 Calm",
            {"tempo": 68, "key_idx": 7, "mode": "Minor", "energy": 0.2, "description": "Minor ballad"},
        ),
        (
            "✨ Euphoric",
            {"tempo": 138, "key_idx": 7, "mode": "Major", "energy": 0.95, "description": "Peak-time anthem"},
        ),
    ]
    last_valence = None
    last_mood = None
    for expected_mood, params in mood_expectations:
        chroma = _deterministic_chroma(params["key_idx"])
        # Updated to pass None for new optional parameters (pitch_features, spectral_rolloff)
        valence, mood = estimate_valence_and_mood(
            params["tempo"],
            params["key_idx"],
            params["mode"],
            chroma,
            params["energy"],
            pitch_features=None,
            spectral_rolloff=None,
        )
        print(f"   ✓ {params['description']}: valence={valence:.2f}, mood={mood}")
        _assert_mood(expected_mood, mood)
        assert 0.0 <= valence <= 1.0, "Valence outside normalized range"
        last_valence, last_mood = valence, mood

    print("\n3. Testing Loudness and Dynamic Range")
    print("-" * 70)
    loudness, dynamic_range = calculate_loudness_and_dynamics(y, sr)
    print(f"   ✓ Loudness: {loudness:.2f} dB")
    print(f"   ✓ Dynamic range: {dynamic_range:.2f} dB")
    assert dynamic_range > 0.0, "Dynamic range should be positive for varying envelope"

    print("\n4. Testing Silence Detection")
    print("-" * 70)
    silence_ratio = detect_silence_ratio(y, sr)
    print(f"   ✓ Silence ratio (active signal): {silence_ratio:.1%}")
    assert 0.0 <= silence_ratio <= 1.0, "Silence ratio must be normalized"

    silence_duration_seconds = 2
    y_silent = np.zeros(silence_duration_seconds * sr)
    frame_rms = librosa.feature.rms(
        y=y_silent,
        frame_length=2048,
        hop_length=512,
    )[0]
    frame_rms_db = librosa.amplitude_to_db(frame_rms + 1e-12, ref=1.0)
    silence_ratio_silent = detect_silence_ratio(y_silent, sr, frame_rms_db=frame_rms_db)
    print(f"   ✓ Silent audio detection (zero input): {silence_ratio_silent:.1%}")
    assert silence_ratio_silent > 0.99, "Silent buffer should be ~100% silent when using absolute dB reference"

    empty_signal_ratio = detect_silence_ratio(np.array([]), sr)
    print(f"   ✓ Empty buffer detection: {empty_signal_ratio:.1%}")
    assert empty_signal_ratio == 1.0, "Empty array should be treated as fully silent"

    print("\n" + "=" * 70)
    print("  ✅ All Phase 1 features tested successfully!")
    print("=" * 70)

    assert time_sig in ["3/4", "4/4", "5/4", "6/8"], f"Unexpected time signature result: {time_sig}"
    assert last_valence is not None and last_mood is not None
    print("\n✅ All validations passed!\n")

if __name__ == '__main__':
    try:
        test_phase1_features()
    except ImportError as e:
        print(f"❌ Import error: {e}")
        print("   Make sure librosa and numpy are installed:")
        print("   pip install librosa numpy")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
