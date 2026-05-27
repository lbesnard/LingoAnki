"""Tests for lingodiary/diary_json.py.

Covers pure logic only — no I/O mocking needed except for save/load round-trips
which use a real temp file (stdlib tempfile).
"""

import json
import os
import tempfile
from datetime import datetime, timezone

import pytest

from lingodiary.diary_json import (
    DiaryDay,
    Sentence,
    DiaryJson,
    VariantSet,
    ReviewingState,
    SentenceBlock,
    apply_sm2,
    get_day,
    get_entry,
    load_diary_json,
    save_diary_json,
    upsert_day,
)


# ── Fixtures ───────────────────────────────────────────────────────────────────


def _make_entry(index: int = 0, study_sentence: str = "Test sentence") -> Sentence:
    return Sentence(
        index=index,
        input_language_sentence="Test input",
        output_language_translation=study_sentence,
        lessons=VariantSet(reviewing=ReviewingState()),
    )


def _make_diary(*date_strs: str) -> DiaryJson:
    diary = DiaryJson()
    for date_str in date_strs:
        diary.diaries.append(
            DiaryDay(date=date_str, title="", entries=[_make_entry(0)])
        )
    return diary


# ── apply_sm2 ─────────────────────────────────────────────────────────────────


class TestApplySm2:
    def test_score_0_resets_interval(self):
        r = ReviewingState(interval_days=10, status="learning")
        apply_sm2(r, 0)
        assert r.interval_days == 1
        assert r.status == "learning"

    def test_score_2_hard_multiplies(self):
        r = ReviewingState(interval_days=5)
        apply_sm2(r, 2)
        assert r.interval_days == 6  # round(5 * 1.2) == 6
        assert r.status == "learning"

    def test_score_2_hard_minimum_is_1(self):
        r = ReviewingState(interval_days=1)
        apply_sm2(r, 2)
        assert r.interval_days >= 1

    def test_score_3_good_first_review_gives_3(self):
        r = ReviewingState(interval_days=1)
        apply_sm2(r, 3)
        assert r.interval_days == 3
        assert r.status == "learning"

    def test_score_3_good_subsequent_multiplies(self):
        r = ReviewingState(interval_days=4)
        apply_sm2(r, 3)
        assert r.interval_days == 10  # round(4 * 2.5) == 10

    def test_score_5_easy_first_review_gives_7(self):
        r = ReviewingState(interval_days=1)
        apply_sm2(r, 5)
        assert r.interval_days == 7
        assert r.status == "learning"  # review_count==1 < 2

    def test_score_5_easy_second_review_masters(self):
        r = ReviewingState(interval_days=7, review_count=1)
        apply_sm2(r, 5)
        assert r.status == "mastered"  # review_count becomes 2

    def test_score_5_easy_subsequent_multiplies(self):
        r = ReviewingState(interval_days=7, review_count=1)
        apply_sm2(r, 5)
        assert r.interval_days == 28  # round(7 * 4.0)

    def test_review_count_increments(self):
        r = ReviewingState(review_count=3)
        apply_sm2(r, 3)
        assert r.review_count == 4

    def test_last_reviewed_and_next_review_are_set(self):
        r = ReviewingState()
        before = datetime.now(timezone.utc)
        apply_sm2(r, 3)
        assert r.last_reviewed is not None
        assert r.next_review is not None
        # next_review should be in the future
        next_dt = datetime.fromisoformat(r.next_review)
        assert next_dt > before

    def test_mastery_score_is_recorded(self):
        r = ReviewingState()
        apply_sm2(r, 5)
        assert r.mastery_score == 5

    def test_invalid_score_1_raises(self):
        with pytest.raises(ValueError, match="Invalid SM-2 score"):
            apply_sm2(ReviewingState(), 1)

    def test_invalid_score_4_raises(self):
        with pytest.raises(ValueError, match="Invalid SM-2 score"):
            apply_sm2(ReviewingState(), 4)

    def test_invalid_score_negative_raises(self):
        with pytest.raises(ValueError):
            apply_sm2(ReviewingState(), -1)

    def test_invalid_score_6_raises(self):
        with pytest.raises(ValueError):
            apply_sm2(ReviewingState(), 6)


# ── upsert_day ────────────────────────────────────────────────────────────────


