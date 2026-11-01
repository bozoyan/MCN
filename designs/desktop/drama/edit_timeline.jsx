// edit_timeline.jsx — 多轨时间线:工具条、刻度、轨道头、片段、转场点、播放头;拖动 / 裁剪 / 拖入素材。
// 拖动过程只在本组件里预览,松手才把结果交给 editing.jsx 提交(一次拖动 = 一步撤销)。
//   主轨 V1   磁吸:拖动改顺序,裁剪让后面的片段跟着前移;空缺只能改长短
//   其他轨道  自由摆放,吸附到播放头和各片段边缘;同一轨内不能重叠;音频片段可以换到别的音频轨
// 关联文件: drama/editing.jsx, drama/edit_data.jsx, drama/edit_panels.jsx, drama/editing.css

const ED_HEAD_W = 150;
const ED_RULER_H = 38;
function edRowH(t) {
  if (t.main) return 64;
  return t.kind === "text" ? 32 : t.kind === "video" ? 46 : 42;
}

/* ---------------- 波形 / 胶片条 ---------------- */
// 波形按源时间取样,裁剪时同一处声音的形状不变。
function edNoise(seed, k) {
  let h = 2166136261;
  const s = seed + ":" + k;
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return ((h >>> 0) % 1000) / 1000;
}
function edWavePath(c, w, h, pps, role) {
  const step = 3;
  const mid = h / 2;
  let d = "";
  for (let x = 1; x < w; x += step) {
    const src = (c.in || 0) + x / pps;
    const k = Math.floor(src * 10);
    let a = edNoise(c.asset || c.id, k);
    if (role === "dialogue") a = 0.25 + a * 0.75 * (0.6 + 0.4 * Math.sin(src * 9));
    else if (role === "music") a = 0.35 + 0.4 * a + 0.2 * Math.sin(src * 1.3);
    else a = 0.2 + a * 0.6;
    const amp = Math.max(1, a * (mid - 3));
    d += `M${x},${(mid - amp).toFixed(1)}V${(mid + amp).toFixed(1)}`;
  }
  return d;
}
// 音量包络:0 dB 在 30% 高度,-30 dB 贴底;对白处压低(duck)画成凹口。
function edEnvPath(c, w, h, pps, duckRanges) {
  const y = (db) => Math.min(h - 2, Math.max(2, h * 0.3 + (-db / 30) * h * 0.65));
  const base = c.vol || 0;
  const pts = [[0, y(base - (c.fadeIn ? 30 : 0))]];
  if (c.fadeIn) pts.push([c.fadeIn * pps, y(base)]);
  if (c.duck) {
    duckRanges.forEach(([a, b]) => {
      const xa = (a - c.start) * pps;
      const xb = (b - c.start) * pps;
      if (xb < 0 || xa > w) return;
      pts.push([Math.max(0, xa - 6), y(base)], [Math.max(0, xa), y(base - 8)], [Math.min(w, xb), y(base - 8)], [Math.min(w, xb + 6), y(base)]);
    });
  }
  if (c.fadeOut) pts.push([w - c.fadeOut * pps, y(base)]);
  pts.push([w, y(base - (c.fadeOut ? 30 : 0))]);
  return "M" + pts.map(([px, py]) => `${px.toFixed(1)},${py.toFixed(1)}`).join("L");
}

function EdFilmstrip({ c, w, h }) {
  const tone = edClipTone(c);
  const tw = Math.max(18, Math.round(h * 9 / 16));
  const n = Math.min(90, Math.ceil(w / tw) + 1);
  return (
    <span className="ed-strip">
      {Array.from({ length: n }).map((_, i) => (
        <span key={i} className={`dr-frame dr-frame--${tone} ed-strip__tile`} style={{ width: tw, height: h, filter: i % 3 === 1 ? "brightness(1.08)" : i % 3 === 2 ? "brightness(.92)" : undefined }}>
          {h > 40 && <span className="dr-frame__figs"><span className="dr-frame__fig" /><span className="dr-frame__fig" /></span>}
        </span>
      ))}
    </span>
  );
}

