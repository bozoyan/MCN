// screenplay/views.jsx — 剧本写作的第二列(剧集 + 场次)与主区各分区。
// 由 EditorView 在 novel.screenplay 存在时渲染,复用编辑器三列框架:
//   NavRail | ScreenplayContext | ScreenplayWorkspace | AgentPanel(不变)
// 分区:概览 / 剧本 / 大纲 / 节拍 / 场次(列表·场次板·出场矩阵) / 关系图谱。
// 制作(场次下的片段)只在独立的制片页 drama/Drama.html,剧本这里不放制作界面。
// 全局名统一 Sp 前缀,避免与其他原型脚本的全局名冲突。

/* ============================ 数据小工具 ============================ */

function spScenesOf(projId, epId) {
  return SP_SCENES.filter((s) => s.proj === projId && (epId ? s.ep === epId : true));
}
// seasonId 为空 = 整部剧集的集;集号在季内从 1 重来,所以凡是按集号显示的地方
// (出场矩阵列头、状态栏)都要传 seasonId,不能跨季拼。
function spEpisodesOf(projId, seasonId) {
  return SP_EPISODES.filter(
    (e) => e.proj === projId && (seasonId ? e.season === seasonId : true)
  );
}
function spCharsOf(projId) {
  return SP_CHARS.filter((c) => c.proj === projId);
}
// 场次头语序 —— 地点在前,时间与内外作为一组拍摄条件跟在后面:
//   1、嘉兴码头　昏 / 外
// 华语/日韩剧本都是地点优先(日韩甚至不标内外);把 INT./EXT. 提到最前是美式
// 惯例,因为内外景是好莱坞通告单的第一分类键。中文场景名自带内外信息,不需要。
// 斜线只绑定「时间 / 内外」这一组,不用来劈开地点。
function spSlug(scene) {
  return `${scene.place} ${scene.time} / ${scene.ie}`;
}

/* ---- 场次的四个新字段（阶段 M，方案 §4.1） ---- */

// 场次在列表里的显示名：有短标题用短标题，没有就回退地点。
// 回退只发生在展示层 —— 数据里的 title 仍然是空串，不从梗概截取回填(§3.1)。
// 正文不走这个函数：正文场次头永远显示 place，见 SpElement 的 scene 分支。
function spSceneName(scene) {
  return scene.title || scene.place;
}

// 短标题顶掉地点之后，地点得有地方去 —— 跟时间、内外一起降成次行。
// 没有短标题时地点已经在主行了，次行就只剩时间和内外，不重复一遍地点。
function spSceneCond(scene) {
  const cond = `${scene.time} / ${scene.ie}`;
  return scene.title ? `${scene.place} · ${cond}` : cond;
}

// 「内外」在 mockup 里就是 ie 的第三个字符串取值，没有分支要改。
// 真实实现不是这样：§11.1 点名了三处 switch / 三元对未知取值静默回退成
// 「外景」或空字符串，加取值的成本全在那三处，不在 schema。
const SP_IE_VALUES = ["内", "外", "内外"];

// 目标秒数 → 「2 分 30 秒」。null 是没填，调用方自己决定显示什么，不在这里造 0。
function spSecsLabel(secs) {
  if (secs == null) return null;
  if (secs < 60) return `${secs} 秒`;
  const m = Math.floor(secs / 60);
  const rest = secs % 60;
  return rest ? `${m} 分 ${rest} 秒` : `${m} 分`;
}

/* ============================ 通用小件 ============================ */

function SpChip({ icon, children, tone }) {
  return (
    <span className={"sp-chip" + (tone ? ` sp-chip--${tone}` : "")}>
      {icon && <Icon name={icon} size={12} />}
      {children}
    </span>
  );
}

function SpState({ state }) {
  return <span className={`sp-state sp-state--${state}`}>{state}</span>;
}

// 八分之一页要排成真正的带分数 —— 直接写 "1 6/8 页" 会被读成 "16/8"。
function SpPages({ value, unit = "页" }) {
  const m = /(\d+)\s+(\d)\/8/.exec(value || "");
  if (!m) return <span className="sp-pages">{value} {unit}</span>;
  const whole = Number(m[1]);
  const num = Number(m[2]);
  return (
    <span className="sp-pages">
      {(whole > 0 || num === 0) && <span>{whole}</span>}
      {num > 0 && (
        <span className="sp-pages__frac">
          <sup>{num}</sup>⁄<sub>8</sub>
        </span>
      )}
      <span className="sp-pages__unit">{unit}</span>
    </span>
  );
}

// 把 "@沈砚 递出短烛" 里的 @角色 渲染成提及 chip。
function SpAtText({ text, projId }) {
  const chars = spCharsOf(projId);
  if (!chars.length) return <React.Fragment>{text}</React.Fragment>;
  const names = chars.map((c) => c.name).sort((a, b) => b.length - a.length);
  const re = new RegExp(`@(${names.join("|")})`, "g");
  const out = [];
  let last = 0;
  let m;
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) out.push(text.slice(last, m.index));
    const char = chars.find((c) => c.name === m[1]);
    out.push(
      <span key={`${m.index}-${m[1]}`} className={"sp-at" + (char.role === "主角" ? " sp-at--lead" : "")}>
        @{m[1]}
      </span>
    );
    last = m.index + m[0].length;
  }
  if (last < text.length) out.push(text.slice(last));
  return <React.Fragment>{out}</React.Fragment>;
}

// 情绪 badge —— 跟在场次标题后面，不混进下面那排 meta chip。
// 位置本身是区分手段：状态徽章永远在 meta 行，情绪永远在标题行，两者不会看混,
// 所以情绪可以用 accent 色而不必再发明一套色阶。
// 最多露两个，其余收成 +N —— 一场戏的主导情绪就那么一两个，列出五个等于没有重点。
function SpEmoBadges({ scene, max = 2 }) {
  const tags = scene.emotion || [];
  if (!tags.length && !scene.analysisStale) return null;
  const shown = tags.slice(0, max);
  const rest = tags.length - shown.length;
  return (
    <span className="sp-emos">
      {shown.map((t) => <span key={t} className="sp-emo">{t}</span>)}
      {rest > 0 && <span className="sp-emo sp-emo--more">+{rest}</span>}
      {/* 正文改过、整理结果还没重跑。旧值照显示，这一枚只说明它是旧的。 */}
      {scene.analysisStale && <span className="sp-emo sp-emo--stale">待核对</span>}
    </span>
  );
}

function SpSeg({ value, options, onChange }) {
  return (
    <div className="sp-seg">
      {options.map((o) => (
        <button
          key={o.id}
          type="button"
          className={"sp-seg__opt" + (value === o.id ? " is-active" : "")}
          onClick={() => onChange(o.id)}
        >
          <Icon name={o.icon} size={14} />
          <span>{o.label}</span>
        </button>
      ))}
    </div>
  );
}

/* ---------------------------- AI 改动 ---------------------------- */
// 跟章节侧完全同一套约定(ChatPanel 的「最近改动」卡):AI 的改动已经应用，
// 界面上不是「接受吗」的决策门，而是标出改了哪些 + 可以回退。文案也照搬，
// 不为剧本另发明一套「待接受 / 已拒绝」的词。
// 审阅单位是场次:AI 在一场里改了三处，这里也只有一条。
// 类型与 kit.css 的 CHANGE_TYPE 对齐。
const SP_CHANGE_TYPE = {
  create:  { label: "新增", icon: "plus",        color: "var(--accent-warm)" },
  rewrite: { label: "改写", icon: "note-pencil", color: "var(--accent)" },
  expand:  { label: "扩写", icon: "note-pencil", color: "var(--addition-border)" },
  trim:    { label: "删减", icon: "scissors",    color: "var(--deletion-border)" },
};

// 场次列表和场次表里的小圆点 —— 只说「这一场 AI 动过」，细节留给场次卡和正文。
function SpAiDot({ sceneId }) {
  const change = spAiChangeOf(sceneId);
  if (!change) return null;
  const t = SP_CHANGE_TYPE[change.change] || SP_CHANGE_TYPE.rewrite;
  return (
    <span
      className="sp-aidot"
      style={{ background: t.color }}
      title={`AI ${t.label} · ${change.field}`}
    />
  );
}

function SpAiBar({ sceneId }) {
  const change = spAiChangeOf(sceneId);
  if (!change) return null;
  const t = SP_CHANGE_TYPE[change.change] || SP_CHANGE_TYPE.rewrite;
  return (
    <div className={"sp-aibar sp-aibar--" + change.change}>
      <Icon name={t.icon} size={13} style={{ color: t.color }} />
      <span className="sp-aibar__label">AI {t.label} · {change.field}</span>
      <span className="sp-aibar__spacer" />
      <button type="button" className="sp-aibar__btn">查看变更</button>
      <button type="button" className="sp-aibar__btn">
        <Icon name="arrow-counter-clockwise" size={12} />
        回退
      </button>
      {/* 新建整场的回退后果和改一段正文不一样，必须说清楚，不能共用一句话。
          场次卡只有 340 宽，这一句放同一行会把提示条撑成一块，所以独占一行。 */}
      {change.hint && <span className="sp-aibar__hint">{change.hint}</span>}
    </div>
  );
}

