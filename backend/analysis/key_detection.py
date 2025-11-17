"""Key detection entrypoint using shared helpers."""

from __future__ import annotations

import logging
from typing import Dict, List, Optional

import librosa
import numpy as np

from backend.analysis.settings import KEY_ANALYSIS_SAMPLE_RATE
from backend.analysis.utils import clamp_to_unit
from backend.analysis.key_detection_helpers import (
    KEY_NAMES,
    KEY_WINDOW_SECONDS,
    KEY_WINDOW_HOP_SECONDS,
    _HAS_ESSENTIA,
    _CHROMA_PEAK_ENERGY_MARGIN,
    _CHROMA_PEAK_SUPPORT_GAP,
    _CHROMA_PEAK_SUPPORT_RATIO,
    _DOMINANT_INTERVAL_STEPS,
    _DOMINANT_OVERRIDE_SCORE,
    _EDM_RELAXED_SCORE,
    _EDM_STRICT_SCORE,
    _FINAL_SUPPORT_FLOOR,
    _INTERVAL_OVERRIDE_STEPS,
    _MODE_BIAS_CONF_LIMIT,
    _MODE_BIAS_THRESHOLD,
    _MODE_RESCUE_SCORE,
    _MODE_VOTE_CONF_GAIN,
    _MODE_VOTE_THRESHOLD,
    _RUNNER_SCORE_MARGIN,
    _WINDOW_SUPPORT_DELTA,
    _WINDOW_SUPPORT_PROMOTION,
    _chroma_peak_root,
    _essentia_key_candidate,
    _essentia_supports,
    _interval_distance,
    _librosa_key_signature,
    _mode_bias_from_chroma,
    _mode_vote_breakdown,
    _normalize_mode_label,
    _resample_for_key_extractor,
    _root_support_ratio,
    _root_weight_map,
    _score_chroma_profile,
    _sorted_candidates,
    _vote_supports_candidate,
    configure_key_detection,
)

logger = logging.getLogger(__name__)

