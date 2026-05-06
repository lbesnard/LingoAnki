"""
audio_timing.py — Per-sentence audio timing backfill.

Re-generates TTS audio for each sentence (and its Q&A) in memory, measures
durations using pydub, then stores start_ms/end_ms per entry per variant into
diary.json.  No permanent extra files are created.

Usage:
    python -m lingoanki.audio_timing \\
        --config ~/.config/lingoDiary/config.yaml \\
        --json ~/Documents/lingodiary/<user>/diary.json

    # Or call programmatically:
    from lingoanki.audio_timing import backfill_audio_timings
    backfill_audio_timings(config_path, diary_json_path, variants=None)
"""

from __future__ import annotations

import argparse
import logging
import os
import tempfile
from pathlib import Path

logger = logging.getLogger(__name__)

_VARIANT_KEYS = ("original", "enhanced", "future", "present")


def _get_audio_duration_ms(text: str, config: dict, tts_model: str) -> int:
    """
    Generate TTS for `text` into a temp file, measure duration in ms, delete file.

    Returns 0 if TTS fails or text is empty.
    """
    if not text or not text.strip():
        return 0

    tmp_path = None
    try:
        from pydub import AudioSegment  # type: ignore

        if tts_model == "gtts":
            from gtts import gTTS  # type: ignore

            tts = gTTS(
                text=text,
                lang=config["languages"]["study_language_code"],
            )
            tmp_path = os.path.join(
                tempfile.gettempdir(), f"_timing_{abs(hash(text))}.mp3"
            )
            tts.save(tmp_path)
            seg = AudioSegment.from_mp3(tmp_path)

        elif tts_model == "piper":
            from ovos_plugin_manager.tts import load_tts_plugin  # type: ignore

            piper_cfg = config["tts"]["piper"]
            TTSClass = load_tts_plugin("ovos-tts-plugin-piper")
            tts = TTSClass(
                config={
                    "module": "ovos-tts-plugin-piper",
                    "ovos-tts-plugin-piper": {"voice": piper_cfg["voice"]},
                }
            )
            tts.length_scale = piper_cfg.get("piper_length_scale_diary", 1.0)
            tmp_path = os.path.join(
                tempfile.gettempdir(), f"_timing_{abs(hash(text))}.wav"
            )
            tts.get_tts(
                text,
                tmp_path,
                lang=config["languages"]["study_language_code"],
                voice=piper_cfg["voice"],
            )
            seg = AudioSegment.from_wav(tmp_path)

        elif tts_model == "melo":
            from ovos_plugin_manager.tts import load_tts_plugin  # type: ignore

            melo_cfg = config["tts"]["melo"]
            TTSClass = load_tts_plugin(melo_cfg["module"])
            tts = TTSClass(config=melo_cfg)
            tmp_path = os.path.join(
                tempfile.gettempdir(), f"_timing_{abs(hash(text))}.wav"
            )
            tts.tts_to_file(
                text=text,
                filename=tmp_path,
                speaker_ids=melo_cfg["speaker_ids"],
                speed=melo_cfg["speed"],
            )
            seg = AudioSegment.from_wav(tmp_path)

        else:
            logger.warning(
                f"TTS model '{tts_model}' not supported for timing; skipping."
            )
            return 0

        return len(seg)

    except Exception as exc:
        logger.warning(f"TTS duration failed for text '{text[:40]}': {exc}")
        return 0
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass


def _measure_variant_timings(
    entries: list,
    variant_key: str,
    config: dict,
    tts_model: str,
) -> list[tuple[int, int]]:
    """
    Compute (start_ms, end_ms) for each entry's sentence in the given variant.

    The cumulative offset accounts for sentence + all Q&A segments that come
    before each entry, mirroring the structure of the real TTS audio file.

    Returns a list of (start_ms, end_ms) tuples, one per entry, or an empty
    list if the variant has no data.
    """
    cumulative_ms = 0
    timings: list[tuple[int, int]] = []
    has_any = False

    for entry in entries:
        variant = entry.lessons.get_variant(variant_key)
        if not variant.sentence:
            timings.append((cumulative_ms, cumulative_ms))
            continue

        has_any = True
        entry_start = cumulative_ms

        # Measure the sentence itself
        sentence_dur = _get_audio_duration_ms(variant.sentence, config, tts_model)
        entry_end = entry_start + sentence_dur
        timings.append((entry_start, entry_end))

        # Advance cursor past sentence + all Q&A for this entry
        cumulative_ms = entry_end
        for qa in variant.qa:
            cumulative_ms += _get_audio_duration_ms(qa.question, config, tts_model)
            cumulative_ms += _get_audio_duration_ms(qa.answer, config, tts_model)

    return timings if has_any else []


