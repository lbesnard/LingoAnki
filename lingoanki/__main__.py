#!/usr/bin/env python3
"""
Script Explanation:

This script automates the creation of Anki flashcards from transcripts extracted from audio recordings. It processes
both individual words and sentences, generating transcriptions and translations, and attaching audio to each flashcard.

Features:
- Uses Whisper for transcription and Google Text-to-Speech (TTS) for generating audio.
- Translates words and sentences using GoogleTranslator or ChatGptTranslator.
- Organizes flashcards into two Anki subdecks: one for words and one for sentences.
- Supports multiple languages.

Example:
```bash
python lingoAnki.py path_to_audio_files --ankideck "MyDeckName" --input-language "en" --target-language "fr" --output-folder "output_directory"
```
"""

import argparse
import hashlib
import json
import logging
import os
import re
import shutil
import tempfile
import inquirer

import genanki
import spacy
import spacy.cli
import whisper
from deep_translator import GoogleTranslator, ChatGptTranslator
from gtts import gTTS
from pydub import AudioSegment

ANKICONNECT_URL = "http://localhost:8765"

# Create unique model ids for different card types
WORD_CARD_MODEL_ID = 123456789
SENTENCE_CARD_MODEL_ID = 987654321
COMBINED_SENTENCES_MODEL_ID = 987654322

WHISPER_MODELS = ["tiny", "medium", "large-v2", "large-v3"]

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


# Define a mapping of language names to spaCy model names
# see https://spacy.io/models
language_to_model = {
    "no": "nb_core_news_lg",
    "en": "en_core_web_lg",
    "ger": "de_core_news_lg",
    "fr": "fr_core_news_lg",
    # Add other languages and models as needed
}

# TODO: remove maybe as was robotic
language_to_pyttsx3 = {"no": "nb", "fr": "fr-fr", "en": "en-gb"}

# TODO: investigate, not for all languages, for example not for bokmal
language_to_tts = {"no": "tts_models/nb/nb_model", "fr": "tts_models/fr/css10"}


def download_model_for_language(language_name):
    """
    Downloads the spaCy model for the specified language.

    Args:
        language_name (str): The name of the language for which to download the model.

    Returns:
        str: The name of the downloaded model, or None if no model is available.
    """
    model_name = language_to_model.get(language_name.lower())

    if model_name:
        installed_models = spacy.util.get_installed_models()

        if model_name in installed_models:
            logger.info(f"Model for {language_name} is already installed.")
        else:
            logger.info(
                f"Model for {language_name} not found. Downloading: {model_name}"
            )
            spacy.cli.download(model_name)
        return model_name
    else:
        logger.info(f"No model found for language: {language_name}")
        return None


def generate_unique_id(input_string, length=9):
    """
    Generates a unique ID based on a hash of the input string.

    Args:
        input_string (str): The string to hash.
        length (int): The length of the unique ID to generate (default: 9).

    Returns:
        int: A unique ID of the specified length.
    """
    # Hash the string using SHA256
    hash_object = hashlib.sha256(input_string.encode("utf-8"))

    # Convert the hash to an integer
    hash_int = int(hash_object.hexdigest(), 16)

    # Take a portion of the integer and ensure it's the desired length
    unique_id = hash_int % (10**length)

    return unique_id


def process_words_with_audio(words_list, audio_dir, input_language="no"):
    """
    Processes words and generates audio if necessary, returning a dictionary of words and audio paths.

    Args:
        words_list (list): List of words to process.
        audio_dir (str): Directory to save the generated audio.
        input_language (str): The language code for TTS (default: 'no').

    Returns:
        dict: Dictionary mapping words to their audio file paths.
    """
    audio_paths = {}  # Dictionary to hold words and their audio file paths

    for word in words_list:
        audio_fp = handle_missing_audio(word, audio_dir, input_language)
        audio_paths[word] = audio_fp

    return audio_paths


