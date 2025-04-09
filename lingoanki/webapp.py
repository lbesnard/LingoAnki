#!/usr/bin/env python3
import io
import json
import logging
import os
import subprocess
import yaml
import time
import zipfile
from queue import Queue
from threading import Thread

import bcrypt
import markdown
from flask import (
    Flask,
    Response,
    flash,
    jsonify,
    get_flashed_messages,
    redirect,
    render_template_string,
    request,
    send_file,
    session,
    url_for,
)

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

from pathlib import Path

from platformdirs import user_config_dir

USER_CONFIG_FILE = "users.json"
user_config_path = Path(user_config_dir(APP_NAME)) / USER_CONFIG_FILE

USER_DB_FILE = os.getenv("USER_DB_FILE", user_config_path)
CONFIG_ROOT = os.getenv(
    "CONFIG_ROOT", os.path.expanduser(Path(user_config_dir(APP_NAME)))
)

#
# diary_instance = DiaryHandler()
# DIARY_FILE = diary_instance.config["markdown_diary_path"]
# TPRS_FILE = diary_instance.config["markdown_tprs_path"]
# OUTPUT_FOLDER = diary_instance.config["output_dir"]
# LOG_FILE = os.path.join(diary_instance.config["output_dir"], "output.log")
# os.makedirs(OUTPUT_FOLDER, exist_ok=True)
#
# Update the template to include the edit functionality
TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>Markdown WebApp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 2em; }
        nav a { margin-right: 2em; text-decoration: none; }
        textarea { width: 100%; height: 300px; }
        .output-list { margin-top: 2em; }
        .entry { display: flex; align-items: center; }
        .entry input { margin-left: 10px; width: 300px; }

                body { font-family: Arial, sans-serif; margin: 2em; }
        nav a { margin-right: 2em; text-decoration: none; }
        textarea { width: 100%; height: 300px; }
        .output-list { margin-top: 2em; }
        .entry { display: flex; align-items: center; }
        .entry input { margin-left: 10px; width: 300px; }
        .banner { padding: 10px; background-color: #f4f4f4; text-align: right; }
        .banner button { padding: 5px 15px; background-color: #ff4d4d; border: none; color: white; cursor: pointer; }
        .banner button:hover { background-color: #ff1a1a; }
        .flash-message {
            padding: 10px;
            margin-bottom: 20px;
            border-radius: 5px;
            font-size: 14px;
        }
        .flash-error {
            background-color: #f8d7da;
            color: #721c24;
        }
        .flash-success {
            background-color: #d4edda;
            color: #155724;
        }
    </style>
</head>
<body>
    <!-- Banner with logout button -->
    <div class="banner">
        {% if session.get('username') %}
            <span>Logged in as {{ session['username'] }}</span>
            <form action="/logout" method="POST" style="display:inline;">
                <button type="submit">Logout</button>
            </form>
        {% endif %}
    </div>


    <nav>
        <a href="/">Step 1: Edit Diary</a>
        <a href="/diary_html">View Diary HTML</a>
        <a href="/tprs">View TPRS</a>
        <a href="/generate_lessons">Step 2: Generate Lessons</a>
        <a href="/output">Step 3: Output Files</a>
    </nav>

    {% with messages = get_flashed_messages(with_categories=true) %}
        {% if messages %}
            <div id="flash-messages">
                {% for category, message in messages %}
                    <div class="alert {{ category }}">
                        {{ message }}
                    </div>
                {% endfor %}
            </div>
        {% endif %}
    {% endwith %}

    {% if tab == 'edit' %}
    <h2>Edit Diary</h2>
    <p>
        You can edit the diary in two ways:
        <ul>
            <li>By adding sentences directly in the text box below with the following template and clicking "Save".</li>
"""

TEMPLATE += """
<button onclick="copyHelp()">Copy</button>
<script>
function copyHelp() {
    const textarea = document.querySelector('#help-template');
    textarea.select();
    document.execCommand('copy');
}
</script>
<textarea id="help-template" readonly style="width: 100%; height: 200px;">{{ template_help }}</textarea>

"""

TEMPLATE += """
            <li>By selecting a specific date from the calendar widget or entering the date manually, then adding sentences for that day.</li>
        </ul>
    </p>
    <form method="POST">
        <textarea name="content">{{ content }}</textarea><br>
        <button type="submit">Save</button>
    </form>

    <h3>Add Sentence for Specific Date</h3>
    <form method="POST" action="/edit_entry">
        <label for="date_input">Select a date:</label>
        <input type="date" id="date_input" name="date_input"><br>
        <button type="submit">Set Date</button>
    </form>

    {% if selected_date %}
    <h3>Sentence for {{ selected_date }}</h3>
    <form method="POST" action="/add_sentence">
        <input type="text" name="sentence" placeholder="Add a new sentence" required>
        <button type="submit">Add Sentence</button>
    </form>
    {% endif %}

    <div id="entries">
        {% for entry in diary_entries %}
        <div class="entry">
            <form method="POST" action="/edit_sentence/{{ loop.index0 }}">
                <button type="submit">Edit</button>
            </form>
            <p>{{ entry.date }}:
                {% if loop.index0 == selected_edit %}
                <form method="POST" action="/edit_sentence/{{ loop.index0 }}">
                    <input type="text" name="sentence" value="{{ entry.sentence }}" required>
                    <button type="submit">Apply</button>
                </form>
                {% else %}
                    {{ entry.sentence }}
                {% endif %}
            </p>
        </div>
        {% endfor %}
    </div>

    <form method="POST" action="/save_diary_entry">
        <button type="submit" id="save_diary">Save Diary Entry for Date</button>
    </form>

    {% elif tab == 'diary_html' %}
    <h2>Diary HTML</h2>
    <div>{{ content|safe }}</div>
    {% elif tab == 'tprs' %}
    <h2>TPRS Markdown</h2>
    <div>{{ tprs_content|safe }}</div>
    <form method="POST" action="/refresh_tprs">
        <button type="submit">Refresh TPRS</button>
    </form>
    {% elif tab == 'generate_lessons' %}
    <h2>Generate Lessons</h2>
    <form method="POST" action="/generate_lessons">
        <button type="submit">Generate</button>
    </form>
    <p>TODO: Define function to generate lessons here.</p>
       <div id="log-container" style="height: 300px; overflow-y: auto; border: 1px solid #ccc;">
        <pre id="log-content"></pre>
    </div>

    <script>
        function fetchLog() {
            fetch('/get_log')
                .then(response => response.json())
                .then(data => {
                    const logContent = document.getElementById("log-content");
                    logContent.textContent = data.log; // Update the log content with new logs
                    logContent.scrollTop = logContent.scrollHeight; // Auto-scroll to the latest log
                })
                .catch(error => console.error('Error fetching log:', error));
        }

        // Call fetchLog every 200ms to refresh the content
        setInterval(fetchLog, 200);
    </script>

        {% elif tab == 'output' %}
    <h2>Output Files</h2>
    <ul>
        {% for filename in files %}
        <li><a href="/download/{{ filename }}">{{ filename }}</a></li>
        {% endfor %}
    </ul>
    <form action="/download_zip">
        <button type="submit">Download All as Zip</button>
    </form>
    {% endif %}

</body>
</html>

"""

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


# @app.route("/login", methods=["GET", "POST"])
# def login():
#     if request.method == "POST":
#         username = request.form["username"]
#         password = request.form["password"]
#         with open(USER_DB_FILE) as f:
#             users = json.load(f)
#         if username in users and bcrypt.checkpw(
#             password.encode(), users[username].encode()
#         ):
#             session["username"] = username
#             return redirect("/")
#         return "Invalid login", 401
#     return """
#         <form method="post">
#             Username: <input name="username"><br>
#             Password: <input name="password" type="password"><br>
#             <input type="submit" value="Login">
#         </form>
#     """


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

    return render_template_string(
        TEMPLATE,
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
    return render_template_string(
        TEMPLATE, content=content, tab="diary_html", files=files
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
    return render_template_string(
        TEMPLATE, tprs_content=tprs_content, tab="tprs", files=files
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
    return render_template_string(TEMPLATE, tab="generate_lessons", files=files)


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
    return render_template_string(TEMPLATE, content="", tab="output", files=files)


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
    return render_template_string(
        TEMPLATE,
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


def main():
    app.run(debug=True, use_reloader=False, host="0.0.0.0", port=8084)


if __name__ == "__main__":
    main()
