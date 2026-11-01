// board.jsx — DrBoard:每集一张的制作画布。
// 几何(cvWire / cvFitView)复用 canvas/board.jsx;平移、缩放、拖拽与构思画布同一手感。
// 节点:素材(图片/视频/音频) / 场次导演工程 / 视频节点(带场次的是片段节点,进成片) / 图片节点(生成或上传一张图)。
// 视频 / 图片节点还没有结果时,画面位置放「上传」,上传的文件直接成为这个节点的结果。
// 连线只有一种参与生成:素材或视频节点右侧输出口 → 视频节点左侧输入口,松手后选用途。常态细虚线、低对比。
// 视频节点作为来源时,传给下游的是它当前采用的结果。
// 选中视频节点时,它的输入连线高亮并标出「用途 + 媒体槽」(图片1、视频1…),其余变淡。
// 点连线选中它,可以改用途或断开;断开即删除这条输入(用途、顺序不保留)。
// 关联文件: drama/data.jsx, drama/app.jsx, canvas/board.jsx, drama/drama.css

/* ---------------- 画面占位 ----------------
   没有真实素材,用色调 + 剪影表达「这是一帧画面」;ratio 决定外框比例。 */
function DrFrame({ tone = "lamp", ratio = "9:16", w, h, play, label, figures = 2, style }) {
  const [rw, rh] = ratio.split(":").map(Number);
  const box = w ? { width: w, height: h || Math.round((w * rh) / rw) } : { height: h, width: Math.round((h * rw) / rh) };
  return (
    <span className={`dr-frame dr-frame--${tone}`} style={{ ...box, ...style }}>
      {figures > 0 && (
        <span className="dr-frame__figs">
          {Array.from({ length: figures }).map((_, i) => <span key={i} className="dr-frame__fig" />)}
        </span>
      )}
      {play && (
        <span className="dr-frame__play"><CvIcon name="play" size={10} color="currentColor" /></span>
      )}
      {label && <span className="dr-frame__label">{label}</span>}
    </span>
  );
}

/* 资产缩略:图片/视频画面占位,音频画波形条 */
function DrAssetThumb({ asset, h = 64, ratio }) {
  if (asset.type === "audio") {
    return (
      <span className="dr-wave" style={{ height: h, width: Math.round(h * 1.6) }}>
        {[5, 9, 14, 8, 12, 6, 10, 15, 7, 11, 5, 9].map((v, i) => <span key={i} style={{ height: `${v * 6}%` }} />)}
      </span>
    );
  }
  const r = ratio || (asset.spec && asset.spec.startsWith("720×1280") ? "9:16" : asset.spec && asset.spec.startsWith("1920") ? "16:9" : "1:1");
  return <DrFrame tone={asset.tone} ratio={r} h={h} figures={asset.char ? 1 : asset.type === "video" ? 2 : 0} play={asset.type === "video"} />;
}

/* ---------------- 任务状态投影 ---------------- */
// 只看这个来源最近一次任务;和片段制作状态分开显示。
function drLastTask(tasks, source) {
  const list = tasks.filter((t) => t.source.type === source.type && t.source.id === source.id);
  return list[list.length - 1] || null;
}

// 失败提醒:一行给「图标 + 状态 + 一个能解决它的动作 + 关闭」,原因和对采用结果的影响放悬停提示。
// 下载失败可只重新下载、不再计费,用警示色;生成失败用错误色,动作是打开「结果」看原因。
// 关闭只隐藏这条提醒,「结果」里仍保留这次记录。
const DR_TASK_FAIL = {
  download_failed: { label: "下载失败", tone: "warn", action: "重新下载" },
  failed:          { label: "生成失败", tone: "err",  action: "查看原因" },
};
function drTaskShown(task) {
  if (!task || task.state === "succeeded") return false;
  return !(DR_TASK_FAIL[task.state] && task.dismissed);
}

