/* ===================================================================
   Banks of the Boneyard – Layout Editor (client)
   =================================================================== */

// ─── Palette of distinct article colors ──────────────────────────────
const PALETTE = [
  '#e74c3c', '#3498db', '#2ecc71', '#e67e22', '#9b59b6',
  '#1abc9c', '#f39c12', '#e84393', '#00b894', '#6c5ce7',
  '#fd79a8', '#0984e3', '#00cec9', '#d63031', '#a29bfe',
  '#ffeaa7', '#fab1a0', '#74b9ff', '#55efc4', '#fdcb6e',
];

// ─── Application state ──────────────────────────────────────────────
const S = {
  layout: null,           // layout.yaml data
  articles: [],           // [{slug, title, authors}] from articles/*.md
  images: [],             // [filename] from articles/images/
  config: null,           // config.yaml data
  events: null,           // events.yaml data

  currentPage: 1,
  totalPages: 0,
  selectedSlug: null,     // currently-selected article slug
  tool: 'article',        // 'article' | 'image' | 'eraser'
  selectedImageFile: null,

  dragging: false,
  dragStart: null,        // {row, col}
  dragEnd: null,          // {row, col}

  dirty: false,           // unsaved layout changes
};

// slug → color
const colorMap = {};
function colorFor(slug) {
  if (!colorMap[slug]) colorMap[slug] = PALETTE[Object.keys(colorMap).length % PALETTE.length];
  return colorMap[slug];
}

// ─── API helpers ─────────────────────────────────────────────────────
async function api(path, opts = {}) {
  const res = await fetch('/api' + path, {
    headers: { 'Content-Type': 'application/json', ...opts.headers },
    ...opts,
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });
  if (!res.ok) {
    const msg = await res.text();
    throw new Error(`API ${path}: ${res.status} ${msg}`);
  }
  return res.json();
}

function toast(msg, type = 'success') {
  const el = document.createElement('div');
  el.className = `toast ${type}`;
  el.textContent = msg;
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 3200);
}

// ─── Data loading ────────────────────────────────────────────────────
async function loadAll() {
  [S.layout, S.articles, S.images] = await Promise.all([
    api('/layout'),
    api('/articles'),
    api('/images'),
  ]);
  computePages();
}

function computePages() {
  let maxPage = 0;
  for (const art of S.layout.articles) {
    for (const pl of art.placements) {
      if (pl.page > maxPage) maxPage = pl.page;
    }
  }
  S.totalPages = Math.max(maxPage, 1);
  if (S.currentPage > S.totalPages) S.currentPage = S.totalPages;
}

// ─── Cell map: page → {"row,col" → {type, slug, imageSrc}} ─────────
function buildCellMap(page) {
  const map = {};
  for (const art of S.layout.articles) {
    for (const pl of art.placements) {
      if (pl.page !== page) continue;
      for (const cr of (pl.cells || [])) {
        for (const [r, c] of expandRange(cr)) {
          map[`${r},${c}`] = { type: 'article', slug: art.slug };
        }
      }
      for (const img of (pl.images || [])) {
        if (img.mode === 'grid' && img.cells) {
          for (const cr of img.cells) {
            for (const [r, c] of expandRange(cr)) {
              map[`${r},${c}`] = { type: 'image', slug: art.slug, imageSrc: img.src };
            }
          }
        }
      }
    }
  }
  return map;
}

function expandRange(range) {
  if (typeof range[0] === 'number') return [[range[0], range[1]]];
  const [[r1, c1], [r2, c2]] = range;
  const cells = [];
  for (let r = Math.min(r1, r2); r <= Math.max(r1, r2); r++)
    for (let c = Math.min(c1, c2); c <= Math.max(c1, c2); c++)
      cells.push([r, c]);
  return cells;
}

// ─── Convert a set of cells back to minimal rectangles ──────────────
function cellsToRanges(cells) {
  const set = new Set(cells.map(([r, c]) => `${r},${c}`));
  const ranges = [];
  while (set.size > 0) {
    let minR = Infinity, minC = Infinity;
    for (const key of set) {
      const [r, c] = key.split(',').map(Number);
      if (r < minR || (r === minR && c < minC)) { minR = r; minC = c; }
    }
    let maxC = minC;
    while (set.has(`${minR},${maxC + 1}`)) maxC++;
    let maxR = minR;
    outer: while (true) {
      for (let c = minC; c <= maxC; c++) {
        if (!set.has(`${maxR + 1},${c}`)) break outer;
      }
      maxR++;
    }
    for (let r = minR; r <= maxR; r++)
      for (let c = minC; c <= maxC; c++)
        set.delete(`${r},${c}`);
    if (minR === maxR && minC === maxC) ranges.push([minR, minC]);
    else ranges.push([[minR, minC], [maxR, maxC]]);
  }
  return ranges;
}

// =====================================================================
//  GRID SETTINGS
// =====================================================================

