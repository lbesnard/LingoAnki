#!/usr/bin/env python3
"""
This code converts diary entries written in a foreign language into flashcards to learn more efficently.

TODO:
create a markdown template, which could be used by the code for different language.
make different language usuable

This is a bit hacky, but here is my workflow:

1) writing in a markdown file (Joplin) sentences in english following the template defined below
2) attempt to write in Norwegian the sentence
3) open chatgpt, copy the all markdown text for the day, and ask to translate into Norwegian by adding the tips and keeping the given markdown format
4) Paste the markdown output back into Joplin.
5) run this script which creates an anki deck
6) import the anki deck


TEMPLATE:

# 2025

## 2025/01/28 Tirsdag 28. Januar (Tuesday) 2025

- **I want to speak Bokmal**
  <span style="color: #C70039 ">Forsøk</span>:
  <span style="color: #097969">Rettelse</span>:
  <span style="color: #dda504">Tips</span>:

"""

import argparse
import hashlib
import logging
import os
import re
from sre_compile import REPEAT_ONE
import tempfile

from genanki import Deck, Model, Note, Package
from gtts import gTTS
from ovos_tts_plugin_piper import PiperTTSPlugin
from piper import PiperVoice
from pydub import AudioSegment


# norwegian template used in markdown file
diary_template = {
    "trial": '<span style="color: #C70039 ">Forsøk</span>:',
    "answer": '<span style="color: #097969">Rettelse</span>:',
    "tips": '<span style="color: #dda504">Tips</span>:',
}


# Define the model for Anki cards
anki_model = Model(
    model_id=3602398329,
    name="English-Norwegian Model",
    fields=[
        {"name": "English"},
        {"name": "Norwegian"},
        {"name": "Tips"},
        {"name": "Audio"},
        {"name": "Date"},
        {"name": "SentenceNumber"},
    ],
    templates=[
        {
            "name": "English to Norwegian",
            "qfmt": "{{English}}",
            "afmt": """
            {{FrontSide}}<hr id="answer">
            <div style="background-color:#f0f0f0; padding:10px; border-radius:8px;">
              <div style="color:#009933; font-size:1em;">{{Norwegian}}</div>
              <div style="color:#666; font-size:0.9em; margin-top:5px;"><em>{{Tips}}</em></div>
            </div>
            <center>{{Audio}}</center>

            """,
        },
        {
            "name": "Norwegian to English",
            "qfmt": "{{Audio}}",
            "afmt": """
                    <div style="font-weight:bold; font-size:1.2em; color:#0073e6;">
                    {{FrontSide}}<hr id="answer">
                    </div>
                    <div style="background-color:#f0f0f0; padding:10px; border-radius:8px;">
                    <div style="color:#333; font-size:1em;">{{Norwegian}}</div>
                    <hr style="border: 1px solid #0073e6;">
                    <div style="color:#009933; font-size:1em;">{{English}}</div>
                    <div style="color:#666; font-size:0.9em; margin-top:5px;"><em>{{Tips}}</em></div>
                    </div>
                    """,
        },
    ],
    css="""
        .card {
        display: flex;
        justify-content: center;
        align-items: center;
        height: 100vh;
        }

        .card {
        display: flex;
        justify-content: center;
        align-items: center;
        font-family: arial;
        font-size: 20px;
        text-align: center; bottom: 0
        color: black;
        background-color: white;
        }
        .replay-button svg
        { width: 80px;
        height: 80px;
        }
        """,
)


