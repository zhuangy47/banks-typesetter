"""
Banks of the Boneyard - Layout Editor UI
Flask server providing a visual grid editor and article management.
"""
import json
import os
import re
import subprocess
import threading
from pathlib import Path

import yaml
from flask import Flask, render_template, jsonify, request, send_file, abort

ROOT = Path(__file__).resolve().parent.parent


def _resolve_issue_dir():
    """Active issue directory: $BANKS_ISSUE, else the most-recent issues/<name>/."""
    issues_dir = ROOT / "issues"
    name = os.environ.get("BANKS_ISSUE", "").strip()
    if name and (issues_dir / name).is_dir():
        return issues_dir / name
    candidates = [
        p for p in (issues_dir.iterdir() if issues_dir.is_dir() else [])
        if p.is_dir() and not p.name.startswith(("_", "."))
    ]
    if candidates:
        return max(candidates, key=lambda p: p.stat().st_mtime)
    # Nothing exists yet — fall back so the app still starts.
    return issues_dir / (name or "issue")


ISSUE_DIR = _resolve_issue_dir()
ISSUE = ISSUE_DIR.name
app = Flask(__name__)

# ---------------------------------------------------------------------------
# Build state (shared across requests via threading)
# ---------------------------------------------------------------------------
build_state = {"running": False, "log": "", "return_code": None, "mode": None}
build_lock = threading.Lock()


# ===== Page routes =========================================================

@app.route("/")
def index():
    return render_template("index.html")


# ===== Layout API ==========================================================

def _layout_path_for_mode(mode):
    """Return the layout file path for a given mode (online/print)."""
    if mode not in ("online", "print"):
        mode = "online"
    return ISSUE_DIR / f"layout-{mode}.yaml"


def _read_layout(path):
    """Read and normalize a layout file, returning a dict."""
    empty = {
        "grid": {"rows": 12, "columns": 6, "gutter": "8pt", "text_gutter": "8pt"},
        "articles": [],
    }
    if not path.exists() or path.stat().st_size == 0:
        return empty
    with open(path) as f:
        data = yaml.safe_load(f)
    if not data or not isinstance(data, dict):
        return empty
    for art in data.get("articles") or []:
        if not art.get("placements"):
            art["placements"] = []
        if art.get("images") is None:
            art["images"] = []
        for pl in art["placements"]:
            if pl.get("cells") is None:
                pl["cells"] = []
            if pl.get("images") is None:
                pl["images"] = []
    if data.get("articles") is None:
        data["articles"] = []
    return data


@app.route("/api/layout")
def get_layout():
    mode = request.args.get("mode", "")
    # Missing file → _read_layout returns an empty grid to start from.
    return jsonify(_read_layout(_layout_path_for_mode(mode)))


@app.route("/api/layout", methods=["PUT"])
def put_layout():
    data = request.json
    mode = request.args.get("mode", "")
    text = serialize_layout(data)
    path = _layout_path_for_mode(mode)
    path.write_text(text)
    return jsonify({"ok": True})


@app.route("/api/layout/copy", methods=["POST"])
def copy_layout():
    """Copy layout from one mode to another. Body: {"from": "online", "to": "print"}"""
    body = request.json
    src_mode = body.get("from", "")
    dst_mode = body.get("to", "")
    if src_mode not in ("online", "print") or dst_mode not in ("online", "print"):
        return jsonify({"error": "from/to must be 'online' or 'print'"}), 400
    if src_mode == dst_mode:
        return jsonify({"error": "from and to must differ"}), 400
    src_path = _layout_path_for_mode(src_mode)
    dst_path = _layout_path_for_mode(dst_mode)
    if not src_path.exists():
        return jsonify({"error": f"Source layout ({src_path.name}) not found"}), 404
    dst_path.write_text(src_path.read_text())
    return jsonify({"ok": True})


# ===== Config API ==========================================================

@app.route("/api/config")
def get_config():
    with open(ISSUE_DIR / "config.yaml") as f:
        return jsonify(yaml.safe_load(f))


@app.route("/api/config", methods=["PUT"])
def put_config():
    data = request.json
    with open(ISSUE_DIR / "config.yaml", "w") as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
    return jsonify({"ok": True})


# ===== Events API ==========================================================

@app.route("/api/events")
def get_events():
    with open(ISSUE_DIR / "events.yaml") as f:
        return jsonify(yaml.safe_load(f))


@app.route("/api/events", methods=["PUT"])
def put_events():
    data = request.json
    with open(ISSUE_DIR / "events.yaml", "w") as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
    return jsonify({"ok": True})


# ===== Articles API ========================================================

