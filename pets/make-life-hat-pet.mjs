/**
 * LIFE Hat — an original desk-pet spritesheet, hand-drawn ink style.
 *
 * Character (from the reference sketch):
 *   a small figure seen from behind, sitting on the ground with splayed legs,
 *   dark soles facing the viewer, head swallowed by an oversized black top hat
 *   lettered "LIFE", one arm resting beside a yellow banana peel, a crumpled
 *   paper and a tiny bug on the ground.
 *
 * Output: v2 atlas, 1536 x 2288, 8 cols x 11 rows, 192 x 208 cells, RGBA PNG.
 * Everything is drawn procedurally with signed-distance shapes and analytic AA,
 * so every frame shares one locked silhouette and no pixels are guessed.
 */
import { deflateSync } from 'node:zlib';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const CW = 192;
const CH = 208;
const COLS = 8;
const ROWS = 11;
const AW = CW * COLS;
const AH = CH * ROWS;

const INK = [26, 24, 22];
const PAPER = [252, 248, 239];
const HATC = [44, 40, 38];
const SOLEC = [40, 36, 33];
const YELLOW = [255, 206, 61];
const BUG = [30, 27, 25];
const WHITE = [255, 255, 255];
const BLUSH = [233, 216, 196];

const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const lerp = (a, b, t) => a + (b - a) * t;
const TAU = Math.PI * 2;

/* ---------------------------------------------------------------- canvas --- */

class Canvas {
  constructor(w, h) {
    this.w = w;
    this.h = h;
    this.r = new Float64Array(w * h);
    this.g = new Float64Array(w * h);
    this.b = new Float64Array(w * h);
    this.a = new Float64Array(w * h);
  }

  over(i, col, cov) {
    if (cov <= 0.0009) return;
    const da = this.a[i];
    const oa = cov + da * (1 - cov);
    if (oa <= 0) return;
    const k = da * (1 - cov) / oa;
    const s = cov / oa;
    this.r[i] = col[0] * s + this.r[i] * k;
    this.g[i] = col[1] * s + this.g[i] * k;
    this.b[i] = col[2] * s + this.b[i] * k;
    this.a[i] = oa;
  }
}

/* ------------------------------------------------------------- rasteriser --- */

/** Rasterise a signed-distance field into the canvas inside a bbox. */
function stamp(ctx, box, sd, col, alpha) {
  const x0 = Math.max(0, Math.floor(box[0]));
  const x1 = Math.min(ctx.w - 1, Math.ceil(box[2]));
  const y0 = Math.max(0, Math.floor(box[1]));
  const y1 = Math.min(ctx.h - 1, Math.ceil(box[3]));
  for (let y = y0; y <= y1; y++) {
    const py = y + 0.5;
    for (let x = x0; x <= x1; x++) {
      const d = sd(x + 0.5, py);
      if (d > 0.75) continue;
      ctx.over(y * ctx.w + x, col, clamp01(0.5 - d) * alpha);
    }
  }
}

function segDist(px, py, ax, ay, bx, by) {
  const vx = bx - ax;
  const vy = by - ay;
  const wx = px - ax;
  const wy = py - ay;
  const l2 = vx * vx + vy * vy;
  let t = l2 > 1e-9 ? (wx * vx + wy * vy) / l2 : 0;
  t = t < 0 ? 0 : t > 1 ? 1 : t;
  return { d: Math.hypot(wx - vx * t, wy - vy * t), t };
}

/** Stroke/brush path: polyline with a per-point radius. */
function pathBox(pts, pad) {
  let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity, r = 0;
  for (const p of pts) {
    if (p.x < x0) x0 = p.x;
    if (p.x > x1) x1 = p.x;
    if (p.y < y0) y0 = p.y;
    if (p.y > y1) y1 = p.y;
    if (p.r > r) r = p.r;
  }
  return [x0 - r - pad, y0 - r - pad, x1 + r + pad, y1 + r + pad];
}

function pathSD(pts) {
  if (pts.length === 1) {
    const c = pts[0];
    return (x, y) => Math.hypot(x - c.x, y - c.y) - c.r;
  }
  return (x, y) => {
    let best = Infinity;
    for (let i = 0; i < pts.length - 1; i++) {
      const A = pts[i];
      const B = pts[i + 1];
      const s = segDist(x, y, A.x, A.y, B.x, B.y);
      const d = s.d - (A.r + (B.r - A.r) * s.t);
      if (d < best) best = d;
    }
    return best;
  };
}

function drawPath(ctx, pts, o) {
  if (!pts.length) return;
  const sw = o.sw ?? 2.2;
  const alpha = o.alpha ?? 1;
  const sd = pathSD(pts);
  const box = pathBox(pts, sw + 2);
  if (o.fill) stamp(ctx, box, sd, o.fill, alpha * (o.fillAlpha ?? 1));
  if (o.stroke) {
    const h = sw / 2;
    stamp(ctx, box, (x, y) => Math.abs(sd(x, y)) - h, o.stroke, alpha * (o.strokeAlpha ?? 1));
  }
}

