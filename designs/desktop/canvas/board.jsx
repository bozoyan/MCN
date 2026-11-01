// board.jsx — CanvasBoard:无限画布工作区。
// 真实实现基于 lib/third/flow/vyuh_node_flow(MobX NodeFlowController);这里用等价的
// pan/zoom/drag/connect 手写一层,只为把交互手感和视觉语言定下来。
//   · 平移:拖空白;缩放:滚轮(以指针为锚点)
//   · 节点拖拽:拖拽中只动 UI,松手(onDragStop)才写库 —— 与方案「流程 A」一致
//   · 连线:从节点右侧 anchor port 拖到另一个节点,松手后选边类型
//   · LOD:缩放 < 0.55 时节点降级为缩略条
// 关联文件: canvas/data.jsx, canvas/panels.jsx, canvas/app.jsx, canvas/canvas.css

const CV_ZOOM_MIN = 0.28;
const CV_ZOOM_MAX = 2.2;
const CV_LOD_K = 0.55;

/* ---------------- 几何 ---------------- */
function cvCenter(n) {
  return { x: n.x + n.w / 2, y: n.y + n.h / 2 };
}

// 从节点中心朝 target 射线与节点矩形边界的交点(anchor port 的视觉落点)。
function cvBoundary(n, target, pad = 4) {
  const c = cvCenter(n);
  const dx = target.x - c.x;
  const dy = target.y - c.y;
  if (dx === 0 && dy === 0) return c;
  const hw = n.w / 2 + pad;
  const hh = n.h / 2 + pad;
  const sx = dx === 0 ? Infinity : hw / Math.abs(dx);
  const sy = dy === 0 ? Infinity : hh / Math.abs(dy);
  const s = Math.min(sx, sy);
  return { x: c.x + dx * s, y: c.y + dy * s };
}

// 二次贝塞尔:bow 为垂直于两端连线的弯曲量,用来让并行/跨越的边绕开中间节点。
function cvWire(a, b, bow = 0) {
  const ca = cvCenter(a);
  const cb = cvCenter(b);
  const dx = cb.x - ca.x;
  const dy = cb.y - ca.y;
  const len = Math.hypot(dx, dy) || 1;
  const m = {
    x: (ca.x + cb.x) / 2 + (-dy / len) * bow,
    y: (ca.y + cb.y) / 2 + (dx / len) * bow,
  };
  const p1 = cvBoundary(a, m);
  const p2 = cvBoundary(b, m);
  return {
    d: `M ${p1.x} ${p1.y} Q ${m.x} ${m.y} ${p2.x} ${p2.y}`,
    mid: {
      x: 0.25 * p1.x + 0.5 * m.x + 0.25 * p2.x,
      y: 0.25 * p1.y + 0.5 * m.y + 0.25 * p2.y,
    },
  };
}

function cvBounds(nodes, pad = 80) {
  if (!nodes.length) return { x: 0, y: 0, w: 800, h: 600 };
  const x1 = Math.min(...nodes.map((n) => n.x)) - pad;
  const y1 = Math.min(...nodes.map((n) => n.y)) - pad;
  const x2 = Math.max(...nodes.map((n) => n.x + n.w)) + pad;
  const y2 = Math.max(...nodes.map((n) => n.y + n.h)) + pad;
  return { x: x1, y: y1, w: x2 - x1, h: y2 - y1 };
}

// 把内容 bbox 装进 size 视口,返回 {x,y,k}
function cvFitView(nodes, size) {
  const b = cvBounds(nodes);
  if (!size.w || !size.h) return { x: 0, y: 0, k: 1 };
  const k = Math.max(CV_ZOOM_MIN, Math.min(1.05, Math.min(size.w / b.w, size.h / b.h)));
  return {
    k,
    x: (size.w - b.w * k) / 2 - b.x * k,
    y: (size.h - b.h * k) / 2 - b.y * k,
  };
}

