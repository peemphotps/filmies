// viewfinder.jsx — procedural fallback scene + layered film viewfinder + capture bake.
// Exports to window: drawScene, Viewfinder, bakeCapture

// ── Procedural "live" scene (used when no camera permission) ────────────
// A warm dusk landscape — broad tonal + colour range so film looks read clearly.
function drawScene(ctx, w, h, t) {
  const horizon = h * 0.62;

  // Sky gradient
  const sky = ctx.createLinearGradient(0, 0, 0, horizon);
  sky.addColorStop(0, '#243a63');
  sky.addColorStop(0.45, '#5b6f96');
  sky.addColorStop(0.72, '#caa07a');
  sky.addColorStop(1, '#f4c98a');
  ctx.fillStyle = sky;
  ctx.fillRect(0, 0, w, horizon);

  // Sun glow
  const sx = w * 0.5, sy = horizon - 8;
  const glow = ctx.createRadialGradient(sx, sy, 0, sx, sy, h * 0.5);
  glow.addColorStop(0, 'rgba(255,233,180,0.95)');
  glow.addColorStop(0.18, 'rgba(255,205,130,0.6)');
  glow.addColorStop(0.5, 'rgba(255,180,110,0.12)');
  glow.addColorStop(1, 'rgba(255,180,110,0)');
  ctx.fillStyle = glow;
  ctx.fillRect(0, 0, w, horizon);
  // Sun disc
  const pulse = 1 + Math.sin(t / 1800) * 0.02;
  ctx.fillStyle = 'rgba(255,244,214,0.98)';
  ctx.beginPath();
  ctx.arc(sx, sy - h * 0.05, h * 0.05 * pulse, 0, Math.PI * 2);
  ctx.fill();

  // Drifting clouds
  ctx.save();
  for (let i = 0; i < 4; i++) {
    const cy = h * (0.12 + i * 0.1);
    const speed = 12 + i * 6;
    const cx = ((t / 1000 * speed) + i * 260) % (w + 360) - 180;
    const cw = 150 + i * 40, ch = 26 + i * 6;
    const g = ctx.createLinearGradient(0, cy - ch, 0, cy + ch);
    g.addColorStop(0, 'rgba(255,224,196,0.34)');
    g.addColorStop(1, 'rgba(120,110,140,0.16)');
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.ellipse(cx, cy, cw, ch, 0, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();

  // Mountain layers (atmospheric haze)
  const ranges = [
    { y: horizon - 70, amp: 38, col: '#6e6f8e' },
    { y: horizon - 34, amp: 30, col: '#54506f' },
    { y: horizon - 6, amp: 22, col: '#3a3550' },
  ];
  ranges.forEach((r, idx) => {
    ctx.fillStyle = r.col;
    ctx.beginPath();
    ctx.moveTo(0, horizon);
    for (let x = 0; x <= w; x += 12) {
      const y = r.y + Math.sin(x * 0.012 + idx * 2) * r.amp + Math.sin(x * 0.05 + idx) * (r.amp * 0.3);
      ctx.lineTo(x, y);
    }
    ctx.lineTo(w, horizon);
    ctx.closePath();
    ctx.fill();
  });

  // Water
  const water = ctx.createLinearGradient(0, horizon, 0, h);
  water.addColorStop(0, '#c79a6e');
  water.addColorStop(0.4, '#8a6f73');
  water.addColorStop(1, '#3c3550');
  ctx.fillStyle = water;
  ctx.fillRect(0, horizon, w, h - horizon);
  // Sun reflection shimmer
  for (let i = 0; i < 26; i++) {
    const yy = horizon + (i / 26) * (h - horizon);
    const wob = Math.sin(t / 600 + i * 0.7) * (6 + i);
    const ww = (h * 0.05) * (1 + i * 0.14);
    ctx.fillStyle = `rgba(255,228,180,${0.5 * (1 - i / 30)})`;
    ctx.fillRect(sx - ww / 2 + wob, yy, ww, 2.4);
  }

  // Birds
  ctx.strokeStyle = 'rgba(30,26,40,0.5)';
  ctx.lineWidth = 2;
  for (let i = 0; i < 3; i++) {
    const bx = w * 0.2 + ((t / 1000 * 16 + i * 70) % (w * 0.7));
    const by = h * 0.2 + i * 22 + Math.sin(t / 700 + i) * 4;
    ctx.beginPath();
    ctx.moveTo(bx, by);
    ctx.quadraticCurveTo(bx + 7, by - 6, bx + 14, by);
    ctx.quadraticCurveTo(bx + 21, by - 6, bx + 28, by);
    ctx.stroke();
  }
}

// ── Layered viewfinder ─────────────────────────────────────────────────
function Viewfinder({ sourceRef, recipe, grain, grainSize = 170, exposure, usingCamera, sceneRef, showGrid, mirrored }) {
  const filter = window.buildFilter(recipe, exposure);
  const srcStyle = {
    position: 'absolute', inset: 0, width: '100%', height: '100%',
    objectFit: 'cover', filter,
    transform: mirrored ? 'scaleX(-1)' : 'none',
    transition: 'filter 0.45s ease',
  };
  return (
    <div style={{ position: 'absolute', inset: 0, overflow: 'hidden', background: '#000' }}>
      {/* sources */}
      <video ref={sourceRef} autoPlay playsInline muted
        style={{ ...srcStyle, display: usingCamera ? 'block' : 'none' }} />
      <canvas ref={sceneRef}
        style={{ ...srcStyle, display: usingCamera ? 'none' : 'block', transform: 'none' }} />

      {/* tint overlays */}
      {recipe.overlays.map((o, i) => (
        <div key={i} style={{
          position: 'absolute', inset: 0, background: o.bg,
          mixBlendMode: o.blend, opacity: o.opacity, transition: 'opacity 0.45s ease',
        }} />
      ))}

      {/* halation glow */}
      {recipe.halation && (
        <div style={{
          position: 'absolute', inset: 0, mixBlendMode: 'screen', opacity: 0.5,
          background: `radial-gradient(120% 70% at 50% 38%, ${recipe.halation}22 0%, transparent 60%)`,
        }} />
      )}

      {/* grain */}
      <div style={{
        position: 'absolute', inset: '-50%', width: '200%', height: '200%',
        backgroundImage: `url(${window.FILM_GRAIN_URL})`,
        backgroundSize: `${grainSize}px ${grainSize}px`,
        mixBlendMode: 'overlay', opacity: grain,
        animation: 'grainShift 0.6s steps(2) infinite',
        transition: 'opacity 0.3s ease, background-size 0.3s ease',
      }} />

      {/* vignette */}
      <div style={{
        position: 'absolute', inset: 0, pointerEvents: 'none',
        background: `radial-gradient(130% 100% at 50% 50%, transparent 52%, rgba(0,0,0,${recipe.vignette}) 100%)`,
        transition: 'background 0.45s ease',
      }} />

      {/* rule-of-thirds grid */}
      {showGrid && (
        <svg style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', pointerEvents: 'none' }}>
          <line x1="33.3%" y1="0" x2="33.3%" y2="100%" stroke="rgba(255,255,255,0.28)" strokeWidth="0.6" />
          <line x1="66.6%" y1="0" x2="66.6%" y2="100%" stroke="rgba(255,255,255,0.28)" strokeWidth="0.6" />
          <line x1="0" y1="33.3%" x2="100%" y2="33.3%" stroke="rgba(255,255,255,0.28)" strokeWidth="0.6" />
          <line x1="0" y1="66.6%" x2="100%" y2="66.6%" stroke="rgba(255,255,255,0.28)" strokeWidth="0.6" />
        </svg>
      )}
    </div>
  );
}

// ── Bake the current frame to a dataURL with the look applied ───────────
function bakeCapture(source, recipe, { grain, grainSize = 170, exposure, mirrored }) {
  const sw = source.videoWidth || source.width || 1080;
  const sh = source.videoHeight || source.height || 1440;
  // output a 3:4 crop (centre)
  const targetRatio = 3 / 4;
  let cw = sw, ch = sh;
  if (sw / sh > targetRatio) { cw = sh * targetRatio; } else { ch = sw / targetRatio; }
  const sx = (sw - cw) / 2, sy = (sh - ch) / 2;

  const out = document.createElement('canvas');
  out.width = 1080; out.height = 1440;
  const ctx = out.getContext('2d');
  const W = out.width, H = out.height;

  // base frame with primary filter
  ctx.save();
  ctx.filter = window.buildFilter(recipe, exposure);
  if (mirrored) { ctx.translate(W, 0); ctx.scale(-1, 1); }
  ctx.drawImage(source, sx, sy, cw, ch, 0, 0, W, H);
  ctx.restore();

  // tint overlays
  recipe.overlays.forEach((o) => {
    ctx.save();
    ctx.globalCompositeOperation = window.BLEND_TO_COMPOSITE[o.blend] || 'source-over';
    ctx.globalAlpha = o.opacity;
    ctx.fillStyle = o.bg;
    ctx.fillRect(0, 0, W, H);
    ctx.restore();
  });

  // halation
  if (recipe.halation) {
    ctx.save();
    ctx.globalCompositeOperation = 'screen';
    const g = ctx.createRadialGradient(W / 2, H * 0.38, 0, W / 2, H * 0.38, W * 0.8);
    g.addColorStop(0, recipe.halation + '55');
    g.addColorStop(0.6, 'transparent');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);
    ctx.restore();
  }

  // grain (scaled tile so capture matches the chosen on-screen grain size)
  if (grain > 0.01) {
    const gi = window.__grainImg;
    if (gi && gi.complete) {
      // build a tile at grainSize, then upscale relative to the 1080px-wide preview
      const scale = W / 1080; // bake is rendered larger than the live frame
      const tile = document.createElement('canvas');
      tile.width = tile.height = Math.max(8, Math.round(grainSize * scale));
      tile.getContext('2d').drawImage(gi, 0, 0, tile.width, tile.height);
      ctx.save();
      ctx.globalCompositeOperation = 'overlay';
      ctx.globalAlpha = grain;
      ctx.fillStyle = ctx.createPattern(tile, 'repeat');
      ctx.fillRect(0, 0, W, H);
      ctx.restore();
    }
  }

  // vignette
  ctx.save();
  const vg = ctx.createRadialGradient(W / 2, H / 2, H * 0.32, W / 2, H / 2, H * 0.72);
  vg.addColorStop(0, 'transparent');
  vg.addColorStop(1, `rgba(0,0,0,${recipe.vignette})`);
  ctx.fillStyle = vg;
  ctx.fillRect(0, 0, W, H);
  ctx.restore();

  return out.toDataURL('image/jpeg', 0.9);
}

// preload grain as an <img> for canvas pattern use
(function () {
  const im = new Image();
  im.src = window.FILM_GRAIN_URL;
  window.__grainImg = im;
})();

Object.assign(window, { drawScene, Viewfinder, bakeCapture });
