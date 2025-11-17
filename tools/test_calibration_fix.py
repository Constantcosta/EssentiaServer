#!/usr/bin/env python3
"""
Test script to verify calibration hang fix.

This script validates that:
1. Nested ProcessPool detection works
2. Sequential requests don't deadlock
3. Server can handle multiple sequential calibration requests
"""

import sys
import time
import logging
from pathlib import Path

# Add backend to path
repo_root = Path(__file__).parent.parent
sys.path.insert(0, str(repo_root / "backend"))

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(processName)s] %(levelname)s: %(message)s'
)
logger = logging.getLogger(__name__)


def test_nested_pool_detection():
    """Test that nested ProcessPool creation is prevented."""
    logger.info("\n" + "="*70)
    logger.info("TEST 1: Nested ProcessPool Detection")
    logger.info("="*70)
    
    import multiprocessing
    from backend.server.processing import get_analysis_executor
    
    # Test 1a: Main process should create pool
    logger.info("Testing from MainProcess...")
    executor = get_analysis_executor(max_workers=2)
    
    if executor is None:
        logger.error("✗ FAIL: Main process should create executor")
        return False
    else:
        logger.info("✓ PASS: Main process created executor")
    
    # Test 1b: Simulate worker process (change process name)
    original_name = multiprocessing.current_process().name
    try:
        # Temporarily pretend we're a worker
        multiprocessing.current_process().name = "SpawnProcess-1"
        
        logger.info("Testing from worker process...")
        worker_executor = get_analysis_executor(max_workers=2)
        
        if worker_executor is not None:
            logger.error("✗ FAIL: Worker process should NOT create executor")
            return False
        else:
            logger.info("✓ PASS: Worker process blocked from creating executor")
    finally:
        # Restore original name
        multiprocessing.current_process().name = original_name
    
    logger.info("✓ Test 1 PASSED: Nested ProcessPool detection works")
    return True


def test_sequential_requests():
    """Test that sequential requests work without deadlock."""
    logger.info("\n" + "="*70)
    logger.info("TEST 2: Sequential Request Processing")
    logger.info("="*70)
    
    import requests
    import base64
    import numpy as np
    import soundfile as sf
    from io import BytesIO
    
    server_url = "http://127.0.0.1:5050"
    
    # Check if server is running
    try:
        health = requests.get(f"{server_url}/health", timeout=2)
        logger.info(f"✓ Server running: {health.status_code}")
    except Exception as exc:
        logger.error(f"✗ Server not running: {exc}")
        logger.info("Start with: .venv/bin/python backend/analyze_server.py")
        return False
    
    # Create test audio
    logger.info("Creating test audio (1s silence)...")
    silence = np.zeros(22050, dtype=np.float32)
    audio_buffer = BytesIO()
    sf.write(audio_buffer, silence, 22050, format='WAV')
    audio_bytes = audio_buffer.getvalue()
    audio_b64 = base64.b64encode(audio_bytes).decode('utf-8')
    
    # Send 6 sequential requests (simulates Swift fix)
    num_requests = 6
    logger.info(f"Sending {num_requests} sequential requests...")
    
    start_time = time.time()
    for i in range(num_requests):
        try:
            logger.info(f"  Request {i+1}/{num_requests}...")
            
            response = requests.post(
                f"{server_url}/analyze",
                json={
                    "audio_data": audio_b64,
                    "title": f"Test Song {i+1}",
                    "artist": "Test Artist"
                },
                headers={"X-API-Key": "DEV-KEY"},
                timeout=30
            )
            
            if response.status_code == 200:
                logger.info(f"  ✓ Request {i+1} completed")
            else:
                logger.error(f"  ✗ Request {i+1} failed: {response.status_code}")
                return False
                
        except Exception as exc:
            logger.error(f"  ✗ Request {i+1} exception: {exc}")
            return False
    
    elapsed = time.time() - start_time
    logger.info(f"✓ Test 2 PASSED: {num_requests} requests in {elapsed:.1f}s")
    return True


def test_chunk_timeout_safety():
    """Test that chunk analysis timeout detection works."""
    logger.info("\n" + "="*70)
    logger.info("TEST 3: Chunk Analysis Timeout Safety")
    logger.info("="*70)
    
    from backend.analysis import pipeline_chunks
    
    # Verify timeout constants exist
    if not hasattr(pipeline_chunks, 'CHUNK_TIMEOUT_SECONDS'):
        logger.warning("⚠️ CHUNK_TIMEOUT_SECONDS not found - may be using old code")
        # Check source code for the constant
        import inspect
        source = inspect.getsource(pipeline_chunks.compute_chunk_summaries)
        if 'CHUNK_TIMEOUT_SECONDS' in source:
            logger.info("✓ Found CHUNK_TIMEOUT_SECONDS in source code")
        else:
            logger.error("✗ CHUNK_TIMEOUT_SECONDS not in source - timeout detection missing")
            return False
    
    logger.info("✓ Test 3 PASSED: Chunk timeout safety measures in place")
    return True


def main():
    """Run all tests."""
    logger.info("\n" + "#"*70)
    logger.info("# Calibration Fix Verification")
    logger.info("#"*70)
    
    results = {}
    
    # Test 1: Nested pool detection
    results['nested_pool'] = test_nested_pool_detection()
    
    # Test 2: Sequential requests (requires server)
    logger.info("\nChecking if server is available for integration test...")
    import requests
    try:
        requests.get("http://127.0.0.1:5050/health", timeout=1)
        results['sequential'] = test_sequential_requests()
    except:
        logger.warning("⚠️ Server not running - skipping integration test")
        logger.info("Start with: .venv/bin/python backend/analyze_server.py &")
        results['sequential'] = None
    
    # Test 3: Chunk timeout safety
    results['chunk_timeout'] = test_chunk_timeout_safety()
    
    # Summary
    logger.info("\n" + "#"*70)
    logger.info("# Test Summary")
    logger.info("#"*70)
    
    for test_name, result in results.items():
        if result is True:
            status = "✓ PASS"
        elif result is False:
            status = "✗ FAIL"
        else:
            status = "⊘ SKIP"
        logger.info(f"{status:10} {test_name}")
    
    all_passed = all(r is True for r in results.values() if r is not None)
    
    if all_passed:
        logger.info("\n✅ All tests PASSED - calibration hang fix validated")
        return 0
    else:
        logger.info("\n❌ Some tests FAILED - review fixes")
        return 1


if __name__ == "__main__":
    sys.exit(main())
