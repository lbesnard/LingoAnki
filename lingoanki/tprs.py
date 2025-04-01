#!/usr/bin/env python3
"""
This code converts diary entries written in a foreign language into TPRS style audio file to learn more efficently.

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


"""

import argparse
import hashlib
import logging
import os
import re
from sre_compile import REPEAT_ONE
import tempfile
import numpy as np

from genanki import Deck, Model, Note, Package
from ovos_tts_plugin_piper import PiperTTSPlugin
from piper import PiperVoice
from pydub import AudioSegment
from collections import defaultdict
from lingoanki.diary import AnkiMarkdownParser


# norwegian template used in markdown file
diary_template = {}


class TprsParser(AnkiMarkdownParser):
    def __init__(self, markdown_path, output_dir, deck_name, use_piper=False):
        super().__init__(markdown_path, output_dir, deck_name, use_piper)
        self.markdown_path = markdown_path
        self.deck_name = deck_name
        self.output_dir = output_dir
        self.use_piper = use_piper
        self.repeat_sentence = 2
        self.validate_arguments()
        self.setup_logging()

    def process_day_block_tprs(self, day_block):
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

        logging.info(f"Processing day: {date} - {title}")

        #
        result = defaultdict(list)
        current_setning = None
        current_question = None

        for line in day_block.split("\n"):
            line = line.strip()
            if line.startswith("SETNING:"):
                current_setning = line[len("SETNING:") :].strip()
            elif line.startswith("SPØRSMÅL:") and current_setning:
                current_question = line[len("SPØRSMÅL:") :].strip()
            elif line.startswith("SVAR:") and current_setning and current_question:
                answer = line[len("SVAR:") :].strip()
                result[current_setning].append((current_question, answer))
                current_question = None  # Reset question after storing the pair

        return result, date

    def create_tprs_audio(self, day_block, date):
        logging.info("Using piper-tts")
        # config = {
        #     "module": "ovos-tts-plugin-piper",
        # }
        # e = PiperTTSPlugin(config=config)
        e = PiperTTSPlugin()
        e.length_scale = 2.0

        # voice = PiperVoice.load("no_NO-talesyntese-medium.onnx")
        # wav_file = wave.open(audio_filename, "w")

        # create a pause file
        pause_filename = os.path.join(tempfile.gettempdir(), f"{hash('pause')}.wav")
        paused_duration = 600  # ms
        pause_segment = AudioSegment.silent(duration=paused_duration)
        pause_segment.export(pause_filename, format="wav")

        media_files = []
        for key, value in day_block.items():
            audio_filename = os.path.join(tempfile.gettempdir(), f"{hash(key)}.wav")

            # add main sentence
            e.get_tts(key, audio_filename, lang="no")
            media_files.append(audio_filename)
            media_files.append(pause_filename)

            print(f"SETNING: {key}")
            for question, answer in value:
                # create question file
                audio_filename = os.path.join(
                    tempfile.gettempdir(), f"{hash(question)}.wav"
                )
                e.get_tts(question, audio_filename, lang="no")
                media_files.append(audio_filename)
                media_files.append(pause_filename)

                # create a silent file
                audio_filename = os.path.join(
                    tempfile.gettempdir(), f"{hash('silence')}.wav"
                )
                silence_duration = 5000 / self.repeat_sentence  # ms
                silenced_segment = AudioSegment.silent(duration=silence_duration)
                silenced_segment.export(audio_filename, format="wav")
                media_files.append(audio_filename)

                # create answer file
                audio_filename = os.path.join(
                    tempfile.gettempdir(), f"{hash(answer)}.wav"
                )
                e.get_tts(answer, audio_filename, lang="no")
                media_files.append(audio_filename)
                media_files.append(pause_filename)

                print(f"  SPØRSMÅL: {question}")
                print(f"  SVAR: {answer}")
            print()
        #
        # create a mp3 per day of all the notes to be listened with an audio player
        playlist_media = [AudioSegment.from_mp3(mp3_file) for mp3_file in media_files]

        combined = AudioSegment.empty()
        for sentence in playlist_media:
            combined += (
                sentence * self.repeat_sentence
            )  # repeat audio n times so that it's easier to remember

        combined.export(
            f"{self.output_dir}/{self.deck_name.replace(':', '')}_TPRS_{date.replace('/', '-')}.mp3",
            format="mp3",
        )

        for f in np.unique(media_files):
            os.remove(f)

    def process_tprs(self):
        # /home/lbesnard/Nextcloud_efunk/joplin/ecc5d58773214322bc91cfb676f62c4f.md
        self.validate_arguments()
        content = self.read_markdown_file()

        logging.basicConfig(
            level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
        )

        days = re.split(r"^##\s+", content, flags=re.MULTILINE)

        for day_block in days:
            if day_block.strip():
                result, date = self.process_day_block_tprs(day_block)
                if result:
                    self.create_tprs_audio(result, date)


def main():
    parser = argparse.ArgumentParser(
        description="Create TPRS audio from a Markdown file.",
        epilog='Example:\n diaryTprs -m /home/lbesnard/Nextcloud/joplin/ecc5d58773214322bc91cfb676f62c4f.md -d "Norwegian 🇳🇴:::Diary 📖" -o ~/Documents',
    )
    parser.add_argument(
        "-m", "--markdown-path", required=True, help="Path to the markdown file."
    )
    parser.add_argument(
        "-d", "--deck-name", required=True, help="Name of the TPRS lessons."
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

    parser_instance = TprsParser(
        markdown_path=args.markdown_path,
        deck_name=args.deck_name,
        output_dir=args.output_dir,
        use_piper=args.piper,
    )
    parser_instance.process_tprs()


if __name__ == "__main__":
    main()
