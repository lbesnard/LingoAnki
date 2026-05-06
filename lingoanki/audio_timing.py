"""
audio_timing.py — Per-sentence audio timing backfill.

Re-generates TTS audio for each sentence (and its Q&A) in memory using the
same parameters as the real TPRS audio generation, measures durations, then
stores start_ms/end_ms per entry per variant into diary.json.

The audio file structure per sentence mirrors _create_audio_for_day_block():

    For each sentence S with Q&A pairs [(Q1,A1), (Q2,A2), ...]:
        [S  × repeat_tprs] + [pause × repeat_tprs]
        + [pause × repeat_tprs] + [Q1 × repeat_tprs] + [silence × repeat_tprs]
        + [A1 × repeat_tprs] + [pause × repeat_tprs]
        + [pause × repeat_tprs] + [Q2 × repeat_tprs] + ...

    Since actual_pause_duration = config_pause / repeat_tprs, repeating it
    repeat_tprs times gives exactly config_pause ms of silence.
    Same logic for answer_silence_duration.

So:
    entry_start_ms = cumulative offset up to that sentence
    entry_end_ms   = entry_start_ms + (sentence_tts_ms * repeat_tprs)

JSON is saved after each day so progress is not lost if the script is interrupted.

Usage:
    python -m lingoanki.audio_timing \\
        --config ~/.config/lingoDiary/config.yaml \\
        --json ~/Documents/lingodiary/<user>/diary.json

    from lingoanki.audio_timing import backfill_audio_timings
    backfill_audio_timings(config_path, diary_json_path)
"""

from __future__ import annotations

import argparse
import logging
import os
import tempfile
from pathlib import Path

logger = logging.getLogger(__name__)

_VARIANT_KEYS = ("original", "enhanced", "future", "present")


def _tts_duration_ms(
    text: str,
    tts_plugin,
    lang: str,
    voice: str,
) -> int:
    """Generate TTS for *text*, measure duration in ms, delete temp file. Returns 0 on failure."""
    if not text or not text.strip():
        return 0
    tmp_path = os.path.join(
        tempfile.gettempdir(), f"_timing_{abs(hash(text)) % 10**9}.wav"
    )
    try:
        from pydub import AudioSegment  # type: ignore

        tts_plugin.get_tts(text, tmp_path, lang=lang, voice=voice)
        seg = AudioSegment.from_wav(tmp_path)
        return len(seg)
    except Exception as exc:
        logger.warning(f"TTS failed for '{text[:50]}': {exc}")
        return 0
    finally:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass


def _compute_day_timings(
    entries: list,
    variant_key: str,
    tts_plugin,
    lang: str,
    voice: str,
    repeat_tprs: int,
    pause_ms: int,
    answer_silence_ms: int,
) -> list[tuple[int, int]]:
    """
    Compute (start_ms, end_ms) for each entry's sentence in the audio file.

    Mirrors the exact segment order in _create_audio_for_day_block():
      [sentence * R] + [pause * R]
      + per Q&A: [pause * R] + [question * R] + [silence * R] + [answer * R] + [pause * R]

    Since actual_pause = pause_ms/R repeated R times = pause_ms total,
    we just add pause_ms and answer_silence_ms directly (no TTS needed for pauses).

    Returns list of (start_ms, end_ms) per entry, or [] if variant has no data.
    Q&A timings are stored directly onto each QA object (question_timing/answer_timing).
    """
    R = max(1, repeat_tprs)
    cumulative = 0
    timings: list[tuple[int, int]] = []
    has_any = False

    for entry in entries:
        variant = entry.lessons.get_variant(variant_key)
        if not variant.sentence:
            timings.append((cumulative, cumulative))
            continue

        has_any = True

        # ── Sentence ──────────────────────────────────────────────────────
        entry_start = cumulative
        s_dur = _tts_duration_ms(variant.sentence, tts_plugin, lang, voice)
        entry_end = entry_start + s_dur * R
        timings.append((entry_start, entry_end))

        # Advance cursor past sentence + its pause
        cumulative = entry_end + pause_ms

        # ── Q&A pairs — compute and store individual timings ──────────────
        for qa in variant.qa:
            from lingoanki.diary_json import AudioTiming  # type: ignore

            cumulative += pause_ms  # pause before question
            q_start = cumulative
            q_dur = _tts_duration_ms(qa.question, tts_plugin, lang, voice)
            cumulative += q_dur * R
            qa.question_timing = AudioTiming(start_ms=q_start, end_ms=cumulative)

            cumulative += answer_silence_ms  # silence for user to answer
            a_start = cumulative
            a_dur = _tts_duration_ms(qa.answer, tts_plugin, lang, voice)
            cumulative += a_dur * R
            qa.answer_timing = AudioTiming(start_ms=a_start, end_ms=cumulative)

            cumulative += pause_ms  # pause after answer

    return timings if has_any else []


