#!/usr/bin/env python3
"""Test just the 4ever song to debug octave detection."""

import requests
import sys

def test_4ever():
    url = "http://127.0.0.1:5050/analyze_data"
    song_file = "Test files/preview_samples/07_The_Veronicas_4ever_.m4a"
    
    headers = {
        'X-Song-Title': '4ever',
        'X-Song-Artist': 'The Veronicas',
        'Content-Type': 'application/octet-stream',
        'X-Force-Reanalyze': '1',
        'X-Cache-Namespace': 'debug-test',
    }
    
    print(f"Testing: {song_file}")
    
    with open(song_file, 'rb') as f:
        audio_data = f.read()
    
    response = requests.post(url, data=audio_data, headers=headers, timeout=60)
    
    if response.status_code == 200:
        data = response.json()
        print(f"\n✅ Analysis successful")
        print(f"BPM: {data.get('bpm')} (expected: ~144)")
        print(f"Key: {data.get('key')} (expected: F Minor)")
    else:
        print(f"\n❌ Analysis failed: {response.status_code}")
        print(response.text)
        sys.exit(1)

if __name__ == "__main__":
    test_4ever()
