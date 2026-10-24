(() => {
  const root = document.documentElement;
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ---------- language (EN in markup, IT from i18n.js) ----------
  const LANG_KEY = 'tully-lang';
  const nodes = [...document.querySelectorAll('[data-i18n]')];
  const english = new Map(nodes.map(n => [n, n.innerHTML]));
  const langBtn = document.getElementById('lang');
  let lang = 'en';
  try { lang = localStorage.getItem(LANG_KEY) || (navigator.language.startsWith('it') ? 'it' : 'en') } catch { /* storage blocked */ }

  function applyLang(next) {
    lang = next;
    root.lang = next;
    // static first-party strings only
    nodes.forEach(n => { n.innerHTML = next === 'it' ? (window.I18N.it[n.dataset.i18n] ?? english.get(n)) : english.get(n) });
    langBtn.textContent = next === 'it' ? 'EN' : 'IT';
    langBtn.setAttribute('aria-label', next === 'it' ? 'Switch to English' : 'Passa all\'italiano');
    try { localStorage.setItem(LANG_KEY, next) } catch { /* storage blocked */ }
    dial?.relabel();
  }
  langBtn.addEventListener('click', () => applyLang(lang === 'it' ? 'en' : 'it'));

  // ---------- Window Ring demo ----------
  const ZONES = [ // angle (deg, 0 = right, counter-clockwise), name, preview rect as viewport fractions
    [0, 'Right Half', 'Metà destra', [.5, 0, .5, 1]],
    [45, 'Top Right', 'In alto a destra', [.5, 0, .5, .5]],
    [90, 'Top Half', 'Metà superiore', [0, 0, 1, .5]],
    [135, 'Top Left', 'In alto a sinistra', [0, 0, .5, .5]],
    [180, 'Left Half', 'Metà sinistra', [0, 0, .5, 1]],
    [225, 'Bottom Left', 'In basso a sinistra', [0, .5, .5, .5]],
    [270, 'Bottom Half', 'Metà inferiore', [0, .5, 1, .5]],
    [315, 'Bottom Right', 'In basso a destra', [.5, .5, .5, .5]]
  ];
  const DEAD_ZONE = 34;
  const ring = document.getElementById('ring');
  const svg = document.getElementById('ringSvg');
  const ringLabel = document.getElementById('ringLabel');
  const zone = Object.assign(document.createElement('div'), { className: 'zone' });
  document.body.append(zone);
  const NS = 'http://www.w3.org/2000/svg';

  const polar = (r, deg) => [r * Math.cos(deg * Math.PI / 180), -r * Math.sin(deg * Math.PI / 180)];
  const paths = ZONES.map(([deg, , , rect]) => {
    const [a, b] = [deg - 22, deg + 22];
    const [x1, y1] = polar(100, a), [x2, y2] = polar(100, b), [x3, y3] = polar(40, b), [x4, y4] = polar(40, a);
    const p = document.createElementNS(NS, 'path');
    p.setAttribute('d', `M${x1} ${y1}A100 100 0 0 0 ${x2} ${y2}L${x3} ${y3}A40 40 0 0 1 ${x4} ${y4}Z`);
    svg.append(p);
    // tiny window glyph with the target area filled
    const [cx, cy] = polar(70, deg);
    const frame = document.createElementNS(NS, 'rect');
    Object.entries({ x: cx - 9, y: cy - 7, width: 18, height: 14, rx: 2, class: 'glyph' }).forEach(([k, v]) => frame.setAttribute(k, v));
    const fill = document.createElementNS(NS, 'rect');
    Object.entries({ x: cx - 9 + rect[0] * 18, y: cy - 7 + rect[1] * 14, width: rect[2] * 18, height: rect[3] * 14, class: 'glyph-fill' }).forEach(([k, v]) => fill.setAttribute(k, v));
    svg.append(frame, fill);
    return p;
  });
  const hubCircle = document.createElementNS(NS, 'circle');
  hubCircle.setAttribute('r', 38);
  svg.append(hubCircle);

  let ringOpen = false, ox = 0, oy = 0, mx = innerWidth / 2, my = innerHeight / 2, picked = -1;

  function openRing(x, y) {
    if (ringOpen) return;
    ringOpen = true; ox = x; oy = y;
    ring.style.translate = `${x}px ${y}px`;
    root.classList.add('ring-on');
    pick(x, y);
  }
  function closeRing() {
    if (!ringOpen) return;
    ringOpen = false;
    root.classList.remove('ring-on');
  }
  function pick(x, y) {
    const dx = x - ox, dy = y - oy;
    picked = Math.hypot(dx, dy) < DEAD_ZONE ? -1 : Math.round(((Math.atan2(-dy, dx) * 180 / Math.PI + 360) % 360) / 45) % 8;
    paths.forEach((p, i) => p.classList.toggle('on', i === picked));
    ringLabel.textContent = picked < 0 ? (lang === 'it' ? 'Annulla' : 'Cancel') : ZONES[picked][lang === 'it' ? 2 : 1];
    const [fx, fy, fw, fh] = picked < 0 ? [.5, .5, 0, 0] : ZONES[picked][3];
    const top = 60, h = innerHeight - top - 8, w = innerWidth - 16;
    Object.assign(zone.style, { left: `${8 + fx * w}px`, top: `${top + fy * h}px`, width: `${fw * w}px`, height: `${fh * h}px` });
  }

  const keys = document.getElementById('ringKeys');
  keys.addEventListener('pointerdown', e => { keys.setPointerCapture(e.pointerId); openRing(e.clientX, e.clientY) });
  addEventListener('pointerup', closeRing);
  addEventListener('pointercancel', closeRing);
  addEventListener('pointermove', e => { mx = e.clientX; my = e.clientY; if (ringOpen) pick(mx, my) }, { passive: true });
  addEventListener('keydown', e => { if (e.ctrlKey && e.altKey && (e.key === 'Control' || e.key === 'Alt')) openRing(mx, my) });
  addEventListener('keyup', e => { if (e.key === 'Control' || e.key === 'Alt' || e.key === 'Escape') closeRing() });
  addEventListener('blur', closeRing);

  // ---------- converter wheels ----------
  const wheel = document.getElementById('wheel');
  const cvKeys = [...document.querySelectorAll('.cv-key')];
  function selectWheel(btn) {
    cvKeys.forEach(b => { b.classList.toggle('on', b === btn); b.setAttribute('aria-selected', b === btn) });
    const src = `assets/wheel-${btn.dataset.wheel}.png`;
    if (wheel.getAttribute('src') === src) return;
    if (still) { wheel.src = src; return }
    wheel.classList.add('spin');
    setTimeout(() => { wheel.src = src; wheel.alt = btn.querySelector('b').textContent; wheel.decode().finally(() => wheel.classList.remove('spin')) }, 250);
  }
  cvKeys.forEach(b => {
    b.addEventListener('click', () => selectWheel(b));
    b.addEventListener('mouseenter', () => selectWheel(b));
  });
  // real modifier keys work too while the section is on screen
  const MOD_TO_WHEEL = { Shift: 'convert', Meta: 'tools', Control: 'actions' };
  addEventListener('keydown', e => {
    const name = MOD_TO_WHEEL[e.key];
    const box = document.getElementById('convert').getBoundingClientRect();
    if (name && !ringOpen && box.top < innerHeight && box.bottom > 0) selectWheel(cvKeys.find(b => b.dataset.wheel === name));
  });

  // ---------- reveal on scroll ----------
  const io = new IntersectionObserver(entries => entries.forEach(e => { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target) } }), { threshold: .15 });
  document.querySelectorAll('.sec-head, .mb-shot, .cv-grid, .strip, .table, .steps').forEach(el => { el.classList.add('reveal'); io.observe(el) });

  // ---------- dial (needs three.js) ----------
  let dial = null;
  try {
    if (window.THREE) dial = window.initDial(() => lang);
  } catch (err) {
    console.error('Dial failed to start', err);
  }
  if (!dial) document.querySelector('.dial-track').classList.add('no-gl');

  if (lang !== 'en') applyLang(lang);
})();