def handle_missing_audio(word, audio_dir, language_code="no"):
    """
    Generates TTS audio for a word and saves it to the specified directory.

    Args:
        word (str): The word for which to generate audio.
        audio_dir (str): Directory to save the audio file.
        language_code (str): The language code for the TTS engine (default: 'no').

    Returns:
        str: The file path to the generated audio.
    """

    # import ipdb;ipdb.set_trace()
    # tts = TTS(model_name=language_to_tts[language_code], progress_bar=True)
    # tts = TTS("tts_models/multilingual/multi-dataset/xtts_v2").to(device)
    # tts = TTS(model_name="vocoder_models/en/ljspeech/hifigan_v2", progress_bar=True)

    # Initialize TTS engine
    # engine = pyttsx3.init()

    # List all available voices
    # voices = engine.getProperty('voices')

    # Select a voice based on language code
    #     selected_voice = None
    # for voice in voices:
    # # Check if the voice's language matches the desired language code
    # if language_code in voice.languages:
    # selected_voice = voice
    # break

    # if selected_voice:
    # engine.setProperty('voice', selected_voice.id)
    # print(f"Selected voice: {selected_voice.name}")
    # else:
    # print(f"No voice found for language code: {language_code}. Using default voice.")

    # Define file path
    # wave_fp = tempfile.NamedTemporaryFile(suffix='.wav', dir=audio_dir, delete=False).name
    # audio_fp = wave_fp.replace('.wav', '.mp3')

    # tts.tts_to_file(text=word, file_path=wave_fp)
    # tts.tts_to_file(text=word, speaker_wav="my/cloning/audio.wav", language=language_code, file_path=wave_fp)

    # # Convert WAV to MP3
    # audio = AudioSegment.from_wav(wav_file)
    # audio.export(audio_fp, format="mp3")

    #  engine.save_to_file(word, audio_fp)
    # engine.runAndWait()
    #  engine.stop()
    # audio_fp = tempfile.NamedTemporaryFile(suffix='.mp3', dir=audio_dir, delete=False).name
    audio_fp = os.path.join(audio_dir, f"{word.replace(' ', '_')}.mp3")
    tts = gTTS(word, lang=language_code, tld="com.au")
    tts.save(audio_fp)

    logger.info(f"Generated TTS audio for: {word}")
    return audio_fp


def transcript_audio(audio_fp, input_language="no", check=False, model="large-v3"):
    """
    Transcribes an audio file using the Whisper model.

    Args:
        audio_fp (str): The path to the audio file.
        input_language (str): The language of the audio (default: 'no').
        check (bool): If True, manually review and modify transcription (default: False).
        model (str): The Whisper model to use (default: 'large-v3').

    Returns:
        dict: The transcription result including segments.
    """
    model = whisper.load_model(model)
    # model = whisper.load_model("large-v2")
    audio = whisper.load_audio(audio_fp)
    mel = whisper.log_mel_spectrogram(audio).to(model.device)
    # import ipdb; ipdb.set_trace()

    transcription_options = {
        "language": input_language,
        "beam_size": 2,
        "best_of": 3,
        "word_timestamps": True,
        "no_speech_threshold": 0.4,  # Adjusted
        "logprob_threshold": -0.3,  # Adjusted
        "compression_ratio_threshold": 2.0,  # Adjusted
        "condition_on_previous_text": False,  # Use context from previous text
        "verbose": True,
    }

    # Transcribe the audio
    transcription = model.transcribe(audio, **transcription_options)

    # Filter out segments with a duration less than 200ms (0.2 seconds)
    filtered_segments = []

    for segment in transcription["segments"]:
        start_time = segment["start"]
        end_time = segment["end"]
        duration = end_time - start_time

        # Check if duration is 200ms or more
        if duration >= 0.3:
            filtered_segments.append(segment)

    transcription["segments"] = filtered_segments

    # Adjust the end time of each segment
    additional_time = 0.500
    for idx, segment in enumerate(transcription["segments"]):
        # Adjust the start time
        if idx > 0:
            previous_segment_end = transcription["segments"][idx - 1]["end"]
            segment["start"] = max(
                segment["start"] - additional_time / 3, previous_segment_end
            )
        else:
            # For the first segment, just subtract the additional time
            segment["start"] = max(
                segment["start"] - additional_time / 3, 0
            )  # Ensure start time doesn't go below 0

        # Increase the end time of each segment by additional_time, but ensure it does not overlap with the next segment
        if idx < len(transcription["segments"]) - 1:
            next_segment_start = transcription["segments"][idx + 1]["start"]
            segment["end"] = min(segment["end"] + additional_time, next_segment_start)
        else:
            # For the last segment, just add the additional time
            segment["end"] = segment["end"] + additional_time

    # If check flag is set, manually review each sentence
    if check:
        logger.info("Review the transcription below:")
        for idx, segment in enumerate(
            transcription["segments"], start=1
        ):  # start=1 for numbering from 1
            logger.info(f"Sentence {idx}: {segment['text']}")
            modified = input(
                f"Press Enter to keep Sentence {idx}, or type a new sentence to modify: "
            ).strip()

            if modified:  # If the user provides a new sentence, overwrite the original
                transcription["segments"][idx - 1][
                    "text"
                ] = modified  # idx-1 to match zero-indexed list
            print()  # For spacing between sentences

    return transcription


