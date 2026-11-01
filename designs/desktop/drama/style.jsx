// style.jsx — 风格与生成规格的选择弹层:剧集全局风格 / 节点风格共用一个风格库弹层,
// 视频 / 图片节点与顶栏剧本制作设置共用「清晰度 + 比例」弹层。
// 风格存法见 data.jsx「风格」:剧集一个全局值;节点 style 为空 = 跟随剧集,"none" = 不用风格,{ custom } = 自定义提示词。
// 关联文件: drama/data.jsx, drama/composer.jsx, drama/app.jsx, drama/drama.css

// 风格预览图:渐变 + 剪影代画。无风格 / 自定义 / 未设置用图标。
function DrStyleThumb({ st, w = 20, h = 20, radius = 5 }) {
  const box = { width: w, height: h, borderRadius: radius };
  if (!st || !st.art) {
    const icon = st && st.custom ? "pencil-simple" : "prohibit";
    return <span className="dr-sthumb dr-sthumb--blank" style={box}><CvIcon name={icon} size={Math.round(h * 0.6)} color="var(--text-muted)" /></span>;
  }
  return (
    <span className="dr-sthumb" style={{ ...box, background: st.art }}>
      {st.figs > 0 && (
        <span className="dr-frame__figs">
          {Array.from({ length: st.figs }).map((_, i) => <span key={i} className="dr-frame__fig" />)}
        </span>
      )}
    </span>
  );
}

// 风格库弹层。value:当前存的值;forNode 时第一张卡是「跟随剧集」(value 为 undefined)。
function DrStylePicker({ value, epStyle, forNode, onPick, onClose, style, className }) {
  const [cat, setCat] = React.useState("all");
  const [q, setQ] = React.useState("");
  const isCustom = value && value.custom !== undefined;
  const [editing, setEditing] = React.useState(isCustom);
  const [text, setText] = React.useState(isCustom ? value.custom : "");
  const list = DR_STYLES.filter((s) => (cat === "all" || s.cat === cat) && (!q || s.name.includes(q)));
  const ep = drStyleOf(null, epStyle);
  const card = (key, on, thumb, label, onClick) => (
    <button key={key} type="button" className={"dr-stcard" + (on ? " is-on" : "")} onClick={onClick}>
      <span className="dr-stcard__pv">{thumb}{on && <span className="dr-stcard__check"><CvIcon name="check" size={11} color="currentColor" /></span>}</span>
      <span className="dr-stcard__label">{label}</span>
    </button>
  );
  return (
    <div className={"dr-pop dr-stpick " + (className || "")} style={style} onPointerDown={(e) => e.stopPropagation()}>
      <div className="dr-stpick__search">
        <CvIcon name="magnifying-glass" size={16} color="var(--text-muted)" />
        <input placeholder="搜索风格" value={q} onChange={(e) => setQ(e.target.value)} />
        <button type="button" className="cv-iconbtn dr-pop__x" onClick={onClose}><CvIcon name="x" size={14} /></button>
      </div>
      <div className="dr-stpick__body">
        <nav className="dr-stpick__cats">
          {DR_STYLE_CATS.map((c) => (
            <button key={c.id} type="button" className={"dr-stpick__cat" + (cat === c.id && !editing ? " is-on" : "")}
              onClick={() => { setCat(c.id); setEditing(false); }}>{c.label}</button>
          ))}
        </nav>
        {editing ? (
          <div className="dr-stpick__custom">
            <div className="dr-stpick__customhead">自定义风格提示词</div>
            <textarea autoFocus value={text} onChange={(e) => setText(e.target.value)}
              placeholder="例：写实历史剧质感，胶片颗粒，低饱和暖光" />
            <div className="dr-stpick__customfoot">
              <button type="button" className="cv-btn" onClick={() => setEditing(false)}>返回</button>
              <button type="button" className="cv-btn cv-btn--primary" disabled={!text.trim()}
                onClick={() => onPick({ custom: text.trim() })}>使用</button>
            </div>
          </div>
        ) : (
          <div className="dr-stpick__grid">
            {forNode && card("inherit", value === undefined,
              <DrStyleThumb st={ep} w="100%" h="100%" radius={0} />,
              <span>跟随剧集<span className="dr-stcard__sub"> · {ep.name}</span></span>, () => onPick(undefined))}
            {card("none", value === "none" || (!forNode && !value), <span className="dr-stcard__icon"><CvIcon name="prohibit" size={30} color="var(--text-muted)" /></span>,
              "无风格", () => onPick("none"))}
            {card("custom", isCustom, <span className="dr-stcard__icon"><CvIcon name="pencil-simple" size={28} color="var(--text-muted)" /></span>,
              "自定义风格提示词", () => setEditing(true))}
            {list.map((s) => card(s.id, value === s.id, <DrStyleThumb st={s} w="100%" h="100%" radius={0} />, s.name, () => onPick(s.id)))}
          </div>
        )}
      </div>
    </div>
  );
}

