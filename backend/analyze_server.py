#!/usr/bin/env python3
"""
Mac Studio Audio Analysis Server
Analyzes Apple Music previews and caches results
Acts as intelligent fallback for GetSongBPM
"""

# Load .env file FIRST before any other imports
from pathlib import Path
import os
import sys

REPO_ROOT = Path(__file__).resolve().parent.parent
# Add repo root to path so we can import backend modules
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

env_file = REPO_ROOT / ".env"
if env_file.exists():
    print(f"🔧 Loading configuration from {env_file}")
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                os.environ[key.strip()] = value.strip()
    print(f"✅ Loaded .env with ANALYSIS_WORKERS={os.environ.get('ANALYSIS_WORKERS', 'not set')}, ANALYSIS_SAMPLE_RATE={os.environ.get('ANALYSIS_SAMPLE_RATE', 'not set')}")
else:
    print(f"⚠️ No .env file found at {env_file}, using defaults")

from flask import Flask, jsonify, request
from flask_cors import CORS
import logging
from datetime import datetime
import secrets
from functools import wraps
import time
from threading import Lock
import subprocess
from typing import Optional
import sys
import traceback

from backend.server.app_config import ServerConfig

# REPO_ROOT already defined above when loading .env
CONFIG = ServerConfig.from_env(REPO_ROOT)
EXPECTED_VENV_PYTHON = CONFIG.expected_venv_python
ALLOW_SYSTEM_PYTHON = CONFIG.allow_system_python
PRODUCTION_MODE = CONFIG.production_mode
DEFAULT_PORT = CONFIG.default_port
ENV_HOST = CONFIG.host
RATE_LIMIT = CONFIG.rate_limit

def _ensure_virtualenv_python(expected_path: Path, allow_system_python: bool) -> None:
    if allow_system_python:
        print("⚠️ ALLOW_SYSTEM_PYTHON=1 set — skipping virtual environment enforcement.")
        return
    if not expected_path.exists():
        message = (
            f"❌ Required virtual environment not found at {expected_path}.\n"
            "Create it with: python3.12 -m venv .venv && "
            ".venv/bin/pip install -r backend/requirements.txt\n"
            "To bypass temporarily (not recommended), set ALLOW_SYSTEM_PYTHON=1."
        )
        print(message, file=sys.stderr)
        raise SystemExit(2)
    current = Path(sys.executable).resolve()
    expected_real = expected_path.resolve()
    if current != expected_real:
        message = (
            f"❌ Analyzer must run via {expected_real}, but current interpreter is {current}.\n"
            "Please restart using the repo virtual environment "
            "(.venv/bin/python backend/analyze_server.py). "
            "Set ALLOW_SYSTEM_PYTHON=1 to skip this check (not recommended)."
        )
        print(message, file=sys.stderr)
        raise SystemExit(3)

_ensure_virtualenv_python(EXPECTED_VENV_PYTHON, ALLOW_SYSTEM_PYTHON)
# Ensure we know which interpreter launched this server (helps GUI verification).
print(f"🧠 Analyzer running via {sys.executable}")

from backend.analysis.utils import clamp_to_unit, safe_float, percentage
from backend.analysis.pipeline import CalibrationHooks
from backend.analysis.pipeline_core import perform_audio_analysis
from backend.analysis.pipeline_chunks import attach_chunk_analysis
from backend.analysis.reporting import (
    ANALYSIS_TIMER_EXPORT_FIELDS,
    CHUNK_TIMING_EXPORT_FIELDS,
    EXPORT_DIR,
)
from backend.analysis.calibration import (
    KEY_CALIBRATION_PATH,
    apply_calibration_layer,
    apply_calibration_models,
    apply_key_calibration,
    apply_bpm_calibration,
    load_calibration_config,
    load_calibration_models,
    load_key_calibration,
    load_bpm_calibration,
    refresh_calibration_assets,
)
from backend.analysis.essentia_support import HAS_ESSENTIA, es
from backend.server import configure_processing, process_audio_bytes
from backend.server.admin_routes import error_hint_from_exception, register_admin_routes
from backend.server.analysis_routes import register_analysis_routes
from backend.server.cache_routes import (
    cache_search,
    clear_cache,
    configure_cache_routes,
    delete_cache_entry,
    export_cache,
    list_cache,
)
from backend.server.cache_store import check_cache, get_url_hash, save_to_cache, update_stats
from backend.server.calibration_routes import register_calibration_routes
from backend.server.database import configure_database, get_db_connection, initialize_database
from backend.server.scipy_compat import ensure_hann_patch
from backend.analysis.key_detection import configure_key_detection

