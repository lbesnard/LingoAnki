#!/usr/bin/env python3
import whisper
import re
import hashlib
import pyttsx3
import numpy as np
from pydub import AudioSegment
import spacy
import argparse
import os
from deep_translator import GoogleTranslator
import genanki
import re
import glob
import tempfile
import spacy.cli
import shutil
from time import sleep
from TTS.api import TTS
from gtts import gTTS
import json
import requests

ANKICONNECT_URL = 'http://localhost:8765'

# Define a mapping of language names to spaCy model names
language_to_model = {
    'no': 'nb_core_news_sm',
    'en': 'en_core_web_sm',
    'ger': 'de_core_news_sm',
    'fr': 'fr_core_news_sm',
    # Add other languages and models as needed
}

language_to_pyttsx3 = {
    'no': 'nb',
    'fr': 'fr-fr',
    'en': 'en-gb'
}

language_to_tts = {
    'no': "tts_models/nb/nb_model",
    'fr': "tts_models/fr/css10"
}


def download_model_for_language(language_name):
    model_name = language_to_model.get(language_name.lower())

    if model_name:
        installed_models = spacy.util.get_installed_models()

        if model_name in installed_models:
            print(f"Model for {language_name} is already installed.")
        else:
            print(f"Model for {language_name} not found. Downloading: {model_name}")
            spacy.cli.download(model_name)
        return model_name
    else:
        print(f"No model found for language: {language_name}")
        return None

def generate_unique_id(input_string, length=9):
    # Hash the string using SHA256
    hash_object = hashlib.sha256(input_string.encode('utf-8'))

    # Convert the hash to an integer
    hash_int = int(hash_object.hexdigest(), 16)

    # Take a portion of the integer and ensure it's the desired length
    unique_id = hash_int % (10 ** length)

    return unique_id


def process_words_with_audio(words_list, audio_dir, language_code='no'):
    """Process words, generating missing audio if necessary and returning a dictionary of words and audio file paths."""
    audio_paths = {}  # Dictionary to hold words and their audio file paths

    for word in words_list:
        # audio_fp = tempfile.NamedTemporaryFile(suffix='.mp3', dir=audio_dir, delete=False).name
        # audio_fp = os.path.join(audio_dir, f"{word}.mp3")

        # if not os.path.exists(audio_fp):
        audio_fp = handle_missing_audio(word, audio_dir, language_code)

        # Add the word and its audio file path to the dictionary

        audio_paths[word] = audio_fp

    return audio_paths

def handle_missing_audio(word, audio_dir, language_code='no'):
    """Generate and save TTS audio for a missing word."""

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
    tts = gTTS(word, lang=language_code, tld='com.au')
    tts.save(audio_fp)

    print(f"Generated TTS audio for: {word}")
    return audio_fp


def transcript_audio(audio_fp, language="no", check=False):
    model = whisper.load_model("large-v3")
    # model = whisper.load_model("tiny")

    result = model.transcribe(
        audio_fp,
        language=language,
        beam_size=1,
        best_of=2,
        word_timestamps=True,
        no_speech_threshold=0.6,
        logprob_threshold=-0.5,
        compression_ratio_threshold=2.4,
        condition_on_previous_text=False,
        verbose=True,
    )

    # Filter out segments with a duration less than 200ms (0.2 seconds)
    transcription = result
    filtered_segments = []

    for segment in transcription['segments']:
        start_time = segment['start']
        end_time = segment['end']
        duration = end_time - start_time

        # Check if duration is 200ms or more
        if duration >= 0.3:
            filtered_segments.append(segment)

    transcription['segments'] = filtered_segments

    # Adjust the end time of each segment
    additional_time = 0.500
    for idx, segment in enumerate(transcription['segments']):
        # Adjust the start time
        if idx > 0:
            previous_segment_end = transcription['segments'][idx - 1]['end']
            segment['start'] = max(segment['start'] - additional_time/3, previous_segment_end)
        else:
            # For the first segment, just subtract the additional time
            segment['start'] = max(segment['start'] - additional_time/3, 0)  # Ensure start time doesn't go below 0

        # Increase the end time of each segment by additional_time, but ensure it does not overlap with the next segment
        if idx < len(transcription['segments']) - 1:
            next_segment_start = transcription['segments'][idx + 1]['start']
            segment['end'] = min(segment['end'] + additional_time, next_segment_start)
        else:
            # For the last segment, just add the additional time
            segment['end'] = segment['end'] + additional_time

    # If check flag is set, manually review each sentence
    if check:
        print("Review the transcription below:")
        for idx, segment in enumerate(transcription['segments'], start=1):  # start=1 for numbering from 1
            print(f"Sentence {idx}: {segment['text']}")
            modified = input(f"Press Enter to keep Sentence {idx}, or type a new sentence to modify: ").strip()

            if modified:  # If the user provides a new sentence, overwrite the original
                transcription['segments'][idx-1]['text'] = modified  # idx-1 to match zero-indexed list
            print()  # For spacing between sentences

    return transcription