def split_audio_sentences(audio_fp, whisper_transcription):
    """
    Splits an audio file into individual sentences based on timestamps from a Whisper transcription.

    This function uses Whisper transcription results to extract the start and end timestamps of each sentence.
    It splits the audio file into smaller audio files for each sentence, saving them as MP3 files.

    Args:
        audio_fp (str): The file path of the input audio file.
        whisper_transcription (dict): The Whisper transcription containing sentence start and end timestamps.

    Returns:
        list: A list of file paths for the split sentence audio clips.
    """
    audio = AudioSegment.from_file(audio_fp)
    sentence_timestamps = whisper_transcription[
        "segments"
    ]  # Assuming Whisper returns timestamps
    tmpdir = tempfile.mkdtemp()

    sentence_audio_fp_list = []
    for idx, segment in enumerate(sentence_timestamps):
        start = segment["start"] * 1000  # in milliseconds
        end = segment["end"] * 1000
        sentence_audio = audio[start:end]
        sentence_audio_fp = os.path.join(tmpdir, f"sentence_{idx}.mp3")
        sentence_audio.export(sentence_audio_fp, format="mp3")
        sentence_audio_fp_list.append(sentence_audio_fp)
    return sentence_audio_fp_list


def create_list_word_verbs(transcription, input_language="no"):
    """
    Extracts and returns a list of lemmatized verbs, nouns, adjectives, adverbs, and other tokens from a transcription.

    This function processes the provided transcription using the spaCy model for the specified input language,
    identifies the part of speech for each token (verb, noun, adjective, adverb), and lemmatizes them to create a
    list of unique words.

    Args:
        transcription (dict): The transcription containing the text to be analyzed.
        input_language (str): The language code of the input text for spaCy model loading (default: 'no' for Norwegian).

    Returns:
        list: A list of unique, cleaned, and lemmatized words (verbs, nouns, adjectives, adverbs, etc.).
    """
    language_model = download_model_for_language(input_language)
    nlp = spacy.load(language_model)
    sentence = transcription["text"]
    doc = nlp(sentence)
    infinitive_verbs, singular_nouns, base_adjectives, adverbs, other_tokens = (
        [],
        [],
        [],
        [],
        [],
    )

    for token in doc:
        if token.pos_ == "VERB":
            if input_language == "no":
                infinitive_verbs.append("å " + token.lemma_)
            else:
                infinitive_verbs.append(token.lemma_)
        elif token.pos_ == "NOUN":
            singular_nouns.append(token.lemma_)
        elif token.pos_ == "ADJ":
            base_adjectives.append(token.lemma_)
        elif token.pos_ == "ADV":
            adverbs.append(token.lemma_)
        elif token.is_alpha:  # Ensures the token is made up of letters only
            other_tokens.append(token.lemma_)

    list_words = (
        infinitive_verbs + singular_nouns + adverbs + base_adjectives + other_tokens
    )
    list_words = [word.lower() for word in list_words]

    unique_list = [*{*list_words}]
    unique_list = clean_and_lemmatize(unique_list)
    unique_list = [word for word in unique_list if word.isalpha()]

    return unique_list


