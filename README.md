# LingoAnki

This script automates the creation of Anki flashcards from transcripts extracted from audio recordings. It processes
both individual words and sentences, generating transcriptions and translations, and attaching audio to each flashcard.

Features:
- Uses Whisper for transcription and Google Text-to-Speech (TTS) for generating audio.
- Translates words and sentences using GoogleTranslator or ChatGptTranslator.
- Organizes flashcards into two Anki subdecks: one for words and one for sentences.
- Supports multiple languages.

## Installation

```bash
curl -f https://raw.githubusercontent.com/lbesnard/LingoAnki/refs/heads/main/install.sh | bash
```

## Installation with Poetry
Clone the repo
```bash
pip install poetry
poetry install
```

## Example:
```bash
usage: lingoAnki [-h] [--ankideck ANKIDECK] [--input-language INPUT_LANGUAGE] [--target-language TARGET_LANGUAGE] [--output-folder OUTPUT_FOLDER] [--check-sentences] [--model [MODEL]] [--select-files] audio_dir

Automates the creation of Anki flashcards from transcripts extracted from audio recordings.

positional arguments:
  audio_dir             Directory containing the input audio files to process

options:
  -h, --help            show this help message and exit
  --ankideck ANKIDECK, -a ANKIDECK
                        Anki main Deck name
  --input-language INPUT_LANGUAGE, -il INPUT_LANGUAGE
                        Language Code input to parse (en,bo,fr ...)
  --target-language TARGET_LANGUAGE, -tl TARGET_LANGUAGE
                        Language Code output (en,fr ...)
  --output-folder OUTPUT_FOLDER, -o OUTPUT_FOLDER
                        Output folder
  --check-sentences, -c
                        Manually review and modify the transcription
  --model [MODEL], -m [MODEL]
                        Choose a model from the list or use default.
  --select-files, -s    If set, allows you to select files interactively for processing.
```

## When to use
It is especially useful to convert Audio lessons, for example converting all the
audio files from an Assimil course into flashcards. This script is mainly
intended for this

But one could use this script as well to convert podcasts.
