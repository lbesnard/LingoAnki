"""
audio_timing.py — Per-sentence audio timing backfill.

Generates individual TTS audio segments (sentence, questions, answers) for each
TPRS variant, measuring their exact WAV durations to build precise start/end_ms
timings, then exports each segment as MP3.

After measuring timings, the full lesson MP3 is **reassembled from those exact
segment files**.  This guarantees that the timings stored in diary.json match
the audio file the Flutter player actually loads — Piper TTS is non-deterministic,
so re-generating TTS at a later time produces slightly different durations.

Segment files are kept permanently in:
    output_dir/TPRS/SEGMENTS/{YYYY-MM-DD}_{variant}/
        {entry_idx}_s.mp3        <- sentence (single copy, pre-repeat)
        {entry_idx}_q{j}.mp3     <- question j
        {entry_idx}_a{j}.mp3     <- answer j

All paths and timings are written back into diary.json.

Audio structure (per sentence S, R = repeat_tprs):
    [S x R] + pause_ms
    per Q&A: pause_ms + [Q x R] + answer_silence_ms + [A x R] + pause_ms

Usage:
    python -m lingodiary.audio_timing \\
        --config ~/.config/lingoDiary/config.yaml \\
        --json ~/Documents/lingodiary/<user>/diary.json

    from lingodiary.audio_timing import backfill_audio_timings
    backfill_audio_timings(config_path, diary_json_path)
"""

from __future__ import annotations

import argparse
import logging
import os
from datetime import datetime, timezone
from pathlib import Path

logger = logging.getLogger(__name__)

_VARIANT_KEYS = ("original", "enhanced", "future", "present")
_KEY_TO_SUFFIX = {
    "original": "",
    "enhanced": "_enhanced",
    "future": "_future",
    "present": "_present",
}


def _generate_segment(
    text: str,
    out_path: str,
    tts_plugin,
    lang: str,
    voice: str,
) -> int:
    """
    Generate TTS for *text* -> temp WAV -> measure duration -> export as MP3 to *out_path*.

    Returns duration in ms (measured from WAV before conversion). Returns 0 on failure.
    The intermediate WAV is always deleted; only the MP3 is kept.
    """
    if not text or not text.strip():
        return 0

    tmp_wav = out_path.replace(".mp3", "_tmp.wav")
    dur_ms = 0
    try:
        from pydub import AudioSegment  # type: ignore

        tts_plugin.get_tts(text, tmp_wav, lang=lang, voice=voice)
        seg = AudioSegment.from_wav(tmp_wav)
        dur_ms = len(seg)
        seg.export(out_path, format="mp3")
        return dur_ms
    except Exception as exc:
        logger.warning(f"TTS failed for '{text[:50]}': {exc}")
        return 0
    finally:
        if os.path.exists(tmp_wav):
            try:
                os.remove(tmp_wav)
            except OSError:
                pass


def _find_day_mp3(tprs_dir: str, date_str: str, file_suffix: str) -> str | None:
    """
    Find the full-lesson MP3 for a specific day+variant, preferring audio-matched files.
    date_str is 'YYYY/MM/DD', file_suffix is '' or '_enhanced' etc.
    """
    import glob as g

    date_dash = date_str.replace("/", "-")
    if file_suffix:
        pattern = os.path.join(tprs_dir, f"*_TPRS_{date_dash}*{file_suffix}.mp3")
    else:
        pattern = os.path.join(tprs_dir, f"*_TPRS_{date_dash}*.mp3")

    candidates = sorted(g.glob(pattern))
    if not file_suffix:
        candidates = [
            c
            for c in candidates
            if not any(
                os.path.basename(c).endswith(f"{s}.mp3")
                for s in ("_enhanced", "_future", "_present")
            )
        ]
    return candidates[0] if candidates else None


def _segments_dir(output_dir: str, date_str: str, variant_key: str) -> str:
    """Return the SEGMENTS subdirectory path for a given day/variant."""
    date_dash = date_str.replace("/", "-")
    return os.path.join(output_dir, "TPRS", "SEGMENTS", f"{date_dash}_{variant_key}")