function DrTaskLine({ task, hasResult, onRedownload, onOpenResults, onDismiss }) {
  if (!drTaskShown(task)) return null;
  const fail = DR_TASK_FAIL[task.state];
  if (!fail) {
    const st = SP_TASK_STATE[task.state];
    return <span className={"dr-tstate dr-tstate--" + st.tone}>{task.state === "running" ? `生成中 ${task.progress}%` : st.label}</span>;
  }
  const stop = (e) => e.stopPropagation();
  const tip = [task.error, hasResult ? "当前仍使用采用中的结果" : "还没有可用结果"].filter(Boolean).join("\n");
  return (
    <span className={"dr-talert dr-tstate--" + fail.tone} title={tip}>
      <CvIcon name="warning-circle" size={12} color="currentColor" />
      <span className="dr-talert__label">{fail.label}</span>
      <span className="dr-talert__dot">·</span>
      <button type="button" className="dr-talert__act" onPointerDown={stop}
        onClick={(e) => { stop(e); task.state === "download_failed" ? onRedownload(task.id) : onOpenResults(task.source.id); }}>
        {fail.action}
      </button>
      <button type="button" className="dr-talert__close" title="关闭提醒 · 「结果」里仍保留这次记录" onPointerDown={stop}
        onClick={(e) => { stop(e); onDismiss(task.id); }}>
        <CvIcon name="x" size={10} color="currentColor" />
      </button>
    </span>
  );
}

/* ---------------- 节点卡 ---------------- */
// 节点上的风格只在单独设置时标出来;跟随剧集不重复显示。
function drStyleNote(node) {
  if (node.style === undefined) return "";
  const st = drStyleOf(node, null);
  return ` · ${st.name}`;
}

// 还没有结果:画面位置放上传入口,点了走系统文件选择器;文件去重保存进资产库(见 app.jsx fakeUpload)。
function DrUploadSlot({ image, w, h, onUpload }) {
  return (
    <button type="button" className="dr-frame dr-frame--empty dr-upslot" style={{ width: w, height: h }}
      onPointerDown={(e) => e.stopPropagation()} onClick={onUpload}>
      <CvIcon name="upload" size={16} color="currentColor" />
      <span>上传</span>
    </button>
  );
}

function DrGenCard({ node, cfg, task, selected, connectTarget, onPointerDown, onPortDown, onUpload, taskActs }) {
  const box = { left: node.x, top: node.y, width: node.w, height: node.h, zIndex: selected ? 20 : 2 };
  const model = drModel(cfg.gen.model);
  const adopted = cfg.adopted && spAsset(cfg.adopted);
  return (
    <div className={"cv-node dr-node dr-node--gen" + (selected ? " is-selected" : "") + (connectTarget ? " is-target" : "")}
      style={box} onPointerDown={onPointerDown} data-gen={node.id}>
      <div className="dr-video">
        <span className="dr-port dr-port--in" />
        <div className="dr-video__thumb">
          {adopted
            ? <DrFrame tone={adopted.tone} h={150} play label={adopted.sample ? "样片 · 480P" : "采用中"} />
            : <DrUploadSlot w={84} h={150} onUpload={() => onUpload(node)} />}
        </div>
        <div className="dr-video__body">
          <div className="dr-video__head">
            {drIsSeg(node)
              ? <span className="dr-shotno">段 {drSegNo(node)}</span>
              : <span className="dr-shotno dr-shotno--free">视频</span>}
            <span className="dr-video__title">{cfg.title}</span>
          </div>
          <div className="dr-video__desc">
            {cfg.prompt ? spPromptPlain(cfg.prompt) : <span className="dr-muted">还没写提示词</span>}
          </div>
          <div className="dr-video__meta">
            {model.name} · {drSecs(cfg.ms) ? `${drSecs(cfg.ms)}s` : "—"} · {cfg.gen.ratio}{drStyleNote(cfg)}
          </div>
          <div className="dr-video__foot">
            {drIsSeg(node) && (
              <span className={"dr-pstatus dr-pstatus--" + cfg.status}>
                <span className="dr-pstatus__dot" />{DR_SEG_STATUS[cfg.status].label}
              </span>
            )}
            <DrTaskLine task={task} hasResult={!!adopted} {...taskActs} />
          </div>
        </div>
        <span className="dr-port dr-port--out" title="拖到另一个视频节点,把采用的结果作为参考"
          onPointerDown={(e) => { e.stopPropagation(); onPortDown(e, node); }} />
      </div>
    </div>
  );
}

