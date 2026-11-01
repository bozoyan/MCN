// chat.jsx — 制作画布右栏:制作助手(聊天)。消息组件复用 ChatPanel.jsx 的 ChatBubble / ToolActivity。
// 助手走现有聊天 Agent 与资源工具:读片段、剧本、资产,建片段节点、写提示词与输入连线;
// 写入直接生效并进入变更审阅与历史,没有「AI 草稿 → 应用」的第二道流程。
// 助手发起生成 / 读外部文件走 Run,按工具权限决定直接执行、出审批卡或拒绝(approval.jsx);
// 采用结果、标记完成仍由作者在节点上明确操作。
// 上下文条跟着画布选中走:选中哪个节点,对话默认带上它。
// 分镜 / 列表视图:展开是右侧停靠面板、收起是 44px 竖条,和写作页的 Flutter 实现一致。
// 画布视图:同一个聊天面板换外层容器 —— 收起是右下角 Agent 头像悬浮球,展开是浮在画布上的卡片,
// 画布不让出宽度。Flutter 侧复用 AiChatPanel,只换外层(avoidWindowCaption = false),收起时保持挂载,
// 流式输出、滚动位置、输入框草稿都不丢。
// 关联文件: drama/app.jsx, drama/composer.jsx, drama/approval.jsx, ChatPanel.jsx

const DR_CHAT = [
  { role: "user", content: "第 2 场三个片段帮我检查一下参考：角色图都连上，2-3 的短烛补一下。" },
  {
    role: "assistant",
    blocks: [
      {
        type: "activity",
        steps: [
          { kind: "thinking", status: "success",
            detail: { type: "thinking", label: "推理过程", text: "先读第 2 场的三个片段和画布上的输入连线，对照提示词里的引用，找出没连上的。生成要花钱，只整理输入，不替作者提交。" } },
          { verb: "读取", icon: "eye", target: "片段 · 第 2 场 · 段 2-1 ～ 2-3", status: "success" },
          { verb: "读取", icon: "eye", target: "画布输入连线 · 12 条", status: "success",
            detail: { type: "paths", label: "引用了但没连上", items: ["段 2-3 · @短烛"] } },
          { verb: "编辑", icon: "note-pencil", target: "段 2-1 · 提示词", status: "success", mono: false,
            detail: { type: "diff", old: "右侧男子的手停在深色木案上", now: "@沈砚 · 青衫 的手停在深色木案上" } },
        ],
      },
      { type: "text", text: "段 2-2 的参考都齐了。段 2-1 第 3 个镜头把「右侧男子的手」改成引用沈砚的角色图，和已连的输入对上。\n\n段 2-2 的结果有一处穿帮，我按原配置重新生成一版。" },
      { type: "approval", id: "ap0" },
    ],
  },
  { role: "user", content: "前舱宽景图再出一版，周慎补个头像。我桌面上有张 布光参考.jpg，看看能不能按它调提示词。" },
  {
    role: "assistant",
    blocks: [
      {
        type: "activity",
        steps: [
          { verb: "读取", icon: "eye", target: "图片节点 · 前舱 · 夜 · 宽景", status: "success" },
          { verb: "生成图片", icon: "image", target: "前舱 · 夜 · 宽景", status: "running" },
          { verb: "生成头像", icon: "image", target: "周慎", status: "running" },
          { verb: "读取文件", icon: "file-text", target: "布光参考.jpg", status: "running" },
        ],
      },
      { type: "approval", id: "ap1" },
      { type: "approval", id: "ap2" },
      { type: "approval", id: "ap3" },
    ],
  },
  { role: "user", content: "把第 2 到 7 场抽出来的帧合成一版预览配上 BGM，然后把临时帧清掉。" },
  {
    role: "assistant",
    blocks: [
      {
        type: "activity",
        steps: [
          { verb: "读取", icon: "eye", target: "media-editing · ffmpeg", status: "success" },
          { verb: "合成预览", icon: "film-strip", target: "preview.mp4", status: "running" },
          { verb: "删除文件", icon: "trash", target: "sessions/c81f/frames/**", status: "running" },
        ],
      },
      { type: "approval", id: "ap4" },
      { type: "approval", id: "ap5" },
    ],
  },
];

// 带审批卡的助手消息:外层与 ChatBubble 一致,approval 块换成审批卡。
function DrAssistantTurn({ blocks, appr }) {
  return (
    <div className="m-bubble m-bubble--ai">
      <div className="m-bubble__avatar"><Icon name="sparkle" size={12} /></div>
      <div className="m-bubble__col">
        <div className="m-ui-tiny" style={{ marginBottom: 4 }}>主笔 · Primary agent</div>
        {blocks.map((b, i) => {
          if (b.type === "activity") return <ToolActivity key={i} steps={b.steps} />;
          if (b.type === "text") return <div className="m-bubble__text" key={i}><div className="m-bubble__content">{b.text}</div></div>;
          if (b.type === "approval") {
            const ap = appr.items.find((x) => x.id === b.id);
            return <DrApprovalCard key={i} ap={ap} focused={appr.focus === ap.id}
              onAllow={appr.onAllow} onDeny={appr.onDeny} />;
          }
          return null;
        })}
      </div>
    </div>
  );
}

