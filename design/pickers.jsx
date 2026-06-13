// pickers.jsx — three film-selector directions: FilmDial (carousel), FilmWheel
// (curved rotary), FilmSheet (slide-up grid browser). Plus shared FilmBox + FilmThumb.
// Exports to window: FilmBox, FilmDial, FilmWheel, FilmSheet, FilmThumb

const { useRef, useEffect, useState, useCallback } = React;

// ── A little 35mm film box ─────────────────────────────────────────────
function FilmBox({ recipe, active, size = 1 }) {
  const w = 46 * size, h = 62 * size;
  return (
    <div style={{
      width: w, height: h, borderRadius: 8 * size, position: 'relative',
      background: 'linear-gradient(160deg,#26262b,#141417)',
      boxShadow: active
        ? `0 0 0 2px ${recipe.color}, 0 8px 20px rgba(0,0,0,0.5)`
        : '0 2px 6px rgba(0,0,0,0.4)',
      overflow: 'hidden', flexShrink: 0,
      transition: 'box-shadow 0.25s ease',
    }}>
      <div style={{ height: h * 0.30, background: recipe.color, opacity: active ? 1 : 0.82 }} />
      <div style={{
        position: 'absolute', top: h * 0.30, left: 0, right: 0,
        height: 3 * size, background: 'rgba(0,0,0,0.35)',
      }} />
      <div style={{
        position: 'absolute', top: h * 0.30 + 6 * size, left: 0, right: 0, bottom: 0,
        display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
        gap: 1,
      }}>
        <div style={{
          fontSize: 8 * size, fontWeight: 700, letterSpacing: 0.3,
          color: 'rgba(255,255,255,0.55)', textTransform: 'uppercase',
        }}>{recipe.brand === 'Digital' ? 'AUTO' : recipe.brand.slice(0, 7)}</div>
        <div style={{
          fontSize: 15 * size, fontWeight: 800, color: '#fff', lineHeight: 1,
          fontFamily: 'ui-monospace, "SF Mono", monospace',
        }}>{recipe.iso}</div>
      </div>
      {/* sprocket flecks */}
      <div style={{
        position: 'absolute', left: 3 * size, top: 3 * size, width: 4 * size, height: 4 * size,
        borderRadius: 1, background: 'rgba(255,255,255,0.15)',
      }} />
    </div>
  );
}

// ── Shared horizontal scroller (flat = dial, curved = wheel) ────────────
function Scroller({ recipes, index, onSelect, curved }) {
  const ref = useRef(null);
  const itemRefs = useRef([]);
  const lockUntil = useRef(0);
  const ITEM = 78; // px footprint per item incl. gap

  const applyCurve = useCallback(() => {
    if (!curved || !ref.current) return;
    const box = ref.current.getBoundingClientRect();
    const mid = box.left + box.width / 2;
    itemRefs.current.forEach((el) => {
      if (!el) return;
      const r = el.getBoundingClientRect();
      const c = r.left + r.width / 2;
      const ratio = Math.max(-1.4, Math.min(1.4, (c - mid) / (box.width / 2)));
      const rotY = ratio * -48;
      const tz = -Math.abs(ratio) * 60;
      const op = Math.max(0.25, 1 - Math.abs(ratio) * 0.55);
      el.style.transform = `perspective(520px) rotateY(${rotY}deg) translateZ(${tz}px)`;
      el.style.opacity = op;
    });
  }, [curved]);

  // centre the active item
  const centerTo = useCallback((i, smooth = true) => {
    const el = itemRefs.current[i];
    const sc = ref.current;
    if (!el || !sc) return;
    const target = el.offsetLeft - sc.clientWidth / 2 + el.offsetWidth / 2;
    sc.scrollTo({ left: target, behavior: smooth ? 'smooth' : 'auto' });
  }, []);

  useEffect(() => {
    let r1 = requestAnimationFrame(() => {
      centerTo(index, false);
      let r2 = requestAnimationFrame(applyCurve);
    });
    const t = setTimeout(() => { centerTo(index, false); applyCurve(); }, 120);
    return () => { cancelAnimationFrame(r1); clearTimeout(t); };
  }, []); // eslint-disable-line
  useEffect(() => {
    lockUntil.current = Date.now() + 350;
    centerTo(index);
    requestAnimationFrame(applyCurve);
  }, [index]); // eslint-disable-line

  const onScroll = useCallback(() => {
    applyCurve();
    if (Date.now() < lockUntil.current) return;
    const sc = ref.current;
    const mid = sc.scrollLeft + sc.clientWidth / 2;
    let best = 0, bestD = Infinity;
    itemRefs.current.forEach((el, i) => {
      if (!el) return;
      const c = el.offsetLeft + el.offsetWidth / 2;
      const d = Math.abs(c - mid);
      if (d < bestD) { bestD = d; best = i; }
    });
    if (best !== index) onSelect(best);
  }, [applyCurve, index, onSelect]);

  return (
    <div ref={ref} onScroll={onScroll} style={{
      display: 'flex', gap: 32, overflowX: 'auto', overflowY: 'hidden',
      position: 'relative',
      scrollSnapType: 'x mandatory', padding: '6px 50%',
      WebkitOverflowScrolling: 'touch', scrollbarWidth: 'none',
      maskImage: 'linear-gradient(90deg,transparent,#000 14%,#000 86%,transparent)',
      WebkitMaskImage: 'linear-gradient(90deg,transparent,#000 14%,#000 86%,transparent)',
    }}>
      <style>{`div::-webkit-scrollbar{display:none}`}</style>
      {recipes.map((r, i) => (
        <button key={r.id} ref={(e) => (itemRefs.current[i] = e)}
          onClick={() => onSelect(i)}
          style={{
            scrollSnapAlign: 'center', flexShrink: 0, background: 'none', border: 'none',
            cursor: 'pointer', padding: 0, transformStyle: 'preserve-3d',
            transition: 'opacity 0.15s linear',
          }}>
          <div style={{ transform: i === index ? 'scale(1.14)' : 'scale(0.92)', transition: 'transform 0.25s ease' }}>
            <FilmBox recipe={r} active={i === index} />
          </div>
        </button>
      ))}
    </div>
  );
}

