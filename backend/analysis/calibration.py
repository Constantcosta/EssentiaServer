"""Shared calibration helpers for analyzer workers and pipelines."""

from __future__ import annotations

import copy
import json
import logging
from pathlib import Path
from threading import Lock
from typing import Dict, List, Optional, Tuple

import numpy as np

from backend.analysis import settings
from backend.analysis.utils import clamp_to_unit
from tools.key_utils import (
    canonical_key_id,
    format_canonical_key,
    normalize_key_label,
    parse_canonical_key_id,
)

LOGGER = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).resolve().parents[2]
CALIBRATION_CONFIG_PATH = REPO_ROOT / "config" / "calibration_scalers.json"
CALIBRATION_MODEL_PATH = REPO_ROOT / "models" / "calibration_models.json"
KEY_CALIBRATION_PATH = REPO_ROOT / "config" / "key_calibration.json"
BPM_CALIBRATION_PATH = REPO_ROOT / "config" / "bpm_calibration.json"

CALIBRATED_RESULT_FIELDS = {
    "bpm": "bpm",
    "danceability": "danceability",
    "energy": "energy",
    "acousticness": "acousticness",
    "valence": "valence",
    "loudness": "loudness",
}

CALIBRATION_RULES: Dict[str, Dict[str, float]] = {}
CALIBRATION_METADATA: Dict[str, object] = {}
CALIBRATION_MODELS: Dict[str, Dict[str, object]] = {}
CALIBRATION_MODEL_META: Dict[str, object] = {}
KEY_CALIBRATION_RULES: Dict[str, Dict[str, object]] = {}
KEY_CALIBRATION_META: Dict[str, object] = {}
BPM_CALIBRATION_RULES: List[Dict[str, object]] = []
BPM_CALIBRATION_META: Dict[str, object] = {}

CALIBRATION_FILE_PATHS = {
    "scalers": CALIBRATION_CONFIG_PATH,
    "models": CALIBRATION_MODEL_PATH,
    "key": KEY_CALIBRATION_PATH,
    "bpm": BPM_CALIBRATION_PATH,
}
CALIBRATION_FILE_MTIMES = {name: None for name in CALIBRATION_FILE_PATHS}
_calibration_reload_lock = Lock()


def _safe_file_mtime(path: Path) -> Optional[float]:
    try:
        return path.stat().st_mtime
    except FileNotFoundError:
        return None


def _record_calibration_mtime(tag: str):
    CALIBRATION_FILE_MTIMES[tag] = _safe_file_mtime(CALIBRATION_FILE_PATHS[tag])


def load_calibration_config():
    """Load linear calibration coefficients shared by backend and GUI."""
    global CALIBRATION_RULES, CALIBRATION_METADATA
    if not CALIBRATION_CONFIG_PATH.exists():
        LOGGER.info("ℹ️ Calibration config not found at %s – using raw analyzer outputs.", CALIBRATION_CONFIG_PATH)
        CALIBRATION_RULES = {}
        CALIBRATION_METADATA = {}
        _record_calibration_mtime("scalers")
        return
    try:
        with open(CALIBRATION_CONFIG_PATH, "r", encoding="utf-8") as config_file:
            data = json.load(config_file)
        CALIBRATION_RULES = data.get("features", {})
        CALIBRATION_METADATA = {
            "generated_at": data.get("generated_at"),
            "feature_set_version": data.get("feature_set_version"),
            "notes": data.get("notes"),
        }
        LOGGER.info(
            "🎚️ Loaded calibration scalers (%d features, version %s).",
            len(CALIBRATION_RULES),
            CALIBRATION_METADATA.get("feature_set_version", "unknown"),
        )
        _record_calibration_mtime("scalers")
    except Exception as exc:
        LOGGER.error("⚠️ Failed to load calibration config: %s", exc)
        CALIBRATION_RULES = {}
        CALIBRATION_METADATA = {}
        _record_calibration_mtime("scalers")