def clean_and_lemmatize(word_list):
    """
    Cleans and removes duplicates from a list of words.

    This function strips whitespace from each word in the provided list and then removes any duplicates
    by converting the list to a set.

    Args:
        word_list (list): A list of words to clean and de-duplicate.

    Returns:
        list: A cleaned and de-duplicated list of words.
    """
    cleaned_words = [word.strip() for word in word_list]
    return list(set(cleaned_words))  # Remove duplicates


def translate_list(list_words, input_language="no", target_language="en"):
    """
    Translates a list of words from the input language to the target language using OpenAI's ChatGPT translator
    or Google Translator as a fallback.

    This function checks for an OpenAI API key in the 'openai.json' file. If available, it uses the ChatGptTranslator
    to translate the list of words. If the translation fails or the API key is unavailable, it falls back to the
    GoogleTranslator.

    Args:
        list_words (list): The list of words to translate.
        input_language (str): The language code of the source language (default: 'no' for Norwegian).
        target_language (str): The language code for the target language (default: 'en' for English).

    Returns:
        list: A list of translated words.
    """
    # Get the path to the openai.json file (in the same directory as the script)
    file_path = os.path.join(os.path.dirname(__file__), "openai.json")
    if os.path.exists(file_path):
        # Load the JSON file
        with open(file_path, "r") as file:
            data = json.load(file)

        # Extract the OpenAI API key and assign it to a variable
        api_key = data["api_key"]
        try:
            translated = ChatGptTranslator(
                api_key=api_key, source=input_language, target=target_language
            ).translate_batch(list_words)
        except Exception as err:
            logger.info(
                f"ChatGPT translator failed: {err}. Fallback using Google Translator"
            )
            translated = GoogleTranslator(
                source=input_language, target=target_language
            ).translate_batch(list_words)
    else:
        logger.info("Using Google Translator")
        translated = GoogleTranslator(
            source=input_language, target=target_language
        ).translate_batch(list_words)

    return translated


def sentences_list(transcription):
    """
    Extracts sentences from a Whisper transcription.

    This function takes a transcription result from Whisper and extracts the text of each segment as a sentence.

    Args:
        transcription (dict): The Whisper transcription containing text segments.

    Returns:
        list
    """
    sentences = [segment["text"] for segment in transcription["segments"]]
    return sentences


def add_audio(media_file):
    """
    Formats the media file path for use in Anki flashcards.

    This function takes the path to a media file and returns a formatted string that Anki can use to include audio in a flashcard.

    Args:
        media_file (str): The file path of the audio file.

    Returns:
        str: A formatted string to include audio in Anki flashcards.
    """
    return f"[sound:{os.path.basename(media_file)}]"


def create_word_model():
    """
    Creates an Anki model for word flashcards.

    This function defines an Anki model for flashcards that display a word, its translation, and an audio clip.
    The model includes two templates: one to show the word and ask for the translation, and another to show
    the translation and ask for the word.

    Returns:
        genanki.Model: A model for generating word flashcards in Anki.
    """
    return genanki.Model(
        WORD_CARD_MODEL_ID,
        "Word Flashcards Model",
        fields=[
            {"name": "Word"},
            {"name": "Translation"},
            {"name": "Audio"},
        ],
        templates=[
            {
                "name": "Word to Translation",
                "qfmt": "{{Word}}<br>{{Audio}}",
                "afmt": """
                {{FrontSide}}<hr id="answer">

                <div style="background-color:#f0f0f0; padding:10px; border-radius:8px;">
                  <div style="color:#009933; font-size:1em;">{{Translation}}</div>
                </div>
                """,
            },
            {
                "name": "Translation to Word",
                "qfmt": "{{Translation}}",
                "afmt": """
                {{FrontSide}}<hr id="answer">
                <div style="background-color:#f0f0f0; padding:10px; border-radius:8px;">
                  <div style="color:#009933; font-size:1em;">{{Word}}<br>{{Audio}}
                </div>
                </div>
                """,
            },
        ],
        css="""
        .card {
            font-family: arial;
            font-size: 20px;
            text-align: center;
            color: black;
            background-color: white;
        }
        .button {
            padding: 10px;
        }
        """,
    )


