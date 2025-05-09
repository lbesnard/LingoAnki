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
from typing import Callable

import numpy as np
import yaml
from genanki import Deck, Model, Note, Package
from gtts import gTTS
from openai import OpenAI
from ovos_plugin_manager.tts import load_tts_plugin
from ovos_tts_plugin_piper import PiperTTSPlugin
from piper import PiperVoice
from platformdirs import user_config_dir
from pydub import AudioSegment

APP_NAME = "lingoDiary"
CONFIG_FILE = "config.yaml"


class DiaryHandler:
    def __init__(self, config_path=None):
        """Initializes the DiaryHandler with configuration and sets up necessary attributes.

        Args:
            config_path (str, optional): Path to the configuration file. 
                                         Defaults to None, which then uses the default user config path.
        """
        self.config = self.load_config(config_path=config_path)
        self.markdown_diary_path = self.config["markdown_diary_path"]
        self.deck_name = self.config["anki_deck_name"]
        self.output_dir = self.config["output_dir"]
        self.backup_dir = os.path.join(self.output_dir, ".backup")
        self.tts_model = self.config["tts"]["model"]
        self.diary_new_entries_day = None
        self.template_help_string = self.template_help()

        self.setup_logging()
        self.validate_arguments()

        self.setup_output_diary_markdown()
        self.anki_model_def()

    def load_config(self, config_path=None):
        """Loads the YAML configuration file.

        Args:
            config_path (str, optional): The path to the configuration file. 
                                         If None, uses the default user config path. 
                                         Defaults to None.

        Returns:
            dict: The loaded configuration as a dictionary.

        Raises:
            FileNotFoundError: If the configuration file is not found.
        """
        if config_path is None:
            config_path = Path(user_config_dir(APP_NAME)).joinpath(CONFIG_FILE)

        if os.path.exists(config_path):
            with open(config_path) as f:
                return yaml.safe_load(f) or {}

        logger = logging.getLogger(__name__)
        logger.error(f"Please create configuration file {config_path}")
        raise FileNotFoundError

    def setup_output_diary_markdown(self):
        """Sets up the path for the output diary Markdown file.

        Handles backup of the original diary file if overwrite is enabled.
        Manages naming conventions for the output file based on whether
        it's being called by DiaryHandler or a subclass (like TprsCreation).
        """
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
        """Sets up logging for the application.

        Configures a logger with both file and stream handlers if not already set up.
        Logs are written to 'output.log' in the configured output directory.
        """
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
        """Closes all logging handlers associated with this instance's logger."""
        if hasattr(self, "logging"):
            logger = self.logging
            handlers = logger.handlers[:]
            for handler in handlers:
                handler.close()
                logger.removeHandler(handler)

    def stop(self):
        """Stops the DiaryHandler by closing logging resources."""
        self.close_logging()

    def validate_arguments(self):
        """Validates the markdown diary path and output directory.

        If the markdown diary path does not exist, it creates an empty file.
        If the output directory does not exist, it attempts to create it.
        Also creates a backup directory.

        Raises:
            ValueError: If the output directory cannot be created.
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
        """Generates a help string showing the template for diary entries.

        Returns:
            str: A multiline string illustrating the diary entry template.
        """
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
        """Prompts the user to add new diary entries if configured to do so.

        This method checks the configuration and, if called by DiaryHandler,
        invokes `_prompt_new_diary_entry` to interact with the user.
        The result is stored in `self.diary_new_entries_day`.
        """
        if self.config["diary_entries_prompt_user"]:
            if self.__class__.__name__ == "DiaryHandler":
                self.diary_new_entries_day = self._prompt_new_diary_entry()
        else:
            self.diary_new_entries_day = None
            return

    def _prompt_new_diary_entry(self):
        """Interactively prompts the user to add new diary entries for the current day.

        Collects sentences in the primary language and optional trial translations
        in the study language from the user.

        Returns:
            dict or None: A dictionary containing the new diary entries for today,
                          structured by date and sentence number. Returns None if
                          the user chooses not to add entries or adds no sentences.
        """
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
        """Defines the Anki card model structure.

        Sets up the fields and templates for the Anki cards that will be generated.
        The model includes fields for primary language, study language, tips, audio,
        date, and sentence number. It also defines two card templates: one for
        primary to study language, and one for study language (audio) to primary.
        """
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
        """Generates a unique ID based on a hash of the input string.

        Args:
            input_string (str): The string to hash.
            length (int, optional): The length of the unique ID to generate. 
                                    Defaults to 9.

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
        """Reads the content of the specified markdown file.

        Args:
            markdown_path (str): The path to the markdown file.

        Returns:
            str: The cleaned content of the markdown file.
        """
        # with open(self.markdown_diary_path, "r", encoding="utf-8") as file:
        with open(markdown_path, "r", encoding="utf-8") as file:
            return self.clean_joplin_markdown(file.read())

    def clean_joplin_markdown(self, content: str):
        """Removes Joplin-specific metadata from markdown content.

        This function targets metadata lines starting with "id:" and removes
        them along with any subsequent related metadata lines.

        Args:
            content (str): The raw markdown content.

        Returns:
            str: The markdown content with Joplin metadata removed.
        """
        # Define a regular expression pattern that matches the section starting with "id:" followed by "parent_id:" and others in order
        pattern = (
            # r"(id:\s+[a-z0-9]+.*?parent_id:\s+[a-z0-9]+.*?created_time:\s+[0-9TZ:-]+.*)"
            r"(id:\s+[a-z0-9]+.*)"
        )

        # Find the first occurrence of the unwanted section and slice the content up to that point
        clean_content = re.split(pattern, content, maxsplit=1)[0]

        return clean_content.strip()  # Optionally strip any leading/trailing whitespace

    def create_main_deck(self):
        """Creates the main Anki deck.

        The deck ID is generated by hashing the deck name.

        Returns:
            genanki.Deck: The main Anki deck object.
        """
        return Deck(deck_id=hash(self.deck_name), name=self.deck_name)

    def process_day_block_anki(self, day_block):
        """Processes a single day's entries to create Anki notes and a daily audio compilation.

        Args:
            day_block (tuple): A tuple containing the date (datetime.date) and 
                               a dictionary of the day's entries. 
                               The dictionary includes a title and sentences.

        Returns:
            tuple: A tuple containing:
                - list: A list of genanki.Note objects for the day.
                - list: A list of paths to the media files (audio) for these notes.
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
        """Creates an Anki note and its corresponding TTS audio.

        Args:
            primary_language_sentence (str): The sentence in the primary language.
            study_language_sentence (str): The sentence in the study language.
            tips (str): Learning tips related to the translation.
            date (datetime.date): The date of the diary entry.
            i (int): The sentence number within the diary entry for that day.

        Returns:
            tuple: A tuple containing:
                - genanki.Note or None: The created Anki note, or None if the study
                  language sentence is empty.
                - str or None: The path to the generated audio file, or None if no
                  audio was created.
        
        Raises:
            ValueError: If an unsupported TTS model is specified in the config.
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
        """Parses diary entries and generates an Anki deck with flashcards and audio.

        If `create_anki_deck` is False in the configuration, this method returns early.
        It reads the diary, processes each day's entries, creates notes and audio,
        and packages them into an .apkg file.
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
        """Extracts all dates from headers in a markdown file.

        Dates are expected to be in 'YYYY/MM/DD' format following '## '.

        Args:
            markdown_path (str): The path to the markdown file.

        Returns:
            list[datetime.datetime]: A list of dates found in the markdown file.
        """
        text = self.read_markdown_file(markdown_path)
        # Regex pattern to match lines starting with ## followed by a date (YYYY/MM/DD)
        pattern = r"^##\s(\d{4}/\d{2}/\d{2})"

        # Extract matching date strings
        date_strings = re.findall(pattern, text, re.MULTILINE)

        # Convert to datetime format
        dates = [datetime.strptime(date, "%Y/%m/%d") for date in date_strings]
        return dates

    def get_title_for_date(self, text, target_date):
        """Extracts the title associated with a specific date from markdown text.

        The title is expected to follow the date in a header, separated by a colon.
        e.g., "## YYYY/MM/DD: Title of the day"

        Args:
            text (str): The markdown content to search within.
            target_date (datetime.datetime): The date for which to find the title.

        Returns:
            str or None: The extracted title, or None if no title is found for the date.
        """
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
        """Extracts the block of text associated with a specific date from markdown.

        This includes all lines under a date header (e.g., "## YYYY/MM/DD")
        until the next date header or the end of the text.

        Args:
            text (str): The markdown content to search within.
            target_date (datetime.datetime): The date for which to extract text.

        Returns:
            str: The block of text associated with the target date.
        """
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
        """Extracts study language sentences from a block of diary text for a specific day.

        Parses the day_block using configured templates for trial, answer, and tips.

        Args:
            day_block (str): The markdown text block for a single day's diary entries.

        Returns:
            list[str] or None: A list of study language sentences extracted from the block.
                               Returns None if no valid translations are found.
        """
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
        """Generates a catchy title for a day's diary entries using OpenAI.

        The title is based on the study language sentences for that day.

        Args:
            sentences_block_dict (dict): A dictionary where keys are sentence numbers
                                         and values are dictionaries containing sentence details,
                                         including "study_language_sentence".

        Returns:
            str: The generated title in the study language.
        """
        sentences = [
            entry["study_language_sentence"] for entry in sentences_block_dict.values()
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
        """Translates a sentence from the primary language to the study language using OpenAI.

        Also generates learning tips for the translation. The request considers the user's
        gender for grammatically correct translations.

        Args:
            sentence_dict (dict): A dictionary containing the "primary_language_sentence"
                                  and "study_language_sentence_trial".

        Returns:
            dict: A dictionary containing the "primary_language_sentence",
                  "study_language_sentence" (the translation), "tips", and
                  "study_language_sentence_trial".
        """
        prompt = f"""
        You need to translate a sentence given in {self.config["languages"]["primary_language"]} into {self.config["languages"]["study_language"]}].
        The output should be a JSON dictionary where:
        - The main key is "sentence".
        - Under "sentence" is another dictionnary with 3 keys:
            - the "primary_language_sentence" to translate.
            - the "study_language_sentence" is the translation you need to create
            - the "tips" is some tips to explain the translation. The tips should be written in {self.config["languages"]["primary_language"]}.
        - **DO NOT invent extra words or modify the original meaning of the sentence.**
        - If the primary_language_sentence is not grammatically correct, or if there are minor issues, you could fix the grammar and ponctuation only.
        - if the primary_language_sentence has reference about I, as me, you should know that my gender is {self.config["gender"]} as this will be useful to have the proper grammar and ending on words
        - Generate a sentence that is ready to be spoken by a Text-to-Speech system. Expand abbreviations that are not normally spoken as-is (e.g., 'km/h' should become 'kilometers per hour'), but keep common spoken abbreviations (e.g., 'AM', 'PM') unchanged. Ensure the result is natural for TTS. Adapt abbreviation expansion appropriately to the target language {self.config["languages"]["study_language"]}.
        - In addition, when generating text for non-English languages, expand non-spoken abbreviations according to natural usage in that language (e.g., in French, 'km/h' ➔ 'kilomètres par heure').

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
        """Gets or generates titles for all days in the diary_dict.

        If the diary is new or a title is missing for an existing entry,
        it uses OpenAI to generate a title based on the day's sentences.
        Otherwise, it attempts to extract existing titles from the diary markdown.

        Args:
            diary_dict (dict): A dictionary of diary entries, keyed by date.

        Returns:
            dict: A dictionary where keys are dates and values are the titles for those dates.
                  This dictionary is also stored in `self.titles_dict`.
        """
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
        """Writes the processed diary entries to markdown files.

        This includes a main diary markdown file and individual markdown files
        for each day's audio content. Titles for each day are retrieved or generated.

        Args:
            diary_dict (dict): A dictionary of diary entries, keyed by date.
                               Each entry contains sentences with translations and tips.
        """
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
                    file.write(
                        f"## {date_diary.strftime('%Y/%m/%d')} \n"
                    )  # to respect regexp and look for title

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
        """Parses the main diary markdown file into a structured dictionary.

        Extracts dates, titles, and individual sentence entries (primary language,
        trial translation, study language translation, and tips) from the markdown.

        Returns:
            dict: A dictionary where keys are dates (datetime.date objects) and
                  values are dictionaries containing the "title" for the day and
                  a "sentences" dictionary. The "sentences" dictionary is keyed
                  by sentence number and contains details for each sentence.
        """
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
        """Completes missing translations in the diary using OpenAI.

        Reads the current diary into a dictionary, merges any new entries prompted
        from the user, and then iterates through all entries. If a study language
        sentence is missing and automatic translation is enabled in the config,
        it calls OpenAI to generate the translation and tips. Finally, writes
        the updated diary back to the markdown file.
        """
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
        """Initializes the TprsCreation class, inheriting from DiaryHandler.

        Sets up paths for TPRS markdown files (standard, enhanced, future, present).
        Creates these files if they don't exist. Also initializes directories
        for TPRS output and fetches titles for TPRS and diary entries.

        Args:
            config_path (str, optional): Path to the configuration file. 
                                         Defaults to None.
        """
        super().__init__(config_path)
        self.markdown_tprs_path = self.config["markdown_tprs_path"]
        self.markdown_tprs_enhanced_path = self.markdown_tprs_path.replace(
            ".md", "_Enhanced.md"
        )
        self.markdown_tprs_future_path = self.markdown_tprs_path.replace(
            ".md", "_Future.md"
        )
        self.markdown_tprs_present_path = self.markdown_tprs_path.replace(
            ".md", "_Present.md"
        )

        self.setup_output_tprs_markdown()
        if not os.path.exists(self.markdown_tprs_path):
            self.create_first_tprs_md_file()

        if not os.path.exists(self.markdown_tprs_enhanced_path):
            self.create_first_tprs_enhanced_md_file()

        if not os.path.exists(self.markdown_tprs_future_path):
            self.create_first_tprs_future_md_file()

        if not os.path.exists(self.markdown_tprs_present_path):
            self.create_first_tprs_present_md_file()

        os.makedirs(os.path.join(f"{self.output_dir}", "TPRS"), exist_ok=True)
        self.get_all_tprs_titles()
        self.get_all_diary_titles()

    def setup_output_tprs_markdown(self):
        """Sets up paths for various TPRS output markdown files.

        Handles backup of existing TPRS files if overwrite is enabled in the config.
        Manages naming conventions for output files based on configuration
        (overwrite vs. new timestamped files, output directory).
        This method sets paths for standard, enhanced, future, and present
        tense TPRS markdown files.
        """
        time_now_str = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")  # filename-safe

        def backup_if_exists(src_path):
            if os.path.exists(src_path):
                bak_path = src_path.replace(".md", f".md.bak_{time_now_str}").replace(
                    os.path.basename(src_path),
                    "." + os.path.basename(src_path),
                )
                shutil.copy(src_path, bak_path)
            return src_path

        if self.config["overwrite_tprs_markdown"]:
            self.markdown_script_generated_tprs_all_path = backup_if_exists(
                self.markdown_tprs_path
            )
            self.markdown_script_generated_tprs_enhanced_all_path = backup_if_exists(
                self.markdown_tprs_enhanced_path
            )
            self.markdown_script_generated_tprs_future_all_path = backup_if_exists(
                self.markdown_tprs_future_path
            )
            self.markdown_script_generated_tprs_present_all_path = backup_if_exists(
                self.markdown_tprs_present_path
            )

        else:
            # Always set default values first
            org_dir_path = os.path.dirname(self.markdown_tprs_path)
            self.markdown_script_generated_tprs_all_path = self.markdown_tprs_path
            self.markdown_script_generated_tprs_enhanced_all_path = (
                self.markdown_tprs_enhanced_path
            )
            self.markdown_script_generated_tprs_future_all_path = (
                self.markdown_tprs_future_path
            )
            self.markdown_script_generated_tprs_present_all_path = (
                self.markdown_tprs_present_path
            )

            if org_dir_path == self.output_dir:
                # same dir, modify filenames with timestamp
                self.markdown_script_generated_tprs_all_path = (
                    self.markdown_script_generated_tprs_all_path.replace(
                        ".md", f"_{time_now_str}.md"
                    )
                )
                self.markdown_script_generated_tprs_enhanced_all_path = (
                    self.markdown_script_generated_tprs_enhanced_all_path.replace(
                        ".md", f"_{time_now_str}.md"
                    )
                )
                self.markdown_script_generated_tprs_future_all_path = (
                    self.markdown_script_generated_tprs_future_all_path.replace(
                        ".md", f"_{time_now_str}.md"
                    )
                )
                self.markdown_script_generated_tprs_present_all_path = (
                    self.markdown_script_generated_tprs_present_all_path.replace(
                        ".md", f"_{time_now_str}.md"
                    )
                )
            else:
                # different dir, replace dir part only
                self.markdown_script_generated_tprs_all_path = (
                    self.markdown_script_generated_tprs_all_path.replace(
                        org_dir_path, self.output_dir
                    )
                )
                self.markdown_script_generated_tprs_enhanced_all_path = (
                    self.markdown_script_generated_tprs_enhanced_all_path.replace(
                        org_dir_path, self.output_dir
                    )
                )
                self.markdown_script_generated_tprs_future_all_path = (
                    self.markdown_script_generated_tprs_future_all_path.replace(
                        org_dir_path, self.output_dir
                    )
                )
                self.markdown_script_generated_tprs_present_all_path = (
                    self.markdown_script_generated_tprs_present_all_path.replace(
                        org_dir_path, self.output_dir
                    )
                )

    def _generate_tprs_md_file(
        self,
        tprs_generator_fn,
        write_fn,
        needs_existing_tprs=False,
        log_prefix="Creating TPRS content for",
    ):
        """Generates TPRS content for diary entries using a specified generator function.

        Iterates through diary entries, generates TPRS questions and answers
        using `tprs_generator_fn`, and then writes the output using `write_fn`.
        Can optionally use existing TPRS content if `needs_existing_tprs` is True.

        Args:
            tprs_generator_fn (Callable): Function to generate TPRS Q&A for a sentence.
                                          Takes a sentence (str) and optionally existing Q&A (dict).
            write_fn (Callable): Function to write the generated TPRS dictionary to a file.
                                 Takes the TPRS dictionary (dict).
            needs_existing_tprs (bool, optional): Whether `tprs_generator_fn` requires
                                                  existing TPRS data. Defaults to False.
            log_prefix (str, optional): Prefix for log messages.
                                        Defaults to "Creating TPRS content for".
        """
        diary_dict = self.markdown_diary_to_dict()
        output_dict = {}
        existing_tprs = self.read_tprs_to_dict() if needs_existing_tprs else {}

        for diary_date, date_entry in diary_dict.items():
            output_dict[diary_date] = {}

            for sentence_no, sentence_dict in date_entry["sentences"].items():
                sentence = sentence_dict["study_language_sentence"]
                self.logging.info(f'{log_prefix} "{sentence}"')

                if needs_existing_tprs:
                    existing_qa = existing_tprs[diary_date][sentence]
                    qa_dict = tprs_generator_fn(sentence, existing_qa)
                    output_dict[diary_date].update(qa_dict)
                else:
                    qa_dict = tprs_generator_fn(sentence)
                    output_dict[diary_date][sentence] = qa_dict

                self.logging.info(json.dumps(qa_dict, indent=2, ensure_ascii=False))

            write_fn(output_dict)

    def create_first_tprs_md_file(self):
        """Creates the initial standard TPRS markdown file if it doesn't exist.

        Uses `openai_tprs` to generate content and `write_tprs_dict_to_md` to save it.
        """
        self._generate_tprs_md_file(
            tprs_generator_fn=self.openai_tprs,
            write_fn=self.write_tprs_dict_to_md,
            log_prefix="Creating TPRS content for",
        )

    def create_first_tprs_enhanced_md_file(self):
        """Creates the initial enhanced TPRS markdown file if it doesn't exist.

        Uses `openai_tprs_enhanced` and existing TPRS data to generate content,
        and `write_tprs_enhanced_dict_to_md` to save it.
        """
        self._generate_tprs_md_file(
            tprs_generator_fn=self.openai_tprs_enhanced,
            write_fn=self.write_tprs_enhanced_dict_to_md,
            needs_existing_tprs=True,
            log_prefix="Creating a TPRS alternative version content for",
        )

    def create_first_tprs_future_md_file(self):
        """Creates the initial future tense TPRS markdown file if it doesn't exist.

        Uses `openai_tprs_future` and existing TPRS data to generate content,
        and `write_tprs_future_dict_to_md` to save it.
        """
        self._generate_tprs_md_file(
            tprs_generator_fn=self.openai_tprs_future,
            write_fn=self.write_tprs_future_dict_to_md,
            needs_existing_tprs=True,
            log_prefix="Creating TPRS in the Future version content for",
        )

    def create_first_tprs_present_md_file(self):
        """Creates the initial present tense TPRS markdown file if it doesn't exist.

        Uses `openai_tprs_present` and existing TPRS data to generate content,
        and `write_tprs_present_dict_to_md` to save it.
        """
        self._generate_tprs_md_file(
            tprs_generator_fn=self.openai_tprs_present,
            write_fn=self.write_tprs_present_dict_to_md,
            needs_existing_tprs=True,
            log_prefix="Creating TPRS in the Present version content for",
        )

    def get_all_tprs_titles(self):
        """Extracts all TPRS titles from the main TPRS markdown file.

        Populates `self.titles_dict` with dates as keys and titles as values.
        If the TPRS markdown file doesn't exist, it does nothing.
        """
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
        """Extracts all titles from the script-generated diary markdown file.

        Populates `self.titles_diary_dict` with dates as keys and titles as values.
        """
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
        """Parses a block of TPRS markdown text for a single day.

        Extracts the date, title, and TPRS questions and answers.
        The TPRS Q&A are structured as a dictionary where keys are sentences
        and values are lists of (question, answer) tuples.

        Args:
            day_block (str): The markdown text block for a single day's TPRS entries.

        Returns:
            tuple: A tuple containing:
                - collections.defaultdict(list) or None: A dictionary of TPRS Q&A
                  for the day, or None if the block is empty.
                - str or None: The date string (YYYY/MM/DD) for the block, or None.
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

    def _create_tprs_audio_generic(self, day_block, date, suffix=""):
        """Generates a TPRS audio lesson for a given day's content.

        This is a generic helper function used by specific TPRS audio creation methods.
        It synthesizes audio for sentences, questions, and answers, adding pauses
        and silences as configured. The final audio is saved as an MP3 file.

        Args:
            day_block (dict): A dictionary where keys are sentences and values are
                              lists of (question, answer) tuples for a specific day.
            date (str): The date string (YYYY/MM/DD) for the lesson.
            suffix (str, optional): A suffix to append to the output filename
                                    (e.g., "_enhanced", "_future"). Defaults to "".
        """
        tprs_audio_lesson_filepath = os.path.join(
            self.output_dir,
            "TPRS",
            f"{self.config['tprs_lesson_name']}_TPRS_{date.replace('/', '-')}_{self.titles_dict[datetime.strptime(date, '%Y/%m/%d')]}{suffix}.mp3",
        )

        if (
            os.path.exists(tprs_audio_lesson_filepath)
            and not self.config["overwrite_tprs_audio"]
        ):
            self.logging.info(f"TPRS file for {date} already processed")
            return

        self.logging.info(f"Generating TPRS file for {date}")
        e = PiperTTSPlugin()
        e.length_scale = self.config["tts"]["piper"]["piper_length_scale_tprs"]

        pause_filename = os.path.join(tempfile.gettempdir(), f"{hash('pause')}.wav")
        paused_duration = self.config["tts"]["pause_between_sentences_duration"]
        pause_segment = AudioSegment.silent(
            duration=paused_duration / self.config["tts"]["repeat_sentence_tprs"]
        )
        pause_segment.export(pause_filename, format="wav")

        media_files = []
        for sentence, tprs_qa in day_block.items():
            self.logging.info(f"Generating audio for {sentence}")
            audio_filename = os.path.join(
                tempfile.gettempdir(), f"{hash(sentence)}.wav"
            )
            e.get_tts(
                sentence,
                audio_filename,
                lang=self.config["languages"]["study_language_code"],
                voice=self.config["tts"]["piper"]["voice"],
            )
            media_files.append(audio_filename)
            media_files.append(pause_filename)

            for question, answer in tprs_qa:
                media_files.append(pause_filename)

                question_audio = os.path.join(
                    tempfile.gettempdir(), f"{hash(question)}.wav"
                )
                e.get_tts(
                    question,
                    question_audio,
                    lang=self.config["languages"]["study_language_code"],
                    voice=self.config["tts"]["piper"]["voice"],
                )
                media_files.append(question_audio)

                silence_file = os.path.join(
                    tempfile.gettempdir(), f"{hash('silence')}.wav"
                )
                silence_duration = (
                    self.config["tts"]["answer_silence_duration"]
                    / self.config["tts"]["repeat_sentence_tprs"]
                )
                AudioSegment.silent(duration=silence_duration).export(
                    silence_file, format="wav"
                )
                media_files.append(silence_file)

                answer_audio = os.path.join(
                    tempfile.gettempdir(), f"{hash(answer)}.wav"
                )
                e.get_tts(
                    answer,
                    answer_audio,
                    lang=self.config["languages"]["study_language_code"],
                    voice=self.config["tts"]["piper"]["voice"],
                )
                media_files.append(answer_audio)
                media_files.append(pause_filename)

                self.logging.info(f"  QUESTION: {question}")
                self.logging.info(f"  ANSWER: {answer}")

        e.stop()

        playlist_media = [AudioSegment.from_wav(wav_file) for wav_file in media_files] # Corrected from_mp3 to from_wav
        combined = AudioSegment.empty()
        for segment in playlist_media:
            for _ in range(self.config["tts"]["repeat_sentence_tprs"]):
                combined += segment
                # Removed redundant pause_segment addition here as pauses are already in media_files

        combined.export(tprs_audio_lesson_filepath, format="mp3")

        for f in np.unique(media_files): # Ensure all temporary .wav files are removed
            if os.path.exists(f):
                os.remove(f)

    def create_tprs_audio(self, day_block, date):
        """Creates standard TPRS audio for a given day's block.

        Args:
            day_block (dict): Parsed TPRS content for the day.
            date (str): Date string for the lesson.
        """
        self._create_tprs_audio_generic(day_block, date)

    def create_tprs_enhanced_audio(self, day_block, date):
        """Creates enhanced TPRS audio for a given day's block.

        Args:
            day_block (dict): Parsed TPRS content for the day.
            date (str): Date string for the lesson.
        """
        self._create_tprs_audio_generic(day_block, date, suffix="_enhanced")

    def create_tprs_future_audio(self, day_block, date):
        """Creates future tense TPRS audio for a given day's block.

        Args:
            day_block (dict): Parsed TPRS content for the day.
            date (str): Date string for the lesson.
        """
        self._create_tprs_audio_generic(day_block, date, suffix="_future")

    def create_tprs_present_audio(self, day_block, date):
        """Creates present tense TPRS audio for a given day's block.

        Args:
            day_block (dict): Parsed TPRS content for the day.
            date (str): Date string for the lesson.
        """
        self._create_tprs_audio_generic(day_block, date, suffix="_present")

    def _convert_tts_tprs_entries(
        self,
        markdown_path_candidates: list[str],
        parse_func: Callable,
        create_func: Callable,
        label: str = "",
    ):
        """Internal helper to convert TPRS markdown entries to TPRS audio.

        Reads TPRS data from a markdown file, parses it, and then uses a
        creation function to generate audio for each day's entries.

        Args:
            markdown_path_candidates (list[str]): A list of possible paths to the
                                                  TPRS markdown file. The first
                                                  existing path will be used.
            parse_func (Callable): Function to parse a day block of TPRS markdown.
                                   Should return parsed data and date.
            create_func (Callable): Function to create TPRS audio from parsed data.
                                    Takes parsed data and date as arguments.
            label (str, optional): A label for logging purposes (e.g., "enhanced ").
                                   Defaults to "".

        Raises:
            FileNotFoundError: If no valid markdown path is found from the candidates.
        """
        self.validate_arguments()

        # Select the first existing path from candidates
        markdown_path = next(
            (p for p in markdown_path_candidates if os.path.exists(p)), None
        )
        if not markdown_path:
            raise FileNotFoundError("No valid markdown path found for TPRS conversion.")

        content = self.read_markdown_file(markdown_path)
        days = re.split(r"^##\s+", content, flags=re.MULTILINE)

        for day_block in days:
            if day_block.strip():
                result, date = parse_func(day_block)
                if result:
                    create_func(result, date)

        self.logging.info(f"All diary entries converted into {label}TPRS entries")

    def convert_tts_tprs_entries(self):
        """Converts standard TPRS markdown entries into TPRS audio lessons."""
        self._convert_tts_tprs_entries(
            markdown_path_candidates=[
                self.markdown_script_generated_tprs_all_path,
                self.markdown_tprs_path,
            ],
            parse_func=self.read_tprs_day_block,
            create_func=self.create_tprs_audio,
            label="",
        )

    def convert_tts_tprs_enhanced_entries(self):
        """Converts enhanced TPRS markdown entries into TPRS audio lessons."""
        self._convert_tts_tprs_entries(
            markdown_path_candidates=[
                self.markdown_script_generated_tprs_enhanced_all_path,
                self.markdown_tprs_enhanced_path,
            ],
            parse_func=self.read_tprs_day_block,
            create_func=self.create_tprs_enhanced_audio,
            label="enhanced ",
        )

    def convert_tts_tprs_future_entries(self):
        """Converts future tense TPRS markdown entries into TPRS audio lessons."""
        self._convert_tts_tprs_entries(
            markdown_path_candidates=[
                self.markdown_script_generated_tprs_future_all_path,
                self.markdown_tprs_future_path,
            ],
            parse_func=self.read_tprs_day_block,
            create_func=self.create_tprs_future_audio,
            label="future ",
        )

    def convert_tts_tprs_present_entries(self):
        """Converts present tense TPRS markdown entries into TPRS audio lessons."""
        self._convert_tts_tprs_entries(
            markdown_path_candidates=[
                self.markdown_script_generated_tprs_present_all_path,
                self.markdown_tprs_present_path,
            ],
            parse_func=self.read_tprs_day_block,
            create_func=self.create_tprs_present_audio,
            label="present ",
        )

    def openai_tprs_enhanced(self, study_language_sentence, qa_org_dict):
        """Generates an enhanced TPRS teaching block using OpenAI.

        Rewrites a given sentence and its original Q&A block for better clarity,
        fluency, and TTS compatibility.

        Args:
            study_language_sentence (str): The original sentence in the study language.
            qa_org_dict (dict): The original TPRS question and answer dictionary
                                for the sentence.

        Returns:
            dict: A new TPRS Q&A dictionary where the key is the revised sentence
                  and the value is a dictionary of new circling-style questions and answers.
        """
        # study_language_sentence = next(iter(qa_org_dict))
        prompt = f"""
        You are an expert in language teaching using the TPRS (Teaching Proficiency through Reading and Storytelling) method.

        Your task is to rewrite a {self.config["languages"]["study_language"]} teaching block using the TPRS method, enhancing it for clarity and spoken fluency with Text-to-Speech (TTS).

        I will give you a teaching block in {self.config["languages"]["study_language"]} that contains:
        - the main key is One or more narrative sentences,
        - containing a sub-json dictionary: A set of comprehension questions and answers, formatted as a Python dictionary like this:
        {{
            "1": {{"question": "Hva skjedde med Johanne på fredag?", "answer": "Johanne var veldig syk."}},
            "2": {{"question": "Hva gjorde vi etter at Johanne var syk?", "answer": "Vi ble hjemme og senere dro vi for å fiske med Emil og Mati."}},
            "3": {{"question": "Hvem var de vi dro for å fiske med?", "answer": "Vi dro for å fiske med Emil og Mati."}},
            "4": {{"question": "Hva var spesielt med fisken jeg fanget?", "answer": "Det var min første norske fisk."}}
        }}


        Follow these guidelines:
        - Generate a revised version of the input sentence: "{study_language_sentence}".
        - Vary the wording slightly for fluency and naturalness.
        - After revising the sentence, generate circling-style questions (yes/no, either/or, open-ended) that cover all key information.
        - Use natural, beginner-friendly language.
        - Add brief synonym explanations or rewordings only if they help understanding.
        - Do not omit any details. Expand abbreviations into natural spoken forms for TTS output in {self.config["languages"]["study_language"]}.
        - Output in {self.config["languages"]["study_language"]} only.
        - Ensure the final output is a single valid JSON object.
        - The **key** must be the revised sentence as a natural language string in {self.config["languages"]["study_language"]}.
        - The **value** must be a dictionary of circling-style questions and answers, where keys are strings of integers starting from "1".

        For example:

        {{
        "Neste morgen, på søndag, var havet helt stille – det glitret som et speil, og det lå lave skyer over det.": {{
            "1": {{"question": "Var det søndag eller mandag morgen?", "answer": "Det var søndag morgen."}},
            "2": {{"question": "Hvordan så havet ut?", "answer": "Det så ut som et speil."}}
        }}
        }}

        Do **not** use keys like "key" or "value". Only use the revised sentence itself as the top-level key.

        Do **not** use placeholder strings like "REVISED SENTENCE".

        Now generate logical questions and answers in {self.config["languages"]["study_language"]} for the following sentence:
        - "{study_language_sentence}"

        Here is the existing Question and Answer block:
        {qa_org_dict}
        """

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

    def openai_tprs_future(self, study_language_sentence, qa_org_dict):
        """Generates a future tense TPRS teaching block using OpenAI.

        Transforms a given sentence and its original Q&A block into the future tense,
        enhancing it for clarity, fluency, and TTS compatibility.

        Args:
            study_language_sentence (str): The original sentence in the study language.
            qa_org_dict (dict): The original TPRS question and answer dictionary
                                for the sentence.

        Returns:
            dict: A new TPRS Q&A dictionary where the key is the revised sentence
                  (in future tense) and the value is a dictionary of new, future-oriented
                  circling-style questions and answers.
        """
        prompt = f"""
        You are an expert in language teaching using the TPRS (Teaching Proficiency through Reading and Storytelling) method.

        Your task is to rewrite a {self.config["languages"]["study_language"]} teaching block using the TPRS method, transforming it into the **future tense** for clarity and spoken fluency with Text-to-Speech (TTS).

        I will give you a teaching block in {self.config["languages"]["study_language"]} that contains:
        - the main key is one or more narrative sentences,
        - containing a sub-json dictionary: a set of comprehension questions and answers, formatted as a Python dictionary like this:
        {{
            "1": {{"question": "Hva skjedde med Johanne på fredag?", "answer": "Johanne var veldig syk."}},
            "2": {{"question": "Hva gjorde vi etter at Johanne var syk?", "answer": "Vi ble hjemme og senere dro vi for å fiske med Emil og Mati."}}
        }}

        Follow these guidelines:
        - Convert the input sentence "{study_language_sentence}" to future tense, as it would be spoken naturally in {self.config["languages"]["study_language"]}.
        - Vary the wording slightly to ensure fluency and naturalness.
        - After revising the sentence, generate circling-style questions (yes/no, either/or, open-ended) that reflect the new future-oriented sentence.
        - Use beginner-friendly vocabulary and phrasing.
        - Add brief synonym explanations or rewordings only when helpful for comprehension.
        - Do not omit any factual content. Expand abbreviations into full, natural spoken forms suitable for TTS.
        - Output in {self.config["languages"]["study_language"]} only.
        - Ensure the final output is a single valid JSON object.
        - The **key** must be the revised sentence in future tense, as a natural sentence in {self.config["languages"]["study_language"]}.
        - The **value** must be a dictionary of circling-style questions and answers, with string keys starting from "1".

        For example:

        {{
        "Neste søndag morgen vil havet være helt stille – det vil glitre som et speil, og det vil være lave skyer over det.": {{
            "1": {{"question": "Vil havet være stille eller stormfullt?", "answer": "Havet vil være stille."}},
            "2": {{"question": "Hvordan vil havet se ut?", "answer": "Det vil glitre som et speil."}}
        }}
        }}

        Do **not** use keys like "key" or "value". Only use the revised sentence itself as the top-level key.

        Do **not** use placeholder strings like "REVISED SENTENCE".

        Now generate logical **future tense** questions and answers in {self.config["languages"]["study_language"]} for the following sentence:
        - "{study_language_sentence}"

        Here is the existing Question and Answer block:
        {qa_org_dict}
        """

        client = OpenAI(api_key=self.config["openai"]["key"])

        response = client.chat.completions.create(
            model=self.config["openai"]["model"],
            messages=[
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": prompt},
            ],
            response_format={"type": "json_object"},
        )

        output = response.choices[0].message.content
        qa_dict = json.loads(output)
        return qa_dict

    def openai_tprs_present(self, study_language_sentence, qa_org_dict):
        """Generates a present tense TPRS teaching block using OpenAI.

        Transforms a given sentence and its original Q&A block into the present tense,
        enhancing it for clarity, fluency, and TTS compatibility.

        Args:
            study_language_sentence (str): The original sentence in the study language.
            qa_org_dict (dict): The original TPRS question and answer dictionary
                                for the sentence.

        Returns:
            dict: A new TPRS Q&A dictionary where the key is the revised sentence
                  (in present tense) and the value is a dictionary of new, present-oriented
                  circling-style questions and answers.
        """
        prompt = f"""
        You are an expert in language teaching using the TPRS (Teaching Proficiency through Reading and Storytelling) method.

        Your task is to rewrite a {self.config["languages"]["study_language"]} teaching block using the TPRS method, transforming it into the **present tense** for clarity and spoken fluency with Text-to-Speech (TTS).

        I will give you a teaching block in {self.config["languages"]["study_language"]} that contains:
        - the main key is one or more narrative sentences,
        - containing a sub-json dictionary: a set of comprehension questions and answers, formatted as a Python dictionary like this:
        {{
            "1": {{"question": "Hva skjer med Johanne på fredag?", "answer": "Johanne er veldig syk."}},
            "2": {{"question": "Hva gjør vi etter at Johanne er syk?", "answer": "Vi blir hjemme og senere drar vi for å fiske med Emil og Mati."}}
        }}

        Follow these guidelines:
        - Convert the input sentence "{study_language_sentence}" to **present tense**, as it would be spoken naturally in {self.config["languages"]["study_language"]}.
        - Vary the wording slightly to ensure fluency and naturalness.
        - After revising the sentence, generate circling-style questions (yes/no, either/or, open-ended) that reflect the new **present-tense** sentence.
        - Use beginner-friendly vocabulary and phrasing.
        - Add brief synonym explanations or rewordings only when helpful for comprehension.
        - Do not omit any factual content. Expand abbreviations into full, natural spoken forms suitable for TTS.
        - Output in {self.config["languages"]["study_language"]} only.
        - Ensure the final output is a single valid JSON object.
        - The **key** must be the revised sentence in present tense, as a natural sentence in {self.config["languages"]["study_language"]}.
        - The **value** must be a dictionary of circling-style questions and answers, with string keys starting from "1".

        For example:

        {{
        "Nå på søndag morgen er havet helt stille – det glitrer som et speil, og det er lave skyer over det.": {{
            "1": {{"question": "Er havet stille eller stormfullt?", "answer": "Havet er stille."}},
            "2": {{"question": "Hvordan ser havet ut?", "answer": "Det glitrer som et speil."}}
        }}
        }}

        Do **not** use keys like "key" or "value". Only use the revised sentence itself as the top-level key.

        Do **not** use placeholder strings like "REVISED SENTENCE".

        Now generate logical **present tense** questions and answers in {self.config["languages"]["study_language"]} for the following sentence:
        - "{study_language_sentence}"

        Here is the existing Question and Answer block:
        {qa_org_dict}
        """

        client = OpenAI(api_key=self.config["openai"]["key"])

        response = client.chat.completions.create(
            model=self.config["openai"]["model"],
            messages=[
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": prompt},
            ],
            response_format={"type": "json_object"},
        )

        output = response.choices[0].message.content
        qa_dict = json.loads(output)
        return qa_dict

    def openai_tprs(self, study_language_sentence):
        """Generates TPRS questions and answers for a given sentence using OpenAI.

        The generated Q&A aims to be natural, logically sound, and suitable for TTS.
        It considers the emotional tone and style of the input sentence.

        Args:
            study_language_sentence (str): The sentence in the study language for which
                                           to generate TPRS content.

        Returns:
            dict: A dictionary where keys are numbers (as strings, starting from "1")
                  and values are dictionaries, each containing a "question" and "answer".
        """
        # Define the prompt

        prompt = f"""
        We are working on a TPRS (Teaching Proficiency through Reading and Storytelling) method to learn {
            self.config["languages"]["study_language"]
        }.
        All output must be written in {self.config["languages"]["study_language"]}.
        From the following {
            self.config["languages"]["study_language"]
        } input, generate a few questions and answers per sentence.
        The output should be a JSON dictionary where:
        - The main keys are numbers (starting from 1) as strings.
        - Each value is another dictionary with two keys: "question" and "answer".
        - **DO NOT invent extra words or modify the original meaning of the sentence.**
        - **Preserve unusual or idiomatic expressions exactly as they appear.**
        - **Questions must be logically sound and relevant to the sentence.**
        - **Make sure the questions and answers sound natural, like a native speaker would actually say them.**
        - Ensure that the **answers are complete, not just one-word replies.**
        - **Avoid overly formal, awkward, or robotic phrases.**
        - Each question should be directly answerable from the sentence, but not repetitive.
        - don't use emojis as this will be converted for TTS
        - The original sentence may include informal, emotional, or sexual language. Do not censor or sanitise it.
        - Interpret the sentence like a native speaker would, even if the content is suggestive or mature.
        - **Questions should explore various aspects of the sentence (who, what, when, how, why), without repeating the same information.**
        - **Try to match the emotional tone or style of the sentence (e.g., casual, funny, dramatic).**
        - **Avoid repeating the same phrasing or vocabulary in both the questions and answers. Use different angles, emotions, or contextual clues to make each question unique.**
        - **You can explore the setting, emotional dynamics, or deeper meanings behind the actions in the sentence.**
        - Generate a sentence that is ready to be spoken by a Text-to-Speech system. Expand abbreviations that are not normally spoken as-is (e.g., 'km/h' should become 'kilometers per hour'), but keep common spoken abbreviations (e.g., 'AM', 'PM') unchanged. Ensure the result is natural for TTS. Adapt abbreviation expansion appropriately to the target language {self.config["languages"]["study_language"]}.
        - In addition, when generating text for non-English languages, expand non-spoken abbreviations according to natural usage in that language (e.g., in French, 'km/h' ➔ 'kilomètres par heure').

         ### Example 1 – Neutral:
        Input sentence: "Fredag var Johanne veldig syk. Vi ble hjemme og dro for å fiske med Emil og Mati. Jeg var den første som fanget noe – min første norske fisk."

        Expected questions and answers:
        {{
            "1": {{"question": "Hva skjedde med Johanne på fredag?", "answer": "Johanne var veldig syk."}},
            "2": {{"question": "Hva gjorde vi etter at Johanne var syk?", "answer": "Vi ble hjemme og senere dro vi for å fiske med Emil og Mati."}},
            "3": {{"question": "Hvem var de vi dro for å fiske med?", "answer": "Vi dro for å fiske med Emil og Mati."}},
            "4": {{"question": "Hva var spesielt med fisken jeg fanget?", "answer": "Det var min første norske fisk."}}
        }}

        ### Example 2 – Sad:
        Input sentence: "Elle est partie sans dire au revoir. Je suis resté seul avec mon café froid."

        Expected questions and answers:
        {{
            "1": {{"question": "Pourquoi est-ce que tu es resté seul ?", "answer": "Parce qu'elle est partie sans dire au revoir."}},
            "2": {{"question": "Qu'est-ce qu'elle a oublié de faire en partant ?", "answer": "Elle n'a pas dit au revoir."}},
            "3": {{"question": "Avec quoi es-tu resté après son départ ?", "answer": "Avec mon café froid... et ma solitude."}}
        }}

        ### Example 3 – Funny:
        Input sentence: "J'ai mis du sel au lieu du sucre dans mon café. Résultat : je me suis réveillé plus vite que prévu."

        Expected questions and answers:
        {{
            "1": {{"question": "Qu'est-ce que tu as mis dans ton café par erreur ?", "answer": "Du sel au lieu du sucre."}},
            "2": {{"question": "Comment as-tu réagi après avoir bu le café ?", "answer": "Je me suis réveillé plus vite que prévu !"}},
            "3": {{"question": "Pourquoi ton café avait un goût bizarre ?", "answer": "Parce qu’il y avait du sel dedans, pas du sucre."}}
        }}


       ### Example 4 - Cheeky (French):
        Input sentence: "Hier soir, elle est rentrée avec un grand sourire... et sans pantalon."

        Expected questions and answers:
        {{"1": {{"question": "Pourquoi elle avait un grand sourire hier soir ?", "answer": "Parce qu'elle est rentrée sans pantalon."}},
            "2": {{"question": "Comment est-elle rentrée hier soir ?", "answer": "Avec un grand sourire et sans pantalon."}},
            "3": {{"question": "Qu'est-ce qu'il manquait à sa tenue ?", "answer": "Elle n'avait pas de pantalon."}},
            "4": {{"question": "On peut deviner pourquoi elle souriait ?", "answer": "Probablement... mais ce n’est pas écrit dans la phrase."}}
        }}

        ### Now generate logical questions and answers in {
            self.config["languages"]["study_language"]
        } for the following sentence: "{study_language_sentence}"
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
        """Creates a markdown block of TPRS content for a list of sentences for one day.

        For each sentence, it generates TPRS questions and answers using `openai_tprs`
        and formats them into a markdown string.

        Args:
            study_language_sentences (list[str]): A list of sentences in the study
                                                  language for a single day.

        Returns:
            str: A multiline string containing the formatted TPRS content for the day.
        """
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

    def create_tprs_other_version_block_day(self, qa_tprs_day_dict):
        """Creates a markdown block for alternative TPRS versions (e.g., enhanced, future).

        Formats a given dictionary of TPRS Q&A (where keys are sentences) into
        a markdown string.

        Args:
            qa_tprs_day_dict (dict): A dictionary where keys are study language sentences
                                     (potentially revised) and values are dictionaries
                                     of their corresponding TPRS questions and answers.

        Returns:
            str: A multiline string containing the formatted TPRS content for the day.
        """
        multiline_text = ""
        for study_language_sentence, qa_dict in qa_tprs_day_dict.items():

            multiline_text += f"{self.config['template_tprs']['sentence']} {study_language_sentence.strip()}\n"  # Add each item with a newline

            for id, item in qa_dict.items():
                multiline_text += f"{self.config['template_tprs']['question']} {item['question'].strip()}\n"  # Add each item with a newline
                multiline_text += f"{self.config['template_tprs']['answer']} {item['answer'].strip()}\n"  # Add each item with a newline

            multiline_text += "\n"

        return multiline_text

    def read_tprs_to_dict(self):
        """Reads the main TPRS markdown file and parses it into a structured dictionary.

        The dictionary is keyed by date (datetime.date objects). Each date entry
        contains another dictionary where keys are sentences and values are
        dictionaries of TPRS questions and answers (keyed by number string).

        Returns:
            dict or None: The parsed TPRS content as a nested dictionary,
                          or None if the TPRS markdown file does not exist.
        """
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
        """Checks for sentences in the diary that are missing from TPRS content.

        Compares sentences in the main diary with those in the parsed TPRS dictionary.
        If a sentence from the diary is not found in the TPRS content for that day,
        it generates new TPRS Q&A for that sentence using `openai_tprs`.
        The updated TPRS content (including new and existing entries) is then
        written back to the TPRS markdown file.

        Returns:
            dict or None: The updated TPRS dictionary, or None if the initial TPRS
                          file doesn't exist.
        """
        # TODO: ceate code to check if a new sentence was added manually to the main diary, but now missing from the individual TPRS lesson for a day
        tprs_dict = self.read_tprs_to_dict()

        if tprs_dict is None:  # when the TPRS file hasnt been created yet
            return

        diary_dict = self.markdown_diary_to_dict()
        new_tprs_dict = {}  # to preserver order and add missing sentences if applicable
        # Iterate over diary dates to ensure all diary entries are considered
        for date_diary in diary_dict.keys():
            if date_diary not in tprs_dict: # If date is not in TPRS, create new entry
                 tprs_dict[date_diary] = {}

            diary_day_dict = diary_dict[date_diary]
            diary_day_dict_all_sentences = [
                s["study_language_sentence"]
                for no, s in diary_day_dict["sentences"].items()
            ]
            new_tprs_dict[date_diary] = dict()
            for sentence in diary_day_dict_all_sentences:
                new_tprs_dict[date_diary][sentence] = dict()
                # Check if sentence is in the TPRS dict for that date
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

    def _write_tprs_dict_to_md_generic(self, tprs_dict, all_path, file_suffix=""):
        """Generic function to write a TPRS dictionary to markdown files.

        Writes a combined markdown file containing all TPRS entries, and also
        individual markdown files for each day.

        Args:
            tprs_dict (dict): The TPRS dictionary to write. Keyed by date, then
                              sentence, then Q&A.
            all_path (str): Path to the combined TPRS markdown file.
            file_suffix (str, optional): Suffix to append to individual day
                                         markdown filenames (e.g., "_enhanced").
                                         Defaults to "".
        """
        with open(all_path, "w", encoding="utf-8") as file:
            for date_diary, sentence_dict in tprs_dict.items():
                file.write(
                    f"## {date_diary.strftime('%Y/%m/%d')}: {self.titles_dict[date_diary]}\n"
                )
                for sentence, qa_dict in sentence_dict.items():
                    file.write(
                        f"{self.config['template_tprs']['sentence']} {sentence.strip()}\n"
                    )
                    for item in qa_dict.values():
                        file.write(
                            f"{self.config['template_tprs']['question']} {item['question'].strip()}\n"
                        )
                        file.write(
                            f"{self.config['template_tprs']['answer']} {item['answer'].strip()}\n"
                        )
                    file.write("\n")

        # Write individual markdown files per day
        tprs_dir = os.path.join(self.output_dir, "TPRS")
        os.makedirs(tprs_dir, exist_ok=True)

        for date_diary, sentence_dict in tprs_dict.items():
            day_filename = (
                f"{self.config['tprs_lesson_name']}_TPRS_{date_diary.strftime('%Y-%m-%d')}_"
                f"{self.titles_dict[date_diary]}{file_suffix}.md"
            )
            full_day_path = os.path.join(tprs_dir, day_filename)
            with open(full_day_path, "w", encoding="utf-8") as file:
                file.write(
                    f"## {date_diary.strftime('%Y/%m/%d')}: {self.titles_dict[date_diary]}\n"
                )
                for sentence, qa_dict in sentence_dict.items():
                    file.write(
                        f"{self.config['template_tprs']['sentence']} {sentence.strip()}\n"
                    )
                    for item in qa_dict.values():
                        file.write(
                            f"{self.config['template_tprs']['question']} {item['question'].strip()}\n"
                        )
                        file.write(
                            f"{self.config['template_tprs']['answer']} {item['answer'].strip()}\n"
                        )
                    file.write("\n")

    def write_tprs_dict_to_md(self, tprs_dict):
        """Writes the standard TPRS dictionary to markdown files.

        Uses `_write_tprs_dict_to_md_generic` for the actual writing.

        Args:
            tprs_dict (dict): The standard TPRS dictionary.
        """
        self._write_tprs_dict_to_md_generic(
            tprs_dict,
            all_path=self.markdown_script_generated_tprs_all_path,
            file_suffix="",
        )

    def write_tprs_enhanced_dict_to_md(self, tprs_dict):
        """Writes the enhanced TPRS dictionary to markdown files.

        Uses `_write_tprs_dict_to_md_generic` with an "_enhanced" suffix.

        Args:
            tprs_dict (dict): The enhanced TPRS dictionary.
        """
        self._write_tprs_dict_to_md_generic(
            tprs_dict,
            all_path=self.markdown_script_generated_tprs_enhanced_all_path,
            file_suffix="_enhanced",
        )

    def write_tprs_future_dict_to_md(self, tprs_dict):
        """Writes the future tense TPRS dictionary to markdown files.

        Uses `_write_tprs_dict_to_md_generic` with a "_future" suffix.

        Args:
            tprs_dict (dict): The future tense TPRS dictionary.
        """
        self._write_tprs_dict_to_md_generic(
            tprs_dict,
            all_path=self.markdown_script_generated_tprs_future_all_path,
            file_suffix="_future",
        )

    def write_tprs_present_dict_to_md(self, tprs_dict):
        """Writes the present tense TPRS dictionary to markdown files.

        Uses `_write_tprs_dict_to_md_generic` with a "_present" suffix.

        Args:
            tprs_dict (dict): The present tense TPRS dictionary.
        """
        self._write_tprs_dict_to_md_generic(
            tprs_dict,
            all_path=self.markdown_script_generated_tprs_present_all_path,
            file_suffix="_present",
        )

    def _add_missing_tprs_generic(
        self,
        tprs_path,
        tprs_all_path,
        version_suffix,
        get_tprs_block_day_text_fn,
    ):
        """Generic function to add missing TPRS entries to a TPRS markdown file.

        Compares dates in the diary with dates in the specified TPRS file.
        For any missing dates, it generates new TPRS content using
        `get_tprs_block_day_text_fn` and appends it.
        Updates both the combined TPRS file and individual day files.

        Args:
            tprs_path (str): Path to the existing TPRS markdown file to check.
            tprs_all_path (str): Path to the combined TPRS markdown file to write/update.
            version_suffix (str): Suffix for versioning (e.g., "enhanced", "future").
                                  Used for logging and filenames.
            get_tprs_block_day_text_fn (Callable): Function to generate the TPRS
                                                   markdown text for a day's sentences
                                                   or existing Q&A.
        """
        dates_tprs = self.extract_dates_from_md(tprs_path)
        diary_path = self.markdown_script_generated_diary_path
        dates_diary = self.extract_dates_from_md(diary_path)

        missing_dates = sorted(set(dates_diary) - set(dates_tprs))
        all_tprs_text = self.read_markdown_file(tprs_path)

        tprs_dict = {dt: self.get_text_for_date(all_tprs_text, dt) for dt in dates_tprs}

        if get_tprs_block_day_text_fn.__name__ == "create_tprs_block_day":
            all_diary_text = self.read_markdown_file(diary_path)
            for dt in missing_dates:
                self.logging.info(f"Missing TPRS entries for {dt.date()}")
                diary_text = self.get_text_for_date(all_diary_text, dt)
                sentences = self.get_sentences_from_diary(diary_text)
                if sentences:
                    tprs_dict[dt] = get_tprs_block_day_text_fn(sentences)
        else:
            existing_tprs = self.read_tprs_to_dict()
            for dt in missing_dates:
                self.logging.info(
                    f"Missing TPRS {version_suffix or 'base'} entries for {dt.date()}"
                )
                qa_dict_day = {}
                for sentence, sentence_dict in existing_tprs[dt].items():
                    qa_dict = get_tprs_block_day_text_fn(sentence, sentence_dict)
                    qa_dict_day.update(qa_dict)
                    self.logging.info(json.dumps(qa_dict, indent=2, ensure_ascii=False))
                tprs_dict[dt] = self.create_tprs_other_version_block_day(qa_dict_day)

        # Update missing titles
        for dt in dates_diary:
            if dt not in self.titles_dict:
                self.titles_dict[dt] = self.titles_diary_dict[dt]

        # Write combined TPRS file
        with open(tprs_all_path, "w", encoding="utf-8") as file:
            for dt in dates_diary:
                if dt in tprs_dict:
                    file.write(
                        f"## {dt.strftime('%Y/%m/%d')}: {self.titles_dict[dt]}\n"
                    )
                    file.write(tprs_dict[dt])
                    file.write("\n\n")

        # Write per-day TPRS markdown files
        for dt in dates_diary:
            if dt in tprs_dict:
                suffix = f"_{version_suffix}" if version_suffix else ""
                filename = os.path.join(
                    self.output_dir,
                    "TPRS",
                    f"{self.config['tprs_lesson_name']}_TPRS_{dt.strftime('%Y-%m-%d')}_{self.titles_dict[dt]}{suffix}.md",
                )
                with open(filename, "w", encoding="utf-8") as file:
                    file.write(
                        f"## {dt.strftime('%Y/%m/%d')}: {self.titles_dict[dt]}\n"
                    )
                    file.write(tprs_dict[dt])
                    file.write("\n\n")

    def add_missing_tprs(self):
        """Adds missing entries to the standard TPRS markdown file.

        Uses `create_tprs_block_day` to generate content for missing dates.
        """
        self._add_missing_tprs_generic(
            tprs_path=self.markdown_tprs_path,
            tprs_all_path=self.markdown_script_generated_tprs_all_path,
            version_suffix="",
            get_tprs_block_day_text_fn=self.create_tprs_block_day,
        )

    def add_missing_tprs_enhanced(self):
        """Adds missing entries to the enhanced TPRS markdown file.

        Uses `openai_tprs_enhanced` to generate content for missing dates.
        """
        self._add_missing_tprs_generic(
            tprs_path=self.markdown_tprs_enhanced_path,
            tprs_all_path=self.markdown_script_generated_tprs_enhanced_all_path,
            version_suffix="enhanced",
            get_tprs_block_day_text_fn=self.openai_tprs_enhanced,
        )

    def add_missing_tprs_future(self):
        """Adds missing entries to the future tense TPRS markdown file.

        Uses `openai_tprs_future` to generate content for missing dates.
        """
        self._add_missing_tprs_generic(
            tprs_path=self.markdown_tprs_future_path,
            tprs_all_path=self.markdown_script_generated_tprs_future_all_path,
            version_suffix="future",
            get_tprs_block_day_text_fn=self.openai_tprs_future,
        )

    def add_missing_tprs_present(self):
        """Adds missing entries to the present tense TPRS markdown file.

        Uses `openai_tprs_present` to generate content for missing dates.
        """
        self._add_missing_tprs_generic(
            tprs_path=self.markdown_tprs_present_path,
            tprs_all_path=self.markdown_script_generated_tprs_present_all_path,
            version_suffix="present",
            get_tprs_block_day_text_fn=self.openai_tprs_present,
        )


def main():
    """Main function to run the diary and TPRS processing workflow.

    Initializes DiaryHandler, prompts for new entries, completes translations,
    and converts entries to an Anki deck.
    Then, initializes TprsCreation, checks for missing TPRS sentences,
    adds missing TPRS content for all versions (standard, enhanced, future, present),
    and finally converts all TPRS markdown entries to audio.
    """
    diary_instance = DiaryHandler()
    diary_instance.prompt_new_diary_entry()
    diary_instance.diary_complete_translations()
    diary_instance.convert_diary_entries_to_ankideck()
    diary_instance.stop()

    tprs_instance = TprsCreation()
    tprs_instance.check_missing_sentences_from_existing_tprs()

    tprs_instance.add_missing_tprs()
    tprs_instance.add_missing_tprs_enhanced()
    tprs_instance.add_missing_tprs_future()
    tprs_instance.add_missing_tprs_present()

    tprs_instance.convert_tts_tprs_entries()
    tprs_instance.convert_tts_tprs_enhanced_entries()
    tprs_instance.convert_tts_tprs_future_entries()
    tprs_instance.convert_tts_tprs_present_entries()

    tprs_instance.stop()


if __name__ == "__main__":
    main()
