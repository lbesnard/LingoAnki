#!/bin/bash
# restore_and_remigrate.sh
#
# Restores TPRS markdown and audio from the pre-May-6 backup (~/lingodiary),
# then rebuilds diary.json from the original (correct) files.
#
# Steps performed:
#   0. Save SRS scores from current diary.json  →  /tmp/srs_scores.json
#   1. Restore TPRS/*.md and TPRS/*.mp3 from backup
#   2. Delete stale SEGMENTS/ directories and diary.json
#   3. Run convert_md_json.sh  (rebuilds diary.json from original markdown)
#   4. Re-apply saved SRS scores into the new diary.json
#
# After this script finishes, run manually:
#   migration/backfill_qa_translations.sh   (translates correct Q&A text, ~$2-5 OpenAI)
#   migration/backfill_audiotiming.sh       (regenerates per-sentence segments via TTS)

set -euo pipefail
cd "$(dirname "$0")/.."

BACKUP_ROOT="${HOME}/lingodiary"
DATA_ROOT="${HOME}/Documents/lingodiary"
SRS_BACKUP="/tmp/srs_scores.json"
USERS=(laurent claudine johanne)

if [[ ! -d "$BACKUP_ROOT" ]]; then
  echo "ERROR: Backup directory not found: $BACKUP_ROOT"
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 0 — Export SRS scores from all users' current diary.json
# ---------------------------------------------------------------------------
echo "=== Step 0: Exporting SRS scores ==="
docker compose exec lingo-diary python3 -c "
import json, os

users = ['laurent', 'claudine', 'johanne']
all_scores = {}

for user in users:
    path = f'/data/{user}/diary.json'
    if not os.path.exists(path):
        print(f'  {user}: no diary.json found, skipping')
        continue
    with open(path) as f:
        data = json.load(f)
    scores = []
    for day in data.get('diaries', []):
        date = day.get('date', '')
        for i, entry in enumerate(day.get('entries', [])):
            for variant, lesson in entry.get('lessons', {}).items():
                if isinstance(lesson, dict) and lesson.get('mastery_score', 0):
                    scores.append({
                        'date': date,
                        'entry_index': i,
                        'variant': variant,
                        'lesson': lesson,
                    })
    all_scores[user] = scores
    print(f'  {user}: {len(scores)} SRS score entries saved')

with open('${SRS_BACKUP}', 'w') as f:
    json.dump(all_scores, f, indent=2, ensure_ascii=False)
print(f'Scores written to ${SRS_BACKUP}')
"

# ---------------------------------------------------------------------------
# Step 1 — Restore TPRS files from backup
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 1: Restoring TPRS files from backup ==="
for USER in "${USERS[@]}"; do
  BACKUP_TPRS="${BACKUP_ROOT}/${USER}/TPRS"
  CURRENT_TPRS="${DATA_ROOT}/${USER}/TPRS"

  if [[ ! -d "$BACKUP_TPRS" ]]; then
    echo "  WARNING: No backup TPRS dir for ${USER}: $BACKUP_TPRS — skipping"
    continue
  fi

  echo "  ${USER}: restoring *.md and *.mp3 ..."
  rsync -av --include="*.md" --include="*.mp3" --exclude="*" \
    "${BACKUP_TPRS}/" "${CURRENT_TPRS}/"

  echo "  ${USER}: restore done."
done

# ---------------------------------------------------------------------------
# Step 2 — Delete stale SEGMENTS and diary.json
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 2: Removing stale SEGMENTS and diary.json ==="
for USER in "${USERS[@]}"; do
  SEGMENTS_DIR="${DATA_ROOT}/${USER}/TPRS/SEGMENTS"
  DIARY_JSON="${DATA_ROOT}/${USER}/diary.json"

  if [[ -d "$SEGMENTS_DIR" ]]; then
    echo "  ${USER}: removing SEGMENTS/ ..."
    rm -rf "$SEGMENTS_DIR"
    echo "  ${USER}: SEGMENTS removed."
  else
    echo "  ${USER}: no SEGMENTS dir found, skipping."
  fi

  if [[ -f "$DIARY_JSON" ]]; then
    echo "  ${USER}: removing diary.json ..."
    rm "$DIARY_JSON"
    echo "  ${USER}: diary.json removed."
  else
    echo "  ${USER}: no diary.json found, skipping."
  fi
done

# ---------------------------------------------------------------------------
# Step 3 — Rebuild diary.json from original markdown
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 3: Running convert_md_json.sh ==="
bash migration/convert_md_json.sh

# ---------------------------------------------------------------------------
# Step 4 — Re-apply SRS scores
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 4: Re-applying SRS scores ==="
docker compose exec lingo-diary python3 -c "
import json, os

with open('${SRS_BACKUP}') as f:
    all_scores = json.load(f)

for user, scores in all_scores.items():
    if not scores:
        print(f'  {user}: no scores to apply')
        continue

    path = f'/data/{user}/diary.json'
    if not os.path.exists(path):
        print(f'  {user}: diary.json not found after migration — skipping score re-apply')
        continue

    with open(path) as f:
        data = json.load(f)

    # Build a lookup: date → list of entries
    day_map = {day['date']: day for day in data.get('diaries', [])}

    applied = 0
    skipped = 0
    for s in scores:
        date = s['date']
        idx = s['entry_index']
        variant = s['variant']
        lesson = s['lesson']

        day = day_map.get(date)
        if day is None:
            print(f'  {user}: WARNING date {date} not found in new diary.json — skipping')
            skipped += 1
            continue

        entries = day.get('entries', [])
        if idx >= len(entries):
            print(f'  {user}: WARNING entry index {idx} out of range for {date} — skipping')
            skipped += 1
            continue

        entry = entries[idx]
        if 'lessons' not in entry:
            entry['lessons'] = {}
        entry['lessons'][variant] = lesson
        applied += 1

    with open(path, 'w') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print(f'  {user}: applied {applied} scores, skipped {skipped}')

print('SRS scores re-applied.')
"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "=== Restore & re-migration complete ==="
echo ""
echo "Next steps (run these manually when ready):"
echo "  1. migration/backfill_qa_translations.sh   # translates Q&A from correct original text"
echo "  2. migration/backfill_audiotiming.sh        # regenerates per-sentence segments via TTS"
