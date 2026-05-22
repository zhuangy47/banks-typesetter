# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A typesetting pipeline that compiles markdown articles + YAML config + live ACM@UIUC org data into a PDF newspaper ("Banks of the Boneyard") via Typst. Two render modes:
- **online** — links become clickable `#link()` (blue, underlined)
- **print** — links render as plain text followed by a QR code + tiny URL caption

## Commands

```bash
make setup          # create .venv and pip install requirements.txt (sentinel: .venv/.installed)
make all            # build both modes
make online         # build online only
make print          # build print only
make strict         # print mode with --strict (content overflow becomes a fatal error)
make online-debug   # online build with grid lines / bounding-box / overflow overlays
make print-debug    # print build with debug overlays
make ui             # Flask layout editor on http://localhost:3000
make clean          # rm -rf build/
```

Direct invocation: `.venv/bin/python build.py --mode online|print|both [--strict] [--debug]`

Outputs: `build/output/banks-<mode>.pdf` (debug builds: `banks-<mode>-debug.pdf`).

There is no test suite. Verify changes by building and inspecting the PDF (`open build/output/banks-online.pdf`); use the `*-debug` targets to see how the grid engine placed things.

**Requirements:** Python 3.10+ (the code uses `str | None` / `dict[...]` annotations), the `typst` CLI on PATH (must support `context`, `measure`, and `metadata`/`query`), the Georgia font (see `typst/lib/theme.typ`), and the packages in `requirements.txt` (pyyaml, requests, qrcode[pil], flask).

## Architecture: two stages joined by `build/data.json`

1. **`build.py` (Python orchestrator)** — loads YAML config, fetches org data from the ACM Core API, converts each markdown body to a Typst fragment via regex, generates QR codes (print mode), and writes `build/data.json` + `build/articles/<slug>.typ` + `build/lftc.typ`. Then it shells out to `typst compile`, and afterward runs `typst query <overflow>` to report content that didn't fit.
2. **`typst/main.typ` + `typst/lib/*` (renderer)** — reads `/build/data.json`, then lays out the title page, article pages, directory, and optional horoscope. `main.typ` receives `mode` and `debug` via `--input`. `typst/lib/grid-engine.typ` is the heart of layout (absolute placement, image placement, column flow, overflow metadata); `article-page.typ` orchestrates per-article rendering; `theme.typ` holds all design tokens.

Everything in `build/` is generated and gitignored.

## Per-mode layouts

`build.py` loads `layout-<mode>.yaml` (e.g. `layout-online.yaml`, `layout-print.yaml`), falling back to `layout.yaml` if the mode-specific file is missing. Online and print can therefore differ (print typically reflows to leave room for QR codes). The web UI reads/writes the mode-specific file. Keep all three files' `grid:` blocks consistent unless you intend them to differ.

## Grid coordinate convention (the #1 gotcha)

The grid size is **not fixed** — it comes from the layout file's `grid:` block (`rows`, `columns`, `gutter`, `text_gutter`); the layouts currently use **24 rows × 6 columns**. The `default-grid` in `grid-engine.typ` is only a fallback and is overridden per-render.

Cell specs in the layout YAML are **row-major and 0-indexed**, origin top-left, ranges inclusive:
- single cell: `[row, col]`
- rectangle: `[[row_start, col_start], [row_end, col_end]]`

Both `build.py` (`_expand_cells`) and the Typst engine (`cells-bbox`, `expand-cell-specs`) internally flip these to `(col, row)` tuples. When editing either side, remember the YAML is `[row, col]` but the internal math is `(col, row)`.

A placement's `page` is the article-page number (1-based). It is offset by the title page in the final PDF, which is why "Continued on page N" markers in `article-page.typ` add 1.

## How articles flow onto pages

`build.py` writes the **entire** article body to a single `.typ` fragment — it does **not** pre-split multi-page articles. Pagination, column flow, and splitting all happen in Typst at measurement time:

- `article-page.typ` picks a renderer per placement. If `build.py` attached `text_columns` to the placement (it does this only for genuinely non-rectangular / staggered cell shapes, via `compute_text_columns`), it uses `place-article-columns` (independent per-column atom flow). Otherwise it uses `place-article-text` (Typst `columns()`).
- For multi-page articles, the engine decomposes the body into word-level "atoms," binary-searches the max that fits on each page, and coordinates page boundaries by emitting/reading `<article-consumed>` metadata across `query` passes.
- When content still overflows, the engine emits a `[#metadata(...) <overflow>]` label. `build.py`'s `_check_typst_overflow` queries these and warns; `--strict` turns overflow into a non-zero exit.

## Markdown → Typst conversion (`md_to_typst` in build.py)

Line-based regex conversion. Beyond the usual headings / bold / italic / lists / links, note:
- **Grid-placed images are stripped from the body** (they're positioned absolutely by the grid engine). Inline images stay and are centered, with `scale`/`border` taken from the layout entry.
- **Markdown HTML-comment markers** let you nudge print layout without affecting how the same source renders on the website: `<!-- break -->` → `#v(1em)`, `<!-- vspace 1.5em -->` → `#v(1.5em)`, `<!-- colbreak -->` → `#colbreak()`.
- In print mode, links become text + a QR image (filename is `md5(url)[:12].png`) + a tiny URL caption.
- `@` is escaped to `\@` because Typst uses `@` for references.

## Content & config files

- `config.yaml` — publication metadata + `directory_order` (controls org ordering in the directory).
- `events.yaml` — events on the title page.
- `articles/<slug>.md` — article; frontmatter `title` + `authors`. Body images live in `articles/images/`.
- `lftc.md` — Letter from the Chair; frontmatter `author` (singular).
- `horoscope.yaml` — optional; if present, a horoscope page is appended.
- `blurbs/<slug>.yaml` — per-org `blurb` + `meeting_times`, merged with API data.
- `logo/<slug>.{png,jpg,jpeg,svg}` — org logos (extension auto-detected).

## Directory data (ACM Core API)

Org data is fetched from `https://core.acm.illinois.edu/api/v1/organizations` at build time and merged with local `blurbs/` + `logo/`. API names are mapped to slugs by `normalize_org_slug` (an explicit `slug_map` plus a lowercase fallback). A failed API fetch is non-fatal (build continues with empty org data). A `directory_order` slug with no matching API org is reported but non-fatal.

**Adding an org** generally means: an entry in `slug_map` (if the name doesn't auto-derive), a `blurbs/<slug>.yaml`, a `logo/<slug>.*`, and a line in `config.yaml` `directory_order`.

**Adding an article** means: `articles/<slug>.md`, plus a matching `slug` with `placements` in the relevant `layout-*.yaml`. Layout validation (`validate_layout`) is strict and fails the build on: out-of-bounds cells, non-contiguous article cells, non-rectangular image cells, cells shared between two articles/images, missing image/article files, and a `column_width` that doesn't divide the article's width.

## Web UI (`ui/app.py`)

Flask app (`make ui`, port 3000) — a visual grid editor that reads/writes the per-mode layout, config, events, articles (CRUD), LFTC, and image uploads, and can trigger builds asynchronously and serve the resulting PDFs. It serializes layout YAML with its own `serialize_layout` (not `yaml.dump`) to keep the project's formatting; if you change the layout schema, update that function too.
