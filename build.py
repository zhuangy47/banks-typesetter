#!/usr/bin/env python3
"""Banks of the Boneyard Typesetter - Build Script

Ingests markdown articles, YAML config, blurbs, and images,
then outputs a formatted newspaper PDF using Typst.
"""

import argparse
import hashlib
import json
import logging
import os
import re
import subprocess
import sys
from pathlib import Path

import requests
import yaml

try:
    import qrcode
except ImportError:
    qrcode = None

ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "build"
ARTICLES_DIR = ROOT / "articles"
IMAGES_DIR = ARTICLES_DIR / "images"
BLURBS_DIR = ROOT / "blurbs"
LOGO_DIR = ROOT / "logo"

API_URL = "https://core.acm.illinois.edu/api/v1/organizations"


# ---------------------------------------------------------------------------
# Markdown → Typst conversion
# ---------------------------------------------------------------------------

def md_to_typst(text: str, mode: str,
                placed_images: set[str] | None = None,
                qr_map: dict[str, str] | None = None,
                image_widths: dict[str, int] | None = None,
                image_borders: dict[str, float] | None = None) -> str:
    """Convert markdown text to Typst markup.

    placed_images: set of image filenames that are positioned by the grid
    engine and should be removed from the article body.
    qr_map: url→QR code image path mapping (print mode).
    image_widths: image filename → width percentage for inline images.
    image_borders: image filename → border size in pt for inline images.
    """
    if placed_images is None:
        placed_images = set()
    if qr_map is None:
        qr_map = {}
    if image_widths is None:
        image_widths = {}
    if image_borders is None:
        image_borders = {}

    lines = text.split("\n")
    result_lines: list[str] = []

    for line in lines:
        line = _convert_line(line, mode, placed_images, qr_map, image_widths, image_borders)
        result_lines.append(line)

    result = "\n".join(result_lines)
    # Escape @ signs (Typst uses @ for references)
    # But don't escape inside #link() calls
    result = re.sub(r'@(?!["\s])', r'\\@', result)
    return result


def _convert_line(line: str, mode: str, placed_images: set[str],
                   qr_map: dict[str, str] | None = None,
                   image_widths: dict[str, int] | None = None,
                   image_borders: dict[str, float] | None = None) -> str:
    if image_widths is None:
        image_widths = {}
    if image_borders is None:
        image_borders = {}
    # --- images (must be processed first) ---
    # ![alt](src)  optionally followed by a caption line (handled separately)
    img_match = re.match(r'^!\[([^\]]*)\]\(([^)]+)\)\s*$', line)
    if img_match:
        alt = img_match.group(1)
        src = img_match.group(2)
        basename = os.path.basename(src)
        if basename in placed_images:
            return ""  # removed; placed by grid engine
        img_path = "/" + str((IMAGES_DIR / basename).relative_to(ROOT))
        width_str = f"{image_widths.get(basename, 100)}%"
        border_pt = image_borders.get(basename, 1)
        img = f'image("{img_path}", width: {width_str})'
        if border_pt > 0:
            # Pad the outer container so the border stroke (centered on the
            # box edge) is not clipped at column boundaries.
            border_str = f"{border_pt}pt"
            img = f'pad({border_str}, box(stroke: {border_str}, {img}))'
        figure = f'#align(center, {img})'
        if alt:
            figure += f'\n#v(2pt)\n#align(center, text(size: 7pt, style: "italic")[{alt}])'
        return figure

    # --- italic caption lines like *caption text* ---
    caption_match = re.match(r'^\*([^*]+)\*\s*$', line)
    if caption_match and not line.startswith('**'):
        # This is a standalone italic line (image caption), keep as italic
        return f'_{caption_match.group(1)}_'

    # --- headings ---
    heading_match = re.match(r'^(#{1,6})\s+(.+)$', line)
    if heading_match:
        level = len(heading_match.group(1))
        title = heading_match.group(2)
        title = _convert_inline(title, mode)
        return f'{"=" * level} {title}'

    # --- ordered list ---
    ol_match = re.match(r'^(\d+)\.\s+(.+)$', line)
    if ol_match:
        content = _convert_inline(ol_match.group(2), mode)
        return f'+ {content}'

    # --- unordered list (unchanged prefix, just convert inline) ---
    ul_match = re.match(r'^([*-])\s+(.+)$', line)
    if ul_match:
        content = _convert_inline(ul_match.group(2), mode)
        return f'- {content}'

    # --- br tags ---
    line = re.sub(r'<br\s*/?>', '#v(0.5em)', line)

    # --- markdown comment markers ---
    # <!-- break --> → vertical space equal to one line height
    line = re.sub(r'<!--\s*break\s*-->', '#v(1em)', line)
    # <!-- vspace 1.5em --> → configurable vertical space (default 1em)
    line = re.sub(r'<!--\s*vspace\s+([\d.]+\s*\w+)\s*-->', r'#v(\1)', line)
    line = re.sub(r'<!--\s*vspace\s*-->', '#v(1em)', line)
    # <!-- colbreak --> → force column break
    line = re.sub(r'<!--\s*colbreak\s*-->', '#colbreak()', line)

    # --- inline conversions ---
    line = _convert_inline(line, mode, qr_map)

    return line


