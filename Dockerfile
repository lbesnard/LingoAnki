# ── Stage 1: base — heavy ML dependencies ────────────────────────────────────
# This stage is cached by Docker between builds. It is only rebuilt when
# the pip install lines below change (i.e. when you upgrade torch/whisper/
# spacy/piper). Normal code or poetry.lock changes only rebuild stage 2.
#
# To also publish this as a standalone image for faster CI/CD:
#   bash scripts/build_base.sh

# 3.10 required for piper
FROM python:3.10.1 AS base

ENV POETRY_VERSION=2.3.3
ENV POETRY_HOME=/opt/poetry
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# System tools + ffmpeg + Poetry binary
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ffmpeg \
    && curl -sSL https://install.python-poetry.org | python3 - \
    && ln -s ${POETRY_HOME}/bin/poetry /usr/local/bin/poetry \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Heavy ML packages installed into system Python — pinned so this layer
# is only invalidated when YOU deliberately change one of these lines.
RUN pip install --no-cache-dir \
    "torch==2.6.0" \
    "torchaudio==2.6.0" \
    --index-url https://download.pytorch.org/whl/cpu

RUN pip install --no-cache-dir \
    "openai-whisper @ git+https://github.com/openai/whisper.git@main"

RUN pip install --no-cache-dir \
    "spacy==3.7.5" \
    "piper-tts==1.2.0" \
    "ovos-tts-plugin-piper==0.0.2"

RUN mkdir -p /app/.local && chown -R 1000:1000 /app/.local

# ── Stage 2: app — lightweight deps + source code ────────────────────────────
# Rebuilt on every poetry.lock or source change, but stays fast because
# the heavy ML packages are already present from stage 1.

FROM base AS app

# Poetry venv inherits system-level packages (torch, whisper, spacy, piper)
# installed in the base stage so poetry install skips them.
ENV POETRY_NO_INTERACTION=1
ENV POETRY_VIRTUALENVS_IN_PROJECT=1
ENV POETRY_VIRTUALENVS_CREATE=1
ENV POETRY_VIRTUALENVS_SYSTEM_PACKAGES=true
ENV VIRTUAL_ENV=/app/.venv
ENV PATH="${VIRTUAL_ENV}/bin:$PATH"

# Container-level defaults — consistent with the volume mounts in docker-compose.yml
ENV CONFIG_ROOT=/app/.config/lingoDiary
ENV USER_DB_FILE=/app/.config/lingoDiary/users.yaml
ENV DATA_ROOT=/data

# ✅ Copy only dependency manifests first — cached unless they change
COPY pyproject.toml poetry.lock* /app/

# ✅ Install lightweight app deps (flask, openai, pydub, etc.)
RUN poetry config virtualenvs.in-project true && \
    poetry install --with dev --no-root

# 🔁 Copy source (invalidates cache only on code changes, not dep changes)
COPY lingoanki/ /app/lingoanki
COPY README.md /app/

# ✅ Install the lingoanki package itself; write lock hash for entrypoint check
RUN poetry install --only-root && \
    sha256sum /app/poetry.lock | awk '{print $1}' > /app/.poetry.lock.sha256

# For piper voice models
ENV XDG_DATA_HOME=/app/.local

# Allow user 1000 to write anywhere in /app (needed when running as non-root)
RUN chown -R 1000:1000 /app

EXPOSE 8084

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
