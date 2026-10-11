// Rendu 3D d'une scène exportée par tools/sim (Parts, Terrain, éclairage).
// Objectif : se rapprocher de ce qu'affiche Roblox (Lighting.Technology = Future).
import * as THREE from "three";
import { RoundedBoxGeometry } from "three/addons/geometries/RoundedBoxGeometry.js";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { GTAOPass } from "three/addons/postprocessing/GTAOPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";

const arr = x => Array.isArray(x) ? x : [];
const rgb = c => new THREE.Color(`rgb(${c[0]},${c[1]},${c[2]})`);

// ---------------------------------------------------------------------------
// Textures procédurales (tuilables), à l'échelle du monde comme dans Roblox
// ---------------------------------------------------------------------------
function noiseCanvas(size, draw) {
  const c = document.createElement("canvas"); c.width = c.height = size;
  const g = c.getContext("2d"); g.fillStyle = "#fff"; g.fillRect(0, 0, size, size); draw(g, size); return c;
}
let seed = 1; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
function speckle(g, s, n, a0, a1, r0, r1) {
  for (let i = 0; i < n; i++) {
    const v = rnd() < 0.5 ? 0 : 255; g.fillStyle = `rgba(${v},${v},${v},${a0 + rnd() * (a1 - a0)})`;
    const r = r0 + rnd() * (r1 - r0); const x = rnd() * s, y = rnd() * s;
    for (const dx of [-s, 0, s]) for (const dy of [-s, 0, s]) { g.beginPath(); g.arc(x + dx, y + dy, r, 0, Math.PI * 2); g.fill(); }
  }
}
const TEX = {};
function makeTex(name, studsPerTile, draw) {
  const t = new THREE.CanvasTexture(noiseCanvas(256, draw));
  t.wrapS = t.wrapT = THREE.RepeatWrapping; t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8;
  t.userData.studs = studsPerTile; TEX[name] = t;
}
makeTex("Grass", 8, (g, s) => { speckle(g, s, 900, 0.03, 0.09, 1, 3); });
makeTex("Ground", 8, (g, s) => { speckle(g, s, 500, 0.04, 0.12, 1, 4); });
makeTex("Sand", 6, (g, s) => { speckle(g, s, 1400, 0.02, 0.07, 0.6, 1.4); });
makeTex("Rock", 12, (g, s) => { speckle(g, s, 120, 0.04, 0.12, 6, 18); speckle(g, s, 400, 0.03, 0.08, 1, 3); });
makeTex("WoodPlanks", 4, (g, s) => {
  for (let i = 0; i < 4; i++) { g.fillStyle = `rgba(0,0,0,${0.04 + (i % 2) * 0.04})`; g.fillRect(0, i * s / 4, s, s / 4); g.fillStyle = "rgba(0,0,0,0.22)"; g.fillRect(0, i * s / 4, s, 3); g.fillRect(((i * 97) % s), i * s / 4, 3, s / 4); }
  for (let i = 0; i < 60; i++) { g.fillStyle = "rgba(0,0,0,0.05)"; g.fillRect(0, rnd() * s, s, 1); }
});
makeTex("Wood", 4, (g, s) => { for (let i = 0; i < 40; i++) { g.fillStyle = `rgba(0,0,0,${0.03 + rnd() * 0.05})`; g.fillRect(0, rnd() * s, s, 1 + rnd() * 3); } });
makeTex("Brick", 4, (g, s) => {
  g.fillStyle = "rgba(255,255,255,0.0)"; const rows = 8;
  for (let r = 0; r < rows; r++) { g.fillStyle = "rgba(0,0,0,0.28)"; g.fillRect(0, r * s / rows, s, 3); const off = (r % 2) * s / 8; for (let k = 0; k < 4; k++) g.fillRect((off + k * s / 4) % s, r * s / rows, 3, s / rows); }
});
makeTex("Cobblestone", 6, (g, s) => { for (let i = 0; i < 40; i++) { g.fillStyle = `rgba(0,0,0,${0.06 + rnd() * 0.1})`; const x = rnd() * s, y = rnd() * s; g.beginPath(); g.ellipse(x, y, 14 + rnd() * 10, 10 + rnd() * 8, rnd() * 3, 0, Math.PI * 2); g.fill(); } speckle(g, s, 200, 0.03, 0.06, 1, 2); });
makeTex("Slate", 8, (g, s) => { speckle(g, s, 60, 0.04, 0.1, 10, 30); for (let i = 0; i < 12; i++) { g.strokeStyle = "rgba(0,0,0,0.12)"; g.lineWidth = 2; g.beginPath(); g.moveTo(rnd() * s, rnd() * s); g.lineTo(rnd() * s, rnd() * s); g.stroke(); } });
makeTex("Concrete", 8, (g, s) => { speckle(g, s, 900, 0.02, 0.06, 0.6, 1.6); });
makeTex("Fabric", 2, (g, s) => { for (let i = 0; i < s; i += 4) { g.fillStyle = "rgba(0,0,0,0.05)"; g.fillRect(i, 0, 2, s); g.fillRect(0, i, s, 2); } });
makeTex("DiamondPlate", 3, (g, s) => { g.fillStyle = "rgba(0,0,0,0.18)"; for (let x = 0; x < s; x += 32) for (let y = 0; y < s; y += 32) { g.save(); g.translate(x + ((y / 32) % 2) * 16 + 8, y + 8); g.rotate(0.8); g.fillRect(-7, -2, 14, 4); g.restore(); } });
makeTex("Plaster", 8, (g, s) => { speckle(g, s, 500, 0.02, 0.05, 1, 3); });
makeTex("Metal", 6, (g, s) => { for (let i = 0; i < 80; i++) { g.fillStyle = `rgba(0,0,0,${rnd() * 0.04})`; g.fillRect(0, rnd() * s, s, 1); } });
makeTex("Pavement", 8, (g, s) => { g.fillStyle = "rgba(0,0,0,0.12)"; for (let k = 0; k < 4; k++) { g.fillRect(0, k * s / 4, s, 2); g.fillRect(k * s / 4, 0, 2, s); } speckle(g, s, 400, 0.02, 0.05, 0.6, 1.4); });
TEX.LeafyGrass = TEX.Grass; TEX.Mud = TEX.Ground; TEX.Sandstone = TEX.Sand; TEX.Limestone = TEX.Concrete; TEX.Basalt = TEX.Rock; TEX.Granite = TEX.Rock; TEX.Pebble = TEX.Cobblestone; TEX.Asphalt = TEX.Concrete; TEX.Salt = TEX.Sand; TEX.Marble = TEX.Plaster; TEX.CorrodedMetal = TEX.Metal;

