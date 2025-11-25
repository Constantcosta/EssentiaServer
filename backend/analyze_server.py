#!/usr/bin/env python3
"""
Mac Studio Audio Analysis Server
Analyzes Apple Music previews and caches results
Acts as intelligent fallback for GetSongBPM
"""

from flask import Flask, jsonify, request
from flask_cors import CORS
import librosa
import numpy as np
import requests
from io import BytesIO
import sqlite3
import hashlib
import logging
from datetime import datetime
import os
import secrets
from functools import wraps
from collections import defaultdict
import time

app = Flask(__name__)

# SECURITY CONFIGURATION
# For development: localhost only
# For production: set PRODUCTION_MODE=True and generate secure API keys
PRODUCTION_MODE = os.environ.get('PRODUCTION_MODE', 'false').lower() == 'true'

if PRODUCTION_MODE:
    # Production: Allow all origins but require API key authentication
    CORS(app)
    print("🔒 PRODUCTION MODE: API key authentication required")
else:
    # Development: localhost only, no auth required
    CORS(app, resources={r"/*": {"origins": ["http://localhost:*", "http://127.0.0.1:*"]}})
    print("🔧 DEVELOPMENT MODE: localhost only, no authentication")

# Rate limiting (requests per minute per API key)
RATE_LIMIT = 60  # requests per minute
rate_limit_data = defaultdict(lambda: {'count': 0, 'reset_time': time.time() + 60})

# Configuration
DEFAULT_PORT = int(os.environ.get('MAC_STUDIO_SERVER_PORT', '5050'))
ENV_HOST = os.environ.get('MAC_STUDIO_SERVER_HOST')
DB_PATH = os.path.expanduser('~/Music/audio_analysis_cache.db')
CACHE_DIR = os.path.expanduser('~/Music/AudioAnalysisCache')
os.makedirs(CACHE_DIR, exist_ok=True)

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(os.path.join(CACHE_DIR, 'server.log')),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

# SECURITY: API Key Authentication
def require_api_key(f):
    """Decorator to require API key authentication in production mode"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not PRODUCTION_MODE:
            # Development mode: no auth required
            return f(*args, **kwargs)
        
        # Production mode: require API key
        api_key = request.headers.get('X-API-Key')
        
        if not api_key:
            logger.warning(f"❌ Unauthorized request from {request.remote_addr} - No API key")
            return jsonify({'error': 'API key required', 'message': 'Include X-API-Key header'}), 401
        
        # Validate API key
        if not validate_api_key(api_key):
            logger.warning(f"❌ Invalid API key from {request.remote_addr}: {api_key[:8]}...")
            return jsonify({'error': 'Invalid API key'}), 403
        
        # Check rate limit
        if not check_rate_limit(api_key):
            logger.warning(f"⚠️ Rate limit exceeded for key {api_key[:8]}...")
            return jsonify({'error': 'Rate limit exceeded', 'message': 'Too many requests'}), 429
        
        # Log authorized request
        logger.info(f"✅ Authorized request from key {api_key[:8]}...")
        
        return f(*args, **kwargs)
    return decorated_function

def generate_api_key():
    """Generate a secure API key"""
    return secrets.token_urlsafe(32)

def validate_api_key(api_key):
    """Check if API key is valid"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    try:
        cursor.execute('SELECT id, active, daily_limit FROM api_keys WHERE key = ?', (api_key,))
        result = cursor.fetchone()
        
        if not result:
            return False
        
        key_id, active, daily_limit = result
        
        if not active:
            return False
        
        # Check daily usage limit (reuse the same connection)
        if daily_limit > 0:
            cursor.execute('''
                SELECT COUNT(*) FROM api_usage 
                WHERE api_key_id = ? AND DATE(timestamp) = DATE('now')
            ''', (key_id,))
            daily_usage = cursor.fetchone()[0]
            
            if daily_usage >= daily_limit:
                logger.warning(f"⚠️ Daily limit reached for key {api_key[:8]}...")
                return False
        
        return True
    finally:
        conn.close()

def check_rate_limit(api_key):
    """Check and update rate limit for API key"""
    current_time = time.time()
    
    if current_time > rate_limit_data[api_key]['reset_time']:
        # Reset counter
        rate_limit_data[api_key] = {'count': 0, 'reset_time': current_time + 60}
    
    rate_limit_data[api_key]['count'] += 1
    
    return rate_limit_data[api_key]['count'] <= RATE_LIMIT

