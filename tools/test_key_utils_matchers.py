#!/usr/bin/env python3
"""Targeted tests for enharmonic key matching utilities."""

from __future__ import annotations

import unittest
from pathlib import Path
import sys

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.key_utils import keys_match_fuzzy, normalize_key_label


class KeyUtilsMatcherTests(unittest.TestCase):
    def test_enharmonic_equivalents_match(self):
        match, reason = keys_match_fuzzy("D# minor", "Eb minor")
        self.assertTrue(match)
        self.assertEqual(reason, "enharmonic")

    def test_slash_notation_matches_single_spelling(self):
        match, reason = keys_match_fuzzy("D# Minor", "D#/Eb minor")
        self.assertTrue(match)
        self.assertIn(reason, {"exact", "enharmonic"})

    def test_enharmonic_majors_match(self):
        match, reason = keys_match_fuzzy("F# Major", "Gb Major")
        self.assertTrue(match)
        self.assertEqual(reason, "enharmonic")

    def test_unicode_flat_and_slash_match(self):
        match, reason = keys_match_fuzzy("F# Major", "F#/G♭")
        self.assertTrue(match)
        self.assertIn(reason, {"exact", "enharmonic"})

    def test_different_keys_fail(self):
        match, reason = keys_match_fuzzy("D minor", "D# minor")
        self.assertFalse(match)
        self.assertEqual(reason, "different")

    def test_normalize_handles_double_accidentals(self):
        # Cb should normalize to pitch class 11 (B)
        root_idx, mode = normalize_key_label("Cb minor") or (None, None)
        self.assertEqual(root_idx, 11)
        self.assertEqual(mode, "minor")

    def test_truncated_label_matches_plain(self):
        match, reason = keys_match_fuzzy("A Major…", "A")
        self.assertTrue(match)
        self.assertIn(reason, {"exact", "enharmonic"})


if __name__ == "__main__":
    unittest.main()
