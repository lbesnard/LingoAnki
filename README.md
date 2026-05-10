# lingoDiary

## About

lingoDiary converts your personal diary entries into language learning materials:

- 🎧 **TPRS MP3 lessons** (Teaching Proficiency Through Reading and Storytelling) — effective and natural language acquisition
- 📱 **Android app** with offline lesson playback and auto sentence highlighting
- 🤖 **OpenAI-powered** translation, Q&A generation, and learning tips

---

## How It Works

You write diary entries in your native language. The app:

1. Translates each sentence into your study language using OpenAI
2. Generates TPRS-style Q&A for each sentence
3. Produces audio lessons with multiple grammatical variants (original, enhanced, present, future)
4. Syncs lessons to the Android app for offline playback

> ✍️ **Tip**: Start with very simple sentences. The goal is to reach fluency through spaced repetition, not complexity.

---

## Server Setup (Docker)

### Prerequisites

- Docker + Docker Compose
- An OpenAI API key

### 1. Clone the repo

```bash
git clone https://github.com/lbesnard/LingoDiary.git
cd LingoDiary
```

### 2. Create the config directory structure

```bash
mkdir -p ~/.config/lingoDiary/
mkdir -p ~/Documents/lingodiary/
```

### 3. Create `users.yaml`

```bash
cat > ~/.config/lingoDiary/users.yaml << 'EOF'
users:
  yourname:
    password: "BCRYPT_HASH_HERE"
    language: "en"
EOF
```

Generate a bcrypt password hash:
```bash
python3 -c "import bcrypt; print(bcrypt.hashpw(b'yourpassword', bcrypt.gensalt()).decode())"
```

### 4. Start the server

```bash
docker compose up --build -d
```

The server runs at `http://localhost:8083`.

> **Note:** The first build is slow (~20 min) because it compiles PyTorch, Whisper, and Piper TTS.
> Subsequent rebuilds are fast — only the app code layer is rebuilt.

---

## Adding a New User

### 1. Create the user config directory

```bash
mkdir -p ~/.config/lingoDiary/<username>/
```

### 2. Create `~/.config/lingoDiary/<username>/config.yaml`

Only these fields are required — paths are derived automatically from the username:

```yaml
openai:
  key: "sk-..."
  model: "gpt-4o-mini"   # or "gpt-4o" for higher quality

languages:
  primary_language: "english"       # language you write your diary in
  primary_language_code: "en"
  study_language: "norwegian"       # language you are learning
  study_language_code: "no"

gender: "male"   # for TTS voice selection

tts:
  model: "piper"
  piper:
    piper_length_scale_diary: 2     # speech speed (2 = slow)
    piper_length_scale_tprs: 2
    voice: "talesyntese-medium"     # Piper voice name
  repeat_sentence_tprs: 2          # how many times each sentence is repeated
  repeat_sentence_diary: 2
  pause_between_sentences_duration: 600   # ms between sentences
  answer_silence_duration: 5000           # ms silence for Q&A answer pause
```

> **Paths are automatic.** With `DATA_ROOT=/data` (set in docker-compose), the user's data
> lives at `/data/<username>/` inside the container, which maps to
> `~/Documents/lingodiary/<username>/` on the host. No path config needed.

### 3. Add the user to `users.yaml`

```yaml
users:
  existinguser:
    password: "..."
    language: "en"
  newuser:                           # ← add this
    password: "BCRYPT_HASH_HERE"
    language: "en"
```

### 4. Create the data directory on the host

```bash
mkdir -p ~/Documents/lingodiary/<username>/
```

### 5. Restart the container

```bash
docker compose restart
```

### 6. Sync from the Android app

Open the app → Settings → **Fix everything** to backfill any missing Q&A translations and audio timing.

---

## Android App

The `android_app/` directory contains a Flutter Android app with offline support.

### Features
- Login with your lingoDiary server credentials
- Browse and listen to lessons offline (MP3s synced locally)
- Active sentence highlighting during playback (bold + auto-scroll)
- Click any sentence to reveal translation
- Settings: auto-repeat, auto-cycle variants (Original → Enhanced → Present → Future)
- Maintenance section: trigger backfills (Q&A, audio timing, full fix) from the app

### Build the APK (GitHub Actions)
APK is built automatically on every push to `main` via `.github/workflows/release.yml`.
Download from the **Releases** tab or the **Actions** tab → latest run.

### Build locally

```bash
bash scripts/setup_flutter_app.sh
cd android_app && flutter build apk --release
# APK: android_app/build/app/outputs/flutter-apk/app-release.apk
```

---

## Docker Hub

### Normal app rebuild (fast, ~1-2 GB push)

```bash
docker compose up --build -d
docker push lozzaroo/lingodiary
```

### Rebuild base image (slow, ~10 GB — only when upgrading torch/whisper/piper)

```bash
bash scripts/build_base.sh
```

---

## Development

### Testing GitHub Actions locally with `act`

```bash
# Install act: https://github.com/nektos/act
act push -W .github/workflows/build.yml -P ubuntu-latest=catthehacker/ubuntu:act-latest
```

### Server API (JWT auth)

| Endpoint | Method | Description |
|---|---|---|
| `/api/login` | POST | Returns a JWT token |
| `/api/diary` | GET/POST | Fetch or save diary content |
| `/api/generate` | POST | Trigger lesson generation |
| `/api/generate/status` | GET | Poll generation progress |
| `/api/lessons` | GET | List lessons + variants |
| `/api/sync/manifest` | GET | File manifest for app sync |
| `/api/sync/file/<path>` | GET | Download a synced file |
| `/api/backfill/qa_translations` | POST | Fill missing Q&A translations |
| `/api/backfill/audio_timing` | POST | Rebuild audio segments + timing |
| `/api/backfill/all` | POST | Full maintenance (diary sync + Q&A + audio) |

Set `JWT_SECRET` env var in production (defaults to `SECRET_KEY`).