function drawEllipse(ctx, cx, cy, rx, ry, rot, o) {
  const c = Math.cos(rot || 0);
  const s = Math.sin(rot || 0);
  const m = Math.min(rx, ry);
  const sd = (x, y) => {
    const dx = x - cx;
    const dy = y - cy;
    const u = (dx * c + dy * s) / rx;
    const v = (-dx * s + dy * c) / ry;
    return (Math.hypot(u, v) - 1) * m;
  };
  const sw = o.sw ?? 2.2;
  const rad = Math.max(rx, ry) + sw + 2;
  const box = [cx - rad, cy - rad, cx + rad, cy + rad];
  const alpha = o.alpha ?? 1;
  if (o.fill) stamp(ctx, box, sd, o.fill, alpha);
  if (o.stroke) stamp(ctx, box, (x, y) => Math.abs(sd(x, y)) - sw / 2, o.stroke, alpha);
}

function drawPoly(ctx, pts, o) {
  const n = pts.length;
  const sd = (x, y) => {
    let inside = false;
    let best = Infinity;
    for (let i = 0, j = n - 1; i < n; j = i++) {
      const A = pts[j];
      const B = pts[i];
      if ((A.y > y) !== (B.y > y) && x < ((B.x - A.x) * (y - A.y)) / (B.y - A.y) + A.x) {
        inside = !inside;
      }
      const s = segDist(x, y, A.x, A.y, B.x, B.y);
      if (s.d < best) best = s.d;
    }
    return inside ? -best : best;
  };
  const sw = o.sw ?? 2.2;
  let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
  for (const p of pts) {
    x0 = Math.min(x0, p.x);
    x1 = Math.max(x1, p.x);
    y0 = Math.min(y0, p.y);
    y1 = Math.max(y1, p.y);
  }
  const box = [x0 - sw - 2, y0 - sw - 2, x1 + sw + 2, y1 + sw + 2];
  const alpha = o.alpha ?? 1;
  if (o.fill) stamp(ctx, box, sd, o.fill, alpha);
  if (o.stroke) stamp(ctx, box, (x, y) => Math.abs(sd(x, y)) - sw / 2, o.stroke, alpha);
}

/* -------------------------------------------------------------- transforms --- */

const P = (x, y, r) => ({ x, y, r });

function makeTf(pose) {
  const rad = pose.lean || 0;
  const c = Math.cos(rad);
  const s = Math.sin(rad);
  const [px, py] = pose.pivot || [96, 172];
  const bob = pose.bob || 0;
  const sx = pose.sx ?? 1;
  const sy = pose.sy ?? 1;
  return (x, y) => {
    const dx = (x - px) * sx;
    const dy = (y - py) * sy;
    return [px + dx * c - dy * s, py + dx * s + dy * c + bob];
  };
}

function makeHatTf(tf, pose) {
  const tilt = pose.hatTilt || 0;
  const px = 96;
  const py = 78;
  const c = Math.cos(tilt);
  const s = Math.sin(tilt);
  const dx0 = pose.hatDX || 0;
  const dy0 = pose.hatDY || 0;
  return (x, y) => {
    const dx = x - px;
    const dy = y - py;
    return tf(px + dx * c - dy * s + dx0, py + dx * s + dy * c + dy0);
  };
}

/* -------------------------------------------------------------------- art --- */

const GROUND_Y = 177;

const HAT_CROWN = [
  [68, 31], [96, 30], [124, 31], [131, 58], [133, 79], [96, 80.5], [59, 79], [61, 58],
];

// extra hand-drawn wobble for the crown, fixed for every frame
const WOBBLE = [
  [0.4, -0.5], [0.1, 0.6], [-0.5, -0.3], [0.6, 0.4], [-0.2, 0.5], [0.3, -0.4], [-0.6, 0.2], [0.5, 0.1],
];

function drawHatLetters(ctx, hatTf) {
  const y0 = 42;
  const y1 = 61;
  const at = (p) => {
    const [x, y] = hatTf(p.x, p.y);
    return { x, y, r: 0 };
  };
  const seg = (x0, yy0, x1, yy1) => [P(x0, yy0, 0), P(x1, yy1, 0)];
  const letters = [
    seg(70, y0, 70, y1), seg(70, y1, 80, y1), // L
    seg(85, y0, 85, y1), seg(81.5, y0, 88.5, y0), seg(81.5, y1, 88.5, y1), // I
    seg(95, y0, 95, y1), seg(95, y0, 105, y0), seg(95, 52, 102, 52), // F
    seg(110, y0, 110, y1), seg(110, y0, 121, y0), seg(110, 52, 118, 52), seg(110, y1, 121, y1), // E
  ];
  for (const s of letters) {
    drawPath(ctx, s.map(at), { stroke: WHITE, sw: 3.1, strokeAlpha: 0.97 });
  }
}