def backfill_audio_timings(
    config_path: str | Path,
    diary_json_path: str | Path,
    variants: list[str] | None = None,
    overwrite_existing: bool = False,
) -> None:
    """
    Compute and store per-sentence audio timings for all TPRS variant lessons.

    Args:
        config_path:         Path to the user's config.yaml.
        diary_json_path:     Path to diary.json (updated in-place, saved per day).
        variants:            Variant keys to process. Defaults to all four.
        overwrite_existing:  If False (default), skip entries that already have
                             non-zero timings.
    """
    import yaml  # type: ignore
    from ovos_tts_plugin_piper import PiperTTSPlugin  # type: ignore

    from lingoanki.diary_json import AudioTiming, load_diary_json, save_diary_json

    variants = variants or list(_VARIANT_KEYS)
    diary_json_path = Path(diary_json_path)

    if not diary_json_path.exists():
        logger.error(f"diary.json not found at {diary_json_path}")
        return

    with open(config_path, encoding="utf-8") as f:
        config = yaml.safe_load(f)

    tts_cfg = config.get("tts", {})
    piper_cfg = tts_cfg.get("piper", {})
    lang = config["languages"]["study_language_code"]
    voice = piper_cfg["voice"]
    length_scale = piper_cfg.get("piper_length_scale_tprs", 1.0)
    repeat_tprs = max(1, tts_cfg.get("repeat_sentence_tprs", 1) or 1)
    pause_ms = int(tts_cfg.get("pause_between_sentences_duration", 500))
    answer_silence_ms = int(tts_cfg.get("answer_silence_duration", 3000))

    logger.info(
        f"Config: voice={voice}, length_scale={length_scale}, "
        f"repeat={repeat_tprs}, pause={pause_ms}ms, silence={answer_silence_ms}ms"
    )

    tts_plugin = PiperTTSPlugin()
    tts_plugin.length_scale = length_scale

    diary = load_diary_json(diary_json_path)
    total_days = len(diary.diaries)
    logger.info(f"Processing {total_days} diary days…")

    try:
        for day_idx, day in enumerate(diary.diaries, 1):
            logger.info(f"Day {day_idx}/{total_days}: {day.date} — {day.title}")
            day_modified = False

            for variant_key in variants:
                populated = [
                    e
                    for e in day.entries
                    if e.lessons.get_variant(variant_key).sentence
                ]
                if not populated:
                    logger.debug(f"  {variant_key}: no entries, skipping.")
                    continue

                if not overwrite_existing:
                    already_done = all(
                        e.lessons.get_variant(variant_key).audio_timing.end_ms > 0
                        for e in populated
                    )
                    if already_done:
                        logger.info(f"  {variant_key}: already timed, skipping.")
                        continue

                logger.info(
                    f"  {variant_key}: timing {len(populated)} entries "
                    f"(repeat×{repeat_tprs})…"
                )
                timings = _compute_day_timings(
                    day.entries,
                    variant_key,
                    tts_plugin,
                    lang,
                    voice,
                    repeat_tprs,
                    pause_ms,
                    answer_silence_ms,
                )
                if not timings:
                    continue

                for entry, (start_ms, end_ms) in zip(day.entries, timings):
                    v = entry.lessons.get_variant(variant_key)
                    if v.sentence:
                        v.audio_timing = AudioTiming(start_ms=start_ms, end_ms=end_ms)
                        day_modified = True

                if timings:
                    logger.info(
                        f"  {variant_key}: done. Last end_ms={timings[-1][1]}ms "
                        f"(~{timings[-1][1]//1000}s)"
                    )

            # Save after each day so progress is not lost on interruption
            if day_modified:
                save_diary_json(diary, diary_json_path)
                logger.info(f"  Saved progress for {day.date}.")

    finally:
        try:
            tts_plugin.stop()
        except Exception:
            pass

    logger.info(f"Audio timing backfill complete: {diary_json_path}")


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
        "--config", required=True, metavar="PATH", help="Path to user config.yaml"
    )
    parser.add_argument(
        "--json", required=True, metavar="PATH", help="Path to diary.json"
    )
    parser.add_argument(
        "--variants",
        nargs="+",
        metavar="VARIANT",
        default=None,
        help=f"Variants to process (default: all). Choices: {_VARIANT_KEYS}",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        default=False,
        help="Overwrite existing timings",
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