def _segments_complete(segs_dir: str, entries: list, variant_key: str) -> bool:
    """Return True if all expected MP3 segment files already exist."""
    for idx, entry in enumerate(entries):
        variant = entry.lessons.get_variant(variant_key)
        if not variant.sentence:
            continue
        if not os.path.exists(os.path.join(segs_dir, f"{idx}_s.mp3")):
            return False
        for j in range(len(variant.qa)):
            if not os.path.exists(os.path.join(segs_dir, f"{idx}_q{j}.mp3")):
                return False
            if not os.path.exists(os.path.join(segs_dir, f"{idx}_a{j}.mp3")):
                return False
    return True


def _assemble_full_mp3(
    entries: list,
    variant_key: str,
    segs_dir: str,
    repeat_tprs: int,
    pause_ms: int,
    answer_silence_ms: int,
    output_mp3_path: str,
) -> bool:
    """
    Reassemble the full lesson MP3 from individual segment files.

    This guarantees that the timings stored in diary.json (measured from these
    exact segment files) precisely match the rebuilt MP3.  Must be called after
    _compute_day_timings() or when segments are already confirmed complete.

    Structure (mirrors _create_audio_for_day_block):
        per entry:  s × R  +  silent(pause_ms)
        per Q&A:    silent(pause_ms)  +  q × R  +  silent(answer_silence_ms)
                    +  a × R  +  silent(pause_ms)

    Returns True if the MP3 was written, False if no usable segments were found.
    """
    from pydub import AudioSegment  # type: ignore

    R = max(1, repeat_tprs)
    pause_seg = AudioSegment.silent(duration=pause_ms)
    silence_seg = AudioSegment.silent(duration=answer_silence_ms)
    combined = AudioSegment.empty()
    has_any = False

    for idx, entry in enumerate(entries):
        variant = entry.lessons.get_variant(variant_key)
        if not variant.sentence:
            continue

        s_path = os.path.join(segs_dir, f"{idx}_s.mp3")
        if not os.path.exists(s_path):
            logger.warning(f"  Segment missing, skipping entry {idx}: {s_path}")
            continue

        has_any = True
        s_seg = AudioSegment.from_mp3(s_path)
        for _ in range(R):
            combined += s_seg
        combined += pause_seg

        for j, qa in enumerate(variant.qa):
            q_path = os.path.join(segs_dir, f"{idx}_q{j}.mp3")
            a_path = os.path.join(segs_dir, f"{idx}_a{j}.mp3")
            if not os.path.exists(q_path) or not os.path.exists(a_path):
                logger.warning(
                    f"  Q/A segment missing for entry {idx} qa {j}, skipping Q&A block"
                )
                continue
            q_seg = AudioSegment.from_mp3(q_path)
            a_seg = AudioSegment.from_mp3(a_path)
            combined += pause_seg
            for _ in range(R):
                combined += q_seg
            combined += silence_seg
            for _ in range(R):
                combined += a_seg
            combined += pause_seg

    if not has_any:
        return False

    os.makedirs(os.path.dirname(output_mp3_path), exist_ok=True)
    combined.export(output_mp3_path, format="mp3")
    logger.info(
        f"  Rebuilt full MP3 from segments: {os.path.basename(output_mp3_path)} "
        f"({len(combined) // 1000}s)"
    )
    return True


def _mp3_stale(day, variant_key: str) -> bool:
    """Return True if the full lesson MP3 is stale relative to its Q&A segments.

    Uses the user's rule: if any qa.generated_at is None OR mp3_ts is None OR
    any qa.generated_at > mp3_ts → the MP3 needs rebuilding.

    This function is the authority on staleness once both sides have timestamps.
    Before the backfill script is run, lesson_mp3_timestamps is empty for all
    historical entries, so this returns False and the existing
    ``segments_newly_generated`` flag remains the primary rebuild trigger.
    """
    mp3_ts_str = day.lesson_mp3_timestamps.get(variant_key)
    if mp3_ts_str is None:
        # No MP3 timestamp — can't evaluate; let segments_newly_generated handle it
        return False

    mp3_ts = datetime.fromisoformat(mp3_ts_str)

    for entry in day.entries:
        v = entry.lessons.get_variant(variant_key)
        for qa in v.qa:
            if qa.generated_at is None:
                # Q&A has no timestamp — treat as stale (either not yet generated
                # or pre-backfill data; the latter should not exist after backfill)
                return True
            if datetime.fromisoformat(qa.generated_at) > mp3_ts:
                return True

    return False


