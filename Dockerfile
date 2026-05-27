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

# ── Stage 2: flutter-web — build the Flutter web app ─────────────────────────
# Rebuilt only when the Flutter source or pubspec changes.
# The output (build/web/) is copied into stage 3 so no Flutter SDK ends up in
# the final image.
FROM debian:bookworm-slim AS flutter-web

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        unzip \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Install Flutter as root into /opt/flutter (pinned to the same version used in CI)
ENV FLUTTER_VERSION=3.41.9
RUN git config --global --add safe.directory /opt/flutter && \
    curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar -xJ -C /opt && \
    git config --global --add safe.directory /opt/flutter && \
    /opt/flutter/bin/flutter config --no-analytics --suppress-analytics && \
    /opt/flutter/bin/flutter precache --web

ENV PATH="/opt/flutter/bin:$PATH"
ENV FLUTTER_SUPPRESS_ANALYTICS=true

# Run Flutter as a non-root user to suppress the "running as root" warning
RUN useradd -m -u 1000 flutteruser && \
    chown -R flutteruser:flutteruser /opt/flutter
ENV GIT_GLOBAL_CONFIG_DIR=/home/flutteruser
USER flutteruser

WORKDIR /flutter_app
COPY --chown=flutteruser:flutteruser android_app/pubspec.yaml android_app/pubspec.lock* ./
RUN git config --global --add safe.directory /opt/flutter && flutter pub get

# Copy only the source that affects the web build
COPY --chown=flutteruser:flutteruser android_app/lib/ ./lib/
COPY --chown=flutteruser:flutteruser android_app/web/ ./web/

RUN git config --global --add safe.directory /opt/flutter && \
    flutter build web --release

# ── Stage 3: app — lightweight deps + source code ────────────────────────────
# Rebuilt on every poetry.lock or source change, but stays fast because
# the heavy ML packages are already present from stage 1.
#
# No virtualenv — Docker containers are already isolated, so a venv inside
# a container adds no benefit and doubles the storage cost for large ML packages.
# See docs/adr/0001-no-venv-in-docker.md for rationale.

FROM base AS app

ENV POETRY_NO_INTERACTION=1 \
    POETRY_VIRTUALENVS_CREATE=false

# Container-level defaults — consistent with the volume mounts in docker-compose.yml
ENV CONFIG_ROOT=/app/.config/lingoDiary \
    USER_DB_FILE=/app/.config/lingoDiary/users.yaml \
    DATA_ROOT=/data \
    XDG_DATA_HOME=/app/.local

# ✅ Copy only dependency manifests first — cached unless they change
COPY --chown=1000:1000 pyproject.toml poetry.lock* /app/

# ✅ Install runtime app deps directly into system Python (no venv).
# --without ml:  whisper/spacy/piper are already in system Python from base.
# No --with dev: dev tools (pytest, poetry, coverage) are not needed at runtime
#                and poetry==2.3.3 cannot install itself via pip into system Python.
RUN poetry install --without ml --no-root

# 🔁 Copy source (invalidates cache only on code changes, not dep changes)
COPY --chown=1000:1000 lingodiary/ /app/lingodiary/
COPY --chown=1000:1000 README.md /app/

# ✅ Copy Flutter web build from stage 2
COPY --chown=1000:1000 --from=flutter-web /flutter_app/build/web/ /app/web_build/

# ✅ Install the lingodiary package itself (registers lingoWebapp entry point)
RUN poetry install --only-root

EXPOSE 8084

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
