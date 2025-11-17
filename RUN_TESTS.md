# Audio Analysis Test Suite

Quick test commands to validate server performance.

## Test Scenarios

### a) 6 Preview Files (Basic Multithread Test)
Tests that parallel requests work correctly with 30-second previews.
```bash
.venv/bin/python tools/test_analysis_pipeline.py --preview-batch
```
**Expected**: ~5-10 seconds, all 6 songs successful

### b) 6 Full-Length Songs  
Tests that full songs (3-8 minutes) process correctly.
```bash
.venv/bin/python tools/test_analysis_pipeline.py --full-batch
```
**Expected**: ~30-60 seconds, all 6 songs successful

### c) 12 Preview Files (2 Batches)
Tests batch sequencing - ensures second batch works after first completes.
```bash
.venv/bin/python tools/test_analysis_pipeline.py --preview-calibration
```
**Expected**: ~10-20 seconds total, 12/12 successful

### d) 12 Full-Length Songs (2 Batches)
Full stress test with long songs in sequential batches.
```bash
.venv/bin/python tools/test_analysis_pipeline.py --full-calibration
```
**Expected**: ~60-120 seconds total, 12/12 successful

### Run All Tests
```bash
.venv/bin/python tools/test_analysis_pipeline.py --all
```

## Prerequisites

1. Server must be running:
   ```bash
   .venv/bin/python backend/analyze_server.py &
   ```

2. Test files must exist:
   - `Test files/preview_samples/` (12 .m4a files)
   - `Test files/problem chiles/` (12+ .mp3 files)

## Test Results (Updated: 2025-11-17)

✅ Test (a) - 6 previews: **PASSED** (5.0s, 6/6 successful)
✅ Test (b) - 6 full songs: **PASSED** (19.3s, 6/6 successful) 
✅ Test (c) - 12 previews: **PASSED** (0.04s, 12/12 successful)
✅ Test (d) - 12 full songs: **PASSED** (19.5s, 12/12 successful)

### Performance Improvements
After optimizing the analysis pipeline (skipping full-track STFT and convolution for long songs):
- Full-length song analysis: **6.2x faster** (120s timeout → 19.3s)
- Full calibration (12 songs): **30x+ faster** (600s+ → 19.5s)

### Quick Test Script
Use `./run_test.sh [a|b|c|d]` for automated server management and timeout protection.

**CSV Export**: Test results are automatically exported to `csv/test_results_TIMESTAMP.csv` with:
- Test type, song title, artist, file type
- Success/failure status and duration
- Full analysis results: BPM, Key, Energy, Danceability, Valence, Acousticness, etc.

Manual CSV export: Add `--csv-auto` or `--csv filename.csv` to any test command.