// 图片节点:上面是采用的图(按比例,夹在卡片内),下面一行标题与规格。
function DrImageCard({ node, task, selected, connectTarget, onPointerDown, onPortDown, onUpload, taskActs }) {
  const box = { left: node.x, top: node.y, width: node.w, height: node.h, zIndex: selected ? 20 : 2 };
  const model = drModel(node.gen.model);
  const adopted = node.adopted && spAsset(node.adopted);
  const line = drTaskShown(task);
  const [rw, rh] = node.gen.ratio.split(":").map(Number);
  const maxW = node.w - 20;
  // 有任务提醒时多占一行,画面相应缩小,卡片高度不变。
  const maxH = node.h - 58 - (line ? 20 : 0);
  const k = Math.min(maxW / rw, maxH / rh);
  const fw = Math.round(rw * k);
  const fh = Math.round(rh * k);
  return (
    <div className={"cv-node dr-node dr-node--gen dr-node--image" + (selected ? " is-selected" : "") + (connectTarget ? " is-target" : "")}
      style={box} onPointerDown={onPointerDown} data-gen={node.id}>
      <div className="dr-imgnode">
        <span className="dr-port dr-port--in" />
        <div className="dr-imgnode__pv">
          {adopted
            ? <DrFrame tone={adopted.tone} w={fw} h={fh} figures={adopted.char ? 1 : 0} label={node.uploaded ? "上传" : "采用中"} />
            : <DrUploadSlot image w={fw} h={fh} onUpload={() => onUpload(node)} />}
        </div>
        <div className="dr-video__head">
          <span className="dr-shotno dr-shotno--free"><CvIcon name="image" size={10} color="currentColor" />图片</span>
          <span className="dr-video__title">{node.title}</span>
        </div>
        <div className="dr-video__meta">
          {node.uploaded ? "上传" : model.name} · {node.gen.ratio} · {node.gen.res}{drStyleNote(node)}
        </div>
        {line && <div className="dr-imgnode__task"><DrTaskLine task={task} hasResult={!!adopted} {...taskActs} /></div>}
        <span className="dr-port dr-port--out" title="拖到视频节点,作为参考图或首尾帧"
          onPointerDown={(e) => { e.stopPropagation(); onPortDown(e, node); }} />
      </div>
    </div>
  );
}