function FilmDial(props) { return <Scroller {...props} curved={false} />; }
function FilmWheel(props) { return <Scroller {...props} curved={true} />; }

// ── Static film thumbnail (image + same look stack) ────────────────────
function FilmThumb({ recipe, snapshot, grainScale = 0.6 }) {
  return (
    <div style={{ position: 'absolute', inset: 0, overflow: 'hidden', background: '#111' }}>
      <div style={{
        position: 'absolute', inset: 0, backgroundImage: `url(${snapshot})`,
        backgroundSize: 'cover', backgroundPosition: 'center',
        filter: window.buildFilter(recipe, 0),
      }} />
      {recipe.overlays.map((o, i) => (
        <div key={i} style={{ position: 'absolute', inset: 0, background: o.bg, mixBlendMode: o.blend, opacity: o.opacity }} />
      ))}
      <div style={{
        position: 'absolute', inset: 0, mixBlendMode: 'overlay',
        opacity: recipe.grain * grainScale,
        backgroundImage: `url(${window.FILM_GRAIN_URL})`, backgroundSize: '120px 120px',
      }} />
      <div style={{
        position: 'absolute', inset: 0,
        background: `radial-gradient(130% 100% at 50% 50%, transparent 50%, rgba(0,0,0,${recipe.vignette}) 100%)`,
      }} />
    </div>
  );
}

// ── Slide-up grid browser ──────────────────────────────────────────────
function FilmSheet({ open, recipes, index, onSelect, onClose, snapshot }) {
  return (
    <div style={{
      position: 'absolute', inset: 0, zIndex: 80, pointerEvents: open ? 'auto' : 'none',
    }}>
      {/* scrim */}
      <div onClick={onClose} style={{
        position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.5)',
        opacity: open ? 1 : 0, transition: 'opacity 0.3s ease',
        backdropFilter: open ? 'blur(2px)' : 'none',
      }} />
      {/* sheet */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0, maxHeight: '74%',
        background: 'rgba(28,28,30,0.86)', backdropFilter: 'blur(28px) saturate(160%)',
        WebkitBackdropFilter: 'blur(28px) saturate(160%)',
        borderTopLeftRadius: 28, borderTopRightRadius: 28,
        transform: open ? 'translateY(0)' : 'translateY(102%)',
        transition: 'transform 0.4s cubic-bezier(0.32,0.72,0,1)',
        display: 'flex', flexDirection: 'column', paddingBottom: 28,
        boxShadow: '0 -12px 40px rgba(0,0,0,0.5)',
      }}>
        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 10 }}>
          <div style={{ width: 38, height: 5, borderRadius: 3, background: 'rgba(255,255,255,0.3)' }} />
        </div>
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '8px 20px 12px',
        }}>
          <span style={{ color: '#fff', fontSize: 20, fontWeight: 700 }}>Film Library</span>
          <button onClick={onClose} style={{
            border: 'none', background: 'rgba(255,255,255,0.14)', color: '#fff',
            width: 30, height: 30, borderRadius: 15, fontSize: 15, cursor: 'pointer',
          }}>✕</button>
        </div>
        <div style={{
          overflowY: 'auto', padding: '4px 16px 8px',
          display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: 12,
        }}>
          {recipes.map((r, i) => (
            <button key={r.id} onClick={() => { onSelect(i); onClose(); }} style={{
              background: 'none', border: 'none', padding: 0, cursor: 'pointer', textAlign: 'left',
            }}>
              <div style={{
                position: 'relative', width: '100%', aspectRatio: '3/4', borderRadius: 12,
                overflow: 'hidden',
                boxShadow: i === index ? `0 0 0 2.5px ${r.color}` : '0 0 0 1px rgba(255,255,255,0.08)',
              }}>
                <FilmThumb recipe={r} snapshot={snapshot} />
                {i === index && (
                  <div style={{
                    position: 'absolute', top: 6, right: 6, width: 18, height: 18, borderRadius: 9,
                    background: r.color, display: 'flex', alignItems: 'center', justifyContent: 'center',
                    fontSize: 11, color: '#fff', fontWeight: 800,
                  }}>✓</div>
                )}
              </div>
              <div style={{ color: '#fff', fontSize: 12, fontWeight: 600, marginTop: 5 }}>{r.name}</div>
              <div style={{ color: 'rgba(255,255,255,0.5)', fontSize: 10.5, fontWeight: 500 }}>
                {r.brand} · ISO {r.iso}
              </div>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { FilmBox, FilmDial, FilmWheel, FilmSheet, FilmThumb });
