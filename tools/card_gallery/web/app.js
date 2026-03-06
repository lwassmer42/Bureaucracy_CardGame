const state = {
  frame: null,
  cardsDoc: null,
  activeId: null,
  frameImg: null,
  artImgCache: new Map(),
};

function el(id) { return document.getElementById(id); }

function setStatus(msg) {
  el('status').textContent = msg || '';
}

function toWebPath(p) {
  if (!p) return null;
  if (p.startsWith('res://')) return '/' + p.slice('res://'.length);
  if (p.startsWith('/')) return p;
  return '/' + p;
}

function slugify(input) {
  return (input || '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 60) || 'card';
}

async function readResponse(res) {
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = null; }
  return { text, data };
}

async function apiGet(path) {
  const res = await fetch(path);
  const { text, data } = await readResponse(res);
  if (!res.ok) throw new Error((data && data.error) || text || `HTTP ${res.status}`);
  return data;
}

async function apiPost(path, body) {
  const res = await fetch(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const { text, data } = await readResponse(res);
  if (!res.ok) throw new Error((data && data.error) || text || `HTTP ${res.status}`);
  return data;
}

function getActiveCard() {
  return state.cardsDoc?.cards?.find(c => c.id === state.activeId) || null;
}

function renderCardList() {
  const list = el('cardList');
  list.innerHTML = '';

  const cards = state.cardsDoc?.cards || [];
  for (const card of cards) {
    const row = document.createElement('div');
    row.className = 'card-row' + (card.id === state.activeId ? ' active' : '');

    const left = document.createElement('div');
    left.style.minWidth = '0';
    left.innerHTML = `<div style="font-weight:600; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">${card.name || card.id}</div>
                      <div class="muted" style="overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">${card.id}</div>`;

    const badge = document.createElement('div');
    const promoted = !!card.promoted;
    const approved = !!card.approved;
    badge.className = 'badge' + ((promoted || approved) ? ' approved' : '');
    badge.textContent = promoted ? 'PROMOTED' : (approved ? 'APPROVED' : 'DRAFT');

    row.appendChild(left);
    row.appendChild(badge);

    row.addEventListener('click', () => selectCard(card.id));
    list.appendChild(row);
  }
}

function bindEditor(card) {
  el('activeCardId').textContent = card ? card.id : '(no card selected)';
  el('approveBtn').textContent = card?.approved ? 'Unapprove' : 'Approve';
  el('promoteBtn').textContent = card?.promoted ? 'Re-promote' : 'Promote';
  el('promoteBtn').disabled = !card || !card.selected_seed;

  const set = (id, val) => { el(id).value = (val ?? ''); };

  if (!card) {
    set('nameInput', '');
    set('costInput', 0);
    set('typeInput', 'SKILL');
    set('rarityInput', 'COMMON');
    set('targetInput', 'SELF');
    set('artFitInput', 'cover');
    set('rulesInput', '');
    set('promptInput', '');
    set('accentInput', '');
    set('negativeInput', '');
    set('notesInput', '');
    set('peopleModeInput', 'auto');
    return;
  }

  set('nameInput', card.name);
  set('costInput', card.cost ?? 0);
  set('typeInput', card.type || 'SKILL');
  set('rarityInput', card.rarity || 'COMMON');
  set('targetInput', card.target || 'SELF');
  set('artFitInput', card.art_fit || 'cover');
  set('rulesInput', card.rules_text || '');
  set('promptInput', card.art_prompt || '');
  set('accentInput', card.color_accent || '');
  set('negativeInput', card.negative_prompt || '');
  set('notesInput', card.notes || '');
  const peopleMode = (card.contains_people === true) ? 'yes' : ((card.contains_people === false) ? 'no' : 'auto');
  set('peopleModeInput', peopleMode);

  const onChange = () => {
    card.name = el('nameInput').value;
    card.cost = parseInt(el('costInput').value || '0', 10);
    card.type = el('typeInput').value;
    card.rarity = el('rarityInput').value;
    card.target = el('targetInput').value;
    card.art_fit = el('artFitInput').value;
    card.rules_text = el('rulesInput').value;
    card.art_prompt = el('promptInput').value;
    card.color_accent = el('accentInput').value;
    card.negative_prompt = el('negativeInput').value.trim() ? el('negativeInput').value : null;
    card.notes = el('notesInput').value;
    const peopleMode = el('peopleModeInput').value;
    card.contains_people = (peopleMode === 'yes') ? true : ((peopleMode === 'no') ? false : null);
    el('approveBtn').textContent = card.approved ? 'Unapprove' : 'Approve';
    el('promoteBtn').textContent = card.promoted ? 'Re-promote' : 'Promote';
    el('promoteBtn').disabled = !card.selected_seed;
    renderCardList();
    renderVariants();
    renderPreview().catch(e => setStatus("Render failed: " + e.message));
  };

  for (const id of ['nameInput','costInput','typeInput','rarityInput','targetInput','artFitInput','rulesInput','promptInput','accentInput','negativeInput','notesInput']) {
    el(id).oninput = onChange;
    el(id).onchange = onChange;
  }
  el('peopleModeInput').oninput = onChange;
  el('peopleModeInput').onchange = onChange;
}

async function loadImage(src) {
  return await new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error(`Failed to load image: ${src}`));
    img.src = src;
  });
}

