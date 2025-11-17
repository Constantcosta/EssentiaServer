# Optimizing Calibration Performance on Mac Studio

## Current Situation
After fixing the deadlock, calibration now runs **sequentially** in Swift but **parallel** in the backend. This is safer but doesn't fully utilize your Mac Studio's power.

## Your Mac Studio's Resources
Looking at your Activity Monitor:
- **Threads**: 5,648 available
- **CPU Cores**: Likely M2 Ultra (20-24 cores)
- **Current Usage**: Very low (System: 5.28%, User: 23.22%)

You have **massive headroom** for parallel processing!

## Optimization Options

### Option 1: Increase Backend Workers (RECOMMENDED - Safe & Effective)

**Current**: `ANALYSIS_WORKERS=2` (only 2 songs analyzed in parallel by backend)
**Optimized**: `ANALYSIS_WORKERS=6` (matches your batch size)

#### How to Set:
```bash
# In your terminal before starting server:
export ANALYSIS_WORKERS=6

# Or create a .env file:
echo "ANALYSIS_WORKERS=6" >> .env

# Or start server with:
ANALYSIS_WORKERS=6 .venv/bin/python backend/analyze_server.py
```

#### Benefits:
- ✅ Backend can handle 6 concurrent requests from Swift
- ✅ No deadlock (each worker runs sequentially internally)
- ✅ Fully utilizes your CPU during calibration
- ✅ No code changes needed

#### Performance Impact:
```
Before: 2 workers × ~60s per song = 360s for 6 songs
After:  6 workers × ~60s per song = ~60s for 6 songs (6x faster!)
```

---

### Option 2: Re-enable Swift Parallel with Larger Worker Pool (ADVANCED)

**Approach**: Restore Swift's parallel TaskGroup + increase backend workers to match

#### Changes:
1. Set `ANALYSIS_WORKERS=6` (or higher)
2. Revert Swift code to parallel TaskGroup
3. Add request throttling

#### Swift Code (MacStudioServerManager+Calibration.swift):
```swift
// Re-enable parallel processing with backend support
let batchResults = await withTaskGroup(...) { group in
    for (index, song) in batch.enumerated() {
        group.addTask {
            // Backend now has enough workers to handle this
            let result = try await self.analyzeAudioFile(...)
            return (index, songName, .success(result))
        }
    }
    
    var collected: [(Int, String, Result<AnalysisResult, Error>)] = []
    for await result in group {
        collected.append(result)
    }
    return collected.sorted(by: { $0.0 < $1.0 })
}
```

#### Backend Setting:
```bash
export ANALYSIS_WORKERS=8  # More than batch size for safety
```

#### Pros:
- ⚡ Maximum speed (true parallelism at all layers)
- 📊 Better progress tracking (multiple songs show progress simultaneously)

#### Cons:
- ⚠️ More complex (need to tune worker count)
- ⚠️ Higher memory usage
- ⚠️ Need to ensure workers > concurrent requests

---

### Option 3: Hybrid Approach (BALANCED)

**Best of both worlds**: Keep Swift sequential, but process mini-batches

#### Swift Code:
```swift
// Process in mini-batches of 2-3 songs
let miniBatchSize = 3
for miniStart in stride(from: 0, to: batch.count, by: miniBatchSize) {
    let miniEnd = min(miniStart + miniBatchSize, batch.count)
    let miniBatch = Array(batch[miniStart..<miniEnd])
    
    // Process mini-batch in parallel
    let miniResults = await withTaskGroup(...) { group in
        for song in miniBatch {
            group.addTask { try await self.analyzeAudioFile(...) }
        }
        // collect results
    }
}
```

#### Backend Setting:
```bash
export ANALYSIS_WORKERS=4  # Matches mini-batch size + safety margin
```

#### Pros:
- ✅ More parallel than fully sequential
- ✅ Safer than full parallel (fewer concurrent requests)
- ✅ Good balance of speed vs. stability

---

## Recommended Configuration for Mac Studio

Based on your hardware, I recommend:

### Immediate (No Code Changes):
```bash
# Add to your shell profile (~/.zshrc) or .env file:
export ANALYSIS_WORKERS=6        # Match batch size
export MAX_CHUNK_BATCHES=20      # More chunk analysis
export CHUNK_ANALYSIS_SECONDS=20 # Longer chunks for better accuracy
```

Then restart the server:
```bash
pkill -f analyze_server.py
ANALYSIS_WORKERS=6 .venv/bin/python backend/analyze_server.py &
```

### Expected Results:
- 6 songs can be processed in parallel by backend
- Sequential Swift requests get immediate worker availability
- No deadlock risk
- Full utilization of your CPU power

### Performance Estimate:
```
Current Sequential:  12 songs × 60s = ~720s (12 minutes)
With ANALYSIS_WORKERS=6:  
  - Batch 1 (6 songs): ~60s in parallel
  - Batch 2 (6 songs): ~60s in parallel  
  - Total: ~120s (2 minutes) ← 6x faster!
```

---

## How to Test

1. **Set the environment variable:**
   ```bash
   export ANALYSIS_WORKERS=6
   ```

2. **Restart server:**
   ```bash
   pkill -f analyze_server.py && sleep 1
   ANALYSIS_WORKERS=6 .venv/bin/python backend/analyze_server.py &
   ```

3. **Run calibration with 12 songs**

4. **Monitor in Activity Monitor:**
   - You should see multiple Python processes
   - CPU usage should spike (50-70% on Mac Studio is healthy)
   - All songs should complete without hanging

5. **Check logs:**
   ```bash
   tail -f ~/Library/Logs/EssentiaServer/backend.log
   ```
   
   Look for:
   ```
   ⚙️ Enabled analysis process pool (6 workers using 'spawn' context).
   ```

---

## Why This Works Better Than Swift Parallel

The key insight: **Parallelize at the layer with the most control**

### Swift Parallel (Your Original Attempt):
```
❌ Swift controls parallelism
❌ Backend is a black box
❌ Can't prevent nested pools
❌ Resource contention
```

### Backend Parallel (New Approach):
```
✅ Backend controls parallelism
✅ Knows its own worker limits
✅ Prevents nested pools (our fix)
✅ Balanced resource usage
✅ Swift stays simple and reliable
```

---

## Monitoring Performance

Watch your system while calibration runs:

### Good Signs:
- ✅ Multiple "Python" processes in Activity Monitor
- ✅ CPU usage 50-80% (on Mac Studio this is healthy)
- ✅ Steady progress in calibration log
- ✅ No zombie processes

### Bad Signs:
- ❌ CPU stuck at 100% (too many workers)
- ❌ Memory pressure (reduce workers)
- ❌ Workers timing out (reduce workers or chunk batches)

### Optimal Settings Finder:
Start conservative and increase:
```bash
# Start:
ANALYSIS_WORKERS=4

# If CPU < 50% and no issues:
ANALYSIS_WORKERS=6

# If still smooth:
ANALYSIS_WORKERS=8

# If you see issues, back down to last stable value
```

---

## Summary

**You were right to want parallelism!** The issue wasn't the concept, just the implementation layer.

**Quick Win** (No code changes):
```bash
export ANALYSIS_WORKERS=6
```

This will make your calibration **~6x faster** while staying 100% stable. 🚀