function SpEmpty({ title, sub, action, onAction }) {
  return (
    <div className="sp-empty">
      <div className="sp-empty__title">{title}</div>
      <div className="sp-empty__sub">{sub}</div>
      {action && (
        <button className="m-btn m-btn--secondary m-btn--sm" style={{ marginTop: 16 }} onClick={onAction}>
          <Icon name="plus" size={14} />
          {action}
        </button>
      )}
    </div>
  );
}

/* ============================ 第二列:季 + 集 + 场次 ============================ */

// 集数的三种态共用这一枚：3 集 / 2/8 集 / 5/4 集 + 已超出规划。
// 超出规划是有效状态，不是错误 —— 用 warning 底色提示，不拦任何操作。
function SpEpisodeCount({ seasonId, showOver = true }) {
  const c = spEpisodeCount(seasonId);
  return (
    <React.Fragment>
      <span className={"sp-epcount" + (c.over ? " is-over" : "")}>{c.text}</span>
      {c.over && showOver && <span className="sp-overplan">已超出规划</span>}
    </React.Fragment>
  );
}

/* ============================ 管理季弹窗 ============================
   早先管理季是季选择器的第三态，内联在第二列里。第二列只有 200 出头，
   「季名 + 集数 + 规划输入 + 四个操作」挤不进一行，只能把每一季拆成三行读，
   重排时上下两季的前后关系反而看不全。改成 640px 弹窗之后一行就够 ——
   这是它离开第二列的唯一理由，不是为了「弹窗更正式」。

   「新增一季」关掉弹窗并直接跳进新的一季：新增之后要写的是那一季的第一集，
   停在管理列表里没有意义。 */
function SpSeasonManagerDialog({ proj, seasonId, onSelectSeason, onClose }) {
  const seasons = spSeasonsOf(proj.id);
  // null = 列表态；否则是正在改的那一季。编辑就地换掉列表，不再叠一层弹窗。
  const [editing, setEditing] = React.useState(null);
  const editSeason = editing ? spSeasonById(editing) : null;
  const only = seasons.length === 1;

  return (
    <div className="m-dialog-scrim" onClick={onClose}>
      <div
        className="m-dialog m-dialog--season"
        data-screen-label={editSeason ? "本季设置" : "管理季"}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="m-dialog__head">
          <span className="sp-smgr__title">{editSeason ? "本季设置" : "管理季"}</span>
          <button className="m-icon-btn" onClick={onClose} title="关闭">
            <Icon name="x" size={16} />
          </button>
        </div>

        {editSeason ? (
          <React.Fragment>
            <div className="sp-smgr__body">
              <SpFieldRow label="季标题" hint="留空就只显示季号">
                <div className="sp-input" contentEditable suppressContentEditableWarning
                  data-placeholder={`第 ${editSeason.no} 季`}>
                  {editSeason.title}
                </div>
              </SpFieldRow>
              {/* 规划是作者给自己定的目标，不是上限 —— 写超了只提示，不拦。 */}
              <SpFieldRow label="规划集数" hint="留空就只显示实际集数">
                <div className="sp-input sp-input--num" contentEditable suppressContentEditableWarning
                  data-placeholder="未设定">
                  {editSeason.planned == null ? "" : editSeason.planned}
                </div>
              </SpFieldRow>
            </div>
            <div className="sp-smgr__foot">
              <button type="button" className="m-btn m-btn--text" onClick={() => setEditing(null)}>
                取消
              </button>
              <button type="button" className="m-btn m-btn--primary" onClick={() => setEditing(null)}>
                保存
              </button>
            </div>
          </React.Fragment>
        ) : (
          <React.Fragment>
            <div className="sp-smgr__body">
              {seasons.map((s, i) => (
                <div key={s.id} className={"sp-smgr__card" + (s.id === seasonId ? " is-active" : "")}>
                  {/* 整块摘要就是「进入这一季」，不另设一个箭头按钮 —— 管理季时
                      最常做的事仍然是换一季去写。 */}
                  <button
                    type="button"
                    className="sp-smgr__sum"
                    onClick={() => { onSelectSeason(s.id); onClose(); }}
                  >
                    <span className="sp-smgr__name">{spSeasonLabel(s)}</span>
                    <span className="sp-smgr__meta"><SpEpisodeCount seasonId={s.id} /></span>
                  </button>
                  <div className="sp-smgr__acts">
                    <button type="button" className="sp-smgr__act" title="上移" disabled={i === 0}>
                      <Icon name="caret-up" size={15} />
                    </button>
                    <button type="button" className="sp-smgr__act" title="下移"
                            disabled={i === seasons.length - 1}>
                      <Icon name="caret-down" size={15} />
                    </button>
                    <button type="button" className="sp-smgr__act" title="本季设置"
                            onClick={() => setEditing(s.id)}>
                      <Icon name="pencil-simple" size={15} />
                    </button>
                    {/* 删一季会连着这一季的集、节拍、场次和正文一起删，第一期没有回收站，
                        所以删除只留在管理弹窗里，AI 不给这条路径。唯一一季没有删除入口。 */}
                    <button
                      type="button"
                      className="sp-smgr__act sp-smgr__act--danger"
                      title={only ? "至少保留一季" : "删除这一季"}
                      disabled={only}
                    >
                      <Icon name="trash-simple" size={15} />
                    </button>
                  </div>
                </div>
              ))}
            </div>
            <div className="sp-smgr__foot">
              <button type="button" className="m-btn m-btn--primary" onClick={onClose}>
                <Icon name="plus" size={13} />
                新增一季
              </button>
            </div>
          </React.Fragment>
        )}
      </div>
    </div>
  );
}

// 季选择器 —— 只有多季才渲染。单季时整个季这一层在界面上不存在：
// 没有选择器、没有「第 1 季」标签、也没有管理入口，唯一一季是隐式当前季。
function SpSeasonPicker({ proj, seasonId, onSelectSeason }) {
  const seasons = spSeasonsOf(proj.id);
  const [mode, setMode] = React.useState("closed");   // closed | list
  // 管理季是独立弹窗，不再是这个 popover 的第三态。
  const [manager, setManager] = React.useState(false);
  const current = spSeasonById(seasonId);

  return (
    <div className="sp-season">
      <button
        type="button"
        className={"sp-season__cur" + (mode !== "closed" ? " is-open" : "")}
        onClick={() => setMode(mode === "closed" ? "list" : "closed")}
      >
        <Icon name="film-strip" size={14} />
        <span className="sp-season__name">{spSeasonLabel(current)}</span>
        <SpEpisodeCount seasonId={seasonId} showOver={false} />
        <Icon name={mode === "closed" ? "caret-down" : "caret-up"} size={12} />
      </button>

      {mode === "list" && (
        <div className="sp-season__pop">
          {seasons.map((s) => (
            <button
              key={s.id}
              type="button"
              className={"sp-season__row" + (s.id === seasonId ? " is-active" : "")}
              onClick={() => { onSelectSeason(s.id); setMode("closed"); }}
            >
              {/* 季名和集数分两行 —— 第二列只有 200 出头，
                  "第 1 季 · 淤沙" + "5/4 集" + "已超出规划" 挤一行会把季名截成「第 ...」。 */}
              <span className="sp-season__row-name">{spSeasonLabel(s)}</span>
              <span className="sp-season__row-meta"><SpEpisodeCount seasonId={s.id} /></span>
            </button>
          ))}
          <div className="sp-season__div" />
          <button type="button" className="sp-season__act">
            <Icon name="plus" size={13} />
            新增一季
          </button>
          <button
            type="button"
            className="sp-season__act"
            onClick={() => { setMode("closed"); setManager(true); }}
          >
            <Icon name="sliders-horizontal" size={13} />
            管理季
          </button>
        </div>
      )}

      {manager && (
        <SpSeasonManagerDialog
          proj={proj}
          seasonId={seasonId}
          onSelectSeason={onSelectSeason}
          onClose={() => setManager(false)}
        />
      )}
    </div>
  );
}