// Texture de tenons (dessus des pièces "Studs")
const studCanvas = noiseCanvas(64, (c) => {
  c.strokeStyle = "rgba(0,0,0,0.10)"; c.lineWidth = 2; c.strokeRect(1, 1, 62, 62);
  c.fillStyle = "rgba(0,0,0,0.13)"; c.beginPath(); c.arc(34, 34, 17, 0, Math.PI * 2); c.fill();
  c.fillStyle = "rgba(255,255,255,0.35)"; c.beginPath(); c.arc(30, 30, 15, 0, Math.PI * 2); c.fill();
});

const ROUGH = { Neon: 0.3, Glass: 0.05, SmoothPlastic: 0.5, Plastic: 0.55, Grass: 0.95, Mud: 1, Sand: 1, Sandstone: 0.95, Slate: 0.9, Brick: 0.9, Cobblestone: 0.95, Wood: 0.8, WoodPlanks: 0.8, Metal: 0.35, CorrodedMetal: 0.7, DiamondPlate: 0.35, Fabric: 1, Rock: 0.95, Concrete: 0.95, Ice: 0.15, Plaster: 0.9, Pavement: 0.95 };

// Matériau d'une Part (texture mondiale : UV recalculés par géométrie)
const matCache = new Map();
function partMaterial(p, faceTex) {
  const key = [p.color.join(","), p.material, p.t, faceTex ? 1 : 0].join("|");
  if (matCache.has(key) && !faceTex) return matCache.get(key);
  const col = rgb(p.color);
  const neon = p.material === "Neon";
  const glass = p.material === "Glass";
  const m = new THREE.MeshStandardMaterial({
    color: col, roughness: ROUGH[p.material] ?? 0.55,
    metalness: p.material === "Metal" || p.material === "DiamondPlate" ? 0.45 : 0,
    transparent: p.t > 0 || glass, opacity: glass ? Math.min(1 - p.t, 0.55) : 1 - p.t,
    emissive: neon ? col : new THREE.Color(0), emissiveIntensity: neon ? 1.6 : 0,
    envMapIntensity: 0.6,
  });
  const tex = TEX[p.material];
  if (tex) m.map = tex;
  if (!faceTex) matCache.set(key, m);
  return m;
}

// UV mondiaux (projection boîte) pour que les textures gardent leur échelle
function boxWorldUV(geo, size, studs) {
  const pos = geo.attributes.position, nor = geo.attributes.normal; const uv = new Float32Array(pos.count * 2);
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i), y = pos.getY(i), z = pos.getZ(i), nx = Math.abs(nor.getX(i)), ny = Math.abs(nor.getY(i));
    let u, v; if (ny > 0.6) { u = x; v = z; } else if (nx > 0.6) { u = z; v = y; } else { u = x; v = y; }
    uv[i * 2] = u / studs; uv[i * 2 + 1] = v / studs;
  }
  geo.setAttribute("uv", new THREE.BufferAttribute(uv, 2));
}

