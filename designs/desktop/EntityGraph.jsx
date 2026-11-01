// Relations view — entity-relationship graph as the novel editor's main content.
// Chrome (WindowFrame + NavRail) is reused from the kit; the graph, force layout,
// navigator column, toolbar and inspector are this file. Data: entity_graph_data.js.
// Layout is a JS port of lib/shared/entity_graph/layout.dart (radial BFS init +
// force relaxation, fixed center).

const D = window.EG_DATA;

// ---- index data ------------------------------------------------------------
const NODE_BY_KEY = {};
const NODE_BY_ID = {};
D.nodes.forEach((n) => {
  n.key = `${n.type}_${n.id}`;
  NODE_BY_KEY[n.key] = n;
  NODE_BY_ID[n.id] = n;
});
const ALL_EDGES = D.edges.map((e, i) => {
  const src = NODE_BY_ID[e.s];
  const tgt = NODE_BY_ID[e.t];
  const meta = D.relations[e.type] || { zh: e.type, cat: "other" };
  return {
    id: `e${i}`,
    sourceKey: src.key,
    targetKey: tgt.key,
    type: e.type,
    label: meta.zh,
    cat: meta.cat,
    directed: !!meta.directed,
    color: D.relCatColor[meta.cat] || D.relCatColor.other,
  };
});

const ENTITY_ORDER = ["character", "faction", "skill", "item", "location", "creature"];
const TYPE_COUNTS = {};
ENTITY_ORDER.forEach((t) => (TYPE_COUNTS[t] = 0));
D.nodes.forEach((n) => TYPE_COUNTS[n.type]++);
const initials = (name) => Array.from(name).slice(0, 2).join("");
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));

// adjacency over all edges — reused for the center node's "间接关系" BFS.
const ADJ = {};
ALL_EDGES.forEach((e) => {
  (ADJ[e.sourceKey] = ADJ[e.sourceKey] || new Set()).add(e.targetKey);
  (ADJ[e.targetKey] = ADJ[e.targetKey] || new Set()).add(e.sourceKey);
});

// direct = immediate neighbours; indirect = distinct nodes two hops out.
function egCenterStats(centerKey) {
  const dist1 = ADJ[centerKey];
  if (!dist1) return { direct: 0, indirect: 0 };
  const at2 = new Set();
  dist1.forEach((nb) =>
    (ADJ[nb] || []).forEach((nn) => {
      if (nn !== centerKey && !dist1.has(nn)) at2.add(nn);
    })
  );
  return { direct: dist1.size, indirect: at2.size };
}

// relation category → zh label. Single source for both the legend and the
// left-rail relation-overview donut.
const CAT_LABELS = {
  kin: "亲族", bond: "盟友 / 同门", lover: "情缘", enemy: "敌对",
  master: "师承", faction: "门派归属", item: "持有", skill: "功法",
  alter: "化身", evolve: "演化", other: "其他",
};