def log_api_usage(api_key, endpoint, success=True):
    """Log API usage for analytics and billing"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    cursor.execute('SELECT id FROM api_keys WHERE key = ?', (api_key,))
    result = cursor.fetchone()
    
    if result:
        key_id = result[0]
        cursor.execute('''
            INSERT INTO api_usage (api_key_id, endpoint, success, timestamp)
            VALUES (?, ?, ?, CURRENT_TIMESTAMP)
        ''', (key_id, endpoint, 1 if success else 0))
        conn.commit()
    
    conn.close()

# Initialize database
def init_db():
    """Create cache database if it doesn't exist"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS analysis_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            preview_url_hash TEXT UNIQUE NOT NULL,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            preview_url TEXT NOT NULL,
            bpm REAL,
            bpm_confidence REAL,
            key TEXT,
            key_confidence REAL,
            energy REAL,
            danceability REAL,
            acousticness REAL,
            spectral_centroid REAL,
            analyzed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            analysis_duration REAL,
            user_verified INTEGER DEFAULT 0,
            manual_bpm REAL,
            manual_key TEXT,
            bpm_notes TEXT
        )
    ''')
    
    cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_hash ON analysis_cache(preview_url_hash)
    ''')
    
    cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_artist_title ON analysis_cache(artist, title)
    ''')
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS server_stats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            total_analyses INTEGER DEFAULT 0,
            cache_hits INTEGER DEFAULT 0,
            cache_misses INTEGER DEFAULT 0,
            last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    # Initialize stats if empty
    cursor.execute('SELECT COUNT(*) FROM server_stats')
    if cursor.fetchone()[0] == 0:
        cursor.execute('INSERT INTO server_stats (total_analyses, cache_hits, cache_misses) VALUES (0, 0, 0)')
    
    # API Keys table for authentication
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS api_keys (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            key TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL,
            email TEXT,
            active INTEGER DEFAULT 1,
            daily_limit INTEGER DEFAULT 1000,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_used TIMESTAMP
        )
    ''')
    
    # API Usage tracking for analytics and billing
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS api_usage (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            api_key_id INTEGER NOT NULL,
            endpoint TEXT NOT NULL,
            success INTEGER DEFAULT 1,
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (api_key_id) REFERENCES api_keys(id)
        )
    ''')
    
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_api_usage_key ON api_usage(api_key_id)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_api_usage_timestamp ON api_usage(timestamp)')
    
    conn.commit()
    conn.close()
    logger.info(f"Database initialized at {DB_PATH}")

def get_url_hash(url):
    """Generate hash for preview URL (for cache lookup)"""
    return hashlib.sha256(url.encode()).hexdigest()

def check_cache(preview_url):
    """Check if analysis already exists in cache"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    url_hash = get_url_hash(preview_url)
    cursor.execute('''
        SELECT bpm, bpm_confidence, key, key_confidence, 
               energy, danceability, acousticness, spectral_centroid,
               analyzed_at
        FROM analysis_cache 
        WHERE preview_url_hash = ?
    ''', (url_hash,))
    
    result = cursor.fetchone()
    conn.close()
    
    if result:
        logger.info(f"✅ CACHE HIT for {preview_url[:50]}...")
        return {
            'bpm': result[0],
            'bpm_confidence': result[1],
            'key': result[2],
            'key_confidence': result[3],
            'energy': result[4],
            'danceability': result[5],
            'acousticness': result[6],
            'spectral_centroid': result[7],
            'cached': True,
            'analyzed_at': result[8]
        }
    
    logger.info(f"❌ CACHE MISS for {preview_url[:50]}...")
    return None

def save_to_cache(preview_url, title, artist, analysis_result, duration):
    """Save analysis result to cache"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    url_hash = get_url_hash(preview_url)
    
    cursor.execute('''
        INSERT OR REPLACE INTO analysis_cache 
        (preview_url_hash, title, artist, preview_url, 
         bpm, bpm_confidence, key, key_confidence,
         energy, danceability, acousticness, spectral_centroid,
         analysis_duration)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', (
        url_hash,
        title,
        artist,
        preview_url,
        analysis_result['bpm'],
        analysis_result['bpm_confidence'],
        analysis_result['key'],
        analysis_result['key_confidence'],
        analysis_result['energy'],
        analysis_result['danceability'],
        analysis_result['acousticness'],
        analysis_result['spectral_centroid'],
        duration
    ))
    
    conn.commit()
    conn.close()
    logger.info(f"💾 Cached analysis for '{title}' by {artist}")

