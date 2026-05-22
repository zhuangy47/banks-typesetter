# Banks of the Boneyard -- Architecture & Developer Guide

This document explains, in full detail, how every piece of the Banks of the Boneyard typesetting system works. After reading it, a developer should be able to modify any part of the pipeline -- from YAML configuration to Typst rendering -- with confidence.

---

## Table of Contents

1. [High-Level Overview](#1-high-level-overview)
2. [Repository Structure](#2-repository-structure)
3. [Prerequisites & Setup](#3-prerequisites--setup)
4. [Configuration Files](#4-configuration-files)
   - 4.1 [config.yaml](#41-configyaml)
   - 4.2 [layout.yaml](#42-layoutyaml)
   - 4.3 [events.yaml](#43-eventsyaml)
   - 4.4 [lftc.md](#44-lftcmd)
5. [Content Authoring](#5-content-authoring)
   - 5.1 [Article Markdown Format](#51-article-markdown-format)
   - 5.2 [Organization Blurbs](#52-organization-blurbs)
   - 5.3 [Logos](#53-logos)
6. [The Build Pipeline (build.py)](#6-the-build-pipeline-buildpy)
   - 6.1 [Step 1 -- Load Configuration](#61-step-1----load-configuration)
   - 6.2 [Step 2 -- Validate Layout](#62-step-2----validate-layout)
   - 6.3 [Step 3 -- Compute Non-Rectangular Text Columns](#63-step-3----compute-non-rectangular-text-columns)
   - 6.4 [Step 4 -- Fetch Organization Data](#64-step-4----fetch-organization-data)
   - 6.5 [Step 5 -- Load Articles & LFTC](#65-step-5----load-articles--lftc)
   - 6.6 [Step 6 -- Build Table of Contents](#66-step-6----build-table-of-contents)
   - 6.7 [Step 7 -- Generate QR Codes (Print Mode)](#67-step-7----generate-qr-codes-print-mode)
   - 6.8 [Step 8 -- Markdown-to-Typst Conversion](#68-step-8----markdown-to-typst-conversion)
   - 6.9 [Step 9 -- Multi-Page Articles](#69-step-9----multi-page-articles)
   - 6.10 [Step 10 -- Merge Image Captions](#610-step-10----merge-image-captions)
   - 6.11 [Step 11 -- Write data.json](#611-step-11----write-datajson)
   - 6.12 [Step 12 -- Compile with Typst](#612-step-12----compile-with-typst)
   - 6.13 [Step 13 -- Post-Compilation Overflow Check](#613-step-13----post-compilation-overflow-check)
7. [The Layout System In Depth](#7-the-layout-system-in-depth)
   - 7.1 [Grid Coordinate System](#71-grid-coordinate-system)
   - 7.2 [Cell Specification Syntax](#72-cell-specification-syntax)
   - 7.3 [Column Width & Text Columns](#73-column-width--text-columns)
   - 7.4 [Image Placement Modes](#74-image-placement-modes)
   - 7.5 [Non-Rectangular Layouts](#75-non-rectangular-layouts)
   - 7.6 [Layout Validation Rules](#76-layout-validation-rules)
8. [The Typst Template System](#8-the-typst-template-system)
   - 8.1 [main.typ -- Entry Point](#81-maintyp----entry-point)
   - 8.2 [theme.typ -- Design Tokens](#82-themtyp----design-tokens)
   - 8.3 [grid-engine.typ -- Layout Math](#83-grid-enginetyp----layout-math)
   - 8.4 [title-page.typ -- Title Page](#84-title-pagetyp----title-page)
   - 8.5 [article-page.typ -- Article Rendering](#85-article-pagetyp----article-rendering)
   - 8.6 [directory.typ -- Organization Directory](#86-directorytyp----organization-directory)
   - 8.7 [horoscope.typ -- Optional Horoscope Section](#87-horoscopetyp----optional-horoscope-section)
9. [Overflow Detection & Handling](#9-overflow-detection--handling)
10. [Online vs. Print Mode](#10-online-vs-print-mode)
11. [The Web UI](#11-the-web-ui)
12. [Build Artifacts](#12-build-artifacts)
13. [Common Tasks & Recipes](#13-common-tasks--recipes)

---

## 1. High-Level Overview

Banks of the Boneyard is a two-stage typesetting pipeline:

```
                         ┌─────────────────────┐
  config.yaml ──────────>│                     │
  layout-*.yaml ────────>│                     │──> build/data.json
  events.yaml ──────────>│     build.py        │──> build/articles/*.typ
  articles/*.md ────────>│   (Python stage)    │──> build/lftc.typ
  lftc.md ──────────────>│                     │──> build/qrcodes/*.png
  blurbs/*.yaml ────────>│                     │
  ACM Core API ────────->│                     │
                         └─────────┬───────────┘
                                   │
                                   v
                         ┌─────────────────────┐
  typst/main.typ ──────->│                     │
  typst/lib/*.typ ──────>│     Typst compiler  │──> build/output/banks-online.pdf
  build/data.json ──────>│                     │──> build/output/banks-print.pdf
  build/articles/*.typ ─>│                     │
                         └─────────────────────┘
```

**Stage 1 (Python)** handles all data ingestion: it loads YAML configuration, fetches live organization data from the ACM Core API, validates layout constraints, converts Markdown articles to Typst markup, generates QR codes for print mode, and writes everything into a `build/` directory as `data.json` plus `.typ` fragment files. Multi-page article splitting is **not** done here -- each article body is written as a single fragment and Typst splits it across pages at render time (see [Section 6.9](#69-step-9----multi-page-articles)). The layout is read **per mode** from `layout-<mode>.yaml` (falling back to `layout.yaml`), so online and print can use different placements.

**Stage 2 (Typst)** reads `data.json` and the generated `.typ` fragments, then renders the final PDF. The Typst template system handles page layout, grid-based absolute positioning, multi-column text flow, image placement, the title page, the organization directory, and optional sections like horoscopes.

The system supports two render modes:
- **Online**: Hyperlinks are clickable and styled in blue with underlines.
- **Print**: Links are displayed as plain text accompanied by inline QR code images and the raw URL in tiny text.

---

## 2. Repository Structure

```
new_banks/
├── build.py                  # Main build script (Python stage)
├── Makefile                  # Build automation
├── requirements.txt          # Python dependencies
├── config.yaml               # Publication metadata
├── layout-online.yaml        # Grid-based placement DSL (online mode)
├── layout-print.yaml         # Grid-based placement DSL (print mode)
├── layout.yaml               # Fallback layout if a mode-specific file is absent
├── events.yaml               # Upcoming events for title page
├── lftc.md                   # Letter from the Chair (markdown)
├── articles/                 # Article markdown files
│   ├── banks.md
│   ├── icpc.md
│   ├── ...
│   └── images/               # Article images (referenced by markdown & layout)
│       ├── career_fair.jpg
│       ├── icpc.jpg
│       └── ...
├── blurbs/                   # Organization descriptions (one YAML per org)
│   ├── acm.yaml
│   ├── sigplan.yaml
│   └── ...  (44 files total)
├── logo/                     # Organization logos
│   ├── acm.png
│   ├── acm-logo.png          # Used on title page banner
│   ├── banks-logo.png        # Used on title page banner
│   └── ...  (46+ files)
├── typst/                    # Typst template system
│   ├── main.typ              # Entry point
│   └── lib/
│       ├── theme.typ         # Design tokens (fonts, sizes, colors)
│       ├── grid-engine.typ   # Grid math & article text placement
│       ├── title-page.typ    # Title page layout
│       ├── article-page.typ  # Article page rendering
│       ├── directory.typ     # Organization directory
│       └── horoscope.typ     # Optional horoscope section
├── ui/                       # Flask web editor (optional)
│   ├── app.py
│   ├── templates/index.html
│   └── static/
│       ├── style.css
│       └── app.js
├── CLAUDE.md                 # AI assistant instructions
├── README.md                 # User-facing README
└── build/                    # Generated at build time (gitignored)
    ├── data.json
    ├── articles/*.typ
    ├── lftc.typ
    ├── qrcodes/*.png
    └── output/
        ├── banks-online.pdf
        └── banks-print.pdf
```

---

## 3. Prerequisites & Setup

**Required software:**
- **Python 3.10+** (for `build.py`)
- **Typst 0.14+** (must be on `PATH`; install from https://github.com/typst/typst)
- **Python packages** (installed via `requirements.txt`):
  - `pyyaml` -- YAML parsing
  - `requests` -- HTTP client for ACM Core API
  - `qrcode[pil]` -- QR code generation (print mode)
  - `flask` -- Web editor UI (optional)

**Setup:**

```bash
make setup    # Creates .venv and installs Python deps
```

This runs `python3 -m venv .venv && .venv/bin/pip install -r requirements.txt` and touches a sentinel file `.venv/.installed` to skip re-installation on subsequent runs. The Makefile checks `requirements.txt` for changes and re-runs setup if needed.

**Build commands:**

| Command | Effect |
|---------|--------|
| `make all` | Build both online and print PDFs |
| `make online` | Build online PDF only |
| `make print` | Build print PDF only |
| `make strict` | Build print PDF; exit non-zero if any article overflows |
| `make online-debug` | Build online PDF with debug overlays (grid lines, bounding boxes, overflow bands) |
| `make print-debug` | Build print PDF with debug overlays |
| `make ui` | Start the Flask web editor (http://localhost:3000) |
| `make clean` | Delete the `build/` directory |

Direct invocation: `.venv/bin/python build.py --mode online|print|both [--strict] [--debug]`

`--debug` passes `debug=true` to Typst, which draws the grid, per-article/image bounding boxes, text-column outlines, and red overflow bands. Debug builds are written to `banks-<mode>-debug.pdf` so they don't clobber the normal output.

---

## 4. Configuration Files

### 4.1 config.yaml

Defines publication-level metadata. Every field is consumed either by `build.py` (for validation and data merging) or by Typst (for rendering the title page and directory).

```yaml
volume: 43                   # Rendered on title page info bar
issue: 1                     # Rendered on title page info bar
date: "November 11, 2025"   # Rendered on title page info bar (uppercased)
headline: "BANKS RETURNS"   # Large bold text on title page
subtitle: "The Journal of..."  # Small text below banner
url: "https://banks.acm.illinois.edu"  # Shown on title page info bar

editors:                     # Listed in the "Editors" footer box
  - "Yanni Zhuang"
  - "Minh Duong"

featured_email: "banks@acm.illinois.edu"  # "Get Featured" footer box

directory_order:             # MUST list every org slug from the API
  - acm                     # Determines display order in directory page
  - corporate_committee
  - sigplan
  - ...
```

**`directory_order` is critical**: it defines the exact display order of organizations on the directory page. If the ACM Core API returns an organization not listed here, the build prints a warning. If a slug listed here does not exist in the API response, an error is printed but the build continues (the slug is skipped).

### 4.2 layout-<mode>.yaml

This is the heart of the placement system. It defines a grid and specifies where every article and image sits on each page. A full explanation of the layout DSL is in [Section 7](#7-the-layout-system-in-depth).

**Per-mode layouts.** `build.py` loads `layout-<mode>.yaml` for the mode being built (`layout-online.yaml` or `layout-print.yaml`), falling back to `layout.yaml` only if the mode-specific file does not exist. This lets the print edition reflow differently from the online edition (e.g., leaving room for QR codes). The web UI reads and writes the mode-specific file. Keep the three files' `grid:` blocks consistent unless you intend them to differ.

**Top-level structure:**

```yaml
grid:
  rows: 24          # Number of rows per page (current layouts use 24)
  columns: 6        # Number of columns per page
  gutter: 8pt       # Space between grid cells
  text_gutter: 8pt  # Gap between text columns within an article

articles:
  - slug: banks                  # Must match articles/banks.md
    column_width: 3              # Text column width in grid units
    full_width_header: true      # Title spans full article width
    images:                      # Article-level images are INLINE (see 7.4)
      - src: photo.jpg
        scale: 70
    placements:
      - page: 1
        cells:
          - [[0, 0], [9, 5]]    # Rows 0-9, columns 0-5
  - slug: rparticle
    # ...
```

Each article entry has:
- `slug` (required): matches the `.md` filename in `articles/`
- `column_width` (required): how many grid columns make one text column
- `full_width_header` (optional, default `false`): if `true`, the title/author line spans the full article width above the text columns
- `full_width_footer` (optional, default `false`): if `true`, the end-of-article rule / continuation marker spans the full width below all columns instead of sitting in the last column
- `column_gap` (optional): overrides `grid.text_gutter` for this article
- `column_separator` (optional, default `false`): draw vertical rules between columns
- `show_border` (optional, default `false`): draw an outline around the article
- `images` (optional): **inline** images for this article (declared at the article level, not inside a placement; see [Section 7.4](#74-image-placement-modes))
- `placements` (required): array of page placements (one per page the article appears on). **Grid-mode** images are declared inside a placement's `images` array.

### 4.3 events.yaml

Lists upcoming events displayed on the title page under "Upcoming Events":

```yaml
events:
  - name: "Weekly Social Hour"
    date: "Every Friday"
    time: "5:00 PM - 6:00 PM"     # Optional
    location: "Legends"            # Optional
    description: "Join us for..."  # Optional (shown in smaller text)
```

### 4.4 lftc.md

The "Letter from the Chair" is a special article that appears on the title page rather than on article pages. It uses the same markdown format as articles but with a single `author` field:

```markdown
---
author: Jacob Levine
---

Letter body in markdown...
```

This is converted to Typst and included in the title page via `#include("/build/lftc.typ")`.

---

## 5. Content Authoring

### 5.1 Article Markdown Format

Articles live in `articles/<slug>.md`. Each file has YAML frontmatter followed by a markdown body:

```markdown
---
title: "My Article Title"
authors:
  - "First Author"
  - "Second Author"
---

Article body using standard markdown.

## Subheadings work

**Bold**, *italic*, and [links](https://example.com) are supported.

![Alt text becomes caption](images/photo.jpg)

- Unordered lists
- Work fine

1. Ordered lists
2. Also work

<br/> tags create vertical space.
```

**Supported markdown features:**

| Markdown | Typst Output | Notes |
|----------|-------------|-------|
| `# Heading` | `= Heading` | Up to 6 levels |
| `**bold**` | `*bold*` | |
| `*italic*` | `_italic_` | |
| `***bold italic***` | `*_bold italic_*` | |
| `[text](url)` | `#link("url")[text]` (online) | Print mode adds QR code |
| `![alt](src)` | `#image(...)` or removed | Depends on grid/inline mode |
| `- item` | `- item` | Unordered list |
| `1. item` | `+ item` | Ordered list (Typst auto-numbers) |
| `<br/>` | `#v(0.5em)` | Vertical space |
| `<!-- break -->` | `#v(1em)` | One blank line of vertical space |
| `<!-- vspace 1.5em -->` | `#v(1.5em)` | Configurable vertical space (bare `<!-- vspace -->` = 1em) |
| `<!-- colbreak -->` | `#colbreak()` | Force the following content into the next text column |
| `@` | `\@` | Escaped (Typst uses @ for references) |

The `<!-- ... -->` markers are HTML comments, so they are invisible when the same markdown is rendered on the website but let you nudge the print/PDF layout (extra space, forced column breaks) without affecting the web copy.

**Image handling** depends on placement mode (see [Section 7.4](#74-image-placement-modes)):
- **Grid-mode images**: declared inside a placement's `images` array (with `cells`, `mode: grid` is the default there). These are *removed* from the markdown body (the grid engine places them at their cell coordinates).
- **Inline images**: declared in the article-level `images` array. These *remain* in the markdown flow and are rendered at their position in the text with an optional `scale` (width percentage) and `border`.

If an image in the markdown is not declared in the layout at all, it is treated as inline at 100% width with a 1pt border.

### 5.2 Organization Blurbs

Each organization has an optional blurb file at `blurbs/<slug>.yaml`:

```yaml
status: active

meeting_times:
  - date: wednesday
    start_time: "17:00"      # Can be "HH:MM" string or minutes since midnight (int)
    end_time: "18:00"
    location: Siebel 1302

blurb: |
  Multi-line description of the organization
  that appears in the directory section.
```

The `status` field is currently informational. `meeting_times` and `blurb` are merged with data fetched from the ACM Core API and rendered in the directory section.

### 5.3 Logos

Organization logos live in `logo/<slug>.{png,jpg,jpeg,svg}`. The build script checks for each extension in that order and uses the first match. Two special logos exist:
- `logo/acm-logo.png` -- ACM logo shown in the title page banner (left side)
- `logo/banks-logo.png` -- Banks logo shown in the title page banner (center)

---

## 6. The Build Pipeline (build.py)

`build.py` is a ~980-line Python script that orchestrates the entire build. It accepts `--mode online|print|both`, `--strict` (treat overflow as error), and `--debug` (draw layout overlays). When `mode` is `both`, it runs the entire per-mode pipeline twice, since both the layout file and the markdown-to-Typst conversion differ between modes (link rendering and QR codes).

**Once-per-run vs. per-mode.** The config/events/horoscope load, API fetch, and article/LFTC load (Steps 1, 4, 5 below) happen a single time. Everything else -- layout load + validation, text-column computation, TOC, QR codes, conversion, caption merge, `data.json` write, compile, and overflow check -- runs once **per mode** inside the mode loop, because each mode has its own `layout-<mode>.yaml`.

### 6.1 Step 1 -- Load Configuration

```python
config = yaml.safe_load(open("config.yaml"))
events_data = yaml.safe_load(open("events.yaml"))
# Optional:
horoscope = yaml.safe_load(open("horoscope.yaml"))  # if file exists

# ...later, inside the per-mode loop:
layout_path = ROOT / f"layout-{mode}.yaml"
if not layout_path.exists():
    layout_path = ROOT / "layout.yaml"   # fallback
layout = yaml.safe_load(open(layout_path))
```

`config.yaml`, `events.yaml`, and the optional `horoscope.yaml` are loaded once and kept in memory. The horoscope file is optional -- if absent, `horoscope` is `None` and the Typst template skips the horoscope page. The **layout** is loaded inside the per-mode loop, choosing `layout-<mode>.yaml` and falling back to `layout.yaml`. Each article's `placements` are then sorted by page number.

### 6.2 Step 2 -- Validate Layout

`validate_layout(layout, article_files)` performs comprehensive validation:

1. **Cell bounds checking**: Every cell `(col, row)` must be within `0..columns-1` and `0..rows-1`.
2. **Contiguity**: Each article's cells on a given page must form a contiguous region (verified by flood-fill).
3. **Column width divisibility**: The article's column span must be evenly divisible by `column_width`.
4. **Image file existence**: Every image `src` must exist in `articles/images/`.
5. **Image cell rectangularity**: Grid-mode image cells must form a perfect rectangle.
6. **Image cell bounds**: Image cells must be within grid bounds.
7. **No cell overlaps**: A per-page cell ownership map detects any cell claimed by two different articles or two different images. An article's own grid-mode images *may* overlap with its text cells (this is expected -- the text region shrinks to accommodate).
8. **Placement image mode**: an image declared inside a placement's `images` array must be `mode: grid` (the default). Inline images belong in the article-level `images` array, not in a placement.
9. **Inline image constraints**: article-level (inline) images must not have `cells`; `scale` must be 1-100.
10. **Alignment validation**: Grid images' `x-alignment` and `y-alignment` must be `left`, `center`, or `right`.
11. **Border validation**: `border` must be a non-negative number.

If any errors are found, they are printed and the build exits with code 1.

**Key helper functions:**

- `_expand_cells(cell_spec)` -- Converts a cell spec (`[row, col]` or `[[r0, c0], [r1, c1]]`) into a set of `(col, row)` tuples. Note the coordinate swap: the YAML format is `[row, col]` but internal representation is `(col, row)`.

- `_is_contiguous(cells)` -- Flood-fill from an arbitrary start cell. If the visited set equals the input set, the region is contiguous (4-connected adjacency).

- `_is_rectangular(cells)` -- Checks `len(cells) == len(unique_cols) * len(unique_rows)`. A rectangular region has exactly this many cells.

### 6.3 Step 3 -- Compute Non-Rectangular Text Columns

After validation, `build.py` computes `text_columns` for placements that span non-rectangular regions:

```python
for article in layout["articles"]:
    col_width = article.get("column_width", 1)
    for placement in article["placements"]:
        text_cols = compute_text_columns(placement["cells"], col_width)
        # Non-rectangular if columns have different row ranges
        if len(text_cols) > 1 and not all(same row ranges):
            placement["text_columns"] = text_cols
```

`compute_text_columns()` groups grid columns into `column_width`-sized chunks, then for each chunk, finds the row range where *all* grid columns in the chunk are occupied. If different chunks have different row ranges (e.g., an L-shaped layout), the placement gets `text_columns` metadata that the Typst renderer uses for atom-based column splitting.

**Example**: An article occupying `[[7,0],[11,1]]` and `[[7,2],[8,3]]` (an L-shape) would produce two text columns with different heights -- column 1 spans rows 7-11, column 2 spans rows 7-8.

### 6.4 Step 4 -- Fetch Organization Data

```python
api_orgs = fetch_api_orgs()  # GET https://core.acm.illinois.edu/api/v1/organizations
blurbs = load_blurbs()       # Load all blurbs/*.yaml
directory = merge_org_data(api_orgs, blurbs, config["directory_order"])
```

**`fetch_api_orgs()`** makes a GET request to the ACM Core API with a 15-second timeout. If it fails, the build continues with an empty org list (non-fatal).

**`normalize_org_slug(name, org_type)`** maps API org names (like `"SIGPwny"`, `"Reflections | Projections"`) to filesystem-friendly slugs (`"sigpwny"`, `"reflections_projections"`). It uses a hardcoded mapping for known names and a fallback regex for unknown names.

**`merge_org_data()`** does three things:
1. Converts each API org into a normalized dict with `slug`, `name`, `type`, `description`, `website`, `email`, `logo` (searched across multiple extensions), `leads`, and `links`.
2. Merges local blurb data (`meeting_times`, `blurb`) into the org dicts.
3. Orders the final list according to `directory_order` from `config.yaml`.

### 6.5 Step 5 -- Load Articles & LFTC

```python
articles = {}
for md_file in ARTICLES_DIR.glob("*.md"):
    article = load_article(md_file)
    articles[article["slug"]] = article
```

`load_article()` parses YAML frontmatter from the markdown file using a regex (`^---\n...\n---\n`) and extracts `title`, `authors`, and `body`. The LFTC is loaded the same way.

### 6.6 Step 6 -- Build Table of Contents

`build_toc()` iterates through `layout["articles"]` sorted by first page number, and builds a list of `{slug, title, authors, page}` dicts (`page` is the placement's layout page number, 1-based). This is rendered as the "In This Issue" section on the title page. The title-page template displays `page + 1` because the title page is PDF page 1, so layout article-page *N* is PDF page *N+1*.

### 6.7 Step 7 -- Generate QR Codes (Print Mode)

Only runs when `mode == "print"`:

```python
all_urls = [url for slug, article in articles.items()
            for _, url in extract_urls_from_markdown(article["body"])]
# Also extracts URLs from LFTC
qr_map = generate_qr_codes(list(set(all_urls)), BUILD / "qrcodes")
```

`extract_urls_from_markdown()` finds all `[text](url)` patterns via regex.

`generate_qr_codes()` creates a QR code PNG for each unique URL:
- Filename: first 12 characters of the MD5 hash of the URL + `.png`
- Files are cached: if the file already exists, it's not regenerated
- Returns a `url -> relative_path` mapping (e.g., `"https://..." -> "qrcodes/a1b2c3d4e5f6.png"`)

If the `qrcode` package is not installed, QR generation is skipped with a warning (non-fatal; links then fall back to plain text + tiny URL).

### 6.8 Step 8 -- Markdown-to-Typst Conversion

The conversion is done per-article by `md_to_typst()`:

```python
for slug, article in articles.items():
    placed = get_placed_images(layout, slug)    # Set of grid-mode image basenames
    img_widths = get_inline_image_scales(layout, slug)  # {basename: scale%}
    img_borders = get_inline_image_borders(layout, slug)  # {basename: border_pt}
    typ_content = md_to_typst(article["body"], mode, slug, placed, qr_map, img_widths, img_borders)
```

**Conversion is line-by-line** via `_convert_line()`:

1. **Images** (`![alt](src)`): If the image basename is in `placed_images` (grid-mode), the line becomes empty (removed). Otherwise, it becomes a Typst `#image()` call with the configured width percentage and border.

2. **Italic caption lines** (`*caption text*`): Standalone italic lines (not bold) are kept as `_caption text_` (typically image captions in the markdown that follow inline images).

3. **Headings** (`# Title`): Converted to Typst headings (`= Title`). The heading text gets inline conversion applied.

4. **Ordered lists** (`1. item`): Converted to `+ item` (Typst's auto-numbering syntax).

5. **Unordered lists** (`- item` or `* item`): Kept as `- item`.

6. **`<br/>` tags**: Replaced with `#v(0.5em)`.

7. **Inline formatting** (via `_convert_inline()`):
   - Bold-italic `***text***` -> `*_text_*`
   - Bold `**text**` -> `*text*`
   - Italic `*text*` -> `_text_` (with negative lookbehind/ahead to avoid matching bold markers)
   - Links `[text](url)`:
     - Online: `#link("url")[text]`
     - Print: `text #box(image("qr_path"), ...) #text(size: 5pt)[url]`

8. **`@` escaping**: After all lines are converted, `@` is escaped to `\@` (Typst uses `@` for cross-references). The regex avoids escaping `@` inside `#link()` calls.

### 6.9 Step 9 -- Multi-Page Articles

**Splitting is not done in Python.** Whether an article spans one page or several, `build.py` writes its *entire* converted body to a single fragment:

```python
(build_articles / f"{slug}.typ").write_text(typ_content)
```

There are no `-part0.typ` / `-part1.typ` files. An article spans multiple pages purely by having multiple `placements` in the layout, and Typst performs the actual splitting at render time: it decomposes the body into word-level "atoms," binary-searches how many atoms fit in each page's allocated area, and coordinates the page boundaries by emitting `<article-consumed>` metadata that later pages read back via Typst's in-document `query()` introspection (resolved over Typst's multi-pass layout, not the external `typst query` CLI; see [Section 8.3](#83-grid-enginetyp----layout-math) and [Section 8.5](#85-article-pagetyp----article-rendering)). Splitting at measurement time is what lets it fill each page exactly rather than guessing at paragraph boundaries.

### 6.10 Step 10 -- Merge Image Captions

`merge_image_captions()` extracts alt text from markdown image syntax (`![alt text](path)`) and merges it into `layout.yaml` image entries that don't have an explicit `caption` field. This allows authors to write captions naturally in markdown while still using grid-mode placement.

Priority: explicit `caption` in `layout.yaml` > alt text from markdown > no caption.

### 6.11 Step 11 -- Write data.json

All merged metadata is written to `build/data.json`:

```json
{
  "config": { /* from config.yaml */ },
  "events": [ /* from events.yaml */ ],
  "toc": [ /* {slug, title, authors, page} */ ],
  "directory": [ /* merged org data, ordered */ ],
  "layout": { /* from layout.yaml, with text_columns added */ },
  "lftc": { "author": "...", "body_file": "lftc.typ" },
  "articles": {
    "slug": { "title": "...", "authors": [...], "typ_file": "articles/slug.typ" }
  },
  "qr_codes": { "url": "qrcodes/hash.png" },
  "horoscope": null,
  "mode": "online"
}
```

This is the **sole data interface** between the Python stage and the Typst stage. Everything the Typst templates need is in this file (plus the generated `.typ` article fragments that are `#include`d).

### 6.12 Step 12 -- Compile with Typst

```python
suffix = f"{mode}-debug" if args.debug else mode
cmd = [
    "typst", "compile",
    "typst/main.typ",
    f"build/output/banks-{suffix}.pdf",
    "--root", ROOT,                  # Root directory for absolute paths in Typst
    "--input", f"mode={mode}",       # CLI variable accessible via sys.inputs
    "--input", f"debug={debug_str}", # "true"/"false" toggles layout overlays
]
subprocess.run(cmd, capture_output=True, text=True)
```

The `--root` flag tells Typst that `/` in import paths resolves to the project root. This is why Typst files use paths like `"/build/data.json"` and `"/articles/images/photo.jpg"`.

The `--input mode=online` flag passes the mode as a Typst system input, accessed in `main.typ` via `sys.inputs.at("mode")`. Likewise `--input debug=...` is read as `sys.inputs.at("debug")`; when `--debug` is set the output filename gains a `-debug` suffix (e.g. `banks-online-debug.pdf`) so it doesn't overwrite the clean PDF.

### 6.13 Step 13 -- Post-Compilation Overflow Check

After compilation, `build.py` queries Typst for overflow metadata:

```python
cmd = ["typst", "query", "typst/main.typ", "<overflow>",
       "--root", ROOT, "--input", f"mode={mode}", "--field", "value"]
```

The Typst template emits `#metadata((...)) <overflow>` labels when an article's content exceeds its allocated space. The `typst query` command extracts these labels. For each overflow, a warning is logged to stderr:

```
WARNING: [online] Article 'slug' content overflows (needs X, allocated Y)
```

With `--strict`, any overflow causes exit code 1.

---

## 7. The Layout System In Depth

### 7.1 Grid Coordinate System

Each article page uses a grid whose dimensions come from the layout file's `grid:` block. The current layouts use **24 rows x 6 columns**; the grid engine's built-in fallback (`default-grid`, used only if a layout omits the values) is 12 rows x 6 columns. The grid covers the full content area of the page (page size minus margins). The diagram below shows a 12-row grid for illustration.

```
          col 0    col 1    col 2    col 3    col 4    col 5
        ┌────────┬────────┬────────┬────────┬────────┬────────┐
 row 0  │        │        │        │        │        │        │
        ├────────┼────────┼────────┼────────┼────────┼────────┤
 row 1  │        │        │        │        │        │        │
        ├────────┼────────┼────────┼────────┼────────┼────────┤
  ...   │        │        │        │        │        │        │
        ├────────┼────────┼────────┼────────┼────────┼────────┤
 row 11 │        │        │        │        │        │        │
        └────────┴────────┴────────┴────────┴────────┴────────┘
```

Cells are separated by `gutter` spacing (default 8pt). The cell dimensions are computed as:

```
cell_width  = (content_width  - (columns - 1) * gutter) / columns
cell_height = (content_height - (rows - 1)    * gutter) / rows
```

Where `content_width = 8.5in - 2 * 0.5in = 7.5in` and `content_height = 11in - 2 * 0.5in = 10in`.

### 7.2 Cell Specification Syntax

Cells in the layout files use `[row, col]` coordinates (origin at top-left, 0-indexed):

```yaml
# Single cell:
[3, 2]                          # row 3, column 2

# Rectangular range (inclusive):
[[0, 0], [4, 5]]               # rows 0-4, columns 0-5 (full width, top half)
[[5, 0], [9, 5]]               # rows 5-9, columns 0-5 (full width, lower area)
[[7, 0], [11, 1]]              # rows 7-11, columns 0-1 (bottom-left block)
```

**Important**: YAML uses `[row, col]` but the internal Python and Typst code uses `(col, row)`. The `_expand_cells()` function in `build.py` and `expand-cell-specs()` in `grid-engine.typ` both handle this coordinate swap.

An article's `cells` list can contain **multiple cell specs** per placement, allowing non-rectangular regions:

```yaml
cells:
  - [[0, 0], [6, 3]]      # Tall left block
  - [[4, 4], [6, 5]]      # Short right extension
```

This creates an L-shaped article region.

### 7.3 Column Width & Text Columns

`column_width` defines how many grid columns make up one text column. The number of text columns is `floor(article_grid_width / column_width)`.

**Examples:**
- Article spanning columns 0-5 (width 6) with `column_width: 3` = **2 text columns**
- Article spanning columns 0-5 (width 6) with `column_width: 2` = **3 text columns**
- Article spanning columns 0-1 (width 2) with `column_width: 2` = **1 text column**

Text columns are separated by `text_gutter` (or the per-article `column_gap` override). When `column_separator: true`, a thin vertical rule (0.25pt) is drawn between columns.

### 7.4 Image Placement Modes

The two image modes are declared in **different places**: grid images live inside a *placement's* `images` array, while inline images live in the *article-level* `images` array (a sibling of `placements`).

#### Grid Mode (declared inside a placement)

```yaml
placements:
  - page: 1
    cells:
      - [[0, 0], [11, 5]]
    images:                       # placement-level → grid mode
      - src: photo.jpg
        mode: grid
        cells:
          - [[10, 0], [11, 1]]    # Where to position the image
        caption: "Photo credit"   # Optional (auto-extracted from markdown alt text)
        x-alignment: center       # left | center | right (default: center)
        y-alignment: center       # left | center | right (default: center)
        border: 1                 # Border width in pt (0 = no border, default: 1)
```

Grid-mode images are:
- **Removed** from the markdown body during conversion (the line becomes empty)
- **Placed** by the Typst grid engine at their specified cell coordinates
- Required to have **rectangular** cells
- Their cells may overlap with the parent article's cells (the text area shrinks to exclude image cells)

The image is fit within its cell box while maintaining aspect ratio. If the image is taller than the available height, it is scaled down proportionally.

#### Inline Mode (declared at the article level)

```yaml
- slug: my-article
  column_width: 2
  images:                        # article-level → inline mode
    - src: photo.jpg
      scale: 80                  # Width as % of text column (default: 100)
      border: 1                  # Border width in pt (default: 1)
  placements:
    - page: 1
      cells:
        - [[0, 0], [11, 1]]
```

Inline images:
- **Stay** in the markdown body at their original position (matched by filename)
- Are rendered with the specified `scale` and `border`
- Must NOT have `cells` (they're not grid-positioned), and need no `mode` key
- Are centered and include the markdown alt text as a caption below

### 7.5 Non-Rectangular Layouts

When an article's cells form a non-rectangular shape (e.g., L-shaped), the build script detects this by computing `text_columns` and checking if columns have different row ranges. In this case:

1. `build.py` adds `text_columns` metadata to the placement:
   ```json
   "text_columns": [
     {"col_start": 0, "col_end": 1, "row_start": 7, "row_end": 11},
     {"col_start": 2, "col_end": 3, "row_start": 7, "row_end": 8}
   ]
   ```

2. The Typst renderer uses `place-article-columns()` instead of `place-article-text()`. This function:
   - Decomposes the article body into word-level **atoms** (via `content-to-atoms()`)
   - Uses **binary search** to find the maximum number of atoms that fit in each column's unique dimensions
   - Reconstructs content from atoms (with proper enum/list formatting) via `build-content()`
   - Places each column independently with its own height

This is significantly more complex than rectangular layouts because Typst's built-in `columns()` function assumes all columns have the same height.

### 7.6 Layout Validation Rules

Summary of all validations performed by `validate_layout()`:

| Rule | Error Message |
|------|--------------|
| Cell out of grid bounds | `cell (c,r) out of bounds (grid is CxR)` |
| Non-contiguous article cells | `cells are not contiguous` |
| Column width doesn't divide width | `column_width N does not divide article width W` |
| Missing article .md file | `Layout references article 'slug' but no .md file found` |
| Missing image file | `file not found at path` |
| Non-rectangular grid image | `cells are not rectangular` |
| Image cell out of bounds | `cell (c,r) out of bounds` |
| Cell overlap between articles/images | `cell (c,r) claimed by both 'X' and 'Y'` |
| Non-grid image in a placement | `placement images must be mode 'grid', got 'X'` |
| Inline image with cells | `inline images must not have 'cells'` |
| Invalid scale | `scale N must be between 1 and 100` |
| Invalid alignment | `x-alignment 'X' must be one of: left, center, right` |
| Invalid border | `border must be a non-negative number` |

---

## 8. The Typst Template System

### 8.1 main.typ -- Entry Point

`typst/main.typ` (60 lines) is the root entry point. Its responsibilities:

1. **Import** all library modules from `typst/lib/`
2. **Read mode & debug** from CLI input: `sys.inputs.at("mode", default: "online")` and `sys.inputs.at("debug", default: "false") == "true"`; `debug` is threaded into `render-article-page`
3. **Load data**: `json("/build/data.json")`
4. **Configure page**: US Letter (8.5" x 11"), 0.5" margins, Georgia font, 9pt body size, justified paragraphs
5. **Global link styling**: In online mode, links are underlined and blue; in print mode, unstyled
6. **Render pages in order**:
   - Title page (constrained to exactly 1 page via `block(height: 100%, ...)`)
   - Article pages (loop from page 1 to max page)
   - Directory page
   - Horoscope page (if `data.horoscope != none`)

### 8.2 theme.typ -- Design Tokens

`typst/lib/theme.typ` (31 lines) defines all visual constants as Typst variables:

**Page geometry:**
- `page-width`: 8.5in, `page-height`: 11in
- `margin-x`, `margin-y`: 0.5in
- `content-width`: 7.5in, `content-height`: 10in (computed)

**Typography:**
- `heading-font`: Georgia
- `body-font`: Georgia
- `mono-font`: Courier New
- `headline-size`: 28pt (title page headline)
- `title-size`: 36pt (defined but not currently referenced by the templates)
- `subtitle-size`: 8pt
- `section-heading-size`: 16pt (directory/horoscope headings)
- `article-title-size`: 14pt
- `body-size`: 9pt
- `small-size`: 7pt (captions, author lines, continuation markers)
- `tiny-size`: 6pt (horoscope dates)

**Colors:**
- `accent-color`: #1a1a1a (dark gray)
- `link-color`: #0645AD (blue, used in online mode)
- `rule-color`: #333333 (horizontal and vertical rules)
- `bg-light`: #f5f5f5 (not currently used in templates)

### 8.3 grid-engine.typ -- Layout Math

`typst/lib/grid-engine.typ` (~1310 lines) is the most complex module. It provides everything needed to convert grid coordinates to absolute positions and place content on the page.

#### Coordinate Conversion

**`cell-rect(col-start, row-start, col-end, row-end)`** converts inclusive grid coordinates to absolute `(x, y, width, height)`:

```
x = col-start * (cell_width + gutter)
y = row-start * (cell_height + gutter)
w = (col-end - col-start + 1) * (cell_width + gutter) - gutter
h = (row-end - row-start + 1) * (cell_height + gutter) - gutter
```

The `-gutter` at the end ensures the cell rectangle doesn't include the gutter on its right/bottom edge.

**`cells-bbox(cells)`** computes the bounding box (min/max col/row) of a set of cell specs.

#### Cell Expansion & Adjacency

**`expand-cell-specs(cells)`** converts an array of cell specs into deduplicated `(col, row)` tuples.

**`cells-are-adjacent(cells-a, cells-b)`** checks if two cell regions share at least one 4-connected edge. Used to determine if images are contiguous with their parent article (for border drawing).

#### Border Drawing

**`draw-cell-border(cells)`** draws a perimeter outline around an arbitrary set of grid cells:

- **Rectangular case**: Simple `block(stroke: ...)` at the bounding box.
- **Non-rectangular case**: Traces a clockwise polygon by walking right-side vertices (top to bottom) and left-side vertices, handling "steps" where the shape narrows or widens. The polygon is drawn with Typst's `path()` function.

Each row is assumed to have a single contiguous column range (valid for all contiguous shapes used in practice).

#### Content Decomposition (Atom System)

For non-rectangular layouts, content must be split at word boundaries to fill columns of different heights. The atom system breaks content into individual words and structural markers:

**`tokenize(content, wrappers)`** recursively walks the Typst content tree:
- `text` elements are split on spaces into individual words
- Style wrappers (`strong`, `emph`, `underline`, etc.) are tracked and re-applied to each word
- `parbreak` becomes the `"¶PARBREAK¶"` marker
- `enum.item` and `list.item` become `"¶ENUM:N¶"` / `"¶LIST¶"` and `"¶/ENUM¶"` / `"¶/LIST¶"` markers

**`group-words(tokens)`** groups tokens into complete words (joining fragments between spaces and markers).

**`content-to-atoms(body)`** is the top-level function: tokenizes, groups, deduplicates consecutive parbreaks, and strips leading/trailing parbreaks.

**`build-content(atom-slice)`** reconstructs Typst content from an atom slice:
- Segments atoms by structural markers
- Each segment is rendered as: text (joined with spaces), `enum(start: N, ...)`, `list(...)`, or `pad(left: 1.5em, ...)` for continuations split mid-item

#### Rectangular Article Placement

**`place-article-text()`** handles standard rectangular layouts:

1. Computes the text region from the article's bounding box
2. If grid-mode images exist within the bounding box, shrinks the text region by finding the widest contiguous column span not occupied by images in the first row
3. Applies border padding (6pt) if `show-border` is true
4. Renders body using Typst's built-in `columns()` function
5. Optionally draws column separators
6. **Full-width header**: If enabled, the header (title + authors + rule) spans the full article width including image areas. Header width is computed as the union of text area and top-row images.
7. **Overflow detection**: Measures body content at single-column width, divides by column count, and compares against available height. If overflowing, emits a `<overflow>` metadata label and clips content.
8. Images are placed at their grid coordinates with optional `dy-offset` if they conflict with the header.

**Multi-page rectangular articles** take a separate path inside the same function: `article-page.typ` passes the full unstyled body as `raw-body` plus `page-index`. The engine decomposes `raw-body` into atoms, sums how many atoms prior pages consumed (read from `<article-consumed>` metadata via `query`), binary-searches how many of the remaining atoms fit in this page's `body-h × num-columns` area, renders that slice, and emits its own `<article-consumed>` count so the next page knows where to resume. Overflow on the final page emits `<overflow>`.

#### Non-Rectangular Article Placement

**`place-article-columns()`** handles L-shaped and other non-rectangular layouts:

1. Receives pre-computed `text-columns` (from `build.py`) with independent row/col ranges per column
2. Decomposes body into atoms via `content-to-atoms()`
3. Computes a header that spans all first-row columns (including image areas)
4. For each column:
   - Computes available height (minus header if applicable, minus footer space in last column)
   - Tries placing all remaining atoms; if they fit, done
   - Otherwise, **binary search** finds the maximum atom count that fits:
     ```
     bsearch(lo, hi, width, height, offset):
       mid = (lo + hi) / 2
       measure(build-content(atoms[offset:offset+mid]))
       if fits: search upper half
       else: search lower half
     ```
   - Places the fitted atom slice and advances the offset
5. After all columns, checks if atoms remain (overflow)
6. Draws column separators (clipped to below the header)

### 8.4 title-page.typ -- Title Page

`typst/lib/title-page.typ` (195 lines) renders the title page with these sections:

1. **Banner** (3-column grid):
   - Left: ACM logo (`logo/acm-logo.png`, 60pt height)
   - Center: Banks logo (`logo/banks-logo.png`, 80pt height)
   - Right: "Urbana, IL" text

2. **Subtitle**: Publication tagline from `config.subtitle`, centered, 8pt

3. **Info bar** (3-column grid, between horizontal rules):
   - Left: "Volume 43, Issue 1"
   - Center: Date in bold italic, uppercased
   - Right: URL (clickable in online mode)

4. **Headline**: Large bold text (`headline-size`, 28pt) from `config.headline`

5. **Letter from the Chair**:
   - Title "Letter from the Chair" (18pt bold)
   - "By {author}" in bold (body size)
   - Short centered rule (40% width)
   - Body included from `/build/lftc.typ`

6. **Double rule separator**: Two 1pt lines with 2pt gap

7. **Two-column layout** (flexibly fills remaining space with `v(1fr)` above and below):
   - **Left: "In This Issue"** -- TOC with dot leaders and page numbers
   - **Right: "Upcoming Events"** -- Event name (bold), date/time/location (italic), optional description

8. **Footer** (2-column grid, 3:2 ratio):
   - Left: "Get Featured in Banks!" box with submission email
   - Right: "Editors" box listing editor names

The title page is wrapped in `block(height: 100%, ...)` in `main.typ` to ensure it fills exactly one page.

### 8.5 article-page.typ -- Article Rendering

`typst/lib/article-page.typ` (~320 lines) handles all article pages.

**`render-article-page(page-num, layout-data, articles-data, mode, debug: false)`**:

1. Parses the grid configuration from the layout's `grid:` block (evaluating `"8pt"` strings into Typst lengths via `eval`).

2. Collects all articles scheduled for this page by scanning `layout.articles[].placements[].page`.

3. For each article on the page:

   a. **Determines multi-page state**: Checks if the article has multiple placements. Determines `is-first-page`, `is-last-page`, and `page-index`.

   b. **Checks for non-rectangular layout**: Looks for `text_columns` in the placement (set by `build.py`).

   c. **Prepares image data**: Filters to grid-mode images only (inline images are already in the `.typ` body). Maps each to `{cells, path, caption, x-alignment, y-alignment, border}`.

   d. **Builds header content**:
      - First page: article title (14pt bold) + authors ("By Author1, Author2" in 7pt italic) + horizontal rule
      - Continuation pages: smaller title (body-size + 2pt) + "Continued from page N" in italic

   e. **Loads article body**: Always includes the single `/build/articles/{slug}.typ` fragment (there are no per-page files). For multi-page articles the full body is included on every page the article spans, and the grid engine renders only the slice that belongs to the current page (via the atom/`<article-consumed>` mechanism in [Section 8.3](#83-grid-enginetyp----layout-math)).

   f. **Builds body content** (for rectangular path): wraps raw body with text styling, link styling, and appends footer:
      - Last page: double rule (two horizontal lines)
      - Non-last multi-page: "Continued on page N" (right-aligned, italic, 7pt)

   g. **Draws borders** (if `show_border`): Combines article cells with contiguous image cells iteratively (using `cells-are-adjacent()`), then draws a single border around the combined region. Non-contiguous images get separate borders.

   h. **Dispatches to renderer**:
      - Non-rectangular (`text_columns != none`): calls `place-article-columns()` with footer content separated out
      - Rectangular: calls `place-article-text()`:
        - If `full_width_header`: header is passed separately, body excludes header
        - If not: header is prepended to body, header param is `none`

When `debug` is true, each article additionally draws its cell bounding box (blue) with a slug label and its grid-image boxes (green), and after all articles the whole page grid is outlined with `row,col` labels in red. The per-region overlays (header/body/columns/footer/overflow bands) are drawn inside `place-article-text` / `place-article-columns`.

**`max-page(layout-data)`** scans all placements to find the highest page number.

### 8.6 directory.typ -- Organization Directory

`typst/lib/directory.typ` (179 lines) renders a two-column directory of all organizations.

**Helper functions:**
- `format-day("wednesday")` -> `"Wednesdays"` (maps day slugs to display names)
- `format-time(t)` -> `"5:00 PM"` (handles both integer minutes-since-midnight and `"HH:MM"` strings, converts to 12-hour AM/PM)
- `link-type-label("DISCORD")` -> `"Discord"` (maps API link type codes to display labels)

**Each organization entry renders:**
1. Logo (24pt height) + name (14pt bold) in a 2-column grid
2. Leadership:
   - ACM main (`type == "main"`): Lists Chair, Vice Chair, Treasurer, Secretary as individual labeled roles, plus any others
   - Other orgs: "Chairs: Name1, Name2"
3. Website (clickable in online mode, plain text in print)
4. Email (mailto link in online mode, plain text in print)
5. Meeting times: "Wednesdays, 5:00 PM-6:00 PM, Siebel 1302"
6. Social links: Discord, Instagram, GitHub, Twitter, LinkedIn, Matrix
7. Blurb text (justified, no first-line indent)
8. Thin separator line (0.25pt)

Each entry is rendered as a non-breakable block (`breakable: false`) so organizations don't split across columns.

### 8.7 horoscope.typ -- Optional Horoscope Section

`typst/lib/horoscope.typ` (42 lines) renders an optional horoscope page if `data.horoscope != none` (controlled by whether `horoscope.yaml` exists).

Structure:
- "Horoscope" heading (16pt)
- Optional `horoscope.title` subtitle
- Two-column layout of zodiac signs, each with:
  - Sign name (10pt bold) + optional dates (6pt)
  - Horoscope text (7pt)
  - Thin separator

---

## 9. Overflow Detection & Handling

Overflow is detected in two places:

### In `place-article-text()` (rectangular layouts):
```typst
let single-col-h = measure(block(width: single-col-w, spacing: 0pt, effective-body)).height
let body-overflows = single-col-h / num-columns > body-h
```
The body is measured at single-column width, and the height is divided by the number of columns (approximating balanced column heights). If this exceeds the available `body-h`, an `<overflow>` metadata label is emitted and content is clipped. (For multi-page articles, overflow is instead reported by the atom-splitting path described in [Section 8.3](#83-grid-enginetyp----layout-math), only on the last page.)

### In `place-article-columns()` (non-rectangular layouts):
```typst
if offset < total {
  [#metadata((slug: slug, ...)) <overflow>]
}
```
After flowing atoms through all columns, if atoms remain unplaced, an overflow is detected.

### Post-compilation:
`build.py` runs `typst query ... <overflow>` to extract all overflow labels and prints warnings. With `--strict`, any overflow is fatal.

**Behavior on overflow:**
- Rectangular: content is **clipped** (rendered but cut off at the boundary)
- Non-rectangular: remaining words are silently dropped (the binary search only places what fits)
- In both cases, the metadata label allows the build script to detect and report the issue

**Visualizing overflow.** Build with `make online-debug` / `make print-debug` (or `--debug`). The grid engine then draws the header (orange), body (magenta), text columns (cyan dashed), footer (brown), and image (green) regions, plus a red band and an `OVERFLOW: …` label at the column that overran -- making it obvious how much content was cut and where.

---

## 10. Online vs. Print Mode

The mode flows through the entire pipeline:

| Aspect | Online | Print |
|--------|--------|-------|
| Links in articles | `#link("url")[text]` (clickable, blue, underlined) | `text + QR image + tiny URL` |
| Links in directory | Clickable `link()` for websites, emails, social links | Plain text |
| Links on title page | Clickable URL, clickable mailto | Plain text |
| QR codes | Not generated | Generated for every URL in articles and LFTC |
| Global link styling | `underline(text(fill: link-color, it))` | No styling (identity) |

The mode is:
1. Passed to `build.py` via `--mode` CLI flag
2. Stored in `data.json` as `data.mode`
3. Passed to Typst via `--input mode=online|print`
4. Read in `main.typ` via `sys.inputs.at("mode")`
5. Threaded through rendering functions as a `mode` parameter

---

## 11. The Web UI

The optional Flask web UI (`ui/app.py`) provides a browser-based editor for managing the newspaper.

**Server**: `make ui` starts Flask on `http://localhost:3000`.

**REST API endpoints:**

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Serve the editor HTML |
| `/api/layout?mode=<mode>` | GET/PUT | Read/update the mode-specific `layout-<mode>.yaml` (falls back to `layout.yaml`); PUT re-serializes via `serialize_layout()` |
| `/api/layout/copy` | POST | Copy one mode's layout to the other (`{"from": "online", "to": "print"}`) |
| `/api/config` | GET/PUT | Read/update `config.yaml` |
| `/api/events` | GET/PUT | Read/update `events.yaml` |
| `/api/articles` | GET | List all articles (slug, title, authors, images) |
| `/api/articles/<slug>` | GET/PUT | Read/update an article |
| `/api/articles` | POST | Create a new article |
| `/api/articles/<slug>` | DELETE | Delete an article |
| `/api/lftc` | GET/PUT | Read/update the LFTC |
| `/api/images` | GET | List all images |
| `/api/images/<name>` | GET | Serve an image |
| `/api/images` | POST | Upload an image |
| `/api/build` | POST | Trigger a build in a background thread (body: `{"mode", "debug"}`) |
| `/api/build/status` | GET | Get build status and log output |
| `/api/pdf/<mode>` | GET | Download a built PDF (`online`, `print`, `online-debug`, `print-debug`) |
| `/api/pdfs` | GET | List which PDF variants currently exist on disk |

Note that `PUT /api/layout` does not use `yaml.dump`; `serialize_layout()` writes the YAML by hand to preserve the project's formatting and field ordering. If you change the layout schema, update that function too.

**Editor tabs:**
1. **Layout**: Visual grid editor with drag-to-draw article placement, image positioning, properties panel
2. **Articles**: List, edit, and create articles; edit the LFTC
3. **Config & Events**: Edit publication metadata and event listings
4. **Build**: Trigger builds, view logs, preview PDFs

---

## 12. Build Artifacts

After a successful build, the `build/` directory contains:

```
build/
├── data.json                    # All merged metadata (Typst reads this); overwritten per mode
├── lftc.typ                     # Converted LFTC markdown
├── articles/
│   ├── banks.typ                # One fragment per article (full body, even if multi-page)
│   ├── rparticle.typ
│   └── ...
├── qrcodes/                     # Print mode only
│   ├── a1b2c3d4e5f6.png        # QR code PNGs (MD5 hash filenames)
│   └── ...
└── output/
    ├── banks-online.pdf         # Final output (online mode)
    ├── banks-print.pdf          # Final output (print mode)
    ├── banks-online-debug.pdf   # Only when built with --debug
    └── banks-print-debug.pdf    # Only when built with --debug
```

The `build/` directory is gitignored and fully regenerated on each build. There is exactly one `.typ` per article regardless of how many pages it spans (Typst splits at render time). `data.json` is rewritten for each mode that is built. The `qrcodes/` subdirectory uses content-addressable filenames (MD5 of URL), so unchanged URLs don't regenerate.

---

## 13. Common Tasks & Recipes

### Add a new article

1. Create `articles/my-article.md` with frontmatter:
   ```markdown
   ---
   title: "My Article"
   authors:
     - "Author Name"
   ---
   Article body...
   ```
2. Add a placement entry in the layout file(s) -- `layout-online.yaml` and/or `layout-print.yaml` (or `layout.yaml` if you keep a single shared layout). Remember to add it for **every** mode you build:
   ```yaml
   - slug: my-article
     column_width: 3
     full_width_header: true
     placements:
       - page: 2
         cells:
           - [[0, 0], [11, 5]]
   ```
3. Run `make all` to build.

### Add images to an article

**Grid-mode** (positioned at specific cells):
```yaml
placements:
  - page: 2
    cells:
      - [[0, 0], [5, 5]]
    images:
      - src: my-photo.jpg
        mode: grid
        cells:
          - [[4, 4], [5, 5]]
        caption: "Photo caption"
```
Place `my-photo.jpg` in `articles/images/`.

**Inline** (in markdown flow):
```yaml
images:
  - src: my-photo.jpg
    mode: inline
    scale: 80
```
Reference the image normally in your markdown: `![Caption](images/my-photo.jpg)`

### Add a new organization

1. Ensure the org exists in the ACM Core API (it must be returned by the API endpoint).
2. Create `blurbs/<slug>.yaml` with meeting times and blurb.
3. Add the logo to `logo/<slug>.png`.
4. Add the slug to `directory_order` in `config.yaml` at the desired position.

### Create an L-shaped article layout

Specify multiple cell ranges in the placement:
```yaml
- slug: my-article
  column_width: 2
  full_width_header: true
  placements:
    - page: 2
      cells:
        - [[0, 0], [6, 3]]      # Tall left portion
        - [[4, 4], [6, 5]]      # Short right extension
      images:
        - src: photo.jpg
          mode: grid
          cells:
            - [[0, 4], [3, 5]]  # Image fills the "gap" in the L
```

The build script will detect the non-rectangular shape and use atom-based column splitting.

### Span an article across multiple pages

Add multiple placement entries:
```yaml
- slug: long-article
  column_width: 3
  placements:
    - page: 1
      cells:
        - [[6, 0], [11, 5]]
    - page: 2
      cells:
        - [[0, 0], [5, 5]]
```

No splitting markup is needed: the full body is written once and Typst flows it across the listed pages at render time, filling each page's area by measurement. The renderer adds "Continued on page N" / "Continued from page N" markers automatically.

### Debug content overflow

1. Run `make strict` to make overflow errors fatal.
2. Check stderr for overflow warnings: `WARNING: [online] Article 'slug' content overflows (needs X, allocated Y)`.
3. Run `make online-debug` (or `make print-debug`) and open `banks-<mode>-debug.pdf` to *see* the overrun: a red band + `OVERFLOW: …` label marks the column that didn't fit, over the grid/region overlays.
4. Possible fixes:
   - Give the article more grid cells
   - Reduce the text content
   - Use a smaller `column_width` (more text columns = more space)
   - Split the article across multiple pages

### Change the design

Edit `typst/lib/theme.typ` to change fonts, sizes, or colors. All Typst modules import from `theme.typ`, so changes propagate automatically. For structural layout changes, edit the relevant module in `typst/lib/`.
