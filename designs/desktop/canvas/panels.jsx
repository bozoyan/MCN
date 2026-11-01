// panels.jsx — CanvasToolbar / 节点原地详情 / 连线原地编辑 / 图例 / 资源选择器。
// 没有右侧检查器:选中节点就在节点下方原地展开,选中连线就在连线上原地编辑,
// 右栏只留给助手。位置(x/y/尺寸)对作者没有意义,不展示。
// 关联文件: canvas/board.jsx, canvas/data.jsx, canvas/app.jsx, canvas/canvas.css

/* ---------------- 小原子 ---------------- */
function CvBtn({ kind = "ghost", icon, children, onClick, disabled, title, style }) {
  return (
    <button type="button" className={`cv-btn cv-btn--${kind}`} onClick={onClick}
      disabled={disabled} title={title} style={style}>
      {icon && <CvIcon name={icon} size={14} />}
      {children}
    </button>
  );
}
function CvIconBtn({ icon, onClick, title, on, size = 16 }) {
  return (
    <button type="button" className={"cv-iconbtn" + (on ? " is-on" : "")}
      onClick={onClick} title={title}>
      <CvIcon name={icon} size={size} />
    </button>
  );
}
function CvSwatch({ type }) {
  const m = CV_EDGE_TYPES[type];
  return (
    <span className="cv-etype__swatch" style={{
      borderTopStyle: m.dash ? (m.dash.startsWith("2") ? "dotted" : "dashed") : "solid",
      borderTopColor: m.color,
    }} />
  );
}

/* ---------------- 顶部工具栏 ---------------- */
function CanvasToolbar({
  canvas, view, onZoom, onFit, onBack,
  onAddReference, onAddSticky, deadCount, onCleanDead,
  agentBusy, onStartAgent,
}) {
  return (
    <div className="cv-toolbar">
      <CvIconBtn icon="arrow-left" title={`返回 ${canvas.novel}`} onClick={onBack} />
      <span className="cv-toolbar__sep" />
      <span className="cv-toolbar__title" title={canvas.desc}>
        <span className="cv-toolbar__name">{canvas.name}</span>
        <span className="cv-toolbar__crumb">{canvas.novel} · 画布</span>
      </span>

      <span className="cv-spacer" />

      <CvBtn icon="plus" onClick={onAddReference} title="把已有资源放到画布上">引用</CvBtn>
      <CvBtn icon="note-pencil" onClick={onAddSticky} title="写一张便签">便签</CvBtn>
      {deadCount > 0 && (
        <CvBtn icon="trash-simple" onClick={onCleanDead} title="移除引用已失效的节点">
          清理失效 {deadCount}
        </CvBtn>
      )}

      <span className="cv-toolbar__sep" />

      <CvIconBtn icon="minus" size={14} title="缩小" onClick={() => onZoom(-1)} />
      <span className="cv-zoom-value">{Math.round(view.k * 100)}%</span>
      <CvIconBtn icon="plus" size={14} title="放大" onClick={() => onZoom(1)} />
      <CvIconBtn icon="arrows-out" title="适应视图" onClick={onFit} />

      <span className="cv-toolbar__sep" />

      <CvBtn kind={agentBusy ? "outline" : "primary"} icon="sparkle"
        onClick={onStartAgent} disabled={agentBusy}
        title="让助手在这张画布上组织资源">
        {agentBusy ? "共创中…" : "AI 共创"}
      </CvBtn>
    </div>
  );
}

/* ---------------- 边类型选择列表 ---------------- */
function CvEdgeTypeList({ value, onPick, compact }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
      {CV_EDGE_ORDER.map((t) => {
        const m = CV_EDGE_TYPES[t];
        return (
          <button key={t} type="button"
            className={"cv-etype" + (value === t ? " is-active" : "")}
            onClick={() => onPick(t)}>
            <CvSwatch type={t} />
            <span style={{ flex: 1, minWidth: 0 }}>
              <span style={{ display: "block", fontWeight: 600 }}>{m.label}</span>
              {!compact && <span className="cv-etype__desc">{m.desc}</span>}
            </span>
            {value === t && <CvIcon name="check" size={13} color="var(--accent-warm)" />}
          </button>
        );
      })}
    </div>
  );
}

/* 连线落点后的类型选择弹层(屏幕坐标,跟着鼠标松手的位置) */
function CvEdgeTypePopover({ at, onPick, onCancel }) {
  return (
    <div className="cv-pop" style={{
      left: Math.max(12, at.x - 130), top: Math.max(12, at.y + 10), width: 236,
    }}>
      <div className="cv-pop__head" style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <CvIcon name="link" size={14} color="var(--text-muted)" />
        <span style={{ flex: 1, fontSize: 12, color: "var(--text-secondary)", fontWeight: 600 }}>
          这条线是什么关系？
        </span>
        <CvIconBtn icon="x" size={13} title="取消" onClick={onCancel} />
      </div>
      <div className="cv-scroll" style={{ padding: 6 }}>
        <CvEdgeTypeList value={null} onPick={onPick} compact />
      </div>
    </div>
  );
}

