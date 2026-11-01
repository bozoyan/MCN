// edit_panels.jsx — 多轨剪辑的周边区域:预览、走带条、右侧「属性 / 素材」、导出弹窗、制作助手。
// 都是展示组件:状态在 editing.jsx,这里只接 props、回调改动。
// 预览按播放头合成:主轨画面 → 转场(叠化 / 黑场 / 闪白)→ 叠加轨(不透明度 + 淡入淡出)→ 字幕;隐藏的轨道不进画面。
// 导出只在本机合成,不调用生成模型、不计费;空缺导出为黑场,静音 / 隐藏的轨道不导出。
// 关联文件: drama/editing.jsx, drama/edit_data.jsx, drama/edit_timeline.jsx, drama/composer.jsx, ChatPanel.jsx

/* ---------------- 预览 ---------------- */
function EdPvFrame({ c, t, opacity = 1, style }) {
  if (!c) return null;
  if (c.gap) {
    const seg = edSegOf(c);
    return (
      <span className="ed-pv__layer ed-pv__gap" style={{ opacity }}>
        <span>段 {drSegNo(seg)} · {seg.title}</span>
        <span className="ed-pv__gapsub">未采用 · 导出为黑场</span>
      </span>
    );
  }
  const p = Math.min(1, Math.max(0, (t - c.start) / c.dur));
  return (
    <span className={`ed-pv__layer dr-frame dr-frame--${edClipTone(c)}`} style={{ opacity, ...style }}>
      <span className="dr-frame__figs" style={{ transform: `translateX(${((p - 0.5) * 14).toFixed(2)}%) scale(${1 + p * 0.06})` }}>
        <span className="dr-frame__fig" /><span className="dr-frame__fig" />
      </span>
    </span>
  );
}

function edFadeAt(c, t) {
  const local = t - c.start;
  let k = 1;
  if (c.fadeIn && local < c.fadeIn) k = Math.min(k, local / c.fadeIn);
  if (c.fadeOut && c.dur - local < c.fadeOut) k = Math.min(k, (c.dur - local) / c.fadeOut);
  return Math.max(0, k);
}

function EdPreview({ main, clips, transitions, tracks, t, ratio }) {
  const laid = edLayoutMain(main);
  const end = edMainEnd(main);
  const cur = laid.find((c) => t >= c.start && t < c.start + c.dur) || null;
  const hidden = (id) => (tracks.find((x) => x.id === id) || {}).hidden;
  // 衔接处的转场:前后各占一半时长。
  let trans = null;
  laid.slice(0, -1).forEach((c, i) => {
    const tr = transitions[c.id];
    if (!tr || tr.type === "none") return;
    const join = c.start + c.dur;
    if (Math.abs(t - join) < tr.dur / 2) trans = { ...tr, p: (t - (join - tr.dur / 2)) / tr.dur, a: c, b: laid[i + 1] };
  });
  const overlays = hidden("V2") ? [] : clips.filter((c) => c.track === "V2" && t >= c.start && t < c.start + c.dur);
  const texts = hidden("T1") ? [] : clips.filter((c) => c.track === "T1" && t >= c.start && t < c.start + c.dur);
  const [rw, rh] = ratio.split(":").map(Number);
  const flash = trans && trans.type !== "dissolve" ? 1 - Math.abs(trans.p - 0.5) * 2 : 0;
  return (
    <div className="ed-pv">
      <div className="ed-pv__frame" style={{ aspectRatio: `${rw} / ${rh}` }}>
        {hidden("V1") ? null : trans && trans.type === "dissolve" ? (
          <React.Fragment>
            <EdPvFrame c={trans.a} t={t} />
            <EdPvFrame c={trans.b} t={t} opacity={trans.p} />
          </React.Fragment>
        ) : (
          <EdPvFrame c={cur} t={t} />
        )}
        {overlays.map((c) => {
          const s = (c.scale || 100) / 100;
          return <EdPvFrame key={c.id} c={c} t={t} opacity={((c.opacity == null ? 100 : c.opacity) / 100) * edFadeAt(c, t)}
            style={s !== 1 ? { inset: "auto", right: "6%", top: "6%", width: `${s * 100}%`, height: `${s * 100}%` } : undefined} />;
        })}
        {flash > 0 && <span className={"ed-pv__layer ed-pv__flash" + (trans.type === "white" ? " is-white" : "")} style={{ opacity: flash }} />}
        {t >= end && <span className="ed-pv__layer ed-pv__end">结尾</span>}
        {texts.map((c) => (
          <span key={c.id} className={"ed-pv__text ed-pv__text--" + c.style + " ed-pv__text--" + (c.pos || "bottom")}>{c.text}</span>
        ))}
      </div>
    </div>
  );
}

