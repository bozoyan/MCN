// Manuscript editor — top breadcrumb toolbar, chapter meta, 章节大纲
// summary card, body, status bar. Matches the actual Reveric editor view.
// 正文选区批注（选区工具条 + 浮动气泡）见 Comments.jsx / comments.css。

function EditorToolbar({ novelTitle, chapter, onSave }) {
  return (
    <div className="m-editor__topbar">
      <div className="m-editor__crumbs">
        <button className="m-icon-btn m-icon-btn--ghost" style={{ marginRight: 6 }} title="折叠章节侧栏">
          <Icon name="caret-left" size={14} />
        </button>
        <span className="m-crumb">{novelTitle}</span>
        <Icon name="caret-right" size={12} style={{ opacity: 0.4 }} />
        <span className="m-crumb">章节</span>
        <Icon name="caret-right" size={12} style={{ opacity: 0.4 }} />
        <span className="m-crumb m-crumb--active">第{parseInt(chapter.number)}章 · {chapter.title}</span>
      </div>
      <div className="m-editor__topbar-r">
        <button className="m-icon-btn" title="历史">
          <Icon name="clock-counter-clockwise" size={16} />
        </button>
        <button className="m-icon-btn" title="章节设置">
          <Icon name="gear-six" size={16} />
        </button>
        <button className="m-icon-btn" title="预览">
          <Icon name="eye" size={16} />
        </button>
        <button className="m-btn m-btn--primary m-btn--sm" onClick={onSave}>保存</button>
      </div>
    </div>
  );
}

function ChapterStatePill({ state }) {
  return (
    <button type="button" className={`m-state-pill m-state-pill--${state}`}>
      <Icon name="pencil-simple" size={11} />
      <span>{state}</span>
    </button>
  );
}

function OutlineCard({ outline, expanded, onToggle }) {
  return (
    <div className="m-outline-card">
      <button type="button" className="m-outline-card__head" onClick={onToggle}>
        <Icon name="trend-up" size={14} />
        <span className="m-outline-card__title">章节大纲</span>
        <span style={{ flex: 1 }} />
        {/* 头部整条是折叠按钮，里面不能再套 <button>；「展开」用 span 承载并拦住冒泡。 */}
        <span
          role="button"
          tabIndex={0}
          className="m-icon-btn m-icon-btn--ghost"
          title="展开"
          onClick={(event) => event.stopPropagation()}
        >
          <Icon name="arrows-out" size={12} />
        </span>
        <Icon
          name="caret-down"
          size={14}
          style={{
            transform: `rotate(${expanded ? 0 : -90}deg)`,
            transition: "transform 180ms ease",
            opacity: 0.6,
          }}
        />
      </button>
      {expanded && outline && (
        <div className="m-outline-card__body">{outline}</div>
      )}
    </div>
  );
}

