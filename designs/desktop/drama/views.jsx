// views.jsx — 制片页周边:本集场次与片段导航、添加节点、资产库选择、连线用途、提交前预览。
// 不提供拆片段弹窗 —— 拆片段交给右栏聊天 Agent,结果直接建成片段节点并进入变更审阅。
// 关联文件: drama/data.jsx, drama/app.jsx, drama/composer.jsx, screenplay/data.jsx

/* ---------------- 第二栏:作品、剧集、场次 ---------------- */
// 照搬剧本 / 场次页的第二栏(m-ctx / sp-ep / sp-scene-row),只负责定位,不重复片段明细:
// 分镜视图里点场次滚到这一场,画布视图里点场次定位到这一场的色带。
function DrEpisodeRail({ sceneId, onSelectScene, onSelectEp, onCollapse, onBack }) {
  const episodes = SP_EPISODES.filter((e) => e.proj === DR_PROJECT.id && e.season === DR_EPISODE.season);
  return (
    <aside className="m-ctx">
      {/* 对齐 Flutter ContextColumnScaffold:左返回(离开作品),右折叠整个左侧栏。 */}
      <div className="m-ctx__head">
        <button type="button" className="m-icon-btn" title="返回" onClick={onBack}>
          <Icon name="caret-left" size={16} />
        </button>
        <span style={{ flex: 1 }} />
        <button type="button" className="m-icon-btn" title="折叠侧栏" onClick={onCollapse}>
          <SidebarCollapseIcon base={window.CV_BASE} />
        </button>
      </div>
      <button className="m-ctx__novel" type="button">
        <span className="m-avatar m-avatar--user" style={{ width: 36, height: 36 }}>{DR_PROJECT.title.slice(0, 1)}</span>
        <span className="m-ui-medium dr-rail__novel">{DR_PROJECT.title}</span>
        <Icon name="caret-down" size={12} />
      </button>
      <div className="m-ctx__sec-head">
        <span className="m-ctx__sec-title">剧集</span>
        <span className="m-ctx__sec-count">{episodes.length}</span>
      </div>
      <div className="sp-eps">
        {episodes.map((e) => (
          <button key={e.id} type="button" className={"sp-ep" + (e.id === DR_EPISODE.id ? " is-active" : "")} onClick={() => onSelectEp(e)}>
            <span>{e.label}</span>
            <span className="sp-ep__title">{e.title}</span>
            <span className="sp-ep__meta">{SP_SCENES.filter((x) => x.ep === e.id).length} 场</span>
          </button>
        ))}
      </div>
      <div className="m-ctx__sec-head">
        <span className="m-ctx__sec-title">场次</span>
        <span className="m-ctx__sec-count">{DR_SCENES.length}</span>
      </div>
      <div className="sp-scenes">
        {DR_SCENES.map((sc) => (
          <button key={sc.id} type="button" className={"sp-scene-row" + (sc.id === sceneId ? " is-active" : "")} onClick={() => onSelectScene(sc.id)}>
            <span className="sp-scene-row__main">
              <span className="sp-scene-row__no">{sc.no}、</span>
              <span className="sp-scene-row__place">{sc.title || sc.place}</span>
            </span>
            <span className="sp-scene-row__cond">{sc.title ? `${sc.place} · ` : ""}{sc.time} / {sc.ie}</span>
          </button>
        ))}
      </div>
    </aside>
  );
}

/* ---------------- 添加节点 ----------------
   画布底部「＋」与双击空白处打开同一份菜单。按节点类型列:片段 / 视频 / 图片 / 视频素材 / 音频 / 3D 导演台。
   不列角色、场景、文本:角色沿用剧本人物模型,文本与场景资产不是可上传媒体;多轨剪辑不在 MVP。
   点类型就在画布上直接新建节点,内容在节点上再填:
     片段       属于落点所在场次色带的那一场,排在这一场末尾,进成片
     视频       自由试验,不进成片;结果登记为资产,片段可以从资产库选它采用;也可以连给别的节点当参考
     图片       图片节点:生成一张图,或直接上传;可作为视频节点的参考图 / 首尾帧
     视频素材/音频  建一个空素材节点,在节点上拖入文件、从资产库选或导入
     3D 导演台  建落点所在场次的导演工程并打开导演台;一场一个,已有就定位原节点 */
