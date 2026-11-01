// segments.jsx — 制片页「分镜」视图:按场分组的整集片段列表,通读、审阅、修改提示词。
// 流程:先让 AI 把场次拆成片段(或手工新建),在这里通读修改,再去画布连参考、生成视频。
// 和画布 tab 读写同一份片段(同一批视频节点),不是第二份数据;生成、输入连线只在画布上做。
// AI 写入直接生效,行内只标小圆点;回退走右栏聊天的「最近改动」卡片(ChatPanel.jsx RecentChangesLog)。
// 关联文件: drama/app.jsx, drama/composer.jsx, drama/data.jsx, drama/drama.css

// 只看最近一次任务,和制作状态分开显示;失败提醒与画布卡片同一套(board.jsx DrTaskLine)。


// AI 改动已直接生效(同 Flutter「最近改动」):行内只用小圆点说「AI 动过」,
// 回退在右栏聊天输入框上方的「最近改动」卡片里,不设「接受」这一步。颜色与 ChatPanel 的 CHANGE_TYPE 一致。
const DR_AI_MARK = { new: { label: "新增", color: "var(--accent-warm)" }, edit: { label: "改写", color: "var(--accent)" } };

function DrSegRow({ node, nodes, edges, tasks, focused, onPatch, onToCanvas, taskActs }) {
  const ref = React.useRef(null);
  // 提示词默认展开、可直接编辑;收起就只剩标题行,不留前几行摘要。
  const [open, setOpen] = React.useState(true);
  const model = drModel(node.gen.model);
  const task = drLastTask(tasks, { type: "node", id: node.id });
  const secs = drSecs(node.ms);
  const inputKeys = new Set(drInputsOf(edges, node.id, nodes).map((i) => i.key));
  const broken = spPromptParts(node.prompt).filter((p) => p.ref && !inputKeys.has(p.ref.assetId)).length;

  React.useEffect(() => {
    if (!focused) return;
    setOpen(true);
    if (ref.current) ref.current.scrollIntoView({ block: "center" });
  }, [focused]);

  return (
    <div ref={ref} className={"dr-plrow" + (focused ? " is-focus" : "")}>
      <span className="dr-plrow__grip" title="拖动调整场内顺序"><CvIcon name="dots-three-vertical" size={14} /></span>
      <div className="dr-plrow__body">
        <div className="dr-plrow__head">
          {node.prompt ? (
            <button type="button" className="m-icon-btn m-icon-btn--ghost dr-plrow__toggle" title={open ? "收起提示词" : "展开提示词"} onClick={() => setOpen(!open)}>
              <CvIcon name={open ? "caret-down" : "caret-right"} size={12} />
            </button>
          ) : <span className="dr-plrow__toggle" />}
          <span className="dr-plrow__no">{drSegNo(node)}</span>
          <span className="dr-plrow__title">{node.title}</span>
          {node.ai && <span className="sp-aidot" style={{ background: DR_AI_MARK[node.ai].color }} title={`AI ${DR_AI_MARK[node.ai].label} · 在右侧「最近改动」里可回退`} />}
          <DrSelect pill value={node.status} onChange={(v) => onPatch({ status: v })}
            label={<span className={"dr-pstatus dr-pstatus--" + node.status}><span className="dr-pstatus__dot" />{DR_SEG_STATUS[node.status].label}</span>}
            options={Object.entries(DR_SEG_STATUS).map(([k, s]) => ({ value: k, label: s.label }))} />
          <DrTaskLine task={task} hasResult={!!node.adopted} {...taskActs} />
          {!open && broken > 0 && <span className="dr-issue" style={{ margin: 0 }} title={`${broken} 处引用没有对应的输入连线`}><CvIcon name="warning-circle" size={12} /></span>}
          <span className="cv-spacer" />
          <span className="dr-plrow__spec">{model.name} · {node.gen.ratio}</span>
          <span className={"dr-plrow__dur" + (secs ? "" : " is-empty")}>{secs ? `${secs} 秒` : "— 秒"}</span>
          <button type="button" className="dr-plrow__go" onClick={() => onToCanvas(node.id)} title="切到画布并选中这一段的节点">
            在画布中<CvIcon name="arrow-right" size={12} />
          </button>
        </div>
        {node.prompt ? (open && (
          <div className="dr-plrow__prompt">
            <div className="dr-plrow__text" contentEditable suppressContentEditableWarning>
              <DrPromptView prompt={node.prompt} inputKeys={inputKeys} />
            </div>
            {broken > 0 && (
              <div className="dr-plrow__bar">
                <span className="dr-issue" style={{ margin: 0 }}><CvIcon name="warning-circle" size={12} />{broken} 处引用没有对应的输入连线 · 到画布上连好</span>
              </div>
            )}
          </div>
        )        ) : (
          <button type="button" className="dr-plrow__add"><CvIcon name="plus" size={12} />写提示词</button>
        )}
      </div>
    </div>
  );
}