function EdTransport({ t, total, playing, onPlay, onPrev, onNext, label }) {
  return (
    <div className="ed-transport">
      <span className="ed-transport__label">{label}</span>
      <span className="ed-transport__btns">
        <button type="button" className="cv-iconbtn" title="上一个剪辑点 ↑" onClick={onPrev}><CvIcon name="skip-back" size={15} /></button>
        <button type="button" className="ed-play" title={playing ? "暂停 空格" : "播放 空格"} onClick={onPlay}>
          <CvIcon name={playing ? "pause" : "play"} size={16} />
        </button>
        <button type="button" className="cv-iconbtn" title="下一个剪辑点 ↓" onClick={onNext}><CvIcon name="skip-forward" size={15} /></button>
      </span>
      <span className="ed-transport__tc"><b>{edTc(t)}</b> / {edTc(total)}</span>
    </div>
  );
}

/* ---------------- 右侧:属性 ---------------- */
function EdRow({ label, children, hint }) {
  return (
    <div className="ed-prow">
      <span className="ed-prow__label">{label}</span>
      <span className="ed-prow__ctl">{children}</span>
      {hint && <span className="ed-prow__hint">{hint}</span>}
    </div>
  );
}
function EdRange({ value, min, max, step = 1, onChange, fmt, disabled }) {
  return (
    <span className="ed-range">
      <input type="range" min={min} max={max} step={step} value={value} disabled={disabled}
        onChange={(e) => onChange(Number(e.target.value))} />
      <span className="ed-range__v">{fmt ? fmt(value) : value}</span>
    </span>
  );
}
function EdSwitch({ on, onChange }) {
  return (
    <button type="button" role="switch" aria-checked={on} className={"ed-switch" + (on ? " is-on" : "")} onClick={() => onChange(!on)}>
      <span />
    </button>
  );
}
const edDb = (v) => (v > 0 ? "+" : "") + v + " dB";
const edSec1 = (v) => v.toFixed(1) + "s";