def backfill_audio_timings(
    config_path: str | Path,
    diary_json_path: str | Path,
    variants: list[str] | None = None,
    overwrite_existing: bool = False,
) -> None:
    """
    Compute and store per-sentence audio timings for all variant lessons.

    For each diary day and each requested variant, generates TTS for every
    sentence (and Q&A), measures duration with pydub, and stores
    ``audio_timing.start_ms`` / ``audio_timing.end_ms`` into diary.json.

    Args:
        config_path:         Path to the user's config.yaml.
        diary_json_path:     Path to diary.json (will be updated in-place).
        variants:            Variant keys to process.  Defaults to all four:
                             ``["original", "enhanced", "future", "present"]``.
        overwrite_existing:  If False (default), skip entries that already have
                             non-zero audio timings.
    """
    import yaml  # type: ignore

    from lingoanki.diary_json import AudioTiming, load_diary_json, save_diary_json

    variants = variants or list(_VARIANT_KEYS)
    diary_json_path = Path(diary_json_path)

    if not diary_json_path.exists():
        logger.error(f"diary.json not found at {diary_json_path}")
        return

    with open(config_path, encoding="utf-8") as f:
        config = yaml.safe_load(f)

    tts_model = config.get("tts", {}).get("model", "piper")
    logger.info(f"TTS model: {tts_model}")

    diary = load_diary_json(diary_json_path)
    total_days = len(diary.diaries)
    logger.info(f"Processing {total_days} diary days…")

    for day_idx, day in enumerate(diary.diaries, 1):
        logger.info(f"Day {day_idx}/{total_days}: {day.date} — {day.title}")

        for variant_key in variants:
            # Check if already populated (variant has content when sentence != "")
            populated_entries = [
                entry
                for entry in day.entries
                if entry.lessons.get_variant(variant_key).sentence
            ]
            if not overwrite_existing:
                already_done = all(
                    entry.lessons.get_variant(variant_key).audio_timing.end_ms > 0
                    for entry in populated_entries
                )
                if already_done and populated_entries:
                    logger.debug(f"  {variant_key}: already timed, skipping.")
                    continue

            timings = _measure_variant_timings(
                day.entries, variant_key, config, tts_model
            )
            if not timings:
                logger.debug(f"  {variant_key}: no entries, skipping.")
                continue

            for entry, (start_ms, end_ms) in zip(day.entries, timings):
                variant = entry.lessons.get_variant(variant_key)
                if variant.sentence:
                    variant.audio_timing = AudioTiming(start_ms=start_ms, end_ms=end_ms)

            logger.info(
                f"  {variant_key}: timed {len(timings)} sentences "
                f"(last end_ms={timings[-1][1]}ms)"
            )

    save_diary_json(diary, diary_json_path)
    logger.info(f"Audio timings saved to {diary_json_path}")


def _setup_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s  %(levelname)-8s  %(message)s",
        datefmt="%H:%M:%S",
    )


def main(argv: list[str] | None = None) -> int:
    _setup_logging()
    parser = argparse.ArgumentParser(
        description="Backfill per-sentence audio timings into diary.json"
    )
    parser.add_argument(
        "--config",
        required=True,
        metavar="PATH",
        help="Path to the user's config.yaml",
    )
    parser.add_argument(
        "--json",
        required=True,
        metavar="PATH",
        help="Path to diary.json",
    )
    parser.add_argument(
        "--variants",
        nargs="+",
        metavar="VARIANT",
        default=None,
        help=f"Variant keys to process (default: all). Choices: {_VARIANT_KEYS}",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        default=False,
        help="Overwrite existing timings (default: skip already timed entries)",
    )
    args = parser.parse_args(argv)

    try:
        backfill_audio_timings(
            config_path=args.config,
            diary_json_path=args.json,
            variants=args.variants,
            overwrite_existing=args.overwrite,
        )
        return 0
    except Exception as exc:
        logger.exception(f"Audio timing backfill failed: {exc}")
        return 1


if __name__ == "__main__":
    import sys

    sys.exit(main())