/* ---------------- 边层 ---------------- */
function CvWires({ nodes, edges, selectedId, onSelectEdge, k }) {
  const byId = {};
  nodes.forEach((n) => { byId[n.id] = n; });
  const drawn = edges
    .map((e) => {
      const a = byId[e.from];
      const b = byId[e.to];
      if (!a || !b) return null;
      const meta = CV_EDGE_TYPES[e.type];
      return { e, meta, ...cvWire(a, b, e.bow || 0) };
    })
    .filter(Boolean);

  return (
    <React.Fragment>
      <svg className="cv-wires">
        <defs>
          {CV_EDGE_ORDER.filter((t) => CV_EDGE_TYPES[t].directed).map((t) => (
            <marker key={t} id={`cv-arrow-${t}`} markerWidth="8" markerHeight="8"
              refX="6.2" refY="4" orient="auto">
              <path d="M1,1 L6.4,4 L1,7" fill="none" strokeWidth="1.5"
                strokeLinecap="round" strokeLinejoin="round"
                style={{ stroke: CV_EDGE_TYPES[t].color }} />
            </marker>
          ))}
        </defs>
        {drawn.map(({ e, meta, d }) => {
          const on = selectedId === e.id;
          return (
            <g key={e.id}>
              <path
                d={d}
                fill="none"
                strokeWidth={on ? 3 : 1.8}
                strokeLinecap="round"
                strokeDasharray={meta.dash || undefined}
                style={{ stroke: meta.color, opacity: on ? 1 : 0.9, transition: "stroke-width .12s" }}
                markerEnd={meta.directed ? `url(#cv-arrow-${e.type})` : undefined}
              />
              {on && (
                <path d={d} fill="none" strokeWidth={9} strokeLinecap="round"
                  style={{ stroke: meta.color, opacity: 0.16 }} />
              )}
              <path className="cv-wire-hit" d={d} strokeWidth={16 / Math.max(k, 0.4)}
                onPointerDown={(ev) => { ev.stopPropagation(); onSelectEdge(e.id); }} />
            </g>
          );
        })}
      </svg>
      {k >= CV_LOD_K &&
        drawn
          .filter(({ e }) => e.label)
          .map(({ e, meta, mid }) => (
            <div key={`l-${e.id}`} className="cv-edge-label"
              style={{ left: mid.x, top: mid.y, color: meta.color }}>
              {e.label}
            </div>
          ))}
    </React.Fragment>
  );
}

/* ---------------- 节点 ---------------- */
function CvNodeCard({ node, selected, dead, linkTarget, lod, onPointerDown, onAnchorDown, detail }) {
  const cls = [
    "cv-node",
    selected ? "is-selected" : "",
    dead ? "is-dead" : "",
    linkTarget ? "is-linktarget" : "",
  ].join(" ").trim();

  const box = {
    left: node.x, top: node.y, width: node.w, height: node.h,
    zIndex: selected ? 20 : 1,
  };

  if (lod) {
    const meta = node.kind === "reference" ? CV_REF_TYPES[node.refType] : null;
    return (
      <div className={cls} style={box} onPointerDown={onPointerDown}>
        <div className="cv-lod" style={node.kind === "sticky"
          ? { background: `var(--cv-sticky-${node.color})`, border: "1px solid transparent" }
          : null}>
          <span style={{
            width: 10, height: 10, borderRadius: 3, flex: "none",
            background: dead ? "var(--text-subtle)" : (meta ? meta.color : "var(--accent-amber)"),
          }} />
          <span className="cv-lod__bar" />
        </div>
      </div>
    );
  }

  if (node.kind === "sticky") {
    return (
      <div className={cls} style={box} onPointerDown={onPointerDown}>
        <div className="cv-sticky" style={{ background: `var(--cv-sticky-${node.color})` }}>
          <div className="cv-sticky__label">
            <CvIcon name="note-pencil" size={12} />
            {node.title || "便签"}
          </div>
          <div className="cv-sticky__body">{node.text}</div>
          <div className="cv-sticky__author">— {node.author}</div>
        </div>
        <span className="cv-anchor" onPointerDown={onAnchorDown} title="拖出一条连线" />
        {selected && detail}
      </div>
    );
  }

  const meta = CV_REF_TYPES[node.refType];
  return (
    <div className={cls} style={box} onPointerDown={onPointerDown}>
      <div className="cv-ref">
        <span className="cv-ref__chip" style={{
          background: dead ? "var(--surface-dim)" : cvTint(meta.color, 13),
          border: dead ? "1px dashed var(--border-input)" : "none",
        }}>
          <CvIcon name={dead ? "warning-circle" : meta.icon} size={15}
            color={dead ? "var(--text-subtle)" : meta.color} />
        </span>
        <span className="cv-ref__meta">
          <span className="cv-ref__title">{node.title}</span>
          <span className="cv-ref__kind">{dead ? `${meta.label} · 引用已失效` : meta.label}</span>
        </span>
      </div>
      <span className="cv-anchor" onPointerDown={onAnchorDown} title="拖出一条连线" />
      {selected && detail}
    </div>
  );
}