// ---------------------------------------------------------------------------
// Géométries des Parts
// ---------------------------------------------------------------------------
function wedgeGeometry(sx, sy, sz) {
  // Roblox : face verticale à l'arrière (+Z), pente qui descend vers l'avant (-Z)
  const x = sx / 2, y = sy / 2, z = sz / 2;
  const A = [-x, -y, -z], B = [x, -y, -z], C = [-x, -y, z], D = [x, -y, z], E = [-x, y, z], F = [x, y, z];
  const tris = [A, C, D, A, D, B, /* dessous */ C, E, F, C, F, D, /* arrière */ A, B, F, A, F, E, /* pente */ A, E, C, /* gauche */ B, D, F /* droite */];
  const g = new THREE.BufferGeometry(); g.setAttribute("position", new THREE.Float32BufferAttribute(tris.flat(), 3));
  g.computeVertexNormals(); return g;
}
function cornerWedgeGeometry(sx, sy, sz) {
  // Sommet au-dessus du coin (+X, -Z)
  const x = sx / 2, y = sy / 2, z = sz / 2;
  const A = [-x, -y, -z], B = [x, -y, -z], C = [-x, -y, z], D = [x, -y, z], T = [x, y, -z];
  const tris = [A, C, D, A, D, B, B, D, T, A, B, T, D, C, T, C, A, T];
  const g = new THREE.BufferGeometry(); g.setAttribute("position", new THREE.Float32BufferAttribute(tris.flat(), 3));
  g.computeVertexNormals(); return g;
}
// Tête Roblox : cylindre vertical aux arêtes arrondies
function headGeometry(sx, sy, sz) {
  const r = sx > sz * 1.5 ? Math.min(sx * 0.62, sz * 1.25) / 2 : sx / 2, h = sx > sz * 1.5 ? sy * 1.2 / 2 : sy / 2, k = Math.min(r, h) * 0.45;
  const pts = [];
  pts.push(new THREE.Vector2(0, -h));
  for (let i = 0; i <= 6; i++) { const a = -Math.PI / 2 + i / 6 * Math.PI / 2; pts.push(new THREE.Vector2(r - k + Math.cos(a) * k, -h + k + Math.sin(a) * k)); }
  for (let i = 0; i <= 6; i++) { const a = i / 6 * Math.PI / 2; pts.push(new THREE.Vector2(r - k + Math.cos(a) * k, h - k + Math.sin(a) * k)); }
  pts.push(new THREE.Vector2(0, h));
  const g = new THREE.LatheGeometry(pts, 28); g.userData.radius = r; g.userData.half = h; return g;
}
const geoCache = new Map();
function geometry(p) {
  const shape = p.cls === "WedgePart" || p.shape === "Wedge" ? "Wedge" : p.cls === "CornerWedgePart" || p.shape === "CornerWedge" ? "CornerWedge" : p.shape;
  const charPart = p.char && shape === "Block";
  const kind = charPart ? (p.name === "Head" ? "Head" : "Round") : shape;
  const key = kind + p.size.map(v => v.toFixed(2)).join(",") + p.material;
  if (geoCache.has(key)) return geoCache.get(key);
  const s = p.size; let g;
  if (kind === "Head") g = headGeometry(s[0], s[1], s[2]);
  else if (kind === "Round") g = new RoundedBoxGeometry(s[0], s[1], s[2], 2, Math.min(0.18, Math.min(...s) * 0.2));
  else if (shape === "Ball") g = new THREE.SphereGeometry(Math.min(...s) / 2, 28, 18);
  else if (shape === "Cylinder") { g = new THREE.CylinderGeometry(Math.min(s[1], s[2]) / 2, Math.min(s[1], s[2]) / 2, s[0], 40); g.rotateZ(Math.PI / 2); }
  else if (shape === "Wedge") g = wedgeGeometry(s[0], s[1], s[2]);
  else if (shape === "CornerWedge") g = cornerWedgeGeometry(s[0], s[1], s[2]);
  else g = new THREE.BoxGeometry(s[0], s[1], s[2]);
  const tex = TEX[p.material]; if (tex && kind !== "Head") boxWorldUV(g, s, tex.userData.studs);
  geoCache.set(key, g); return g;
}

// Visage classique (yeux + sourire) dessiné sur une petite plaque devant la tête
let faceTexture = null;
function faceMaterial() {
  if (!faceTexture) {
    const c = document.createElement("canvas"); c.width = c.height = 128; const g = c.getContext("2d");
    g.fillStyle = "#1a1a1a";
    g.beginPath(); g.ellipse(44, 52, 7, 12, 0, 0, Math.PI * 2); g.fill();
    g.beginPath(); g.ellipse(84, 52, 7, 12, 0, 0, Math.PI * 2); g.fill();
    g.lineWidth = 7; g.lineCap = "round"; g.strokeStyle = "#1a1a1a"; g.beginPath(); g.arc(64, 70, 24, 0.2 * Math.PI, 0.8 * Math.PI); g.stroke();
    faceTexture = new THREE.CanvasTexture(c); faceTexture.colorSpace = THREE.SRGBColorSpace;
  }
  return new THREE.MeshStandardMaterial({ map: faceTexture, transparent: true, roughness: 0.8, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2 });
}

