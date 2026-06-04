<p align="center">
  <img src="android_app/assets/icon/app_icon.png" width="96" alt="LingoDiary Icon"/>
</p>

## <h1 align="center">LingoDiary</h1>

Write diary entries in your own language. LingoDiary turns them into TPRS-style audio lessons — translated sentences, Q&A pairs, and multiple grammatical variants — ready to listen on your phone or in the browser.

## Quick start

**You need:** Docker, Docker Compose, and an OpenAI API key.

Create a `docker-compose.yml` anywhere on your machine:

```yaml
services:
  lingo-diary:
    image: lozzaroo/lingodiary
    ports:
      - 8083:8084
    volumes:
      - ~/.config/lingoDiary/:/app/.config/lingoDiary/
      - ~/Documents/lingodiary/:/data/
    environment:
      SECRET_KEY: "change-me-to-a-random-string"
```

### Creating user configs

**Option A: Automated setup tool** (recommended)

Use the interactive `manage-config.py` script to create and manage user configurations:

```bash
# From the repo directory
python scripts/manage-config.py add-user
```

The script will guide you through:
1. **Username** — your login name
2. **Password** — stored with bcrypt hashing
3. **Primary Language** — language you write your diary in (menu: english, norwegian, french, etc.)
4. **Study Language** — language you're learning (menu: english, norwegian, french, etc.)
5. **Gender** — for grammatical output (male/female)
6. **Voice selections** — TTS voices for study language and primary language
7. **OpenAI API key** — for translation and tips generation

This automatically creates:
- `~/.config/lingoDiary/users.yaml` (if not exists)
- `~/.config/lingoDiary/{username}/config.yaml`

**Option B: Custom config directory**

If you use a different config location:

```bash
python scripts/manage-config.py add-user -o ~/my-lingodiary-config
```

**Option C: Custom docker-compose.yml path**

```bash
python scripts/manage-config.py add-user -i /path/to/docker-compose.yml
```

### Managing users

```bash
# List all registered users
python scripts/manage-config.py list-users

# Modify an existing user's config
python scripts/manage-config.py modify-user myuser

# Delete a user (backs up config automatically)
python scripts/manage-config.py delete-user myuser
```

### Manual setup (if not using the tool)

If you prefer to create configs manually, replace `myuser` with your username:

```bash
mkdir -p ~/.config/lingoDiary/myuser
mkdir -p ~/Documents/lingodiary/myuser
```

Generate a bcrypt hash for your password:

```bash
python3 -c "import bcrypt; print(bcrypt.hashpw(b'yourpassword', bcrypt.gensalt()).decode())"
```

Create `~/.config/lingoDiary/users.yaml`:

```yaml
users:
  myuser:
    password: "$2b$12$..." # paste your bcrypt hash here
    language: "en"
```

Create `~/.config/lingoDiary/myuser/config.yaml`:

```yaml
output_dir: "/data/myuser/"

create_diary_answers_auto: true

openai:
  key: "sk-..."
  model: "gpt-4o-mini"

languages:
  primary_language: "english"
  primary_language_code: "en"
  study_language: "norwegian"
  study_language_code: "no"

gender: "male"

tts:
  model: "piper"
  piper:
    piper_length_scale_tprs: 2
    piper_length_scale_diary: 2
    voice: "talesyntese-medium"
  piper_input_language:
    voice: "alan-low"
  repeat_sentence_tprs: 2
  repeat_sentence_diary: 2
  pause_between_sentences_duration: 600
  answer_silence_duration: 5000
```

Pull the image and start:

```bash
docker compose pull
docker compose up -d
```

The server runs at `http://localhost:8083`.

---

## Web app

Open `http://localhost:8083` in your browser and log in. Write diary entries, trigger generation, and listen to lessons — all from the browser.

---

## Android app

Download the latest APK from the [Releases](../../releases) tab and install it on your phone.

Open the app, and enter your server URL (e.g. `http://192.168.1.x:8083`). Log in with your username and password.

|               Home Screen                |               Lesson Screen                |
| :--------------------------------------: | :----------------------------------------: |
| <img src="assets/home.png" width="100%"> | <img src="assets/lesson.png" width="100%"> |

---

## Build from source

Only needed if you want to modify the code. The first build is slow (compiles PyTorch, Whisper, and Piper TTS).

```bash
git clone https://github.com/lbesnard/LingoDiary.git
cd LingoDiary
docker compose up --build -d
```

To build the Android APK locally:

```bash
cd android_app && flutter build apk --release
# APK: android_app/build/app/outputs/flutter-apk/app-release.apk
```

---

## Developer: Managing Piper Voices

If you add new Piper TTS voice models to the Docker image, you must regenerate the voice list:

```bash
# 1. Start the container
docker compose up -d

# 2. Run voice discovery inside the container
docker compose exec lingo-diary python scripts/discover-voices.py

# 3. Commit the updated voice list
git add scripts/piper_voices.yaml
git commit -m "chore: update available Piper voices"
```

This creates `scripts/piper_voices.yaml` which is used by the configuration tool (`scripts/manage-config.py`) to help users select voices when creating accounts.
