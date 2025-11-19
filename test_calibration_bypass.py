#!/usr/bin/env python3
"""Quick test to verify BPM calibration bypass works correctly."""

from backend.analysis.calibration import load_calibration_config, apply_calibration_layer

# Load calibration config
load_calibration_config()

# Test case 1: High-confidence 144 BPM (should bypass calibration)
result_high_conf = {
    "bpm": 143.6,
    "bpm_confidence": 0.85,
    "energy": 0.75
}

print("Test 1: High-confidence 143.6 BPM (should bypass calibration)")
print(f"Before: BPM={result_high_conf['bpm']:.2f}, confidence={result_high_conf['bpm_confidence']:.2f}")
result_high_conf = apply_calibration_layer(result_high_conf)
print(f"After:  BPM={result_high_conf['bpm']:.2f}")
print(f"Expected: ~143.6 (no calibration applied)")
print()

# Test case 2: Low-confidence 143.6 BPM (should apply calibration)
result_low_conf = {
    "bpm": 143.6,
    "bpm_confidence": 0.50,
    "energy": 0.75
}

print("Test 2: Low-confidence 143.6 BPM (should apply calibration)")
print(f"Before: BPM={result_low_conf['bpm']:.2f}, confidence={result_low_conf['bpm_confidence']:.2f}")
result_low_conf = apply_calibration_layer(result_low_conf)
print(f"After:  BPM={result_low_conf['bpm']:.2f}")
print(f"Expected: ~137.0 (calibration applied: 0.7365 * 143.6 + 31.276)")
print()

# Test case 3: High-confidence 120 BPM (outside bypass range, should apply calibration)
result_120 = {
    "bpm": 120.0,
    "bpm_confidence": 0.85,
    "energy": 0.75
}

print("Test 3: High-confidence 120 BPM (outside bypass range)")
print(f"Before: BPM={result_120['bpm']:.2f}, confidence={result_120['bpm_confidence']:.2f}")
result_120 = apply_calibration_layer(result_120)
print(f"After:  BPM={result_120['bpm']:.2f}")
print(f"Expected: ~119.7 (calibration applied: 0.7365 * 120 + 31.276)")
print()

print("✅ Calibration bypass test complete!")