// ---------------------------------------------------------------------------
// Terrain : colonnes verticales exactes calculées à partir des opérations de
// remplissage (même ordre que Roblox), puis surface lissée.
// ---------------------------------------------------------------------------
const DEFAULT_TERRAIN = {
  Grass: [106, 127, 63], LeafyGrass: [115, 132, 74], Sand: [143, 126, 95], Ground: [102, 92, 59], Mud: [58, 46, 36],
  Rock: [102, 108, 111], Slate: [63, 127, 107], Sandstone: [137, 90, 71], Basalt: [30, 30, 37], Snow: [195, 199, 218],
  Ice: [129, 194, 224], Glacier: [101, 176, 234], Asphalt: [115, 123, 107], Concrete: [127, 102, 63], Cobblestone: [132, 123, 90],
  Brick: [138, 86, 62], WoodPlanks: [139, 109, 79], Pavement: [148, 148, 140], Limestone: [206, 173, 148], Salt: [198, 189, 181],
  CrackedLava: [232, 156, 74],
};

function makeFrame(cf) {
  // cf = [x,y,z,R00..R22] ; colonnes = axes locaux
  return { c: [cf[0], cf[1], cf[2]], ax: [[cf[3], cf[6], cf[9]], [cf[4], cf[7], cf[10]], [cf[5], cf[8], cf[11]]] };
}
// Intervalle [t0,t1] de la verticale (x,z) à l'intérieur d'une boîte orientée
function boxInterval(fr, half, x, z) {
  let t0 = -Infinity, t1 = Infinity;
  for (let k = 0; k < 3; k++) {
    const a = fr.ax[k];
    const base = a[0] * (x - fr.c[0]) + a[2] * (z - fr.c[2]) - a[1] * fr.c[1];
    if (Math.abs(a[1]) < 1e-9) { if (Math.abs(base) > half[k]) return null; continue; }
    let lo = (-half[k] - base) / a[1], hi = (half[k] - base) / a[1]; if (lo > hi) [lo, hi] = [hi, lo];
    t0 = Math.max(t0, lo); t1 = Math.min(t1, hi); if (t0 >= t1) return null;
  }
  return [t0, t1];
}
function local(fr, x, y, z) { return fr.ax.map(a => a[0] * (x - fr.c[0]) + a[1] * (y - fr.c[1]) + a[2] * (z - fr.c[2])); }
function opInterval(op, x, z) {
  if (op.op === "Ball") {
    const dx = x - op.center[0], dz = z - op.center[2], d2 = dx * dx + dz * dz, r2 = op.radius * op.radius;
    if (d2 >= r2) return null; const h = Math.sqrt(r2 - d2); return [op.center[1] - h, op.center[1] + h];
  }
  const fr = op._fr || (op._fr = makeFrame(op.cf));
  if (op.op === "Cylinder") {
    const ax = fr.ax[1];
    if (Math.abs(ax[1]) > 0.999) { // debout
      const dx = x - fr.c[0], dz = z - fr.c[2]; if (dx * dx + dz * dz >= op.radius * op.radius) return null;
      return [fr.c[1] - op.height / 2, fr.c[1] + op.height / 2];
    }
    return boxInterval(fr, [op.radius, op.height / 2, op.radius], x, z);
  }
  const half = [op.size[0] / 2, op.size[1] / 2, op.size[2] / 2];
  const iv = boxInterval(fr, half, x, z); if (!iv) return null;
  if (op.op !== "Wedge") return iv;
  // Coin : garder la partie sous la pente  (y+h)/H <= (z+d)/D en local
  const f = t => { const l = local(fr, x, t, z); return (l[1] + half[1]) / op.size[1] - (l[2] + half[2]) / op.size[2]; };
  const f0 = f(iv[0]), f1 = f(iv[1]);
  if (f0 > 0 && f1 > 0) return null; if (f0 <= 0 && f1 <= 0) return iv;
  const tc = iv[0] + (iv[1] - iv[0]) * (f0 / (f0 - f1));
  return f0 <= 0 ? [iv[0], tc] : [tc, iv[1]];
}
function opBounds(op) {
  if (op.op === "Ball") return [op.center[0] - op.radius, op.center[0] + op.radius, op.center[2] - op.radius, op.center[2] + op.radius];
  const fr = makeFrame(op.cf); const half = op.op === "Cylinder" ? [op.radius, op.height / 2, op.radius] : op.size.map(v => v / 2);
  let ex = 0, ez = 0; for (let k = 0; k < 3; k++) { ex += Math.abs(fr.ax[k][0]) * half[k]; ez += Math.abs(fr.ax[k][2]) * half[k]; }
  return [fr.c[0] - ex, fr.c[0] + ex, fr.c[2] - ez, fr.c[2] + ez];
}
// Colonne : liste triée d'intervalles [y0, y1, matIndex]
function subtract(col, a, b) {
  const out = [];
  for (const s of col) {
    if (s[1] <= a || s[0] >= b) { out.push(s); continue; }
    if (s[0] < a) out.push([s[0], a, s[2]]);
    if (s[1] > b) out.push([b, s[1], s[2]]);
  }
  return out;
}

