// recipes.jsx — Film stock / recipe definitions + grain texture generator.
// Each recipe is a base CSS `filter` plus a stack of blend-mode tint overlays,
// a grain weight and a vignette weight. The same data drives the live viewfinder
// (CSS) and the baked capture (canvas compositing).
// Exports to window: FILM_RECIPES, FILM_GRAIN_URL, buildFilter, BLEND_TO_COMPOSITE

// ── Grain texture: monochrome noise tile, generated once ───────────────
function makeGrain(size = 160) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const ctx = c.getContext('2d');
  const img = ctx.createImageData(size, size);
  for (let i = 0; i < img.data.length; i += 4) {
    const v = 110 + Math.random() * 90; // mid-grey scatter -> reads on overlay blend
    img.data[i] = img.data[i + 1] = img.data[i + 2] = v;
    img.data[i + 3] = 255;
  }
  ctx.putImageData(img, 0, 0);
  return c.toDataURL('image/png');
}

const FILM_GRAIN_URL = makeGrain();

// CSS blend-mode name -> canvas globalCompositeOperation (for baked capture)
const BLEND_TO_COMPOSITE = {
  'soft-light': 'soft-light',
  'overlay': 'overlay',
  'multiply': 'multiply',
  'screen': 'screen',
  'lighten': 'lighten',
  'color': 'color',
  'hue': 'hue',
  'normal': 'source-over',
};