function drawHat(ctx, tf, pose, withText = true) {
  const hatTf = makeHatTf(tf, pose);
  const crown = HAT_CROWN.map((p, i) => {
    const [x, y] = hatTf(p[0] + WOBBLE[i][0], p[1] + WOBBLE[i][1]);
    return { x, y };
  });
  drawPoly(ctx, crown, { fill: HATC, stroke: INK, sw: 2.6 });

  // brim: a shallow ellipse, slightly tipped with the hat
  const [bcx, bcy] = hatTf(96, 80);
  drawEllipse(ctx, bcx, bcy, 50, 8.6, (pose.hatTilt || 0) * 0.9, {
    fill: HATC,
    stroke: INK,
    sw: 2.6,
  });
  // brim underside highlight so the hat reads as a hat, not a blob
  drawEllipse(ctx, bcx, bcy + 2.2, 44, 3.2, (pose.hatTilt || 0) * 0.9, {
    fill: [70, 64, 60],
    alpha: 0.5,
    sw: 0,
  });

  if (withText) drawHatLetters(ctx, hatTf);
}

function drawBody(ctx, tf, pose) {
  const body = [
    P(96, 102, 31),
    P(96, 128, 29.5),
    P(96, 147, 28.5),
  ].map((p) => {
    const [x, y] = tf(p.x, p.y);
    return P(x, y, p.r);
  });
  drawPath(ctx, body, { fill: PAPER, stroke: INK, sw: 2.6 });
}

function drawLegs(ctx, tf, pose) {
  const fL = pose.footL || { x: 44, y: 170, rot: -0.34 };
  const fR = pose.footR || { x: 148, y: 170, rot: 0.34 };
  const legs = [
    { hip: P(84, 151, 9.4), knee: P(64, 162, 8.4), foot: fL },
    { hip: P(108, 151, 9.4), knee: P(128, 162, 8.4), foot: fR },
  ];
  for (const L of legs) {
    const end = P(lerp(L.knee.x, L.foot.x, 0.92), lerp(L.knee.y, L.foot.y, 0.92), 7.6);
    const pts = [L.hip, L.knee, end].map((p) => {
      const [x, y] = tf(p.x, p.y);
      return P(x, y, p.r);
    });
    drawPath(ctx, pts, { fill: PAPER, stroke: INK, sw: 2.5 });
  }
  for (const f of [fL, fR]) {
    const [x, y] = tf(f.x, f.y);
    drawEllipse(ctx, x, y, 11.0, 8.2, (f.rot || 0) + (pose.lean || 0), {
      fill: SOLEC,
      stroke: INK,
      sw: 2.2,
    });
  }
}

function drawArms(ctx, tf, pose) {
  const hL = pose.handL || { x: 62, y: 171 };
  const hR = pose.handR || { x: 130, y: 171 };
  const arms = [
    { sh: P(72, 112, 6.8), el: P(lerp(72, hL.x, 0.55), lerp(112, hL.y, 0.5), 6.2), hand: hL },
    { sh: P(120, 112, 6.8), el: P(lerp(120, hR.x, 0.55), lerp(112, hR.y, 0.5), 6.2), hand: hR },
  ];
  for (const a of arms) {
    const pts = [
      a.sh,
      a.el,
      P(a.hand.x, a.hand.y, 5.6),
    ].map((p) => {
      const [x, y] = tf(p.x, p.y);
      return P(x, y, p.r);
    });
    drawPath(ctx, pts, { fill: PAPER, stroke: INK, sw: 2.4 });
    // mitten hand
    const [hx, hy] = tf(a.hand.x, a.hand.y);
    drawEllipse(ctx, hx, hy, 6.6, 6.0, 0, { fill: PAPER, stroke: INK, sw: 2.2 });
  }
}

function drawGroundLine(ctx, alpha = 0.55) {
  const pts = [];
  for (let x = 22; x <= 170; x += 6) {
    const wob = Math.sin(x * 0.11) * 0.8 + Math.sin(x * 0.37 + 1.2) * 0.4;
    pts.push(P(x, GROUND_Y + wob, 0));
  }
  drawPath(ctx, pts, { stroke: INK, sw: 2.0, strokeAlpha: alpha });
}

