#!/usr/bin/env python3
"""
This code converts diary entries written in a foreign language into flashcards to learn more efficently.

Here is the workflow:

1) writing in a markdown file (for example Joplin) sentences in primary_language following the template defined below
2) attempt to write in study_language the sentence (optional)
3) run this script which creates an anki deck and calls openai to fill up the correct answers
4) import the anki deck

Audio "Lessons" will also be generated.


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
from datetime import datetime
from pathlib import Path
from sre_compile import REPEAT_ONE

import openai
import yaml
from genanki import Deck, Model, Note, Package
from gtts import gTTS
from ovos_plugin_manager.tts import load_tts_plugin
from ovos_tts_plugin_piper import PiperTTSPlugin
from piper import PiperVoice
from pydub import AudioSegment

CONFIG_DIR = os.path.join(Path.home(), ".config", "diaryAnki")
CONFIG_PATH = os.path.join(CONFIG_DIR, "config.yaml")


class DiaryHandler:
    def __init__(self):
        self.config = self.load_config()
        self.markdown_diary_path = self.config["markdown_diary_path"]
        self.deck_name = self.config["anki_deck_name"]
        self.output_dir = os.path.dirname(self.config["output_dir"])
        self.tts_model = self.config["tts"]["model"]

        self.validate_arguments()
        self.setup_logging()
        self.setup_output_diary_markdown()
        self.anki_model_def()

        if self.config["diary_entries_prompt_user"]:
            if self.__class__.__name__ == "DiaryHandler":
                self.diary_new_entries_day = self.prompt_new_diary_entry()
        else:
            self.diary_new_entries_day = None

    def load_config(self):
        """Load YAML config if it exists."""
        if os.path.exists(CONFIG_PATH):
            with open(CONFIG_PATH) as f:
                return yaml.safe_load(f) or {}
        raise FileNotFoundError

    def setup_output_diary_markdown(self):
        # doing it this way, as the TPRS class can inherit this DiaryHandler class
        if self.__class__.__name__ == "DiaryHandler":
            time_now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            if self.config["overwrite_diary_markdown"]:
                # backing up original file, and add bak.timestamp
                shutil.copy(
                    self.markdown_diary_path,
                    self.markdown_diary_path.replace(
                        ".md",
                        f".md.bak_{time_now_str}",
                    ).replace(
                        os.path.basename(self.markdown_diary_path),
                        "." + os.path.basename(self.markdown_diary_path),
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
        if not os.path.exists(self.markdown_diary_path):
            raise FileNotFoundError(
                f"Markdown file not found: {self.markdown_diary_path}"
            )

        if self.output_dir:
            if not os.path.exists(self.output_dir):
                try:
                    os.makedirs(self.output_dir, exist_ok=True)
                except Exception as e:
                    raise ValueError(
                        f"Failed to create output directory: {self.output_dir}. Error: {e}"
                    )

    def prompt_new_diary_entry(self):
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

            diary[today_key][sentence_number] = {
                "study_language_sentence": "",
                "study_language_sentence_trial": trial_translation,
                "primary_language_sentence": primary_sentence,
                "tips": "",
            }

            sentence_number += 1

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

    def process_all_days_anki(self, year_block):
        """
        Process a year block and create subdecks.

        Args:
            year_block (str): Block of text for a specific year.
            deck_name (str): Name of the main deck.

        Returns:
            list: List of notes for the year.
        """
        logging.info("Processing all days")

        days = re.split(r"^##\s+", year_block, flags=re.MULTILINE)
        notes = []
        media_files = []

        for day_block in days:
            note, media_file = self.process_day_block_anki(day_block)
            if note and media_file:
                notes.extend(note)
                media_files.extend(media_file)

        return notes, media_files

    def process_day_block_anki(self, day_block):
        """
        Process a day block and add notes to the deck.

        Args:
            day_block (str): Block of text for a specific day.
            year_deck_prefix (str): Prefix for the year deck name.

        Returns:
            list: List of notes for the day.
        """
        if not day_block.strip():
            return None, None

        # day_match = re.match(r"^(\d{4}/\d{2}/\d{2})\s+(.*)", day_block)
        day_match = re.match(r"^(\d{4}/\d{2}/\d{2})(.*)", day_block)
        if not day_match:
            return None, None

        date = day_match.group(1)
        title = day_match.group(2)

        logging.info(f"Processing day: {date} - {title}")

        answer_template = self.config["template_diary"]["answer"]
        tips_template = self.config["template_diary"]["tips"]

        pattern = rf"-(.*?)\n.*?{answer_template}(.*?)\n.*?{tips_template}(.*?)\n"
        entries = re.findall(pattern, day_block, re.DOTALL)

        if not any(entry[1] for entry in entries):
            logging.warning(f"Skipping day {date} as it has no valid translations.")
            return None, None

        notes = []
        media_files = []
        i_sentence = 0
        for primary_language_sentence, study_language_sentence, tips in entries:
            if study_language_sentence:
                logging.info(
                    f"Sentence in {self.config['languages']['primary_language']}: {primary_language_sentence}"
                )
                logging.info(
                    f"Sentence in {self.config['languages']['study_language']}: {study_language_sentence}"
                )
                note, media_file = self.create_note(
                    primary_language_sentence,
                    study_language_sentence,
                    tips,
                    date,
                    i_sentence,
                )
                i_sentence += 1
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
                f"{self.deck_name.replace(':', '')}_{date.replace('/', '-')}_{self.titles_dict[datetime.strptime(date, '%Y/%m/%d')]}.mp3",
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
            date (str): Date tag.
            sub_deck_name (str): Name of the subdeck.
            i (int): number of the sentence in diary

        Returns:
            Note: Anki Note object.
        """
        study_language_sentence = study_language_sentence.replace("**", "").strip()
        primary_language_sentence = primary_language_sentence.replace("**", "").strip()
        logging.info(f"Creating TTS audio for: {study_language_sentence}")

        if study_language_sentence == "":
            return None, None

        if self.tts_model == "gtts":
            logging.info("Using gTTS")
            tts = gTTS(
                text=study_language_sentence,
                lang=self.config["languages"]["study_language_code"],
            )
            audio_filename = os.path.join(
                tempfile.gettempdir(), f"{hash(study_language_sentence)}.mp3"
            )
            tts.save(audio_filename)
        elif self.tts_model == "piper":
            logging.info("Using piper-tts")
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
            )

            # convert to mp3
            audio = AudioSegment.from_wav(audio_filename)
            audio.export(audio_filename.replace(".wav", ".mp3"), format="mp3")
            audio_filename = audio_filename.replace(".wav", ".mp3")
            os.remove(audio_filename.replace(".mp3", ".wav"))
            logging.info(f"{audio_filename}")
        else:
            raise ValueError

        note = Note(
            model=self.anki_model,
            fields=[
                primary_language_sentence.strip(),
                study_language_sentence,
                tips,
                f"[sound:{os.path.basename(audio_filename)}]",
                date,
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

        content = self.read_markdown_file(self.markdown_diary_path)

        years = re.split(r"^#\s+", content, flags=re.MULTILINE)
        main_deck = self.create_main_deck()
        all_notes = []
        all_media_files = []

        for year_block in years:
            if year_block.strip():
                all_note, all_media_file = self.process_all_days_anki(year_block)
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

        if not any(entry[1] for entry in entries):
            logging.warning(f"Skipping day as it has no valid translations.")
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

    def openai_create_day_title(self, day_block_dict):
        sentences = [
            dict[1]["study_language_sentence"] for dict in day_block_dict.items()
        ]
        # TODO:

        prompt = f"""
        Given the following sentences (written as python array) in {self.config["languages"]["study_language"]},
        could you create in no more than 5/6 words a catchy title about them?
        - Don't use commas, exclamation marks, column.
        - if you need a comma, use a -


        give the result as text in {self.config["languages"]["study_language"]}

        The sentences are:
            {sentences}
        """
        openai.api_key = self.config["openai"]["key"]  # Set the API key
        response = openai.ChatCompletion.create(
            model=self.config["openai"]["model"],
            messages=[
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": prompt},
            ],
        )

        # Extract and parse the JSON response
        output = response["choices"][0]["message"]["content"]
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

        openai.api_key = self.config["openai"]["key"]  # Set the API key
        response = openai.ChatCompletion.create(
            model=self.config["openai"]["model"],
            messages=[
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": prompt},
            ],
            response_format={"type": "json_object"},
        )

        # Extract and parse the JSON response
        output = response["choices"][0]["message"]["content"]
        output = json.loads(output)
        output["sentence"]["study_language_sentence_trial"] = sentence_dict[
            "study_language_sentence_trial"
        ]
        return output["sentence"]

    def get_all_days_title(self, diary_dict):
        titles_dict = {}
        for date_diary in diary_dict:
            if date_diary in diary_dict.keys():
                title_day = self.get_title_for_date(self.all_diary_text, date_diary)
                if title_day is None:
                    title_day = self.openai_create_day_title(diary_dict[date_diary])
                    logging.info(
                        f"created title with openai for {date_diary} - {title_day}"
                    )
                titles_dict[date_diary] = title_day

        self.titles_dict = titles_dict

    def write_diary(self, diary_dict):
        # create one mardkown files for all entries
        self.get_all_days_title(diary_dict)

        logging.info(f"Writing diary to {self.markdown_script_generated_diary_path}")
        with open(
            self.markdown_script_generated_diary_path, "w", encoding="utf-8"
        ) as file:
            for date_diary in diary_dict:
                file.write(
                    f"## {date_diary.strftime('%Y/%m/%d')}: {self.titles_dict[date_diary]} \n"
                )
                for sentence_no, sentence_dict in diary_dict[date_diary].items():
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

                logging.info(f"Writing daily diary to {diary_day_txt_filename}")
                with open(diary_day_txt_filename, "w", encoding="utf-8") as file:
                    file.write(
                        f"## {date_diary.strftime('%Y/%m/%d')}: {self.titles_dict[date_diary]} \n"
                    )
                    for sentence_no, sentence_dict in diary_dict[date_diary].items():
                        file.write(
                            f"- **{sentence_dict['primary_language_sentence']}\n"
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
                logging.warning(f"{date_diary} has no valid translations.")

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

                diary_dict[date_diary] = diary_day_dict
                i += 1

        return diary_dict

    def diary_complete_translations(self):
        diary_dict = self.markdown_diary_to_dict()
        if self.diary_new_entries_day:
            diary_dict = self.diary_new_entries_day | diary_dict

        for date_diary, date_dict in diary_dict.items():
            for sentence_no, sentence_dict in date_dict.items():
                primary_language_sentence = sentence_dict["primary_language_sentence"]
                if sentence_dict["study_language_sentence"] == "":
                    logging.info(
                        f"create missing diary entry with openai for {primary_language_sentence.strip()}"
                    )
                    if self.config["create_diary_answers_auto"]:
                        res = self.openai_translate_sentence(sentence_dict)
                        diary_dict[date_diary][sentence_no] = res

        self.write_diary(diary_dict)


def main():
    parser_instance = DiaryHandler()
    parser_instance.diary_complete_translations()
    parser_instance.convert_diary_entries_to_ankideck()


if __name__ == "__main__":
    main()
