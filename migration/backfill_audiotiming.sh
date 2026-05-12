#!/bin/bash
set -e
cd "$(dirname "$0")/.."
for USER in claudine johanne laurent; do
  docker compose exec lingo-diary python -m lingodiary.audio_timing \
    --config /app/.config/lingoDiary/${USER}/config.yaml \
    --json /data/${USER}/diary.json
done
