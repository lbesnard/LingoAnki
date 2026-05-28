# Lesson text synced into SQLite per-day, not via diary.json download

`diary.json` is the server's single source of truth for all lesson content. Before this decision, the Android app always bundled `diary.json` in every per-lesson sync manifest, meaning syncing a single lesson downloaded the entire file — already 10 MB at 69 days and growing ~150 KB/day.

We decided that the Android app will never download `diary.json` at all. Instead:

1. A new server endpoint `GET /api/diary/day/{date}` returns the **complete Day object** for one date — all 4 Lesson Variants, all entries including `title`, `tips`, `user_trial_translation`, reviewing state, and audio timings. Median size is ~85 KB per day.
2. The Android app caches this response in a `day_cache` SQLite table (primary key: `date`). One row per Day.
3. Per-lesson sync and Sync All populate `day_cache` by calling this endpoint for each affected day.
4. The player reads text offline from `day_cache`. When online, it refreshes the cache in the background on every lesson open — ensuring scores made on another device are reflected next time the lesson is opened.
5. `diary.json` is removed from all sync manifests.

The `day_cache` schema:
```sql
CREATE TABLE day_cache (
  date       TEXT PRIMARY KEY,  -- YYYY-MM-DD
  day_json   TEXT NOT NULL,     -- complete Day object from /api/diary/day/{date}
  fetched_at TEXT NOT NULL
)
```

## Considered options

- **Per-day JSON files on disk** (`diary/YYYY-MM-DD.json` referenced from the manifest) — rejected because it adds server-side file management and still requires manifest coordination.
- **Per-variant endpoint `getLessonEntries`** (4 calls per day) — rejected in favour of a single full-day endpoint that includes all fields and all variants at once.
- **Keep diary.json in Sync All only** — rejected because it still means re-downloading 10 MB+ on every full sync.
- **No local cache; always fetch live from API** — rejected because offline text during lesson playback is a hard requirement.

## Consequences

- `day_cache` must be populated before a lesson can be played offline. This happens automatically during `syncLesson()` or `syncAll()` (both require connectivity).
- Reviewing state inside the cached JSON is a snapshot. It is refreshed on the next lesson open when online. Scores submitted offline are queued in `srs_scores` and flushed when connectivity is restored — the server remains authoritative for SM-2 computation.
- Cross-device reviewing state (e.g. scored on a computer, then opened on phone) is visible on the phone the next time the lesson is opened while online. Real-time push is not needed.
- The web browser version is unaffected — it always reads live from the API and has no local file cache.
