#!/usr/bin/env python3
"""Utilities for canonicalizing musical key strings."""
from __future__ import annotations

from typing import Optional, Tuple

NOTE_NAMES_SHARP = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

MODE_ALIASES = {
    "maj": "major",
    "major": "major",
    "ionian": "major",
    "min": "minor",
    "minor": "minor",
    "aeolian": "minor",
    "mixolydian": "mixolydian",
    "mixo": "mixolydian",
    "lydian": "lydian",
    "dorian": "dorian",
    "phrygian": "phrygian",
    "locrian": "locrian",
}


def _normalize_note_text(text: str) -> str:
    text = text.replace("♯", "#").replace("♭", "b")
    text = text.replace("sharp", "#").replace("flat", "b")
    return text


def _pitch_class_from_token(token: str) -> Optional[int]:
    """Convert a note token (e.g., c, db, d##, cb) into a pitch class 0–11."""
    if not token:
        return None
    token = token.strip().lower()
    if not token:
        return None
    base_map = {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}
    base = token[0]
    if base not in base_map:
        return None
    pitch = base_map[base]
    for accidental in token[1:]:
        if accidental == "#":
            pitch += 1
        elif accidental == "b":
            pitch -= 1
        elif accidental == "x":  # double-sharp shorthand
            pitch += 2
        else:
            return None
    return pitch % 12


def normalize_key_label(label: Optional[str]) -> Optional[Tuple[int, str]]:
    """Convert an arbitrary key label to (root_index, mode)."""
    if not label:
        return None
    text = _normalize_note_text(str(label))
    text = text.replace("-", "").replace("_", "")
    text = text.strip().lower()
    if not text:
        return None

    # Detect mode before stripping mode tokens
    mode: Optional[str] = None
    raw_tokens = text.replace("/", " ").split()
    if any(tok in MODE_ALIASES for tok in raw_tokens):
        for tok in raw_tokens:
            if tok in MODE_ALIASES:
                mode = MODE_ALIASES[tok]
                break
    if mode is None:
        # Fallback: if the mode token is attached to the tonic (e.g., "cmixolydian")
        for token, canonical in MODE_ALIASES.items():
            if token in text:
                mode = canonical
                break
    if mode is None and text.endswith("m"):
        mode = "minor"
    if mode is None:
        mode = "major"

    # Remove mode markers to leave only the tonic spelling
    for alias in sorted(MODE_ALIASES.keys(), key=len, reverse=True):
        text = text.replace(alias, "")
    text = text.replace("major", "").replace("minor", "")
    if text.endswith("m"):
        text = text[:-1]
    text = text.strip()
    if not text:
        return None

    # Drop any non-note/accidental/slash characters introduced by metadata
    import re  # Local import to avoid module cost for callers that don't need regex
    text = re.sub(r"[^a-g#/xb]+", "", text, flags=re.IGNORECASE)
    if not text:
        return None

    # Support slash tokens (use the first parsable tonic)
    for root_token in text.split("/"):
        root_token = root_token.strip()
        if not root_token:
            continue
        root_index = _pitch_class_from_token(root_token)
        if root_index is not None:
            return root_index, mode

    # Fallback: grab first note-like token (handles ellipses or other noise)
    note_tokens = re.findall(r"[a-g][#bx]*", text)
    if note_tokens:
        root_index = _pitch_class_from_token(note_tokens[0])
        if root_index is not None:
            return root_index, mode
    return None


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
    if mode == "minor":
        suffix = "minor"
    elif mode == "major":
        suffix = "major"
    else:
        suffix = mode
    return f"{root} {suffix}"


def keys_match_fuzzy(key1: Optional[str], key2: Optional[str]) -> Tuple[bool, str]:
    """
    Compare two keys with enharmonic matching.
    
    Returns:
        (match: bool, reason: str) - True if keys match exactly or are enharmonic (or relative) equivalents
    
    Matching rules:
    1. Exact match (e.g., "D# Minor" == "D# Minor")
    2. Enharmonic equivalent (e.g., "D# Minor" == "Eb Minor", "G#/Ab" == "Ab")
    3. Relative major/minor (e.g., "C Major" == "A Minor")
    4. Major vs mixolydian sharing the same pitch material (e.g., "F Major" == "C Mixolydian")
    """
    if not key1 or not key2:
        return (False, "missing key")
    
    parsed1 = normalize_key_label(key1)
    parsed2 = normalize_key_label(key2)

    if not parsed1 or not parsed2:
        return (False, "unparseable key")

    root1, mode1 = parsed1
    root2, mode2 = parsed2

    if root1 == root2 and mode1 == mode2:
        # Check if spelling differed for a clearer reason
        canonical1 = _normalize_note_text(str(key1)).strip().lower()
        canonical2 = _normalize_note_text(str(key2)).strip().lower()
        if canonical1 == canonical2:
            return (True, "exact")
        return (True, "enharmonic")

    # Relative major/minor share pitch material: major tonic is +3 semitones above its relative minor
    if {mode1, mode2} == {"major", "minor"}:
        major_root = root1 if mode1 == "major" else root2
        minor_root = root1 if mode1 == "minor" else root2
        if (major_root - minor_root) % 12 == 3:
            return (True, "relative major/minor")

    # Mixolydian on the dominant shares notes with the major scale a fourth above.
    if (
        (mode1 == "mixolydian" and mode2 == "major" and (root1 + 5) % 12 == root2)
        or (mode2 == "mixolydian" and mode1 == "major" and (root2 + 5) % 12 == root1)
    ):
        return (True, "relative mixolydian/major")

    return (False, "different")


__all__ = [
    "NOTE_NAMES_SHARP",
    "normalize_key_label",
    "canonical_key_id",
    "parse_canonical_key_id",
    "format_canonical_key",
    "keys_match_fuzzy",
]