def _calibrate_value(feature_name: str, value):
    rule = CALIBRATION_RULES.get(feature_name)
    if not rule:
        return value, False
    try:
        numeric_value = float(value)
    except (TypeError, ValueError):
        return value, False
    slope = rule.get("slope")
    intercept = rule.get("intercept")
    if slope is None or intercept is None:
        return value, False
    calibrated = (numeric_value * slope) + intercept
    clamp_cfg = rule.get("clamp") or {}
    min_val = clamp_cfg.get("min")
    max_val = clamp_cfg.get("max")
    if min_val is not None:
        calibrated = max(min_val, calibrated)
    if max_val is not None:
        calibrated = min(max_val, calibrated)
    return calibrated, True


def apply_calibration_layer(result: Dict[str, object]) -> Dict[str, object]:
    if not CALIBRATION_RULES:
        return result
    applied_strings = []
    
    signal_duration = float(result.get("signal_duration", 0.0) or 0.0)
    is_short_clip = signal_duration < settings.SHORT_CLIP_THRESHOLD

    # Get BPM confidence for smart calibration decisions
    bpm_confidence = clamp_to_unit(result.get("bpm_confidence", 0.0))
    raw_bpm = result.get("bpm")
    
    for feature_name, field_name in CALIBRATED_RESULT_FIELDS.items():
        if field_name not in result:
            continue
        if feature_name == "bpm" and is_short_clip:
            LOGGER.info("⏭️  Skipping BPM calibration for short clip (%.1fs)", signal_duration)
            continue
        # For BPM: apply calibration but cap maximum change to ±10 BPM
        # This prevents calibration from causing octave-level errors
        # while still allowing fine-tuning adjustments
        if feature_name == "bpm" and raw_bpm is not None:
            try:
                raw_bpm_float = float(raw_bpm)
            except (TypeError, ValueError):
                raw_bpm_float = None

            # For short previews: keep tempos in the 138-152 BPM sweet spot untouched
            if is_short_clip and raw_bpm_float is not None:
                in_sweet_spot = 138.0 <= raw_bpm_float <= 152.0
                if in_sweet_spot:
                    LOGGER.info(
                        "⏭️  Skipping BPM calibration for short clip (%.1fs) in sweet spot: raw BPM %.1f (conf=%.2f)",
                        signal_duration,
                        raw_bpm_float,
                        bpm_confidence,
                    )
                    continue
                if raw_bpm_float >= 145.0:
                    LOGGER.info(
                        "⏭️  Skipping BPM calibration for short clip (%.1fs) high tempo %.1f (conf=%.2f)",
                        signal_duration,
                        raw_bpm_float,
                        bpm_confidence,
                    )
                    continue

            try:
                calibrated_value, changed = _calibrate_value(feature_name, result[field_name])
                if changed and raw_bpm_float is not None:
                    bpm_change = abs(calibrated_value - raw_bpm_float)
                    if bpm_change > 10.0:
                        LOGGER.info(
                            f"⚠️  Capping BPM calibration: {raw_bpm_float:.1f}→{calibrated_value:.1f} "
                            f"would change by {bpm_change:.1f} BPM (max ±10)"
                        )
                        continue  # Skip this calibration
            except (TypeError, ValueError):
                pass
        
        calibrated_value, changed = _calibrate_value(feature_name, result[field_name])
        if not changed:
            continue
        original_value = result[field_name]
        result[field_name] = calibrated_value
        try:
            applied_strings.append(f"{feature_name}: {float(original_value):.3f}→{calibrated_value:.3f}")
        except (TypeError, ValueError):
            applied_strings.append(f"{feature_name}: updated")
    if applied_strings:
        LOGGER.info("🎯 Applied calibration layer (%s)", ", ".join(applied_strings))
    return result


def _confidence_bin_accuracy(raw_conf: float) -> Optional[float]:
    bins = KEY_CALIBRATION_META.get("confidence_bins") if KEY_CALIBRATION_META else None
    if not bins:
        return None
    for entry in bins:
        try:
            if entry["min"] <= raw_conf < entry["max"]:
                return float(entry.get("accuracy", 0.0))
        except (KeyError, TypeError):
            continue
    return None