function EdInspector({ sel, doc, tracks, total, spec, onPatch, onPatchTrans, onReplace, onSelectClip, onAskAI, onSplitHint }) {
  const laid = edLayoutMain(doc.main);
  if (sel && sel.type === "trans") {
    const i = laid.findIndex((c) => c.id === sel.id);
    const a = laid[i];
    const b = laid[i + 1];
    if (!a || !b) return null;
    const tr = doc.transitions[a.id] || { type: "none", dur: 0.5 };
    const name = (c) => (edSegOf(c) ? `段 ${drSegNo(edSegOf(c))}` : edClipLabel(c));
    return (
      <div className="ed-props">
        <div className="ed-props__head">
          <span className="ed-props__title">转场</span>
          <span className="ed-props__sub">{name(a)} → {name(b)} · {edTc(a.start + a.dur)}</span>
        </div>
        <EdRow label="方式">
          <DrSeg value={tr.type} options={ED_TRANSITION_TYPES} onChange={(v) => onPatchTrans(a.id, { ...tr, type: v })} />
        </EdRow>
        <EdRow label="时长">
          <EdRange value={tr.dur} min={0.2} max={1.5} step={0.1} fmt={edSec1} disabled={tr.type === "none"}
            onChange={(v) => onPatchTrans(a.id, { ...tr, dur: v }, "tr-dur-" + a.id)} />
        </EdRow>
        <div className="ed-props__note">转场占衔接处前后各一半，不改变总时长。</div>
      </div>
    );
  }

  const c = sel && sel.type === "clip" && (laid.find((x) => x.id === sel.id) || doc.clips.find((x) => x.id === sel.id));
  if (!c) {
    const gaps = laid.filter((x) => x.gap);
    const n = laid.length + doc.clips.length;
    return (
      <div className="ed-props">
        <div className="ed-props__head">
          <span className="ed-props__title">{DR_EPISODE.label} · {DR_EPISODE.title} · 剪辑</span>
          <span className="ed-props__sub">选中片段或转场可以编辑它</span>
        </div>
        <EdRow label="时长"><span className="ed-mono">{edTc(total)}</span></EdRow>
        <EdRow label="画面"><span>{spec.ratio} · {spec.res} · {ED_FPS} fps</span></EdRow>
        <EdRow label="轨道"><span>{tracks.length} 条 · {n} 个片段</span></EdRow>
        <div className="ed-sec">
          <div className="ed-sec__title">来源</div>
          <div className="ed-props__text">今天 16:40 从制片按成片顺序导入 {laid.filter((x) => x.seg).length} 段，{gaps.length} 段未采用、留作空缺。</div>
          <div className="ed-props__note">剪辑是独立工程：之后在制片里换结果、改时长，不会同步到这里。要用新结果，从「素材」拖到主轨替换。</div>
          {gaps.length > 0 && (
            <div className="ed-chips">
              {gaps.map((g) => (
                <button key={g.id} type="button" className="ed-chip" onClick={() => onSelectClip(g)}>
                  <CvIcon name="warning-circle" size={12} />段 {drSegNo(edSegOf(g))} {edSegOf(g).title}
                </button>
              ))}
            </div>
          )}
        </div>
        <div className="ed-keys">
          <span><kbd>空格</kbd>播放</span><span><kbd>S</kbd>分割</span><span><kbd>⌫</kbd>删除</span><span><kbd>⌘Z</kbd>撤销</span>
        </div>
      </div>
    );
  }

  const track = tracks.find((t) => t.id === c.track);
  const a = c.asset && spAsset(c.asset);
  const seg = edSegOf(c);
  const src = edSrcSecs(c.asset);
  const set = (p, key) => onPatch(c.id, p, key);
  const isMain = track.main;
  const title = c.text ? (c.style === "title" ? "标题" : "字幕") : seg ? `段 ${drSegNo(seg)} · ${seg.title}` : edClipLabel(c);

  const head = (
    <div className="ed-props__head">
      <span className="ed-props__title">
        {c.ai && <CvIcon name="sparkle" size={12} color="var(--accent)" />}
        {title}
      </span>
      <span className="ed-props__sub">
        {track.name} {track.id} · {edTc(c.start)} 起 · {edSecsLabel(c.dur)}
      </span>
    </div>
  );

  if (c.gap) {
    return (
      <div className="ed-props">
        {head}
        <div className="dr-film__block ed-props__block">
          <CvIcon name="warning-circle" size={14} />
          <span>导入时这一段还没有采用结果。导出时这里是黑场。</span>
        </div>
        <EdRow label="时长">
          <EdRange value={c.dur} min={0.5} max={20} step={0.1} fmt={edSec1} onChange={(v) => set({ dur: v }, "dur-" + c.id)} />
        </EdRow>
        <div className="ed-actions">
          <button type="button" className="cv-btn cv-btn--outline" onClick={() => onReplace(c.id)}><CvIcon name="squares-four" size={13} />从素材选择</button>
          <a className="cv-btn" href={`Drama.html?tab=story&seg=${c.seg}`}><CvIcon name="arrow-square-out" size={13} />去制片生成</a>
        </div>
      </div>
    );
  }

  if (track.kind === "text") {
    return (
      <div className="ed-props">
        {head}
        <label className="ed-field">
          <span className="ed-prow__label">文字</span>
          <textarea className="ed-textarea" rows={3} value={c.text} spellCheck={false}
            onChange={(e) => set({ text: e.target.value }, "text-" + c.id)} />
        </label>
        <EdRow label="样式">
          <DrSeg value={c.style} options={[{ value: "sub", label: "字幕" }, { value: "title", label: "标题" }]} onChange={(v) => set({ style: v, pos: v === "title" ? "center" : "bottom" })} />
        </EdRow>
        <EdRow label="位置">
          <DrSeg value={c.pos || "bottom"} options={[{ value: "top", label: "上" }, { value: "center", label: "中" }, { value: "bottom", label: "下" }]} onChange={(v) => set({ pos: v })} />
        </EdRow>
        {c.ai && <div className="ed-props__note">由制作助手按对白写入，文字取自剧本台词，起止对齐对白音频。</div>}
      </div>
    );
  }

  if (track.kind === "audio") {
    return (
      <div className="ed-props">
        {head}
        <div className="ed-src">
          <DrAssetThumb asset={a} h={30} />
          <span className="ed-src__main">
            <span className="ed-src__name">{a.name}</span>
            <span className="ed-src__sub">{a.source} · 用 {edSecsLabel(c.in || 0)}–{edSecsLabel((c.in || 0) + c.dur)}{src ? ` / ${edSecsLabel(src)}` : ""}</span>
          </span>
        </div>
        <EdRow label="音量">
          <EdRange value={c.vol || 0} min={-30} max={6} fmt={edDb} onChange={(v) => set({ vol: v }, "vol-" + c.id)} />
        </EdRow>
        <EdRow label="淡入">
          <EdRange value={c.fadeIn || 0} min={0} max={Math.min(5, c.dur / 2)} step={0.1} fmt={edSec1} onChange={(v) => set({ fadeIn: v }, "fi-" + c.id)} />
        </EdRow>
        <EdRow label="淡出">
          <EdRange value={c.fadeOut || 0} min={0} max={Math.min(5, c.dur / 2)} step={0.1} fmt={edSec1} onChange={(v) => set({ fadeOut: v }, "fo-" + c.id)} />
        </EdRow>
        {track.role !== "dialogue" && (
          <EdRow label="对白处压低" hint="对白轨有声音时自动压低 8 dB，前后各留 0.25 秒过渡">
            <EdSwitch on={!!c.duck} onChange={(v) => set({ duck: v })} />
          </EdRow>
        )}
        {track.role === "dialogue" && (
          <div className="ed-actions">
            <button type="button" className="cv-btn cv-btn--outline" onClick={() => onAskAI("给这句对白配字幕")}><CvIcon name="sparkle" size={13} />配字幕</button>
          </div>
        )}
      </div>
    );
  }

  // 视频 / 图片(主轨或叠加)
  const media = DR_FILM_MEDIA[c.asset];
  const speed = c.speed || 1;
  return (
    <div className="ed-props">
      {head}
      <div className="ed-src">
        <DrAssetThumb asset={a} h={40} ratio="9:16" />
        <span className="ed-src__main">
          <span className="ed-src__name">{a.name}</span>
          <span className="ed-src__sub">{a.source} · {a.spec}</span>
          {src && <span className="ed-src__sub">用 {edSecsLabel(c.in || 0)}–{edSecsLabel((c.in || 0) + c.dur * speed)} / {edSecsLabel(src)}</span>}
        </span>
      </div>
      {a.type === "video" && (
        <EdRow label="速度">
          <DrSeg value={speed} options={[0.5, 1, 1.5, 2].map((v) => ({ value: v, label: v + "×" }))}
            onChange={(v) => {
              const range = c.dur * speed;
              const max = src ? (src - (c.in || 0)) / v : Infinity;
              set({ speed: v, dur: Math.max(0.5, Math.min(max, range / v)) });
            }} />
        </EdRow>
      )}
      {!isMain && (
        <React.Fragment>
          <EdRow label="不透明度">
            <EdRange value={c.opacity == null ? 100 : c.opacity} min={0} max={100} fmt={(v) => v + "%"} onChange={(v) => set({ opacity: v }, "op-" + c.id)} />
          </EdRow>
          <EdRow label="大小">
            <EdRange value={c.scale || 100} min={20} max={100} fmt={(v) => (v === 100 ? "铺满" : v + "%")} onChange={(v) => set({ scale: v }, "sc-" + c.id)} />
          </EdRow>
          <EdRow label="淡入">
            <EdRange value={c.fadeIn || 0} min={0} max={Math.min(3, c.dur / 2)} step={0.1} fmt={edSec1} onChange={(v) => set({ fadeIn: v }, "fi-" + c.id)} />
          </EdRow>
          <EdRow label="淡出">
            <EdRange value={c.fadeOut || 0} min={0} max={Math.min(3, c.dur / 2)} step={0.1} fmt={edSec1} onChange={(v) => set({ fadeOut: v }, "fo-" + c.id)} />
          </EdRow>
        </React.Fragment>
      )}
      {a.type === "video" && (
        <EdRow label="原声" hint={media && media.audio === false ? "这段素材没有声音" : undefined}>
          <EdRange value={c.vol || 0} min={-30} max={6} fmt={edDb} disabled={media && media.audio === false}
            onChange={(v) => set({ vol: v }, "vol-" + c.id)} />
        </EdRow>
      )}
      <div className="ed-actions">
        {isMain && <button type="button" className="cv-btn cv-btn--outline" onClick={() => onReplace(c.id)}><CvIcon name="arrows-clockwise" size={13} />替换素材</button>}
        {seg && <a className="cv-btn" href={`Drama.html?sel=${seg.id}`}><CvIcon name="arrow-square-out" size={13} />在制片中查看</a>}
      </div>
      {seg && <div className="ed-props__note">今天 16:40 导入。之后段 {drSegNo(seg)} 换了结果不会同步到这里，要用新结果就替换素材。</div>}
    </div>
  );
}