function DrNodeCard({ node, cfg, task, selected, connectTarget, onPointerDown, onPortDown, onOpenDirector, onUpload, taskActs }) {
  if (node.kind === "video") {
    return <DrGenCard node={node} cfg={cfg} task={task} selected={selected} taskActs={taskActs}
      connectTarget={connectTarget} onPointerDown={onPointerDown} onPortDown={onPortDown} onUpload={onUpload} />;
  }
  if (node.kind === "image") {
    return <DrImageCard node={node} task={task} selected={selected} taskActs={taskActs}
      connectTarget={connectTarget} onPointerDown={onPointerDown} onPortDown={onPortDown} onUpload={onUpload} />;
  }
  const box = { left: node.x, top: node.y, width: node.w, height: node.h, zIndex: selected ? 20 : 2 };
  const cls = "cv-node dr-node dr-node--" + node.kind + (selected ? " is-selected" : "");
  const asset = node.assetId ? spAsset(node.assetId) : null;

  if (node.kind === "director") {
    const sc = SP_SCENES.find((x) => x.id === node.sceneId);
    return (
      <div className={cls} style={box} onPointerDown={onPointerDown}>
        <div className="dr-dir">
          <div className="dr-dir__head">
            <span className="dr-chip" style={{ background: cvTint("var(--dr-director)", 16) }}>
              <CvIcon name="cube" size={15} color="var(--dr-director)" />
            </span>
            <span className="cv-ref__meta">
              <span className="cv-ref__title">{asset ? asset.name : `第 ${sc.no} 场布景`}</span>
              <span className="cv-ref__kind">导演工程 · {asset ? asset.spec : "还没有布景"}</span>
            </span>
          </div>
          <button type="button" className="cv-btn cv-btn--outline dr-dir__open"
            onPointerDown={(e) => e.stopPropagation()} onClick={onOpenDirector}>
            <CvIcon name="arrow-square-out" size={13} />打开导演台
          </button>
        </div>
      </div>
    );
  }

  // 空素材节点:从「添加」新建、还没选内容。没有输出口 —— 选了资产才能连线。
  if (!asset) {
    const t = DR_ASSET_TYPES[node.mediaType];
    return (
      <div className={cls + " dr-node--empty"} style={box} onPointerDown={onPointerDown}>
        <div className="dr-asset dr-asset--empty">
          <span className="dr-asset__ph"><CvIcon name={t.icon} size={20} color="var(--text-subtle)" /></span>
          <span className="cv-ref__meta">
            <span className="dr-asset__kind" style={{ color: "var(--text-muted)" }}>
              <CvIcon name={t.icon} size={11} color="currentColor" />{t.label}
            </span>
            <span className="cv-ref__kind">拖入文件，或从资产库选择</span>
          </span>
        </div>
      </div>
    );
  }

  // 素材:图片 / 视频 / 音频。右侧输出口拖线到视频节点即成为输入。
  const t = DR_ASSET_TYPES[asset.type];
  const fromDirector = asset.source.startsWith("导演输出");
  return (
    <div className={cls} style={box} onPointerDown={onPointerDown}>
      <div className="dr-asset">
        <DrAssetThumb asset={asset} h={node.h - 20} />
        <span className="cv-ref__meta">
          <span className="dr-asset__kind" style={{ color: fromDirector ? "var(--dr-director)" : "var(--text-muted)" }}>
            <CvIcon name={fromDirector ? "cube" : t.icon} size={11} color="currentColor" />
            {fromDirector ? (asset.type === "video" ? "导演预演" : "导演构图") : t.label}
          </span>
          <span className="cv-ref__title">{asset.name}</span>
          <span className="cv-ref__kind">{fromDirector ? asset.source.replace("导演输出 · ", "") : asset.spec}</span>
        </span>
        <span className="dr-port dr-port--out" title="拖到视频节点,作为生成输入"
          onPointerDown={(e) => { e.stopPropagation(); onPortDown(e, node); }} />
      </div>
    </div>
  );
}

