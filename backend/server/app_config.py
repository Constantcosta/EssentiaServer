"""Shared, typed configuration for the analysis server.

This keeps environment overrides discoverable for agents and avoids spreading
one-off globals across modules.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ServerConfig:
    repo_root: Path
    expected_venv_python: Path
    allow_system_python: bool
    production_mode: bool
    default_port: int
    host: str | None
    cache_dir: Path
    db_path: Path
    log_file: Path
    rate_limit: int

    @classmethod
    def from_env(cls, repo_root: Path) -> "ServerConfig":
        """Build config from environment with sensible defaults."""
        production_mode = os.environ.get("PRODUCTION_MODE", "false").lower() == "true"
        default_port = int(os.environ.get("MAC_STUDIO_SERVER_PORT", "5050"))
        host = os.environ.get("MAC_STUDIO_SERVER_HOST")
        cache_dir = Path(os.environ.get("MAC_STUDIO_CACHE_DIR", "~/Music/AudioAnalysisCache")).expanduser()
        db_path = Path(os.environ.get("MAC_STUDIO_DB_PATH", "~/Music/audio_analysis_cache.db")).expanduser()
        cache_dir.mkdir(parents=True, exist_ok=True)
        log_file = cache_dir / "server.log"
        rate_limit = int(os.environ.get("RATE_LIMIT", "60"))
        expected_venv_python = repo_root / ".venv" / "bin" / "python"
        allow_system_python = os.environ.get("ALLOW_SYSTEM_PYTHON", "").strip() == "1"
        return cls(
            repo_root=repo_root,
            expected_venv_python=expected_venv_python,
            allow_system_python=allow_system_python,
            production_mode=production_mode,
            default_port=default_port,
            host=host,
            cache_dir=cache_dir,
            db_path=db_path,
            log_file=log_file,
            rate_limit=rate_limit,
        )

