#!/usr/bin/env python3
"""Quick test for The Scientist BPM detection."""

import librosa
import logging
from backend.analysis.pipeline_core import perform_audio_analysis

# Enable logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')

# Load The Scientist
audio_path = "/Users/costasconstantinou/Documents/GitHub/EssentiaServer/Test files/problem chiles/The Scientist.mp3"
print(f"Loading: {audio_path}")
y, sr = librosa.load(audio_path, sr=None)
print(f"Loaded: {len(y)/sr:.1f} seconds at {sr} Hz\n")

# Analyze
print("Running analysis...")
result = perform_audio_analysis(y, sr, "The Scientist", "Coldplay")

print(f"\n{'='*60}")
print(f"BPM: {result['bpm']:.2f}")
print(f"BPM Confidence: {result['bpm_confidence']:.2f}")
print(f"Energy: {result['energy']:.2f}")
print(f"Key: {result['key']}")
print(f"{'='*60}")
