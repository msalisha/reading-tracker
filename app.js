(() => {
  'use strict';
  // ================= storage =================
  // Everything lives in one JSON blob in localStorage on the phone: { books, sessions, timer }.
  // On first launch it is filled from seed.js (your data from the web tracker).
  const KEY = 'rt-data-v1';
  const state = { books: {}, sessions: {}, timer: {}, view: 'today', range: 'day', dailyDays: 30, shelf: 'finished', histAll: false };
  let canSave = true;

  function load() {
    let raw = null;
    try { raw = localStorage.getItem(KEY); } catch (_) { canSave = false; }
    let data = null;
    if (raw) { try { data = JSON.parse(raw); } catch (_) { data = null; } }
    if (!data && window.RT_SEED) data = JSON.parse(JSON.stringify(window.RT_SEED));
    data = data || {};
    state.books = data.books || {}; state.sessions = data.sessions || {}; state.timer = data.timer || {};
    if (!raw) persist();
  }
  function persist() {
    try { localStorage.setItem(KEY, JSON.stringify({ books: state.books, sessions: state.sessions, timer: state.timer, savedAt: new Date().toISOString() })); return true; }
    catch (e) { canSave = false; toast(e && e.name === 'QuotaExceededError' ? 'Phone storage is full, so that wasn\'t saved.' : 'Couldn\'t save on this phone.'); return false; }
  }
  const store = {
    put(col, id, data) { state[col][id] = data; },
    patch(col, id, p) { state[col][id] = { ...state[col][id], ...p }; for (const k in p) if (p[k] === null) delete state[col][id][k]; },
    del(col, id) { delete state[col][id]; }
  };
  function commit() { const ok = persist(); render(); return ok; }
  const newId = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
  try { navigator.storage && navigator.storage.persist && navigator.storage.persist(); } catch (_) {}

  // ================= dates =================
  const pad = n => String(n).padStart(2, '0');
  const dayKey = d => d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
  const monthKey = d => d.getFullYear() + '-' + pad(d.getMonth() + 1);
  const parseDay = k => { const [y, m, d] = k.split('-').map(Number); return new Date(y, m - 1, d || 1); };
  const weekStart = d => { const x = new Date(d.getFullYear(), d.getMonth(), d.getDate()); x.setDate(x.getDate() - ((x.getDay() + 6) % 7)); return x; };
  const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
  const nowInput = () => { const d = new Date(); return dayKey(d) + 'T' + pad(d.getHours()) + ':' + pad(d.getMinutes()); };
  const MON = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const fmtDay = k => { const d = parseDay(k); return d.getDate() + ' ' + MON[d.getMonth()]; };
  const fmtDayLong = k => parseDay(k).toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
  const fmtMonth = k => { const d = parseDay(k); return MON[d.getMonth()] + ' ' + d.getFullYear(); };
  const fmtWhen = s => {
    const [day, time] = s.split('T'); const d = parseDay(day);
    return d.getDate() + ' ' + MON[d.getMonth()] + (d.getFullYear() !== new Date().getFullYear() ? ' ' + d.getFullYear() : '') + (time ? ', ' + time.slice(0, 5) : '');
  };
  const nf = n => Math.round(n).toLocaleString();

  // ================= derived =================
  const books = () => Object.entries(state.books).map(([id, b]) => ({ id, ...b }));
  const reading = () => books().filter(b => b.status === 'reading').sort((a, b) => (b.lastAt || b.addedAt || '').localeCompare(a.lastAt || a.addedAt || ''));
  const sessions = () => Object.entries(state.sessions).map(([id, s]) => ({ id, ...s })).filter(s => typeof s.day === 'string' && Number.isFinite(s.pages));
  const sessionsFor = id => sessions().filter(s => s.bookId === id).sort((a, b) => (a.startedAt > b.startedAt ? 1 : -1));
  function currentPage(b) {
    let p = Number(b.startPage) || 0;
    for (const s of Object.values(state.sessions)) if (s.bookId === b.id && s.endPage > p) p = s.endPage;
    return Math.min(p, b.totalPages);
  }
  function pagesByDay() { const m = {}; for (const s of sessions()) m[s.day] = (m[s.day] || 0) + Math.max(0, s.pages); return m; }
  const countFinishedThisMonth = () => books().filter(b => b.status === 'finished' && (b.finishedDay || '').slice(0, 7) === monthKey(new Date())).length;

  // ================= dom helpers =================
  const $ = s => document.querySelector(s);
  const h = (tag, attrs = {}, ...kids) => {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
      if (v == null || v === false) continue;
      if (k === 'class') el.className = v;
      else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
      else if (k === 'style') el.style.cssText = v;
      else el.setAttribute(k, v === true ? '' : v);
    }
    for (const kid of kids.flat()) if (kid != null && kid !== false) el.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
    return el;
  };
  const SVGNS = 'http://www.w3.org/2000/svg';
  const s = (tag, attrs = {}) => { const el = document.createElementNS(SVGNS, tag); for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v); return el; };
  const esc = v => String(v).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  function showErr(el, msg) { el.textContent = msg; el.hidden = !msg; }
  const buzz = ms => { try { navigator.vibrate && navigator.vibrate(ms); } catch (_) {} };

  let toastTimer;
  function toast(msg, good) {
    const t = $('#toast'); t.textContent = msg; t.className = good ? 'good' : ''; t.hidden = false;
    clearTimeout(toastTimer); toastTimer = setTimeout(() => { t.hidden = true; }, 3200);
  }
  const tip = $('#tip'); let tipTimer;
  function showTip(evt, html) {
    tip.innerHTML = html; tip.hidden = false;
    const r = tip.getBoundingClientRect();
    let x = evt.clientX - r.width / 2, y = evt.clientY - r.height - 14;
    x = Math.min(Math.max(8, x), innerWidth - r.width - 8);
    if (y < 8) y = evt.clientY + 16;
    tip.style.left = x + 'px'; tip.style.top = y + 'px';
    clearTimeout(tipTimer); tipTimer = setTimeout(hideTip, 2600);
  }
  const hideTip = () => { tip.hidden = true; };

  // sheets (bottom dialogs)
  function openSheet(el) { if (!el.open) el.showModal(); }
  function closeSheet(el) { if (el.open) el.close(); }
  document.querySelectorAll('dialog.sheet').forEach(d => {
    d.addEventListener('click', e => { if (e.target === d) closeSheet(d); });
    d.querySelectorAll('[data-close]').forEach(b => b.addEventListener('click', () => closeSheet(d)));
  });

  // confirm sheet, with an optional text field
  let confirmAction = null;
  function confirmSheet({ title, text, yes, field, onYes }) {
    $('#confirmHead').textContent = title; $('#confirmText').textContent = text || '';
    $('#confirmYes').textContent = yes;
    $('#confirmFieldWrap').hidden = !field;
    if (field) { $('#confirmFieldLabel').textContent = field.label; $('#confirmField').value = ''; $('#confirmField').placeholder = field.placeholder || ''; }
    confirmAction = onYes;
    openSheet($('#confirmSheet'));
  }
  $('#confirmYes').addEventListener('click', () => {
    const fn = confirmAction; confirmAction = null; closeSheet($('#confirmSheet'));
    if (fn) fn($('#confirmField').value);
  });

  // ================= charts =================
  function niceStep(max, target = 4) {
    const raw = Math.max(max, 1) / target, mag = Math.pow(10, Math.floor(Math.log10(raw))), n = raw / mag;
    return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10) * mag;
  }
  const compact = n => n >= 1000 ? (n / 1000).toFixed(1).replace(/\.0$/, '') + 'K' : String(n);
  function barPath(x, y, w, hgt, r) {
    r = Math.min(r, hgt, w / 2);
    return `M${x},${y + hgt}V${y + r}Q${x},${y} ${x + r},${y}H${x + w - r}Q${x + w},${y} ${x + w},${y + r}V${y + hgt}Z`;
  }
  function columnChart(container, data, opts = {}) {
    container.innerHTML = '';
    const W = Math.max(260, container.clientWidth || 340), H = 200;
    const m = { l: 30, r: 4, t: 18, b: 24 };
    const pw = W - m.l - m.r, ph = H - m.t - m.b;
    const max = Math.max(1, ...data.map(d => d.value + (d.stack ? d.stack.value : 0)));
    const step = opts.integer ? Math.max(1, Math.ceil(niceStep(max))) : niceStep(max);
    const top = Math.ceil(max / step) * step;
    const y = v => m.t + ph - (v / top) * ph;
    const svg = s('svg', { viewBox: `0 0 ${W} ${H}`, role: 'img', 'aria-label': opts.aria || '' });
    for (let v = 0; v <= top + 1e-9; v += step) {
      svg.append(s('line', { x1: m.l, x2: W - m.r, y1: y(v), y2: y(v), stroke: v === 0 ? 'var(--board-muted)' : 'var(--board-grid)', 'stroke-width': 1 }));
      const t = s('text', { x: m.l - 6, y: y(v) + 4, 'text-anchor': 'end' }); t.textContent = compact(v); svg.append(t);
    }
    const band = pw / data.length, bw = Math.min(22, Math.max(3, band * 0.68));
    const every = Math.max(1, Math.ceil(data.length / Math.max(1, pw / 50)));
    data.forEach((d, i) => {
      const cx = m.l + band * i + band / 2, x = cx - bw / 2;
      let base = 0;
      if (d.value > 0) {
        const hgt = Math.max(2, (d.value / top) * ph);
        svg.append(s('path', { d: barPath(x, m.t + ph - hgt, bw, hgt, 4), fill: d.color })); base = hgt + 2;
      }
      if (d.stack && d.stack.value > 0) {
        const h2 = Math.max(2, (d.stack.value / top) * ph);
        svg.append(s('path', { d: barPath(x, m.t + ph - base - h2, bw, h2, 4), fill: d.stack.color }));
      }
      if (d.cap) { const t = s('text', { x: cx, y: y(d.value + (d.stack ? d.stack.value : 0)) - 6, 'text-anchor': 'middle', class: 'cap' }); t.textContent = d.cap; svg.append(t); }
      const last = data.length - 1;
      if (i === last || (i % every === 0 && last - i >= every)) { const t = s('text', { x: cx, y: H - 6, 'text-anchor': 'middle' }); t.textContent = d.label; svg.append(t); }
      const hit = s('rect', { x: m.l + band * i, y: m.t, width: band, height: ph, fill: 'transparent', 'aria-label': d.aria || '' });
      hit.addEventListener('pointerdown', e => showTip(e, d.tip));
      svg.append(hit);
    });
    if (opts.avg > 0) {
      svg.append(s('line', { x1: m.l, x2: W - m.r, y1: y(opts.avg), y2: y(opts.avg), stroke: 'var(--board-fg)', 'stroke-width': 1.5, 'stroke-dasharray': '5 4', 'pointer-events': 'none' }));
      const t = s('text', { x: W - m.r, y: y(opts.avg) - 6, 'text-anchor': 'end', class: 'avg', 'pointer-events': 'none' }); t.textContent = opts.avgLabel; svg.append(t);
    }
    container.append(svg);
  }
  function sparkline(book) {
    const ss = sessionsFor(book.id), W = 300, H = 44, p = 5;
    const svg = s('svg', { class: 'spark', viewBox: `0 0 ${W} ${H}`, preserveAspectRatio: 'none', 'aria-hidden': 'true' });
    const pts = [];
    if (ss.length) {
      pts.push([parseDay(ss[0].day).getTime() - 864e5 * 0.5, Math.min(Number(book.startPage) || 0, ss[0].startPage)]);
      let mx = 0;
      for (const x of ss) { mx = Math.max(mx, x.endPage); pts.push([new Date(x.startedAt).getTime() || parseDay(x.day).getTime(), mx]); }
    }
    if (pts.length < 2) { svg.append(s('line', { x1: p, x2: W - p, y1: H - p, y2: H - p, stroke: 'var(--line)', 'stroke-width': 2, 'vector-effect': 'non-scaling-stroke' })); return svg; }
    const t0 = pts[0][0], t1 = Math.max(pts[pts.length - 1][0], t0 + 1);
    const X = t => p + ((t - t0) / (t1 - t0)) * (W - p * 2), Y = v => H - p - (v / book.totalPages) * (H - p * 2);
    let d = `M${X(pts[0][0])},${Y(pts[0][1])}`; for (let i = 1; i < pts.length; i++) d += `L${X(pts[i][0])},${Y(pts[i][1])}`;
    svg.append(s('path', { d: d + `L${X(pts[pts.length - 1][0])},${H - p}L${X(pts[0][0])},${H - p}Z`, fill: 'var(--brand)', 'fill-opacity': .12 }));
    svg.append(s('path', { d, fill: 'none', stroke: 'var(--brand-ink)', 'stroke-width': 2, 'stroke-linejoin': 'round', 'vector-effect': 'non-scaling-stroke' }));
    return svg;
  }

  // ================= navigation =================
  const TITLES = { today: 'Reading <mark>Tracker</mark>', books: 'My <mark>books</mark>', stats: 'The <mark>stats</mark>', log: 'Reading <mark>log</mark>' };
  function go(view, push = true) {
    if (!TITLES[view]) view = 'today';
    state.view = view;
    document.querySelectorAll('.view').forEach(v => { v.hidden = v.dataset.view !== view; });
    document.querySelectorAll('[data-go]').forEach(b => { if (b.dataset.go === view) b.setAttribute('aria-current', 'page'); else b.removeAttribute('aria-current'); });
    $('#viewTitle').innerHTML = TITLES[view];
    if (push && location.hash !== '#' + view) history.replaceState(null, '', '#' + view);
    window.scrollTo(0, 0);
    hideTip();
    render();
  }
  document.querySelectorAll('[data-go]').forEach(b => b.addEventListener('click', () => go(b.dataset.go)));

  // ================= render =================
  function render() {
    $('#todayLine').textContent = new Date().toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' });
    renderTimer();
    if (state.view === 'today') { renderScores(); renderToday(); }
    if (state.view === 'books') { renderReading(); renderShelf(); }
    if (state.view === 'stats') { renderMonth(); renderPagesChart(); renderDaily(); renderBooksChart(); }
    if (state.view === 'log') renderLog();
  }

  function vs(cur, prev, label) {
    if (!prev) return cur ? 'nothing ' + label + ' by now' : 'so far';
    const diff = cur - prev; return (diff >= 0 ? '+' : '−') + nf(Math.abs(diff)) + ' vs ' + label;
  }
  function renderScores() {
    const pbd = pagesByDay(), now = new Date(), today = dayKey(now), ws = weekStart(now), mk = monthKey(now);
    const lws = addDays(ws, -7), lm = monthKey(new Date(now.getFullYear(), now.getMonth() - 1, 1));
    let week = 0, month = 0, lastWeek = 0, lastMonth = 0;
    for (const [k, v] of Object.entries(pbd)) {
      const d = parseDay(k);
      if (d >= ws && d <= now) week += v;
      else if (d >= lws && d < ws && (d - lws) / 864e5 <= ((now.getDay() + 6) % 7)) lastWeek += v;
      if (k.slice(0, 7) === mk) month += v;
      else if (k.slice(0, 7) === lm && d.getDate() <= now.getDate()) lastMonth += v;
    }
    $('#sToday').textContent = nf(pbd[today] || 0);
    $('#sWeek').textContent = nf(week); $('#sWeekSub').textContent = 'pages · ' + vs(week, lastWeek, 'last week');
    $('#sMonth').textContent = nf(month); $('#sMonthSub').textContent = 'pages · ' + vs(month, lastMonth, 'last month');
    const fin = books().filter(b => b.status === 'finished' && (b.finishedDay || '').slice(0, 7) === mk).length;
    const dnf = books().filter(b => b.status === 'dnf' && (b.dnfDay || '').slice(0, 7) === mk).length;
    $('#sBooks').textContent = fin; $('#sBooksSub').textContent = (fin === 1 ? 'book' : 'books') + (dnf ? ` · ${dnf} written off` : '');
    let streak = 0, d = new Date(now);
    if (!pbd[dayKey(d)]) d = addDays(d, -1);
    while (pbd[dayKey(d)] > 0) { streak++; d = addDays(d, -1); }
    $('#sStreak').textContent = streak;
  }

  function progressBits(b) {
    const cp = currentPage(b), pct = Math.min(100, Math.round(cp / b.totalPages * 100)), left = b.totalPages - cp;
    const ss = sessionsFor(b.id), cut = dayKey(addDays(new Date(), -13));
    const pace = ss.filter(x => x.day >= cut).reduce((a, x) => a + x.pages, 0) / 14;
    const eta = pace > 0 ? Math.ceil(left / pace) : null;
    const line = ss.length ? (eta ? `${nf(left)} left · about ${eta} ${eta === 1 ? 'day' : 'days'} at your pace` : `${nf(left)} pages left`) : 'No sessions yet';
    return { cp, pct, left, line, ss };
  }

  function renderToday() {
    const list = reading(), wrap = $('#todayBooks'); wrap.innerHTML = '';
    $('#todayCount').textContent = list.length ? `${list.length} in progress` : '';
    $('#openLog').disabled = !list.length;
    if (!list.length) { wrap.append(h('div', { class: 'empty' }, 'Nothing on the go. Head to Books to add one.')); return; }
    for (const b of list) {
      const { cp, pct, line } = progressBits(b);
      wrap.append(h('button', { class: 'mini', type: 'button', style: 'border:0;text-align:left;font:inherit;color:inherit;cursor:pointer', onclick: () => openLog(b.id), 'aria-label': `Log pages for ${b.title}` },
        h('span', { class: 't' }, b.title),
        h('span', { class: 'pct' }, pct + '%'),
        h('span', { class: 'bar' }, h('i', { style: `width:${pct}%` })),
        h('span', { class: 'm' }, `Page ${nf(cp)} of ${nf(b.totalPages)} · ${line}`)));
    }
  }

  function renderReading() {
    const wrap = $('#readingCards'); wrap.innerHTML = '';
    const list = reading();
    if (!list.length) { wrap.append(h('div', { class: 'empty' }, 'Nothing on the go. Tap "Add a book" and it will show up here with its progress.')); return; }
    const t = activeTimer();
    for (const b of list) {
      const { cp, pct, line } = progressBits(b);
      wrap.append(h('article', { class: 'book' },
        h('div', { class: 'title-row' },
          h('div', { style: 'min-width:0' }, h('h3', {}, b.title), b.author ? h('p', { class: 'muted' }, b.author) : null),
          h('span', { class: 'pct' }, pct + '%')),
        h('div', { class: 'bar', role: 'progressbar', 'aria-valuemin': 0, 'aria-valuemax': b.totalPages, 'aria-valuenow': cp, 'aria-label': `${b.title} progress` }, h('i', { style: `width:${pct}%` })),
        h('div', { class: 'meta' }, h('span', {}, `Page ${nf(cp)} of ${nf(b.totalPages)}`), h('span', {}, line)),
        sparkline(b),
        h('div', { class: 'actions' },
          h('button', { class: 'btn small', type: 'button', onclick: () => openLog(b.id) }, 'Log pages'),
          h('button', { class: 'btn small neon', type: 'button', onclick: () => markFinished(b) }, 'Finished it'),
          !t ? h('button', { class: 'btn small ghost wide', type: 'button', onclick: () => { startTimer(b.id); go('today'); } }, 'Start timer')
            : t.bookId === b.id ? h('button', { class: 'btn small ghost wide', type: 'button', onclick: () => go('today') }, t.status === 'running' ? 'Timer running · open' : 'Timer paused · open') : null),
        h('div', { class: 'more' },
          h('button', { class: 'iconbtn', type: 'button', onclick: () => askDnf(b, cp) }, 'Did not finish'),
          h('button', { class: 'iconbtn', type: 'button', onclick: () => askDelete(b) }, 'Delete'))));
    }
  }

  function renderShelf() {
    const all = books();
    const fin = all.filter(b => b.status === 'finished').sort((a, b) => (b.finishedDay || '').localeCompare(a.finishedDay || ''));
    const dnf = all.filter(b => b.status === 'dnf').sort((a, b) => (b.dnfDay || '').localeCompare(a.dnfDay || ''));
    $('#tabFin').textContent = `Finished (${fin.length})`; $('#tabDnf').textContent = `Written off (${dnf.length})`;
    document.querySelectorAll('[data-shelf]').forEach(bt => bt.setAttribute('aria-pressed', String(bt.dataset.shelf === state.shelf)));
    const list = state.shelf === 'finished' ? fin : dnf, box = $('#shelfRows'); box.innerHTML = '';
    if (!list.length) {
      box.append(h('div', { class: 'empty' }, state.shelf === 'finished' ? 'Finished books land here. Log the last page, or tap "Finished it" on a book.' : 'Books you give up on land here. The pages you read still count.'));
      return;
    }
    const rows = h('div', { class: 'rows' });
    for (const b of list) {
      const cp = currentPage(b), ss = sessionsFor(b.id), isDnf = b.status === 'dnf';
      let sub;
      if (isDnf) sub = `${b.author ? b.author + ' · ' : ''}stopped on page ${cp} of ${b.totalPages} (${Math.round(cp / b.totalPages * 100)}%) · ${fmtDay(b.dnfDay)}${b.dnfNote ? ' · "' + b.dnfNote + '"' : ''}`;
      else {
        const first = ss[0] ? ss[0].day : null;
        const days = first && b.finishedDay ? Math.max(1, Math.round((parseDay(b.finishedDay) - parseDay(first)) / 864e5) + 1) : null;
        sub = `${b.author ? b.author + ' · ' : ''}${nf(b.totalPages)} pages · finished ${fmtDay(b.finishedDay)}${b.finishedDay.slice(0, 4) !== String(new Date().getFullYear()) ? ' ' + b.finishedDay.slice(0, 4) : ''}${days ? ` · took ${days} ${days === 1 ? 'day' : 'days'}` : ''}`;
      }
      rows.append(h('div', { class: 'row' + (isDnf ? ' dnf' : '') },
        h('div', {}, h('span', { class: 'pill ' + (isDnf ? 'dnf' : 'fin') }, isDnf ? 'DNF' : 'Done'), h('span', { class: 't' }, b.title)),
        h('div', { class: 's' }, sub),
        h('div', { class: 'acts' },
          h('button', { class: 'btn small ghost', type: 'button', onclick: () => restore(b) }, 'Back to reading'),
          h('button', { class: 'iconbtn', type: 'button', onclick: () => askDelete(b) }, 'Delete'))));
    }
    box.append(rows);
  }

  function renderMonth() {
    const now = new Date(), mk = monthKey(now), all = books();
    const monthName = now.toLocaleDateString(undefined, { month: 'long' });
    const lmDate = new Date(now.getFullYear(), now.getMonth() - 1, 1), lmk = monthKey(lmDate), lmName = lmDate.toLocaleDateString(undefined, { month: 'long' });
    const fin = all.filter(b => b.status === 'finished' && (b.finishedDay || '').slice(0, 7) === mk).sort((a, b) => a.finishedDay.localeCompare(b.finishedDay));
    const dnf = all.filter(b => b.status === 'dnf' && (b.dnfDay || '').slice(0, 7) === mk);
    const lastN = all.filter(b => b.status === 'finished' && (b.finishedDay || '').slice(0, 7) === lmk).length;
    const pbd = pagesByDay();
    let monthPages = 0; for (const [k, v] of Object.entries(pbd)) if (k.slice(0, 7) === mk) monthPages += v;
    const daysIn = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate(), left = daysIn - now.getDate();
    $('#monthHead').textContent = `Finished in ${monthName}`; $('#monthBig').textContent = fin.length;
    const diff = fin.length - lastN;
    const cmp = lastN || fin.length ? (diff === 0 ? `same as ${lmName}` : `${diff > 0 ? diff + ' more' : -diff + ' fewer'} than ${lmName}`) : '';
    $('#monthSub').textContent = [cmp, `${nf(monthPages)} pages read`, left ? `${left} ${left === 1 ? 'day' : 'days'} to go` : 'last day of the month'].filter(Boolean).join(' · ');

    const spines = $('#monthSpines'); spines.innerHTML = '';
    const height = p => Math.round(110 + Math.min(1, Math.max(0, (p - 100) / 600)) * 80);
    fin.forEach((b, i) => spines.append(h('div', { class: 'spine c' + (i % 4), role: 'listitem', 'aria-label': `${b.title}, finished ${fmtDay(b.finishedDay)}`, style: `height:${height(b.totalPages)}px` },
      h('span', { class: 'spine-t' }, b.title), h('span', { class: 'spine-d' }, parseDay(b.finishedDay).getDate()))));
    for (const b of dnf) spines.append(h('div', { class: 'spine dnf', role: 'listitem', 'aria-label': `${b.title}, written off`, style: `height:${height(b.totalPages)}px` },
      h('span', { class: 'spine-t' }, b.title), h('span', { class: 'spine-d' }, 'DNF')));
    const onGo = reading().map(b => ({ b, pct: Math.min(1, currentPage(b) / b.totalPages) })).sort((x, y) => y.pct - x.pct);
    for (const { b, pct } of onGo) spines.append(h('div', { class: 'spine ghost', role: 'listitem', 'aria-label': `On the go: ${b.title}, ${Math.round(pct * 100)}% read`, style: `height:${height(b.totalPages)}px` },
      h('i', { class: 'fill', style: `height:${Math.round(pct * 100)}%` }), h('span', { class: 'spine-t' }, b.title), h('span', { class: 'spine-d' }, Math.round(pct * 100) + '%')));

    const cal = $('#monthCal'); cal.innerHTML = '';
    for (const w of ['M', 'T', 'W', 'T', 'F', 'S', 'S']) cal.append(h('span', { class: 'wd', 'aria-hidden': 'true' }, w));
    const lead = (new Date(now.getFullYear(), now.getMonth(), 1).getDay() + 6) % 7;
    for (let i = 0; i < lead; i++) cal.append(h('span', { class: 'd blank' }));
    const finDays = new Set(fin.map(b => b.finishedDay));
    let readDays = 0;
    for (let d = 1; d <= daysIn; d++) {
      const k = mk + '-' + pad(d), p = pbd[k] || 0; if (p > 0) readDays++;
      cal.append(h('span', { class: ['d', finDays.has(k) ? 'fin' : p > 0 ? 'read' : '', d === now.getDate() ? 'today' : '', d > now.getDate() ? 'future' : ''].filter(Boolean).join(' ') }, d));
    }
    cal.setAttribute('aria-label', `${monthName}: read on ${readDays} days, finished ${fin.length}`);
  }

  function renderPagesChart() {
    const pbd = pagesByDay(), now = new Date(), r = state.range, data = [];
    const pink = 'var(--brand)', neon = 'var(--neon)';
    if (r === 'day') {
      for (let i = 13; i >= 0; i--) {
        const k = dayKey(addDays(now, -i)), v = pbd[k] || 0;
        data.push({ label: i === 0 ? 'Today' : fmtDay(k), value: v, color: i === 0 ? neon : pink, tip: `<b>${esc(fmtDayLong(k))}</b><br>${nf(v)} pages` });
      }
    } else if (r === 'week') {
      const ws = weekStart(now);
      for (let i = 7; i >= 0; i--) {
        const st = addDays(ws, -7 * i); let v = 0; for (let j = 0; j < 7; j++) v += pbd[dayKey(addDays(st, j))] || 0;
        data.push({ label: i === 0 ? 'This wk' : fmtDay(dayKey(st)), value: v, color: i === 0 ? neon : pink, tip: `<b>Week of ${esc(fmtDay(dayKey(st)))}</b><br>${nf(v)} pages · ${nf(v / 7)} a day` });
      }
    } else {
      for (let i = 11; i >= 0; i--) {
        const md = new Date(now.getFullYear(), now.getMonth() - i, 1), mk = monthKey(md);
        let v = 0; for (const [k, p] of Object.entries(pbd)) if (k.slice(0, 7) === mk) v += p;
        data.push({ label: MON[md.getMonth()].slice(0, i === 0 ? 3 : 1), value: v, color: i === 0 ? neon : pink, tip: `<b>${esc(fmtMonth(mk))}</b><br>${nf(v)} pages` });
      }
    }
    const total = data.reduce((a, d) => a + d.value, 0);
    $('#pagesSub').textContent = r === 'day' ? `${nf(total)} pages in the last 14 days · ${nf(total / 14)} a day`
      : r === 'week' ? `${nf(total)} pages in the last 8 weeks · ${nf(total / 8)} a week`
      : `${nf(total)} pages in the last 12 months`;
    $('#curKey').textContent = r === 'day' ? 'Today' : r === 'week' ? 'This week' : 'This month';
    document.querySelectorAll('[data-range]').forEach(x => x.setAttribute('aria-pressed', String(x.dataset.range === r)));
    columnChart($('#pagesChart'), data, { aria: 'Pages read per ' + r });
  }

  function renderBooksChart() {
    const now = new Date(), data = [], all = books(); let totalFin = 0;
    for (let i = 11; i >= 0; i--) {
      const md = new Date(now.getFullYear(), now.getMonth() - i, 1), mk = monthKey(md);
      const fin = all.filter(b => b.status === 'finished' && (b.finishedDay || '').slice(0, 7) === mk);
      const dnf = all.filter(b => b.status === 'dnf' && (b.dnfDay || '').slice(0, 7) === mk);
      totalFin += fin.length;
      data.push({ label: MON[md.getMonth()].slice(0, i === 0 ? 3 : 1), value: fin.length, color: 'var(--neon)', stack: { value: dnf.length, color: 'var(--gray)' }, cap: fin.length ? String(fin.length) : '',
        tip: `<b>${esc(fmtMonth(mk))}</b><br>${fin.length} finished${dnf.length ? `, ${dnf.length} written off` : ''}${fin.length ? '<br>' + fin.map(b => '· ' + esc(b.title)).join('<br>') : ''}` });
    }
    $('#booksSub').textContent = `${totalFin} ${totalFin === 1 ? 'book' : 'books'} in the last 12 months`;
    columnChart($('#booksChart'), data, { integer: true, aria: 'Books finished per month' });
  }

  function renderDaily() {
    const n = state.dailyDays, now = new Date(), pages = {}, mins = {};
    let pacePages = 0, paceMins = 0;
    const cut = dayKey(addDays(now, -(n - 1)));
    for (const x of sessions()) {
      if (x.day < cut) continue;
      pages[x.day] = (pages[x.day] || 0) + Math.max(0, x.pages);
      if (x.minutes > 0) { mins[x.day] = (mins[x.day] || 0) + x.minutes; pacePages += x.pages; paceMins += x.minutes; }
    }
    const pageDays = Object.keys(pages).filter(k => pages[k] > 0), minDays = Object.keys(mins);
    const avgP = pageDays.length ? pageDays.reduce((a, k) => a + pages[k], 0) / pageDays.length : 0;
    const avgM = minDays.length ? minDays.reduce((a, k) => a + mins[k], 0) / minDays.length : 0;
    const fmtMins = v => v >= 60 ? Math.floor(v / 60) + 'h ' + pad(Math.round(v % 60)) + 'm' : nf(v) + ' min';
    $('#avgMins').textContent = avgM >= 60 ? fmtMins(avgM) : nf(avgM);
    $('#avgMinsSub').textContent = (avgM >= 60 ? '' : 'minutes · ') + (minDays.length ? `${minDays.length} timed ${minDays.length === 1 ? 'day' : 'days'} of ${n}` : 'time a session to see this');
    $('#avgPages').textContent = nf(avgP);
    $('#avgPagesSub').textContent = 'pages · ' + (pageDays.length ? `read on ${pageDays.length} of ${n} days` : 'nothing logged yet');
    $('#dailySub').textContent = paceMins ? `About ${nf(pacePages / paceMins * 60)} pages an hour, from your timed sessions` : `Last ${n} days. Use the timer to see your pace`;
    const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'], md = [], pd = [];
    for (let i = n - 1; i >= 0; i--) {
      const d = addDays(now, -i), k = dayKey(d), label = i === 0 ? 'Today' : n === 7 ? WD[d.getDay()] : fmtDay(k);
      const m = mins[k] || 0, p = pages[k] || 0, tp = `<b>${esc(fmtDayLong(k))}</b><br>${m ? esc(fmtMins(m)) : 'No time logged'} · ${nf(p)} pages`;
      md.push({ label, value: m, color: 'var(--neon)', tip: tp }); pd.push({ label, value: p, color: 'var(--brand)', tip: tp });
    }
    columnChart($('#minsChart'), md, { aria: `Minutes read per day, last ${n} days`, avg: avgM, avgLabel: 'avg ' + fmtMins(avgM) });
    columnChart($('#dayPagesChart'), pd, { aria: `Pages read per day, last ${n} days`, avg: avgP, avgLabel: 'avg ' + nf(avgP) + ' pages' });
    document.querySelectorAll('[data-days]').forEach(x => x.setAttribute('aria-pressed', String(+x.dataset.days === n)));
  }

  function renderLog() {
    const all = sessions().sort((a, b) => (b.startedAt || '').localeCompare(a.startedAt || ''));
    $('#histCount').textContent = all.length ? `${all.length} sessions · ${nf(all.reduce((a, x) => a + x.pages, 0))} pages` : '';
    const box = $('#histList'); box.innerHTML = '';
    if (!all.length) { box.append(h('div', { class: 'empty' }, 'Every session you log shows up here.')); }
    const shown = state.histAll ? all : all.slice(0, 30);
    let lastDay = null;
    for (const x of shown) {
      if (x.day !== lastDay) { lastDay = x.day; box.append(h('div', { class: 'log-day' }, fmtDayLong(x.day))); }
      const b = state.books[x.bookId];
      box.append(h('div', { class: 'log-row' },
        h('div', { style: 'min-width:0' }, h('div', { class: 't' }, b ? b.title : 'Deleted book'),
          h('div', { class: 's' }, `${(x.startedAt || '').slice(11, 16) || ''}${x.startedAt && x.startedAt.length > 11 ? ' · ' : ''}p. ${x.startPage} → ${x.endPage}${x.minutes ? ' · ' + x.minutes + ' min' : ''}`)),
        h('div', { class: 'plus' }, '+' + x.pages),
        h('button', { class: 'iconbtn', type: 'button', 'aria-label': 'Delete this session', onclick: () => askDeleteSession(x) }, 'Delete')));
    }
    if (all.length > 30) box.append(h('div', { style: 'padding-top:12px' }, h('button', { class: 'btn small ghost', type: 'button', onclick: () => { state.histAll = !state.histAll; renderLog(); } }, state.histAll ? 'Show recent only' : `Show all ${all.length} sessions`)));
    $('#dataLine').textContent = (canSave ? 'Everything is saved on this phone.' : 'This phone isn\'t letting the app save, so changes may be lost.') + ` ${Object.keys(state.books).length} books and ${all.length} sessions. Save a backup now and then so you can move them to a new phone.`;
  }

  // ================= timer =================
  // One timer at a time, saved with the data so it keeps counting if the app is closed.
  const activeTimer = () => state.timer.active || null;
  const timerMs = t => (t.accumMs || 0) + (t.runningSince ? Math.max(0, Date.now() - t.runningSince) : 0);
  const timerMins = t => Math.max(1, Math.round(timerMs(t) / 60000));
  function fmtClock(ms) { const sec = Math.floor(ms / 1000), hr = Math.floor(sec / 3600), min = Math.floor(sec / 60) % 60; return (hr ? hr + ':' + pad(min) : String(min)) + ':' + pad(sec % 60); }
  let timerTick = null;
  function renderTimer() {
    const t = activeTimer(), status = t ? t.status : 'idle', acts = $('#timerActs');
    $('#timer').className = 'timer ' + status;
    acts.innerHTML = '';
    // the picker shows only when no timer is going
    const pick = $('#timerBook'), keep = pick.value, list = reading();
    pick.innerHTML = '';
    for (const b of list) pick.append(h('option', { value: b.id }, b.title));
    if (list.some(b => b.id === keep)) pick.value = keep;
    $('#timerPickWrap').hidden = !!t || !list.length;
    const b = t ? state.books[t.bookId] : null;
    $('#timerBookName').hidden = !t; $('#timerBookName').textContent = b ? b.title : 'Deleted book';
    $('#timerLog').hidden = !t || !b || status === 'running';
    if (!t) showErr($('#timerErr'), '');
    if (t && b) {
      const from = currentPage({ id: t.bookId, ...b }), inp = $('#timerTo');
      inp.min = from + 1; inp.max = b.totalPages; inp.placeholder = `${from + 1}–${b.totalPages}`;
      $('#timerFrom').textContent = `You started on page ${from}.`;
    }
    if (!t) {
      acts.append(h('button', { class: 'btn neon', type: 'button', disabled: !list.length, onclick: () => startTimer(pick.value) }, 'Start reading'));
      $('#timerNote').textContent = list.length ? 'Tap start when you open the book. It keeps counting even if you close the app.' : 'Add a book first, then time your reading.';
    } else if (!b) {
      acts.append(h('button', { class: 'btn ghost', type: 'button', onclick: discardTimer }, 'Discard'));
      $('#timerNote').textContent = 'The book for this timer was deleted.';
    } else if (status === 'running') {
      acts.append(h('button', { class: 'btn', type: 'button', onclick: pauseTimer }, 'Pause'), h('button', { class: 'btn neon', type: 'button', onclick: finishTimer }, 'Done'));
      $('#timerNote').textContent = `Started ${fmtWhen(t.startedAt)}.`;
    } else {
      acts.append(h('button', { class: 'btn neon', type: 'button', onclick: stopTimer }, 'Log it'), h('button', { class: 'btn', type: 'button', onclick: resumeTimer }, 'Resume'));
      $('#timerNote').textContent = 'Type the page you got to and tap Log it. ';
      $('#timerNote').append(h('button', { class: 'iconbtn', type: 'button', style: 'color:#111113;padding:0 4px;min-height:0;text-decoration:underline', onclick: discardTimer }, 'Discard this timer'));
    }
    clearInterval(timerTick); timerTick = null;
    if (status === 'running') timerTick = setInterval(tickTimer, 1000);
    tickTimer();
  }
  function tickTimer() { const t = activeTimer(); $('#timerClock').textContent = t ? fmtClock(timerMs(t)) : '0:00'; }
  function startTimer(bookId) {
    if (activeTimer() || !state.books[bookId]) return;
    $('#timerTo').value = '';
    store.put('timer', 'active', { bookId, startedAt: nowInput(), accumMs: 0, runningSince: Date.now(), status: 'running' });
    buzz(20); commit();
  }
  function pauseTimer() { const t = activeTimer(); if (!t || t.status !== 'running') return; store.patch('timer', 'active', { accumMs: timerMs(t), runningSince: null, status: 'paused' }); commit(); }
  function finishTimer() {
    const t = activeTimer(); if (!t) return;
    store.patch('timer', 'active', { accumMs: timerMs(t), runningSince: null, status: 'stopped' }); buzz(20); commit();
    setTimeout(() => $('#timerTo').focus(), 50);
  }
  function resumeTimer() { const t = activeTimer(); if (!t || t.status === 'running') return; store.patch('timer', 'active', { runningSince: Date.now(), status: 'running' }); commit(); }
  function stopTimer() {
    const t = activeTimer(); if (!t) return;
    const b = state.books[t.bookId], err = $('#timerErr'), inp = $('#timerTo'); if (!b) return;
    const from = currentPage({ id: t.bookId, ...b }), to = parseInt(inp.value, 10);
    const fail = msg => { showErr(err, msg); inp.focus(); };
    if (!Number.isFinite(to)) return fail('Type the page you finished on first.');
    if (to <= from) return fail(`You started on page ${from}, so the finishing page needs to be higher.`);
    if (to > b.totalPages) return fail(`This book has ${b.totalPages} pages, so the finishing page can't be higher.`);
    showErr(err, '');
    if (saveSession(t.bookId, t.startedAt, from, to, timerMins(t), true)) inp.value = '';
  }
  function discardTimer() { store.del('timer', 'active'); $('#timerTo').value = ''; commit(); toast('Timer discarded.'); }

  function saveSession(bookId, startedAt, from, to, mins, clearTimer) {
    const b = state.books[bookId], day = startedAt.slice(0, 10);
    store.put('sessions', newId(), { bookId, startedAt: startedAt.slice(0, 16), day, startPage: from, endPage: to, pages: to - from, minutes: mins, createdAt: new Date().toISOString() });
    const patch = { lastAt: new Date().toISOString() };
    if (to >= b.totalPages) Object.assign(patch, { status: 'finished', finishedDay: day });
    store.patch('books', bookId, patch);
    if (clearTimer) store.del('timer', 'active');
    if (!commit()) return false;
    buzz(30);
    if (to >= b.totalPages) toast(`You finished ${b.title}! That's ${countFinishedThisMonth()} this month.`, true);
    else toast(`Logged ${to - from} pages of ${b.title}${mins ? ` in ${mins} min` : ''}.`, true);
    return true;
  }

  // ================= book actions =================
  function markFinished(b) {
    store.patch('books', b.id, { status: 'finished', finishedDay: dayKey(new Date()), dnfDay: null, dnfNote: null });
    if (commit()) toast(`Finished ${b.title}. That's ${countFinishedThisMonth()} this month.`, true);
  }
  function askDnf(b, cp) {
    confirmSheet({ title: `Write off ${b.title}?`, text: `It stops on page ${cp} and moves to the shelf. Your pages still count.`, yes: 'Write it off',
      field: { label: 'Why? (optional)', placeholder: 'e.g. Slow middle, not for me' },
      onYes: note => { store.patch('books', b.id, { status: 'dnf', dnfDay: dayKey(new Date()), dnfNote: (note || '').trim().slice(0, 200) || null, finishedDay: null }); if (commit()) toast(`${b.title} written off. On to the next one.`); } });
  }
  function restore(b) { store.patch('books', b.id, { status: 'reading', finishedDay: null, dnfDay: null, dnfNote: null }); if (commit()) toast(`${b.title} is back on the go.`); }
  function askDelete(b) {
    const n = sessionsFor(b.id).length;
    confirmSheet({ title: `Delete ${b.title}?`, text: `This removes the book and its ${n} ${n === 1 ? 'session' : 'sessions'}. It can't be undone.`, yes: 'Delete book',
      onYes: () => { for (const [id, x] of Object.entries(state.sessions)) if (x.bookId === b.id) store.del('sessions', id); if (activeTimer() && activeTimer().bookId === b.id) store.del('timer', 'active'); store.del('books', b.id); commit(); toast(`Deleted ${b.title}.`); } });
  }
  function askDeleteSession(x) {
    const b = state.books[x.bookId];
    confirmSheet({ title: 'Delete this session?', text: `${x.pages} pages${b ? ' of ' + b.title : ''} on ${fmtWhen(x.startedAt || x.day)}.`, yes: 'Delete session',
      onYes: () => { store.del('sessions', x.id); commit(); toast('Session deleted.'); } });
  }

  // ================= log sheet =================
  function openLog(bookId) {
    const sel = $('#logBook'), list = reading();
    if (!list.length) return;
    sel.innerHTML = '';
    for (const b of list) sel.append(h('option', { value: b.id }, b.title + (b.author ? ' — ' + b.author : '')));
    sel.value = bookId && list.some(b => b.id === bookId) ? bookId : list[0].id;
    $('#logStart').value = nowInput(); $('#logTo').value = ''; $('#logMins').value = ''; showErr($('#logErr'), '');
    fillFrom(); updatePreview();
    openSheet($('#logSheet'));
  }
  function fillFrom() {
    const id = $('#logBook').value, b = state.books[id]; if (!b) return;
    const cp = currentPage({ id, ...b });
    $('#logFrom').value = cp; $('#logTo').min = cp + 1; $('#logTo').max = b.totalPages; $('#logTo').placeholder = 'up to ' + b.totalPages;
  }
  function updatePreview() {
    const b = state.books[$('#logBook').value], from = parseInt($('#logFrom').value, 10), to = parseInt($('#logTo').value, 10), p = $('#logPreview');
    if (!b || !Number.isFinite(from) || !Number.isFinite(to) || to <= from) { p.textContent = b ? `${b.totalPages - (Number.isFinite(from) ? from : 0)} pages left in this book.` : ''; return; }
    p.textContent = to >= b.totalPages ? `${to - from} pages, and that's the end of the book.` : `${to - from} pages. You'll be ${Math.round(to / b.totalPages * 100)}% through.`;
  }
  $('#openLog').addEventListener('click', () => openLog());
  $('#logBook').addEventListener('change', () => { fillFrom(); updatePreview(); });
  ['#logFrom', '#logTo'].forEach(sel => $(sel).addEventListener('input', updatePreview));
  $('#logForm').addEventListener('submit', e => {
    e.preventDefault();
    const err = $('#logErr'), bookId = $('#logBook').value, b = state.books[bookId];
    if (!b) return showErr(err, 'Pick a book.');
    const startedAt = $('#logStart').value;
    if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(startedAt)) return showErr(err, 'Add the date and time you started.');
    const from = parseInt($('#logFrom').value, 10), to = parseInt($('#logTo').value, 10);
    const mins = $('#logMins').value === '' ? null : parseInt($('#logMins').value, 10);
    if (!Number.isFinite(from) || from < 0) return showErr(err, 'Add the page you started on.');
    if (!Number.isFinite(to)) return showErr(err, 'Add the page you finished on.');
    if (to <= from) return showErr(err, 'The finishing page needs to be after the starting page.');
    if (to > b.totalPages) return showErr(err, `This book has ${b.totalPages} pages, so the finishing page can't be higher.`);
    if (mins != null && (!Number.isFinite(mins) || mins < 1)) return showErr(err, 'Minutes should be a whole number, or leave it empty.');
    showErr(err, '');
    if (saveSession(bookId, startedAt, from, to, mins, false)) closeSheet($('#logSheet'));
  });
  $('#timerTo').addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); stopTimer(); } });

  // ================= add book + barcode =================
  $('#openAdd').addEventListener('click', () => { $('#addForm').reset(); setScanStatus(''); showErr($('#addErr'), ''); openSheet($('#addSheet')); });
  $('#addSheet').addEventListener('close', stopCamera);

  function ean13ok(v) { let t = 0; for (let i = 0; i < 13; i++) t += +v[i] * (i % 2 ? 3 : 1); return t % 10 === 0; }
  function normIsbn(raw) {
    const v = String(raw || '').replace(/[^0-9Xx]/g, '').toUpperCase();
    if (v.length === 13 && /^97[89]\d{10}$/.test(v) && ean13ok(v)) return v;
    if (v.length === 10 && /^\d{9}[\dX]$/.test(v)) {
      let t = 0; for (let i = 0; i < 10; i++) t += (10 - i) * (v[i] === 'X' ? 10 : +v[i]);
      if (t % 11) return null;
      const b = '978' + v.slice(0, 9); let c = 0; for (let i = 0; i < 12; i++) c += +b[i] * (i % 2 ? 3 : 1);
      return b + ((10 - c % 10) % 10);
    }
    return null;
  }
  function setScanStatus(msg, kind) { const el = $('#scanStatus'); el.textContent = msg; el.hidden = !msg; el.className = 'scan-status' + (kind ? ' ' + kind : ''); }

  let zxingLoad = null;
  function loadZXing() {
    if (window.ZXing) return Promise.resolve(window.ZXing);
    return zxingLoad || (zxingLoad = new Promise((res, rej) => {
      const sc = document.createElement('script');
      sc.src = 'vendor/zxing.min.js';
      sc.onload = () => window.ZXing ? res(window.ZXing) : rej(new Error('missing'));
      sc.onerror = () => { zxingLoad = null; rej(new Error('load failed')); };
      document.head.append(sc);
    }));
  }
  const FORMATS = ['ean_13', 'upc_a', 'ean_8'];
  let detector = null;
  async function getDetector() {
    if (detector !== null) return detector;
    try {
      if ('BarcodeDetector' in window) {
        const ok = await BarcodeDetector.getSupportedFormats();
        if (ok.includes('ean_13')) return (detector = new BarcodeDetector({ formats: FORMATS.filter(f => ok.includes(f)) }));
      }
    } catch (_) {}
    return (detector = false);
  }
  let zxReader = null;
  async function getReader() {
    if (zxReader) return zxReader;
    const ZX = await loadZXing();
    const hints = new Map();
    hints.set(ZX.DecodeHintType.POSSIBLE_FORMATS, [ZX.BarcodeFormat.EAN_13, ZX.BarcodeFormat.UPC_A, ZX.BarcodeFormat.EAN_8]);
    hints.set(ZX.DecodeHintType.TRY_HARDER, true);
    const reader = new ZX.MultiFormatReader(); reader.setHints(hints);
    return (zxReader = { ZX, reader });
  }
  function zxDecode({ ZX, reader }, canvas) {
    try { return reader.decode(new ZX.BinaryBitmap(new ZX.HybridBinarizer(new ZX.HTMLCanvasElementLuminanceSource(canvas)))).getText(); }
    catch (_) { return null; } finally { try { reader.reset(); } catch (_) {} }
  }
  // A photo: try a few sizes, upright and turned, since the barcode can be anywhere.
  async function decodeWithZXing(source) {
    const r = await getReader();
    for (const side of [1200, 800, 1800]) for (const rot of [false, true]) { const c = zxDecode(r, drawScaled(source, side, rot)); if (c) return c; }
    return null;
  }
  // A live camera frame: only the band inside the green box, which is quicker and sharper.
  const band = document.createElement('canvas');
  async function decodeVideoFrame(v) {
    const r = await getReader();
    const vw = v.videoWidth, vh = v.videoHeight; if (!vw || !vh) return null;
    // the green box covers the middle 80% across and 40% down of what the viewer sees (object-fit: cover, 4:3)
    const viewRatio = 4 / 3, srcRatio = vw / vh;
    let sw = vw, sh = vh, sx = 0, sy = 0;
    if (srcRatio > viewRatio) { sw = vh * viewRatio; sx = (vw - sw) / 2; } else { sh = vw / viewRatio; sy = (vh - sh) / 2; }
    const cx = sx + sw * 0.05, cy = sy + sh * 0.25, cw = sw * 0.9, ch = sh * 0.5;
    const k = Math.min(1, 1000 / cw);
    band.width = Math.round(cw * k); band.height = Math.round(ch * k);
    band.getContext('2d', { willReadFrequently: true }).drawImage(v, cx, cy, cw, ch, 0, 0, band.width, band.height);
    return zxDecode(r, band);
  }
  function drawScaled(src, maxSide, rot) {
    const w = src.videoWidth || src.width, hh = src.videoHeight || src.height, k = Math.min(1, maxSide / Math.max(w, hh));
    const cw = Math.round(w * k), ch = Math.round(hh * k), c = document.createElement('canvas');
    c.width = rot ? ch : cw; c.height = rot ? cw : ch;
    const g = c.getContext('2d', { willReadFrequently: true });
    if (rot) { g.translate(c.width / 2, c.height / 2); g.rotate(Math.PI / 2); g.drawImage(src, -cw / 2, -ch / 2, cw, ch); } else g.drawImage(src, 0, 0, cw, ch);
    return c;
  }

  // Live camera: point at the barcode and it reads itself. Falls back to taking a photo.
  let camStream = null, camLoop = null;
  async function startCamera() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) { $('#scanFile').value = ''; $('#scanFile').click(); return; }
    try {
      camStream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: 'environment' }, width: { ideal: 1920 } }, audio: false });
    } catch (_) {
      setScanStatus('No camera access, so take a photo of the barcode instead.', 'warn');
      $('#scanFile').value = ''; $('#scanFile').click(); return;
    }
    const v = $('#camVideo'); v.srcObject = camStream; $('#camera').hidden = false; $('#scanBtn').hidden = true;
    await v.play().catch(() => {});
    setScanStatus('Hold the barcode inside the green box.', 'busy');
    const det = await getDetector();
    if (!det) getReader().catch(() => {});
    let busy = false, tries = 0;
    camLoop = setInterval(async () => {
      if (busy || !camStream || v.readyState < 2) return;
      busy = true; tries++;
      try {
        let code = null;
        if (det) { const f = await det.detect(v); const hit = f.find(x => normIsbn(x.rawValue)) || f[0]; code = hit && hit.rawValue; }
        else code = await decodeVideoFrame(v);
        if (code) { const isbn = normIsbn(code); if (isbn) { stopCamera(); buzz(40); $('#addIsbn').value = isbn; await lookupIsbn(isbn); } }
      } catch (_) {}
      busy = false;
    }, det ? 250 : 200);
  }
  function stopCamera() {
    clearInterval(camLoop); camLoop = null;
    if (camStream) camStream.getTracks().forEach(t => t.stop());
    camStream = null; $('#camera').hidden = true; $('#scanBtn').hidden = false;
    if ($('#scanStatus').classList.contains('busy') && /green box/.test($('#scanStatus').textContent)) setScanStatus('');
  }
  $('#scanBtn').addEventListener('click', startCamera);
  $('#camStop').addEventListener('click', stopCamera);
  $('#scanFile').addEventListener('change', async e => {
    const file = e.target.files && e.target.files[0]; if (!file) return;
    setScanStatus('Reading the barcode…', 'busy');
    let bmp;
    try { bmp = await createImageBitmap(file); } catch (_) { const img = new Image(); img.src = URL.createObjectURL(file); try { await img.decode(); bmp = img; } catch (_) { return setScanStatus("Couldn't open that photo.", 'warn'); } }
    let code = null;
    const det = await getDetector();
    try { if (det) { const f = await det.detect(bmp); code = f[0] && f[0].rawValue; } if (!code) code = await decodeWithZXing(bmp); }
    catch (_) { return setScanStatus("The barcode reader didn't load. Check your connection, or type the ISBN.", 'warn'); }
    if (!code) return setScanStatus("Couldn't find a barcode. Fill the frame with it, keep it sharp and try again, or type the ISBN.", 'warn');
    const isbn = normIsbn(code);
    if (!isbn) return setScanStatus(`That barcode (${code}) isn't a book ISBN. Look for the one starting 978 or 979.`, 'warn');
    $('#addIsbn').value = isbn; await lookupIsbn(isbn);
  });

  async function fetchJson(url) { const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 8000); try { const r = await fetch(url, { signal: ctl.signal }); if (!r.ok) throw new Error(r.status); return await r.json(); } finally { clearTimeout(t); } }
  async function lookupIsbn(isbn) {
    const have = books().find(b => b.isbn === isbn);
    if (have) { setScanStatus(`You already have ${have.title} (${have.status === 'reading' ? 'on the go' : have.status === 'finished' ? 'finished' : 'written off'}).`, 'warn'); return; }
    setScanStatus(`Got ISBN ${isbn}. Looking up the book…`, 'busy');
    let found = null;
    try {
      const j = await fetchJson(`https://openlibrary.org/api/books?bibkeys=ISBN:${isbn}&format=json&jscmd=data`);
      const r = j && j['ISBN:' + isbn];
      if (r && r.title) found = { title: r.title + (r.subtitle ? ': ' + r.subtitle : ''), author: (r.authors || []).map(a => a.name).join(', '), pages: r.number_of_pages || null };
    } catch (_) {}
    if (!found || !found.pages) {
      try {
        const j = await fetchJson(`https://www.googleapis.com/books/v1/volumes?q=isbn:${isbn}`);
        const v = j && j.items && j.items[0] && j.items[0].volumeInfo;
        if (v && v.title) found = { title: (found && found.title) || v.title + (v.subtitle ? ': ' + v.subtitle : ''), author: (found && found.author) || (v.authors || []).join(', '), pages: (found && found.pages) || v.pageCount || null };
      } catch (_) {}
    }
    if (!found) { setScanStatus(navigator.onLine === false ? `Got ISBN ${isbn}. You're offline, so fill in the details below.` : `Got ISBN ${isbn}, but couldn't find the book. Fill in the details below.`, 'warn'); $('#addTitle').focus(); return; }
    $('#addTitle').value = found.title.slice(0, 200);
    if (found.author) $('#addAuthor').value = found.author.slice(0, 200);
    if (found.pages) $('#addPages').value = found.pages;
    setScanStatus(`Found: ${found.title}${found.author ? ' by ' + found.author : ''}${found.pages ? `, ${found.pages} pages` : ''}. ` + (found.pages ? 'Editions differ, so check the last page of your copy.' : 'Add the number of pages from your copy.'), 'ok');
  }
  $('#isbnLookup').addEventListener('click', async () => {
    const raw = $('#addIsbn').value.trim();
    if (!raw) { setScanStatus('Type the 13-digit number under the barcode, or tap Scan.', 'warn'); return; }
    const isbn = normIsbn(raw);
    if (!isbn) { setScanStatus("That doesn't look like an ISBN. It's the 13-digit number starting 978 or 979.", 'warn'); return; }
    $('#addIsbn').value = isbn; await lookupIsbn(isbn);
  });
  $('#addIsbn').addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); $('#isbnLookup').click(); } });

  $('#addForm').addEventListener('submit', e => {
    e.preventDefault();
    const err = $('#addErr'), title = $('#addTitle').value.trim(), author = $('#addAuthor').value.trim();
    const pages = parseInt($('#addPages').value, 10), at = $('#addAt').value === '' ? 0 : parseInt($('#addAt').value, 10);
    if (!title) return showErr(err, 'Add the book name.');
    if (!Number.isFinite(pages) || pages < 1) return showErr(err, 'Number of pages should be 1 or more.');
    if (!Number.isFinite(at) || at < 0 || at >= pages) return showErr(err, `"Already on page" should be between 0 and ${pages - 1}.`);
    const isbnRaw = $('#addIsbn').value.trim(), isbn = isbnRaw ? normIsbn(isbnRaw) : null;
    if (isbnRaw && !isbn) return showErr(err, "That ISBN doesn't look right. Clear it or check the number.");
    showErr(err, '');
    const nowIso = new Date().toISOString();
    store.put('books', newId(), { title: title.slice(0, 200), author: author.slice(0, 200), totalPages: pages, startPage: at, isbn, status: 'reading', addedAt: nowIso, lastAt: nowIso });
    if (commit()) { closeSheet($('#addSheet')); toast(`Added ${title}.`, true); }
  });

  // ================= backup =================
  $('#exportBtn').addEventListener('click', async () => {
    const json = JSON.stringify({ app: 'reading-tracker', version: 1, exportedAt: new Date().toISOString(), books: state.books, sessions: state.sessions, timer: state.timer }, null, 1);
    const name = `reading-tracker-${dayKey(new Date())}.json`;
    const file = new File([json], name, { type: 'application/json' });
    try { if (navigator.canShare && navigator.canShare({ files: [file] })) { await navigator.share({ files: [file], title: 'Reading Tracker backup' }); return; } } catch (e) { if (e && e.name === 'AbortError') return; }
    const a = h('a', { href: URL.createObjectURL(file), download: name }); document.body.append(a); a.click(); a.remove();
    toast('Backup saved.', true);
  });
  $('#importBtn').addEventListener('click', () => { $('#importFile').value = ''; $('#importFile').click(); });
  $('#importFile').addEventListener('change', async e => {
    const f = e.target.files && e.target.files[0]; if (!f) return;
    let data; try { data = JSON.parse(await f.text()); } catch (_) { return toast("That file isn't a Reading Tracker backup."); }
    if (!data || typeof data.books !== 'object' || typeof data.sessions !== 'object') return toast("That file isn't a Reading Tracker backup.");
    const nb = Object.keys(data.books).length, ns = Object.keys(data.sessions).length;
    confirmSheet({ title: 'Restore this backup?', text: `It has ${nb} books and ${ns} sessions, and replaces what's on this phone now.`, yes: 'Restore',
      onYes: () => { state.books = data.books; state.sessions = data.sessions; state.timer = data.timer || {}; commit(); toast('Backup restored.', true); } });
  });

  // ================= wiring =================
  document.querySelectorAll('[data-shelf]').forEach(bt => bt.addEventListener('click', () => { state.shelf = bt.dataset.shelf; renderShelf(); }));
  document.querySelectorAll('[data-range]').forEach(bt => bt.addEventListener('click', () => { state.range = bt.dataset.range; try { localStorage.setItem('rt-range', state.range); } catch (_) {} renderPagesChart(); }));
  document.querySelectorAll('[data-days]').forEach(bt => bt.addEventListener('click', () => { state.dailyDays = +bt.dataset.days; try { localStorage.setItem('rt-daily', bt.dataset.days); } catch (_) {} renderDaily(); }));
  document.addEventListener('visibilitychange', () => { if (!document.hidden) render(); });
  addEventListener('storage', e => { if (e.key === KEY) { load(); render(); } });
  let rz; addEventListener('resize', () => { clearTimeout(rz); rz = setTimeout(() => { if (state.view === 'stats') { renderPagesChart(); renderDaily(); renderBooksChart(); } }, 120); });
  document.addEventListener('scroll', hideTip, { passive: true });

  try { const r = localStorage.getItem('rt-range'); if (['day', 'week', 'month'].includes(r)) state.range = r; } catch (_) {}
  try { const d = +localStorage.getItem('rt-daily'); if ([7, 30, 90].includes(d)) state.dailyDays = d; } catch (_) {}
  load();
  go((location.hash || '').slice(1) || 'today', false);

  if ('serviceWorker' in navigator && location.protocol !== 'file:') navigator.serviceWorker.register('sw.js').catch(() => {});
  window.__rt = { state, render };
})();
