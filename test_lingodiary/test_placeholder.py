"""Placeholder tests — ensures pytest always collects at least one test."""


def test_import_diary_json():
    """Smoke-test: diary_json module imports without errors."""
    from lingodiary import diary_json  # noqa: F401

    assert hasattr(diary_json, "DiaryJson")


def test_import_diary():
    """Smoke-test: core diary module imports without errors."""
    import lingodiary.diary_json as dj

    d = dj.DiaryJson()
    assert d.diaries == []
