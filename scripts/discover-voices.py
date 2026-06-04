#!/usr/bin/env python3
"""
Discover available Piper TTS voices

This script queries the Piper plugin's available voices and organizes them by
language and gender (male/female). The output is saved to scripts/piper_voices.yaml.

"""

#!/usr/bin/env python3
import sys
import yaml
import requests
from pathlib import Path
from collections import defaultdict

# The definitive source of truth for all Piper voices
PIPER_VOICES_URL = (
    "https://huggingface.co/rhasspy/piper-voices/resolve/main/voices.json"
)


def get_remote_voices_data():
    """Fetch the full registry to access metadata for each voice."""
    print(f"Fetching registry from {PIPER_VOICES_URL}...")
    try:
        response = requests.get(PIPER_VOICES_URL, timeout=10)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"❌ Failed to fetch voice registry: {e}")
        return None


def discover_voices():
    """Download and organize all valid Piper voices using registry metadata."""
    data = get_remote_voices_data()

    if not data:
        print("\n❌ FATAL: Could not retrieve voice registry.")
        sys.exit(1)

    # languages[family][gender] = [voice_names...]
    languages = defaultdict(lambda: {"male": [], "female": [], "unknown": []})
    family_names = {}  # Stores {family: name_english}

    for voice_name, metadata in data.items():
        # 1. Use the 'family' key for language grouping
        family = metadata.get("language", {}).get("family", "unknown").lower()

        # 2. Get English name for the language
        if family not in family_names:
            family_names[family] = (
                metadata.get("language", {}).get("name_english", family).lower()
            )

        # 3. Get gender
        gender = metadata.get("gender", "unknown").lower()

        languages[family][gender].append(voice_name)

    # Build the final structure
    organized = {}
    for family in sorted(languages.keys()):
        organized[family] = {"name": family_names[family]}
        for gender in ["male", "female", "unknown"]:
            if languages[family][gender]:
                organized[family][gender] = sorted(languages[family][gender])

    return organized


def save_voices_config(voices: dict):
    # Uses .cwd() to work in both scripts and Jupyter
    output_file = Path.cwd() / "piper_voices.yaml"

    config = {"languages": voices, "_metadata": {"source": PIPER_VOICES_URL}}

    with open(output_file, "w") as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False)
    print(f"\n✓ Saved to: {output_file}")


if __name__ == "__main__":
    voices_data = discover_voices()
    if voices_data:
        save_voices_config(voices_data)
        print("\n✓ Discovery complete!")