@app.route("/api/articles")
def list_articles():
    articles = []
    for md in sorted((ISSUE_DIR / "articles").glob("*.md")):
        text = md.read_text()
        fm = _parse_frontmatter(text)
        body = _extract_body(text)
        images = _extract_images(body)
        articles.append({
            "slug": md.stem,
            "title": fm.get("title", md.stem),
            "authors": fm.get("authors", []),
            "images": images,
        })
    return jsonify(articles)


@app.route("/api/articles/<slug>")
def get_article(slug):
    path = ISSUE_DIR / "articles" / f"{slug}.md"
    if not path.exists():
        abort(404)
    text = path.read_text()
    fm = _parse_frontmatter(text)
    body = _extract_body(text)
    return jsonify({
        "slug": slug,
        "title": fm.get("title", slug),
        "authors": fm.get("authors", []),
        "body": body,
    })


@app.route("/api/articles/<slug>", methods=["PUT"])
def put_article(slug):
    data = request.json
    path = ISSUE_DIR / "articles" / f"{slug}.md"
    content = "---\n"
    content += yaml.dump(
        {"title": data["title"], "authors": data["authors"]},
        default_flow_style=False, sort_keys=False, allow_unicode=True,
    )
    content += "---\n\n"
    content += data["body"]
    path.write_text(content)
    return jsonify({"ok": True})


@app.route("/api/articles", methods=["POST"])
def create_article():
    data = request.json
    slug = data["slug"]
    path = ISSUE_DIR / "articles" / f"{slug}.md"
    if path.exists():
        return jsonify({"error": "Article already exists"}), 409
    content = "---\n"
    content += yaml.dump(
        {"title": data.get("title", slug), "authors": data.get("authors", [])},
        default_flow_style=False, sort_keys=False, allow_unicode=True,
    )
    content += "---\n\n"
    content += data.get("body", "")
    path.write_text(content)
    return jsonify({"ok": True}), 201


@app.route("/api/articles/<slug>", methods=["DELETE"])
def delete_article(slug):
    path = ISSUE_DIR / "articles" / f"{slug}.md"
    if not path.exists():
        abort(404)
    path.unlink()
    return jsonify({"ok": True})


# ===== LFTC API ============================================================

@app.route("/api/lftc")
def get_lftc():
    path = ISSUE_DIR / "lftc.md"
    text = path.read_text()
    fm = _parse_frontmatter(text)
    body = _extract_body(text)
    return jsonify({
        "author": (fm.get("authors") or [""])[0] if fm.get("authors") else fm.get("author", ""),
        "title": fm.get("title", "Letter from the Chair"),
        "body": body,
    })


@app.route("/api/lftc", methods=["PUT"])
def put_lftc():
    data = request.json
    path = ISSUE_DIR / "lftc.md"
    content = "---\n"
    content += yaml.dump(
        {"title": data.get("title", "Letter from the Chair"), "authors": [data["author"]]},
        default_flow_style=False, sort_keys=False, allow_unicode=True,
    )
    content += "---\n\n"
    content += data["body"]
    path.write_text(content)
    return jsonify({"ok": True})


# ===== Images API ==========================================================

@app.route("/api/images")
def list_images():
    img_dir = ISSUE_DIR / "articles" / "images"
    if not img_dir.exists():
        return jsonify([])
    exts = {".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp"}
    images = sorted(f.name for f in img_dir.iterdir() if f.suffix.lower() in exts)
    return jsonify(images)


@app.route("/api/images/<name>")
def get_image(name):
    path = ISSUE_DIR / "articles" / "images" / name
    if not path.exists():
        abort(404)
    return send_file(path)


@app.route("/api/images", methods=["POST"])
def upload_image():
    if "file" not in request.files:
        return jsonify({"error": "No file"}), 400
    f = request.files["file"]
    dest = ISSUE_DIR / "articles" / "images" / f.filename
    f.save(dest)
    return jsonify({"ok": True, "name": f.filename}), 201


# ===== Build API ===========================================================

@app.route("/api/build", methods=["POST"])
def start_build():
    mode = request.json.get("mode", "online")
    debug = request.json.get("debug", False)
    with build_lock:
        if build_state["running"]:
            return jsonify({"error": "Build already running"}), 409
        build_state.update(running=True, log="", return_code=None, mode=mode,
                           debug=debug)

    def run():
        try:
            cmd = [str(ROOT / ".venv" / "bin" / "python"), str(ROOT / "build.py"),
                   "--mode", mode, "--issue", ISSUE]
            if debug:
                cmd.append("--debug")
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                cwd=str(ROOT), text=True,
            )
            for line in proc.stdout:
                build_state["log"] += line
            proc.wait()
            build_state["return_code"] = proc.returncode
        finally:
            build_state["running"] = False

    threading.Thread(target=run, daemon=True).start()
    return jsonify({"ok": True})