function ScreenplayContext({ novel, seasonId, onSelectSeason, epId, onSelectEp, sceneId, onSelectScene, onBack }) {
  const proj = novel.screenplay;
  const seasons = spSeasonsOf(proj.id);
  const multi = seasons.length > 1;
  const episodes = spEpisodesOf(proj.id, seasonId);
  const scenes = spScenesOf(proj.id, epId);
  const [menuEp, setMenuEp] = React.useState(null);

  return (
    <aside className="m-ctx">
      <PanelHeader onBack={onBack} onCollapse={() => {}} />
      <NovelSwitcher novel={novel} />

      {multi && (
        <SpSeasonPicker proj={proj} seasonId={seasonId} onSelectSeason={onSelectSeason} />
      )}

      {episodes.length > 0 && (
        <React.Fragment>
          <div className="m-ctx__sec-head">
            <span className="m-ctx__sec-title">剧集</span>
            <span className="m-ctx__sec-count"><SpEpisodeCount seasonId={seasonId} /></span>
            <button className="m-icon-btn m-icon-btn--ghost" title="新增一集">
              <Icon name="plus" size={12} />
            </button>
          </div>
          <div className="sp-eps">
            {episodes.map((e) => (
              <div key={e.id} className="sp-ep-wrap">
                <button
                  type="button"
                  className={"sp-ep" + (e.id === epId ? " is-active" : "")}
                  onClick={() => onSelectEp(e.id)}
                >
                  <span>{e.label}</span>
                  <span className="sp-ep__title">{e.title}</span>
                  <span className="sp-ep__meta">{spScenesOf(proj.id, e.id).length} 场</span>
                </button>
                {/* 跨季移动是多季才有的操作，单季作品连这个入口都不出现。 */}
                {multi && (
                  <button
                    type="button"
                    className="sp-ep__more"
                    title="更多"
                    onClick={() => setMenuEp(menuEp === e.id ? null : e.id)}
                  >
                    <Icon name="dots-three" size={13} />
                  </button>
                )}
                {menuEp === e.id && (
                  <div className="sp-epmenu">
                    <div className="sp-epmenu__label">移动到其他季</div>
                    {seasons.filter((s) => s.id !== seasonId).map((s) => (
                      <button key={s.id} type="button" className="sp-epmenu__item">
                        {spSeasonLabel(s)}
                      </button>
                    ))}
                    {/* 每季至少留一集 —— 移走最后一集会让这一季没有可写的地方。 */}
                    {episodes.length === 1 && (
                      <div className="sp-epmenu__hint">本季只剩这一集，移走之后这一季就没有集了。</div>
                    )}
                    <div className="sp-season__div" />
                    <button type="button" className="sp-epmenu__item sp-epmenu__item--danger">
                      删除这一集
                    </button>
                  </div>
                )}
              </div>
            ))}
            {/* 单季作品把「新增一季」放在集列表底部 —— 它是低频操作，
                不值得为它在顶部常驻一个季选择器。 */}
            {!multi && (
              <button type="button" className="m-ctx__add sp-addseason">
                <Icon name="film-strip" size={14} />
                <span>新增一季</span>
              </button>
            )}
          </div>
        </React.Fragment>
      )}

      <div className="m-ctx__sec-head">
        <span className="m-ctx__sec-title">场次</span>
        <span className="m-ctx__sec-count">{scenes.length}</span>
        <button className="m-icon-btn m-icon-btn--ghost" title="新增场次">
          <Icon name="plus" size={12} />
        </button>
      </div>

      <div className="sp-scenes">
        {scenes.map((s) => (
          <button
            key={s.id}
            type="button"
            className={"sp-scene-row" + (s.id === sceneId ? " is-active" : "")}
            onClick={() => onSelectScene(s.id)}
          >
            {/* 主行是事件短标题，地点降到次行 —— 同一集里三场都叫「客船前舱」时，
                单行只有地点的列表读不出哪场是哪场。没写短标题就还是老样子：
                主行显示地点，次行只剩时间和内外，不重复一遍地点。 */}
            <span className="sp-scene-row__main">
              <span className="sp-scene-row__no">{s.no}、</span>
              <span className="sp-scene-row__place">{spSceneName(s)}</span>
              {/* 这一列 230 宽，是跳场次用的导航栏。情绪 badge 放这儿会把场次名挤没
                  （「藏匣」只剩一个顿号），所以不放 —— 情绪在正文和场次列表里看。 */}
              <SpAiDot sceneId={s.id} />
            </span>
            <span className="sp-scene-row__cond">{spSceneCond(s)}</span>
          </button>
        ))}
        <button type="button" className="m-ctx__add">
          <Icon name="plus" size={14} />
          <span>新增场次</span>
        </button>
      </div>
    </aside>
  );
}

/* ============================ 剧本正文 ============================ */

// 元素类型 —— 顺序即 ⌘1..⌘8,也是 Tab 循环的顺序。
const SP_ELEMENTS = [
  { id: "scene", label: "场次", icon: "grid-nine" },
  { id: "action", label: "动作", icon: "waves" },
  { id: "char", label: "角色", icon: "user" },
  { id: "paren", label: "括号", icon: "quotes" },
  { id: "dialog", label: "对话", icon: "chat-centered" },
  { id: "trans", label: "转场", icon: "arrow-right" },
  { id: "note", label: "注释", icon: "note-pencil" },
  { id: "sub", label: "字幕", icon: "text-t" },
];

function SpElementBar({ active, onPick }) {
  return (
    <div className="sp-eltbar">
      {/* 按钮组跟着正文栏走 —— 工具条说的是光标所在那一行的元素类型,
          它就该在那一栏正上方,而不是贴在主区最左边。 */}
      <div className="sp-eltbar__inner">
        {SP_ELEMENTS.map((el, i) => (
          <button
            key={el.id}
            type="button"
            className={"sp-elt" + (active === el.id ? " is-active" : "")}
            onClick={() => onPick(el.id)}
            title={`${el.label}（⌘${i + 1}）`}
          >
            <Icon name={el.icon} size={16} />
            <span>{el.label}</span>
            <span className="sp-elt__key">⌘{i + 1}</span>
          </button>
        ))}
      </div>
      <span className="sp-eltbar__hint">
        <span className="sp-kbd">Tab</span> 切换元素
        <span className="sp-kbd">Enter</span> 下一个
      </span>
    </div>
  );
}

// 正文场次头右侧那一块：情绪 badge（常驻，贴最右）。
// 整块 contentEditable={false} 且 user-select:none —— 它是界面元件，不是正文。
// 光标进不去、选不中、复制不走，导出的 screenplay.md 里也没有它，
// 正文本身仍然只有「场号、地点 时间/内外」这个标准剧本格式（§3.1）。
// 这也是为什么情绪能进正文而场次短标题不能：短标题长得就像正文的一部分，
// 情绪是 sans 小号 accent 色的 chip，一眼看得出不是稿子里的字。
//
// 没有「属性」按钮：场次头本身可点，点了就开属性（见 SpElement 的 scene 分支）。
// 一行里既有可点的标题、又有一个干同样事的按钮，是两个入口一件事。
function SpHeadingMeta({ scene }) {
  if (!scene) return null;
  return (
    <span className="sp-el__meta" contentEditable={false}>
      {/* 情绪贴最右 —— 一整集扫下来是一列对齐的调子，不跟着标题长短左右浮动。 */}
      <SpEmoBadges scene={scene} />
    </span>
  );
}

// 单条剧本元素。
function SpElement({ el, onFocus, caret, scene, onSceneProps }) {
  const common = {
    onMouseDown: () => onFocus(el.t),
    contentEditable: true,
    suppressContentEditableWarning: true,
  };
  const cls = (t) => `sp-el sp-el--${t}` + (caret === el ? " is-caret" : "");

  switch (el.t) {
    case "scene":
      // 场次头是结构化元素，不是自由文本：地点是地点实体的引用（属性里是下拉 +
      // 「新建地点」），内外景是枚举。所以这一行不可直接编辑，点一下开场次属性。
      return (
        <div
          className={cls("scene") + " is-clickable"}
          title="编辑场次属性"
          onMouseDown={() => onFocus(el.t)}
          onClick={() => scene && onSceneProps(scene)}
        >
          <span className="sp-el__no">{el.no}、</span>
          <span>{el.place}</span>
          <span className="sp-el__cond">
            {el.time}<span className="sp-el__sep">/</span>{el.ie}
          </span>
          <SpHeadingMeta scene={scene} />
        </div>
      );
    case "cast":
      return (
        <div className={cls("cast")} {...common}>
          出场人物：<b>{el.names.join("、")}</b>
        </div>
      );
    case "action":
      return <div className={cls("action")} {...common}>{el.text}</div>;
    case "char":
      return (
        <div className={cls("char")} {...common}>
          {el.name}
          {el.cont && <span className="sp-el__cont">（续）</span>}：
        </div>
      );
    case "paren":
      return <div className={cls("paren")} {...common}>（{el.text}）</div>;
    case "dialog":
      return <div className={cls("dialog")} {...common}>{el.text}</div>;
    case "trans":
      return <div className={cls("trans")} {...common}>{el.text}</div>;
    case "sub":
      // 内层 span 不是装饰 —— 居中/左对齐的切换靠它收缩到内容宽度来实现,见 css。
      return (
        <div className={cls("sub")} {...common}>
          <span className="sp-el__subtext">{el.text}</span>
        </div>
      );
    case "note":
      return <div className={cls("note")} {...common}>{el.text}</div>;
    default:
      return null;
  }
}