def update_stats(cache_hit):
    """Update server statistics"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    if cache_hit:
        cursor.execute('UPDATE server_stats SET cache_hits = cache_hits + 1, last_updated = CURRENT_TIMESTAMP')
    else:
        cursor.execute('UPDATE server_stats SET total_analyses = total_analyses + 1, cache_misses = cache_misses + 1, last_updated = CURRENT_TIMESTAMP')
    
    conn.commit()
    conn.close()

def analyze_audio(audio_url, title, artist):
    """Perform audio analysis using librosa"""
    import time
    start_time = time.time()
    
    logger.info(f"🎵 Analyzing '{title}' by {artist}...")
    
    try:
        # Download audio
        response = requests.get(audio_url, timeout=30)
        if response.status_code != 200:
            raise Exception(f"Failed to download audio: HTTP {response.status_code}")
        
        audio_data = BytesIO(response.content)
        logger.info(f"📥 Downloaded {len(response.content) / 1024:.1f}KB")
        
        # Load with librosa
        y, sr = librosa.load(audio_data, duration=30, sr=22050)
        logger.info(f"🔊 Loaded audio: {len(y)} samples at {sr}Hz")
        
        # Basic tempo detection for old endpoint (deprecated)
        tempo, beats = librosa.beat.beat_track(y=y, sr=sr)
        onset_env = librosa.onset.onset_strength(y=y, sr=sr)
        
        # Confidence based on beat strength consistency
        if len(beats) > 0:
            beat_strengths = onset_env[beats]
            std_val = float(np.std(beat_strengths))
            mean_val = float(np.mean(beat_strengths))
            # Calculate confidence: lower variance relative to mean = higher confidence
            variance_ratio = std_val / (mean_val + 1e-6)
            bpm_confidence = float(max(0.0, min(1.0, 1.0 - variance_ratio)))
        else:
            bpm_confidence = 0.0
        
        # 2. KEY DETECTION
        chroma = librosa.feature.chroma_cqt(y=y, sr=sr)
        chroma_sums = np.sum(chroma, axis=1)
        key_idx = int(np.argmax(chroma_sums))
        keys = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
        key = keys[key_idx]
        
        # Key confidence based on dominant chroma strength
        total_chroma = float(np.sum(chroma_sums))
        key_confidence = float(chroma_sums[key_idx]) / (total_chroma + 1e-6)
        
        # Detect major/minor (simplified)
        # Major third is 4 semitones up, minor is 3
        major_third_idx = (key_idx + 4) % 12
        minor_third_idx = (key_idx + 3) % 12
        
        if float(chroma_sums[major_third_idx]) > float(chroma_sums[minor_third_idx]):
            scale = "Major"
        else:
            scale = "Minor"
        
        full_key = f"{key} {scale}"
        
        # 3. AUDIO FEATURES
        
        # Energy (RMS energy)
        rms = librosa.feature.rms(y=y)
        energy = float(np.mean(rms))
        energy = min(energy * 3, 1.0)  # Normalize to 0-1
        
        # Spectral centroid (brightness)
        spectral_centroid = librosa.feature.spectral_centroid(y=y, sr=sr)
        avg_centroid = float(np.mean(spectral_centroid))
        
        # Acousticness (inverse of brightness) - reuse avg_centroid
        brightness = avg_centroid / 4000.0
        acousticness = 1.0 - min(brightness, 1.0)
        
        # Danceability (beat strength + regularity)
        tempogram = librosa.feature.tempogram(onset_envelope=onset_env, sr=sr)
        beat_strength = float(np.mean(tempogram))
        tempogram_std = float(np.std(tempogram))
        beat_regularity = 1.0 - (tempogram_std / (beat_strength + 1e-6))
        danceability = min((beat_strength * 2 + beat_regularity) / 2, 1.0)
        
        duration = time.time() - start_time
        
        result = {
            'bpm': float(tempo),
            'bpm_confidence': bpm_confidence,
            'key': full_key,
            'key_confidence': key_confidence,
            'energy': energy,
            'danceability': danceability,
            'acousticness': acousticness,
            'spectral_centroid': avg_centroid,
            'analysis_duration': duration,
            'cached': False
        }
        
        logger.info(f"✅ Analysis complete in {duration:.2f}s - BPM: {tempo:.1f}, Key: {full_key}")
        return result
        
    except Exception as e:
        logger.error(f"❌ Analysis failed: {str(e)}")
        raise

# API ENDPOINTS

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'running': True,
        'port': DEFAULT_PORT,
        'version': '1.0.0',
        'status': 'healthy',
        'server': 'Mac Studio Audio Analysis Server',
        'timestamp': datetime.now().isoformat()
    })

@app.route('/stats', methods=['GET'])
def get_stats():
    """Get server statistics"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    cursor.execute('SELECT total_analyses, cache_hits, cache_misses, last_updated FROM server_stats LIMIT 1')
    stats = cursor.fetchone()
    
    cursor.execute('SELECT COUNT(*) FROM analysis_cache')
    total_cached = cursor.fetchone()[0]
    
    conn.close()
    
    total = stats[0] if stats else 0
    hits = stats[1] if stats else 0
    misses = stats[2] if stats else 0
    last_updated = stats[3] if stats and len(stats) > 3 else datetime.now().isoformat()
    
    hit_rate = (hits / (hits + misses)) if (hits + misses) > 0 else 0.0
    
    return jsonify({
        'total_analyses': total,
        'cache_hits': hits,
        'cache_misses': misses,
        'cache_hit_rate': hit_rate,
        'last_updated': last_updated,
        'total_cached_songs': total_cached
    })