function renderGridSettings() {
  const g = S.layout.grid;
  const container = document.getElementById('grid-settings');
  container.innerHTML = `
    <label>Rows</label>
    <input type="number" id="gs-rows" value="${g.rows}" min="1" max="30" />
    <label>Columns</label>
    <input type="number" id="gs-cols" value="${g.columns}" min="1" max="12" />
    <label>Gutter</label>
    <input type="text" id="gs-gutter" value="${g.gutter}" placeholder="8pt" />
    <label>Text gutter</label>
    <input type="text" id="gs-text-gutter" value="${g.text_gutter}" placeholder="8pt" />
  `;

  document.getElementById('gs-rows').onchange = (e) => {
    const val = Math.max(1, +e.target.value || 1);
    resizeGrid(val, g.columns);
  };
  document.getElementById('gs-cols').onchange = (e) => {
    const val = Math.max(1, +e.target.value || 1);
    resizeGrid(g.rows, val);
  };
  document.getElementById('gs-gutter').onchange = (e) => {
    g.gutter = e.target.value.trim() || '0pt';
    markDirty();
  };
  document.getElementById('gs-text-gutter').onchange = (e) => {
    g.text_gutter = e.target.value.trim() || '0pt';
    markDirty();
  };
}

function resizeGrid(newRows, newCols) {
  const oldRows = S.layout.grid.rows;
  const oldCols = S.layout.grid.columns;
  S.layout.grid.rows = newRows;
  S.layout.grid.columns = newCols;

  // Clamp / remove cells that fall outside the new bounds
  if (newRows < oldRows || newCols < oldCols) {
    for (const art of S.layout.articles) {
      for (const pl of art.placements) {
        // Clamp article cells
        const kept = [];
        for (const cr of (pl.cells || [])) {
          for (const [r, c] of expandRange(cr)) {
            if (r < newRows && c < newCols) kept.push([r, c]);
          }
        }
        pl.cells = cellsToRanges(kept);
        // Clamp image cells
        pl.images = (pl.images || []).map(img => {
          if (img.mode !== 'grid' || !img.cells) return img;
          const imgKept = [];
          for (const icr of img.cells) {
            for (const [r, c] of expandRange(icr)) {
              if (r < newRows && c < newCols) imgKept.push([r, c]);
            }
          }
          return { ...img, cells: cellsToRanges(imgKept) };
        }).filter(img => img.mode !== 'grid' || (img.cells && img.cells.length > 0));
      }
    }
    // Remove empty placements
    for (const art of S.layout.articles) {
      art.placements = art.placements.filter(pl =>
        (pl.cells && pl.cells.length > 0) || (pl.images && pl.images.length > 0));
    }
  }

  markDirty();
  renderGridSettings();
  renderGrid();
  renderProperties();
}

// =====================================================================
//  GRID RENDERING
// =====================================================================

function renderGrid() {
  const { rows, columns } = S.layout.grid;
  const grid = document.getElementById('grid');
  grid.innerHTML = '';
  grid.style.gridTemplateColumns = `repeat(${columns}, 1fr)`;
  grid.style.gridTemplateRows = `repeat(${rows}, 1fr)`;

  // Column labels
  const colLabels = document.getElementById('grid-col-labels');
  colLabels.innerHTML = '';
  colLabels.style.gridTemplateColumns = `repeat(${columns}, 1fr)`;
  for (let c = 0; c < columns; c++) {
    const s = document.createElement('span');
    s.textContent = c;
    colLabels.appendChild(s);
  }

  // Row labels
  const rowLabels = document.getElementById('grid-row-labels');
  rowLabels.innerHTML = '';
  rowLabels.style.gridTemplateRows = `repeat(${rows}, 1fr)`;
  for (let r = 0; r < rows; r++) {
    const s = document.createElement('span');
    s.textContent = r;
    rowLabels.appendChild(s);
  }

  const cellMap = buildCellMap(S.currentPage);

  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < columns; c++) {
      const cell = document.createElement('div');
      cell.className = 'grid-cell';
      cell.dataset.row = r;
      cell.dataset.col = c;

      const key = `${r},${c}`;
      const owner = cellMap[key];
      if (owner) {
        cell.style.backgroundColor = colorFor(owner.slug);
        cell.classList.add('occupied');
        cell.textContent = owner.slug.substring(0, 6);
        if (owner.type === 'image') {
          cell.classList.add('image-cell');
          cell.title = `${owner.slug} — image: ${owner.imageSrc}`;
        } else {
          cell.title = `${owner.slug}`;
        }
      }

      cell.addEventListener('mousedown', onCellDown);
      cell.addEventListener('mouseenter', onCellEnter);
      grid.appendChild(cell);
    }
  }

  document.getElementById('grid-page-label').textContent = `Page ${S.currentPage}`;
}

// ─── Grid drag interaction ───────────────────────────────────────────
function cellCoords(el) {
  return { row: +el.dataset.row, col: +el.dataset.col };
}

function onCellDown(e) {
  e.preventDefault();
  S.dragging = true;
  S.dragStart = cellCoords(e.currentTarget);
  S.dragEnd = { ...S.dragStart };
  updateDragPreview();
}

function onCellEnter(e) {
  if (!S.dragging) {
    const { row, col } = cellCoords(e.currentTarget);
    document.getElementById('grid-cell-info').textContent = `[${row}, ${col}]`;
    return;
  }
  S.dragEnd = cellCoords(e.currentTarget);
  updateDragPreview();
}