/* ---------------- 连线 ---------------- */
function DrWires({ nodes, edges, focusGen, selectedEdge, slots, onSelectEdge, draft }) {
  const byId = {};
  nodes.forEach((n) => { byId[n.id] = n; });
  const items = edges.map((e) => {
    const a = byId[e.from];
    const b = byId[e.to];
    if (!a || !b) return null;
    const w = cvWire(a, b, e.bow || 0);
    const focused = focusGen && e.to === focusGen;
    const dim = (focusGen && !focused) || (selectedEdge && selectedEdge !== e.id);
    return { e, ...w, focused, dim, sel: selectedEdge === e.id };
  }).filter(Boolean);

  return (
    <React.Fragment>
      {/* 连线默认是细虚线、低对比 —— 画布上线多,常态只需要看出「谁连着谁」。
          选中视频节点时只有它的输入变成强调色并标出用途;选中的那一条再加粗。
          不画箭头:方向由端口决定(素材右侧输出 → 视频左侧输入)。 */}
      <svg className="cv-wires">
        {items.map(({ e, d, focused, dim, sel }) => (
          <g key={e.id}>
            <path d={d} fill="none" strokeWidth="14" style={{ stroke: "transparent", cursor: "pointer", pointerEvents: "stroke" }}
              onPointerDown={(ev) => { ev.stopPropagation(); onSelectEdge(e.id); }} />
            <path d={d} fill="none" strokeLinecap="round"
              strokeWidth={sel ? 2.2 : focused ? 1.6 : 1.1}
              strokeDasharray={sel ? "6 4" : "4 5"}
              style={{
                stroke: focused || sel ? "var(--accent)" : "var(--text-subtle)",
                opacity: sel || focused ? 0.95 : dim ? 0.18 : 0.5,
                pointerEvents: "none",
              }} />
          </g>
        ))}
        {draft && (
          <path d={`M ${draft.x1} ${draft.y1} C ${draft.x1 + 80} ${draft.y1}, ${draft.x2 - 80} ${draft.y2}, ${draft.x2} ${draft.y2}`}
            fill="none" strokeWidth="1.6" strokeDasharray="4 5" style={{ stroke: "var(--accent)" }} />
        )}
      </svg>
      {items.filter((x) => x.focused || x.sel).map(({ e, mid }) => {
        const slot = slots && slots.find((s) => s.id === e.id);
        return (
          <div key={"l-" + e.id} className={"cv-edge-label dr-edge-role" + (e.id === selectedEdge ? " is-sel" : "")}
            style={{ left: mid.x, top: mid.y }}>
            {DR_ROLES[e.role].label}{slot && slot.slot !== DR_ROLES[e.role].label ? ` · ${slot.slot}` : ""}
          </div>
        );
      })}
    </React.Fragment>
  );
}

/* ---------------- 场次色带 ---------------- */
function DrBands() {
  return DR_BANDS.map((b) => {
    const sc = SP_SCENES.find((s) => s.id === b.sceneId);
    return (
      <div key={b.sceneId} className="dr-band" style={{ left: b.x, top: b.y, width: b.w, height: b.h }}>
        <span className="dr-band__label">
          第 {sc.no} 场 · {sc.place} · {sc.time} / {sc.ie}
        </span>
      </div>
    );
  });
}

