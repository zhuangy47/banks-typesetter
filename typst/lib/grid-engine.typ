// Grid Engine - converts grid coordinates to absolute positions
// Grid is columns × rows with gutter spacing

#import "theme.typ": *

// Default grid configuration (overridden by layout.yaml values at render time)
#let default-grid = (
  cols: 6,
  rows: 12,
  gutter: 4pt,
  text-gutter: 8pt,
)

// Convert grid coordinates to absolute position and size
// col-start, row-start, col-end, row-end are inclusive
#let cell-rect(col-start, row-start, col-end, row-end, grid: default-grid) = {
  let cw = (content-width - (grid.cols - 1) * grid.gutter) / grid.cols
  let ch = (content-height - (grid.rows - 1) * grid.gutter) / grid.rows
  let x = col-start * (cw + grid.gutter)
  let y = row-start * (ch + grid.gutter)
  let w = (col-end - col-start + 1) * (cw + grid.gutter) - grid.gutter
  let h = (row-end - row-start + 1) * (ch + grid.gutter) - grid.gutter
  (x: x, y: y, width: w, height: h)
}

// Get bounding box of a set of cells
// cells is an array of cell specs: either [row, col] or [[r0, c0], [r1, c1]]
#let cells-bbox(cells) = {
  let min-col = 999
  let min-row = 999
  let max-col = -1
  let max-row = -1

  for cell in cells {
    if type(cell.at(0)) == int {
      // Single cell [row, col]
      let r = cell.at(0)
      let c = cell.at(1)
      if c < min-col { min-col = c }
      if r < min-row { min-row = r }
      if c > max-col { max-col = c }
      if r > max-row { max-row = r }
    } else {
      // Rectangle [[r0, c0], [r1, c1]]
      let r0 = cell.at(0).at(0)
      let c0 = cell.at(0).at(1)
      let r1 = cell.at(1).at(0)
      let c1 = cell.at(1).at(1)
      if c0 < min-col { min-col = c0 }
      if r0 < min-row { min-row = r0 }
      if c1 > max-col { max-col = c1 }
      if r1 > max-row { max-row = r1 }
    }
  }

  (col-start: min-col, row-start: min-row, col-end: max-col, row-end: max-row)
}

// Place content at grid position
#let place-at-cells(cells, content, grid: default-grid) = {
  let bbox = cells-bbox(cells)
  let rect = cell-rect(bbox.col-start, bbox.row-start, bbox.col-end, bbox.row-end, grid: grid)
  place(
    top + left,
    dx: rect.x,
    dy: rect.y,
    block(
      width: rect.width,
      height: rect.height,
      clip: true,
      content,
    )
  )
}

// ── Cell Expansion & Adjacency ──────────────────────────────

// Expand cell specs into individual (col, row) position arrays.
// Input: array of cell specs ([row, col] or [[r0, c0], [r1, c1]])
// Output: array of (col, row) arrays (deduplicated)
#let expand-cell-specs(cells) = {
  let seen = (:)
  let unique = ()
  for cell in cells {
    if type(cell.at(0)) == int {
      // Single cell [row, col]
      let c = cell.at(1)
      let r = cell.at(0)
      let key = str(c) + "," + str(r)
      if key not in seen {
        seen.insert(key, true)
        unique.push((c, r))
      }
    } else {
      // Range [[r0, c0], [r1, c1]]
      let r0 = cell.at(0).at(0)
      let c0 = cell.at(0).at(1)
      let r1 = cell.at(1).at(0)
      let c1 = cell.at(1).at(1)
      for r in range(r0, r1 + 1) {
        for c in range(c0, c1 + 1) {
          let key = str(c) + "," + str(r)
          if key not in seen {
            seen.insert(key, true)
            unique.push((c, r))
          }
        }
      }
    }
  }
  unique
}

// Check if two cell spec sets share an edge (4-connected adjacency)
#let cells-are-adjacent(cells-a, cells-b) = {
  let set-b = (:)
  for p in expand-cell-specs(cells-b) {
    set-b.insert(str(p.at(0)) + "," + str(p.at(1)), true)
  }
  for p in expand-cell-specs(cells-a) {
    let c = p.at(0)
    let r = p.at(1)
    for d in ((0, 1), (0, -1), (1, 0), (-1, 0)) {
      let key = str(c + d.at(0)) + "," + str(r + d.at(1))
      if key in set-b { return true }
    }
  }
  false
}

// ── Border Drawing ──────────────────────────────────────────