def _convert_inline(text: str, mode: str, qr_map: dict[str, str] | None = None) -> str:
    if qr_map is None:
        qr_map = {}

    # Processing order: bold-italic → bold → italic → links

    # bold-italic ***text*** or ___text___
    text = re.sub(r'\*\*\*(.+?)\*\*\*', r'*_\1_*', text)

    # bold **text**
    text = re.sub(r'\*\*(.+?)\*\*', r'*\1*', text)

    # italic *text* — but not inside already-converted bold markers
    # Use negative lookbehind/lookahead to avoid matching bold markers
    text = re.sub(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)', r'_\1_', text)

    # links [text](url)
    def replace_link(m):
        link_text = m.group(1)
        url = m.group(2)
        if mode == "online":
            return f'#link("{url}")[{link_text}]'
        else:
            # Print mode: show link text, then QR code block below with URL caption
            qr_path = qr_map.get(url, "")
            if qr_path:
                return (
                    f'{link_text}\n'
                    f'#align(center)[#box(image("/build/{qr_path}", height: 5em)) \\ #text(size: 5pt)[{url}]]'
                )
            else:
                return f'{link_text} #text(size: 5pt)[({url})]'

    text = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', replace_link, text)

    return text


# ---------------------------------------------------------------------------
# Layout validation
# ---------------------------------------------------------------------------

