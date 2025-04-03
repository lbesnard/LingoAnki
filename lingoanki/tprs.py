#!/usr/bin/env python3
"""
This code converts diary entries written in a foreign language into TPRS style audio file to learn more efficently.

"""

import logging
import os
import re
import json
import openai
import tempfile
import numpy as np

from ovos_tts_plugin_piper import PiperTTSPlugin
from pydub import AudioSegment
from collections import defaultdict
from lingoanki.diary import DiaryHandler


class TprsCreation(DiaryHandler):
    def __init__(self):
        super().__init__()
        self.markdown_tprs_path = self.config["markdown_tprs_path"]
        self.tprs_lessons_filepath = os.path.join(
            self.config["output_dir"], "tprs_lessons.md"
        )

    def read_tprs_day_block(self, day_block):
        """
        Process a day block and add notes to the deck.

        Args:
            day_block (str): Block of text for a specific day.

        Returns:
            list: List of notes for the day.
        """
        if not day_block.strip():
            return None, None

        day_match = re.match(r"^(\d{4}/\d{2}/\d{2})\s+(.*)", day_block)
        if not day_match:
            day_match = re.match(r"^(\d{4}-\d{2}-\d{2})\s+(.*)", day_block)
            if not day_match:
                return None, None

        date = day_match.group(1)
        title = day_match.group(2)

        logging.info(f"Processing day: {date} - {title}")

        #
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
            f"{self.config['tprs_lesson_name']}_TPRS_{date.replace('/', '-')}.mp3",
        )
        if (
            os.path.exists(tprs_audio_lesson_filepath)
            and not self.config["overwrite_tprs_audio"]
        ):
            logging.info("Already processed")
            return

        logging.info("Using piper-tts")
        # config = {
        #     "module": "ovos-tts-plugin-piper",
        # }
        # e = PiperTTSPlugin(config=config)
        e = PiperTTSPlugin()
        e.length_scale = self.config["tts"]["piper"]["piper_length_scale_tprs"]

        # create a pause file
        pause_filename = os.path.join(tempfile.gettempdir(), f"{hash('pause')}.wav")
        paused_duration = self.config["tts"]["pause_between_sentences_duration"]  # ms
        pause_segment = AudioSegment.silent(duration=paused_duration)
        pause_segment.export(pause_filename, format="wav")

        media_files = []
        for key, value in day_block.items():
            audio_filename = os.path.join(tempfile.gettempdir(), f"{hash(key)}.wav")

            # add main sentence
            e.get_tts(
                key,
                audio_filename,
                lang=self.config["languages"]["study_language_code"],
            )
            media_files.append(audio_filename)
            media_files.append(pause_filename)

            logging.info(f"SENTENCE: {key}")
            for question, answer in value:
                # create question file
                audio_filename = os.path.join(
                    tempfile.gettempdir(), f"{hash(question)}.wav"
                )
                e.get_tts(
                    question,
                    audio_filename,
                    lang=self.config["languages"]["study_language_code"],
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
                )
                media_files.append(audio_filename)
                media_files.append(pause_filename)

                logging.info(f"  QUESTION: {question}")
                logging.info(f"  ANSWER: {answer}")

        # create a mp3 per day of all the notes to be listened with an audio player
        playlist_media = [AudioSegment.from_mp3(mp3_file) for mp3_file in media_files]

        combined = AudioSegment.empty()
        for sentence in playlist_media:
            combined += (
                sentence * self.config["tts"]["repeat_sentence_tprs"]
            )  # repeat audio n times so that it's easier to remember

        os.makedirs(os.path.join(f"{self.output_dir}", "TPRS"), exist_ok=True)

        combined.export(
            tprs_audio_lesson_filepath,
            format="mp3",
        )

        # cleaning
        for f in np.unique(media_files):
            os.remove(f)

    def convert_tts_tprs_entries(self):
        self.validate_arguments()
        if os.path.exists(self.tprs_lessons_filepath):
            content = self.read_markdown_file(self.tprs_lessons_filepath)
        else:
            content = self.read_markdown_file(self.markdown_tprs_path)

        logging.basicConfig(
            level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
        )

        days = re.split(r"^##\s+", content, flags=re.MULTILINE)

        for day_block in days:
            if day_block.strip():
                result, date = self.read_tprs_day_block(day_block)
                if result:
                    self.create_tprs_audio(result, date)

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
        qa_dict = json.loads(output)
        return qa_dict

    def create_tprs_block_day(self, study_language_sentences):
        multiline_text = ""

        for study_language_sentence in study_language_sentences:
            logging.info(study_language_sentence)
            qa_dict = self.openai_tprs(study_language_sentence)
            multiline_text += f"{self.config['template_tprs']['sentence']} {study_language_sentence.strip()}\n"  # Add each item with a newline

            for id, item in qa_dict.items():
                multiline_text += f"{self.config['template_tprs']['question']} {item['question'].strip()}\n"  # Add each item with a newline
                multiline_text += f"{self.config['template_tprs']['answer']} {item['answer'].strip()}\n"  # Add each item with a newline

            multiline_text += "\n"

        return multiline_text

    def add_missing_tprs(self):
        dates_tprs = self.extract_dates_from_md(self.markdown_tprs_path)
        dates_diary = self.extract_dates_from_md(self.markdown_diary_path)
        missing_dates_tprs = list(set(dates_diary) - set(dates_tprs))
        missing_dates_tprs.sort()

        all_diary_text = self.read_markdown_file(self.config["markdown_diary_path"])
        all_tprs_text = self.read_markdown_file(self.config["markdown_tprs_path"])

        tprs_dict = {}
        for dt in dates_tprs:
            tprs_dict[dt] = self.get_text_for_date(all_tprs_text, dt)

        for missing_date_tprs in missing_dates_tprs:
            logging.info(f"Missing TPRS entries for {missing_date_tprs.date()}")
            day_block_text = self.get_text_for_date(all_diary_text, missing_date_tprs)
            study_language_sentences = self.get_sentences_from_diary(day_block_text)

            if study_language_sentences:
                tprs_block_day_text = self.create_tprs_block_day(
                    study_language_sentences
                )

                tprs_dict[missing_date_tprs] = tprs_block_day_text

        # append tprs_block_day_text to top of markdown_tprs_path
        if not self.config["overwrite_tprs_markdown"]:
            with open(self.tprs_lessons_filepath, "w", encoding="utf-8") as file:
                for date_diary in dates_diary:
                    if date_diary in tprs_dict.keys():
                        file.write(f"## {date_diary.strftime('%Y/%m/%d')} lesson\n")
                        file.write(tprs_dict[date_diary])
                        file.write("\n\n")


def main():
    parser_instance = TprsCreation()
    parser_instance.add_missing_tprs()
    parser_instance.convert_tts_tprs_entries()


if __name__ == "__main__":
    main()
