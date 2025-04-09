FROM python:3.10.1

# Set environment variables for Poetry
ENV POETRY_VERSION=1.8.4
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

# RUN apt install ffmpeg

# Set the working directory
WORKDIR /app


# ✅ Only copy dependency files first to use caching and speed up deployment on code change
# COPY pyproject.toml poetry.lock* lingoanki/ /app/

COPY . /app

# ✅ Install dependencies first (cached if no change)
# RUN poetry config virtualenvs.in-project true
RUN poetry install --with dev #--no-interaction # --no-root


# 🔁 Now copy the rest of the app (changing this won't invalidate install layer)
# COPY . /app
#
EXPOSE 8084

# Set environment variables for config and port, with defaults
# ENV CONFIG_PATH=~/.config/lingoDiary/config.yaml
# ENV FLASK_RUN_PORT=8084

CMD ["poetry", "run", "python", "lingoanki/webapp.py"]
# CMD ["/bin/bash"]
