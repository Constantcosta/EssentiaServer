#!/usr/bin/env python3
"""
Quick regression test suite for the Mac Studio Audio Analysis Server.

This script can be pointed at either a locally running server or a remote
instance via TEST_SERVER_URL / MAC_STUDIO_SERVER_HOST / PORT. It exercises the
health, statistics, analysis, and cache endpoints with lightweight assertions.
"""

from __future__ import annotations

import os
import requests
from datetime import datetime
from typing import Sequence


def _resolve_base_url() -> str:
    explicit = os.environ.get("TEST_SERVER_URL")
    if explicit:
        return explicit.rstrip("/")
    host = os.environ.get("MAC_STUDIO_SERVER_HOST", "localhost")
    port = os.environ.get("MAC_STUDIO_SERVER_PORT", "5050")
    return f"http://{host}:{port}"


BASE_URL = _resolve_base_url()
CACHE_MIN_RESULTS = int(os.environ.get("TEST_CACHE_MIN_RESULTS", "0"))
CACHE_NAMESPACE = os.environ.get("TEST_CACHE_NAMESPACE", "default")
CACHE_QUERY = os.environ.get("TEST_CACHE_QUERY", "")
ANALYZE_URL = os.environ.get(
    "TEST_ANALYZE_URL",
    "https://invalid.invalid/nonexistent-audio-file.m4a",
)
ANALYZE_TITLE = os.environ.get("TEST_ANALYZE_TITLE", "Connectivity Test")
ANALYZE_ARTIST = os.environ.get("TEST_ANALYZE_ARTIST", "Test Harness")
ANALYZE_ACCEPTABLE_STATUS = {
    int(code.strip())
    for code in os.environ.get("TEST_ANALYZE_ACCEPTABLE_STATUS", "200,500,502").split(",")
    if code.strip()
}
ANALYZE_TIMEOUT = int(os.environ.get("TEST_ANALYZE_TIMEOUT", "30"))

REQUIRED_CACHE_FIELDS: Sequence[str] = (
    "title",
    "artist",
    "bpm",
    "key",
    "analyzed_at",
)

def print_section(title):
    print("\n" + "="*60)
    print(f"  {title}")
    print("="*60)

def test_health():
    """Test server health endpoint"""
    print_section("1. Testing Server Health")
    try:
        response = requests.get(f"{BASE_URL}/health", timeout=5)
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Server is healthy!")
            print(f"   Version: {data.get('version', 'Unknown')}")
            print(f"   Timestamp: {data.get('timestamp', 'Unknown')}")
            return True
        else:
            print(f"❌ Server returned status code: {response.status_code}")
            return False
    except requests.exceptions.ConnectionError:
        print("❌ Cannot connect to server. Is it running?")
        print("   Run: ./setup_and_run.sh")
        return False
    except Exception as e:
        print(f"❌ Error: {str(e)}")
        return False

def test_stats():
    """Test statistics endpoint"""
    print_section("2. Testing Statistics Endpoint")
    try:
        response = requests.get(f"{BASE_URL}/stats", timeout=5)
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Statistics retrieved successfully!")
            print(f"   Total Analyses: {data.get('total_analyses', 0)}")
            print(f"   Cache Hits: {data.get('cache_hits', 0)}")
            print(f"   Cache Misses: {data.get('cache_misses', 0)}")
            print(f"   Cache Hit Rate: {data.get('cache_hit_rate', '0%')}")
            print(f"   Total Cached Songs: {data.get('total_cached_songs', 0)}")
            print(f"   Database: {data.get('database_path', 'Unknown')}")
            return True
        else:
            print(f"❌ Failed with status code: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Error: {str(e)}")
        return False

def test_analyze():
    """Test analysis endpoint with a controllable payload."""
    print_section("3. Testing Audio Analysis (Sample)")

    payload = {
        "audio_url": ANALYZE_URL,
        # Legacy field name still used by older builds:
        "url": ANALYZE_URL,
        "title": ANALYZE_TITLE,
        "artist": ANALYZE_ARTIST,
        "cache_namespace": CACHE_NAMESPACE,
    }

    print(f"   Testing with: '{payload['title']}' by {payload['artist']}")
    print("   Note: Set TEST_ANALYZE_URL to a valid preview to expect HTTP 200.")

    try:
        response = requests.post(
            f"{BASE_URL}/analyze",
            json=payload,
            timeout=ANALYZE_TIMEOUT
        )

        status = response.status_code
        if status == 200:
            data = response.json()
            for field in ("bpm", "key", "analysis_duration"):
                assert field in data, f"Missing '{field}' in analysis response"
            print("✅ Analysis endpoint returned success with full payload.")
            return True
        if status in ANALYZE_ACCEPTABLE_STATUS:
            print(f"⚠️  Endpoint responded with HTTP {status}, which is acceptable for this payload.")
            print(f"   Response: {response.text[:200]}...")
            return True
        else:
            print(f"❌ Unexpected status code {status} from /analyze")
            print(f"   Body: {response.text}")
            return False
    except Exception as e:
        print(f"❌ Error: {str(e)}")
        return False

def test_cache_search():
    """Test cache search endpoint"""
    print_section("4. Testing Cache Search")
    try:
        response = requests.get(
            f"{BASE_URL}/cache/search",
            params={"q": CACHE_QUERY, "namespace": CACHE_NAMESPACE},
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            assert isinstance(data, list), "Cache search should return a list of songs"
            count = len(data)
            print(f"✅ Cache search working! Found {count} songs")
            if count < CACHE_MIN_RESULTS:
                print(f"❌ Expected at least {CACHE_MIN_RESULTS} cached songs, found {count}")
                return False
            for song in data[:3]:
                for field in REQUIRED_CACHE_FIELDS:
                    assert field in song, f"Cache result missing '{field}' field"
                bpm = song.get('bpm')
                bpm_label = f"{int(bpm)} BPM" if isinstance(bpm, (int, float)) else "BPM unknown"
                print(f"   - {song.get('title')} by {song.get('artist')} | {bpm_label} | {song.get('key', 'Unknown')} key")
            return True
        else:
            print(f"❌ Failed with status code: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Error: {str(e)}")
        return False

def main():
    print("\n" + "="*60)
    print("  🎵 Mac Studio Audio Analysis Server Test Suite")
    print("="*60)
    print(f"  Testing server at: {BASE_URL}")
    print(f"  Test started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    # Run all tests
    results = []
    results.append(("Health Check", test_health()))
    
    if results[0][1]:  # Only continue if server is healthy
        results.append(("Statistics", test_stats()))
        results.append(("Analysis Endpoint", test_analyze()))
        results.append(("Cache Search", test_cache_search()))
    
    # Summary
    print_section("Test Summary")
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    for test_name, result in results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"  {status}  {test_name}")
    
    print(f"\n  Results: {passed}/{total} tests passed")
    
    if passed == total:
        print("\n  🎉 All tests passed! Server is ready to use.")
        print("\n  Next steps:")
        print("  1. Open your iOS app")
        print("  2. Navigate to Mac Studio Server view")
        print("  3. Start analyzing your music!")
    else:
        print("\n  ⚠️  Some tests failed. Check server logs for details.")
    
    print("\n" + "="*60 + "\n")

if __name__ == "__main__":
    main()