function SpScriptView({ proj, scenes, sceneId, onSelectScene, onSceneProps }) {
  const [element, setElement] = React.useState("action");
  const [caret, setCaret] = React.useState(null);
  const scrollRef = React.useRef(null);

  // 左栏点场次 → 正文滚到那一场。
  React.useEffect(() => {
    const node = scrollRef.current && scrollRef.current.querySelector(`[data-scene="${sceneId}"]`);
    if (node) node.scrollIntoView({ block: "start", behavior: "smooth" });
  }, [sceneId]);

  function focusElement(el, type) {
    setCaret(el);
    setElement(type);
  }

  return (
    <React.Fragment>
      <SpElementBar active={element} onPick={setElement} />
      <div className="sp-scroll" ref={scrollRef}>
        <div className="sp-page">
          {scenes.map((s) => {
            const body = SP_SCRIPT[s.id];
            return (
              <div
                key={s.id}
                data-scene={s.id}
                data-screen-label={`场 ${s.no}`}
                className={"sp-scene" + (spAiChangeOf(s.id) ? " has-ai" : "")}
              >
                <SpAiBar sceneId={s.id} />
                {body ? (
                  body.map((el, i) => (
                    <SpElement
                      key={i}
                      el={el}
                      caret={caret}
                      scene={s}
                      onSceneProps={onSceneProps}
                      onFocus={(t) => focusElement(el, t)}
                    />
                  ))
                ) : (
                  <React.Fragment>
                    <div className="sp-el sp-el--scene is-clickable" title="编辑场次属性"
                      onClick={() => onSceneProps(s)}>
                      <span className="sp-el__no">{s.no}、</span>
                      <span>{s.place}</span>
                      <span className="sp-el__cond">
                        {s.time}<span className="sp-el__sep">/</span>{s.ie}
                      </span>
                      <SpHeadingMeta scene={s} />
                    </div>
                    <div className="sp-el sp-el--cast">
                      出场人物：<b>{s.cast.join("、")}</b>
                    </div>
                    <div className="sp-el sp-el--note">{s.desc}</div>
                    <button
                      className="m-btn m-btn--secondary m-btn--sm"
                      style={{ marginTop: 12 }}
                      onClick={() => onSelectScene(s.id)}
                    >
                      <Icon name="pencil-simple" size={13} />
                      从梗概写这一场
                    </button>
                  </React.Fragment>
                )}
              </div>
            );
          })}
        </div>
      </div>
    </React.Fragment>
  );
}

/* ============================ 大纲 ============================ */

// 大纲的正文是一份 markdown 文档，随打字自动保存（600ms 静默后落盘），
// 切集或切分区时先落盘再走 —— 所以这里没有「保存」按钮，只有状态提示。
// 空文档不编内容，只给提示行，让写作者知道这一格该放什么。
function SpOutlineDoc({ text }) {
  if (!text) {
    return (
      <div className="sp-odoc__body sp-odoc__body--empty">
        把这一集的 Logline、Synopsis、人物弧光、主题写在这里……
      </div>
    );
  }
  // 编辑器是实时预览式的：光标不在的行只显示排版结果，标记本身收起来。
  return (
    <div className="sp-odoc__body" contentEditable suppressContentEditableWarning>
      {text.split("\n").map((line, i) => {
        if (!line.trim()) return <div key={i} className="sp-odoc__gap" />;
        if (line.startsWith("## ")) return <div key={i} className="sp-odoc__h">{line.slice(3)}</div>;
        if (line.startsWith("- ")) return <div key={i} className="sp-odoc__li">{line.slice(2)}</div>;
        return <div key={i} className="sp-odoc__p">{line}</div>;
      })}
    </div>
  );
}

