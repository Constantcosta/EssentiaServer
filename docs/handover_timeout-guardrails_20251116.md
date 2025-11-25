# Handover: Timeout Guardrails & Flask Threading Fix
**Date**: November 16, 2025  
**Agent**: Timeout Protection Implementation  
**Next Agent**: Continue testing and validation

---

## 🎯 Problem Statement

Calibration analysis was **hanging indefinitely** (15+ minutes) when processing 12-song batches. Investigation revealed multiple root causes:

1. **Flask running single-threaded** - Only 1 concurrent request despite 8 worker processes
2. **.env file not loading** - Server using preview-mode defaults (12kHz, 2 workers, 5s chunks)
3. **No timeout protection** - Hung analyses never failed, just waited forever
4. **Wrong log path in GUI** - Monitoring showed empty file instead of actual logs

**Expected Performance**: 5-10 seconds for 12-song calibration (2 batches of 6 songs)  
**Actual Performance**: 15+ minutes with 7 songs stuck indefinitely

---

## ✅ Solutions Implemented

### 1. Fixed .env Loading (`backend/analyze_server.py`)
**Problem**: Environment variables weren't being loaded at startup  
**Solution**: Added manual .env file parsing before imports (lines 1-23)

```python
# Load .env before imports to ensure settings are available
env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
if os.path.exists(env_path):
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                os.environ.setdefault(key.strip(), value.strip())
```

**Verification**: Server now loads with correct config (8 workers, 22050 Hz, 30s chunks)

### 2. Enabled Flask Threading (`backend/analyze_server.py`)
**Problem**: Flask defaults to single-threaded mode, blocking concurrent requests  
**Solution**: Added `threaded=True` to `app.run()` call (line 669)

```python
app.run(
    host=host,
    port=port,
    debug=False,
    use_reloader=False,
    threaded=True,  # Enable threading for concurrent request handling
)
```

**Impact**: Allows Swift's parallel TaskGroup to send 6 concurrent requests without blocking

### 3. Added Timeout Guardrails (Multiple Files)

#### Core Processing (`backend/server/processing.py`)
Added `timeout` parameter to `process_audio_bytes()` function:

```python
def process_audio_bytes(
    audio_bytes: bytes,
    title: str,
    artist: str,
    skip_chunk: bool,
    load_kwargs: dict,
    use_tempfile: bool = False,
    temp_suffix: str = ".m4a",
    max_workers: Optional[int] = None,
    timeout: int = 120,  # 2-minute timeout per song
) -> dict:
```

Changed `future.result()` to include timeout:

```python
try:
    result = future.result(timeout=timeout)
    return result
except TimeoutError:
    raise TimeoutError(
        f"Audio analysis for '{title}' by '{artist}' exceeded {timeout} second timeout. "
        "This may indicate the server is overloaded or the song has processing issues."
    )
```

#### Analysis Routes (`backend/server/analysis_routes.py`)
Added `timeout=120` to all three routes:

1. **`/analyze_url`** (line 152): Direct URL analysis with timeout
2. **`/analyze_data`** (line 215): Direct file upload with timeout  
3. **`/analyze_batch`** (line 34): Batch worker helper function with timeout

All routes now return HTTP 504 with clear error message if timeout occurs:

```python
except TimeoutError as exc:
    logger.error("⏱️ Analysis timed out...")
    return jsonify({
        "error": "timeout",
        "message": str(exc),
        "hint": "Song analysis took longer than 2 minutes..."
    }), 504
```

### 4. Enhanced GUI Logging (`MacStudioServerSimulator`)

#### Fixed Log Path (`ServerManagementLogStore.swift`)
**Before**: `~/Library/Logs/EssentiaServer/backend.log` (wrong location)  
**After**: `~/Music/AudioAnalysisCache/server.log` (correct location)

#### Enhanced Log Viewer (`ServerManagementLogsTab.swift`)
- **Real-time updates**: Auto-refresh every 1 second
- **Auto-scroll**: Automatically scrolls to bottom on new content
- **Live toggle**: Enable/disable live updates
- **Metadata display**: Shows file size and last update time
- **Auto-enable**: Live updates activate when tab is opened

---

## 📊 Technical Specifications

### System Configuration
- **Hardware**: Mac Studio M4 Max (14 cores, 36GB RAM)
- **Python**: 3.11+ in virtual environment (`.venv/`)
- **Worker Pool**: ProcessPoolExecutor with 8 workers, 'spawn' context
- **Server**: Flask with `threaded=True` on port 5050

### Analysis Settings (.env)
```bash
ANALYSIS_WORKERS=8
ANALYSIS_SAMPLE_RATE=22050
CHUNK_ANALYSIS_SECONDS=30
```

### Performance Targets
- **Single song**: ~0.5-1 second
- **6-song batch**: ~2.5-5 seconds  
- **12-song calibration**: 5-10 seconds total (2 parallel batches)
- **Timeout threshold**: 120 seconds per song (generous safety margin)

### Log Locations
- **Server logs**: `~/Music/AudioAnalysisCache/server.log`
- **Cache data**: `~/Music/AudioAnalysisCache/` (SQLite database)