def validate_layout(layout: dict, article_files: set[str]) -> list[str]:
    """Validate layout.yaml. Returns list of error messages."""
    errors = []
    grid = layout["grid"]
    max_cols = grid["columns"]
    max_rows = grid["rows"]

    # Per-page cell ownership tracking: maps (page, col, row) → owner label
    # Used to detect any cell shared by two articles or two images
    cell_owners: dict[tuple[int, int, int], str] = {}

    def _claim_cells(page: int, cells: set[tuple[int, int]], owner: str):
        """Register cells for an owner. Appends to errors on conflict."""
        for c, r in cells:
            key = (page, c, r)
            if key in cell_owners:
                errors.append(
                    f"Page {page}: cell ({c},{r}) claimed by both "
                    f"'{cell_owners[key]}' and '{owner}'"
                )
            else:
                cell_owners[key] = owner

    for article in layout["articles"]:
        slug = article["slug"]

        # Check article file exists
        if slug not in article_files:
            errors.append(f"Layout references article '{slug}' but no .md file found")

        # Validate article-level inline images
        for img in article.get("images", []):
            img_src = img.get("src", "")
            img_file = IMAGES_DIR / os.path.basename(img_src)
            if not img_file.exists():
                errors.append(
                    f"Article '{slug}' inline image '{img_src}': "
                    f"file not found at {img_file}"
                )
            border = img.get("border", 1)
            if not isinstance(border, (int, float)) or border < 0:
                errors.append(
                    f"Article '{slug}' inline image '{img_src}': "
                    f"border must be a non-negative number (got {border!r})"
                )
            scale = img.get("scale", 100)
            if not (1 <= scale <= 100):
                errors.append(
                    f"Article '{slug}' inline image '{img_src}': "
                    f"scale {scale} must be between 1 and 100"
                )
            if "cells" in img:
                errors.append(
                    f"Article '{slug}' inline image '{img_src}': "
                    f"inline images must not have 'cells'"
                )

        col_width = article.get("column_width", 1)

        for placement in article["placements"]:
            page = placement["page"]
            article_cell_set: set[tuple[int, int]] = set()

            for cell_spec in placement.get("cells") or []:
                cells = _expand_cells(cell_spec)
                for c, r in cells:
                    if c < 0 or c >= max_cols or r < 0 or r >= max_rows:
                        errors.append(
                            f"Article '{slug}' cell ({c},{r}) out of bounds "
                            f"(grid is {max_cols}x{max_rows})"
                        )
                    article_cell_set.add((c, r))

            # Check contiguity via flood fill
            if article_cell_set and not _is_contiguous(article_cell_set):
                errors.append(f"Article '{slug}' page {page}: cells are not contiguous")

            # Check column_width divides article width
            if article_cell_set:
                cols_used = set(c for c, r in article_cell_set)
                width = max(cols_used) - min(cols_used) + 1
                if width % col_width != 0:
                    errors.append(
                        f"Article '{slug}': column_width {col_width} does not "
                        f"divide article width {width}"
                    )

            for img in placement.get("images", []):
                img_src = img.get("src", "")
                img_file = IMAGES_DIR / os.path.basename(img_src)
                if not img_file.exists():
                    errors.append(
                        f"Article '{slug}' image '{img_src}': "
                        f"file not found at {img_file}"
                    )

                img_mode = img.get("mode", "grid")

                # Validate border property
                border = img.get("border", 1)
                if not isinstance(border, (int, float)) or border < 0:
                    errors.append(
                        f"Article '{slug}' image '{img_src}': "
                        f"border must be a non-negative number (got {border!r})"
                    )

                if img_mode == "grid":
                    # Validate alignment properties
                    valid_alignments = {"left", "center", "right"}
                    for axis in ("x-alignment", "y-alignment"):
                        val = img.get(axis, "center")
                        if val not in valid_alignments:
                            errors.append(
                                f"Article '{slug}' image '{img_src}': "
                                f"{axis} '{val}' must be one of: "
                                f"left, center, right"
                            )

                    if "cells" not in img:
                        errors.append(
                            f"Article '{slug}' image '{img['src']}': "
                            f"grid images must have 'cells'"
                        )
                        continue

                    img_cells: set[tuple[int, int]] = set()
                    for cell_spec in img["cells"]:
                        img_cells.update(_expand_cells(cell_spec))

                    # Image cells must be rectangular
                    if img_cells and not _is_rectangular(img_cells):
                        errors.append(
                            f"Article '{slug}' image '{img['src']}': "
                            f"cells are not rectangular"
                        )

                    # Image cells must be within bounds
                    for c, r in img_cells:
                        if c < 0 or c >= max_cols or r < 0 or r >= max_rows:
                            errors.append(
                                f"Article '{slug}' image '{img['src']}' "
                                f"cell ({c},{r}) out of bounds"
                            )

                    # Claim image cells (detect image-image overlaps)
                    _claim_cells(page, img_cells,
                                 f"image:{slug}/{img['src']}")

                else:
                    errors.append(
                        f"Article '{slug}' image '{img['src']}': "
                        f"placement images must be mode 'grid', "
                        f"got '{img_mode}' (inline images belong "
                        f"at the article level)"
                    )

            # Claim the article's text cells (minus its own images)
            # to detect overlaps with other articles/images.
            # An article's own images may share cells with its text area.
            own_image_cells: set[tuple[int, int]] = set()
            for img in placement.get("images", []):
                if img.get("mode", "grid") == "grid" and "cells" in img:
                    for cell_spec in img["cells"]:
                        own_image_cells.update(_expand_cells(cell_spec))
            text_cells = article_cell_set - own_image_cells
            _claim_cells(page, text_cells, f"article:{slug}")

    return errors


