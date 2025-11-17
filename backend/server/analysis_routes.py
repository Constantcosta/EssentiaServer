"""Flask route registration for /analyze and /analyze_data endpoints."""

from __future__ import annotations

import os
from typing import Callable, Optional

import requests
from flask import jsonify, request

from backend.server.cache_store import DEFAULT_CACHE_NAMESPACE


# Module-level worker function (must be picklable for multiprocessing)
def _batch_analysis_worker(
    audio_bytes: bytes,
    title: str,
    artist: str,
    skip_chunk: bool,
    load_kwargs: dict,
    temp_suffix: str,
    use_tempfile: bool,
    cache_namespace: str,
):
    """Worker function for batch analysis - runs in subprocess.
    
    Imports functions here to avoid pickling closures.
    Each worker runs analysis sequentially (max_workers=0) to avoid nested multiprocessing.
    """
    from backend.server import process_audio_bytes
    from backend.server.cache_store import save_to_cache
    
    result = process_audio_bytes(
        audio_bytes,
        title,
        artist,
        skip_chunk,
        load_kwargs,
        use_tempfile=use_tempfile,
        temp_suffix=temp_suffix,
        max_workers=0,  # Sequential in worker - parallelism is at batch level
        timeout=120,  # 2-minute timeout per song
    )
    save_to_cache(
        f"audiodata://{artist}/{title}",
        title,
        artist,
        result,
        result["analysis_duration"],
        namespace=cache_namespace,
    )
    return result


