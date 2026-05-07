"""
migrate_to_json.py — One-time migration utility.

Reads all existing Markdown diary files (diary entries + all TPRS variant files)
for a given user and writes a consolidated diary.json in the new schema.

Existing markdown files are NOT modified or deleted — they remain as backup/fallback.

Usage:
    python -m lingoanki.migrate_to_json \\
        --config ~/.config/lingoDiary/config.yaml \\
        --output ~/Documents/lingodiary/<user>/diary.json

    # Or call programmatically:
    from lingoanki.migrate_to_json import migrate_markdown_to_json
    migrate_markdown_to_json(config_path, output_json_path, overwrite=False)
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from datetime import datetime
from pathlib import Path

from lingoanki.diary import DiaryHandler
from lingoanki.diary_json import (
    DiaryEntry,
    DiaryJson,
    LessonsBlock,
    QA,
    ReviewingState,
    VariantLesson,
    get_day,
    load_diary_json,
    save_diary_json,
    upsert_day,
)

logger = logging.getLogger(__name__)

# Maps variant display name → (json_key, file_suffix)
_VARIANTS: list[tuple[str, str, str]] = [
    ("Standard", "original", ""),
    ("Enhanced", "enhanced", "_enhanced"),
    ("Future", "future", "_future"),
    ("Present", "present", "_present"),
]


def _date_obj_to_str(date_obj) -> str:
    """Convert a datetime / datetime.date object to 'YYYY/MM/DD' string."""
    if isinstance(date_obj, datetime):
        return date_obj.strftime("%Y/%m/%d")
    return date_obj.strftime("%Y/%m/%d")


# Suffixes used by non-standard variants — used to filter Standard files
_VARIANT_SUFFIXES = ("_enhanced", "_future", "_present")


def _read_per_day_variant_files(
    diary_handler: DiaryHandler,
    config: dict,
    file_suffix: str,
    display_name: str,
) -> dict:
    """
    Read per-day TPRS markdown files from the TPRS/ subdirectory.

    Prefers files that have a matching .mp3 (audio-first), which are guaranteed
    to match what was actually spoken.  Falls back to a config-name glob if no
    audio-matched files exist.

    Does NOT instantiate TprsCreation — avoids triggering any content regeneration.

    Returns {date_obj: ordered_list_of_(sentence, qa_raw_dict)}.
    """
    import glob as glob_module

    tprs_dir = os.path.join(config.get("output_dir", ""), "TPRS")

    if not os.path.isdir(tprs_dir):
        logger.warning(f"  TPRS dir not found for '{display_name}' — no Q&A data.")
        return {}

    # ── Strategy 1: files with a matching .mp3 ────────────────────────────────
    if file_suffix:
        all_md = sorted(
            glob_module.glob(os.path.join(tprs_dir, f"*_TPRS_*{file_suffix}.md"))
        )
    else:
        all_md = sorted(glob_module.glob(os.path.join(tprs_dir, "*_TPRS_*.md")))
        all_md = [
            f
            for f in all_md
            if not any(
                os.path.basename(f).endswith(f"{s}.md") for s in _VARIANT_SUFFIXES
            )
        ]

    audio_matched = [
        f for f in all_md if os.path.exists(os.path.splitext(f)[0] + ".mp3")
    ]

    if audio_matched:
        logger.info(
            f"  '{display_name}': {len(audio_matched)} audio-matched files found."
        )
        chosen = audio_matched
    else:
        # ── Strategy 2: fall back to config lesson-name glob ──────────────────
        lesson_name = config.get("tprs_lesson_name", "")
        if file_suffix:
            pattern = os.path.join(
                tprs_dir, f"{glob_module.escape(lesson_name)}_TPRS_*{file_suffix}.md"
            )
        else:
            pattern = os.path.join(
                tprs_dir, f"{glob_module.escape(lesson_name)}_TPRS_*.md"
            )
        chosen = sorted(glob_module.glob(pattern))
        if not file_suffix:
            chosen = [
                f
                for f in chosen
                if not any(
                    os.path.basename(f).endswith(f"{s}.md") for s in _VARIANT_SUFFIXES
                )
            ]
        if chosen:
            logger.info(
                f"  '{display_name}': {len(chosen)} config-name files (no audio match)."
            )
        else:
            logger.warning(
                f"  '{display_name}': no per-day files found — variant will have no Q&A."
            )
            return {}

    result: dict = {}
    for filepath in chosen:
        try:
            content = diary_handler.read_markdown_file(filepath)
            parsed, date_str = diary_handler.read_tprs_day_block(content)
            if not parsed or not date_str:
                continue
            date_obj = datetime.strptime(date_str, "%Y/%m/%d")
            ordered = []
            for sentence, qa_tuples in parsed.items():
                qa_raw = {
                    str(i + 1): {"question": q, "answer": a}
                    for i, (q, a) in enumerate(qa_tuples)
                }
                ordered.append((sentence, qa_raw))
            result[date_obj] = ordered
        except Exception as exc:
            logger.warning(f"  Failed to parse {filepath}: {exc}")

    return result


def migrate_markdown_to_json(
    config_path: str | Path,
    output_json_path: str | Path,
    overwrite: bool = False,
) -> DiaryJson:
    """
    Parse all existing Markdown diary files for a user and write diary.json.

    Args:
        config_path:      Path to the user's config.yaml.
        output_json_path: Destination path for diary.json.
        overwrite:        If False (default), raise if output file already exists.

    Returns:
        The populated DiaryJson object.
    """
    output_json_path = Path(output_json_path)

    if output_json_path.exists() and not overwrite:
        raise FileExistsError(
            f"{output_json_path} already exists. Pass overwrite=True to replace it."
        )

    logger.info("=== LingoAnki Markdown → JSON Migration ===")
    logger.info(f"Config: {config_path}")
    logger.info(f"Output: {output_json_path}")

    # ── Step 1: Parse diary entries (input/output/tips) ───────────────────────
    logger.info("Step 1: Parsing diary entries from Markdown…")
    diary_handler = DiaryHandler(config_path=str(config_path))
    diary_dict = diary_handler.markdown_diary_to_dict()
    # diary_dict: {date_obj: {"title": str, "sentences": {0: {...}}}}

    entry_count = sum(len(v["sentences"]) for v in diary_dict.values())
    logger.info(f"  Found {len(diary_dict)} days, {entry_count} sentences.")

    # ── Step 2: Parse all TPRS variant files (no TprsCreation — avoids side effects) ──
    logger.info("Step 2: Parsing TPRS variant Markdown files…")
    config = diary_handler.config

    variant_dicts: dict[str, dict] = {}
    for display_name, json_key, file_suffix in _VARIANTS:
        tprs_data = _read_per_day_variant_files(
            diary_handler, config, file_suffix, display_name
        )
        day_count = len(tprs_data)
        qa_count = sum(len(sentences) for sentences in tprs_data.values())
        logger.info(
            f"  Variant '{display_name}' ({json_key}): {day_count} days, {qa_count} sentences with Q&A."
        )
        variant_dicts[json_key] = tprs_data

    # ── Step 3: Build the DiaryJson structure ─────────────────────────────────
    logger.info("Step 3: Building JSON structure…")
    diary_json = DiaryJson()

    for date_obj, day_data in sorted(diary_dict.items()):
        date_str = _date_obj_to_str(date_obj)
        title = day_data.get("title", "")
        sentences_data = day_data.get("sentences", {})

        # Pre-build ordered position lists per variant for this date (match by index)
        day_tprs_by_variant: dict[str, list[tuple[str, dict]]] = {}
        for json_key, tprs_date_dict in variant_dicts.items():
            for tprs_date_obj, tprs_sentences in tprs_date_dict.items():
                if _date_obj_to_str(tprs_date_obj) == date_str:
                    # already a list of (sentence_text, qa_raw_dict)
                    day_tprs_by_variant[json_key] = (
                        tprs_sentences
                        if isinstance(tprs_sentences, list)
                        else list(tprs_sentences.items())
                    )
                    break

        entries: list[DiaryEntry] = []
        for position, (idx, sentence_dict) in enumerate(sorted(sentences_data.items())):
            input_sentence = sentence_dict.get("primary_language_sentence", "").strip()
            output_sentence = sentence_dict.get("study_language_sentence", "").strip()
            trial = sentence_dict.get("study_language_sentence_trial", "").strip()
            tips = sentence_dict.get("tips", "").strip()

            lessons = LessonsBlock(reviewing=ReviewingState())

            # Match TPRS Q&A by position (index), not by text.
            # Each variant lists sentences in the same order as diary entries.
            for json_key, ordered_sentences in day_tprs_by_variant.items():
                if position >= len(ordered_sentences):
                    logger.warning(
                        f"  {date_str} [{json_key}]: no entry at position {position}, skipping."
                    )
                    continue
                tprs_sentence_text, qa_raw = ordered_sentences[position]
                qa_list = _parse_qa_raw(qa_raw)
                lessons.set_variant(
                    json_key, VariantLesson(sentence=tprs_sentence_text, qa=qa_list)
                )

            entry = DiaryEntry(
                index=int(idx),
                input_language_sentence=input_sentence,
                user_trial_translation=trial,
                output_language_translation=output_sentence,
                tips=tips,
                lessons=lessons,
            )
            entries.append(entry)

        diary_json = upsert_day(diary_json, date_str, title, entries)
        logger.info(f"  {date_str}: {len(entries)} entries added.")

    # ── Step 4: Write JSON ────────────────────────────────────────────────────
    logger.info(f"Step 4: Writing JSON to {output_json_path}…")
    save_diary_json(diary_json, output_json_path)

    total_entries = sum(len(day.entries) for day in diary_json.diaries)
    logger.info(
        f"Migration complete: {len(diary_json.diaries)} days, "
        f"{total_entries} entries written to {output_json_path}"
    )
    return diary_json


# ── Matching helpers ──────────────────────────────────────────────────────────


def _find_best_sentence_match(
    target: str, tprs_day: dict
) -> tuple[str | None, dict | None]:
    """
    Find the best matching sentence key in tprs_day for the given target string.

    Returns (matched_sentence_key, qa_raw_dict) or (None, None).
    Tries exact match first, then case-insensitive, then substring overlap.
    """
    if not target:
        return None, None

    # Exact match
    if target in tprs_day:
        return target, tprs_day[target]

    target_lower = target.lower().strip()

    # Case-insensitive exact
    for key in tprs_day:
        if key.lower().strip() == target_lower:
            return key, tprs_day[key]

    # Best substring overlap (longest common prefix heuristic)
    best_key = None
    best_score = 0
    for key in tprs_day:
        score = _overlap_score(target_lower, key.lower().strip())
        if score > best_score:
            best_score = score
            best_key = key

    # Only accept if meaningful overlap (> 40% of shorter string)
    if best_key is not None:
        shorter = min(len(target_lower), len(best_key.lower()))
        if shorter > 0 and best_score / shorter > 0.4:
            return best_key, tprs_day[best_key]

    return None, None


def _overlap_score(a: str, b: str) -> int:
    """Count common leading characters (simple prefix match length)."""
    score = 0
    for ca, cb in zip(a, b):
        if ca == cb:
            score += 1
        else:
            break
    return score


def _parse_qa_raw(qa_raw: dict) -> list[QA]:
    """
    Convert the raw Q&A dict from _read_variant_tprs_to_dict into a list of QA objects.

    The raw format is either:
      {"1": {"question": "...", "answer": "..."}, ...}  — dict of numbered items
    or a list of (question, answer) tuples.
    """
    qa_list: list[QA] = []
    if isinstance(qa_raw, dict):
        for key in sorted(qa_raw.keys(), key=lambda k: int(k) if k.isdigit() else 0):
            item = qa_raw[key]
            if isinstance(item, dict):
                qa_list.append(
                    QA(question=item.get("question", ""), answer=item.get("answer", ""))
                )
            elif isinstance(item, (list, tuple)) and len(item) == 2:
                qa_list.append(QA(question=item[0], answer=item[1]))
    elif isinstance(qa_raw, list):
        for item in qa_raw:
            if isinstance(item, (list, tuple)) and len(item) == 2:
                qa_list.append(QA(question=item[0], answer=item[1]))
    return qa_list


# ── CLI ───────────────────────────────────────────────────────────────────────


def _setup_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s  %(levelname)-8s  %(message)s",
        datefmt="%H:%M:%S",
    )


def main(argv: list[str] | None = None) -> int:
    _setup_logging()
    parser = argparse.ArgumentParser(
        description="Migrate LingoAnki Markdown diary files to diary.json"
    )
    parser.add_argument(
        "--config",
        required=True,
        metavar="PATH",
        help="Path to the user's config.yaml",
    )
    parser.add_argument(
        "--output",
        required=True,
        metavar="PATH",
        help="Destination path for diary.json",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        default=False,
        help="Overwrite output file if it already exists",
    )
    args = parser.parse_args(argv)

    try:
        migrate_markdown_to_json(args.config, args.output, overwrite=args.overwrite)
        return 0
    except FileExistsError as exc:
        logger.error(str(exc))
        return 1
    except Exception as exc:
        logger.exception(f"Migration failed: {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