// ---- derived relation metadata --------------------------------------------
// entity_graph_data.js carries no chapter / evidence / strength fields. We
// derive stable mock story-bible metadata from each edge id (FNV-1a hash) so the
// inspector reads like a real relation record without touching the data file.
// Deterministic by design — no Math.random / Date.now.
function egHash(str) {
  let h = 2166136261;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

const REL_STATUS = {
  kin: ["血脉相连", "保持联系", "已然疏远"],
  bond: ["生死相托", "并肩同行", "渐生嫌隙"],
  lover: ["情根深种", "藕断丝连", "缘尽于此"],
  enemy: ["不死不休", "敌对正酣", "暂避锋芒"],
  master: ["师承延续", "衣钵相授", "已逐出师门"],
  faction: ["效忠如初", "门规所系", "貌合神离"],
  item: ["随身不离", "暂借在手", "已然遗失"],
  skill: ["勤修不辍", "已窥门径", "搁置未练"],
  alter: ["真身未露", "另有其面"],
  evolve: ["一脉相承", "由此演化"],
  other: ["维持现状"],
};
const EVIDENCE_LABELS = [
  "家族宴会对话", "遗产分配记录", "私人信件往来", "夜袭幸存口供",
  "藏经阁残卷", "临安坊间传闻", "天枢阁密档", "剑冢碑文",
  "幽冥渊见闻", "知府案牍记录",
];

const _relMetaCache = {};
function relMeta(edge) {
  if (_relMetaCache[edge.id]) return _relMetaCache[edge.id];
  const h = egHash(edge.id);
  const src = NODE_BY_KEY[edge.sourceKey];
  const tgt = NODE_BY_KEY[edge.targetKey];
  const chapter = (h % D.novel.chapters) + 1;
  const evidence = (h % 11) + 2; // 2..12
  const strength = 55 + ((h >>> 3) % 45); // 55..99
  const important =
    edge.cat === "kin" || edge.cat === "lover" || edge.cat === "master" || (h & 8) !== 0;
  const statuses = REL_STATUS[edge.cat] || REL_STATUS.other;
  const status = statuses[h % statuses.length];
  const descTail = (tgt.desc || "").split(/[。;,，]/)[0];
  const desc = `${src.name} 与 ${tgt.name} 因「${edge.label}」相系。${descTail}。`;
  const nSrc = 2 + (h % 2); // 2..3
  const sources = [];
  for (let i = 0; i < nSrc; i++) {
    const hi = egHash(edge.id + ":" + i);
    sources.push({
      chapter: (hi % D.novel.chapters) + 1,
      label: EVIDENCE_LABELS[hi % EVIDENCE_LABELS.length],
    });
  }
  sources.sort((a, b) => a.chapter - b.chapter);
  const meta = { chapter, evidence, strength, important, status, desc, sources };
  _relMetaCache[edge.id] = meta;
  return meta;
}

// ===========================================================================
// Force-directed radial layout (port of computeEntityGraphLayout)
// ===========================================================================
const SPACING = 150;
const MIN_DIST = 150;

function egMulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function egComputeLayout(nodes, edges, centerKey, seed = 42) {
  if (nodes.length === 0) return {};
  if (nodes.length === 1) return { [nodes[0].key]: { x: 0, y: 0 } };

  const adj = {};
  edges.forEach((e) => {
    (adj[e.sourceKey] = adj[e.sourceKey] || new Set()).add(e.targetKey);
    (adj[e.targetKey] = adj[e.targetKey] || new Set()).add(e.sourceKey);
  });

  const rng = egMulberry32(seed);
  const pos = {};

  // radial BFS init
  const hasCenter = centerKey && nodes.some((n) => n.key === centerKey);
  if (hasCenter) {
    pos[centerKey] = { x: 0, y: 0 };
    const depths = { [centerKey]: 0 };
    const q = [centerKey];
    while (q.length) {
      const k = q.shift();
      (adj[k] || []).forEach((nb) => {
        if (depths[nb] === undefined) { depths[nb] = depths[k] + 1; q.push(nb); }
      });
    }
    const maxD = Object.values(depths).reduce((a, b) => Math.max(a, b), 0);
    const byDepth = {};
    nodes.forEach((n) => {
      const d = depths[n.key] !== undefined ? depths[n.key] : maxD + 1;
      (byDepth[d] = byDepth[d] || []).push(n.key);
    });
    Object.keys(byDepth).forEach((dStr) => {
      const d = +dStr;
      if (d === 0) return;
      const keys = byDepth[d].slice().sort();
      const radius = SPACING * d * 1.05;
      keys.forEach((key, i) => {
        const angle = (2 * Math.PI * i) / keys.length - Math.PI / 2;
        pos[key] = { x: Math.cos(angle) * radius, y: Math.sin(angle) * radius };
      });
    });
  }
  nodes.forEach((n) => {
    if (!pos[n.key]) {
      pos[n.key] = {
        x: (rng() - 0.5) * SPACING * 2,
        y: (rng() - 0.5) * SPACING * 2,
      };
    }
  });

  const area = nodes.length * SPACING * SPACING;
  const k = Math.sqrt(area / nodes.length);
  const pairs = {};
  edges.forEach((e) => {
    const pk = e.sourceKey < e.targetKey ? `${e.sourceKey}|${e.targetKey}` : `${e.targetKey}|${e.sourceKey}`;
    if (!pairs[pk]) pairs[pk] = [e.sourceKey, e.targetKey];
  });
  const uniquePairs = Object.values(pairs);
  const iterations = Math.min(300, 80 + nodes.length * 8);
  let temp = k * 2.5;
  const cooling = temp / iterations;

  for (let it = 0; it < iterations; it++) {
    const disp = {};
    nodes.forEach((n) => (disp[n.key] = { x: 0, y: 0 }));

    for (let a = 0; a < nodes.length; a++) {
      for (let b = a + 1; b < nodes.length; b++) {
        const ka = nodes[a].key, kb = nodes[b].key;
        let dx = pos[ka].x - pos[kb].x, dy = pos[ka].y - pos[kb].y;
        let dist = Math.hypot(dx, dy);
        if (dist < 0.01) {
          const ang = rng() * 2 * Math.PI;
          dx = Math.cos(ang); dy = Math.sin(ang); dist = 0.01;
        }
        let rep = (k * k) / dist;
        if (dist < MIN_DIST) { const o = MIN_DIST - dist; rep += o * o * 0.8; }
        const nx = dx / dist, ny = dy / dist;
        disp[ka].x += nx * rep; disp[ka].y += ny * rep;
        disp[kb].x -= nx * rep; disp[kb].y -= ny * rep;
      }
    }
    uniquePairs.forEach(([s, t]) => {
      let dx = pos[s].x - pos[t].x, dy = pos[s].y - pos[t].y;
      let dist = Math.hypot(dx, dy) || 0.01;
      const att = (dist * dist) / k;
      const nx = dx / dist, ny = dy / dist;
      disp[s].x -= nx * att; disp[s].y -= ny * att;
      disp[t].x += nx * att; disp[t].y += ny * att;
    });
    nodes.forEach((n) => {
      if (n.key === centerKey) return;
      const d = disp[n.key];
      const dist = Math.hypot(d.x, d.y);
      if (dist > 0) {
        const capped = Math.min(dist, temp);
        pos[n.key].x += (d.x / dist) * capped;
        pos[n.key].y += (d.y / dist) * capped;
      }
    });
    temp -= cooling;
    if (temp < 0.05) break;
  }

  // collision relax
  for (let iter = 0; iter < 60; iter++) {
    let moved = false;
    for (let a = 0; a < nodes.length; a++) {
      for (let b = a + 1; b < nodes.length; b++) {
        const ka = nodes[a].key, kb = nodes[b].key;
        let dx = pos[ka].x - pos[kb].x, dy = pos[ka].y - pos[kb].y;
        let dist = Math.hypot(dx, dy);
        if (dist >= MIN_DIST) continue;
        if (dist < 0.01) { const ang = rng() * 2 * Math.PI; dx = Math.cos(ang); dy = Math.sin(ang); dist = 0.01; }
        const push = (MIN_DIST - dist) / 2;
        const nx = dx / dist, ny = dy / dist;
        if (ka !== centerKey) { pos[ka].x += nx * push; pos[ka].y += ny * push; moved = true; }
        if (kb !== centerKey) { pos[kb].x -= nx * push; pos[kb].y -= ny * push; moved = true; }
      }
    }
    if (!moved) break;
  }
  return pos;
}

// ===========================================================================
// Graph data prep — filter by visible types + BFS depth (port of data.dart)
// ===========================================================================
function egPrepGraph(centerKey, visibleTypes, depth) {
  let edges = ALL_EDGES.filter((e) => {
    const st = NODE_BY_KEY[e.sourceKey].type;
    const tt = NODE_BY_KEY[e.targetKey].type;
    return visibleTypes.has(st) && visibleTypes.has(tt);
  });

  const centerInGraph =
    centerKey &&
    edges.some((e) => e.sourceKey === centerKey || e.targetKey === centerKey);

  if (centerInGraph) {
    const visited = new Set([centerKey]);
    let frontier = new Set([centerKey]);
    const kept = [];
    const keptIds = new Set();
    for (let d = 0; d < depth; d++) {
      const next = new Set();
      edges.forEach((e) => {
        if (frontier.has(e.sourceKey) || frontier.has(e.targetKey)) {
          if (!keptIds.has(e.id)) { kept.push(e); keptIds.add(e.id); }
          [e.sourceKey, e.targetKey].forEach((kk) => {
            if (!visited.has(kk)) { visited.add(kk); next.add(kk); }
          });
        }
      });
      if (next.size === 0) break;
      frontier = next;
    }
    edges = kept;
  }

  const keys = new Set();
  edges.forEach((e) => { keys.add(e.sourceKey); keys.add(e.targetKey); });
  if (centerKey && NODE_BY_KEY[centerKey]) keys.add(centerKey);
  const nodes = Array.from(keys).map((kk) => NODE_BY_KEY[kk]);

  // parallel-edge offsets for curvature
  const groups = {};
  edges.forEach((e) => {
    const pk = e.sourceKey < e.targetKey ? `${e.sourceKey}|${e.targetKey}` : `${e.targetKey}|${e.sourceKey}`;
    (groups[pk] = groups[pk] || []).push(e);
  });
  Object.values(groups).forEach((g) => {
    g.forEach((e, i) => { e.curveIdx = i - (g.length - 1) / 2; });
  });

  const positions = egComputeLayout(nodes, edges, centerKey);
  return { nodes, edges, positions };
}

// ===========================================================================
// Presentational bits
// ===========================================================================
const NODE_R = 30; // ring radius for edge trimming

function EgNodeAvatar({ node, size }) {
  const et = D.entityTypes[node.type];
  const isChar = node.type === "character";
  return (
    <span
      className="eg-node__ring"
      style={{ width: size, height: size, borderColor: et.color }}
    >
      {isChar ? (
        <span className="eg-node__initials" style={{ color: et.color }}>
          {initials(node.name)}
        </span>
      ) : (
        <Icon name={et.icon} size={Math.round(size * 0.42)} color={et.color} />
      )}
    </span>
  );
}

function EgTypeBadge({ type }) {
  const et = D.entityTypes[type];
  return (
    <span className="eg-badge" style={{ "--c": et.color }}>
      <span className="eg-badge__dot" />
      {et.zh}
    </span>
  );
}

// Toolbar dropdown — button + popover menu. Open state is owned by the parent so
// only one menu shows at a time; a full-bleed scrim (rendered by the parent)
// closes it on outside click.
function EgDropdown({ label, icon, summary, open, onToggle, width, children }) {
  return (
    <div className="eg-dd">
      <button className={"eg-ddbtn" + (open ? " is-open" : "")} onClick={onToggle}>
        {icon && <Icon name={icon} size={13} />}
        <span>{label}</span>
        {summary != null && <span className="eg-ddbtn__sum">{summary}</span>}
        <Icon name="caret-down" size={11} color="var(--text-subtle)" />
      </button>
      {open && (
        <div className="eg-menu" style={width ? { width } : null}>
          {children}
        </div>
      )}
    </div>
  );
}

// ===========================================================================
// Graph canvas
// ===========================================================================
function EgGraphCanvas({ graph, centerKey, hovered, setHovered, onCenter, onReset, showLabels }) {
  const viewportRef = React.useRef(null);
  const [view, setView] = React.useState({ zoom: 1, panX: 0, panY: 0 });
  const pan = React.useRef(null);

  const { nodes, edges, positions } = graph;

  // world geometry
  const PAD = 80;
  const geo = React.useMemo(() => {
    if (nodes.length === 0) return { w: 600, h: 400, minX: 0, minY: 0 };
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    nodes.forEach((n) => {
      const p = positions[n.key];
      minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x);
      minY = Math.min(minY, p.y); maxY = Math.max(maxY, p.y);
    });
    return { w: maxX - minX + PAD * 2, h: maxY - minY + PAD * 2, minX: minX - PAD, minY: minY - PAD };
  }, [nodes, positions]);

  const sx = (k) => positions[k].x - geo.minX;
  const sy = (k) => positions[k].y - geo.minY;

  const fit = React.useCallback(() => {
    const vp = viewportRef.current;
    if (!vp) return;
    const vw = vp.clientWidth, vh = vp.clientHeight;
    const z = clamp(Math.min(vw / geo.w, vh / geo.h) * 0.94, 0.42, 1.6);
    setView({ zoom: z, panX: (vw - geo.w * z) / 2, panY: (vh - geo.h * z) / 2 });
  }, [geo]);

  // refit when the focused graph changes
  React.useEffect(() => {
    const id = requestAnimationFrame(fit);
    return () => cancelAnimationFrame(id);
  }, [centerKey, geo.w, geo.h, fit]);

  function onWheel(e) {
    e.preventDefault();
    const rect = viewportRef.current.getBoundingClientRect();
    const mx = e.clientX - rect.left, my = e.clientY - rect.top;
    setView((v) => {
      const nz = clamp(v.zoom * (e.deltaY < 0 ? 1.12 : 1 / 1.12), 0.3, 2.6);
      const r = nz / v.zoom;
      return { zoom: nz, panX: mx - (mx - v.panX) * r, panY: my - (my - v.panY) * r };
    });
  }
  function onPointerDown(e) {
    if (e.button !== 0) return;
    pan.current = { x: e.clientX, y: e.clientY, px: view.panX, py: view.panY };
    viewportRef.current.setPointerCapture(e.pointerId);
  }
  function onPointerMove(e) {
    if (!pan.current) return;
    setView((v) => ({ ...v, panX: pan.current.px + (e.clientX - pan.current.x), panY: pan.current.py + (e.clientY - pan.current.y) }));
  }
  function onPointerUp() { pan.current = null; }
  const zoomBy = (f) =>
    setView((v) => {
      const vp = viewportRef.current, cx = vp.clientWidth / 2, cy = vp.clientHeight / 2;
      const nz = clamp(v.zoom * f, 0.3, 2.6), r = nz / v.zoom;
      return { zoom: nz, panX: cx - (cx - v.panX) * r, panY: cy - (cy - v.panY) * r };
    });

  // focus highlighting
  const focusKey = hovered || null;
  const connected = React.useMemo(() => {
    if (!focusKey) return null;
    const s = new Set([focusKey]);
    edges.forEach((e) => {
      if (e.sourceKey === focusKey) s.add(e.targetKey);
      if (e.targetKey === focusKey) s.add(e.sourceKey);
    });
    return s;
  }, [focusKey, edges]);

  const colors = Array.from(new Set(edges.map((e) => e.color)));

  return (
    <div className="eg-canvas">
      <div
        ref={viewportRef}
        className="eg-viewport"
        onWheel={onWheel}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerLeave={onPointerUp}
      >
        <div
          className="eg-world"
          style={{ transform: `translate(${view.panX}px, ${view.panY}px) scale(${view.zoom})` }}
        >
          <svg className="eg-edges" width={geo.w} height={geo.h} style={{ overflow: "visible" }}>
            <defs>
              {colors.map((c, i) => (
                <marker key={i} id={`eg-arrow-${i}`} viewBox="0 0 10 10" refX="8.5" refY="5"
                  markerWidth="7" markerHeight="7" orient="auto-start-reverse">
                  <path d="M1,1 L9,5 L1,9" fill="none" stroke={c} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
                </marker>
              ))}
            </defs>
            {edges.map((e) => {
              const x0 = sx(e.sourceKey), y0 = sy(e.sourceKey);
              const x1 = sx(e.targetKey), y1 = sy(e.targetKey);
              let dx = x1 - x0, dy = y1 - y0; const len = Math.hypot(dx, dy) || 1;
              const ux = dx / len, uy = dy / len;
              const ax = x0 + ux * NODE_R, ay = y0 + uy * NODE_R;
              const bx = x1 - ux * NODE_R, by = y1 - uy * NODE_R;
              const off = (e.curveIdx || 0) * 30;
              const cxp = (ax + bx) / 2 - uy * off;
              const cyp = (ay + by) / 2 + ux * off;
              const lx = 0.25 * ax + 0.5 * cxp + 0.25 * bx;
              const ly = 0.25 * ay + 0.5 * cyp + 0.25 * by;
              const dim = connected && !(connected.has(e.sourceKey) && connected.has(e.targetKey));
              const hot = connected && e.sourceKey === focusKey || e.targetKey === focusKey;
              const ci = colors.indexOf(e.color);
              return (
                <g key={e.id} style={{ opacity: dim ? 0.12 : 1, transition: "opacity .2s" }}>
                  <path
                    d={`M${ax},${ay} Q${cxp},${cyp} ${bx},${by}`}
                    fill="none" stroke={e.color}
                    strokeWidth={hot ? 2.4 : 1.6}
                    strokeOpacity={hot ? 0.95 : 0.6}
                    markerEnd={e.directed ? `url(#eg-arrow-${ci})` : undefined}
                  />
                  {showLabels && (
                    <g transform={`translate(${lx}, ${ly})`}>
                      <rect x={-(e.label.length * 6.6 + 8) / 2} y="-9" width={e.label.length * 6.6 + 8}
                        height="18" rx="9" fill="var(--surface)" stroke={e.color} strokeOpacity="0.4" />
                      <text x="0" y="4" textAnchor="middle" className="eg-edge-label" fill={e.color}>{e.label}</text>
                    </g>
                  )}
                </g>
              );
            })}
          </svg>

          {nodes.map((n) => {
            const isCenter = n.key === centerKey;
            const dim = connected && !connected.has(n.key);
            const size = isCenter ? 76 : 58;
            const stats = isCenter ? egCenterStats(n.key) : null;
            return (
              <div
                key={n.key}
                className={"eg-node" + (isCenter ? " is-center" : "") + (dim ? " is-dim" : "")}
                style={{ left: sx(n.key), top: sy(n.key) }}
                onMouseEnter={() => setHovered(n.key)}
                onMouseLeave={() => setHovered(null)}
                onClick={() => onCenter(n.key)}
              >
                <EgNodeAvatar node={n} size={size} />
                <div className="eg-node__labels" style={{ top: size / 2 + 7 }}>
                  <div className="eg-node__name" style={{ maxWidth: isCenter ? 132 : 100 }}>{n.name}</div>
                  <div className="eg-node__type">
                    {n.type === "character" ? D.characterRoles[n.role] : D.entityTypes[n.type].zh}
                  </div>
                  {isCenter && (
                    <div className="eg-node__stats">
                      <span className="eg-stat">直接 {stats.direct}</span>
                      <span className="eg-stat">间接 {stats.indirect}</span>
                    </div>
                  )}
                </div>
              </div>
            );
          })}
        </div>

        {/* hover card */}
        {hovered && NODE_BY_KEY[hovered] && (
          <EgHoverCard node={NODE_BY_KEY[hovered]} />
        )}
      </div>

      {/* reset view — re-center on the default node and refit zoom/pan */}
      <button className="eg-reset" title="重置视图" onClick={onReset}>
        <Icon name="arrow-clockwise" size={14} />
        <span>重置视图</span>
      </button>

      {/* zoom controls */}
      <div className="eg-zoom">
        <button className="eg-zoom__btn" title="放大" onClick={() => zoomBy(1.2)}><Icon name="plus" size={15} /></button>
        <button className="eg-zoom__btn" title="缩小" onClick={() => zoomBy(1 / 1.2)}><Icon name="x" size={13} style={{ transform: "rotate(45deg)" }} /></button>
        <button className="eg-zoom__btn" title="适应窗口" onClick={fit}><Icon name="arrows-out" size={15} /></button>
        <div className="eg-zoom__pct">{Math.round(view.zoom * 100)}%</div>
      </div>
    </div>
  );
}

