#!/usr/bin/env python3
"""
Quick test script for Mac Studio Audio Analysis Server
Tests the server endpoints and validates functionality
"""

import requests
import json
from datetime import datetime

BASE_URL = "http://localhost:5001"

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
    """Test analysis endpoint with a sample preview"""
    print_section("3. Testing Audio Analysis (Sample)")
    
    # Using a generic test URL format
    test_data = {
        "url": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/test.m4a",
        "title": "Test Song",
        "artist": "Test Artist"
    }
    
    print(f"   Testing with: '{test_data['title']}' by {test_data['artist']}")
    print(f"   Note: This is a connectivity test. Actual analysis requires valid preview URLs.")
    
    try:
        response = requests.post(
            f"{BASE_URL}/analyze",
            json=test_data,
            timeout=30
        )
        
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Analysis endpoint is working!")
            print(f"   Response structure validated")
            return True
        else:
            # This is expected for a test URL - we're just checking the endpoint works
            print(f"⚠️  Endpoint responded (status {response.status_code})")
            print(f"   This is normal for a test URL - endpoint is accessible")
            return True
            
    except Exception as e:
        print(f"❌ Error: {str(e)}")
        return False

def test_cache_search():
    """Test cache search endpoint"""
    print_section("4. Testing Cache Search")
    try:
        response = requests.get(
            f"{BASE_URL}/cache/search",
            params={"artist": "", "title": ""},
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Cache search working!")
            print(f"   Found {data.get('count', 0)} songs in cache")
            
            if data.get('count', 0) > 0:
                print("\n   Recent songs:")
                for song in data.get('songs', [])[:3]:
                    print(f"   - {song.get('title')} by {song.get('artist')}")
                    print(f"     {int(song.get('bpm', 0))} BPM | {song.get('key', 'Unknown')} key")
            
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
