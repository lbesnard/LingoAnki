#!/usr/bin/env python3
import logging
import os
import re
from collections import defaultdict
from datetime import datetime, timedelta
from functools import wraps
from pathlib import Path
import queue
from threading import Thread

import jwt

import bcrypt
import yaml
from flask import (
    Flask,
    Response,
    g,
    jsonify,
    request,
    send_file,
    send_from_directory,
)
from platformdirs import user_config_dir

from lingodiary.diary import (
    APP_NAME,
    DiaryHandler,
    TprsCreation,
    main as main_diary_tprs,
)


app = Flask(__name__)
_secret_key = os.getenv("SECRET_KEY", "super-secret-key")
if _secret_key == "super-secret-key":
    raise RuntimeError(
        "SECRET_KEY environment variable is not set. "
        'Generate one with: python3 -c "import secrets; print(secrets.token_hex(32))"'
    )
app.secret_key = _secret_key
JWT_SECRET = _secret_key
JWT_ALGORITHM = "HS256"
JWT_EXPIRY_HOURS = 24 * 7  # 7 days

# Bounded job queue — at most 1 pending job (current + 1 queued).
_job_queue: queue.Queue = queue.Queue(maxsize=2)


def _start_job_worker():
    """Single background worker that drains the job queue sequentially."""
    while True:
        fn = _job_queue.get()
        try:
            fn()
        except Exception as exc:
            app.logger.error(f"Background job failed: {exc}", exc_info=True)
        finally:
            _job_queue.task_done()


Thread(target=_start_job_worker, daemon=True).start()


@app.after_request
def add_cache_headers(response):
    """Add cache-control headers to prevent browser caching of API responses."""
    # API responses should not be cached by the browser to avoid stale data issues
    if request.path.startswith("/api/"):
        response.headers[
            "Cache-Control"
        ] = "no-cache, no-store, must-revalidate, max-age=0"
        response.headers["Pragma"] = "no-cache"
        response.headers["Expires"] = "0"
    return response


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


USER_CONFIG_FILE = "users.yaml"
users_config_path = Path(user_config_dir(APP_NAME)) / USER_CONFIG_FILE

USER_DB_FILE = os.getenv("USER_DB_FILE", users_config_path)
CONFIG_ROOT = os.getenv(
    "CONFIG_ROOT", os.path.expanduser(Path(user_config_dir(APP_NAME)))
)


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

        # Inject into Flask's g so route handlers can access it.
        # Load config directly (no DiaryHandler instantiation) to avoid a race
        # condition where stop() would destroy the background generation thread's
        # file log handler on every polling request.
        from flask import g as _g

        config = DiaryHandler.load_config(user_config_path)
        _g.api_username = username
        _g.api_config_path = user_config_path
        _g.api_output_folder = config["output_dir"]
        _g.api_tprs_folder = os.path.join(_g.api_output_folder, "TPRS")
        _g.api_json_diary_path = config.get("json_diary_path") or os.path.join(
            _g.api_output_folder, "diary.json"
        )
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
        log_file = os.path.join(output_folder, "output.log")

        def _log_to_file(msg):
            try:
                with open(log_file, "a", encoding="utf-8") as lf:
                    lf.write(msg + "\n")
            except Exception:
                pass

        # Back up diary.json before anything mutates it.
        try:
            import shutil
            from datetime import datetime as _dt, timezone as _tz
            from pathlib import Path as _Path

            json_src = os.path.join(output_folder, "diary.json")
            if os.path.exists(json_src):
                backup_dir = _Path(output_folder) / ".backup"
                backup_dir.mkdir(parents=True, exist_ok=True)
                ts = _dt.now(_tz.utc).strftime("%Y%m%dT%H%M%SZ")
                shutil.copy2(json_src, backup_dir / f"diary_{ts}.json")
                # Prune backups older than 7 days
                cutoff = _dt.now(_tz.utc).timestamp() - 7 * 86400
                for old in backup_dir.glob("diary_*.json"):
                    try:
                        if old.stat().st_mtime < cutoff:
                            old.unlink()
                    except OSError:
                        pass
        except Exception as exc:
            app.logger.warning(f"diary.json backup failed: {exc}")

        try:
            main_diary_tprs(config_path=config_path)
        except Exception as exc:
            app.logger.error(f"API generate error: {exc}")
            _log_to_file(f"ERROR: Generation failed: {exc}")
        # Backfill any missing Q&A translations
        try:
            json_path = os.path.join(output_folder, "diary.json")
            TprsCreation(config_path).backfill_qa_translations(json_path)
        except Exception as exc:
            app.logger.warning(f"Q&A translation backfill failed: {exc}")
            _log_to_file(f"WARNING: Q&A translation backfill failed: {exc}")
        # Backfill missing variant sentence_input translations
        try:
            json_path = os.path.join(output_folder, "diary.json")
            TprsCreation(config_path).backfill_sentence_inputs(json_path)
        except Exception as exc:
            app.logger.warning(f"sentence_input backfill failed: {exc}")
            _log_to_file(f"WARNING: sentence_input backfill failed: {exc}")
        # Backfill missing per-sentence audio segments and timing data in diary.json
        try:
            from lingodiary.audio_timing import backfill_audio_timings

            json_path = os.path.join(output_folder, "diary.json")
            backfill_audio_timings(config_path=config_path, diary_json_path=json_path)
        except Exception as exc:
            app.logger.warning(f"Audio timing backfill failed: {exc}")
            _log_to_file(f"WARNING: Audio timing backfill failed: {exc}")
        # Write a completion marker so the client can stop polling.
        try:
            with open(log_file, "a", encoding="utf-8") as lf:
                lf.write("=== Generation finished ===\n")
        except Exception:
            pass

    try:
        _job_queue.put_nowait(_run)
    except queue.Full:
        return (
            jsonify(
                {"ok": False, "error": "A job is already queued. Try again later."}
            ),
            409,
        )
    return jsonify({"ok": True, "message": "Generation started"})