function ManuscriptEditor({ novel, chapter }) {
  const [outlineOpen, setOutlineOpen] = React.useState(false);
  const [appliedMessage, setAppliedMessage] = React.useState("");

  // ---- 批注状态 ----------------------------------------------------
  // 批注是作者写给自己的笔记，不接 AI —— 要问助手走工具条上的「加入对话」。
  const body = chapter.body || [];
  const [comments, setComments] = React.useState(CHAPTER_COMMENTS);
  const [sel, setSel] = React.useState(null);   // 选区工具条：{ rect, text, para }
  const [pop, setPop] = React.useState(null);   // 批注气泡：{ mode, rect, id?, quote, para }
  const [draftText, setDraftText] = React.useState("");
  const [replyText, setReplyText] = React.useState("");
  const bodyRef = React.useRef(null);

  const wordCount = body.join("").length;
  const minutes = Math.max(1, Math.round(wordCount / 200));
  const openCount = comments.filter((c) => c.status === "open").length;
  const activeComment = pop && pop.id ? comments.find((c) => c.id === pop.id) : null;

  function toast(message) {
    setAppliedMessage(message);
    window.setTimeout(() => setAppliedMessage(""), 3200);
  }


  // 选中正文 → 在选区上方浮出工具条。折叠选区（只是点了一下）则收起。
  function handleBodyMouseUp() {
    window.setTimeout(() => {
      const s = window.getSelection();
      if (!s || s.isCollapsed || !s.rangeCount) {
        setSel(null);
        return;
      }
      const text = s.toString().trim();
      const node = s.anchorNode;
      const el = node && (node.nodeType === 1 ? node : node.parentElement);
      const para = el && el.closest("[data-para]");
      if (!text || !para || !bodyRef.current || !bodyRef.current.contains(para)) {
        setSel(null);
        return;
      }
      setSel({
        rect: s.getRangeAt(0).getBoundingClientRect(),
        text,
        para: Number(para.dataset.para),
      });
    }, 0);
  }

  function closeAll() {
    setSel(null);
    setPop(null);
    setDraftText("");
    setReplyText("");
  }

  function openDraft() {
    if (!sel) return;
    setPop({ mode: "draft", rect: sel.rect, quote: sel.text, para: sel.para });
    setSel(null);
    setDraftText("");
  }

  function openThread(id, rect) {
    const c = comments.find((x) => x.id === id);
    if (!c) return;
    setSel(null);
    setReplyText("");
    setPop({ mode: "thread", rect, id, quote: c.quote, para: c.para });
  }

  function submitDraft() {
    const text = draftText.trim();
    if (!text || !pop) return;
    const id = `cm${Date.now()}`;
    const created = {
      id,
      para: pop.para,
      quote: pop.quote,
      status: "open",
      entries: [{ text, time: "刚刚" }],
    };
    setComments((list) => [...list, created]);
    setPop({ ...pop, mode: "thread", id });
    setDraftText("");
  }

  function submitReply() {
    const text = replyText.trim();
    if (!text || !pop) return;
    setComments((list) =>
      list.map((c) =>
        c.id === pop.id ? { ...c, entries: [...c.entries, { text, time: "刚刚" }] } : c
      )
    );
    setReplyText("");
  }

  function setStatus(id, status) {
    setComments((list) => list.map((c) => (c.id === id ? { ...c, status } : c)));
  }

  function deleteComment(id) {
    setComments((list) => list.filter((c) => c.id !== id));
    setPop(null);
  }

  // 状态栏计数 → 跳到第一条未解决的批注并展开。
  function jumpToFirstOpen() {
    const first = comments.find((c) => c.status === "open");
    if (!first) return;
    const el = document.querySelector(`[data-comment-id="${first.id}"]`);
    if (!el) return;
    el.scrollIntoView({ block: "center", behavior: "smooth" });
    window.setTimeout(() => openThread(first.id, el.getBoundingClientRect()), 320);
  }

  return (
    <div className="m-editor">
      <EditorToolbar novelTitle={novel.title} chapter={chapter} />

      <div
        className="m-editor__scroll"
        onScroll={() => {
          // 浮层锚在视口坐标上，滚动即失效 —— 收起而不是让它飘着。
          setSel(null);
          setPop((p) => (p && p.mode === "thread" ? null : p));
        }}
      >
        <div className="m-editor__inner">
          <div className="m-editor__meta">
            <span className="m-chapter-num">第{parseInt(chapter.number)}章</span>
            <ChapterStatePill state="草稿" />
          </div>

          <h1 className="m-editor__title" contentEditable="true" suppressContentEditableWarning>
            {chapter.title}
          </h1>

          <OutlineCard
            outline={chapter.summary}
            expanded={outlineOpen}
            onToggle={() => setOutlineOpen((o) => !o)}
          />

          <div
            className="m-editor__body"
            ref={bodyRef}
            contentEditable="true"
            suppressContentEditableWarning
            onMouseUp={handleBodyMouseUp}
          >
            {body.map((p, i) => {
              const marks = comments.filter((c) => c.para === i);
              // 正在写的批注：先把选区高亮固化，textarea 抢走焦点也不会“丢锚点”。
              const pending =
                pop && pop.mode === "draft" && pop.para === i
                  ? [{ id: "__pending", quote: pop.quote, status: "pending" }]
                  : [];
              return (
                <p key={i} data-para={i}>
                  {renderParagraphWithMarks(
                    p,
                    [...marks, ...pending],
                    pop && pop.id ? pop.id : "__pending",
                    openThread
                  )}
                </p>
              );
            })}
          </div>
        </div>
      </div>

      <div className="m-editor__statusbar">
        <span><Icon name="floppy-disk" size={12} /> 已启用自动保存</span>
        <span><Icon name="text-t" size={12} /> 字数 {(wordCount / 1000).toFixed(1)}千</span>
        <span><Icon name="clock" size={12} /> 预计阅读 {minutes} 分钟</span>
        <span className="m-editor__statusbar-spacer" />
        {comments.length > 0 && (
          <button type="button" className="m-cmt-status" onClick={jumpToFirstOpen}>
            <Icon name="chat-centered" size={12} />
            <span>批注</span>
            <span className="m-cmt-status__count">{openCount}</span>
          </button>
        )}
        <span><Icon name="article" size={12} /> 格式化</span>
        <span><Icon name="clock-counter-clockwise" size={12} /> 历史</span>
      </div>

      {!pop && (
        <SelectionToolbar
          rect={sel && sel.rect}
          onComment={openDraft}
          onAddToChat={() => {
            setSel(null);
            toast("已把这段加入当前对话");
          }}
          onCopy={() => {
            setSel(null);
            toast("已复制");
          }}
        />
      )}

      {pop && (
        <CommentPopover
          mode={pop.mode}
          rect={pop.rect}
          quote={pop.quote}
          comment={activeComment}
          draftText={draftText}
          onDraftChange={setDraftText}
          onSubmitDraft={submitDraft}
          replyText={replyText}
          onReplyChange={setReplyText}
          onSubmitReply={submitReply}
          onResolve={() => {
            setStatus(pop.id, "resolved");
            toast("批注已标记为已解决");
          }}
          onReopen={() => setStatus(pop.id, "open")}
          onDelete={() => deleteComment(pop.id)}
          onClose={closeAll}
        />
      )}

      {appliedMessage && (
        <div className="m-editor-toast" role="status">
          <Icon name="check-circle" size={16} />
          <span>{appliedMessage}</span>
        </div>
      )}
    </div>
  );
}

Object.assign(window, { ManuscriptEditor });