function onMouseUp() {
  if (!S.dragging) return;
  S.dragging = false;
  const { dragStart: ds, dragEnd: de } = S;
  if (!ds || !de) return;
  const r1 = Math.min(ds.row, de.row), r2 = Math.max(ds.row, de.row);
  const c1 = Math.min(ds.col, de.col), c2 = Math.max(ds.col, de.col);
  applyDrag(r1, c1, r2, c2);
  clearDragPreview();
  S.dragStart = S.dragEnd = null;
}
document.addEventListener('mouseup', onMouseUp);

function updateDragPreview() {
  clearDragPreview();
  if (!S.dragStart || !S.dragEnd) return;
  const r1 = Math.min(S.dragStart.row, S.dragEnd.row);
  const r2 = Math.max(S.dragStart.row, S.dragEnd.row);
  const c1 = Math.min(S.dragStart.col, S.dragEnd.col);
  const c2 = Math.max(S.dragStart.col, S.dragEnd.col);
  const grid = document.getElementById('grid');
  const cols = S.layout.grid.columns;
  for (let r = r1; r <= r2; r++)
    for (let c = c1; c <= c2; c++)
      grid.children[r * cols + c]?.classList.add('drag-preview');
}

function clearDragPreview() {
  document.querySelectorAll('.grid-cell.drag-preview').forEach(el =>
    el.classList.remove('drag-preview'));
}

// ─── Apply a completed drag ─────────────────────────────────────────
function applyDrag(r1, c1, r2, c2) {
  if (S.tool === 'eraser') {
    eraseCells(r1, c1, r2, c2);
  } else if (S.tool === 'image') {
    placeImage(r1, c1, r2, c2);
  } else {
    // article draw
    if (!S.selectedSlug) { toast('Select an article first', 'error'); return; }
    addArticleCells(S.selectedSlug, S.currentPage, r1, c1, r2, c2);
  }
  markDirty();
  renderGrid();
  renderProperties();
}

function addArticleCells(slug, page, r1, c1, r2, c2) {
  // Remove any existing cells in this rectangle (from other articles)
  eraseFromLayout(page, r1, c1, r2, c2);

  let art = S.layout.articles.find(a => a.slug === slug);
  if (!art) {
    art = { slug, column_width: 2, placements: [] };
    S.layout.articles.push(art);
  }
  let pl = art.placements.find(p => p.page === page);
  if (!pl) {
    pl = { page, cells: [], images: [] };
    art.placements.push(pl);
  }
  // Merge new rectangle with existing cells
  const existingCells = [];
  for (const cr of (pl.cells || [])) {
    for (const cell of expandRange(cr)) existingCells.push(cell);
  }
  for (let r = r1; r <= r2; r++)
    for (let c = c1; c <= c2; c++)
      if (!existingCells.some(([er, ec]) => er === r && ec === c))
        existingCells.push([r, c]);
  pl.cells = cellsToRanges(existingCells);
}

function eraseCells(r1, c1, r2, c2) {
  eraseFromLayout(S.currentPage, r1, c1, r2, c2);
}

function eraseFromLayout(page, r1, c1, r2, c2) {
  const eraseSet = new Set();
  for (let r = r1; r <= r2; r++)
    for (let c = c1; c <= c2; c++)
      eraseSet.add(`${r},${c}`);

  for (const art of S.layout.articles) {
    for (const pl of art.placements) {
      if (pl.page !== page) continue;
      // Remove from article cells
      const remaining = [];
      for (const cr of (pl.cells || [])) {
        for (const [r, c] of expandRange(cr)) {
          if (!eraseSet.has(`${r},${c}`)) remaining.push([r, c]);
        }
      }
      pl.cells = cellsToRanges(remaining);
      // Remove overlapping image cells
      pl.images = (pl.images || []).filter(img => {
        if (img.mode !== 'grid' || !img.cells) return true;
        const imgRemaining = [];
        for (const cr of img.cells) {
          for (const [r, c] of expandRange(cr)) {
            if (!eraseSet.has(`${r},${c}`)) imgRemaining.push([r, c]);
          }
        }
        if (imgRemaining.length === 0) return false;
        img.cells = cellsToRanges(imgRemaining);
        return true;
      });
    }
  }
  // Clean up empty placements and articles
  for (const art of S.layout.articles) {
    art.placements = art.placements.filter(pl =>
      (pl.cells && pl.cells.length > 0) || (pl.images && pl.images.length > 0));
  }
}

function placeImage(r1, c1, r2, c2) {
  const imgFile = S.selectedImageFile || document.getElementById('image-file-select').value;
  if (!imgFile) { toast('Select an image file first', 'error'); return; }
  if (!S.selectedSlug) { toast('Select a parent article first', 'error'); return; }

  const art = S.layout.articles.find(a => a.slug === S.selectedSlug);
  if (!art) { toast('Article not in layout', 'error'); return; }
  let pl = art.placements.find(p => p.page === S.currentPage);
  if (!pl) { toast('Article has no placement on this page', 'error'); return; }
  if (!pl.images) pl.images = [];
  pl.images.push({
    src: imgFile,
    mode: 'grid',
    cells: [[[r1, c1], [r2, c2]]],
    'x-alignment': 'center',
    'y-alignment': 'center',
    border: 1,
  });
}

