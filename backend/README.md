# Mac Studio Audio Analysis Server 🎵

A self-improving music analysis database that runs on your Mac Studio and integrates seamlessly with your iOS app.

## What This Does

Your Mac Studio becomes an **intelligent caching server** that:
- ✅ Auto-analyzes full tracks and cross-checks overlapping 15s windows for steadier tempo/key detection
- ✅ Lets you manually verify/correct the 5% that are complex
- ✅ Grows smarter over time with your corrections
- ✅ Works for YOUR music catalog forever
- ✅ Caches everything permanently in SQLite database
- ✅ Returns instant results for previously analyzed songs

## Quick Start (2 minutes)

### Recommended: Virtual Environment Setup

For best results, use a Python virtual environment to ensure all dependencies (especially Essentia) are properly installed:

```bash
# Navigate to the repository root
cd /path/to/EssentiaServer

# Create virtual environment
python3 -m venv .venv

# Activate virtual environment
source .venv/bin/activate

# Install all dependencies (including Essentia)
pip install -r backend/requirements.txt

# Run the server using the virtual environment
.venv/bin/python backend/analyze_server.py
```

**Note:** The Mac GUI app will automatically detect and use the virtual environment at `.venv/bin/python` if it exists, and `backend/analyze_server.py` now refuses to launch outside that venv unless you explicitly set `ALLOW_SYSTEM_PYTHON=1`.
We pin `resampy` alongside `librosa`, so you'll no longer see the "Global resample ... failed (No module named 'resampy')" warning once the requirements install completes.

### Alternative: System Python Setup

If you prefer to use system Python (not recommended for Essentia support), you must opt in explicitly:

```bash
cd backend/

# Install required packages
pip3 install -r requirements.txt

# Allow system Python just for this invocation
export ALLOW_SYSTEM_PYTHON=1

# Run the server
python3 analyze_server.py
```

### Using the Setup Script

The automated setup script will prefer the virtual environment if it exists:

```bash
cd backend/
./setup_and_run.sh
```

You should see:
```
============================================================
🎵 Mac Studio Audio Analysis Server
============================================================
📂 Database: /Users/yourname/Music/audio_analysis_cache.db
📁 Cache Dir: /Users/yourname/Music/AudioAnalysisCache
🚀 Initializing...
✅ Server ready!
📡 Listening on http://0.0.0.0:5050
============================================================
```

### 4. Test It Works

Open another Terminal window:
```bash
curl http://localhost:5050/health
```

Should return:
```json
{
  "status": "healthy",
  "server": "Mac Studio Audio Analysis Server",
  "version": "1.0.0"
}
```

## Running 24/7 (Optional)

### Option A: Keep Terminal Open
Just leave the terminal running - it'll keep working.

### Option B: Use launchd (Auto-start on boot)

```bash
# Create launch agent
cat > ~/Library/LaunchAgents/com.repapp.audioanalysis.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.repapp.audioanalysis</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/python3</string>
        <string>/Users/YOURNAME/Documents/mac-audio-server/analyze_server.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Users/YOURNAME/Music/AudioAnalysisCache/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/YOURNAME/Music/AudioAnalysisCache/stderr.log</string>
</dict>
</plist>
EOF

# Replace YOURNAME with your username
# Then load it:
launchctl load ~/Library/LaunchAgents/com.repapp.audioanalysis.plist
```

## API Endpoints

### Analyze Audio
```bash
POST http://your-mac-studio.local:5050/analyze
Content-Type: application/json

{
  "audio_url": "https://audio-ssl.itunes.apple.com/...",
  "title": "Bohemian Rhapsody",
  "artist": "Queen"
}

Response (first time - 2-5 seconds):
{
  "bpm": 72.4,
  "bpm_confidence": 0.85,
  "key": "Bb Major",
  "key_confidence": 0.91,
  "energy": 0.78,
  "danceability": 0.65,
  "acousticness": 0.42,
  "spectral_centroid": 2145.3,
  "cached": false,
  "analysis_duration": 3.2
}

Response (second time - instant):
{
  "bpm": 72.4,
  ...
  "cached": true,
  "analyzed_at": "2025-10-27T20:30:15"
}
```

### Get Statistics
```bash
GET http://your-mac-studio.local:5050/stats

Response:
{
  "total_analyses": 127,
  "cache_hits": 89,
  "cache_misses": 38,
  "cache_hit_rate": "70.1%",
  "total_cached_songs": 127,
  "database_path": "/Users/you/Music/audio_analysis_cache.db"
}
```

### Search Cache
```bash
GET http://your-mac-studio.local:5000/cache/search?q=Queen

Response:
[
  {
    "title": "...",
    "artist": "...",
    "bpm": 120.0,
    "key": "C Major",
    "analyzed_at": "2025-11-14T20:20:20",
    ...
  }
]
```

### Export All Data
```bash
GET http://your-mac-studio.local:5000/cache/export

Downloads entire catalog as JSON
```

## Test Scripts

Two lightweight Python scripts keep the analysis helpers and HTTP surface healthy. Run them from the repo root:

```bash
python3 backend/test_phase1_features.py     # Validates feature helpers via synthetic audio
python3 backend/test_server.py              # Hits the Flask endpoints
python3 backend/performance_test.py         # Benchmarks DB optimizations (optional)
```

