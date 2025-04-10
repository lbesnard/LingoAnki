#!/usr/bin/env python3
import io
import json
import logging
import os
import subprocess
import time
import zipfile
from pathlib import Path
from queue import Queue
from threading import Thread

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
app.config["BABEL_DEFAULT_LOCALE"] = "en"
app.jinja_env.autoescape = True
app.jinja_env.globals.update(_=_)
app.config["LANGUAGES"] = ["en", "fr"]  # Supported languages

babel = Babel(app)

app.secret_key = os.getenv("SECRET_KEY", "super-secret-key")


USER_CONFIG_FILE = "users.json"
user_config_path = Path(user_config_dir(APP_NAME)) / USER_CONFIG_FILE

USER_DB_FILE = os.getenv("USER_DB_FILE", user_config_path)
CONFIG_ROOT = os.getenv(
    "CONFIG_ROOT", os.path.expanduser(Path(user_config_dir(APP_NAME)))
)

#
#
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
            session["diary_file"] = diary_instance.config["markdown_diary_path"]
            session["tprs_file"] = diary_instance.config["markdown_tprs_path"]
            session["output_folder"] = diary_instance.config["output_dir"]
            session["log_File"] = os.path.join(
                diary_instance.config["output_dir"], "output.log"
            )
            os.makedirs(session["output_folder"], exist_ok=True)

            return redirect("/")  # Redirect to the home page or the main page

        # If login fails, show an error message
        flash("Invalid login. Please check your username and password.", "error")
        return redirect(url_for("login"))

    # If it's a GET request, display the login form
    return render_template_string(
        """
        <form method="post">
            Username: <input name="username" required><br>
            Password: <input name="password" type="password" required><br>
            <input type="submit" value="Login">
        </form>
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
    user_config_path = os.path.join(CONFIG_ROOT, username, "config.yaml")
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

    user_config_path = session["user_config_path"]
    diary_instance = DiaryHandler(config_path=user_config_path)
    DIARY_FILE = diary_instance.config["markdown_diary_path"]
    OUTPUT_FOLDER = diary_instance.config["output_dir"]
    if request.method == "POST":
        with open(DIARY_FILE, "w") as f:
            f.write(request.form["content"])

    content = ""
    if os.path.exists(DIARY_FILE):
        with open(DIARY_FILE) as f:
            content = f.read()

    files = [
        f
        for f in os.listdir(OUTPUT_FOLDER)
        if not f.startswith(".") and f != "output.zip"
    ]

    template_help_text = diary_instance.template_help()

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

    user_config_path = session["user_config_path"]
    diary_instance = DiaryHandler(config_path=user_config_path)
    DIARY_FILE = diary_instance.config["markdown_diary_path"]
    OUTPUT_FOLDER = diary_instance.config["output_dir"]
    if os.path.exists(DIARY_FILE):
        with open(DIARY_FILE) as f:
            content = markdown.markdown(
                f.read(), extensions=["nl2br", "extra", "codehilite", "tables"]
            )
    files = [
        f
        for f in os.listdir(OUTPUT_FOLDER)
        if not f.startswith(".") and f != "output.zip"
    ]
    return render_template(
        "diary_html.html", content=content, tab="diary_html", files=files
    )


@app.route("/tprs", methods=["GET", "POST"])
def view_tprs():
    global tprs_content

    user_config_path = session["user_config_path"]
    diary_instance = DiaryHandler(config_path=user_config_path)
    TPRS_FILE = diary_instance.config["markdown_tprs_path"]
    OUTPUT_FOLDER = diary_instance.config["output_dir"]
    if request.method == "POST":
        pass
    if os.path.exists(TPRS_FILE):
        with open(TPRS_FILE) as f:
            tprs_content = markdown.markdown(
                f.read(), extensions=["nl2br", "extra", "codehilite", "tables"]
            )

    files = [
        f
        for f in os.listdir(OUTPUT_FOLDER)
        if not f.startswith(".") and f != "output.zip"
    ]
    return render_template(
        "diary_tprs.html", tprs_content=tprs_content, tab="tprs", files=files
    )


@app.route("/generate_lessons", methods=["GET", "POST"])
def generate_lessons():
    if request.method == "POST":
        app.config["PROPAGATE_EXCEPTIONS"] = True

        app.logger.setLevel(logging.DEBUG)

        app.logger.debug("Starting generate_lessons process.")

        # Call the standalone script
        try:
            user_config_path = session["user_config_path"]
            diary_instance = DiaryHandler(config_path=user_config_path)
            OUTPUT_FOLDER = diary_instance.config["output_dir"]

            # some issues with sqlite when calling PiperTTS. requires flask to run with app.run(debug=True, use_reloader=False)
            diary_instance = DiaryHandler(config_path=user_config_path)
            diary_instance.diary_complete_translations()
            diary_instance.convert_diary_entries_to_ankideck()

            tprs_instance = TprsCreation(config_path=user_config_path)
            tprs_instance.check_missing_sentences_from_existing_tprs()
            tprs_instance.add_missing_tprs()
            tprs_instance.convert_tts_tprs_entries()

            app.logger.debug(f"generated_tprs.py output")
        except subprocess.CalledProcessError as e:
            app.logger.error("generate_tprs.py failed")

        app.logger.debug("Completed generate_lessons process.")

        app.logger.debug("Completed TPRS creation process.")

    user_config_path = session["user_config_path"]
    diary_instance = DiaryHandler(config_path=user_config_path)
    OUTPUT_FOLDER = diary_instance.config["output_dir"]
    files = [
        f
        for f in os.listdir(OUTPUT_FOLDER)
        if not f.startswith(".") and f != "output.zip"
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
    user_config_path = session["user_config_path"]
    diary_instance = DiaryHandler(config_path=user_config_path)
    OUTPUT_FOLDER = diary_instance.config["output_dir"]
    files = [
        f
        for f in os.listdir(OUTPUT_FOLDER)
        if not f.startswith(".") and f != "output.zip"
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
    user_config_path = session["user_config_path"]
    diary_instance = DiaryHandler(config_path=user_config_path)
    LOG_FILE = os.path.join(diary_instance.config["output_dir"], "output.log")

    log_file = LOG_FILE
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
    user_config_path = session["user_config_path"]
    diary_instance = DiaryHandler(config_path=user_config_path)
    OUTPUT_FOLDER = diary_instance.config["output_dir"]

    return send_file(
        # os.path.join(OUTPUT_FOLDER, secure_filename(filename)), as_attachment=True
        os.path.join(OUTPUT_FOLDER, filename),
        as_attachment=True,
    )


@app.route("/download_zip")
def download_zip():
    user_config_path = session["user_config_path"]
    diary_instance = DiaryHandler(config_path=user_config_path)
    OUTPUT_FOLDER = diary_instance.config["output_dir"]
    zip_path = os.path.join(OUTPUT_FOLDER, "output.zip")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zipf:
        for root, _, files in os.walk(OUTPUT_FOLDER):
            for file in files:
                if not file.startswith(".") and file != "output.zip":
                    full_path = os.path.join(root, file)
                    rel_path = os.path.relpath(full_path, OUTPUT_FOLDER)
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


def main():
    app.run(debug=True, use_reloader=False, host="0.0.0.0", port=8084)


if __name__ == "__main__":
    main()
