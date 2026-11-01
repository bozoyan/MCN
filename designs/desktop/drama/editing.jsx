// editing.jsx — EditingPage:「剪辑」页,一集的多轨剪辑工程(状态唯一持有者)。
// app 内页面,和制片页同一套外壳:NavRail + 第二栏(作品、剧集、场次)+ 主区 + 制作助手。
// 主区:上半是预览 + 右侧「属性 / 素材」,下半是多轨时间线(中间的分隔条可以拖动改高度)。
// 入口:制片页顶栏的剪辑按钮。首次进入按成片顺序导入一次采用结果,之后是独立工程(见 edit_data.jsx)。
// 改动都进撤销栈:拖动、裁剪、分割、删除、替换、属性修改;连续拖同一个滑块只算一步。
// 深链(便于截图核对):&t=<秒>(播放头) &sel=<片段 id>|none &trans=<主轨片段 id> &panel=bin &replace=<主轨片段 id>
//   &dialog=export &xstate=running|done &chat=0 &ctx=0 &import=1(首次导入后的提示)
// 关联文件: drama/edit_timeline.jsx, drama/edit_panels.jsx, drama/edit_data.jsx, drama/views.jsx, drama/app.jsx

const ED_Q = new URLSearchParams(location.search);

function edInitialSel() {
  if (ED_Q.get("trans")) return { type: "trans", id: ED_Q.get("trans") };
  const s = ED_Q.get("sel");
  if (s === "none") return null;
  return { type: "clip", id: s || "c3" };
}