@app.route('/analyze', methods=['POST'])
@require_api_key
def analyze():
    """Main analysis endpoint"""
    try:
        data = request.get_json()
        
        if not data or 'url' not in data:
            return jsonify({'error': 'Missing preview URL'}), 400
        
        preview_url = data['url']
        title = data.get('title', 'Unknown')
        artist = data.get('artist', 'Unknown')
        
        logger.info(f"📨 Request: '{title}' by {artist}")
        
        # Check cache first
        cached_result = check_cache(preview_url)
        
        if cached_result:
            update_stats(cache_hit=True)
            return jsonify(cached_result)
        
        # Cache miss - analyze
        result = analyze_audio(preview_url, title, artist)
        
        # Save to cache
        save_to_cache(preview_url, title, artist, result, result['analysis_duration'])
        update_stats(cache_hit=False)
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"❌ Error: {str(e)}")
        return jsonify({
            'error': str(e),
            'message': 'Analysis failed'
        }), 500

@app.route('/analyze_data', methods=['POST'])
@require_api_key
def analyze_data():
    """Analyze audio data sent directly from iOS (Apple Music previews require iOS auth)"""
    import tempfile
    import time
    
    try:
        # Get audio data from request body
        audio_data = request.get_data()
        
        if not audio_data:
            return jsonify({'error': 'No audio data provided'}), 400
        
        # Get metadata from headers
        title = request.headers.get('X-Song-Title', 'Unknown')
        artist = request.headers.get('X-Song-Artist', 'Unknown')
        
        logger.info(f"📨 Analyzing audio data for '{title}' by {artist}")
        logger.info(f"📦 Received {len(audio_data) / 1024:.1f}KB of audio data")
        
        # Create a cache key based on title + artist (since we don't have a URL)
        cache_key = f"audiodata://{artist}/{title}"
        
        # Check cache first
        cached_result = check_cache(cache_key)
        if cached_result:
            logger.info("✅ Found in cache")
            update_stats(cache_hit=True)
            return jsonify(cached_result)
        
        # Analyze the audio data
        start_time = time.time()
        
        # Save audio data to temporary file
        # Librosa can handle M4A files directly when they're saved as actual files
        temp_fd, temp_path = tempfile.mkstemp(suffix='.m4a')
        try:
            os.write(temp_fd, audio_data)
            os.close(temp_fd)
            logger.info(f"💾 Saved to temp file: {temp_path}")
            
            # Load with librosa - it will use audioread backend for M4A
            y, sr = librosa.load(temp_path, duration=30, sr=22050)
            logger.info(f"🔊 Loaded audio: {len(y)} samples at {sr}Hz")
            
            # 1. ENHANCED TEMPO/BPM DETECTION
            
            # Skip first 0.5 seconds (intro/silence can confuse beat detection)
            trim_samples = int(0.5 * sr)
            if len(y) > trim_samples:
                y_trimmed = y[trim_samples:]
            else:
                y_trimmed = y
            
            # Harmonic-percussive separation for better beat tracking
            y_harmonic, y_percussive = librosa.effects.hpss(y_trimmed)
            
            # Method 1: Beat tracking on percussive component (most reliable for rhythm)
            tempo_percussive, beats = librosa.beat.beat_track(y=y_percussive, sr=sr)
            
            # Method 2: Tempo estimation from onset envelope (good for complex rhythms)
            onset_env = librosa.onset.onset_strength(y=y_percussive, sr=sr)
            tempo_onset = librosa.feature.tempo(onset_envelope=onset_env, sr=sr)[0]
            
            # Convert numpy arrays to Python floats immediately for safe usage
            if isinstance(tempo_percussive, np.ndarray):
                tempo_percussive_float = float(tempo_percussive.flatten()[0])
            else:
                tempo_percussive_float = float(tempo_percussive)
            
            if isinstance(tempo_onset, np.ndarray):
                tempo_onset_float = float(tempo_onset.flatten()[0])
            else:
                tempo_onset_float = float(tempo_onset)
            
            # Log the detected tempos
            logger.info(f"🎯 BPM Detection - Method 1 (beat_track): {tempo_percussive_float:.1f}, Method 2 (onset): {tempo_onset_float:.1f}")
            
            # Aggregate tempos: choose the most consistent one
            # If tempos are within 2% of each other, they agree - use their average
            if abs(tempo_percussive_float - tempo_onset_float) / tempo_onset_float < 0.02:
                tempo = (tempo_percussive_float + tempo_onset_float) / 2
                bpm_confidence = 0.95  # High confidence when methods agree
                logger.info(f"✅ BPM methods agree: using average {tempo:.1f}")
            else:
                # Methods disagree - check if one is a multiple/fraction of the other
                ratio = tempo_percussive_float / tempo_onset_float
                if 1.8 < ratio < 2.2:  # Double-time detection
                    tempo = tempo_onset_float  # Use the slower tempo (more fundamental)
                    bpm_confidence = 0.75
                    logger.info(f"⚠️ Double-time detected: using {tempo:.1f} BPM instead of {tempo_percussive_float:.1f}")
                elif 0.45 < ratio < 0.55:  # Half-time detection
                    tempo = tempo_percussive_float  # Use the faster tempo
                    bpm_confidence = 0.75
                    logger.info(f"⚠️ Half-time detected: using {tempo:.1f} BPM instead of {tempo_onset_float:.1f}")
                else:
                    # Use beat tracking result (generally more reliable)
                    tempo = tempo_percussive_float
                    bpm_confidence = 0.65  # Medium confidence when methods disagree
                    logger.info(f"⚠️ BPM methods disagree: using beat_track result {tempo:.1f}")
            
            # Additional confidence boost from beat strength consistency
            if len(beats) > 0:
                beat_strengths = onset_env[beats]
                std_val = float(np.std(beat_strengths))
                mean_val = float(np.mean(beat_strengths))
                beat_consistency = 1.0 - min(std_val / (mean_val + 1e-6), 1.0)
                bpm_confidence = float((bpm_confidence + beat_consistency) / 2)  # Average both confidence measures
            
            bpm_confidence = float(max(0.0, min(1.0, bpm_confidence)))
            
            # 2. KEY DETECTION
            chroma = librosa.feature.chroma_cqt(y=y, sr=sr)
            chroma_sums = np.sum(chroma, axis=1)
            key_idx = int(np.argmax(chroma_sums))
            keys = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
            key = keys[key_idx]
            
            # Key confidence based on dominant chroma strength
            total_chroma = float(np.sum(chroma_sums))
            key_confidence = float(chroma_sums[key_idx]) / (total_chroma + 1e-6)
            
            # Detect major/minor
            major_third_idx = (key_idx + 4) % 12
            minor_third_idx = (key_idx + 3) % 12
            
            if float(chroma_sums[major_third_idx]) > float(chroma_sums[minor_third_idx]):
                scale = "Major"
            else:
                scale = "Minor"
            
            full_key = f"{key} {scale}"
            
            # 3. AUDIO FEATURES
            
            # Energy (RMS energy)
            rms = librosa.feature.rms(y=y)
            energy = float(np.mean(rms))
            energy = min(energy * 3, 1.0)  # Normalize to 0-1
            
            # Spectral centroid (brightness)
            spectral_centroid = librosa.feature.spectral_centroid(y=y, sr=sr)
            avg_centroid = float(np.mean(spectral_centroid))
            
            # Acousticness (inverse of brightness) - reuse avg_centroid
            brightness = avg_centroid / 4000.0
            acousticness = 1.0 - min(brightness, 1.0)
            
            # Danceability (beat strength + regularity)
            tempogram = librosa.feature.tempogram(onset_envelope=onset_env, sr=sr)
            beat_strength = float(np.mean(tempogram))
            tempogram_std = float(np.std(tempogram))
            beat_regularity = 1.0 - (tempogram_std / (beat_strength + 1e-6))
            danceability = min((beat_strength * 2 + beat_regularity) / 2, 1.0)
            
            duration = time.time() - start_time
            
            # Convert tempo to Python scalar (librosa returns numpy array)
            # Handle all numpy types: scalar, 0-d array, 1-d array
            if isinstance(tempo, np.ndarray):
                bpm_value = float(tempo.flatten()[0])
            else:
                bpm_value = float(tempo)
            
            result = {
                'bpm': bpm_value,
                'bpm_confidence': bpm_confidence,
                'key': full_key,
                'key_confidence': key_confidence,
                'energy': energy,
                'danceability': danceability,
                'acousticness': acousticness,
                'spectral_centroid': avg_centroid,
                'analysis_duration': duration,
                'cached': False
            }
            
            logger.info(f"✅ Analysis complete in {duration:.2f}s - BPM: {bpm_value:.1f}, Key: {full_key}")
            
            # Save to cache
            save_to_cache(cache_key, title, artist, result, duration)
            update_stats(cache_hit=False)
            
            return jsonify(result)
            
        finally:
            # Clean up temp file
            try:
                if os.path.exists(temp_path):
                    os.unlink(temp_path)
                    logger.info(f"🗑️ Cleaned up temp file")
            except Exception as cleanup_error:
                logger.warning(f"⚠️ Could not clean up temp file: {cleanup_error}")
        
    except Exception as e:
        logger.error(f"❌ Error analyzing audio data: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({
            'error': str(e),
            'message': 'Analysis failed'
        }), 500

