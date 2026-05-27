# LingoDiary — Bounded Context

## Glossary

### Day
A single diary day, identified by a `YYYY/MM/DD` date string.  A Day has a title,
an ordered list of **Entries**, and one assembled **Lesson Audio** file per **Variant**.
`DiaryDay` in code.

### Entry
One sentence the user wrote in their **Input Language**, together with its
**Output Language** translation and AI-generated tips.  Entries within a Day are
numbered from 1 (1-based `index`).  Each Entry owns a **Lessons Block**.
`DiaryEntry` in code.

### Input Language
The language the user already speaks and writes their diary in (their native or
dominant language).  Fields whose names end in `_input` or `input_language_*`
hold text in this language.

### Output Language
The language the user is learning.  Fields whose names end in `_translation` or
`output_language_*` hold text in this language.

### Lessons Block
The collection of all **Variants** for one Entry, plus the shared **Reviewing State**.
`LessonsBlock` in code.

### Variant
One grammatical retelling of an Entry's sentence in the **Output Language**.
There are exactly four: `original`, `enhanced`, `present`, `future`.
Each Variant has a **Variant Sentence**, a list of **Q&A Pairs**, and **Audio Segments**
with **Audio Timings** relative to the **Lesson Audio** for that Variant.
`VariantLesson` in code.

### Variant Sentence
The rewritten sentence that belongs to a specific **Variant**.  Stored alongside
its **Input Language** back-translation (`sentence_input`).

### Q&A Pair
A comprehension question and its answer, both in the **Output Language**, within a
**Variant**.  Each also carries an **Input Language** translation (`question_input`,
`answer_input`) so the learner can check meaning.  `QA` in code.

### Audio Segment
An individual MP3 clip for one unit of audio content: a **Variant Sentence**
(`*_s.mp3`), a question (`*_q{n}.mp3`), or an answer (`*_a{n}.mp3`).  Stored
under `TPRS/SEGMENTS/{date}_{variant}/`.  Path is relative to the server's
`output_dir`.

### Audio Timing
A `{start_ms, end_ms}` pair that locates an **Audio Segment** within the assembled
**Lesson Audio** for its Variant.  `AudioTiming` in code.

### Lesson Audio
The single assembled MP3 for one **Variant** on one **Day**; a concatenation of all
Audio Segments in order (sentence → Q&A pairs, with inter-segment silence).
Stored at `TPRS/TPRS_{date}{variant_suffix}.mp3`.  Path tracked per-variant in
`DiaryDay.lesson_audio_paths`.

### Reviewing State
SM-2 spaced-repetition metadata for one **Entry**: status (`new` / `learning` /
`mastered`), mastery score (0–5), interval, and next-review date.  Shared across
all Variants of the same Entry.  `ReviewingState` in code.

### TPRS
Total Physical Response Storytelling — the language-teaching method that motivates
the Variant/Q&A structure.  Also used as the top-level folder name for all
generated audio files (`TPRS/`).