def split_audio_sentences(audio_fp, whisper_transcription):
    audio = AudioSegment.from_file(audio_fp)
    sentence_timestamps = whisper_transcription['segments']  # Assuming Whisper returns timestamps
    tmpdir = tempfile.mkdtemp()

    sentence_audio_fp_list = []
    for idx, segment in enumerate(sentence_timestamps):
        start = segment['start'] * 1000  # in milliseconds
        end = segment['end'] * 1000
        sentence_audio = audio[start:end]
        sentence_audio_fp = os.path.join(tmpdir, f"sentence_{idx}.mp3")
        sentence_audio.export(sentence_audio_fp, format="mp3")
        sentence_audio_fp_list.append(sentence_audio_fp)
    return sentence_audio_fp_list

def create_list_word_verbs(transcription, language_name='no'):

    language_model = download_model_for_language(language_name)
    nlp = spacy.load(language_model)
    sentence = transcription['text']
    doc = nlp(sentence)
    infinitive_verbs, singular_nouns, base_adjectives, adverbs, other_tokens = [], [], [], [], []

    for token in doc:
        if token.pos_ == "VERB":
            infinitive_verbs.append("å " + token.lemma_)
        elif token.pos_ == "NOUN":
            singular_nouns.append(token.lemma_)
        elif token.pos_ == "ADJ":
            base_adjectives.append(token.lemma_)
        elif token.pos_ == "ADV":
            adverbs.append(token.lemma_)
        elif token.is_alpha:  # Ensures the token is made up of letters only
            other_tokens.append(token.lemma_)

    list_words = infinitive_verbs + singular_nouns + adverbs + base_adjectives + other_tokens
    unique_list = [*{*list_words}]
    unique_list = clean_and_lemmatize(unique_list)
    return unique_list

def clean_and_lemmatize(word_list):
    cleaned_words = [word.strip() for word in word_list]
    return list(set(cleaned_words))  # Remove duplicates

def translate_list(list_words, language='no', translate_language_output='en'):
    translated = GoogleTranslator(language, translate_language_output).translate_batch(list_words)
    return translated

def sentences_list(transcription):
    sentences = [segment['text'] for segment in transcription['segments']]
    return sentences

# Function to add media (audio) to Anki note
def add_audio(media_file):
    return f'[sound:{os.path.basename(media_file)}]'

# Create unique model ids for different card types
WORD_CARD_MODEL_ID = 123456789
SENTENCE_CARD_MODEL_ID = 987654321
COMBINED_SENTENCES_MODEL_ID = 987654322