@app.route('/cache/search', methods=['GET'])
@require_api_key
def search_cache():
    """Search cached analyses"""
    query = request.args.get('q', '')
    
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    sql = '''
        SELECT id, title, artist, preview_url, bpm, bpm_confidence, key, key_confidence,
               energy, danceability, acousticness, spectral_centroid, analyzed_at,
               analysis_duration, user_verified, manual_bpm, manual_key, bpm_notes
        FROM analysis_cache
        WHERE artist LIKE ? OR title LIKE ?
        ORDER BY analyzed_at DESC
        LIMIT 100
    '''
    
    cursor.execute(sql, (f"%{query}%", f"%{query}%"))
    results = cursor.fetchall()
    conn.close()
    
    songs = [{
        'id': r[0],
        'title': r[1],
        'artist': r[2],
        'preview_url': r[3],
        'bpm': r[4],
        'bpm_confidence': r[5],
        'key': r[6],
        'key_confidence': r[7],
        'energy': r[8],
        'danceability': r[9],
        'acousticness': r[10],
        'spectral_centroid': r[11],
        'analyzed_at': r[12],
        'analysis_duration': r[13],
        'user_verified': bool(r[14]),
        'manual_bpm': r[15],
        'manual_key': r[16],
        'bpm_notes': r[17]
    } for r in results]
    
    return jsonify(songs)

