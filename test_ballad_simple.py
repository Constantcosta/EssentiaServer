#!/usr/bin/env python3
"""Simple test to see ballad detection logs."""
import sys
import logging
import os

# Setup path
sys.path.insert(0, "/Users/costasconstantinou/Documents/GitHub/EssentiaServer")

# Apply scipy.signal.hann compatibility shim FIRST
from backend.server.scipy_compat import ensure_hann_patch
ensure_hann_patch()

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(levelname)s - %(message)s'
)

# Import after logging setup
import librosa
from backend.analysis.pipeline_core import perform_audio_analysis

# Test The Scientist
audio_path = "/Users/costasconstantinou/Documents/GitHub/EssentiaServer/Test files/problem chiles/The Scientist.mp3"

print(f"Loading: {audio_path}")
y, sr = librosa.load(audio_path, sr=22050, mono=True)
print(f"Loaded {len(y)/sr:.1f}s audio at {sr}Hz\n")

print("Running analysis...\n")
result = perform_audio_analysis(y, sr, "The Scientist", "Coldplay")

print(f"\n✅ Final BPM: {result['bpm']:.2f}")
print(f"   Energy: {result['energy']:.4f}")