@app.route("/api/backfill/qa_translations", methods=["POST"])
@_jwt_required
def api_backfill_qa_translations():
    """Background job: translate all missing Q&A pairs to the primary language."""
    from flask import g as _g

    config_path = _g.api_config_path
    output_folder = _g.api_output_folder

    def _run():
        try:
            json_path = os.path.join(output_folder, "diary.json")
            TprsCreation(config_path).backfill_qa_translations(json_path)
        except Exception as exc:
            app.logger.error(f"Q&A translation backfill error: {exc}")

    try:
        _job_queue.put_nowait(_run)
    except queue.Full:
        return (
            jsonify(
                {"ok": False, "error": "A job is already queued. Try again later."}
            ),
            409,
        )
    return jsonify({"ok": True, "message": "Q&A translation backfill started"})


@app.route("/api/backfill/audio_timing", methods=["POST"])
@_jwt_required
def api_backfill_audio_timing():
    """Background job: generate per-sentence audio segments and write timings to diary.json.

    Accepts optional JSON body: {"overwrite": true} to force TTS re-generation for all
    days (slow).  Without the flag (default false), only recomputes timing from existing
    segment files when zero timing is detected — much faster.
    """
    from flask import g as _g, request as _req

    config_path = _g.api_config_path
    output_folder = _g.api_output_folder

    body = _req.get_json(silent=True) or {}
    overwrite = bool(body.get("overwrite", False))

    def _run():
        try:
            from lingodiary.audio_timing import backfill_audio_timings

            json_path = os.path.join(output_folder, "diary.json")
            backfill_audio_timings(
                config_path=config_path,
                diary_json_path=json_path,
                overwrite_existing=overwrite,
            )
        except Exception as exc:
            app.logger.error(f"Audio timing backfill error: {exc}")

    try:
        _job_queue.put_nowait(_run)
    except queue.Full:
        return (
            jsonify(
                {"ok": False, "error": "A job is already queued. Try again later."}
            ),
            409,
        )
    return jsonify({"ok": True, "message": "Audio timing backfill started"})