function EditingPage() {
  const [hist, setHist] = React.useState({
    past: [], future: [], key: null,
    present: { main: ED_MAIN, clips: ED_CLIPS, transitions: ED_TRANSITIONS, aiDuck: true },
  });
  const doc = hist.present;
  // key 相同的连续改动(拖同一个滑块、连续打字)合并成一步撤销。
  const commit = (fn, key) => setHist((h) => {
    const next = fn(h.present);
    if (next === h.present) return h;
    if (key && h.key === key) return { ...h, present: next };
    return { past: [...h.past.slice(-49), h.present], present: next, future: [], key: key || null };
  });
  const undo = () => setHist((h) => (h.past.length ? { past: h.past.slice(0, -1), present: h.past[h.past.length - 1], future: [h.present, ...h.future], key: null } : h));
  const redo = () => setHist((h) => (h.future.length ? { past: [...h.past, h.present], present: h.future[0], future: h.future.slice(1), key: null } : h));

  const [tracks, setTracks] = React.useState(() => ED_TRACKS.map((t) => ({ ...t })));
  const [playhead, setPlayhead] = React.useState(() => Number(ED_Q.get("t") || 24.2));
  const [playing, setPlaying] = React.useState(false);
  const [pps, setPps] = React.useState(null);
  const [laneW, setLaneW] = React.useState(0);
  const [sel, setSel] = React.useState(edInitialSel);
  const [panel, setPanel] = React.useState(ED_Q.get("panel") === "bin" || ED_Q.get("replace") ? "bin" : "props");
  const [replaceFor, setReplaceFor] = React.useState(ED_Q.get("replace"));
  const [snapOn, setSnapOn] = React.useState(true);
  const [chatOpen, setChatOpen] = React.useState(ED_Q.get("chat") !== "0");
  const [ctxOpen, setCtxOpen] = React.useState(ED_Q.get("ctx") !== "0");
  const [dlg, setDlg] = React.useState(ED_Q.get("dialog") === "export" ? { type: "export", state: ED_Q.get("xstate") } : null);
  const [toast, setToast] = React.useState(null);
  const [tlH, setTlH] = React.useState(368);

  const total = edTotal(doc.main, doc.clips);
  const laid = edLayoutMain(doc.main);

  const say = (t, ms = 2600) => {
    setToast(t);
    window.clearTimeout(say.timer);
    say.timer = window.setTimeout(() => setToast(null), ms);
  };
  React.useEffect(() => {
    if (ED_Q.get("import") === "1") say(`已按成片顺序导入 ${laid.length} 段 · ${laid.filter((c) => c.gap).length} 段未采用留作空缺 · 之后片段改动不会自动同步`, 5200);
  }, []);

  const fit = (w = laneW) => w && setPps(Math.min(90, Math.max(6, (w - 8) / (total + 8))));
  React.useEffect(() => { if (pps === null && laneW) fit(laneW); }, [laneW]);

  // 播放:按真实时间推进,到结尾停。
  const totalRef = React.useRef(total);
  totalRef.current = total;
  React.useEffect(() => {
    if (!playing) return;
    let raf;
    let last = performance.now();
    const tick = (now) => {
      const dt = (now - last) / 1000;
      last = now;
      setPlayhead((p) => {
        const n = p + dt;
        if (n >= totalRef.current) { setPlaying(false); return totalRef.current; }
        return n;
      });
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [playing]);
  const togglePlay = () => {
    if (!playing && playhead >= total - 0.05) setPlayhead(0);
    setPlaying(!playing);
  };
  const seek = (t) => setPlayhead(Math.max(0, Math.min(total, t)));
  const cuts = () => [...new Set([0, ...laid.map((c) => c.start + c.dur), ...doc.clips.flatMap((c) => [c.start, c.start + c.dur])])].sort((a, b) => a - b);
  const prevCut = () => seek([...cuts()].reverse().find((x) => x < playhead - 0.05) || 0);
  const nextCut = () => { const n = cuts().find((x) => x > playhead + 0.05); seek(n == null ? total : n); };

  /* ---------- 编辑操作 ---------- */
  const findClip = (id) => doc.main.find((c) => c.id === id) || doc.clips.find((c) => c.id === id);
  const isMainId = (id) => doc.main.some((c) => c.id === id);
  const patchClip = (id, patch, key) => commit((d) => (d.main.some((c) => c.id === id)
    ? { ...d, main: d.main.map((c) => (c.id === id ? { ...c, ...patch } : c)) }
    : { ...d, clips: d.clips.map((c) => (c.id === id ? { ...c, ...patch } : c)) }), key);
  const patchTrans = (id, tr, key) => commit((d) => ({ ...d, transitions: { ...d.transitions, [id]: tr } }), key);

  const selClip = sel && sel.type === "clip" ? findClip(sel.id) : null;
  const splitTarget = () => {
    if (selClip) {
      const c = isMainId(selClip.id) ? laid.find((x) => x.id === selClip.id) : selClip;
      return c;
    }
    return laid.find((c) => playhead > c.start && playhead < c.start + c.dur) || null;
  };
  const split = () => {
    const c = splitTarget();
    if (!c) return;
    const local = edSnapFrame(playhead - c.start);
    if (local < 0.1 || local > c.dur - 0.1) return say("播放头不在这个片段里");
    const nid = c.id + "_" + Date.now().toString(36);
    const speed = c.speed || 1;
    const a = { ...c, dur: local, fadeOut: 0 };
    const b = { ...c, id: nid, dur: c.dur - local, fadeIn: 0, ...(c.in != null ? { in: c.in + local * speed } : {}), ...(c.start != null && !isMainId(c.id) ? { start: c.start + local } : {}) };
    if (isMainId(c.id)) {
      const strip = ({ start, track, ...rest }) => rest;
      commit((d) => {
        const i = d.main.findIndex((x) => x.id === c.id);
        const tr = { ...d.transitions };
        if (tr[c.id]) { tr[nid] = tr[c.id]; delete tr[c.id]; }
        return { ...d, main: [...d.main.slice(0, i), strip(a), strip(b), ...d.main.slice(i + 1)], transitions: tr };
      });
    } else {
      commit((d) => ({ ...d, clips: d.clips.flatMap((x) => (x.id === c.id ? [a, b] : [x])) }));
    }
    setSel({ type: "clip", id: nid });
    say(`已在 ${edTc(playhead)} 分割`);
  };
  const remove = () => {
    if (sel && sel.type === "trans") {
      patchTrans(sel.id, { type: "none", dur: 0.5 });
      return say("已去掉转场");
    }
    if (!selClip) return;
    if (isMainId(selClip.id)) {
      commit((d) => {
        const tr = { ...d.transitions };
        delete tr[selClip.id];
        return { ...d, main: d.main.filter((c) => c.id !== selClip.id), transitions: tr };
      });
      say(`已删除 · 后面的片段前移 ${edSecsLabel(selClip.dur)}`);
    } else {
      commit((d) => ({ ...d, clips: d.clips.filter((c) => c.id !== selClip.id) }));
      say("已删除");
    }
    setSel(null);
  };
  const move = (id, p) => commit((d) => ({ ...d, clips: d.clips.map((c) => (c.id === id ? { ...c, ...p } : c)) }));
  const reorder = (id, index) => {
    commit((d) => {
      const c = d.main.find((x) => x.id === id);
      const rest = d.main.filter((x) => x.id !== id);
      return { ...d, main: [...rest.slice(0, index), c, ...rest.slice(index)] };
    });
    say("已调整主轨顺序");
  };
  const trim = (id, patch) => patchClip(id, patch);

  // 放素材:主轨落在空缺上 = 填空缺,落在片段上 = 插到最近的衔接点;其他轨落在空处。
  const place = (assetId, trackId, t) => {
    const a = spAsset(assetId);
    const track = tracks.find((x) => x.id === trackId);
    if (!track || track.locked) return say("这条轨道已锁定");
    if (!edAccepts(track, a)) return say(track.kind === "text" ? "字幕轨只放文字" : track.kind === "audio" ? "音频轨只放音频" : "视频轨只放视频和图片");
    const src = edSrcSecs(assetId) || 3;
    const id = "x" + Date.now().toString(36);
    if (track.main) {
      const hit = laid.find((c) => t >= c.start && t < c.start + c.dur);
      if (hit && hit.gap) {
        commit((d) => ({ ...d, main: d.main.map((c) => (c.id === hit.id ? { ...c, gap: false, asset: assetId, in: 0, dur: src, vol: 0 } : c)) }));
        setSel({ type: "clip", id: hit.id });
        return say(`已填入段 ${drSegNo(edSegOf(hit))} 的空缺 · 时长按素材 ${edSecsLabel(src)}，后面片段顺延`);
      }
      let index = laid.findIndex((c) => t < c.start + c.dur / 2);
      if (index < 0) index = laid.length;
      commit((d) => ({ ...d, main: [...d.main.slice(0, index), { id, asset: assetId, in: 0, dur: src, vol: 0 }, ...d.main.slice(index)] }));
      setSel({ type: "clip", id });
      return say(`已插入主轨 · 后面的片段顺延 ${edSecsLabel(src)}`);
    }
    const start = edSnapFrame(t);
    const others = doc.clips.filter((c) => c.track === trackId);
    if (others.some((c) => start >= c.start && start < c.start + c.dur)) return say("这里已有片段，换个空处或换一条轨");
    const next = Math.min(Infinity, ...others.filter((c) => c.start > start).map((c) => c.start));
    const dur = Math.min(src, next - start);
    commit((d) => ({ ...d, clips: [...d.clips, { id, track: trackId, asset: assetId, start, in: 0, dur, vol: 0, ...(track.kind === "video" ? { opacity: 100 } : {}) }] }));
    setSel({ type: "clip", id });
    say(`已放到${track.name} ${track.id} · ${edTc(start)}`);
  };
  // 素材「＋」:放到播放头。视频进主轨,图片进叠加,音频找第一条播放头处空着的音频轨。
  const addAtPlayhead = (assetId) => {
    const a = spAsset(assetId);
    if (a.type === "video") return place(assetId, "V1", playhead);
    if (a.type === "image") return place(assetId, "V2", playhead);
    const free = tracks.find((t) => t.kind === "audio" && !t.locked && !doc.clips.some((c) => c.track === t.id && playhead >= c.start && playhead < c.start + c.dur));
    if (!free) return say("播放头处的音频轨都占满了，先加一条音频轨");
    place(assetId, free.id, playhead);
  };
  const replace = (assetId) => {
    const c = doc.main.find((x) => x.id === replaceFor);
    if (!c) return;
    const src = edSrcSecs(assetId);
    patchClip(c.id, { gap: false, asset: assetId, in: 0, speed: 1, dur: src ? (c.gap ? src : Math.min(c.dur, src)) : c.dur, vol: c.vol || 0 });
    setReplaceFor(null);
    setPanel("props");
    setSel({ type: "clip", id: c.id });
    say(c.gap ? `已填入空缺 · ${spAsset(assetId).name}` : `已替换为 ${spAsset(assetId).name} · 时长不变`);
  };
  const toggleTrack = (id, key) => setTracks((ts) => ts.map((t) => (t.id === id ? { ...t, [key]: !t[key] } : t)));
  const addTrack = () => {
    const n = tracks.filter((t) => t.kind === "audio").length + 1;
    setTracks((ts) => [...ts, { id: "A" + n, kind: "audio", name: "音频", icon: "waveform", role: "sfx" }]);
    say(`已添加音频轨 A${n}`);
  };
  const selectClip = (c) => {
    setSel({ type: "clip", id: c.id });
    setPanel("props");
    const lc = laid.find((x) => x.id === c.id) || c;
    seek(lc.start + 0.01);
  };
  const askAI = (text) => {
    setChatOpen(true);
    say(`已发到右侧对话：「${text}」`);
  };

  // AI 改动(已生效,可回退):字幕轨里助手写入的 + 配乐的对白处压低。
  const aiSubs = doc.clips.filter((c) => c.ai);
  const changes = [
    ...(aiSubs.length ? [{ key: "subs", title: `字幕 · ${aiSubs.length} 条`, sub: "字幕轨 T1", change: "create" }] : []),
    ...(doc.aiDuck ? [{ key: "duck", title: "音乐 · 古琴 · 夜泊", sub: "对白处压低 8 dB", change: "rewrite" }] : []),
  ];
  const revert = (ch) => {
    if (ch.key === "subs") commit((d) => ({ ...d, clips: d.clips.filter((c) => !c.ai) }));
    if (ch.key === "duck") commit((d) => ({ ...d, aiDuck: false, clips: d.clips.map((c) => (c.id === "m1" ? { ...c, duck: false } : c)) }));
    say(`已回退「${ch.title}」`);
  };

  // 键盘:空格播放、S 分割、⌫ 删除、⌘Z / ⇧⌘Z、←→ 逐帧。焦点在输入框里时不拦截。
  const keyRef = React.useRef();
  keyRef.current = { togglePlay, split, remove, undo, redo, seek, playhead };
  React.useEffect(() => {
    const onKey = (e) => {
      const tag = (e.target.tagName || "").toLowerCase();
      if (tag === "input" || tag === "textarea") return;
      const k = keyRef.current;
      if (e.repeat && e.key !== "ArrowLeft" && e.key !== "ArrowRight") return;
      if (e.key === " ") { e.preventDefault(); k.togglePlay(); }
      else if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "z") { e.preventDefault(); e.shiftKey ? k.redo() : k.undo(); }
      else if (e.key === "s" || e.key === "S") k.split();
      else if (e.key === "Backspace" || e.key === "Delete") k.remove();
      else if (e.key === "ArrowLeft") k.seek(k.playhead - 1 / ED_FPS);
      else if (e.key === "ArrowRight") k.seek(k.playhead + 1 / ED_FPS);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  // 时间线高度:拖分隔条。
  const dragSplit = (e) => {
    const y0 = e.clientY;
    const h0 = tlH;
    const mv = (ev) => setTlH(Math.max(220, Math.min(window.innerHeight - 320, h0 - (ev.clientY - y0))));
    const up = () => { window.removeEventListener("pointermove", mv); window.removeEventListener("pointerup", up); };
    window.addEventListener("pointermove", mv);
    window.addEventListener("pointerup", up);
  };

  const curMain = laid.find((c) => playhead >= c.start && playhead < c.start + c.dur);
  const railScene = curMain ? edSceneOf(curMain) : null;
  const pvLabel = curMain ? (curMain.gap ? `段 ${drSegNo(edSegOf(curMain))} · 空缺` : `${edClipLabel(curMain)} · ${spAsset(curMain.asset).name.replace(/^段 [\d-]+ · /, "")}`) : "结尾";
  const ctxLabel = sel && sel.type === "clip" && selClip ? edClipLabel(selClip) : sel && sel.type === "trans" ? "转场" : null;

  return (
    <div className="m-editor-page dr-page ed-page">
      <NavRail activeId="production" screenplay hrefBase="../" collapsed={!ctxOpen} onExpand={() => setCtxOpen(true)}
        onSelect={(id) => drGoEditor(id)} onOpenSettings={() => say("设置在主窗口打开")} />
      {ctxOpen && (
        <DrEpisodeRail sceneId={railScene}
          onCollapse={() => setCtxOpen(false)} onBack={() => (window.location.href = "Drama.html")}
          onSelectEp={(e) => (e.id === DR_EPISODE.id ? null : say(`切到 ${e.label} · mockup 只有 ${DR_EPISODE.label} 的剪辑数据`))}
          onSelectScene={(sceneId) => {
            const c = laid.find((x) => edSceneOf(x) === sceneId);
            const sc = SP_SCENES.find((s) => s.id === sceneId);
            if (!c) return say(`第 ${sc.no} 场还没有导入片段`);
            seek(c.start);
          }} />
      )}

      <div className="dr-main ed-main">
        <div className="sp-top ed-top">
          {/* 位置(作品 › 制片 › 剪辑 · 集名)由工作区面包屑显示,这里只留关闭和保存状态。 */}
          <a className="cv-iconbtn" href="Drama.html" title="关闭"><CvIcon name="x" size={15} /></a>
          <span className="ed-top__saved"><CvIcon name="check" size={12} />已保存</span>
          <span className="sp-top__spacer" />
          <span className="ed-spec" title="跟随剧本设置，在制片页顶栏修改">
            <CvIcon name="frame-corners" size={13} />{DR_SPEC.ratio} · {DR_SPEC.res} · {ED_FPS} fps
          </span>
          <span className="dr-top__sep" />
          <button type="button" className="cv-btn cv-btn--primary" onClick={() => { setPlaying(false); setDlg({ type: "export" }); }}>
            <CvIcon name="download-simple" size={14} />导出
          </button>
        </div>

        <div className="ed-upper">
          <div className="ed-viewer">
            <EdPreview main={doc.main} clips={doc.clips} transitions={doc.transitions} tracks={tracks} t={playhead} ratio={DR_SPEC.ratio} />
            <EdTransport t={playhead} total={total} playing={playing} onPlay={togglePlay} onPrev={prevCut} onNext={nextCut} label={pvLabel} />
          </div>
          <aside className="ed-side">
            <div className="ed-side__tabs">
              <DrSeg value={panel} onChange={(v) => { setPanel(v); if (v === "props") setReplaceFor(null); }}
                options={[{ value: "props", label: "属性" }, { value: "bin", label: "素材" }]} />
            </div>
            <div className="ed-side__body">
              {panel === "props" ? (
                <EdInspector sel={sel} doc={doc} tracks={tracks} total={total} spec={DR_SPEC}
                  onPatch={patchClip} onPatchTrans={patchTrans} onSelectClip={selectClip} onAskAI={askAI}
                  onReplace={(id) => { setReplaceFor(id); setPanel("bin"); }} />
              ) : (
                <EdBin doc={doc} replaceFor={replaceFor} onAdd={addAtPlayhead} onReplace={replace}
                  onCancelReplace={() => { setReplaceFor(null); setPanel("props"); }}
                  onImport={() => say("已上传 · 存进资产库")} />
              )}
            </div>
          </aside>
        </div>

        <div className="ed-splitter" onPointerDown={dragSplit} title="拖动调整时间线高度" />

        <div className="ed-tl" style={{ height: tlH }}>
          <EdTimelineBar canUndo={hist.past.length > 0} canRedo={hist.future.length > 0} onUndo={undo} onRedo={redo}
            canSplit={!!splitTarget()} onSplit={split} canDelete={!!selClip || (sel && sel.type === "trans")} onDelete={remove}
            snapOn={snapOn} onSnap={() => setSnapOn(!snapOn)} pps={pps || 12}
            onZoom={(v) => setPps(Math.min(90, Math.max(6, v)))} onFit={() => fit()} onAddTrack={addTrack} />
          <EdTimeline tracks={tracks} main={doc.main} clips={doc.clips} transitions={doc.transitions}
            pps={pps || 12} playhead={playhead} playing={playing} sel={sel} snapOn={snapOn}
            onSeek={seek} onSelect={(s) => { setSel(s); if (s) { setPanel("props"); setReplaceFor(null); } }}
            onMove={move} onReorder={reorder} onTrim={trim} onToggleTrack={toggleTrack}
            onDropAsset={place} onAskSubs={() => askAI("按对白轨生成字幕")} onViewport={setLaneW} onToast={say} />
        </div>
        {toast && <div className="dr-toast ed-toast">{toast}</div>}
      </div>

      {chatOpen
        ? <EdChatPanel context={ctxLabel} changes={changes} onRevert={revert} onRevertAll={() => changes.forEach(revert)} onClose={() => setChatOpen(false)} />
        : <DrChatRail onExpand={() => setChatOpen(true)} />}

      {dlg && dlg.type === "export" && (
        <EdExportDialog doc={doc} tracks={tracks} spec={DR_SPEC} total={total} initialState={dlg.state}
          onClose={() => setDlg(null)} onGoClip={(c) => { setDlg(null); selectClip(c); }} />
      )}
    </div>
  );
}

function EditingEntry() {
  return (
    <WindowFrame>
      <div className="m-app">
        <EditingPage />
      </div>
    </WindowFrame>
  );
}

Object.assign(window, { EditingPage, EditingEntry });
