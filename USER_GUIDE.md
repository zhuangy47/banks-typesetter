# Banks of the Boneyard — Editor's Guide

This guide is for the people who put together an issue of *Banks of the Boneyard*: writing and placing articles, setting the masthead, and producing the final PDFs. You don't need to understand the code — just how to edit a handful of files (or use the web editor) and run a build.

If you want to know *how the machinery works*, see `ARCHITECTURE.md`. This guide is about *getting an issue out the door*.

---

## Contents

1. [What you're producing](#1-what-youre-producing)
2. [One-time setup](#2-one-time-setup)
3. [Two ways to work](#3-two-ways-to-work)
4. [Anatomy of an issue (which file controls what)](#4-anatomy-of-an-issue)
5. [Issue settings — `config.yaml`](#5-issue-settings--configyaml)
6. [The title page: events & the letter](#6-the-title-page-events--the-letter)
7. [Writing articles](#7-writing-articles)
8. [Laying out the pages](#8-laying-out-the-pages)
9. [Adding images](#9-adding-images)
10. [The organization directory](#10-the-organization-directory)
11. [Building the PDFs](#11-building-the-pdfs)
12. [Making sure everything fits](#12-making-sure-everything-fits)
13. [Using the web editor](#13-using-the-web-editor)
14. [Starting a fresh issue — checklist](#14-starting-a-fresh-issue--checklist)
15. [Troubleshooting](#15-troubleshooting)

---

## 1. What you're producing

Each build produces a print-ready PDF newspaper. There are **two editions** of every issue:

- **Online** — links are clickable and shown in blue. Meant for reading on a screen / sharing the PDF.
- **Print** — links can't be clicked on paper, so each one is shown as plain text with a small **QR code** and the URL beneath it.

A finished issue is laid out like a newspaper:

- a **title page** (masthead, headline, Letter from the Chair, table of contents, upcoming events, editor credits),
- one or more **article pages**, and
- an **organization directory** of ACM@UIUC groups (and an optional horoscope page).

You control all of this by editing text files (or using the web editor) and running a build.

---

## 2. One-time setup

You need:

- **Python 3.10 or newer**
- **Typst** (the `typst` command must be installed and on your `PATH`) — see https://typst.app
- The **Georgia** font installed on your machine (it's the newspaper's typeface; without it the text will look wrong)

Then, from the project folder, install the Python helpers once:

```bash
make setup
```

That's it. You won't normally need to run it again — the other build commands run it for you if anything changes.

> You also need an **internet connection when you build**: the organization directory is pulled live from the ACM@UIUC API each time. If you're offline the build still succeeds, just with an empty directory.

---

## 3. Two ways to work

You can edit an issue either way, and mix and match:

- **Edit the files directly** and run builds from the terminal. This is the source of truth and what the rest of this guide mostly shows.
- **Use the web editor** (`make ui`, then open http://localhost:3000). It gives you a visual grid for placing articles, forms for the masthead and events, an article editor, and buttons to build and preview. See [Section 13](#13-using-the-web-editor).

Both read and write the same files, so anything you do in one shows up in the other.

---

## 4. Anatomy of an issue

Here's where each part of the printed paper comes from:

| File / folder | Controls |
|---|---|
| `config.yaml` | Volume, issue, date, headline, subtitle, URL, editor names, "Get Featured" email, and the directory order |
| `events.yaml` | The "Upcoming Events" box on the title page |
| `lftc.md` | The "Letter from the Chair" on the title page |
| `articles/<name>.md` | One article (its title, authors, and body text) |
| `articles/images/` | Image files used by articles |
| `layout-online.yaml` / `layout-print.yaml` | Where each article and image sits on each page, for each edition |
| `blurbs/<org>.yaml` | An org's description and meeting times in the directory |
| `logo/<org>.png` | An org's logo in the directory and on the banner |
| `horoscope.yaml` *(optional)* | Adds a horoscope page if present |

The **table of contents** and the **"Continued on page…"** markers are generated automatically — you don't write them.

---

## 5. Issue settings — `config.yaml`

This is the masthead and the per-issue metadata. Open `config.yaml` and update the top fields for the new issue:

```yaml
volume: 43
issue: 1
date: "November 11, 2025"
headline: "TYPST LEADS UPRISING AGAINST LaTeX; ESTABLISHED ORDER COLLAPSES"
subtitle: "The Journal of the Association for Computing Machinery at the University of Illinois Urbana-Champaign"
url: "banks.acm.illinois.edu"

editors:
  - "Yanni Zhuang"
  - "Minh Duong"

featured_email: "banks@acm.illinois.edu"
```

Notes:

- **`headline`** prints exactly as you type it. If you want it in ALL CAPS (the usual newspaper look), type it in caps.
- **`date`** is automatically shown in uppercase on the title page — type it normally.
- **`editors`** appear in the "Editors" box in the title-page footer.
- **`featured_email`** appears in the "Get Featured in Banks!" box.
- **`directory_order`** (the long list at the bottom) controls the order organizations appear in the directory. You normally won't touch this unless ACM adds or removes a group — see [Section 10](#10-the-organization-directory).

---

## 6. The title page: events & the letter

### Upcoming Events — `events.yaml`

Each entry becomes one item in the "Upcoming Events" box. Only `name` and `date` are required:

```yaml
events:
  - name: "Weekly Social Hour"
    date: "Every Friday"
    time: "5:00 PM - 6:00 PM"     # optional
    location: "Siebel CS 1404"     # optional
    description: "Come hang out!"  # optional
```

### Letter from the Chair — `lftc.md`

This is a short markdown file with the author's name in the frontmatter and the letter body below:

```markdown
---
author: Jacob Levine
---

Dear members,

Welcome back to another semester...
```

> **Important:** the letter uses a single **`author:`** field (not the `authors:` list that articles use). If the letter prints with no author name, this is almost always the cause.

The letter supports the same formatting as articles (see next section).

---

## 7. Writing articles

Each article is one markdown file in `articles/`. The **file name (without `.md`) is the article's "slug"** — you'll use it again when you lay out the page. For example, `articles/robotics.md` has the slug `robotics`.

Start every article with frontmatter (the part between the `---` lines) giving the title and authors, then write the body:

```markdown
---
title: "SIG Robotics Builds a Better Boneyard"
authors:
  - "Jane Hacker"
  - "Sam Coder"
---

Article body goes here. You can use standard markdown.

## A subheading

**Bold**, *italic*, and ***bold italic*** all work, as do
[links](https://acm.illinois.edu).

- bullet lists
- like this

1. and numbered
2. lists too
```

### Formatting you can use

| You write | You get |
|---|---|
| `# Heading` … `###### Heading` | Headings (six levels) |
| `**bold**` | **bold** |
| `*italic*` | *italic* |
| `***bold italic***` | ***bold italic*** |
| `[text](https://url)` | A link (clickable online; QR code in print) |
| `![caption](images/photo.jpg)` | An image with the alt text used as its caption |
| `- item` or `* item` | Bullet list |
| `1. item` | Numbered list |
| `<br/>` | A small vertical gap |

### Fine-tuning the print layout without affecting the website

Because the same article text may also be published on the website, there are a few **invisible markers** (HTML comments) that only affect the typeset PDF — they vanish in normal markdown rendering:

| You write | Effect in the PDF |
|---|---|
| `<!-- break -->` | One blank line of vertical space |
| `<!-- vspace 1.5em -->` | A custom amount of vertical space |
| `<!-- colbreak -->` | Pushes the following text into the next column |

Use these sparingly to nudge things when an article is *almost* fitting nicely.

> Tip: an article file with no placement in the layout simply won't appear in the paper — no error. So you can draft articles freely and only place them when they're ready.

---

## 8. Laying out the pages

Layout is where you decide which article goes where. Each **edition has its own layout file** so print and online can differ if you need them to:

- `layout-online.yaml` — the online edition
- `layout-print.yaml` — the print edition (often needs a bit more room for QR codes)

If you only keep one layout, you can use `layout.yaml` and both editions will use it. **A common workflow is to lay out one edition, then copy it to the other and adjust** (the web editor has a "Copy to other mode" button for exactly this).

### The page grid

Every article page is divided into a grid of **rows and columns** (currently **24 rows tall, 6 columns wide**). You place things by naming the grid cells they occupy.

Cells are written as **`[row, column]`**, both starting at `0` in the **top-left** corner:

- A single cell: `[3, 2]` → row 3, column 2.
- A rectangle (corners included): `[[0, 0], [9, 5]]` → rows 0–9, columns 0–5 (the top ~40% of the page, full width).

```
        col 0   col 1   col 2   col 3   col 4   col 5
row 0   ┌─────────────────────────────────────────────┐
        │  [[0,0],[9,5]]  → top of the page, full width │
row 9   └─────────────────────────────────────────────┘
row 10  ┌──────────────────────┐┌─────────────────────┐
        │  left half            ││  right half          │
row 23  └──────────────────────┘└─────────────────────┘
```

### Placing an article

Each article you want in the paper gets an entry under `articles:` in the layout file. The `slug` must match the article's file name.

```yaml
articles:
  - slug: robotics            # ↔ articles/robotics.md
    column_width: 2           # how wide each text column is, in grid columns
    full_width_header: true   # title/byline span the whole article, above the columns
    placements:
      - page: 1
        cells:
          - [[10, 2], [23, 3]]   # lower-middle of page 1
```

- **`page`** numbers start at 1 for the first article page. (The title page is separate; in the final PDF it's page 1, so article "page 1" is the second physical page. The table of contents shows the physical page numbers automatically.)
- **`column_width`** sets how many grid columns make up one text column. The number of text columns is the article's width divided by `column_width`. Example: an article 6 columns wide with `column_width: 3` gets **2 text columns**; with `column_width: 2` it gets **3 columns**.

### Per-article options

All optional, set alongside `slug`:

| Option | Default | What it does |
|---|---|---|
| `full_width_header` | `false` | Title + byline span the full article width, above the columns (good for featured pieces) |
| `full_width_footer` | `false` | The closing rule / "continued" note spans the full width instead of sitting under the last column |
| `column_separator` | `false` | Draws thin vertical rules between text columns |
| `show_border` | `false` | Draws an outline around the whole article |
| `column_gap` | grid default | Overrides the spacing between text columns (e.g. `column_gap: 12pt`) |

### Spanning an article across pages

Give it more than one placement. The system flows the text to fill each page automatically and adds "Continued on page N" / "Continued from page N" markers for you:

```yaml
  - slug: rparticle
    column_width: 2
    full_width_header: true
    placements:
      - page: 1
        cells:
          - [[10, 4], [23, 5]]   # starts in a corner of page 1
      - page: 3
        cells:
          - [[0, 0], [16, 5]]    # continues on page 3
```

You don't split the text yourself — write the whole article in one file and let the layout decide how much lands on each page.

### Non-rectangular (L-shaped) articles

An article's cells don't have to be a simple rectangle. List several cell ranges to make an L-shape or step, e.g. to wrap around an image. The text flows into the columns correctly even when they're different heights:

```yaml
    placements:
      - page: 2
        cells:
          - [[0, 0], [11, 1]]   # tall left column
          - [[0, 2], [5, 3]]    # shorter middle column
```

---

## 9. Adding images

First, put the image file in **`articles/images/`**. Then choose one of two ways to place it.

### Inline images (flow with the text)

An inline image appears right where you reference it in the article body. Declare it at the **article level** (next to `slug`, not inside a placement):

```yaml
  - slug: icpc
    column_width: 2
    images:                  # article-level = inline
      - src: icpc.jpg
        scale: 70            # width as a % of the column (default 100)
        border: 1            # outline thickness in pt; use 0 for none
    placements:
      - page: 1
        cells:
          - [[10, 0], [23, 1]]
```

In the article body, reference it normally — the alt text becomes the caption:

```markdown
![Left to right: the ICPC team at regionals](images/icpc.jpg)
```

### Grid images (pinned to specific cells)

A grid image is placed at exact grid cells (and **removed** from the text flow, so the words wrap around it). Declare it **inside a placement**:

```yaml
    placements:
      - page: 2
        cells:
          - [[11, 0], [23, 5]]
        images:                       # inside a placement = grid
          - src: QiskitFallFest.png
            cells:
              - [[20, 4], [23, 5]]    # bottom-right corner of the article
            caption: "Qiskit Fall Fest 2025"   # optional
            x-alignment: center       # left | center | right
            y-alignment: center       # left | center | right
            border: 1
```

- Grid-image cells must form a **rectangle**.
- If you don't give a `caption`, the alt text from the matching `![...]()` in the markdown is used.

**Rule of thumb:** use *inline* for images that should sit in the reading flow, and *grid* for photos you want anchored to a corner or column with text wrapping around them.

---

## 10. The organization directory

The directory at the back lists ACM@UIUC organizations. Most of it is **automatic**: each org's name, leadership, website, email, and social links come live from the ACM@UIUC system at build time. You usually don't touch this between issues.

What lives in this repo and you *can* edit:

- **`blurbs/<org>.yaml`** — the description and meeting times shown for an org:

  ```yaml
  status: active
  meeting_times:
    - date: thursday          # lowercase day name
      start_time: "18:00"     # "HH:MM" (or minutes past midnight, e.g. 1080)
      end_time: "19:00"
      location: Siebel CS 1302
  blurb: >
    A one-paragraph description of the org that appears
    under its name in the directory.
  ```

- **`logo/<org>.png`** — the org's logo (`.jpg`, `.jpeg`, or `.svg` also work).
- **`directory_order`** in `config.yaml` — the order orgs appear in.

If ACM adds a new org, create its `blurbs/<slug>.yaml` and `logo/<slug>.png`, and add the slug to `directory_order`.

---

## 11. Building the PDFs

From the project folder:

| Command | What it does |
|---|---|
| `make all` | Build both editions |
| `make online` | Build the online edition only |
| `make print` | Build the print edition only |
| `make online-debug` | Online build with layout guides drawn on top (see below) |
| `make print-debug` | Print build with layout guides |
| `make clean` | Delete the generated files and start fresh |

The finished PDFs land in **`build/output/`**:

- `build/output/banks-online.pdf`
- `build/output/banks-print.pdf`
- (and `banks-online-debug.pdf` / `banks-print-debug.pdf` from the debug builds)

Open one to take a look — for example, on macOS:

```bash
make all
open build/output/banks-online.pdf
```

---

## 12. Making sure everything fits

The most common layout problem is **overflow**: an article has more text than the cells you gave it, so the end gets cut off.

The build warns you when this happens. Watch the output for lines like:

```
WARNING: [print] Article 'robotics' content overflows (needs ..., allocated ...)
```

To *see* exactly where it's overflowing, run a **debug build**:

```bash
make online-debug
open build/output/banks-online-debug.pdf
```

The debug PDF draws the grid and outlines each article's regions, and marks any overrun with a **red band labelled `OVERFLOW`** at the column that didn't fit. That tells you precisely how much is over and where.

**Ways to fix overflow:**

- Give the article more cells (make it taller or wider).
- Use a smaller `column_width` so it gets more, narrower columns.
- Trim the text.
- Spread the article across an extra page.
- Nudge with `<!-- colbreak -->` or a smaller image `scale`.

> Want the build to *fail* if anything overflows (useful for a final pass)? Run `make strict` — it builds the print edition and exits with an error if any article is over.

---

## 13. Using the web editor

If you'd rather work visually:

```bash
make ui
```

Then open **http://localhost:3000**. There are four tabs:

- **Layout** — the visual grid. Pick the edition (Online / Print) at the top, choose a page, then use the tools:
  - **Draw** an article's cells by dragging on the grid,
  - **Image** to drop a grid image into cells,
  - **Eraser** to clear cells.
  Add articles to the page from the **Articles** palette (the `+` button), edit a selected article's options in the **Properties** panel on the right, add/remove pages, and **Save Layout** when done. "Copy to other mode" duplicates this edition's layout to the other one.
- **Articles** — list, create (`+ New`), and edit articles; also **Edit LFTC** for the Letter from the Chair.
- **Config & Events** — forms for the masthead fields (volume, issue, date, headline, subtitle, URL, featured email, editors) and the events list.
- **Build** — buttons to build Online / Print / Both (and the debug variants), a live build log, and an in-browser PDF preview.

Everything you save here writes the same files described above, so you can switch between the editor and hand-editing freely.

---

## 14. Starting a fresh issue — checklist

1. **Bump the masthead** in `config.yaml`: `volume`, `issue`, `date`, `headline`, and `editors`.
2. **Update the Letter from the Chair** (`lftc.md`).
3. **Refresh `events.yaml`** with the events you want featured.
4. **Add the new articles** as `articles/<slug>.md`, with images dropped in `articles/images/`.
5. **Lay them out**: place each article (and its images) in `layout-online.yaml` and `layout-print.yaml`.
6. **Build and review**: `make all`, then open the PDFs.
7. **Check the fit**: resolve any overflow warnings (use `make online-debug` / `make print-debug` to see them).
8. **Final pass**: `make strict` to confirm nothing overflows; eyeball both editions one more time.
9. The directory and table of contents take care of themselves.

---

## 15. Troubleshooting

**The build stops with a layout error.** The layout is checked before rendering, and these errors must be fixed before it will build:

| Message (roughly) | What it means / fix |
|---|---|
| `references article 'X' but no .md file found` | The layout has a `slug` with no matching `articles/X.md`. Create the file or remove the entry. |
| `cell (c,r) out of bounds (grid is 6x24)` | A cell is outside the grid. Remember cells are `[row, column]`, and rows go 0–23, columns 0–5. |
| `cells are not contiguous` | An article's cells don't touch. Make them connect, or it's not one shape. |
| `cell (c,r) claimed by both 'A' and 'B'` | Two articles (or two images) overlap on the same cell. Move one. |
| `column_width N does not divide article width W` | The article's width isn't a multiple of `column_width`. Adjust one of them. |
| `image 'X': file not found` | The image isn't in `articles/images/`. Add it (check the spelling). |
| `cells are not rectangular` | A grid image's cells must form a rectangle. |

**An article doesn't appear.** It probably has no placement in the layout for the edition you built. Add it under `articles:` in `layout-online.yaml` / `layout-print.yaml`.

**The end of an article is cut off.** That's overflow — see [Section 12](#12-making-sure-everything-fits).

**The Letter from the Chair shows no author.** Make sure `lftc.md` uses `author:` (singular) in its frontmatter.

**Links show no QR codes in the print edition.** QR generation needs the `qrcode` package; re-run `make setup`. (The build still succeeds without it — links just fall back to plain text.)

**The directory is empty.** The org data is fetched live at build time; you were probably offline. Reconnect and rebuild.

**The text looks wrong / the wrong font.** Install the **Georgia** font, then rebuild.

**Online and print look out of sync.** They use separate layout files. Update both `layout-online.yaml` and `layout-print.yaml` (or use the web editor's "Copy to other mode").
