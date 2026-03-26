"""
Banks of the Boneyard - Layout Editor UI
Flask server providing a visual grid editor and article management.
"""
import json
import subprocess
import threading
from pathlib import Path

import yaml
from flask import Flask, render_template, jsonify, request, send_file, abort

ROOT = Path(__file__).resolve().parent.parent
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

@app.route("/api/layout")
def get_layout():
    with open(ROOT / "layout.yaml") as f:
        return jsonify(yaml.safe_load(f))


@app.route("/api/layout", methods=["PUT"])
def put_layout():
    data = request.json
    text = serialize_layout(data)
    (ROOT / "layout.yaml").write_text(text)
    return jsonify({"ok": True})


# ===== Config API ==========================================================

@app.route("/api/config")
def get_config():
    with open(ROOT / "config.yaml") as f:
        return jsonify(yaml.safe_load(f))


@app.route("/api/config", methods=["PUT"])
def put_config():
    data = request.json
    with open(ROOT / "config.yaml", "w") as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
    return jsonify({"ok": True})


# ===== Events API ==========================================================

@app.route("/api/events")
def get_events():
    with open(ROOT / "events.yaml") as f:
        return jsonify(yaml.safe_load(f))


@app.route("/api/events", methods=["PUT"])
def put_events():
    data = request.json
    with open(ROOT / "events.yaml", "w") as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
    return jsonify({"ok": True})


# ===== Articles API ========================================================

@app.route("/api/articles")
def list_articles():
    articles = []
    for md in sorted((ROOT / "articles").glob("*.md")):
        fm = _parse_frontmatter(md.read_text())
        articles.append({
            "slug": md.stem,
            "title": fm.get("title", md.stem),
            "authors": fm.get("authors", []),
        })
    return jsonify(articles)


@app.route("/api/articles/<slug>")
def get_article(slug):
    path = ROOT / "articles" / f"{slug}.md"
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
    path = ROOT / "articles" / f"{slug}.md"
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
    path = ROOT / "articles" / f"{slug}.md"
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
    path = ROOT / "articles" / f"{slug}.md"
    if not path.exists():
        abort(404)
    path.unlink()
    return jsonify({"ok": True})


# ===== LFTC API ============================================================

@app.route("/api/lftc")
def get_lftc():
    path = ROOT / "lftc.md"
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
    path = ROOT / "lftc.md"
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
    img_dir = ROOT / "articles" / "images"
    if not img_dir.exists():
        return jsonify([])
    exts = {".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp"}
    images = sorted(f.name for f in img_dir.iterdir() if f.suffix.lower() in exts)
    return jsonify(images)


@app.route("/api/images/<name>")
def get_image(name):
    path = ROOT / "articles" / "images" / name
    if not path.exists():
        abort(404)
    return send_file(path)


@app.route("/api/images", methods=["POST"])
def upload_image():
    if "file" not in request.files:
        return jsonify({"error": "No file"}), 400
    f = request.files["file"]
    dest = ROOT / "articles" / "images" / f.filename
    f.save(dest)
    return jsonify({"ok": True, "name": f.filename}), 201


# ===== Build API ===========================================================

@app.route("/api/build", methods=["POST"])
def start_build():
    mode = request.json.get("mode", "online")
    with build_lock:
        if build_state["running"]:
            return jsonify({"error": "Build already running"}), 409
        build_state.update(running=True, log="", return_code=None, mode=mode)

    def run():
        try:
            proc = subprocess.Popen(
                [str(ROOT / ".venv" / "bin" / "python"), str(ROOT / "build.py"), "--mode", mode],
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
    })


@app.route("/api/pdf/<mode>")
def get_pdf(mode):
    if mode not in ("online", "print"):
        abort(400)
    path = ROOT / "build" / "output" / f"banks-{mode}.pdf"
    if not path.exists():
        abort(404)
    return send_file(path, mimetype="application/pdf")


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
        if art.get("column_separator"):
            lines.append("    column_separator: true")
        if art.get("show_border"):
            lines.append("    show_border: true")
        if art.get("column_gap"):
            lines.append(f"    column_gap: {art['column_gap']}")
        lines.append("    placements:")
        for pl in art.get("placements", []):
            lines.append(f"      - page: {pl['page']}")
            lines.append("        cells:")
            for cr in pl.get("cells", []):
                lines.append(f"          - {json.dumps(cr)}")
            if pl.get("images"):
                lines.append("        images:")
                for img in pl["images"]:
                    lines.append(f"          - src: {img['src']}")
                    lines.append(f"            mode: {img.get('mode', 'grid')}")
                    if img.get("cells"):
                        lines.append("            cells:")
                        for icr in img["cells"]:
                            lines.append(f"              - {json.dumps(icr)}")
                    if img.get("caption"):
                        # Escape quotes in caption
                        cap = str(img["caption"]).replace('"', '\\"')
                        lines.append(f'            caption: "{cap}"')
                    if img.get("x-alignment") and img.get("x-alignment") != "center":
                        lines.append(f"            x-alignment: {img['x-alignment']}")
                    if img.get("y-alignment") and img.get("y-alignment") != "center":
                        lines.append(f"            y-alignment: {img['y-alignment']}")
                    if img.get("border") is not None and img["border"] != 1:
                        lines.append(f"            border: {img['border']}")
                    if img.get("scale") is not None and img["scale"] != 100:
                        lines.append(f"            scale: {img['scale']}")
        lines.append("")

    return "\n".join(lines) + "\n"


# ===== Entry point =========================================================

if __name__ == "__main__":
    print(f"  Project root: {ROOT}")
    print(f"  Open http://localhost:3000 in your browser")
    app.run(debug=True, port=3000)