// =====================================================================
//  SIDEBAR
// =====================================================================

function renderPageSelector() {
  const container = document.getElementById('page-selector');
  container.innerHTML = '';
  for (let p = 1; p <= S.totalPages; p++) {
    const btn = document.createElement('button');
    btn.className = 'page-btn' + (p === S.currentPage ? ' active' : '');
    btn.textContent = p;
    btn.onclick = () => { S.currentPage = p; renderGrid(); renderPageSelector(); };
    container.appendChild(btn);
  }
}

function renderArticlePalette() {
  const container = document.getElementById('article-palette');
  container.innerHTML = '';
  const layoutSlugs = S.layout.articles.map(a => a.slug);

  for (const slug of layoutSlugs) {
    const chip = document.createElement('div');
    chip.className = 'article-chip' + (slug === S.selectedSlug ? ' selected' : '');
    const meta = S.articles.find(a => a.slug === slug);
    chip.innerHTML = `
      <span class="swatch" style="background:${colorFor(slug)}"></span>
      <span class="slug" title="${meta ? meta.title : slug}">${slug}</span>
      <button class="remove-btn" title="Remove from layout">&times;</button>
    `;
    chip.querySelector('.slug').onclick = () => {
      S.selectedSlug = slug;
      S.tool = 'article';
      renderArticlePalette();
      renderProperties();
      renderToolButtons();
    };
    chip.querySelector('.remove-btn').onclick = (e) => {
      e.stopPropagation();
      removeArticleFromLayout(slug);
    };
    container.appendChild(chip);
  }
}

function removeArticleFromLayout(slug) {
  S.layout.articles = S.layout.articles.filter(a => a.slug !== slug);
  if (S.selectedSlug === slug) S.selectedSlug = null;
  computePages();
  markDirty();
  renderGrid();
  renderPageSelector();
  renderArticlePalette();
  renderProperties();
}

function renderToolButtons() {
  document.querySelectorAll('.tool-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.tool === S.tool);
  });
  document.getElementById('image-tool-options').classList.toggle('hidden', S.tool !== 'image');
}

// =====================================================================
//  PROPERTIES PANEL
// =====================================================================