/* ---------------- 小地图 ---------------- */
function CvMinimap({ nodes, view, size }) {
  // world 窗口 = 内容 bbox ∪ 当前视口,这样视口框永远画得下、不会被裁掉
  const c = cvBounds(nodes, 60);
  const vwx = -view.x / view.k;
  const vwy = -view.y / view.k;
  const b = (() => {
    const x1 = Math.min(c.x, vwx);
    const y1 = Math.min(c.y, vwy);
    const x2 = Math.max(c.x + c.w, vwx + size.w / view.k);
    const y2 = Math.max(c.y + c.h, vwy + size.h / view.k);
    return { x: x1, y: y1, w: x2 - x1, h: y2 - y1 };
  })();
  const pad = 8;
  const mw = 172 - pad * 2;
  const mh = 116 - pad * 2;
  const s = Math.min(mw / b.w, mh / b.h);
  const ox = pad + (mw - b.w * s) / 2;
  const oy = pad + (mh - b.h * s) / 2;
  const px = (wx) => ox + (wx - b.x) * s;
  const py = (wy) => oy + (wy - b.y) * s;

  const vx = px(vwx);
  const vy = py(vwy);
  const vw = (size.w / view.k) * s;
  const vh = (size.h / view.k) * s;

  return (
    <div className="cv-minimap" aria-hidden="true">
      {nodes.map((n) => (
        <span key={n.id} style={{
          position: "absolute",
          left: px(n.x), top: py(n.y),
          width: Math.max(3, n.w * s), height: Math.max(2, n.h * s),
          borderRadius: 2,
          background: n.kind === "sticky"
            ? cvTint("var(--accent-amber)", 55)
            : cvTint(CV_REF_TYPES[n.refType].color, 55),
        }} />
      ))}
      <span style={{
        position: "absolute", left: vx, top: vy, width: vw, height: vh,
        border: "1.5px solid var(--accent)", borderRadius: 3,
        background: cvTint("var(--accent)", 8), pointerEvents: "none",
      }} />
    </div>
  );
}