@app.route("/api/build/status")
def build_status():
    return jsonify({
        "running": build_state["running"],
        "log": build_state["log"],
        "return_code": build_state["return_code"],
        "mode": build_state["mode"],
        "debug": build_state.get("debug", False),
    })


@app.route("/api/pdf/<mode>")
def get_pdf(mode):
    if mode not in ("online", "print", "online-debug", "print-debug"):
        abort(400)
    path = ROOT / "build" / "output" / f"banks-{mode}.pdf"
    if not path.exists():
        abort(404)
    return send_file(path, mimetype="application/pdf")


@app.route("/api/pdfs")
def list_pdfs():
    """Return which PDF variants exist on disk."""
    output_dir = ROOT / "build" / "output"
    available = []
    for name in ("online", "print", "online-debug", "print-debug"):
        if (output_dir / f"banks-{name}.pdf").exists():
            available.append(name)
    return jsonify(available)


# ===== Helpers =============================================================

def _parse_frontmatter(text):
    if text.startswith("---"):
        parts = text.split("---", 2)
        if len(parts) >= 3:
            return yaml.safe_load(parts[1]) or {}
    return {}


def _extract_body(text):
    if text.startswith("---"):
        parts = text.split("---", 2)
        if len(parts) >= 3:
            return parts[2].strip()
    return text


_IMG_RE = re.compile(r"!\[([^\]]*)\]\(([^)]+)\)")

def _extract_images(body):
    """Return list of {src, caption} for images found in markdown body."""
    return [{"src": m.group(2), "caption": m.group(1)} for m in _IMG_RE.finditer(body)]


def serialize_layout(data):
    """Serialize layout dict to clean YAML matching the project's format."""
    lines = [
        "# layout.yaml -- Grid-based article placement",
        "",
        "grid:",
        f"  rows: {data['grid']['rows']}",
        f"  columns: {data['grid']['columns']}",
        f"  gutter: {data['grid']['gutter']}",
        f"  text_gutter: {data['grid']['text_gutter']}",
        "",
        "articles:",
    ]

    for art in data.get("articles", []):
        lines.append(f"  - slug: {art['slug']}")
        if art.get("column_width"):
            lines.append(f"    column_width: {art['column_width']}")
        if art.get("full_width_header"):
            lines.append("    full_width_header: true")
        if art.get("full_width_footer"):
            lines.append("    full_width_footer: true")
        if art.get("column_separator"):
            lines.append("    column_separator: true")
        if art.get("show_border"):
            lines.append("    show_border: true")
        if art.get("column_gap"):
            lines.append(f"    column_gap: {art['column_gap']}")

        # Article-level inline images
        inline_imgs = art.get("images", [])
        if inline_imgs:
            lines.append("    images:")
            for img in inline_imgs:
                lines.append(f"      - src: {img['src']}")
                if img.get("caption"):
                    cap = str(img["caption"]).replace('"', '\\"')
                    lines.append(f'        caption: "{cap}"')
                if img.get("border") is not None and img["border"] != 1:
                    lines.append(f"        border: {img['border']}")
                if img.get("scale") is not None and img["scale"] != 100:
                    lines.append(f"        scale: {img['scale']}")

        lines.append("    placements:")
        for pl in art.get("placements", []):
            lines.append(f"      - page: {pl['page']}")
            cell_list = pl.get("cells", []) or []
            if cell_list:
                lines.append("        cells:")
                for cr in cell_list:
                    lines.append(f"          - {json.dumps(cr)}")
            else:
                lines.append("        cells: []")
            # Only grid images remain in placements
            grid_imgs = [img for img in pl.get("images", []) if img.get("mode") == "grid"]
            if grid_imgs:
                lines.append("        images:")
                for img in grid_imgs:
                    lines.append(f"          - src: {img['src']}")
                    lines.append(f"            mode: grid")
                    if img.get("cells"):
                        lines.append("            cells:")
                        for icr in img["cells"]:
                            lines.append(f"              - {json.dumps(icr)}")
                    if img.get("caption"):
                        cap = str(img["caption"]).replace('"', '\\"')
                        lines.append(f'            caption: "{cap}"')
                    if img.get("x-alignment") and img.get("x-alignment") != "center":
                        lines.append(f"            x-alignment: {img['x-alignment']}")
                    if img.get("y-alignment") and img.get("y-alignment") != "center":
                        lines.append(f"            y-alignment: {img['y-alignment']}")
                    if img.get("border") is not None and img["border"] != 1:
                        lines.append(f"            border: {img['border']}")
        lines.append("")

    return "\n".join(lines) + "\n"


# ===== Entry point =========================================================

if __name__ == "__main__":
    print(f"  Project root: {ROOT}")
    print(f"  Open http://localhost:3000 in your browser")
    app.run(debug=True, port=3000)