function renderProperties() {
  const container = document.getElementById('properties-content');
  if (!S.selectedSlug) {
    container.innerHTML = '<p class="hint">Select an article to edit its properties.</p>';
    return;
  }
  const art = S.layout.articles.find(a => a.slug === S.selectedSlug);
  if (!art) {
    container.innerHTML = '<p class="hint">Article not in layout.</p>';
    return;
  }
  const meta = S.articles.find(a => a.slug === S.selectedSlug);

  let html = `<div class="prop-group">
    <label>Slug</label>
    <input type="text" value="${art.slug}" disabled />
  </div>`;

  if (meta) {
    html += `<div class="prop-group">
      <label>Title</label>
      <input type="text" value="${escHtml(meta.title)}" disabled />
    </div>`;
  }

  // Generate column_width options dynamically based on grid columns
  const colOpts = [];
  for (let v = 1; v <= S.layout.grid.columns; v++) {
    if (S.layout.grid.columns % v === 0) colOpts.push(v);
  }

  html += `<div class="prop-group">
    <label>Column Width</label>
    <select id="prop-col-width">
      ${colOpts.map(v => `<option value="${v}" ${v === (art.column_width||2) ? 'selected' : ''}>${v}</option>`).join('')}
    </select>
  </div>`;

  html += `<div class="prop-group">
    <label class="checkbox-label">
      <input type="checkbox" id="prop-full-header" ${art.full_width_header ? 'checked' : ''} />
      Full-width header
    </label>
    <label class="checkbox-label">
      <input type="checkbox" id="prop-col-sep" ${art.column_separator ? 'checked' : ''} />
      Column separator
    </label>
    <label class="checkbox-label">
      <input type="checkbox" id="prop-border" ${art.show_border ? 'checked' : ''} />
      Show border
    </label>
  </div>`;

  html += `<div class="prop-group">
    <label>Column Gap</label>
    <input type="text" id="prop-col-gap" value="${art.column_gap || ''}" placeholder="e.g. 8pt" />
  </div>`;

  // Placements summary
  html += `<div class="prop-group"><label>Placements</label>`;
  for (const pl of art.placements) {
    const cellCount = (pl.cells || []).reduce((n, cr) => n + expandRange(cr).length, 0);
    html += `<div style="font-size:11px;margin:2px 0">Page ${pl.page}: ${cellCount} cells</div>`;
  }
  html += `</div>`;

  // ── Images section (current page) ──────────────────────────────────
  const pl = art.placements.find(p => p.page === S.currentPage);
  const imgs = pl ? (pl.images || []) : [];

  html += `<div class="prop-images"><label>Images (page ${S.currentPage})</label>`;

  if (imgs.length === 0) {
    html += `<div style="font-size:11px;color:var(--text-light)">No images on this page</div>`;
  }

  const alignOpts = ['left', 'center', 'right'];

  for (let i = 0; i < imgs.length; i++) {
    const img = imgs[i];
    const isGrid = img.mode === 'grid';
    const imgSrcOpts = S.images.map(f =>
      `<option value="${f}" ${f === img.src ? 'selected' : ''}>${f}</option>`
    ).join('');

    html += `<div class="prop-image-item" data-img-idx="${i}">
      <div class="img-header">
        <span class="img-mode-badge mode-${img.mode}">${img.mode}</span>
        <button class="img-remove" data-idx="${i}" title="Remove image">&times;</button>
      </div>
      <div class="img-preview">
        <img src="/api/images/${encodeURIComponent(img.src)}" alt="${escHtml(img.src)}" />
      </div>

      <div class="img-field">
        <label>File</label>
        <select class="img-src" data-idx="${i}">${imgSrcOpts}</select>

        <label>Mode</label>
        <select class="img-mode" data-idx="${i}">
          <option value="grid" ${isGrid ? 'selected' : ''}>grid</option>
          <option value="inline" ${!isGrid ? 'selected' : ''}>inline</option>
        </select>

        <label>Caption</label>
        <input type="text" class="img-caption" data-idx="${i}" value="${escHtml(img.caption || '')}" placeholder="optional" />

        <label>Border</label>
        <input type="number" class="img-border" data-idx="${i}" value="${img.border != null ? img.border : 1}" min="0" step="0.5" />`;

    if (isGrid) {
      html += `
        <label>X-align</label>
        <select class="img-x-align" data-idx="${i}">
          ${alignOpts.map(a => `<option value="${a}" ${(img['x-alignment']||'center') === a ? 'selected' : ''}>${a}</option>`).join('')}
        </select>

        <label>Y-align</label>
        <select class="img-y-align" data-idx="${i}">
          ${alignOpts.map(a => `<option value="${a}" ${(img['y-alignment']||'center') === a ? 'selected' : ''}>${a}</option>`).join('')}
        </select>`;
    } else {
      html += `
        <label>Scale %</label>
        <input type="number" class="img-scale" data-idx="${i}" value="${img.scale != null ? img.scale : 100}" min="1" max="100" />`;
    }

    html += `</div>`; // close .img-field

    if (isGrid && img.cells) {
      html += `<div class="img-cells">Cells: ${JSON.stringify(img.cells)}</div>`;
    }

    html += `</div>`; // close .prop-image-item
  }

  html += `</div>`; // close .prop-images

  container.innerHTML = html;

  // ── Wire up article property handlers ──────────────────────────────
  const setArt = (key, val) => { art[key] = val; markDirty(); };
  document.getElementById('prop-col-width').onchange = (e) => setArt('column_width', +e.target.value);
  document.getElementById('prop-full-header').onchange = (e) => setArt('full_width_header', e.target.checked || undefined);
  document.getElementById('prop-col-sep').onchange = (e) => setArt('column_separator', e.target.checked || undefined);
  document.getElementById('prop-border').onchange = (e) => setArt('show_border', e.target.checked || undefined);
  document.getElementById('prop-col-gap').onchange = (e) => {
    const v = e.target.value.trim();
    setArt('column_gap', v || undefined);
  };

  // ── Wire up image property handlers ────────────────────────────────
  if (pl) {
    const imgList = pl.images || [];

    // Helper: set an image prop and mark dirty
    const setImg = (idx, key, val) => {
      if (val === '' || val === undefined) delete imgList[idx][key];
      else imgList[idx][key] = val;
      markDirty();
    };

    container.querySelectorAll('.img-src').forEach(el => {
      el.onchange = () => {
        setImg(+el.dataset.idx, 'src', el.value);
        // Update the thumbnail preview
        const item = el.closest('.prop-image-item');
        const preview = item?.querySelector('.img-preview img');
        if (preview) preview.src = `/api/images/${encodeURIComponent(el.value)}`;
      };
    });

    container.querySelectorAll('.img-mode').forEach(el => {
      el.onchange = () => {
        const idx = +el.dataset.idx;
        const newMode = el.value;
        const img = imgList[idx];
        img.mode = newMode;
        if (newMode === 'inline') {
          // Switching to inline: remove cells, add default scale
          delete img.cells;
          delete img['x-alignment'];
          delete img['y-alignment'];
          if (img.scale == null) img.scale = 100;
        } else {
          // Switching to grid: remove scale, cells need to be drawn
          delete img.scale;
          img.cells = img.cells || [];
        }
        markDirty();
        renderGrid();
        renderProperties();
      };
    });

    container.querySelectorAll('.img-caption').forEach(el => {
      el.onchange = () => setImg(+el.dataset.idx, 'caption', el.value.trim());
    });

    container.querySelectorAll('.img-border').forEach(el => {
      el.onchange = () => setImg(+el.dataset.idx, 'border', +el.value);
    });

    container.querySelectorAll('.img-x-align').forEach(el => {
      el.onchange = () => setImg(+el.dataset.idx, 'x-alignment', el.value);
    });

    container.querySelectorAll('.img-y-align').forEach(el => {
      el.onchange = () => setImg(+el.dataset.idx, 'y-alignment', el.value);
    });

    container.querySelectorAll('.img-scale').forEach(el => {
      el.onchange = () => {
        const v = Math.max(1, Math.min(100, +el.value || 100));
        el.value = v;
        setImg(+el.dataset.idx, 'scale', v);
      };
    });

    // Remove buttons
    container.querySelectorAll('.img-remove').forEach(btn => {
      btn.onclick = () => {
        imgList.splice(+btn.dataset.idx, 1);
        markDirty();
        renderGrid();
        renderProperties();
      };
    });

  }
}

