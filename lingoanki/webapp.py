#!/usr/bin/env python3
import io
import re
from pathlib import Path
import json
import logging
import os
import subprocess
import time
import zipfile
from pathlib import Path
from queue import Queue
from threading import Thread
from datetime import datetime

import bcrypt
import markdown
import yaml
from flask import (
    Flask,
    Response,
    flash,
    get_flashed_messages,
    jsonify,
    redirect,
    render_template,
    render_template_string,
    request,
    send_file,
    send_from_directory,
    session,
    url_for,
)
from flask_babel import Babel
from flask_babel import gettext as _
from platformdirs import user_config_dir

# from werkzeug.utils import secure_filename
from lingoanki.diary import APP_NAME, CONFIG_FILE, DiaryHandler, TprsCreation

# Create an in-memory buffer to capture logs
log_stream = io.StringIO()

# Create a logging handler that writes to the log_stream
log_handler = logging.StreamHandler(log_stream)
log_handler.setLevel(logging.INFO)

# Set the logger to write to this handler
logger = logging.getLogger()
logger.addHandler(log_handler)
logger.setLevel(logging.INFO)

# Create a queue to manage logs
log_queue = Queue()


# Function to stream logs
def log_streamer():
    while True:
        line = log_stream.getvalue()
        if line:
            log_queue.put(line)
        time.sleep(1)


# Start a background thread to process log output
thread = Thread(target=log_streamer, daemon=True)
thread.start()

app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY", "super-secret-key")

# babel setup
app.config["BABEL_DEFAULT_LOCALE"] = "en"
app.jinja_env.autoescape = True
app.jinja_env.globals.update(_=_)
app.config["LANGUAGES"] = ["en", "fr"]  # Supported languages
babel = Babel(app)


SESSION_VERSION = "1.0"  # change this when you update session structure


@app.before_request
def check_session_version():
    if "username" in session:  # user is "logged in"
        if session.get("version") != SESSION_VERSION:
            session.clear()
            return redirect(url_for("logout"))


USER_CONFIG_FILE = "users.json"
user_config_path = Path(user_config_dir(APP_NAME)) / USER_CONFIG_FILE

USER_DB_FILE = os.getenv("USER_DB_FILE", user_config_path)
CONFIG_ROOT = os.getenv(
    "CONFIG_ROOT", os.path.expanduser(Path(user_config_dir(APP_NAME)))
)

# Update the template to include the edit functionality
diary_entries = []
selected_date = None
tprs_content = ""


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form["username"]
        password = request.form["password"]

        # Check if the user exists in the user database
        with open(USER_DB_FILE) as f:
            users = json.load(f)

        if username in users and bcrypt.checkpw(
            password.encode(), users[username].encode()
        ):
            # Check if the user has a valid config
            user_config_path = os.path.join(CONFIG_ROOT, username, "config.yaml")
            if not os.path.exists(user_config_path):
                # If no config found, log the user out and show an error
                session.clear()  # Log out the user by clearing the session
                flash(
                    f"No config found for user '{username}'. Please log in again.",
                    "error",
                )
                print(
                    f"Flash messages: {get_flashed_messages(with_categories=True)}"
                )  # Debugging line

                return redirect(url_for("login"))  # Redirect to login page

            # If login is successful and config exists, store the username in the session
            session["username"] = username
            session["user_config_path"] = os.path.join(
                CONFIG_ROOT, username, "config.yaml"
            )

            diary_instance = DiaryHandler(config_path=user_config_path)
            session["version"] = SESSION_VERSION
            session["diary_file"] = diary_instance.config["markdown_diary_path"]
            session["tprs_file"] = diary_instance.config["markdown_tprs_path"]
            session["output_folder"] = diary_instance.config["output_dir"]
            session["tprs_folder"] = os.path.join(session["output_folder"], "TPRS")
            session["daily_audio_folder"] = os.path.join(
                session["output_folder"], "DAILY_AUDIO"
            )
            session["log_file"] = os.path.join(
                diary_instance.config["output_dir"], "output.log"
            )
            session["template_help_text"] = diary_instance.template_help()
            diary_instance.stop()

            time_now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            session["output_zip"] = f"TPRS_{session['username']}_{time_now_str}.zip"
            os.makedirs(session["output_folder"], exist_ok=True)

            return redirect("/")  # Redirect to the home page or the main page

        # If login fails, show an error message
        flash("Invalid login. Please check your username and password.", "error")
        return redirect(url_for("login"))

    # If it's a GET request, display the login form
    return render_template_string(
        """
  <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">

        <style>
            button {
                margin-top: 0.5em;
                padding: 0.6em 1.2em;
                border-radius: 4px;
                border: none;
                background-color: #007bff;
                color: white;
                cursor: pointer;
            }
            button:hover {
                background-color: #0056b3;
            }
            @media (min-width: 600px) {
                .entry {
                flex-direction: row;
                align-items: center;
            }

            .entry input[type="text"] {
            width: 300px;
            margin-left: 10px;
            }
        </style>
        <form method="post">
            Username: <input name="username" required><br>
            Password: <input name="password" type="password" required><br>
            <button type="submit">Login</button>
        </form>
  </head>
        """
    )