function buildTerrain(scene, data, center, extent) {
  const ops = arr(data.terrain); if (!ops.length) return;
  const RES = 2;
  const mats = []; const matIndex = name => { let i = mats.indexOf(name); if (i < 0) { mats.push(name); i = mats.length - 1; } return i; };
  let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
  const clamp = [center[0] - extent, center[0] + extent, center[2] - extent, center[2] + extent];
  for (const op of ops) { const b = opBounds(op); op._b = b; minX = Math.min(minX, b[0]); maxX = Math.max(maxX, b[1]); minZ = Math.min(minZ, b[2]); maxZ = Math.max(maxZ, b[3]); }
  minX = Math.max(minX, clamp[0]); maxX = Math.min(maxX, clamp[1]); minZ = Math.max(minZ, clamp[2]); maxZ = Math.min(maxZ, clamp[3]);
  if (!(maxX > minX && maxZ > minZ)) return;
  const nx = Math.floor((maxX - minX) / RES) + 1, nz = Math.floor((maxZ - minZ) / RES) + 1;
  const cols = new Array(nx * nz);
  for (const op of ops) {
    const b = op._b; const air = op.material === "Air"; const mi = air ? -1 : matIndex(op.material);
    const i0 = Math.max(0, Math.floor((b[0] - minX) / RES)), i1 = Math.min(nx - 1, Math.ceil((b[1] - minX) / RES));
    const j0 = Math.max(0, Math.floor((b[2] - minZ) / RES)), j1 = Math.min(nz - 1, Math.ceil((b[3] - minZ) / RES));
    for (let j = j0; j <= j1; j++) for (let i = i0; i <= i1; i++) {
      const x = minX + i * RES, z = minZ + j * RES; const iv = opInterval(op, x, z); if (!iv) continue;
      const idx = j * nx + i; let col = cols[idx] || [];
      col = subtract(col, iv[0], iv[1]); if (!air) col.push([iv[0], iv[1], mi]);
      cols[idx] = col;
    }
  }
  const waterIdx = mats.indexOf("Water");
  // Hauteur du sol (solide le plus haut) et de l'eau
  const hs = new Float32Array(nx * nz).fill(NaN), hw = new Float32Array(nx * nz).fill(NaN); const ms = new Int16Array(nx * nz).fill(-1);
  for (let k = 0; k < cols.length; k++) {
    const col = cols[k]; if (!col) continue;
    let top = -Infinity, tm = -1, wtop = -Infinity;
    for (const s of col) { if (s[1] - s[0] < 0.01) continue; if (s[2] === waterIdx) { if (s[1] > wtop) wtop = s[1]; } else if (s[1] > top) { top = s[1]; tm = s[2]; } }
    if (tm >= 0) { hs[k] = top; ms[k] = tm; }
    if (wtop > -Infinity && wtop > top) hw[k] = wtop;
  }
  // Lissage léger (comme les voxels "smooth" de Roblox), sans toucher aux zones plates
  const sm = new Float32Array(hs);
  for (let j = 1; j < nz - 1; j++) for (let i = 1; i < nx - 1; i++) {
    const k = j * nx + i; if (isNaN(hs[k])) continue; let sum = 0, n = 0;
    for (let dj = -1; dj <= 1; dj++) for (let di = -1; di <= 1; di++) { const v = hs[k + dj * nx + di]; if (!isNaN(v)) { sum += v; n++; } }
    sm[k] = sum / n;
  }
  const colors = data.terrainColors || {};
  const matColor = mats.map(m => rgb(colors[m] || DEFAULT_TERRAIN[m] || [120, 120, 120]));
  const hash = (i, j) => { const s = Math.sin(i * 12.9898 + j * 78.233) * 43758.5453; return s - Math.floor(s); };
  function surface(heights, withColor, cond) {
    const pos = [], col = [], uv = [], idx = []; const vid = new Int32Array(nx * nz).fill(-1);
    for (let j = 0; j < nz; j++) for (let i = 0; i < nx; i++) {
      const k = j * nx + i; const h = heights[k]; if (isNaN(h) || (cond && !cond(k))) continue;
      vid[k] = pos.length / 3; const x = minX + i * RES, z = minZ + j * RES;
      pos.push(x, h, z); uv.push(x / 8, z / 8);
      if (withColor) {
        const c = matColor[ms[k]] || new THREE.Color(0.5, 0.5, 0.5); const n = 0.94 + hash(i, j) * 0.1 + (hash(i >> 3, j >> 3) - 0.5) * 0.06;
        col.push(c.r * n, c.g * n, c.b * n);
      }
    }
    for (let j = 0; j < nz - 1; j++) for (let i = 0; i < nx - 1; i++) {
      const a = vid[j * nx + i], b = vid[j * nx + i + 1], c = vid[(j + 1) * nx + i], d = vid[(j + 1) * nx + i + 1];
      if (a >= 0 && b >= 0 && c >= 0 && d >= 0) { idx.push(a, c, b, b, c, d); }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
    g.setAttribute("uv", new THREE.Float32BufferAttribute(uv, 2));
    if (withColor) g.setAttribute("color", new THREE.Float32BufferAttribute(col, 3));
    g.setIndex(idx); g.computeVertexNormals(); return g;
  }
  // Adoucit les transitions de matière (couleurs moyennées sur 3x3, comme le
  // fondu entre matériaux du Terrain Roblox)
  const groundGeo = surface(sm, true);
  {
    const pos = groundGeo.attributes.position, colA = groundGeo.attributes.color;
    const map = new Map(); for (let v = 0; v < pos.count; v++) map.set(Math.round((pos.getX(v) - minX) / RES) + "," + Math.round((pos.getZ(v) - minZ) / RES), v);
    const out = new Float32Array(colA.array.length);
    for (let v = 0; v < pos.count; v++) {
      const i = Math.round((pos.getX(v) - minX) / RES), j = Math.round((pos.getZ(v) - minZ) / RES); let r = 0, g = 0, b = 0, n = 0;
      for (let dj = -1; dj <= 1; dj++) for (let di = -1; di <= 1; di++) { const u = map.get((i + di) + "," + (j + dj)); if (u !== undefined) { const w = di === 0 && dj === 0 ? 2 : 1; r += colA.getX(u) * w; g += colA.getY(u) * w; b += colA.getZ(u) * w; n += w; } }
      out[v * 3] = r / n; out[v * 3 + 1] = g / n; out[v * 3 + 2] = b / n;
    }
    groundGeo.setAttribute("color", new THREE.BufferAttribute(out, 3));
  }
  const ground = new THREE.Mesh(groundGeo, new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.95, map: TEX.Grass }));
  ground.receiveShadow = true; ground.castShadow = true; scene.add(ground);
  if (waterIdx >= 0) {
    const w = data.water || { color: [36, 150, 186], transparency: 0.35 };
    const water = new THREE.Mesh(surface(hw, false), new THREE.MeshStandardMaterial({ color: rgb(w.color), roughness: 0.08, metalness: 0.1, transparent: true, opacity: Math.max(0.55, 1 - w.transparency), envMapIntensity: 1.4 }));
    water.receiveShadow = true; scene.add(water);
  }
}

