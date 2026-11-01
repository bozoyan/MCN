// agent.jsx — 画布助手面板(人机共创)。
// 演示方案「流程 B / C」:LLM 调 canvas 工具 → CanvasService → DB → stream →
// 画布实时出现节点与连线。面板本身是纯展示,重放驱动在 app.jsx。
// 关联文件: canvas/app.jsx, canvas/data.jsx, canvas/canvas.css

const CV_TOOLS = [
  "CanvasGetContent", "CanvasAddNode", "CanvasUpdateNode",
  "CanvasRemoveNode", "CanvasAddEdge", "CanvasRemoveEdge", "CanvasCreate",
];

function CvToolCard({ name, detail }) {
  return (
    <div className="cv-tool">
      <CvIcon name="lightning" size={13} color="var(--accent-warm)" />
      <span className="cv-tool__name">{name}</span>
      <span className="cv-tool__detail">{detail}</span>
      <CvIcon name="check" size={12} color="var(--success)" />
    </div>
  );
}

function CvAgentEmpty() {
  return (
    <div className="cv-sec" style={{ borderBottom: "none" }}>
      <div className="cv-note" style={{ marginBottom: 16 }}>
        <CvIcon name="robot" size={14} color="var(--text-muted)" style={{ marginTop: 2 }} />
        <span>
          画布工具只在这一页注入。回到编辑器后助手就不带这 7 个工具，
          留在上下文里的调用会返回 <code style={{ fontFamily: "var(--font-mono)" }}>no_active_canvas</code>。
        </span>
      </div>
      <div className="cv-sec__label">可用的画布工具</div>
      <div className="cv-chiprow">
        {CV_TOOLS.map((t) => (
          <span key={t} className="cv-chip" style={{
            color: "var(--text-secondary)", background: "var(--surface-dim)",
            fontFamily: "var(--font-mono)",
          }}>{t}</span>
        ))}
      </div>
      <div className="cv-etype__desc" style={{ marginTop: 14, lineHeight: 1.8 }}>
        试一句：「把主角团的关系画到画布上」。
        助手只组织已有资源、写便签，不在画布上生成新的正文。
      </div>
    </div>
  );
}

function CanvasAgentPanel({ log, busy, onStart, onReset }) {
  const scroller = React.useRef(null);
  const [draft, setDraft] = React.useState("把主角团的关系画到画布上，顺便标一下谁和谁互相猜忌。");

  React.useEffect(() => {
    if (scroller.current) scroller.current.scrollTop = scroller.current.scrollHeight;
  }, [log.length]);

  const send = () => {
    if (busy || !draft.trim()) return;
    onStart();
  };

  const lastIsAi = log.length > 0 && log[log.length - 1].kind === "ai";

  return (
    <React.Fragment>
      <div className="cv-chat" ref={scroller}>
        {log.length === 0 && <CvAgentEmpty />}
        {log.map((m, i) => {
          if (m.kind === "tool") return <CvToolCard key={i} name={m.name} detail={m.detail} />;
          if (m.kind === "user") return <div key={i} className="cv-msg-user">{m.text}</div>;
          return (
            <div key={i} className="cv-msg-ai">
              {m.text}
              {busy && lastIsAi && i === log.length - 1 && <span className="cv-caret" />}
            </div>
          );
        })}
        {busy && !lastIsAi && (
          <div className="cv-msg-ai" style={{ color: "var(--text-muted)" }}>
            正在写入画布<span className="cv-caret" />
          </div>
        )}
      </div>

      {log.length > 0 && !busy && (
        <div style={{ padding: "0 var(--space-lg) var(--space-lg)" }}>
          <CvBtn kind="outline" icon="arrow-counter-clockwise" style={{ width: "100%" }} onClick={onReset}>
            重放这段共创
          </CvBtn>
        </div>
      )}

      <div className="cv-composer">
        <div className="cv-composer__box">
          <textarea rows={2} value={draft} disabled={busy}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) { e.preventDefault(); send(); }
            }}
            placeholder={busy ? "助手正在操作画布…" : "让助手在这张画布上帮你组织…"} />
          <button type="button" className="cv-send" title="发送" onClick={send}
            style={{
              background: busy || !draft.trim() ? "var(--surface-dim)" : "var(--accent)",
              cursor: busy || !draft.trim() ? "default" : "pointer",
            }}>
            <CvIcon name="paper-plane-tilt" size={15}
              color={busy || !draft.trim() ? "var(--text-subtle)" : "var(--on-accent)"} />
          </button>
        </div>
        <div className="cv-etype__desc" style={{ marginTop: 8, lineHeight: 1.6 }}>
          每次写入都是一次工具调用，画布通过 stream 实时同步。
        </div>
      </div>
    </React.Fragment>
  );
}

Object.assign(window, { CanvasAgentPanel, CvToolCard, CV_TOOLS });