def _compute_day_timings(
    entries: list,
    variant_key: str,
    tts_plugin,
    lang: str,
    voice: str,
    repeat_tprs: int,
    pause_ms: int,
    answer_silence_ms: int,
    output_dir: str,
    date_str: str,
) -> list[tuple[int, int]]:
    """
    Generate individual MP3 segments for each sentence/Q/A, measure exact durations,
    store files in TPRS/SEGMENTS/{date}_{variant}/, update audio paths in entries.

    Returns list of (start_ms, end_ms) per entry for the sentence block start/end.
    Q&A timings are stored directly onto each QA object.
    """
    from lingodiary.diary_json import AudioTiming  # type: ignore

    R = max(1, repeat_tprs)
    segs_dir = _segments_dir(output_dir, date_str, variant_key)
    os.makedirs(segs_dir, exist_ok=True)

    cumulative = 0
    timings: list[tuple[int, int]] = []
    has_any = False

    for idx, entry in enumerate(entries):
        variant = entry.lessons.get_variant(variant_key)
        if not variant.sentence:
            timings.append((cumulative, cumulative))
            continue

        has_any = True

        # -- Sentence ------------------------------------------------------
        entry_start = cumulative
        s_path = os.path.join(segs_dir, f"{idx}_s.mp3")
        s_dur = _generate_segment(variant.sentence, s_path, tts_plugin, lang, voice)
        entry_end = int(entry_start + s_dur * R)
        timings.append((int(entry_start), entry_end))
        variant.sentence_audio_path = os.path.relpath(s_path, output_dir)

        # Advance past sentence + its trailing pause
        cumulative = entry_end + pause_ms

        # -- Q&A pairs -----------------------------------------------------
        for j, qa in enumerate(variant.qa):
            cumulative += pause_ms  # pause before question

            q_path = os.path.join(segs_dir, f"{idx}_q{j}.mp3")
            q_start = int(cumulative)
            q_dur = _generate_segment(qa.question, q_path, tts_plugin, lang, voice)
            cumulative = int(cumulative + q_dur * R)
            qa.question_timing = AudioTiming(start_ms=q_start, end_ms=cumulative)
            qa.question_audio_path = os.path.relpath(q_path, output_dir)

            cumulative += answer_silence_ms  # silence for user to answer

            a_path = os.path.join(segs_dir, f"{idx}_a{j}.mp3")
            a_start = int(cumulative)
            a_dur = _generate_segment(qa.answer, a_path, tts_plugin, lang, voice)
            cumulative = int(cumulative + a_dur * R)
            qa.answer_timing = AudioTiming(start_ms=a_start, end_ms=cumulative)
            qa.answer_audio_path = os.path.relpath(a_path, output_dir)

            qa.generated_at = datetime.now(timezone.utc).isoformat()

            cumulative += pause_ms  # pause after answer

    if not has_any:
        return []

    return timings


