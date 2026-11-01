// composer.jsx — 选中节点时浮在画布上的两层:节点上方的工具条 + 视频 / 图片节点下方的生成输入框。
// 右栏留给制作助手(聊天),编辑不再占一整列 —— 选中哪个节点,就在哪个节点旁边改。
// 生成输入框:上排是实际输入(缩略图 + 媒体槽,= 输入连线的用途和顺序),中间是提示词(@资产 chip),
// 底栏是 ＋(上传 / 资产库)/ @ / 运镜 / 风格 / 模型 / 比例·清晰度 / 时长 / 生成方式 / 预估费用 / 发送。
// 发送先打开提交预览,确认后才计费。图片节点没有时长、生成方式和运镜,按张计费。
// 支持样片的模型(Seedance 2.5)在「比例 · 清晰度」的清晰度里多一个「样片」:选中后 pill 写「480P 样片」,
// 按样片提交和估价,不改节点保存的清晰度;每次打开输入框默认不选。样片转 1080P 成片从节点工具条或结果弹层发起。
// 风格默认跟随剧集全局风格,可在节点上单独改;一段里的多个镜头按 Shot 格式写在提示词里,时间码由作者手写。
// 工具条:制作状态(仅片段)、结果与重做历史(可切回历史,或从资产库选一个视频采用)、预览、导出、作为参考、查看原文;
// 素材节点是预览、导出、被谁使用。
// 关联文件: drama/app.jsx, drama/board.jsx, drama/views.jsx, drama/data.jsx, drama/drama.css

function DrSeg({ value, options, onChange }) {
  return (
    <div className="dr-seg">
      {options.map((o) => (
        <button key={o.value} type="button" disabled={o.disabled} title={o.title}
          className={"dr-seg__btn" + (value === o.value ? " is-on" : "")}
          onClick={() => onChange(o.value)}>{o.label}</button>
      ))}
    </div>
  );
}

// 下拉。pill 用在输入框底栏(向上展开),普通样式用在弹窗里。
function DrSelect({ value, options, onChange, width, pill, icon, up, label }) {
  const [open, setOpen] = React.useState(false);
  const cur = options ? options.find((o) => o.value === value) : null;
  return (
    <span className="dr-select__wrap" style={{ width }}>
      <button type="button" className={pill ? "dr-pill" : "dr-select"} onClick={() => options && setOpen(!open)}>
        {icon && <CvIcon name={icon} size={13} color="currentColor" />}
        <span>{label || (cur ? cur.label : value)}</span>
        <CvIcon name="caret-down" size={10} color="var(--text-muted)" />
      </button>
      {open && (
        <span className={"dr-menu" + (up ? " dr-menu--up" : "")} onMouseLeave={() => setOpen(false)}>
          {options.map((o) => (
            <button key={o.value} type="button" disabled={o.disabled}
              className={"dr-menu__item" + (o.value === value ? " is-on" : "")}
              onClick={() => { onChange(o.value); setOpen(false); }}>
              {o.label}
              {o.hint && <span className="dr-menu__hint">{o.hint}</span>}
            </button>
          ))}
        </span>
      )}
    </span>
  );
}

/* ---------------- 提示词 ---------------- */
// 引用没有对应输入连线时 chip 标红,发送被挡住,不静默丢参考。
// 引用视频节点(type=nodes)时显示节点名,传给模型的是它当前采用的结果。
function DrRefChip({ refType, id, label, broken }) {
  const a = refType === "assets" ? spAsset(id) : null;
  return (
    <span className={"dr-ref" + (broken ? " is-broken" : "")} contentEditable={false}
      title={broken ? "没有对应的输入连线" : a ? `${a.name} · ${a.source}` : `${label} · 采用的结果`}>
      {a && a.type !== "audio"
        ? <DrFrame tone={a.tone} ratio="1:1" h={14} figures={0} style={{ borderRadius: 3 }} />
        : <CvIcon name={a ? DR_ASSET_TYPES[a.type].icon : "film-strip"} size={11} color="currentColor" />}
      {a ? a.name : label}
    </span>
  );
}

// inputKeys:当前输入的身份集合(资产 id 或来源节点 id)
function DrPromptView({ prompt, inputKeys }) {
  return spPromptParts(prompt).map((p, i) => p.ref
    ? <DrRefChip key={i} refType={p.ref.type} id={p.ref.assetId} label={p.ref.label} broken={!inputKeys.has(p.ref.assetId)} />
    : <React.Fragment key={i}>{p.text}</React.Fragment>);
}