const DR_ADD_ITEMS = [
  { key: "seg",      icon: "film-strip",          label: "片段",     sub: "落点所在场次，排在这一场末尾，进成片" },
  { key: "video",    icon: "video-camera",        label: "视频",     sub: "自由试验，不进成片；结果可被片段采用或作为参考" },
  { key: "image",    icon: "image",               label: "图片",     sub: "生成或上传；角色图、场景图、首尾帧" },
  { key: "clip",     icon: "play",                label: "视频素材", sub: "外部素材、导演预演" },
  { key: "audio",    icon: "waveform",            label: "音频",     sub: "录音、配音、音乐" },
  { key: "director", icon: "person-simple-walk",  label: "3D 导演台", sub: "落点所在场次的导演工程，一场一个" },
];

function DrAddMenu({ at, onCreate, onImport, onClose }) {
  // 从底部「＋」打开:贴在加号上方居中;双击画布打开:贴在鼠标处。
  const style = !at ? { left: "50%", bottom: 84, transform: "translateX(-50%)" }
    : at.dock ? { left: at.x, bottom: window.innerHeight - at.y + 12, transform: "translateX(-50%)" }
    : { left: at.x, top: at.y };
  return (
    <div className="dr-modal dr-modal--clear" onPointerDown={onClose}>
      <div className="dr-pop dr-addmenu" style={style} onPointerDown={(e) => e.stopPropagation()}>
        <div className="dr-addmenu__title">添加节点</div>
        {DR_ADD_ITEMS.map((it) => (
          <button key={it.key} type="button" className="dr-addmenu__item" onClick={() => onCreate(it.key)}>
            <span className="dr-addmenu__icon"><CvIcon name={it.icon} size={18} color="var(--text-secondary)" /></span>
            <span className="dr-pop__text">
              <span className="dr-addmenu__label">{it.label}</span>
              <span className="dr-pop__desc">{it.sub}</span>
            </span>
          </button>
        ))}
        <div className="dr-addmenu__title">添加资源</div>
        <button type="button" className="dr-addmenu__item" onClick={onImport}>
          <span className="dr-addmenu__icon"><CvIcon name="upload" size={18} color="var(--text-secondary)" /></span>
          <span className="dr-addmenu__label">上传</span>
        </button>
      </div>
    </div>
  );
}

/* ---------------- 画布浮动控件 ----------------
   形态对齐真实 Flutter 画布(lib/desktop/features/canvas/widgets/canvas_board.dart):
   竖排浮动簇,按钮 40×38,圆角 + 细边框 + 轻投影;缩放簇:放大 / 百分比 / 缩小 / 适配视图,
   适配按钮上方一条分隔线,步长 1.25。
   左下:缩放簇叠在画布工具(资产管理 / 上传 / 整理布局)上方,两簇同宽成一列,资产抽屉打开时一起右移;
   底部居中:添加节点「＋」;右下角留给 AI 悬浮球(chat.jsx DrAgentFab),展开的 AI 面板也只占右侧,
   不会盖住缩放。 */
function DrClusterBtn({ icon, title, onClick, on, sep, children }) {
  return (
    <button type="button" className={"dr-cluster__btn" + (on ? " is-on" : "") + (sep ? " is-sep" : "")}
      title={title} onClick={onClick}>
      {children || <CvIcon name={icon} size={17} color="currentColor" />}
    </button>
  );
}

function DrCanvasStack({ drawerOpen, children }) {
  return <div className={"dr-lstack" + (drawerOpen ? " is-shifted" : "")}>{children}</div>;
}

function DrCanvasTools({ drawerOpen, onToggleDrawer, onImport, onLayout }) {
  return (
    <div className="dr-cluster dr-cluster--tools" onPointerDown={(e) => e.stopPropagation()}>
      <DrClusterBtn icon="folder" title="资产管理" on={drawerOpen} onClick={onToggleDrawer} />
      <DrClusterBtn icon="upload" title="上传" onClick={onImport} />
      <DrClusterBtn icon="tree-structure" title="整理布局：按场次重新排列节点" onClick={onLayout} />
    </div>
  );
}