function EgHoverCard({ node }) {
  const isChar = node.type === "character";
  return (
    <div className="eg-hovercard">
      <div className="eg-hovercard__head">
        <EgNodeAvatar node={node} size={40} />
        <div>
          <div className="eg-hovercard__name">{node.name}</div>
          <div className="eg-hovercard__en">{node.en}</div>
        </div>
      </div>
      <div className="eg-hovercard__meta">
        <EgTypeBadge type={node.type} />
        {isChar && <span className="eg-role">{D.characterRoles[node.role]}</span>}
      </div>
      <p className="eg-hovercard__desc">{node.desc}</p>
    </div>
  );
}

// ===========================================================================
// Left navigator column
// ===========================================================================
function EgNavigator({ railTypes, centerKey, onCenter, query, setQuery, toggleRailType, setAllRailTypes }) {
  const q = query.trim().toLowerCase();
  const allOn = ENTITY_ORDER.every((t) => railTypes.has(t));
  const grouped = ENTITY_ORDER
    .filter((t) => railTypes.has(t))
    .map((t) => ({
      type: t,
      items: D.nodes.filter(
        (n) => n.type === t && (!q || n.name.toLowerCase().includes(q) || (n.en || "").toLowerCase().includes(q))
      ),
    }))
    .filter((g) => g.items.length);

  return (
    <aside className="eg-rail">
      <div className="eg-rail__head">
        <Icon name="tree-structure" size={16} color="var(--accent)" />
        <div className="eg-rail__title">
          <div className="eg-rail__novel">《{D.novel.title}》关系图谱</div>
          <div className="eg-rail__sub">{D.nodes.length} 个实体 · {ALL_EDGES.length} 条关系</div>
        </div>
      </div>

      <div className="eg-search">
        <Icon name="magnifying-glass" size={14} color="var(--text-muted)" />
        <input
          className="eg-search__input"
          placeholder="搜索实体…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        {query && (
          <button className="eg-search__clear" onClick={() => setQuery("")}><Icon name="x" size={12} /></button>
        )}
      </div>

      <div className="eg-chips">
        <button className={"eg-chip eg-chip--all" + (allOn ? " is-on" : "")} onClick={setAllRailTypes}>
          全部<span className="eg-chip__n">{D.nodes.length}</span>
        </button>
        {ENTITY_ORDER.map((t) => (
          <button
            key={t}
            className={"eg-chip" + (railTypes.has(t) ? " is-on" : "")}
            style={{ "--c": D.entityTypes[t].color }}
            onClick={() => toggleRailType(t)}
          >
            <span className="eg-chip__dot" />
            {D.entityTypes[t].zh}
            <span className="eg-chip__n">{TYPE_COUNTS[t]}</span>
          </button>
        ))}
      </div>

      <div className="eg-rail__list">
        {grouped.map((g) => (
          <div key={g.type} className="eg-rail__group">
            <div className="eg-rail__group-label">{D.entityTypes[g.type].zh}</div>
            {g.items.map((n) => (
              <button
                key={n.key}
                className={"eg-rail__row" + (n.key === centerKey ? " is-active" : "")}
                onClick={() => onCenter(n.key)}
              >
                <span className="eg-rail__dot" style={{ background: D.entityTypes[n.type].color }} />
                <span className="eg-rail__row-name">{n.name}</span>
                {n.type === "character" && <span className="eg-rail__row-role">{D.characterRoles[n.role]}</span>}
              </button>
            ))}
          </div>
        ))}
        {grouped.length === 0 && <div className="eg-rail__empty">无匹配实体</div>}
      </div>

      <EgOverview />
    </aside>
  );
}

