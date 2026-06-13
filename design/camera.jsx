// camera.jsx — the camera screen: source management, top controls, viewfinder,
// switchable picker, shutter row, fine-adjust sliders, capture + gallery.
// Exports to window: CameraApp

const { useRef: useRefC, useEffect: useEffectC, useState: useStateC, useCallback: useCbC } = React;

// ── tiny inline icons ──────────────────────────────────────────────────
const Ico = {
  bolt: (c) => <svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M13 2L4 14h6l-1 8 9-12h-6l1-8z" fill={c} stroke={c} strokeWidth="1.4" strokeLinejoin="round"/></svg>,
  boltOff: (c) => <svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M13 2L4 14h6l-1 8 9-12h-6l1-8z" stroke={c} strokeWidth="1.5" strokeLinejoin="round"/><path d="M3 3l18 18" stroke={c} strokeWidth="1.6" strokeLinecap="round"/></svg>,
  grid: (c) => <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.4"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M9 3v18M15 3v18M3 9h18M3 15h18"/></svg>,
  sliders: (c) => <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.7" strokeLinecap="round"><path d="M4 8h10M18 8h2M4 16h2M10 16h10"/><circle cx="16" cy="8" r="2.2" fill={c} stroke="none"/><circle cx="8" cy="16" r="2.2" fill={c} stroke="none"/></svg>,
  flip: (c) => <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M3 7h13l-2.5-2.5M21 17H8l2.5 2.5"/><circle cx="12" cy="12" r="3.2"/></svg>,
  stack: (c) => <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.6"><rect x="4" y="7" width="16" height="13" rx="2"/><path d="M7 7V5a2 2 0 012-2h6a2 2 0 012 2v2"/></svg>,
};

function GlassBtn({ children, onClick, active, size = 40 }) {
  return (
    <button onClick={onClick} style={{
      width: size, height: size, borderRadius: size / 2, border: 'none', cursor: 'pointer',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      background: active ? 'rgba(255,214,10,0.92)' : 'rgba(40,40,44,0.55)',
      backdropFilter: 'blur(14px) saturate(160%)', WebkitBackdropFilter: 'blur(14px) saturate(160%)',
      boxShadow: 'inset 0 0 0 0.5px rgba(255,255,255,0.14)',
      transition: 'background 0.2s ease',
    }}>{children}</button>
  );
}

function Slider({ label, value, min, max, step, onChange, accent, fmt }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
      <span style={{ width: 58, fontSize: 11, fontWeight: 600, color: 'rgba(255,255,255,0.7)', letterSpacing: 0.3 }}>{label}</span>
      <input type="range" min={min} max={max} step={step} value={value}
        onChange={(e) => onChange(parseFloat(e.target.value))}
        style={{ flex: 1, accentColor: accent, height: 4 }} />
      <span style={{ width: 42, textAlign: 'right', fontSize: 11, fontWeight: 700, color: '#fff', fontFamily: 'ui-monospace,monospace' }}>{fmt(value)}</span>
    </div>
  );
}

function ChipRow({ label, value, options, onChange, accent }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
      <span style={{ width: 58, fontSize: 11, fontWeight: 600, color: 'rgba(255,255,255,0.7)', letterSpacing: 0.3 }}>{label}</span>
      <div style={{ flex: 1, display: 'flex', gap: 6 }}>
        {options.map((opt) => {
          const on = opt === value;
          return (
            <button key={opt} onClick={() => onChange(opt)} style={{
              flex: 1, padding: '6px 0', borderRadius: 9, border: 'none', cursor: 'pointer',
              fontSize: 11.5, fontWeight: 700, letterSpacing: 0.2,
              color: on ? '#161618' : 'rgba(255,255,255,0.82)',
              background: on ? accent : 'rgba(255,255,255,0.10)',
              boxShadow: on ? 'none' : 'inset 0 0 0 0.5px rgba(255,255,255,0.12)',
              transition: 'background 0.18s ease, color 0.18s ease',
            }}>{opt}</button>
          );
        })}
      </div>
    </div>
  );
}