function DrZoomCluster({ zoom, onZoom, onFit }) {
  return (
    <div className="dr-cluster dr-cluster--zoom" onPointerDown={(e) => e.stopPropagation()}>
      <DrClusterBtn icon="plus" title="放大" onClick={() => onZoom(1)} />
      <DrClusterBtn title="当前缩放"><span className="dr-cluster__zoom">{zoom}%</span></DrClusterBtn>
      <DrClusterBtn icon="minus" title="缩小" onClick={() => onZoom(-1)} />
      <DrClusterBtn icon="frame-corners" title="适配视图" sep onClick={onFit} />
    </div>
  );
}

function DrAddDock({ onAdd, addOpen }) {
  return (
    <div className="dr-dock dr-dock--center" onPointerDown={(e) => e.stopPropagation()}>
      <button type="button" className={"dr-dock__add" + (addOpen ? " is-on" : "")} title="添加节点"
        onClick={(e) => {
          const r = e.currentTarget.getBoundingClientRect();
          onAdd({ x: r.left + r.width / 2, y: r.top, dock: true });
        }}>
        <CvIcon name={addOpen ? "x" : "plus"} size={20} color="currentColor" />
      </button>
    </div>
  );
}

/* ---------------- 资产抽屉(资产管理) ----------------
   从画布左侧滑出,浏览统一资产库;点一项放到画布中心。已在画布上的标出来,不阻止再放一个
   (同一资产可以有多个素材节点,连线时按资产去重)。 */
function DrAssetDrawer({ nodes, onPlace, onImport, onClose }) {
  const [tab, setTab] = React.useState("all");
  const tabs = [["all", "全部"], ["image", "图片"], ["video", "视频"], ["audio", "音频"], ["director", "导演"]];
  const list = SP_ASSETS.filter((a) => a.type !== "style" && a.type !== "text")
    .filter((a) => tab === "all" || a.type === tab);
  return (
    <aside className="dr-drawer" onPointerDown={(e) => e.stopPropagation()} onWheel={(e) => e.stopPropagation()}>
      <div className="dr-drawer__head">
        <span className="dr-drawer__title">资产管理</span>
        <span className="cv-spacer" />
        <button type="button" className="cv-iconbtn" title="上传" onClick={onImport}><CvIcon name="upload" size={14} /></button>
        <button type="button" className="cv-iconbtn" title="收起" onClick={onClose}><CvIcon name="x" size={14} /></button>
      </div>
      <div className="dr-drawer__tabs">
        {tabs.map(([k, l]) => (
          <button key={k} type="button" className={"dr-drawer__tab" + (tab === k ? " is-on" : "")} onClick={() => setTab(k)}>{l}</button>
        ))}
      </div>
      <div className="dr-drawer__grid">
        {list.map((a) => {
          const placed = nodes.some((n) => n.assetId === a.id);
          return (
            <button key={a.id} type="button" className="dr-drawer__card" title={`${a.source} · 点击放到画布`} onClick={() => onPlace(a.id)}>
              <span className="dr-drawer__pv">
                {a.type === "director"
                  ? <CvIcon name="cube" size={22} color="var(--dr-director)" />
                  : <DrAssetThumb asset={a} h={a.type === "audio" ? 32 : 70} />}
                {placed && <span className="dr-drawer__placed">已在画布</span>}
              </span>
              <span className="dr-drawer__name">{a.name}</span>
              <span className="dr-drawer__meta">{DR_ASSET_TYPES[a.type].label} · {a.source}</span>
            </button>
          );
        })}
      </div>
    </aside>
  );
}

/* ---------------- 资产库选择 ----------------
   mode="place":放到画布(可多选);mode="input":给某个视频节点加输入,选一个并定用途;
   mode="fill":给空素材节点选内容,只列该媒体类型,选一个。
   mode="adopt":给片段 / 视频节点选一个视频资产作为采用结果(比如某个视频节点生成的结果),只列视频,选一个。 */