// ── The film library ───────────────────────────────────────────────────
// overlays: [{ bg, blend, opacity }]  — painted bottom→top over the source
const FILM_RECIPES = [
  {
    id: 'standard', name: 'Standard', brand: 'Digital', iso: 'AUTO', color: '#8E8E93',
    bw: false, filter: 'contrast(1) saturate(1.02) brightness(1)',
    grain: 0.05, vignette: 0.04, overlays: [],
  },
  {
    id: 'portra400', name: 'Portra 400', brand: 'Kodak', iso: '400', color: '#E0A24A',
    bw: false, filter: 'contrast(0.96) saturate(1.06) brightness(1.05) sepia(0.10)',
    grain: 0.30, vignette: 0.14,
    overlays: [
      { bg: '#ffd9a8', blend: 'soft-light', opacity: 0.22 },
      { bg: '#2a2620', blend: 'lighten', opacity: 0.10 }, // lifted, creamy blacks
    ],
  },
  {
    id: 'gold200', name: 'Gold 200', brand: 'Kodak', iso: '200', color: '#F4A823',
    bw: false, filter: 'contrast(1.06) saturate(1.22) brightness(1.03) sepia(0.20) hue-rotate(-8deg)',
    grain: 0.28, vignette: 0.18,
    overlays: [
      { bg: '#ffbf5e', blend: 'soft-light', opacity: 0.30 },
      { bg: '#3a1f00', blend: 'multiply', opacity: 0.08 },
    ],
  },
  {
    id: 'ektar100', name: 'Ektar 100', brand: 'Kodak', iso: '100', color: '#D8352A',
    bw: false, filter: 'contrast(1.16) saturate(1.34) brightness(1.02)',
    grain: 0.10, vignette: 0.16,
    overlays: [
      { bg: '#ff5a3c', blend: 'soft-light', opacity: 0.12 },
      { bg: '#0a2a5e', blend: 'soft-light', opacity: 0.10 },
    ],
  },
  {
    id: 'classicchrome', name: 'Classic Chrome', brand: 'Fujifilm', iso: '—', color: '#3F8B8B',
    bw: false, filter: 'contrast(1.10) saturate(0.70) brightness(0.98) sepia(0.06)',
    grain: 0.18, vignette: 0.22,
    overlays: [
      { bg: '#16324a', blend: 'soft-light', opacity: 0.20 },
      { bg: '#d9c9a8', blend: 'soft-light', opacity: 0.10 },
    ],
  },
  {
    id: 'velvia50', name: 'Velvia 50', brand: 'Fujifilm', iso: '50', color: '#E2231A',
    bw: false, filter: 'contrast(1.20) saturate(1.55) brightness(1.0)',
    grain: 0.10, vignette: 0.24,
    overlays: [
      { bg: '#0b3d2e', blend: 'soft-light', opacity: 0.14 }, // deepen greens
      { bg: '#3a0010', blend: 'soft-light', opacity: 0.12 },
    ],
  },
  {
    id: 'superia400', name: 'Superia 400', brand: 'Fujifilm', iso: '400', color: '#4FAF2C',
    bw: false, filter: 'contrast(1.06) saturate(1.16) brightness(1.01) hue-rotate(-6deg)',
    grain: 0.30, vignette: 0.18,
    overlays: [
      { bg: '#1f6b3a', blend: 'soft-light', opacity: 0.16 },
      { bg: '#2a2620', blend: 'lighten', opacity: 0.07 },
    ],
  },
  {
    id: 'cinestill800t', name: 'CineStill 800T', brand: 'CineStill', iso: '800', color: '#2B6CB0',
    bw: false, filter: 'contrast(1.06) saturate(1.10) brightness(1.0) hue-rotate(8deg)',
    grain: 0.34, vignette: 0.20, halation: '#ff2d2d',
    overlays: [
      { bg: '#0b2a55', blend: 'soft-light', opacity: 0.26 }, // tungsten/blue shadows
      { bg: '#2a2620', blend: 'lighten', opacity: 0.08 },
    ],
  },
  {
    id: 'cinestill50d', name: 'CineStill 50D', brand: 'CineStill', iso: '50', color: '#1F9E8E',
    bw: false, filter: 'contrast(1.08) saturate(1.06) brightness(1.02)',
    grain: 0.12, vignette: 0.16, halation: '#ff5a3c',
    overlays: [
      { bg: '#123a3a', blend: 'soft-light', opacity: 0.14 },
      { bg: '#ffcaa0', blend: 'soft-light', opacity: 0.10 },
    ],
  },
  {
    id: 'hp5', name: 'HP5 Plus', brand: 'Ilford', iso: '400', color: '#9AA0A6',
    bw: true, filter: 'grayscale(1) contrast(1.18) brightness(1.03)',
    grain: 0.45, vignette: 0.22,
    overlays: [
      { bg: '#1c1c1c', blend: 'lighten', opacity: 0.10 },
    ],
  },
  {
    id: 'trix400', name: 'Tri-X 400', brand: 'Kodak', iso: '400', color: '#C9A227',
    bw: true, filter: 'grayscale(1) contrast(1.34) brightness(0.97)',
    grain: 0.52, vignette: 0.26,
    overlays: [
      { bg: '#000000', blend: 'multiply', opacity: 0.06 },
    ],
  },
  {
    id: 'polaroid600', name: 'Polaroid 600', brand: 'Instant', iso: '640', color: '#2BB3C0',
    bw: false, filter: 'contrast(0.84) saturate(0.92) brightness(1.12) sepia(0.14)',
    grain: 0.22, vignette: 0.10,
    overlays: [
      { bg: '#9fe3d6', blend: 'soft-light', opacity: 0.22 }, // cyan wash
      { bg: '#34323a', blend: 'lighten', opacity: 0.20 },    // heavily lifted blacks
      { bg: '#ffe7c2', blend: 'soft-light', opacity: 0.14 },
    ],
  },
  {
    id: 'lomochrome', name: 'LomoChrome', brand: 'Lomography', iso: '400', color: '#6FBF73',
    bw: false, filter: 'contrast(1.30) saturate(1.42) brightness(1.0) hue-rotate(-16deg)',
    grain: 0.34, vignette: 0.40,
    overlays: [
      { bg: '#1f5e3a', blend: 'soft-light', opacity: 0.26 }, // cross-process green
      { bg: '#3a0030', blend: 'soft-light', opacity: 0.16 },
    ],
  },
];

// Compose the live CSS filter, folding in exposure (EV-ish brightness nudge).
function buildFilter(recipe, exposure = 0) {
  // exposure: -1..+1  ->  brightness multiplier ~0.7..1.3
  const expMul = 1 + exposure * 0.3;
  return `${recipe.filter} brightness(${expMul.toFixed(3)})`;
}

Object.assign(window, { FILM_RECIPES, FILM_GRAIN_URL, buildFilter, BLEND_TO_COMPOSITE });
