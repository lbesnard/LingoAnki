#!/usr/bin/env python3
"""
Backfill script to add last_reviewed field to all diary days in diary.json files.
Adds the field with null value to maintain compatibility with new features.
"""

import json
import os
import sys
from pathlib import Path
import argparse
import logging

def backfill_lesson_last_reviewed(diary_json_path: str) -> None:
    """Add last_reviewed field to all diary days with null value."""
    diary_path = Path(diary_json_path)
    
    if not diary_path.exists():
        logging.warning(f"diary.json not found at {diary_path}")
        return
    
    # Load diary.json
    with open(diary_path, 'r', encoding='utf-8') as f:
        diary_data = json.load(f)
    
    modified = False
    
    # Add last_reviewed to each diary day if not present
    for day in diary_data.get('diaries', []):
        if 'last_reviewed' not in day:
            day['last_reviewed'] = None
            modified = True
    
    if modified:
        # Write back to file
        with open(diary_path, 'w', encoding='utf-8') as f:
            json.dump(diary_data, f, ensure_ascii=False, indent=2)
        logging.info(f"Backfilled last_reviewed for {len(diary_data.get('diaries', []))} days in {diary_path}")
    else:
        logging.info(f"All days already have last_reviewed field in {diary_path}")

def main():
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
    
    parser = argparse.ArgumentParser(description='Backfill last_reviewed field in diary.json files')
    parser.add_argument('--config-root', default=os.getenv('CONFIG_ROOT', '~/.config/lingoDiary'),
                       help='Root directory containing user configs')
    parser.add_argument('--diary-path', help='Specific diary.json path to process')
    
    args = parser.parse_args()
    
    if args.diary_path:
        # Process single file
        backfill_lesson_last_reviewed(args.diary_path)
    else:
        # Process all users
        config_root = Path(args.config_root).expanduser()
        if not config_root.exists():
            logging.error(f"Config root not found: {config_root}")
            return 1
        
        for user_dir in config_root.iterdir():
            if user_dir.is_dir():
                diary_path = user_dir / 'diary.json'
                if diary_path.exists():
                    backfill_lesson_last_reviewed(str(diary_path))
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