---

## 🔧 Files Modified

### Backend Changes
1. **`backend/analyze_server.py`**
   - Lines 1-23: Added .env loading
   - Line 669: Added `threaded=True` to Flask

2. **`backend/server/processing.py`**
   - Function signature: Added `timeout=120` parameter
   - Lines ~90-100: Changed `future.result()` to `future.result(timeout=timeout)`
   - Added TimeoutError exception handling

3. **`backend/server/analysis_routes.py`**
   - Line 34: Added `timeout=120` to `_batch_analysis_worker()`
   - Line 152: Added `timeout=120` to `/analyze_url` route
   - Line 215: Added `timeout=120` to `/analyze_data` route
   - Added TimeoutError exception blocks to all routes

### Swift GUI Changes
4. **`MacStudioServerSimulator/MacStudioServerSimulator/ServerManagementLogStore.swift`**
   - Fixed log path to `~/Music/AudioAnalysisCache/server.log`
   - Changed refresh interval from 2s to 1s
   - Added `lastUpdate` and `logFileSize` tracking

5. **`MacStudioServerSimulator/MacStudioServerSimulator/ServerManagementLogsTab.swift`**
   - Added live updates toggle with auto-enable
   - Added auto-scroll to bottom functionality
   - Added file size and last update time display
   - Enhanced UI with metadata section

---

## 🧪 Testing Status

### ✅ Verified Working
- [x] Server starts with correct .env configuration (8 workers, 22050 Hz, 30s chunks)
- [x] Flask threading enabled (confirmed in startup logs)
- [x] Log file exists at correct path (`~/Music/AudioAnalysisCache/server.log`)
- [x] Diagnostics endpoint returns expected values
- [x] GUI log viewer shows real-time updates with 1-second refresh

### ⏳ Pending Validation
- [ ] Run full 12-song calibration workflow
- [ ] Verify completion time is 5-10 seconds (not 15+ minutes)
- [ ] Confirm timeout triggers properly if song hangs (>120s)
- [ ] Check GUI Logs tab shows real-time progress during analysis
- [ ] Validate all three routes (`/analyze_url`, `/analyze_data`, `/analyze_batch`)

---

## 🚀 Next Steps for Continuation

### Immediate Testing (Priority 1)
1. **Test calibration workflow**:
   ```bash
   # In GUI: Run calibration with 12 songs
   # Expected: Complete in 5-10 seconds
   # Watch Logs tab for real-time progress
   ```

2. **Verify timeout protection**:
   - If any song hangs >120s, should see clear timeout error
   - Should return HTTP 504 with descriptive message
   - Should not block other songs in batch

3. **Monitor performance**:
   - Check logs for analysis durations
   - Verify parallel processing (should see ~6 concurrent analyses)
   - Confirm no blocking/queueing issues

### If Issues Arise

**If calibration still slow (>30 seconds)**:
- Check `curl http://127.0.0.1:5050/diagnostics` - verify 8 workers active
- Check logs for queueing indicators
- May need to increase worker count or check hardware throttling

**If timeouts occur frequently (<120s)**:
- May indicate hardware overload or problematic audio files
- Check CPU usage during analysis
- Consider increasing timeout or reducing parallel batch size

**If GUI logs not updating**:
- Verify log file exists: `ls -lh ~/Music/AudioAnalysisCache/server.log`
- Check file permissions (should be writable)
- Verify server is actually writing logs (check file size changes)

### Future Improvements (Optional)
1. **Dynamic timeout**: Calculate based on song duration instead of fixed 120s
2. **Progress reporting**: Add WebSocket for real-time progress updates
3. **Graceful degradation**: Reduce worker count if system is under load
4. **Retry logic**: Automatically retry failed analyses with adjusted parameters

---

## 📝 Key Learnings

1. **Flask defaults matter**: Always explicitly enable threading for concurrent APIs
2. **.env loading**: Not automatic - requires manual parsing or python-dotenv package
3. **Timeout layers**: Need protection at both worker pool AND route levels
4. **Log locations**: macOS apps may write logs to non-standard locations
5. **Real-time monitoring**: Essential for debugging performance issues in production

---

## 🔗 Related Documentation

- Original issue investigation: `docs/handover_2025-11-16_logging-and-fixes.md`
- Calibration workflow: `docs/calibration-handover.md`
- Performance optimizations: `backend/PERFORMANCE_OPTIMIZATIONS.md`
- Server architecture: `backend/README.md`

---

## 💡 Context for Next Agent

The server is **currently running** with all fixes applied. The timeout guardrails are **live and active**. 

**What's working**: .env loading, Flask threading, timeout protection, GUI log viewer  
**What needs testing**: Actual calibration run to verify 5-10 second performance

The main risk now is **false positives** - if 120-second timeout is too aggressive for certain edge cases. Monitor the first few calibration runs to ensure legitimate analyses don't timeout unnecessarily.

**Quick verification command**:
```bash
curl http://127.0.0.1:5050/diagnostics | python3 -m json.tool | grep -E "(workers|sample_rate|chunk_size|threaded)"
```

Good luck! 🎵
