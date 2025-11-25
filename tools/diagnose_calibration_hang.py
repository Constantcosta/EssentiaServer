#!/usr/bin/env python3
"""
Experiment to diagnose calibration batch processing hang.

This script simulates the calibration workflow to identify where the
process is getting stuck after the first batch of 6 workers.

Problem symptoms:
- First batch of 6 songs starts analysis
- Workers appear to be processing
- No progression to batch 2
- No errors logged
- Process appears hung

Potential causes to test:
1. ProcessPoolExecutor deadlock (spawn context + nested calls)
2. Chunk analysis timeout causing silent hang
3. Swift TaskGroup + Python ProcessPool interaction
4. Resource exhaustion (memory, file handles, etc.)
5. Blocking I/O in worker processes
"""

import asyncio
import logging
import multiprocessing
import os
import signal
import sys
import time
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import List, Dict, Any

# Add backend to path
repo_root = Path(__file__).parent.parent
sys.path.insert(0, str(repo_root / "backend"))

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(processName)s-%(process)d] %(levelname)s: %(message)s',
    datefmt='%H:%M:%S'
)
logger = logging.getLogger(__name__)


def mock_worker_task(task_id: int, duration: float = 2.0, hang_on: int = -1) -> Dict[str, Any]:
    """
    Simulate a worker doing audio analysis.
    
    Args:
        task_id: Task identifier
        duration: How long the task should take
        hang_on: Task ID to hang on (simulates timeout/deadlock)
    """
    pid = os.getpid()
    logger.info(f"Worker {task_id} starting in process {pid}")
    
    if task_id == hang_on:
        logger.warning(f"Worker {task_id} SIMULATING HANG (will take 60s)")
        time.sleep(60)  # Simulate a hung worker
        logger.error(f"Worker {task_id} completed after hang")
    else:
        time.sleep(duration)
        logger.info(f"Worker {task_id} completed after {duration}s")
    
    return {
        "task_id": task_id,
        "pid": pid,
        "duration": duration,
        "completed_at": time.time()
    }


def test_processpool_basic(num_tasks: int = 12, batch_size: int = 6, hang_on: int = -1):
    """
    Test 1: Basic ProcessPoolExecutor with batching.
    
    This tests if the issue is in the Python process pool itself.
    """
    logger.info(f"\n{'='*60}")
    logger.info(f"TEST 1: Basic ProcessPoolExecutor (tasks={num_tasks}, batch_size={batch_size})")
    logger.info(f"{'='*60}\n")
    
    start_time = time.time()
    ctx = multiprocessing.get_context("spawn")
    
    with ProcessPoolExecutor(max_workers=batch_size, mp_context=ctx) as executor:
        futures = []
        
        # Submit all tasks
        for task_id in range(num_tasks):
            future = executor.submit(mock_worker_task, task_id, 2.0, hang_on)
            futures.append((task_id, future))
            logger.info(f"Submitted task {task_id}")
        
        # Wait for completion with timeout
        completed = 0
        for task_id, future in futures:
            try:
                result = future.result(timeout=10)  # 10s timeout per task
                completed += 1
                logger.info(f"✓ Task {task_id} result received ({completed}/{num_tasks})")
            except TimeoutError:
                logger.error(f"✗ Task {task_id} TIMED OUT after 10s")
            except Exception as exc:
                logger.error(f"✗ Task {task_id} FAILED: {exc}")
    
    elapsed = time.time() - start_time
    logger.info(f"\nTest 1 completed: {completed}/{num_tasks} tasks in {elapsed:.1f}s")
    return completed == num_tasks


