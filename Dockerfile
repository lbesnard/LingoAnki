# App image — built on top of the pre-built base image.
# The base image (Dockerfile.base) contains all heavy ML deps (torch,
# whisper, spacy, piper-tts) which rarely change. This image only
# contains the lightweight app deps + source code, keeping rebuilds fast
# and Docker Hub pushes small (~1-2 GB instead of ~10 GB).
#
# To rebuild the base (rarely needed):  bash scripts/build_base.sh
# To rebuild this image (normal):
#   docker build -t lozzaroo/lingodiary:latest .
#   docker push lozzaroo/lingodiary:latest

FROM lozzaroo/lingodiary-base:latest

# Poetry settings
ENV POETRY_VERSION=2.3.3
ENV POETRY_HOME=/opt/poetry
ENV POETRY_NO_INTERACTION=1
ENV POETRY_VIRTUALENVS_IN_PROJECT=1
ENV POETRY_VIRTUALENVS_CREATE=1
# Inherit torch/whisper/spacy/piper from the base image's system Python
ENV POETRY_VIRTUALENVS_SYSTEM_PACKAGES=true
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV VIRTUAL_ENV=/app/.venv
ENV PATH="${VIRTUAL_ENV}/bin:$PATH"

ENV CONFIG_PATH=/app/.config/lingoDiary/config.yaml
ENV CONFIG_ROOT=/app/.config/lingoDiary
ENV USER_DB_FILE=/app/.config/lingoDiary/users.yaml

# ✅ Copy only dependency manifests first — this layer is cached unless they change
COPY pyproject.toml poetry.lock* /app/

# ✅ Install lightweight app deps (heavy ML deps already in system Python via base image)
RUN poetry config virtualenvs.in-project true && \
    poetry install --with dev --no-root

# 🔁 Copy source code (invalidates cache only on code changes, not dep changes)
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
