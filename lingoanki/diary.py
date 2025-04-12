#!/usr/bin/env python3
"""
This script helps convert diary entries written in a foreign language into flashcards to support more effective language learning.

## Workflow

1. **Write sentences in your prlimary language** in a Markdown file, following the template provided:
    - This can be done manually,
    - or generated interactively using this script with user prompts.

2. **Optionally, write your own translation** of each sentence in the study language:
    - Either manually,
    - or through the script with prompting.

3. **The script uses OpenAI** to:
    - Translate the sentences into the study language,
    - Provide helpful learning tips,
    - Generate a title for the diary entry.

4. **An Anki deck is created** (if enabled in `config.yaml`; disabled by default):
    - This must be imported manually into Anki.

5. **A TPRS (Teaching Proficiency Through Reading and Storytelling) resource is generated** for each diary entry:
    - Includes both an audio file and a corresponding Markdown file.


TEMPLATE:

# 2025

## 2025/01/28
- **I want to speak Bokmal**
  <span style="color: #C70039 ">Forsøk</span>:
  <span style="color: #097969">Rettelse</span>:
  <span style="color: #dda504">Tips</span>:

"""

import hashlib
import json
import logging
import os
import re
import shutil
import tempfile
import textwrap
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from sre_compile import REPEAT_ONE

import numpy as np
from openai import OpenAI
import yaml
from genanki import Deck, Model, Note, Package
from gtts import gTTS
from ovos_plugin_manager.tts import load_tts_plugin
from ovos_tts_plugin_piper import PiperTTSPlugin
from piper import PiperVoice
from platformdirs import user_config_dir
from pydub import AudioSegment

APP_NAME = "lingoDiary"
CONFIG_FILE = "config.yaml"