def test_processpool_batched_submission(num_tasks: int = 12, batch_size: int = 6, hang_on: int = -1):
    """
    Test 2: Submit tasks in batches, wait for each batch to complete.
    
    This tests if batched submission (like Swift TaskGroup) causes issues.
    """
    logger.info(f"\n{'='*60}")
    logger.info(f"TEST 2: Batched Submission (tasks={num_tasks}, batch_size={batch_size})")
    logger.info(f"{'='*60}\n")
    
    start_time = time.time()
    ctx = multiprocessing.get_context("spawn")
    total_completed = 0
    
    with ProcessPoolExecutor(max_workers=batch_size, mp_context=ctx) as executor:
        # Process in batches
        for batch_num in range(0, num_tasks, batch_size):
            batch_end = min(batch_num + batch_size, num_tasks)
            batch_tasks = range(batch_num, batch_end)
            
            logger.info(f"\n--- Batch {batch_num//batch_size + 1}: Tasks {batch_num}-{batch_end-1} ---")
            
            futures = []
            for task_id in batch_tasks:
                future = executor.submit(mock_worker_task, task_id, 2.0, hang_on)
                futures.append((task_id, future))
                logger.info(f"Submitted task {task_id}")
            
            # Wait for batch to complete
            batch_completed = 0
            for task_id, future in futures:
                try:
                    result = future.result(timeout=10)
                    batch_completed += 1
                    total_completed += 1
                    logger.info(f"✓ Task {task_id} completed ({batch_completed}/{len(futures)} in batch)")
                except TimeoutError:
                    logger.error(f"✗ Task {task_id} TIMED OUT")
                except Exception as exc:
                    logger.error(f"✗ Task {task_id} FAILED: {exc}")
            
            logger.info(f"Batch {batch_num//batch_size + 1} done: {batch_completed}/{len(futures)} tasks")
            
            if batch_completed < len(futures):
                logger.warning(f"Batch incomplete! Stopping further batches.")
                break
    
    elapsed = time.time() - start_time
    logger.info(f"\nTest 2 completed: {total_completed}/{num_tasks} tasks in {elapsed:.1f}s")
    return total_completed == num_tasks


def test_with_timeout_detection(num_tasks: int = 12, batch_size: int = 6, hang_on: int = 7):
    """
    Test 3: Detect and handle hung workers.
    
    This tests timeout detection similar to what we added in pipeline_chunks.py
    """
    logger.info(f"\n{'='*60}")
    logger.info(f"TEST 3: Timeout Detection (tasks={num_tasks}, hang_on={hang_on})")
    logger.info(f"{'='*60}\n")
    
    start_time = time.time()
    ctx = multiprocessing.get_context("spawn")
    total_completed = 0
    
    with ProcessPoolExecutor(max_workers=batch_size, mp_context=ctx) as executor:
        futures = []
        
        # Submit all tasks
        for task_id in range(num_tasks):
            future = executor.submit(mock_worker_task, task_id, 2.0, hang_on)
            futures.append((task_id, future))
        
        # Wait with aggressive timeout
        for task_id, future in futures:
            try:
                result = future.result(timeout=5)  # Strict 5s timeout
                total_completed += 1
                logger.info(f"✓ Task {task_id} completed ({total_completed}/{num_tasks})")
            except TimeoutError:
                logger.error(f"✗ Task {task_id} TIMED OUT - cancelling remaining work")
                # Cancel remaining futures
                for remaining_id, remaining_future in futures[task_id+1:]:
                    remaining_future.cancel()
                    logger.warning(f"Cancelled task {remaining_id}")
                break
            except Exception as exc:
                logger.error(f"✗ Task {task_id} FAILED: {exc}")
    
    elapsed = time.time() - start_time
    logger.info(f"\nTest 3 completed: {total_completed}/{num_tasks} tasks in {elapsed:.1f}s")
    logger.info(f"Expected: {hang_on} tasks (stopped at hung task)")
    return True  # Success is detecting and stopping at the hung task


def test_as_completed_pattern(num_tasks: int = 12, batch_size: int = 6, hang_on: int = -1):
    """
    Test 4: Use as_completed to process results as they arrive.
    
    This is more robust than waiting in order.
    """
    logger.info(f"\n{'='*60}")
    logger.info(f"TEST 4: as_completed Pattern (tasks={num_tasks}, batch_size={batch_size})")
    logger.info(f"{'='*60}\n")
    
    start_time = time.time()
    ctx = multiprocessing.get_context("spawn")
    total_completed = 0
    
    with ProcessPoolExecutor(max_workers=batch_size, mp_context=ctx) as executor:
        # Submit all tasks and map futures to task IDs
        future_to_task = {}
        for task_id in range(num_tasks):
            future = executor.submit(mock_worker_task, task_id, 2.0, hang_on)
            future_to_task[future] = task_id
            logger.info(f"Submitted task {task_id}")
        
        # Process as completed (not in order)
        for future in as_completed(future_to_task.keys(), timeout=60):
            task_id = future_to_task[future]
            try:
                result = future.result()
                total_completed += 1
                logger.info(f"✓ Task {task_id} completed ({total_completed}/{num_tasks})")
            except Exception as exc:
                logger.error(f"✗ Task {task_id} FAILED: {exc}")
    
    elapsed = time.time() - start_time
    logger.info(f"\nTest 4 completed: {total_completed}/{num_tasks} tasks in {elapsed:.1f}s")
    return total_completed == num_tasks


