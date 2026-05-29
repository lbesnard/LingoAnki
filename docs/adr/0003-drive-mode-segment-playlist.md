# Drive Mode plays individual Audio Segments as a playlist, not a pre-assembled MP3

Drive Mode interleaves Input Language and Output Language audio in an order
(Input sentence → Output sentence → Input Q → Output Q → Input A → Output A per
Q&A Pair) that differs from the Lesson Audio assembly order.  Assembling a
separate Drive Mode Lesson Audio would invalidate the existing `audio_timing`
values stored in `diary.json` (which are byte-offsets into the standard Lesson
Audio), require regenerating those files on every Drive Mode backfill, and double
storage.  Instead, Drive Mode chains the individual Audio Segment files at runtime
in Flutter, with a short inter-segment delay handled in the player.  Bold-text
highlighting is driven by playlist index (which segment is playing now), not by
`audio_timing` offsets, so no timing data is needed for Drive Mode at all.

## Considered Options

- **Pre-assembled Drive Mode MP3** — simple audio player but requires new `audio_timing`
  values, double storage, and regeneration whenever segments change.
- **Playlist of existing segments** (chosen) — zero new server-side assembly, no
  `audio_timing` impact, highlighting is simpler (playlist index → text item).