function drawBanana(ctx, tf, dx = 0, dy = 0) {
  const t = (x, y, r) => {
    const [a, b] = tf(x + dx, y + dy);
    return P(a, b, r);
  };
  // two short peeled flaps splaying up out of the fruit
  const flaps = [
    [t(115, 184, 3.0), t(112, 179, 2.7), t(110, 175, 2.2)],
    [t(121, 184, 3.0), t(124, 179, 2.7), t(126, 176, 2.2)],
  ];
  for (const f of flaps) drawPath(ctx, f, { fill: YELLOW, stroke: INK, sw: 2.0 });
  // the banana itself, lying on the ground
  drawPath(ctx, [t(107, 187, 3.4), t(117, 184, 3.6), t(128, 187, 3.4)], {
    fill: YELLOW,
    stroke: INK,
    sw: 2.2,
  });
  // stem
  drawPath(ctx, [t(130, 187, 2.0), t(133, 185, 1.7)], { fill: [216, 182, 84], stroke: INK, sw: 1.6 });
}

function drawPaper(ctx, tf, cx = 33, cy = 170, s = 1, rot = 0) {
  const base = [
    [-9, -1], [-4, -7], [1, -6.2], [4, -8], [9, -3], [8, 5], [1, 8], [-6, 5],
  ];
  const c = Math.cos(rot);
  const sn = Math.sin(rot);
  const pts = base.map(([x, y]) => {
    const px = x * s;
    const py = y * s;
    const [a, b] = tf(cx + px * c - py * sn, cy + px * sn + py * c);
    return { x: a, y: b };
  });
  drawPoly(ctx, pts, { fill: PAPER, stroke: INK, sw: 2.0 });
  const creases = [
    [[-5, -2], [1, 1]],
    [[0, 6], [4, 0]],
    [[2, -5], [-1, 1]],
  ];
  for (const [u, v] of creases) {
    const [a1, b1] = tf(cx + (u[0] * s) * c - (u[1] * s) * sn, cy + (u[0] * s) * sn + (u[1] * s) * c);
    const [a2, b2] = tf(cx + (v[0] * s) * c - (v[1] * s) * sn, cy + (v[0] * s) * sn + (v[1] * s) * c);
    drawPath(ctx, [P(a1, b1, 0), P(a2, b2, 0)], { stroke: INK, sw: 1.3, strokeAlpha: 0.5 });
  }
}

function drawBug(ctx, tf, cx = 99, cy = 187) {
  const [bx, by] = tf(cx, cy);
  // shell + head
  drawEllipse(ctx, bx, by, 4.0, 2.7, 0.12, { fill: BUG, sw: 0 });
  drawEllipse(ctx, bx + 3.6, by - 0.9, 2.0, 1.8, 0, { fill: BUG, sw: 0 });
  // four short legs and two short antennae
  const legs = [
    [[bx - 1.5, by + 2.1], [bx - 3.4, by + 3.6]],
    [[bx + 1.6, by + 2.1], [bx + 2.4, by + 3.7]],
    [[bx - 2.4, by + 1.0], [bx - 4.4, by + 1.8]],
    [[bx + 2.8, by + 0.9], [bx + 4.8, by + 1.5]],
  ];
  for (const [a, b] of legs) {
    drawPath(ctx, [P(a[0], a[1], 0), P(b[0], b[1], 0)], { stroke: BUG, sw: 1.0, strokeAlpha: 0.85 });
  }
  drawPath(ctx, [P(bx + 4.4, by - 2.0, 0), P(bx + 6.2, by - 3.6, 0)], { stroke: BUG, sw: 1.0, strokeAlpha: 0.85 });
  drawPath(ctx, [P(bx + 3.4, by - 2.3, 0), P(bx + 3.6, by - 4.4, 0)], { stroke: BUG, sw: 1.0, strokeAlpha: 0.85 });
}

function sparkle(ctx, x, y, s, alpha) {
  const arms = [
    [0, -1, 0, 1],
    [-1, 0, 1, 0],
    [-0.6, -0.6, 0.6, 0.6],
    [-0.6, 0.6, 0.6, -0.6],
  ];
  for (const [x0, y0, x1, y1] of arms) {
    drawPath(ctx, [P(x + x0 * s, y + y0 * s, 0), P(x + x1 * s, y + y1 * s, 0)], {
      stroke: INK,
      sw: 1.8,
      strokeAlpha: alpha,
    });
  }
}

function puff(ctx, x, y, r, alpha) {
  drawEllipse(ctx, x - r * 0.8, y, r * 0.75, r * 0.7, 0, { stroke: INK, sw: 1.6, alpha });
  drawEllipse(ctx, x + r * 0.5, y + r * 0.3, r * 0.6, r * 0.55, 0, { stroke: INK, sw: 1.6, alpha });
  drawEllipse(ctx, x, y - r * 0.7, r * 0.55, r * 0.5, 0, { stroke: INK, sw: 1.6, alpha });
}

/* ------------------------------------------------------------------ frames --- */