/* ---------------- 片段 ---------------- */
function EdClip({ c, track, x, w, h, pps, selected, dragging, invalid, locked, duckRanges, onDown, onTrim }) {
  const a = c.asset && spAsset(c.asset);
  const seg = edSegOf(c);
  const kind = c.gap ? "gap" : track.kind === "text" ? "text" : track.kind === "audio" ? "audio" : a && a.type === "image" ? "image" : "video";
  const cls = "ed-clip ed-clip--" + kind + (track.role ? " ed-clip--" + track.role : "") +
    (selected ? " is-sel" : "") + (dragging ? " is-drag" : "") + (invalid ? " is-invalid" : "") + (locked ? " is-locked" : "");
  const ih = h - 2;
  return (
    <div className={cls} style={{ left: x, width: Math.max(4, w), height: h }} onPointerDown={onDown}
      title={edClipLabel(c) + " · " + edSecsLabel(c.dur)}>
      {(kind === "video" || kind === "image") && <EdFilmstrip c={c} w={w} h={ih} />}
      {kind === "gap" && <span className="ed-clip__gap" />}
      {kind === "audio" && (
        <svg className="ed-clip__svg" width={w} height={ih}>
          <path className="ed-wave" d={edWavePath(c, w, ih, pps, track.role)} />
          <path className="ed-env" d={edEnvPath(c, w, ih, pps, duckRanges)} />
        </svg>
      )}
      {(kind === "video" || kind === "image") && (c.fadeIn || c.fadeOut) && (
        <svg className="ed-clip__svg" width={w} height={ih}>
          {c.fadeIn ? <polygon className="ed-fade" points={`0,0 ${c.fadeIn * pps},0 0,${ih}`} /> : null}
          {c.fadeOut ? <polygon className="ed-fade" points={`${w},0 ${w - c.fadeOut * pps},0 ${w},${ih}`} /> : null}
        </svg>
      )}
      <span className="ed-clip__label">
        {seg && !c.gap && <span className="ed-clip__no">段 {drSegNo(seg)}</span>}
        {w > 44 && kind === "text" && c.style === "title" && <CvIcon name="text-t" size={11} />}
        {w > 44 && c.ai && <CvIcon name="sparkle" size={10} color="var(--accent)" />}
        <span className="ed-clip__name">
          {c.gap ? `段 ${drSegNo(seg)} · ${seg.title} · 未采用` : seg ? seg.title : edClipLabel(c)}
        </span>
        {kind === "image" && <span className="ed-clip__meta">{c.opacity != null ? c.opacity + "%" : ""}</span>}
        {kind === "video" && track.id !== "V1" && c.opacity != null && <span className="ed-clip__meta">{c.opacity}%</span>}
        {c.duck && <span className="ed-clip__meta">对白处压低</span>}
      </span>
      {w > 56 && kind !== "text" && <span className="ed-clip__dur">{edSecsLabel(c.dur)}</span>}
      {!locked && (
        <React.Fragment>
          <span className="ed-clip__handle ed-clip__handle--l" onPointerDown={(e) => onTrim(e, "l")} />
          <span className="ed-clip__handle ed-clip__handle--r" onPointerDown={(e) => onTrim(e, "r")} />
        </React.Fragment>
      )}
    </div>
  );
}

/* ---------------- 轨道头 ---------------- */
function EdTrackHead({ t, h, onToggle, onAskSubs }) {
  const audio = t.kind === "audio";
  return (
    <div className={"ed-thead" + (t.main ? " ed-thead--main" : "")} style={{ height: h }}>
      <span className="ed-thead__name">
        <CvIcon name={t.icon} size={13} />
        <span>{t.name}</span>
        <span className="ed-thead__id">{t.id}</span>
      </span>
      <span className="ed-thead__btns">
        {t.main && <span className="ed-thead__tag" title="主轨磁吸：片段首尾相接，删除或裁剪后自动前移"><CvIcon name="magnet" size={12} /></span>}
        {t.kind === "text" && (
          <button type="button" className="ed-tbtn" title="让助手按对白生成字幕" onClick={onAskSubs}><CvIcon name="sparkle" size={12} /></button>
        )}
        <button type="button" className={"ed-tbtn" + (t.locked ? " is-on" : "")} title={t.locked ? "解锁" : "锁定"} onClick={() => onToggle(t.id, "locked")}>
          <CvIcon name="lock-simple" size={12} />
        </button>
        {audio ? (
          <button type="button" className={"ed-tbtn" + (t.muted ? " is-on" : "")} title={t.muted ? "取消静音" : "静音"} onClick={() => onToggle(t.id, "muted")}>
            <CvIcon name={t.muted ? "speaker-slash" : "speaker-high"} size={12} />
          </button>
        ) : (
          <button type="button" className={"ed-tbtn" + (t.hidden ? " is-on" : "")} title={t.hidden ? "显示" : "隐藏"} onClick={() => onToggle(t.id, "hidden")}>
            <CvIcon name={t.hidden ? "eye-slash" : "eye"} size={12} />
          </button>
        )}
      </span>
    </div>
  );
}