@app.route('/cache', methods=['GET'])
def get_cache():
    """Get cached analyses with pagination"""
    limit = request.args.get('limit', 100, type=int)
    offset = request.args.get('offset', 0, type=int)
    
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    cursor.execute('''
        SELECT id, title, artist, preview_url, bpm, bpm_confidence, key, key_confidence,
               energy, danceability, acousticness, spectral_centroid, analyzed_at,
               analysis_duration, user_verified, manual_bpm, manual_key, bpm_notes
        FROM analysis_cache
        ORDER BY analyzed_at DESC
        LIMIT ? OFFSET ?
    ''', (limit, offset))
    
    results = cursor.fetchall()
    conn.close()
    
    songs = [{
        'id': r[0],
        'title': r[1],
        'artist': r[2],
        'preview_url': r[3],
        'bpm': r[4],
        'bpm_confidence': r[5],
        'key': r[6],
        'key_confidence': r[7],
        'energy': r[8],
        'danceability': r[9],
        'acousticness': r[10],
        'spectral_centroid': r[11],
        'analyzed_at': r[12],
        'analysis_duration': r[13],
        'user_verified': bool(r[14]),
        'manual_bpm': r[15],
        'manual_key': r[16],
        'bpm_notes': r[17]
    } for r in results]
    
    return jsonify(songs)

