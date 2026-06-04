#!/usr/bin/env python3
"""
Discover available Piper TTS voices in the installed ovos-tts-plugin-piper.

This script queries the Piper plugin's available voices and organizes them by
language and gender (male/female). The output is saved to scripts/piper_voices.yaml.

Usage:
    # From repo root: python scripts/discover-voices.py
    # It will use docker compose exec to query voices inside the container
"""

import sys
import subprocess
import yaml
import json
from pathlib import Path
from collections import defaultdict


def extract_language_and_gender(voice_name: str) -> tuple[str, str]:
    """
    Extract language code and gender from a Piper voice name.

    Expected format: {lang-REGION}[-{gender}[-{variant}[-{speed}]]]
    Examples:
      - "en-US" -> (en, unknown)
      - "en-US-male" -> (en, male)
      - "en-US-female-medium" -> (en, female)
      - "talesyntese-medium" -> (no, unknown) [Norwegian specific]
      - "alan-low" -> (en, male) [assumed from context]

    Returns:
        Tuple of (language_code, gender) where gender is "male", "female", or "unknown"
    """
    parts = voice_name.split("-")

    # Language is always the first part (e.g., "en" from "en-US-male")
    lang = parts[0].lower()

    # Check if there's a gender indicator (typically 2nd or 3rd part)
    gender = "unknown"
    for part in parts[1:]:
        if part.lower() in ("male", "female"):
            gender = part.lower()
            break

    # Heuristic fixes for known voices:
    # "alan-low" is English male
    if voice_name.lower() == "alan-low":
        lang = "en"
        gender = "male"
    # "talesyntese-medium" is Norwegian (female by default in Piper)
    elif "talesyntese" in voice_name.lower():
        lang = "no"
        if gender == "unknown":
            gender = "female"

    return lang, gender


def query_piper_via_docker() -> dict:
    """Query Piper voices by running a script inside the Docker container."""
    print("Querying Piper voices from Docker container...")

    # Create a simple script that scans the Piper models directory
    query_script = """
import json
from pathlib import Path
try:
    # Scan the Piper models directory
    model_paths = [
        Path.home() / ".local" / "share" / "piper" / "models",
        Path("/tmp/piper_models"),
        Path("/app/.local/share/piper/models"),
    ]

    voices_dict = {}
    for model_path in model_paths:
        if model_path.exists():
            for model_file in model_path.glob("*.onnx"):
                voice_name = model_file.stem
                voices_dict[voice_name] = str(model_file)
            if voices_dict:
                break  # Found models, stop searching

    # Also try to use Piper's voice listing if available
    if not voices_dict:
        try:
            import piper_tts
            piper_models = piper_tts.piper_models.get_available_languages()
            if isinstance(piper_models, dict):
                for lang, variants in piper_models.items():
                    if isinstance(variants, dict):
                        for variant in variants.keys():
                            voice_name = f"{lang}-{variant}"
                            voices_dict[voice_name] = voice_name
        except:
            pass

    if voices_dict:
        print(json.dumps({"voices": sorted(voices_dict.keys()), "error": None}))
    else:
        print(json.dumps({"voices": [], "error": "No Piper models found"}))
except Exception as e:
    import traceback
    print(json.dumps({"voices": [], "error": str(e)}))
"""

    try:
        result = subprocess.run(
            [
                "docker",
                "compose",
                "exec",
                "-T",
                "lingo-diary",
                "python",
                "-c",
                query_script,
            ],
            capture_output=True,
            text=True,
            cwd=Path(__file__).parent.parent,  # Run from repo root
        )

        if result.returncode != 0:
            print(f"⚠ Docker query failed, using fallback voice list...")
            return None

        # Parse JSON output
        output = result.stdout.strip()
        try:
            data = json.loads(output)
            if data.get("error"):
                print(f"⚠ {data['error']}, using fallback voice list...")
                return None
            return {"voices": data.get("voices", [])}
        except json.JSONDecodeError:
            print(f"⚠ Could not parse Docker output, using fallback voice list...")
            return None

    except FileNotFoundError:
        print("⚠ docker compose not found, using fallback voice list...")
        return None
    except Exception as e:
        print(f"⚠ {e}, using fallback voice list...")
        return None


# Canonical language code to name mapping (lowercase)
LANGUAGE_NAMES = {
    "en": "english",
    "no": "norwegian",
    "fr": "french",
    "de": "german",
    "es": "spanish",
    "it": "italian",
    "pt": "portuguese",
    "ru": "russian",
    "zh": "chinese",
    "ja": "japanese",
    "ko": "korean",
}