function DrAssetPicker({ mode, target, initialTab, onPlace, onAddInput, onFill, onClose }) {
  const [tab, setTab] = React.useState(initialTab || "all");
  const [picked, setPicked] = React.useState([]);
  const model = target ? drModel(target.cfg.gen.model) : null;
  const roles = target ? drRolesFor(model, target.cfg.gen.mode) : [];
  const accept = new Set(roles.map((r) => DR_ROLES[r].accepts));
  const single = mode === "fill" || mode === "adopt";
  const tabs = single ? [[initialTab, DR_ASSET_TYPES[initialTab].label]]
    : [["all", "全部"], ["image", "图片"], ["video", "视频"], ["audio", "音频"], ["director", "导演工程"]];
  const list = SP_ASSETS.filter((a) => a.type !== "style" && a.type !== "text")
    .filter((a) => tab === "all" || a.type === tab)
    .filter((a) => mode !== "input" || a.type !== "director")
    .filter((a) => !single || a.type === initialTab);
  const toggle = (id) => setPicked((p) => (mode !== "place" ? [id] : p.includes(id) ? p.filter((x) => x !== id) : [...p, id]));
  const one = picked[0] && spAsset(picked[0]);
  const role = one && roles.find((r) => DR_ROLES[r].accepts === one.type);

  return (
    <div className="dr-modal" onPointerDown={onClose}>
      <div className="dr-dialog dr-lib" onPointerDown={(e) => e.stopPropagation()}>
        <div className="dr-dialog__head">
          <span className="dr-dialog__title">{mode === "input" ? `资产库 · 添加输入到${target.label}` : mode === "adopt" ? `资产库 · 选择${target.label}采用的视频` : mode === "fill" ? `资产库 · 选择${DR_ASSET_TYPES[initialTab].label}` : "资产库"}</span>
          {mode === "input" && <span className="dr-dialog__sub">{model.name} · {SP_GEN_MODES[target.cfg.gen.mode]}</span>}
          <span className="cv-spacer" />
          <button type="button" className="cv-iconbtn" onClick={onClose}><CvIcon name="x" size={15} /></button>
        </div>
        <div className="dr-lib__tabs">
          {tabs.map(([k, l]) => (
            <button key={k} type="button" className={"dr-views__btn" + (tab === k ? " is-on" : "")} onClick={() => setTab(k)}>{l}</button>
          ))}
          <span className="cv-spacer" />
          <button type="button" className="cv-btn cv-btn--outline"><CvIcon name="upload" size={13} />上传</button>
        </div>
        <div className="dr-lib__grid">
          {list.map((a) => {
            const blocked = mode === "input" && !accept.has(a.type);
            const on = picked.includes(a.id);
            return (
              <button key={a.id} type="button" disabled={blocked}
                className={"dr-lib__card" + (on ? " is-on" : "") + (blocked ? " is-blocked" : "")}
                title={blocked ? `${model.name} 当前模式不接受${DR_ASSET_TYPES[a.type].label}` : a.source}
                onClick={() => toggle(a.id)}>
                <span className="dr-lib__pv">
                  {a.type === "director"
                    ? <CvIcon name="cube" size={26} color="var(--dr-director)" />
                    : <DrAssetThumb asset={a} h={a.type === "audio" ? 40 : 96} />}
                </span>
                <span className="dr-lib__name">{a.name}</span>
                <span className="dr-lib__meta">{DR_ASSET_TYPES[a.type].label} · {a.source}</span>
                {on && <span className="dr-lib__check"><CvIcon name="check" size={11} color="var(--on-accent)" /></span>}
              </button>
            );
          })}
        </div>
        <div className="dr-dialog__foot">
          {mode === "input" && one ? (
            <span className="dr-dialog__meta">用途：<b>{DR_ROLES[role].label}</b> · 会在画布上补一条输入连线，可在节点里改用途和顺序</span>
          ) : (
            <span className="dr-dialog__meta">{picked.length ? `已选 ${picked.length} 个` : "角色图、场景图、导演输出都在这里"}</span>
          )}
          <span className="cv-spacer" />
          <button type="button" className="cv-btn" onClick={onClose}>取消</button>
          <button type="button" className="cv-btn cv-btn--primary" disabled={!picked.length}
            onClick={() => (mode === "input" ? onAddInput(picked[0], role) : single ? onFill(picked[0]) : onPlace(picked))}>
            {mode === "input" ? "添加为输入" : mode === "adopt" ? "采用" : mode === "fill" ? "使用" : "放到画布"}
          </button>
        </div>
      </div>
    </div>
  );
}

/* ---------------- 拖线松手:选用途 ----------------
   只列这个来源类型能承担、且当前模型 + 生成方式可用的用途;已是输入的来源直接提示改原输入。
   asset 是来源的媒体:素材节点是资产本身,视频节点是它采用的结果(未采用时是空帧,按视频算)。 */