// Relation-overview donut — category shares across all edges. Pinned at the
// rail bottom; data-driven (not decorative), single CAT_LABELS source.
function EgOverview() {
  const segs = React.useMemo(() => {
    const counts = {};
    ALL_EDGES.forEach((e) => (counts[e.cat] = (counts[e.cat] || 0) + 1));
    const total = ALL_EDGES.length;
    const R = 26, C = 2 * Math.PI * R;
    let acc = 0;
    return Object.keys(counts)
      .map((c) => ({
        cat: c,
        label: CAT_LABELS[c] || c,
        n: counts[c],
        color: D.relCatColor[c] || D.relCatColor.other,
        pct: counts[c] / total,
      }))
      .sort((a, b) => b.n - a.n)
      .map((s) => {
        const len = s.pct * C;
        const seg = { ...s, R, dash: len, gap: C - len, offset: -acc };
        acc += len;
        return seg;
      });
  }, []);

  return (
    <div className="eg-overview">
      <div className="eg-overview__head">关系概览</div>
      <div className="eg-overview__body">
        <svg className="eg-donut" width="72" height="72" viewBox="0 0 72 72">
          {segs.map((s) => (
            <circle
              key={s.cat}
              cx="36" cy="36" r={s.R} fill="none"
              stroke={s.color} strokeWidth="10"
              strokeDasharray={`${s.dash} ${s.gap}`}
              strokeDashoffset={s.offset}
              transform="rotate(-90 36 36)"
            />
          ))}
          <text x="36" y="34" textAnchor="middle" className="eg-donut__num">{ALL_EDGES.length}</text>
          <text x="36" y="46" textAnchor="middle" className="eg-donut__lbl">关系</text>
        </svg>
        <div className="eg-ov-legend">
          {segs.slice(0, 6).map((s) => (
            <div key={s.cat} className="eg-ov-row">
              <span className="eg-ov-dot" style={{ background: s.color }} />
              <span className="eg-ov-label">{s.label}</span>
              <span className="eg-ov-pct">{Math.round(s.pct * 100)}%</span>
              <span className="eg-ov-n">{s.n}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ===========================================================================
// Right inspector
// ===========================================================================
function EgInspector({ centerKey, onCenter }) {
  const [tab, setTab] = React.useState("relations"); // 'relations' | 'details'
  const [selRelId, setSelRelId] = React.useState(null);

  const node = NODE_BY_KEY[centerKey];

  // relations touching this node, sorted by the other end's entity type.
  const rels = React.useMemo(() => {
    if (!node) return [];
    return ALL_EDGES.filter((e) => e.sourceKey === centerKey || e.targetKey === centerKey)
      .map((e) => {
        const otherKey = e.sourceKey === centerKey ? e.targetKey : e.sourceKey;
        return { ...e, other: NODE_BY_KEY[otherKey], outgoing: e.sourceKey === centerKey };
      })
      .sort((a, b) => ENTITY_ORDER.indexOf(a.other.type) - ENTITY_ORDER.indexOf(b.other.type));
  }, [centerKey, node]);

  // refocus → relations tab + first relation selected, so the card is populated.
  React.useEffect(() => {
    setTab("relations");
    setSelRelId(rels.length ? rels[0].id : null);
  }, [centerKey]);

  if (!node) return <aside className="eg-inspector" />;
  const isChar = node.type === "character";
  const selRel = rels.find((r) => r.id === selRelId) || null;

  // 实体详情 tab — derived profile stats for this node.
  const stats = egCenterStats(centerKey);
  const importantCount = rels.filter((r) => relMeta(r).important).length;
  const catRows = (() => {
    const counts = {};
    rels.forEach((r) => {
      const c = r.cat;
      (counts[c] = counts[c] || {
        cat: c,
        label: CAT_LABELS[c] || c,
        color: D.relCatColor[c] || D.relCatColor.other,
        n: 0,
      });
      counts[c].n++;
    });
    return Object.values(counts).sort((a, b) => b.n - a.n);
  })();

  return (
    <aside className="eg-inspector">
      <div className="eg-inspector__hero">
        <EgNodeAvatar node={node} size={48} />
        <div className="eg-inspector__herobody">
          <div className="eg-inspector__name">{node.name}</div>
          <div className="eg-inspector__en">{node.en}</div>
        </div>
        <div className="eg-inspector__tags">
          <EgTypeBadge type={node.type} />
          {isChar && <span className="eg-role">{D.characterRoles[node.role]}</span>}
        </div>
      </div>

      <div className="eg-tabs">
        <button className={"eg-tab" + (tab === "relations" ? " is-on" : "")} onClick={() => setTab("relations")}>
          关系管理
        </button>
        <button className={"eg-tab" + (tab === "details" ? " is-on" : "")} onClick={() => setTab("details")}>
          实体详情
        </button>
      </div>

      {tab === "relations" ? (
        <div className="eg-inspector__body">
          <div className="eg-inspector__subhead">
            <span>全部关系 <b>{rels.length}</b></span>
            <button className="eg-ddbtn eg-ddbtn--mini">
              <Icon name="funnel" size={12} />
              <span>筛选</span>
            </button>
          </div>

          <div className="eg-rels">
            {rels.map((r) => {
              const m = relMeta(r);
              return (
                <button
                  key={r.id}
                  className={"eg-rel" + (r.id === selRelId ? " is-sel" : "")}
                  onClick={() => setSelRelId(r.id)}
                >
                  <span className="eg-rel__dot" style={{ background: D.entityTypes[r.other.type].color }} />
                  <span className="eg-rel__main">
                    <span className="eg-rel__row1">
                      <span className="eg-rel__other-name">{r.other.name}</span>
                      <span className="eg-rel__label" style={{ color: r.color, borderColor: r.color }}>
                        {r.label}{r.directed && (r.outgoing ? " →" : " ←")}
                      </span>
                    </span>
                    <span className="eg-rel__meta">
                      建立于 第{m.chapter}章 · 证据 {m.evidence} 条
                      <span className={"eg-rel__imp" + (m.important ? " is-imp" : "")}>
                        {m.important ? "重要" : "一般"}
                      </span>
                    </span>
                  </span>
                </button>
              );
            })}
            {rels.length === 0 && <div className="eg-rail__empty">该实体暂无关系</div>}
          </div>

          {selRel && <EgRelDetail node={node} rel={selRel} onCenter={onCenter} />}
        </div>
      ) : (
        <div className="eg-inspector__body">
          <section className="eg-sec">
            <div className="eg-sec__head">简介</div>
            <p className="eg-sec__desc">{node.desc}</p>
          </section>

          <section className="eg-sec">
            <div className="eg-sec__head">基础属性</div>
            <div className="eg-kv">
              <div className="eg-kv__row"><span className="eg-kv__k">类型</span><span className="eg-kv__v">{D.entityTypes[node.type].zh}</span></div>
              {isChar && <div className="eg-kv__row"><span className="eg-kv__k">角色</span><span className="eg-kv__v">{D.characterRoles[node.role]}</span></div>}
              <div className="eg-kv__row"><span className="eg-kv__k">原文名</span><span className="eg-kv__v">{node.en}</span></div>
              <div className="eg-kv__row"><span className="eg-kv__k">关系数</span><span className="eg-kv__v">{rels.length}</span></div>
            </div>
          </section>

          <section className="eg-sec">
            <div className="eg-sec__head">关系概览</div>
            <div className="eg-statgrid">
              <div className="eg-statgrid__cell"><b>{stats.direct}</b><span>直接关系</span></div>
              <div className="eg-statgrid__cell"><b>{stats.indirect}</b><span>间接关系</span></div>
              <div className="eg-statgrid__cell"><b>{importantCount}</b><span>重要关系</span></div>
            </div>
            {catRows.length > 0 && (
              <div className="eg-sec__cats">
                {catRows.map((c) => (
                  <div key={c.cat} className="eg-ov-row">
                    <span className="eg-ov-dot" style={{ background: c.color }} />
                    <span className="eg-ov-label">{c.label}</span>
                    <span className="eg-ov-n">{c.n}</span>
                  </div>
                ))}
              </div>
            )}
          </section>
        </div>
      )}
    </aside>
  );
}

// Selected-relation detail card — strength meter, status, evidence sources.
function EgRelDetail({ node, rel, onCenter }) {
  const m = relMeta(rel);
  const filled = Math.round(m.strength / 10);
  return (
    <div className="eg-reldetail">
      <div className="eg-reldetail__head">
        <span className="eg-reldetail__pair">
          <span className="eg-reldetail__self">{node.name}</span>
          <Icon name="path" size={12} color="var(--text-subtle)" />
          <button className="eg-reldetail__other" onClick={() => onCenter(rel.other.key)}>
            {rel.other.name}
          </button>
        </span>
        <span className={"eg-rel__imp" + (m.important ? " is-imp" : "")}>
          {m.important ? "重要" : "一般"}
        </span>
      </div>

      <div className="eg-kv">
        <div className="eg-kv__row">
          <span className="eg-kv__k">关系类型</span>
          <span className="eg-rel__label" style={{ color: rel.color, borderColor: rel.color }}>{rel.label}</span>
        </div>
        <div className="eg-kv__row">
          <span className="eg-kv__k">强度</span>
          <span className="eg-meter">
            {Array.from({ length: 10 }, (_, i) => (
              <span
                key={i}
                className={"eg-meter__dot" + (i < filled ? " is-on" : "")}
                style={i < filled ? { background: rel.color } : null}
              />
            ))}
            <span className="eg-meter__pct">{m.strength}%</span>
          </span>
        </div>
        <div className="eg-kv__row"><span className="eg-kv__k">建立时间</span><span className="eg-kv__v">第{m.chapter}章</span></div>
        <div className="eg-kv__row"><span className="eg-kv__k">当前状态</span><span className="eg-kv__v">{m.status}</span></div>
      </div>

      <div className="eg-reldetail__desc">{m.desc}</div>

      <div className="eg-reldetail__evi-head">
        <span>证据来源</span>
        <span className="eg-inspector__count">{m.evidence} 条</span>
      </div>
      <div className="eg-evi">
        {m.sources.map((s, i) => (
          <div key={i} className="eg-evi__row">
            <span className="eg-evi__ch">第{s.chapter}章</span>
            <span className="eg-evi__label">{s.label}</span>
          </div>
        ))}
        <button className="eg-evi__more">查看全部</button>
      </div>
    </div>
  );
}

// ===========================================================================
// EntityGraphView — the three editor columns (navigator + canvas + inspector).
// Window frame + NavRail are owned by EditorView; this slots in as the editor's
// main content when the "实体关系图" nav item is active.
// ===========================================================================
function EntityGraphView() {
  const [centerKey, setCenterKey] = React.useState(D.defaultCenter);
  // Graph filter (toolbar 实体类型 dropdown) — drives which entity types render
  // on the canvas. Defaults to characters only.
  const [visibleTypes, setVisibleTypes] = React.useState(new Set(["character"]));
  // Rail filter (left 实体类型 chips) — drives only the navigator list. Kept
  // independent from the graph so the two panels can show different scopes.
  const [railTypes, setRailTypes] = React.useState(new Set(["character"]));
  const [depth, setDepth] = React.useState(2);
  const [showLabels, setShowLabels] = React.useState(true);
  const [hovered, setHovered] = React.useState(null);
  const [query, setQuery] = React.useState("");
  const [openMenu, setOpenMenu] = React.useState(null); // 'types' | 'depth' | null

  const toggleType = (t) =>
    setVisibleTypes((prev) => {
      const next = new Set(prev);
      if (next.has(t)) { if (next.size > 1) next.delete(t); } else next.add(t);
      return next;
    });

  const setAllTypes = () => setVisibleTypes(new Set(ENTITY_ORDER));

  const toggleRailType = (t) =>
    setRailTypes((prev) => {
      const next = new Set(prev);
      if (next.has(t)) { if (next.size > 1) next.delete(t); } else next.add(t);
      return next;
    });
  const setAllRailTypes = () => setRailTypes(new Set(ENTITY_ORDER));

  const onCenter = (key) => { setCenterKey(key); setHovered(null); };
  const onReset = () => { setCenterKey(D.defaultCenter); setHovered(null); };
  const toggleMenu = (m) => setOpenMenu((cur) => (cur === m ? null : m));
  const visibleCount = ENTITY_ORDER.filter((t) => visibleTypes.has(t)).length;

  const visKey = ENTITY_ORDER.filter((t) => visibleTypes.has(t)).join(",");
  const graph = React.useMemo(
    () => egPrepGraph(centerKey, visibleTypes, depth),
    [centerKey, visKey, depth]
  );

  return (
    <React.Fragment>
      <EgNavigator
        railTypes={railTypes}
        centerKey={centerKey}
        onCenter={onCenter}
        query={query}
        setQuery={setQuery}
        toggleRailType={toggleRailType}
        setAllRailTypes={setAllRailTypes}
      />
      <main className="eg-main">
        <div className="eg-toolbar">
          <div className="eg-toolbar__crumb">
            <Icon name="tree-structure" size={15} color="var(--text-muted)" />
            <span>关系图谱</span>
            <Icon name="caret-right" size={12} color="var(--text-subtle)" />
            <span className="eg-toolbar__center">{NODE_BY_KEY[centerKey].name}</span>
          </div>
          <div className="eg-toolbar__spacer" />

          <EgDropdown
            label="实体类型"
            icon="funnel"
            summary={`${visibleCount}/${ENTITY_ORDER.length}`}
            open={openMenu === "types"}
            onToggle={() => toggleMenu("types")}
            width={210}
          >
            <div className="eg-menu__head">显示实体类型</div>
            {ENTITY_ORDER.map((t) => {
              const et = D.entityTypes[t];
              const on = visibleTypes.has(t);
              return (
                <button key={t} className="eg-menu__check" onClick={() => toggleType(t)}>
                  <span className={"eg-check" + (on ? " is-on" : "")} style={{ "--c": et.color }}>
                    {on && <Icon name="check" size={11} />}
                  </span>
                  <span className="eg-menu__dot" style={{ background: et.color }} />
                  <span className="eg-menu__label">{et.zh}</span>
                  <span className="eg-menu__n">{TYPE_COUNTS[t]}</span>
                </button>
              );
            })}
          </EgDropdown>

          <EgDropdown
            label="关系深度"
            summary={`${depth} 跳`}
            open={openMenu === "depth"}
            onToggle={() => toggleMenu("depth")}
            width={150}
          >
            <div className="eg-menu__head">从焦点展开</div>
            {[1, 2, 3].map((d) => (
              <button key={d} className={"eg-menu__item" + (depth === d ? " is-on" : "")} onClick={() => { setDepth(d); setOpenMenu(null); }}>
                <span className="eg-menu__label">{d} 跳关系</span>
                {depth === d && <Icon name="check" size={12} color="var(--accent)" />}
              </button>
            ))}
          </EgDropdown>

          <button className={"eg-toggle" + (showLabels ? " is-on" : "")} onClick={() => setShowLabels((s) => !s)}>
            <Icon name="tag" size={14} />
            关系标签
          </button>

          {openMenu && <div className="eg-menu-scrim" onClick={() => setOpenMenu(null)} />}
        </div>

        <EgGraphCanvas
          graph={graph}
          centerKey={centerKey}
          hovered={hovered}
          setHovered={setHovered}
          onCenter={onCenter}
          onReset={onReset}
          showLabels={showLabels}
        />

        <EgLegend />
      </main>
      <EgInspector centerKey={centerKey} onCenter={onCenter} />
    </React.Fragment>
  );
}

function EgLegend() {
  const cats = Object.keys(CAT_LABELS)
    .filter((c) => c !== "other")
    .map((c) => [c, CAT_LABELS[c]]);
  return (
    <div className="eg-legend">
      <span className="eg-legend__title">关系类型</span>
      {cats.map(([c, label]) => (
        <span key={c} className="eg-legend__item">
          <span className="eg-legend__line" style={{ background: D.relCatColor[c] }} />
          {label}
        </span>
      ))}
    </div>
  );
}

Object.assign(window, { EntityGraphView });