def _expand_cells(cell_spec) -> set[tuple[int, int]]:
    """Expand a cell spec into a set of (col, row) tuples.

    Input format is [row, col] or [[row_start, col_start], [row_end, col_end]].
    Output tuples are (col, row) for internal consistency with grid math.
    """
    if isinstance(cell_spec[0], int):
        # Single cell: [row, col] → (col, row)
        return {(cell_spec[1], cell_spec[0])}
    else:
        # Rectangle: [[row_start, col_start], [row_end, col_end]]
        r0, c0 = cell_spec[0]
        r1, c1 = cell_spec[1]
        return {(c, r) for c in range(c0, c1 + 1) for r in range(r0, r1 + 1)}


def _is_contiguous(cells: set[tuple[int, int]]) -> bool:
    """Check if cells form a contiguous region via flood fill."""
    if not cells:
        return True
    start = next(iter(cells))
    visited: set[tuple[int, int]] = set()
    stack = [start]
    while stack:
        c, r = stack.pop()
        if (c, r) in visited or (c, r) not in cells:
            continue
        visited.add((c, r))
        for dc, dr in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            stack.append((c + dc, r + dr))
    return visited == cells


def compute_text_columns(cell_specs, column_width: int) -> list[dict]:
    """Compute text columns for a cell layout.

    Groups grid columns into text-column-width chunks.  For each chunk,
    finds the row range where ALL grid columns in the chunk are occupied.

    Returns a list of column dicts sorted left-to-right:
        [{"col_start": c0, "col_end": c1, "row_start": r0, "row_end": r1}, ...]

    Returns an empty list only when cell_specs is empty.
    """
    all_cells: set[tuple[int, int]] = set()
    for spec in cell_specs:
        all_cells.update(_expand_cells(spec))

    if not all_cells:
        return []

    min_col = min(c for c, _ in all_cells)
    max_col = max(c for c, _ in all_cells)

    text_columns: list[dict] = []
    col = min_col
    while col + column_width - 1 <= max_col:
        grid_cols = range(col, col + column_width)
        # Find rows where ALL grid columns in this group are present
        row_sets = [{r for c, r in all_cells if c == gc} for gc in grid_cols]
        common_rows = row_sets[0]
        for rs in row_sets[1:]:
            common_rows &= rs

        if common_rows:
            sorted_rows = sorted(common_rows)
            text_columns.append({
                "col_start": col,
                "col_end": col + column_width - 1,
                "row_start": sorted_rows[0],
                "row_end": sorted_rows[-1],
            })
        col += column_width

    return text_columns


log = logging.getLogger("banks-build")


def _is_rectangular(cells: set[tuple[int, int]]) -> bool:
    """Check if cells form a rectangle."""
    if not cells:
        return True
    cols = set(c for c, r in cells)
    rows = set(r for c, r in cells)
    return len(cells) == len(cols) * len(rows)


# ---------------------------------------------------------------------------
# API + blurbs
# ---------------------------------------------------------------------------

def fetch_api_orgs() -> list[dict]:
    """Fetch organizations from ACM core API."""
    print("Fetching organizations from API...")
    resp = requests.get(API_URL, timeout=15)
    resp.raise_for_status()
    return resp.json()


def load_blurbs() -> dict[str, dict]:
    """Load all blurb YAML files."""
    blurbs = {}
    for f in BLURBS_DIR.glob("*.yaml"):
        slug = f.stem
        with open(f) as fh:
            blurbs[slug] = yaml.safe_load(fh)
    return blurbs