function DrRolePopover({ at, asset, target, existing, onPick, onClose }) {
  const model = drModel(target.cfg.gen.model);
  const roles = drRolesFor(model, target.cfg.gen.mode);
  const opts = Object.entries(DR_ROLES).filter(([, r]) => r.accepts === asset.type);
  return (
    <div className="dr-modal dr-modal--clear" onPointerDown={onClose}>
      <div className="dr-pop dr-rolepop" style={{ left: at.x + 8, top: at.y + 8 }} onPointerDown={(e) => e.stopPropagation()}>
        <div className="dr-pop__head">
          <DrAssetThumb asset={asset} h={22} />
          <span className="dr-pop__name">{asset.name} → {target.label}</span>
        </div>
        {existing ? (
          <div className="dr-pop__empty">
            它已经是「{DR_ROLES[existing.role].label}」输入。同一节点里一个来源只承担一个用途，改用途请在输入列表里修改。
          </div>
        ) : opts.map(([k, r]) => {
          const ok = roles.includes(k);
          return (
            <button key={k} type="button" className="dr-pop__item" disabled={!ok} onClick={() => onPick(k)}>
              <span className="dr-pop__name">{r.label}</span>
              <span className="dr-pop__meta">{ok ? "" : target.cfg.gen.mode === "text" ? "纯文本不带输入" : `${model.name} ${SP_GEN_MODES[target.cfg.gen.mode]}不支持`}</span>
            </button>
          );
        })}
        {!existing && !opts.some(([k]) => roles.includes(k)) && (
          <div className="dr-pop__empty">先在节点里换生成方式或模型</div>
        )}
      </div>
    </div>
  );
}

/* ---------------- 选中连线 ---------------- */
// edge.asset / edge.fromLabel 由 app 解析:素材来源是资产本身,视频来源是它采用的结果。
function DrEdgeBar({ edge, onRole, onUnlink, onClose }) {
  const a = edge.asset;
  return (
    <div className="dr-edgebar">
      <DrAssetThumb asset={a} h={22} />
      <span className="dr-edgebar__name">{edge.fromLabel}</span>
      <CvIcon name="arrow-right" size={12} color="var(--text-muted)" />
      <span className="dr-edgebar__name">{edge.toLabel}</span>
      <span className="cv-toolbar__sep" />
      <DrSelect value={edge.role} width={88} onChange={onRole}
        options={Object.entries(DR_ROLES).filter(([, r]) => r.accepts === a.type).map(([k, r]) => ({ value: k, label: r.label }))} />
      <button type="button" className="cv-btn cv-btn--danger" onClick={onUnlink}>
        <CvIcon name="trash-simple" size={12} />断开
      </button>
      <button type="button" className="cv-iconbtn" onClick={onClose}><CvIcon name="x" size={13} /></button>
    </div>
  );
}

/* ---------------- 提交前预览 ----------------
   原稿(带 @chip) → 按供应商合同编译后的最终文本 → 有序媒体槽。确认后才建任务、才计费。
   视频来源在这里解析成它当前采用的结果,写进任务快照;之后再改提示词、连线或上游采用,不影响这次任务。 */
