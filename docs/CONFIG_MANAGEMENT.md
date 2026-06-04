# User Configuration Management

LingoDiary provides two tools for managing user configs and Piper TTS voices:

## Tools

### `scripts/discover-voices.py`

Discovers available Piper TTS voices and saves them to `scripts/piper_voices.yaml`.

**Usage:**
```bash
python scripts/discover-voices.py
```

**How it works:**
1. Connects to the `lingo-diary` Docker container via `docker compose exec`
2. Scans the Piper models directory (`~/.local/share/piper/models/`)
3. Falls back to a built-in list of known Piper voices if models are not found
4. Organizes voices by language code and gender (male/female)
5. Saves to `scripts/piper_voices.yaml` for use by `manage-config.py`

**Output:**
```yaml
languages:
  en:
    male:
      - alan-low
      - en-US-lessac-low
    female:
      - en-US-ryan-high
  no:
    female:
      - talesyntese-medium
  # ... more languages
```

### `scripts/manage-config.py`

Interactive CLI tool for creating, updating, and deleting user configurations.

**Config directory resolution** (in priority order):
1. `-o/--output` flag (overrides everything)
2. Parse `docker-compose.yml` to extract `/app/.config/lingoDiary/` volume mount
3. Fallback: `~/.config/efunk_lingo/lingoDiary/`

**Usage (interactive menu):**
```bash
python scripts/manage-config.py
```

**Usage (with custom config directory):**
```bash
python scripts/manage-config.py -o /path/to/config add-user
python scripts/manage-config.py -i /path/to/docker-compose.yml add-user
```

**Usage (direct commands):**
```bash
python scripts/manage-config.py add-user
python scripts/manage-config.py modify-user [username]
python scripts/manage-config.py delete-user [username]
python scripts/manage-config.py list-users

# With options:
python scripts/manage-config.py -o ~/.config/custom add-user
python scripts/manage-config.py -i docker-compose.yml list-users
```

**Options:**
- `-i, --input FILE` — Path to docker-compose.yml (default: ../docker-compose.yml)
- `-o, --output DIR` — Config directory (overrides docker-compose.yml volume)

## Configuration Files

### `users.yaml`

Located at: `~/.config/efunk_lingo/lingoDiary/users.yaml`

System-wide user registry with password hashes:
```yaml
users:
  laurent:
    password: "$2b$12$..."  # bcrypt hash
    language: "en"         # interface language
  johanne:
    password: "$2b$12$..."
    language: "fr"
```

**Managed by:** `manage-config.py add-user`, `modify-user`, `delete-user`

### Per-User Config

Located at: `~/.config/efunk_lingo/lingoDiary/{username}/config.yaml`

Per-user settings for language learning, TTS, and content generation:
```yaml
output_dir: "/data/laurent/"
gender: "male"

languages:
  primary_language: "English"
  primary_language_code: "en"
  study_language: "Norwegian"
  study_language_code: "no"

tts:
  piper:
    voice: "talesyntese-medium"        # output language voice
  piper_input_language:
    voice: "alan-low"                  # input language voice (Drive Mode)

openai:
  key: "sk-..."                        # OpenAI API key
```

**Managed by:** `manage-config.py add-user`, `modify-user`

## Workflow

### Adding a New User

```bash
python scripts/manage-config.py add-user
```

Prompts for:
1. **Username** — unique identifier
2. **Password** — bcrypt hashed before storage
3. **Primary Language** — language they write in (e.g., "English (en)")
4. **Study Language** — language they're learning (e.g., "Norwegian (no)")
5. **Gender** — male/female (used for grammar output)
6. **Study Language Voice** — Piper voice for output language audio
7. **Primary Language Voice** — Piper voice for input language audio (Drive Mode)
8. **OpenAI API Key** — for translation and Q&A generation

Creates:
- Entry in `users.yaml` with password hash
- Directory `~/.config/efunk_lingo/lingoDiary/{username}/`
- Config file `{username}/config.yaml` with default values

### Modifying a User

```bash
python scripts/manage-config.py modify-user [username]
```

Shows current config values and lets you update any field by pressing Enter to skip.

### Deleting a User

```bash
python scripts/manage-config.py delete-user [username]
```

1. **Backs up** the user's config to `~/.config/efunk_lingo/lingoDiary/backups/{username}_{timestamp}.tar.gz`
2. **Removes** the config directory
3. **Deletes** the user entry from `users.yaml`

Confirm deletion by typing the username.

## Security Notes

### Password Storage
- Passwords are hashed using **bcrypt** with salt
- Hashes are stored in `users.yaml`
- Never commit real passwords to version control

### OpenAI API Keys
- Keys are stored in plaintext in `config.yaml`
- File permissions are set to `0o600` (owner only)
- **Keep file permissions tight** — run `chmod 600 ~/.config/efunk_lingo/lingoDiary/*/config.yaml`
- **Rotate keys periodically** if exposed
- **Never commit real keys** to version control

### File Permissions
After setup, ensure restrictive permissions:
```bash
chmod 600 ~/.config/efunk_lingo/lingoDiary/users.yaml
chmod 600 ~/.config/efunk_lingo/lingoDiary/*/config.yaml
```

## Example: Adding Laurent's Config

```bash
$ python scripts/manage-config.py add-user

Username: laurent
Password: ••••••••
Confirm password: ••••••••

Primary Language []: English (en)
Study Language []: Norwegian (no)
Gender []:
  1. male
  2. female
Enter choice: 1

Study Language Voice (available voices for no):
  1. talesyntese-medium
Enter choice: 1

Primary Language Voice (male voices for en):
  1. alan-low
  2. en-US-artic-neural-8000hz
  ...
Enter choice: 1

OpenAI Key: sk-proj-...

✓ User 'laurent' added to users.yaml
✓ Config created: /home/user/.config/efunk_lingo/lingoDiary/laurent/config.yaml
✓ User 'laurent' set up successfully!
```

## Regenerating Voice List (Developer Task)

After installing new Piper voice models in the Docker container, you must regenerate the voice list so users can select them:

```bash
# 1. Start the container
docker compose up -d

# 2. Run voice discovery inside the container
docker compose exec lingo-diary python scripts/discover-voices.py

# 3. Commit the updated voice list
git add scripts/piper_voices.yaml
git commit -m "chore: update available Piper voices"
```

This updates `scripts/piper_voices.yaml`, which is checked into the repository and used by `manage-config.py` for voice selection during user setup.

## Troubleshooting

### Limited Norwegian Voices

**Note:** Piper TTS currently has only one Norwegian voice: `talesyntese-medium` (female). Users selecting Norwegian as their study language will only have this single voice available, regardless of the "male" or "female" gender selection.

This is a limitation of the Piper voice library, not LingoDiary. If you need male Norwegian voices, consider using a different TTS engine or waiting for new voice models to be added to Piper.

### "No voices found" when running discover-voices

**Possible causes:**
- Docker container not running: `docker compose up -d`
- Piper models not installed in container (expected on first run)

**Solution:** The tool uses a fallback list of known Piper voices. To get specific voices, download them into the container's `~/.local/share/piper/models/` directory.

### "User config not found" when starting the app

**Cause:** User added to `users.yaml` but config file is missing

**Solution:**
```bash
python scripts/manage-config.py modify-user username
```
Then save (press Enter on all fields to use defaults).

### OpenAI key errors in logs

**Cause:** Key missing or invalid

**Solution:**
```bash
python scripts/manage-config.py modify-user username
```
Then update the OpenAI key when prompted.
