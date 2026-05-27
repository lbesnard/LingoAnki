# No Python virtualenv inside the Docker image

The Docker image installs all Python dependencies directly into system Python (`POETRY_VIRTUALENVS_CREATE=false`). There is no `.venv` directory in the image.

A venv inside Docker provides no isolation benefit — the container is already isolated. The alternative (venv with `--system-site-packages`) was tried but caused poetry to reinstall large ML packages (whisper, spacy, piper-tts) into the venv even though they were already in system Python, producing a 12 GB layer that rebuilt on every `poetry.lock` change. A trailing `chown -R /app` then snapshotted that layer again (+6 GB). Dropping the venv reduces the rebuild surface from ~18 GB to a few hundred MB for a typical dependency or code change.

The `/opt/lingodiary_venv:/app/.venv` volume mount in the dev `docker-compose.yml` was a leftover from running the webapp directly on the host before Docker was adopted; it has been removed.