@app.route('/cache/<int:cache_id>', methods=['DELETE'])
def delete_cache_item(cache_id):
    """Delete a specific cached analysis"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        cursor.execute('DELETE FROM analysis_cache WHERE id = ?', (cache_id,))
        conn.commit()
        conn.close()
        
        logger.info(f"🗑️ Deleted cache item {cache_id}")
        
        return jsonify({
            'success': True,
            'message': f'Deleted cache item {cache_id}'
        })
    except Exception as e:
        logger.error(f"❌ Error deleting cache item: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/cache/clear', methods=['POST'])
def clear_cache():
    """Clear all cached analyses"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        cursor.execute('DELETE FROM analysis_cache')
        cursor.execute('UPDATE server_stats SET total_analyses = 0, cache_hits = 0, cache_misses = 0')
        conn.commit()
        conn.close()
        
        logger.info("🗑️ Cleared all cache")
        
        return jsonify({
            'success': True,
            'message': 'Cache cleared'
        })
    except Exception as e:
        logger.error(f"❌ Error clearing cache: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/cache/export', methods=['GET'])
def export_cache():
    """Export entire cache as JSON"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    cursor.execute('''
        SELECT title, artist, bpm, key, energy, danceability, acousticness, analyzed_at
        FROM analysis_cache
        ORDER BY artist, title
    ''')
    
    results = cursor.fetchall()
    conn.close()
    
    songs = [{
        'title': r[0],
        'artist': r[1],
        'bpm': r[2],
        'key': r[3],
        'energy': r[4],
        'danceability': r[5],
        'acousticness': r[6],
        'analyzed_at': r[7]
    } for r in results]
    
    return jsonify({
        'total_songs': len(songs),
        'exported_at': datetime.now().isoformat(),
        'songs': songs
    })

@app.route('/shutdown', methods=['POST'])
def shutdown():
    """Shutdown the server"""
    logger.info("🛑 Server shutdown requested")
    func = request.environ.get('werkzeug.server.shutdown')
    if func is None:
        return jsonify({'error': 'Not running with Werkzeug Server'}), 500
    func()
    return jsonify({'message': 'Server shutting down...'})

@app.route('/verify', methods=['POST'])
def verify_manual():
    """Manual verification and override endpoint"""
    try:
        data = request.get_json()
        
        if not data or 'url' not in data:
            return jsonify({'error': 'Missing preview URL'}), 400
        
        preview_url = data['url']
        url_hash = get_url_hash(preview_url)
        
        # Optional manual overrides
        manual_bpm = data.get('manual_bpm')
        manual_key = data.get('manual_key')
        bpm_notes = data.get('bpm_notes')  # e.g., "Starts at 82, goes to 168"
        
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # Update verification status and manual overrides
        cursor.execute('''
            UPDATE analysis_cache 
            SET user_verified = 1,
                manual_bpm = ?,
                manual_key = ?,
                bpm_notes = ?
            WHERE preview_url_hash = ?
        ''', (manual_bpm, manual_key, bpm_notes, url_hash))
        
        conn.commit()
        conn.close()
        
        logger.info(f"✅ User verified: {data.get('title', 'Unknown')} - Manual BPM: {manual_bpm}, Notes: {bpm_notes}")
        
        return jsonify({
            'success': True,
            'message': 'Song verified and updated'
        })
        
    except Exception as e:
        logger.error(f"❌ Verification error: {str(e)}")
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    print("=" * 60)
    print("🎵 Mac Studio Audio Analysis Server")
    print("=" * 60)
    print(f"📂 Database: {DB_PATH}")
    print(f"📁 Cache Dir: {CACHE_DIR}")
    print("🚀 Initializing...")
    
    init_db()
    
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
    
    app.run(host=bind_host, port=DEFAULT_PORT, debug=False)