// =====================================================================
//  ARTICLES TAB
// =====================================================================

let editingArticleSlug = null;

function renderArticlesTab() {
  const list = document.getElementById('articles-list');
  list.innerHTML = '';
  for (const art of S.articles) {
    const item = document.createElement('div');
    item.className = 'article-list-item' + (art.slug === editingArticleSlug ? ' active' : '');
    item.innerHTML = `<span class="slug">${art.slug}</span><span class="title">${escHtml(art.title)}</span>`;
    item.onclick = () => { editingArticleSlug = art.slug; renderArticlesTab(); loadArticleEditor(art.slug); };
    list.appendChild(item);
  }
}

async function loadArticleEditor(slug) {
  const container = document.getElementById('article-editor-content');
  try {
    const art = await api(`/articles/${slug}`);
    container.innerHTML = `
      <h3>Editing: ${escHtml(slug)}</h3>
      <label>Title</label>
      <input type="text" id="edit-title" value="${escHtml(art.title)}" />
      <label>Authors (comma-separated)</label>
      <input type="text" id="edit-authors" value="${escHtml(art.authors.join(', '))}" />
      <label>Body (Markdown)</label>
      <textarea id="edit-body">${escHtml(art.body)}</textarea>
      <div style="margin-top:12px;display:flex;gap:8px">
        <button class="btn btn-primary" id="btn-save-article">Save</button>
        <button class="btn btn-danger" id="btn-delete-article">Delete</button>
      </div>
    `;
    document.getElementById('btn-save-article').onclick = async () => {
      await api(`/articles/${slug}`, {
        method: 'PUT',
        body: {
          title: document.getElementById('edit-title').value,
          authors: document.getElementById('edit-authors').value.split(',').map(s => s.trim()).filter(Boolean),
          body: document.getElementById('edit-body').value,
        },
      });
      toast('Article saved');
      S.articles = await api('/articles');
      renderArticlesTab();
      renderArticlePalette();
    };
    document.getElementById('btn-delete-article').onclick = async () => {
      if (!confirm(`Delete article "${slug}"? This cannot be undone.`)) return;
      await api(`/articles/${slug}`, { method: 'DELETE' });
      toast('Article deleted');
      S.articles = await api('/articles');
      editingArticleSlug = null;
      renderArticlesTab();
      renderArticlePalette();
      document.getElementById('article-editor-content').innerHTML = '<p class="hint">Select an article to edit.</p>';
    };
  } catch (err) {
    container.innerHTML = `<p class="hint" style="color:var(--danger)">${err.message}</p>`;
  }
}

// ─── LFTC editor ─────────────────────────────────────────────────────
document.getElementById('btn-edit-lftc').onclick = async () => {
  editingArticleSlug = null;
  renderArticlesTab();
  const container = document.getElementById('article-editor-content');
  try {
    const data = await api('/lftc');
    container.innerHTML = `
      <h3>Letter from the Chair</h3>
      <label>Author</label>
      <input type="text" id="lftc-author" value="${escHtml(data.author)}" />
      <label>Body (Markdown)</label>
      <textarea id="lftc-body">${escHtml(data.body)}</textarea>
      <div style="margin-top:12px"><button class="btn btn-primary" id="btn-save-lftc">Save</button></div>
    `;
    document.getElementById('btn-save-lftc').onclick = async () => {
      await api('/lftc', {
        method: 'PUT',
        body: {
          author: document.getElementById('lftc-author').value,
          body: document.getElementById('lftc-body').value,
        },
      });
      toast('LFTC saved');
    };
  } catch (err) {
    container.innerHTML = `<p class="hint" style="color:var(--danger)">${err.message}</p>`;
  }
};

// =====================================================================
//  CONFIG & EVENTS TAB
// =====================================================================

async function loadConfigTab() {
  S.config = await api('/config');
  S.events = await api('/events');

  const form = document.getElementById('config-form');
  form.querySelector('[name=volume]').value = S.config.volume || '';
  form.querySelector('[name=issue]').value = S.config.issue || '';
  form.querySelector('[name=date]').value = S.config.date || '';
  form.querySelector('[name=headline]').value = S.config.headline || '';
  form.querySelector('[name=subtitle]').value = S.config.subtitle || '';
  form.querySelector('[name=url]').value = S.config.url || '';
  form.querySelector('[name=featured_email]').value = S.config.featured_email || '';
  form.querySelector('[name=editors]').value = (S.config.editors || []).join('\n');

  renderEvents();
}

