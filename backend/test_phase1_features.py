#!/usr/bin/env python3
"""
Test Phase 1 advanced audio analysis features
"""

import sys
import os

# Add backend to path
sys.path.insert(0, os.path.dirname(__file__))

# Import the analysis functions
from analyze_server import (
    detect_time_signature,
    estimate_valence_and_mood,
    calculate_loudness_and_dynamics,
    detect_silence_ratio
)

import numpy as np
import librosa

def test_phase1_features():
    """Test all Phase 1 features with synthetic audio"""
    print("=" * 70)
    print("  🧪 Testing Phase 1 Advanced Features")
    print("=" * 70)
    
    # Create synthetic test audio (440 Hz sine wave - A4 note)
    sr = 22050
    duration = 5  # seconds
    t = np.linspace(0, duration, int(sr * duration))
    
    # Generate a simple melody with varying amplitude
    frequency = 440  # A4
    y = 0.5 * np.sin(2 * np.pi * frequency * t)
    
    # Add some amplitude variation (dynamics)
    envelope = 0.3 + 0.7 * np.sin(2 * np.pi * 0.5 * t)
    y = y * envelope
    
    print("\n1. Testing Time Signature Detection")
    print("-" * 70)
    # Get beats for time signature detection
    tempo, beats = librosa.beat.beat_track(y=y, sr=sr)
    time_sig = detect_time_signature(beats, sr)
    print(f"   ✓ Detected time signature: {time_sig}")
    print(f"   ✓ Number of beats detected: {len(beats)}")
    
    print("\n2. Testing Valence and Mood Estimation")
    print("-" * 70)
    # Test with different parameters
    test_cases = [
        (120, 0, "Major", "fast major"),
        (80, 9, "Minor", "slow minor"),
        (140, 2, "Major", "energetic"),
    ]
    
    for tempo, key_idx, mode, description in test_cases:
        chroma_sums = np.random.rand(12)  # Synthetic chroma
        chroma_sums[key_idx] = 2.0  # Make one key dominant
        energy = 0.6
        
        valence, mood = estimate_valence_and_mood(tempo, key_idx, mode, chroma_sums, energy)
        print(f"   ✓ {description}: valence={valence:.2f}, mood={mood}")
    
    print("\n3. Testing Loudness and Dynamic Range")
    print("-" * 70)
    loudness, dynamic_range = calculate_loudness_and_dynamics(y, sr)
    print(f"   ✓ Loudness: {loudness:.2f} dB")
    print(f"   ✓ Dynamic range: {dynamic_range:.2f} dB")
    print(f"   ✓ Dynamic range is positive: {dynamic_range > 0}")
    
    print("\n4. Testing Silence Detection")
    print("-" * 70)
    silence_ratio = detect_silence_ratio(y, sr)
    print(f"   ✓ Silence ratio: {silence_ratio:.1%}")
    print(f"   ✓ Reasonable silence ratio: {0 <= silence_ratio <= 1}")
    
    # Test with actual silent audio
    y_silent = np.zeros(sr * 2)
    silence_ratio_silent = detect_silence_ratio(y_silent, sr)
    print(f"   ✓ Silent audio detection: {silence_ratio_silent:.1%} (should be ~100%)")
    
    print("\n" + "=" * 70)
    print("  ✅ All Phase 1 features tested successfully!")
    print("=" * 70)
    
    # Validation
    assert time_sig in ["3/4", "4/4", "5/4", "6/8"], "Invalid time signature"
    assert 0 <= valence <= 1, "Valence out of range"
    assert mood in ["energetic", "happy", "neutral", "tense", "melancholic"], "Invalid mood"
    assert dynamic_range > 0, "Dynamic range should be positive"
    assert 0 <= silence_ratio <= 1, "Silence ratio out of range"
    assert silence_ratio_silent > 0.9, "Silent audio not detected"
    
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