def create_sentence_model():
    return genanki.Model(
        SENTENCE_CARD_MODEL_ID,
        "Sentence Flashcards Model",
        fields=[
            {"name": "Sentence"},
            {"name": "Translation"},
            {"name": "Audio"},
        ],
        templates=[
            {
                "name": "Sentence to Translation",
                "qfmt": "{{Audio}}",
                "afmt": """
            <div style="font-weight:bold; font-size:1.2em; color:#0073e6;">
              {{FrontSide}}<hr id="answer">
            </div>
            <div style="background-color:#f0f0f0; padding:10px; border-radius:8px;">
              <div style="color:#333; font-size:1em;">{{Sentence}}</div>
              <hr style="border: 1px solid #0073e6;">
              <div style="color:#009933; font-size:1em;">{{Translation}}</div>
            </div>
            """,
            },
            {
                "name": "Translation to Sentence",
                "qfmt": "{{Translation}}",
                "afmt": """
            {{FrontSide}}<hr id="answer">{{Audio}}
            <div style="background-color:#f0f0f0; padding:10px; border-radius:8px;">
              <div style="color:#009933; font-size:1em;">{{Sentence}}</div>
            </div>
            """,
            },
        ],
        css="""
        .card {
            font-family: arial;
            font-size: 20px;
            text-align: center;
            color: black;
            background-color: white;
        }
        .button {
            padding: 10px;
        }
        """,
    )


def create_combined_sentences_model():
    return genanki.Model(
        COMBINED_SENTENCES_MODEL_ID,
        "Combined Sentences Flashcards Model",
        fields=[
            {"name": "CombinedSentences"},
            {"name": "Translation"},
            {"name": "Audio"},
        ],
        templates=[
            {
                "name": "Combined Sentences Card",
                "qfmt": """
                    {{#CombinedSentences}}
                    {{CombinedSentences}}<br>
                    {{/CombinedSentences}}
                    <br>
                """,
                "afmt": '{{FrontSide}}<hr id="answer">{{Translation}}',
            }
        ],
        css="""
        .card {
            font-family: arial;
            font-size: 20px;
            text-align: center;
            color: black;
            background-color: white;
        }
        .button {
            padding: 10px;
        }
        """,
    )