@app.route("/api/backfill/all", methods=["POST"])
@_jwt_required
def api_backfill_all():
    """Background job: fill in everything missing — Q&A translations, sentence inputs, audio segments.

    Runs in sequence:
      1. backfill_qa_translations    (translate missing Q&A pairs)
      2. backfill_sentence_inputs    (translate missing variant sentence_input fields)
      3. backfill_audio_timings      (generate missing segment MP3s + timing data)
    """
    from flask import g as _g

    config_path = _g.api_config_path
    output_folder = _g.api_output_folder

    def _run():
        json_path = os.path.join(output_folder, "diary.json")

        app.logger.info("Backfill all: step 1/3 — Q&A translations")
        try:
            TprsCreation(config_path).backfill_qa_translations(json_path)
        except Exception as exc:
            app.logger.warning(f"Backfill all: Q&A translation failed: {exc}")

        app.logger.info("Backfill all: step 2/3 — variant sentence_input translations")
        try:
            TprsCreation(config_path).backfill_sentence_inputs(json_path)
        except Exception as exc:
            app.logger.warning(f"Backfill all: sentence_input backfill failed: {exc}")

        app.logger.info("Backfill all: step 3/3 — audio timing / segments")
        try:
            from lingodiary.audio_timing import backfill_audio_timings

            backfill_audio_timings(config_path=config_path, diary_json_path=json_path)
        except Exception as exc:
            app.logger.warning(f"Backfill all: audio timing failed: {exc}")

        app.logger.info("Backfill all: complete")

    try:
        _job_queue.put_nowait(_run)
    except queue.Full:
        return (
            jsonify(
                {"ok": False, "error": "A job is already queued. Try again later."}
            ),
            409,
        )
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
        with open(log_file, "r", encoding="utf-8") as f:
            lines = f.readlines()
        lines = lines[-50:]
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

    # Get recently studied lessons (by lesson last_reviewed, not entry last_reviewed)
    recently_studied = [day for day in diary.diaries if day.last_reviewed is not None]
    recently_studied.sort(key=lambda d: d.last_reviewed, reverse=True)

    recent_lessons = []
    for day in recently_studied[:5]:
        recent_lessons.append(
            {
                "date": day.date,
                "title": day.title,
                "last_reviewed": day.last_reviewed,
                "entry_count": len(day.entries),
            }
        )

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
            get_day,
            load_diary_json,
            save_diary_json,
            upsert_day,
        )

        json_path = _g.api_json_diary_path
        if not json_path:
            return jsonify({"error": "json_diary_path not configured"}), 500

        date_slash = selected_date.replace("-", "/")
        diary_json = load_diary_json(json_path)
        day_existed = get_day(diary_json, date_slash) is not None
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
        {
            "success": True,
            "date": selected_date,
            "sentences_added": len(sentences),
            "warnings": (
                [
                    f"Day {selected_date} already existed — new sentences were merged into the existing day. Audio will need to be regenerated."
                ]
                if day_existed
                else []
            ),
        }
    )


@app.route("/api/config", methods=["GET"])
@_jwt_required
def api_get_config():
    """Return user config values relevant to the mobile app (TPRS keywords)."""
    return jsonify(
        {
            "tprs": {
                "sentence": "SETNING:",
                "question": "SPØRSMÅL:",
                "answer": "SVAR:",
            }
        }
    )


@app.route("/api/lessons/last_reviewed/<date>", methods=["GET"])
@_jwt_required
def api_get_lesson_last_reviewed(date):
    """Get the last_reviewed timestamp for a specific lesson date."""
    from flask import g as _g
    from lingodiary.diary_json import load_diary_json, get_day

    # Normalize date to YYYY/MM/DD
    date_slash = date.replace("-", "/")

    try:
        diary = load_diary_json(_g.api_json_diary_path)
        day = get_day(diary, date_slash)
        if day is None:
            return jsonify({"error": "Lesson not found"}), 404

        return jsonify({"date": date_slash, "last_reviewed": day.last_reviewed})
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@app.route("/api/lessons/last_reviewed/<date>", methods=["PUT"])
@_jwt_required
def api_update_lesson_last_reviewed(date):
    """Update the last_reviewed timestamp for a specific lesson date."""
    from flask import g as _g
    from lingodiary.diary_json import load_diary_json, save_diary_json, get_day
    from datetime import datetime, timezone

    # Normalize date to YYYY/MM/DD
    date_slash = date.replace("-", "/")

    data = request.get_json(silent=True) or {}
    timestamp = data.get("timestamp")

    # If no timestamp provided, use current time
    if not timestamp:
        timestamp = datetime.now(timezone.utc).isoformat()

    try:
        diary = load_diary_json(_g.api_json_diary_path)
        day = get_day(diary, date_slash)
        if day is None:
            return jsonify({"error": "Lesson not found"}), 404

        day.last_reviewed = timestamp
        save_diary_json(diary, _g.api_json_diary_path)

        return jsonify(
            {"date": date_slash, "last_reviewed": day.last_reviewed, "success": True}
        )
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


@app.route("/api/lessons/recently_studied", methods=["GET"])
@_jwt_required
def api_recently_studied_lessons():
    """Get the 10 most recently studied lessons (by last_reviewed timestamp)."""
    from flask import g as _g
    from lingodiary.diary_json import load_diary_json

    limit = int(request.args.get("limit", 10))

    try:
        diary = load_diary_json(_g.api_json_diary_path)

        # Filter days that have been reviewed and sort by last_reviewed desc
        reviewed_days = [day for day in diary.diaries if day.last_reviewed is not None]
        reviewed_days.sort(key=lambda d: d.last_reviewed, reverse=True)

        # Take the most recent ones
        recent = reviewed_days[:limit]

        result = []
        for day in recent:
            result.append(
                {
                    "date": day.date,
                    "title": day.title,
                    "last_reviewed": day.last_reviewed,
                    "entry_count": len(day.entries),
                }
            )

        return jsonify({"lessons": result, "total": len(result)})
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


def main():
    app.run(debug=True, use_reloader=False, host="0.0.0.0", port=8084)


if __name__ == "__main__":
    main()