def _canonical_from_candidate(root_index: int, mode: str) -> Tuple[int, str]:
    canonical_mode = "minor" if str(mode).strip().lower().startswith("min") else "major"
    return root_index % 12, canonical_mode


def _label_for_canonical(canonical: str, fallback: Optional[str] = None) -> Optional[str]:
    parsed = parse_canonical_key_id(canonical)
    if not parsed:
        return fallback
    prefer_flats = "♭" in (fallback or "")
    return format_canonical_key(parsed[0], parsed[1], prefer_flats=prefer_flats)


def apply_key_calibration(result: Dict[str, object]) -> Dict[str, object]:
    if not KEY_CALIBRATION_RULES:
        return result
    
    # Skip key calibration for short clips (< 45s)
    # Calibration was trained on full songs and breaks preview file detection
    from backend.analysis.settings import SHORT_CLIP_THRESHOLD
    signal_duration = result.get("signal_duration", 0.0)
    if signal_duration > 0 and signal_duration < SHORT_CLIP_THRESHOLD:
        LOGGER.info(f"🎬 Skipping key calibration for short clip ({signal_duration:.1f}s)")
        return result
    
    details = dict(result.get("key_details") or {})
    candidate_scores = details.get("scores")
    normalized_current = normalize_key_label(result.get("key"))
    candidates: List[Tuple[int, str, float]] = []
    if candidate_scores:
        for entry in candidate_scores:
            try:
                root = int(entry.get("root", 0))
            except (TypeError, ValueError):
                continue
            mode = str(entry.get("mode", "Major"))
            score = clamp_to_unit(entry.get("score", 0.0))
            if score <= 0.0:
                continue
            root_idx, canonical_mode = _canonical_from_candidate(root, mode)
            candidates.append((root_idx, canonical_mode, score))
    elif normalized_current:
        root_idx, mode = normalized_current
        score = clamp_to_unit(result.get("key_confidence") or 0.0)
        if score == 0.0:
            score = 0.25
        candidates.append((root_idx, mode, score))
    else:
        return result
    actual_votes: Dict[str, float] = {}
    label_lookup: Dict[str, str] = {}
    vote_debug: List[Dict[str, object]] = []
    for root_idx, mode, score in candidates:
        if score <= 0.0:
            continue
        canonical_id = canonical_key_id(root_idx, mode)
        entry = KEY_CALIBRATION_RULES.get(canonical_id)
        targets = (entry or {}).get("targets") or []
        total_prob = 0.0
        if targets:
            for target in targets:
                canonical_target = target.get("canonical")
                probability = float(target.get("probability", 0.0) or 0.0)
                if not canonical_target or probability <= 0.0:
                    continue
                weighted = score * probability
                actual_votes[canonical_target] = actual_votes.get(canonical_target, 0.0) + weighted
                total_prob += probability
                label_lookup[canonical_target] = (
                    target.get("label")
                    or _label_for_canonical(canonical_target, result.get("key"))
                    or canonical_target
                )
                vote_debug.append(
                    {
                        "from": canonical_id,
                        "to": canonical_target,
                        "weight": weighted,
                        "probability": probability,
                    }
                )
        residual = max(0.0, 1.0 - total_prob)
        if residual > 0.0:
            actual_votes[canonical_id] = actual_votes.get(canonical_id, 0.0) + score * residual
            label_lookup[canonical_id] = _label_for_canonical(canonical_id, result.get("key")) or canonical_id
            vote_debug.append(
                {
                    "from": canonical_id,
                    "to": canonical_id,
                    "weight": score * residual,
                    "probability": residual,
                }
            )
    if not actual_votes:
        return result
    best_canonical, best_vote = max(actual_votes.items(), key=lambda item: item[1])
    total_vote = sum(actual_votes.values())
    posterior = best_vote / total_vote if total_vote > 0 else 0.0
    new_label = label_lookup.get(best_canonical) or _label_for_canonical(best_canonical, result.get("key"))
    if new_label:
        result["key"] = new_label
    raw_conf = clamp_to_unit(result.get("key_confidence"))
    bin_accuracy = _confidence_bin_accuracy(raw_conf)
    if bin_accuracy is None:
        bin_accuracy = KEY_CALIBRATION_META.get("raw_accuracy", 0.0) if KEY_CALIBRATION_META else 0.0
    calibrated_conf = clamp_to_unit(max(raw_conf, bin_accuracy, posterior))
    result["key_confidence"] = calibrated_conf
    details["calibrated_votes"] = vote_debug
    result["key_details"] = details
    return result


