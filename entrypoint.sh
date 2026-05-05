#!/bin/bash
set -e

LOCKFILE="/app/poetry.lock"
HASHFILE="/app/.poetry.lock.sha256"

# Compute current hash
CURRENT_HASH=$(sha256sum "$LOCKFILE" | awk '{print $1}')

# Check if venv exists and hash matches
if [ -f "$HASHFILE" ] && [ -d /app/.venv ]; then
  CACHED_HASH=$(cat "$HASHFILE")
  if [ "$CACHED_HASH" = "$CURRENT_HASH" ]; then
    echo "✓ poetry.lock unchanged. Skipping install."
  else
    echo "⚠ poetry.lock changed. Reinstalling dependencies..."
    poetry install --with dev
    echo "$CURRENT_HASH" >"$HASHFILE"
  fi
else
  echo "🆕 No hash or venv found. Installing dependencies..."
  poetry install --with dev
  echo "$CURRENT_HASH" >"$HASHFILE"
fi

exec poetry run lingoWebapp
