"""Shared utilities for the audio analysis test suite."""

from __future__ import annotations

import csv
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional


class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    RESET = '\033[0m'
    BOLD = '\033[1m'


def print_header(text: str):
    print(f"\n{Colors.BOLD}{Colors.BLUE}{'='*80}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}{text.center(80)}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}{'='*80}{Colors.RESET}\n")


def print_success(text: str):
    print(f"{Colors.GREEN}✓ {text}{Colors.RESET}")


def print_error(text: str):
    print(f"{Colors.RED}✗ {text}{Colors.RESET}")


def print_warning(text: str):
    print(f"{Colors.YELLOW}⚠ {text}{Colors.RESET}")


def print_info(text: str):
    print(f"{Colors.BLUE}ℹ {text}{Colors.RESET}")


def save_results_to_csv(results: List[Dict], filename: Optional[str] = None):
    """Save analysis results to CSV file."""
    if not results:
        print_warning("No results to save")
        return None

    if filename is None:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"test_results_{timestamp}.csv"

    repo_root = Path(__file__).parent.parent
    csv_dir = repo_root / "csv"
    csv_dir.mkdir(exist_ok=True)
    filepath = csv_dir / filename

    fieldnames = [
        'test_type',
        'song_title',
        'artist',
        'file_type',
        'success',
        'duration_s',
        'bpm',
        'key',
        'energy',
        'danceability',
        'valence',
        'acousticness',
        'instrumentalness',
        'liveness',
        'speechiness',
        'error',
    ]

    with open(filepath, 'w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()

        for result in results:
            row = {
                'test_type': result.get('test_type', 'unknown'),
                'song_title': result.get('song', 'unknown'),
                'artist': result.get('artist', 'unknown'),
                'file_type': result.get('file_type', 'unknown'),
                'success': result.get('success', False),
                'duration_s': result.get('duration', ''),
                'bpm': '',
                'key': '',
                'energy': '',
                'danceability': '',
                'valence': '',
                'acousticness': '',
                'instrumentalness': '',
                'liveness': '',
                'speechiness': '',
                'error': result.get('error', ''),
            }

            if result.get('data'):
                data = result['data']
                row.update({
                    'bpm': data.get('bpm', ''),
                    'key': data.get('key', ''),
                    'energy': data.get('energy', ''),
                    'danceability': data.get('danceability', ''),
                    'valence': data.get('valence', ''),
                    'acousticness': data.get('acousticness', ''),
                    'instrumentalness': data.get('instrumentalness', ''),
                    'liveness': data.get('liveness', ''),
                    'speechiness': data.get('speechiness', ''),
                })

            writer.writerow(row)

    print_success(f"Results saved to {filepath}")
    return filepath


__all__ = [
    "Colors",
    "print_header",
    "print_success",
    "print_error",
    "print_warning",
    "print_info",
    "save_results_to_csv",
]
