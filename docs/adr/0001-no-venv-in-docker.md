# Lightweight venv with system-site-packages in Docker

The Docker image uses a venv at `/app/.venv` created with `--system-site-packages` (`POETRY_VIRTUALENVS_OPTIONS_SYSTEM_SITE_PACKAGES=true`). The venv can see torch, whisper, spacy, and piper-tts from system Python (installed in the base stage) without copying them.

This means `poetry install --without ml --without dev` only installs the lightweight runtime deps (flask, openai, pydub, PyJWT, etc.) into the venv, producing a layer of ~100–200 MB instead of the 12+ GB seen when poetry reinstalled ML packages. It also avoids the version-conflict downgrades that occur when installing into system Python directly (`POETRY_VIRTUALENVS_CREATE=false`), because poetry's lockfile pins exact versions which would downgrade already-installed system packages.

The `/opt/lingodiary_venv:/app/.venv` volume mount in the dev `docker-compose.yml` was a leftover from running the webapp directly on the host before Docker was adopted; it has been removed. Dev deps (`pytest`, `poetry`, `coverage`) are excluded from the Docker install — they are not needed at runtime and `poetry==2.3.3` cannot install itself via pip into an existing Python environment.
