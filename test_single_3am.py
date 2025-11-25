#!/usr/bin/env python3
"""Test just the 3am song to debug octave detection."""

import requests
import sys

def test_3am():
    url = "http://127.0.0.1:5050/analyze_data"
    song_file = "Test files/preview_samples/06_Matchbox_20_3am.m4a"
    
    headers = {
        'X-Song-Title': '3am',
        'X-Song-Artist': 'Matchbox Twenty',
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
        print(f"BPM: {data.get('bpm')} (expected: ~108)")
        print(f"Key: {data.get('key')} (expected: G# Major)")
    else:
        print(f"\n❌ Analysis failed: {response.status_code}")
        print(response.text)
        sys.exit(1)

if __name__ == "__main__":
    test_3am()
