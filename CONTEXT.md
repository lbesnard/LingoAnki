# LingoDiary — Bounded Context

## Glossary

### Day
A single diary day, identified by a `YYYY/MM/DD` date string.  A Day has a title,
an ordered list of **Sentences**, and one assembled **Lesson Audio** file per
**Lesson Variant**.  `DiaryDay` in code.

### Sentence
One sentence the user wrote in their **Input Language**, together with its
**Output Language** translation and AI-generated tips.  Sentences within a Day are
numbered from 1 (1-based `index`).  Each Sentence owns a **Variant Set**.
`DiaryEntry` in code.

### Input Language
The language the user already speaks and writes their diary in (their native or
dominant language).  Fields whose names end in `_input` or `input_language_*`
hold text in this language.

### Output Language
The language the user is learning.  Fields whose names end in `_translation` or
`output_language_*` hold text in this language.

### Lesson
All **Sentence Blocks** for one **Lesson Variant** across an entire **Day**.
A Lesson is what gets assembled into a single **Lesson Audio** file and played
back in the app.

### Lesson Variant
One of the four grammatical retellings of a Day's content: `original`,
`enhanced`, `present`, `future`.

### Variant Set
The group of four **Sentence Blocks** (one per **Lesson Variant**) that belong to
a single **Sentence**, together with its shared **Reviewing State**.
`LessonsBlock` in code.

### Sentence Block
One **Lesson Variant**'s retelling of a **Sentence**: the retold sentence text in
the **Output Language** plus its list of **Q&A Pairs**, audio segment path, and
**Audio Timing**.  `VariantLesson` in code.

### Q&A Pair
A comprehension question and its answer, both in the **Output Language**, within a
**Sentence Block**.  Each also carries an **Input Language** translation
(`question_input`, `answer_input`) so the learner can check meaning.  `QA` in code.

### Audio Segment
An individual MP3 clip for one unit of audio content: a **Sentence Block**'s
sentence (`*_s.mp3`), a question (`*_q{n}.mp3`), or an answer (`*_a{n}.mp3`).
Stored under `TPRS/SEGMENTS/{date}_{variant}/`.  Path is relative to the server's
`output_dir`.

### Audio Timing
A `{start_ms, end_ms}` pair that locates an **Audio Segment** within the
assembled **Lesson Audio** for its **Lesson Variant**.  `AudioTiming` in code.

### Lesson Audio
The single assembled MP3 for one **Lesson** (one **Lesson Variant** on one **Day**);
a concatenation of all Audio Segments in order (sentence → Q&A pairs, with
inter-segment silence).  Stored at `TPRS/TPRS_{date}{variant_suffix}.mp3`.
Path tracked per-variant in `DiaryDay.lesson_audio_paths`.

### Reviewing State
SM-2 spaced-repetition metadata for one **Sentence**: status (`new` / `learning` /
`mastered`), mastery score (0–5), interval, and next-review date.  Shared across
all Lesson Variants of the same Sentence.  `ReviewingState` in code.

### Translation Attempt
The learner's own rendering of a **Sentence** in the **Output Language**, written
before the AI-generated translation is revealed.  Stored per-Sentence in
`user_trial_translation`.  Not meant to be correct — its value is in the act of
trying.
_Avoid_: trial sentence, trial translation, draft translation

### TPRS
Total Physical Response Storytelling — the language-teaching method that motivates
the Lesson Variant / Q&A structure.  Also used as the top-level folder name for
all generated audio files (`TPRS/`).

### Drive Mode
An audio-first, hands-free playback experience for a **Lesson**.  Plays
**Input Language Audio Segments** and **Audio Segments** in sequence per
**Sentence Block**, with auto-advance, without requiring the user to look at
the screen.  Within each Sentence Block the playback order is: Input Language
sentence → Output Language sentence → for each **Q&A Pair**, Input Language
question → Output Language question → Input Language answer → Output Language
answer.  Auto-advances to the next Sentence Block when complete.  In the
Drive Mode UI the navigable unit is called a **Block** (short for Sentence
Block).
_Avoid_: car mode, driving mode, chapter (legacy term, ambiguous)

### Input Language Audio Segment
A Piper TTS-generated MP3 of one unit of **Input Language** text: the
`sentence_input` of a **Sentence Block**, or the `question_input`/`answer_input`
of a **Q&A Pair**.  Paths stored as `sentence_input_language_audio_path`,
`question_input_language_audio_path`, `answer_input_language_audio_path`.
_Avoid_: native audio, input audio