function DrSegmentList({ nodes, edges, tasks, focus, onPatch, onToCanvas, onAdd, onGoScript, onAsk, toast, taskActs }) {
  const scrollRef = React.useRef(null);
  React.useEffect(() => {
    if (focus.seg || !focus.scene) return;
    const el = scrollRef.current && scrollRef.current.querySelector(`[data-plscene="${focus.scene}"]`);
    if (el) el.scrollIntoView({ block: "start" });
  }, [focus.scene, focus.seg]);

  const all = drOrderedSegs(nodes);
  const planned = all.filter((n) => n.ms).reduce((sum, n) => sum + n.ms, 0);

  return (
    <div className="dr-plist">
      <div className="dr-plist__scroll" ref={scrollRef}>
        <div className="dr-plist__pad">
          {DR_SCENES.map((sc) => {
            const list = drSegsOf(nodes, sc.id);
            const ms = list.filter((n) => n.ms).reduce((sum, n) => sum + n.ms, 0);
            const unknown = list.filter((n) => !n.ms).length;
            const done = list.filter((n) => n.status === "done").length;
            return (
              <section key={sc.id} data-plscene={sc.id} className={"dr-plscene" + (focus.scene === sc.id ? " is-active" : "")}>
                <header className="dr-plscene__head">
                  <span className="dr-plscene__no">{sc.no}、</span>
                  <span className="dr-plscene__slug">{sc.title || sc.place}</span>
                  <span className="dr-plscene__cond">{sc.place} · {sc.time} / {sc.ie}</span>
                  <span className="cv-spacer" />
                  {list.length > 0 ? (
                    <span className="dr-plscene__stat">
                      {done}/{list.length} 段已完成 · 计划 {Math.round(ms / 1000)} 秒
                      {unknown > 0 && <span className="dr-plscene__warn">（{unknown} 段未填时长）</span>}
                    </span>
                  ) : <span className="dr-plscene__stat">尚无片段</span>}
                  <button type="button" className="dr-plscene__btn" onClick={() => onAsk(sc)}>
                    <CvIcon name="sparkle" size={12} />AI 拆片段
                  </button>
                  <button type="button" className="dr-plscene__btn" onClick={() => onGoScript(sc.id)}>
                    <CvIcon name="file-text" size={12} />查看原文
                  </button>
                </header>
                <div className="dr-plscene__list">
                  {list.map((n) => (
                    <DrSegRow key={n.id} node={n} nodes={nodes} edges={edges} tasks={tasks}
                      focused={focus.seg === n.id}
                      onPatch={onPatch(n)} onToCanvas={onToCanvas} taskActs={taskActs} />
                  ))}
                  <button type="button" className="dr-plscene__add" onClick={() => onAdd(sc.id)}>
                    <CvIcon name="plus" size={13} />新增片段
                  </button>
                </div>
              </section>
            );
          })}
        </div>
      </div>
      <div className="dr-plist__status">
        <span><CvIcon name="floppy-disk" size={12} /> 已启用自动保存</span>
        <span><CvIcon name="flag-pennant" size={12} /> 目标 {DR_EPISODE.target} 分钟</span>
        <span><CvIcon name="film-strip" size={12} /> 计划 {Math.round(planned / 1000)} 秒</span>
        <span><CvIcon name="squares-four" size={12} /> {all.length} 段 / {DR_SCENES.length} 场</span>
        <span><CvIcon name="list-checks" size={12} /> 已完成 {all.filter((n) => n.status === "done").length}/{all.length}</span>
      </div>
      {toast && <div className="dr-toast">{toast}</div>}
    </div>
  );
}

Object.assign(window, { DrSegmentList });
