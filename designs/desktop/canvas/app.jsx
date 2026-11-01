// app.jsx — CanvasEditorPage:画布详情独立页(对应方案 5.4 的 canvas_editor_page.dart)。
// 这一层是唯一的状态所有者:节点 / 连线 / 选中 / 视口 / 助手会话都在这里,
// 画布与面板只拿 props —— 对应真实实现里「DB 是唯一真相源」的分工。
// 关联文件: canvas/board.jsx, canvas/panels.jsx, canvas/agent.jsx, canvas/data.jsx

function CanvasEditorPage({ onBack }) {
  const [nodes, setNodes] = React.useState(CV_INITIAL_NODES);
  const [edges, setEdges] = React.useState(CV_INITIAL_EDGES);
  const [selection, setSelection] = React.useState({ kind: "none", id: null });
  const [view, setView] = React.useState({ x: 0, y: 0, k: 1 });
  const [size, setSize] = React.useState({ w: 0, h: 0 });
  const [smooth, setSmooth] = React.useState(false);
  const [agentOpen, setAgentOpen] = React.useState(true);
  const [popover, setPopover] = React.useState(null);

  const [agentRun, setAgentRun] = React.useState(0);
  const [agentBusy, setAgentBusy] = React.useState(false);
  const [agentLog, setAgentLog] = React.useState([]);

  /* 引用失效:源资源被删,画布节点保留但标为失效(流程 D) */
  const deadIds = React.useMemo(() => {
    const s = new Set();
    nodes.forEach((n) => {
      if (n.kind !== "reference") return;
      const r = cvResource(n.refId);
      if (!r || r.deleted) s.add(n.id);
    });
    return s;
  }, [nodes]);

  const usedRefIds = React.useMemo(
    () => new Set(nodes.filter((n) => n.kind === "reference").map((n) => n.refId)),
    [nodes]
  );

  /* ---------------- 视口 ---------------- */
  const onSize = React.useCallback((s) => {
    setSize((p) => (p.w === s.w && p.h === s.h ? p : s));
  }, []);
  const setViewUser = React.useCallback((u) => { setSmooth(false); setView(u); }, []);

  const fitted = React.useRef(false);
  React.useEffect(() => {
    if (fitted.current || !size.w) return;
    fitted.current = true;
    setView(cvFitView(nodes, size));
  }, [size, nodes]);

  const fit = () => { setSmooth(true); setView(cvFitView(nodes, size)); };
  const zoom = (dir) => {
    setSmooth(true);
    setView((v) => {
      const k = Math.min(CV_ZOOM_MAX, Math.max(CV_ZOOM_MIN, v.k * (dir > 0 ? 1.2 : 1 / 1.2)));
      const cx = size.w / 2;
      const cy = size.h / 2;
      return { k, x: cx - (cx - v.x) * (k / v.k), y: cy - (cy - v.y) * (k / v.k) };
    });
  };
  const worldCenter = () => ({
    x: (size.w / 2 - view.x) / view.k,
    y: (size.h / 2 - view.y) / view.k,
  });

  /* ---------------- 选中 ---------------- */
  const selectNode = (id) => setSelection({ kind: "node", id });
  const selectEdge = (id) => setSelection({ kind: "edge", id });
  const clearSelection = () => { setSelection({ kind: "none", id: null }); setPopover(null); };

  /* ---------------- 节点 / 连线写入 ---------------- */
  // commit=false 表示拖拽过程中(只动 UI);true 表示 onDragStop → 落库
  const moveNode = React.useCallback((id, x, y, _commit) => {
    setNodes((ns) => ns.map((n) => (n.id === id ? { ...n, x, y } : n)));
  }, []);

  const updateNode = (id, patch) =>
    setNodes((ns) => ns.map((n) => (n.id === id ? { ...n, ...patch } : n)));

  const updateEdge = (id, patch) =>
    setEdges((es) => es.map((e) => (e.id === id ? { ...e, ...patch } : e)));

  const deleteNode = (id) => {
    setNodes((ns) => ns.filter((n) => n.id !== id));
    setEdges((es) => es.filter((e) => e.from !== id && e.to !== id));
    clearSelection();
  };
  const deleteEdge = (id) => {
    setEdges((es) => es.filter((e) => e.id !== id));
    clearSelection();
  };

  const addSticky = () => {
    const c = worldCenter();
    const id = `n_note_${Date.now()}`;
    setNodes((ns) => [...ns, {
      id, kind: "sticky", color: "sand", author: "作者",
      title: "新便签", text: "写点什么。",
      x: Math.round(c.x - 120), y: Math.round(c.y - 68), w: 240, h: 136,
    }]);
    selectNode(id);
    setPopover(null);
  };

  const addReference = (res) => {
    const c = worldCenter();
    const jitter = (nodes.length % 5) * 26;
    const id = `n_ref_${res.id}_${Date.now()}`;
    setNodes((ns) => [...ns, {
      id, kind: "reference", refType: res.type, refId: res.id, title: res.title,
      x: Math.round(c.x - CV_NODE_W / 2 + jitter), y: Math.round(c.y - CV_NODE_H / 2 + jitter),
      w: CV_NODE_W, h: CV_NODE_H,
    }]);
    selectNode(id);
    setPopover(null);
  };

  const cleanDead = () => {
    setNodes((ns) => ns.filter((n) => !deadIds.has(n.id)));
    setEdges((es) => es.filter((e) => !deadIds.has(e.from) && !deadIds.has(e.to)));
    clearSelection();
  };

  const requestEdge = React.useCallback((req) => setPopover({ type: "edge", ...req }), []);

  const createEdge = (type) => {
    const { from, to } = popover;
    setPopover(null);
    const dup = edges.some((e) => e.from === from && e.to === to && e.type === type);
    if (dup) return;
    const id = `e_${Date.now()}`;
    setEdges((es) => [...es, { id, from, to, type, label: "" }]);
    selectEdge(id);
  };

  /* ---------------- 键盘 ---------------- */
  React.useEffect(() => {
    const onKey = (e) => {
      const t = document.activeElement;
      const typing = t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA");
      if (e.key === "Escape") { clearSelection(); return; }
      if (typing || selection.kind === "none") return;
      if (e.key === "Delete" || e.key === "Backspace") {
        e.preventDefault();
        if (selection.kind === "node") deleteNode(selection.id);
        else deleteEdge(selection.id);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [selection]);

  /* ---------------- 助手共创重放 ---------------- */
  const startAgent = () => { setAgentOpen(true); setAgentRun((r) => r + 1); };

  // ?agent=1 直接进共创演示(方便把这一段单独发给别人看)
  React.useEffect(() => {
    if (new URLSearchParams(window.location.search).get("agent") !== "1") return;
    const t = setTimeout(startAgent, 700);
    return () => clearTimeout(t);
  }, []);

  React.useEffect(() => {
    if (!agentRun) return;
    setAgentLog([]);
    setAgentBusy(true);
    setNodes((ns) => ns.filter((n) => !n.byAgent));
    setEdges((es) => es.filter((e) => !e.byAgent));
    clearSelection();

    const timers = CV_AGENT_SCRIPT.map((step) =>
      setTimeout(() => {
        setAgentLog((l) => [...l, step]);
        if (step.addNode) setNodes((ns) => (ns.some((n) => n.id === step.addNode.id) ? ns : [...ns, step.addNode]));
        if (step.addEdge) setEdges((es) => (es.some((e) => e.id === step.addEdge.id) ? es : [...es, step.addEdge]));
      }, step.at)
    );
    const last = CV_AGENT_SCRIPT[CV_AGENT_SCRIPT.length - 1].at;
    const end = setTimeout(() => setAgentBusy(false), last + 300);
    return () => { timers.forEach(clearTimeout); clearTimeout(end); };
  }, [agentRun]);

  // agent 每放一个节点就把视图拉回来,作者能跟着它的思路走(方案 user story 5)
  const nodeCount = nodes.length;
  React.useEffect(() => {
    if (!agentBusy || !size.w) return;
    setSmooth(true);
    setView(cvFitView(nodes, size));
    // eslint-disable-next-line
  }, [nodeCount, agentBusy]);

  /* ---------------- 渲染 ---------------- */
  return (
    <div className="cv-page">
      <CanvasToolbar
        canvas={CV_CANVAS}
        view={view}
        onZoom={zoom}
        onFit={fit}
        onBack={onBack}
        onAddReference={() => setPopover(popover && popover.type === "resource" ? null : { type: "resource" })}
        onAddSticky={addSticky}
        deadCount={deadIds.size}
        onCleanDead={cleanDead}
        agentBusy={agentBusy}
        onStartAgent={startAgent}
      />

      <div className="cv-body">
        <div style={{ position: "relative", flex: 1, minWidth: 0, display: "flex" }}>
          <CanvasBoard
            nodes={nodes}
            edges={edges}
            view={view}
            setView={setViewUser}
            smooth={smooth}
            size={size}
            onSize={onSize}
            selection={selection}
            onSelectNode={selectNode}
            onSelectEdge={selectEdge}
            onClearSelection={clearSelection}
            onMoveNode={moveNode}
            onRequestEdge={requestEdge}
            deadIds={deadIds}
            onUpdateNode={updateNode}
            onDeleteNode={deleteNode}
            onUpdateEdge={updateEdge}
            onDeleteEdge={deleteEdge}
          />
          {popover && popover.type === "edge" && (
            <CvEdgeTypePopover at={popover.at} onPick={createEdge} onCancel={() => setPopover(null)} />
          )}
          {!agentOpen && (
            <button type="button" className="cv-float"
              style={{ right: 14, top: 14, gap: 6, padding: "0 12px", height: 32, cursor: "pointer",
                fontFamily: "inherit", fontSize: 12, fontWeight: 600, color: "var(--text-secondary)" }}
              onClick={() => setAgentOpen(true)} title="打开画布助手">
              <CvIcon name="sparkle" size={14} />助手
              {agentBusy && <span style={{ width: 6, height: 6, borderRadius: 99, background: "var(--accent)" }} />}
            </button>
          )}
        </div>

        {agentOpen && (
          <aside className="cv-right">
            <div className="cv-right__head">
              <CvIcon name="sparkle" size={15} color="var(--accent-warm)" />
              <span className="cv-right__title">画布助手</span>
              {agentBusy && <span style={{ width: 6, height: 6, borderRadius: 99, background: "var(--accent)" }} />}
              <CvIconBtn icon="x" size={14} title="收起" onClick={() => setAgentOpen(false)} />
            </div>
            <CanvasAgentPanel
              log={agentLog}
              busy={agentBusy}
              onStart={startAgent}
              onReset={startAgent}
            />
          </aside>
        )}
      </div>

      {popover && popover.type === "resource" && (
        <CvResourcePopover
          usedRefIds={usedRefIds}
          onPick={addReference}
          onCancel={() => setPopover(null)}
          rightOffset={agentOpen ? 372 : 12}
        />
      )}
    </div>
  );
}

/* 页面入口 —— 画布是独立路由页,整页占满窗口(没有 NavRail / ChatPanel)。
   agent 的 7 个 canvas 工具只在停在这一页时注入,离开即 no_active_canvas。 */
function CanvasEntry() {
  const from = new URLSearchParams(window.location.search).get("from");
  const back = () => {
    window.location.href = from === "editor"
      ? `../index.html?novel=${CV_CANVAS.novelId}`
      : "../index.html";
  };
  if (typeof WindowFrame === "function") {
    return (
      <WindowFrame>
        <div className="m-app">
          <CanvasEditorPage onBack={back} />
        </div>
      </WindowFrame>
    );
  }
  return <CanvasEditorPage onBack={back} />;
}

Object.assign(window, { CanvasEditorPage, CanvasEntry });
