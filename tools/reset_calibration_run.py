#!/usr/bin/env python3
"""
Reset the MacStudioServerSimulator calibration workspace so each sweep starts
with a clean slate of staged songs/exports.

This CLI archives the current contents of
~/Library/Application Support/MacStudioServerSimulator/{CalibrationSongs,
calibration_songs.json, CalibrationExports} into a timestamped run folder and
recreates the folders the Mac app expects. Use it whenever you want to run a
small targeted calibration pass without reusing the previous playlist.
"""
from __future__ import annotations

import argparse
import datetime as dt
import shutil
from pathlib import Path
from typing import Optional


APP_SUPPORT_DIR = (
    Path.home()
    / "Library"
    / "Application Support"
    / "MacStudioServerSimulator"
)
CALIBRATION_SONGS_DIR = APP_SUPPORT_DIR / "CalibrationSongs"
CALIBRATION_EXPORTS_DIR = APP_SUPPORT_DIR / "CalibrationExports"
CALIBRATION_METADATA = APP_SUPPORT_DIR / "calibration_songs.json"
ARCHIVE_ROOT = APP_SUPPORT_DIR / "CalibrationRuns"


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def archive_path(source: Path, run_dir: Path) -> Optional[Path]:
    if not source.exists():
        return None
    ensure_dir(run_dir)
    destination = run_dir / source.name
    if destination.exists():
        # Avoid collision by appending suffix
        destination = destination.with_name(f"{destination.name}_{dt.datetime.now():%H%M%S}")
    shutil.move(str(source), str(destination))
    return destination


def reset_calibration(run_label: str, archive_exports: bool) -> dict[str, Optional[str]]:
    timestamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    run_id = f"{timestamp}_{run_label}" if run_label else timestamp
    run_dir = ARCHIVE_ROOT / run_id
    ensure_dir(run_dir)

    summary: dict[str, Optional[str]] = {
        "run_id": run_id,
        "songs_archive": None,
        "metadata_archive": None,
        "exports_archive": None,
        "songs_folder": str(CALIBRATION_SONGS_DIR),
        "exports_folder": str(CALIBRATION_EXPORTS_DIR),
    }

    songs_archive = archive_path(CALIBRATION_SONGS_DIR, run_dir)
    metadata_archive = archive_path(CALIBRATION_METADATA, run_dir) if CALIBRATION_METADATA.exists() else None
    exports_archive = archive_path(CALIBRATION_EXPORTS_DIR, run_dir) if (archive_exports and CALIBRATION_EXPORTS_DIR.exists()) else None

    summary["songs_archive"] = str(songs_archive) if songs_archive else None
    summary["metadata_archive"] = str(metadata_archive) if metadata_archive else None
    summary["exports_archive"] = str(exports_archive) if exports_archive else None

    # Recreate expected folders for the Mac app
    ensure_dir(CALIBRATION_SONGS_DIR)
    ensure_dir(CALIBRATION_EXPORTS_DIR)
    if not CALIBRATION_METADATA.exists():
        CALIBRATION_METADATA.write_text("[]", encoding="utf-8")

    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description="Reset staged calibration songs/exports for a fresh run.")
    parser.add_argument(
        "--run-label",
        default="manual",
        help="Optional tag appended to the archive folder (default: manual).",
    )
    parser.add_argument(
        "--include-exports",
        action="store_true",
        help="Also archive and clear the CalibrationExports folder.",
    )
    args = parser.parse_args()

    summary = reset_calibration(args.run_label.strip(), args.include_exports)

    print("✅ Calibration workspace reset.")
    print(f"Run archive: {ARCHIVE_ROOT / summary['run_id']}")
    if summary["songs_archive"]:
        print(f"• Moved staged songs → {summary['songs_archive']}")
    else:
        print("• No staged songs to archive.")
    if summary["metadata_archive"]:
        print(f"• Archived calibration_songs.json → {summary['metadata_archive']}")
    else:
        print("• No calibration metadata file found (nothing to archive).")
    if args.include_exports:
        if summary["exports_archive"]:
            print(f"• Archived CalibrationExports → {summary['exports_archive']}")
        else:
            print("• No exports folder to archive.")
    print(f"Fresh songs folder: {summary['songs_folder']}")
    print(f"Fresh exports folder: {summary['exports_folder']}")
    print("Next steps:")
    print("  1. Relaunch the Mac Studio Server app (Calibration tab will show 0 staged songs).")
    print("  2. Use “Add Songs…” or drag-and-drop to stage your targeted sample set.")
    print("  3. Run the calibration sweep to generate a dataset just for this run.")


if __name__ == "__main__":
    main()
