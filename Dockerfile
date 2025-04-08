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

# Set the working directory
WORKDIR /app

COPY . /app

# Install dependencies
RUN poetry install --with dev #--no-interaction # --no-root

EXPOSE 8084

# Set environment variables for config and port, with defaults
ENV CONFIG_PATH=~/.config/lingoDiary/config.yaml
ENV FLASK_RUN_PORT=8084

# Run the application using Poetry
# CMD ["poetry", "run", "flask", "run", "--host=0.0.0.0", "--port", "${FLASK_RUN_PORT}"]
# CMD ["poetry", "run", "flask", "run", "--host=0.0.0.0", "--port", "${FLASK_RUN_PORT}"]
#
# ENV FLASK_APP=lingoanki/webapp.py
# CMD ["poetry", "run", "flask", "run", "--host=0.0.0.0", "--port", "${FLASK_RUN_PORT}"]

CMD ["poetry", "run", "python", "lingoanki/webapp.py"]