function drawCell(ctx, pose, tfIn) {
  const tf = tfIn || makeTf(pose);
  // ground props belong to the floor, not to the body: they must not bob
  const idt = (x, y) => [x, y];
  if (pose.ground) drawGroundLine(ctx, pose.groundAlpha ?? 0.5);
  drawLegs(ctx, tf, pose);
  drawBody(ctx, tf, pose);
  const props = pose.props || {};
  if (props.banana) drawBanana(ctx, idt, pose.bananaDX || 0, pose.bananaDY || 0);
  if (props.paper) drawPaper(ctx, idt, 78, 184, 0.85, -0.12);
  if (props.bug) drawBug(ctx, idt, 99, 186);
  if (props.sheet) drawPaper(ctx, idt, 128, 173, 1.1, 0.12);
  drawArms(ctx, tf, pose);
  drawHat(ctx, tf, pose, pose.mirrored ? false : true);
  if (pose.scratches) {
    for (const [x, y, len, a] of pose.scratches) {
      const [a1, b1] = tf(x, y);
      const [a2, b2] = tf(x + len, y - 2);
      drawPath(ctx, [P(a1, b1, 0), P(a2, b2, 0)], { stroke: INK, sw: 1.4, strokeAlpha: a });
    }
  }
  if (pose.puffs) {
    for (const [x, y, r, a] of pose.puffs) puff(ctx, x, y, r, a);
  }
  if (pose.sparkle) sparkle(ctx, pose.sparkle[0], pose.sparkle[1], pose.sparkle[2], pose.sparkle[3]);
}

const POSE_IDLE = (t) => {
  const p = (t / 6) * TAU;
  const breathe = Math.sin(p);
  // feet stay planted: the body breathes by scaling, the hat bobs on its own
  return {
    bob: 0,
    sy: 1 + 0.013 * breathe,
    lean: 0.009 * Math.sin(p + 0.7),
    hatDY: -1.7 * breathe + (t === 3 ? 1.1 : 0),
    hatTilt: 0.03 * Math.sin(p + 1.1),
    ground: true,
    props: { banana: true, paper: true, bug: true },
  };
};

const POSE_RUN = (t) => {
  const p = (t / 8) * TAU;
  const liftL = Math.max(0, Math.sin(p));
  const liftR = Math.max(0, Math.sin(p + Math.PI));
  return {
    lean: 0.13 + 0.022 * Math.sin(p * 2),
    bob: -2.6 - 2.3 * Math.sin(p * 2),
    hatDY: -1.6 * Math.sin(p * 2 + 0.6),
    hatTilt: 0.055 + 0.03 * Math.sin(p * 2),
    footL: { x: 52 + 9 * Math.sin(p), y: 171 - 10 * liftL, rot: -0.34 - 0.25 * liftL },
    footR: { x: 140 + 9 * Math.sin(p + Math.PI), y: 171 - 10 * liftR, rot: 0.34 + 0.25 * liftR },
    handL: { x: 56 - 8 * Math.sin(p), y: 160 - 6 * Math.abs(Math.sin(p)) },
    handR: { x: 136 + 8 * Math.sin(p + Math.PI), y: 160 - 6 * Math.abs(Math.sin(p + Math.PI)) },
    ground: true,
    props: {},
  };
};

const POSE_WAVE = (t) => {
  const p = (t / 4) * TAU;
  const sw = Math.sin(p);
  return {
    bob: -0.8 - 0.9 * Math.abs(sw),
    lean: -0.03,
    hatTilt: -0.05 + 0.05 * sw,
    hatDY: -1,
    handR: { x: 150 + 10 * sw, y: 98 + 7 * sw },
    handL: { x: 55, y: 172 },
    ground: true,
    props: { banana: true, paper: true, bug: true },
  };
};

const POSE_JUMP = (t) => {
  const f = [
    { bob: 0, footY: 169, spread: 3, hatDY: 3.5, sy: 0.9, ground: true },
    { bob: -9, footY: 168, spread: 0, hatDY: -1.5, sy: 1.04, ground: false },
    { bob: -18, footY: 162, spread: -5, hatDY: -3, sy: 1.02, ground: false },
    { bob: -8, footY: 167, spread: 1, hatDY: 0.5, sy: 1.0, ground: false },
    { bob: 0, footY: 169, spread: 3, hatDY: 3.5, sy: 0.91, ground: true },
  ][t];
  return {
    bob: f.bob,
    sy: f.sy,
    lean: 0.02,
    hatDY: f.hatDY,
    hatTilt: 0.02 + 0.02 * t,
    footL: { x: 44 - f.spread, y: f.footY, rot: -0.34 },
    footR: { x: 148 + f.spread, y: f.footY, rot: 0.34 },
    handL: { x: 56, y: 164 + (f.bob > 0 ? 3 : -6) },
    handR: { x: 140, y: 164 + (f.bob > 0 ? 3 : -6) },
    ground: f.ground,
    props: {},
  };
};