async function ensureFrameImage() {
  if (state.frameImg) return;

  const tex = state.frame?.frame_texture;
  if (!tex) return;

  const src = toWebPath(tex);
  try {
    state.frameImg = await loadImage(src);
  } catch (e) {
    if (src.endsWith('.png')) {
      const svgFallback = src.replace(/\.png$/i, '.svg');
      state.frameImg = await loadImage(svgFallback);
    } else {
      throw e;
    }
  }
}

async function ensureArtImage(card) {
  const seed = card?.selected_seed;
  if (!seed) return null;

  const variants = card.variants || [];
  const v = variants.find(x => x.seed === seed) || null;
  if (!v?.file) return null;

  const src = toWebPath(v.file);
  if (state.artImgCache.has(src)) return state.artImgCache.get(src);

  const img = await loadImage(src);
  state.artImgCache.set(src, img);
  return img;
}

function drawCover(ctx, img, rect) {
  const scale = Math.max(rect.w / img.width, rect.h / img.height);
  const dw = img.width * scale;
  const dh = img.height * scale;
  const dx = rect.x + (rect.w - dw) / 2;
  const dy = rect.y + (rect.h - dh) / 2;
  ctx.drawImage(img, dx, dy, dw, dh);
}

function drawFitted(ctx, img, rect, mode) {
  const m = String(mode || 'cover').toLowerCase();
  if (m === 'contain') {
    const scale = Math.min(rect.w / img.width, rect.h / img.height);
    const dw = img.width * scale;
    const dh = img.height * scale;
    const dx = rect.x + (rect.w - dw) / 2;
    const dy = rect.y + (rect.h - dh) / 2;
    ctx.drawImage(img, dx, dy, dw, dh);
    return;
  }

  // default: cover
  drawCover(ctx, img, rect);
}

function wrapLines(ctx, text, maxWidth) {
  const paragraphs = (text || '').split(/\n+/);
  const lines = [];
  for (const p of paragraphs) {
    const words = p.split(/\s+/).filter(Boolean);
    let line = '';
    for (const w of words) {
      const test = line ? line + ' ' + w : w;
      if (ctx.measureText(test).width > maxWidth && line) {
        lines.push(line);
        line = w;
      } else {
        line = test;
      }
    }
    if (line) lines.push(line);
    lines.push('');
  }
  if (lines.length && lines[lines.length - 1] === '') lines.pop();
  return lines;
}