/* ---------------- 右侧:素材 ---------------- */
function EdBinItem({ asset, used, replacing, onAdd, onReplace }) {
  return (
    <div className="ed-bin__item" draggable
      onDragStart={(e) => { window.__edDragAsset = asset; e.dataTransfer.setData("text/plain", asset.id); e.dataTransfer.effectAllowed = "copy"; }}
      onDragEnd={() => { window.__edDragAsset = null; }}
      title="拖到时间线上">
      <DrAssetThumb asset={asset} h={34} />
      <span className="ed-bin__main">
        <span className="ed-bin__name">{asset.name}</span>
        <span className="ed-bin__sub">{asset.spec}{used ? ` · 已用 ${used}` : ""}</span>
      </span>
      {replacing
        ? <button type="button" className="cv-btn cv-btn--outline ed-bin__act" onClick={onReplace}>替换</button>
        : <button type="button" className="cv-iconbtn ed-bin__act" title="加到播放头" onClick={onAdd}><CvIcon name="plus" size={14} /></button>}
    </div>
  );
}

function EdBin({ doc, replaceFor, onAdd, onReplace, onCancelReplace, onImport }) {
  const [filter, setFilter] = React.useState(replaceFor ? "video" : "all");
  React.useEffect(() => { if (replaceFor) setFilter("video"); }, [replaceFor]);
  const used = {};
  [...doc.main, ...doc.clips].forEach((c) => c.asset && (used[c.asset] = (used[c.asset] || 0) + 1));
  const segs = drOrderedSegs(DR_NODES);
  const segAssets = new Set(segs.map((n) => n.adopted).filter(Boolean));
  const of = (type) => SP_ASSETS.filter((a) => a.type === type && !segAssets.has(a.id));
  const show = (type) => filter === "all" || filter === type;
  const canReplace = (a) => replaceFor && (a.type === "video" || a.type === "image");
  const item = (a) => (
    <EdBinItem key={a.id} asset={a} used={used[a.id]} replacing={canReplace(a)}
      onAdd={() => onAdd(a.id)} onReplace={() => onReplace(a.id)} />
  );
  return (
    <div className="ed-bin">
      {replaceFor && (
        <div className="ed-bin__replace">
          <CvIcon name="arrows-clockwise" size={13} />
          <span>{doc.main.find((c) => c.id === replaceFor)?.gap ? "填入" : "替换"} {edClipLabel(doc.main.find((c) => c.id === replaceFor))}</span>
          <button type="button" className="cv-iconbtn" title="取消" onClick={onCancelReplace}><CvIcon name="x" size={13} /></button>
        </div>
      )}
      <div className="ed-bin__bar">
        <DrSeg value={filter} onChange={setFilter} options={[
          { value: "all", label: "全部" }, { value: "video", label: "视频" }, { value: "image", label: "图片" }, { value: "audio", label: "音频" },
        ]} />
        <button type="button" className="cv-iconbtn" title="导入文件" onClick={onImport}><CvIcon name="upload" size={14} /></button>
      </div>
      <div className="ed-bin__scroll">
        {show("video") && (
          <React.Fragment>
            <div className="ed-sec__title">片段 · 当前采用</div>
            {segs.map((n) => {
              const a = n.adopted && spAsset(n.adopted);
              if (!a) {
                return (
                  <div key={n.id} className="ed-bin__item is-off">
                    <span className="dr-frame dr-frame--empty" style={{ width: 19, height: 34 }} />
                    <span className="ed-bin__main">
                      <span className="ed-bin__name">段 {drSegNo(n)} · {n.title}</span>
                      <span className="ed-bin__sub">未采用</span>
                    </span>
                    <a className="cv-btn ed-bin__act" href={`Drama.html?tab=story&seg=${n.id}`}>去制片</a>
                  </div>
                );
              }
              return <EdBinItem key={n.id} asset={{ ...a, name: `段 ${drSegNo(n)} · ${n.title}` }} used={used[a.id]} replacing={canReplace(a)}
                onAdd={() => onAdd(a.id)} onReplace={() => onReplace(a.id)} />;
            })}
            <div className="ed-sec__title">其他视频</div>
            {of("video").map(item)}
          </React.Fragment>
        )}
        {show("image") && (
          <React.Fragment>
            <div className="ed-sec__title">图片</div>
            {of("image").map(item)}
          </React.Fragment>
        )}
        {show("audio") && (
          <React.Fragment>
            <div className="ed-sec__title">音频</div>
            {of("audio").map(item)}
          </React.Fragment>
        )}
      </div>
    </div>
  );
}