SCIPY_HANN_PATCHED = ensure_hann_patch()
if not SCIPY_HANN_PATCHED:
    print("⚠️ Could not apply scipy.signal.hann compatibility shim – check SciPy installation.")
else:
    print("✅ Enabled scipy.signal.hann compatibility shim.")

configure_key_detection(HAS_ESSENTIA, es)

app = Flask(__name__)
app.config["SERVER_CONFIG"] = CONFIG

# SECURITY CONFIGURATION
# For development: localhost only
# For production: set PRODUCTION_MODE=True and generate secure API keys
if PRODUCTION_MODE:
    # Production: Allow all origins but require API key authentication
    CORS(app)
    print("🔒 PRODUCTION MODE: API key authentication required")
else:
    # Development: localhost only, no auth required
    CORS(app, resources={r"/*": {"origins": ["http://localhost:*", "http://127.0.0.1:*"]}})
    print("🔧 DEVELOPMENT MODE: localhost only, no authentication")

# Rate limiting (requests per minute per API key)
rate_limit_data = {}
rate_limit_lock = Lock()

# API key cache to avoid repeated database queries
api_key_cache = {}
api_key_cache_lock = Lock()
API_KEY_CACHE_TTL = 300  # 5 minutes

# Configuration
if str(REPO_ROOT) not in sys.path:
    sys.path.append(str(REPO_ROOT))
from tools.key_utils import (
    canonical_key_id,
    normalize_key_label,
    parse_canonical_key_id,
    format_canonical_key,
)  # type: ignore  # noqa: E402

# Database connection pool with thread safety
from backend.analysis import settings as analysis_settings  # noqa: E402

ANALYSIS_SAMPLE_RATE = analysis_settings.ANALYSIS_SAMPLE_RATE
ANALYSIS_FFT_SIZE = analysis_settings.ANALYSIS_FFT_SIZE
ANALYSIS_HOP_LENGTH = analysis_settings.ANALYSIS_HOP_LENGTH
ANALYSIS_RESAMPLE_TYPE = analysis_settings.ANALYSIS_RESAMPLE_TYPE
TEMPO_WINDOW_SECONDS = analysis_settings.TEMPO_WINDOW_SECONDS
MAX_ANALYSIS_SECONDS = analysis_settings.MAX_ANALYSIS_SECONDS
CHUNK_ANALYSIS_SECONDS = analysis_settings.CHUNK_ANALYSIS_SECONDS
CHUNK_OVERLAP_SECONDS = analysis_settings.CHUNK_OVERLAP_SECONDS
MIN_CHUNK_DURATION_SECONDS = analysis_settings.MIN_CHUNK_DURATION_SECONDS
KEY_ANALYSIS_SAMPLE_RATE = analysis_settings.KEY_ANALYSIS_SAMPLE_RATE
MAX_CHUNK_BATCHES = analysis_settings.MAX_CHUNK_BATCHES
CHUNK_ANALYSIS_ENABLED = analysis_settings.CHUNK_ANALYSIS_ENABLED
CHUNK_BEAT_TARGET = analysis_settings.CHUNK_BEAT_TARGET
CONSENSUS_STD_EPS = analysis_settings.CONSENSUS_STD_EPS
ANALYSIS_WORKERS = analysis_settings.ANALYSIS_WORKERS
ENABLE_TONAL_EXTRACTOR = analysis_settings.ENABLE_TONAL_EXTRACTOR
ENABLE_ESSENTIA_DANCEABILITY = analysis_settings.ENABLE_ESSENTIA_DANCEABILITY
ENABLE_ESSENTIA_DESCRIPTORS = analysis_settings.ENABLE_ESSENTIA_DESCRIPTORS
def get_build_signature() -> str:
    try:
        sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO_ROOT).decode().strip()
    except Exception:
        sha = "unknown"
    timestamp = datetime.now().strftime('%Y%m%d%H%M%S')
    return f"{sha[:7]}-{timestamp}"

SERVER_BUILD_SIGNATURE = get_build_signature()

DB_PATH = str(CONFIG.db_path)
CACHE_DIR = str(CONFIG.cache_dir)

configure_database(DB_PATH)
configure_cache_routes(EXPORT_DIR)
initialize_database()

# Setup logging with rotation (max 10MB per file, keep 5 backups = ~50MB total)
from logging.handlers import RotatingFileHandler
log_file = str(CONFIG.log_file)