// Draw a border outline around an arbitrary set of grid cells.
// Handles both rectangular and non-rectangular shapes by tracing
// the perimeter polygon, including through gutters at shape steps.
//
// Assumes each row has a single contiguous column range
// (valid for all contiguous shapes in practice).
#let draw-cell-border(cells, grid: default-grid, border-stroke: 0.5pt + rule-color) = {
  let positions = expand-cell-specs(cells)
  if positions.len() == 0 { return }

  // Cell dimension helpers
  let cw = (content-width - (grid.cols - 1) * grid.gutter) / grid.cols
  let ch = (content-height - (grid.rows - 1) * grid.gutter) / grid.rows
  let cell-left(c) = c * (cw + grid.gutter)
  let cell-right(c) = c * (cw + grid.gutter) + cw
  let cell-top(r) = r * (ch + grid.gutter)
  let cell-bottom(r) = r * (ch + grid.gutter) + ch

  // Build row -> (c-start, c-end) from occupied cells
  let min-row = calc.min(..positions.map(p => p.at(1)))
  let max-row = calc.max(..positions.map(p => p.at(1)))

  let row-data = ()
  for r in range(min-row, max-row + 1) {
    let cols-in-row = positions.filter(p => p.at(1) == r).map(p => p.at(0))
    if cols-in-row.len() > 0 {
      row-data.push((row: r, c-start: calc.min(..cols-in-row), c-end: calc.max(..cols-in-row)))
    }
  }
  if row-data.len() == 0 { return }

  // Simple rectangle: all rows have the same column range
  if row-data.len() == 1 or row-data.slice(1).all(rd => rd.c-start == row-data.first().c-start and rd.c-end == row-data.first().c-end) {
    let r = cell-rect(row-data.first().c-start, row-data.first().row, row-data.first().c-end, row-data.last().row, grid: grid)
    place(
      top + left,
      dx: r.x,
      dy: r.y,
      block(width: r.width, height: r.height, stroke: border-stroke),
    )
    return
  }

  // --- Non-rectangular: trace perimeter polygon ---

  // Right-side vertices (top to bottom)
  let right-verts = ()
  right-verts.push((cell-right(row-data.at(0).c-end), cell-top(row-data.at(0).row)))
  for i in range(1, row-data.len()) {
    let prev = row-data.at(i - 1)
    let curr = row-data.at(i)
    let pr = cell-right(prev.c-end)
    let cr = cell-right(curr.c-end)
    let pb = cell-bottom(prev.row)
    let ct = cell-top(curr.row)
    if cr < pr {
      // Narrowing: step inward
      right-verts.push((pr, pb))
      right-verts.push((cr, pb))
    } else if cr > pr {
      // Widening: step outward
      right-verts.push((pr, pb))
      if ct != pb { right-verts.push((pr, ct)) }
      right-verts.push((cr, ct))
    }
  }
  let last = row-data.last()
  right-verts.push((cell-right(last.c-end), cell-bottom(last.row)))

  // Left-side vertices (top to bottom)
  let left-verts = ()
  left-verts.push((cell-left(row-data.at(0).c-start), cell-top(row-data.at(0).row)))
  for i in range(1, row-data.len()) {
    let prev = row-data.at(i - 1)
    let curr = row-data.at(i)
    let pl = cell-left(prev.c-start)
    let cl = cell-left(curr.c-start)
    let pb = cell-bottom(prev.row)
    let ct = cell-top(curr.row)
    if cl > pl {
      // Narrowing: left edge moves right
      left-verts.push((pl, pb))
      left-verts.push((cl, pb))
    } else if cl < pl {
      // Widening: left edge moves further left
      left-verts.push((pl, pb))
      if ct != pb { left-verts.push((pl, ct)) }
      left-verts.push((cl, ct))
    }
  }
  left-verts.push((cell-left(last.c-start), cell-bottom(last.row)))

  // Assemble clockwise polygon: top-left → top-right → right down → bottom-left → left up
  let verts = ()
  verts.push(left-verts.at(0))
  verts.push(right-verts.at(0))
  for v in right-verts.slice(1) { verts.push(v) }
  verts.push(left-verts.last())
  if left-verts.len() > 2 {
    for v in left-verts.slice(1, -1).rev() { verts.push(v) }
  }

  place(
    top + left,
    path(stroke: border-stroke, closed: true, ..verts),
  )
}

