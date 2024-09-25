# LingoAnki

This script automates the creation of Anki flashcards from transcripts extracted from audio recordings. It processes
both individual words and sentences, generating transcriptions and translations, and attaching audio to each flashcard.

Features:
- Uses Whisper for transcription and Google Text-to-Speech (TTS) for generating audio.
- Translates words and sentences using GoogleTranslator or ChatGptTranslator.
- Organizes flashcards into two Anki subdecks: one for words and one for sentences.
- Supports multiple languages.

##Example:
```bash
python lingoAnki.py path_to_audio_files --ankideck "MyDeckName" --input-language "en" --target-language "fr" --output-folder "output_directory"
```

## When to use
It is especially useful to convert Audio lessons, for example converting all the
audio files from an Assimil course into flashcards. This script is mainly
intended for this

But one could use this script as well to convert podcasts.