# Clear log if --clear-log flag or CLEAR_LOG env var is set
if '--clear-log' in sys.argv or os.environ.get('CLEAR_LOG', '').lower() in ('1', 'true', 'yes'):
    if os.path.exists(log_file):
        open(log_file, 'w').close()

file_handler = RotatingFileHandler(
    log_file,
    maxBytes=10*1024*1024,  # 10MB
    backupCount=5,
    encoding='utf-8'
)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        file_handler,
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)
logger.info(f"🚀 Server build {SERVER_BUILD_SIGNATURE} (hann shim enabled: {SCIPY_HANN_PATCHED})")
if not ENABLE_TONAL_EXTRACTOR:
    logger.info("🎚️ Essentia TonalExtractor disabled (set ENABLE_TONAL_EXTRACTOR=true to re-enable tonal strength).")
if not ENABLE_ESSENTIA_DANCEABILITY:
    logger.info("💃 Essentia danceability disabled – using heuristic scorer (set ENABLE_ESSENTIA_DANCEABILITY=true to enable).")
if not ENABLE_ESSENTIA_DESCRIPTORS:
    logger.info("📊 Essentia descriptor extractors disabled – using librosa fallbacks (set ENABLE_ESSENTIA_DESCRIPTORS=true to enable).")

load_calibration_config()
load_calibration_models()
load_key_calibration()
load_bpm_calibration()

DEFAULT_CALIBRATION_HOOKS = CalibrationHooks(
    apply_scalers=apply_calibration_layer,
    apply_key=apply_key_calibration,
    apply_bpm=apply_bpm_calibration,
    apply_models=apply_calibration_models,
)
configure_processing(DEFAULT_CALIBRATION_HOOKS)


@app.before_request
def _ensure_calibration_assets_current():
    refresh_calibration_assets()