/* ---------------- 工具条 ---------------- */
function EdTimelineBar({ canUndo, canRedo, onUndo, onRedo, canSplit, onSplit, canDelete, onDelete, snapOn, onSnap, pps, onZoom, onFit, onAddTrack }) {
  return (
    <div className="ed-tlbar">
      <button type="button" className="cv-iconbtn" title="撤销 ⌘Z" disabled={!canUndo} onClick={onUndo}><CvIcon name="arrow-counter-clockwise" size={15} /></button>
      <button type="button" className="cv-iconbtn" title="重做 ⇧⌘Z" disabled={!canRedo} onClick={onRedo}><CvIcon name="arrow-clockwise" size={15} /></button>
      <span className="ed-tlbar__sep" />
      <button type="button" className="cv-btn" title="在播放头处分割 S" disabled={!canSplit} onClick={onSplit}><CvIcon name="scissors" size={14} />分割</button>
      <button type="button" className="cv-btn" title="删除 ⌫" disabled={!canDelete} onClick={onDelete}><CvIcon name="trash-simple" size={14} />删除</button>
      <span className="ed-tlbar__sep" />
      <button type="button" className={"cv-iconbtn" + (snapOn ? " is-on" : "")} title={snapOn ? "吸附：开" : "吸附：关"} onClick={onSnap}><CvIcon name="magnet" size={15} /></button>
      <button type="button" className="cv-btn" title="添加音频轨" onClick={onAddTrack}><CvIcon name="plus" size={13} />音频轨</button>
      <span className="cv-spacer" />
      <button type="button" className="cv-iconbtn" title="缩小" onClick={() => onZoom(pps / 1.4)}><CvIcon name="minus" size={14} /></button>
      <input className="ed-zoom" type="range" min={Math.log(6)} max={Math.log(90)} step={0.01} value={Math.log(pps)}
        onChange={(e) => onZoom(Math.exp(Number(e.target.value)))} title="时间线缩放" />
      <button type="button" className="cv-iconbtn" title="放大" onClick={() => onZoom(pps * 1.4)}><CvIcon name="plus" size={14} /></button>
      <button type="button" className="cv-iconbtn" title="适应宽度" onClick={onFit}><CvIcon name="arrows-in" size={14} /></button>
    </div>
  );
}