/* ---------------- 导出 ---------------- */
const ED_EXPORT_STEPS = ["读取素材", "合成画面", "混音", "编码 MP4", "保存"];

function EdExportDialog({ doc, tracks, spec, total, initialState, onClose, onGoClip }) {
  const [phase, setPhase] = React.useState(initialState || "form");
  const [pct, setPct] = React.useState(initialState === "running" ? 46 : 0);
  const [res, setRes] = React.useState(["1080P", "2160P"].includes(spec.res) ? "1080P" : "720P");
  const [fps, setFps] = React.useState(ED_FPS);
  const [subs, setSubs] = React.useState("burn");
  const [name, setName] = React.useState(`Ep${DR_EPISODE.label.replace(/\D/g, "")}-${DR_EPISODE.title}`);
  React.useEffect(() => {
    if (phase !== "running") return;
    const id = window.setInterval(() => setPct((p) => {
      if (p >= 100) { window.clearInterval(id); setPhase("done"); return 100; }
      return Math.min(100, p + 2);
    }), 90);
    return () => window.clearInterval(id);
  }, [phase]);

  const laid = edLayoutMain(doc.main);
  const gaps = laid.filter((c) => c.gap);
  const [w, h] = drFilmSize(spec.ratio, res);
  const muted = tracks.filter((t) => t.muted);
  const hidden = tracks.filter((t) => t.hidden);
  const audioTracks = tracks.filter((t) => t.kind === "audio" && !t.muted);
  const textCount = doc.clips.filter((c) => c.track === "T1").length;
  const mb = Math.round((total * (res === "1080P" ? 3.4 : 1.8)) / 8 + 0.5);
  const step = Math.min(ED_EXPORT_STEPS.length - 1, Math.floor(pct / (100 / ED_EXPORT_STEPS.length)));

  return (
    <div className="dr-modal" onPointerDown={phase === "running" ? undefined : onClose}>
      <div className="dr-dialog ed-export" onPointerDown={(e) => e.stopPropagation()}>
        <div className="dr-dialog__head">
          <span className="dr-dialog__title">导出成片 · {DR_EPISODE.label} {DR_EPISODE.title}</span>
          <span className="dr-dialog__sub">按时间线合成</span>
          <span className="cv-spacer" />
          <button type="button" className="cv-iconbtn" onClick={onClose}><CvIcon name="x" size={15} /></button>
        </div>

        {phase === "form" && (
          <div className="dr-export__body">
            <div className="dr-xrow">
              <span className="dr-xrow__main">
                <span className="dr-xrow__title"><CvIcon name="file-text" size={13} />文件</span>
                <span className="dr-film__sub">~/Movies/{DR_PROJECT.title}/</span>
              </span>
              <span className="ed-filename">
                <input className="cv-input" value={name} spellCheck={false} onChange={(e) => setName(e.target.value)} />
                <span>.mp4</span>
              </span>
            </div>
            <div className="dr-xrow">
              <span className="dr-xrow__main">
                <span className="dr-xrow__title"><CvIcon name="frame-corners" size={13} />画面</span>
                <span className="dr-film__sub">{spec.ratio} 跟随剧本设置 · {w}×{h} · H.264</span>
              </span>
              <DrSeg value={res} onChange={setRes} options={[{ value: "720P", label: "720P" }, { value: "1080P", label: "1080P" }]} />
            </div>
            <div className="dr-xrow">
              <span className="dr-xrow__main">
                <span className="dr-xrow__title"><CvIcon name="film-strip" size={13} />帧率</span>
                <span className="dr-film__sub">素材帧率不同时按这里重采样</span>
              </span>
              <DrSeg value={fps} onChange={setFps} options={[{ value: 24, label: "24 fps" }, { value: 30, label: "30 fps" }]} />
            </div>
            <div className="dr-xrow">
              <span className="dr-xrow__main">
                <span className="dr-xrow__title"><CvIcon name="subtitles" size={13} />字幕</span>
                <span className="dr-film__sub">字幕轨 {textCount} 条{subs === "srt" ? " · 标题仍烧录进画面" : ""}</span>
              </span>
              <DrSeg value={subs} onChange={setSubs} options={[{ value: "burn", label: "烧录" }, { value: "srt", label: "另存 SRT" }, { value: "none", label: "不导出" }]} />
            </div>
            <div className="dr-xrow">
              <span className="dr-xrow__main">
                <span className="dr-xrow__title"><CvIcon name="waveform" size={13} />声音</span>
                <span className="dr-film__sub">{audioTracks.length} 条音轨混成立体声 · AAC 48 kHz{muted.length ? ` · ${muted.map((t) => t.name).join("、")}已静音，不导出` : ""}</span>
              </span>
            </div>
            {hidden.length > 0 && (
              <div className="dr-film__block ed-export__note">
                <CvIcon name="eye-slash" size={14} />
                <span>{hidden.map((t) => `${t.name} ${t.id}`).join("、")} 已隐藏，不进成片</span>
              </div>
            )}
            {gaps.length > 0 && (
              <div className="dr-film__block">
                <CvIcon name="warning-circle" size={14} />
                <span className="dr-xrow__main">
                  <span>{gaps.length} 处空缺导出为黑场</span>
                  <span className="dr-film__missing">
                    {gaps.map((g) => (
                      <button key={g.id} type="button" onClick={() => onGoClip(g)}>段 {drSegNo(edSegOf(g))} {edSegOf(g).title} · {edTc(g.start)}</button>
                    ))}
                  </span>
                </span>
              </div>
            )}
          </div>
        )}

        {phase === "running" && (
          <div className="dr-export__body">
            <div className="dr-film__run">
              <div className="dr-film__runhead"><span>{ED_EXPORT_STEPS[step]}…</span><span className="dr-film__pct">{pct}%</span></div>
              <span className="dr-prog dr-film__prog"><span style={{ width: pct + "%" }} /></span>
              <div className="dr-film__steps">
                {ED_EXPORT_STEPS.map((s, i) => (
                  <span key={s} className={i < step ? "is-done" : i === step ? "is-on" : ""}>
                    <CvIcon name={i < step ? "check-circle" : i === step ? "circle-notch" : "circle"} size={13} />{s}
                    {i === 0 && ` · ${laid.filter((c) => !c.gap).length} 段主轨、${doc.clips.filter((c) => c.track === "V2").length} 个叠加、${doc.clips.filter((c) => c.track.startsWith("A")).length} 段音频`}
                  </span>
                ))}
              </div>
            </div>
            <div className="dr-muted" style={{ marginTop: 10 }}>只在本机合成，不调用生成模型，不产生费用。取消会删掉临时文件。</div>
          </div>
        )}

        {phase === "done" && (
          <div className="dr-export__body">
            <div className="dr-film__done">
              <CvIcon name="check-circle" size={18} color="var(--success)" />
              <span className="dr-xrow__main">
                <span className="dr-xrow__title">已导出 {name}.mp4</span>
                <span className="dr-film__path">~/Movies/{DR_PROJECT.title}/{name}.mp4 · {w}×{h} · {fps} fps · {edTc(total)}</span>
                {subs === "srt" && <span className="dr-film__path">字幕另存为 {name}.srt</span>}
              </span>
            </div>
          </div>
        )}

        <div className="dr-dialog__foot">
          <span className="dr-dialog__meta">
            {phase === "form" ? `MP4 · ${w}×${h} · ${fps} fps · ${edTc(total)} · 约 ${mb} MB` : phase === "running" ? "导出中" : ""}
          </span>
          <span className="cv-spacer" />
          {phase === "form" && (
            <React.Fragment>
              <button type="button" className="cv-btn" onClick={onClose}>取消</button>
              <button type="button" className="cv-btn cv-btn--primary" onClick={() => { setPct(0); setPhase("running"); }}>
                <CvIcon name="download-simple" size={14} />导出
              </button>
            </React.Fragment>
          )}
          {phase === "running" && <button type="button" className="cv-btn" onClick={() => setPhase("form")}>取消导出</button>}
          {phase === "done" && (
            <React.Fragment>
              <button type="button" className="cv-btn" onClick={onClose}>完成</button>
              <button type="button" className="cv-btn cv-btn--primary"><CvIcon name="folder" size={14} />在访达中显示</button>
            </React.Fragment>
          )}
        </div>
      </div>
    </div>
  );
}