/* ---------------- 节点原地详情(挂在节点下方,随节点一起缩放) ---------------- */
function CvNodeDetail({ node, nodes, edges, dead, onUpdateNode, onDeleteNode, onSelectNode }) {
  const linked = edges.filter((e) => e.from === node.id || e.to === node.id);
  const stop = (e) => e.stopPropagation();

  return (
    <div className="cv-node__detail" onPointerDown={stop}>
      {node.kind === "sticky" ? (
        <React.Fragment>
          <div className="cv-detail__label">便签</div>
          <input className="cv-input" value={node.title} placeholder="标题"
            onChange={(e) => onUpdateNode(node.id, { title: e.target.value })} />
          <textarea className="cv-input" rows={4} value={node.text}
            style={{ marginTop: 6 }}
            onChange={(e) => onUpdateNode(node.id, { text: e.target.value })} />
          <div style={{ marginTop: 10, display: "flex", alignItems: "center", gap: 6 }}>
            {CV_STICKY_COLORS.map((c) => (
              <button key={c.key} type="button" title={c.label}
                onClick={() => onUpdateNode(node.id, { color: c.key })}
                style={{
                  width: 26, height: 20, borderRadius: "var(--radius-medium)",
                  background: c.value, cursor: "pointer",
                  border: node.color === c.key
                    ? "2px solid var(--accent)"
                    : "1px solid var(--border-input)",
                }} />
            ))}
            <span style={{ flex: 1 }} />
            <CvIconBtn icon="trash-simple" size={14} title="删除便签"
              onClick={() => onDeleteNode(node.id)} />
          </div>
        </React.Fragment>
      ) : (
        <React.Fragment>
          <div className="cv-detail__sub">
            {dead
              ? "该人物已在人物编辑器中删除。节点保留在画布上，资源恢复后自动重新生效。"
              : (() => {
                  const r = cvResource(node.refId);
                  return r && r.sub ? r.sub : CV_REF_TYPES[node.refType].label;
                })()}
          </div>
          <div className="cv-detail__hr" />
        </React.Fragment>
      )}

      {node.kind === "reference" && (
        <React.Fragment>
          <div className="cv-detail__label">连线 {linked.length}</div>
          {linked.length === 0 && (
            <div className="cv-detail__sub">拖右侧圆点连到另一个节点。</div>
          )}
          {linked.map((e) => {
            const m = CV_EDGE_TYPES[e.type];
            const otherId = e.from === node.id ? e.to : e.from;
            const other = nodes.find((n) => n.id === otherId);
            return (
              <button key={e.id} type="button" className="cv-detail__row"
                onClick={() => onSelectNode(otherId)}>
                <CvIcon name={e.from === node.id ? "arrow-right" : "arrow-left"}
                  size={13} color={m.color} style={{ marginTop: 3 }} />
                <span style={{ flex: 1, minWidth: 0 }}>
                  <span style={{ display: "block", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                    {other ? other.title : "—"}
                  </span>
                  <span className="cv-etype__desc">{m.label}{e.label ? " · " + e.label : ""}</span>
                </span>
              </button>
            );
          })}

          <div className="cv-detail__hr" />
          <div className="cv-detail__actions">
            {!dead && (
              <CvBtn kind="outline" icon="arrow-square-out">
                打开{CV_REF_TYPES[node.refType].label}原文
              </CvBtn>
            )}
            <CvBtn kind="danger" icon="trash-simple" title="删除节点"
              style={dead ? null : { flex: "0 0 auto" }}
              onClick={() => onDeleteNode(node.id)}>
              {dead ? "移除失效节点" : null}
            </CvBtn>
          </div>
        </React.Fragment>
      )}
    </div>
  );
}

/* ---------------- 连线原地编辑(挂在连线中点) ---------------- */
function CvEdgeEditor({ edge, at, onUpdateEdge, onDeleteEdge, onClose }) {
  const stop = (e) => e.stopPropagation();
  return (
    <div className="cv-edge-editor" style={{ left: at.x, top: at.y }} onPointerDown={stop}>
      <CvEdgeTypeList value={edge.type} onPick={(t) => onUpdateEdge(edge.id, { type: t })} compact />
      <div style={{ display: "flex", gap: 6, marginTop: 8 }}>
        <input className="cv-input" placeholder="说明文字，如「旧友 · 互相隐瞒」"
          value={edge.label || ""}
          onChange={(e) => onUpdateEdge(edge.id, { label: e.target.value })} />
        <CvIconBtn icon="trash-simple" size={14} title="删除连线"
          onClick={() => onDeleteEdge(edge.id)} />
        <CvIconBtn icon="x" size={14} title="收起" onClick={onClose} />
      </div>
    </div>
  );
}

/* ---------------- 图例(浮在画布左下,收纳「构思 ≠ 正典」的边界说明) ---------------- */
function CvLegend({ edges }) {
  const [open, setOpen] = React.useState(false);
  const counts = {};
  edges.forEach((e) => { counts[e.type] = (counts[e.type] || 0) + 1; });

  return (
    <div className="cv-legend">
      {open && (
        <div className="cv-legend__card">
          {CV_EDGE_ORDER.map((t) => (
            <div key={t} className="cv-legend__row">
              <CvSwatch type={t} />
              <span style={{ flex: 1 }}>{CV_EDGE_TYPES[t].label}</span>
              <span className="cv-legend__count">{counts[t] || 0}</span>
            </div>
          ))}
          <div className="cv-note" style={{ marginTop: 12 }}>
            <CvIcon name="info" size={14} color="var(--text-muted)" style={{ marginTop: 2 }} />
            <span>
              画布上的连线只用于构思，不会进入实体关系图。想把某条关系变成正典，
              用 <b>CreateRelation</b> 单独写入。
            </span>
          </div>
        </div>
      )}
      <div className="cv-hint" style={{ position: "static" }}>
        <button type="button" onClick={() => setOpen((o) => !o)}
          style={{
            display: "inline-flex", alignItems: "center", gap: 5, border: "none",
            background: "transparent", padding: 0, cursor: "pointer",
            font: "inherit", color: open ? "var(--accent-warm)" : "var(--text-secondary)",
          }}>
          <CvIcon name="list-bullets" size={13} />图例
        </button>
        <span style={{ opacity: 0.4 }}>·</span>
        <span>拖空白平移</span>
        <span className="cv-kbd">滚轮</span>
        <span>缩放</span>
        <span style={{ opacity: 0.4 }}>·</span>
        <span>拖节点右侧圆点连线</span>
      </div>
    </div>
  );
}

/* ---------------- 引用资源选择器 ---------------- */
function CvResourcePopover({ usedRefIds, onPick, onCancel, rightOffset = 12 }) {
  const [q, setQ] = React.useState("");
  const hit = CV_RESOURCES.filter(
    (r) => !r.deleted && (!q || r.title.includes(q) || CV_REF_TYPES[r.type].label.includes(q))
  );
  const groups = [];
  hit.forEach((r) => {
    let g = groups.find((x) => x.type === r.type);
    if (!g) { g = { type: r.type, rows: [] }; groups.push(g); }
    g.rows.push(r);
  });

  return (
    <div className="cv-pop" style={{ right: rightOffset, top: 52 }}>
      <div className="cv-pop__head">
        <input className="cv-input" autoFocus placeholder="搜索人物 / 章节 / 伏笔…"
          value={q} onChange={(e) => setQ(e.target.value)} />
      </div>
      <div className="cv-scroll">
        {groups.length === 0 && <div className="cv-empty">没有匹配的资源。</div>}
        {groups.map((g) => {
          const m = CV_REF_TYPES[g.type];
          return (
            <div key={g.type}>
              <div className="cv-pop__group">{m.label}</div>
              {g.rows.map((r) => {
                const used = usedRefIds.has(r.id);
                return (
                  <button key={r.id} type="button" className="cv-pop__row"
                    disabled={used} onClick={() => onPick(r)}>
                    <span className="cv-ref__chip" style={{ background: cvTint(m.color, 13), width: 24, height: 24 }}>
                      <CvIcon name={m.icon} size={13} color={m.color} />
                    </span>
                    <span style={{ flex: 1, minWidth: 0 }}>
                      <span style={{ display: "block", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                        {r.title}
                      </span>
                      {r.sub && <span className="cv-etype__desc">{r.sub}</span>}
                    </span>
                    {used && <span className="cv-etype__desc">已在画布</span>}
                  </button>
                );
              })}
            </div>
          );
        })}
      </div>
      <div style={{ padding: 10, borderTop: "1px solid var(--border-subtle)", display: "flex", justifyContent: "flex-end" }}>
        <CvBtn onClick={onCancel}>取消</CvBtn>
      </div>
    </div>
  );
}

Object.assign(window, {
  CvBtn, CvIconBtn, CvSwatch,
  CanvasToolbar, CvEdgeTypeList, CvEdgeTypePopover,
  CvNodeDetail, CvEdgeEditor, CvLegend, CvResourcePopover,
});