def detect_global_key(y_signal: np.ndarray, sr: int, adaptive_params: Optional[dict] = None) -> Dict[str, object]:
    """Estimate key using Essentia (when available) with a chroma fallback."""
    # Use adaptive parameters if provided, otherwise use defaults
    if adaptive_params is None:
        from backend.analysis.settings import get_adaptive_analysis_params
        # Estimate duration from signal length
        signal_duration = len(y_signal) / sr if sr > 0 else 0
        adaptive_params = get_adaptive_analysis_params(signal_duration)
    
    is_short_clip = adaptive_params.get('is_short_clip', False)
    use_window_consensus = adaptive_params.get('use_window_consensus', True)
    
    if is_short_clip:
        logger.info(
            f"🎬 Key detection for short clip: window_consensus={'enabled' if use_window_consensus else 'disabled'}"
        )
    
    result = {
        "key_index": 0,
        "mode": "Major",
        "confidence": 0.0,
        "tuning": 0.0,
        "chroma_profile": np.zeros(12, dtype=float).tolist(),
        "scores": [],
    }
    if y_signal.size == 0 or sr <= 0:
        return result
    key_signal = y_signal
    key_sr = sr
    if (
        KEY_ANALYSIS_SAMPLE_RATE > 0
        and sr > KEY_ANALYSIS_SAMPLE_RATE * 1.02
        and y_signal.size > KEY_ANALYSIS_SAMPLE_RATE // 2
    ):
        try:
            key_signal = librosa.resample(
                y_signal.astype(np.float32),
                orig_sr=sr,
                target_sr=KEY_ANALYSIS_SAMPLE_RATE,
                res_type="kaiser_fast",
            )
            key_sr = KEY_ANALYSIS_SAMPLE_RATE
        except Exception as exc:
            logger.warning("⚠️ Key-analysis resample failed (%s) – falling back to original SR.", exc)
            key_signal = y_signal
            key_sr = sr
    try:
        tuning = float(librosa.estimate_tuning(y=key_signal, sr=key_sr))
    except Exception:
        tuning = 0.0
    chroma_profile, fallback_scores, fallback_conf, vote_meta = _librosa_key_signature(
        key_signal, key_sr, tuning, use_window_consensus=use_window_consensus
    )
    fallback_scores = list(fallback_scores or [])
    sorted_candidates = _sorted_candidates(fallback_scores)
    fallback_best_score = float(sorted_candidates[0].get("score", 0.0)) if sorted_candidates else float(fallback_conf)
    runner_candidate = sorted_candidates[1] if len(sorted_candidates) > 1 else None
    essentia_std_candidate: Optional[Dict[str, object]] = None
    essentia_edm_candidate: Optional[Dict[str, object]] = None
    if _HAS_ESSENTIA:
        essentia_std_candidate = _essentia_key_candidate(key_signal, key_sr, edm=False)
        try:
            essentia_edm_candidate = _essentia_key_candidate(key_signal, key_sr, edm=True)
        except Exception:
            essentia_edm_candidate = None
    best_entry = vote_meta.get("best") if isinstance(vote_meta, dict) else None
    fallback_root = int(best_entry.get("root", 0)) if best_entry else 0
    fallback_mode = best_entry.get("mode", "Major") if best_entry else "Major"
    def _record_essentia_score(candidate: Optional[Dict[str, object]], source_label: str):
        if not candidate:
            return
        ess_root = candidate.get("root")
        if ess_root is None:
            return
        ess_mode = candidate.get("mode")
        ess_score = clamp_to_unit(candidate.get("score", 0.0))
        try:
            result["scores"].append(
                {
                    "root": int(ess_root) % 12,
                    "mode": ess_mode,
                    "score": ess_score,
                    "source": source_label,
                }
            )
        except Exception:
            pass

    def _blend_essentia_candidate(
        candidate: Optional[Dict[str, object]],
        source_label: str,
        strict_score: float = 0.55,
        mode_score: float = 0.35,
        rescue_score: float = 0.4,
    ):
        nonlocal final_root, final_mode, final_confidence, key_source
        if not candidate:
            return
        ess_root = candidate.get("root")
        if ess_root is None:
            return
        ess_mode = _normalize_mode_label(candidate.get("mode", final_mode))
        ess_score = clamp_to_unit(candidate.get("score", 0.0))
        try:
            ess_root = int(ess_root) % 12
        except (TypeError, ValueError):
            return
        differs = ess_root != final_root or ess_mode != final_mode
        if ess_score >= strict_score and differs:
            final_root = ess_root
            final_mode = ess_mode
            final_confidence = max(final_confidence, ess_score)
            key_source = source_label
            return
        if ess_root == final_root and ess_mode != final_mode and ess_score >= mode_score:
            final_mode = ess_mode
            final_confidence = max(final_confidence, ess_score)
            key_source = f"{source_label}_mode"
            return
        if ess_score >= rescue_score and final_confidence < 0.35:
            final_root = ess_root
            final_mode = ess_mode
            final_confidence = max(final_confidence, ess_score)
            key_source = source_label

    def _apply_dominant_interval_override(candidate: Optional[Dict[str, object]], source_label: str):
        nonlocal final_root, final_mode, final_confidence, key_source, final_support_ratio
        if not candidate:
            return
        cand_root = candidate.get("root")
        if cand_root is None:
            return
        try:
            cand_root = int(cand_root) % 12
        except (TypeError, ValueError):
            return
        cand_mode = _normalize_mode_label(candidate.get("mode", final_mode))
        cand_score = clamp_to_unit(candidate.get("score", 0.0))
        if cand_score < _DOMINANT_OVERRIDE_SCORE:
            return
        interval = _interval_distance(final_root, cand_root)
        if interval in _DOMINANT_INTERVAL_STEPS:
            final_root = cand_root
            final_mode = cand_mode
            final_confidence = max(final_confidence, cand_score)
            key_source = f"{source_label}_dominant"
            final_support_ratio = _root_support_ratio(window_root_weights, final_root)
            return

    def _mode_rescue_from_candidate(candidate: Optional[Dict[str, object]], source_label: str):
        nonlocal final_mode, final_confidence, key_source
        if not candidate:
            return
        cand_root = candidate.get("root")
        if cand_root is None:
            return
        try:
            cand_root = int(cand_root) % 12
        except (TypeError, ValueError):
            return
        cand_mode = _normalize_mode_label(candidate.get("mode", final_mode))
        cand_score = clamp_to_unit(candidate.get("score", 0.0))
        if cand_root == final_root and cand_mode != final_mode and cand_score >= _MODE_RESCUE_SCORE:
            final_mode = cand_mode
            final_confidence = max(final_confidence, cand_score)
            key_source = f"{source_label}_mode_rescue"

    result.update(
        {
            "key_index": fallback_root,
            "mode": fallback_mode,
            "confidence": fallback_conf,
            "chroma_profile": chroma_profile,
            "scores": fallback_scores,
            "tuning": tuning,
        }
    )
    
    # DEBUG: Log initial fallback values to diagnose "stuck on D" issue
    logger.info(
        f"🔑 Initial fallback: {KEY_NAMES[fallback_root]} {fallback_mode} (index {fallback_root}, conf {fallback_conf:.2f})"
    )
    chroma_array = np.array(chroma_profile, dtype=float)
    
    # DEBUG: Log chroma profile distribution
    logger.debug(f"🎨 Chroma profile: {[f'{v:.3f}' for v in chroma_array]}")
    
    if runner_candidate:
        try:
            runner_gap = fallback_best_score - float(runner_candidate.get("score", 0.0) or 0.0)
            result["runner_up_score_gap"] = float(max(0.0, runner_gap))
        except (TypeError, ValueError):
            pass
    window_meta = vote_meta.get("window_consensus") if isinstance(vote_meta, dict) else None
    if window_meta:
        result["window_consensus"] = window_meta
    final_root = fallback_root
    final_mode = fallback_mode
    final_confidence = fallback_conf
    key_source = "librosa"
    window_votes: List[Dict[str, object]] = []
    window_root_weights: Dict[int, float] = {}
    if window_meta and isinstance(window_meta, dict):
        window_votes = window_meta.get("votes") or []
        window_root_weights = _root_weight_map(window_votes)
        best_window = window_meta.get("best") or {}
        dominance = float(window_meta.get("dominance") or 0.0)
        total_weight = float(window_meta.get("total_weight") or 0.0)
        runner_weight = float(window_meta.get("runner_up_weight") or 0.0)
        separation = 0.0
        if total_weight > 0:
            separation = (float(best_window.get("weight", 0.0)) - runner_weight) / total_weight
        window_root = best_window.get("root")
        window_mode = best_window.get("mode")
        if window_root is not None:
            window_root = int(window_root) % 12
            same_root = window_root == final_root
            same_mode = str(window_mode or final_mode) == final_mode
            if dominance >= 0.5 and (not same_root or not same_mode):
                if separation >= 0.15 or dominance >= 0.65:
                    final_root = window_root
                    final_mode = window_mode or final_mode
                    final_confidence = max(final_confidence, min(0.99, dominance))
                    key_source = "window_consensus"
            elif same_root and not same_mode and separation >= 0.05:
                final_mode = window_mode or final_mode
                final_confidence = max(final_confidence, min(0.95, dominance))
                key_source = "window_consensus"
    final_support_ratio = _root_support_ratio(window_root_weights, final_root)
    if runner_candidate:
        try:
            runner_score = float(runner_candidate.get("score", 0.0) or 0.0)
        except (TypeError, ValueError):
            runner_score = 0.0
        score_gap = fallback_best_score - runner_score
        candidate_root = runner_candidate.get("root")
        candidate_mode = _normalize_mode_label(runner_candidate.get("mode"))
        if candidate_root is not None:
            candidate_root = int(candidate_root) % 12
            interval = _interval_distance(candidate_root, final_root)
            candidate_support_ratio = _root_support_ratio(window_root_weights, candidate_root)
            support_delta = candidate_support_ratio - final_support_ratio
            window_support = candidate_support_ratio >= _WINDOW_SUPPORT_PROMOTION or support_delta >= _WINDOW_SUPPORT_DELTA
            ess_support = False
            if not window_support:
                ess_support = _essentia_supports(essentia_std_candidate, candidate_root, candidate_mode, 0.35)
            if not window_support and not ess_support:
                ess_support = _essentia_supports(essentia_edm_candidate, candidate_root, candidate_mode, 0.45)
            weak_final = final_support_ratio < _FINAL_SUPPORT_FLOOR
            promote_runner = window_support or ess_support
            if not promote_runner and weak_final and score_gap <= (_RUNNER_SCORE_MARGIN * 0.6):
                promote_runner = True
            if interval in _INTERVAL_OVERRIDE_STEPS and promote_runner:
                margin = _RUNNER_SCORE_MARGIN
                if candidate_support_ratio >= (_WINDOW_SUPPORT_PROMOTION + 0.1):
                    margin *= 1.8
                if ess_support or weak_final:
                    margin *= 1.2
                if score_gap <= margin or ess_support:
                    final_root = candidate_root
                    final_mode = candidate_mode
                    final_confidence = max(
                        final_confidence,
                        min(0.75, max(candidate_support_ratio, fallback_conf) + 0.15),
                    )
                    key_source = "runner_interval"
                    final_support_ratio = _root_support_ratio(window_root_weights, final_root)
    if window_votes:
        mode_breakdown, mode_weight = _mode_vote_breakdown(window_votes, final_root)
        if mode_weight > 0:
            major_ratio = mode_breakdown.get("Major", 0.0) / mode_weight
            minor_ratio = mode_breakdown.get("Minor", 0.0) / mode_weight
            mode_difference = abs(major_ratio - minor_ratio)
            dominant_mode = "Major" if major_ratio >= minor_ratio else "Minor"
            if mode_difference >= _MODE_VOTE_THRESHOLD and dominant_mode != final_mode:
                final_mode = dominant_mode
                final_confidence = max(final_confidence, min(0.85, final_confidence + mode_difference * _MODE_VOTE_CONF_GAIN))
                key_source = "window_mode_votes"
    if chroma_array.size >= 12:
        peak_root, peak_energy = _chroma_peak_root(chroma_array)
        
        # DEBUG: Log chroma peak analysis
        logger.debug(
            f"🎨 Chroma peak: {KEY_NAMES[peak_root]} (index {peak_root}, energy {peak_energy:.3f}) "
            f"vs current: {KEY_NAMES[final_root]} (energy {float(chroma_array[final_root % 12]):.3f})"
        )
        
        if peak_root != final_root:
            try:
                final_energy = float(chroma_array[final_root % chroma_array.size])
            except Exception:
                final_energy = float(chroma_array[final_root % 12])
            energy_gap = peak_energy - final_energy
            peak_support = _root_support_ratio(window_root_weights, peak_root)
            support_gap = peak_support - final_support_ratio
            if (
                energy_gap >= _CHROMA_PEAK_ENERGY_MARGIN
                or peak_support >= _CHROMA_PEAK_SUPPORT_RATIO
                or support_gap >= _CHROMA_PEAK_SUPPORT_GAP
            ):
                final_root = peak_root
                final_confidence = max(final_confidence, min(0.9, max(final_confidence, peak_support) + 0.1))
                key_source = "chroma_peak"
                final_support_ratio = peak_support
    if essentia_std_candidate:
        result["essentia"] = essentia_std_candidate
        _record_essentia_score(essentia_std_candidate, "essentia_std")
        _blend_essentia_candidate(essentia_std_candidate, "essentia", strict_score=0.55, mode_score=0.35, rescue_score=0.4)
        _apply_dominant_interval_override(essentia_std_candidate, "essentia")
    if essentia_edm_candidate:
        result["essentia_edm"] = essentia_edm_candidate
        _record_essentia_score(essentia_edm_candidate, "essentia_edm")
        _blend_essentia_candidate(
            essentia_edm_candidate,
            "essentia_edm",
            strict_score=_EDM_STRICT_SCORE,
            mode_score=0.33,
            rescue_score=_EDM_RELAXED_SCORE,
        )
        _apply_dominant_interval_override(essentia_edm_candidate, "essentia_edm")
    final_mode = str(final_mode or "Major")
    mode_bias_value = _mode_bias_from_chroma(chroma_array, final_root)
    result["mode_bias"] = mode_bias_value
    if abs(mode_bias_value) >= _MODE_BIAS_THRESHOLD and final_confidence < _MODE_BIAS_CONF_LIMIT:
        inferred_mode = "Major" if mode_bias_value >= 0 else "Minor"
        if inferred_mode != final_mode:
            final_mode = inferred_mode
            final_confidence = max(final_confidence, min(0.55, final_confidence + abs(mode_bias_value) * 0.4))
            key_source = "mode_bias"
    _mode_rescue_from_candidate(essentia_std_candidate, "essentia")
    _mode_rescue_from_candidate(essentia_edm_candidate, "essentia_edm")
    result["key_index"] = int(final_root) % 12
    result["mode"] = final_mode
    result["confidence"] = clamp_to_unit(final_confidence)
    result["key_source"] = key_source
    
    # DEBUG: Log final key detection result
    logger.info(
        f"🎹 Final key: {KEY_NAMES[int(final_root) % 12]} {final_mode} "
        f"(index {int(final_root) % 12}, conf {clamp_to_unit(final_confidence):.2f}, source: {key_source})"
    )
    
    return result


__all__ = ["KEY_NAMES", "detect_global_key", "configure_key_detection"]

__all__ = ["KEY_NAMES", "detect_global_key", "configure_key_detection"]