/* ---------------- 制作助手 ---------------- */
// 和制片页同一个聊天 Agent,换成剪辑工具:读写时间线上的片段、字幕与音量;写入直接生效,可在「最近改动」回退。
const ED_CHAT = [
  { role: "user", content: "按对白轨生成字幕；第 2 场的配乐在对白处压低一点。" },
  {
    role: "assistant",
    blocks: [
      {
        type: "activity",
        steps: [
          { kind: "thinking", status: "success",
            detail: { type: "thinking", label: "推理过程", text: "字幕文字取剧本台词，起止对齐对白轨每段音频。配乐只改音量包络，不动片段位置。" } },
          { verb: "读取", icon: "eye", target: "对白轨 A1 · 4 段", status: "success" },
          { verb: "读取", icon: "eye", target: "剧本 · 第 1、2 场台词", status: "success" },
          { verb: "写入", icon: "note-pencil", target: "字幕轨 T1 · 4 条", status: "success",
            detail: { type: "paths", label: "新增", items: ["00:14 老崔：开船了，三倍。", "00:23 周慎：先生这手，是拿笔的手。", "00:36 阿茴：我家小姐想讨一盏灯。", "00:43 沈砚：拿去。"] } },
          { verb: "编辑", icon: "note-pencil", target: "音乐 A3 · 古琴 · 夜泊", status: "success", mono: false,
            detail: { type: "diff", old: "对白处压低：关", now: "对白处压低：开（-8 dB）" } },
        ],
      },
      { type: "text", text: "加了 4 条字幕，配乐在对白处会自动压低 8 dB。\n\n老崔和沈砚的两句落在空缺上（段 1-2、段 2-3），补上片段后字幕和对白位置不用动。" },
    ],
  },
];