function DrChatPanel({ context, onClose, aiSegs, onRevert, floating, style, appr }) {
  const [text, setText] = React.useState("");
  // 打开时停在最新消息,和 Flutter 聊天面板一致。
  const scrollRef = React.useRef(null);
  React.useEffect(() => {
    if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
  }, []);
  return (
    <aside className={"m-chat dr-chat" + (floating ? " dr-chat--float" : "")} style={style}
      onPointerDown={floating ? (e) => e.stopPropagation() : undefined}>
      {/* 头部对齐 Flutter 聊天面板:模型名 + 下拉 / 全屏 / 新会话 / 收起。 */}
      <div className="m-chat__head">
        <div className="m-chat__head-l">
          <Icon name="sparkle" size={16} color="var(--accent)" />
          <span className="m-ui-semibold">DeepSeek</span>
          <Icon name="caret-down" size={12} color="var(--text-muted)" />
        </div>
        <div className="m-chat__head-r">
          <button className="m-icon-btn" title="助手权限" onClick={appr.onOpenPerms}><Icon name="shield-check" size={14} /></button>
          <button className="m-icon-btn" title="全屏"><Icon name="arrows-out" size={14} /></button>
          <button className="m-icon-btn" title="新会话"><Icon name="note-pencil" size={14} /></button>
          <button className="m-icon-btn" title={floating ? "收起为悬浮球" : "收起"} onClick={onClose}>
            <Icon name={floating ? "minus" : "x"} size={14} />
          </button>
        </div>
      </div>
      <div className="m-chat__context">
        <Icon name="frame-corners" size={12} />
        <span>当前上下文：{DR_EPISODE.label} 制片{context ? ` · ${context}` : ""}</span>
      </div>
      <div className="m-chat__scroll" ref={scrollRef}>
        {DR_CHAT.map((m, i) => (m.blocks && m.blocks.some((b) => b.type === "approval")
          ? <DrAssistantTurn key={i} blocks={m.blocks} appr={appr} />
          : <ChatBubble key={i} {...m} />))}
      </div>
      <DrRunStrip runs={appr.runs} onLocate={appr.onLocate} onCancel={appr.onCancelRun} />
      {/* 同 Flutter PendingChangesSummaryCard:输入框正上方,改动已生效,逐条 / 全部回退。 */}
      {aiSegs.length > 0 && (
        <div style={{ margin: "0 var(--space-lg)" }}>
          <RecentChangesLog
            changes={aiSegs.map((n) => ({ title: `段 ${drSegNo(n)} · ${n.title}`, sub: n.ai === "new" ? "片段" : "提示词", change: n.ai === "new" ? "create" : "rewrite", node: n }))}
            onRevert={(c) => onRevert(c.node)}
            onRevertAll={() => aiSegs.forEach(onRevert)} />
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
            placeholder="让助手拆片段、改提示词、整理输入连线…"
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

// 收起态:对齐 Flutter NovelEditorCollapsedAiPanel —— 44px 竖条,AI 图标 + 竖排「AI」+ 展开箭头,整条可点。
// 只用于分镜 / 列表视图;画布视图用下面的悬浮球。
function DrChatRail({ onExpand }) {
  return (
    <button type="button" className="dr-airail" title="展开 AI 面板" onClick={onExpand}>
      <Icon name="sparkle" size={18} color="var(--accent)" />
      <span className="dr-airail__text">AI</span>
      <Icon name="caret-left" size={18} color="var(--text-muted)" />
    </button>
  );
}

// 画布视图的收起态:右下角 Agent 头像悬浮球。头像取设置 › AI 助手里的自定义头像,
// 没设置时回退内置 orchestrator 头像(Flutter AgentAvatar,slug = orchestrator)。
// 运行中:头像外圈转动 + 左侧进度胶囊,不展开面板也能知道助手在干活;有新回复时右上角小圆点。
// 展开时球保持在原位作为收起开关,面板浮在它上方。
// 有等待确认的请求时,胶囊换成「N 项待确认」,点开直接看到审批卡。
function DrAgentFab({ open, busy, progress, unread, waiting, onToggle }) {
  return (
    <div className="dr-aifab" onPointerDown={(e) => e.stopPropagation()}>
      {waiting > 0 && !open && (
        <button type="button" className="dr-aifab__pill is-waiting" onClick={onToggle} title="查看审批">
          <Icon name="shield-check" size={13} color="var(--accent-warm)" />
          <span>{waiting} 项待确认</span>
        </button>
      )}
      {busy && !open && !waiting && (
        <button type="button" className="dr-aifab__pill" onClick={onToggle} title="查看执行过程">
          <span className="dr-aifab__spin" />
          <span>执行中</span>
          {progress && <span className="dr-aifab__step">{progress}</span>}
        </button>
      )}
      <button type="button" className={"dr-aifab__ball" + (open ? " is-open" : "") + (busy ? " is-busy" : "")}
        title={open ? "收起 AI 面板" : "打开 AI 面板"} onClick={onToggle}>
        <img src="../assets/images/agent_avatars/viber.webp" alt="" draggable={false} />
        {(waiting > 0 || unread) && !open && !busy && <span className="dr-aifab__dot" />}
      </button>
    </div>
  );
}

Object.assign(window, { DrChatPanel, DrChatRail, DrAgentFab });