function DrSubmitDialog({ label, cfg, epStyle, inputs, sample, onConfirm, onClose }) {
  const model = drModel(cfg.gen.model);
  const image = cfg.kind === "image";
  const st = drStyleOf(cfg, epStyle);
  const slotOf = {};
  inputs.forEach((i) => { slotOf[i.key] = i.slot; });
  // 风格提示词追加在末尾,和原稿分段;无风格时不追加。
  const body = spPromptParts(cfg.prompt).map((p) => (p.ref ? `[${slotOf[p.ref.assetId]}]` : p.text)).join("");
  const finalText = [body, st.prompt].filter(Boolean).join("\n\n");
  const secs = drSecs(cfg.ms);
  return (
    <div className="dr-modal" onPointerDown={onClose}>
      <div className="dr-dialog dr-submit" onPointerDown={(e) => e.stopPropagation()}>
        <div className="dr-dialog__head">
          <span className="dr-dialog__title">{sample ? "提交样片" : "提交生成"} · {label}</span>
          <span className="dr-dialog__sub">{model.name} · {model.channel} · {model.adapter}</span>
          <span className="cv-spacer" />
          <button type="button" className="cv-iconbtn" onClick={onClose}><CvIcon name="x" size={15} /></button>
        </div>
        <div className="dr-submit__body">
          <div className="dr-submit__col">
            <div className="dr-sec__title">提示词原稿</div>
            <div className="dr-prompt dr-prompt--ro"><DrPromptView prompt={cfg.prompt} inputKeys={new Set(inputs.map((i) => i.key))} /></div>
            <div className="dr-sec__title" style={{ marginTop: 16 }}>实际发送的文本</div>
            <div className="dr-prompt dr-prompt--ro dr-prompt--mono">{finalText}</div>
            <div className="dr-muted dr-submit__note">引用按 {model.name} 的媒体槽写法替换，位置不变；{st.prompt ? "末尾追加风格提示词。" : "无风格，不追加。"}</div>
          </div>
          <div className="dr-submit__col">
            <div className="dr-sec__title">媒体输入 · {inputs.length}</div>
            <table className="dr-slots">
              <tbody>
                {inputs.map((i) => {
                  const a = drInputAsset(i);
                  return (
                    <tr key={i.id}>
                      <td><span className="dr-slot-tag">{i.slot}</span></td>
                      <td><DrAssetThumb asset={a} h={28} /></td>
                      <td>
                        <div className="dr-input__name">{i.name}</div>
                        <div className="dr-muted">{i.src ? `${a.name} · ${a.spec}` : a.spec}</div>
                      </td>
                      <td className="dr-muted">{DR_ROLES[i.role].label}</td>
                    </tr>
                  );
                })}
                {!inputs.length && <tr><td className="dr-muted">无媒体输入</td></tr>}
              </tbody>
            </table>
            <div className="dr-sec__title" style={{ marginTop: 16 }}>参数</div>
            <div className="dr-kv"><span>风格</span><b>{st.name}{st.inherited ? "（跟随剧集）" : ""}</b></div>
            {!image && <div className="dr-kv"><span>生成方式</span><b>{SP_GEN_MODES[cfg.gen.mode]}</b></div>}
            {!image && <div className="dr-kv"><span>时长</span><b>{secs}s</b></div>}
            <div className="dr-kv"><span>{image ? "比例 / 清晰度" : "画幅 / 分辨率"}</span><b>{cfg.gen.ratio} · {sample ? `${model.sample.res} 样片` : cfg.gen.res}</b></div>
            <div className="dr-kv"><span>预估供应商费用</span><b>¥{image ? model.pricePerImage.toFixed(2) : (secs * (sample ? model.sample.pricePerSec : model.pricePerSec)).toFixed(1)}</b></div>
            {sample && (
              <div className="dr-kv"><span>转成片</span><b>{model.sample.days} 天内 · {model.sample.finalRes} · 预估 ¥{(secs * model.sample.finalPricePerSec).toFixed(1)}</b></div>
            )}
          </div>
        </div>
        <div className="dr-dialog__foot">
          <span className="dr-dialog__meta">{sample ? "生成一个样片" : "生成一个结果"} · 成功后自动采用 · 关闭页面不会取消任务 · 结果保存在本机</span>
          <span className="cv-spacer" />
          <button type="button" className="cv-btn" onClick={onClose}>取消</button>
          <button type="button" className="cv-btn cv-btn--primary" onClick={onConfirm}>
            <CvIcon name="sparkle" size={14} />{sample ? "生成样片" : "确认生成"}
          </button>
        </div>
      </div>
    </div>
  );
}

/* ---------------- 样片转成片 ----------------
   按样片任务 ID 出 1080P 成片:提示词、输入、时长、画幅都沿用样片当时的快照,这里只读展示,不能改。
   出样片后又改过提示词或输入时提示一句 —— 想用新内容就得重新出样片。成功后自动采用,样片留在结果里。 */