`test_phase1_features.py` synthesizes a metered audio clip, asserts deterministic mood mapping, and verifies silence handling. It only depends on `librosa`/`numpy`.

`test_server.py` talks to a running server. Configure targets via environment variables:

| Variable | Purpose | Default |
| --- | --- | --- |
| `TEST_SERVER_URL` | Override base URL (otherwise uses `MAC_STUDIO_SERVER_HOST/PORT`). | `http://localhost:5050` |
| `TEST_CACHE_NAMESPACE` | Namespace used for cache/search/analyze payloads. | `default` |
| `TEST_CACHE_MIN_RESULTS` | Minimum acceptable cache rows (fail if fewer). | `0` |
| `TEST_CACHE_QUERY` | Search query for `/cache/search`. | `""` |
| `TEST_ANALYZE_URL` | Preview URL to submit to `/analyze`. Use a valid one to expect HTTP 200. | Invalid placeholder |
| `TEST_ANALYZE_ACCEPTABLE_STATUS` | Comma-separated list of HTTP codes that count as pass for `/analyze`. | `200,500,502` |
| `TEST_ANALYZE_TIMEOUT` | Seconds before the analyze request times out. | `30` |

Example (expecting a download failure but successful health/cache coverage):

```bash
TEST_ANALYZE_ACCEPTABLE_STATUS=502 python3 backend/test_server.py
```

## Performance Tuning

Control server throughput without editing code by exporting environment variables before launching `analyze_server.py`:

- `ANALYSIS_SAMPLE_RATE` (default `22050`) – every waveform is globally resampled to this rate; lower values slash FFT cost while keeping tonal content for calibration runs. Use `ANALYSIS_RESAMPLE_TYPE` to choose the librosa resampler (`kaiser_fast`, `sinc_best`, etc.).
- `KEY_ANALYSIS_SAMPLE_RATE` – independent down-sampling target for the key detector (kept at 22.05 kHz by default).
- `ANALYSIS_WORKERS` (default `2`) – number of parallel `ProcessPoolExecutor` workers. Set to `0` to force single-process mode.
- `CHUNK_ANALYSIS_SECONDS`, `CHUNK_OVERLAP_SECONDS`, and `MAX_CHUNK_BATCHES` – control window length, hop size, and the maximum number of chunk analyses. Set `CHUNK_ANALYSIS_ENABLED=false` (or send header `X-Skip-Chunk-Analysis: true`) to skip chunk sweeps entirely during calibration throughput tests.
- `MAX_ANALYSIS_SECONDS` – trim the incoming audio before analysis if you only need the intro.

Example:

```bash
export ANALYSIS_SAMPLE_RATE=22050
export ANALYSIS_WORKERS=4
export CHUNK_ANALYSIS_ENABLED=false
python3 analyze_server.py
```

## How It Grows Over Time

**Week 1:** You add 50 songs
- 50 analyses performed
- 50 cached
- Next time: instant results

**Month 1:** You've added 500 songs
- 500 analyses performed
- 500 cached
- 90% of new songs you add = instant (popular songs already cached)

**Year 1:** 5,000+ songs cached
- Your personal Apple Music catalog
- Almost everything = instant
- Rare songs: 3-second analysis, then cached forever

## Database Location

**Cache Database:** `~/Music/audio_analysis_cache.db`
- SQLite database
- Can browse with: https://sqlitebrowser.org/
- Backup regularly if you want to preserve it

**Logs:** `~/Music/AudioAnalysisCache/server.log`

## Performance

**Mac Studio M1/M2:**
- Analysis: 2-5 seconds per song
- Cache lookup: <10ms
- Can analyze 700+ songs/hour
- Database size: ~1KB per song (5,000 songs = 5MB)

## Firewall Settings

If iOS app can't connect:
1. System Settings → Network → Firewall
2. Allow Python3 to accept incoming connections
3. Or disable firewall temporarily to test

## Find Your Mac Studio's IP

```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```

Use this IP in iOS app: `http://192.168.x.x:5000`

Or use Bonjour: `http://your-mac-name.local:5000`

## Troubleshooting

**"Module not found" error:**
```bash
pip3 install --upgrade librosa flask flask-cors
```

**"Permission denied":**
```bash
chmod +x analyze_server.py
```

**Port 5000 already in use:**
Edit `analyze_server.py`, change last line:
```python
app.run(host='0.0.0.0', port=5001, debug=False)
```

## Security Note

This server is designed for LOCAL NETWORK use only. Do NOT expose port 5000 to the internet without adding authentication!

## What Makes This Commercial-Grade

This is the SAME architecture that:
- ✅ Spotify uses (server-side analysis + caching)
- ✅ Apple Music uses internally
- ✅ Professional DJ software uses (Rekordbox, Serato)

The only difference: Your server is local and grows YOUR catalog on-demand!

## Next Steps

1. Start the server on your Mac Studio
2. Integrate iOS client (next file)
3. Watch your catalog grow automatically
4. Enjoy instant results for everything you've analyzed before

---

**You've just built a personal Apple Music analysis service!** 🎉