function measureTrackedWidth(ctx, text, trackingPx) {
  const s = String(text || "");
  let glyphWidth = 0;
  for (let i = 0; i < s.length; i++) glyphWidth += ctx.measureText(s[i]).width;
  const gaps = Math.max(0, s.length - 1);
  const width = glyphWidth + (trackingPx || 0) * gaps;
  return { glyphWidth, width, gaps };
}

function drawCenteredTrackedText(ctx, text, centerX, centerY, trackingPx) {
  const s = String(text || "");
  if (!s) return;

  const m = measureTrackedWidth(ctx, s, trackingPx || 0);
  let x = centerX - m.width / 2;
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    ctx.fillText(ch, x, centerY);
    x += ctx.measureText(ch).width + (trackingPx || 0);
  }
}

async function renderPreview() {
  const canvas = el('previewCanvas');
  const ctx = canvas.getContext('2d');
  ctx.clearRect(0, 0, canvas.width, canvas.height);

  ctx.fillStyle = '#101017';
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  await ensureFrameImage();
  if (state.frameImg) {
    ctx.drawImage(state.frameImg, 0, 0, canvas.width, canvas.height);
  }

  const card = getActiveCard();
  if (!card) return;

  const artRect = state.frame?.art_rect;
  if (artRect) {
    const artImg = await ensureArtImage(card);
    if (artImg) {
      ctx.save();
      ctx.beginPath();
      ctx.rect(artRect.x, artRect.y, artRect.w, artRect.h);
      ctx.clip();
      drawFitted(ctx, artImg, artRect, card.art_fit || "cover");
      ctx.restore();
    }
  }

  const fontFamily = state.frame?.fonts?.family || 'Courier New, monospace';

  const nameRect = state.frame?.name_rect;
  if (nameRect) {
    ctx.fillStyle = '#2a1a05';
    ctx.font = `bold 20px ${fontFamily}`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(card.name || card.id, nameRect.x + nameRect.w / 2, nameRect.y + nameRect.h / 2);
  }

  const costCenter = state.frame?.cost_center;
  if (costCenter) {
    ctx.fillStyle = '#8b1a1a';
    ctx.font = `bold 48px ${fontFamily}`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(String(card.cost ?? 0), costCenter.cx, costCenter.cy);
  }

  const rarityRect = state.frame?.rarity_rect;
  if (rarityRect) {
    const baseFontPx = state.frame?.rarity_font_px ?? 18;
    const rarityYOffset = state.frame?.rarity_value_offset_y ?? 0;
    const baseTracking = state.frame?.rarity_tracking_px ?? 0;
    const pad = state.frame?.rarity_padding_px ?? 6;
    const maxWidth = Math.max(10, rarityRect.w - pad * 2);

    ctx.fillStyle = '#8b1a1a';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';

    const text = String(card.rarity || 'COMMON');
    let fontPx = baseFontPx;
    let tracking = baseTracking;
    for (let attempt = 0; attempt < 20; attempt++) {
      ctx.font = `bold ${fontPx}px ${fontFamily}`;
      const m = measureTrackedWidth(ctx, text, tracking);
      if (m.width <= maxWidth) break;
      if (m.gaps > 0 && tracking > 0) {
        const req = (maxWidth - m.glyphWidth) / m.gaps;
        tracking = Math.max(0, Math.min(tracking, req));
        const m2 = measureTrackedWidth(ctx, text, tracking);
        if (m2.width <= maxWidth) break;
      }
      fontPx = Math.max(8, fontPx - 1);
      if (fontPx === 8) break;
    }

    const cx = rarityRect.x + rarityRect.w / 2;
    const cy = rarityRect.y + rarityRect.h / 2 + rarityYOffset;
    ctx.font = `bold ${fontPx}px ${fontFamily}`;
    drawCenteredTrackedText(ctx, text, cx, cy, tracking);
  }

  const rulesRect = state.frame?.rules_rect;
  if (rulesRect) {
    ctx.fillStyle = '#2a1a05';
    ctx.font = `16px ${fontFamily}`;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';

    const pad = 12;
    const lines = wrapLines(ctx, card.rules_text || '', rulesRect.w - pad * 2);
    const lineHeight = 20;
    let y = rulesRect.y + pad;
    for (const line of lines) {
      if (y > rulesRect.y + rulesRect.h - pad - lineHeight) break;
      ctx.fillText(line, rulesRect.x + pad, y);
      y += lineHeight;
    }
  }

  ctx.fillStyle = 'rgba(0,0,0,0.35)';
  ctx.fillRect(0, canvas.height - 22, canvas.width, 22);
  ctx.fillStyle = '#e9e9ef';
  ctx.font = `12px ${fontFamily}`;
  ctx.textAlign = 'left';
  ctx.textBaseline = 'middle';
  const seed = card.selected_seed ? `seed ${card.selected_seed}` : 'no art selected';
  ctx.fillText(`${card.id} • ${seed}`, 10, canvas.height - 11);
}