document.getElementById('config-form').onsubmit = async (e) => {
  e.preventDefault();
  const form = e.target;
  const data = {
    volume: +form.querySelector('[name=volume]').value,
    issue: +form.querySelector('[name=issue]').value,
    date: form.querySelector('[name=date]').value,
    headline: form.querySelector('[name=headline]').value,
    subtitle: form.querySelector('[name=subtitle]').value,
    url: form.querySelector('[name=url]').value,
    featured_email: form.querySelector('[name=featured_email]').value,
    editors: form.querySelector('[name=editors]').value.split('\n').map(s => s.trim()).filter(Boolean),
    directory_order: S.config.directory_order,  // preserve
  };
  await api('/config', { method: 'PUT', body: data });
  toast('Config saved');
};

function renderEvents() {
  const container = document.getElementById('events-list');
  container.innerHTML = '';
  const events = (S.events && S.events.events) || [];
  for (let i = 0; i < events.length; i++) {
    const ev = events[i];
    const card = document.createElement('div');
    card.className = 'event-card';
    card.innerHTML = `
      <button class="event-remove" data-idx="${i}">&times;</button>
      <label>Name</label>
      <input type="text" data-field="name" value="${escHtml(ev.name || '')}" />
      <label>Date</label>
      <input type="text" data-field="date" value="${escHtml(ev.date || '')}" />
      <label>Time</label>
      <input type="text" data-field="time" value="${escHtml(ev.time || '')}" />
      <label>Location</label>
      <input type="text" data-field="location" value="${escHtml(ev.location || '')}" />
      <label>Description</label>
      <input type="text" data-field="description" value="${escHtml(ev.description || '')}" />
    `;
    card.querySelector('.event-remove').onclick = () => {
      events.splice(i, 1);
      renderEvents();
    };
    // Update data on input change
    card.querySelectorAll('input').forEach(input => {
      input.oninput = () => {
        const field = input.dataset.field;
        const val = input.value.trim();
        if (val) ev[field] = val;
        else delete ev[field];
      };
    });
    container.appendChild(card);
  }
}

document.getElementById('btn-add-event').onclick = () => {
  if (!S.events) S.events = { events: [] };
  if (!S.events.events) S.events.events = [];
  S.events.events.push({ name: '', date: '' });
  renderEvents();
};

document.getElementById('btn-save-events').onclick = async () => {
  await api('/events', { method: 'PUT', body: S.events });
  toast('Events saved');
};

// =====================================================================
//  BUILD TAB
// =====================================================================

let buildPollTimer = null;

async function startBuild(mode) {
  try {
    await api('/build', { method: 'POST', body: { mode } });
    toast(`Build started (${mode})`);
    pollBuild();
  } catch (err) {
    toast(err.message, 'error');
  }
}

function pollBuild() {
  clearInterval(buildPollTimer);
  buildPollTimer = setInterval(async () => {
    const s = await api('/build/status');
    const statusEl = document.getElementById('build-status');
    const logEl = document.getElementById('build-log');
    logEl.textContent = s.log || '(no output yet)';
    logEl.scrollTop = logEl.scrollHeight;

    if (s.running) {
      statusEl.className = 'build-status running';
      statusEl.textContent = `Building (${s.mode})...`;
    } else if (s.return_code === 0) {
      statusEl.className = 'build-status success';
      statusEl.textContent = `Build succeeded (${s.mode})`;
      clearInterval(buildPollTimer);
      showPdfPreview(s.mode);
    } else if (s.return_code !== null) {
      statusEl.className = 'build-status error';
      statusEl.textContent = `Build failed (exit ${s.return_code})`;
      clearInterval(buildPollTimer);
    } else {
      statusEl.className = 'build-status';
      statusEl.textContent = 'Idle';
      clearInterval(buildPollTimer);
    }
  }, 800);
}

function showPdfPreview(mode) {
  const container = document.getElementById('build-preview');
  if (mode === 'both') mode = 'online';
  container.innerHTML = `
    <h3>Preview (${mode})</h3>
    <iframe src="/api/pdf/${mode}#toolbar=1"></iframe>
  `;
}

document.getElementById('btn-build-online').onclick = () => startBuild('online');
document.getElementById('btn-build-print').onclick = () => startBuild('print');
document.getElementById('btn-build-both').onclick = () => startBuild('both');

// =====================================================================
//  TABS
// =====================================================================

document.querySelectorAll('.tab').forEach(tab => {
  tab.onclick = () => {
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
    tab.classList.add('active');
    document.getElementById('tab-' + tab.dataset.tab).classList.add('active');

    // Lazy-load tab data
    if (tab.dataset.tab === 'articles' && S.articles.length) renderArticlesTab();
    if (tab.dataset.tab === 'config') loadConfigTab();
  };
});

// =====================================================================
//  PAGE / LAYOUT MANAGEMENT
// =====================================================================

document.getElementById('btn-add-page').onclick = () => {
  S.totalPages++;
  S.currentPage = S.totalPages;
  renderPageSelector();
  renderGrid();
};

