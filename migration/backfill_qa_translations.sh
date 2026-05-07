#!/bin/bash
# Backfill question_input / answer_input translations for all users.
# Runs inside the lingo-diary container; safe to re-run (skips already translated pairs).
set -e
cd "$(dirname "$0")/.."
for USER in claudine johanne laurent; do
  echo "=== Backfilling Q&A translations for ${USER} ==="
  docker compose exec lingo-diary python -c "
import logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
from lingoanki.diary import TprsCreation
tprs = TprsCreation(config_path='/app/.config/lingoDiary/${USER}/config.yaml')
tprs.backfill_qa_translations('/data/${USER}/diary.json')
tprs.stop()
"
done