function CameraApp({ pickerStyle = 'dial' }) {
  const [index, setIndex] = useStateC(1);
  const [exposure, setExposure] = useStateC(0);
  const [grainStrength, setGrainStrength] = useStateC('High');
  const [grainSize, setGrainSize] = useStateC('Medium');
  const [adjustOpen, setAdjustOpen] = useStateC(false);
  const [shots, setShots] = useStateC([]);
  const [flash, setFlash] = useStateC(false);
  const [pressed, setPressed] = useStateC(false);
  const [usingCamera, setUsingCamera] = useStateC(false);
  const [showGrid, setShowGrid] = useStateC(false);
  const [flashMode, setFlashMode] = useStateC(false);
  const [mirrored, setMirrored] = useStateC(true);
  const [facing, setFacing] = useStateC('user');
  const [sheetOpen, setSheetOpen] = useStateC(false);
  const [snapshot, setSnapshot] = useStateC(null);
  const [gallery, setGallery] = useStateC(null); // index into shots, or null
  const [frames, setFrames] = useStateC(0);

  const videoRef = useRefC(null);
  const sceneRef = useRefC(null);
  const streamRef = useRefC(null);
  const recipes = window.FILM_RECIPES;
  const recipe = recipes[index];
  const GRAIN_STRENGTH = { Low: 0.55, High: 1.3 };
  const GRAIN_SIZE_PX = { Small: 110, Medium: 175, Large: 260 };
  const grainMul = GRAIN_STRENGTH[grainStrength] ?? 1;
  const grainPx = GRAIN_SIZE_PX[grainSize] ?? 175;
  const effGrain = Math.min(0.9, recipe.grain * grainMul);

  // ── camera / scene source ────────────────────────────────────────────
  const startCamera = useCbC(async (face) => {
    try {
      if (streamRef.current) streamRef.current.getTracks().forEach((t) => t.stop());
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: face, width: { ideal: 1280 }, height: { ideal: 1280 } }, audio: false,
      });
      streamRef.current = stream;
      if (videoRef.current) videoRef.current.srcObject = stream;
      setUsingCamera(true);
      setMirrored(face === 'user');
    } catch (e) {
      setUsingCamera(false);
    }
  }, []);

  useEffectC(() => { startCamera('user'); return () => { if (streamRef.current) streamRef.current.getTracks().forEach((t) => t.stop()); }; }, []); // eslint-disable-line

  // scene animation when no camera
  useEffectC(() => {
    if (usingCamera) return;
    const start = performance.now();
    const cv = sceneRef.current;
    if (cv) { cv.width = 1080; cv.height = 1440; }
    const draw = () => {
      const el = sceneRef.current;
      if (el) window.drawScene(el.getContext('2d'), 1080, 1440, performance.now() - start);
    };
    draw(); // immediate first frame (robust to rAF throttling)
    let raf = 0;
    const loop = () => { draw(); raf = requestAnimationFrame(loop); };
    raf = requestAnimationFrame(loop);
    const iv = setInterval(draw, 66); // fallback ticker
    return () => { cancelAnimationFrame(raf); clearInterval(iv); };
  }, [usingCamera]);

  const activeSource = () => (usingCamera ? videoRef.current : sceneRef.current);

  // ── grab a clean snapshot (for sheet thumbnails) ─────────────────────
  const grabSnapshot = useCbC(() => {
    const src = activeSource();
    if (!src) return;
    const c = document.createElement('canvas');
    c.width = 360; c.height = 480;
    const ctx = c.getContext('2d');
    const sw = src.videoWidth || src.width || 1080;
    const sh = src.videoHeight || src.height || 1440;
    const ratio = 3 / 4; let cw = sw, ch = sh;
    if (sw / sh > ratio) cw = sh * ratio; else ch = sw / ratio;
    try {
      if (mirrored && usingCamera) { ctx.translate(360, 0); ctx.scale(-1, 1); }
      ctx.drawImage(src, (sw - cw) / 2, (sh - ch) / 2, cw, ch, 0, 0, 360, 480);
      setSnapshot(c.toDataURL('image/jpeg', 0.8));
    } catch (e) { /* tainted/empty */ }
  }, [mirrored, usingCamera]);

  useEffectC(() => { const t = setTimeout(grabSnapshot, 700); return () => clearTimeout(t); }, [grabSnapshot]);

  const openSheet = () => { grabSnapshot(); setSheetOpen(true); };

  // ── capture ──────────────────────────────────────────────────────────
  const capture = useCbC(() => {
    const src = activeSource();
    if (!src) return;
    setPressed(true); setTimeout(() => setPressed(false), 140);
    setFlash(true); setTimeout(() => setFlash(false), 320);
    try {
      const url = window.bakeCapture(src, recipe, { grain: effGrain, grainSize: grainPx, exposure, mirrored: mirrored && usingCamera });
      setShots((p) => [{ url, name: recipe.name }, ...p].slice(0, 40));
      setFrames((f) => f + 1);
    } catch (e) { /* ignore */ }
  }, [recipe, effGrain, exposure, mirrored, usingCamera, grainPx]);

  const flip = () => {
    const next = facing === 'user' ? 'environment' : 'user';
    setFacing(next);
    if (usingCamera) startCamera(next); else setMirrored((m) => !m);
  };

  // ── render ─────────────────────────────────────────────────────────
  const inlinePicker = pickerStyle !== 'sheet';

  return (
    <div style={{ position: 'absolute', inset: 0, background: '#000', overflow: 'hidden', userSelect: 'none' }}>
      {/* VIEWFINDER fills behind everything */}
      <div style={{ position: 'absolute', top: 96, left: 0, right: 0, bottom: 196, borderRadius: 6, overflow: 'hidden' }}>
        <window.Viewfinder sourceRef={videoRef} sceneRef={sceneRef} recipe={recipe}
          grain={effGrain} grainSize={grainPx} exposure={exposure} usingCamera={usingCamera}
          showGrid={showGrid} mirrored={mirrored && usingCamera} />

        {/* film label badge — top-left of frame */}
        <div style={{
          position: 'absolute', top: 12, left: 12, display: 'flex', alignItems: 'center', gap: 7,
          padding: '6px 11px 6px 8px', borderRadius: 20,
          background: 'rgba(0,0,0,0.32)', backdropFilter: 'blur(8px)', WebkitBackdropFilter: 'blur(8px)',
        }}>
          <span style={{ width: 9, height: 9, borderRadius: 5, background: recipe.color }} />
          <span style={{ color: '#fff', fontSize: 12.5, fontWeight: 700, letterSpacing: 0.2 }}>{recipe.name}</span>
        </div>
        {/* frame counter — top-right of frame */}
        <div style={{
          position: 'absolute', top: 12, right: 12, padding: '5px 10px', borderRadius: 14,
          background: 'rgba(0,0,0,0.32)', backdropFilter: 'blur(8px)', WebkitBackdropFilter: 'blur(8px)',
          color: 'rgba(255,255,255,0.92)', fontSize: 11.5, fontWeight: 700,
          fontFamily: 'ui-monospace,monospace', letterSpacing: 0.5,
        }}>{String(frames).padStart(2, '0')}<span style={{ opacity: 0.5 }}>/36</span></div>

        {/* fine-adjust panel */}
        <div style={{
          position: 'absolute', left: 12, right: 12, bottom: 12,
          padding: '12px 14px', borderRadius: 18,
          background: 'rgba(18,18,20,0.6)', backdropFilter: 'blur(20px) saturate(160%)',
          WebkitBackdropFilter: 'blur(20px) saturate(160%)',
          boxShadow: 'inset 0 0 0 0.5px rgba(255,255,255,0.12)',
          display: 'flex', flexDirection: 'column', gap: 10,
          transform: adjustOpen ? 'translateY(0)' : 'translateY(14px)',
          opacity: adjustOpen ? 1 : 0, pointerEvents: adjustOpen ? 'auto' : 'none',
          transition: 'all 0.28s cubic-bezier(0.32,0.72,0,1)',
        }}>
          <Slider label="EXPOSURE" value={exposure} min={-1} max={1} step={0.05} onChange={setExposure}
            accent={recipe.color} fmt={(v) => `${v > 0 ? '+' : ''}${v.toFixed(1)}`} />
          <ChipRow label="STRENGTH" value={grainStrength} options={['Low', 'High']}
            onChange={setGrainStrength} accent={recipe.color} />
          <ChipRow label="GRAIN" value={grainSize} options={['Small', 'Medium', 'Large']}
            onChange={setGrainSize} accent={recipe.color} />
        </div>

        {/* capture flash */}
        <div style={{
          position: 'absolute', inset: 0, background: '#fff', pointerEvents: 'none',
          opacity: flash ? 0.85 : 0, transition: flash ? 'none' : 'opacity 0.32s ease',
        }} />

        {/* permission hint */}
        {!usingCamera && (
          <div style={{
            position: 'absolute', bottom: adjustOpen ? 86 : 12, left: '50%', transform: 'translateX(-50%)',
            padding: '5px 12px', borderRadius: 20, whiteSpace: 'nowrap',
            background: 'rgba(0,0,0,0.4)', backdropFilter: 'blur(8px)',
            color: 'rgba(255,255,255,0.8)', fontSize: 10.5, fontWeight: 600,
            transition: 'bottom 0.28s ease',
          }}>◦ Demo scene · enable camera for live preview</div>
        )}
      </div>

      {/* TOP control bar */}
      <div style={{
        position: 'absolute', top: 54, left: 0, right: 0, padding: '0 16px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between', zIndex: 30,
      }}>
        <GlassBtn active={flashMode} onClick={() => setFlashMode((v) => !v)}>
          {flashMode ? Ico.bolt('#1c1c1c') : Ico.boltOff('#fff')}
        </GlassBtn>
        <div style={{ display: 'flex', gap: 10 }}>
          <GlassBtn active={showGrid} onClick={() => setShowGrid((v) => !v)}>{Ico.grid(showGrid ? '#1c1c1c' : '#fff')}</GlassBtn>
          <GlassBtn active={adjustOpen} onClick={() => setAdjustOpen((v) => !v)}>{Ico.sliders(adjustOpen ? '#1c1c1c' : '#fff')}</GlassBtn>
        </div>
      </div>

      {/* BOTTOM zone */}
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 196, zIndex: 30,
        display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', paddingBottom: 30 }}>

        {/* picker */}
        {inlinePicker ? (
          <div style={{ marginBottom: 12 }}>
            {pickerStyle === 'wheel'
              ? <window.FilmWheel recipes={recipes} index={index} onSelect={setIndex} />
              : <window.FilmDial recipes={recipes} index={index} onSelect={setIndex} />}
          </div>
        ) : (
          <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 16 }}>
            <button onClick={openSheet} style={{
              display: 'flex', alignItems: 'center', gap: 10, cursor: 'pointer',
              padding: '9px 18px', borderRadius: 22, border: 'none',
              background: 'rgba(40,40,44,0.6)', backdropFilter: 'blur(14px)',
              boxShadow: 'inset 0 0 0 0.5px rgba(255,255,255,0.14)',
            }}>
              <window.FilmBox recipe={recipe} active size={0.5} />
              <span style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-start' }}>
                <span style={{ color: '#fff', fontSize: 14, fontWeight: 700 }}>{recipe.name}</span>
                <span style={{ color: 'rgba(255,255,255,0.55)', fontSize: 11 }}>{recipe.brand} · ISO {recipe.iso} ›</span>
              </span>
            </button>
          </div>
        )}

        {/* shutter row */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 32px' }}>
          {/* recent thumb */}
          <button onClick={() => shots.length && setGallery(0)} style={{
            width: 50, height: 50, borderRadius: 11, border: 'none', cursor: shots.length ? 'pointer' : 'default',
            overflow: 'hidden', background: 'rgba(255,255,255,0.06)',
            boxShadow: 'inset 0 0 0 1px rgba(255,255,255,0.18)', padding: 0,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            {shots.length
              ? <img src={shots[0].url} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
              : Ico.stack('rgba(255,255,255,0.5)')}
          </button>

          {/* shutter */}
          <button onClick={capture} style={{
            width: 74, height: 74, borderRadius: 37, border: 'none', cursor: 'pointer', padding: 0,
            background: 'transparent', position: 'relative',
          }}>
            <div style={{ position: 'absolute', inset: 0, borderRadius: 37, boxShadow: '0 0 0 3px #fff' }} />
            <div style={{
              position: 'absolute', inset: pressed ? 8 : 5, borderRadius: 37,
              background: '#fff', transition: 'inset 0.12s ease',
            }} />
          </button>

          {/* flip */}
          <GlassBtn size={50} onClick={flip}>{Ico.flip('#fff')}</GlassBtn>
        </div>
      </div>

      {/* FILM LIBRARY sheet */}
      <window.FilmSheet open={sheetOpen} recipes={recipes} index={index}
        onSelect={setIndex} onClose={() => setSheetOpen(false)} snapshot={snapshot} />

      {/* GALLERY viewer */}
      {gallery !== null && (
        <GalleryView shots={shots} start={gallery} onClose={() => setGallery(null)} />
      )}
    </div>
  );
}

// ── fullscreen gallery ─────────────────────────────────────────────────
function GalleryView({ shots, start, onClose }) {
  const [i, setI] = useStateC(start);
  const s = shots[i];
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 90, background: '#000', display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '60px 18px 12px' }}>
        <button onClick={onClose} style={{ background: 'none', border: 'none', color: '#fff', fontSize: 16, fontWeight: 600, cursor: 'pointer' }}>‹ Camera</button>
        <span style={{ color: 'rgba(255,255,255,0.6)', fontSize: 13, fontWeight: 600 }}>{s.name}</span>
        <span style={{ color: 'rgba(255,255,255,0.4)', fontSize: 13, width: 60, textAlign: 'right' }}>{i + 1}/{shots.length}</span>
      </div>
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '0 16px' }}>
        <img src={s.url} alt="" style={{ maxWidth: '100%', maxHeight: '100%', borderRadius: 14, boxShadow: '0 20px 60px rgba(0,0,0,0.6)' }} />
      </div>
      <div style={{ display: 'flex', gap: 8, overflowX: 'auto', padding: '14px 16px 40px', scrollbarWidth: 'none' }}>
        {shots.map((sh, k) => (
          <button key={k} onClick={() => setI(k)} style={{
            width: 54, height: 54, borderRadius: 9, flexShrink: 0, overflow: 'hidden', cursor: 'pointer', padding: 0,
            border: 'none', boxShadow: k === i ? '0 0 0 2.5px #fff' : '0 0 0 1px rgba(255,255,255,0.15)',
          }}>
            <img src={sh.url} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
          </button>
        ))}
      </div>
    </div>
  );
}

Object.assign(window, { CameraApp });
