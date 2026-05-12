#!/bin/bash
# Backfill question_input / answer_input translations for all users.
# Uses the standalone _backfill_qa_translations function — does NOT instantiate
# TprsCreation, so no markdown files are created as side effects.
# Safe to re-run (skips already translated pairs).
set -e
cd "$(dirname "$0")/.."
for USER in claudine johanne laurent; do
  echo "=== Backfilling Q&A translations for ${USER} ==="
  docker compose exec lingo-diary python -c "
import logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
from lingodiary.diary import DiaryHandler, _backfill_qa_translations
handler = DiaryHandler.__new__(DiaryHandler)
handler.config = DiaryHandler.load_config(handler, '/app/.config/lingoDiary/${USER}/config.yaml')
logger = logging.getLogger('backfill')
_backfill_qa_translations(handler.config, '/data/${USER}/diary.json', logger)
"
done
