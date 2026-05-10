#!/bin/bash
# Backfill sentence_input (primary-language translation) for enhanced/future/present
# variant sentences in diary.json for all users.
#
# The 'original' variant is skipped — its sentence_input equals the entry-level
# input_language_sentence which is already stored.
#
# Safe to re-run (skips already-filled fields).
set -e
cd "$(dirname "$0")/.."
for USER in claudine johanne laurent; do
  echo "=== Backfilling variant sentence_input for ${USER} ==="
  docker compose exec lingo-diary python -c "
import logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
from lingoanki.diary import DiaryHandler, _backfill_variant_sentence_inputs
handler = DiaryHandler.__new__(DiaryHandler)
handler.config = DiaryHandler.load_config(handler, '/app/.config/lingoDiary/${USER}/config.yaml')
logger = logging.getLogger('backfill')
_backfill_variant_sentence_inputs(handler.config, '/data/${USER}/diary.json', logger)
"
done