def load_calibration_models():
    """Load ridge calibration models if available."""
    global CALIBRATION_MODELS, CALIBRATION_MODEL_META
    if not CALIBRATION_MODEL_PATH.exists():
        CALIBRATION_MODELS = {}
        CALIBRATION_MODEL_META = {}
        LOGGER.info("ℹ️ Calibration model file not found at %s", CALIBRATION_MODEL_PATH)
        _record_calibration_mtime("models")
        return
    try:
        with open(CALIBRATION_MODEL_PATH, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        CALIBRATION_MODELS = data.get("targets", {})
        CALIBRATION_MODEL_META = {
            "generated_at": data.get("generated_at"),
            "feature_set_version": data.get("feature_set_version"),
            "notes": data.get("notes"),
            "feature_columns": data.get("feature_columns", []),
        }
        LOGGER.info(
            "🧠 Loaded calibration models (%d targets, version %s).",
            len(CALIBRATION_MODELS),
            CALIBRATION_MODEL_META.get("feature_set_version", "unknown"),
        )
        _record_calibration_mtime("models")
    except Exception as exc:
        LOGGER.error("⚠️ Failed to load calibration models: %s", exc)
        CALIBRATION_MODELS = {}
        CALIBRATION_MODEL_META = {}
        _record_calibration_mtime("models")


def load_key_calibration():
    """Load key-mode calibration metadata for posterior confidence estimates."""
    global KEY_CALIBRATION_RULES, KEY_CALIBRATION_META
    if not KEY_CALIBRATION_PATH.exists():
        KEY_CALIBRATION_RULES = {}
        KEY_CALIBRATION_META = {}
        LOGGER.info("ℹ️ Key calibration file not found at %s – skipping posterior tweaks.", KEY_CALIBRATION_PATH)
        _record_calibration_mtime("key")
        return
    try:
        with open(KEY_CALIBRATION_PATH, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        KEY_CALIBRATION_RULES = data.get("keys", {})
        KEY_CALIBRATION_META = {
            "generated_at": data.get("generated_at"),
            "raw_accuracy": data.get("raw_accuracy"),
            "calibrated_accuracy": data.get("calibrated_accuracy"),
            "confidence_bins": data.get("confidence_bins"),
        }
        LOGGER.info(
            "🗝️ Loaded key calibration (%d analyzer keys, %.1f%% → %.1f%% accuracy).",
            len(KEY_CALIBRATION_RULES),
            100.0 * KEY_CALIBRATION_META.get("raw_accuracy", 0.0),
            100.0 * KEY_CALIBRATION_META.get("calibrated_accuracy", 0.0),
        )
        _record_calibration_mtime("key")
    except Exception as exc:
        LOGGER.error("⚠️ Failed to load key calibration: %s", exc)
        KEY_CALIBRATION_RULES = {}
        KEY_CALIBRATION_META = {}
        _record_calibration_mtime("key")


def refresh_calibration_assets():
    """Reload calibration/scaler artifacts when underlying files change."""
    loaders = {
        "scalers": load_calibration_config,
        "models": load_calibration_models,
        "key": load_key_calibration,
        "bpm": load_bpm_calibration,
    }
    with _calibration_reload_lock:
        for tag, loader in loaders.items():
            path = CALIBRATION_FILE_PATHS[tag]
            current_mtime = _safe_file_mtime(path)
            if current_mtime == CALIBRATION_FILE_MTIMES.get(tag):
                continue
            loader()
            CALIBRATION_FILE_MTIMES[tag] = _safe_file_mtime(path)
            LOGGER.info("♻️ Reloaded %s calibration asset (mtime change detected).", tag)


def calibration_snapshot() -> Dict[str, Dict[str, object]]:
    """Capture the current calibration artifacts so workers can apply identical math."""
    return {
        "rules": copy.deepcopy(CALIBRATION_RULES),
        "metadata": copy.deepcopy(CALIBRATION_METADATA),
        "models": copy.deepcopy(CALIBRATION_MODELS),
        "model_meta": copy.deepcopy(CALIBRATION_MODEL_META),
        "key_rules": copy.deepcopy(KEY_CALIBRATION_RULES),
        "key_meta": copy.deepcopy(KEY_CALIBRATION_META),
    }


def apply_calibration_snapshot(snapshot: Optional[Dict[str, Dict[str, object]]]):
    """Replace calibration globals inside worker processes."""
    if not snapshot:
        return
    global CALIBRATION_RULES, CALIBRATION_METADATA
    global CALIBRATION_MODELS, CALIBRATION_MODEL_META
    global KEY_CALIBRATION_RULES, KEY_CALIBRATION_META
    CALIBRATION_RULES = snapshot.get("rules", {}) or {}
    CALIBRATION_METADATA = snapshot.get("metadata", {}) or {}
    CALIBRATION_MODELS = snapshot.get("models", {}) or {}
    CALIBRATION_MODEL_META = snapshot.get("model_meta", {}) or {}
    KEY_CALIBRATION_RULES = snapshot.get("key_rules", {}) or {}
    KEY_CALIBRATION_META = snapshot.get("key_meta", {}) or {}


def apply_calibration_models(result: Dict[str, object]) -> Dict[str, object]:
    """Apply learned calibration models when available."""
    if not CALIBRATION_MODELS:
        return result
    feature_names = CALIBRATION_MODEL_META.get("feature_columns", [])
    if not feature_names:
        return result
    feature_vector = []
    for name in feature_names:
        value = result.get(name)
        if value is None:
            return result
        feature_vector.append(float(value))
    X = np.array(feature_vector, dtype=float)
    for target_name, model in CALIBRATION_MODELS.items():
        weights = np.array(model.get("weights", []), dtype=float)
        means = np.array(model.get("feature_means", []), dtype=float)
        stds = np.array(model.get("feature_stds", []), dtype=float)
        if X.shape[0] != weights.shape[0]:
            continue
        stds[stds == 0.0] = 1.0
        normalized = (X - means) / stds
        prediction = float(normalized.dot(weights) + model.get("intercept", 0.0))
        percent_scale = bool(model.get("percent_scale"))
        if percent_scale:
            prediction = max(0.0, min(1.0, prediction))
        result[target_name] = prediction
    return result


def load_bpm_calibration():
    """Load BPM calibration rules for systematic tempo corrections."""
    global BPM_CALIBRATION_RULES, BPM_CALIBRATION_META
    if not BPM_CALIBRATION_PATH.exists():
        LOGGER.info("ℹ️ BPM calibration config not found at %s – no BPM corrections will be applied.", BPM_CALIBRATION_PATH)
        BPM_CALIBRATION_RULES = []
        BPM_CALIBRATION_META = {}
        _record_calibration_mtime("bpm")
        return
    try:
        with open(BPM_CALIBRATION_PATH, "r", encoding="utf-8") as config_file:
            data = json.load(config_file)
        rules = data.get("rules", [])
        # Sort rules by priority (highest first)
        BPM_CALIBRATION_RULES = sorted(
            [r for r in rules if r.get("enabled", True)],
            key=lambda x: x.get("priority", 0),
            reverse=True
        )
        BPM_CALIBRATION_META = {
            "version": data.get("version"),
            "generated_at": data.get("generated_at"),
            "description": data.get("description"),
        }
        LOGGER.info(
            "🎚️ Loaded BPM calibration rules (%d enabled, version %s).",
            len(BPM_CALIBRATION_RULES),
            BPM_CALIBRATION_META.get("version", "unknown"),
        )
        _record_calibration_mtime("bpm")
    except Exception as exc:
        LOGGER.error("⚠️ Failed to load BPM calibration config: %s", exc)
        BPM_CALIBRATION_RULES = []
        BPM_CALIBRATION_META = {}
        _record_calibration_mtime("bpm")


def apply_bpm_calibration(result: Dict[str, object]) -> Dict[str, object]:
    """
    Apply BPM calibration rules based on detected patterns.
    
    This function systematically corrects BPM octave errors and other
    tempo detection issues by applying learned correction rules.
    
    Args:
        result: Analysis result dict with bpm, energy, signal_duration, etc.
    
    Returns:
        Updated result dict with corrected BPM if applicable
    """
    if not BPM_CALIBRATION_RULES:
        return result
    
    bpm = result.get("bpm")
    energy = result.get("energy")
    signal_duration = result.get("signal_duration", 0.0)
    confidence = result.get("bpm_confidence", 0.0)
    
    try:
        duration_float = float(signal_duration)
    except (TypeError, ValueError):
        duration_float = 0.0

    if duration_float < settings.SHORT_CLIP_THRESHOLD:
        LOGGER.info(
            "⏭️  Skipping BPM calibration rules for short clip (%.1fs)",
            duration_float,
        )
        return result
    
    if bpm is None or energy is None:
        return result
    
    try:
        bpm_float = float(bpm)
        energy_float = float(energy)
        confidence_float = float(confidence)
    except (TypeError, ValueError):
        return result
    
    # Try each rule in priority order (highest first)
    for rule in BPM_CALIBRATION_RULES:
        conditions = rule.get("conditions", {})
        
        # Check BPM range
        bpm_range = conditions.get("bpm_range")
        if bpm_range and not (bpm_range[0] <= bpm_float <= bpm_range[1]):
            continue
        
        # Check energy range
        energy_range = conditions.get("energy_range")
        if energy_range and not (energy_range[0] <= energy_float <= energy_range[1]):
            continue
        
        # Check duration max
        duration_max = conditions.get("duration_max")
        if duration_max and signal_duration > duration_max:
            continue
        
        # Check minimum confidence
        confidence_min = conditions.get("confidence_min")
        if confidence_min and confidence_float < confidence_min:
            continue
        
        # All conditions matched - apply the rule
        action = rule.get("action", {})
        action_type = action.get("type")
        
        if action_type == "multiply":
            factor = action.get("factor", 1.0)
            corrected_bpm = bpm_float * factor
            
            # Log the correction
            LOGGER.info(
                "🎚️ BPM calibration rule '%s': %.1f → %.1f BPM (factor %.1fx, energy=%.2f, duration=%.1fs)",
                rule.get("name", "unnamed"),
                bpm_float,
                corrected_bpm,
                factor,
                energy_float,
                signal_duration,
            )
            
            result["bpm"] = corrected_bpm
            result["bpm_calibration_applied"] = rule.get("name")
            
            # Only apply one rule per analysis
            return result
    
    return result


__all__ = [
    "CALIBRATED_RESULT_FIELDS",
    "CALIBRATION_METADATA",
    "CALIBRATION_MODEL_META",
    "CALIBRATION_MODELS",
    "CALIBRATION_RULES",
    "KEY_CALIBRATION_META",
    "KEY_CALIBRATION_RULES",
    "BPM_CALIBRATION_RULES",
    "BPM_CALIBRATION_META",
    "apply_calibration_layer",
    "apply_calibration_models",
    "apply_calibration_snapshot",
    "apply_key_calibration",
    "apply_bpm_calibration",
    "calibration_snapshot",
    "load_calibration_config",
    "load_calibration_models",
    "load_key_calibration",
    "load_bpm_calibration",
    "refresh_calibration_assets",
]
