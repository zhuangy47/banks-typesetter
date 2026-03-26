# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Banks of the Boneyard is the newspaper/journal of ACM@UIUC. This repo is a typesetting pipeline that transforms markdown articles, YAML configuration, and organization data into a professionally formatted PDF newspaper using Typst.

Two render modes: **online** (clickable hyperlinks) and **print** (plain text links with inline QR codes).

## Build Commands

```bash
make setup          # Create .venv and install Python deps
make all            # Build both online and print PDFs
make online         # Build online PDF only
make print          # Build print PDF only
make clean          # Remove build/ directory
```

Output: `build/output/banks-online.pdf` and `build/output/banks-print.pdf`

Direct invocation: `.venv/bin/python build.py --mode online|print|both`

### Requirements

- Python 3.10+
- Typst 0.14+ on PATH
- Python packages: pyyaml, requests, qrcode[pil]

## Architecture

The build is a two-stage pipeline:

1. **`build.py`** (Python) — orchestrates everything: loads YAML config, validates layout, fetches org data from ACM Core API (`core.acm.illinois.edu`), converts markdown to Typst markup via regex, splits multi-page articles, generates QR codes (print mode), and writes `build/data.json` + converted `.typ` fragments into `build/`.

2. **`typst/main.typ`** (Typst) — reads `build/data.json` and the generated fragments, then renders the final PDF. Delegates to modules in `typst/lib/`:
   - `theme.typ` — fonts, sizes, colors, page dimensions
   - `grid-engine.typ` — converts grid coordinates to absolute positions
   - `title-page.typ` — title page layout
   - `article-page.typ` — article rendering with multi-column support
   - `directory.typ` — organization directory section
   - `horoscope.typ` — optional horoscope section

## Key Data Flow

- `config.yaml` — publication metadata (volume, issue, editors, directory_order)
- `events.yaml` — upcoming events for title page
- `layout.yaml` — grid-based article/image placement DSL (12x6 grid per page)
- `articles/*.md` — markdown with YAML frontmatter (title, authors)
- `lftc.md` — letter from the chair (single author)
- `blurbs/<slug>.yaml` — org descriptions, meeting times, status
- `logo/<slug>.{png,jpg,svg}` — org logos
- All merged into `build/data.json` which Typst consumes

## Layout System

Each article page is a **12 rows x 6 columns** grid. Articles specify cell ranges in `layout.yaml`. The build validates: cell bounds, contiguity (flood-fill), rectangular images, no cell overlaps between articles/images. Images can be `grid` mode (positioned at cells, removed from markdown) or `inline` mode (stays in markdown flow).

## Markdown-to-Typst Conversion

`build.py` contains a regex-based markdown-to-Typst converter (`md_to_typst`). It handles headings, bold/italic, links, images, lists, and `<br/>` tags. In print mode, links get QR code images and small-text URLs. Grid-positioned images are stripped from the markdown body.

## Organization Data

Org data is fetched from the ACM Core API at build time and merged with local `blurbs/*.yaml` files. The `directory_order` list in `config.yaml` must include every org from the API or the build will error.