// ---------------------------------------------------------------------------
// Ciel, soleil, brume
// ---------------------------------------------------------------------------
function skyTexture(L) {
  const c = document.createElement("canvas"); c.width = 16; c.height = 512; const g = c.getContext("2d");
  const clock = L ? L.clock : 14;
  const stops = clock > 17.8 ? ["#2c3f6e", "#6f78a8", "#f2a77c", "#ffcf9a"]
    : clock > 16.8 ? ["#4f86d8", "#a9c4ee", "#ffd7b0", "#ffc89a"]
    : ["#2f7fe6", "#7cbcff", "#cfe7ff", "#e8f4ff"];
  const grad = g.createLinearGradient(0, 0, 0, 512);
  grad.addColorStop(0, stops[0]); grad.addColorStop(0.55, stops[1]); grad.addColorStop(0.85, stops[2]); grad.addColorStop(1, stops[3]);
  g.fillStyle = grad; g.fillRect(0, 0, 16, 512);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
}
function cloudLayer(scene, center, L) {
  const c = document.createElement("canvas"); c.width = c.height = 1024; const g = c.getContext("2d");
  seed = 7;
  for (let i = 0; i < 70; i++) {
    const x = rnd() * 1024, y = rnd() * 1024, r = 30 + rnd() * 70;
    for (let k = 0; k < 6; k++) {
      const gx = x + (rnd() - 0.5) * r * 1.6, gy = y + (rnd() - 0.5) * r * 0.6, gr = r * (0.5 + rnd() * 0.5);
      const rg = g.createRadialGradient(gx, gy, 0, gx, gy, gr); rg.addColorStop(0, "rgba(255,255,255,0.85)"); rg.addColorStop(1, "rgba(255,255,255,0)");
      g.fillStyle = rg; g.beginPath(); g.arc(gx, gy, gr, 0, Math.PI * 2); g.fill();
    }
  }
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace;
  const tint = L && L.clock > 17.8 ? new THREE.Color("#f4b8a0") : L && L.clock > 16.8 ? new THREE.Color("#ffe6d2") : new THREE.Color("#ffffff");
  const m = new THREE.Mesh(new THREE.PlaneGeometry(9000, 9000), new THREE.MeshBasicMaterial({ map: t, transparent: true, depthWrite: false, fog: false, color: tint, opacity: 0.9 }));
  m.rotation.x = Math.PI / 2; m.position.set(center[0], 700, center[2]); scene.add(m);
}

