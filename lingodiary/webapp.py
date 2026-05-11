#!/usr/bin/env python3
import io
import logging
import os
import re
import subprocess
import time
import zipfile
from collections import defaultdict
from datetime import datetime, timedelta
from functools import wraps
from pathlib import Path
from queue import Queue
from threading import Thread

import jwt

import bcrypt
import yaml
from flask import (
    Flask,
    Response,
    flash,
    g,
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

from lingodiary.diary import (
    APP_NAME,
    DiaryHandler,
    _backfill_qa_translations,
    main as main_diary_tprs,
)

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
JWT_SECRET = os.getenv("JWT_SECRET", app.secret_key)
JWT_ALGORITHM = "HS256"
JWT_EXPIRY_HOURS = 24 * 7  # 7 days

# Flutter web build directory (copied into the image at /app/web_build)
_WEB_BUILD_DIR = os.path.join(os.path.dirname(__file__), "..", "web_build")


@app.route("/")
@app.route("/<path:subpath>")
def serve_flutter_web(subpath=""):
    """Serve the Flutter web app for all non-API routes."""
    full = os.path.join(_WEB_BUILD_DIR, subpath)
    if subpath and os.path.isfile(full):
        return send_from_directory(_WEB_BUILD_DIR, subpath)
    # For unknown paths (SPA routes) serve index.html so go_router handles it.
    index = os.path.join(_WEB_BUILD_DIR, "index.html")
    if os.path.isfile(index):
        return send_from_directory(_WEB_BUILD_DIR, "index.html")
    # Fallback: no web build present, return 404 with a helpful message.
    return "Flutter web build not found. Run 'flutter build web' in android_app/.", 404


# babel setup
app.config["BABEL_DEFAULT_LOCALE"] = "en"
app.config["BABEL_SUPPORTED_LOCALES"] = ["en", "fr"]  # Add more as needed

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


app.permanent_session_lifetime = timedelta(days=7)


@app.before_request
def make_session_permanent():
    session.permanent = True


USER_CONFIG_FILE = "users.yaml"
users_config_path = Path(user_config_dir(APP_NAME)) / USER_CONFIG_FILE

USER_DB_FILE = os.getenv("USER_DB_FILE", users_config_path)
CONFIG_ROOT = os.getenv(
    "CONFIG_ROOT", os.path.expanduser(Path(user_config_dir(APP_NAME)))
)


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form["username"]
        password = request.form["password"]

        # Check if the user exists in the user database
        with open(USER_DB_FILE) as f:
            users = yaml.safe_load(f)

        if username in users["users"] and bcrypt.checkpw(
            password.encode(), users["users"][username]["password"].encode()
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
                # print(
                #     f"Flash messages: {get_flashed_messages(with_categories=True)}"
                # )  # Debugging line
                #
                return redirect(url_for("login"))  # Redirect to login page

            # If login is successful and config exists, store the username in the session
            session["username"] = username
            session["user_config_path"] = os.path.join(
                CONFIG_ROOT, username, "config.yaml"
            )

            # Get the user's preferred language and store it in the session
            user_language = users["users"][username].get(
                "language", "en"
            )  # Default to "en" if not set
            session["lang"] = user_language

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

            time_now_str = datetime.now().strftime("%Y%m%dT%H%M%S")
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


def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if "username" not in session:
            flash("Please log in to continue.", "error")
            return redirect(url_for("login"))
        return f(*args, **kwargs)

    return decorated_function


@app.route("/logout", methods=["POST"])
def logout():
    session.clear()
    return redirect("/login")


@app.route("/", methods=["GET", "POST"])
@login_required
def edit_diary():
    diary_entries = session.get("diary_entries", [])
    selected_date = session.get("selected_date", [])

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

    output_folder = session["output_folder"]
    json_path = os.path.join(output_folder, "diary.json")

    if request.method == "POST":
        # Accept a structured JSON body from the new diary editor UI
        try:
            from lingodiary.diary_json import (
                load_diary_json,
                save_diary_json,
                upsert_day,
                DiaryEntry,
                LessonsBlock,
                ReviewingState,
            )

            posted = request.get_json(silent=True) or {}
            date_str = posted.get("date", "")
            sentences = posted.get("sentences", [])
            if date_str and sentences:
                date_slash = date_str.replace("-", "/")
                diary_json = load_diary_json(json_path)
                entries = [
                    DiaryEntry(
                        index=i + 1,
                        input_language_sentence=s,
                        lessons=LessonsBlock(reviewing=ReviewingState()),
                    )
                    for i, s in enumerate(sentences)
                ]
                diary_json = upsert_day(diary_json, date_slash, "", entries)
                save_diary_json(diary_json, json_path)
                return jsonify({"ok": True})
        except Exception as exc:
            app.logger.error(f"edit_diary POST error: {exc}")
            return jsonify({"error": str(exc)}), 500

    # GET: load structured diary data from diary.json
    diary_data = None
    if os.path.exists(json_path):
        try:
            from lingodiary.diary_json import load_diary_json

            diary_data = load_diary_json(json_path)
        except Exception:
            diary_data = None

    files = [
        f
        for f in os.listdir(output_folder)
        if not f.startswith(".")
        and f != session["output_zip"]
        and not f.endswith("zip")
        and not f.endswith("log")
    ]

    template_help_text = session["template_help_text"]

    return render_template(
        "diary.html",
        content="",
        diary_data=diary_data,
        tab="edit",
        files=files,
        diary_entries=diary_entries,
        selected_date=selected_date,
        template_help=template_help_text,
        username=username,
    )


@app.route("/diary_html")
@login_required
def diary_html():
    output_folder = session["output_folder"]

    json_path = os.path.join(output_folder, "diary.json")
    diary_data = None
    if os.path.exists(json_path):
        try:
            from lingodiary.diary_json import load_diary_json

            diary_data = load_diary_json(json_path)
        except Exception:
            diary_data = None

    files = [
        f
        for f in os.listdir(output_folder)
        if not f.startswith(".")
        and f != session["output_zip"]
        and not f.endswith("zip")
        and not f.endswith("log")
    ]

    return render_template(
        "diary_html.html",
        content="",
        diary_data=diary_data,
        tab="diary_html",
        files=files,
    )


@app.route("/tprs", methods=["GET", "POST"])
@login_required
def view_tprs():
    output_folder = session["output_folder"]

    json_path = os.path.join(output_folder, "diary.json")
    diary_data = None
    if os.path.exists(json_path):
        try:
            from lingodiary.diary_json import load_diary_json

            diary_data = load_diary_json(json_path)
        except Exception:
            diary_data = None

    files = [
        f
        for f in os.listdir(output_folder)
        if not f.startswith(".")
        and f != session["output_zip"]
        and not f.endswith("zip")
        and not f.endswith("log")
    ]
    return render_template(
        "diary_tprs.html",
        tprs_content=None,
        diary_data=diary_data,
        tab="tprs",
        files=files,
    )


@app.route("/generate_lessons", methods=["GET", "POST"])
@login_required
def generate_lessons():
    output_folder = session["output_folder"]
    if request.method == "POST":
        app.config["PROPAGATE_EXCEPTIONS"] = True

        app.logger.setLevel(logging.DEBUG)

        app.logger.debug("Starting generate_lessons process.")

        try:
            user_config_path = session["user_config_path"]
            main_diary_tprs(config_path=user_config_path)
        except subprocess.CalledProcessError:
            app.logger.error("generate_tprs.py failed")

        # Auto-update diary.json so it stays in sync with newly generated content
        try:
            from lingodiary.migrate_to_json import (
                migrate_markdown_to_json as migrate_to_json,
            )

            json_path = os.path.join(output_folder, "diary.json")
            migrate_to_json(
                config_path=session["user_config_path"],
                output_json_path=json_path,
                overwrite=True,
            )
            app.logger.debug("diary.json updated after generation.")
        except Exception as exc:
            app.logger.warning(f"diary.json update failed: {exc}")

        app.logger.debug("Completed generate_lessons process.")

    user_config_path = session["user_config_path"]
    files = [
        f
        for f in os.listdir(output_folder)
        if not f.startswith(".")
        and f != session["output_zip"]
        and not f.endswith("zip")
        and not f.endswith("log")
    ]
    return render_template(
        "diary_generate_lessons.html", tab="generate_lessons", files=files
    )


@app.route("/backfill/qa_translations", methods=["POST"])
@login_required
def web_backfill_qa_translations():
    """Web UI: background-thread Q&A translation backfill (session auth)."""
    import yaml

    config_path = session["user_config_path"]
    output_folder = session["output_folder"]
    json_path = os.path.join(output_folder, "diary.json")

    def _run():
        try:
            with open(config_path, encoding="utf-8") as f:
                config = yaml.safe_load(f)
            _backfill_qa_translations(config, json_path, app.logger)
            app.logger.info("Q&A translation backfill complete.")
        except Exception as exc:
            app.logger.error(f"Q&A translation backfill error: {exc}")

    Thread(target=_run, daemon=True).start()
    return jsonify({"ok": True, "message": "Q&A translation backfill started"})


@app.route("/backfill/audio_timing", methods=["POST"])
@login_required
def web_backfill_audio_timing():
    """Web UI: background-thread audio segment backfill (session auth)."""
    config_path = session["user_config_path"]
    output_folder = session["output_folder"]
    json_path = os.path.join(output_folder, "diary.json")

    def _run():
        try:
            from lingodiary.audio_timing import backfill_audio_timings

            backfill_audio_timings(config_path=config_path, diary_json_path=json_path)
            app.logger.info("Audio timing backfill complete.")
        except Exception as exc:
            app.logger.error(f"Audio timing backfill error: {exc}")

    Thread(target=_run, daemon=True).start()
    return jsonify({"ok": True, "message": "Audio timing backfill started"})


@app.route("/backfill/all", methods=["POST"])
@login_required
def web_backfill_all():
    """Web UI: background-thread full backfill — diary.json sync + Q&A + audio (session auth)."""
    import yaml

    config_path = session["user_config_path"]
    output_folder = session["output_folder"]
    json_path = os.path.join(output_folder, "diary.json")

    def _run():
        app.logger.info("Backfill all: step 1/3 — syncing diary.json from markdown")
        try:
            from lingodiary.migrate_to_json import (
                migrate_markdown_to_json as migrate_to_json,
            )

            migrate_to_json(
                config_path=config_path,
                output_json_path=json_path,
                overwrite=True,
            )
        except Exception as exc:
            app.logger.warning(f"Backfill all: diary.json sync failed: {exc}")

        app.logger.info("Backfill all: step 2/3 — Q&A translations")
        try:
            with open(config_path, encoding="utf-8") as f:
                config = yaml.safe_load(f)
            _backfill_qa_translations(config, json_path, app.logger)
        except Exception as exc:
            app.logger.warning(f"Backfill all: Q&A translation failed: {exc}")

        app.logger.info("Backfill all: step 3/3 — audio timing / segments")
        try:
            from lingodiary.audio_timing import backfill_audio_timings

            backfill_audio_timings(config_path=config_path, diary_json_path=json_path)
        except Exception as exc:
            app.logger.warning(f"Backfill all: audio timing failed: {exc}")

        app.logger.info("Backfill all: complete")

    Thread(target=_run, daemon=True).start()
    return jsonify({"ok": True, "message": "Full backfill started"})


@app.route("/stream_logs")
@login_required
def stream_logs():
    def generate():
        while True:
            log_message = log_queue.get()  # Block until new log appears
            yield f"data: {log_message}\n\n"  # Send log message to client in SSE format

    return Response(generate(), content_type="text/event-stream")


@app.route("/output")
@login_required
def view_output():
    output_folder = session["output_folder"]
    files = [
        f
        for f in os.listdir(output_folder)
        if not f.startswith(".")
        and f != session["output_zip"]
        and not f.endswith("zip")
        and not f.endswith("log")
    ]
    return render_template("diary_output.html", content="", tab="output", files=files)


@app.route("/edit_entry", methods=["POST"])
@login_required
def edit_entry():
    selected_date = request.form.get("date_input")
    session["selected_date"] = selected_date
    print("Selected date:", selected_date)  # Debug print

    if selected_date:
        return jsonify({"success": True, "selected_date": selected_date})

    return jsonify({"success": False, "error": "Invalid date"}), 400


@app.route("/clear_selected_date", methods=["POST"])
@login_required
def clear_selected_date():
    session["selected_date"] = None
    session["diary_entries"] = []

    return "", 204


@app.route("/edit_sentence/<int:index>", methods=["POST", "GET"])
@login_required
def edit_sentence(index):
    diary_entries = session["diary_entries"]
    selected_date = session["selected_date"]
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
@login_required
def save_diary_entry():
    diary_entries = session["diary_entries"]
    selected_date = session["selected_date"]

    if not selected_date or not diary_entries:
        flash("No date or entries to save", "error")
        return redirect(url_for("edit_diary"))

    output_folder = session["output_folder"]
    json_path = os.path.join(output_folder, "diary.json")

    try:
        from lingodiary.diary_json import (
            DiaryEntry,
            LessonsBlock,
            ReviewingState,
            load_diary_json,
            save_diary_json,
            upsert_day,
        )

        date_slash = selected_date.replace("-", "/")
        diary_json = load_diary_json(json_path)
        entries = [
            DiaryEntry(
                index=i + 1,
                input_language_sentence=entry["sentence"],
                lessons=LessonsBlock(reviewing=ReviewingState()),
            )
            for i, entry in enumerate(diary_entries)
        ]
        diary_json = upsert_day(diary_json, date_slash, "", entries)
        save_diary_json(diary_json, json_path)
        flash("Diary entry saved successfully!", "success")
    except Exception as exc:
        app.logger.error(f"save_diary_entry error: {exc}")
        flash(f"Failed to save diary entry: {exc}", "error")

    return redirect(url_for("edit_diary"))


@app.route("/get_log")
@login_required
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
@login_required
def add_sentence():
    selected_date = session["selected_date"]
    sentence = request.form.get("sentence")

    diary_entries = session.get("diary_entries", [])

    if selected_date and sentence:
        entry = {"date": selected_date, "sentence": sentence}
        diary_entries.append(entry)
        session["diary_entries"] = diary_entries
        return jsonify({"success": True, "entry": entry})

    return (
        jsonify({"success": False, "error": "Missing selected_date or sentence"}),
        400,
    )


@app.route("/download/<filename>")
@login_required
def download_file(filename):
    output_folder = session["output_folder"]

    return send_file(
        # os.path.join(OUTPUT_FOLDER, secure_filename(filename)), as_attachment=True
        os.path.join(output_folder, filename),
        as_attachment=True,
    )


@app.route("/download_zip")
@login_required
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
                    and not file.endswith("log")
                ):
                    full_path = os.path.join(root, file)
                    rel_path = os.path.relpath(full_path, output_folder)
                    zipf.write(full_path, arcname=rel_path)
    return send_file(zip_path, as_attachment=True)


app.config["LANGUAGES"] = ["en", "fr"]  # Supported languages


def get_locale():
    if "lang" in session:
        return session["lang"]
    return request.accept_languages.best_match(app.config["LANGUAGES"])


babel = Babel(app, locale_selector=get_locale)


@app.route("/set_language/<lang_code>")
@login_required
def set_language(lang_code):
    session["lang"] = lang_code
    return redirect(request.referrer or url_for("edit_diary"))


@app.route("/play/<filename>")
@login_required
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


@app.route("/view_markdown/<filename>")
@login_required
def view_markdown(filename):
    """Redirect legacy /view_markdown URLs to the new /lesson_player route."""
    try:
        date_str = extract_date(filename)
    except ValueError:
        return "Could not extract date from filename.", 400

    match = re.match(
        r"(.+?)(_enhanced|_present|_future)?\.mp3$", filename, re.IGNORECASE
    )
    variant = "original"
    if match:
        variant_suffix = match.group(2) or ""
        variant = variant_suffix.lstrip("_").lower() or "original"

    username = session.get("username", "")
    return redirect(
        url_for("lesson_player", username=username, date=date_str, variant=variant),
        code=301,
    )


@app.route("/lesson_player/<username>/<date>/<variant>")
@login_required
def lesson_player(username, date, variant):
    """Renders the TPRS lesson player using diary.json data."""
    output_folder = session["output_folder"]
    json_path = os.path.join(output_folder, "diary.json")

    _VARIANT_DISPLAY = {
        "original": "Original",
        "enhanced": "Enhanced",
        "future": "Future",
        "present": "Present",
    }
    variant = variant.lower()

    lesson_data = None
    lesson_title = ""
    if os.path.exists(json_path):
        try:
            from lingodiary.diary_json import load_diary_json

            diary_json = load_diary_json(json_path)
            date_slash = date.replace("-", "/")
            day = next((d for d in diary_json.diaries if d.date == date_slash), None)
            if day:
                lesson_title = day.title or date
                lesson_data = []
                for entry in day.entries:
                    variant_lesson = entry.lessons.get_variant(variant)
                    lesson_data.append(
                        {
                            "input_sentence": entry.input_language_sentence,
                            "output_sentence": entry.output_language_translation,
                            "tips": entry.tips,
                            "variant_sentence": variant_lesson.sentence,
                            "qa": [
                                {"question": qa.question, "answer": qa.answer}
                                for qa in variant_lesson.qa
                            ],
                        }
                    )
        except Exception as exc:
            app.logger.error(f"lesson_player error loading diary.json: {exc}")

    display_items = get_mp3_variants(session["tprs_folder"])

    # Find matching mp3 filename for the given date+variant
    filename = _find_mp3_for_date_variant(session["tprs_folder"], date, variant)

    return render_template(
        "diary_tprs_play_audio.html",
        lesson_data=lesson_data,
        lesson_title=lesson_title,
        date=date,
        variant=variant,
        variant_display=_VARIANT_DISPLAY.get(variant, variant.title()),
        filename=filename or "",
        mp3_variants=display_items,
        selected_base=filename.replace(".mp3", "") if filename else "",
        selected_variant=_VARIANT_DISPLAY.get(variant, variant.title()),
        username=session.get("username", ""),
    )


def _find_mp3_for_date_variant(tprs_folder: str, date: str, variant: str) -> str | None:
    """Find the mp3 filename for a given date and variant."""
    suffix_map = {
        "original": "",
        "enhanced": "_enhanced",
        "future": "_future",
        "present": "_present",
    }
    suffix = suffix_map.get(variant, "")
    if not os.path.exists(tprs_folder):
        return None
    for f in os.listdir(tprs_folder):
        if f.endswith(f"{suffix}.mp3") and date in f:
            return f
    return None


def get_mp3_variants(folder):
    variants_by_base = defaultdict(list)

    if os.path.exists(folder):
        for f in os.listdir(folder):
            if f.endswith(".mp3"):
                match = re.match(
                    r"(.+?)(_enhanced|_present|_future)?\.mp3$", f, re.IGNORECASE
                )
                if match:
                    base, variant = match.groups()
                    variant_display = (
                        variant.lstrip("_").title() if variant else "Original"
                    )
                    variants_by_base[base].append((variant_display, f))

    display_items = []
    for base, variants in variants_by_base.items():
        parts = base.split("_TPRS_")
        if len(parts) == 2:
            display = parts[1]
        else:
            display = base
        display_items.append((base, display, dict(variants)))

    display_items.sort(key=lambda x: x[1], reverse=True)
    return display_items


@app.route("/play_audio")
@login_required
def play_audio_page():
    mp3_variants = get_mp3_variants(session["tprs_folder"])
    return render_template(
        "diary_tprs_play_audio.html",
        mp3_variants=mp3_variants,
        username=session.get("username", ""),
        lesson_data=None,
        lesson_title="",
        date="",
        variant="original",
        variant_display="Original",
        filename="",
        selected_base="",
        selected_variant="Original",
    )


@app.route("/download_markdown/<filename>")
@login_required
def download_markdown(filename):
    return send_from_directory(session["tprs_folder"], filename, as_attachment=True)


@app.route("/backup/download")
@login_required
def backup_download():
    output_folder = session["output_folder"]
    username = session["username"]
    time_now_str = datetime.now().strftime("%Y%m%dT%H%M%S")
    zip_name = f"backup_{username}_{time_now_str}.zip"

    json_path = os.path.join(output_folder, "diary.json")

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zipf:
        # diary.json (primary source of truth)
        if os.path.exists(json_path):
            zipf.write(json_path, arcname="diary.json")
        # Full output folder (mp3s, TPRS/, DAILY_AUDIO/, etc.) — exclude .md files
        for root, _, files in os.walk(output_folder):
            for file in files:
                if (
                    not file.startswith(".")
                    and not file.endswith(".zip")
                    and not file.endswith(".log")
                    and not file.endswith(".md")
                ):
                    full_path = os.path.join(root, file)
                    rel_path = os.path.relpath(full_path, output_folder)
                    zipf.write(full_path, arcname=f"output/{rel_path}")

    buf.seek(0)
    return send_file(
        buf, as_attachment=True, download_name=zip_name, mimetype="application/zip"
    )


@app.route("/backup/upload", methods=["POST"])
@login_required
def backup_upload():
    if "backup_file" not in request.files:
        flash("No file uploaded.", "error")
        return redirect("/backup")

    f = request.files["backup_file"]
    if not f.filename.endswith(".zip"):
        flash("Please upload a .zip backup file.", "error")
        return redirect("/backup")

    output_folder = session["output_folder"]

    try:
        with zipfile.ZipFile(f, "r") as zipf:
            names = zipf.namelist()
            restored = []

            for name in names:
                if name == "diary.json":
                    data = zipf.read(name)
                    dest = os.path.join(output_folder, "diary.json")
                    os.makedirs(os.path.dirname(dest), exist_ok=True)
                    with open(dest, "wb") as out:
                        out.write(data)
                    restored.append("diary.json")

                elif name.startswith("output/") and not name.endswith("/"):
                    rel = name[len("output/") :]
                    dest = os.path.join(output_folder, rel)
                    os.makedirs(os.path.dirname(dest), exist_ok=True)
                    with zipf.open(name) as src, open(dest, "wb") as out:
                        out.write(src.read())

            if not restored:
                flash("No recognisable backup content found in the zip.", "error")
            else:
                flash(
                    f"Backup restored successfully ({', '.join(set(restored))} + output files).",
                    "success",
                )

    except zipfile.BadZipFile:
        flash("Invalid zip file.", "error")

    return redirect("/backup")


@app.route("/backup")
@login_required
def backup_page():
    return render_template("diary_backup.html")


@app.route("/diary_entries", methods=["GET", "POST"])
@login_required
def diary_entries_route():
    import datetime as _dt

    today = _dt.date.today().strftime("%Y-%m-%d")
    primary_language = session.get("primary_language", "English")
    if request.method == "POST":
        date_str = request.form.get("date", "")
        sentences = request.form.getlist("sentence")
        sentences = [s.strip() for s in sentences if s.strip()]
        if date_str and sentences:
            user_config_path = session.get("user_config_path", "")
            output_folder = session.get("output_folder", "")
            if user_config_path and output_folder:
                try:
                    from lingodiary.diary_json import (
                        DiaryEntry,
                        LessonsBlock,
                        ReviewingState,
                        load_diary_json,
                        save_diary_json,
                        upsert_day,
                    )

                    json_path = os.path.join(output_folder, "diary.json")
                    diary_json = load_diary_json(json_path)
                    date_slash = date_str.replace("-", "/")
                    entries = [
                        DiaryEntry(
                            index=i,
                            input_language_sentence=s,
                            user_trial_translation="",
                            output_language_translation="",
                            tips="",
                            lessons=LessonsBlock(reviewing=ReviewingState()),
                        )
                        for i, s in enumerate(sentences)
                    ]
                    diary_json = upsert_day(diary_json, date_slash, "", entries)
                    save_diary_json(diary_json, json_path)
                    flash(_("Entries saved successfully."), "success")
                except Exception as e:
                    flash(f"Error: {e}", "danger")
        return redirect(url_for("diary_entries_route"))
    return render_template(
        "diary_entries.html",
        today=today,
        primary_language=primary_language,
        tab="diary_entries",
    )


# REST API for mobile app
# ---------------------------------------------------------------------------


def _jwt_required(f):
    """Decorator that validates a Bearer JWT token and injects user context."""

    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.headers.get("Authorization", "")
        if auth.startswith("Bearer "):
            token = auth[len("Bearer ") :]
        elif request.args.get("token"):
            # Fallback for media streaming (e.g. HTML5 audio can't set headers)
            token = request.args["token"]
        else:
            return jsonify({"error": "Missing or invalid Authorization header"}), 401
        try:
            payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        except jwt.ExpiredSignatureError:
            return jsonify({"error": "Token expired"}), 401
        except jwt.InvalidTokenError:
            return jsonify({"error": "Invalid token"}), 401

        username = payload.get("sub")
        user_config_path = os.path.join(CONFIG_ROOT, username, "config.yaml")
        if not os.path.exists(user_config_path):
            return jsonify({"error": "User config not found"}), 403

        # Inject into Flask's g so route handlers can access it
        from flask import g as _g

        _g.api_username = username
        _g.api_config_path = user_config_path
        diary_instance = DiaryHandler(config_path=user_config_path)
        _g.api_diary_file = diary_instance.config["markdown_diary_path"]
        _g.api_tprs_file = diary_instance.config["markdown_tprs_path"]
        _g.api_output_folder = diary_instance.config["output_dir"]
        _g.api_tprs_folder = os.path.join(_g.api_output_folder, "TPRS")
        json_diary_path = diary_instance.config.get("json_diary_path") or os.path.join(
            _g.api_output_folder, "diary.json"
        )
        _g.api_json_diary_path = json_diary_path
        diary_instance.stop()
        return f(*args, **kwargs)

    return decorated


@app.route("/api/login", methods=["POST"])
def api_login():
    data = request.get_json(silent=True) or {}
    username = data.get("username", "")
    password = data.get("password", "")

    if not username or not password:
        return jsonify({"error": "username and password required"}), 400

    with open(USER_DB_FILE) as f_db:
        users = yaml.safe_load(f_db)

    if username not in users.get("users", {}) or not bcrypt.checkpw(
        password.encode(), users["users"][username]["password"].encode()
    ):
        return jsonify({"error": "Invalid credentials"}), 401

    user_config_path = os.path.join(CONFIG_ROOT, username, "config.yaml")
    if not os.path.exists(user_config_path):
        return jsonify({"error": "No config found for this user"}), 403

    expiry = datetime.utcnow() + timedelta(hours=JWT_EXPIRY_HOURS)
    token = jwt.encode(
        {"sub": username, "exp": expiry}, JWT_SECRET, algorithm=JWT_ALGORITHM
    )
    return jsonify({"token": token, "expires_at": expiry.isoformat()})


@app.route("/api/diary", methods=["GET"])
@_jwt_required
def api_get_diary():
    return (
        jsonify(
            {
                "deprecated": True,
                "message": "This endpoint is removed. Use /api/diary/json instead.",
            }
        ),
        410,
    )


@app.route("/api/diary", methods=["POST"])
@_jwt_required
def api_save_diary():
    return (
        jsonify(
            {
                "deprecated": True,
                "message": "This endpoint is removed. Use /api/diary/json instead.",
            }
        ),
        410,
    )


@app.route("/api/generate", methods=["POST"])
@_jwt_required
def api_generate():
    from flask import g as _g
    import yaml

    config_path = _g.api_config_path
    output_folder = _g.api_output_folder

    def _run():
        try:
            main_diary_tprs(config_path=config_path)
        except Exception as exc:
            app.logger.error(f"API generate error: {exc}")
        # Backfill any missing Q&A translations (safe standalone function — no markdown side effects)
        try:
            with open(config_path, encoding="utf-8") as f:
                config = yaml.safe_load(f)
            json_path = os.path.join(output_folder, "diary.json")
            _backfill_qa_translations(config, json_path, app.logger)
        except Exception as exc:
            app.logger.warning(f"Q&A translation backfill failed: {exc}")
        # Write a completion marker so the client can stop polling.
        log_file = os.path.join(output_folder, "output.log")
        try:
            with open(log_file, "a", encoding="utf-8") as lf:
                lf.write("=== Generation finished ===\n")
        except Exception:
            pass

    t = Thread(target=_run, daemon=True)
    t.start()
    return jsonify({"ok": True, "message": "Generation started"})


@app.route("/api/backfill/qa_translations", methods=["POST"])
@_jwt_required
def api_backfill_qa_translations():
    """Background job: translate all missing Q&A pairs to the primary language.

    Uses the safe standalone _backfill_qa_translations() — does NOT instantiate
    TprsCreation, so no markdown files are created or overwritten as side effects.
    """
    from flask import g as _g
    import yaml

    config_path = _g.api_config_path
    output_folder = _g.api_output_folder

    def _run():
        try:
            with open(config_path, encoding="utf-8") as f:
                config = yaml.safe_load(f)
            json_path = os.path.join(output_folder, "diary.json")
            _backfill_qa_translations(config, json_path, app.logger)
        except Exception as exc:
            app.logger.error(f"Q&A translation backfill error: {exc}")

    t = Thread(target=_run, daemon=True)
    t.start()
    return jsonify({"ok": True, "message": "Q&A translation backfill started"})


@app.route("/api/backfill/audio_timing", methods=["POST"])
@_jwt_required
def api_backfill_audio_timing():
    """Background job: generate per-sentence audio segments and write timings to diary.json."""
    from flask import g as _g

    config_path = _g.api_config_path
    output_folder = _g.api_output_folder

    def _run():
        try:
            from lingodiary.audio_timing import backfill_audio_timings

            json_path = os.path.join(output_folder, "diary.json")
            backfill_audio_timings(config_path=config_path, diary_json_path=json_path)
        except Exception as exc:
            app.logger.error(f"Audio timing backfill error: {exc}")

    t = Thread(target=_run, daemon=True)
    t.start()
    return jsonify({"ok": True, "message": "Audio timing backfill started"})


@app.route("/api/backfill/all", methods=["POST"])
@_jwt_required
def api_backfill_all():
    """Background job: fill in everything missing — diary.json sync, Q&A translations, audio segments.

    Runs in sequence:
      1. migrate_to_json  (sync diary.json with current markdown)
      2. _backfill_qa_translations  (translate missing Q&A pairs)
      3. backfill_audio_timings  (generate missing segment MP3s + timing data)
    """
    from flask import g as _g
    import yaml

    config_path = _g.api_config_path
    output_folder = _g.api_output_folder

    def _run():
        json_path = os.path.join(output_folder, "diary.json")

        app.logger.info("Backfill all: step 1/3 — syncing diary.json from markdown")
        try:
            from lingodiary.migrate_to_json import (
                migrate_markdown_to_json as migrate_to_json,
            )

            migrate_to_json(
                config_path=config_path,
                output_json_path=json_path,
                overwrite=True,
            )
        except Exception as exc:
            app.logger.warning(f"Backfill all: diary.json sync failed: {exc}")

        app.logger.info("Backfill all: step 2/3 — Q&A translations")
        try:
            with open(config_path, encoding="utf-8") as f:
                config = yaml.safe_load(f)
            _backfill_qa_translations(config, json_path, app.logger)
        except Exception as exc:
            app.logger.warning(f"Backfill all: Q&A translation failed: {exc}")

        app.logger.info("Backfill all: step 3/3 — audio timing / segments")
        try:
            from lingodiary.audio_timing import backfill_audio_timings

            backfill_audio_timings(config_path=config_path, diary_json_path=json_path)
        except Exception as exc:
            app.logger.warning(f"Backfill all: audio timing failed: {exc}")

        app.logger.info("Backfill all: complete")

    t = Thread(target=_run, daemon=True)
    t.start()
    return jsonify(
        {
            "ok": True,
            "message": "Full backfill started (Q&A translations + audio segments)",
        }
    )


@app.route("/api/generate/status", methods=["GET"])
@_jwt_required
def api_generate_status():
    from flask import g as _g

    log_file = os.path.join(_g.api_output_folder, "output.log")
    lines = []
    if os.path.exists(log_file):
        with open(log_file, "r") as f:
            lines = f.readlines()[-50:]
    return jsonify({"log": "".join(lines)})


@app.route("/api/lessons", methods=["GET"])
@_jwt_required
def api_lessons():
    from flask import g as _g

    items = get_mp3_variants(_g.api_tprs_folder)
    result = []
    diary = None
    try:
        from lingodiary.diary_json import load_diary_json, compute_stats, get_day

        diary = load_diary_json(_g.api_json_diary_path)
    except Exception:
        diary = None

    for base, display, variants in items:
        lesson = {"base": base, "display": display, "variants": variants}
        if diary is not None:
            try:
                m = re.search(r"_TPRS_(\d{4}-\d{2}-\d{2})", base)
                if m:
                    date_dash = m.group(1)
                    date_slash = date_dash.replace("-", "/")
                    day = get_day(diary, date_slash)
                    if day is not None:
                        total = len(day.entries)
                        mastered = sum(
                            1
                            for e in day.entries
                            if e.lessons.reviewing.status == "mastered"
                        )
                        learning = sum(
                            1
                            for e in day.entries
                            if e.lessons.reviewing.status == "learning"
                        )
                        new_count = total - mastered - learning
                        lesson["srs"] = {
                            "total": total,
                            "mastered": mastered,
                            "learning": learning,
                            "new": new_count,
                        }
            except Exception:
                pass
        result.append(lesson)
    return jsonify({"lessons": result})


@app.route("/api/sync/manifest", methods=["GET"])
@_jwt_required
def api_sync_manifest():
    """Return a manifest of all syncable files (mp3 + md) with size and mtime."""
    from flask import g as _g

    output_folder = _g.api_output_folder
    manifest = []
    for root, _, files in os.walk(output_folder):
        for fname in files:
            if (
                fname.startswith(".")
                or fname.endswith(".zip")
                or fname.endswith(".log")
            ):
                continue
            full = os.path.join(root, fname)
            rel = os.path.relpath(full, output_folder)
            stat = os.stat(full)
            manifest.append(
                {
                    "path": rel,
                    "size": stat.st_size,
                    "mtime": stat.st_mtime,
                }
            )
    return jsonify({"manifest": manifest})


@app.route("/api/sync/file/<path:rel_path>", methods=["GET"])
@_jwt_required
def api_sync_file(rel_path):
    """Download a single output file by its relative path."""
    from flask import g as _g

    output_folder = _g.api_output_folder
    # Security: resolve and ensure the path stays within output_folder
    safe_path = os.path.realpath(os.path.join(output_folder, rel_path))
    if not safe_path.startswith(os.path.realpath(output_folder)):
        return jsonify({"error": "Access denied"}), 403
    if not os.path.exists(safe_path):
        return jsonify({"error": "File not found"}), 404
    return send_file(safe_path, as_attachment=True)


@app.route("/api/sync/manifest/<path:base>", methods=["GET"])
@_jwt_required
def api_sync_lesson_manifest(base):
    """Return manifest filtered to files belonging to a single lesson (by base name).

    Always includes diary.json so the app can read lesson text offline.
    """
    from flask import g as _g

    output_folder = _g.api_output_folder
    manifest = []
    for root, _, files in os.walk(output_folder):
        for fname in files:
            if (
                fname.startswith(".")
                or fname.endswith(".zip")
                or fname.endswith(".log")
            ):
                continue
            full = os.path.join(root, fname)
            rel = os.path.relpath(full, output_folder)
            # Always include diary.json so lesson text is available offline
            if base not in rel and rel != "diary.json":
                continue
            stat = os.stat(full)
            manifest.append(
                {
                    "path": rel,
                    "size": stat.st_size,
                    "mtime": stat.st_mtime,
                }
            )
    return jsonify({"manifest": manifest})


@app.route("/api/diary/json", methods=["GET"])
@_jwt_required
def api_get_diary_json():
    """Return the full diary JSON for the authenticated user."""
    from flask import g as _g
    from lingodiary.diary_json import load_diary_json

    json_path = _g.api_json_diary_path
    if not os.path.exists(json_path):
        return jsonify({"diaries": []})
    try:
        diary = load_diary_json(json_path)
        return jsonify(diary.to_dict())
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@app.route("/api/diary/json", methods=["POST"])
@_jwt_required
def api_post_diary_json():
    """Overwrite diary JSON (full replace, for migration tool)."""
    from flask import g as _g
    from lingodiary.diary_json import DiaryJson, save_diary_json

    data = request.get_json(silent=True)
    if data is None:
        return jsonify({"error": "Invalid JSON body"}), 400
    try:
        diary = DiaryJson.from_dict(data)
        save_diary_json(diary, _g.api_json_diary_path)
        return jsonify({"ok": True})
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@app.route("/api/lessons/entries/<date>/<variant>", methods=["GET"])
@_jwt_required
def api_lesson_entries(date, variant):
    """Return entries list with audio timings for a given date and variant."""
    from flask import g as _g
    from lingodiary.diary_json import load_diary_json, get_day

    # Normalise date to YYYY/MM/DD
    date_slash = date.replace("-", "/")
    try:
        diary = load_diary_json(_g.api_json_diary_path)
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500

    day = get_day(diary, date_slash)
    if day is None:
        return jsonify({"date": date_slash, "variant": variant, "entries": []})

    entries_out = []
    for entry in day.entries:
        v_obj = entry.lessons.get_variant(variant)
        if not v_obj or not v_obj.sentence:
            continue
        entries_out.append(
            {
                "index": entry.index,
                "input_language_sentence": entry.input_language_sentence,
                "output_language_translation": entry.output_language_translation,
                "sentence": v_obj.sentence,
                "sentence_input": v_obj.sentence_input,
                "audio_timing": v_obj.audio_timing.to_dict(),
                "qa": [q.to_dict() for q in v_obj.qa],
                "reviewing": entry.lessons.reviewing.to_dict(),
            }
        )

    return jsonify({"date": date_slash, "variant": variant, "entries": entries_out})


@app.route("/api/lessons/score", methods=["POST"])
@_jwt_required
def api_lesson_score():
    """Apply SM-2 score to a diary entry. Body: {date, entry_index, score}."""
    from flask import g as _g
    from lingodiary.diary_json import load_diary_json, save_diary_json, update_srs

    data = request.get_json(silent=True) or {}
    date = data.get("date", "")
    entry_index = data.get("entry_index")
    score = data.get("score")

    if not date or entry_index is None or score is None:
        return jsonify({"error": "date, entry_index, and score are required"}), 400
    if score not in (0, 2, 3, 5):
        return jsonify({"error": "score must be one of 0, 2, 3, 5"}), 400

    date_slash = date.replace("-", "/")
    try:
        diary = load_diary_json(_g.api_json_diary_path)
        diary, reviewing = update_srs(diary, date_slash, int(entry_index), int(score))
        save_diary_json(diary, _g.api_json_diary_path)
        return jsonify({"ok": True, "reviewing": reviewing.to_dict()})
    except ValueError:
        return jsonify({"error": "Entry not found"}), 404
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@app.route("/api/home", methods=["GET"])
@_jwt_required
def api_home():
    """Dashboard: stats + recent + recommended lesson."""
    from flask import g as _g
    from lingodiary.diary_json import (
        load_diary_json,
        compute_stats,
        get_due_entries,
        get_recently_reviewed,
    )

    try:
        diary = load_diary_json(_g.api_json_diary_path)
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500

    stats = compute_stats(diary)

    recent_days = get_recently_reviewed(diary, limit=5)
    recent_lessons = []
    for day in recent_days:
        for entry in day.entries:
            lr = entry.lessons.reviewing.last_reviewed
            if lr:
                recent_lessons.append(
                    {
                        "date": day.date,
                        "title": day.title,
                        "entry_index": entry.index,
                        "last_reviewed": lr,
                        "status": entry.lessons.reviewing.status,
                    }
                )
    recent_lessons.sort(key=lambda x: x["last_reviewed"], reverse=True)
    recent_lessons = recent_lessons[:5]

    recommended = None
    due = get_due_entries(diary)
    if due:
        day, entry = due[0]
        recommended = {
            "date": day.date,
            "title": day.title,
            "entry_index": entry.index,
            "variant": "original",
            "reason": "due_for_review",
        }
    else:
        # Fall back to first new entry
        for day in diary.diaries:
            for entry in day.entries:
                if entry.lessons.reviewing.status == "new":
                    recommended = {
                        "date": day.date,
                        "title": day.title,
                        "entry_index": entry.index,
                        "variant": "original",
                        "reason": "new",
                    }
                    break
            if recommended:
                break

    return jsonify(
        {"stats": stats, "recent_lessons": recent_lessons, "recommended": recommended}
    )


@app.route("/api/migrate", methods=["POST"])
@_jwt_required
def api_migrate():
    """Trigger server-side migration from Markdown to JSON in a background thread."""
    from flask import g as _g

    config_path = _g.api_config_path
    json_path = _g.api_json_diary_path

    def _run():
        try:
            from lingodiary.migrate_to_json import migrate_markdown_to_json

            migrate_markdown_to_json(config_path, json_path, overwrite=True)
        except Exception as exc:
            app.logger.error("Migration failed: %s", exc)

    Thread(target=_run, daemon=True).start()
    return jsonify({"ok": True, "message": "Migration started"})


@app.route("/api/sentences/due", methods=["GET"])
@_jwt_required
def api_sentences_due():
    """Return due (or new) sentences for Anki-style review.

    Query params:
      limit  (int, default 20)  — max sentences to return
      variant (str, default "original") — which variant lesson to pull sentence/qa from
    """
    from flask import g as _g
    from lingodiary.diary_json import load_diary_json, get_due_entries

    limit = int(request.args.get("limit", 20))
    variant = request.args.get("variant", "original")

    try:
        diary = load_diary_json(_g.api_json_diary_path)
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500

    due_pairs = get_due_entries(diary)[:limit]
    sentences = []
    for day, entry in due_pairs:
        vl = getattr(entry.lessons, variant, None)
        if vl is None:
            continue
        sentences.append(
            {
                "date": day.date,
                "title": day.title,
                "entry_index": entry.index,
                "variant": variant,
                "input_language_sentence": entry.input_language_sentence,
                "output_language_translation": entry.output_language_translation,
                "tips": entry.tips,
                "sentence": vl.sentence,
                "sentence_audio_path": vl.sentence_audio_path,
                "audio_timing": vl.audio_timing.to_dict(),
                "qa": [qa.to_dict() for qa in vl.qa],
                "reviewing": entry.lessons.reviewing.to_dict(),
            }
        )
    return jsonify({"sentences": sentences, "total": len(sentences)})

    """Return the diary section for a specific date.

    date_str format: YYYY-MM-DD (as embedded in lesson base names).
    Returns JSON {"content": "<text>"} or {"content": ""} if not found.
    """
    from flask import g as _g

    diary_file = _g.api_diary_file
    if not os.path.exists(diary_file):
        return jsonify({"content": ""})

    # Convert YYYY-MM-DD -> YYYY/MM/DD for matching diary headers (## YYYY/MM/DD)
    try:
        date_slash = datetime.strptime(date_str, "%Y-%m-%d").strftime("%Y/%m/%d")
    except ValueError:
        return jsonify({"error": "Invalid date format, expected YYYY-MM-DD"}), 400

    with open(diary_file, "r", encoding="utf-8") as f:
        content = f.read()

    # Split on diary section headers  ## YYYY/MM/DD
    sections = re.split(r"(^##\s+\d{4}/\d{2}/\d{2}.*)", content, flags=re.MULTILINE)
    # sections: ["preamble", "## header", "body", "## header2", "body2", ...]
    for i in range(1, len(sections) - 1, 2):
        header = sections[i]
        body = sections[i + 1] if i + 1 < len(sections) else ""
        if date_slash in header:
            return jsonify({"content": (header + body).strip()})

    return jsonify({"content": ""})


@app.route("/api/diary/entry", methods=["POST"])
@_jwt_required
def api_add_diary_entry():
    """Add a structured diary entry: {date: 'YYYY-MM-DD', sentences: [...]}."""
    from flask import g as _g

    data = request.get_json(silent=True) or {}
    selected_date = data.get("date", "")
    sentences = data.get("sentences", [])

    if not selected_date or not sentences:
        return jsonify({"error": "date and sentences are required"}), 400

    try:
        datetime.strptime(selected_date, "%Y-%m-%d")
    except ValueError:
        return jsonify({"error": "Invalid date format, expected YYYY-MM-DD"}), 400

    try:
        from lingodiary.diary_json import (
            DiaryEntry,
            LessonsBlock,
            ReviewingState,
            load_diary_json,
            save_diary_json,
            upsert_day,
        )

        json_path = _g.api_json_diary_path
        if not json_path:
            return jsonify({"error": "json_diary_path not configured"}), 500

        date_slash = selected_date.replace("-", "/")
        diary_json = load_diary_json(json_path)
        entries = [
            DiaryEntry(
                index=i + 1,
                input_language_sentence=s,
                lessons=LessonsBlock(reviewing=ReviewingState()),
            )
            for i, s in enumerate(sentences)
        ]
        diary_json = upsert_day(diary_json, date_slash, "", entries)
        save_diary_json(diary_json, json_path)
    except Exception as exc:
        app.logger.error(f"api_add_diary_entry error: {exc}")
        return jsonify({"error": str(exc)}), 500

    return jsonify(
        {"success": True, "date": selected_date, "sentences_added": len(sentences)}
    )


@app.route("/api/config", methods=["GET"])
@_jwt_required
def api_get_config():
    """Return user config values relevant to the mobile app (TPRS keywords)."""
    from lingodiary.diary import (
        _TMPL_TPRS_ANSWER,
        _TMPL_TPRS_QUESTION,
        _TMPL_TPRS_SENTENCE,
    )

    return jsonify(
        {
            "tprs": {
                "sentence": _TMPL_TPRS_SENTENCE,
                "question": _TMPL_TPRS_QUESTION,
                "answer": _TMPL_TPRS_ANSWER,
            }
        }
    )


def main():
    app.run(debug=True, use_reloader=False, host="0.0.0.0", port=8084)


if __name__ == "__main__":
    main()