// @ 选择器:已连为输入的来源只插入引用;资产库里的媒体选中后同时补一条输入连线。
function DrRefPicker({ model, mode, inputs, onPick, onClose }) {
  const inputIds = new Set(inputs.map((i) => i.key));
  const roles = drRolesFor(model, mode);
  const accept = new Set(roles.map((r) => DR_ROLES[r].accepts));
  const lib = SP_ASSETS.filter((a) => accept.has(a.type) && !inputIds.has(a.id) && !a.id.startsWith("r_"));
  return (
    <div className="dr-pop dr-pop--up" onPointerDown={(e) => e.stopPropagation()}>
      <div className="dr-pop__head">
        引用资产 <span className="dr-muted">· {model.name} {SP_GEN_MODES[mode]}可用</span>
        <span className="cv-spacer" />
        <button type="button" className="cv-iconbtn dr-pop__x" onClick={onClose}><CvIcon name="x" size={13} /></button>
      </div>
      <div className="dr-pop__group">已连为输入</div>
      {inputs.length === 0 && <div className="dr-pop__empty">还没有输入</div>}
      {inputs.map((i) => {
        const ref = i.src ? { type: "nodes", id: i.key, label: drVideoLabel(i.src) } : { type: "assets", id: i.key, label: i.name };
        return (
          <button key={i.id} type="button" className="dr-pop__item" onClick={() => onPick(ref, null)}>
            <DrAssetThumb asset={drInputAsset(i)} h={26} />
            <span className="dr-pop__name">{i.src ? ref.label : i.name}</span>
            <span className="dr-pop__meta">{i.slot}</span>
          </button>
        );
      })}
      {roles.length > 0 && <div className="dr-pop__group">资产库 · 选中后补一条输入连线</div>}
      {roles.length > 0 && lib.map((a) => {
        const role = roles.find((r) => DR_ROLES[r].accepts === a.type);
        return (
          <button key={a.id} type="button" className="dr-pop__item" onClick={() => onPick({ type: "assets", id: a.id, label: a.name }, role)}>
            <DrAssetThumb asset={a} h={26} />
            <span className="dr-pop__name">{a.name}</span>
            <span className="dr-pop__meta">＋ {DR_ROLES[role].label}</span>
          </button>
        );
      })}
    </div>
  );
}

