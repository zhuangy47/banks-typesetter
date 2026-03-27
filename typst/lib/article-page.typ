// Article page rendering using grid engine

#import "theme.typ": *
#import "grid-engine.typ": *

// Find all pages an article spans
#let article-pages(layout-data, slug) = {
  let pages = ()
  for article in layout-data.articles {
    if article.slug == slug {
      for placement in article.placements {
        pages.push(placement.page)
      }
    }
  }
  pages
}

// Render a single article page with all its articles
#let render-article-page(page-num, layout-data, articles-data, mode, debug: false) = {
  let grid-raw = layout-data.grid
  let grid-config = (
    cols: grid-raw.columns,
    rows: grid-raw.rows,
    gutter: eval(str(grid-raw.gutter)),
    text-gutter: eval(str(grid-raw.text_gutter)),
  )
  let page-articles = ()

  // Find all articles on this page
  for article in layout-data.articles {
    for placement in article.placements {
      if placement.page == page-num {
        page-articles.push((
          slug: article.slug,
          column-width: article.column_width,
          placement: placement,
          all-placements: article.placements,
          full-width-header: article.at("full_width_header", default: false),
          full-width-footer: article.at("full_width_footer", default: false),
          column-gap: article.at("column_gap", default: none),
          column-separator: article.at("column_separator", default: false),
          show-border: article.at("show_border", default: false),
        ))
      }
    }
  }

  if page-articles.len() == 0 {
    return
  }

  // Render each article on the page
  for art in page-articles {
    let slug = art.slug
    let article-info = articles-data.at(slug, default: none)
    if article-info == none { continue }

    let placement = art.placement
    let cells = placement.cells
    let all-images = placement.at("images", default: ())
    let column-width = art.column-width

    // Filter to only grid-mode images (inline images are handled in the .typ body)
    let grid-images = all-images.filter(img => img.at("mode", default: "grid") == "grid")

    // Determine if this is a multi-page article and which page we're on
    let all-pages = art.all-placements.map(p => p.page)
    let page-index = all-pages.position(p => p == page-num)
    let is-first-page = page-index == 0
    let is-last-page = page-index == all-pages.len() - 1
    let is-multi-page = all-pages.len() > 1

    // Check for non-rectangular layout
    let text-columns = placement.at("text_columns", default: none)

    // Prepare image data for layout functions (which handle header conflicts)
    let img-data = grid-images.map(img => (
      cells: img.cells,
      path: "/articles/images/" + img.src,
      caption: img.at("caption", default: none),
      x-alignment: img.at("x-alignment", default: "center"),
      y-alignment: img.at("y-alignment", default: "center"),
      border: img.at("border", default: 1),
    ))

    // Determine if we use full-width header (only on first page)
    let use-full-header = art.full-width-header and is-first-page

    // Build header content
    let header-content = {
      if is-first-page {
        text(size: article-title-size, weight: "bold", font: heading-font)[
          #article-info.title
        ]
        if article-info.authors.len() > 0 {
          linebreak()
          v(0.1pt)
          text(size: small-size, style: "italic")[
            By #article-info.authors.join(", ")
          ]
        }
      } else {
        text(size: body-size + 2pt, weight: "bold", font: heading-font)[
          #article-info.title
        ]
        linebreak()
        text(size: small-size, style: "italic")[
          Continued from page #str(all-pages.at(page-index - 1) + 1)
        ]
      }
      v(6pt)
      block(spacing: 0pt, line(length: 100%, stroke: 0.5pt + rule-color))
      v(6pt)
    }

    // Resolve column gap
    let col-gap = if art.column-gap != none {
      eval(art.column-gap)
    } else {
      grid-config.text-gutter
    }

    // Raw article text (used by both paths)
    let raw-body = include("/build/articles/" + slug + ".typ")

    // Build body content (for rectangular path — text only, no footer)
    let body-content = {
      set text(size: body-size, font: body-font)
      show link: it => {
        if mode == "online" {
          underline(text(fill: link-color, it))
        } else {
          it
        }
      }

      raw-body
    }

    // Build footer content (placed separately so it stays visible on overflow)
    let rect-footer = {
      if is-last-page or not is-multi-page {
        v(6pt)
        block(spacing: 0pt, {
          set block(spacing: 0pt)
          line(length: 100%, stroke: 1pt + rule-color)
          v(2pt)
          line(length: 100%, stroke: 1pt + rule-color)
        })
      }
      if is-multi-page and not is-last-page {
        v(6pt)
        align(right,
          text(size: small-size, style: "italic")[
            Continued on page #str(all-pages.at(page-index + 1) + 1)
          ]
        )
      }
    }

    // --- Draw article border (encompasses article + contiguous images) ---
    if art.show-border {
      let combined-cells = cells
      let contiguous-img-idx = ()

      // Iteratively find images contiguous with article cells
      for _ in range(grid-images.len()) {
        for (idx, img) in grid-images.enumerate() {
          if not contiguous-img-idx.contains(idx) {
            if cells-are-adjacent(combined-cells, img.cells) {
              contiguous-img-idx.push(idx)
              combined-cells = combined-cells + img.cells
            }
          }
        }
      }

      // Draw border around article + contiguous images
      draw-cell-border(combined-cells, grid: grid-config)

      // Draw separate borders for non-contiguous images
      for (idx, _img) in grid-images.enumerate() {
        if not contiguous-img-idx.contains(idx) {
          draw-cell-border(_img.cells, grid: grid-config)
        }
      }
    }

    if text-columns != none {
      // --- Non-rectangular: atom-based column rendering ---
      // Footer content (placed at end of last column)
      let footer = {
        if is-last-page or not is-multi-page {
          v(6pt)
          block(spacing: 0pt, {
            set block(spacing: 0pt)
            line(length: 100%, stroke: 1pt + rule-color)
            v(2pt)
            line(length: 100%, stroke: 1pt + rule-color)
          })
        }
        if is-multi-page and not is-last-page {
          v(6pt)
          align(right,
            text(size: small-size, style: "italic")[
              Continued on page #str(all-pages.at(page-index + 1) + 1)
            ]
          )
        }
      }

      place-article-columns(
        text-columns,
        slug,
        header-content,
        raw-body,
        footer-content: footer,
        full-width-header: use-full-header,
        full-width-footer: art.full-width-footer,
        col-gap: col-gap,
        col-separator: art.column-separator,
        show-border: art.show-border,
        images: img-data,
        grid: grid-config,
        debug: debug,
      )
    } else {
      // --- Rectangular: place-article-text ---
      // For multi-page articles, always use full-width header so body
      // contains only article text (needed for atom-based page splitting).
      let separate-header = use-full-header or is-multi-page
      place-article-text(
        cells,
        grid-images,
        column-width,
        slug,
        if separate-header { header-content } else { none },
        if separate-header { body-content } else { header-content + body-content },
        footer-content: rect-footer,
        full-width-footer: art.full-width-footer,
        col-gap: col-gap,
        col-separator: art.column-separator,
        show-border: art.show-border,
        images: img-data,
        grid: grid-config,
        raw-body: if is-multi-page { raw-body } else { none },
        page-index: page-index,
        is-last-page: is-last-page,
        debug: debug,
      )
    }

    // Debug: draw article cell bounding box and image cell bounding boxes
    if debug {
      // Article cells — blue dashed outline
      draw-cell-border(cells, grid: grid-config, border-stroke: 1pt + rgb("#0066ff80"))
      // Slug label at top-left of article bbox
      let ab = cells-bbox(cells)
      let ar = cell-rect(ab.col-start, ab.row-start, ab.col-end, ab.row-end, grid: grid-config)
      place(top + left, dx: ar.x + 2pt, dy: ar.y + 2pt,
        block(fill: rgb("#0066ffcc"), inset: 2pt, radius: 2pt,
          text(size: 5pt, fill: white, weight: "bold")[#slug]
        )
      )
      // Grid-mode image cells — green dashed outline
      for img in grid-images {
        draw-cell-border(img.cells, grid: grid-config, border-stroke: 1pt + rgb("#00aa0080"))
        let ib = cells-bbox(img.cells)
        let ir = cell-rect(ib.col-start, ib.row-start, ib.col-end, ib.row-end, grid: grid-config)
        place(top + left, dx: ir.x + 2pt, dy: ir.y + 2pt,
          block(fill: rgb("#00aa00cc"), inset: 2pt, radius: 2pt,
            text(size: 4pt, fill: white)[img]
          )
        )
      }
    }
  }

  // Debug: draw grid cell outlines and row,col labels
  if debug {
    let cw = (content-width - (grid-config.cols - 1) * grid-config.gutter) / grid-config.cols
    let ch = (content-height - (grid-config.rows - 1) * grid-config.gutter) / grid-config.rows
    for r in range(grid-config.rows) {
      for c in range(grid-config.cols) {
        let x = c * (cw + grid-config.gutter)
        let y = r * (ch + grid-config.gutter)
        place(
          top + left,
          dx: x,
          dy: y,
          block(
            width: cw,
            height: ch,
            stroke: 0.25pt + rgb("#ff000040"),
          ),
        )
        place(
          top + left,
          dx: x + 1pt,
          dy: y + 1pt,
          text(size: 4pt, fill: rgb("#ff000080"))[#r,#c],
        )
      }
    }
  }
}

// Get max page number from layout
#let max-page(layout-data) = {
  let max-p = 0
  for article in layout-data.articles {
    for placement in article.placements {
      if placement.page > max-p {
        max-p = placement.page
      }
    }
  }
  max-p
}