document.getElementById('btn-remove-page').onclick = () => {
  if (S.totalPages <= 1) return;
  // Check if current page has content
  const hasContent = S.layout.articles.some(a =>
    a.placements.some(p => p.page === S.currentPage &&
      ((p.cells && p.cells.length > 0) || (p.images && p.images.length > 0))));
  if (hasContent && !confirm(`Page ${S.currentPage} has content. Remove it?`)) return;
  // Remove all placements on this page
  for (const art of S.layout.articles) {
    art.placements = art.placements.filter(p => p.page !== S.currentPage);
    // Shift pages above down
    for (const p of art.placements) {
      if (p.page > S.currentPage) p.page--;
    }
  }
  S.totalPages--;
  if (S.currentPage > S.totalPages) S.currentPage = S.totalPages;
  computePages();
  markDirty();
  renderPageSelector();
  renderGrid();
  renderArticlePalette();
};

// ─── Add article to layout modal ─────────────────────────────────────
document.getElementById('btn-add-to-layout').onclick = () => {
  const modal = document.getElementById('modal-add-article');
  const select = document.getElementById('modal-article-select');
  select.innerHTML = '';
  const layoutSlugs = new Set(S.layout.articles.map(a => a.slug));
  const available = S.articles.filter(a => !layoutSlugs.has(a.slug));
  if (available.length === 0) {
    toast('All articles are already in the layout', 'error');
    return;
  }
  for (const art of available) {
    const opt = document.createElement('option');
    opt.value = art.slug;
    opt.textContent = `${art.slug} — ${art.title}`;
    select.appendChild(opt);
  }
  modal.classList.remove('hidden');
};
document.getElementById('modal-cancel').onclick = () =>
  document.getElementById('modal-add-article').classList.add('hidden');
document.getElementById('modal-confirm').onclick = () => {
  const slug = document.getElementById('modal-article-select').value;
  if (!slug) return;
  S.layout.articles.push({
    slug,
    column_width: 2,
    full_width_header: true,
    placements: [],
  });
  S.selectedSlug = slug;
  markDirty();
  document.getElementById('modal-add-article').classList.add('hidden');
  renderArticlePalette();
  renderProperties();
  renderToolButtons();
};

// ─── New article modal ───────────────────────────────────────────────
document.getElementById('btn-new-article').onclick = () => {
  document.getElementById('new-article-slug').value = '';
  document.getElementById('new-article-title').value = '';
  document.getElementById('new-article-authors').value = '';
  document.getElementById('modal-new-article').classList.remove('hidden');
};
document.getElementById('modal-new-cancel').onclick = () =>
  document.getElementById('modal-new-article').classList.add('hidden');
document.getElementById('modal-new-confirm').onclick = async () => {
  const slug = document.getElementById('new-article-slug').value.trim();
  const title = document.getElementById('new-article-title').value.trim() || slug;
  const authors = document.getElementById('new-article-authors').value
    .split(',').map(s => s.trim()).filter(Boolean);
  if (!slug) { toast('Slug is required', 'error'); return; }
  try {
    await api('/articles', { method: 'POST', body: { slug, title, authors } });
    toast('Article created');
    S.articles = await api('/articles');
    renderArticlesTab();
    renderArticlePalette();
    document.getElementById('modal-new-article').classList.add('hidden');
  } catch (err) {
    toast(err.message, 'error');
  }
};

// ─── Tool buttons ────────────────────────────────────────────────────
document.querySelectorAll('.tool-btn').forEach(btn => {
  btn.onclick = () => {
    S.tool = btn.dataset.tool;
    renderToolButtons();
  };
});

// ─── Image file selector ─────────────────────────────────────────────
function populateImageSelect() {
  const sel = document.getElementById('image-file-select');
  sel.innerHTML = '<option value="">-- select --</option>';
  for (const img of S.images) {
    const opt = document.createElement('option');
    opt.value = img;
    opt.textContent = img;
    sel.appendChild(opt);
  }
  sel.onchange = () => { S.selectedImageFile = sel.value; };
}

// ─── Save layout ─────────────────────────────────────────────────────
document.getElementById('btn-save-layout').onclick = async () => {
  // Clean up empty placements and articles with no placements
  for (const art of S.layout.articles) {
    art.placements = art.placements.filter(pl =>
      (pl.cells && pl.cells.length > 0) || (pl.images && pl.images.length > 0));
  }
  // Remove text_columns (computed by build.py)
  for (const art of S.layout.articles) {
    for (const pl of art.placements) {
      delete pl.text_columns;
    }
  }
  try {
    await api('/layout', { method: 'PUT', body: S.layout });
    S.dirty = false;
    document.getElementById('save-indicator').classList.add('hidden');
    toast('Layout saved');
  } catch (err) {
    toast(err.message, 'error');
  }
};

function markDirty() {
  S.dirty = true;
  document.getElementById('save-indicator').classList.remove('hidden');
}

// ─── Utility ─────────────────────────────────────────────────────────
function escHtml(s) {
  return String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// =====================================================================
//  INIT
// =====================================================================

async function init() {
  await loadAll();
  renderGridSettings();
  renderPageSelector();
  renderArticlePalette();
  renderGrid();
  populateImageSelect();
  renderArticlesTab();

  // Warn before leaving with unsaved changes
  window.onbeforeunload = (e) => {
    if (S.dirty) { e.preventDefault(); return ''; }
  };
}

init().catch(err => {
  console.error('Init failed:', err);
  document.body.innerHTML = `<div style="padding:40px;color:#dc3545"><h2>Failed to load</h2><pre>${err.message}</pre></div>`;
});
