"""Normalization helpers for calibration dataset building."""

from __future__ import annotations

import re

_TRAILING_PARENS_RE = re.compile(r"\s*[\(\[][^)\]]*[\)\]]\s*$")
_UNMATCHED_TRAILING_PAREN_RE = re.compile(r"\s*[\(\[][^)\]]*$")
_PARENS_ANYWHERE_RE = re.compile(r"[\(\[][^)\]]*[\)\]]")
_EDITION_PATTERNS = [
    re.compile(r"\b\d{4}\s+remaster(?:ed)?\b"),
    re.compile(r"\bremaster(?:ed)?\b"),
    re.compile(r"\bsingle version\b"),
    re.compile(r"\balbum version\b"),
    re.compile(r"\bradio edit\b"),
    re.compile(r"\bclub edit\b"),
    re.compile(r"\bclub mix\b"),
    re.compile(r"\bdemo version\b"),
    re.compile(r"\bacoustic version\b"),
    re.compile(r"\blive version\b"),
    re.compile(r"\bbonus track\b"),
    re.compile(r"\bdeluxe edition\b"),
    re.compile(r"\bsped up\b"),
    re.compile(r"\bslow(?:ed)? version\b"),
    re.compile(r"\btaylor s version\b"),
    re.compile(r"\btaylors version\b"),
    re.compile(r"\btaylor version\b"),
]
_EDITION_TOKENS = {
    "live",
    "acoustic",
    "remix",
    "mix",
    "edit",
    "version",
    "remastered",
    "remaster",
}


def normalize_text(value: str) -> str:
    if value is None:
        return ""
    text = str(value).strip().lower()
    if not text:
        return ""
    text = text.replace("–", " ").replace("—", " ")
    text = _PARENS_ANYWHERE_RE.sub(" ", text)
    text = _TRAILING_PARENS_RE.sub(" ", text)
    text = _UNMATCHED_TRAILING_PAREN_RE.sub(" ", text)
    text = text.replace("&", " and ")
    text = re.sub(r"\(feat[^\)]*\)", " ", text)
    text = re.sub(r"\b(feat|featuring|ft)\.\b.*", " ", text)
    text = text.replace("/", " ")
    text = text.replace("'", "").replace("’", "").replace("`", "")
    text = text.replace('"', " ")
    text = text.replace("-", " ")
    text = text.replace("♭", "b").replace("♯", "sharp")
    for pattern in _EDITION_PATTERNS:
        text = pattern.sub(" ", text)
    tokens = [token for token in text.split() if token not in _EDITION_TOKENS]
    text = " ".join(tokens)
    text = text.encode("ascii", "ignore").decode("ascii", errors="ignore")
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return " ".join(text.split())


def build_match_key(title: str, artist: str) -> str:
    return f\"{normalize_text(title)}::{normalize_text(artist)}\"


__all__ = ["normalize_text", "build_match_key"]
