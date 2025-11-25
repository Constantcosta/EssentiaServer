"""Administrative and diagnostics routes for the analysis server."""

from __future__ import annotations

from datetime import datetime
from typing import Dict, Optional

from flask import jsonify, request
import sys


def error_hint_from_exception(exc: Exception) -> Optional[str]:
    """Return a friendly hint for common errors."""
    message = str(exc).lower()
    if "_generatorcontextmanager" in message:
        return (
            "The Python server is still running an older build. "
            "Stop the server in the macOS app, wait a few seconds, then press Start again so it reloads."
        )
    if "scipy.signal.hann" in message or "has no attribute 'hann'" in message:
        return "SciPy is missing the hann window. Run 'pip3 install --upgrade scipy' and restart the server."
    if "403" in message or "unauthorized" in message or "permission" in message:
        return "Apple Music previews often require entitlement-based auth; ensure the downloader has access."
    if "timeout" in message:
        return "Network timeout – verify the audio URL is reachable and retry."
    if "unsupported file type" in message or "codec" in message:
        return "Convert the source file to AAC/MP3/WAV before uploading."
    return None


def register_admin_routes(
    app,
    *,
    logger,
    default_port: int,
    production_mode: bool,
    server_build_signature: str,
    db_path: str,
    cache_dir: str,
    analysis_config: Dict[str, object],
    feature_flags: Dict[str, bool],
    export_dir: str,
    has_essentia: bool,
    scipy_hann_patched: bool,
    get_db_connection,
    get_url_hash,
):
    """Attach health, diagnostics, stats, shutdown, and manual verify routes."""

    @app.route("/health", methods=["GET"])
    def health_check():
        """Health check endpoint - simple ping"""
        return jsonify(
            {
                "running": True,
                "port": default_port,
                "version": server_build_signature,
                "status": "healthy",
                "server": "Mac Studio Audio Analysis Server",
                "timestamp": datetime.now().isoformat(),
            }
        )

    @app.route("/diagnostics", methods=["GET"])
    def diagnostics_check():
        """Comprehensive system diagnostics endpoint"""
        diagnostics = {
            "timestamp": datetime.now().isoformat(),
            "build": server_build_signature,
            "python_executable": sys.executable,
            "mode": "production" if production_mode else "development",
            "components": {},
            "configuration": {},
            "warnings": [],
            "overall_status": "healthy",
        }

        # Check database connectivity
        try:
            with get_db_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT COUNT(*) FROM analysis_cache")
                cache_count = cursor.fetchone()[0]
                cursor.execute("SELECT total_analyses FROM server_stats LIMIT 1")
                stats = cursor.fetchone()
                diagnostics["components"]["database"] = {
                    "status": "operational",
                    "path": db_path,
                    "cache_entries": cache_count,
                    "total_analyses": stats[0] if stats else 0,
                }
        except Exception as exc:
            diagnostics["components"]["database"] = {
                "status": "failed",
                "error": str(exc),
            }
            diagnostics["overall_status"] = "degraded"
            diagnostics["warnings"].append(f"Database error: {exc}")

        # Check Essentia availability
        diagnostics["components"]["essentia"] = {
            "status": "operational" if has_essentia else "unavailable",
            "available": has_essentia,
        }
        if not has_essentia:
            diagnostics["warnings"].append("Essentia library not available - using fallback algorithms")

        # Check calibration assets
        try:
            from backend.analysis.calibration import (
                CALIBRATION_RULES,
                CALIBRATION_MODELS,
                KEY_CALIBRATION_RULES,
            )

            scalers_loaded = bool(CALIBRATION_RULES)
            models_loaded = bool(CALIBRATION_MODELS)
            key_cal_loaded = bool(KEY_CALIBRATION_RULES)

            diagnostics["components"]["calibration"] = {
                "status": "operational" if (scalers_loaded and key_cal_loaded) else "degraded",
                "scalers_loaded": scalers_loaded,
                "scaler_count": len(CALIBRATION_RULES) if scalers_loaded else 0,
                "models_loaded": models_loaded,
                "model_count": len(CALIBRATION_MODELS) if models_loaded else 0,
                "key_calibration_loaded": key_cal_loaded,
                "key_rule_count": len(KEY_CALIBRATION_RULES) if key_cal_loaded else 0,
            }

            if not scalers_loaded:
                diagnostics["warnings"].append("Calibration scalers not loaded")
            if not models_loaded:
                diagnostics["warnings"].append("Calibration models not loaded - ML predictions unavailable")
            if not key_cal_loaded:
                diagnostics["warnings"].append("Key calibration not loaded")

        except Exception as exc:
            diagnostics["components"]["calibration"] = {
                "status": "failed",
                "error": str(exc),
            }
            diagnostics["warnings"].append(f"Calibration check error: {exc}")

        # Check scipy hann compatibility
        diagnostics["components"]["scipy_compat"] = {
            "status": "operational" if scipy_hann_patched else "degraded",
            "hann_patch_applied": scipy_hann_patched,
        }
        if not scipy_hann_patched:
            diagnostics["warnings"].append("SciPy hann window compatibility patch not applied")

        # Configuration info
        diagnostics["configuration"] = {
            "analysis": analysis_config,
            "features": feature_flags,
            "cache": {"cache_dir": cache_dir, "export_dir": export_dir},
            "security": {"production_mode": production_mode},
        }

        # Set overall status based on warnings
        if diagnostics["warnings"]:
            if any("failed" in str(w).lower() or "error" in str(w).lower() for w in diagnostics["warnings"]):
                diagnostics["overall_status"] = "degraded"

        # Check for critical failures
        if diagnostics["components"].get("database", {}).get("status") == "failed":
            diagnostics["overall_status"] = "unhealthy"

        return jsonify(diagnostics)

    @app.route("/stats", methods=["GET"])
    def get_stats():
        """Get server statistics"""
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT total_analyses, cache_hits, cache_misses, last_updated FROM server_stats LIMIT 1")
            stats = cursor.fetchone()

            cursor.execute("SELECT COUNT(*) FROM analysis_cache")
            total_cached = cursor.fetchone()[0]

        total = stats[0] if stats else 0
        hits = stats[1] if stats else 0
        misses = stats[2] if stats else 0
        last_updated = stats[3] if stats and len(stats) > 3 else datetime.now().isoformat()

        hit_rate = (hits / (hits + misses)) if (hits + misses) > 0 else 0.0

        return jsonify(
            {
                "total_analyses": total,
                "cache_hits": hits,
                "cache_misses": misses,
                "cache_hit_rate": hit_rate,
                "last_updated": last_updated,
                "total_cached_songs": total_cached,
            }
        )

    @app.route("/shutdown", methods=["POST"])
    def shutdown():
        """Shutdown the server"""
        logger.info("🛑 Server shutdown requested")
        func = request.environ.get("werkzeug.server.shutdown")
        if func is None:
            return jsonify({"error": "Not running with Werkzeug Server"}), 500
        func()
        return jsonify({"message": "Server shutting down..."})

    @app.route("/verify", methods=["POST"])
    def verify_manual():
        """Manual verification and override endpoint"""
        try:
            data = request.get_json()

            if not data or "url" not in data:
                return jsonify({"error": "Missing preview URL"}), 400

            preview_url = data["url"]
            url_hash = get_url_hash(preview_url)

            manual_bpm = data.get("manual_bpm")
            manual_key = data.get("manual_key")
            bpm_notes = data.get("bpm_notes")

            with get_db_connection() as conn:
                cursor = conn.cursor()
                cursor.execute(
                    """
                    UPDATE analysis_cache
                    SET user_verified = 1,
                        manual_bpm = ?,
                        manual_key = ?,
                        bpm_notes = ?
                    WHERE preview_url_hash = ?
                    """,
                    (manual_bpm, manual_key, bpm_notes, url_hash),
                )

            logger.info(
                "✅ User verified: %s - Manual BPM: %s, Notes: %s",
                data.get("title", "Unknown"),
                manual_bpm,
                bpm_notes,
            )

            return jsonify({"success": True, "message": "Song verified and updated"})

        except Exception as exc:
            logger.error("❌ Verification error: %s", exc)
            return jsonify({"error": str(exc)}), 500


__all__ = ["register_admin_routes", "error_hint_from_exception"]
