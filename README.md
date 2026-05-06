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

## Publishing to Docker Hub

```bash
# Build and tag
docker build -t lozzaroo/lingodiary .

# Push to Docker Hub (requires: docker login)
docker push lozzaroo/lingodiary
```

To pull and run on another machine without building from source, uncomment the
`image:` line in `docker-compose.yml` and comment out `build: .`:

```yaml
services:
  lingo-diary:
    image: lozzaroo/lingodiary   # ← uncomment this
    # build: .                   # ← comment this out
```

Then just:

```bash
docker compose up -d
```

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

---

## Android App

The `android_app/` directory contains a Flutter Android app with offline support.

### Features
- Login with your LingoDiary server credentials
- Edit diary + sync with server when connected
- Generate lessons (calls the server, polls progress)
- Browse and listen to lessons offline (mp3s synced locally)
- Connection badge shows online/offline status at all times

### Build the APK (GitHub Actions)
The APK is built automatically on every push to `main` via `.github/workflows/build_android.yml`.
Download the artifact from the **Actions** tab → latest run → `lingodiary-apk-*`.

### Build locally
```bash
# Install Flutter: https://docs.flutter.dev/get-started/install/linux
# Then from the repo root — this regenerates the Gradle scaffold and restores our source:
bash scripts/setup_flutter_app.sh
cd android_app && flutter build apk --release
# APK: android_app/build/app/outputs/flutter-apk/app-release.apk
```

> **Why the setup script?** Flutter requires its Gradle project to be generated by
> `flutter create`. The `android_app/` directory contains only the Dart source and
> `pubspec.yaml`; the script regenerates the full project structure and merges the
> dependencies automatically.

### Test on Linux with Android emulator

**Install Android command-line tools:**
```bash
# Download from https://developer.android.com/studio#command-line-tools-only
mkdir -p ~/android-sdk/cmdline-tools
unzip commandlinetools-linux-*.zip -d ~/android-sdk/cmdline-tools
mv ~/android-sdk/cmdline-tools/cmdline-tools ~/android-sdk/cmdline-tools/latest
export ANDROID_SDK_ROOT=~/android-sdk
export PATH=$PATH:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/emulator:$ANDROID_SDK_ROOT/platform-tools
```

**Create and launch an emulator:**
```bash
# Accept licences and install required packages
sdkmanager --licenses
sdkmanager "platform-tools" "emulator" "platforms;android-34" \
           "system-images;android-34;google_apis;x86_64"

# Create AVD
avdmanager create avd -n lingodiary_test \
  -k "system-images;android-34;google_apis;x86_64" --device "pixel_6"

# Start emulator (requires KVM — enable with: sudo usermod -aG kvm $USER)
emulator -avd lingodiary_test &
adb wait-for-device
```

**Install and run the APK:**
```bash
adb install android_app/build/app/outputs/flutter-apk/app-release.apk
```

**Or run in debug mode directly (no APK needed, fastest for development):**
```bash
cd android_app
flutter run   # automatically detects the running emulator
```

### Server API (for the app)
The Flask server exposes a REST API under `/api/` using JWT auth:

| Endpoint | Method | Description |
|---|---|---|
| `/api/login` | POST | Returns a JWT token |
| `/api/diary` | GET | Fetch diary content |
| `/api/diary` | POST | Save diary content |
| `/api/generate` | POST | Trigger lesson generation |
| `/api/generate/status` | GET | Poll generation log |
| `/api/lessons` | GET | List available lessons + variants |
| `/api/sync/manifest` | GET | File manifest (path, size, mtime) |
| `/api/sync/file/<path>` | GET | Download a specific output file |

Set `JWT_SECRET` env var in production (defaults to `SECRET_KEY`).