// 输入框底栏的风格 pill:缩略图 + 名称;跟随剧集时名称后带「剧集」小标。
function DrStylePill({ node, epStyle, onPatch }) {
  const [open, setOpen] = React.useState(DR_Q.get("pop") === "style");
  const st = drStyleOf(node, epStyle);
  return (
    <span className="dr-pop__anchor">
      <button type="button" className={"dr-pill" + (open ? " is-on" : "")}
        title={st.inherited ? "跟随剧集风格 · 点开可单独设置" : "这个节点单独设置的风格"} onClick={() => setOpen(!open)}>
        <DrStyleThumb st={st} w={18} h={18} radius={4} />
        <span className="dr-pill__ellipsis">{st.name}</span>
        {st.inherited && <span className="dr-pill__tag">剧集</span>}
        <CvIcon name={open ? "caret-up" : "caret-down"} size={10} color="var(--text-muted)" />
      </button>
      {open && (
        <DrStylePicker className="dr-pop--up" forNode value={node.style} epStyle={epStyle} onClose={() => setOpen(false)}
          onPick={(v) => { onPatch({ style: v }); setOpen(false); }} />
      )}
    </span>
  );
}

// 「清晰度 + 比例」弹层本体(上排清晰度分段,下排比例卡):节点输入框和顶栏剧本设置共用。
// sample:{ model, on, onToggle } —— 模型支持样片时清晰度末尾多一个「样片」,和清晰度互斥;
// 只是这次提交的选项,不写进节点保存的清晰度,选回任一清晰度即关闭。
function DrSpecPanel({ ratios, resList, value, onChange, className, onMouseLeave, children, sample }) {
  const sampleOn = !!(sample && sample.on);
  return (
    <div className={"dr-pop dr-spec " + (className || "")} onPointerDown={(e) => e.stopPropagation()} onMouseLeave={onMouseLeave}>
      <div className="dr-spec__title">清晰度</div>
      <div className="dr-spec__res">
        {resList.map((r) => (
          <button key={r} type="button" className={"dr-spec__resbtn" + (!sampleOn && value.res === r ? " is-on" : "")}
            onClick={() => { onChange({ res: r }); if (sampleOn) sample.onToggle(false); }}>{r}</button>
        ))}
        {sample && (
          <button type="button" className={"dr-spec__resbtn" + (sampleOn ? " is-on" : "")}
            title={`先出 ${sample.model.sample.res} 样片，满意后 ${sample.model.sample.days} 天内可转 ${sample.model.sample.finalRes} 成片，另行计费`}
            onClick={() => sample.onToggle(true)}>样片</button>
        )}
      </div>
      <div className="dr-spec__title">比例</div>
      <div className="dr-spec__ratios">
        {ratios.map((r) => {
          const [bw, bh] = DR_RATIO_BOX[r] || [17, 17];
          return (
            <button key={r} type="button" className={"dr-spec__ratio" + (value.ratio === r ? " is-on" : "")}
              onClick={() => onChange({ ratio: r })}>
              {value.ratio === r && <span className="dr-spec__check"><CvIcon name="check" size={12} color="var(--accent)" /></span>}
              <span className="dr-spec__box" style={{ width: bw, height: bh }} />
              <span>{r}</span>
            </button>
          );
        })}
      </div>
      {children}
    </div>
  );
}