function EdChatPanel({ context, changes, onRevert, onRevertAll, onClose }) {
  const [text, setText] = React.useState("");
  return (
    <aside className="m-chat dr-chat">
      <div className="m-chat__head">
        <div className="m-chat__head-l">
          <Icon name="sparkle" size={16} color="var(--accent)" />
          <span className="m-ui-semibold">DeepSeek</span>
          <Icon name="caret-down" size={12} color="var(--text-muted)" />
        </div>
        <div className="m-chat__head-r">
          <button className="m-icon-btn" title="全屏"><Icon name="arrows-out" size={14} /></button>
          <button className="m-icon-btn" title="新会话"><Icon name="note-pencil" size={14} /></button>
          <button className="m-icon-btn" title="收起" onClick={onClose}><Icon name="x" size={14} /></button>
        </div>
      </div>
      <div className="m-chat__context">
        <Icon name="film-strip" size={12} />
        <span>当前上下文：{DR_EPISODE.label} 剪辑{context ? ` · ${context}` : ""}</span>
      </div>
      <div className="m-chat__scroll">
        {ED_CHAT.map((m, i) => <ChatBubble key={i} {...m} />)}
      </div>
      {changes.length > 0 && (
        <div style={{ margin: "0 var(--space-lg)" }}>
          <RecentChangesLog changes={changes} onRevert={onRevert} onRevertAll={onRevertAll} />
        </div>
      )}
      <div className="m-composer">
        {context && (
          <div className="m-composer__refs">
            <span className="m-cref">
              <Icon name="film-strip" size={12} color="var(--accent)" />
              <span>{context}</span>
              <Icon name="x" size={10} color="var(--accent)" />
            </span>
          </div>
        )}
        <div className="m-composer__field">
          <textarea className="m-composer__input" rows={3} spellCheck={false}
            placeholder="让助手配字幕、调音量、按节奏粗剪…"
            value={text} onChange={(e) => setText(e.target.value)} />
        </div>
        <div className="m-composer__toolbar">
          <div style={{ flex: 1 }} />
          <button className="m-composer__send" title="发送"><Icon name="arrow-up" size={18} /></button>
        </div>
      </div>
    </aside>
  );
}

Object.assign(window, { EdPreview, EdTransport, EdInspector, EdBin, EdExportDialog, EdChatPanel });
