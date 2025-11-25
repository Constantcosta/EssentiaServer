"""Key detection helpers shared between analyzer components."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

import librosa
import numpy as np

from backend.analysis.settings import KEY_ANALYSIS_SAMPLE_RATE
from backend.analysis.utils import clamp_to_unit
from tools.key_utils import normalize_key_label  # type: ignore

logger = logging.getLogger(__name__)

KEY_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
KRUMHANSL_MAJOR = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88], dtype=float)
KRUMHANSL_MINOR = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17], dtype=float)

CHROMA_CQT_HOP = 512
KEY_WINDOW_SECONDS = 6.0
KEY_WINDOW_HOP_SECONDS = 3.0
_INTERVAL_OVERRIDE_STEPS = {2, 3, 4, 5, 7, 9, 10}
_RUNNER_SCORE_MARGIN = 0.025
_WINDOW_SUPPORT_RATIO = 0.65
_MODE_BIAS_THRESHOLD = 0.08
_MODE_BIAS_CONF_LIMIT = 0.5
_WINDOW_SUPPORT_PROMOTION = 0.72  # Increased from 0.66 to 0.72 for preview clips (reduce fifth-related errors)
_FINAL_SUPPORT_FLOOR = 0.5
_WINDOW_SUPPORT_DELTA = 0.18
_MODE_VOTE_THRESHOLD = 0.32  # Increased from 0.28 to 0.32 to reduce relative major/minor confusion
_MODE_VOTE_CONF_GAIN = 0.3
_CHROMA_PEAK_ENERGY_MARGIN = 0.075
_CHROMA_PEAK_SUPPORT_RATIO = 0.55
_CHROMA_PEAK_SUPPORT_GAP = 0.18
_EDM_STRICT_SCORE = 0.55
_EDM_RELAXED_SCORE = 0.42
_EDM_SUPPORT_RATIO = 0.45
_DOMINANT_INTERVAL_STEPS = {5, 7}
_DOMINANT_OVERRIDE_SCORE = 0.55
_WINDOW_SUPPORT_PROMOTION_SHORT = 0.78
# Fifth reconciliation thresholds for short clips (dominant/tonic ambiguity)
_FIFTH_RECON_CHROMA_RATIO = 0.57
_FIFTH_RECON_SCORE_EPS = 0.04
_FIFTH_RUNNER_SCORE_EPS = 0.02
_ESSENTIA_TONIC_OVERRIDE_SCORE = 0.55
_ESSENTIA_TONIC_OVERRIDE_CONFIDENCE = 0.45
_MODE_RESCUE_SCORE = 0.58

_HAS_ESSENTIA = False
_essentia_module = None
ESSENTIA_KEY_FALLBACK_SR = 44100


@dataclass
class _EssentiaExtractorEntry:
    extractor: object
    expected_sr: int


_ESSENTIA_KEY_EXTRACTORS: Dict[int, Optional[_EssentiaExtractorEntry]] = {}
_ESSENTIA_EDM_EXTRACTORS: Dict[int, Optional[_EssentiaExtractorEntry]] = {}
_ESSENTIA_KEY_ACCEPTS_SAMPLE_RATE = True
_ESSENTIA_EDM_ACCEPTS_SAMPLE_RATE = True


def configure_key_detection(has_essentia: bool, essentia_module):
    """Provide the Essentia module so key detection can use it when available."""
    global _HAS_ESSENTIA, _essentia_module, _ESSENTIA_KEY_EXTRACTORS, _ESSENTIA_EDM_EXTRACTORS
    global _ESSENTIA_KEY_ACCEPTS_SAMPLE_RATE, _ESSENTIA_EDM_ACCEPTS_SAMPLE_RATE
    _HAS_ESSENTIA = has_essentia and essentia_module is not None
    _essentia_module = essentia_module if _HAS_ESSENTIA else None
    _ESSENTIA_KEY_EXTRACTORS = {}
    _ESSENTIA_EDM_EXTRACTORS = {}
    _ESSENTIA_KEY_ACCEPTS_SAMPLE_RATE = True
    _ESSENTIA_EDM_ACCEPTS_SAMPLE_RATE = True


def _normalize_mode_label(mode_value) -> str:
    text = str(mode_value).strip().lower()
    if text.startswith("min"):
        return "Minor"
    return "Major"


def _interval_distance(candidate_root: int, reference_root: int) -> int:
    return int(candidate_root - reference_root) % 12


def _vote_supports_candidate(votes, target_root: int, target_mode: str, ratio_threshold: float) -> bool:
    if not votes:
        return False
    best_weight = float(votes[0].get("weight", 0.0) or 0.0)
    if best_weight <= 0:
        return False
    for entry in votes:
        root = entry.get("root")
        if root is None:
            continue
        mode = _normalize_mode_label(entry.get("mode"))
        if int(root) % 12 == target_root % 12 and mode == target_mode:
            weight = float(entry.get("weight", 0.0) or 0.0)
            return (weight / best_weight) >= ratio_threshold
    return False


def _root_weight_map(votes: List[Dict[str, object]]) -> Dict[int, float]:
    weights: Dict[int, float] = {}
    for entry in votes or []:
        root = entry.get("root")
        weight = entry.get("weight")
        if root is None or weight is None:
            continue
        try:
            root_idx = int(root) % 12
            weight_val = float(weight)
        except (TypeError, ValueError):
            continue
        if weight_val <= 0:
            continue
        weights[root_idx] = weights.get(root_idx, 0.0) + weight_val
    return weights


def _root_support_ratio(weight_map: Dict[int, float], target_root: int) -> float:
    if not weight_map:
        return 0.0
    best_weight = max(weight_map.values())
    if best_weight <= 0:
        return 0.0
    return float(weight_map.get(target_root % 12, 0.0) / best_weight)


def _mode_vote_breakdown(
    votes: List[Dict[str, object]], target_root: int
) -> Tuple[Dict[str, float], float]:
    breakdown: Dict[str, float] = {"Major": 0.0, "Minor": 0.0}
    total_weight = 0.0
    if not votes:
        return breakdown, total_weight
    for entry in votes:
        root = entry.get("root")
        if root is None:
            continue
        try:
            root_idx = int(root) % 12
        except (TypeError, ValueError):
            continue
        if root_idx != target_root % 12:
            continue
        mode = _normalize_mode_label(entry.get("mode"))
        try:
            weight_val = float(entry.get("weight", 0.0) or 0.0)
        except (TypeError, ValueError):
            continue
        if weight_val <= 0:
            continue
        breakdown[mode] = breakdown.get(mode, 0.0) + weight_val
        total_weight += weight_val
    return breakdown, total_weight


def _essentia_supports(candidate: Optional[Dict[str, object]], target_root: int, target_mode: str, min_score: float) -> bool:
    if not candidate:
        return False
    root = candidate.get("root")
    if root is None:
        return False
    try:
        root_idx = int(root) % 12
    except (TypeError, ValueError):
        return False
    score = clamp_to_unit(candidate.get("score", 0.0))
    if score < min_score:
        return False
    mode = _normalize_mode_label(candidate.get("mode", target_mode))
    return root_idx == (target_root % 12) and mode == target_mode


def _chroma_peak_root(chroma_profile: np.ndarray) -> Tuple[int, float]:
    if chroma_profile.size == 0:
        return 0, 0.0
    idx = int(np.argmax(chroma_profile))
    return idx, float(chroma_profile[idx])


def _mode_bias_from_chroma(chroma_profile: np.ndarray, root_index: int) -> float:
    if chroma_profile.size < 12:
        return 0.0
    major_third = chroma_profile[(root_index + 4) % 12]
    minor_third = chroma_profile[(root_index + 3) % 12]
    major_sixth = chroma_profile[(root_index + 9) % 12]
    minor_sixth = chroma_profile[(root_index + 8) % 12]
    bias = (major_third - minor_third) + 0.5 * (major_sixth - minor_sixth)
    return float(bias)


def _triad_energy(chroma_profile: np.ndarray, root_index: int, mode: str) -> float:
    """Sum chroma energy for the root, third, and fifth of the key."""
    chroma_profile = np.array(chroma_profile, dtype=float)
    if chroma_profile.size < 12:
        return 0.0
    root = int(root_index) % 12
    mode_norm = _normalize_mode_label(mode)
    third = (root + (4 if mode_norm == "Major" else 3)) % 12
    fifth = (root + 7) % 12
    return float(chroma_profile[root] + chroma_profile[third] + chroma_profile[fifth])


def _sorted_candidates(score_entries: List[Dict[str, object]]) -> List[Dict[str, object]]:
    try:
        return sorted(
            score_entries,
            key=lambda entry: float(entry.get("score", 0.0) or 0.0),
            reverse=True,
        )
    except Exception:
        return list(score_entries or [])


def _normalized_profile(profile: np.ndarray) -> np.ndarray:
    norm = np.linalg.norm(profile)
    if norm == 0:
        return profile
    return profile / norm


MAJOR_PROFILE = _normalized_profile(KRUMHANSL_MAJOR)
MINOR_PROFILE = _normalized_profile(KRUMHANSL_MINOR)


def _score_chroma_profile(chroma_profile: np.ndarray):
    """Return normalized chroma, per-key scores, and the best candidate."""
    chroma = np.array(chroma_profile, dtype=float)
    denom = float(np.max(chroma)) + 1e-9
    if denom > 0:
        chroma = chroma / denom
    scores = []
    votes = {}
    best_entry = {"root": 0, "mode": "Major", "score": -np.inf}
    for root in range(12):
        rolled = np.roll(chroma, -root)
        for mode, profile in (("Major", MAJOR_PROFILE), ("Minor", MINOR_PROFILE)):
            score = float(np.dot(rolled, profile))
            entry = {"root": root, "mode": mode, "score": score}
            scores.append(entry)
            votes[(root, mode)] = score
            if score > best_entry["score"]:
                best_entry = entry
    return chroma, scores, votes, best_entry


def _windowed_key_consensus(chroma_cqt: np.ndarray, sr: int):
    """Slide a window across the chroma matrix to capture section-level keys."""
    if chroma_cqt.size == 0 or chroma_cqt.shape[1] == 0 or sr <= 0:
        return {}
    frames_per_second = sr / float(CHROMA_CQT_HOP)
    window_frames = max(1, int(KEY_WINDOW_SECONDS * frames_per_second))
    hop_frames = max(1, int(KEY_WINDOW_HOP_SECONDS * frames_per_second))
    totals = {}
    total_weight = 0.0
    for start in range(0, chroma_cqt.shape[1], hop_frames):
        end = min(start + window_frames, chroma_cqt.shape[1])
        window_slice = chroma_cqt[:, start:end]
        if window_slice.size == 0:
            continue
        profile = np.sum(window_slice, axis=1)
        window_energy = float(np.sum(window_slice))
        if window_energy <= 1e-6:
            continue
        _, _, _, best = _score_chroma_profile(profile)
        key = (best["root"], best["mode"])
        totals[key] = totals.get(key, 0.0) + window_energy
        total_weight += window_energy
    if total_weight <= 0 or not totals:
        return {}
    sorted_totals = sorted(totals.items(), key=lambda item: item[1], reverse=True)
    best_key, best_weight = sorted_totals[0]
    runner_weight = sorted_totals[1][1] if len(sorted_totals) > 1 else 0.0
    dominance = best_weight / total_weight
    votes = [
        {
            "root": key[0],
            "mode": key[1],
            "weight": float(weight),
            "label": f"{KEY_NAMES[key[0]]} {key[1]}",
        }
        for key, weight in sorted_totals
    ]
    return {
        "votes": votes,
        "best": {"root": best_key[0], "mode": best_key[1], "weight": float(best_weight)},
        "runner_up_weight": float(runner_weight),
        "total_weight": float(total_weight),
        "dominance": float(dominance),
    }


def _sample_rate_kw_not_supported(exc: Exception) -> bool:
    message = str(exc).lower()
    return "samplerate" in message and ("not" in message and "parameter" in message or "unexpected" in message and "keyword" in message)


def _resample_for_key_extractor(audio32: np.ndarray, source_sr: int, target_sr: int) -> np.ndarray:
    if target_sr <= 0 or target_sr == source_sr:
        return audio32
    try:
        resampled = librosa.resample(
            np.asarray(audio32, dtype=np.float32),
            orig_sr=source_sr,
            target_sr=target_sr,
            res_type="kaiser_fast",
        )
        return np.ascontiguousarray(resampled.astype(np.float32))
    except Exception as exc:
        logger.warning("⚠️ Essentia key extractor resample failed (%s) – using SR %s.", exc, source_sr)
        return audio32


def _get_essentia_key_extractor(sr: int, edm: bool = False) -> Optional[_EssentiaExtractorEntry]:
    if sr <= 0 or not _HAS_ESSENTIA or _essentia_module is None:
        return None
    global _ESSENTIA_KEY_ACCEPTS_SAMPLE_RATE, _ESSENTIA_EDM_ACCEPTS_SAMPLE_RATE
    if edm:
        cache = _ESSENTIA_EDM_EXTRACTORS
        attr = "KeyExtractorEDM"
        accepts_sample_rate = _ESSENTIA_EDM_ACCEPTS_SAMPLE_RATE
    else:
        cache = _ESSENTIA_KEY_EXTRACTORS
        attr = "KeyExtractor"
        accepts_sample_rate = _ESSENTIA_KEY_ACCEPTS_SAMPLE_RATE
    cache_sr = sr if accepts_sample_rate else ESSENTIA_KEY_FALLBACK_SR
    if cache_sr in cache:
        return cache[cache_sr]
    factory = getattr(_essentia_module, attr, None)
    if factory is None:
        cache[cache_sr] = None
        return None
    kwargs = {"sampleRate": sr} if accepts_sample_rate else {}
    target_sr = cache_sr if cache_sr > 0 else sr
    try:
        extractor_obj = factory(**kwargs)
        entry = _EssentiaExtractorEntry(extractor=extractor_obj, expected_sr=target_sr)
        cache[cache_sr] = entry
        return entry
    except TypeError as exc:
        if accepts_sample_rate and _sample_rate_kw_not_supported(exc):
            logger.info("♻️ Essentia %s sampleRate fallback: %s", attr, exc)
            if edm:
                _ESSENTIA_EDM_ACCEPTS_SAMPLE_RATE = False
            else:
                _ESSENTIA_KEY_ACCEPTS_SAMPLE_RATE = False
            cache.clear()
            return _get_essentia_key_extractor(sr, edm=edm)
        logger.warning("⚠️ Essentia %s init failed: %s", attr, exc)
    except Exception as exc:
        logger.warning("⚠️ Essentia %s init failed: %s", attr, exc)
    cache[cache_sr] = None
    return None


def _parse_essentia_key_result(output) -> Optional[Dict[str, object]]:
    if not isinstance(output, (list, tuple)):
        return None
    if len(output) >= 3:
        key_label, scale_label, strength = output[0], output[1], output[2]
    elif len(output) == 2:
        key_label, scale_label = output
        strength = 0.0
    else:
        return None
    try:
        strength_value = clamp_to_unit(float(strength))
    except (TypeError, ValueError):
        strength_value = 0.0
    normalized = normalize_key_label(f"{key_label} {scale_label}")
    if not normalized:
        return None
    root_index, mode = normalized
    return {
        "root": int(root_index),
        "mode": "Minor" if mode == "minor" else "Major",
        "score": strength_value,
    }


def _essentia_key_candidate(y_signal: np.ndarray, sr: int, edm: bool = False) -> Optional[Dict[str, object]]:
    entry = _get_essentia_key_extractor(sr, edm=edm)
    if not entry:
        return None
    audio32 = np.ascontiguousarray(y_signal.astype(np.float32))
    adjusted_audio = _resample_for_key_extractor(audio32, sr, entry.expected_sr)
    try:
        parsed = _parse_essentia_key_result(entry.extractor(adjusted_audio))
        if parsed:
            parsed["score"] = clamp_to_unit(parsed.get("score", 0.0))
        return parsed
    except Exception as exc:
        logger.warning("⚠️ Essentia key extraction failed: %s", exc)
        return None


def _librosa_key_signature(y_signal: np.ndarray, sr: int, tuning: float, use_window_consensus: bool = True):
    chroma_cqt = librosa.feature.chroma_cqt(
        y=y_signal,
        sr=sr,
        hop_length=CHROMA_CQT_HOP,
        n_chroma=12,
        n_octaves=7,
        tuning=tuning,
    )
    chroma_profile = np.sum(chroma_cqt, axis=1)
    normalized_chroma, scores, votes, best = _score_chroma_profile(chroma_profile)
    consistency = clamp_to_unit(best["score"])
    
    # For short clips, skip window consensus and trust the direct chroma-based detection
    if use_window_consensus:
        window_meta = _windowed_key_consensus(chroma_cqt, sr)
    else:
        logger.debug("🎬 Skipping window consensus for short clip - using direct chroma detection")
        window_meta = {}
    
    best_entry = {
        "root": int(best["root"]),
        "mode": best["mode"],
        "score": float(best["score"]),
    }
    return normalized_chroma.tolist(), scores, consistency, {
        "votes": votes,
        "best": best_entry,
        "raw_scores": scores,
        "consistency": consistency,
        "window_consensus": window_meta,
    }
