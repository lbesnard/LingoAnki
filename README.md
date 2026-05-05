# lingoDiary

## About This Script

This script converts your personal diary entries into powerful language learning materials:

- 📇 **Anki flashcards** to reinforce vocabulary and sentence structure through spaced repetition
- 🎧 **MP3 lessons using TPRS** (Teaching Proficiency Through Reading and Storytelling), a highly effective and natural method for language acquisition

---

## Why This Approach?

Most language learning resources teach you someone else's vocabulary. The result? You struggle to express yourself — because you're not learning the words that matter **to you**.

By writing a diary, you're telling **your own story**, using **your own vocabulary**. This makes the learning process more relevant, personal, and effective. Each diary entry is then transformed into a TPRS-style lesson — tailored to your life.

> ✨ We use **OpenAI** to:
>
> - Translate your diary entries into the study language
> - Generate helpful tips to understand the translation
> - Create **Q&A prompts** in TPRS style for each sentence

TPRS is a proven method that emphasises storytelling, repetition, and comprehension questions. Unfortunately, for many languages, high-quality TPRS resources are hard to find. This script fills that gap by letting you create your own.

---

## How to Use the MP3 Lessons

Listen to each audio file **repeatedly** — 20 times is not an exaggeration. The goal is to reach the point where you **respond without thinking**.

As you progress, so will your diary entries. They'll naturally become more complex.

> ✍️ **Tip**: Start with **very simple sentences** — it's better to master the basics before adding complexity.

---

This script empowers you to build your fluency one story at a time — your story.

## Example

Below is an example of a diary entry to learn Norwegian:

[📖 Diary Example](readme_ressources/%F0%9F%93%96%20Diary%20-%20Dagbokkorrigering.md)

[📄 View TPRS markdown example](readme_ressources/TPRS/Norwegian%20🇳🇴-%20Diary%20📖_TPRS_2025-04-07_Testens%20spennende%20reise.md)

[🎧 Download and listen to the MP3 TPRS lesson](readme_ressources/TPRS/Norwegian%20🇳🇴-%20Diary%20📖_TPRS_2025-04-07_Testens%20spennende%20reise.mp3)

## usage

Copy the [Config file example](lingoanki/config.yaml) into `~/.config/lingoDiary/config.yaml`
An OpenAi API is required to translate and create TPRS style Q&A.

```bash
lingoDiary  # will automatically prompt the user for new entries
```

# lingoAnki

This script automates the creation of Anki flashcards from transcripts extracted from audio recordings. It processes
both individual words and sentences, generating transcriptions and translations, and attaching audio to each flashcard.

Features:

- Uses Whisper for transcription and Google Text-to-Speech (TTS) for generating audio.
- Translates words and sentences using GoogleTranslator or ChatGptTranslator.
- Organizes flashcards into two Anki subdecks: one for words and one for sentences.
- Supports multiple languages.

## Installation

```bash
curl -f https://raw.githubusercontent.com/lbesnard/LingoAnki/refs/heads/main/install.sh | bash
```

## Installation with Poetry

Clone the repo

```bash
pip install poetry
poetry install
```

## Example

```bash
usage: lingoAnki [-h] [--ankideck ANKIDECK] [--input-language INPUT_LANGUAGE] [--target-language TARGET_LANGUAGE] [--output-folder OUTPUT_FOLDER] [--check-sentences] [--model [MODEL]] [--select-files] audio_dir

Automates the creation of Anki flashcards from transcripts extracted from audio recordings.

positional arguments:
  audio_dir             Directory containing the input audio files to process

options:
  -h, --help            show this help message and exit
  --ankideck ANKIDECK, -a ANKIDECK
                        Anki main Deck name
  --input-language INPUT_LANGUAGE, -il INPUT_LANGUAGE
                        Language Code input to parse (en,bo,fr ...)
  --target-language TARGET_LANGUAGE, -tl TARGET_LANGUAGE
                        Language Code output (en,fr ...)
  --output-folder OUTPUT_FOLDER, -o OUTPUT_FOLDER
                        Output folder
  --check-sentences, -c
                        Manually review and modify the transcription
  --model [MODEL], -m [MODEL]
                        Choose a model from the list or use default.
  --select-files, -s    If set, allows you to select files interactively for processing.
```

## When to use

It is especially useful to convert Audio lessons, for example converting all the
audio files from an Assimil course into flashcards. This script is mainly
intended for this

But one could use this script as well to convert podcasts.

---

## Development & Testing

### Docker (local)

Use `docker-compose_dev.yml` for local development. Always pass `--build` to
force Docker to rebuild the image from the `Dockerfile` — without it, Docker
reuses the cached image and your changes won't be picked up.

```bash
# Rebuild and start (uses Docker layer cache where possible)
docker compose -f docker-compose_dev.yml up -d --build

# Full clean rebuild (no cache — useful after Dockerfile changes)
docker compose -f docker-compose_dev.yml up -d --build --no-cache

# View logs
docker compose -f docker-compose_dev.yml logs -f

# Stop
docker compose -f docker-compose_dev.yml down
```

> **Note:** `docker compose up -d` without `--build` will **not** rebuild the
> image even if you've changed the `Dockerfile`.

### Testing GitHub Actions locally with `act`

[`act`](https://github.com/nektos/act) lets you run GitHub Actions workflows
locally without pushing to GitHub.

**Install:**
```bash
# macOS
brew install act

# Linux (via script)
curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
```

**Run the CI build workflow** (mirrors what runs on push/PR to `main`):
```bash
# Run the full build workflow (tests + package build)
act push -W .github/workflows/build.yml

# Run for a specific Python version only
act push -W .github/workflows/build.yml --matrix python-version:3.10.14

# Use a larger runner image (recommended — avoids missing-tool errors)
act push -W .github/workflows/build.yml -P ubuntu-latest=catthehacker/ubuntu:act-latest
```

> **Tip:** The first run downloads a Docker image for the runner (~1–4 GB).
> Subsequent runs are fast. The "Clean up directories" step in the workflow is
> automatically skipped when running under `act` (it's only needed on
> GitHub-hosted runners).