const POSE_FAIL = (t) => {
  const sag = [0, 1.6, 3.2, 4.4, 4.8, 4.8, 3.4, 1.8][t];
  const shiver = t === 4 || t === 5 ? (t === 4 ? 0.6 : -0.6) : 0;
  return {
    // the feet stay planted; the body compresses and the hat slides down
    bob: 0,
    sy: 1 - 0.03 * (sag / 4.8),
    lean: -0.02 + shiver * 0.01,
    hatDY: sag * 1.7,
    hatTilt: -0.02 - sag * 0.006,
    footL: { x: 44, y: 169, rot: -0.30 },
    footR: { x: 148, y: 169, rot: 0.30 },
    handL: { x: 55, y: 172 },
    handR: { x: 139, y: 172 },
    ground: true,
    props: { banana: true, paper: true, bug: true },
    puffs: t >= 1 && t <= 5 ? [[70, 30 - t * 1.5, 5.2 - t * 0.5, 0.55 - t * 0.07]] : null,
  };
};

const POSE_WAIT = (t) => {
  const p = (t / 6) * TAU;
  const tap = Math.max(0, Math.sin(p * 2));
  return {
    bob: 0,
    sy: 1 + 0.006 * Math.sin(p),
    lean: 0.026 * Math.sin(p),
    hatTilt: 0.045 * Math.sin(p + 0.4),
    hatDY: -0.6 - 0.6 * Math.sin(p),
    footR: { x: 148, y: 169 - 3.4 * tap, rot: 0.34 + 0.18 * tap },
    ground: true,
    props: { banana: true, paper: true, bug: true },
  };
};

const POSE_WORK = (t) => {
  const p = (t / 6) * TAU;
  return {
    lean: 0.045 + 0.012 * Math.sin(p),
    bob: 0,
    sy: 1 - 0.004 * Math.sin(p * 2),
    hatDY: 1.0 + 0.6 * Math.sin(p * 2),
    hatTilt: 0.05 + 0.02 * Math.sin(p),
    handR: { x: 126 + 7 * Math.cos(p * 2), y: 172 + 4.5 * Math.sin(p * 2) },
    handL: { x: 74, y: 172 },
    ground: true,
    props: { sheet: true },
    scratches: [
      [116 + 4 * Math.cos(p * 2), 172, 5.5 * (0.6 + 0.4 * Math.sin(p * 2)), 0.45],
      [121 + 3 * Math.cos(p * 2 + 1), 168 - 2 * Math.sin(p * 2), 4, 0.3],
    ],
  };
};

const POSE_REVIEW = (t) => {
  const p = (t / 6) * TAU;
  const up = 0.5 + 0.5 * Math.sin(p);
  return {
    lean: -0.035 - 0.012 * Math.sin(p),
    bob: -1.2 * Math.sin(p),
    hatTilt: -0.06 - 0.03 * Math.sin(p),
    hatDY: -1.2 - 0.8 * up,
    handR: { x: 138 + 6 * up, y: 146 - 26 * up },
    handL: { x: 56, y: 152 },
    ground: true,
    props: { banana: true, paper: true, bug: true },
    sparkle: [156, 62, 4.5 + 3.2 * up, 0.55 + 0.35 * up],
  };
};

const POSE_LOOK = (i) => {
  const a = (i * 22.5 * Math.PI) / 180; // 0 = up, clockwise
  const dx = Math.sin(a);
  const dy = -Math.cos(a);
  // the face is hidden under the hat, so direction is read from the whole
  // silhouette: the body leans, the hat slides and skews, and looking up lifts
  // the hat off the head while looking down pulls it over the body.
  return {
    bob: 3.0 * dy,
    sy: 1 + 0.1 * dy,
    lean: 0.17 * dx,
    hatDX: 5.0 * dx,
    hatDY: 16.0 * dy,
    hatTilt: 0.3 * dx,
    footL: { x: 44 + 2 * dx, y: 169, rot: -0.34 },
    footR: { x: 148 + 2 * dx, y: 169, rot: 0.34 },
    handL: { x: 62 + 4 * dx, y: 171 + 3 * dy },
    handR: { x: 130 + 4 * dx - 6 * dy, y: 171 + 3 * dy },
    ground: true,
    props: {},
  };
};

/* ------------------------------------------------------------------- atlas --- */

const TRACKS = [
  { name: 'idle', frames: 6, pose: POSE_IDLE },
  { name: 'running-right', frames: 8, pose: POSE_RUN },
  { name: 'running-left', frames: 8, pose: POSE_RUN, mirror: true },
  { name: 'waving', frames: 4, pose: POSE_WAVE },
  { name: 'jumping', frames: 5, pose: POSE_JUMP },
  { name: 'failed', frames: 8, pose: POSE_FAIL },
  { name: 'waiting', frames: 6, pose: POSE_WAIT },
  { name: 'running', frames: 6, pose: POSE_WORK },
  { name: 'review', frames: 6, pose: POSE_REVIEW },
];

const atlas = new Canvas(AW, AH);

