#!/bin/bash
set -e
cd "$(dirname "$0")/.."
for USER in claudine johanne laurent; do
  docker compose exec lingo-diary python -m lingoanki.migrate_to_json \
    --config /app/.config/lingoDiary/${USER}/config.yaml \
    --output /data/${USER}/diary.json \
    --overwrite
done