/* ---------------- 画布 ---------------- */
function CanvasBoard({
  nodes, edges, view, setView, smooth, size, onSize,
  selection, onSelectNode, onSelectEdge, onClearSelection,
  onMoveNode, onRequestEdge, deadIds,
  onUpdateNode, onDeleteNode, onUpdateEdge, onDeleteEdge,
}) {
  const boardRef = React.useRef(null);
  const dragRef = React.useRef(null);
  const [panning, setPanning] = React.useState(false);
  const [link, setLink] = React.useState(null); // {fromId, to:{x,y}, overId}

  // 视口尺寸(小地图 + fitToView 需要)
  React.useEffect(() => {
    const el = boardRef.current;
    if (!el) return;
    const report = () => onSize({ w: el.clientWidth, h: el.clientHeight });
    report();
    const ro = new ResizeObserver(report);
    ro.observe(el);
    return () => ro.disconnect();
  }, [onSize]);

  // 滚轮缩放 —— 必须 non-passive 才能 preventDefault
  React.useEffect(() => {
    const el = boardRef.current;
    if (!el) return;
    const onWheel = (ev) => {
      ev.preventDefault();
      const r = el.getBoundingClientRect();
      const mx = ev.clientX - r.left;
      const my = ev.clientY - r.top;
      setView((v) => {
        const k = Math.min(CV_ZOOM_MAX, Math.max(CV_ZOOM_MIN, v.k * Math.exp(-ev.deltaY * 0.0016)));
        return { k, x: mx - (mx - v.x) * (k / v.k), y: my - (my - v.y) * (k / v.k) };
      });
    };
    el.addEventListener("wheel", onWheel, { passive: false });
    return () => el.removeEventListener("wheel", onWheel);
  }, [setView]);

  const toWorld = React.useCallback((ev) => {
    const r = boardRef.current.getBoundingClientRect();
    return {
      x: (ev.clientX - r.left - view.x) / view.k,
      y: (ev.clientY - r.top - view.y) / view.k,
    };
  }, [view]);

  /* --- 全局 pointer 处理:平移 / 节点拖拽 / 连线 --- */
  React.useEffect(() => {
    const move = (ev) => {
      const d = dragRef.current;
      if (!d) return;
      if (d.mode === "pan") {
        setView((v) => ({ ...v, x: d.vx + (ev.clientX - d.sx), y: d.vy + (ev.clientY - d.sy) }));
      } else if (d.mode === "node") {
        const dx = (ev.clientX - d.sx) / view.k;
        const dy = (ev.clientY - d.sy) / view.k;
        onMoveNode(d.id, d.nx + dx, d.ny + dy, false);
      } else if (d.mode === "link") {
        const p = toWorld(ev);
        const over = nodes.find(
          (n) => n.id !== d.id && p.x >= n.x && p.x <= n.x + n.w && p.y >= n.y && p.y <= n.y + n.h
        );
        setLink({ fromId: d.id, to: p, overId: over ? over.id : null });
      }
    };
    const up = (ev) => {
      const d = dragRef.current;
      dragRef.current = null;
      setPanning(false);
      if (!d) return;
      if (d.mode === "node") {
        // 拖拽结束才落库(流程 A:拖拽中只动 flow controller)
        const dx = (ev.clientX - d.sx) / view.k;
        const dy = (ev.clientY - d.sy) / view.k;
        onMoveNode(d.id, d.nx + dx, d.ny + dy, true);
      } else if (d.mode === "link") {
        const p = toWorld(ev);
        const over = nodes.find(
          (n) => n.id !== d.id && p.x >= n.x && p.x <= n.x + n.w && p.y >= n.y && p.y <= n.y + n.h
        );
        if (over) {
          const r = boardRef.current.getBoundingClientRect();
          onRequestEdge({
            from: d.id, to: over.id,
            at: { x: ev.clientX - r.left, y: ev.clientY - r.top },
          });
        }
        setLink(null);
      }
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
    return () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
    };
  }, [nodes, view, setView, onMoveNode, onRequestEdge, toWorld]);

  const startPan = (ev) => {
    if (ev.button !== 0) return;
    onClearSelection();
    dragRef.current = { mode: "pan", sx: ev.clientX, sy: ev.clientY, vx: view.x, vy: view.y };
    setPanning(true);
  };
  const startNodeDrag = (node) => (ev) => {
    if (ev.button !== 0) return;
    ev.stopPropagation();
    onSelectNode(node.id);
    dragRef.current = { mode: "node", id: node.id, sx: ev.clientX, sy: ev.clientY, nx: node.x, ny: node.y };
  };
  const startLink = (node) => (ev) => {
    ev.stopPropagation();
    ev.preventDefault();
    dragRef.current = { mode: "link", id: node.id };
    setLink({ fromId: node.id, to: cvCenter(node), overId: null });
  };

  const lod = view.k < CV_LOD_K;
  const linkFrom = link ? nodes.find((n) => n.id === link.fromId) : null;

  // 选中的连线 —— 编辑器就浮在这条线的中点上(原地编辑,不进右栏)
  const selEdge = selection.kind === "edge" ? edges.find((e) => e.id === selection.id) : null;
  const selEdgeAt = (() => {
    if (!selEdge || lod) return null;
    const a = nodes.find((n) => n.id === selEdge.from);
    const b = nodes.find((n) => n.id === selEdge.to);
    return a && b ? cvWire(a, b, selEdge.bow || 0).mid : null;
  })();

  return (
    <div
      ref={boardRef}
      className={"cv-board" + (panning ? " is-panning" : "") + (link ? " is-linking" : "")}
      onPointerDown={startPan}
      style={{
        backgroundSize: `${24 * view.k}px ${24 * view.k}px`,
        backgroundPosition: `${view.x}px ${view.y}px`,
      }}
    >
      <div
        className="cv-layer"
        style={{
          transform: `translate(${view.x}px, ${view.y}px) scale(${view.k})`,
          transition: smooth ? "transform .5s cubic-bezier(.2,.7,.3,1)" : "none",
        }}
      >
        <CvWires
          nodes={nodes}
          edges={edges}
          k={view.k}
          selectedId={selection.kind === "edge" ? selection.id : null}
          onSelectEdge={onSelectEdge}
        />

        {/* 正在拖出的连线 */}
        {link && linkFrom && (
          <svg className="cv-wires">
            <path
              d={`M ${cvBoundary(linkFrom, link.to).x} ${cvBoundary(linkFrom, link.to).y} L ${link.to.x} ${link.to.y}`}
              fill="none" strokeWidth={1.8} strokeDasharray="5 5" strokeLinecap="round"
              style={{ stroke: "var(--accent)" }}
            />
          </svg>
        )}

        {nodes.map((n) => {
          const sel = selection.kind === "node" && selection.id === n.id;
          return (
            <CvNodeCard
              key={n.id}
              node={n}
              lod={lod}
              dead={deadIds.has(n.id)}
              selected={sel}
              linkTarget={!!link && link.overId === n.id}
              onPointerDown={startNodeDrag(n)}
              onAnchorDown={startLink(n)}
              detail={
                <CvNodeDetail
                  node={n}
                  nodes={nodes}
                  edges={edges}
                  dead={deadIds.has(n.id)}
                  onUpdateNode={onUpdateNode}
                  onDeleteNode={onDeleteNode}
                  onSelectNode={onSelectNode}
                />
              }
            />
          );
        })}

        {selEdge && selEdgeAt && (
          <CvEdgeEditor
            edge={selEdge}
            at={selEdgeAt}
            onUpdateEdge={onUpdateEdge}
            onDeleteEdge={onDeleteEdge}
            onClose={onClearSelection}
          />
        )}
      </div>

      <CvMinimap nodes={nodes} view={view} size={size} />
      <CvLegend edges={edges} />
    </div>
  );
}

Object.assign(window, {
  CanvasBoard, cvCenter, cvBoundary, cvWire, cvBounds, cvFitView,
  CV_ZOOM_MIN, CV_ZOOM_MAX, CV_LOD_K,
});