function blit(dst, src, ox, oy, flip) {
  for (let y = 0; y < src.h; y++) {
    for (let x = 0; x < src.w; x++) {
      const a = src.a[y * src.w + x];
      if (a <= 0.0009) continue;
      const sx = flip ? src.w - 1 - x : x;
      const i = (oy + y) * dst.w + (ox + sx);
      const col = [src.r[y * src.w + x], src.g[y * src.w + x], src.b[y * src.w + x]];
      const da = dst.a[i];
      const oa = a + da * (1 - a);
      const k = (da * (1 - a)) / oa;
      const s = a / oa;
      dst.r[i] = col[0] * s + dst.r[i] * k;
      dst.g[i] = col[1] * s + dst.g[i] * k;
      dst.b[i] = col[2] * s + dst.b[i] * k;
      dst.a[i] = oa;
    }
  }
}

const report = [];
const keep = new Map();

function stash(row, col, cell) {
  keep.set(`${row}:${col}`, cell);
}

TRACKS.forEach((track, row) => {
  for (let col = 0; col < track.frames; col++) {
    const pose = track.pose(col);
    const cell = new Canvas(CW, CH);
    const baseTf = makeTf(pose);
    let tf = baseTf;
    if (track.mirror) {
      // reflect the drawing in cell space; the hat lettering is told separately
      pose.mirrored = true;
      tf = (x, y) => {
        const [a, b] = baseTf(x, y);
        return [192 - a, b];
      };
    }
    drawCell(cell, pose, tf);
    if (track.mirror) {
      // draw "LIFE" upright on the mirrored hat: mirroring a rotation flips its sign
      const textPose = {
        ...pose,
        mirrored: false,
        lean: -(pose.lean || 0),
        hatTilt: -(pose.hatTilt || 0),
        hatDX: -(pose.hatDX || 0),
      };
      drawHatLetters(cell, makeHatTf(makeTf(textPose), textPose));
    }
    blit(atlas, cell, col * CW, row * CH, false);
    stash(row, col, cell);
    report.push(`${track.name}[${col}]`);
  }
});

// rows 9 + 10: sixteen look directions, 0 = up, clockwise in 22.5 deg steps
for (let i = 0; i < 16; i++) {
  const row = 9 + Math.floor(i / 8);
  const col = i % 8;
  const cell = new Canvas(CW, CH);
  drawCell(cell, POSE_LOOK(i));
  blit(atlas, cell, col * CW, row * CH, false);
  stash(row, col, cell);
  report.push(`look[${i}]`);
}

/* --------------------------------------------------------------------- png --- */

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const t = Buffer.from(type, 'ascii');
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([t, data])), 0);
  return Buffer.concat([len, t, data, crc]);
}