def normalize_org_slug(name: str, org_type: str) -> str:
    """Convert API org name to slug matching blurb filenames."""
    slug_map = {
        "ACM": "acm",
        "SIGAIDA": "sigaida",
        "SIGARCH": "sigarch",
        "SIGCHI": "sigchi",
        "SIGecom": "sigecom",
        "SIGGRAPH": "siggraph",
        "SIGma": "sigma",
        "SIGMobile": "sigmobile",
        "SIGMusic": "sigmusic",
        "SIGNLL": "signll",
        "SIGPLAN": "sigplan",
        "SIGPolicy": "sigpolicy",
        "SIGPwny": "sigpwny",
        "SIGQuantum": "sigquantum",
        "SIGRobotics": "sigrobotics",
        "SIGtricity": "sigtricity",
        "GameBuilders": "gamebuilders",
        "GLUG": "glug",
        "HackIllinois": "hackillinois",
        "ICPC": "icpc",
        "Reflections | Projections": "reflections_projections",
        "Agent Fan Club": "agent_fan_club",
        "Infrastructure Committee": "infrastructure_committee",
        "Social Committee": "social_committee",
        "Mentorship Committee": "mentorship_committee",
        "Academic Committee": "academic_committee",
        "Corporate Committee": "corporate_committee",
        "Marketing Committee": "marketing_committee",
    }
    if name in slug_map:
        return slug_map[name]
    # Fallback: lowercase, replace spaces/special chars
    slug = re.sub(r'[^a-z0-9]+', '_', name.lower()).strip('_')
    if org_type == "committee":
        slug += "_committee"
    return slug


def merge_org_data(api_orgs: list[dict], blurbs: dict[str, dict],
                   directory_order: list[str]) -> list[dict]:
    """Merge API org data with blurb data, ordered per config."""
    org_by_slug: dict[str, dict] = {}
    for org in api_orgs:
        slug = normalize_org_slug(org["name"], org.get("type", ""))
        # Find logo file (check multiple extensions)
        logo_path = ""
        for ext in ("png", "jpg", "jpeg", "svg"):
            candidate = LOGO_DIR / f"{slug}.{ext}"
            if candidate.exists():
                logo_path = f"/logo/{slug}.{ext}"
                break

        org_by_slug[slug] = {
            "slug": slug,
            "name": org["name"],
            "type": org.get("type", ""),
            "description": org.get("description", ""),
            "website": org.get("website", ""),
            "email": org.get("email", ""),
            "logo": logo_path,
            "leads": [
                {"name": l.get("name", l.get("username", "")), "title": l.get("title", "")}
                for l in org.get("leads", [])
            ],
            "links": [
                {"type": l.get("type", ""), "url": l.get("url", "")}
                for l in org.get("links", [])
            ],
        }

    # Merge blurb data
    for slug, blurb_data in blurbs.items():
        if slug in org_by_slug:
            org_by_slug[slug]["meeting_times"] = blurb_data.get("meeting_times", [])
            org_by_slug[slug]["blurb"] = blurb_data.get("blurb", "")
        else:
            print(f"  Warning: blurb '{slug}' has no matching API org")

    # Check all directory_order slugs map to API orgs
    errors = []
    for slug in directory_order:
        if slug not in org_by_slug:
            errors.append(f"directory_order slug '{slug}' not found in API orgs")
    if errors:
        for e in errors:
            print(f"  ERROR: {e}")
        # Non-fatal: continue with what we have

    # Warn about API orgs without blurbs
    for slug in org_by_slug:
        if slug not in blurbs:
            print(f"  Warning: API org '{slug}' has no blurb file")

    # Order per directory_order
    ordered = []
    for slug in directory_order:
        if slug in org_by_slug:
            ordered.append(org_by_slug[slug])

    return ordered


# ---------------------------------------------------------------------------
# QR code generation
# ---------------------------------------------------------------------------

def generate_qr_codes(urls: list[str], qr_dir: Path) -> dict[str, str]:
    """Generate QR code PNGs for URLs. Returns url→relative path mapping."""
    if qrcode is None:
        print("  Warning: qrcode package not installed, skipping QR generation")
        return {}

    qr_dir.mkdir(parents=True, exist_ok=True)
    url_to_path: dict[str, str] = {}

    for url in urls:
        url_hash = hashlib.md5(url.encode()).hexdigest()[:12]
        filename = f"{url_hash}.png"
        filepath = qr_dir / filename
        if not filepath.exists():
            img = qrcode.make(url)
            img.save(str(filepath))
        url_to_path[url] = f"qrcodes/{filename}"

    return url_to_path