// 节点输入框的「比例 · 清晰度」pill。可选项来自模型能力。
// sample:开了样片时分辨率固定 480P,pill 上直接写明,和实际提交的一致。
function DrSpecPill({ model, gen, onChange, sample, onSample }) {
  const [open, setOpen] = React.useState(DR_Q.get("pop") === "spec");
  return (
    <span className="dr-pop__anchor">
      <button type="button" className={"dr-pill" + (open ? " is-on" : "")} onClick={() => setOpen(!open)}>
        <span className="dr-pill__num">{gen.ratio} · {sample ? `${model.sample.res} 样片` : gen.res}</span>
        <CvIcon name={open ? "caret-up" : "caret-down"} size={10} color="var(--text-muted)" />
      </button>
      {open && (
        <DrSpecPanel className="dr-pop--up" ratios={model.ratios} resList={model.res} value={gen} onChange={onChange}
          sample={onSample && model.sample ? { model, on: sample, onToggle: onSample } : null}
          onMouseLeave={() => setOpen(false)} />
      )}
    </span>
  );
}

// 顶栏右侧的剧本制作设置:比例框 + 「9:16 · 720P」▾,弹层和节点的比例 / 清晰度同一个,从 chip 下方展开、贴右对齐。
// 可选项是剧本设置的全集(不受某个模型限制);落到节点上时再按模型夹回(drFitSpec)。
function DrProductionSpec({ value, open, onOpen, onChange }) {
  const [bw, bh] = DR_RATIO_BOX[value.ratio] || [17, 17];
  return (
    <span className="dr-pop__anchor dr-epspec">
      <button type="button" className={"dr-epstyle__btn" + (open ? " is-on" : "")} title="剧本制作设置 · 新建视频节点和整集成片默认使用"
        onClick={() => onOpen(!open)}>
        <span className="dr-epspec__icon"><span className="dr-spec__box" style={{ width: Math.round(bw * 0.7), height: Math.round(bh * 0.7) }} /></span>
        <span className="dr-pill__num">{value.ratio} · {value.res}</span>
        <CvIcon name={open ? "caret-up" : "caret-down"} size={11} color="var(--text-muted)" />
      </button>
      {open && (
        <React.Fragment>
          <div className="dr-modal dr-modal--clear" onPointerDown={() => onOpen(false)} />
          <DrSpecPanel ratios={DR_SPEC_RATIOS} resList={DR_SPEC_RES} value={value} onChange={onChange}>
            <div className="dr-spec__note">整部剧共用：新建视频节点默认使用，整集成片按此比例导出；已有节点不变</div>
          </DrSpecPanel>
        </React.Fragment>
      )}
    </span>
  );
}

// 顶栏右侧的剧集全局风格:缩略图 + 名称 ▾,× 清空为无风格。弹层从 chip 下方展开,贴右对齐。
function DrEpisodeStyle({ value, open, onOpen, onChange }) {
  const st = drStyleOf(null, value);
  return (
    <span className="dr-pop__anchor dr-epstyle">
      <button type="button" className={"dr-epstyle__btn" + (open ? " is-on" : "")} title="剧集风格 · 视频和图片节点默认跟随"
        onClick={() => onOpen(!open)}>
        <DrStyleThumb st={st} w={22} h={22} radius={11} />
        <span className="dr-epstyle__name">{st.name}</span>
        <CvIcon name={open ? "caret-up" : "caret-down"} size={11} color="var(--text-muted)" />
      </button>
      {st.value && (
        <button type="button" className="cv-iconbtn dr-epstyle__clear" title="清除剧集风格" onClick={() => onChange("none")}>
          <CvIcon name="x" size={13} />
        </button>
      )}
      {open && (
        <React.Fragment>
          <div className="dr-modal dr-modal--clear" onPointerDown={() => onOpen(false)} />
          <DrStylePicker className="dr-stpick--top" value={value} epStyle={value} onClose={() => onOpen(false)} onPick={onChange} />
        </React.Fragment>
      )}
    </span>
  );
}

Object.assign(window, { DrStyleThumb, DrStylePicker, DrStylePill, DrSpecPanel, DrSpecPill, DrProductionSpec, DrEpisodeStyle });