def register_analysis_routes(
    app,
    *,
    logger,
    require_api_key: Callable,
    process_audio_bytes,
    check_cache,
    save_to_cache,
    update_stats,
    max_analysis_seconds: Optional[float],
    analysis_workers: int,
    error_hint_from_exception: Callable[[Exception], Optional[str]],
):
    """Wire /analyze + /analyze_data endpoints onto the provided Flask app."""

    def _truthy(value) -> bool:
        if isinstance(value, bool):
            return value
        if isinstance(value, (int, float)):
            return value != 0
        if isinstance(value, str):
            return value.strip().lower() in {"1", "true", "yes", "on", "y"}
        return False

    def _should_skip_chunk_analysis(payload: Optional[dict] = None) -> bool:
        header_value = request.headers.get("X-Skip-Chunk-Analysis")
        if header_value is not None:
            return _truthy(header_value)
        if payload and isinstance(payload, dict) and "skip_chunk_analysis" in payload:
            return _truthy(payload.get("skip_chunk_analysis"))
        return False

    def _should_force_reanalyze(payload: Optional[dict] = None) -> bool:
        header_value = request.headers.get("X-Force-Reanalyze") or request.headers.get("X-Bypass-Cache")
        if header_value is not None:
            return _truthy(header_value)
        if payload and isinstance(payload, dict):
            for key in ("force_reanalyze", "bypass_cache"):
                if key in payload:
                    return _truthy(payload.get(key))
        return False

    def _sanitize_cache_namespace(raw: Optional[str]) -> str:
        if not raw:
            return DEFAULT_CACHE_NAMESPACE
        cleaned = "".join(ch for ch in raw if ch.isalnum() or ch in {"-", "_"})
        if not cleaned:
            return DEFAULT_CACHE_NAMESPACE
        return cleaned[:32]

    def _resolve_cache_namespace(payload: Optional[dict] = None) -> str:
        header_value = request.headers.get("X-Cache-Namespace")
        if header_value:
            return _sanitize_cache_namespace(header_value)
        if payload and isinstance(payload, dict):
            for key in ("cache_namespace", "cacheNamespace"):
                if key in payload:
                    return _sanitize_cache_namespace(str(payload.get(key)))
        return DEFAULT_CACHE_NAMESPACE

    @app.route("/analyze", methods=["POST"])
    @require_api_key
    def analyze():
        payload = request.get_json()
        if not payload:
            return jsonify({"error": "Missing payload", "message": "Provide JSON with audio_url/title/artist"}), 400
        audio_url = payload.get("audio_url")
        title = payload.get("title")
        artist = payload.get("artist")
        if not audio_url or not title or not artist:
            return jsonify({"error": "Missing fields", "message": "Require audio_url, title, artist"}), 400
        skip_chunk = _should_skip_chunk_analysis(payload)
        force_reanalyze = _should_force_reanalyze(payload)
        cache_namespace = _resolve_cache_namespace(payload)
        cache_key = f"{audio_url}::chunk=skip" if skip_chunk else audio_url
        if force_reanalyze:
            logger.info(
                "🔁 Force re-analyze requested for %s (namespace=%s) – bypassing cache",
                title,
                cache_namespace,
            )
            cached_result = None
        else:
            cached_result = check_cache(cache_key, namespace=cache_namespace)
        if cached_result:
            logger.info("✅ Serving cached /analyze response for %s", title)
            update_stats(cache_hit=True)
            return jsonify(cached_result)
        try:
            response = requests.get(audio_url, timeout=30)
            response.raise_for_status()
        except Exception as exc:
            logger.exception("❌ Failed to download %s", audio_url)
            return jsonify({"error": "download_failed", "message": str(exc)}), 502
        load_kwargs = {"sr": None}
        if max_analysis_seconds:
            load_kwargs["duration"] = max_analysis_seconds
        temp_suffix = os.path.splitext(audio_url)[-1] or ".m4a"
        result = process_audio_bytes(
            response.content,
            title,
            artist,
            skip_chunk,
            load_kwargs,
            use_tempfile=False,
            temp_suffix=temp_suffix,
            max_workers=analysis_workers,
            timeout=120,  # 2 minute timeout per song
        )
        save_to_cache(
            cache_key,
            title,
            artist,
            result,
            result["analysis_duration"],
            namespace=cache_namespace,
        )
        update_stats(cache_hit=False)
        return jsonify(result)

    @app.route("/analyze_data", methods=["POST"])
    @require_api_key
    def analyze_data():
        try:
            audio_data = request.get_data()
            if not audio_data:
                return jsonify({"error": "No audio data provided"}), 400
            title = request.headers.get("X-Song-Title", "Unknown")
            artist = request.headers.get("X-Song-Artist", "Unknown")
            skip_chunk = _should_skip_chunk_analysis()
            force_reanalyze = _should_force_reanalyze()
            cache_namespace = _resolve_cache_namespace()
            logger.info("📨 Analyzing direct upload '%s' by %s", title, artist)
            cache_key = f"audiodata://{artist}/{title}"
            if skip_chunk:
                cache_key = f"{cache_key}::chunk=skip"
            if force_reanalyze:
                logger.info(
                    "🔁 Force re-analyze requested for direct upload '%s' (namespace=%s) – bypassing cache",
                    title,
                    cache_namespace,
                )
                cached_result = None
            else:
                cached_result = check_cache(cache_key, namespace=cache_namespace)
            if cached_result:
                logger.info("✅ Found direct-upload result in cache")
                update_stats(cache_hit=True)
                return jsonify(cached_result)
            load_kwargs = {"sr": None}
            if max_analysis_seconds:
                load_kwargs["duration"] = max_analysis_seconds
            result = process_audio_bytes(
                audio_data,
                title,
                artist,
                skip_chunk,
                load_kwargs,
                use_tempfile=True,
                temp_suffix=".m4a",
                max_workers=analysis_workers,
                timeout=120,  # 2 minute timeout per song
            )
            save_to_cache(
                cache_key,
                title,
                artist,
                result,
                result["analysis_duration"],
                namespace=cache_namespace,
            )
            update_stats(cache_hit=False)
            return jsonify(result)
        except TimeoutError as exc:
            logger.error("⏱️ Analysis timed out for direct upload '%s' by %s", title, artist)
            return jsonify({
                "error": "timeout",
                "message": str(exc),
                "hint": "Song analysis took longer than 2 minutes. This may indicate the server is overloaded or the song has processing issues."
            }), 504
        except Exception as exc:
            logger.exception("❌ Error analyzing direct upload")
            response = {
                "error": str(exc),
                "message": "Analysis failed",
            }
            hint = error_hint_from_exception(exc)
            if hint:
                response["hint"] = hint
            return jsonify(response), 500

    @app.route("/analyze_batch", methods=["POST"])
    @require_api_key
    def analyze_batch():
        """
        Batch analysis endpoint that processes multiple files in parallel.
        
        Request body should be JSON array of objects with:
        - audio_data: base64-encoded audio bytes
        - title: song title
        - artist: artist name
        
        Returns array of results in the same order.
        """
        import base64
        from concurrent.futures import as_completed
        
        payload = request.get_json()
        if not payload or not isinstance(payload, list):
            return jsonify({
                "error": "Invalid payload", 
                "message": "Provide JSON array of {audio_data, title, artist}"
            }), 400
        
        if len(payload) > 10:
            return jsonify({
                "error": "Too many files",
                "message": f"Maximum 10 files per batch, received {len(payload)}"
            }), 400
        
        skip_chunk = _should_skip_chunk_analysis()
        force_reanalyze = _should_force_reanalyze()
        cache_namespace = _resolve_cache_namespace()
        
        load_kwargs = {"sr": None}
        if max_analysis_seconds:
            load_kwargs["duration"] = max_analysis_seconds
        
        # Process files sequentially in the batch endpoint
        # Parallelism is handled by Swift sending multiple batch requests concurrently
        logger.info(f"🚀 Batch analyzing {len(payload)} files sequentially")
        
        results = []
        for idx, item in enumerate(payload):
            try:
                audio_b64 = item.get("audio_data")
                title = item.get("title", f"Unknown-{idx}")
                artist = item.get("artist", "Unknown")
                
                if not audio_b64:
                    results.append({"error": "Missing audio_data", "index": idx})
                    continue
                
                audio_bytes = base64.b64decode(audio_b64)
                
                cache_key = f"audiodata://{artist}/{title}"
                if skip_chunk:
                    cache_key = f"{cache_key}::chunk=skip"
                
                if not force_reanalyze:
                    cached_result = check_cache(cache_key, namespace=cache_namespace)
                    if cached_result:
                        results.append(cached_result)
                        update_stats(cache_hit=True)
                        continue
                
                result = _batch_analysis_worker(
                    audio_bytes,
                    title,
                    artist,
                    skip_chunk,
                    load_kwargs,
                    ".m4a",
                    True,  # use_tempfile
                    cache_namespace,
                )
                update_stats(cache_hit=False)
                results.append(result)
            except Exception as exc:
                logger.exception(f"❌ Error analyzing batch item {idx}")
                results.append({
                    "error": str(exc),
                    "index": idx,
                    "title": item.get("title", "Unknown"),
                })
        
        logger.info(f"✅ Completed batch analysis of {len(results)} files")
        return jsonify(results)


__all__ = ["register_analysis_routes"]
