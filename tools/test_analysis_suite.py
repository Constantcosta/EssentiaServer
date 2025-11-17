"""
Quick Test Suite for Audio Analysis Pipeline
Allows rapid iteration without full GUI calibration workflow.

Usage:
    python tools/test_analysis_pipeline.py --single    # Test single song
    python tools/test_analysis_pipeline.py --batch     # Test 6-song batch
    python tools/test_analysis_pipeline.py --full      # Test full 12-song calibration
    python tools/test_analysis_pipeline.py --timeout   # Test timeout protection
    python tools/test_analysis_pipeline.py --all       # Run all tests
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, List

import requests

from test_analysis_utils import (
    Colors,
    print_error,
    print_header,
    print_info,
    print_success,
    print_warning,
    save_results_to_csv,
)
from test_analysis_suite_tests import TestErrorTimeoutMixin

# Add backend to path
sys.path.insert(0, str(Path(__file__).parent.parent / "backend"))

class AnalysisTestSuite(TestErrorTimeoutMixin):
    def __init__(
        self,
        base_url: str = "http://127.0.0.1:5050",
        *,
        force_reanalyze: bool = True,
        cache_namespace: str = "gui-tests",
    ):
        self.base_url = base_url
        self.force_reanalyze = force_reanalyze
        self.cache_namespace = cache_namespace
        self.test_songs = self._load_test_songs()
        self.all_results = []  # Store all results for CSV export
        if self.force_reanalyze:
            print_info("Cache bypass enabled: forcing re-analysis for every song")
        else:
            print_info("Cache usage enabled: reusing previous analysis results when available")

    def _build_headers(self, title: str, artist: str) -> Dict[str, str]:
        headers = {
            'X-Song-Title': title,
            'X-Song-Artist': artist,
            'Content-Type': 'application/octet-stream',
        }
        if self.force_reanalyze:
            headers['X-Force-Reanalyze'] = '1'
        if self.cache_namespace:
            headers['X-Cache-Namespace'] = self.cache_namespace
        return headers
        
    def _load_test_songs(self) -> List[Dict[str, str]]:
        """Load test songs from local files - previews and full songs."""
        import glob
        import os
        
        repo_root = Path(__file__).parent.parent
        
        # Load preview files (30-second clips, ~1MB each)
        preview_dir = repo_root / "Test files" / "preview_samples"
        preview_files = sorted(glob.glob(str(preview_dir / "*.m4a")))[:12]
        
        # Load full-length problem files (3-8MB each)
        full_dir = repo_root / "Test files" / "problem chiles"
        full_files = sorted(glob.glob(str(full_dir / "*.mp3")))[:12]
        
        # Create test song entries
        self.preview_songs = []
        for i, filepath in enumerate(preview_files, 1):
            filename = os.path.basename(filepath)
            # Parse title from filename (format: "01_Artist_Title.m4a")
            parts = filename.replace('.m4a', '').split('_', 2)
            title = parts[2] if len(parts) > 2 else f"Preview {i}"
            artist = parts[1] if len(parts) > 1 else "Unknown"
            
            self.preview_songs.append({
                'title': title,
                'artist': artist,
                'file_path': filepath,
                'type': 'preview'
            })
        
        self.full_songs = []
        for i, filepath in enumerate(full_files, 1):
            filename = os.path.basename(filepath)
            # Clean up filename for title
            title = filename.replace('.mp3', '').replace('[SPOTDOWNLOADER.COM] ', '').replace('SpotiDown.App - ', '')
            
            self.full_songs.append({
                'title': title,
                'artist': 'Various',
                'file_path': filepath,
                'type': 'full'
            })
        
        print_info(f"Loaded {len(self.preview_songs)} preview files and {len(self.full_songs)} full-length files")
        
        # Return combined list for backward compatibility
        return self.preview_songs + self.full_songs
    
    def check_server_health(self) -> bool:
        """Check if server is running and healthy."""
        print_header("Server Health Check")
        
        try:
            response = requests.get(f"{self.base_url}/health", timeout=5)
            if response.status_code == 200:
                data = response.json()
                print_success(f"Server is healthy: {data.get('status', 'unknown')}")
                return True
            else:
                print_error(f"Server returned status code: {response.status_code}")
                return False
        except requests.exceptions.ConnectionError:
            print_error("Cannot connect to server. Is it running?")
            print_info("Start server with: .venv/bin/python backend/analyze_server.py &")
            return False
        except Exception as e:
            print_error(f"Health check failed: {e}")
            return False
    
    def get_diagnostics(self) -> Dict[str, Any]:
        """Get server diagnostics."""
        print_header("Server Diagnostics")
        
        try:
            response = requests.get(f"{self.base_url}/diagnostics", timeout=5)
            data = response.json()
            
            print_info(f"Workers: {data.get('worker_info', {}).get('worker_count', 'unknown')}")
            print_info(f"Sample Rate: {data.get('analysis_config', {}).get('sample_rate', 'unknown')} Hz")
            print_info(f"Chunk Size: {data.get('analysis_config', {}).get('chunk_analysis_seconds', 'unknown')} seconds")
            print_info(f"Flask Threaded: {data.get('server_info', {}).get('threaded', 'unknown')}")
            print_info(f"Cache Status: {data.get('cache_info', {}).get('status', 'unknown')}")
            
            return data
        except Exception as e:
            print_error(f"Failed to get diagnostics: {e}")
            return {}
    
    def test_single_song(self, use_preview: bool = True) -> bool:
        """Test analyzing a single song."""
        song_type = "preview" if use_preview else "full-length"
        print_header(f"Test: Single Song Analysis ({song_type})")
        
        songs = self.preview_songs if use_preview else self.full_songs
        if not songs:
            print_error(f"No {song_type} test songs available")
            return False
        
        song = songs[0]
        print_info(f"Testing: {song['title']} by {song['artist']}")
        print_info(f"File: {Path(song['file_path']).name}")
        
        start_time = time.time()
        
        try:
            # Read file and send as binary data
            with open(song['file_path'], 'rb') as f:
                audio_data = f.read()
            
            response = requests.post(
                f"{self.base_url}/analyze_data",
                data=audio_data,
                headers=self._build_headers(song['title'], song['artist']),
                timeout=130  # Slightly more than server's 120s timeout
            )
            
            duration = time.time() - start_time
            
            if response.status_code == 200:
                data = response.json()
                print_success(f"Analysis completed in {duration:.2f}s")
                
                # Show detailed results
                print("\n" + Colors.BOLD + "Analysis Results:" + Colors.RESET)
                print(f"  BPM:          {data.get('bpm', 'N/A')}")
                print(f"  Key:          {data.get('key', 'N/A')}")
                print(f"  Energy:       {data.get('energy', 'N/A')}")
                print(f"  Danceability: {data.get('danceability', 'N/A')}")
                print(f"  Valence:      {data.get('valence', 'N/A')}")
                print(f"  Acousticness: {data.get('acousticness', 'N/A')}")
                print()
                
                # Check for expected keys in response
                expected_keys = ['bpm', 'key', 'energy', 'danceability']
                missing_keys = [k for k in expected_keys if k not in data]
                
                if missing_keys:
                    print_warning(f"Missing expected keys: {missing_keys}")
                else:
                    print_success("All expected keys present in response")
                
                return True
                
            elif response.status_code == 504:
                print_error(f"Analysis timed out after {duration:.2f}s")
                print_info(f"Response: {response.json()}")
                return False
            else:
                print_error(f"Analysis failed with status {response.status_code}")
                print_info(f"Response: {response.text[:500]}")
                return False
                
        except requests.exceptions.Timeout:
            duration = time.time() - start_time
            print_error(f"Request timed out after {duration:.2f}s")
            return False
        except Exception as e:
            duration = time.time() - start_time
            print_error(f"Analysis failed after {duration:.2f}s: {e}")
            return False
    
    def test_batch_analysis(self, batch_size: int = 6, use_preview: bool = True, test_name: str = None) -> bool:
        """Test analyzing a batch of songs in parallel."""
        song_type = "preview" if use_preview else "full-length"
        print_header(f"Test: {batch_size}-Song Batch Analysis ({song_type})")
        
        songs = self.preview_songs if use_preview else self.full_songs
        if len(songs) < batch_size:
            print_error(f"Need at least {batch_size} test songs, only have {len(songs)}")
            return False
        
        batch = songs[:batch_size]
        print_info(f"Testing parallel analysis of {batch_size} {song_type} songs...")
        
        start_time = time.time()
        
        def analyze_song(song):
            song_start = time.time()
            try:
                with open(song['file_path'], 'rb') as f:
                    audio_data = f.read()
                
                response = requests.post(
                    f"{self.base_url}/analyze_data",
                    data=audio_data,
                    headers=self._build_headers(song['title'], song['artist']),
                    timeout=130
                )
                duration = time.time() - song_start
                return {
                    'success': response.status_code == 200,
                    'status_code': response.status_code,
                    'song': song['title'],
                    'artist': song['artist'],
                    'file_type': song['type'],
                    'test_type': test_name or f"{batch_size} {song_type}",
                    'duration': duration,
                    'data': response.json() if response.status_code == 200 else None,
                    'error': response.text if response.status_code != 200 else None
                }
            except Exception as e:
                duration = time.time() - song_start
                return {
                    'success': False,
                    'status_code': 0,
                    'song': song['title'],
                    'artist': song['artist'],
                    'file_type': song['type'],
                    'test_type': test_name or f"{batch_size} {song_type}",
                    'duration': duration,
                    'data': None,
                    'error': str(e)
                }
        
        # Parallel requests (simulates Swift TaskGroup)
        with concurrent.futures.ThreadPoolExecutor(max_workers=batch_size) as executor:
            results = list(executor.map(analyze_song, batch))
        
        # Store results for CSV export
        self.all_results.extend(results)
        
        duration = time.time() - start_time
        
        successes = sum(1 for r in results if r['success'])
        failures = batch_size - successes
        
        print_info(f"Batch completed in {duration:.2f}s")
        print_success(f"Successful: {successes}/{batch_size}")
        
        # Show analysis results for each song
        print("\n" + Colors.BOLD + "Analysis Results:" + Colors.RESET)
        for i, result in enumerate(results, 1):
            if result['success'] and result['data']:
                data = result['data']
                bpm = data.get('bpm', 'N/A')
                key = data.get('key', 'N/A')
                energy = data.get('energy', 'N/A')
                danceability = data.get('danceability', 'N/A')
                print(f"  {i}. {result['song'][:40]:40} | BPM: {bpm:>6} | Key: {key:>4} | Energy: {energy:>5} | Dance: {danceability:>5}")
            else:
                print_error(f"  {i}. {result['song'][:40]:40} | FAILED")
        print()
        
        if failures > 0:
            print_error(f"Failed: {failures}/{batch_size}")
            for result in results:
                if not result['success']:
                    print_error(f"  - {result['song']}: {result['error'][:100]}")
        
        # Performance check
        expected_max_time = batch_size * 1.5  # ~1s per song with some overhead
        if duration > expected_max_time:
            print_warning(f"Batch took longer than expected ({expected_max_time:.1f}s)")
            print_warning("This suggests requests may be queued instead of parallel")
        else:
            print_success(f"Batch performance good (< {expected_max_time:.1f}s)")
        
        return successes == batch_size
    
    def test_full_calibration(self, use_preview: bool = True) -> bool:
        """Test full 12-song calibration workflow (2 batches of 6)."""
        song_type = "preview" if use_preview else "full-length"
        print_header(f"Test: Full 12-Song Calibration ({song_type})")
        
        songs = self.preview_songs if use_preview else self.full_songs
        if len(songs) < 12:
            print_error(f"Need at least 12 test songs, only have {len(songs)}")
            return False
        
        batch1 = songs[:6]
        batch2 = songs[6:12]
        
        print_info(f"Testing 2 batches of 6 {song_type} songs (simulates full calibration)...")
        
        overall_start = time.time()
        
        # Batch 1
        print_info("\n--- Batch 1/2 ---")
        batch1_success = self._run_batch(batch1, "Batch 1")
        
        # Batch 2
        print_info("\n--- Batch 2/2 ---")
        batch2_success = self._run_batch(batch2, "Batch 2")
        
        total_duration = time.time() - overall_start
        
        print_info(f"\nTotal calibration time: {total_duration:.2f}s")
        
        # Expected times depend on song type
        if use_preview:
            # Previews: 5-10 seconds total
            if total_duration > 30:
                print_error(f"Calibration took too long! Expected 5-10s, got {total_duration:.2f}s")
                return False
            elif total_duration > 10:
                print_warning(f"Calibration slower than expected (5-10s), got {total_duration:.2f}s")
            else:
                print_success(f"Calibration performance excellent! ({total_duration:.2f}s)")
        else:
            # Full songs: expect longer (30-60 seconds for 12 full songs)
            if total_duration > 120:
                print_error(f"Calibration took too long! Expected <120s, got {total_duration:.2f}s")
                return False
            elif total_duration > 60:
                print_warning(f"Calibration slower than expected (<60s), got {total_duration:.2f}s")
            else:
                print_success(f"Calibration performance good! ({total_duration:.2f}s)")
        
        return batch1_success and batch2_success
    
    def _run_batch(self, batch: List[Dict], batch_name: str) -> bool:
        """Helper to run a single batch."""
        start_time = time.time()
        
        def analyze_song(song):
            song_start = time.time()
            try:
                with open(song['file_path'], 'rb') as f:
                    audio_data = f.read()
                
                response = requests.post(
                    f"{self.base_url}/analyze_data",
                    data=audio_data,
                    headers=self._build_headers(song['title'], song['artist']),
                    timeout=130
                )
                duration = time.time() - song_start
                return {
                    'success': response.status_code == 200,
                    'song': song['title'],
                    'artist': song['artist'],
                    'file_type': song['type'],
                    'test_type': batch_name,
                    'duration': duration,
                    'data': response.json() if response.status_code == 200 else None
                }
            except:
                duration = time.time() - song_start
                return {
                    'success': False,
                    'song': song['title'],
                    'artist': song['artist'],
                    'file_type': song['type'],
                    'test_type': batch_name,
                    'duration': duration,
                    'data': None
                }
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
            results = list(executor.map(analyze_song, batch))
        
        # Store results for CSV export
        self.all_results.extend(results)
        
        duration = time.time() - start_time
        successes = sum(1 for r in results if r['success'])
        
        print_info(f"{batch_name}: {successes}/{len(batch)} successful in {duration:.2f}s")
        
        # Show results
        for i, result in enumerate(results, 1):
            if result['success'] and result['data']:
                data = result['data']
                bpm = data.get('bpm', 'N/A')
                key = data.get('key', 'N/A')
                print(f"    {i}. {result['song'][:35]:35} | BPM: {bpm:>6} | Key: {key:>4}")
            else:
                print_error(f"    {i}. {result['song'][:35]:35} | FAILED")
        
        return successes == len(batch)
    
    def run_all_tests(self) -> bool:
        """Run all tests in sequence."""
        print_header("Running Full Test Suite")
        
        # Check server first
        if not self.check_server_health():
            return False
        
        self.get_diagnostics()
        
        # Run tests
        results = {
            'Single Song': self.test_single_song(),
            'Batch Analysis (6 songs)': self.test_batch_analysis(6),
            'Full Calibration (12 songs)': self.test_full_calibration(),
            'Error Handling': self.test_error_handling(),
            'Timeout Protection': self.test_timeout_protection()
        }
        
        # Summary
        print_header("Test Summary")
        
        passed = sum(results.values())
        total = len(results)
        
        for test_name, result in results.items():
            if result:
                print_success(f"{test_name}")
            else:
                print_error(f"{test_name}")
        
        print(f"\n{Colors.BOLD}Results: {passed}/{total} tests passed{Colors.RESET}")
        
        if passed == total:
            print_success("All tests passed! 🎉")
        else:
            print_error(f"{total - passed} test(s) failed")
        
        return passed == total