def create_flashcards(word_dict, sentence_dict, deck_name="Language Flashcards"):

    lesson_name = deck_name.split("::")[1].replace(" ", "_")
    main_deck_name = deck_name.split("::")[0].replace(" ", "_")

    # Create unique IDs for the subdecks
    deck_words_name = f"{deck_name} Words"
    deck_sentences_name = f"{deck_name} Sentences"

    deck_words_unique_id = generate_unique_id(deck_words_name)
    deck_sentences_unique_id = generate_unique_id(deck_sentences_name)

    # Create two subdecks: one for words and one for sentences
    deck_words = genanki.Deck(deck_words_unique_id, deck_words_name)
    deck_sentences = genanki.Deck(deck_sentences_unique_id, deck_sentences_name)

    word_model = create_word_model()
    sentence_model = create_sentence_model()
    combined_model = create_combined_sentences_model()
    media_files = []

    # Add word flashcards to the 'Words' subdeck
    for word, data in word_dict.items():
        audio_fp = data["audio_fp"]
        translation = data["translated_word"]
        note = genanki.Note(
            model=word_model,
            fields=[word, translation, add_audio(audio_fp)],
            tags=["lingoAnki_words_verbs_adjs", main_deck_name, lesson_name],
        )
        deck_words.add_note(note)
        media_files.append(audio_fp)

    # Add individual sentence flashcards to the 'Sentences' subdeck
    for sentence, data in sentence_dict.items():
        audio_fp = data["audio_fp"]
        sentence_number = data["sentence_number"]
        translated_sentence = data["translated_sentence"]
        note = genanki.Note(
            model=sentence_model,
            fields=[
                f"{sentence_number:03d}. {sentence}",
                translated_sentence,
                add_audio(audio_fp),
            ],
            tags=["lingoAnki_individual_sentence", main_deck_name, lesson_name],
        )
        deck_sentences.add_note(note)
        media_files.append(audio_fp)

    # Prepare combined sentences with individual play buttons
    combined_sentences = f"{lesson_name}<br><br>"
    combined_audio = ""
    sorted_sentences = sorted(
        sentence_dict.items(), key=lambda item: item[1]["sentence_number"]
    )

    for sentence, data in sorted_sentences:
        sentence_number = data["sentence_number"]
        audio_fp = data["audio_fp"]
        combined_sentences += (
            f"<b>{sentence_number:03d}. {add_audio(audio_fp)} {sentence}</b><br>"
        )
        combined_audio += f"{sentence_number:03d}. {add_audio(audio_fp)} <br>"

    combined_translation = " ".join(
        f"{i + 1}. {data['translated_sentence']} <br>"
        for i, (_, data) in enumerate(sorted_sentences)
    )

    # Add the combined sentences to the 'Sentences' subdeck
    combined_note = genanki.Note(
        model=combined_model,
        fields=[combined_sentences, combined_translation, combined_audio],
        tags=["lingoAnki_combined_sentences", main_deck_name, lesson_name],
    )
    deck_sentences.add_note(combined_note)

    # Return both subdecks in a list and the media files
    return [deck_words, deck_sentences], media_files


def sorted_alphanumeric(data):
    def convert(text):
        return int(text) if text.isdigit() else text.lower()

    def alphanum_key(key):
        return [convert(c) for c in re.split("([0-9]+)", key)]

    return sorted(data, key=alphanum_key)


def get_mp3_files(audio_dir):
    mp3_files = []
    # Walk through all directories and subdirectories
    for root, dirs, files in os.walk(audio_dir):
        # Filter files that end with .mp3 and append full path
        mp3_files.extend(os.path.join(root, f) for f in files if f.endswith(".mp3"))

    return sorted_alphanumeric(mp3_files)


def extract_lesson_number(filename):
    # Regular expression to find 1 to 3 digit numbers, possibly with leading zeros
    # match = re.search(r'\b(0*\d{1,3})\b', filename)
    match = re.search(r"(?<!\w)(0*\d{1,3})(?!\w)", filename)

    if match:
        # Convert the matched string to an integer to remove leading zeros
        return int(match.group(1))
    else:
        return None  # Return None if no number is found