class TestUpsertDay:
    def test_new_day_is_appended(self):
        diary = _make_diary()
        new_entries = [_make_entry(0, "New sentence")]
        upsert_day(diary, "2025/01/01", "My Title", new_entries)
        day = get_day(diary, "2025/01/01")
        assert day is not None
        assert day.title == "My Title"
        assert day.entries[0].output_language_translation == "New sentence"

    def test_new_day_diary_is_sorted_desc(self):
        diary = _make_diary("2025/06/01")
        upsert_day(diary, "2025/01/01", "", [_make_entry()])
        dates = [d.date for d in diary.diaries]
        assert dates == sorted(dates, reverse=True)

    def test_existing_day_title_updated(self):
        diary = _make_diary("2025/06/01")
        upsert_day(diary, "2025/06/01", "New Title", [_make_entry()])
        assert get_day(diary, "2025/06/01").title == "New Title"

    def test_existing_day_srs_state_preserved(self):
        diary = _make_diary("2025/06/01")
        old_entry = diary.diaries[0].entries[0]
        old_entry.lessons.reviewing.status = "mastered"
        old_entry.lessons.reviewing.interval_days = 42
        old_entry.lessons.reviewing.review_count = 5

        new_entry = _make_entry(0, "Updated sentence")
        upsert_day(diary, "2025/06/01", "", [new_entry])

        saved = get_entry(diary, "2025/06/01", 0)
        assert saved.lessons.reviewing.status == "mastered"
        assert saved.lessons.reviewing.interval_days == 42
        assert saved.lessons.reviewing.review_count == 5

    def test_existing_day_variant_qa_preserved(self):
        diary = _make_diary("2025/06/01")
        old_entry = diary.diaries[0].entries[0]
        old_entry.lessons.original = SentenceBlock(sentence="Original variant")

        new_entry = _make_entry(0, "Updated sentence")
        upsert_day(diary, "2025/06/01", "", [new_entry])

        saved = get_entry(diary, "2025/06/01", 0)
        assert saved.lessons.original.sentence == "Original variant"

    def test_empty_title_does_not_overwrite_existing(self):
        diary = _make_diary("2025/06/01")
        diary.diaries[0].title = "Existing Title"
        upsert_day(diary, "2025/06/01", "", [_make_entry()])
        assert get_day(diary, "2025/06/01").title == "Existing Title"

    def test_returns_diary(self):
        diary = _make_diary()
        result = upsert_day(diary, "2025/01/01", "", [_make_entry()])
        assert result is diary


# ── save / load round-trip ────────────────────────────────────────────────────


class TestSaveDiaryJson:
    def test_round_trip_preserves_data(self, tmp_path):
        path = str(tmp_path / "diary.json")
        diary = _make_diary("2025/06/01")
        diary.diaries[0].title = "Round-trip test"
        diary.diaries[0].entries[0].output_language_translation = "Test sentence"

        save_diary_json(diary, path)
        loaded = load_diary_json(path)

        assert loaded.diaries[0].title == "Round-trip test"
        assert (
            loaded.diaries[0].entries[0].output_language_translation == "Test sentence"
        )

    def test_atomic_write_file_exists_after_save(self, tmp_path):
        path = tmp_path / "diary.json"
        save_diary_json(_make_diary("2025/01/01"), str(path))
        assert path.exists()

    def test_atomic_write_no_temp_file_left_behind(self, tmp_path):
        save_diary_json(_make_diary("2025/01/01"), str(tmp_path / "diary.json"))
        tmp_files = list(tmp_path.glob("*.tmp"))
        assert tmp_files == [], f"Leftover tmp files: {tmp_files}"

    def test_written_file_is_valid_json(self, tmp_path):
        path = tmp_path / "diary.json"
        save_diary_json(_make_diary("2025/01/01"), str(path))
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        assert "diaries" in data

    def test_load_missing_file_returns_empty_diary(self, tmp_path):
        """load_diary_json silently bootstraps an empty diary when file is absent."""
        result = load_diary_json(str(tmp_path / "nonexistent.json"))
        assert isinstance(result, DiaryJson)
        assert result.diaries == []

    def test_srs_state_survives_round_trip(self, tmp_path):
        path = str(tmp_path / "diary.json")
        diary = _make_diary("2025/06/01")
        r = diary.diaries[0].entries[0].lessons.reviewing
        r.status = "mastered"
        r.interval_days = 14
        r.review_count = 3

        save_diary_json(diary, path)
        loaded = load_diary_json(path)

        r2 = loaded.diaries[0].entries[0].lessons.reviewing
        assert r2.status == "mastered"
        assert r2.interval_days == 14
        assert r2.review_count == 3