@app.route("/logout", methods=["POST"])
def logout():
    session.clear()
    return redirect("/login")


@app.route("/", methods=["GET", "POST"])
def edit_diary():
    global selected_date

    if "username" not in session:
        return redirect("/login")

    username = session["username"]
    user_config_path = session["user_config_path"]
    if not os.path.exists(user_config_path):  # Check if config exists
        session.clear()  # Clear the session (log out)
        flash(
            "No config found for user '{}'. Please log in again.".format(username),
            "error",
        )
        return redirect(url_for("login"))

    # Optional: load the user's config here if needed
    with open(user_config_path) as f:
        user_config = yaml.safe_load(f)

    # diary_instance = DiaryHandler(config_path=user_config_path)
    diary_file = session["diary_file"]
    output_folder = session["output_folder"]
    if request.method == "POST":
        with open(diary_file, "w") as f:
            f.write(request.form["content"])

    content = ""
    if os.path.exists(diary_file):
        with open(diary_file) as f:
            content = f.read()

    files = [
        f
        for f in os.listdir(output_folder)
        if not f.startswith(".") and f != session["output_zip"]
    ]

    # template_help_text = diary_instance.template_help()
    template_help_text = session["template_help_text"]

    return render_template(
        "diary.html",
        content=content,
        tab="edit",
        files=files,
        diary_entries=diary_entries,
        selected_date=selected_date,
        template_help=template_help_text,
        username=username,  # Optional: pass to template
    )


@app.route("/diary_html")
def diary_html():
    content = ""

    diary_file = session["diary_file"]
    output_folder = session["output_folder"]
    if os.path.exists(diary_file):
        with open(diary_file) as f:
            content = markdown.markdown(
                f.read(), extensions=["nl2br", "extra", "codehilite", "tables"]
            )
    files = [
        f
        for f in os.listdir(output_folder)
        if not f.startswith(".") and f != session["output_zip"]
    ]
    return render_template(
        "diary_html.html", content=content, tab="diary_html", files=files
    )


@app.route("/tprs", methods=["GET", "POST"])
def view_tprs():
    # global tprs_content

    tprs_file = session["tprs_file"]
    output_folder = session["output_folder"]
    if request.method == "POST":
        pass
    if os.path.exists(tprs_file):
        with open(tprs_file) as f:
            tprs_content = markdown.markdown(
                f.read(), extensions=["nl2br", "extra", "codehilite", "tables"]
            )
    else:
        tprs_content = None

    files = [
        f
        for f in os.listdir(output_folder)
        if not f.startswith(".") and f != session["output_zip"]
    ]
    return render_template(
        "diary_tprs.html", tprs_content=tprs_content, tab="tprs", files=files
    )