class DiaryHandler:
    def __init__(self, config_path=None):
        self.config = self.load_config(config_path=config_path)
        self.markdown_diary_path = self.config["markdown_diary_path"]
        self.deck_name = self.config["anki_deck_name"]
        self.output_dir = os.path.dirname(self.config["output_dir"])
        self.backup_dir = os.path.join(self.output_dir, ".backup")
        self.tts_model = self.config["tts"]["model"]
        self.diary_new_entries_day = None
        self.template_help_string = self.template_help()

        self.setup_logging()
        self.validate_arguments()

        self.setup_output_diary_markdown()
        self.anki_model_def()

    def load_config(self, config_path=None):
        if config_path is None:
            config_path = Path(user_config_dir(APP_NAME)).joinpath(CONFIG_FILE)

        """Load YAML config if it exists."""
        if os.path.exists(config_path):
            with open(config_path) as f:
                return yaml.safe_load(f) or {}

        logger = logging.getLogger(__name__)
        logger.error(f"Please create configuration file {config_path}")
        raise FileNotFoundError

    def setup_output_diary_markdown(self):
        # doing it this way, as the TPRS class can inherit this DiaryHandler class
        if self.__class__.__name__ == "DiaryHandler":
            time_now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            if self.config["overwrite_diary_markdown"]:
                # backing up original file, make it hidden and add bak.timestamp
                if os.path.exists(self.markdown_diary_path):
                    shutil.copy(
                        self.markdown_diary_path,
                        self.markdown_diary_path.replace(
                            ".md",
                            f".md.bak_{time_now_str}",
                        )
                        .replace(
                            os.path.basename(self.markdown_diary_path),
                            "." + os.path.basename(self.markdown_diary_path),
                        )
                        .replace(
                            os.path.dirname(self.markdown_diary_path), self.backup_dir
                        ),
                    )

                    self.markdown_script_generated_diary_path = self.markdown_diary_path
            else:
                # if overwrite is False, we need to replace the output_dir
                org_dir_path = os.path.dirname(self.markdown_diary_path)

                self.markdown_script_generated_diary_path = self.markdown_diary_path
                if org_dir_path == self.output_dir:
                    # same dir, modify filename
                    self.markdown_script_generated_diary_path = (
                        self.markdown_script_generated_diary_path.replace(
                            ".md", f"_{time_now_str}.md"
                        )
                    )

                else:
                    # different dir, filename stays the same
                    self.markdown_script_generated_diary_path = (
                        self.markdown_script_generated_diary_path.replace(
                            org_dir_path, self.output_dir
                        )
                    )
        else:
            self.markdown_script_generated_diary_path = self.markdown_diary_path
            org_dir_path = os.path.dirname(self.markdown_diary_path)
            self.markdown_script_generated_diary_path = (
                self.markdown_script_generated_diary_path.replace(
                    org_dir_path, self.output_dir
                )
            )
            # if the new markdown file doesnt exist yet, default back to the original one
            if not os.path.exists(self.markdown_script_generated_diary_path):
                self.markdown_script_generated_diary_path = self.markdown_diary_path

            # simplify code so that when not called from main class, both variables are the same
            self.markdown_diary_path = self.markdown_script_generated_diary_path

    def setup_logging(self):
        # Check if logger is already set up to avoid duplicate handlers
        logger = logging.getLogger(__name__)

        if not any(
            isinstance(handler, logging.FileHandler) for handler in logger.handlers
        ):
            log_formatter = logging.Formatter(
                "%(asctime)s - %(levelname)s - %(message)s"
            )

            # Create file handler to log into output.log
            os.makedirs(self.output_dir, exist_ok=True)
            file_handler = logging.FileHandler(
                os.path.join(self.config["output_dir"], "output.log")
            )
            file_handler.setFormatter(log_formatter)

            # Create stream handler for console output
            stream_handler = logging.StreamHandler()
            stream_handler.setFormatter(log_formatter)

            # Set logger level to INFO
            logger.setLevel(
                logging.INFO
            )  # You can change this to DEBUG for more verbosity
            logger.addHandler(file_handler)
            logger.addHandler(stream_handler)

        self.logging = logger

    def close_logging(self):
        if hasattr(self, "logging"):
            logger = self.logging
            handlers = logger.handlers[:]
            for handler in handlers:
                handler.close()
                logger.removeHandler(handler)

    def stop(self):
        self.close_logging()

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
        if not os.path.exists(self.markdown_diary_path):
            self.logging.warning(
                f"Markdown file not found: {self.markdown_diary_path} - will start with an empty file"
            )
            os.makedirs(os.path.dirname(self.markdown_diary_path), exist_ok=True)
            with open(self.markdown_diary_path, "w"):
                pass
            self.new_diary = True
        else:
            self.new_diary = False

        if self.output_dir:
            if not os.path.exists(self.output_dir):
                try:
                    os.makedirs(self.output_dir, exist_ok=True)
                except Exception as e:
                    raise ValueError(
                        f"Failed to create output directory: {self.output_dir}. Error: {e}"
                    )

        if self.backup_dir:
            os.makedirs(self.backup_dir, exist_ok=True)

    def template_help(self):
        multiline = textwrap.dedent(
            f"""\
            ## YYYY/MM/DD\n
            - **[!!! TO REPLACE FROM [ TO ] !!! sentence to translate from {self.config["languages"]["primary_language"]}]**
              {self.config["template_diary"]["trial"]}\x20
              {self.config["template_diary"]["answer"]}\x20
              {self.config["template_diary"]["tips"]}\x20

            - **[!!! TO REPLACE FROM [ TO ] !!! sentence to translate from {self.config["languages"]["primary_language"]}]**
              {self.config["template_diary"]["trial"]}\x20
              {self.config["template_diary"]["answer"]}\x20
              {self.config["template_diary"]["tips"]}\x20

            - **[!!! TO REPLACE FROM [ TO ] !!! sentence to translate from {self.config["languages"]["primary_language"]}]**
              {self.config["template_diary"]["trial"]}\x20
              {self.config["template_diary"]["answer"]}\x20
              {self.config["template_diary"]["tips"]}\x20
        """
        )
        return multiline

    def prompt_new_diary_entry(self):
        if self.config["diary_entries_prompt_user"]:
            if self.__class__.__name__ == "DiaryHandler":
                self.diary_new_entries_day = self._prompt_new_diary_entry()
        else:
            self.diary_new_entries_day = None
            return

    def _prompt_new_diary_entry(self):
        """Prompt user to add new diary entries for today."""

        diary = {}

        user_input = (
            input("Do you want to add new diary entries for today? (y/N): ")
            .strip()
            .lower()
        )
        if user_input != "y":
            return None

        today_key = datetime.now().date()
        diary[today_key] = {}

        sentence_number = 0
        while True:
            primary_sentence = input(
                f"\nEnter sentence {sentence_number} in your primary language: "
            ).strip()

            if primary_sentence == "":
                confirm = input(
                    "You entered an empty sentence. Press enter again to confirm and stop adding sentences, or type anything to continue: "
                ).strip()
                if confirm == "":
                    print("No more sentences will be added.")
                    break
                else:
                    continue  # User mistyped – let them re-enter the sentence

            trial_translation = input(
                "Try to translate it into the study language (press Enter to skip): "
            ).strip()
            if trial_translation == "":
                print(
                    "Empty input detected – this will be saved as an empty trial translation."
                )

            diary[today_key]["sentences"] = dict()
            diary[today_key]["sentences"][sentence_number] = {
                "study_language_sentence": "",
                "study_language_sentence_trial": trial_translation,
                "primary_language_sentence": primary_sentence,
                "tips": "",
            }

            sentence_number += 1

        if diary[today_key] == {}:
            return None
        else:
            if self.new_diary:
                self.write_diary(diary)
            else:
                return diary

    def anki_model_def(self):
        # Define the model for Anki cards
        self.anki_model = Model(
            model_id=3602398329,
            name=f"{self.config['languages']['primary_language'].title()}-{self.config['languages']['study_language'].title()} Model",
            fields=[
                {"name": self.config["languages"]["primary_language"].title()},
                {"name": self.config["languages"]["study_language"].title()},
                {"name": "Tips"},
                {"name": "Audio"},
                {"name": "Date"},
                {"name": "SentenceNumber"},
            ],
            templates=[
                {
                    "name": f"{self.config['languages']['primary_language'].title()} to {self.config['languages']['study_language'].title()}",
                    "qfmt": f"{{{{{self.config['languages']['primary_language'].title()}}}}}",
                    "afmt": f"""
                    {{{{FrontSide}}}}<hr id="answer">
                    <div style="background-color:#f0f0f0; padding:10px; border-radius:8px;">
                    <div style="color:#009933; font-size:1em;">{{{{{self.config["languages"]["study_language"].title()}}}}}</div>
                    <div style="color:#666; font-size:0.9em; margin-top:5px;"><em>{{{{Tips}}}}</em></div>
                    </div>
                    <center>{{{{Audio}}}}</center>

                    """,
                },
                {
                    "name": f"{self.config['languages']['study_language'].title()} to {self.config['languages']['primary_language'].title()}",
                    "qfmt": "{{Audio}}",
                    "afmt": f"""
                            <div style="font-weight:bold; font-size:1.2em; color:#0073e6;">
                            {{{{FrontSide}}}}<hr id="answer">
                            </div>
                            <div style="background-color:#f0f0f0; padding:10px; border-radius:8px;">
                            <div style="color:#333; font-size:1em;">{{{{{self.config["languages"]["study_language"].title()}}}}}</div>
                            <hr style="border: 1px solid #0073e6;">
                            <div style="color:#009933; font-size:1em;">{{{{{self.config["languages"]["primary_language"].title()}}}}}</div>
                            <div style="color:#666; font-size:0.9em; margin-top:5px;"><em>{{{{Tips}}}}</em></div>
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

    def read_markdown_file(self, markdown_path):
        """
        Read the content of the markdown file.

        Returns:
            str: Content of the markdown file.
        """
        # with open(self.markdown_diary_path, "r", encoding="utf-8") as file:
        with open(markdown_path, "r", encoding="utf-8") as file:
            return self.clean_joplin_markdown(file.read())

    def clean_joplin_markdown(self, content: str):
        # Define a regular expression pattern that matches the section starting with "id:" followed by "parent_id:" and others in order
        pattern = (
            # r"(id:\s+[a-z0-9]+.*?parent_id:\s+[a-z0-9]+.*?created_time:\s+[0-9TZ:-]+.*)"
            r"(id:\s+[a-z0-9]+.*)"
        )

        # Find the first occurrence of the unwanted section and slice the content up to that point
        clean_content = re.split(pattern, content, maxsplit=1)[0]

        return clean_content.strip()  # Optionally strip any leading/trailing whitespace

    def create_main_deck(self):
        """
        Create the main Anki deck.

        Args:
            deck_name (str): Name of the main deck.

        Returns:
            Deck: The main Anki deck object.
        """
        return Deck(deck_id=hash(self.deck_name), name=self.deck_name)

    def process_day_block_anki(self, day_block):
        """
        Process a day block and add notes to the deck.

        Args:
            day_block (dict): dict for a specific day.

        Returns:
            list: List of notes for the day.
        """
        date, day_dict = day_block
        title = day_dict["title"]

        self.logging.info(f"Processing day: {date} - {title}")

        notes = []
        media_files = []
        for sentence_no, sentence in day_dict["sentences"].items():
            primary_language_sentence = sentence["primary_language_sentence"]
            tips = sentence["tips"]
            study_language_sentence = sentence["study_language_sentence"]

            if study_language_sentence:
                self.logging.info(
                    f"Sentence in {self.config['languages']['primary_language']}: {primary_language_sentence}"
                )
                self.logging.info(
                    f"Sentence in {self.config['languages']['study_language']}: {study_language_sentence}"
                )
                note, media_file = self.create_note(
                    primary_language_sentence,
                    study_language_sentence,
                    tips,
                    date,
                    sentence_no,
                )
                if note and media_file:
                    note.guid = self.generate_unique_id(
                        primary_language_sentence
                    )  # create unique id https://github.com/kerrickstaley/genanki/issues/61
                    notes.append(note)
                    media_files.append(media_file)

        # create a mp3 per day of all the notes to be listened with an audio player
        playlist_media = [AudioSegment.from_mp3(mp3_file) for mp3_file in media_files]

        combined = AudioSegment.empty()
        for sentence in playlist_media:
            combined += (
                sentence * self.config["tts"]["repeat_sentence_diary"]
            )  # repeat audio n times so that it's easier to remember

        combined.export(
            os.path.join(
                f"{self.output_dir}",
                "DAILY_AUDIO",
                f"{self.deck_name.replace(':', '')}_{date.strftime('%Y-%m-%d')}_{self.titles_dict[date]}.mp3",
            ),
            format="mp3",
        )

        return notes, media_files

    def create_note(
        self,
        primary_language_sentence,
        study_language_sentence,
        tips,
        date,
        i,
    ):
        """
        Create a note for the subdeck.

        Args:
            primary_language_sentence (str): primary_language_sentence sentence.
            study_language_sentence (str): study_language_sentence translation.
            tips (str): tips about study_language_sentence translation.
            date (datetime): Date tag.
            sub_deck_name (str): Name of the subdeck.
            i (int): number of the sentence in diary

        Returns:
            Note: Anki Note object.
        """
        study_language_sentence = study_language_sentence.replace("**", "").strip()
        primary_language_sentence = primary_language_sentence.replace("**", "").strip()
        self.logging.info(f"Creating TTS audio for: {study_language_sentence}")

        if study_language_sentence == "":
            return None, None

        if self.tts_model == "gtts":
            self.logging.info("Using gTTS")
            tts = gTTS(
                text=study_language_sentence,
                lang=self.config["languages"]["study_language_code"],
            )
            audio_filename = os.path.join(
                tempfile.gettempdir(), f"{hash(study_language_sentence)}.mp3"
            )
            tts.save(audio_filename)
        elif self.tts_model == "piper":
            self.logging.info("Using piper-tts")
            piper_config = {
                "module": "ovos-tts-plugin-piper",
                "ovos-tts-plugin-piper": {
                    "voice": self.config["tts"]["piper"]["voice"]
                },
            }

            # Load the TTS module dynamically
            TTSClass = load_tts_plugin(piper_config["module"])
            e = TTSClass(config=piper_config["ovos-tts-plugin-piper"])

            e.length_scale = self.config["tts"]["piper"]["piper_length_scale_diary"]

            audio_filename = os.path.join(
                tempfile.gettempdir(), f"{hash(study_language_sentence)}.wav"
            )
            e.get_tts(
                study_language_sentence,
                audio_filename,
                lang=self.config["languages"]["study_language_code"],
                voice=self.config["tts"]["piper"]["voice"],
            )

            # convert to mp3
            audio = AudioSegment.from_wav(audio_filename)
            audio.export(audio_filename.replace(".wav", ".mp3"), format="mp3")
            audio_filename = audio_filename.replace(".wav", ".mp3")
            os.remove(audio_filename.replace(".mp3", ".wav"))
            self.logging.info(f"{audio_filename}")
        else:
            raise ValueError

        date = date.strftime("%Y/%m/%d")
        note = Note(
            model=self.anki_model,
            fields=[
                primary_language_sentence.strip(),
                study_language_sentence,
                tips,
                date,
                f"[sound:{os.path.basename(audio_filename)}]",
                str(i).zfill(2),
            ],
            tags=[date],
        )

        return note, audio_filename

    def convert_diary_entries_to_ankideck(self):
        """
        Parse the markdown file and generate Anki flashcards with audio.

        Args:
            markdown_path (str): Path to the markdown file.
            deck_name (str): Name of the main deck.
            output_dir (str): Path to the output directory.
        """
        self.validate_arguments()

        if not self.config["create_anki_deck"]:
            return

        diary_dict = self.markdown_diary_to_dict()

        main_deck = self.create_main_deck()
        all_notes = []
        all_media_files = []

        for day_block in diary_dict.items():
            note, media_file = self.process_day_block_anki(day_block)
            if note and media_file:
                all_notes.extend(note)
                all_media_files.extend(media_file)

        for note in all_notes:
            main_deck.add_note(note)

        output_path = self.output_dir or tempfile.mkdtemp()
        deck_file = os.path.join(output_path, f"{self.deck_name}.apkg")

        package = Package(main_deck)
        package.media_files = all_media_files
        package.write_to_file(deck_file)

        for f in all_media_files:
            os.remove(f)

        self.logging.info(f"Anki deck created: {deck_file}")

    def extract_dates_from_md(self, markdown_path):
        text = self.read_markdown_file(markdown_path)
        # Regex pattern to match lines starting with ## followed by a date (YYYY/MM/DD)
        pattern = r"^##\s(\d{4}/\d{2}/\d{2})"

        # Extract matching date strings
        date_strings = re.findall(pattern, text, re.MULTILINE)

        # Convert to datetime format
        dates = [datetime.strptime(date, "%Y/%m/%d") for date in date_strings]
        return dates

    def get_title_for_date(self, text, target_date):
        # Convert datetime to string format used in the text (YYYY/MM/DD)
        target_date_str = target_date.strftime("%Y/%m/%d")

        # Regex pattern to match headers (## YYYY/MM/DD ...)
        pattern = r"^## (\d{4}/\d{2}/\d{2})(.*)"

        lines = text.split("\n")

        title_exists = None
        for line in lines:
            match = re.match(pattern, line)
            if match:
                # If this is the target date, start capturing text
                if match.group(1) == target_date_str:
                    # check for title
                    # if there is a column after the date,
                    # this means there is a title created by openai. then catch it! otherwise create it
                    if ":" in match.group(2):
                        title_exists = match.group(2).replace(":", "").strip()
                        break
                    else:
                        title_exists = None
                        continue
        return title_exists  # Skip the header itself

    def get_text_for_date(self, text, target_date):
        # Convert datetime to string format used in the text (YYYY/MM/DD)
        target_date_str = target_date.strftime("%Y/%m/%d")

        # Regex pattern to match headers (## YYYY/MM/DD ...)
        pattern = r"^## (\d{4}/\d{2}/\d{2}).*"

        lines = text.split("\n")
        capture = False
        extracted_lines = []

        for line in lines:
            match = re.match(pattern, line)
            if match:
                # If this is the target date, start capturing text
                if match.group(1) == target_date_str:
                    capture = True
                    continue  # Skip the header itself
                # If a new date is found and we were capturing, stop capturing
                elif capture:
                    break

            # Capture lines belonging to the target date
            if capture:
                extracted_lines.append(line)

        return "\n".join(extracted_lines).strip()

    def get_sentences_from_diary(self, day_block):
        answer_template = self.config["template_diary"]["answer"]
        tips_template = self.config["template_diary"]["tips"]
        trial_template = self.config["template_diary"]["trial"]

        pattern = (
            rf"-\s*\*\*(.*?)\*\*.*?"  # The diary entry summary inside bold **
            rf"{trial_template}\s*(.*?)\s*"  # Trial text after template
            rf"{answer_template}\s*(.*?)\s*"  # Answer text after template
            rf"{tips_template}\s*(.*?)\s*(?=-|\Z)"  # Tips text after template until next '-' or end
        )

        entries = re.findall(pattern, day_block, re.DOTALL | re.MULTILINE)

        if not any(entry[2] for entry in entries):
            self.logging.warning(f"Skipping day as it has no valid translations.")
            return None

        study_language_sentences = []
        for entry in entries:
            (
                primary_language_sentence,
                study_language_sentence_trial,
                study_language_sentence,
                tips,
            ) = entry
            study_language_sentences.append(study_language_sentence.strip())

        return study_language_sentences

    def openai_create_day_title(self, sentences_block_dict):
        sentences = [
            dict[1]["study_language_sentence"] for dict in sentences_block_dict.items()
        ]

        prompt = f"""
        Given the following sentences (written as python array) in {self.config["languages"]["study_language"]},
        could you create in no more than 5/6 words a catchy title about them?
        - Don't use commas, exclamation marks, column.
        - if you need a comma, use a -


        give the result as text in {self.config["languages"]["study_language"]}

        The sentences are:
            {sentences}
        """

        client = OpenAI(api_key=self.config["openai"]["key"])

        response = client.chat.completions.create(
            model=self.config["openai"]["model"],
            messages=[
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": prompt},
            ],
        )
        # Extract and parse the JSON response
        output = response.choices[0].message.content
        return output

    def openai_translate_sentence(self, sentence_dict):
        prompt = f"""
        You need to translate a sentence given in {self.config["languages"]["primary_language"]} into {self.config["languages"]["study_language"]}].
        The output should be a JSON dictionary where:
        - The main key is "sentence".
        - Under "sentence" is another dictionnary with 3 keys:
            - the "primary_language_sentence" to translate.
            - the "study_language_sentences" is the translation you need to create
            - the "tips" is some tips to explain the translation. The tips should be written in the studying language.
        - **DO NOT invent extra words or modify the original meaning of the sentence.**
        - If the primary_language_sentence is not grammatically correct, or if there are minor issues, you could fix the grammar and ponctuation only.
        - if the primary_language_sentence has reference about I, as me, you should know that my gender is {self.config["gender"]} as this will be useful to have the proper grammar and ending on words

        Example output format:

        {{
            "sentence": {{
                    "study_language_sentence": "Torsdag var en spesiell dag. Vi dro til Lakseøya, en ganske fancy restaurant.",
                    "primary_language_sentence": "Thursday was a special day. We went to the Salmon Isle. A pretty fancy restaurant.",
                    "tips": "\"pretty fancy\" kan oversettes som \"ganske fancy\" eller \"ganske fin\", men \"fancy\" brukes også ofte på norsk",
                }}
        }}


        ### Now generate the dictionnary for this sentences  "{sentence_dict["primary_language_sentence"]}"
        """

        # Make the API call

        client = OpenAI(api_key=self.config["openai"]["key"])

        response = client.chat.completions.create(
            model=self.config["openai"]["model"],
            messages=[
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": prompt},
            ],
            response_format={"type": "json_object"},
        )

        # Extract and parse the JSON response
        output = response.choices[0].message.content
        output = json.loads(output)
        output["sentence"]["study_language_sentence_trial"] = sentence_dict[
            "study_language_sentence_trial"
        ]
        return output["sentence"]

    def get_all_days_title(self, diary_dict):
        titles_dict = {}

        if self.new_diary:
            for date_diary in diary_dict:
                title_day = self.openai_create_day_title(
                    diary_dict[date_diary]["sentences"]
                )
                self.logging.info(
                    f"created title with openai for {date_diary} - {title_day}"
                )
                titles_dict[date_diary] = title_day

        else:
            for date_diary in diary_dict:
                if date_diary in diary_dict.keys():
                    title_day = self.get_title_for_date(self.all_diary_text, date_diary)
                    if title_day is None:
                        if not any(
                            not sentence_info.get("study_language_sentence")
                            for diary in diary_dict.values()
                            for sentence_info in diary.get("sentences", {}).values()
                        ):
                            title_day = self.openai_create_day_title(
                                diary_dict[date_diary]["sentences"]
                            )
                            self.logging.info(
                                f"created title with openai for {date_diary} - {title_day}"
                            )
                        else:
                            self.logging.info(
                                "Title not created as sentences are not created yet"
                            )
                    titles_dict[date_diary] = title_day

        self.titles_dict = titles_dict
        return titles_dict

    def write_diary(self, diary_dict):
        # create one mardkown files for all entries
        self.get_all_days_title(diary_dict)

        # replace None to empty strings, otherwise None will be written
        self.titles_dict = {
            k: (v if v is not None else "") for k, v in self.titles_dict.items()
        }

        self.logging.info(
            f"Writing diary to {self.markdown_script_generated_diary_path}"
        )
        self.logging.info(diary_dict)
        with open(
            self.markdown_script_generated_diary_path, "w", encoding="utf-8"
        ) as file:
            for date_diary in diary_dict:
                if self.titles_dict[date_diary] == "":
                    file.write(f"## {date_diary.strftime('%Y/%m/%d')} \n")

                else:
                    file.write(
                        f"## {date_diary.strftime('%Y/%m/%d')}: {self.titles_dict[date_diary]} \n"
                    )
                for sentence_no, sentence_dict in diary_dict[date_diary][
                    "sentences"
                ].items():
                    file.write(f"- **{sentence_dict['primary_language_sentence']}**\n")
                    file.write(
                        f"  {self.config['template_diary']['trial']} {sentence_dict['study_language_sentence_trial']}\n"
                    )
                    file.write(
                        f"  {self.config['template_diary']['answer']} {sentence_dict['study_language_sentence']}\n"
                    )
                    file.write(
                        f"  {self.config['template_diary']['tips']} {sentence_dict['tips']}\n\n"
                    )

        for date_diary in diary_dict:
            if date_diary in diary_dict.keys():
                diary_day_txt_filename = os.path.join(
                    self.output_dir,
                    "DAILY_AUDIO",
                    f"{self.deck_name.replace(':', '')}_{date_diary.strftime('%Y-%m-%d')}_{self.titles_dict[date_diary]}.md",
                )

                if self.titles_dict[date_diary] == "":
                    continue

                os.makedirs(os.path.join(self.output_dir, "DAILY_AUDIO"), exist_ok=True)
                if self.titles_dict[date_diary] is None:
                    continue

                self.logging.info(f"Writing daily diary to {diary_day_txt_filename}")
                with open(diary_day_txt_filename, "w", encoding="utf-8") as file:
                    file.write(
                        f"## {date_diary.strftime('%Y/%m/%d')}: {self.titles_dict[date_diary]} \n"
                    )
                    for sentence_no, sentence_dict in diary_dict[date_diary][
                        "sentences"
                    ].items():
                        file.write(
                            f"- **{sentence_dict['primary_language_sentence']}**\n"
                        )
                        file.write(
                            f"  {self.config['template_diary']['trial']} {sentence_dict['study_language_sentence_trial']}\n"
                        )
                        file.write(
                            f"  {self.config['template_diary']['answer']} {sentence_dict['study_language_sentence']}\n"
                        )
                        file.write(
                            f"  {self.config['template_diary']['tips']} {sentence_dict['tips']}\n\n"
                        )

    def markdown_diary_to_dict(self):
        dates_diary = self.extract_dates_from_md(self.markdown_diary_path)
        all_diary_text = self.read_markdown_file(self.config["markdown_diary_path"])
        self.all_diary_text = all_diary_text

        diary_dict = {}
        for date_diary in dates_diary:
            day_block_text = self.get_text_for_date(all_diary_text, date_diary)
            answer_template = self.config["template_diary"]["answer"]
            tips_template = self.config["template_diary"]["tips"]
            trial_template = self.config["template_diary"]["trial"]

            pattern = (
                rf"-\s*\*\*(.*?)\*\*.*?"  # The diary entry summary inside bold **
                rf"{trial_template}\s*(.*?)\s*"  # Trial text after template
                rf"{answer_template}\s*(.*?)\s*"  # Answer text after template
                rf"{tips_template}\s*(.*?)\s*(?=-|\Z)"  # Tips text after template until next '-' or end
            )

            entries = re.findall(pattern, day_block_text, re.DOTALL | re.MULTILINE)

            if not any(entry[2] for entry in entries):
                self.logging.warning(f"{date_diary} has no valid translations.")

            i = 0
            diary_day_dict = {}
            for (
                primary_language_sentence,
                study_language_sentence_trial,
                study_language_sentence,
                tips,
            ) in entries:
                diary_day_dict[i] = {
                    "study_language_sentence": study_language_sentence.strip(),
                    "study_language_sentence_trial": study_language_sentence_trial.strip(),
                    "primary_language_sentence": primary_language_sentence.replace(
                        "**", ""
                    ).strip(),
                    "tips": tips.strip(),
                }

                diary_dict[date_diary] = dict()
                diary_dict[date_diary]["sentences"] = diary_day_dict
                i += 1

        titles_dict = self.get_all_days_title(diary_dict)
        for date_diary in dates_diary:
            diary_dict[date_diary]["title"] = titles_dict[date_diary]

        return diary_dict

    def diary_complete_translations(self):
        diary_dict = self.markdown_diary_to_dict()
        if self.diary_new_entries_day:
            diary_dict = self.diary_new_entries_day | diary_dict

        for date_diary, date_dict in diary_dict.items():
            for sentence_no, sentence_dict in date_dict["sentences"].items():
                primary_language_sentence = sentence_dict["primary_language_sentence"]
                if sentence_dict["study_language_sentence"] == "":
                    self.logging.info(
                        f"create missing diary entry with openai for {primary_language_sentence.strip()}"
                    )
                    if self.config["create_diary_answers_auto"]:
                        res = self.openai_translate_sentence(sentence_dict)
                        diary_dict[date_diary]["sentences"][sentence_no] = res

        self.write_diary(diary_dict)


class TprsCreation(DiaryHandler):
    def __init__(self, config_path=None):
        super().__init__(config_path)
        self.markdown_tprs_path = self.config["markdown_tprs_path"]

        self.setup_output_tprs_markdown()
        if not os.path.exists(self.markdown_tprs_path):
            self.create_first_tprs_md_file()

        os.makedirs(os.path.join(f"{self.output_dir}", "TPRS"), exist_ok=True)
        self.get_all_tprs_titles()
        self.get_all_diary_titles()

    def setup_output_tprs_markdown(self):
        time_now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        if self.config["overwrite_tprs_markdown"]:
            # backing up original file, and add bak.timestamp
            if os.path.exists(self.markdown_tprs_path):
                shutil.copy(
                    self.markdown_tprs_path,
                    self.markdown_tprs_path.replace(
                        ".md",
                        f".md.bak_{time_now_str}",
                    ).replace(
                        os.path.basename(self.markdown_tprs_path),
                        "." + os.path.basename(self.markdown_tprs_path),
                    ),
                )
                self.markdown_script_generated_tprs_all_path = self.markdown_tprs_path
            else:
                self.markdown_script_generated_tprs_all_path = self.markdown_tprs_path

        else:
            # if overwrite is False, we need to replace the output_dir
            org_dir_path = os.path.dirname(self.markdown_tprs_path)
            self.markdown_script_generated_tprs_all_path = self.markdown_tprs_path
            if org_dir_path == self.output_dir:
                # same dir, modify filename
                self.markdown_script_generated_tprs_all_path = (
                    self.markdown_script_generated_tprs_all_path.replace(
                        ".md", f"_{time_now_str}.md"
                    )
                )

            else:
                # different dir, filename stays the same
                self.markdown_script_generated_tprs_all_path = (
                    self.markdown_script_generated_tprs_all_path.replace(
                        org_dir_path, self.output_dir
                    )
                )

    def create_first_tprs_md_file(self):
        diary_dict = self.markdown_diary_to_dict()
        tprs_dict = {}
        for diary_date in diary_dict:
            tprs_dict[diary_date] = dict()

            for sentences in diary_dict[diary_date]["sentences"].items():
                for sentence_no, sentence_dict in diary_dict[diary_date][
                    "sentences"
                ].items():
                    qa_dict = self.openai_tprs(sentence_dict["study_language_sentence"])
                    tprs_dict[diary_date][
                        sentence_dict["study_language_sentence"]
                    ] = qa_dict

        self.write_tprs_dict_to_md(tprs_dict)

    def get_all_tprs_titles(self):
        self.titles_dict = {}
        if not os.path.exists(self.markdown_tprs_path):
            return

        content = self.read_markdown_file(self.markdown_tprs_path)
        days = re.split(r"^##\s+", content, flags=re.MULTILINE)
        for day_block in days:
            if day_block.strip():
                day_match = re.match(r"^(\d{4}/\d{2}/\d{2})(.*)", day_block)
                if day_match:
                    date = day_match.group(1)
                    title = day_match.group(2).replace(":", "").strip()
                    self.titles_dict[datetime.strptime(date, "%Y/%m/%d")] = title

    def get_all_diary_titles(self):
        self.titles_diary_dict = {}

        content = self.read_markdown_file(self.markdown_script_generated_diary_path)

        days = re.split(r"^##\s+", content, flags=re.MULTILINE)
        for day_block in days:
            if day_block.strip():
                day_match = re.match(r"^(\d{4}/\d{2}/\d{2})(.*)", day_block)
                if day_match:
                    date = day_match.group(1)
                    title = day_match.group(2).replace(":", "").strip()
                    self.titles_diary_dict[datetime.strptime(date, "%Y/%m/%d")] = title

    def read_tprs_day_block(self, day_block):
        """
        Process a day block.

        Args:
            day_block (str): Block of text for a specific day.

        Returns:
            list: List of notes for the day.
        """
        if not day_block.strip():
            return None, None

        # pattern where ## from .split()
        day_match = re.match(r"^(\d{4}/\d{2}/\d{2})(.*)", day_block)

        # normal full pattern
        if not day_match:
            day_match = re.match(r"^## (\d{4}/\d{2}/\d{2})(.*)", day_block)

        ## pattern with title
        if not day_match:
            day_match = re.match(r"^(\d{4}-\d{2}-\d{2})\s+(.*)", day_block)
            if not day_match:
                return None, None

        date = day_match.group(1)
        title = day_match.group(2).replace(":", "").strip()

        self.logging.info(f"Processing day: {date} - {title}")

        result = defaultdict(list)
        current_setning = None
        current_question = None

        for line in day_block.split("\n"):
            line = line.strip()
            if line.startswith(self.config["template_tprs"]["sentence"]):
                current_setning = line[
                    len(self.config["template_tprs"]["sentence"]) :
                ].strip()
            elif (
                line.startswith(self.config["template_tprs"]["question"])
                and current_setning
            ):
                current_question = line[
                    len(self.config["template_tprs"]["question"]) :
                ].strip()
            elif (
                line.startswith(self.config["template_tprs"]["answer"])
                and current_setning
                and current_question
            ):
                answer = line[len(self.config["template_tprs"]["answer"]) :].strip()
                result[current_setning].append((current_question, answer))
                current_question = None  # Reset question after storing the pair

        return result, date

    def create_tprs_audio(self, day_block, date):
        tprs_audio_lesson_filepath = os.path.join(
            f"{self.output_dir}",
            "TPRS",
            f"{self.config['tprs_lesson_name']}_TPRS_{date.replace('/', '-')}_{self.titles_dict[datetime.strptime(date, '%Y/%m/%d')]}.mp3",
        )

        # reprocessing existing audio file depending on config
        if (
            os.path.exists(tprs_audio_lesson_filepath)
            and not self.config["overwrite_tprs_audio"]
        ):
            self.logging.info(f"TPRS file for {date} already processed")
            return

        self.logging.info(f"Generating TPRS file for {date}")

        e = PiperTTSPlugin()

        e.length_scale = self.config["tts"]["piper"]["piper_length_scale_tprs"]

        # create a pause file
        pause_filename = os.path.join(tempfile.gettempdir(), f"{hash('pause')}.wav")
        paused_duration = self.config["tts"]["pause_between_sentences_duration"]  # ms
        pause_segment = AudioSegment.silent(duration=paused_duration)
        pause_segment.export(pause_filename, format="wav")

        media_files = []
        for sentence, tprs_qa in day_block.items():
            audio_filename = os.path.join(
                tempfile.gettempdir(), f"{hash(sentence)}.wav"
            )

            # add main sentence
            e.get_tts(
                sentence,
                audio_filename,
                lang=self.config["languages"]["study_language_code"],
                voice=self.config["tts"]["piper"]["voice"],
            )
            media_files.append(audio_filename)
            media_files.append(pause_filename)

            self.logging.info(f"SENTENCE: {sentence}")
            for question, answer in tprs_qa:
                # create question file
                audio_filename = os.path.join(
                    tempfile.gettempdir(), f"{hash(question)}.wav"
                )
                e.get_tts(
                    question,
                    audio_filename,
                    lang=self.config["languages"]["study_language_code"],
                    voice=self.config["tts"]["piper"]["voice"],
                )
                media_files.append(audio_filename)
                media_files.append(pause_filename)

                # create a silent file
                audio_filename = os.path.join(
                    tempfile.gettempdir(), f"{hash('silence')}.wav"
                )
                silence_duration = (
                    self.config["tts"]["answer_silence_duration"]
                    / self.config["tts"]["repeat_sentence_tprs"]
                )  # ms
                silenced_segment = AudioSegment.silent(duration=silence_duration)
                silenced_segment.export(audio_filename, format="wav")
                media_files.append(audio_filename)

                # create answer file
                audio_filename = os.path.join(
                    tempfile.gettempdir(), f"{hash(answer)}.wav"
                )
                e.get_tts(
                    answer,
                    audio_filename,
                    lang=self.config["languages"]["study_language_code"],
                    voice=self.config["tts"]["piper"]["voice"],
                )
                media_files.append(audio_filename)
                media_files.append(pause_filename)

                self.logging.info(f"  QUESTION: {question}")
                self.logging.info(f"  ANSWER: {answer}")

        e.stop()
        # create a mp3 per day of all the notes to be listened with an audio player
        playlist_media = [AudioSegment.from_mp3(mp3_file) for mp3_file in media_files]

        combined = AudioSegment.empty()
        for sentence in playlist_media:
            combined += (
                sentence * self.config["tts"]["repeat_sentence_tprs"]
            )  # repeat audio n times so that it's easier to remember

        combined.export(
            tprs_audio_lesson_filepath,
            format="mp3",
        )

        # cleaning
        for f in np.unique(media_files):
            os.remove(f)
        return

    def convert_tts_tprs_entries(self):
        self.validate_arguments()

        # using the newly generated file by default!
        if os.path.exists(self.markdown_script_generated_tprs_all_path):
            content = self.read_markdown_file(
                self.markdown_script_generated_tprs_all_path
            )
        else:
            content = self.read_markdown_file(self.markdown_tprs_path)

        days = re.split(r"^##\s+", content, flags=re.MULTILINE)

        for day_block in days:
            if day_block.strip():
                result, date = self.read_tprs_day_block(day_block)
                if result:
                    self.create_tprs_audio(result, date)
        self.logging.info("All diary entries converted into TPRS entries")

    def openai_tprs(self, study_language_sentence):
        # Define the prompt
        prompt = f"""
        We are working on a TPRS (Teaching Proficiency through Reading and Storytelling) method to learn {self.config["languages"]["study_language"]}.
        From the following {self.config["languages"]["study_language"]} sentence, generate a few questions and answers.
        The output should be a JSON dictionary where:
        - The main keys are numbers (starting from 1) as strings.
        - Each value is another dictionary with two keys: "question" and "answer".
        - **DO NOT invent extra words or modify the original meaning of the sentence.**
        - If the sentence contains an unusual phrase, keep it as is.
        - **Questions must be logically sound and relevant to the sentence.**
        - **Avoid questions that are vague, redundant, or unnatural.**
        - If a question doesn’t make sense with the given sentence, rephrase it or skip it.
        - Ensure that the **answers are complete and natural responses**, not just one-word replies.


        Example output format:
        {{
            "1": {{"question": "Hvor sitter katten?", "answer": "Katten sitter på bordet."}},
            "2": {{"question": "Hva gjør katten?", "answer": "Den sitter."}}
        }}

        ### Example:
        Input sentence: "Fredag var Johanne veldig syk. Vi ble hjemme og dro for å fiske med Emil og Mati. Jeg var den første som fanget noe – min første norske fisk."

        Expected questions and answers:
        {{
            "1": {{"question": "Hva skjedde med Johanne på fredag?", "answer": "Johanne var veldig syk."}},
            "2": {{"question": "Hva gjorde vi etter at Johanne var syk?", "answer": "Vi ble hjemme og senere dro vi for å fiske med Emil og Mati."}},
            "3": {{"question": "Hvem var de vi dro for å fiske med?", "answer": "Vi dro for å fiske med Emil og Mati."}},
            "4": {{"question": "Hva var spesielt med fisken jeg fanget?", "answer": "Det var min første norske fisk."}}
        }}

        ### Now generate logical questions and answers for this {self.config["languages"]["study_language"]} sentence: "{study_language_sentence}"
        """

        # Make the API call

        client = OpenAI(api_key=self.config["openai"]["key"])

        response = client.chat.completions.create(
            model=self.config["openai"]["model"],
            messages=[
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": prompt},
            ],
            response_format={"type": "json_object"},
        )

        # Extract and parse the JSON response
        output = response.choices[0].message.content
        qa_dict = json.loads(output)
        return qa_dict

    def create_tprs_block_day(self, study_language_sentences):
        multiline_text = ""

        for study_language_sentence in study_language_sentences:
            self.logging.info(study_language_sentence)
            qa_dict = self.openai_tprs(study_language_sentence)
            multiline_text += f"{self.config['template_tprs']['sentence']} {study_language_sentence.strip()}\n"  # Add each item with a newline

            for id, item in qa_dict.items():
                multiline_text += f"{self.config['template_tprs']['question']} {item['question'].strip()}\n"  # Add each item with a newline
                multiline_text += f"{self.config['template_tprs']['answer']} {item['answer'].strip()}\n"  # Add each item with a newline

            multiline_text += "\n"

        return multiline_text

    def read_tprs_to_dict(self):
        if os.path.exists(self.markdown_script_generated_tprs_all_path):
            content = self.read_markdown_file(
                self.markdown_script_generated_tprs_all_path
            )
        elif os.path.exists(self.markdown_tprs_path):
            content = self.read_markdown_file(self.markdown_tprs_path)
        else:
            return None

        days = re.split(r"^##\s+", content, flags=re.MULTILINE)
        tprs_dict = {}
        for day_block in days:
            if day_block.strip():
                result, date = self.read_tprs_day_block(day_block)
                date = datetime.strptime(date, "%Y/%m/%d")
                tprs_dict[date] = dict()
                for sentence in result.keys():
                    qa_dict = {
                        str(i + 1): {"question": q, "answer": a}
                        for i, (q, a) in enumerate(result[sentence])
                    }

                    tprs_dict[date][sentence] = dict()
                    tprs_dict[date][sentence] = qa_dict

        return tprs_dict

    def check_missing_sentences_from_existing_tprs(self):
        # TODO: ceate code to check if a new sentence was added manually to the main diary, but now missing from the individual TPRS lesson for a day
        tprs_dict = self.read_tprs_to_dict()

        if tprs_dict is None:  # when the TPRS file hasnt been created yet
            return

        diary_dict = self.markdown_diary_to_dict()
        new_tprs_dict = {}  # to preserver order and add missing sentences if applicable
        for date_diary in tprs_dict.keys():
            diary_day_dict = diary_dict[date_diary]
            diary_day_dict_all_sentences = [
                s["study_language_sentence"]
                for no, s in diary_day_dict["sentences"].items()
            ]
            new_tprs_dict[date_diary] = dict()
            for sentence in diary_day_dict_all_sentences:
                new_tprs_dict[date_diary][sentence] = dict()
                if sentence not in tprs_dict[date_diary].keys():
                    self.config[
                        "overwrite_tprs_audio"
                    ] = True  # overwrite config to recreate them since some parts are missing

                    self.logging.info(
                        f"{date_diary} - Missing sentence {sentence} from TPRS output"
                    )
                    qa_dict = self.openai_tprs(sentence)
                    new_tprs_dict[date_diary][sentence] = qa_dict
                else:
                    new_tprs_dict[date_diary][sentence] = tprs_dict[date_diary][
                        sentence
                    ]

        self.write_tprs_dict_to_md(new_tprs_dict)
        return new_tprs_dict

    def write_tprs_dict_to_md(self, tprs_dict):
        with open(
            self.markdown_script_generated_tprs_all_path, "w", encoding="utf-8"
        ) as file:
            # multiline_text = ""

            for date_diary in tprs_dict.keys():
                file.write(
                    f"## {date_diary.strftime('%Y/%m/%d')}: {self.titles_dict[date_diary]}\n"
                )
                for study_language_sentence in tprs_dict[date_diary].keys():
                    qa_dict = tprs_dict[date_diary][study_language_sentence]
                    file.write(
                        f"{self.config['template_tprs']['sentence']} {study_language_sentence.strip()}\n"
                    )  # Add each item with a newline

                    for id, item in qa_dict.items():
                        file.write(
                            f"{self.config['template_tprs']['question']} {item['question'].strip()}\n"
                        )  # Add each item with a newline
                        file.write(
                            f"{self.config['template_tprs']['answer']} {item['answer'].strip()}\n"
                        )  # Add each item with a newline

                    file.write("\n")

        # create a markdown tprs file per day for convenience
        for date_diary in tprs_dict.keys():
            tprs_day_txt_filename = os.path.join(
                self.output_dir,
                "TPRS",
                f"{self.config['tprs_lesson_name']}_TPRS_{date_diary.strftime('%Y-%m-%d')}_{self.titles_dict[date_diary]}.md",
            )

            os.makedirs(os.path.join(f"{self.output_dir}", "TPRS"), exist_ok=True)
            with open(tprs_day_txt_filename, "w", encoding="utf-8") as file:
                file.write(
                    f"## {date_diary.strftime('%Y/%m/%d')}: {self.titles_dict[date_diary]}\n"
                )

                for study_language_sentence in tprs_dict[date_diary].keys():
                    qa_dict = tprs_dict[date_diary][study_language_sentence]
                    file.write(
                        f"{self.config['template_tprs']['sentence']} {study_language_sentence.strip()}\n"
                    )  # Add each item with a newline

                    for id, item in qa_dict.items():
                        file.write(
                            f"{self.config['template_tprs']['question']} {item['question'].strip()}\n"
                        )  # Add each item with a newline
                        file.write(
                            f"{self.config['template_tprs']['answer']} {item['answer'].strip()}\n"
                        )  # Add each item with a newline

                    file.write("\n")

    def add_missing_tprs(self):
        dates_tprs = self.extract_dates_from_md(self.markdown_tprs_path)

        # if the diary markdown file generated by the script exists, we privilege it as it has the most up to date
        diary_path = self.markdown_script_generated_diary_path

        dates_diary = self.extract_dates_from_md(diary_path)
        missing_dates_tprs = list(set(dates_diary) - set(dates_tprs))
        missing_dates_tprs.sort()

        all_diary_text = self.read_markdown_file(diary_path)
        all_tprs_text = self.read_markdown_file(self.markdown_tprs_path)

        tprs_dict = {}
        for dt in dates_tprs:
            tprs_dict[dt] = self.get_text_for_date(all_tprs_text, dt)

        for missing_date_tprs in missing_dates_tprs:
            self.logging.info(f"Missing TPRS entries for {missing_date_tprs.date()}")
            day_block_text = self.get_text_for_date(all_diary_text, missing_date_tprs)
            study_language_sentences = self.get_sentences_from_diary(day_block_text)

            if study_language_sentences:
                tprs_block_day_text = self.create_tprs_block_day(
                    study_language_sentences
                )

                tprs_dict[missing_date_tprs] = tprs_block_day_text

        # add missing titles from diary to tprs
        for date_diary in dates_diary:
            if date_diary not in self.titles_dict.keys():
                self.titles_dict[date_diary] = self.titles_diary_dict[date_diary]

        # append tprs_block_day_text to top of markdown_tprs_path
        with open(
            self.markdown_script_generated_tprs_all_path, "w", encoding="utf-8"
        ) as file:
            for date_diary in dates_diary:
                if date_diary in tprs_dict.keys():
                    file.write(
                        f"## {date_diary.strftime('%Y/%m/%d')}: {self.titles_dict[date_diary]}\n"
                    )
                    file.write(tprs_dict[date_diary])
                    file.write("\n\n")

        # create a markdown tprs file per day for convenience
        for date_diary in dates_diary:
            if date_diary in tprs_dict.keys():
                tprs_day_txt_filename = os.path.join(
                    self.output_dir,
                    "TPRS",
                    f"{self.config['tprs_lesson_name']}_TPRS_{date_diary.strftime('%Y-%m-%d')}_{self.titles_dict[date_diary]}.md",
                )
                with open(tprs_day_txt_filename, "w", encoding="utf-8") as file:
                    file.write(
                        f"## {date_diary.strftime('%Y/%m/%d')}: {self.titles_dict[date_diary]}\n"
                    )
                    file.write(tprs_dict[date_diary])
                    file.write("\n\n")


def main():
    diary_instance = DiaryHandler()
    diary_instance.prompt_new_diary_entry()
    diary_instance.diary_complete_translations()
    diary_instance.convert_diary_entries_to_ankideck()
    diary_instance.stop()

    tprs_instance = TprsCreation()
    tprs_instance.check_missing_sentences_from_existing_tprs()
    tprs_instance.add_missing_tprs()
    tprs_instance.convert_tts_tprs_entries()
    tprs_instance.stop()


if __name__ == "__main__":
    main()
