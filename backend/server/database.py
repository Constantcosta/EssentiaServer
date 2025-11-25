"""Database helpers: configuration, pooled connections, schema setup."""

from __future__ import annotations

import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path
from threading import Lock
from typing import Optional
import logging

logger = logging.getLogger(__name__)

_DB_PATH: Optional[str] = None
_db_lock = Lock()
_db_cache: dict[int, sqlite3.Connection] = {}


def configure_database(db_path: str):
    """Configure the sqlite path used by connection helpers."""
    global _DB_PATH
    _DB_PATH = db_path


def _create_db_connection() -> sqlite3.Connection:
    if _DB_PATH is None:
        raise RuntimeError("Database path not configured.")
    conn = sqlite3.connect(_DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


@contextmanager
def get_db_connection():
    """Context manager for database connections with basic pooling."""
    if _DB_PATH is None:
        raise RuntimeError("Database path not configured.")
    thread_id = id(time.time())
    with _db_lock:
        if thread_id not in _db_cache:
            _db_cache[thread_id] = _create_db_connection()
    conn = _db_cache.get(thread_id) or _create_db_connection()
    try:
        yield conn
    finally:
        if conn:
            conn.commit()


def initialize_database():
    """Create tables and indexes if they do not yet exist."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS analysis_cache (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                preview_url_hash TEXT UNIQUE NOT NULL,
                title TEXT NOT NULL,
                artist TEXT NOT NULL,
                preview_url TEXT NOT NULL,
                cache_namespace TEXT DEFAULT 'default',
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
                bpm_notes TEXT,
                time_signature TEXT,
                valence REAL,
                mood TEXT,
                loudness REAL,
                dynamic_range REAL,
                silence_ratio REAL,
                key_details TEXT,
                chunk_analysis TEXT,
                analysis_timing TEXT,
                dynamic_complexity REAL,
                tonal_strength REAL,
                spectral_complexity REAL,
                zero_crossing_rate REAL,
                spectral_flux REAL,
                percussive_energy_ratio REAL,
                harmonic_energy_ratio REAL
            )
            """
        )

        for column_def in [
            ("cache_namespace", "TEXT DEFAULT 'default'"),
            ("time_signature", "TEXT"),
            ("valence", "REAL"),
            ("mood", "TEXT"),
            ("loudness", "REAL"),
            ("dynamic_range", "REAL"),
            ("silence_ratio", "REAL"),
            ("key_details", "TEXT"),
            ("chunk_analysis", "TEXT"),
            ("analysis_timing", "TEXT"),
            ("dynamic_complexity", "REAL"),
            ("tonal_strength", "REAL"),
            ("spectral_complexity", "REAL"),
            ("zero_crossing_rate", "REAL"),
            ("spectral_flux", "REAL"),
            ("percussive_energy_ratio", "REAL"),
            ("harmonic_energy_ratio", "REAL"),
        ]:
            try:
                cursor.execute(
                    f"ALTER TABLE analysis_cache ADD COLUMN {column_def[0]} {column_def[1]}"
                )
            except sqlite3.OperationalError:
                pass

        cursor.execute(
            "CREATE INDEX IF NOT EXISTS idx_hash ON analysis_cache(preview_url_hash)"
        )
        cursor.execute(
            "CREATE INDEX IF NOT EXISTS idx_artist_title ON analysis_cache(artist, title)"
        )
        cursor.execute(
            "CREATE INDEX IF NOT EXISTS idx_namespace_analyzed ON analysis_cache(cache_namespace, analyzed_at)"
        )

        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS server_stats (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                total_analyses INTEGER DEFAULT 0,
                cache_hits INTEGER DEFAULT 0,
                cache_misses INTEGER DEFAULT 0,
                last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        cursor.execute("SELECT COUNT(*) FROM server_stats")
        if cursor.fetchone()[0] == 0:
            cursor.execute(
                "INSERT INTO server_stats (total_analyses, cache_hits, cache_misses) VALUES (0, 0, 0)"
            )

        cursor.execute(
            """
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
            """
        )
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS api_usage (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                api_key_id INTEGER NOT NULL,
                endpoint TEXT NOT NULL,
                success INTEGER DEFAULT 1,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (api_key_id) REFERENCES api_keys(id)
            )
            """
        )

    logger.info("Database initialized at %s", _DB_PATH)


__all__ = ["configure_database", "get_db_connection", "initialize_database"]