// Place an image at specific grid cells (absolute positioning on page)
// caption: optional string to render below the image
// x-alignment / y-alignment: "left", "center", or "right" (default "center")
// border: stroke width in pt (0 = no border, default 1)
#let place-image-at-cells(cells, img-path, caption: none, dy-offset: 0pt, x-alignment: "center", y-alignment: "center", inset: (left: 0pt, right: 0pt, top: 0pt, bottom: 0pt), border: 1, grid: default-grid) = {
  let bbox = cells-bbox(cells)
  let base = cell-rect(bbox.col-start, bbox.row-start, bbox.col-end, bbox.row-end, grid: grid)
  let rect = (x: base.x + inset.left, y: base.y + dy-offset + inset.top, width: base.width - inset.left - inset.right, height: base.height - dy-offset - inset.top - inset.bottom)
  let img-stroke = if border > 0 { border * 1pt } else { none }
  // Account for border stroke extending outside the box (centered on edge)
  let boff = if border > 0 { border * 1pt } else { 0pt }
  let bot-pad = 2pt
  if caption != none {
    let cap-reserve = small-size * 3 + 4pt
    let img-max-h = rect.height - cap-reserve - boff
    let descender-pad = 4pt
    place(
      top + left,
      dx: rect.x,
      dy: rect.y,
      block(
        width: rect.width,
        height: rect.height + bot-pad,
        clip: true,
        inset: (bottom: bot-pad),
        context {
          let avail-w = rect.width - boff
          let natural = measure(image(img-path, width: avail-w))
          let img-w = avail-w
          let img-h = natural.height
          if img-h > img-max-h {
            img-h = img-max-h
            img-w = avail-w * (img-max-h / natural.height)
          }
          let cap-h = measure(text(size: small-size, style: "italic")[#caption]).height + 2pt + descender-pad
          let total-h = img-h + cap-h
          // Vertical offset for alignment
          let off-y = if y-alignment == "center" { calc.max((rect.height - total-h) / 2, 0pt) }
            else if y-alignment == "right" { calc.max(rect.height - total-h, 0pt) }
            else { 0pt }
          // Horizontal offset for alignment
          let off-x = if x-alignment == "center" { (rect.width - img-w) / 2 }
            else if x-alignment == "right" { rect.width - img-w }
            else { 0pt }
          if off-y > 0pt { v(off-y) }
          move(dx: off-x, box(width: img-w, inset: (bottom: descender-pad), {
            box(stroke: img-stroke, image(img-path, width: img-w, height: img-h))
            v(2pt)
            align(center, text(size: small-size, style: "italic")[#caption])
          }))
        },
      )
    )
  } else {
    place(
      top + left,
      dx: rect.x,
      dy: rect.y,
      block(
        width: rect.width,
        height: rect.height,
        clip: true,
        context {
          let avail-w = rect.width - boff
          let avail-h = rect.height - boff
          let natural = measure(image(img-path, width: avail-w))
          let img-w = avail-w
          let img-h = natural.height
          if img-h > avail-h {
            let scale = avail-h / img-h
            img-w = img-w * scale
            img-h = avail-h
          }
          // Vertical offset for alignment
          let off-y = if y-alignment == "center" { calc.max((rect.height - img-h) / 2, 0pt) }
            else if y-alignment == "right" { calc.max(rect.height - img-h, 0pt) }
            else { 0pt }
          // Horizontal offset for alignment
          let off-x = if x-alignment == "center" { (rect.width - img-w) / 2 }
            else if x-alignment == "right" { rect.width - img-w }
            else { 0pt }
          if off-y > 0pt { v(off-y) }
          move(dx: off-x, box(stroke: img-stroke, image(img-path, width: img-w, height: img-h)))
        },
      )
    )
  }
}

// ── Content Decomposition ────────────────────────────────────
// Breaks content into word-level "atoms" for precise column splitting.
// Atoms are either word-content pieces or paragraph-break markers.

#let pg-break = "¶PARBREAK¶"
#let is-pg-break(atom) = atom == pg-break
#let is-enum-start(a) = type(a) == str and a.starts-with("¶ENUM:")
#let is-list-start(a) = a == "¶LIST¶"
#let is-item-end(a) = a == "¶/ENUM¶" or a == "¶/LIST¶"
#let is-marker(a) = is-pg-break(a) or is-enum-start(a) or is-list-start(a) or is-item-end(a)
// ¶ is 2 bytes in UTF-8, so "¶ENUM:" = 7 bytes, trailing "¶" = 2 bytes
#let enum-number(a) = int(a.slice(7, -2))

#let tokenize(c, wrappers) = {
  if c.func() == text {
    let parts = c.text.split(" ")
    let result = ()
    for (i, part) in parts.enumerate() {
      if i > 0 { result.push("space") }
      if part != "" {
        let styled = text(part)
        for w in wrappers.rev() { styled = w(styled) }
        result.push(styled)
      }
    }
    return result
  }
  if c.func() == parbreak { return (pg-break,) }
  if c.func() == linebreak { return ("space",) }
  if c.func() == strong    { return tokenize(c.body, wrappers + (strong,)) }
  if c.func() == emph      { return tokenize(c.body, wrappers + (emph,)) }
  if c.func() == underline  { return tokenize(c.body, wrappers + (underline,)) }
  if c.func() == strike     { return tokenize(c.body, wrappers + (strike,)) }
  if c.func() == highlight  { return tokenize(c.body, wrappers + (highlight,)) }
  // Handle sequences — with special handling for enum.item / list.item
  // children. Typst's + / - syntax creates item elements directly in the
  // content sequence (no enum/list wrapper). We emit structural markers
  // (¶ENUM:N¶ / ¶/ENUM¶ etc.) so build-content can reconstruct proper
  // enum/list formatting while still allowing word-level column splits.
  if c.has("children") {
    let result = ()
    let enum-counter = 0
    for child in c.children {
      if child.func() == enum.item {
        enum-counter += 1
        result.push("¶ENUM:" + str(enum-counter) + "¶")
        let body-tokens = tokenize(child.body, wrappers)
        for t in body-tokens {
          result.push(t)
        }
        result.push("¶/ENUM¶")
      } else if child.func() == list.item {
        enum-counter = 0
        result.push("¶LIST¶")
        let body-tokens = tokenize(child.body, wrappers)
        for t in body-tokens {
          result.push(t)
        }
        result.push("¶/LIST¶")
      } else {
        // Only reset enum counter on paragraph breaks, not on space
        // elements between consecutive items in the same list
        if child.func() == parbreak { enum-counter = 0 }
        for t in tokenize(child, wrappers) {
          result.push(t)
        }
      }
    }
    return result
  }
  return (c,)
}

#let group-words(tokens) = {
  let words = ()
  let current = ()
  for t in tokens {
    if is-marker(t) {
      if current.len() > 0 { words.push(current.join()); current = () }
      words.push(t)
    } else if t == "space" {
      if current.len() > 0 { words.push(current.join()); current = () }
    } else {
      current.push(t)
    }
  }
  if current.len() > 0 { words.push(current.join()) }
  words
}

#let content-to-atoms(body) = {
  let atoms = group-words(tokenize(body, ()))
  // Deduplicate consecutive parbreaks, strip leading/trailing
  let cleaned = ()
  for a in atoms {
    if is-pg-break(a) {
      if cleaned.len() > 0 and not is-pg-break(cleaned.last()) {
        cleaned.push(a)
      }
    } else { cleaned.push(a) }
  }
  if cleaned.len() > 0 and is-pg-break(cleaned.last()) {
    cleaned = cleaned.slice(0, -1)
  }
  cleaned
}