def main():
    parser = argparse.ArgumentParser(
        description="Automates the creation of Anki flashcards from transcripts extracted from audio recordings."
    )
    parser.add_argument(
        "audio_dir",
        type=str,
        help="Directory containing the input audio files to process",
    )
    parser.add_argument(
        "--ankideck",
        "-a",
        type=str,
        default="MyLanguageCards",
        help="Anki main Deck name",
    )
    parser.add_argument(
        "--input-language",
        "-il",
        type=str,
        default="no",
        help="Language Code input to parse (en,bo,fr ...)",
    )
    parser.add_argument(
        "--target-language",
        "-tl",
        type=str,
        default="en",
        help="Language Code output (en,fr ...)",
    )
    parser.add_argument(
        "--output-folder", "-o", type=str, default="", help="Output folder"
    )
    parser.add_argument(
        "--check-sentences",
        "-c",
        action="store_true",
        help="Manually review and modify the transcription",
    )
    # Add the --model argument with default value
    parser.add_argument(
        "--model",
        "-m",
        nargs="?",  # This makes the argument optional with a default
        const=True,  # This will trigger inquirer if the flag is used without a value
        default="large-v3",  # Default value if not specified
        help="Choose a model from the list or use default.",
    )
    parser.add_argument(
        "--select-files",
        "-s",
        action="store_true",
        help="If set, allows you to select files interactively for processing.",
    )
    args = parser.parse_args()

    # Set default to a temporary directory if not specified
    if not args.output_folder:
        args.output_folder = tempfile.mkdtemp()

    # Create the output folder if it does not exist
    os.makedirs(args.output_folder, exist_ok=True)

    # If the model argument is set
    if args.model is True:
        # Use inquirer to display a list of models for the user to choose from
        questions = [
            inquirer.List(
                "selected_model",
                message="Choose a model",
                choices=WHISPER_MODELS,
            )
        ]
        answers = inquirer.prompt(questions)
        selected_model = answers["selected_model"]

        # Output the chosen model
        print(f"Model selected: {selected_model}")
    else:
        print("No model selected. Use --model to select one.")

    # Get the list of .mp3 files in the folder, sorted alphanumerically
    mp3_files = get_mp3_files(args.audio_dir)

    if args.select_files:
        questions = [
            inquirer.Checkbox(
                "selected_files",
                message="Select the files to process (use space to select, arrows to navigate):",
                choices=mp3_files,
            )
        ]
        answers = inquirer.prompt(questions)
        selected_files = answers.get("selected_files", [])
    else:
        selected_files = mp3_files

    # Iterate over each mp3 file and create a deck for each one
    for idx, mp3_file in enumerate(selected_files):
        logger.info(f"Processing {mp3_file}")
        all_media_files = []
        lesson_number = extract_lesson_number(mp3_file)

        if lesson_number == None:
            lesson_number = idx + 1

        lesson_name = f"{args.ankideck}::Lesson {lesson_number:03d}"

        # Generate transcription and split audio into sentences
        audio_fp = os.path.join(args.audio_dir, mp3_file)
        transcription = transcript_audio(
            audio_fp, input_language=args.input_language, check=args.check_sentences
        )
        unique_verb_word_list_og = create_list_word_verbs(
            transcription, input_language=args.input_language
        )
        split_audio_fp_list = split_audio_sentences(audio_fp, transcription)

        unique_verb_word_list_translated = translate_list(
            unique_verb_word_list_og,
            input_language=args.input_language,
            target_language=args.target_language,
        )
        tmpdir = tempfile.mkdtemp()
        words_audio_fp = process_words_with_audio(
            unique_verb_word_list_og, tmpdir, input_language=args.input_language
        )

        sentence_list_og = sentences_list(transcription)
        sentence_list_translated = translate_list(
            sentence_list_og,
            input_language=args.input_language,
            target_language=args.target_language,
        )

        # Create words and sentences dictionaries
        audio_fp_array = [words_audio_fp[word] for word in unique_verb_word_list_og]
        words_dict = {}
        for og_word, translated_word, word_audio_fp in zip(
            unique_verb_word_list_og, unique_verb_word_list_translated, audio_fp_array
        ):
            words_dict[og_word] = {
                "translated_word": translated_word,
                "audio_fp": word_audio_fp,
            }

        sentences_dict = {}
        idx = 1
        for og_sentence, translated_sentence, audio_fp in zip(
            sentence_list_og, sentence_list_translated, split_audio_fp_list
        ):
            sentences_dict[og_sentence] = {
                "translated_sentence": translated_sentence,
                "audio_fp": audio_fp,
                "sentence_number": idx,
            }
            idx += 1

        # Create flashcards for the current lesson and add them to the deck
        deck, media_files = create_flashcards(
            words_dict, sentences_dict, deck_name=lesson_name
        )
        all_media_files.extend(media_files)

        # Write each subdeck to its own Anki package
        package = genanki.Package(deck)
        package.media_files = all_media_files
        package.write_to_file(os.path.join(args.output_folder, f"{lesson_name}.apkg"))

        shutil.rmtree(os.path.dirname(split_audio_fp_list[0]))
        shutil.rmtree(tmpdir)


if __name__ == "__main__":
    main()