function renderVariants() {
  const strip = el('variantStrip');
  strip.innerHTML = '';

  const card = getActiveCard();
  if (!card) {
    el('variantHint').textContent = '';
    return;
  }

  const variants = card.variants || [];
  el('variantHint').textContent = variants.length ? `(${variants.length})` : '(none yet)';

  for (const v of variants) {
    const wrap = document.createElement('div');
    wrap.className = 'variant' + (v.seed === card.selected_seed ? ' active' : '');

    const img = document.createElement('img');
    img.loading = 'lazy';
    img.src = toWebPath(v.file);

    const meta = document.createElement('div');
    meta.className = 'meta';
    meta.textContent = `seed ${v.seed}`;

    wrap.appendChild(img);
    wrap.appendChild(meta);

    wrap.addEventListener('click', async () => {
      card.selected_seed = v.seed;
      el('promoteBtn').disabled = !card.selected_seed;
      el('promoteBtn').textContent = card.promoted ? 'Re-promote' : 'Promote';
      renderVariants();
      await renderPreview().catch(e => setStatus("Render failed: " + e.message));
    });

    strip.appendChild(wrap);
  }
}

async function selectCard(id) {
  state.activeId = id;
  renderCardList();
  const card = getActiveCard();
  bindEditor(card);
  renderVariants();
  await renderPreview().catch(e => setStatus("Render failed: " + e.message));
}

async function reloadAll() {
  setStatus('Loading…');
  state.frame = await apiGet('/api/frame');
  state.cardsDoc = await apiGet('/api/cards');

  const size = state.frame?.card_size;
  if (size?.w && size?.h) {
    const c = el('previewCanvas');
    c.width = size.w;
    c.height = size.h;
    c.style.width = size.w + 'px';
    c.style.height = size.h + 'px';
  }

  state.frameImg = null;
  state.artImgCache.clear();

  if (!state.activeId && state.cardsDoc?.cards?.length) {
    state.activeId = state.cardsDoc.cards[0].id;
  }

  renderCardList();
  bindEditor(getActiveCard());
  renderVariants();
  await renderPreview().catch(e => setStatus("Render failed: " + e.message));
  setStatus('');
}

async function save() {
  setStatus('Saving…');
  await apiPost('/api/cards', state.cardsDoc);
  setStatus('Saved.');
  setTimeout(() => setStatus(''), 1200);
}

async function generateVariants() {
  const card = getActiveCard();
  if (!card) return;

  const count = parseInt(el('genCount').value || '4', 10);
  setStatus(`Generating ${count} variant(s) in ComfyUI…`);

  try {
    const updatedDoc = await apiPost('/api/generate', { card_id: card.id, count });
    state.cardsDoc = updatedDoc;
    renderCardList();
    bindEditor(getActiveCard());
    renderVariants();
    await renderPreview().catch(e => setStatus("Render failed: " + e.message));
    setStatus('Generation complete.');
    setTimeout(() => setStatus(''), 1500);
  } catch (e) {
    setStatus(`Generate failed: ${e.message}`);
  }
}


