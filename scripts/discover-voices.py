#!/usr/bin/env python3
"""
Discover available Piper TTS voices in the installed ovos-tts-plugin-piper.

This script queries the Piper plugin's available voices and organizes them by
language and gender (male/female). The output is saved to scripts/piper_voices.yaml.

⚠️  IMPORTANT: This script MUST be run from INSIDE the Docker container
(where Piper is installed). It does NOT use hardcoded fallbacks.

Usage:
    # From repo root: docker compose exec lingo-diary python scripts/discover-voices.py
    # Or run from inside the container directly: python scripts/discover-voices.py
"""

import sys
import subprocess
import yaml
import json
import os
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
    """Query Piper voices directly from ovos-tts-plugin-piper in Docker.

    This queries the actual installed Piper voice models, not a hardcoded fallback.
    Fails if Docker is not running or the plugin is not available.
    """
    print("Querying Piper voices from Docker container...")

    # Query the actual piper_tts plugin to get real available voices
    query_script = """
import json
from pathlib import Path
try:
    # First try to import from piper_tts directly (system Python in Docker base stage)
    try:
        from piper_tts import get_available_languages
        languages = get_available_languages()
        voices_dict = {}

        if isinstance(languages, dict):
            for lang, variants in languages.items():
                if isinstance(variants, dict):
                    for variant in variants.keys():
                        voice_name = f"{lang}-{variant}"
                        voices_dict[voice_name] = voice_name
    except ImportError:
        # Fallback: try importing from ovos plugin
        from ovos_tts_plugin_piper import PiperTTSPlugin
        voices_dict = {}
        # Try to get models from filesystem
        model_paths = [
            Path.home() / ".local" / "share" / "piper" / "models",
            Path("/app/.local/share/piper/models"),
        ]

        for model_path in model_paths:
            if model_path.exists():
                for model_file in model_path.glob("*.onnx"):
                    voice_name = model_file.stem
                    voices_dict[voice_name] = str(model_file)
                if voices_dict:
                    break

    if voices_dict:
        print(json.dumps({"voices": sorted(voices_dict.keys()), "error": None}))
    else:
        # Last resort: scan models directory
        model_paths = [
            Path.home() / ".local" / "share" / "piper" / "models",
            Path("/app/.local/share/piper/models"),
            Path("/tmp/piper_models"),
        ]

        voices_dict = {}
        for model_path in model_paths:
            if model_path.exists():
                for model_file in model_path.glob("*.onnx"):
                    voice_name = model_file.stem
                    voices_dict[voice_name] = str(model_file)
                if voices_dict:
                    break

        if voices_dict:
            print(json.dumps({"voices": sorted(voices_dict.keys()), "error": None}))
        else:
            print(json.dumps({"voices": [], "error": "No Piper voices found"}))

except Exception as e:
    import traceback
    print(json.dumps({"voices": [], "error": str(e) + ": " + traceback.format_exc()}))
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
            print(f"❌ Docker exec failed: {result.stderr}")
            return None

        # Parse JSON output
        output = result.stdout.strip()
        try:
            data = json.loads(output)
            if data.get("error"):
                error_msg = data["error"]
                # If it's a module not found, give clearer guidance
                if (
                    "No module named" in error_msg
                    or "cannot import" in error_msg.lower()
                ):
                    print(f"❌ Piper not installed: {error_msg}")
                    print()
                    print("SOLUTION: Install Piper in the container:")
                    print(
                        "  docker compose exec lingo-diary pip install ovos-tts-plugin-piper"
                    )
                else:
                    print(f"❌ Error from Docker: {error_msg}")
                return None
            return {"voices": data.get("voices", [])}
        except json.JSONDecodeError:
            print(f"❌ Could not parse Docker output: {output[:200]}")
            return None

    except FileNotFoundError:
        print("❌ docker compose not found. Make sure Docker is running.")
        return None
    except Exception as e:
        print(f"❌ Error querying Docker: {e}")
        return None


# REMOVED: No hardcoded fallback list. Use docker compose exec to query actual voices.


def query_piper_local() -> list:
    """Query Piper voices from local system (when inside Docker or with local install)."""
    try:
        from piper_tts import get_available_languages

        voices_dict = {}
        languages = get_available_languages()

        if isinstance(languages, dict):
            for lang, variants in languages.items():
                if isinstance(variants, dict):
                    for variant in variants.keys():
                        voice_name = f"{lang}-{variant}"
                        voices_dict[voice_name] = voice_name
        return sorted(voices_dict.keys())
    except ImportError:
        # Try scanning model directory
        try:
            from pathlib import Path

            model_paths = [
                Path.home() / ".local" / "share" / "piper" / "models",
                Path("/app/.local/share/piper/models"),
            ]

            voices_dict = {}
            for model_path in model_paths:
                if model_path.exists():
                    for model_file in model_path.glob("*.onnx"):
                        voice_name = model_file.stem
                        voices_dict[voice_name] = str(model_file)
                    if voices_dict:
                        break

            return sorted(voices_dict.keys())
        except Exception:
            return []
    except Exception:
        return []


def discover_voices():
    """Query Piper plugin and organize voices by language and gender.

    Works in three modes:
      1. Inside Docker: Queries piper_tts directly
      2. From host: Queries Docker via docker compose exec
      3. Fallback: Uses existing piper_voices.yaml if discovery fails
    """
    print("=" * 70)
    print("Piper Voice Discovery Tool")
    print("=" * 70)

    # Check if we're inside Docker
    inside_docker = os.path.exists("/.dockerenv")

    if inside_docker:
        print("✓ Running inside Docker container")
        print("Querying Piper directly...")
        voices_list = query_piper_local()
    else:
        print("Running from host machine")
        print("Attempting to query Docker container...")
        result = query_piper_via_docker()
        voices_list = result.get("voices", []) if result else []

    if not voices_list:
        # Fallback: Try to use existing piper_voices.yaml
        script_dir = Path(__file__).parent
        voices_file = script_dir / "piper_voices.yaml"

        if voices_file.exists():
            print(
                "\n⚠️  No voices discovered from Piper, but found existing piper_voices.yaml"
            )
            print("Using cached voice list (may be outdated if you added new voices)")
            print()

            try:
                with open(voices_file, "r") as f:
                    config = yaml.safe_load(f)
                    languages = config.get("languages", {})
                    if languages:
                        return languages
            except Exception as e:
                print(f"⚠️  Could not load existing piper_voices.yaml: {e}")

        # If we get here, discovery failed and we have no fallback
        print("\n❌ FATAL: No voices discovered from Piper.")
        print()
        if inside_docker:
            print("SOLUTION: Ensure Piper and voice models are installed:")
            print("  pip install ovos-tts-plugin-piper")
            print("  piper --download-dir ~/.local/share/piper/models en-US")
        else:
            print("SOLUTION:")
            print("  Option 1: Run discovery INSIDE the container:")
            print(
                "    docker compose exec lingo-diary python scripts/discover-voices.py"
            )
            print()
            print("  Option 2: If Piper voice models are already in the container,")
            print("    check that piper_voices.yaml exists in scripts/")
        print()
        print("NOTE: piper_voices.yaml is already in the repo. This discovery script")
        print(
            "      is only needed when adding NEW Piper voice models to the container."
        )
        sys.exit(1)

    print(f"✓ Found {len(voices_list)} voices")

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

    # Build language name map from discovered languages
    language_name_map = {}
    for lang_code in languages.keys():
        # Default names
        names = {
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
        language_name_map[lang_code] = names.get(lang_code, lang_code)

    # Remove "unknown" gender category if empty, add language names
    organized = {}
    for lang_code in sorted(languages.keys()):
        lang_data = languages[lang_code]
        organized[lang_code] = {"name": language_name_map.get(lang_code, lang_code)}
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