def extract_urls_from_markdown(text: str) -> list[str]:
    """Extract all URLs from markdown link syntax."""
    return re.findall(r'\[([^\]]+)\]\(([^)]+)\)', text)


# ---------------------------------------------------------------------------
# Article processing
# ---------------------------------------------------------------------------

def load_article(path: Path) -> dict:
    """Load article markdown, parse frontmatter."""
    text = path.read_text()
    # Parse YAML frontmatter
    fm_match = re.match(r'^---\s*\n(.*?)\n---\s*\n', text, re.DOTALL)
    if fm_match:
        frontmatter = yaml.safe_load(fm_match.group(1)) or {}
        body = text[fm_match.end():]
    else:
        frontmatter = {}
        body = text
    return {
        "slug": path.stem,
        "title": frontmatter.get("title", path.stem),
        "authors": frontmatter.get("authors", []),
        "author": frontmatter.get("author", ""),
        "body": body.strip(),
    }


def get_inline_image_scales(layout: dict, slug: str) -> dict[str, int]:
    """Get scale percentages for inline images from layout config."""
    scales: dict[str, int] = {}
    for article in layout["articles"]:
        if article["slug"] == slug:
            for img in article.get("images", []):
                scales[os.path.basename(img["src"])] = img.get("scale", 100)
    return scales


def get_inline_image_borders(layout: dict, slug: str) -> dict[str, float]:
    """Get border sizes (pt) for inline images from layout config."""
    borders: dict[str, float] = {}
    for article in layout["articles"]:
        if article["slug"] == slug:
            for img in article.get("images", []):
                borders[os.path.basename(img["src"])] = img.get("border", 1)
    return borders


def get_placed_images(layout: dict, slug: str) -> set[str]:
    """Get set of image filenames placed by grid engine for an article."""
    placed = set()
    for article in layout["articles"]:
        if article["slug"] == slug:
            for placement in article["placements"]:
                for img in placement.get("images", []):
                    if img.get("mode", "grid") == "grid":
                        placed.add(os.path.basename(img["src"]))
    return placed


def extract_image_captions(markdown_body: str) -> dict[str, str]:
    """Extract alt text from markdown images, keyed by basename."""
    captions = {}
    for match in re.finditer(r'!\[([^\]]*)\]\(([^)]+)\)', markdown_body):
        alt = match.group(1).strip()
        basename = os.path.basename(match.group(2))
        if alt:
            captions[basename] = alt
    return captions


def merge_image_captions(layout: dict, articles: dict[str, dict]):
    """Merge auto-extracted captions into layout image entries.

    For each grid-mode image, if no explicit 'caption' is set in layout.yaml,
    use the alt text from the markdown. Modifies layout in place.
    """
    for article in layout["articles"]:
        slug = article["slug"]
        art_data = articles.get(slug)
        if not art_data:
            continue
        md_captions = extract_image_captions(art_data["body"])
        for placement in article["placements"]:
            for img in placement.get("images", []):
                if img.get("mode", "grid") != "grid":
                    continue
                basename = os.path.basename(img["src"])
                # Explicit caption in layout.yaml takes priority
                if "caption" not in img and basename in md_captions:
                    img["caption"] = md_captions[basename]


# ---------------------------------------------------------------------------
# TOC building
# ---------------------------------------------------------------------------

def build_toc(layout: dict, articles: dict[str, dict]) -> list[dict]:
    """Build table of contents from layout metadata."""
    toc = []
    seen = set()
    # Sort articles by their first page appearance
    sorted_articles = sorted(
        layout["articles"],
        key=lambda a: a["placements"][0]["page"]
    )
    for article in sorted_articles:
        slug = article["slug"]
        if slug in seen:
            continue
        seen.add(slug)
        if slug in articles:
            toc.append({
                "slug": slug,
                "title": articles[slug]["title"],
                "authors": articles[slug]["authors"],
                "page": article["placements"][0]["page"],
            })
    return toc


