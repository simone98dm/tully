// The Dial: a 3D knob that turns with scroll, clicks into a detent per feature and lights the active segment.
window.initDial = function initDial(getLang) {
  const canvas = document.getElementById('dial');
  const panel = document.getElementById('dialPanel');
  const count = document.getElementById('dialCount');
  const track = document.querySelector('.dial-track');
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const N = window.I18N.dial.en.length;
  const STEP = Math.PI * 2 / N;
  const R_OUT = 3, R_IN = 1.25, DEPTH = .55, GAP = .025;
  const C = { paper: 0xf7f5ef, ink: 0x16151a, sig: 0x3385ff, edge: 0xc9c4b5 };

  // ---------- panel (DOM) ----------
  let current = -1;
  const dots = document.createElement('div');
  dots.className = 'dial-dots';

  function renderPanel(i) {
    const f = window.I18N.dial[getLang()][i];
    panel.innerHTML = ''; // static, first-party content only
    const box = document.createElement('div');
    box.className = 'swap';
    box.innerHTML = `<span class="k"><kbd></kbd><span></span></span><h2></h2><p></p><ul></ul><img alt="" loading="lazy">`;
    box.querySelector('kbd').textContent = f.key;
    box.querySelector('.k span').textContent = `§ 02.${i + 1}`;
    box.querySelector('h2').textContent = f.name;
    box.querySelector('p').textContent = f.body;
    f.list.forEach(t => { const li = document.createElement('li'); li.textContent = t; box.querySelector('ul').append(li) });
    const img = box.querySelector('img');
    img.src = `assets/${f.shot}`; img.alt = f.name;
    box.append(dots);
    panel.append(box);
    [...dots.children].forEach((d, j) => { d.classList.toggle('on', j === i); d.setAttribute('aria-current', j === i) });
    count.textContent = `${String(i + 1).padStart(2, '0')} / ${String(N).padStart(2, '0')}`;
  }
  function show(i, force) {
    if (i === current && !force) return;
    current = i;
    renderPanel(i);
    segs.forEach((s, j) => {
      const map = j === i ? s.label.userData.white : s.label.userData.ink;
      if (map && s.label.material.map !== map) { s.label.material.map = map; s.label.material.needsUpdate = true }
    });
  }

  function scrollToIndex(i) {
    const span = track.offsetHeight - innerHeight;
    scrollTo({ top: track.offsetTop + (i + .5) / N * span, behavior: still ? 'auto' : 'smooth' });
  }
  for (let i = 0; i < N; i++) {
    const b = document.createElement('button');
    b.type = 'button';
    b.setAttribute('aria-label', window.I18N.dial.en[i].name);
    b.addEventListener('click', () => scrollToIndex(i));
    dots.append(b);
  }

  // ---------- scene ----------
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(32, 1, .1, 100);
  camera.position.set(0, -7, 12);
  camera.lookAt(0, -1.3, 0);

  scene.add(new THREE.HemisphereLight(0xffffff, 0xd8d2c4, .55));
  const sun = new THREE.DirectionalLight(0xffffff, .7);
  sun.position.set(-4, -3, 10);
  sun.castShadow = true;
  sun.shadow.mapSize.set(1024, 1024);
  sun.shadow.radius = 6;
  Object.assign(sun.shadow.camera, { left: -5, right: 5, top: 5, bottom: -5 });
  scene.add(sun);

  const floor = new THREE.Mesh(new THREE.PlaneGeometry(30, 30), new THREE.ShadowMaterial({ opacity: .16 }));
  floor.position.z = -.02;
  floor.receiveShadow = true;
  scene.add(floor);

  const rig = new THREE.Group();     // tilts with the pointer
  const dial = new THREE.Group();    // turns with scroll
  rig.add(dial);
  scene.add(rig);

  function labelTexture(i, color) {
    const f = window.I18N.dial[getLang()][i];
    const c = document.createElement('canvas');
    c.width = 512; c.height = 256;
    const g = c.getContext('2d');
    g.fillStyle = color;
    g.textAlign = 'center';
    g.font = '400 108px "Instrument Serif", Georgia, serif';
    g.fillText(f.name, 256, 140);
    g.font = '700 40px "JetBrains Mono", monospace';
    g.globalAlpha = .7;
    g.fillText(f.key, 256, 212);
    const t = new THREE.CanvasTexture(c);
    t.anisotropy = 4;
    return t;
  }

  const segs = [];
  for (let i = 0; i < N; i++) {
    const a0 = i * STEP + GAP, a1 = (i + 1) * STEP - GAP;
    const shape = new THREE.Shape();
    shape.absarc(0, 0, R_OUT, a0, a1, false);
    shape.absarc(0, 0, R_IN, a1, a0, true);
    const geo = new THREE.ExtrudeGeometry(shape, { depth: DEPTH, bevelEnabled: true, bevelSize: .06, bevelThickness: .06, bevelSegments: 4, curveSegments: 48 });
    const mat = new THREE.MeshStandardMaterial({ color: C.paper, roughness: .55, metalness: .05 });
    const mesh = new THREE.Mesh(geo, mat);
    mesh.castShadow = true;
    mesh.userData.index = i;
    // ink outline, like a drawing in a field manual
    mesh.add(new THREE.LineSegments(new THREE.EdgesGeometry(geo, 30), new THREE.LineBasicMaterial({ color: C.ink, transparent: true, opacity: .55 })));

    // label sits on the top face, reading along the arc's middle
    const mid = (i + .5) * STEP;
    const label = new THREE.Mesh(new THREE.PlaneGeometry(1.7, .85), new THREE.MeshBasicMaterial({ transparent: true, depthWrite: false }));
    label.position.set(Math.cos(mid) * 2.12, Math.sin(mid) * 2.12, DEPTH + .07);
    label.rotation.z = mid - Math.PI / 2;
    label.userData = { ink: null, white: null };
    mesh.add(label);

    dial.add(mesh);
    segs.push({ mesh, mat, label, lift: 0 });
  }

  function paintLabels() {
    segs.forEach((s, i) => {
      s.label.userData.ink?.dispose(); s.label.userData.white?.dispose();
      s.label.userData.ink = labelTexture(i, '#16151a');
      s.label.userData.white = labelTexture(i, '#ffffff');
      s.label.material.map = i === current ? s.label.userData.white : s.label.userData.ink;
      s.label.material.needsUpdate = true;
    });
  }

  // bezel with 60 ticks, turning with the dial
  const ticks = new THREE.Group();
  for (let i = 0; i < 60; i++) {
    const major = i % 10 === 0;
    const t = new THREE.Mesh(new THREE.BoxGeometry(major ? .05 : .025, major ? .28 : .14, .03), new THREE.MeshBasicMaterial({ color: C.ink }));
    const a = i / 60 * Math.PI * 2;
    const r = R_OUT + .32;
    t.position.set(Math.cos(a) * r, Math.sin(a) * r, .02);
    t.rotation.z = a + Math.PI / 2;
    ticks.add(t);
  }
  dial.add(ticks);

  // fixed hub with the tully glyph (3/4 ring around a window)
  const hub = new THREE.Group();
  const hubBody = new THREE.Mesh(new THREE.CylinderGeometry(1.08, 1.12, DEPTH + .35, 64), new THREE.MeshStandardMaterial({ color: C.ink, roughness: .35, metalness: .5 }));
  hubBody.rotation.x = Math.PI / 2;
  hubBody.position.z = (DEPTH + .35) / 2;
  hubBody.castShadow = true;
  hub.add(hubBody);
  const white = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: .3, emissive: 0x223355, emissiveIntensity: .2 });
  const arc = new THREE.Mesh(new THREE.TorusGeometry(.6, .09, 16, 64, Math.PI * 1.5), white);
  arc.rotation.z = -Math.PI * .25;
  arc.position.z = DEPTH + .4;
  hub.add(arc);
  const win = new THREE.Mesh(new THREE.BoxGeometry(.5, .44, .1), white);
  win.position.z = DEPTH + .4;
  hub.add(win);
  rig.add(hub);

  // fixed pointer at 12 o'clock
  const pointer = new THREE.Mesh(new THREE.ConeGeometry(.2, .42, 3), new THREE.MeshStandardMaterial({ color: C.sig, emissive: C.sig, emissiveIntensity: .35 }));
  pointer.position.set(0, R_OUT + .78, .3);
  pointer.rotation.z = Math.PI;
  pointer.castShadow = true;
  rig.add(pointer);

  // ---------- motion ----------
  const TOP = Math.PI / 2;
  let angle = 0, vel = 0, tiltX = 0, tiltY = 0, px = 0, py = 0, visible = true;
  const sigColor = new THREE.Color(C.sig), paperColor = new THREE.Color(C.paper);

  function progress() {
    const span = track.offsetHeight - innerHeight;
    return Math.min(Math.max(-track.getBoundingClientRect().top / span, 0), .9999);
  }
  // detent: slow near each feature, quick between them, like a knob that clicks
  function detent(x) {
    const k = Math.floor(x), f = x - k;
    const s = f * f * f * (f * (f * 6 - 15) + 10);
    return k + s;
  }

  function resize() {
    const w = canvas.clientWidth, h = canvas.clientHeight;
    if (!w || !h) return;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    const portrait = w / h < 1.4; // phone layout: canvas is a short, wide band
    camera.position.z = portrait ? 15 : 12;
    camera.lookAt(0, portrait ? -.4 : -1.3, 0);
    camera.updateProjectionMatrix();
  }

  function frame() {
    const p = progress();
    const pos = p * N - .5;
    const idx = Math.min(N - 1, Math.max(0, Math.round(pos)));
    show(idx);

    // segment i's centre is at (i + .5) * STEP; rotate it to the pointer
    const target = TOP - (detent(Math.max(pos, 0)) + .5) * STEP;
    if (still) { angle = target } else {
      vel += (target - angle) * .09;  // spring
      vel *= .72;                     // damping, just under critical for a tiny settle
      angle += vel;
    }
    dial.rotation.z = angle;

    tiltX += (py * .18 - tiltX) * .06;
    tiltY += (px * .22 - tiltY) * .06;
    rig.rotation.x = tiltX;
    rig.rotation.y = tiltY;

    const t = performance.now() / 1000;
    segs.forEach((s, i) => {
      const on = i === idx;
      s.lift += ((on ? .42 : 0) - s.lift) * .12;
      s.mesh.position.z = s.lift + (still ? 0 : Math.sin(t * 1.6 + i) * .015);
      s.mat.color.lerp(on ? sigColor : paperColor, .12);
      s.label.rotation.z = -angle; // keep every label upright while the dial turns
      s.mat.emissive.copy(s.mat.color).multiplyScalar(on ? .06 : 0);
    });
    pointer.position.z = .3 + (still ? 0 : Math.abs(Math.sin(t * 2.4)) * .08);

    renderer.render(scene, camera);
  }

  function loop() { if (visible) frame(); requestAnimationFrame(loop) }

  // click a segment to jump to it
  const ray = new THREE.Raycaster(), ndc = new THREE.Vector2();
  canvas.addEventListener('click', e => {
    const r = canvas.getBoundingClientRect();
    ndc.set((e.clientX - r.left) / r.width * 2 - 1, -(e.clientY - r.top) / r.height * 2 + 1);
    ray.setFromCamera(ndc, camera);
    const hit = ray.intersectObjects(segs.map(s => s.mesh))[0];
    if (hit) scrollToIndex(hit.object.userData.index);
  });
  canvas.addEventListener('pointermove', e => {
    const r = canvas.getBoundingClientRect();
    px = (e.clientX - r.left) / r.width - .5;
    py = (e.clientY - r.top) / r.height - .5;
  });
  canvas.addEventListener('pointerleave', () => { px = 0; py = 0 });

  new IntersectionObserver(([e]) => { visible = e.isIntersecting }).observe(track);
  addEventListener('resize', resize);
  document.fonts.ready.then(paintLabels);
  resize();
  paintLabels();
  show(0, true);
  loop();

  return { relabel() { paintLabels(); show(current, true) } };
};