# Known Piper voices as fallback (from Hugging Face Piper repository)
FALLBACK_VOICES = {
    "en": {
        "name": "english",
        "male": [
            "alan-low",
            "en-US-artic-neural-8000hz",
            "en-US-glow-tts",
            "en-US-hfc-neural",
            "en-US-lessac-low",
            "en-US-lessac-medium",
            "en-US-libritts",
            "en-US-ljspeech",
            "en-US-rms-low",
            "en-GB-alba-medium",
            "en-GB-alan-medium",
        ],
        "female": [
            "en-US-amy-medium",
            "en-US-azure-neural",
            "en-US-libritts-high",
            "en-US-ljspeech-high",
            "en-US-ryan-high",
            "en-US-ryan-low",
            "en-US-ryan-medium",
        ],
    },
    "no": {
        "name": "norwegian",
        "female": ["talesyntese-medium"],
    },
    "fr": {
        "name": "french",
        "male": ["fr-FR-gilles-low"],
        "female": ["fr-FR-siwis-medium"],
    },
    "de": {
        "name": "german",
        "male": ["de-DE-karlsson-low", "de-DE-thorsten-high"],
        "female": ["de-DE-eva_k-x-low", "de-DE-eva_k-medium", "de-DE-kerstin-low"],
    },
    "es": {
        "name": "spanish",
        "male": ["es-ES-carlos-low", "es-MX-carlos-low"],
        "female": ["es-ES-tania-medium"],
    },
    "it": {
        "name": "italian",
        "male": ["it-IT-riccardo-x-low"],
        "female": ["it-IT-riccardo_riccardo-x-low"],
    },
    "pt": {
        "name": "portuguese",
        "male": ["pt-BR-faber-medium"],
        "female": ["pt-PT-fernanda-medium"],
    },
    "ru": {
        "name": "russian",
        "male": ["ru-RU-igor-medium"],
        "female": ["ru-RU-natasha-medium"],
    },
    "zh": {"name": "chinese", "female": ["zh-CN-huayan-x-low"]},
    "ja": {"name": "japanese", "female": ["ja-JP-kokoro-medium"]},
    "ko": {"name": "korean", "female": ["ko-KR-kss-medium"]},
}


def discover_voices():
    """Query Piper plugin and build voice index organized by language and gender."""
    print("=" * 70)
    print("Piper Voice Discovery Tool")
    print("=" * 70)

    result = query_piper_via_docker()

    if result is None or not result.get("voices"):
        print("\n→ Using fallback voice list (known Piper voices)")
        # Use fallback voices directly (already organized by language/gender)
        organized = FALLBACK_VOICES.copy()
    else:
        voices_list = result["voices"]
        print(f"✓ Found {len(voices_list)} voices from Docker container")

        # Organize by language and gender
        languages = defaultdict(lambda: {"male": [], "female": [], "unknown": []})

        for voice_name in voices_list:
            lang_code, gender = extract_language_and_gender(voice_name)
            if gender == "unknown":
                # Try to infer from voice name patterns
                if "female" in voice_name.lower() or "woman" in voice_name.lower():
                    gender = "female"
                elif "male" in voice_name.lower() or "man" in voice_name.lower():
                    gender = "male"

            languages[lang_code][gender].append(voice_name)

        # Remove "unknown" gender category if empty, add language names
        organized = {}
        for lang_code in sorted(languages.keys()):
            lang_data = languages[lang_code]
            organized[lang_code] = {"name": LANGUAGE_NAMES.get(lang_code, lang_code)}
            for gender in ["male", "female", "unknown"]:
                if lang_data[gender]:
                    organized[lang_code][gender] = sorted(lang_data[gender])

    # Print processing log
    print("\nVoices organized by language and gender:")
    for lang_code, genders in sorted(organized.items()):
        # Skip "name" field in display
        display_genders = {k: v for k, v in genders.items() if k != "name"}
        for gender, voice_names in sorted(display_genders.items()):
            for voice_name in voice_names:
                print(f"  {voice_name:40} → {lang_code} / {gender}")

    return organized


def save_voices_config(voices: dict):
    """Save the discovered voices to scripts/piper_voices.yaml."""
    # Get the scripts directory (same directory as this file)
    script_dir = Path(__file__).parent
    output_file = script_dir / "piper_voices.yaml"

    config = {
        "languages": voices,
        "_metadata": {
            "description": "Available Piper TTS voices, organized by language and gender.",
            "note": "Regenerate this file by running: python scripts/discover-voices.py",
        },
    }

    try:
        with open(output_file, "w") as f:
            yaml.dump(config, f, default_flow_style=False, sort_keys=False)
        print(f"\n✓ Voices saved to: {output_file}")
        return output_file
    except Exception as e:
        print(f"ERROR: Failed to save voices: {e}")
        sys.exit(1)


if __name__ == "__main__":
    voices = discover_voices()

    if voices:
        output_file = save_voices_config(voices)

        print("\nVoice summary:")
        for lang, genders in sorted(voices.items()):
            total = sum(len(voices) for voices in genders.values())
            print(f"  {lang}: {total} voices")
            for gender, voice_list in sorted(genders.items()):
                if voice_list:
                    print(f"    {gender}: {len(voice_list)} voices")

        print("\n✓ Discovery complete!")
    else:
        sys.exit(1)