function DrCompleteSampleDialog({ label, cfg, task, n, onConfirm, onClose }) {
  const model = drModel(task.model);
  const res = spAsset(task.result);
  return (
    <div className="dr-modal" onPointerDown={onClose}>
      <div className="dr-dialog dr-complete" onPointerDown={(e) => e.stopPropagation()}>
        <div className="dr-dialog__head">
          <span className="dr-dialog__title">生成成片 · {label}</span>
          <span className="dr-dialog__sub">{model.name} · {model.channel}</span>
          <span className="cv-spacer" />
          <button type="button" className="cv-iconbtn" onClick={onClose}><CvIcon name="x" size={15} /></button>
        </div>
        <div className="dr-complete__body">
          <div className="dr-complete__src">
            <DrFrame tone={res.tone} w={54} play figures={0} />
            <span className="dr-hist__text">
              <span className="dr-hist__line">第 {n} 次 <span className="dr-sample-tag">样片</span></span>
              <span className="dr-muted">{task.at} · {task.secs}s · {cfg.gen.ratio} · 480P</span>
              <span className="dr-muted">{task.expires} 前可用</span>
            </span>
          </div>
          <div className="dr-kv"><span>提示词与输入</span><b>沿用样片</b></div>
          <div className="dr-kv"><span>时长 / 画幅</span><b>{task.secs}s · {cfg.gen.ratio}</b></div>
          <div className="dr-kv"><span>分辨率</span><b>{model.sample.finalRes}</b></div>
          <div className="dr-kv"><span>预估供应商费用</span><b>¥{(task.secs * model.sample.finalPricePerSec).toFixed(1)}</b></div>
          {cfg.editedSinceSample && (
            <div className="dr-issue dr-issue--warn">
              <CvIcon name="warning-circle" size={12} />出样片后改过提示词，成片不包含这些修改；要用新提示词请重新出样片
            </div>
          )}
        </div>
        <div className="dr-dialog__foot">
          <span className="dr-dialog__meta">成功后自动采用 · 样片保留在结果里</span>
          <span className="cv-spacer" />
          <button type="button" className="cv-btn" onClick={onClose}>取消</button>
          <button type="button" className="cv-btn cv-btn--primary" onClick={onConfirm}>
            <CvIcon name="sparkle" size={14} />生成成片
          </button>
        </div>
      </div>
    </div>
  );
}

/* ---------------- 导出前的样片提醒 ----------------
   有分镜采用的是 480P 样片时先停一下:逐条列出期限,可在这里逐条转成片;照样导出就按当前采用的文件导出。 */
function DrExportSamplesDialog({ rows, onComplete, onExport, onClose }) {
  return (
    <div className="dr-modal" onPointerDown={onClose}>
      <div className="dr-dialog dr-exportsamples" onPointerDown={(e) => e.stopPropagation()}>
        <div className="dr-dialog__head">
          <span className="dr-dialog__title">{rows.length} 段在用 480P 样片</span>
          <span className="cv-spacer" />
          <button type="button" className="cv-iconbtn" onClick={onClose}><CvIcon name="x" size={15} /></button>
        </div>
        <div className="dr-exportsamples__list">
          {rows.map(({ node, info }) => (
            <div key={node.id} className="dr-hist__row">
              <DrFrame tone={spAsset(node.adopted).tone} w={34} play figures={0} />
              <span className="dr-hist__text">
                <span className="dr-hist__line"><span className="dr-shotno">段 {drSegNo(node)}</span>{node.title}</span>
                <span className="dr-muted">
                  {info.completing ? `成片生成中 ${info.completing.progress}%`
                    : info.expired ? `已过成片期限（${info.task.expires}）` : `${info.task.expires} 前可转成片`}
                </span>
              </span>
              <span className="dr-hist__acts">
                {info.canComplete && (
                  <button type="button" className="cv-btn cv-btn--outline dr-cand__btn" onClick={() => onComplete(node, info)}>生成成片</button>
                )}
              </span>
            </div>
          ))}
        </div>
        <div className="dr-dialog__foot">
          <span className="cv-spacer" />
          <button type="button" className="cv-btn" onClick={onClose}>取消</button>
          <button type="button" className="cv-btn cv-btn--primary" onClick={onExport}>照样导出</button>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, {
  DrEpisodeRail, DrAddMenu, DrCanvasStack, DrCanvasTools, DrZoomCluster, DrAddDock, DrAssetDrawer, DrAssetPicker, DrRolePopover, DrEdgeBar, DrSubmitDialog, DrCompleteSampleDialog, DrExportSamplesDialog,
});