@app.route("/generate_lessons", methods=["GET", "POST"])
def generate_lessons():
    output_folder = session["output_folder"]
    if request.method == "POST":
        app.config["PROPAGATE_EXCEPTIONS"] = True

        app.logger.setLevel(logging.DEBUG)

        app.logger.debug("Starting generate_lessons process.")

        # Call the standalone script
        try:
            user_config_path = session["user_config_path"]

            # some issues with sqlite when calling PiperTTS. requires flask to run with app.run(debug=True, use_reloader=False)
            diary_instance = DiaryHandler(config_path=user_config_path)
            diary_instance.diary_complete_translations()
            diary_instance.convert_diary_entries_to_ankideck()
            diary_instance.stop()

            tprs_instance = TprsCreation(config_path=user_config_path)
            tprs_instance.check_missing_sentences_from_existing_tprs()
            tprs_instance.add_missing_tprs()
            tprs_instance.convert_tts_tprs_entries()
            tprs_instance.stop()

            app.logger.debug(f"generated_tprs.py output")
        except subprocess.CalledProcessError as e:
            app.logger.error("generate_tprs.py failed")

        app.logger.debug("Completed generate_lessons process.")

        app.logger.debug("Completed TPRS creation process.")

    user_config_path = session["user_config_path"]
    files = [
        f
        for f in os.listdir(output_folder)
        if not f.startswith(".") and f != session["output_zip"]
    ]
    return render_template(
        "diary_generate_lessons.html", tab="generate_lessons", files=files
    )


@app.route("/stream_logs")
def stream_logs():
    def generate():
        while True:
            log_message = log_queue.get()  # Block until new log appears
            yield f"data: {log_message}\n\n"  # Send log message to client in SSE format

    return Response(generate(), content_type="text/event-stream")


@app.route("/output")
def view_output():
    output_folder = session["output_folder"]
    files = [
        f
        for f in os.listdir(output_folder)
        if not f.startswith(".") and f != session["output_zip"]
    ]
    return render_template("diary_output.html", content="", tab="output", files=files)


@app.route("/edit_entry", methods=["POST"])
def edit_entry():
    global selected_date
    selected_date = request.form.get("date_input")
    return redirect(url_for("edit_diary"))


@app.route("/edit_sentence/<int:index>", methods=["POST", "GET"])
def edit_sentence(index):
    global diary_entries
    sentence = diary_entries[index]["sentence"]
    if request.method == "POST":
        new_sentence = request.form.get("sentence")
        # Ensure that the new sentence is not None or empty
        if new_sentence:
            diary_entries[index]["sentence"] = new_sentence
        return redirect(url_for("edit_diary"))
    return render_template(
        "diary_edit.html",
        diary_entries=diary_entries,
        selected_date=selected_date,
        tab="edit",
        selected_edit=index,
    )


@app.route("/save_diary_entry", methods=["POST"])
def save_diary_entry():
    # Your specific function logic here
    # For example, saving the diary entry for a selected date
    print("Saving diary entry...")  # Placeholder for your function
    # You can also save data to a database or perform any other actions needed
    return redirect(url_for("edit_diary"))  # Redirect to a page after saving


@app.route("/get_log")
def get_log():
    log_file = session["log_file"]

    try:
        with open(log_file, "r") as f:
            log_lines = f.readlines()[
                -20:
            ]  # Get the last 20 lines (or adjust based on your needs)
        return jsonify({"log": "".join(log_lines)})
    except FileNotFoundError:
        return jsonify({"log": "Log file not found."})


@app.route("/add_sentence", methods=["POST"])
def add_sentence():
    global selected_date
    sentence = request.form.get("sentence")
    if selected_date and sentence:
        diary_entries.append({"date": selected_date, "sentence": sentence})
    return redirect(url_for("edit_diary"))


@app.route("/download/<filename>")
def download_file(filename):
    output_folder = session["output_folder"]

    return send_file(
        # os.path.join(OUTPUT_FOLDER, secure_filename(filename)), as_attachment=True
        os.path.join(output_folder, filename),
        as_attachment=True,
    )