class AnkiMarkdownParser:
    def __init__(self, markdown_path, deck_name, output_dir, use_piper=False):
        self.markdown_path = markdown_path
        self.deck_name = deck_name
        self.output_dir = output_dir
        self.use_piper = use_piper
        self.main_deck = None
        self.repeat_sentence = 4
        self.validate_arguments()
        self.setup_logging()

    def setup_logging(self):
        logging.basicConfig(
            level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
        )

    def validate_arguments(self):
        """
        Validate the input arguments.

        Args:
            markdown_path (str): Path to the markdown file.
            output_dir (str): Path to the output directory.

        Raises:
            FileNotFoundError: If the markdown path does not exist.
            ValueError: If the output directory does not exist and cannot be created.
        """
        if not os.path.exists(self.markdown_path):
            raise FileNotFoundError(f"Markdown file not found: {self.markdown_path}")

        if self.output_dir:
            if not os.path.exists(self.output_dir):
                try:
                    os.makedirs(self.output_dir)
                except Exception as e:
                    raise ValueError(
                        f"Failed to create output directory: {self.output_dir}. Error: {e}"
                    )

    def generate_unique_id(self, input_string, length=9):
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

    def read_markdown_file(self):
        """
        Read the content of the markdown file.

        Returns:
            str: Content of the markdown file.
        """
        with open(self.markdown_path, "r", encoding="utf-8") as file:
            return file.read()

    def create_main_deck(self):
        """
        Create the main Anki deck.

        Args:
            deck_name (str): Name of the main deck.

        Returns:
            Deck: The main Anki deck object.
        """
        return Deck(deck_id=hash(self.deck_name), name=self.deck_name)

    def process_year_block(self, year_block):
        """
        Process a year block and create subdecks.

        Args:
            year_block (str): Block of text for a specific year.
            deck_name (str): Name of the main deck.

        Returns:
            list: List of notes for the year.
        """
        year_match = re.match(r"^(\d{4})", year_block)
        if not year_match:
            return None, None

        year = year_match.group(1)
        year_deck_prefix = f"{self.deck_name}::{year}"

        logging.info(f"Processing year: {year}")

        days = re.split(r"^##\s+", year_block, flags=re.MULTILINE)
        notes = []
        media_files = []

        for day_block in days:
            note, media_file = self.process_day_block(day_block, year_deck_prefix)
            if note and media_file:
                notes.extend(note)
                media_files.extend(media_file)

        return notes, media_files

    def process_day_block(self, day_block, year_deck_prefix):
        """
        Process a day block and add notes to the deck.

        Args:
            day_block (str): Block of text for a specific day.
            year_deck_prefix (str): Prefix for the year deck name.
            repeat_sentence (int): for audio file, repeat n times the sentence in a row to facilitate understanding

        Returns:
            list: List of notes for the day.
        """
        if not day_block.strip():
            return None, None

        day_match = re.match(r"^(\d{4}/\d{2}/\d{2})\s+(.*)", day_block)
        if not day_match:
            return None, None

        date = day_match.group(1)
        title = day_match.group(2)
        sub_deck_name = f"{year_deck_prefix}::{date} {title}"

        logging.info(f"Processing day: {date} - {title}")

        entries = re.findall(
            r"-(.*?)\n.*?\n.*Rettelse.*?:(.*)", day_block, flags=re.MULTILINE
        )

        # pattern = r"-\s\*\*(.*?)\*\*\s*\n.*?\s*<span style=\"color: #097969\">Rettelse</span>:\s*\*(.*?)\*\s*\n.*?\s*<span style=\"color: #dda504\">Tips</span>:\s*(.*?)\s*\n"
        # pattern = r"-(.*?)\n.*?<span style=\"color: #097969\">Rettelse</span>:(.*?)\n.*?<span style=\"color: #dda504\">Tips</span>:(.*?)\n"
        answer_template = diary_template["answer"]
        tips_template = diary_template["tips"]

        pattern = rf"-(.*?)\n.*?{answer_template}(.*?)\n.*?{tips_template}(.*?)\n"
        entries = re.findall(pattern, day_block, re.DOTALL)

        if not any(entry[1] for entry in entries):
            logging.warning(f"Skipping day {date} as it has no valid translations.")
            return None, None

        notes = []
        media_files = []
        i_sentence = 0
        for english, norwegian, tips in entries:
            if norwegian:
                logging.info(f"Sentence in English: {english}")
                logging.info(f"Sentence in Norwegian: {norwegian}")
                note, media_file = self.create_note(
                    english, norwegian, tips, date, sub_deck_name, i_sentence
                )
                i_sentence += 1
                if note and media_file:
                    note.guid = self.generate_unique_id(
                        english
                    )  # create unique id https://github.com/kerrickstaley/genanki/issues/61
                    notes.append(note)
                    media_files.append(media_file)

        # create a mp3 per day of all the notes to be listened with an audio player
        playlist_media = [AudioSegment.from_mp3(mp3_file) for mp3_file in media_files]

        combined = AudioSegment.empty()
        for sentence in playlist_media:
            combined += (
                sentence * self.repeat_sentence
            )  # repeat audio 4 times so that it's easier to remember

        combined.export(
            f"{self.output_dir}/{self.deck_name.replace(':', '')}_{date.replace('/', '-')}.mp3",
            format="mp3",
        )

        return notes, media_files

    def create_note(self, english, norwegian, tips, date, sub_deck_name, i):
        """
        Create a note for the subdeck.

        Args:
            english (str): English sentence.
            norwegian (str): Norwegian translation.
            tips (str): tips about Norwegian translation.
            date (str): Date tag.
            sub_deck_name (str): Name of the subdeck.
            i (int): number of the sentence in diary

        Returns:
            Note: Anki Note object.
        """
        norwegian = norwegian.replace("**", "").strip()
        english = english.replace("**", "").strip()
        logging.info(f"Creating TTS audio for: {norwegian}")

        if norwegian == "":
            return None, None

        if not self.use_piper:
            logging.info("Using gTTS")
            tts = gTTS(text=norwegian, lang="no")
            audio_filename = os.path.join(
                tempfile.gettempdir(), f"{hash(norwegian)}.mp3"
            )
            tts.save(audio_filename)
        else:
            logging.info("Using piper-tts")
            # config = {
            #     "module": "ovos-tts-plugin-piper",
            # }
            # e = PiperTTSPlugin(config=config)
            e = PiperTTSPlugin()
            e.length_scale = 1.4

            # voice = PiperVoice.load("no_NO-talesyntese-medium.onnx")
            audio_filename = os.path.join(
                tempfile.gettempdir(), f"{hash(norwegian)}.wav"
            )
            # wav_file = wave.open(audio_filename, "w")
            e.get_tts(norwegian, audio_filename, lang="no")

            # audio = voice.synthesize(norwegian, wav_file) # using plugin instead

            # convert to mp3
            audio = AudioSegment.from_wav(audio_filename)
            audio.export(audio_filename.replace(".wav", ".mp3"), format="mp3")
            audio_filename = audio_filename.replace(".wav", ".mp3")
            os.remove(audio_filename.replace(".mp3", ".wav"))
            logging.info(f"{audio_filename}")

        # main_deck_name = "Diary test"

        # Create unique IDs for the subdecks
        # deck_day_name = f"{main_deck_name}:: {{sub_deck_name}}"

        # deck_day_sentences_unique_id = generate_unique_id(deck_day_name)

        # deck_sentences = Deck(deck_day_sentences_unique_id, deck_day_name)
        # note_id = generate_unique_id(english)

        note = Note(
            model=anki_model,
            fields=[
                english.strip(),
                norwegian,
                tips,
                f"[sound:{os.path.basename(audio_filename)}]",
                date,
                str(i).zfill(2),
            ],
            tags=[date],
        )

        # deck_sentences.add_note(note)

        return note, audio_filename

    def process_markdown(self):
        """
        Parse the markdown file and generate Anki flashcards with audio.

        Args:
            markdown_path (str): Path to the markdown file.
            deck_name (str): Name of the main deck.
            output_dir (str): Path to the output directory.
        """
        self.validate_arguments()
        # global USE_PIPER
        # USE_PIPER = piper

        content = self.read_markdown_file()

        logging.basicConfig(
            level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
        )

        years = re.split(r"^#\s+", content, flags=re.MULTILINE)
        main_deck = self.create_main_deck()
        all_notes = []
        all_media_files = []

        for year_block in years:
            if year_block.strip():
                all_note, all_media_file = self.process_year_block(year_block)
                if all_note and all_media_file:
                    all_notes.extend(all_note)
                    all_media_files.extend(all_media_file)

        for note in all_notes:
            main_deck.add_note(note)

        output_path = self.output_dir or tempfile.mkdtemp()
        deck_file = os.path.join(output_path, f"{self.deck_name}.apkg")

        package = Package(main_deck)
        package.media_files = all_media_files
        package.write_to_file(deck_file)

        for f in all_media_files:
            os.remove(f)

        logging.info(f"Anki deck created: {deck_file}")


def main():
    parser = argparse.ArgumentParser(
        description="Create Anki flashcards from a Markdown file.",
        epilog='Example:\n diaryAnki -m /home/lbesnard/Nextcloud/joplin/18cf5fb35d3d4e20b5c6a4be0a56e429.md -d "Norwegian 🇳🇴:::Diary 📖" -o ~/Documents',
    )
    parser.add_argument(
        "-m", "--markdown-path", required=True, help="Path to the markdown file."
    )
    parser.add_argument(
        "-d", "--deck-name", required=True, help="Name of the Anki deck."
    )
    parser.add_argument(
        "-o",
        "--output-dir",
        required=False,
        help="Path to the output directory. Defaults to a temporary directory.",
    )
    parser.add_argument(
        "-p",
        "--piper",
        action="store_true",
        help="User piper for TTS.",
    )

    args = parser.parse_args()

    parser_instance = AnkiMarkdownParser(
        markdown_path=args.markdown_path,
        deck_name=args.deck_name,
        output_dir=args.output_dir,
        use_piper=args.piper,
    )
    parser_instance.process_markdown()


if __name__ == "__main__":
    main()