// ---------------------------------------------------------------------------
// Rendu principal
// ---------------------------------------------------------------------------
export async function render3D(data, { W, H, drawGui, layoutChildren }) {
  const canvas = document.getElementById("gl");
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, preserveDrawingBuffer: true });
  renderer.setSize(W, H); renderer.setPixelRatio(data.pixelRatio || 1.5);
  renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.outputColorSpace = THREE.SRGBColorSpace; renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.0;

  const L = data.lighting || null;
  const scene = new THREE.Scene();
  scene.background = data.sky ? new THREE.Color(data.sky) : skyTexture(L);
  const c = data.center || [0, 0, 0];

  // Brume (Atmosphere) : densité -> distance de brume
  const atm = L && L.atmosphere;
  const hazeColor = atm && atm.color ? rgb(atm.color) : new THREE.Color("#d6e8ff");
  const density = atm ? atm.density ?? 0.2 : 0.2;
  scene.fog = new THREE.Fog(hazeColor, 260 + (1 - density) * 500, 1200 + (1 - density) * 2200);

  // Soleil d'après l'heure (ClockTime)
  const clock = L ? L.clock : 14;
  const ang = (clock - 6) / 12 * Math.PI;
  const elev = Math.max(0.12, Math.sin(ang) * 0.9);
  const sunDir = new THREE.Vector3(-Math.cos(ang) * 0.75, elev, 0.55).normalize();
  const low = elev < 0.45;
  const sunColor = low ? new THREE.Color("#ffd2a0") : new THREE.Color("#fff6e8");
  const brightness = L ? L.brightness : 2.6;
  const outdoor = L && L.outdoor ? rgb(L.outdoor) : new THREE.Color("#9aa0b0");
  scene.add(new THREE.HemisphereLight(new THREE.Color("#cfe4ff").lerp(outdoor, 0.3), new THREE.Color("#7a8a60").lerp(outdoor, 0.4), 1.15));
  scene.add(new THREE.AmbientLight(outdoor, 0.35));
  // Jour / crépuscule : l'intensité suit la hauteur du soleil
  const day = Math.min(1, Math.max(0.42, Math.sin(ang) * 1.4 + 0.35));
  scene.children.filter(o => o.isLight).forEach(o => { o.intensity *= 0.55 + 0.45 * day; });
  const sun = new THREE.DirectionalLight(clock > 17.8 ? new THREE.Color("#ffb27a") : sunColor, (1.2 + brightness * 0.55) * day);
  // Ombres : cadrées sur la zone regardée par la caméra
  const cam = data.camera; const tgt = cam.target;
  const focus = new THREE.Vector3(tgt[0], tgt[1], tgt[2]);
  const camPos = new THREE.Vector3(...cam.position);
  const span = cam.ortho ? cam.ortho * 0.75 : Math.min(data.shadowExtent || 260, Math.max(60, camPos.distanceTo(focus) * 1.1));
  sun.position.copy(focus).addScaledVector(sunDir, 600); sun.target.position.copy(focus);
  sun.castShadow = true; sun.shadow.mapSize.set(4096, 4096);
  Object.assign(sun.shadow.camera, { left: -span, right: span, top: span, bottom: -span, near: 10, far: 1400 });
  sun.shadow.bias = -0.0004; sun.shadow.normalBias = 0.04; sun.shadow.radius = 3;
  scene.add(sun, sun.target);

  // Reflets doux (environnement)
  const pmrem = new THREE.PMREMGenerator(renderer);
  const envScene = new THREE.Scene(); envScene.background = skyTexture(L);
  scene.environment = pmrem.fromScene(envScene, 0.04).texture;

  cloudLayer(scene, c, L);
  buildTerrain(scene, data, c, Math.max(500, (data.shadowExtent || 260) + 700));

  // ---------- Parts ----------
  const FACE = {
    Front: { dims: s => [s[0], s[1]], pos: s => [0, 0, -s[2] / 2], rot: [0, Math.PI, 0] },
    Back: { dims: s => [s[0], s[1]], pos: s => [0, 0, s[2] / 2], rot: [0, 0, 0] },
    Right: { dims: s => [s[2], s[1]], pos: s => [s[0] / 2, 0, 0], rot: [0, Math.PI / 2, 0] },
    Left: { dims: s => [s[2], s[1]], pos: s => [-s[0] / 2, 0, 0], rot: [0, -Math.PI / 2, 0] },
    Top: { dims: s => [s[0], s[2]], pos: s => [0, s[1] / 2, 0], rot: [-Math.PI / 2, 0, 0] },
    Bottom: { dims: s => [s[0], s[2]], pos: s => [0, -s[1] / 2, 0], rot: [Math.PI / 2, 0, 0] },
  };
  const highlightByModel = new Map(); for (const h of arr(data.highlights)) highlightByModel.set(h.model, h);
  const studCache = new Map();
  function studTexture(sx, sz) {
    const key = Math.round(sx) + "x" + Math.round(sz); if (studCache.has(key)) return studCache.get(key);
    const t = new THREE.CanvasTexture(studCanvas); t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.repeat.set(Math.max(1, sx / 2), Math.max(1, sz / 2)); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8; studCache.set(key, t); return t;
  }
  for (const p of arr(data.parts)) {
    const geo = geometry(p);
    let meshMat = partMaterial(p);
    if (p.studs && p.shape === "Block" && p.cls !== "WedgePart") {
      const base = partMaterial({ ...p, material: "SmoothPlastic" });
      const top = base.clone(); top.map = studTexture(p.size[0], p.size[2]);
      meshMat = [base, base, top, base, base, base];
    }
    const mesh = new THREE.Mesh(geo, meshMat);
    const m = p.cf; mesh.matrixAutoUpdate = false;
    mesh.matrix.set(m[3], m[4], m[5], m[0], m[6], m[7], m[8], m[1], m[9], m[10], m[11], m[2], 0, 0, 0, 1);
    mesh.castShadow = p.t < 0.5 && p.material !== "Glass" && Math.max(...p.size) < 400; mesh.receiveShadow = true;
    scene.add(mesh);
    if (p.char && p.name === "Head" && p.shape === "Block") {
      const r = geo.userData.radius || p.size[2] / 2, hh = geo.userData.half || p.size[1] / 2;
      const face = new THREE.Mesh(new THREE.PlaneGeometry(r * 1.5, hh * 1.5), faceMaterial());
      face.position.set(0, -hh * 0.05, -r - 0.02); face.rotation.y = Math.PI; face.updateMatrix();
      const holder = new THREE.Object3D(); holder.matrixAutoUpdate = false; holder.matrix.copy(mesh.matrix); holder.add(face); scene.add(holder);
    }
    const hl = p.model && highlightByModel.get(p.model);
    if (hl && p.name !== "HumanoidRootPart") {
      const outline = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({ color: rgb(hl.outline), side: THREE.BackSide, fog: false }));
      outline.matrixAutoUpdate = false;
      outline.matrix.copy(mesh.matrix).multiply(new THREE.Matrix4().makeScale(...p.size.map(s => (s + 0.35) / s)));
      scene.add(outline);
    }
    for (const g of arr(p.guis)) {
      const f = FACE[g.face]; if (!f) continue;
      const [fw, fh] = f.dims(p.size); const K = 40;
      const scale = Math.min(1, 2048 / Math.max(fw * K, fh * K));
      const cw = Math.max(2, Math.round(fw * K * scale)), ch = Math.max(2, Math.round(fh * K * scale));
      const cv = document.createElement("canvas"); cv.width = cw; cv.height = ch; const ctx = cv.getContext("2d");
      for (const [kid, r] of layoutChildren({ children: arr(g.children) }, [0, 0, cw, ch], scale)) drawGui(ctx, kid, r, scale);
      const tex = new THREE.CanvasTexture(cv); tex.colorSpace = THREE.SRGBColorSpace; tex.anisotropy = 8;
      const plane = new THREE.Mesh(new THREE.PlaneGeometry(fw, fh), new THREE.MeshBasicMaterial({ map: tex, transparent: true, toneMapped: false }));
      const pos = f.pos(p.size); const n = new THREE.Vector3(...pos).normalize().multiplyScalar(0.03);
      plane.position.set(pos[0] + n.x, pos[1] + n.y, pos[2] + n.z); plane.rotation.set(...f.rot); plane.updateMatrix();
      const holder = new THREE.Object3D(); holder.matrixAutoUpdate = false; holder.matrix.copy(mesh.matrix); holder.add(plane); scene.add(holder);
    }
  }

  // ---------- Caméra ----------
  let camera;
  if (cam.ortho) { const half = cam.ortho / 2, aspect = W / H; camera = new THREE.OrthographicCamera(-half * aspect, half * aspect, half, -half, 1, 4000); }
  else camera = new THREE.PerspectiveCamera(cam.fov || 60, W / H, 0.5, 6000);
  camera.position.set(...cam.position); camera.up.set(...(cam.up || [0, 1, 0])); camera.lookAt(...cam.target);
  camera.updateMatrixWorld();

  // ---------- Post-traitement : occlusion ambiante + bloom des néons ----------
  const composer = new EffectComposer(renderer);
  composer.addPass(new RenderPass(scene, camera));
  if (!cam.ortho && data.ao !== false) {
    const ao = new GTAOPass(scene, camera, W, H);
    ao.output = GTAOPass.OUTPUT.Default;
    ao.updateGtaoMaterial({ radius: 1.6, distanceExponent: 1.5, thickness: 2.5, scale: 1.2, samples: 12 });
    ao.blendIntensity = 0.85;
    composer.addPass(ao);
  }
  const bloom = L && L.bloom;
  composer.addPass(new UnrealBloomPass(new THREE.Vector2(W, H), bloom ? Math.min(0.6, bloom.intensity) : 0.35, 0.5, 0.92));
  composer.addPass(new OutputPass());
  composer.render();

  // Correction colorimétrique (ColorCorrectionEffect) appliquée à l'image
  const cc = L && L.cc;
  if (cc) {
    canvas.style.filter = `saturate(${1 + (cc.saturation || 0)}) contrast(${1 + (cc.contrast || 0)}) brightness(${1 + (cc.brightness || 0)})`;
    if (cc.tint && (cc.tint[0] < 254 || cc.tint[1] < 254 || cc.tint[2] < 254)) {
      const tint = document.createElement("div");
      Object.assign(tint.style, { position: "absolute", left: 0, top: 0, width: W + "px", height: H + "px", background: `rgb(${cc.tint.join(",")})`, mixBlendMode: "multiply", pointerEvents: "none" });
      canvas.parentElement.insertBefore(tint, canvas.nextSibling);
    }
  }
  return { camera, scene };
}
