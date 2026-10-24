// ASCII-art wave behind the page: two interfering swells plus a ripple that follows the pointer.
(() => {
  const canvas = document.createElement('canvas');
  canvas.id = 'ascii';
  canvas.setAttribute('aria-hidden', 'true');
  document.body.prepend(canvas);
  const ctx = canvas.getContext('2d');

  const RAMP = ' .·:-~=+*#';
  const CELL_H = 16;
  const FRAME_MS = 1000 / 30; // ponytail: 30 fps is plenty for a backdrop
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches;

  let cols = 0, rows = 0, cellW = 0, inkFill, sigFill;
  let mx = -1e4, my = -1e4, last = 0;

  function resize() {
    const dpr = Math.min(devicePixelRatio, 2);
    canvas.width = innerWidth * dpr;
    canvas.height = innerHeight * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.font = '12px "JetBrains Mono", ui-monospace, monospace';
    ctx.textBaseline = 'top';
    cellW = ctx.measureText('M').width;
    cols = Math.ceil(innerWidth / cellW);
    rows = Math.ceil(innerHeight / CELL_H);
    // fade the wave in towards the bottom of the viewport
    inkFill = ctx.createLinearGradient(0, 0, 0, innerHeight);
    inkFill.addColorStop(0, '#16151a0a');
    inkFill.addColorStop(.6, '#16151a16');
    inkFill.addColorStop(1, '#16151a2c');
    sigFill = ctx.createLinearGradient(0, 0, 0, innerHeight);
    sigFill.addColorStop(0, '#3385ff40');
    sigFill.addColorStop(1, '#593deb80');
    if (still) draw(0);
  }

  // two water surfaces: a far one (higher, slower) and a near one; returns crest row per column
  function crest(x, t, base, k, speed, amp) {
    const px = x * cellW;
    const dx = px - mx, dy = base * CELL_H - my;
    const d = Math.sqrt(dx * dx + dy * dy);
    const ripple = Math.exp(-d * d / 40000) * Math.sin(d * .05 - t * 6) * 2.2;
    return base
      + amp * Math.sin(x * k + t * speed)
      + amp * .5 * Math.sin(x * k * 2.3 - t * speed * 1.4)
      + ripple;
  }

  function cell(x, y, t, top, seed) {
    const depth = y - top;
    if (depth < -1) return Math.sin(x * 12.9 + y * 78.2 + seed + Math.floor(t * 3)) > .995 ? ['.', 0] : [' ', 0]; // spray
    if (depth < 0) return ['~', 1];                                    // foam on the crest
    if (depth < 1) return ['*', 1];
    const v = (Math.sin(x * .21 + y * .33 - t * 1.8 + seed) + Math.sin(x * .05 - y * .4 + t)) / 4 + .5;
    const deep = Math.min(1, depth / 10);
    return [RAMP[Math.min(RAMP.length - 1, Math.floor((v * .6 + deep * .4) * RAMP.length))], 0];
  }

  function draw(t) {
    ctx.clearRect(0, 0, innerWidth, innerHeight);
    const far = [], near = [];
    for (let x = 0; x < cols; x++) {
      far.push(crest(x, t * .7, rows * .5, .045, .9, 2.4));
      near.push(crest(x, t, rows * .7, .07, 1.3, 2.8));
    }
    for (let y = 0; y < rows; y++) {
      // one string per colour per row keeps this to ~2 fillText calls per line
      let ink = '', sig = '';
      for (let x = 0; x < cols; x++) {
        const [ch, hot] = y >= near[x] - 1 ? cell(x, y, t, near[x], 0) : cell(x, y, t * .8, far[x], 3);
        if (hot) { sig += ch; ink += ' ' } else { ink += ch; sig += ' ' }
      }
      ctx.fillStyle = inkFill; ctx.fillText(ink, 0, y * CELL_H);
      ctx.fillStyle = sigFill; ctx.fillText(sig, 0, y * CELL_H);
    }
  }

  function loop(now) {
    if (!document.hidden && now - last > FRAME_MS) { last = now; draw(now / 1000) }
    requestAnimationFrame(loop);
  }

  addEventListener('resize', resize);
  addEventListener('pointermove', e => { mx = e.clientX; my = e.clientY }, { passive: true });
  document.fonts.ready.then(resize);
  resize();
  if (!still) requestAnimationFrame(loop);
})();
