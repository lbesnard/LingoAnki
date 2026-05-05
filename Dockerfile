# 3.10 required for piper
FROM python:3.10.1

# Set environment variables for Poetry
ENV POETRY_VERSION=2.3.3
ENV POETRY_HOME=/opt/poetry
ENV POETRY_NO_INTERACTION=1
ENV POETRY_VIRTUALENVS_IN_PROJECT=1
ENV POETRY_VIRTUALENVS_CREATE=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV VIRTUAL_ENV=/app/.venv
ENV PATH="${VIRTUAL_ENV}/bin:$PATH"


# Install Poetry and dependencies
RUN apt-get update && apt-get install -y curl && \
  curl -sSL https://install.python-poetry.org | python3 - && \
  ln -s ${POETRY_HOME}/bin/poetry /usr/local/bin/poetry

# Install ffmpeg
WORKDIR /app
RUN apt install ffmpeg -y

# Set the working directory to install the python module
WORKDIR /app

ENV CONFIG_PATH=/app/.config/lingoDiary/config.yaml
ENV CONFIG_ROOT=/app/.config/lingoDiary
ENV USER_DB_FILE=/app/.config/lingoDiary/users.yaml

# ✅ Copy only dependency manifests first — this layer is cached unless they change
COPY pyproject.toml poetry.lock* /app/

# ✅ Install third-party dependencies only (no source needed yet)
RUN poetry config virtualenvs.in-project true && \
    poetry install --with dev --no-root

# 🔁 Copy the actual source code (invalidates cache only on code changes, not dep changes)
COPY lingoanki/ /app/lingoanki
COPY README.md /app/

# ✅ Install the lingoanki project itself (deps already in venv, this is fast)
# Pre-write the hash file so the entrypoint skips re-install on a fresh container start
RUN poetry install --only-root && \
    sha256sum /app/poetry.lock | awk '{print $1}' > /app/.poetry.lock.sha256

# For piper
ENV XDG_DATA_HOME=/app/.local
RUN mkdir -p /app/.local && chown -R 1000:1000 /app/.local

# Allow user 1000 to write anywhere in /app (needed when running as non-root)
RUN chown -R 1000:1000 /app

EXPOSE 8084

# CMD [ "poetry", "run", "lingoWebapp"]
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
