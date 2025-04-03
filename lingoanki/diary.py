#!/usr/bin/env python3
"""
This code converts diary entries written in a foreign language into flashcards to learn more efficently.


This is a bit hacky, but here is my workflow:

1) writing in a markdown file (Joplin) sentences in primary_language following the template defined below
2) attempt to write in study_language the sentence (optional)
3) run this script which creates an anki deck and calls openai to fill up the correct answers
6) import the anki deck


TEMPLATE:

# 2025

## 2025/01/28 Tirsdag 28. Januar (Tuesday) 2025

- **I want to speak Bokmal**
  <span style="color: #C70039 ">Forsøk</span>:
  <span style="color: #097969">Rettelse</span>:
  <span style="color: #dda504">Tips</span>:

"""

import hashlib
import logging
import os
import re
import openai
import json
import tempfile
from datetime import datetime
import yaml

from genanki import Deck, Model, Note, Package
from gtts import gTTS
from ovos_tts_plugin_piper import PiperTTSPlugin
from ovos_plugin_manager.tts import load_tts_plugin
from piper import PiperVoice
from pydub import AudioSegment
from pathlib import Path
from sre_compile import REPEAT_ONE

CONFIG_DIR = os.path.join(Path.home(), ".config", "diaryAnki")
CONFIG_PATH = os.path.join(CONFIG_DIR, "config.yaml")


class DiaryHandler:
    def __init__(self):
        self.config = self.load_config()
        self.markdown_diary_path = self.config["markdown_diary_path"]
        self.deck_name = self.config["anki_deck_name"]
        self.output_dir = self.config["output_dir"]
        self.tts_model = self.config["tts"]["model"]

        self.diary_markdown_filepath = os.path.join(
            self.config["output_dir"], "diary_all.md"
        )

        self.validate_arguments()
        self.setup_logging()
        self.anki_model_def()

    def load_config(self):
        """Load YAML config if it exists."""
        if os.path.exists(CONFIG_PATH):
            with open(CONFIG_PATH) as f:
                return yaml.safe_load(f) or {}
        raise FileNotFoundError

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
                    os.makedirs(self.output_dir)
                except Exception as e:
                    raise ValueError(
                        f"Failed to create output directory: {self.output_dir}. Error: {e}"
                    )

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

        day_match = re.match(r"^(\d{4}/\d{2}/\d{2})\s+(.*)", day_block)
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

        os.makedirs(os.path.join(f"{self.output_dir}", "DAILY_AUDIO"), exist_ok=True)
        combined.export(
            os.path.join(
                f"{self.output_dir}",
                "DAILY_AUDIO",
                f"{self.deck_name.replace(':', '')}_{date.replace('/', '-')}.mp3",
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

        logging.basicConfig(
            level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
        )

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

        pattern = rf"-(.*?)\n.*?{answer_template}(.*?)\n.*?{tips_template}(.*?)\n"
        entries = re.findall(pattern, day_block, re.DOTALL)

        if not any(entry[1] for entry in entries):
            logging.warning(f"Skipping day as it has no valid translations.")
            return None

        study_language_sentences = []
        for primary_language_sentence, study_language_sentence, tips in entries:
            study_language_sentences.append(study_language_sentence.strip())

        return study_language_sentences

    def openapi_translate_sentence(self, sentence_dict):
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

    def write_diary(self, diary_dict):
        if not self.config["overwrite_diary_markdown"]:
            with open(self.diary_markdown_filepath, "w", encoding="utf-8") as file:
                for date_diary in diary_dict:
                    if date_diary in diary_dict.keys():
                        file.write(f"## {date_diary.strftime('%Y/%m/%d')} \n")
                        for sentence_no, sentence_dict in diary_dict[
                            date_diary
                        ].items():
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

    def diary_complete_translations(self):
        dates_diary = self.extract_dates_from_md(self.markdown_diary_path)
        all_diary_text = self.read_markdown_file(self.config["markdown_diary_path"])

        diary_dict = {}
        for date_diary in dates_diary:
            day_block_text = self.get_text_for_date(all_diary_text, date_diary)
            answer_template = self.config["template_diary"]["answer"]
            tips_template = self.config["template_diary"]["tips"]
            trial_template = self.config["template_diary"]["trial"]

            # pattern = rf"-(.*?)\n.*?{answer_template}(.*?)\n.*?{tips_template}(.*?)\n"
            # pattern = rf"-(.*?)\n.*?{answer_template}(.*?)\n.*?{tips_template}(.*?)"
            pattern = rf"-(.*?)\n.*?{trial_template}(.*?)\n.*?{answer_template}(.*?)\n.*?{tips_template}(.*?)"
            entries = re.findall(pattern, day_block_text, re.DOTALL)

            if not any(entry[1] for entry in entries):
                logging.warning(f"{dates_diary} as it has no valid translations.")

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

                if diary_day_dict[i]["study_language_sentence"] == "":
                    logging.info(
                        f"create missing diary entry with openai for {primary_language_sentence.strip()}"
                    )
                    diary_day_dict[i] = self.openapi_translate_sentence(
                        diary_day_dict[i]
                    )

                diary_dict[date_diary] = diary_day_dict
                i += 1

        self.write_diary(diary_dict)
        return


def main():
    parser_instance = DiaryHandler()
    parser_instance.diary_complete_translations()
    parser_instance.convert_diary_entries_to_ankideck()


if __name__ == "__main__":
    main()