// 大纲是「每集一份文档」：上半是这一集的大纲正文，下半只读列出这一集的结构节拍。
// 节拍的真源在节拍板 —— 这里不给增删改，只给「去节拍板编辑」这一个出口，
// 免得同一份数据出现两套编辑入口。场序不在这一页，去场次页的列表视图看。
function SpOutlineView({ proj, epId, onGoto }) {
  const ep = spEpisodesOf(proj.id).find((e) => e.id === epId);
  if (!ep) {
    return <SpEmpty title="还没有大纲" sub="先在左栏选一集，大纲按集写。" />;
  }

  const beats = SP_BEATS.filter((b) => b.proj === proj.id && b.ep === ep.id);
  const acts = SP_ACT_ORDER.filter((a) => beats.some((b) => b.act === a));

  return (
    <div className="sp-scroll">
      <div className="sp-pad">
        <div className="sp-outline">
          <div className="sp-odoc">
            <div className="sp-odoc__bar">
              <button className="m-icon-btn m-icon-btn--ghost" title="标题"><Icon name="text-t" size={15} /></button>
              <button className="m-icon-btn m-icon-btn--ghost" title="加粗"><Icon name="text-b" size={15} /></button>
              <button className="m-icon-btn m-icon-btn--ghost" title="斜体"><Icon name="text-italic" size={15} /></button>
              <span className="sp-odoc__sep" />
              <button className="m-icon-btn m-icon-btn--ghost" title="无序列表"><Icon name="list-bullets" size={15} /></button>
              <button className="m-icon-btn m-icon-btn--ghost" title="有序列表"><Icon name="list-numbers" size={15} /></button>
              <button className="m-icon-btn m-icon-btn--ghost" title="引用"><Icon name="quotes" size={15} /></button>
              <span className="sp-odoc__spacer" />
              <span className="sp-odoc__save">
                <Icon name="floppy-disk" size={12} />
                已启用自动保存
              </span>
              <button className="m-icon-btn m-icon-btn--ghost" title="复制全文"><Icon name="copy" size={15} /></button>
            </div>
            <SpOutlineDoc text={ep.outline} />
          </div>

          <div className="sp-obeats">
            <div className="sp-obeats__head">
              <Icon name="path" size={14} style={{ color: "var(--text-muted)" }} />
              <span className="sp-obeats__title">结构节拍</span>
              <span className="sp-obeats__spacer" />
              <button type="button" className="m-btn m-btn--text m-btn--sm" onClick={() => onGoto("beat")}>
                去节拍板编辑
              </button>
            </div>
            {!beats.length && <div className="sp-obeats__empty">还没有节拍</div>}
            {acts.map((act) => (
              <React.Fragment key={act}>
                <div className="sp-obeats__act">{act}</div>
                {beats.filter((b) => b.act === act).map((b) => (
                  <button key={b.id} type="button" className="sp-obeat" onClick={() => onGoto("beat")}>
                    <div className="sp-obeat__head">
                      <span className="sp-obeat__title">{b.title}</span>
                      <span className="sp-obeat__pages"><SpPages value={b.pages} /></span>
                    </div>
                    <div className="sp-obeat__desc">{b.desc}</div>
                    {b.scenes.length > 0 && (
                      <div className="sp-obeat__scenes">
                        {b.scenes.map((no) => (
                          <SpChip key={no} tone="plain">第 {no} 场</SpChip>
                        ))}
                      </div>
                    )}
                  </button>
                ))}
              </React.Fragment>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

/* ============================ 节拍 ============================ */

// 幕不是固定三栏 —— 幕数由这一集实际排出来的节拍决定，不设上限。
// 列多到装不下时横向滚，桌面端要能用普通鼠标滚轮滚（Flutter 侧用
// HorizontalWheelScroll 包住，浏览器里 overflow-x 天然可用）。
const SP_ACT_ORDER = ["第一幕", "第二幕", "第三幕", "第四幕", "第五幕", "第六幕"];

function SpBeatView({ proj, epId }) {
  const beats = SP_BEATS.filter((b) => b.proj === proj.id && (epId ? b.ep === epId : true));
  const used = new Set(beats.map((b) => b.act));
  const acts = SP_ACT_ORDER.filter((a) => used.has(a));
  // 一集还没有任何节拍时，先给第一幕一个空栏，让「添加节拍」有地方落。
  if (!acts.length) acts.push("第一幕");

  return (
    <div className="sp-scroll">
      <div className="sp-pad">
        <div className="sp-acts">
          {acts.map((act) => {
            const list = beats.filter((b) => b.act === act);
            return (
              <div key={act} className="sp-act">
                <div className="sp-act__head">
                  <Icon name="path" size={14} style={{ color: "var(--text-muted)" }} />
                  <span className="sp-act__title">{act}</span>
                  <span className="sp-act__count">{list.length}</span>
                </div>
                {list.map((b) => (
                  <button key={b.id} type="button" className="sp-beat">
                    <div className="sp-beat__head">
                      <span className="sp-beat__title">{b.title}</span>
                      <span className="sp-beat__pages"><SpPages value={b.pages} /></span>
                    </div>
                    <div className="sp-beat__desc">{b.desc}</div>
                    <div className="sp-beat__scenes">
                      {b.scenes.map((no) => (
                        <SpChip key={no} tone="plain">第 {no} 场</SpChip>
                      ))}
                    </div>
                  </button>
                ))}
                <button type="button" className="sp-beat sp-beat--ghost">
                  + 添加节拍
                </button>
              </div>
            );
          })}
          <button type="button" className="sp-act sp-act--add">
            <Icon name="plus" size={14} />
            <span>新增一幕</span>
          </button>
        </div>
      </div>
    </div>
  );
}

/* ============================ 场次 ============================ */

// 场次卡上方那块「正文缩略」——直接用真正文渲染,没有正文就说没有。
function SpScenePeek({ scene }) {
  const body = SP_SCRIPT[scene.id];
  if (!body) {
    return (
      <div className="sp-scard__peek">
        {/* 这一块是正文的缩略，所以走 spSlug（地点在前）而不是 spSceneName ——
            正文里没有事件短标题，缩略图里也不该凭空长出来。 */}
        <div className="sp-peek-line sp-peek-line--scene">
          {scene.no}、{spSlug(scene)}
        </div>
        <div className="sp-peek-line" style={{ marginTop: 8 }}>
          还没有正文，只有梗概。
        </div>
      </div>
    );
  }
  return (
    <div className="sp-scard__peek">
      {body.slice(0, 18).map((el, i) => {
        if (el.t === "scene") {
          return (
            <div key={i} className="sp-peek-line sp-peek-line--scene">
              {el.no}、{el.place} {el.time} / {el.ie}
            </div>
          );
        }
        if (el.t === "char") return <div key={i} className="sp-peek-line sp-peek-line--char">{el.name}：</div>;
        if (el.t === "dialog") return <div key={i} className="sp-peek-line sp-peek-line--dialog">{el.text}</div>;
        if (el.t === "paren") return <div key={i} className="sp-peek-line sp-peek-line--paren">（{el.text}）</div>;
        if (el.t === "action") return <div key={i} className="sp-peek-line">{el.text}</div>;
        if (el.t === "cast") return <div key={i} className="sp-peek-line">出场人物：{el.names.join("、")}</div>;
        return null;
      })}
    </div>
  );
}

function SpSceneCard({ scene, active, onOpen, onProps }) {
  const change = spAiChangeOf(scene.id);
  return (
    <article
      className={"sp-scard" + (active ? " is-active" : "") + (change ? " has-ai" : "")}
      data-screen-label={`场次卡 ${scene.no}`}
    >
      <SpAiBar sceneId={scene.id} />
      <SpScenePeek scene={scene} />
      <div className="sp-scard__body">
        {/* 标题可点 = 开场次属性，跟正文场次头同一条规则：不为同一件事再放一个按钮。 */}
        <div className="sp-scard__head is-clickable" title="编辑场次属性" onClick={onProps}>
          <span className="sp-scard__name">{spSceneName(scene)}</span>
          <SpEmoBadges scene={scene} />
        </div>
        <div className="sp-scard__cond">{spSceneCond(scene)}</div>
        <div className="sp-scard__chips">
          <SpChip icon="user">{scene.cast.length} 人</SpChip>
          <SpChip icon="chat-centered">{scene.lines} 句</SpChip>
          <SpChip icon="article"><SpPages value={scene.pages} /></SpChip>
          <SpState state={scene.state} />
        </div>
        <div className="sp-scard__desc">{scene.desc}</div>
      </div>
      <div className="sp-scard__actions">
        <button className="m-btn m-btn--secondary m-btn--sm" onClick={onOpen}>
          <Icon name="pencil-simple" size={13} />
          编辑正文
        </button>
      </div>
    </article>
  );
}

function SpBoardTools() {
  return (
    <div className="sp-board__tools">
      <button className="m-icon-btn m-icon-btn--ghost" title="批注"><Icon name="chat-centered" size={15} /></button>
      <button className="m-icon-btn m-icon-btn--ghost" title="整理画布"><Icon name="magic-wand" size={15} /></button>
      <button className="m-icon-btn m-icon-btn--ghost" title="适应窗口"><Icon name="arrows-out" size={15} /></button>
      <button className="m-icon-btn m-icon-btn--ghost" title="缩小"><Icon name="minus" size={15} /></button>
      <button className="m-icon-btn m-icon-btn--ghost" title="放大"><Icon name="plus" size={15} /></button>
    </div>
  );
}

// 场次的列表视图 —— 原来长在大纲页的那份场序，现在归场次页，并且是默认视图。
// 一行一场：左列固定宽的场次头，右列梗概与 meta。整行可点 = 打开场次属性；
// 重排和「编辑正文」收在悬停才出现的菜单里，不让每一行常驻三个按钮。
function SpSceneRow({ scene, onSelectScene, onGoto, onSceneProps }) {
  const beat = SP_BEATS.find((b) => b.id === scene.beat);
  return (
    <div className="sp-orow" onClick={() => onSceneProps(scene)}>
      {/* 左列主行是短标题，地点/时间/内外降为次行（§3.1）。 */}
      <div className="sp-orow__slug">
        <div className="sp-orow__slug-main">
          <span className="sp-orow__slug-no">{scene.no}、</span>
          {spSceneName(scene)}
        </div>
        <SpEmoBadges scene={scene} />
        <div className="sp-orow__slug-cond">{spSceneCond(scene)}</div>
      </div>
      <div className="sp-orow__body">
        <div className="sp-orow__desc">{scene.desc}</div>
        <div className="sp-orow__meta">
          <SpState state={scene.state} />
          {beat && <SpChip icon="path">{beat.title}</SpChip>}
          <SpChip icon="clock"><SpPages value={scene.pages} /></SpChip>
          <SpChip icon="user">{scene.cast.length} 人</SpChip>
        </div>
      </div>
      <div className="sp-orow__more">
        <button
          type="button"
          className="m-icon-btn m-icon-btn--ghost"
          title="编辑正文"
          onClick={(e) => { e.stopPropagation(); onSelectScene(scene.id); onGoto("script"); }}
        >
          <Icon name="pencil-simple" size={15} />
        </button>
      </div>
    </div>
  );
}

function SpScenesView({ proj, scenes, view, seasonId, epId, sceneId, onSelectScene, onGoto, onSceneProps }) {
  // 出场矩阵读的是人物和出场关系，没有场次也照样能看名单，所以放在空态之前。
  if (view === "appearance") {
    return <SpRelationsView proj={proj} seasonId={seasonId} epId={epId} />;
  }

  if (!scenes.length) {
    return <SpEmpty title="这一集还没有场次" sub="先建一场，再补梗概和正文。" action="新增场次" />;
  }

  if (view === "list") {
    return (
      <div className="sp-scroll">
        <div className="sp-pad">
          <div className="sp-outline">
            {scenes.map((s) => (
              <SpSceneRow key={s.id} scene={s} onSelectScene={onSelectScene}
                onGoto={onGoto} onSceneProps={onSceneProps} />
            ))}
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="sp-board">
      <SpBoardTools />
      <div className="sp-board__inner">
        {scenes.map((s, i) => (
          <React.Fragment key={s.id}>
            {i > 0 && <div className="sp-board__link" />}
            <SpSceneCard
              scene={s}
              active={s.id === sceneId}
              onOpen={() => { onSelectScene(s.id); onGoto("script"); }}
              onProps={() => onSceneProps(s)}
            />
          </React.Fragment>
        ))}
      </div>
    </div>
  );
}

/* ============================ 场次属性 ============================ */
// 阶段 M 给场次补的四个字段（短标题、目标时长、情绪、事件）加“内外”取值都落在这里。
// 真实实现里它不是新建的一屏 —— 桌面 `scene_dialog.dart` 已经在做地点、内外景、
// 阶段、节拍和梗概，M 是在那一屏上再扩四项，不另开第二个场次编辑入口。
// mockup 之前没画过这一屏（场次行点击只做选中），所以这里补上。

function SpFieldRow({ label, hint, children }) {
  return (
    <div className="sp-field">
      <div className="sp-field__label">
        {label}
        {hint && <span className="sp-field__hint">{hint}</span>}
      </div>
      {children}
    </div>
  );
}

// 情绪标签：写后整理的产物，作者可增删。空的时候不显示一排假标签。
function SpEmotionTags({ scene }) {
  const tags = scene.emotion || [];
  return (
    <div className="sp-tags">
      {tags.map((t) => (
        <span key={t} className="sp-tag">
          {t}
          <button type="button" className="sp-tag__x" title="移除"><Icon name="x" size={9} /></button>
        </span>
      ))}
      <button type="button" className="sp-tag sp-tag--add">
        <Icon name="plus" size={10} />
        {tags.length ? "加一个" : "添加情绪"}
      </button>
    </div>
  );
}

// 有序事件。每项 title / summary / stateChange，折叠后只留 title —— 一场七八个
// 事件全展开会把这一屏撑成一页纸。stateChange 说的是「这件事改变了什么」，
// 为空是正常的：不是每个事件都改变状态。
function SpSceneEvents({ scene }) {
  const events = scene.events || [];
  const [open, setOpen] = React.useState(events.length ? 0 : null);

  if (!events.length) {
    return (
      <div className="sp-events__empty">
        {scene.state === "待写"
          ? "这一场还没有正文，事件等正文写完由故事连续性维护整理。"
          : "还没有整理过这一场的事件。"}
        <button type="button" className="m-btn m-btn--text m-btn--sm">
          <Icon name="magic-wand" size={12} />
          整理这一场
        </button>
      </div>
    );
  }

  return (
    <div className="sp-events">
      {events.map((e, i) => (
        <div key={i} className={"sp-event" + (open === i ? " is-open" : "")}>
          <div className="sp-event__bar" onClick={() => setOpen(open === i ? null : i)}>
            <span className="sp-event__no">{i + 1}</span>
            <span className="sp-event__title">{e.title}</span>
            <span className="sp-event__spacer" />
            {e.stateChange && <span className="sp-event__flag" title="这件事改变了状态">状态</span>}
            <Icon name={open === i ? "caret-down" : "caret-right"} size={11} />
          </div>
          {open === i && (
            <div className="sp-event__body">
              <div className="sp-event__summary" contentEditable suppressContentEditableWarning>
                {e.summary}
              </div>
              {e.stateChange ? (
                <div className="sp-event__change">
                  <span className="sp-event__change-label">状态变化</span>
                  <span contentEditable suppressContentEditableWarning>{e.stateChange}</span>
                </div>
              ) : (
                <button type="button" className="sp-event__change-add">
                  <Icon name="plus" size={10} />
                  记一条状态变化
                </button>
              )}
            </div>
          )}
        </div>
      ))}
      <button type="button" className="sp-events__add">
        <Icon name="plus" size={12} />
        新增事件
      </button>
    </div>
  );
}

function SpSceneDialog({ scene, proj, onClose, onGoto }) {
  const target = spSecsLabel(scene.targetSecs);

  return (
    <div className="m-dialog-scrim" onClick={onClose}>
      <div
        className="m-dialog m-dialog--scene"
        data-screen-label="场次属性"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="m-dialog__head">
          <div className="sp-sbdlg__title">
            <span className="sp-sbdlg__scene">
              <span className="sp-sbscene__no">{scene.no}、</span>{spSceneName(scene)}
            </span>
            <span className="sp-sbdlg__stat">{spSceneCond(scene)}</span>
          </div>
          <button className="m-icon-btn" onClick={onClose} title="关闭">
            <Icon name="x" size={16} />
          </button>
        </div>

        {/* 正文改过之后整理结果就旧了 —— 旧值保留，只标待核对，不清空也不自动重跑。 */}
        {scene.analysisStale && (
          <div className="sp-stale">
            <Icon name="warning-circle" size={13} />
            <span>正文改过，下面的情绪与事件还是上一版的结果。</span>
            <span className="sp-event__spacer" />
            <button type="button" className="m-btn m-btn--text m-btn--sm">
              <Icon name="arrow-clockwise" size={12} />
              重新整理
            </button>
          </div>
        )}

        <div className="sp-scdlg__body">
          <SpFieldRow label="事件短标题" hint="为空就显示地点，不会拿梗概去凑">
            <div className="sp-input" contentEditable suppressContentEditableWarning
              data-placeholder={scene.place}>
              {scene.title}
            </div>
          </SpFieldRow>

          <div className="sp-field-row2">
            <SpFieldRow label="地点">
              <div className="sp-input" contentEditable suppressContentEditableWarning>{scene.place}</div>
            </SpFieldRow>
            <SpFieldRow label="时间">
              <div className="sp-input" contentEditable suppressContentEditableWarning>{scene.time}</div>
            </SpFieldRow>
          </div>

          <div className="sp-field-row2">
            {/* 「内外」是明确选项，和「未指定」不是一回事，所以这里是四个格子。 */}
            <SpFieldRow label="内外景">
              <div className="sp-choice">
                {SP_IE_VALUES.map((v) => (
                  <button key={v} type="button"
                    className={"sp-choice__opt" + (scene.ie === v ? " is-active" : "")}>
                    {v}
                  </button>
                ))}
                <button type="button"
                  className={"sp-choice__opt sp-choice__opt--none" + (scene.ie ? "" : " is-active")}>
                  未指定
                </button>
              </div>
            </SpFieldRow>
            <SpFieldRow label="本场目标时长" hint="不填就是没定">
              <div className="sp-input sp-input--num" contentEditable suppressContentEditableWarning>
                {scene.targetSecs != null ? scene.targetSecs : ""}
              </div>
              {/* 两种时长并排放，看得出它们互不覆盖：目标是意图，估算来自正文排版。
                  哪个空就是哪个没有。 */}
              <div className="sp-durrow">
                <span>目标 {target || "—"}</span>
                <span>估算 约 {scene.minutes} 分钟</span>
              </div>
            </SpFieldRow>
          </div>

          <SpFieldRow label="梗概" hint="这一场要做什么，和事件不是一回事">
            <div className="sp-input sp-input--area" contentEditable suppressContentEditableWarning>
              {scene.desc}
            </div>
          </SpFieldRow>

          <SpFieldRow label="情绪" hint="从正文整理，作者可改">
            <SpEmotionTags scene={scene} />
          </SpFieldRow>

          <SpFieldRow label="事件" hint="按发生顺序">
            <SpSceneEvents scene={scene} />
          </SpFieldRow>
        </div>
      </div>
    </div>
  );
}

/* ============================ 关系图谱 ============================ */

function SpRelationsView({ proj, seasonId, epId }) {
  // 人物、地点和关系跨季共享 —— 一个作品保存整部剧集，左栏这份名单不按季裁。
  const chars = spCharsOf(proj.id);
  // 矩阵按当前这一集算 —— 跨集拼在一起场号会从 1 重来，读不出谁在哪一场。
  const scenes = spScenesOf(proj.id, epId);
  const ep = spEpisodesOf(proj.id).find((e) => e.id === epId);
  const season = spSeasonById(seasonId);
  const multi = spSeasonsOf(proj.id).length > 1;
  // 多季时集号会重复，列头要带上季才说得清是哪一集的场号。
  const scope = [multi && season ? spSeasonLabel(season) : "", ep ? ep.label : ""]
    .filter(Boolean)
    .join(" · ");
  const nameOf = (id) => (chars.find((c) => c.id === id) || {}).name || "—";

  return (
    <div className="sp-scroll">
      <div className="sp-pad">
        <div className="sp-rel-grid">
          <div className="sp-card">
            <div className="sp-card__title">
              <Icon name="users" size={14} />
              角色
              <span className="sp-card__hint">{chars.length}</span>
            </div>
            {chars.map((c) => (
              <div key={c.id} className="sp-crow">
                <span className="m-avatar m-avatar--user" style={{ width: 28, height: 28, flex: "none" }}>
                  {c.name.slice(0, 1)}
                </span>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div className="sp-crow__name">{c.name}</div>
                  <div className="sp-crow__note">{c.note}</div>
                </div>
                <SpChip tone="plain">{c.role}</SpChip>
              </div>
            ))}
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
            <div className="sp-card">
              <div className="sp-card__title">
                <Icon name="grid-nine" size={14} />
                出场矩阵
                <span className="sp-card__hint">
                  列 = {scope ? `${scope} ` : ""}场号，深色 = 主角在场
                </span>
              </div>
              <table className="sp-matrix">
                <thead>
                  <tr>
                    <th className="sp-matrix__rowhead"></th>
                    {scenes.map((s) => <th key={s.id} title={spSceneName(s)}>{s.no}</th>)}
                  </tr>
                </thead>
                <tbody>
                  {chars.map((c) => (
                    <tr key={c.id}>
                      <td className="sp-matrix__rowhead">{c.name}</td>
                      {scenes.map((s) => {
                        const on = c.scenes.includes(s.id);
                        return (
                          <td key={s.id} className="sp-matrix__cell">
                            <div
                              className={
                                "sp-matrix__box" +
                                (on ? (c.role === "主角" ? " is-lead" : " is-on") : "")
                              }
                              title={on ? `${c.name} 在第 ${s.no} 场` : ""}
                            />
                          </td>
                        );
                      })}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div className="sp-card">
              <div className="sp-card__title">
                <Icon name="tree-structure" size={14} />
                关系
                <span className="sp-card__hint">{SP_RELATIONS.filter((r) => r.proj === proj.id).length}</span>
              </div>
              {SP_RELATIONS.filter((r) => r.proj === proj.id).map((r, i) => (
                <div key={i} className="sp-relline">
                  <span className="sp-relline__who">{nameOf(r.a)}</span>
                  <span className="sp-relline__arrow">—</span>
                  <SpChip>{r.type}</SpChip>
                  <span className="sp-relline__arrow">—</span>
                  <span className="sp-relline__who">{nameOf(r.b)}</span>
                  <span className="sp-relline__note">{r.note}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ============================ 概览 ============================ */

function SpStat({ label, value, unit }) {
  return (
    <div className="sp-stat">
      <div className="sp-stat__label">{label}</div>
      <div className="sp-stat__value">
        {value}
        {unit && <span className="sp-stat__unit">{unit}</span>}
      </div>
    </div>
  );
}

// 来源作品(source_novel_id)：指得到就是可点的改编来源，指不到只标不可用，
// 不自动清空这个字段；为空就是原创。
function SpSourceChip({ proj }) {
  if (!proj.sourceId) return <SpChip icon="pencil-line">原创</SpChip>;
  const source = (window.REVERIC_DATA.novels || []).find((n) => n.id === proj.sourceId);
  if (!source) return <SpChip icon="warning-circle" tone="plain">来源作品不可用</SpChip>;
  return (
    <button type="button" className="sp-chip sp-chip--link" title="打开来源作品">
      <Icon name="book" size={12} />
      改编自《{source.title}》
    </button>
  );
}

// 概览不再给时长 —— 剧本正文推不出成片秒数，时长要求写在作品的智能体规则里。
// 这一屏只摆能如实数出来的东西：写到哪了、写了多少、每集定稿和分镜的进度。
// 概览是整部作品的视图，不挂剧集/场次中栏（EditorView），分集列表由这一屏自己给。
function SpOverview({ proj, seasonId, epId, sceneId, onSelectSeason, onSelectEp, onSelectScene, onGoto }) {
  const seasons = spSeasonsOf(proj.id);
  const multi = seasons.length > 1;
  const isSeries = proj.kind === "series";
  // 单季不出现任何季级控件，范围恒为整部剧集；多季才让作者在两个范围之间切。
  const [scope, setScope] = React.useState("season");   // series | season
  const scoped = multi && scope === "season";
  const stats = SP_STATS_OF(proj.id, scoped ? seasonId : null);
  const episodes = spEpisodesOf(proj.id, multi ? seasonId : null);
  const season = spSeasonById(seasonId);

  return (
    <div className="sp-scroll">
      <div className="sp-pad">
        <div className="sp-ov">
          <div className="sp-ov__head">
            <div className="sp-ov__eyebrow">
              <Icon name={isSeries ? "stack" : "image-square"} size={13} />
              {isSeries ? "剧集" : "电影"} · {proj.genre}
            </div>
            <h1 className="sp-ov__title">{proj.title}</h1>
            <div className="sp-ov__facts">
              <SpSourceChip proj={proj} />
              {isSeries && !multi && (
                <SpChip icon="stack"><SpEpisodeCount seasonId={seasonId} /></SpChip>
              )}
              {isSeries && multi && (
                <SpChip icon="film-strip">{seasons.length} 季 · {stats.episodes} 集</SpChip>
              )}
              <SpChip icon="clock">更新于 {proj.updated}</SpChip>
            </div>
          </div>

          {/* 电影第一期不支持 —— 这一屏留着只作未来形态探索，如实说明，不假装能用。 */}
          {proj.supported === false && (
            <div className="sp-notice">
              <Icon name="warning-circle" size={15} />
              <div>
                <b>电影剧本第一期不支持。</b>
                这一部保留在样例里只作未来形态探索；真要做电影，数据模型、创建流程和迁移都得单独设计，
                不是把剧集当成「只有一集」就能顺带覆盖。
              </div>
            </div>
          )}

          <SpContinueCard proj={proj} epId={epId} sceneId={sceneId} onSelectScene={onSelectScene} onGoto={onGoto} />

          {/* 单季作品这里什么也不出现 —— 季这一层在界面上根本不存在。
              范围同时决定下面的统计和列表，所以排在简介卡之前。 */}
          {multi && (
            <div className="sp-ov__scope">
              <SpSeg
                value={scope}
                onChange={setScope}
                options={[
                  { id: "series", label: "整部剧集", icon: "film-strip" },
                  { id: "season", label: spSeasonLabel(season), icon: "stack" },
                ]}
              />
            </div>
          )}

          <SpIntroCard proj={proj} stats={stats} showBeats={!(multi && scope === "series")} />

          {multi && scope === "series" ? (
            <div className="sp-card">
              <div className="sp-card__title">
                <Icon name="film-strip" size={14} />
                各季
                <span className="sp-card__hint">{seasons.length} 季</span>
              </div>
              {seasons.map((s) => {
                const st = SP_STATS_OF(proj.id, s.id);
                const sc = SP_SCENES.filter((x) => x.proj === proj.id && spEpisodesOf(proj.id, s.id).some((e) => e.id === x.ep));
                const done = sc.filter((x) => x.state === "定稿").length;
                return (
                  <button
                    key={s.id}
                    type="button"
                    className={"sp-seasonrow" + (s.id === seasonId ? " is-current" : "")}
                    onClick={() => onSelectSeason(s.id)}
                  >
                    <span className="sp-seasonrow__top">
                      <span className="sp-seasonrow__name">{spSeasonLabel(s)}</span>
                      <span className="sp-nextrow__go"><Icon name="arrow-right" size={13} /></span>
                    </span>
                    <span className="sp-seasonrow__meta">
                      <SpEpisodeCount seasonId={s.id} />
                      <span>{st.scenes} 场</span>
                      <span>定稿 {done}/{sc.length}</span>
                    </span>
                  </button>
                );
              })}
            </div>
          ) : isSeries ? (
            <SpEpisodeBoard proj={proj} episodes={episodes} seasonId={seasonId} epId={epId} onSelectEp={onSelectEp} onGoto={onGoto} />
          ) : null}

        </div>
      </div>
    </div>
  );
}

// 继续写 —— 落在当前选中的场次；没有选中就落在第一场还没定稿的戏。
// 引的是这一场正文最后一句，作者一眼认得出自己停在哪。
function SpContinueCard({ proj, epId, sceneId, onSelectScene, onGoto }) {
  const all = SP_SCENES.filter((s) => s.proj === proj.id);
  const scene =
    all.find((s) => s.id === sceneId) ||
    all.find((s) => s.ep === epId && s.state !== "定稿") ||
    all.find((s) => s.state !== "定稿") ||
    all[0];
  if (!scene) return null;
  const ep = SP_EPISODES.find((e) => e.id === scene.ep);
  const body = SP_SCRIPT[scene.id] || [];
  const last = [...body].reverse().find((el) => el.t === "dialog" || el.t === "action");
  return (
    <div className="sp-ovc">
      <div className="sp-ovc__label">
        <Icon name="pencil-simple" size={14} />
        继续写作
      </div>
      <div className="sp-ovc__where">
        {ep ? `${ep.label} ${ep.title} · ` : ""}第 {scene.no} 场 {scene.title}
        <SpState state={scene.state} />
      </div>
      <p className="sp-ovc__quote">{last ? last.text : scene.desc}</p>
      <div className="sp-ovc__actions">
        <button className="m-btn m-btn--primary" onClick={() => { onSelectScene && onSelectScene(scene.id); onGoto("script"); }}>
          <Icon name="pencil-simple" size={14} />
          继续写
        </button>
        <button className="m-btn m-btn--secondary" onClick={() => onGoto("outline")}>
          <Icon name="list-numbers" size={14} />
          大纲
        </button>
        <button className="m-btn m-btn--secondary" onClick={() => onGoto("scenes")}>
          <Icon name="squares-four" size={14} />
          场次
        </button>
      </div>
    </div>
  );
}

// 简介 + 规模统计放一张卡 —— 统计是陪衬，不再各占一格大数字。
function SpIntroCard({ proj, stats, showBeats }) {
  const items = [
    ["场次", stats.scenes, "场"],
    ["篇幅", <SpPages value={stats.pages} unit="" />, "页"],
    ["台词", stats.lines, "句"],
    ["角色", stats.chars, "人"],
    ["景地", stats.places, "处"],
    ...(showBeats ? [["节拍", stats.beats, "个"]] : []),
  ];
  return (
    <div className="sp-card sp-ovi">
      <div className="sp-card__title">
        <Icon name="book-open" size={14} />
        故事简介
      </div>
      <div className="sp-ovi__body">
        <div className="sp-ovi__poster" style={{ background: OV_COVER_BG[proj.cover] || OV_COVER_BG.ink }} />
        <p className="sp-ovi__logline">{proj.logline}</p>
      </div>
      <div className="sp-ovi__stats">
        {items.map(([label, value, unit]) => (
          <span key={label} className="sp-ovi__stat">
            <span className="sp-ovi__statlabel">{label}</span>
            <b>{value}</b>
            <span className="sp-ovi__statunit">{unit}</span>
          </span>
        ))}
      </div>
    </div>
  );
}

// 分集看板 —— 每集一行：场次格子（实心 = 定稿）、定稿数、分镜采用数。
// 集数多到几十集也是一屏能扫完的列表，不做卡片墙。
function SpEpisodeBoard({ proj, episodes, seasonId, epId, onSelectEp, onGoto }) {
  return (
    <div className="sp-card">
      <div className="sp-card__title">
        <Icon name="stack" size={14} />
        分集
        <span className="sp-card__hint"><SpEpisodeCount seasonId={seasonId} /></span>
      </div>
      <div className="sp-eprow sp-eprow--head">
        <span className="sp-eprow__no">集</span>
        <span className="sp-eprow__title">标题</span>
        <span className="sp-eprow__cells">场次</span>
        <span className="sp-eprow__num">定稿</span>
        <span className="sp-eprow__num">分镜</span>
        <span className="sp-eprow__go" />
      </div>
      {episodes.map((e) => {
        const list = spScenesOf(proj.id, e.id);
        const done = list.filter((s) => s.state === "定稿").length;
        const clips = list.map((s) => SP_CLIP_STATS[s.id]).filter(Boolean);
        const adopted = clips.reduce((sum, c) => sum + c[0], 0);
        const total = clips.reduce((sum, c) => sum + c[1], 0);
        return (
          <button
            key={e.id}
            type="button"
            className={"sp-eprow" + (e.id === epId ? " is-current" : "")}
            onClick={() => { onSelectEp && onSelectEp(e.id); onGoto("script"); }}
          >
            <span className="sp-eprow__no">{e.label}</span>
            <span className="sp-eprow__title">{e.title || "未命名"}</span>
            <span className="sp-eprow__cells">
              {list.length === 0
                ? <span className="sp-eprow__none">—</span>
                : list.map((s) => (
                    <span
                      key={s.id}
                      className={"sp-eprow__cell" + (s.state === "定稿" ? " is-final" : "")}
                      title={`第 ${s.no} 场 ${s.title} · ${s.state}`}
                    />
                  ))}
            </span>
            <span className="sp-eprow__num">{list.length ? `${done}/${list.length}` : "—"}</span>
            <span className="sp-eprow__num">{total ? `${adopted}/${total}` : "—"}</span>
            <span className="sp-eprow__go"><Icon name="arrow-right" size={13} /></span>
          </button>
        );
      })}
    </div>
  );
}

/* ============================ 主区外壳 ============================ */

// 标题栏的图标与 NavRail 同一份（NavRail.jsx SCREENPLAY_SECTIONS）。
// 制作在「制片」独立页(NavRail href)，不在这张表里。
const SP_SECTION_META = {
  overview: { title: "概览", icon: "grid-nine" },
  script: { title: "剧本", icon: "file-text" },
  outline: { title: "大纲", icon: "list-numbers" },
  beat: { title: "节拍", icon: "path" },
  scenes: { title: "场次", icon: "squares-four" },
  relations: { title: "关系图谱", icon: "tree-structure" },
};

// 还没设计的那几屏 —— 顶栏也得写中文栏目名,不能把 nav id 直接甩到界面上。
const SP_TODO_TITLES = {
  characters: "人物",
  progress: "当前进度",
  materials: "素材",
  world: "设定",
  map: "地图",
  compendium: "图鉴",
  chat: "聊天",
  rules: "智能体规则",
  council: "圆桌会议",
  monologue: "独白",
  theater: "小剧场",
  roleplay: "角色扮演",
};

function ScreenplayWorkspace({ novel, section, seasonId, onSelectSeason, epId, onSelectEp, sceneId, onSelectScene, onGoto }) {
  const proj = novel.screenplay;
  const scenes = spScenesOf(proj.id, epId);
  // 场次默认看列表 —— 排场序、读梗概是最高频的动作；场次板是排完之后才用的。
  const [sceneView, setSceneView] = React.useState("list");   // list | card | appearance
  // 场次属性弹窗。场次列表、场次板和正文标题三处都开这一个，不各写一份。
  const [propScene, setPropScene] = React.useState(null);
  const meta = SP_SECTION_META[section];
  // 状态栏跟着正文走 —— 正文只显示当前这一集，统计就不能拿全剧的。
  const epPages = spFormatEighths(scenes.reduce((sum, s) => sum + spEighths(s.pages), 0));
  const epMinutes = Math.round(scenes.reduce((sum, s) => sum + s.minutes, 0));
  const epLines = scenes.reduce((sum, s) => sum + s.lines, 0);
  const ep = spEpisodesOf(proj.id).find((e) => e.id === epId);
  const season = spSeasonById(seasonId);
  const epChanges = spAiChangesOf(proj.id, scenes.map((s) => s.id));
  // 多季时集号会重复，状态栏光写 "Ep 1" 说不清是哪一季的第 1 集。
  const epLabel = ep
    ? [spSeasonsOf(proj.id).length > 1 && season ? spSeasonLabel(season) : "", ep.label]
        .filter(Boolean)
        .join(" · ")
    : null;

  // NavRail 上剧本没做的栏目(当前进度 / 素材 / AI 各页)——照实说没做,不假装。
  if (!meta) {
    return (
      <div className="sp-main">
        <div className="sp-top">
          <span className="sp-top__title">{SP_TODO_TITLES[section] || section}</span>
        </div>
        <SpEmpty title="这一屏还没设计" sub="本轮 mockup 覆盖概览、剧本、大纲、节拍、场次、关系图谱。" />
      </div>
    );
  }

  const count =
    section === "scenes" ? scenes.length
    : section === "beat" ? SP_BEATS.filter((b) => b.proj === proj.id && (epId ? b.ep === epId : true)).length
    : section === "script" ? scenes.length
    : null;

  return (
    <div className="sp-main" data-screen-label={`剧本 · ${meta.title}`}>
      <div className="sp-top">
        <Icon name={meta.icon} size={15} style={{ color: "var(--text-muted)" }} />
        <span className="sp-top__title">{meta.title}</span>
        {count !== null && <span className="sp-top__count">{count}</span>}
        {/* 待审阅改动入口 —— 只在这一集真有 AI 改动时出现，没有就不占位。
            用词跟章节侧一致：改动已经应用，这里是回看和回退的入口。 */}
        {epChanges.length > 0 && (
          <button type="button" className="sp-top__ai" onClick={() => onGoto("scenes")}>
            <Icon name="clock-counter-clockwise" size={12} />
            AI 改动 {epChanges.length} 处
          </button>
        )}
        <span className="sp-top__spacer" />

        {section === "scenes" && (
          <SpSeg
            value={sceneView}
            onChange={setSceneView}
            options={[
              { id: "list", label: "列表", icon: "list" },
              { id: "card", label: "场次板", icon: "squares-four" },
              { id: "appearance", label: "出场矩阵", icon: "grid-nine" },
            ]}
          />
        )}
        <span className="sp-top__spacer" />
        <button className="m-icon-btn" title="历史"><Icon name="clock-counter-clockwise" size={16} /></button>
        <button className="m-icon-btn" title="导出"><Icon name="download-simple" size={16} /></button>
      </div>

      {section === "overview" && (
        <SpOverview proj={proj} seasonId={seasonId} epId={epId} sceneId={sceneId} onSelectSeason={onSelectSeason} onSelectEp={onSelectEp} onSelectScene={onSelectScene} onGoto={onGoto} />
      )}
      {section === "script" && (
        <SpScriptView
          proj={proj}
          scenes={scenes}
          sceneId={sceneId}
          onSelectScene={onSelectScene}
          onSceneProps={setPropScene}
        />
      )}
      {section === "outline" && <SpOutlineView proj={proj} epId={epId} onGoto={onGoto} />}
      {section === "beat" && <SpBeatView proj={proj} epId={epId} />}
      {section === "scenes" && (
        <SpScenesView
          proj={proj}
          scenes={scenes}
          view={sceneView}
          seasonId={seasonId}
          epId={epId}
          sceneId={sceneId}
          onSelectScene={onSelectScene}
          onGoto={onGoto}
          onSceneProps={setPropScene}
        />
      )}
      {section === "relations" && <SpRelationsView proj={proj} seasonId={seasonId} epId={epId} />}

      {section === "script" && (
        <div className="sp-status">
          <span><Icon name="floppy-disk" size={12} /> 已启用自动保存</span>
          {epLabel && <span><Icon name="stack" size={12} /> {epLabel}</span>}
          <span><Icon name="article" size={12} /> <SpPages value={epPages} /></span>
          <span><Icon name="clock" size={12} /> 约 {epMinutes} 分钟</span>
          <span><Icon name="squares-four" size={12} /> {scenes.length} 场</span>
          <span><Icon name="chat-centered" size={12} /> {epLines} 句台词</span>
          <span className="sp-status__spacer" />
          {/* 同上：格式只有亚洲式一种，状态栏不占这一格。
          <span><Icon name="text-t" size={12} /> {proj.format}格式</span> */}
          <span><Icon name="clock-counter-clockwise" size={12} /> 历史</span>
        </div>
      )}

      {/* 场次属性 —— 短标题、目标时长、内外、情绪、事件都在这里改（§4.1）。 */}
      {propScene && (
        <SpSceneDialog
          scene={propScene}
          proj={proj}
          onClose={() => setPropScene(null)}
          onGoto={(sec) => { onSelectScene(propScene.id); onGoto(sec); }}
        />
      )}
    </div>
  );
}

Object.assign(window, {
  ScreenplayContext, ScreenplayWorkspace,
  spScenesOf, spEpisodesOf, spCharsOf,
});