// 运镜库:点卡片把运镜描述写进提示词(可见编辑,不另存字段、生成时不暗中叠加)。
function DrCameraPicker({ onPick, onClose }) {
  const [g, setG] = React.useState("all");
  const list = DR_CAM_TEMPLATES.filter((t) => g === "all" || t.group === g);
  return (
    <div className="dr-pop dr-pop--up dr-campick" onPointerDown={(e) => e.stopPropagation()}>
      <div className="dr-pop__head">
        运镜库 <span className="dr-muted">· 写进提示词，可再改</span>
        <span className="cv-spacer" />
        <button type="button" className="cv-iconbtn dr-pop__x" onClick={onClose}><CvIcon name="x" size={13} /></button>
      </div>
      <div className="dr-campick__tabs">
        {[{ id: "all", label: "全部" }, ...DR_CAM_GROUPS].map((x) => (
          <button key={x.id} type="button" className={"dr-drawer__tab" + (g === x.id ? " is-on" : "")} onClick={() => setG(x.id)}>{x.label}</button>
        ))}
      </div>
      <div className="dr-campick__grid">
        {list.map((t) => (
          <button key={t.id} type="button" className="dr-camcard" title={t.text} onClick={() => onPick(t)}>
            <span className="dr-camcard__pv"><span className={"dr-move__glyph dr-move__glyph--" + t.base} /></span>
            <span className="dr-camcard__label"><CvIcon name="video-camera" size={12} color="currentColor" />{t.label}</span>
            <span className="dr-camcard__desc">{t.desc}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

/* ---------------- 输入缩略图 ----------------
   一格 = 一条输入连线。角标是本次请求的媒体槽;点开改用途、调顺序或断开。
   来源是视频节点时显示它采用的结果;还没采用就是空帧并标红。 */
function DrInputTile({ input, roles, onRole, onMove, onUnlink }) {
  const [open, setOpen] = React.useState(false);
  const a = drInputAsset(input);
  const bad = !roles.includes(input.role) || input.pending;
  return (
    <span className="dr-tile__wrap">
      <button type="button" className={"dr-tile" + (bad ? " is-bad" : "")} title={`${input.name} · ${DR_ROLES[input.role].label}`}
        onClick={() => setOpen(!open)}>
        <DrAssetThumb asset={a} h={52} ratio="1:1" />
        <span className="dr-tile__slot">{input.slot}</span>
      </button>
      {open && (
        <span className="dr-pop dr-pop--up dr-tilemenu" onMouseLeave={() => setOpen(false)}>
          <div className="dr-pop__head"><span className="dr-pop__name">{input.name}</span></div>
          <div className="dr-pop__group">用途</div>
          {Object.entries(DR_ROLES).filter(([, r]) => r.accepts === a.type).map(([k, r]) => (
            <button key={k} type="button" className={"dr-pop__item" + (k === input.role ? " is-on" : "")}
              disabled={!roles.includes(k)} onClick={() => { onRole(k); setOpen(false); }}>
              <span className="dr-pop__name">{r.label}</span>
              {k === input.role && <CvIcon name="check" size={12} color="var(--accent)" />}
              {!roles.includes(k) && <span className="dr-pop__meta">当前模式不可用</span>}
            </button>
          ))}
          <div className="dr-pop__sep" />
          <button type="button" className="dr-pop__item" onClick={() => onMove(-1)}><span className="dr-pop__name">前移</span></button>
          <button type="button" className="dr-pop__item" onClick={() => onMove(1)}><span className="dr-pop__name">后移</span></button>
          <button type="button" className="dr-pop__item dr-pop__item--danger" onClick={() => { onUnlink(); setOpen(false); }}>
            <span className="dr-pop__name">断开</span><span className="dr-pop__meta">删除这条输入连线</span>
          </button>
        </span>
      )}
    </span>
  );
}

/* ---------------- 生成输入框 ---------------- */
// ＋ 菜单:上传(去重保存进资产库,在节点左侧放一个素材节点并连成输入)/ 从资产库选择输入。
function DrPlusMenu({ onUpload, onPickLib, onClose }) {
  return (
    <div className="dr-pop dr-pop--up dr-plus" onPointerDown={(e) => e.stopPropagation()} onMouseLeave={onClose}>
      <button type="button" className="dr-pop__item" onClick={() => { onUpload(); onClose(); }}>
        <CvIcon name="upload" size={15} color="var(--text-muted)" />
        <span className="dr-pop__name">上传</span>
      </button>
      <button type="button" className="dr-pop__item" onClick={() => { onPickLib(); onClose(); }}>
        <CvIcon name="folder" size={15} color="var(--text-muted)" />
        <span className="dr-pop__name">从资产库选择</span>
      </button>
    </div>
  );
}

function DrComposer({ node, nodes, edges, tasks, epStyle, style, onPatch, onEdges, onInsertRef, onAddInput, onUploadInput, onSubmit }) {
  const cfg = node;
  const image = node.kind === "image";
  const model = drModel(cfg.gen.model);
  const models = image ? DR_IMAGE_MODELS : SP_VIDEO_MODELS;
  const inputs = drInputsOf(edges, node.id, nodes);
  const inputKeys = new Set(inputs.map((i) => i.key));
  const issues = drValidate(cfg, inputs);
  const errors = issues.filter((i) => i.level === "error");
  const history = tasks.filter((t) => t.source.type === "node" && t.source.id === node.id);
  const busy = history.find((t) => ["queued", "running", "downloading"].includes(t.state));
  const roles = drRolesFor(model, cfg.gen.mode);
  const secs = drSecs(cfg.ms);
  const [picker, setPicker] = React.useState(DR_Q.get("pop") === "plus" ? "plus" : null); // "plus" | "ref" | "cam"
  const [expanded, setExpanded] = React.useState(false);
  const [sampleOn, setSampleOn] = React.useState(DR_Q.get("sample") === "on");
  const sample = !image && !!model.sample && sampleOn;
  const gen = (p) => onPatch({ gen: { ...cfg.gen, ...p } });
  // 换模型时把比例 / 清晰度夹回新模型支持的范围。
  const setModel = (id) => {
    const m = drModel(id);
    gen({ model: id, ratio: m.ratios.includes(cfg.gen.ratio) ? cfg.gen.ratio : m.ratios[0],
      res: m.res.includes(cfg.gen.res) ? cfg.gen.res : m.res[m.res.length - 1] });
  };

  const setRole = (edgeId, role) => onEdges((es) => es.map((e) => (e.id === edgeId ? { ...e, role } : e)));
  const unlink = (edgeId) => onEdges((es) => es.filter((e) => e.id !== edgeId));
  const move = (edgeId, d) => onEdges((es) => {
    const e = es.find((x) => x.id === edgeId);
    const peer = es.find((x) => x.to === e.to && x.role === e.role && x.order === e.order + d);
    if (!peer) return es;
    return es.map((x) => (x.id === e.id ? { ...x, order: e.order + d } : x.id === peer.id ? { ...x, order: e.order } : x));
  });

  const blockReason = busy ? "这个节点已有任务进行中" : errors.length ? errors[0].text : null;
  const perSec = sample ? model.sample.pricePerSec : model.pricePerSec;
  const fee = image ? model.pricePerImage : secs ? secs * perSec : null;
  const feeTitle = image ? `按「${model.channel}」单价 ¥${model.pricePerImage.toFixed(2)}/张估算，以供应商账单为准`
    : secs ? `按「${model.channel}」${sample ? "样片" : ""}单价 ¥${perSec.toFixed(1)}/秒 × ${secs} 秒估算，以供应商账单为准` : "填了时长才能估算";
  const toggle = (k) => setPicker(picker === k ? null : k);

  return (
    <div className={"dr-composer" + (expanded ? " is-expanded" : "")} style={style}
      onPointerDown={(e) => e.stopPropagation()} onWheel={(e) => e.stopPropagation()}>
      <div className="dr-composer__tiles">
        {inputs.map((it) => (
          <DrInputTile key={it.id} input={it} roles={roles}
            onRole={(r) => setRole(it.id, r)} onMove={(d) => move(it.id, d)} onUnlink={() => unlink(it.id)} />
        ))}
        <span className="cv-spacer" />
        <button type="button" className="cv-iconbtn dr-composer__exp" title={expanded ? "收起" : "展开"}
          onClick={() => setExpanded(!expanded)}>
          <CvIcon name={expanded ? "arrows-in" : "arrows-out"} size={14} />
        </button>
      </div>

      <div className="dr-composer__prompt" contentEditable suppressContentEditableWarning>
        {cfg.prompt ? <DrPromptView prompt={cfg.prompt} inputKeys={inputKeys} /> : null}
      </div>
      {!cfg.prompt && (
        <div className="dr-composer__ph">
          {image ? "描述这张图：主体、构图、光线；@引用参考图" : "按镜头写：Shot 头（景别·角度·运镜·时长）、区间、首帧、时间码节拍、结束状态；@引用素材"}
        </div>
      )}
      {issues.filter((i) => i.ref || i.level === "error").slice(0, 2).map((i, k) => (
        <div key={k} className="dr-issue"><CvIcon name="warning-circle" size={12} />{i.text}</div>
      ))}
      {!image && cfg.gen.mode === "text" && inputs.length > 0 && (
        <div className="dr-issue"><CvIcon name="warning-circle" size={12} />纯文本不发送输入；切回参考生成或断开这些输入</div>
      )}

      <div className="dr-composer__bar">
        <span className="dr-pop__anchor">
          <button type="button" className={"dr-cbtn" + (picker === "plus" ? " is-on" : "")} title="上传或从资产库添加输入" onClick={() => toggle("plus")}>
            <CvIcon name="plus" size={16} />
          </button>
          {picker === "plus" && (
            <DrPlusMenu onClose={() => setPicker(null)}
              onUpload={() => onUploadInput(node)} onPickLib={() => onAddInput(node)} />
          )}
        </span>
        <span className="dr-pop__anchor">
          <button type="button" className="dr-cbtn" title="引用素材" onClick={() => toggle("ref")}>@</button>
          {picker === "ref" && (
            <DrRefPicker model={model} mode={cfg.gen.mode} inputs={inputs} onClose={() => setPicker(null)}
              onPick={(ref, role) => { onInsertRef(node, ref, role); setPicker(null); }} />
          )}
        </span>
        {!image && (
          <span className="dr-pop__anchor">
            <button type="button" className={"dr-cbtn" + (picker === "cam" ? " is-on" : "")} title="运镜库" onClick={() => toggle("cam")}>
              <CvIcon name="video-camera" size={16} />
            </button>
            {picker === "cam" && (
              <DrCameraPicker onClose={() => setPicker(null)}
                onPick={(t) => { onPatch({ prompt: (cfg.prompt ? cfg.prompt + "\n" : "") + t.text }); setPicker(null); }} />
            )}
          </span>
        )}
        <DrStylePill node={node} epStyle={epStyle} onPatch={onPatch} />
        <span className="dr-composer__sep" />
        <DrSelect pill up icon="sparkle" value={cfg.gen.model} label={model.name} onChange={setModel}
          options={models.map((m) => ({ value: m.id, label: m.name, hint: m.channel }))} />
        <DrSpecPill model={model} gen={cfg.gen} onChange={gen} sample={sample} onSample={image ? null : setSampleOn} />
        {!image && (
          <React.Fragment>
            <DrSelect pill up value={secs ? `${secs}s` : "时长"} label={secs ? `${secs}s` : "时长未填"}
              onChange={(v) => onPatch({ ms: v * 1000 })}
              options={Array.from({ length: model.secs[1] - model.secs[0] + 1 }, (_, i) => model.secs[0] + i)
                .map((s) => ({ value: s, label: `${s} 秒` }))} />
            <DrSelect pill up value={cfg.gen.mode} onChange={(v) => gen({ mode: v })}
              options={Object.entries(SP_GEN_MODES).map(([k, l]) => ({
                value: k, label: l, disabled: !model.modes.includes(k), hint: model.modes.includes(k) ? null : "不支持",
              }))} />
          </React.Fragment>
        )}
        <span className="cv-spacer" />
        {/* 预估供应商费用 = 渠道设置里填的单价 × 时长(图片按张);走用户自配渠道。 */}
        <span className="dr-composer__fee" title={feeTitle}>预估 ¥{fee != null ? fee.toFixed(image ? 2 : 1) : "—"}</span>
        <button type="button" className="dr-send" disabled={!!blockReason}
          title={blockReason || (sample ? "生成样片" : history.length ? "重做" : "生成")}
          onClick={() => onSubmit(sample)}>
          <CvIcon name={history.length ? "arrow-clockwise" : "arrow-up"} size={16} color="currentColor" />
        </button>
      </div>
    </div>
  );
}

/* ---------------- 结果与重做历史 ----------------
   每次任务一行,最新在上。成功结果登记后自动采用(片段同时标为已完成);重做期间保留原采用视频。
   可以切回任意一次历史结果,只改采用指针,不重新生成;下游以它为参考的节点下次生成用切换后的结果。 */
function DrResultsPop({ cfg, history, onAdopt, onRedownload, onPickAsset, onUpload, onCompleteSample }) {
  const image = cfg.kind === "image";
  const list = [...history].reverse();
  // 采用的是资产库里选来或上传的文件(不是本节点生成的),单独列在最上面。
  const picked = cfg.adopted && !history.some((t) => t.result === cfg.adopted) ? spAsset(cfg.adopted) : null;
  return (
    <div className="dr-pop dr-results" onPointerDown={(e) => e.stopPropagation()}>
      <div className="dr-pop__head">结果 <span className="dr-muted">· {history.length} 次生成，成功后自动采用，可切回历史</span></div>
      {picked && (
        <div className="dr-hist__row is-on">
          <DrFrame tone={picked.tone} w={34} play={!image} figures={0} />
          <span className="dr-hist__text">
            <span className="dr-hist__line">{picked.source === "上传" ? "上传" : "资产库"} · {picked.name}</span>
            <span className="dr-muted">{picked.source} · {picked.spec}</span>
          </span>
          <span className="dr-hist__acts"><span className="dr-cand__adopted"><CvIcon name="seal-check" size={11} />采用中</span></span>
        </div>
      )}
      {list.length === 0 && !picked && <div className="dr-pop__empty">还没生成过</div>}
      {list.map((t) => {
        const st = SP_TASK_STATE[t.state];
        const res = t.result && spAsset(t.result);
        const on = res && res.id === cfg.adopted;
        const n = history.indexOf(t) + 1;
        return (
          <div key={t.id} className={"dr-hist__row" + (on ? " is-on" : "")}>
            {res ? <DrFrame tone={res.tone} w={34} play={!image} figures={0} />
              : <span className="dr-frame dr-frame--empty" style={{ width: 34, height: 60 }}>
                  <CvIcon name={t.state === "failed" || t.state === "download_failed" ? "warning-circle" : "circle-notch"} size={13} color="var(--text-subtle)" />
                </span>}
            <span className="dr-hist__text">
              <span className="dr-hist__line">
                第 {n} 次
                {t.sample && <span className="dr-sample-tag">样片</span>}
                {t.fromSample && <span className="dr-sample-tag dr-sample-tag--final">成片</span>}
                <span className={"dr-tstate dr-tstate--" + st.tone}>{t.state === "running" ? `生成中 ${t.progress}%` : st.label}</span>
              </span>
              <span className="dr-muted">
                {t.at} · {drModel(t.model).name}{image ? "" : ` · ${t.secs}s`}
                {t.sample ? " · 480P" : t.fromSample ? " · 1080P" : ""} · ¥{t.fee.toFixed(image ? 2 : 1)}
              </span>
              {t.sample && t.state === "succeeded" && (() => {
                const final = history.findIndex((x) => x.fromSample === t.id);
                return (
                  <span className="dr-muted">
                    {final >= 0 ? `已转成片 · 第 ${final + 1} 次` : t.expired ? `已过成片期限（${t.expires}）` : `${t.expires} 前可转成片`}
                  </span>
                );
              })()}
              {t.fromSample && <span className="dr-muted">来自第 {history.findIndex((x) => x.id === t.fromSample) + 1} 次样片</span>}
              {t.state === "running" && <span className="dr-prog"><span style={{ width: `${t.progress}%` }} /></span>}
              {t.error && <span className="dr-hist__err">{t.error}</span>}
            </span>
            <span className="dr-hist__acts">
              {on && <span className="dr-cand__adopted"><CvIcon name="seal-check" size={11} />采用中</span>}
              {t.sample && t.state === "succeeded" && !t.expired && (() => {
                const pending = history.find((x) => x.fromSample === t.id && !["succeeded", "failed"].includes(x.state));
                const done = history.find((x) => x.fromSample === t.id && x.state === "succeeded");
                if (pending || done) return null;
                return (
                  <button type="button" className="cv-btn cv-btn--outline dr-cand__btn" onClick={() => onCompleteSample(t)}>生成成片</button>
                );
              })()}
              {res && !on && (
                <button type="button" className="cv-btn cv-btn--outline dr-cand__btn" onClick={() => onAdopt(res.id, n)}>改用这次</button>
              )}
              {t.state === "download_failed" && (
                <button type="button" className="cv-btn cv-btn--outline dr-cand__btn" onClick={() => onRedownload(t.id)}>重新下载</button>
              )}
            </span>
          </div>
        );
      })}
      <div className="dr-pop__sep" />
      <button type="button" className="dr-pop__item" onClick={onUpload}>
        <CvIcon name="upload" size={14} color="var(--text-muted)" />
        <span className="dr-pop__name">上传</span>
      </button>
      <button type="button" className="dr-pop__item" onClick={onPickAsset}>
        <CvIcon name="folder" size={14} color="var(--text-muted)" />
        <span className="dr-pop__name">从资产库选择{image ? "图片" : "视频"}…</span>
      </button>
    </div>
  );
}

/* ---------------- 节点工具条 ---------------- */
function DrBarBtn({ icon, children, onClick, on, title }) {
  return (
    <button type="button" className={"dr-nbar__btn" + (on ? " is-on" : "")} onClick={onClick} title={title}>
      {icon && <CvIcon name={icon} size={14} color="currentColor" />}{children}
    </button>
  );
}

// 被谁当作输入:素材节点与视频节点共用这一个弹层。
function DrUsesPop({ title, sub, uses, nodes, empty, onSelectNode }) {
  return (
    <div className="dr-pop dr-results">
      <div className="dr-pop__head">{title} <span className="dr-muted">· {sub}</span></div>
      {uses.length === 0 && <div className="dr-pop__empty">{empty}</div>}
      {uses.map((e) => {
        const g = nodes.find((n) => n.id === e.to);
        return (
          <button key={e.id} type="button" className="dr-pop__item" onClick={() => onSelectNode(g.id)}>
            {drIsSeg(g) ? <span className="dr-shotno">段 {drSegNo(g)}</span> : <span className="dr-shotno dr-shotno--free">{g.kind === "image" ? "图片" : "视频"}</span>}
            <span className="dr-pop__name">{g.title}</span>
            <span className="dr-pop__meta">{DR_ROLES[e.role].label}</span>
          </button>
        );
      })}
    </div>
  );
}

// 采用的是样片时,状态后面紧跟「样片 · 480P」和「生成成片」;成片生成中显示进度,过期只留标签。
function DrSampleBar({ info, onComplete }) {
  if (info.completing) {
    return (
      <span className="dr-nbar__sample">
        <span className="dr-sample-tag">样片</span>
        <span className="dr-tstate dr-tstate--run">成片生成中 {info.completing.progress}%</span>
      </span>
    );
  }
  return (
    <span className="dr-nbar__sample" title={info.expired ? `已过成片期限（${info.task.expires}）` : `${info.task.expires} 前可转 1080P 成片`}>
      <span className="dr-sample-tag">样片 · 480P</span>
      {info.expired
        ? <span className="dr-tstate dr-tstate--muted">已过期</span>
        : (
          <button type="button" className="dr-nbar__btn dr-nbar__btn--accent" onClick={onComplete}>
            <CvIcon name="sparkle" size={14} color="currentColor" />生成成片
          </button>
        )}
    </span>
  );
}

function DrNodeBar({ node, edges, nodes, tasks, style, initialPop, onPatch, onAdopt, onRedownload, onGoScript,
  onPickAdopt, onUploadResult, onGoList, onOpenDirector, onSelectNode, onPlaceAsset, onFill, onImport, onCompleteSample }) {
  const [pop, setPop] = React.useState(initialPop || null);
  const toggle = (k) => setPop(pop === k ? null : k);
  const stop = (e) => e.stopPropagation();

  if (drIsGen(node)) {
    const cfg = node;
    const image = node.kind === "image";
    const history = tasks.filter((t) => t.source.type === "node" && t.source.id === node.id);
    const uses = edges.filter((e) => e.type === "input" && e.from === node.id);
    const sampleInfo = drSampleOf(node, tasks);
    return (
      <div className="dr-nbar" style={style} onPointerDown={stop}>
        {drIsSeg(node) ? (
          <DrSelect pill value={cfg.status} onChange={(v) => onPatch({ status: v })}
            label={<span className={"dr-pstatus dr-pstatus--" + cfg.status}><span className="dr-pstatus__dot" />{DR_SEG_STATUS[cfg.status].label}</span>}
            options={Object.entries(DR_SEG_STATUS).map(([k, s]) => ({ value: k, label: s.label }))} />
        ) : <span className="dr-nbar__tag">{image ? "图片节点" : "视频节点 · 不进成片"}</span>}
        {sampleInfo && <DrSampleBar info={sampleInfo} onComplete={() => onCompleteSample(sampleInfo.task)} />}
        <span className="dr-nbar__sep" />
        <span className="dr-pop__anchor">
          <DrBarBtn icon="film-strip" on={pop === "res"} onClick={() => toggle("res")}>
            结果 {history.length}
          </DrBarBtn>
          {pop === "res" && <DrResultsPop cfg={cfg} history={history} onAdopt={(id, n) => { onAdopt(id, n); setPop(null); }} onRedownload={onRedownload}
            onPickAsset={() => { setPop(null); onPickAdopt(); }} onUpload={() => { setPop(null); onUploadResult(); }}
            onCompleteSample={(t) => { setPop(null); onCompleteSample(t); }} />}
        </span>
        <DrBarBtn icon="upload" onClick={onUploadResult}>上传</DrBarBtn>
        <DrBarBtn icon={image ? "eye" : "play"} title={image ? "查看采用的图片" : "预览采用的视频"}>{image ? "查看" : "预览"}</DrBarBtn>
        <DrBarBtn icon="download-simple" title={image ? "导出采用的图片" : "导出采用的视频"}>导出</DrBarBtn>
        <span className="dr-pop__anchor">
          <DrBarBtn icon="flow-arrow" on={pop === "use"} onClick={() => toggle("use")}>作为参考 {uses.length}</DrBarBtn>
          {pop === "use" && (
            <DrUsesPop title={cfg.title} sub="下游拿到的是采用的结果" uses={uses} nodes={nodes}
              empty="还没连到视频节点 · 从右侧圆点拖线" onSelectNode={onSelectNode} />
          )}
        </span>
        {drIsSeg(node) && (
          <React.Fragment>
            <span className="dr-nbar__sep" />
            <DrBarBtn icon="file-text" onClick={() => onGoScript(node.sceneId)}>查看原文</DrBarBtn>
            <DrBarBtn icon="list-numbers" title="片段列表与画布是同一份内容" onClick={() => onGoList(node)}>在列表中打开</DrBarBtn>
          </React.Fragment>
        )}
      </div>
    );
  }

  if (node.kind === "asset" && !node.assetId) {
    return (
      <div className="dr-nbar" style={style} onPointerDown={stop}>
        <DrBarBtn icon="folder" onClick={() => onFill(node)}>从资产库选择</DrBarBtn>
        <DrBarBtn icon="upload" onClick={onImport}>上传</DrBarBtn>
      </div>
    );
  }

  const a = node.assetId ? spAsset(node.assetId) : null;
  if (node.kind === "director" && !a) {
    return (
      <div className="dr-nbar" style={style} onPointerDown={stop}>
        <DrBarBtn icon="cube" onClick={onOpenDirector}>打开导演台</DrBarBtn>
      </div>
    );
  }
  if (node.kind === "director") {
    return (
      <div className="dr-nbar" style={style} onPointerDown={stop}>
        <DrBarBtn icon="cube" onClick={onOpenDirector}>打开导演台</DrBarBtn>
        <span className="dr-pop__anchor">
          <DrBarBtn icon="film-strip" on={pop === "out"} onClick={() => toggle("out")}>输出 {DR_STAGE.exports.length}</DrBarBtn>
          {pop === "out" && (
            <div className="dr-pop dr-results">
              <div className="dr-pop__head">导演输出 <span className="dr-muted">· 每次输出登记为资产，冻结当时的工程</span></div>
              {DR_STAGE.exports.slice().reverse().map((x) => {
                const out = spAsset(x.asset);
                const placed = nodes.some((n) => n.assetId === x.asset);
                return (
                  <div key={x.id} className="dr-hist__row">
                    <DrAssetThumb asset={out} h={36} />
                    <span className="dr-hist__text">
                      <span className="dr-hist__line">{out.name}</span>
                      <span className="dr-muted">{x.at}{x.usedBy.length ? ` · ${x.usedBy.map((id) => drVideoLabel(drNode(id))).join("、")} 在用` : ""}</span>
                    </span>
                    <span className="dr-hist__acts">
                      {placed ? <span className="dr-muted">已在画布</span>
                        : <button type="button" className="cv-btn cv-btn--outline dr-cand__btn" onClick={() => { onPlaceAsset(x.asset); setPop(null); }}>放到画布</button>}
                    </span>
                  </div>
                );
              })}
            </div>
          )}
        </span>
      </div>
    );
  }

  const uses = edges.filter((e) => e.type === "input" && e.assetId === a.id);
  const fromDirector = a.source.startsWith("导演输出");
  return (
    <div className="dr-nbar" style={style} onPointerDown={stop}>
      <DrBarBtn icon={a.type === "image" ? "eye" : "play"}>{a.type === "image" ? "查看" : "播放"}</DrBarBtn>
      <DrBarBtn icon="download-simple">导出</DrBarBtn>
      <span className="dr-pop__anchor">
        <DrBarBtn icon="flow-arrow" on={pop === "use"} onClick={() => toggle("use")}>作为输入 {uses.length}</DrBarBtn>
        {pop === "use" && (
          <DrUsesPop title={a.name} sub={a.source} uses={uses} nodes={nodes}
            empty="还没连到视频节点 · 从右侧圆点拖线" onSelectNode={onSelectNode} />
        )}
      </span>
      {fromDirector && <DrBarBtn icon="cube" onClick={onOpenDirector}>导演台</DrBarBtn>}
    </div>
  );
}

Object.assign(window, { DrComposer, DrNodeBar, DrSeg, DrSelect, DrPromptView, DrRefChip });