function encodePNG(canvas) {
  const { w, h } = canvas;
  const stride = w * 4 + 1;
  const raw = Buffer.alloc(stride * h);
  for (let y = 0; y < h; y++) {
    const o = y * stride;
    raw[o] = 0;
    for (let x = 0; x < w; x++) {
      const i = y * w + x;
      const a = canvas.a[i];
      const p = o + 1 + x * 4;
      if (a <= 0.0009) {
        raw[p] = 0; raw[p + 1] = 0; raw[p + 2] = 0; raw[p + 3] = 0;
        continue;
      }
      raw[p] = Math.round(clamp01(canvas.r[i] / 255) * 255);
      raw[p + 1] = Math.round(clamp01(canvas.g[i] / 255) * 255);
      raw[p + 2] = Math.round(clamp01(canvas.b[i] / 255) * 255);
      raw[p + 3] = Math.round(clamp01(a) * 255);
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;
  const idat = deflateSync(raw, { level: 9 });
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', idat),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, 'life-hat-pet');
const inspectDir = join(here, '_inspect');
mkdirSync(outDir, { recursive: true });
mkdirSync(inspectDir, { recursive: true });

const png = encodePNG(atlas);
writeFileSync(join(outDir, 'spritesheet.png'), png);

// inspection sheets (preview only, not part of the pet package contract)
{
  const sheet = (keys, cols, S, file) => {
    const rows = Math.ceil(keys.length / cols);
    const c = new Canvas(CW * S * cols, CH * S * rows);
    keys.forEach((key, idx) => {
      const cell = keep.get(key);
      if (!cell) return;
      const ox = (idx % cols) * CW * S;
      const oy = Math.floor(idx / cols) * CH * S;
      for (let y = 0; y < CH * S; y++) {
        for (let x = 0; x < CW * S; x++) {
          const i = Math.floor(y / S) * CW + Math.floor(x / S);
          const a = cell.a[i];
          if (a <= 0.0009) continue;
          c.over((oy + y) * c.w + (ox + x), [cell.r[i], cell.g[i], cell.b[i]], a);
        }
      }
    });
    writeFileSync(join(inspectDir, file), encodePNG(c));
  };

  sheet(
    [
      '0:0', '0:3', '1:0', '1:4', '3:1', '4:0', '4:2', '4:4',
      '5:3', '6:2', '7:2', '8:3', '9:0', '9:4', '10:0', '10:4',
    ],
    4,
    2,
    'preview.png',
  );
  sheet(['1:0', '2:0'], 1, 4, 'zoom.png');
  sheet(
    Array.from({ length: 16 }, (_, i) => `${9 + Math.floor(i / 8)}:${i % 8}`),
    4,
    2,
    'looks.png',
  );
  sheet(
    [
      ...Array.from({ length: 6 }, (_, c) => `0:${c}`),
      ...Array.from({ length: 8 }, (_, c) => `1:${c}`),
    ],
    8,
    2,
    'strip.png',
  );

  const c0 = keep.get('0:0');
  let white = 0;
  for (let y = 36; y < 68; y++) {
    for (let x = 62; x < 130; x++) {
      const i = y * CW + x;
      if (c0.a[i] > 0.5 && c0.r[i] > 210 && c0.g[i] > 210 && c0.b[i] > 210) white++;
    }
  }
  console.log(`LIFE letter pixels inside crown: ${white}`);

  // letter-shape check: white pixel histogram across the crown, per row.
  // A mirrored cell would show this histogram reversed.
  const hist = (c) => {
    const h = new Array(8).fill(0);
    for (let y = 0; y < CH; y++) {
      for (let x = 62; x < 130; x++) {
        const i = y * CW + x;
        if (c.a[i] > 0.5 && c.r[i] > 210 && c.g[i] > 210 && c.b[i] > 210) {
          h[Math.min(7, Math.floor(((x - 62) / 68) * 8))]++;
        }
      }
    }
    return h;
  };
  const base = hist(keep.get('0:0'));
  const norm = (h) => {
    const s = h.reduce((a, b) => a + b, 0) || 1;
    return h.map((v) => v / s);
  };
  const nb = norm(base);
  for (let row = 0; row < 9; row++) {
    const c = keep.get(`${row}:0`);
    if (!c) continue;
    const h = norm(hist(c));
    const fwd = h.reduce((a, v, i) => a + Math.abs(v - nb[i]), 0);
    const rev = h.reduce((a, v, i) => a + Math.abs(v - nb[7 - i]), 0);
    console.log(
      `row ${row} letters: L1-vs-idle=${fwd.toFixed(3)} vs-mirrored=${rev.toFixed(3)} ` +
        `${fwd < rev ? 'upright' : 'MIRRORED?'}`,
    );
  }
}

// numeric self-check: motion per track and content bbox per track
{
  const keysByRow = new Map();
  for (const key of keep.keys()) {
    const [r, c] = key.split(':').map(Number);
    if (!keysByRow.has(r)) keysByRow.set(r, []);
    keysByRow.get(r).push([c, key]);
  }
  for (const [row, list] of [...keysByRow.entries()].sort((a, b) => a[0] - b[0])) {
    list.sort((a, b) => a[0] - b[0]);
    const cells = list.map(([, k]) => keep.get(k));
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    for (const c of cells) {
      for (let y = 0; y < CH; y++) {
        for (let x = 0; x < CW; x++) {
          if (c.a[y * CW + x] > 0.03) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }
    }
    let motion = 0;
    for (let i = 0; i < cells.length; i++) {
      const a = cells[i];
      const b = cells[(i + 1) % cells.length];
      let diff = 0;
      let n = 0;
      for (let p = 0; p < CW * CH; p++) {
        if (a.a[p] > 0.03 || b.a[p] > 0.03) {
          diff += Math.abs(a.a[p] - b.a[p]) + Math.abs(a.r[p] - b.r[p]) / 255 + Math.abs(a.g[p] - b.g[p]) / 255;
          n++;
        }
      }
      motion += n ? diff / n : 0;
    }
    console.log(
      `row ${row}: frames=${cells.length} bbox=[${minX},${minY}..${maxX},${maxY}] ` +
        `meanStepDiff=${(motion / cells.length).toFixed(3)}`,
    );
  }
}

const pet = {
  id: 'life-hat-pet',
  displayName: 'LIFE 帽子小人',
  description:
    '手绘墨线小人：被写有 LIFE 的黑礼帽罩住，背对观众坐在地上，摊开的腿露出深色鞋底，身边是一瓣黄香蕉皮、一团皱纸和一只小虫。',
  spritesheetPath: 'spritesheet.png',
  spriteVersionNumber: 2,
};
writeFileSync(join(outDir, 'pet.json'), JSON.stringify(pet, null, 2) + '\n');

console.log(`cells drawn: ${report.length}`);
console.log(`atlas: ${AW}x${AH}  png bytes: ${png.length} (${(png.length / 1024 / 1024).toFixed(2)} MiB)`);
console.log(`out: ${outDir}`);