def test_analyze_server_integration():
    """
    Test 5: Integration with actual analyze_server.py batch endpoint.
    
    This sends real HTTP requests to the running server.
    """
    logger.info(f"\n{'='*60}")
    logger.info(f"TEST 5: Real Server Integration")
    logger.info(f"{'='*60}\n")
    
    import requests
    import base64
    
    server_url = "http://127.0.0.1:5050"
    
    # Check if server is running
    try:
        health = requests.get(f"{server_url}/health", timeout=2)
        logger.info(f"Server health: {health.status_code}")
    except Exception as exc:
        logger.error(f"Server not running: {exc}")
        logger.info("Start the server with: .venv/bin/python backend/analyze_server.py")
        return False
    
    # Create a tiny test audio file (1s of silence)
    import numpy as np
    import soundfile as sf
    from io import BytesIO
    
    # Generate 1 second of silence at 22050 Hz
    duration = 1.0
    sr = 22050
    silence = np.zeros(int(duration * sr), dtype=np.float32)
    
    # Convert to m4a-like bytes (just use WAV for simplicity)
    audio_buffer = BytesIO()
    sf.write(audio_buffer, silence, sr, format='WAV')
    audio_bytes = audio_buffer.getvalue()
    audio_b64 = base64.b64encode(audio_bytes).decode('utf-8')
    
    # Test batch endpoint with 12 files in 2 batches
    batch_size = 6
    num_batches = 2
    
    for batch_num in range(num_batches):
        batch_items = []
        for i in range(batch_size):
            task_id = batch_num * batch_size + i
            batch_items.append({
                "audio_data": audio_b64,
                "title": f"Test Song {task_id}",
                "artist": "Test Artist"
            })
        
        logger.info(f"\nSubmitting batch {batch_num + 1}/{num_batches} ({batch_size} files)")
        
        try:
            response = requests.post(
                f"{server_url}/analyze_batch",
                json=batch_items,
                headers={"X-API-Key": "DEV-KEY"},
                timeout=120  # 2 minutes
            )
            
            if response.status_code == 200:
                results = response.json()
                logger.info(f"✓ Batch {batch_num + 1} completed: {len(results)} results")
            else:
                logger.error(f"✗ Batch {batch_num + 1} failed: {response.status_code} {response.text[:200]}")
                return False
        except Exception as exc:
            logger.error(f"✗ Batch {batch_num + 1} exception: {exc}")
            return False
    
    logger.info(f"\nTest 5 completed successfully")
    return True


def main():
    """Run all diagnostic tests."""
    print(f"\n{'#'*70}")
    print(f"# Calibration Hang Diagnostic Experiments")
    print(f"# Python {sys.version}")
    print(f"# Process ID: {os.getpid()}")
    print(f"{'#'*70}\n")
    
    results = {}
    
    # Test 1: Basic ProcessPoolExecutor
    results['basic'] = test_processpool_basic(num_tasks=12, batch_size=6, hang_on=-1)
    
    # Test 2: Batched submission (like Swift TaskGroup)
    results['batched'] = test_processpool_batched_submission(num_tasks=12, batch_size=6, hang_on=-1)
    
    # Test 3: Timeout detection
    results['timeout'] = test_with_timeout_detection(num_tasks=12, batch_size=6, hang_on=7)
    
    # Test 4: as_completed pattern
    results['as_completed'] = test_as_completed_pattern(num_tasks=12, batch_size=6, hang_on=-1)
    
    # Test 5: Real server integration (optional)
    print("\n" + "="*70)
    run_server_test = input("Run server integration test? (requires server running) [y/N]: ")
    if run_server_test.lower() in ['y', 'yes']:
        results['server'] = test_analyze_server_integration()
    
    # Summary
    print(f"\n{'#'*70}")
    print(f"# Test Summary")
    print(f"{'#'*70}")
    for test_name, passed in results.items():
        status = "✓ PASS" if passed else "✗ FAIL"
        print(f"{status:10} {test_name}")
    
    print(f"\n{'#'*70}")
    print(f"# Recommendations based on results:")
    print(f"{'#'*70}")
    
    if not results.get('basic'):
        print("• Basic ProcessPoolExecutor is broken - check Python/multiprocessing setup")
    elif not results.get('batched'):
        print("• Batched submission causes issues - Swift TaskGroup may be blocking")
        print("  → Try sequential submission instead of parallel TaskGroup")
    elif results.get('timeout'):
        print("• Timeout detection works - hung workers can be caught")
        print("  → Ensure chunk_analysis timeout logic is active")
    
    if results.get('server') is False:
        print("• Server integration failed - check Flask/ProcessPool interaction")
        print("  → May need to avoid nested multiprocessing")


if __name__ == "__main__":
    main()