#let build-content(atom-slice) = {
  if atom-slice.len() == 0 { return [] }

  // Detect if we start mid-enum/list (first marker is an end, not a start)
  let initial-type = "text"
  for a in atom-slice {
    if is-enum-start(a) or is-list-start(a) or is-pg-break(a) { break }
    if is-item-end(a) {
      if a == "¶/ENUM¶" { initial-type = "enum-cont" }
      else { initial-type = "list-cont" }
      break
    }
  }

  // Segment atoms by structural markers so we can reconstruct
  // proper enum/list formatting after a column split.
  let segments = ()   // array of (kind, num, words)
  let cur-type = initial-type
  let cur-num = 0
  let cur-words = ()
  for a in atom-slice {
    if is-pg-break(a) or is-enum-start(a) or is-list-start(a) or is-item-end(a) {
      if cur-words.len() > 0 {
        segments.push((kind: cur-type, num: cur-num, words: cur-words))
        cur-words = ()
      }
      if is-enum-start(a) {
        cur-type = "enum"
        cur-num = enum-number(a)
      } else if is-list-start(a) {
        cur-type = "list"
        cur-num = 0
      } else {
        cur-type = "text"
        cur-num = 0
      }
    } else {
      cur-words.push(a)
    }
  }
  if cur-words.len() > 0 {
    segments.push((kind: cur-type, num: cur-num, words: cur-words))
  }
  // Render each segment with proper formatting
  let parts = ()
  for seg in segments {
    let joined = seg.words.join([ ])
    if seg.kind == "enum" {
      parts.push(enum(start: seg.num, enum.item(joined)))
    } else if seg.kind == "list" {
      parts.push(list(list.item(joined)))
    } else if seg.kind == "enum-cont" or seg.kind == "list-cont" {
      // Continuation of item from previous column — match body indent
      parts.push(pad(left: 1.5em, joined))
    } else {
      parts.push(joined)
    }
  }
  parts.join(parbreak())
}

