#!/usr/bin/env python3
"""Utilities for canonicalizing musical key strings."""
from __future__ import annotations

from typing import Optional, Tuple

NOTE_NAMES_SHARP = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

NOTE_ALIAS_MAP = {
    "cb": "B",
    "b#": "C",
    "db": "C#",
    "eb": "D#",
    "fb": "E",
    "e#": "F",
    "gb": "F#",
    "ab": "G#",
    "bb": "A#",
    "c#": "C#",
    "d#": "D#",
    "f#": "F#",
    "g#": "G#",
    "a#": "A#",
}

MODE_ALIASES = {
    "maj": "major",
    "major": "major",
    "ionian": "major",
    "min": "minor",
    "minor": "minor",
    "aeolian": "minor",
}


def _normalize_note_text(text: str) -> str:
    text = text.replace("♯", "#").replace("♭", "b")
    text = text.replace("sharp", "#").replace("flat", "b")
    return text


def normalize_key_label(label: Optional[str]) -> Optional[Tuple[int, str]]:
    """Convert an arbitrary key label to (root_index, mode)."""
    if not label:
        return None
    text = _normalize_note_text(str(label).strip().lower())
    if not text:
        return None
    mode = "major"
    for alias, canonical in MODE_ALIASES.items():
        if alias in text.split():
            mode = canonical
            text = text.replace(alias, "")
    text = text.replace("major", "").replace("minor", "").strip()
    if not text:
        return None
    root_token = text.split()[0]
    if "/" in root_token:
        root_token = root_token.split("/", 1)[0]
    root_token = root_token.strip()
    if not root_token:
        return None
    root_token = NOTE_ALIAS_MAP.get(root_token, root_token)
    try:
        root_index = NOTE_NAMES_SHARP.index(root_token.upper())
    except ValueError:
        return None
    return root_index, mode


def canonical_key_id(root_index: int, mode: str) -> str:
    return f"{int(root_index)}:{mode}"


def parse_canonical_key_id(identifier: str) -> Optional[Tuple[int, str]]:
    if not identifier or ":" not in identifier:
        return None
    root_text, mode = identifier.split(":", 1)
    try:
        root_index = int(root_text)
    except ValueError:
        return None
    return root_index % 12, mode


def format_canonical_key(root_index: int, mode: str, prefer_flats: bool = False) -> str:
    sharps = NOTE_NAMES_SHARP
    flats = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    names = flats if prefer_flats else sharps
    root = names[root_index % 12]
    suffix = "minor" if mode == "minor" else "major"
    return f"{root} {suffix}"


def keys_match_fuzzy(key1: Optional[str], key2: Optional[str]) -> Tuple[bool, str]:
    """
    Compare two keys with enharmonic matching.
    
    Returns:
        (match: bool, reason: str) - True if keys match exactly or are enharmonic equivalents
    
    Matching rules:
    1. Exact match (e.g., "D# Minor" == "D# Minor")
    2. Enharmonic equivalent (e.g., "D# Minor" == "Eb Minor", "G#/Ab" == "Ab")
    """
    if not key1 or not key2:
        return (False, "missing key")
    
    parsed1 = normalize_key_label(key1)
    parsed2 = normalize_key_label(key2)
    
    if not parsed1 or not parsed2:
        return (False, "unparseable key")
    
    root1, mode1 = parsed1
    root2, mode2 = parsed2
    
    # Exact match (same root and mode)
    if root1 == root2 and mode1 == mode2:
        return (True, "exact")
    
    return (False, "different")


__all__ = [
    "NOTE_NAMES_SHARP",
    "normalize_key_label",
    "canonical_key_id",
    "parse_canonical_key_id",
    "format_canonical_key",
    "keys_match_fuzzy",
]
