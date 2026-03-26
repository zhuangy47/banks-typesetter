# Banks of the Boneyard Typesetter

A newspaper typesetting system for *Banks of the Boneyard*, the journal of ACM@UIUC. Transforms markdown articles, YAML configuration, and organization data into a professionally formatted PDF newspaper using [Typst](https://typst.app/).

Supports two render modes:
- **Online** — clickable hyperlinks, blue/underlined
- **Print** — plain text links with inline QR codes

## Quick Start

```bash
# Install dependencies (creates .venv automatically)
make setup

# Build both online and print PDFs
make all

# Build only one mode
make online
make print

# Clean build artifacts
make clean
```

Output PDFs are written to `build/output/banks-online.pdf` and `build/output/banks-print.pdf`.

### Requirements

- Python 3.10+
- [Typst](https://typst.app/) 0.14+ (must be on `PATH`)
- Python packages: `pyyaml`, `requests`, `qrcode[pil]`

## Project Structure

```
.
├── build.py                  # Main build orchestrator
├── Makefile                  # Build automation
├── requirements.txt          # Python dependencies
├── config.yaml               # Publication metadata
├── events.yaml               # Upcoming events list
├── layout.yaml               # Grid-based article placement
├── lftc.md                   # Letter from the Chair (markdown)
├── articles/                 # Article markdown files
│   ├── banks.md
│   ├── rparticle.md
│   ├── ...
│   └── images/               # Article images
├── blurbs/                   # Organization blurb YAML files
│   ├── acm.yaml
│   ├── sigpwny.yaml
│   └── ...
├── logo/                     # Organization logos (PNG/JPG/SVG)
├── typst/                    # Typst templates
│   ├── main.typ              # Entry point
│   └── lib/
│       ├── theme.typ          # Fonts, sizes, colors
│       ├── grid-engine.typ    # Grid positioning math
│       ├── title-page.typ     # Title page layout
│       ├── article-page.typ   # Article rendering
│       ├── directory.typ      # Organization directory
│       └── horoscope.typ      # Optional horoscope section
└── build/                    # Generated (gitignored)
    ├── data.json              # Merged metadata for Typst
    ├── articles/              # Converted .typ fragments
    ├── lftc.typ               # Converted letter from the chair
    ├── qrcodes/               # QR code PNGs (print mode)
    └── output/                # Final PDFs
```

## Configuration Files

### `config.yaml`

Publication-level metadata:

```yaml
volume: 43
issue: 1
date: "November 11, 2025"
headline: "BANKS RETURNS"
subtitle: "The Journal of the Association of Computing Machinery at the University of Illinois Urbana-Champaign"
url: "https://banks.acm.illinois.edu"

editors:
  - "Yanni Zhuang"
  - "Minh Duong"

featured_email: "banks@acm.illinois.edu"

# Controls the order of orgs in the directory section.
# Every org returned by the ACM core API must appear here.
directory_order:
  - acm
  - sigpwny
  - icpc
  # ...
```

### `events.yaml`

Events displayed on the title page:

```yaml
events:
  - name: "Weekly Social Hour"
    date: "Every Friday"
    time: "5:00 PM - 6:00 PM"        # optional
    location: "Legends"               # optional
    description: "Come hang out!"     # optional
```

### `layout.yaml`

The grid-based layout DSL that controls where articles and images appear. See [Layout System](#layout-system) for full documentation.

## Writing Articles

Articles are markdown files in `articles/` with YAML frontmatter:

```markdown
---
title: "My Article Title"
authors:
  - "Jane Doe"
  - "John Smith"
---

Article body in markdown. Supports:

**Bold text**, *italic text*, and ***bold italic***.

## Headings

[Links](https://example.com) become clickable (online) or get QR codes (print).

![Alt text becomes caption](my-image.jpg)

- Bullet lists
1. Numbered lists

<br/> for explicit line breaks
```

### Letter from the Chair

`lftc.md` uses the same format but with a single `author` field:

```markdown
---
author: "Jacob Levine"
---

Letter body...
```

## Layout System

The layout is defined in `layout.yaml` using a grid-based coordinate system.

### Grid

Each article page is divided into a **12 × 6 grid** (rows × columns). Cell coordinates use `[row, col]` with origin at top-left `[0, 0]`.

```yaml
grid:
  rows: 12
  columns: 6
  gutter: 4pt         # gap between grid cells
  text_gutter: 8pt     # gap between text columns within an article
```

### Article Placement

Each article specifies which grid cells it occupies and how wide its text columns should be:

```yaml
articles:
  - slug: my-article           # matches articles/my-article.md
    column_width: 3            # text columns are 3 grid units wide (= 2 columns)
    placements:
      - page: 1
        cells:
          - [[0, 0], [5, 5]]   # top half of page, full width
```

#### Cell Syntax

```yaml
# Single cell
[row, col]

# Rectangular region (inclusive)
[[row_start, col_start], [row_end, col_end]]
```

Examples:
- `[[0, 0], [5, 5]]` — top half, full width
- `[[6, 0], [11, 5]]` — bottom half, full width
- `[[0, 0], [11, 2]]` — full height, left half

#### Per-Article Display Options

All optional:

```yaml
- slug: featured-article
  column_width: 3
  full_width_header: true      # title/author spans full width above columns
  column_gap: 12pt             # override default gap between text columns
  column_separator: true       # draw vertical rules between columns
  show_border: true            # draw outline around article bounding box
  placements:
    - page: 1
      cells:
        - [[0, 0], [5, 5]]
```

| Option | Default | Description |
|---|---|---|
| `full_width_header` | `false` | Title and author span full article width above the columns |
| `column_gap` | grid's `text_gutter` | Width of gap between text columns |
| `column_separator` | `false` | Vertical rule between columns |
| `show_border` | `false` | Outline around article bounding box |

### Image Placement

Images have two modes:

#### Grid Mode (positioned at specific cells)

The image is removed from the markdown body and placed at the specified grid cells. Captions are automatically extracted from the markdown alt text, or can be set explicitly.

```yaml
placements:
  - page: 1
    cells:
      - [[0, 0], [11, 5]]
    images:
      - src: hero-photo.jpg
        mode: grid
        cells:
          - [[0, 0], [3, 5]]       # top third of the article area
      - src: detail.png
        mode: grid
        cells:
          - [[0, 4], [2, 5]]
        caption: "Override caption"  # optional, overrides markdown alt text
```

- Image cells must be rectangular and within the page grid bounds
- Image cells don't need to be within the article's text cell range — they can be placed anywhere on the page
- If an article's own images overlap its cell range, the text region automatically shrinks to exclude the image area (images at edges carve out rows or columns)
- No cell can be shared between two different articles or two different images
- Captions are auto-extracted from `![alt text](image.jpg)` in the markdown

#### Inline Mode (rendered in-place)

The image stays in the markdown body at its original position:

```yaml
images:
  - src: diagram.png
    mode: inline
    scale: 80                       # optional, width as % of text column (default 100)
```

### Multi-Page Articles

An article can span multiple pages by listing multiple placements:

```yaml
- slug: long-article
  column_width: 2
  placements:
    - page: 1
      cells:
        - [[6, 0], [11, 5]]
    - page: 2
      cells:
        - [[0, 0], [5, 5]]
```

The build system automatically:
1. Splits the article content at paragraph boundaries
2. Adds "Continued on page X" at the bottom of each part
3. Adds "Continued from page X" at the top of continuation pages
4. Shows a smaller title on continuation pages

## Organization Directory

The directory section is built from two sources:

### API Data

Organization data (name, leads, email, website, links) is fetched automatically from the [ACM@UIUC Core API](https://core.acm.illinois.edu/api/v1/organizations).

### Blurb Files

Supplemental data lives in `blurbs/<slug>.yaml`:

```yaml
status: active

meeting_times:
  - date: thursday            # lowercase day name
    start_time: 1080          # minutes since midnight (18:00)
    end_time: 1140            # minutes since midnight (19:00)
    location: SC 1302
  # or string format:
  - date: sunday
    start_time: "17:00"
    end_time: "18:00"
    location: SC 1404

blurb: >
  A short description of the organization that appears
  in the directory entry.
```

### Logos

Place organization logos in `logo/<slug>.png` (or `.jpg`, `.jpeg`, `.svg`). The build system automatically detects the file extension.

### ACM General Entry

The ACM general entry (slug `acm`, type `main`) displays leadership roles individually — Chair, Vice Chair, Treasurer, Secretary — rather than listing all leads as "Chairs".

### Directory Order

The `directory_order` list in `config.yaml` controls the order orgs appear. Every org returned by the API must be listed or the build will warn.

## Build Process

Running `python build.py --mode online` (or `make online`) performs:

1. **Load config** — `config.yaml`, `events.yaml`, `layout.yaml`
2. **Validate layout** — checks cell bounds, contiguity, rectangular images, no overlapping articles/images, image files exist, article files exist
3. **Fetch API data** — organization info from `core.acm.illinois.edu`
4. **Load blurbs** — merge with API data
5. **Load articles** — parse frontmatter + markdown bodies
6. **Estimate content fit** — warns if articles may overflow their grid regions
7. **Generate QR codes** (print mode only) — for all URLs in articles and LFTC
8. **Convert markdown → Typst** — regex-based conversion (headings, bold/italic, links, images, lists)
9. **Split multi-page articles** — at paragraph boundaries
10. **Merge image captions** — extract alt text from markdown for grid-mode images
11. **Write `data.json`** — all merged metadata for Typst
12. **Compile with Typst** — `typst compile typst/main.typ build/output/banks-{mode}.pdf`
13. **Check overflow** — queries Typst output for articles where content was clipped

## Theming

Visual constants are in `typst/lib/theme.typ`:

| Constant | Default | Description |
|---|---|---|
| `page-width` / `page-height` | US Letter (8.5×11in) | Page dimensions |
| `margin-x` / `margin-y` | 0.5in | Page margins |
| `heading-font` / `body-font` | Georgia | Font families |
| `body-size` | 9pt | Body text size |
| `article-title-size` | 14pt | Article title size |
| `headline-size` | 28pt | Title page headline size |
| `section-heading-size` | 16pt | Section heading size |
| `small-size` | 7pt | Captions, bylines |
| `link-color` | `#0645AD` | Online mode link color |
| `rule-color` | `#333333` | Horizontal/vertical rule color |

## Validation & Warnings

The build system performs extensive validation:

- **Layout validation**: cell bounds, contiguity (flood-fill), rectangular images, image cells ⊂ article cells, no article/image cell overlaps
- **File existence**: checks that article `.md` files and image `src` files exist
- **Content overflow**: pre-compilation heuristic estimate + post-compilation Typst `measure()`-based detection. Warns when article content is clipped
- **Directory validation**: warns if API orgs are missing blurb files, errors if `directory_order` slugs don't match API orgs

## Title Page

The title page is constrained to exactly one page and contains:

1. **Banner** — ACM logo, Banks logo, "Urbana, IL"
2. **Subtitle** — publication tagline
3. **Info bar** — Volume/Issue (left), date (center), URL (right)
4. **Headline** — large bold text from `config.headline`
5. **Letter from the Chair** — title, author, and body from `lftc.md`
6. **Table of Contents** — auto-generated with dot leaders and page numbers
7. **Upcoming Events** — from `events.yaml`
8. **Footer** — "Get Featured in Banks!" box + editors list

## Article Formatting

Each article renders with:
- Title in bold heading font
- Author byline in italic
- Horizontal rule separator
- Body text in justified columns
- Double rule (two thin lines) at the end of the article

Articles end with a double rule on their last page. Multi-page articles show continuation markers.