/* ---------------- 画布 ---------------- */
// onConnect(fromNode, toNode, screenPoint):松手落在视频节点上时调用,由 app 弹出用途选择。
function DrBoard({ nodes, edges, tasks, view, setView, onSize, selectedId, onSelect, selectedEdge, onSelectEdge,
  onMoveNode, onOpenDirector, onConnect, onCanvasMenu, onUpload, taskActs }) {
  const ref = React.useRef(null);
  const dragRef = React.useRef(null);
  const [panning, setPanning] = React.useState(false);
  const [draft, setDraft] = React.useState(null);
  const [hoverGen, setHoverGen] = React.useState(null);

  React.useEffect(() => {
    const el = ref.current;
    const report = () => onSize({ w: el.clientWidth, h: el.clientHeight });
    report();
    const ro = new ResizeObserver(report);
    ro.observe(el);
    return () => ro.disconnect();
  }, [onSize]);

  React.useEffect(() => {
    const el = ref.current;
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

  const toWorld = (cx, cy) => {
    const r = ref.current.getBoundingClientRect();
    return { x: (cx - r.left - view.x) / view.k, y: (cy - r.top - view.y) / view.k };
  };
  const genAt = (cx, cy) => {
    const el = document.elementFromPoint(cx, cy);
    const card = el && el.closest("[data-gen]");
    return card ? card.getAttribute("data-gen") : null;
  };

  React.useEffect(() => {
    const move = (ev) => {
      const d = dragRef.current;
      if (!d) return;
      if (d.mode === "pan") {
        setView((v) => ({ ...v, x: d.vx + ev.clientX - d.sx, y: d.vy + ev.clientY - d.sy }));
      } else if (d.mode === "node") {
        onMoveNode(d.id, d.nx + (ev.clientX - d.sx) / view.k, d.ny + (ev.clientY - d.sy) / view.k);
      } else if (d.mode === "wire") {
        const p = toWorld(ev.clientX, ev.clientY);
        setDraft({ from: d.from, x1: d.x1, y1: d.y1, x2: p.x, y2: p.y });
        setHoverGen(genAt(ev.clientX, ev.clientY));
      }
    };
    const up = (ev) => {
      const d = dragRef.current;
      if (d && d.mode === "wire") {
        const target = genAt(ev.clientX, ev.clientY);
        setDraft(null);
        setHoverGen(null);
        if (target && target !== d.from) onConnect(d.from, target, { x: ev.clientX, y: ev.clientY });
      }
      dragRef.current = null;
      setPanning(false);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
    return () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
    };
  }, [view, setView, onMoveNode, onConnect]);

  const sel = nodes.find((n) => n.id === selectedId);
  const focusGen = drIsGen(sel) ? sel.id : null;
  const slots = focusGen ? drInputsOf(edges, focusGen, nodes) : null;

  return (
    <div ref={ref} className={"cv-board" + (panning ? " is-panning" : "") + (draft ? " is-wiring" : "")}
      onPointerDown={(ev) => {
        if (ev.button !== 0) return;
        onSelect(null);
        onSelectEdge(null);
        dragRef.current = { mode: "pan", sx: ev.clientX, sy: ev.clientY, vx: view.x, vy: view.y };
        setPanning(true);
      }}
      onDoubleClick={(ev) => onCanvasMenu({ x: ev.clientX, y: ev.clientY })}
      style={{
        backgroundSize: `${24 * view.k}px ${24 * view.k}px`,
        backgroundPosition: `${view.x}px ${view.y}px`,
      }}>
      <div className="cv-layer" style={{ transform: `translate(${view.x}px, ${view.y}px) scale(${view.k})` }}>
        <DrBands />
        <DrWires nodes={nodes} edges={edges} focusGen={focusGen} selectedEdge={selectedEdge} slots={slots}
          onSelectEdge={(id) => { onSelect(null); onSelectEdge(id); }} draft={draft} />
        {nodes.map((n) => {
          const isGen = drIsGen(n);
          const task = isGen ? drLastTask(tasks, { type: "node", id: n.id }) : null;
          return (
            <DrNodeCard key={n.id} node={n} cfg={isGen ? n : null} task={task} selected={n.id === selectedId}
              connectTarget={hoverGen === n.id && draft && draft.from !== n.id}
              onOpenDirector={onOpenDirector} onUpload={onUpload} taskActs={taskActs}
              onPortDown={(ev, node) => {
                dragRef.current = { mode: "wire", from: node.id, x1: node.x + node.w, y1: node.y + node.h / 2 };
                const p = toWorld(ev.clientX, ev.clientY);
                setDraft({ from: node.id, x1: node.x + node.w, y1: node.y + node.h / 2, x2: p.x, y2: p.y });
              }}
              onPointerDown={(ev) => {
                if (ev.button !== 0) return;
                ev.stopPropagation();
                onSelect(n.id);
                onSelectEdge(null);
                dragRef.current = { mode: "node", id: n.id, sx: ev.clientX, sy: ev.clientY, nx: n.x, ny: n.y };
              }} />
          );
        })}
      </div>
    </div>
  );
}

Object.assign(window, { DrBoard, DrFrame, DrAssetThumb, DrUploadSlot, drLastTask, DrTaskLine, drTaskShown, DR_TASK_FAIL });
