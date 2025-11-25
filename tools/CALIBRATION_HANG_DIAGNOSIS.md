# Calibration Hang Diagnosis

## Problem Summary
Calibration analysis hangs after the first 6 workers start processing. No errors are logged, and the process appears stuck indefinitely.

## Root Cause
**Nested multiprocessing deadlock** due to three layers of parallelism:

```
Swift TaskGroup (6 parallel tasks)
    ↓
Flask Server (receives 6 concurrent HTTP requests)
    ↓
ProcessPoolExecutor (2 workers, trying to handle 6 requests)
    ↓
Each worker tries to spawn nested ProcessPoolExecutor
    ↓
DEADLOCK: Workers block waiting for nested pools that can't start
```

## Evidence

### 1. Swift Code (`MacStudioServerManager+Calibration.swift`, line 148)
```swift
let batchResults = await withTaskGroup(...) { group in
    for (index, song) in batch.enumerated() {
        group.addTask {  // ← 6 parallel tasks
            let result = try await self.analyzeAudioFile(...)  // ← Individual HTTP request
```

**Issue**: Swift sends 6 concurrent HTTP requests to `/analyze` endpoint

### 2. Flask Endpoint (`analysis_routes.py`, line 160)
```python
result = process_audio_bytes(
    ...,
    max_workers=analysis_workers,  # ← Spawns ProcessPool with N workers
```

**Issue**: Each request tries to create a worker process, but the pool is already saturated

### 3. Worker Function (`processing.py`, line 188)
```python
return executor.submit(_analysis_worker_job, payload).result()
```

**Issue**: Blocks waiting for worker availability, but workers are blocked waiting for nested resources

### 4. The Spawn Context Problem
Using `spawn` context (required on macOS for Flask safety) means:
- Each worker process is fully isolated
- Worker processes import modules fresh
- Worker processes don't inherit the parent's ProcessPool
- **But**: If a worker tries to create its own ProcessPool, it competes for system resources

## Why It Worked Initially
The first 2-3 songs complete because:
1. ProcessPool has 2 workers available
2. They process 2 songs successfully
3. Workers return to pool and process 2 more
4. **BUT**: If chunk analysis or any nested processing triggers, workers get stuck

## Why Batch 2 Never Starts
Swift's `withTaskGroup` waits for ALL 6 tasks in batch 1 to complete before moving to batch 2. Since some tasks are hung, batch 1 never completes.

## Solution Options

### Option A: Sequential Processing in Swift (RECOMMENDED)
**Change**: Process songs one at a time in Swift, not in parallel TaskGroup

**Pros**:
- Eliminates nested parallelism
- Server handles one request at a time with full ProcessPool available
- No code changes to Python backend needed
- Safer and more predictable

**Cons**:
- Slower overall (but not much if server uses ProcessPool internally)

### Option B: Disable ProcessPool for Calibration
**Change**: Add `max_workers=0` flag for calibration namespace requests

**Pros**:
- Keeps Swift parallel processing
- Forces sequential analysis in Flask workers
- No nested ProcessPools

**Cons**:
- Calibration runs slower (no chunk parallelism)
- Requires backend code changes

### Option C: Use Different Endpoint
**Change**: Make Swift use `/analyze_batch` endpoint with all 6 songs at once

**Pros**:
- Backend handles batching internally
- Better timeout control
- More efficient

**Cons**:
- Requires Swift code refactor
- Current `/analyze_batch` endpoint processes sequentially anyway

### Option D: Fix ProcessPool Resource Limits
**Change**: Increase `ANALYSIS_WORKERS` to match Swift batch size

**Pros**:
- Allows parallel processing

**Cons**:
- Doesn't solve nested pool issue
- Requires more system resources
- Still risky with chunk analysis

## Recommended Fix

### Immediate Fix (Swift Side)
Change calibration processing from parallel TaskGroup to sequential loop:

```swift
// BEFORE: Parallel TaskGroup (CAUSES HANG)
let batchResults = await withTaskGroup(...) { group in
    for (index, song) in batch.enumerated() {
        group.addTask {
            let result = try await self.analyzeAudioFile(...)
        }
    }
}

// AFTER: Sequential processing (WORKS RELIABLY)
var batchResults: [(Int, String, Result<AnalysisResult, Error>)] = []
for (index, song) in batch.enumerated() {
    let songURL = fileURL(for: song)
    let songName = song.displayName
    
    do {
        let result = try await self.analyzeAudioFile(
            at: songURL,
            skipChunkAnalysis: false,
            forceFreshAnalysis: true,
            cacheNamespace: calibrationCacheNamespace
        )
        batchResults.append((index, songName, .success(result)))
    } catch {
        batchResults.append((index, songName, .failure(error)))
    }
}
```

### Backend Safety (Python Side)
Add detection for nested multiprocessing:

```python
# In processing.py
def get_analysis_executor(max_workers: int) -> Optional[ProcessPoolExecutor]:
    """Lazily build a shared process pool when ANALYSIS_WORKERS > 0."""
    if max_workers <= 0:
        return None
    
    # Detect if we're already in a worker process
    if multiprocessing.current_process().name != 'MainProcess':
        LOGGER.warning("⚠️ Nested ProcessPool detected - forcing sequential mode")
        return None  # Force sequential processing in workers
    
    # ... rest of function
```

## Testing the Fix

### Test 1: Run diagnostic script
```bash
.venv/bin/python tools/diagnose_calibration_hang.py
```

Should complete all tests without hanging.

### Test 2: Run calibration with sequential Swift code
After applying the Swift fix, run a calibration with 12+ songs and verify:
- All batches complete
- No hangs between batches
- Progress continues smoothly

### Test 3: Monitor worker processes
```bash
# In one terminal
watch -n 1 'ps aux | grep -E "(analyze_server|Python)" | grep -v grep'

# In another terminal  
tail -f ~/Library/Logs/EssentiaServer/backend.log
```

Look for:
- Worker processes spawning and completing
- No zombie processes
- Log messages showing batch progression

## Implementation Priority
1. ✅ **HIGH**: Change Swift calibration to sequential processing
2. ✅ **MEDIUM**: Add nested ProcessPool detection in Python
3. 🔜 **LOW**: Add monitoring/logging for worker pool status
4. 🔜 **LOW**: Consider implementing proper `/analyze_batch` usage

## Related Files
- `MacStudioServerSimulator/.../MacStudioServerManager+Calibration.swift` (line 148)
- `backend/server/processing.py` (line 50, 175)
- `backend/server/analysis_routes.py` (line 15, 160)
- `backend/analysis/pipeline_chunks.py` (timeout detection exists)