# ---------------------------------------------------------------------------
# Main build
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Banks of the Boneyard Typesetter")
    parser.add_argument(
        "--mode", choices=["online", "print", "both"], default="both",
        help="Render mode (default: both)"
    )
    parser.add_argument(
        "--strict", action="store_true",
        help="Treat content overflow warnings as errors (exit non-zero)"
    )
    parser.add_argument(
        "--debug", action="store_true",
        help="Enable debug mode (show grid lines and bounding boxes)"
    )
    args = parser.parse_args()

    # Set up overflow warning logger (writes to stderr)
    logging.basicConfig(
        format="%(levelname)s: %(message)s",
        level=logging.WARNING,
        stream=sys.stderr,
    )

    modes = ["online", "print"] if args.mode == "both" else [args.mode]

    # 1. Load configs
    print("Loading configuration...")
    with open(ROOT / "config.yaml") as f:
        config = yaml.safe_load(f)
    with open(ROOT / "events.yaml") as f:
        events_data = yaml.safe_load(f)

    # Load horoscope if present
    horoscope_path = ROOT / "horoscope.yaml"
    horoscope = None
    if horoscope_path.exists():
        with open(horoscope_path) as f:
            horoscope = yaml.safe_load(f)

    # 3. Fetch API data
    try:
        api_orgs = fetch_api_orgs()
    except Exception as e:
        print(f"  Warning: Could not fetch API data: {e}")
        print("  Continuing with empty org data...")
        api_orgs = []

    blurbs = load_blurbs()
    directory = merge_org_data(api_orgs, blurbs, config["directory_order"])

    # 4. Load articles
    print("Loading articles...")
    articles: dict[str, dict] = {}
    for md_file in ARTICLES_DIR.glob("*.md"):
        article = load_article(md_file)
        articles[article["slug"]] = article

    # 5. Load LFTC
    print("Loading letter from the chair...")
    lftc = load_article(ROOT / "lftc.md")

    article_files = {f.stem for f in ARTICLES_DIR.glob("*.md")}

    post_overflow_total = 0
    for mode in modes:
        # Load mode-specific layout, falling back to layout.yaml
        layout_path = ROOT / f"layout-{mode}.yaml"
        if not layout_path.exists():
            layout_path = ROOT / "layout.yaml"
        print(f"Loading layout from {layout_path.name}...")
        with open(layout_path) as f:
            layout = yaml.safe_load(f)

        # Sort each article's placements by page number
        for article in layout["articles"]:
            article["placements"].sort(key=lambda p: p["page"])

        # Validate layout
        print("Validating layout...")
        layout_errors = validate_layout(layout, article_files)
        if layout_errors:
            for err in layout_errors:
                print(f"  ERROR: {err}")
            sys.exit(1)
        print("  Layout valid.")

        # Compute text columns for non-rectangular placements
        for article in layout["articles"]:
            col_width = article.get("column_width", 1)
            for placement in article["placements"]:
                if not placement.get("cells"):
                    continue
                text_cols = compute_text_columns(placement["cells"], col_width)
                if len(text_cols) > 1 and not all(
                    tc["row_start"] == text_cols[0]["row_start"]
                    and tc["row_end"] == text_cols[0]["row_end"]
                    for tc in text_cols[1:]
                ):
                    placement["text_columns"] = text_cols

        # Build TOC from this mode's layout
        toc = build_toc(layout, articles)
        print(f"\n{'=' * 40}")
        print(f"Building {mode} mode...")
        print(f"{'=' * 40}")

        # Create build directories
        build_articles = BUILD / "articles"
        build_articles.mkdir(parents=True, exist_ok=True)
        (BUILD / "output").mkdir(parents=True, exist_ok=True)

        # 7. Generate QR codes (print mode only) — must happen before conversion
        qr_map: dict[str, str] = {}
        if mode == "print":
            print("Generating QR codes...")
            all_urls: list[str] = []
            for slug, article in articles.items():
                for _, url in extract_urls_from_markdown(article["body"]):
                    all_urls.append(url)
            for _, url in extract_urls_from_markdown(lftc["body"]):
                all_urls.append(url)
            qr_dir = BUILD / "qrcodes"
            qr_map = generate_qr_codes(sorted(set(all_urls)), qr_dir)
            print(f"  Generated {len(qr_map)} QR codes")

        # 8. Convert articles to .typ
        print("Converting articles to Typst...")
        for slug, article in articles.items():
            placed = get_placed_images(layout, slug)
            img_widths = get_inline_image_scales(layout, slug)
            img_borders = get_inline_image_borders(layout, slug)
            typ_content = md_to_typst(article["body"], mode, placed, qr_map, img_widths, img_borders)

            (build_articles / f"{slug}.typ").write_text(typ_content)

        # 9. Convert LFTC
        lftc_typ = md_to_typst(lftc["body"], mode, qr_map=qr_map)
        (BUILD / "lftc.typ").write_text(lftc_typ)

        # 10. Merge image captions from markdown alt text into layout
        merge_image_captions(layout, articles)

        # 11. Write data.json
        print("Writing data.json...")
        data = {
            "config": config,
            "events": events_data.get("events", []),
            "toc": toc,
            "directory": directory,
            "layout": layout,
            "lftc": {
                "author": lftc["author"],
                "body_file": "lftc.typ",
            },
            "articles": {
                slug: {
                    "title": a["title"],
                    "authors": a["authors"],
                    "typ_file": f"articles/{slug}.typ",
                }
                for slug, a in articles.items()
            },
            "qr_codes": qr_map,
            "horoscope": horoscope,
            "mode": mode,
        }

        (BUILD / "data.json").write_text(json.dumps(data, indent=2))

        # 12. Compile with Typst
        print("Compiling with Typst...")
        suffix = f"{mode}-debug" if args.debug else mode
        output_file = BUILD / "output" / f"banks-{suffix}.pdf"
        debug_str = "true" if args.debug else "false"
        cmd = [
            "typst", "compile",
            str(ROOT / "typst" / "main.typ"),
            str(output_file),
            "--root", str(ROOT),
            "--input", f"mode={mode}",
            "--input", f"debug={debug_str}",
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"  Typst compilation failed!")
            print(f"  stdout: {result.stdout}")
            print(f"  stderr: {result.stderr}")
            sys.exit(1)
        print(f"  Output: {output_file}")

        # 13. Check for content overflow via Typst metadata query
        post_overflows = _check_typst_overflow(mode)
        post_overflow_total += post_overflows
        if post_overflows:
            print(f"  {post_overflows} article(s) overflow in {mode} mode (see warnings above).")

    if args.strict and post_overflow_total > 0:
        log.error(
            "Build failed: %d article(s) overflow (--strict mode)",
            post_overflow_total,
        )
        sys.exit(1)

    print("\nBuild complete!")


def _check_typst_overflow(mode: str) -> int:
    """Query Typst for <overflow> metadata labels emitted by the grid engine.

    Returns the number of articles with overflow.
    """
    cmd = [
        "typst", "query",
        str(ROOT / "typst" / "main.typ"),
        "<overflow>",
        "--root", str(ROOT),
        "--input", f"mode={mode}",
        "--field", "value",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        return 0

    try:
        overflows = json.loads(result.stdout)
    except (json.JSONDecodeError, ValueError):
        return 0

    count = 0
    if overflows:
        seen: set[str] = set()
        for entry in overflows:
            slug = entry.get("slug", "?")
            if slug in seen:
                continue
            seen.add(slug)
            allocated = entry.get("allocated", "?")
            needed = entry.get("needed", "?")
            log.warning(
                "[%s] Article '%s' content overflows "
                "(needs %s, allocated %s)",
                mode, slug, needed, allocated,
            )
            count += 1
    return count


if __name__ == "__main__":
    main()