// Place article text in the article's bounding box.
// Images are placed independently at their own cells. If an article's
// own images overlap with its cell range, the text region is reduced
// to exclude the image area.
//
// article-cells: the full article cell range
// image-regions: array of the article's own grid-mode image cell ranges
// column-width: number of grid columns per text column
// slug: article slug (for overflow reporting)
// header-content: content for full-width header (none if not used)
// body-content: the article body content (columns are applied to this)
// col-gap: gap between text columns
// col-separator: whether to draw vertical rules between columns
// show-border: whether to draw an outline around the article bounding box
#let place-article-text(
  article-cells,
  image-regions,
  column-width,
  slug,
  header-content,
  body-content,
  col-gap: none,
  col-separator: false,
  show-border: false,
  images: (),
  grid: default-grid,
) = {
  let col-gap = if col-gap == none { grid.text-gutter } else { col-gap }
  // Use the article's own cells (not bounding box) to determine text region.
  // This correctly handles non-rectangular cell layouts (e.g., L-shapes)
  // where images occupy part of the bounding box.
  let bbox = cells-bbox(article-cells)
  let text-rect = cell-rect(bbox.col-start, bbox.row-start, bbox.col-end, bbox.row-end, grid: grid)

  let total-cols = bbox.col-end - bbox.col-start + 1
  let num-columns = calc.max(1, int(total-cols / column-width))

  let text-w = text-rect.width
  let text-h = text-rect.height
  let text-x = text-rect.x
  let text-y = text-rect.y

  // If images exist within the bounding box, find the largest rectangular
  // text region by examining the actual article cells.
  // Strategy: find the widest contiguous column span at the top row of
  // the article cells, and use that as the primary text width.
  if image-regions.len() > 0 {
    // Find the first row's column span (the primary text region)
    let first-row = bbox.row-start
    let min-col = bbox.col-end + 1
    let max-col = bbox.col-start - 1

    // Check each cell spec to find columns in the first row
    for cell in article-cells {
      let cb = cells-bbox((cell,))
      if cb.row-start <= first-row and cb.row-end >= first-row {
        if cb.col-start < min-col { min-col = cb.col-start }
        if cb.col-end > max-col { max-col = cb.col-end }
      }
    }

    // Check if any image occupies part of this first-row column range
    for img in image-regions {
      let ib = cells-bbox(img.cells)
      if ib.row-start <= first-row and ib.col-end >= min-col and ib.col-start <= max-col {
        // Image overlaps the first row — shrink text columns
        if ib.col-start <= min-col {
          min-col = ib.col-end + 1
        } else if ib.col-end >= max-col {
          max-col = ib.col-start - 1
        }
      }
    }

    if min-col <= max-col {
      let r = cell-rect(min-col, bbox.row-start, max-col, bbox.row-end, grid: grid)
      text-x = r.x
      text-w = r.width
      text-y = r.y
      text-h = r.height
      let new-total-cols = max-col - min-col + 1
      num-columns = calc.max(1, int(new-total-cols / column-width))
    }
  }

  // Apply text padding when border is shown (border itself drawn by caller)
  let border-pad = 6pt
  if show-border {
    text-x = text-x + border-pad
    text-y = text-y + border-pad
    text-w = text-w - 2 * border-pad
    text-h = text-h - 2 * border-pad
  }

  // Build body content (columns only, header placed separately)
  let body-final = {
    let col-body = columns(num-columns, gutter: col-gap, body-content)
    if col-separator and num-columns > 1 {
      col-body
      let col-w = (text-w - (num-columns - 1) * col-gap) / num-columns
      for i in range(1, num-columns) {
        let sep-x = i * (col-w + col-gap) - col-gap / 2
        place(
          top + left,
          dx: sep-x,
          block(
            width: 0pt,
            height: 100%,
            place(line(start: (0pt, 0pt), end: (0pt, 100%), stroke: 0.25pt + rule-color))
          )
        )
      }
    } else {
      col-body
    }
  }

  let top-pad = 2pt
  let bot-pad = 4pt

  context {
    // ── Header: extend across image areas at the top row ──────
    let first-row = bbox.row-start
    let top-imgs = if header-content != none {
      images.filter(img => cells-bbox(img.cells).row-start <= first-row)
    } else { () }

    let hdr-x = if top-imgs.len() > 0 {
      calc.min(text-x, ..top-imgs.map(img => {
        let b = cells-bbox(img.cells)
        cell-rect(b.col-start, b.row-start, b.col-end, b.row-end, grid: grid).x
      }))
    } else { text-x }

    let hdr-right = if top-imgs.len() > 0 {
      calc.max(text-x + text-w, ..top-imgs.map(img => {
        let b = cells-bbox(img.cells)
        let r = cell-rect(b.col-start, b.row-start, b.col-end, b.row-end, grid: grid)
        r.x + r.width
      }))
    } else { text-x + text-w }

    let hdr-w = hdr-right - hdr-x

    let header-h = if header-content != none {
      measure(block(width: hdr-w, spacing: 0pt, header-content)).height
    } else { 0pt }

    if header-content != none {
      place(
        top + left,
        dx: hdr-x,
        dy: text-y,
        block(
          width: hdr-w,
          header-content,
        ),
      )
    }

    // ── Adjusted text area (below header, with bottom padding) ─
    let adj-y = if header-content != none { text-y + header-h } else { text-y }
    let adj-h = if header-content != none { text-h - header-h - bot-pad } else { text-h - bot-pad }

    // ── Place images (offset below header if conflicting) ─────
    let hdr-bottom = text-y + header-h
    for img in images {
      let b = cells-bbox(img.cells)
      let r = cell-rect(b.col-start, b.row-start, b.col-end, b.row-end, grid: grid)
      let dy-off = if header-content != none and r.y < hdr-bottom {
        hdr-bottom - r.y
      } else { 0pt }
      // Apply border-pad only on sides where the image touches the article border
      let img-inset = if show-border {
        (
          left:   if b.col-start == bbox.col-start { border-pad } else { 0pt },
          right:  if b.col-end   == bbox.col-end   { border-pad } else { 0pt },
          top:    if b.row-start == bbox.row-start  { border-pad } else { 0pt },
          bottom: if b.row-end   == bbox.row-end    { border-pad } else { 0pt },
        )
      } else { (left: 0pt, right: 0pt, top: 0pt, bottom: 0pt) }
      place-image-at-cells(img.cells, img.path, caption: img.caption, dy-offset: dy-off, x-alignment: img.at("x-alignment", default: "center"), y-alignment: img.at("y-alignment", default: "center"), inset: img-inset, border: img.at("border", default: 1), grid: grid)
    }

    // ── Overflow detection ────────────────────────────────────
    // Measure body at single-column width and divide by column count,
    // since measure() on columns() doesn't simulate column balancing.
    let single-col-w = if num-columns > 1 {
      (text-w - (num-columns - 1) * col-gap) / num-columns
    } else { text-w }
    let single-col-h = measure(block(width: single-col-w, spacing: 0pt, body-content)).height
    let body-overflows = single-col-h / num-columns > adj-h
    if body-overflows {
      [#metadata((slug: slug, allocated: repr(adj-h), needed: repr(single-col-h / num-columns))) <overflow>]
    }

    // ── Place body content ────────────────────────────────────
    // Only clip when content overflows; otherwise let descenders render naturally
    place(
      top + left,
      dx: text-x,
      dy: adj-y - top-pad,
      block(
        width: text-w,
        height: adj-h + top-pad + bot-pad,
        clip: body-overflows,
        inset: (top: top-pad),
        body-final,
      ),
    )
  }
}

// Place article text in independently-sized columns (for non-rectangular layouts).
// Uses atom decomposition + binary search to split content at word boundaries.
// Each column gets its own independent content slice — no offset-clipping tricks.
//
// header-content: full header (title/author/rule) or none
// body-content:   raw article text (from include, no set/show wrappers)
// footer-content: end-of-article rule or continued marker (or none)
// full-width-header: if true, header spans all first-row columns;
//                    if false, header is placed in the first column only
#let place-article-columns(
  text-columns,
  slug,
  header-content,
  body-content,
  footer-content: none,
  full-width-header: true,
  col-gap: none,
  col-separator: false,
  show-border: false,
  images: (),
  grid: default-grid,
) = {
  let col-gap = if col-gap == none { grid.text-gutter } else { col-gap }
  if text-columns.len() == 0 { return }

  let atoms = content-to-atoms(body-content)
  let total = atoms.len()

  // Sort columns left to right
  let cols = text-columns.sorted(key: c => c.col_start)
  let col-rects = cols.map(c => cell-rect(c.col_start, c.row_start, c.col_end, c.row_end, grid: grid))

  // Apply text padding when border is shown — only on sides that touch the article border
  let border-pad = 6pt
  if show-border {
    // Overall bounding box of all columns + images
    let all-col-starts = cols.map(c => c.col_start) + images.map(img => cells-bbox(img.cells).col-start)
    let all-col-ends   = cols.map(c => c.col_end)   + images.map(img => cells-bbox(img.cells).col-end)
    let all-row-starts = cols.map(c => c.row_start)  + images.map(img => cells-bbox(img.cells).row-start)
    let all-row-ends   = cols.map(c => c.row_end)    + images.map(img => cells-bbox(img.cells).row-end)
    let o-cs = calc.min(..all-col-starts)
    let o-ce = calc.max(..all-col-ends)
    let o-rs = calc.min(..all-row-starts)
    let o-re = calc.max(..all-row-ends)
    col-rects = range(cols.len()).map(i => {
      let c = cols.at(i)
      let r = col-rects.at(i)
      let pl = if c.col_start == o-cs { border-pad } else { 0pt }
      let pr = if c.col_end   == o-ce { border-pad } else { 0pt }
      let pt = if c.row_start == o-rs { border-pad } else { 0pt }
      let pb = if c.row_end   == o-re { border-pad } else { 0pt }
      (x: r.x + pl, y: r.y + pt, width: r.width - pl - pr, height: r.height - pt - pb)
    })
  }

  let col-w = col-rects.first().width
  let first-row = calc.min(..cols.map(c => c.row_start))

  context {
    let top-pad = 2pt
    let bot-pad = 4pt

    // ── Pre-compute header dimensions ────────────────────────
    let hdr-indices = if full-width-header and header-content != none {
      range(cols.len()).filter(i => cols.at(i).row_start == first-row)
    } else { () }

    // Include image cells at the top row in header span so images
    // appear below the header rather than overlapping it
    let top-imgs = if full-width-header and header-content != none {
      images.filter(img => cells-bbox(img.cells).row-start <= first-row)
    } else { () }

    let hdr-x = if hdr-indices.len() > 0 {
      let base-x = col-rects.at(hdr-indices.first()).x
      if top-imgs.len() > 0 {
        calc.min(base-x, ..top-imgs.map(img => {
          let b = cells-bbox(img.cells)
          cell-rect(b.col-start, b.row-start, b.col-end, b.row-end, grid: grid).x
        }))
      } else { base-x }
    } else { col-rects.first().x }

    let hdr-y = if hdr-indices.len() > 0 {
      col-rects.at(hdr-indices.first()).y
    } else { col-rects.first().y }

    let hdr-w = if hdr-indices.len() > 0 {
      let last-r = col-rects.at(hdr-indices.last())
      let base-right = last-r.x + last-r.width
      let right = if top-imgs.len() > 0 {
        calc.max(base-right, ..top-imgs.map(img => {
          let b = cells-bbox(img.cells)
          let r = cell-rect(b.col-start, b.row-start, b.col-end, b.row-end, grid: grid)
          r.x + r.width
        }))
      } else { base-right }
      right - hdr-x
    } else { col-w }

    let header-h = if header-content != none {
      measure(block(width: hdr-w, spacing: 0pt, header-content)).height
    } else { 0pt }

    // ── Place header ──────────────────────────────────────────
    if header-content != none {
      place(
        top + left,
        dx: hdr-x,
        dy: hdr-y,
        block(
          width: hdr-w,
          header-content,
        ),
      )
    }

    // ── Place images (with header conflict resolution) ────────
    let hdr-bottom = hdr-y + header-h
    // Compute overall bounding box of article (text columns + images) for border edge detection
    let overall-col-start = calc.min(..cols.map(c => c.col_start), ..images.map(img => cells-bbox(img.cells).col-start))
    let overall-col-end   = calc.max(..cols.map(c => c.col_end),   ..images.map(img => cells-bbox(img.cells).col-end))
    let overall-row-start = calc.min(..cols.map(c => c.row_start), ..images.map(img => cells-bbox(img.cells).row-start))
    let overall-row-end   = calc.max(..cols.map(c => c.row_end),   ..images.map(img => cells-bbox(img.cells).row-end))
    for img in images {
      let img-bbox = cells-bbox(img.cells)
      let img-rect = cell-rect(img-bbox.col-start, img-bbox.row-start, img-bbox.col-end, img-bbox.row-end, grid: grid)
      let img-offset = if header-content != none and full-width-header {
        let img-right = img-rect.x + img-rect.width
        let hdr-right = hdr-x + hdr-w
        if img-rect.y < hdr-bottom and img-right > hdr-x and img-rect.x < hdr-right {
          hdr-bottom - img-rect.y
        } else { 0pt }
      } else { 0pt }
      // Apply border-pad only on sides where the image touches the article border
      let img-inset = if show-border {
        (
          left:   if img-bbox.col-start == overall-col-start { border-pad } else { 0pt },
          right:  if img-bbox.col-end   == overall-col-end   { border-pad } else { 0pt },
          top:    if img-bbox.row-start == overall-row-start  { border-pad } else { 0pt },
          bottom: if img-bbox.row-end   == overall-row-end    { border-pad } else { 0pt },
        )
      } else { (left: 0pt, right: 0pt, top: 0pt, bottom: 0pt) }
      place-image-at-cells(img.cells, img.path, caption: img.caption, dy-offset: img-offset, x-alignment: img.at("x-alignment", default: "center"), y-alignment: img.at("y-alignment", default: "center"), inset: img-inset, border: img.at("border", default: 1), grid: grid)
    }

    // ── Compute available column heights ──────────────────────
    let col-heights = ()
    let col-ys = ()
    for i in range(cols.len()) {
      let h = col-rects.at(i).height
      let y = col-rects.at(i).y
      // Subtract header height from affected columns
      let reduce = if full-width-header {
        header-content != none and cols.at(i).row_start == first-row
      } else {
        header-content != none and i == 0
      }
      if reduce {
        h -= header-h
        y += header-h
      }
      col-heights.push(h - bot-pad)
      col-ys.push(y)
    }

    // ── Binary search: find max atom count that fits ──────────
    let bsearch(lo, hi, w, h, offset) = {
      if hi - lo <= 1 { lo }
      else {
        let mid = int((lo + hi) / 2)
        let slice = atoms.slice(offset, offset + mid)
        let mh = measure(block(width: w, spacing: 0pt, build-content(slice))).height
        if mh <= h { bsearch(mid, hi, w, h, offset) }
        else       { bsearch(lo, mid, w, h, offset) }
      }
    }

    // ── Flow atoms through columns ────────────────────────────
    let offset = 0

    for i in range(cols.len()) {
      if offset >= total { break }

      // Skip leading parbreak at column boundary
      if is-pg-break(atoms.at(offset)) { offset += 1 }
      if offset >= total { break }

      let w = col-w
      let h = col-heights.at(i)
      let is-last-col = i == cols.len() - 1

      // Reserve space for footer in the last column
      let footer-h = 0pt
      if is-last-col and footer-content != none {
        footer-h = measure(block(width: w, spacing: 0pt, footer-content)).height
        h -= footer-h
      }

      let remaining = total - offset

      // Try placing all remaining content
      let full-content = build-content(atoms.slice(offset, total))
      let full-h = measure(block(width: w, spacing: 0pt, full-content)).height

      if full-h <= h {
        // Everything fits in this column — no clip needed
        let content = if is-last-col and footer-content != none {
          { full-content; footer-content }
        } else {
          full-content
        }
        let place-h = col-heights.at(i)
        place(
          top + left,
          dx: col-rects.at(i).x,
          dy: col-ys.at(i) - top-pad,
          block(
            width: w,
            height: place-h + top-pad + bot-pad,
            inset: (top: top-pad),
            content,
          ),
        )
        offset = total
      } else {
        // Overflow — binary search for the split point
        let count = bsearch(0, remaining + 1, w, h, offset)

        // Trim trailing parbreaks
        let end = offset + count
        while end > offset and is-pg-break(atoms.at(end - 1)) { end -= 1 }
        count = end - offset

        if count > 0 {
          // Content was binary-searched to fit — no clip needed
          let slice = atoms.slice(offset, offset + count)
          place(
            top + left,
            dx: col-rects.at(i).x,
            dy: col-ys.at(i) - top-pad,
            block(
              width: w,
              height: col-heights.at(i) + top-pad + bot-pad,
              inset: (top: top-pad),
              build-content(slice),
            ),
          )
        }
        offset += count
      }
    }

    // ── Overflow detection ────────────────────────────────────
    if offset < total {
      let overflow-count = atoms.slice(offset).filter(a => not is-pg-break(a)).len()
      [#metadata((slug: slug, allocated: "N/A", needed: "overflow: " + str(overflow-count) + " words")) <overflow>]
    }

    // ── Column separators ──────────────────────────────────────
    if col-separator and cols.len() > 1 {
      for i in range(1, cols.len()) {
        let prev = col-rects.at(i - 1)
        let curr = col-rects.at(i)
        // Use union (not intersection) so separator extends through image areas
        let sep-top = calc.min(prev.y, curr.y)
        let sep-bot = calc.max(prev.y + prev.height, curr.y + curr.height)
        let sep-x = prev.x + prev.width + (curr.x - prev.x - prev.width) / 2

        // If separator falls within the header span, clip to below header
        let final-top = if full-width-header and header-content != none and sep-x >= hdr-x and sep-x <= hdr-x + hdr-w {
          calc.max(sep-top, hdr-bottom)
        } else { sep-top }

        if sep-bot > final-top {
          place(
            top + left,
            dx: sep-x,
            dy: final-top,
            line(
              start: (0pt, 0pt),
              end: (0pt, sep-bot - final-top),
              stroke: 0.25pt + rule-color,
            ),
          )
        }
      }
    }
  }
}