def create_word_model():
    return genanki.Model(
        WORD_CARD_MODEL_ID,
        'Word Flashcards Model',
        fields=[
            {'name': 'Word'},
            {'name': 'Translation'},
            {'name': 'Audio'},
        ],
        templates=[
            {
                'name': 'Word to Translation',
                'qfmt': '{{Word}}<br>{{Audio}}',
                'afmt': '{{FrontSide}}<hr id="answer">{{Translation}}',
            },
            {
                'name': 'Translation to Word',
                'qfmt': '{{Translation}}',
                'afmt': '{{FrontSide}}<hr id="answer">{{Word}}<br>{{Audio}}',
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
        """
    )

def create_sentence_model():
    return genanki.Model(
        SENTENCE_CARD_MODEL_ID,
        'Sentence Flashcards Model',
        fields=[
            {'name': 'Sentence'},
            {'name': 'Translation'},
            {'name': 'Audio'},
        ],
        templates=[
            {
                'name': 'Sentence to Translation',
                'qfmt': '{{Audio}}',
                'afmt': '{{FrontSide}}<hr id="answer">{{Sentence}}<br>{{Translation}}',
            },
            {
                'name': 'Translation to Sentence',
                'qfmt': '{{Translation}}',
                'afmt': '{{FrontSide}}<hr id="answer">{{Sentence}}<br>{{Audio}}',
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
        """
    )


def create_combined_sentences_model():
    return genanki.Model(
        COMBINED_SENTENCES_MODEL_ID,
        'Combined Sentences Flashcards Model',
        fields=[
            {'name': 'CombinedSentences'},
            {'name': 'Translation'},
            {'name': 'Audio'},
        ],
        templates=[
            {
                'name': 'Combined Sentences Card',
                'qfmt': '''
                    {{#CombinedSentences}}
                    {{CombinedSentences}}<br>
                    {{/CombinedSentences}}
                    <br>
                    [sound:{{Audio}}]
                ''',
                'afmt': '{{FrontSide}}<hr id="answer">{{Translation}}',
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
        """
    )

def create_flashcards(word_dict, sentence_dict, deck_name="Language Flashcards"):

    lesson_name = deck_name.split('::')[1].replace(' ', '_')
    main_deck_name = deck_name.split('::')[0].replace(' ', '_')

    deck_unique_id = generate_unique_id(deck_name)
    deck = genanki.Deck(deck_unique_id, deck_name)

    word_model = create_word_model()
    sentence_model = create_sentence_model()
    combined_model = create_combined_sentences_model()
    media_files = []

    # Add word flashcards
    for word, data in word_dict.items():
        audio_fp = data["audio_fp"]
        translation = data["translated_word"]
        note = genanki.Note(
            model=word_model,
            fields=[word, translation, add_audio(audio_fp)],
            tags=["lingoAnki_words_verbs_adjs", main_deck_name, lesson_name]
            # tags=["lingoAnki_words_verbs_adjs", main_deck_name]

        )
        deck.add_note(note)
        media_files.append(audio_fp)

    # Add individual sentence flashcards
    for sentence, data in sentence_dict.items():
        audio_fp = data["audio_fp"]
        sentence_number = data["sentence_number"]
        translated_sentence = data["translated_sentence"]
        note = genanki.Note(
            model=sentence_model,
            fields=[ f"{sentence_number:02d}. {sentence}", translated_sentence, add_audio(audio_fp)],
            tags=['lingoAnki_individual_sentence', main_deck_name, lesson_name]
        )
        deck.add_note(note)
        media_files.append(audio_fp)

    # Prepare combined sentences with individual play buttons
    combined_sentences = f"{lesson_name}<br><br>"
    combined_audio = ""
    sorted_sentences = sorted(sentence_dict.items(), key=lambda item: item[1]['sentence_number'])
    for sentence, data in sorted_sentences:#.items():
        sentence_number = data["sentence_number"]
        audio_fp = data["audio_fp"]
        combined_sentences += f'<b>{sentence_number:02d}. {sentence}</b><br>'
        combined_audio += f'{sentence_number:02d}. {add_audio(audio_fp)} <br> '  # Combine audio file paths

    combined_translation = " ".join(
        f"{i + 1}. {data['translated_sentence']} <br>"
        for i, (_, data) in enumerate(sorted_sentences)
    )

    combined_note = genanki.Note(
        model=combined_model,
        fields=[combined_sentences, combined_translation, combined_audio],
        tags=['lingoAnki_combined_sentences', main_deck_name, lesson_name]
    )
    deck.add_note(combined_note)

    # Add combined audio files to media
    # for data in sentence_dict.values():
        # media_files.append(data["audio_fp"])

    return deck, media_files

# Adding a new card with all sentences ordered and numbered
# Function to sort files numerically
def sorted_alphanumeric(data):
    def convert(text):
        return int(text) if text.isdigit() else text.lower()
    def alphanum_key(key):
        return [convert(c) for c in re.split('([0-9]+)', key)]
    return sorted(data, key=alphanum_key)

# Function to list and sort all .mp3 files in a folder
def get_mp3_files(audio_dir):
    mp3_files = [f for f in os.listdir(audio_dir) if f.endswith('.mp3')]
    return sorted_alphanumeric(mp3_files)


def delete_sentence_mp3_files(directory):
    # Get all files starting with 'sentence_' and ending with '.mp3'
    sentence_files = glob.glob(os.path.join(directory, "sentence_*.mp3"))

    # Delete each file
    for file_path in sentence_files:
        try:
            os.remove(file_path)
            print(f"Deleted: {file_path}")
        except OSError as e:
            print(f"Error deleting {file_path}: {e}")

# Function to send requests to AnkiConnect
def invoke(action, params=None):
    return requests.post(ANKICONNECT_URL, json.dumps({
        'action': action,
        'version': 6,
        'params': params
    })).json()

def import_apkg_file(apkg_path):
    params = {
        "path": apkg_path
    }

    response = invoke('importPackage', params)
    return response

def create_filtered_deck(deck_name, tags, combine_logic="AND"):
    if combine_logic == "AND":
        # Combine tags with AND logic
        search_query = " ".join([f"tag:{tag}" for tag in tags])
    elif combine_logic == "OR":
        # Combine tags with OR logic
        search_query = " OR ".join([f"tag:{tag}" for tag in tags])

    params = {
        "deck": deck_name,
        "search": search_query,
        "reschedule": False,  # Set to True if you want to reschedule cards
        "deliberate": False   # Set to True for manual steps mode
    }

    response = invoke('createCustomStudyDeck', params)
    return response


def extract_lesson_number(filename):
    # Regular expression to find 1 to 3 digit numbers, possibly with leading zeros
    match = re.search(r'\b(0*\d{1,3})\b', filename)

    if match:
        # Convert the matched string to an integer to remove leading zeros
        return int(match.group(1))
    else:
        return None  # Return None if no number is found


def main():
    parser = argparse.ArgumentParser(description="Automates the creation of Anki flashcards from transcripts extracted from audio recordings.")
    parser.add_argument('audio_dir', type=str, help="Directory containing the input audio files to process")
    parser.add_argument('--ankideck', '-a', type=str, default="MyLanguageCards", help="Anki main Deck name")
    parser.add_argument('--language', type=str, default="no", help="Language Code to parse (en,bo,fr ...)")
    parser.add_argument('--language-output', type=str, default="en", help="Language Code output (en,fr ...)")
    parser.add_argument('--output-folder', '-o', type=str, default="", help="Output folder")
    parser.add_argument('--check', '-c', action='store_true', help="Manually review and modify the transcription")
    parser.add_argument('--import-anki', '-i', action='store_true', help="Automatically Import anki card via ankiconnect")
    args = parser.parse_args()

    # Set default to a temporary directory if not specified
    if not args.output_folder:
        args.output_folder = tempfile.mkdtemp()

    # Create the output folder if it does not exist
    os.makedirs(args.output_folder, exist_ok=True)

    # Get the list of .mp3 files in the folder, sorted alphanumerically
    mp3_files = get_mp3_files(args.audio_dir)
    print(mp3_files)

    # Iterate over each mp3 file and create a deck for each one
    for idx, mp3_file in enumerate(mp3_files):
        all_media_files = []
        lesson_number = extract_lesson_number(mp3_file)
        if lesson_number == None:
            lesson_number = idx + 1
        lesson_name = f"{args.ankideck}::Lesson {lesson_number:02d}"

        # Generate transcription and split audio into sentences
        audio_fp = os.path.join(args.audio_dir, mp3_file)
        transcription = transcript_audio(audio_fp, language=args.language, check=args.check)
        unique_verb_word_list_og = create_list_word_verbs(transcription, language_name=args.language)
        split_audio_fp_list = split_audio_sentences(audio_fp, transcription)

        unique_verb_word_list_translated = translate_list(unique_verb_word_list_og, translate_language_output=args.language_output)
        tmpdir = tempfile.mkdtemp()
        words_audio_fp = process_words_with_audio(unique_verb_word_list_og, tmpdir, language_code=args.language)

        sentence_list_og = sentences_list(transcription)
        sentence_list_translated = translate_list(sentence_list_og, translate_language_output=args.language_output)

        # Create words and sentences dictionaries
        # words_dict = {og: translated for og, translated in zip(unique_verb_word_list_og, unique_verb_word_list_translated)}
        audio_fp_array = [words_audio_fp[word] for word in unique_verb_word_list_og]
        words_dict = {}
        for og_word, translated_word, word_audio_fp in zip(unique_verb_word_list_og, unique_verb_word_list_translated, audio_fp_array):
            words_dict[og_word] = {
                'translated_word': translated_word,
                'audio_fp': word_audio_fp
            }

        # words_dict =  {
            # og: (translated, audio_fp)
            # for og, translated, audio_fp in zip(unique_verb_word_list_og, unique_verb_word_list_translated, words_audio_fp)
        # }
        # import ipdb; ipdb.set_trace()

        sentences_dict = {}
        idx = 1
        for og_sentence, translated_sentence, audio_fp in zip(sentence_list_og, sentence_list_translated, split_audio_fp_list):
            sentences_dict[og_sentence] = {
                "translated_sentence": translated_sentence,
                "audio_fp": audio_fp,
                "sentence_number": idx
            }
            idx += 1

        # Create flashcards for the current lesson and add them to the deck
        deck, media_files = create_flashcards(words_dict, sentences_dict, deck_name=lesson_name)
        all_media_files.extend(media_files)

        # Write each subdeck to its own Anki package
        package = genanki.Package(deck)
        package.media_files = all_media_files
        package.write_to_file(os.path.join(args.output_folder, f'{lesson_name}.apkg'))

        if args.import_anki:
            try:
                import_apkg_file(os.path.join(args.output_folder, f'{lesson_name}.apkg'))
                print('{lesson_name} imported via ankiconnect')
            except:
                print('Could not import anki package')

        # delete_sentence_mp3_files(os.path.dirname(split_audio_fp_list[0]))
        shutil.rmtree(os.path.dirname(split_audio_fp_list[0]))
        shutil.rmtree(tmpdir)
        # delete_sentence_mp3_files(tmpdir)
        # delete_sentence_mp3_files(os.path.dirname(os.path.abspath(__file__)))

if __name__ == "__main__":
    main()

