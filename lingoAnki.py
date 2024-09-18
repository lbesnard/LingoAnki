#!/usr/bin/env python3
import whisper
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


def transcript_audio(audio_fp, language="no", check=False):
    model = whisper.load_model("large-v2")

    result = model.transcribe(
        audio_fp,
        language=language,
        beam_size=1,
        best_of=1,
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
        if duration >= 0.2:
            filtered_segments.append(segment)

    transcription['segments'] = filtered_segments

    # Adjust the end time of each segment
    additional_time = 0.400
    for idx, segment in enumerate(transcription['segments']):
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


# def transcript_audio(audio_fp, language="no", check=False):
    # model = whisper.load_model("small")
    # # result = model.transcribe(audio_fp, language=language)
    # result = model.transcribe(
        # audio_fp,
        # language=language,
        # # temperature=(0.0, 0.2),  # Adjust to your needs
        # beam_size=1,
        # best_of=1,
        # word_timestamps=True,
        # no_speech_threshold=0.6,
        # logprob_threshold=-0.5,  # Exclude low-confidence transcriptions
        # compression_ratio_threshold=2.4,
        # condition_on_previous_text=False,
        # verbose=True,
    # )

    # transcription = result
    # # If check flag is set, manually review each sentence
    # if check:
        # print("Review the transcription below:")
        # for idx, segment in enumerate(transcription['segments'], start=1):  # start=1 for numbering from 1
            # print(f"Sentence {idx}: {segment['text']}")
            # modified = input(f"Press Enter to keep Sentence {idx}, or type a new sentence to modify: ").strip()

            # if modified:  # If the user provides a new sentence, overwrite the original
                # transcription['segments'][idx-1]['text'] = modified  # idx-1 to match zero-indexed list
            # print()  # For spacing between sentences

    # return transcription


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

def create_list_word_verbs(transcription):
    nlp = spacy.load("nb_core_news_sm")
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
        # else:
            # other_tokens.append(token.lemma_)

    list_words = infinitive_verbs + singular_nouns + adverbs + base_adjectives + other_tokens
    unique_list = [*{*list_words}]
    return unique_list

def translate_list(list_words, language='no'):
    translated = GoogleTranslator(language, 'en').translate_batch(list_words)
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

def create_word_model():
    return genanki.Model(
        WORD_CARD_MODEL_ID,
        'Word Flashcards Model',
        fields=[
            {'name': 'Word'},
            {'name': 'Translation'},
        ],
        templates=[
            {
                'name': 'Word to Translation',
                'qfmt': '{{Word}}',
                'afmt': '{{FrontSide}}<hr id="answer">{{Translation}}',
            },
            {
                'name': 'Translation to Word',
                'qfmt': '{{Translation}}',
                'afmt': '{{FrontSide}}<hr id="answer">{{Word}}',
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
                'name': 'Sentence Card',
                'qfmt': '{{Audio}}<br><button onclick="playAudio()">Play</button>',
                'afmt': '{{FrontSide}}<hr id="answer">{{Sentence}}<br>{{Translation}}',
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
    deck = genanki.Deck(2059400110, deck_name)
    word_model = create_word_model()
    sentence_model = create_sentence_model()
    media_files = []

    for word, translation in word_dict.items():
        note = genanki.Note(
            model=word_model,
            fields=[word, translation]
        )
        deck.add_note(note)

    for sentence, data in sentence_dict.items():
        audio_fp = data["audio_fp"]
        translated_sentence = data["translated_sentence"]
        note = genanki.Note(
            model=sentence_model,
            fields=[sentence, translated_sentence, add_audio(audio_fp)]
        )
        deck.add_note(note)
        media_files.append(audio_fp)

    return deck, media_files

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




def main():
    parser = argparse.ArgumentParser(description="Process multiple audio files and generate flashcards.")
    parser.add_argument('audio_dir', type=str, help="Directory containing the audio files")
    parser.add_argument('--ankideck', '-a', type=str, default="MyLanguageCards", help="Anki main deck name")
    parser.add_argument('--language', type=str, default="no", help="Language to parse")
    parser.add_argument('--check', '-c', action='store_true', help="Manually review and modify the transcription")
    args = parser.parse_args()

    # Get the list of .mp3 files in the folder, sorted alphanumerically
    mp3_files = get_mp3_files(args.audio_dir)
    print(mp3_files)

    # Iterate over each mp3 file and create a deck for each one
    for idx, mp3_file in enumerate(mp3_files):
        all_media_files = []
        lesson_number = idx + 1
        lesson_name = f"{args.ankideck}::Lesson {lesson_number:02d}"
        #TODO: change random number below
        deck = genanki.Deck(2059400110 + lesson_number, lesson_name)

        # Generate transcription and split audio into sentences
        audio_fp = os.path.join(args.audio_dir, mp3_file)
        transcription = transcript_audio(audio_fp, language=args.language, check=args.check)
        unique_verb_word_list_og = create_list_word_verbs(transcription)
        split_audio_fp_list = split_audio_sentences(audio_fp, transcription)

        unique_verb_word_list_translated = translate_list(unique_verb_word_list_og)
        sentence_list_og = sentences_list(transcription)
        sentence_list_translated = translate_list(sentence_list_og)

        # Create words and sentences dictionaries
        words_dict = {og: translated for og, translated in zip(unique_verb_word_list_og, unique_verb_word_list_translated)}
        sentences_dict = {}
        for og_sentence, translated_sentence, audio_fp in zip(sentence_list_og, sentence_list_translated, split_audio_fp_list):
            sentences_dict[og_sentence] = {
                "translated_sentence": translated_sentence,
                "audio_fp": audio_fp
            }


        # Create flashcards for the current lesson and add them to the deck
        deck, media_files = create_flashcards(words_dict, sentences_dict, deck_name=lesson_name)
        all_media_files.extend(media_files)

        # Write each subdeck to its own Anki package
        package = genanki.Package(deck)
        package.media_files = all_media_files
        package.write_to_file(f'{lesson_name}.apkg')

        delete_sentence_mp3_files(os.path.dirname(split_audio_fp_list[0]))
        # delete_sentence_mp3_files(os.path.dirname(os.path.abspath(__file__)))

if __name__ == "__main__":
    main()

