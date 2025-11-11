#!/usr/bin/env python3
"""
API Key Management Tool for Mac Studio Audio Analysis Server
Manage API keys for users, beta testers, and commercial clients
"""

import sqlite3
import secrets
import sys
from datetime import datetime
import os

DB_PATH = os.path.expanduser('~/Music/audio_analysis_cache.db')

def generate_api_key():
    """Generate a secure API key"""
    return secrets.token_urlsafe(32)

def create_api_key(name, email=None, daily_limit=1000):
    """Create a new API key"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    api_key = generate_api_key()
    
    try:
        cursor.execute('''
            INSERT INTO api_keys (key, name, email, active, daily_limit)
            VALUES (?, ?, ?, 1, ?)
        ''', (api_key, name, email, daily_limit))
        conn.commit()
        
        print("=" * 60)
        print("✅ API Key Created Successfully!")
        print("=" * 60)
        print(f"Name:        {name}")
        print(f"Email:       {email or 'N/A'}")
        print(f"Daily Limit: {daily_limit} requests/day")
        print(f"API Key:     {api_key}")
        print("=" * 60)
        print("\n⚠️  IMPORTANT: Save this key securely!")
        print("This is the only time it will be displayed in full.")
        print("\nAdd to app configuration:")
        print(f'  X-API-Key: {api_key}')
        print("=" * 60)
        
        return api_key
    except sqlite3.IntegrityError:
        print("❌ Error: Could not create API key")
        return None
    finally:
        conn.close()

def list_api_keys():
    """List all API keys"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    cursor.execute('''
        SELECT id, name, email, active, daily_limit, created_at,
               (SELECT COUNT(*) FROM api_usage WHERE api_key_id = api_keys.id) as total_usage
        FROM api_keys
        ORDER BY created_at DESC
    ''')
    
    keys = cursor.fetchall()
    conn.close()
    
    if not keys:
        print("No API keys found.")
        return
    
    print("\n" + "=" * 100)
    print(f"{'ID':<5} {'Name':<20} {'Email':<25} {'Status':<10} {'Limit/Day':<12} {'Usage':<10} {'Created':<20}")
    print("=" * 100)
    
    for key in keys:
        key_id, name, email, active, daily_limit, created_at, total_usage = key
        status = "✅ Active" if active else "❌ Disabled"
        print(f"{key_id:<5} {name:<20} {(email or 'N/A'):<25} {status:<10} {daily_limit:<12} {total_usage:<10} {created_at:<20}")
    
    print("=" * 100 + "\n")

def show_key_details(key_id):
    """Show detailed information about a specific API key"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    # Get key info
    cursor.execute('''
        SELECT key, name, email, active, daily_limit, created_at, last_used
        FROM api_keys WHERE id = ?
    ''', (key_id,))
    
    key_info = cursor.fetchone()
    
    if not key_info:
        print(f"❌ API key with ID {key_id} not found")
        conn.close()
        return
    
    api_key, name, email, active, daily_limit, created_at, last_used = key_info
    
    # Get usage stats
    cursor.execute('''
        SELECT 
            COUNT(*) as total_requests,
            COUNT(CASE WHEN success = 1 THEN 1 END) as successful_requests,
            COUNT(CASE WHEN DATE(timestamp) = DATE('now') THEN 1 END) as today_requests
        FROM api_usage WHERE api_key_id = ?
    ''', (key_id,))
    
    usage_stats = cursor.fetchone()
    total_requests, successful_requests, today_requests = usage_stats
    
    # Get recent usage
    cursor.execute('''
        SELECT endpoint, success, timestamp
        FROM api_usage
        WHERE api_key_id = ?
        ORDER BY timestamp DESC
        LIMIT 10
    ''', (key_id,))
    
    recent_usage = cursor.fetchall()
    conn.close()
    
    print("\n" + "=" * 60)
    print(f"API Key Details - ID: {key_id}")
    print("=" * 60)
    print(f"Name:              {name}")
    print(f"Email:             {email or 'N/A'}")
    print(f"Status:            {'✅ Active' if active else '❌ Disabled'}")
    print(f"Daily Limit:       {daily_limit} requests/day")
    print(f"Created:           {created_at}")
    print(f"Last Used:         {last_used or 'Never'}")
    print(f"\nAPI Key:           {api_key[:16]}...{api_key[-8:]}")
    print("\n" + "-" * 60)
    print("Usage Statistics:")
    print("-" * 60)
    print(f"Total Requests:    {total_requests}")
    print(f"Successful:        {successful_requests}")
    print(f"Today:             {today_requests}/{daily_limit}")
    
    if recent_usage:
        print("\n" + "-" * 60)
        print("Recent Activity (Last 10 requests):")
        print("-" * 60)
        for endpoint, success, timestamp in recent_usage:
            status = "✅" if success else "❌"
            print(f"{status} {timestamp} - {endpoint}")
    
    print("=" * 60 + "\n")

def deactivate_key(key_id):
    """Deactivate an API key"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    cursor.execute('UPDATE api_keys SET active = 0 WHERE id = ?', (key_id,))
    
    if cursor.rowcount > 0:
        conn.commit()
        print(f"✅ API key {key_id} deactivated")
    else:
        print(f"❌ API key {key_id} not found")
    
    conn.close()

def activate_key(key_id):
    """Activate an API key"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    cursor.execute('UPDATE api_keys SET active = 1 WHERE id = ?', (key_id,))
    
    if cursor.rowcount > 0:
        conn.commit()
        print(f"✅ API key {key_id} activated")
    else:
        print(f"❌ API key {key_id} not found")
    
    conn.close()

def update_daily_limit(key_id, new_limit):
    """Update daily request limit for an API key"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    cursor.execute('UPDATE api_keys SET daily_limit = ? WHERE id = ?', (new_limit, key_id))
    
    if cursor.rowcount > 0:
        conn.commit()
        print(f"✅ Daily limit for key {key_id} updated to {new_limit}")
    else:
        print(f"❌ API key {key_id} not found")
    
    conn.close()

def delete_key(key_id):
    """Delete an API key (use with caution!)"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    # Get key name first
    cursor.execute('SELECT name FROM api_keys WHERE id = ?', (key_id,))
    result = cursor.fetchone()
    
    if not result:
        print(f"❌ API key {key_id} not found")
        conn.close()
        return
    
    name = result[0]
    
    print(f"\n⚠️  WARNING: You are about to DELETE API key #{key_id} ({name})")
    print("This action CANNOT be undone!")
    confirm = input("Type 'DELETE' to confirm: ")
    
    if confirm == "DELETE":
        cursor.execute('DELETE FROM api_usage WHERE api_key_id = ?', (key_id,))
        cursor.execute('DELETE FROM api_keys WHERE id = ?', (key_id,))
        conn.commit()
        print(f"✅ API key {key_id} deleted")
    else:
        print("❌ Deletion cancelled")
    
    conn.close()

def show_usage():
    """Show command usage"""
    print("""
Mac Studio Audio Analysis Server - API Key Manager

Usage:
    python manage_api_keys.py <command> [options]

Commands:
    create <name> [email] [daily_limit]  - Create a new API key
    list                                  - List all API keys
    show <id>                            - Show detailed info about a key
    activate <id>                        - Activate an API key
    deactivate <id>                      - Deactivate an API key
    limit <id> <new_limit>               - Update daily request limit
    delete <id>                          - Delete an API key (permanent!)

Examples:
    # Create key for yourself (unlimited)
    python manage_api_keys.py create "Costas iPhone" costas@email.com 0

    # Create key for beta tester (1000/day)
    python manage_api_keys.py create "Beta Tester 1" tester@email.com 1000

    # Create key for commercial client (10000/day)
    python manage_api_keys.py create "DJ Pro Client" client@email.com 10000

    # List all keys
    python manage_api_keys.py list

    # Show details
    python manage_api_keys.py show 1

    # Deactivate a key
    python manage_api_keys.py deactivate 2
    """)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        show_usage()
        sys.exit(1)
    
    command = sys.argv[1].lower()
    
    if command == 'create':
        if len(sys.argv) < 3:
            print("❌ Error: Name required")
            print("Usage: python manage_api_keys.py create <name> [email] [daily_limit]")
            sys.exit(1)
        
        name = sys.argv[2]
        email = sys.argv[3] if len(sys.argv) > 3 else None
        daily_limit = int(sys.argv[4]) if len(sys.argv) > 4 else 1000
        
        create_api_key(name, email, daily_limit)
    
    elif command == 'list':
        list_api_keys()
    
    elif command == 'show':
        if len(sys.argv) < 3:
            print("❌ Error: Key ID required")
            sys.exit(1)
        key_id = int(sys.argv[2])
        show_key_details(key_id)
    
    elif command == 'activate':
        if len(sys.argv) < 3:
            print("❌ Error: Key ID required")
            sys.exit(1)
        key_id = int(sys.argv[2])
        activate_key(key_id)
    
    elif command == 'deactivate':
        if len(sys.argv) < 3:
            print("❌ Error: Key ID required")
            sys.exit(1)
        key_id = int(sys.argv[2])
        deactivate_key(key_id)
    
    elif command == 'limit':
        if len(sys.argv) < 4:
            print("❌ Error: Key ID and new limit required")
            sys.exit(1)
        key_id = int(sys.argv[2])
        new_limit = int(sys.argv[3])
        update_daily_limit(key_id, new_limit)
    
    elif command == 'delete':
        if len(sys.argv) < 3:
            print("❌ Error: Key ID required")
            sys.exit(1)
        key_id = int(sys.argv[2])
        delete_key(key_id)
    
    else:
        print(f"❌ Unknown command: {command}")
        show_usage()
        sys.exit(1)