async function promoteCard() {
  const card = getActiveCard();
  if (!card) return;

  setStatus('Promoting to Godot…');
  try {
    const updatedDoc = await apiPost('/api/promote', { card_id: card.id });
    state.cardsDoc = updatedDoc;
    renderCardList();
    bindEditor(getActiveCard());
    renderVariants();
    await renderPreview().catch(e => setStatus('Render failed: ' + e.message));
    setStatus('Promoted. Open Godot and check rewards/shop.');
    setTimeout(() => setStatus(''), 1800);
  } catch (e) {
    setStatus(`Promote failed: ${e.message}`);
  }
}

async function importArt() {
  const card = getActiveCard();
  if (!card) return;
  el('importFile').click();
}

async function handleImportFile() {
  const card = getActiveCard();
  const input = el('importFile');
  const file = input.files && input.files[0];
  input.value = "";
  if (!card || !file) return;

  setStatus(`Importing ${file.name}…`);
  const fd = new FormData();
  fd.append('card_id', card.id);
  fd.append('file', file, file.name);

  try {
    const res = await fetch('/api/upload_art', { method: "POST", body: fd });
    const text = await res.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch { data = null; }
    if (!res.ok) {
      throw new Error((data && data.error) || text || `HTTP ${res.status}`);
    }
    const updatedDoc = data;
    state.cardsDoc = updatedDoc;
    renderCardList();
    bindEditor(getActiveCard());
    renderVariants();
    await renderPreview().catch(e => setStatus("Render failed: " + e.message));
    setStatus('Imported.');
    setTimeout(() => setStatus(''), 1200);
  } catch (e) {
    setStatus(`Import failed: ${e.message}`);
  }
}


function newCard() {
  const name = prompt('New card name?');
  if (!name) return;

  const idBase = slugify(name);
  let id = idBase;
  const existing = new Set((state.cardsDoc.cards || []).map(c => c.id));
  let i = 2;
  while (existing.has(id)) {
    id = `${idBase}_${i++}`;
  }

  const card = {
    id,
    name,
    type: 'SKILL',
    rarity: 'COMMON',
    cost: 1,
    target: 'SINGLE_ENEMY',
    rules_text: 'Describe the effect here.',
    art_prompt: 'Describe the artwork here (no text).',
    negative_prompt: null,
    contains_people: null,
    variants: [],
    selected_seed: null,
    approved: false,
    notes: '',
  };

  state.cardsDoc.cards.push(card);
  selectCard(id);
}

function deleteCard() {
  const card = getActiveCard();
  if (!card) return;
  const ok = confirm(`Delete ${card.id}? This does not delete generated images.`);
  if (!ok) return;

  state.cardsDoc.cards = state.cardsDoc.cards.filter(c => c.id !== card.id);
  state.activeId = state.cardsDoc.cards[0]?.id || null;
  renderCardList();
  bindEditor(getActiveCard());
  renderVariants();
  renderPreview().catch(e => setStatus("Render failed: " + e.message));
}

function toggleApprove() {
  const card = getActiveCard();
  if (!card) return;
  card.approved = !card.approved;
  el('approveBtn').textContent = card.approved ? 'Unapprove' : 'Approve';
  renderCardList();
  renderPreview().catch(e => setStatus("Render failed: " + e.message));
}

function init() {
  el('saveBtn').addEventListener('click', save);
  el('importBtn').addEventListener('click', importArt);
  el('importFile').addEventListener('change', handleImportFile);
  el('generateBtn').addEventListener('click', generateVariants);
  el('reloadBtn').addEventListener('click', reloadAll);
  el('newCardBtn').addEventListener('click', newCard);
  el('deleteBtn').addEventListener('click', deleteCard);
  el('approveBtn').addEventListener('click', toggleApprove);
  el('promoteBtn').addEventListener('click', promoteCard);

  reloadAll().catch(e => setStatus(`Load failed: ${e.message}`));
}

init();