def require_api_key(f):
    """Decorator to require API key authentication in production mode"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not PRODUCTION_MODE:
            return f(*args, **kwargs)
        
        api_key = request.headers.get('X-API-Key')
        
        if not api_key:
            logger.warning(f"❌ Unauthorized request from {request.remote_addr} - No API key")
            return jsonify({'error': 'API key required', 'message': 'Include X-API-Key header'}), 401
        
        if not validate_api_key(api_key):
            logger.warning(f"❌ Invalid API key from {request.remote_addr}: {api_key[:8]}...")
            return jsonify({'error': 'Invalid API key'}), 403
        
        if not check_rate_limit(api_key):
            logger.warning(f"⚠️ Rate limit exceeded for key {api_key[:8]}...")
            return jsonify({'error': 'Rate limit exceeded', 'message': 'Too many requests'}), 429
        
        logger.info(f"✅ Authorized request from key {api_key[:8]}...")
        
        return f(*args, **kwargs)
    return decorated_function

def generate_api_key():
    """Generate a secure API key"""
    return secrets.token_urlsafe(32)

def validate_api_key(api_key):
    """Check if API key is valid with caching"""
    current_time = time.time()
    
    # Check cache first
    with api_key_cache_lock:
        if api_key in api_key_cache:
            cached_data, cache_time = api_key_cache[api_key]
            if current_time - cache_time < API_KEY_CACHE_TTL:
                return cached_data
    
    with get_db_connection() as conn:
        cursor = conn.cursor()
        
        # Combined query to get key info and daily usage in one go
        cursor.execute('''
            SELECT k.id, k.active, k.daily_limit,
                   (SELECT COUNT(*) FROM api_usage 
                    WHERE api_key_id = k.id AND DATE(timestamp) = DATE('now')) as daily_usage
            FROM api_keys k
            WHERE k.key = ?
        ''', (api_key,))
        result = cursor.fetchone()
        
        if not result:
            # Cache negative result too
            with api_key_cache_lock:
                api_key_cache[api_key] = (False, current_time)
            return False
        
        key_id, active, daily_limit, daily_usage = result
        
        if not active:
            with api_key_cache_lock:
                api_key_cache[api_key] = (False, current_time)
            return False
        
        # Check daily usage limit
        if daily_limit > 0 and daily_usage >= daily_limit:
            logger.warning(f"⚠️ Daily limit reached for key {api_key[:8]}...")
            # Don't cache this - usage can change
            return False
        
        # Cache positive result
        with api_key_cache_lock:
            api_key_cache[api_key] = (True, current_time)
        
        return True

def check_rate_limit(api_key):
    """Check and update rate limit for API key with automatic cleanup"""
    current_time = time.time()
    
    with rate_limit_lock:
        # Clean up old entries (older than 2 minutes)
        expired_keys = [k for k, v in rate_limit_data.items() 
                       if current_time > v.get('reset_time', 0) + 60]
        for k in expired_keys:
            del rate_limit_data[k]
        
        # Get or create rate limit entry
        if api_key not in rate_limit_data:
            rate_limit_data[api_key] = {'count': 0, 'reset_time': current_time + 60}
        
        entry = rate_limit_data[api_key]
        
        if current_time > entry['reset_time']:
            # Reset counter
            entry['count'] = 0
            entry['reset_time'] = current_time + 60
        
        entry['count'] += 1
        
        return entry['count'] <= RATE_LIMIT


register_calibration_routes(
    app,
    require_api_key=require_api_key,
    logger=logger,
    repo_root=REPO_ROOT,
    key_calibration_path=KEY_CALIBRATION_PATH,
    load_key_calibration=load_key_calibration,
)


@app.route('/cache/search', methods=['GET'])
def cache_search_route():
    return cache_search()


@app.route('/cache', methods=['GET'])
def cache_list_route():
    return list_cache()


@app.route('/cache/<int:cache_id>', methods=['DELETE'])
def cache_delete_route(cache_id: int):
    return delete_cache_entry(cache_id)


@app.route('/cache/clear', methods=['POST'])
def cache_clear_route():
    return clear_cache()


@app.route('/cache/export', methods=['GET'])
def cache_export_route():
    return export_cache()

# API ENDPOINTS


register_admin_routes(
    app,
    logger=logger,
    default_port=DEFAULT_PORT,
    production_mode=PRODUCTION_MODE,
    server_build_signature=SERVER_BUILD_SIGNATURE,
    db_path=DB_PATH,
    cache_dir=CACHE_DIR,
    analysis_config={
        "sample_rate": ANALYSIS_SAMPLE_RATE,
        "fft_size": ANALYSIS_FFT_SIZE,
        "max_duration": MAX_ANALYSIS_SECONDS,
        "workers": ANALYSIS_WORKERS,
        "chunk_analysis_enabled": CHUNK_ANALYSIS_ENABLED,
    },
    feature_flags={
        "tonal_extractor": ENABLE_TONAL_EXTRACTOR,
        "essentia_danceability": ENABLE_ESSENTIA_DANCEABILITY,
        "essentia_descriptors": ENABLE_ESSENTIA_DESCRIPTORS,
    },
    export_dir=str(EXPORT_DIR),
    has_essentia=HAS_ESSENTIA,
    scipy_hann_patched=SCIPY_HANN_PATCHED,
    get_db_connection=get_db_connection,
    get_url_hash=get_url_hash,
)

register_analysis_routes(
    app,
    logger=logger,
    require_api_key=require_api_key,
    process_audio_bytes=process_audio_bytes,
    check_cache=check_cache,
    save_to_cache=save_to_cache,
    update_stats=update_stats,
    max_analysis_seconds=MAX_ANALYSIS_SECONDS,
    analysis_workers=ANALYSIS_WORKERS,
    error_hint_from_exception=error_hint_from_exception,
)



if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Mac Studio Audio Analysis Server')
    parser.add_argument('--clear-log', action='store_true', 
                       help='Clear the log file on startup (default: keep existing logs)')
    args = parser.parse_args()
    
    print("=" * 60)
    print("🎵 Mac Studio Audio Analysis Server")
    print("=" * 60)
    print(f"📂 Database: {DB_PATH}")
    print(f"📁 Cache Dir: {CACHE_DIR}")
    print("🚀 Database + cache initialized.")
    print("✅ Server ready!")
    
    # Determine bind host
    if ENV_HOST:
        bind_host = ENV_HOST
    else:
        bind_host = '0.0.0.0' if PRODUCTION_MODE else '127.0.0.1'
    
    if bind_host == '0.0.0.0':
        print(f"📡 Listening on all interfaces (port {DEFAULT_PORT})")
        print("⚠️ Network: Accessible to other devices on your network")
    else:
        print(f"📡 Listening on http://{bind_host}:{DEFAULT_PORT}")
        if bind_host.startswith('127.') or bind_host == 'localhost':
            print("🔒 Security: Server only accepts local connections")
        else:
            print("⚠️ Network: Accessible to other devices that can reach this host")
    print("=" * 60)
    
    # Enable threading to handle concurrent requests from Swift TaskGroup
    # threaded=True allows Flask to handle multiple requests simultaneously
    # This works with the ProcessPoolExecutor (8 workers) for true parallelism
    app.run(host=bind_host, port=DEFAULT_PORT, debug=False, threaded=True)
