#!/usr/bin/env python3
"""
One-off backfill script: stamp ISO-8601 UTC timestamps onto all existing
audio entries in diary.json so that the _mp3_stale() check has a valid
baseline for every historical entry.

Run ONCE after deploying the timestamp code:
    python scripts/backfill_audio_timestamps.py \
        --json /path/to/diary.json

For each QA pair that has a question_audio_path pointing to an existing file,
sets qa.generated_at to the file's mtime (if not already set).

For each variant in lesson_audio_paths that has an existing MP3,
sets lesson_mp3_timestamps[variant] to the file's mtime (if not already set).

Paths in diary.json are relative to the parent of the diary.json file.
"""

from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

# Allow running from repo root without installing the package
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from lingodiary.diary_json import load_diary_json, save_diary_json  # noqa: E402


def _mtime_iso(path: str) -> str:
    return datetime.fromtimestamp(os.path.getmtime(path), tz=timezone.utc).isoformat()


def backfill(diary_json_path: str | Path) -> None:
    diary_json_path = Path(diary_json_path).resolve()
    base_dir = diary_json_path.parent

    diary = load_diary_json(diary_json_path)

    qa_stamped = 0
    mp3_stamped = 0
    days_modified = 0

    for day in diary.diaries:
        day_modified = False

        for entry in day.entries:
            for variant_key in ("original", "enhanced", "future", "present"):
                variant = entry.lessons.get_variant(variant_key)
                if variant is None:
                    continue
                for qa in variant.qa:
                    if qa.generated_at is not None:
                        continue
                    audio_path = qa.question_audio_path or qa.answer_audio_path
                    if not audio_path:
                        continue
                    full = base_dir / audio_path
                    if full.exists():
                        qa.generated_at = _mtime_iso(str(full))
                        qa_stamped += 1
                        day_modified = True

        # Stamp MP3 timestamps for the full lesson files
        for variant_key, rel_path in day.lesson_audio_paths.items():
            if not rel_path:
                continue
            if day.lesson_mp3_timestamps.get(variant_key):
                continue
            full = base_dir / rel_path
            if full.exists():
                day.lesson_mp3_timestamps[variant_key] = _mtime_iso(str(full))
                mp3_stamped += 1
                day_modified = True

        if day_modified:
            days_modified += 1

    save_diary_json(diary, diary_json_path)

    print(
        f"Backfill complete: {qa_stamped} Q&A timestamps set, "
        f"{mp3_stamped} MP3 timestamps set across {days_modified} days."
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Backfill audio timestamps into diary.json from file mtimes."
    )
    parser.add_argument(
        "--json",
        required=True,
        metavar="PATH",
        help="Path to diary.json",
    )
    args = parser.parse_args()
    backfill(args.json)


if __name__ == "__main__":
    main()