def backfill_audio_timings(
    config_path: str | Path,
    diary_json_path: str | Path,
    variants: list[str] | None = None,
    overwrite_existing: bool = False,
) -> None:
    """
    Generate individual segment MP3s and store per-sentence audio timings for
    all TPRS variant lessons.

    Args:
        config_path:         Path to the user's config.yaml.
        diary_json_path:     Path to diary.json (updated in-place, saved per day).
        variants:            Variant keys to process. Defaults to all four.
        overwrite_existing:  If False (default), skip days where segment files
                             are already complete.
    """
    import yaml  # type: ignore
    from ovos_tts_plugin_piper import PiperTTSPlugin  # type: ignore

    from lingodiary.diary_json import AudioTiming, load_diary_json, save_diary_json

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
    output_dir = config.get("output_dir", "")
    tprs_dir = os.path.join(output_dir, "TPRS")

    logger.info(
        f"Config: voice={voice}, length_scale={length_scale}, "
        f"repeat={repeat_tprs}, pause={pause_ms}ms, silence={answer_silence_ms}ms"
    )

    tts_plugin = PiperTTSPlugin()
    tts_plugin.length_scale = length_scale

    diary = load_diary_json(diary_json_path)
    total_days = len(diary.diaries)
    logger.info(f"Processing {total_days} diary days...")

    try:
        for day_idx, day in enumerate(diary.diaries, 1):
            logger.info(f"Day {day_idx}/{total_days}: {day.date} -- {day.title}")
            day_modified = False

            # Fill lesson_audio_paths for this day
            for variant_key in variants:
                suffix = _KEY_TO_SUFFIX.get(variant_key, "")
                mp3_path = _find_day_mp3(tprs_dir, day.date, suffix)
                if mp3_path and variant_key not in day.lesson_audio_paths:
                    day.lesson_audio_paths[variant_key] = os.path.relpath(
                        mp3_path, output_dir
                    )
                    day_modified = True

            for variant_key in variants:
                populated = [
                    e
                    for e in day.entries
                    if e.lessons.get_variant(variant_key).sentence
                ]
                if not populated:
                    logger.debug(f"  {variant_key}: no entries, skipping.")
                    continue

                segs_dir = _segments_dir(output_dir, day.date, variant_key)

                segments_newly_generated = False
                if not overwrite_existing and _segments_complete(
                    segs_dir, day.entries, variant_key
                ):
                    logger.info(
                        f"  {variant_key}: segments already complete, skipping TTS."
                    )
                    # Fill paths if they're missing from the JSON
                    for idx, entry in enumerate(day.entries):
                        v = entry.lessons.get_variant(variant_key)
                        if not v.sentence:
                            continue
                        s_path = os.path.join(segs_dir, f"{idx}_s.mp3")
                        if v.sentence_audio_path == "" and os.path.exists(s_path):
                            v.sentence_audio_path = os.path.relpath(s_path, output_dir)
                            day_modified = True
                        for j, qa in enumerate(v.qa):
                            q_path = os.path.join(segs_dir, f"{idx}_q{j}.mp3")
                            a_path = os.path.join(segs_dir, f"{idx}_a{j}.mp3")
                            if qa.question_audio_path == "" and os.path.exists(q_path):
                                qa.question_audio_path = os.path.relpath(
                                    q_path, output_dir
                                )
                                day_modified = True
                            if qa.answer_audio_path == "" and os.path.exists(a_path):
                                qa.answer_audio_path = os.path.relpath(
                                    a_path, output_dir
                                )
                                day_modified = True
                else:
                    logger.info(
                        f"  {variant_key}: generating segments for {len(populated)} entries "
                        f"(repeat x{repeat_tprs})..."
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
                        output_dir=output_dir,
                        date_str=day.date,
                    )
                    if not timings:
                        continue

                    for entry, (start_ms, end_ms) in zip(day.entries, timings):
                        v = entry.lessons.get_variant(variant_key)
                        if v.sentence:
                            v.audio_timing = AudioTiming(
                                start_ms=start_ms, end_ms=end_ms
                            )
                            day_modified = True

                    logger.info(
                        f"  {variant_key}: done. Last end_ms={timings[-1][1]}ms "
                        f"(~{timings[-1][1]//1000}s)"
                    )
                    segments_newly_generated = True

                # Rebuild the full MP3 from segment files only when needed:
                # - segments were newly generated (timing must stay in sync), OR
                # - the MP3 file is missing (segments exist but the MP3 was lost), OR
                # - Q&A segments are newer than the full MP3 (stale MP3 detection)
                mp3_rel = day.lesson_audio_paths.get(variant_key, "")
                mp3_path = os.path.join(output_dir, mp3_rel) if mp3_rel else None
                if mp3_path and (
                    segments_newly_generated
                    or not os.path.exists(mp3_path)
                    or _mp3_stale(day, variant_key)
                ):
                    rebuilt = _assemble_full_mp3(
                        day.entries,
                        variant_key,
                        segs_dir,
                        repeat_tprs,
                        pause_ms,
                        answer_silence_ms,
                        mp3_path,
                    )
                    if rebuilt:
                        day_modified = True
                        day.lesson_mp3_timestamps[variant_key] = datetime.now(
                            timezone.utc
                        ).isoformat()
                        logger.info(f"  {variant_key}: rebuilt MP3 at {mp3_path}.")
                else:
                    logger.debug(f"  {variant_key}: MP3 up-to-date, skipping rebuild.")

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
        description="Backfill per-sentence audio timings and segment MP3s into diary.json"
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
        help="Overwrite existing segment files and timings",
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
