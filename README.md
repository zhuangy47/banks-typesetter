# Banks of the Boneyard

The typesetting pipeline for *Banks of the Boneyard*. It turns Markdown articles, a handful of YAML files, and live organization data into a print-ready PDF newspaper using [Typst](https://typst.app).

Every issue is produced in two editions:

- **Online** — links are clickable (blue/underlined).
- **Print** — each link is shown as plain text with a QR code and the URL beneath it.

## Quick start

```bash
make setup                       # one-time: create .venv and install deps
make all                         # build both editions
open build/output/banks-online.pdf
```

| Command | Builds |
|---|---|
| `make all` | Both editions |
| `make online` / `make print` | One edition |
| `make online-debug` / `make print-debug` | With layout overlays (grid, regions, overflow bands) |
| `make strict` | Print edition; **fails** if any article overflows its space |
| `make ui` | The web editor at http://localhost:3000 |
| `make clean` | Delete generated files |

Finished PDFs land in `build/output/` (`banks-online.pdf`, `banks-print.pdf`).

## Requirements

- **Python 3.10+**
- **Typst 0.14+** — the `typst` command must be on your `PATH`
- The **Georgia** font (the newspaper's typeface)
- An **internet connection at build time** — the organization directory is fetched live from the ACM@UIUC API (the build still succeeds offline, just with an empty directory)

`make setup` installs the Python dependencies (`pyyaml`, `requests`, `qrcode[pil]`, `flask`).

## Issues

Each issue's inputs live in their own folder under `issues/`:

```
issues/vol43-iss1/
  config.yaml          # masthead: volume, issue, date, headline, editors, directory order
  events.yaml          # "Upcoming Events" box on the title page
  lftc.md              # Letter from the Chair
  layout-online.yaml   # where each article/image sits — online edition
  layout-print.yaml    # ...and the print edition (both required)
  articles/*.md        # the articles (markdown with a title/authors header)
  articles/images/     # their images
```

Builds use the most-recently-modified issue folder by default, or you can name one:

```bash
make all ISSUE=vol43-iss1
make new-issue ISSUE=vol43-iss2     # scaffold a new issue from issues/_template/
```

Shared across all issues (at the repo root): the organization directory data
(`blurbs/*.yaml`, `logo/*`) and the build engine (`build.py`, `typst/`, `ui/`).

You can edit an issue's files directly, or use the visual **web editor** (`make ui`) to place articles on a grid, edit the masthead and articles, and build/preview — it reads and writes the same files.

## Documentation

- **[USER_GUIDE.md](USER_GUIDE.md)** — for editors putting together an issue: writing articles, laying out pages, adding images, building, and fixing overflow. **Start here if you're producing an issue.**
- **[ARCHITECTURE.md](ARCHITECTURE.md)** — how the build pipeline and the Typst rendering engine work, end to end.