/* ---------------- 时间线 ---------------- */
function EdTimeline(props) {
  const { tracks, main, clips, transitions, pps, playhead, playing, sel, snapOn,
    onSeek, onSelect, onMove, onReorder, onTrim, onToggleTrack, onDropAsset, onAskSubs, onViewport, onToast } = props;
  const scrollRef = React.useRef(null);
  const contentRef = React.useRef(null);
  const laneRefs = React.useRef({});
  const [drag, setDrag] = React.useState(null);
  const [dropHint, setDropHint] = React.useState(null);
  const dragRef = React.useRef(null);
  const P = React.useRef(props);
  P.current = props;

  const laid = edLayoutMain(main);
  const total = edTotal(main, clips);
  const [vw, setVw] = React.useState(800);
  React.useEffect(() => {
    const el = scrollRef.current;
    const ro = new ResizeObserver(() => {
      setVw(el.clientWidth);
      onViewport(el.clientWidth - ED_HEAD_W);
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  const contentW = Math.max(vw, ED_HEAD_W + (total + 8) * pps);

  // 播放时播放头跑出可视区就翻页跟上。
  React.useEffect(() => {
    if (!playing || !scrollRef.current) return;
    const el = scrollRef.current;
    const x = ED_HEAD_W + playhead * pps;
    if (x > el.scrollLeft + el.clientWidth - 40) el.scrollLeft = x - ED_HEAD_W - 40;
    if (x < el.scrollLeft + ED_HEAD_W) el.scrollLeft = Math.max(0, x - ED_HEAD_W - 40);
  }, [playhead, playing]);

  const tAt = (clientX) => {
    const r = contentRef.current.getBoundingClientRect();
    return Math.max(0, (clientX - r.left - ED_HEAD_W) / P.current.pps);
  };

  // 吸附候选:0、播放头、主轨衔接点、其他片段首尾。阈值 8px。
  const snapCands = (excludeId) => {
    const { main: m, clips: cs, playhead: ph } = P.current;
    const out = [0, ph];
    edLayoutMain(m).forEach((c) => c.id !== excludeId && out.push(c.start, c.start + c.dur));
    cs.forEach((c) => c.id !== excludeId && out.push(c.start, c.start + c.dur));
    return out;
  };
  const snapOne = (t, cands) => {
    if (!P.current.snapOn) return { t, at: null };
    const thr = 8 / P.current.pps;
    let best = null;
    cands.forEach((c) => {
      if (Math.abs(c - t) <= thr && (best === null || Math.abs(c - t) < Math.abs(best - t))) best = c;
    });
    return best === null ? { t, at: null } : { t: best, at: best };
  };
  const neighbors = (trackId, id, start) => {
    const others = P.current.clips.filter((c) => c.track === trackId && c.id !== id);
    const prevEnd = Math.max(0, ...others.filter((c) => c.start + c.dur <= start + 0.001).map((c) => c.start + c.dur));
    const nexts = others.filter((c) => c.start >= start - 0.001).map((c) => c.start);
    return { prevEnd, nextStart: nexts.length ? Math.min(...nexts) : Infinity };
  };
  const overlaps = (trackId, id, start, dur) => P.current.clips.some((c) => c.track === trackId && c.id !== id && c.start < start + dur - 0.001 && start < c.start + c.dur - 0.001);
  const rowAt = (clientY) => {
    const hit = Object.entries(laneRefs.current).find(([, el]) => {
      if (!el) return false;
      const r = el.getBoundingClientRect();
      return clientY >= r.top && clientY < r.bottom;
    });
    return hit ? P.current.tracks.find((t) => t.id === hit[0]) : null;
  };

  const compute = (d, e) => {
    const dx = e.clientX - d.x0;
    const moved = d.moved || Math.abs(dx) > 3 || Math.abs(e.clientY - d.y0) > 3;
    const dt = dx / P.current.pps;
    const o = d.orig;
    if (d.mode === "scrub") {
      P.current.onSeek(edSnapFrame(tAt(e.clientX)));
      return d;
    }
    if (d.mode === "move") {
      const cands = snapCands(o.id);
      const raw = Math.max(0, o.start + dt);
      const a = snapOne(raw, cands);
      const b = snapOne(raw + o.dur, cands);
      let start = raw;
      let at = null;
      if (a.at !== null && (b.at === null || Math.abs(a.t - raw) <= Math.abs(b.t - raw - o.dur))) { start = a.t; at = a.at; }
      else if (b.at !== null) { start = b.t - o.dur; at = b.at; }
      start = edSnapFrame(Math.max(0, start));
      const row = rowAt(e.clientY);
      const srcTrack = edTrackOf(P.current.tracks, o.track);
      const track = row && row.kind === srcTrack.kind && !row.main && !row.locked ? row.id : d.track;
      return { ...d, moved, start, track, snapAt: at, invalid: overlaps(track, o.id, start, o.dur) };
    }
    if (d.mode === "main") {
      const others = edLayoutMain(P.current.main.filter((c) => c.id !== o.id));
      const center = o.start + dt + o.dur / 2;
      let index = others.length;
      for (let i = 0; i < others.length; i++) {
        if (center < others[i].start + others[i].dur / 2) { index = i; break; }
      }
      return { ...d, moved, x: Math.max(0, o.start + dt), index };
    }
    // trim
    const cands = snapCands(o.id);
    const src = o.gap ? null : edSrcSecs(o.asset);
    let patch;
    let at = null;
    if (d.main) {
      if (o.gap) {
        patch = { dur: Math.min(60, Math.max(0.5, o.dur + (d.edge === "r" ? dt : -dt))) };
      } else if (d.edge === "l") {
        const nin = Math.min(o.in + o.dur - 0.5, Math.max(0, o.in + dt));
        patch = { in: nin, dur: o.dur - (nin - o.in) };
      } else {
        const s = snapOne(o.start + o.dur + dt, cands);
        at = s.at;
        const max = src ? src - o.in : 60;
        patch = { dur: Math.min(max, Math.max(0.5, s.t - o.start)) };
      }
    } else {
      const { prevEnd, nextStart } = neighbors(o.track, o.id, o.start);
      if (d.edge === "l") {
        const lo = Math.max(prevEnd, o.in != null && src ? o.start - o.in : 0, 0);
        const s = snapOne(o.start + dt, cands);
        at = s.at;
        const ns = Math.min(o.start + o.dur - 0.5, Math.max(lo, s.t));
        patch = { start: ns, dur: o.dur - (ns - o.start), ...(o.in != null ? { in: o.in + (ns - o.start) } : {}) };
      } else {
        const hi = Math.min(nextStart, src ? o.start + (src - (o.in || 0)) : Infinity);
        const s = snapOne(o.start + o.dur + dt, cands);
        at = s.at;
        const ne = Math.max(o.start + 0.5, Math.min(hi, s.t));
        patch = { dur: ne - o.start };
      }
    }
    Object.keys(patch).forEach((k) => (patch[k] = edSnapFrame(patch[k])));
    const atLimit = src && (d.edge === "r" ? (patch.dur >= (src - (patch.in != null ? patch.in : o.in)) - 0.01) : (patch.in != null && patch.in <= 0.01));
    return { ...d, moved, patch, snapAt: at, atLimit };
  };

  const finish = (d) => {
    if (!d || d.mode === "scrub") return;
    if (!d.moved) return;
    const o = d.orig;
    if (d.mode === "move") {
      if (d.invalid) return onToast("这里已有片段，同一轨内不能重叠");
      if (d.start !== o.start || d.track !== o.track) onMove(o.id, { start: d.start, track: d.track });
    } else if (d.mode === "main") {
      const from = P.current.main.findIndex((c) => c.id === o.id);
      if (d.index !== from) onReorder(o.id, d.index);
    } else if (d.patch) {
      onTrim(o.id, d.patch, d.main);
    }
  };

  React.useEffect(() => {
    if (!drag) return;
    const move = (e) => {
      const next = compute(dragRef.current, e);
      dragRef.current = next;
      setDrag(next);
    };
    const up = () => {
      finish(dragRef.current);
      dragRef.current = null;
      setDrag(null);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
    return () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
    };
  }, [!!drag]);

  const begin = (e, d) => {
    e.stopPropagation();
    if (e.button !== 0) return;
    e.preventDefault();
    const next = { x0: e.clientX, y0: e.clientY, moved: false, ...d };
    dragRef.current = next;
    setDrag(next);
  };
  const scrub = (e) => {
    if (e.button !== 0) return;
    onSeek(edSnapFrame(tAt(e.clientX)));
    begin(e, { mode: "scrub" });
  };

  // 拖动中的预览:主轨重排 / 裁剪,其他轨移动 / 裁剪。
  let viewMain = laid;
  let viewClips = clips;
  if (drag && drag.moved) {
    const o = drag.orig;
    if (drag.mode === "main") {
      const rest = main.filter((c) => c.id !== o.id);
      viewMain = edLayoutMain([...rest.slice(0, drag.index), o, ...rest.slice(drag.index)]);
    } else if (drag.mode === "trim" && drag.patch && drag.main) {
      viewMain = edLayoutMain(main.map((c) => (c.id === o.id ? { ...c, ...drag.patch } : c)));
    } else if (drag.mode === "trim" && drag.patch) {
      viewClips = clips.map((c) => (c.id === o.id ? { ...c, ...drag.patch } : c));
    } else if (drag.mode === "move") {
      viewClips = clips.map((c) => (c.id === o.id ? { ...c, start: drag.start, track: drag.track } : c));
    }
  }
  const duckRanges = viewClips.filter((c) => c.track === "A1").map((c) => [c.start, c.start + c.dur]);
  const isSel = (id) => sel && sel.type === "clip" && sel.id === id;

  // 刻度:按缩放挑标注间隔。
  const labelEvery = pps < 9 ? 10 : pps < 20 ? 5 : pps < 45 ? 2 : 1;
  const tickEvery = labelEvery >= 5 ? 1 : labelEvery === 2 ? 0.5 : 0.25;
  const labels = [];
  for (let t = 0; t * pps < contentW; t += labelEvery) labels.push(t);
  const sceneMarks = [];
  viewMain.forEach((c, i) => {
    const sc = edSceneOf(c);
    if (sc && (i === 0 || edSceneOf(viewMain[i - 1]) !== sc)) sceneMarks.push({ t: c.start, sc: SP_SCENES.find((s) => s.id === sc) });
  });

  const lanesH = tracks.reduce((s, t) => s + edRowH(t), 0);
  const trimTip = drag && drag.mode === "trim" && drag.moved && drag.patch;
  const tipClip = trimTip && (drag.main ? viewMain : viewClips).find((c) => c.id === drag.orig.id);
  const tipTrack = trimTip && (drag.main ? tracks.find((t) => t.main) : tracks.find((t) => t.id === drag.orig.track));
  const rowTop = (trackId) => {
    let y = 0;
    for (const t of tracks) {
      if (t.id === trackId) return y;
      y += edRowH(t);
    }
    return y;
  };

  return (
    <div className="ed-tl__scroll" ref={scrollRef}>
      <div className="ed-tl__content" ref={contentRef} style={{ width: contentW }}>
        {/* 刻度 */}
        <div className="ed-ruler-row" style={{ height: ED_RULER_H }}>
          <div className="ed-corner" style={{ width: ED_HEAD_W }}>
            <span className="ed-corner__tc">{edTc(playhead)}</span>
          </div>
          <div className="ed-ruler" onPointerDown={scrub}
            style={{ backgroundImage: `repeating-linear-gradient(90deg, var(--border-input) 0 1px, transparent 1px ${tickEvery * pps}px)` }}>
            {labels.map((t) => (
              <span key={t} className="ed-ruler__label" style={{ left: t * pps }}>{`${Math.floor(t / 60)}:${String(t % 60).padStart(2, "0")}`}</span>
            ))}
            {sceneMarks.map(({ t, sc }) => (
              <span key={sc.id} className="ed-ruler__scene" style={{ left: t * pps }} title={`第 ${sc.no} 场 · ${sc.title}`}>
                {sc.no}、{sc.title}
              </span>
            ))}
            <span className="ed-ruler__end" style={{ left: total * pps }} title={`结尾 ${edTc(total)}`} />
            <span className="ed-playhead__knob" style={{ left: playhead * pps }} onPointerDown={scrub} />
          </div>
        </div>

        {/* 轨道 */}
        {tracks.map((t) => {
          const h = edRowH(t);
          const rowClips = t.main ? viewMain : viewClips.filter((c) => c.track === t.id);
          const dh = dropHint && dropHint.track === t.id ? dropHint : null;
          return (
            <div key={t.id} className={"ed-row" + (t.main ? " ed-row--main" : "") + (t.hidden || t.muted ? " is-dim" : "")} style={{ height: h }}>
              <EdTrackHead t={t} h={h} onToggle={onToggleTrack} onAskSubs={onAskSubs} />
              <div className={"ed-lane" + (t.locked ? " is-locked" : "") + (dh ? (dh.ok ? " is-drop" : " is-nodrop") : "")}
                ref={(el) => (laneRefs.current[t.id] = el)}
                onPointerDown={(e) => { onSelect(null); scrub(e); }}
                onDragOver={(e) => {
                  const a = window.__edDragAsset;
                  if (!a) return;
                  e.preventDefault();
                  const ok = !t.locked && edAccepts(t, a);
                  setDropHint({ track: t.id, t: tAt(e.clientX), ok, dur: edSrcSecs(a.id) || 3 });
                }}
                onDragLeave={() => setDropHint(null)}
                onDrop={(e) => {
                  e.preventDefault();
                  setDropHint(null);
                  const a = window.__edDragAsset;
                  if (a) onDropAsset(a.id, t.id, tAt(e.clientX));
                }}>
                {rowClips.map((c) => {
                  const dragging = drag && drag.moved && drag.orig.id === c.id && (drag.mode === "move" || drag.mode === "main");
                  const x = dragging && drag.mode === "main" ? drag.x * pps : c.start * pps;
                  return (
                    <EdClip key={c.id} c={c} track={t} x={x} w={c.dur * pps} h={h - 8} pps={pps}
                      selected={isSel(c.id)} dragging={dragging} invalid={dragging && drag.invalid}
                      locked={t.locked} duckRanges={duckRanges}
                      onDown={(e) => {
                        onSelect({ type: "clip", id: c.id });
                        if (t.locked) return e.stopPropagation();
                        begin(e, { mode: t.main ? "main" : "move", orig: c, track: c.track, start: c.start, x: c.start, index: main.findIndex((m) => m.id === c.id) });
                      }}
                      onTrim={(e, edge) => {
                        onSelect({ type: "clip", id: c.id });
                        begin(e, { mode: "trim", edge, orig: c, main: !!t.main });
                      }} />
                  );
                })}
                {t.main && !drag && viewMain.slice(0, -1).map((c) => {
                  const tr = transitions[c.id];
                  const on = sel && sel.type === "trans" && sel.id === c.id;
                  const set = tr && tr.type !== "none";
                  const label = set ? ED_TRANSITION_TYPES.find((x) => x.value === tr.type).label : "添加转场";
                  return (
                    <button key={"tr-" + c.id} type="button" title={label}
                      className={"ed-trans" + (set ? " is-set" : "") + (on ? " is-on" : "")}
                      style={{ left: (c.start + c.dur) * pps }}
                      onPointerDown={(e) => { e.stopPropagation(); onSelect({ type: "trans", id: c.id }); }}>
                      {set && <span className="ed-trans__w" style={{ width: Math.max(10, tr.dur * pps) }} />}
                      <span className="ed-trans__dot" />
                    </button>
                  );
                })}
                {drag && drag.mode === "main" && drag.moved && (() => {
                  const rest = edLayoutMain(main.filter((c) => c.id !== drag.orig.id));
                  const at = drag.index < rest.length ? rest[drag.index].start : edMainEnd(rest);
                  return <span className="ed-insert" style={{ left: at * pps }} />;
                })()}
                {dh && <span className={"ed-drophint" + (dh.ok ? "" : " is-bad")} style={{ left: dh.t * pps, width: Math.max(16, dh.dur * pps) }} />}
              </div>
            </div>
          );
        })}

        {/* 播放头 / 吸附线 / 裁剪提示 */}
        <span className="ed-playhead" style={{ left: ED_HEAD_W + playhead * pps, top: ED_RULER_H, height: lanesH }} />
        {drag && drag.moved && drag.snapAt != null && (
          <span className="ed-snapline" style={{ left: ED_HEAD_W + drag.snapAt * pps, top: ED_RULER_H, height: lanesH }} />
        )}
        {tipClip && (
          <span className={"ed-trimtip" + (drag.atLimit ? " is-limit" : "")}
            style={{ left: ED_HEAD_W + (drag.edge === "l" ? tipClip.start : tipClip.start + tipClip.dur) * pps, top: ED_RULER_H + rowTop(tipTrack.id) - 4 }}>
            {edSecsLabel(tipClip.dur)}{drag.atLimit ? " · 已到素材边缘" : ""}
          </span>
        )}
      </div>
    </div>
  );
}

function edTrackOf(tracks, id) {
  return tracks.find((t) => t.id === id);
}
// 轨道能接什么素材:主轨 / 叠加接视频和图片,音频轨接音频。字幕轨不接素材。
function edAccepts(track, asset) {
  if (track.kind === "video") return asset.type === "video" || asset.type === "image";
  if (track.kind === "audio") return asset.type === "audio";
  return false;
}

Object.assign(window, { EdTimeline, EdTimelineBar, edAccepts, edTrackOf, ED_HEAD_W });
