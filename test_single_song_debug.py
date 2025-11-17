#!/usr/bin/env python3
"""Quick test to check BPM and key detection with debug logging."""
import sys
import logging

# Setup path
sys.path.insert(0, "/Users/costasconstantinou/Documents/GitHub/EssentiaServer")

# Apply scipy compatibility shim
from backend.server.scipy_compat import ensure_hann_patch
ensure_hann_patch()

# Setup logging to see DEBUG messages
logging.basicConfig(
    level=logging.DEBUG,
    format='%(levelname)s - %(name)s - %(message)s'
)

# Import after logging setup
import librosa
from backend.analysis.pipeline_core import perform_audio_analysis

# Test a simple song - Prisoner by Miley Cyrus feat. Dua Lipa
audio_path = "/Users/costasconstantinou/Documents/GitHub/EssentiaServer/Test files/preview/Prisoner (feat. Dua Lipa).mp3"

print("="*80)
print(f"Testing: {audio_path}")
print("="*80)

try:
    y, sr = librosa.load(audio_path, sr=22050, mono=True)
    print(f"✅ Loaded {len(y)/sr:.1f}s audio at {sr}Hz\n")
    
    print("Running analysis with debug logging...\n")
    result = perform_audio_analysis(y, sr, "Prisoner (feat. Dua Lipa)", "Miley Cyrus")
    
    print("\n" + "="*80)
    print("RESULTS:")
    print("="*80)
    print(f"BPM: {result['bpm']:.2f} (confidence: {result['bpm_confidence']:.2f})")
    print(f"Key: {result['key']} (confidence: {result['key_confidence']:.2f})")
    print(f"Key Source: {result.get('key_details', {}).get('key_source', 'unknown')}")
    print(f"Energy: {result['energy']:.4f}")
    print(f"Duration: {result['analysis_duration']:.2f}s")
    print("="*80)
    
except FileNotFoundError:
    print(f"❌ File not found: {audio_path}")
    print("\nTry one of these instead:")
    import os
    preview_dir = "/Users/costasconstantinou/Documents/GitHub/EssentiaServer/Test files/preview"
    if os.path.exists(preview_dir):
        files = [f for f in os.listdir(preview_dir) if f.endswith('.mp3')][:5]
        for f in files:
            print(f"  - {f}")
except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()