@app.route("/download_zip")
def download_zip():
    output_folder = session["output_folder"]
    zip_path = os.path.join(output_folder, session["output_zip"])
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zipf:
        for root, _, files in os.walk(output_folder):
            for file in files:
                if (
                    not file.startswith(".")
                    and file != session["output_zip"]
                    and not file.endswith("zip")
                ):
                    full_path = os.path.join(root, file)
                    rel_path = os.path.relpath(full_path, output_folder)
                    zipf.write(full_path, arcname=rel_path)
    return send_file(zip_path, as_attachment=True)


app.config["LANGUAGES"] = ["en", "fr"]  # Supported languages


def get_locale():
    # Check if the user has selected a language in the session
    return session.get(
        "lang", request.accept_languages.best_match(app.config["LANGUAGES"])
    )


babel.init_app(app, locale_selector=get_locale)


@app.route("/set_language/<lang>")
def set_language(lang):
    if lang in app.config["LANGUAGES"]:
        session["lang"] = lang  # Store the language choice in the session
    return redirect(request.referrer)  # Redirect back to the page the user was on


# @app.route("/")
# def index():
#     # List all mp3 files in the directory
#     mp3_files = [f for f in os.listdir(session["tprs_folder"]) if f.endswith(".mp3")]
#     mp3_files = sorted(set(mp3_files), reverse=True)
#     print(mp3_files)
#     return render_template("diary_tprs_play_audio.html", mp3_files=mp3_files)
#


@app.route("/play/<filename>")
def play_audio(filename):
    # Send the mp3 file for playback
    return send_from_directory(session["tprs_folder"], filename)


def extract_date(filename: str) -> str:
    # Matches YYYY-MM-DD pattern
    match = re.search(r"\d{4}-\d{2}-\d{2}", filename)
    if match:
        return match.group()
    else:
        raise ValueError("No date in YYYY-MM-DD format found in the filename.")


def find_matching_md_file(date_str: str, search_folder: str) -> Path | None:
    folder = Path(search_folder)
    for file in folder.glob(f"*{date_str}*.md"):
        return file  # Return the first match
    return None


@app.route("/view_markdown/<filename>")
def view_markdown(filename):
    md_tprs_filename = filename.replace(".mp3", ".md")
    md_tprs_file_path = os.path.join(session["tprs_folder"], md_tprs_filename)

    mp3_files = [f for f in os.listdir(session["tprs_folder"]) if f.endswith(".mp3")]
    mp3_files = sorted(set(mp3_files), reverse=True)

    date = extract_date(md_tprs_filename)
    match_daily_diary = find_matching_md_file(date, session["daily_audio_folder"])
    if match_daily_diary:
        with open(match_daily_diary, "r") as file:
            content_daily_diary = file.read()

    if os.path.exists(md_tprs_file_path):
        with open(md_tprs_file_path, "r") as file:
            content = file.read()

        if match_daily_diary:
            content += content_daily_diary

        html_content = markdown.markdown(
            content, extensions=["nl2br", "extra", "codehilite", "tables"]
        )
        return render_template(
            "diary_tprs_play_audio.html",
            content=html_content,
            filename=filename,  # <---- pass it in
            mp3_files=mp3_files,
        )
    else:
        return f"Markdown file for {filename} not found", 404


@app.route("/play_audio")
def play_audio_page():
    mp3_files = [f for f in os.listdir(session["tprs_folder"]) if f.endswith(".mp3")]
    mp3_files = sorted(set(mp3_files), reverse=True)

    return render_template("diary_tprs_play_audio.html", mp3_files=mp3_files)


@app.route("/download_markdown/<filename>")
def download_markdown(filename):
    return send_from_directory(session["tprs_folder"], filename, as_attachment=True)


def main():
    app.run(debug=True, use_reloader=False, host="0.0.0.0", port=8084)


if __name__ == "__main__":
    main()
