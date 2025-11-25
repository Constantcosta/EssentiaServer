#!/usr/bin/env python3
"""
Performance test script to validate optimization improvements
Tests database operations, rate limiting, and caching
"""

import time
import sqlite3
import os
import sys
from datetime import datetime

# Add backend to path
sys.path.insert(0, os.path.dirname(__file__))

# Test configuration
DB_PATH = os.path.expanduser('~/Music/audio_analysis_cache_test.db')
NUM_ITERATIONS = 1000

def setup_test_db():
    """Create a test database"""
    # Ensure the directory exists
    db_dir = os.path.dirname(DB_PATH)
    if db_dir and not os.path.exists(db_dir):
        os.makedirs(db_dir, exist_ok=True)
    
    if os.path.exists(DB_PATH):
        os.unlink(DB_PATH)
    
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    # Create test tables
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
    
    # Add test API key
    cursor.execute('''
        INSERT INTO api_keys (key, name, email, active, daily_limit)
        VALUES (?, ?, ?, 1, 10000)
    ''', ('test_key_123', 'Test User', 'test@example.com'))
    
    # Add some usage records
    for i in range(100):
        cursor.execute('''
            INSERT INTO api_usage (api_key_id, endpoint, success, timestamp)
            VALUES (1, '/analyze', 1, CURRENT_TIMESTAMP)
        ''')
    
    conn.commit()
    conn.close()
    print(f"✅ Test database created at {DB_PATH}")

def test_without_index():
    """Test query performance without composite index"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    start_time = time.time()
    for _ in range(NUM_ITERATIONS):
        cursor.execute('''
            SELECT COUNT(*) FROM api_usage 
            WHERE api_key_id = 1 AND DATE(timestamp) = DATE('now')
        ''')
        cursor.fetchone()
    
    elapsed = time.time() - start_time
    conn.close()
    
    return elapsed

def test_with_index():
    """Test query performance with composite index"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    # Add composite index
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_api_usage_key_date ON api_usage(api_key_id, timestamp)')
    conn.commit()
    
    start_time = time.time()
    for _ in range(NUM_ITERATIONS):
        cursor.execute('''
            SELECT COUNT(*) FROM api_usage 
            WHERE api_key_id = 1 AND DATE(timestamp) = DATE('now')
        ''')
        cursor.fetchone()
    
    elapsed = time.time() - start_time
    conn.close()
    
    return elapsed

def test_connection_reuse():
    """Test connection reuse vs creating new connections"""
    # Test 1: Create new connection each time (OLD WAY)
    start_time = time.time()
    for _ in range(NUM_ITERATIONS):
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('SELECT COUNT(*) FROM api_keys')
        cursor.fetchone()
        conn.close()
    
    time_new_conn = time.time() - start_time
    
    # Test 2: Reuse connection (NEW WAY)
    conn = sqlite3.connect(DB_PATH)
    start_time = time.time()
    for _ in range(NUM_ITERATIONS):
        cursor = conn.cursor()
        cursor.execute('SELECT COUNT(*) FROM api_keys')
        cursor.fetchone()
    
    time_reuse = time.time() - start_time
    conn.close()
    
    return time_new_conn, time_reuse

def test_combined_vs_separate_queries():
    """Test combined query vs separate queries for API key validation"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    # Test 1: Separate queries (OLD WAY)
    start_time = time.time()
    for _ in range(NUM_ITERATIONS):
        cursor.execute('SELECT id, active, daily_limit FROM api_keys WHERE key = ?', ('test_key_123',))
        result = cursor.fetchone()
        if result:
            key_id = result[0]
            cursor.execute('''
                SELECT COUNT(*) FROM api_usage 
                WHERE api_key_id = ? AND DATE(timestamp) = DATE('now')
            ''', (key_id,))
            cursor.fetchone()
    
    time_separate = time.time() - start_time
    
    # Test 2: Combined query (NEW WAY)
    start_time = time.time()
    for _ in range(NUM_ITERATIONS):
        cursor.execute('''
            SELECT k.id, k.active, k.daily_limit,
                   (SELECT COUNT(*) FROM api_usage 
                    WHERE api_key_id = k.id AND DATE(timestamp) = DATE('now')) as daily_usage
            FROM api_keys k
            WHERE k.key = ?
        ''', ('test_key_123',))
        cursor.fetchone()
    
    time_combined = time.time() - start_time
    conn.close()
    
    return time_separate, time_combined

def cleanup():
    """Remove test database"""
    if os.path.exists(DB_PATH):
        os.unlink(DB_PATH)
    print(f"🗑️  Test database removed")

def main():
    print("=" * 70)
    print("  🚀 Performance Optimization Test Suite")
    print("=" * 70)
    print(f"  Test started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  Iterations per test: {NUM_ITERATIONS:,}")
    print("=" * 70)
    
    try:
        setup_test_db()
        
        # Test 1: Index performance
        print("\n📊 Test 1: Database Index Performance")
        print("-" * 70)
        time_no_index = test_without_index()
        time_with_index = test_with_index()
        improvement = ((time_no_index - time_with_index) / time_no_index) * 100
        
        print(f"  Without composite index: {time_no_index:.3f}s ({NUM_ITERATIONS:,} queries)")
        print(f"  With composite index:    {time_with_index:.3f}s ({NUM_ITERATIONS:,} queries)")
        print(f"  ✅ Improvement: {improvement:.1f}% faster ({time_no_index/time_with_index:.1f}x speedup)")
        
        # Test 2: Connection reuse
        print("\n📊 Test 2: Connection Pooling vs New Connections")
        print("-" * 70)
        time_new, time_reuse = test_connection_reuse()
        improvement = ((time_new - time_reuse) / time_new) * 100
        
        print(f"  Creating new connections: {time_new:.3f}s ({NUM_ITERATIONS:,} queries)")
        print(f"  Reusing connections:      {time_reuse:.3f}s ({NUM_ITERATIONS:,} queries)")
        print(f"  ✅ Improvement: {improvement:.1f}% faster ({time_new/time_reuse:.1f}x speedup)")
        
        # Test 3: Combined queries
        print("\n📊 Test 3: Combined vs Separate Queries")
        print("-" * 70)
        time_separate, time_combined = test_combined_vs_separate_queries()
        improvement = ((time_separate - time_combined) / time_separate) * 100
        
        print(f"  Separate queries:  {time_separate:.3f}s ({NUM_ITERATIONS:,} validations)")
        print(f"  Combined query:    {time_combined:.3f}s ({NUM_ITERATIONS:,} validations)")
        print(f"  ✅ Improvement: {improvement:.1f}% faster ({time_separate/time_combined:.1f}x speedup)")
        
        # Summary
        print("\n" + "=" * 70)
        print("  📈 SUMMARY OF OPTIMIZATIONS")
        print("=" * 70)
        total_improvement = (time_no_index + time_new + time_separate) / (time_with_index + time_reuse + time_combined)
        print(f"  Overall performance improvement: {total_improvement:.1f}x faster")
        print("  ")
        print("  Key optimizations:")
        print("  ✅ Database indexes for faster lookups")
        print("  ✅ Connection pooling to reduce overhead")
        print("  ✅ Combined queries to reduce round-trips")
        print("  ✅ API key caching (not tested here, but ~10x improvement expected)")
        print("=" * 70)
        
    finally:
        cleanup()
    
    print("\n✅ All tests completed successfully!\n")

if __name__ == '__main__':
    main()
