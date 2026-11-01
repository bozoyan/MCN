// 正文批注 —— 选区工具条 + 锚定选区的浮动批注气泡。
// 批注是作者写给自己的笔记，不接 AI：要问助手走工具条上的「加入对话」。
// 由 ManuscriptEditor 持有状态并调用；这里只做呈现与定位。

// 本章已有的批注。anchor 用「段落序号 + 原文片段」定位，
// 与真实实现里的 TextRange 等价，但 mock 数据改起来直观。
const CHAPTER_COMMENTS = [
  {
    id: "cm1",
    para: 3,
    quote: "指甲很短，但不是男人的样子",
    status: "open",
    entries: [
      {
        text: "这里点得太明。凤瑶的女装伏笔要留到第七章，这一句几乎等于直说了。只留物理细节，判断交给读者。",
        time: "14:02",
      },
    ],
  },
  {
    id: "cm2",
    para: 5,
    quote: "像伤疤一样长在脸上",
    status: "resolved",
    entries: [
      {
        text: "这个比喻第一章写过一次「像旧伤」，重复了。先留着，二稿再换。",
        time: "昨天 21:40",
      },
    ],
  },
];

// 把一段正文按批注锚点切开，命中的片段包成可点的 <mark>。
function renderParagraphWithMarks(text, marks, activeId, onMarkClick) {
  if (!marks || marks.length === 0) {
    return text;
  }
  // 先算出每条批注在本段中的区间，按起点排序，重叠的后者让位。
  const ranges = [];
  marks.forEach((c) => {
    const start = text.indexOf(c.quote);
    if (start >= 0) {
      ranges.push({ start, end: start + c.quote.length, comment: c });
    }
  });
  ranges.sort((a, b) => a.start - b.start);

  const nodes = [];
  let cursor = 0;
  ranges.forEach((r, i) => {
    if (r.start < cursor) {
      return;
    }
    if (r.start > cursor) {
      nodes.push(text.slice(cursor, r.start));
    }
    const c = r.comment;
    const cls = [
      "m-cmt-mark",
      c.status === "resolved" ? "m-cmt-mark--resolved" : "",
      c.status === "pending" ? "m-cmt-mark--pending" : "",
      c.id === activeId ? "is-active" : "",
    ]
      .filter(Boolean)
      .join(" ");
    nodes.push(
      <mark
        key={`${c.id}-${i}`}
        className={cls}
        data-comment-id={c.id}
        onClick={(e) => {
          e.stopPropagation();
          onMarkClick(c.id, e.currentTarget.getBoundingClientRect());
        }}
      >
        {text.slice(r.start, r.end)}
      </mark>
    );
    cursor = r.end;
  });
  if (cursor < text.length) {
    nodes.push(text.slice(cursor));
  }
  return nodes;
}

// 选中正文后浮在选区上方的工具条。与 Flutter 的 _ChapterSelectionToolbar
// 同构：一排文字按钮 + 细分隔线，「批注」是这次新增的入口，用 accent 强调。
function SelectionToolbar({ rect, onComment, onAddToChat, onCopy }) {
  if (!rect) {
    return null;
  }
  const items = [
    { key: "comment", label: "批注", accent: true, onClick: onComment },
    { key: "chat", label: "加入对话", onClick: onAddToChat },
    { key: "copy", label: "复制", onClick: onCopy },
  ];
  return (
    <div
      className="m-sel-toolbar"
      style={{ left: rect.left + rect.width / 2, top: rect.top - 8 }}
      onMouseDown={(e) => e.preventDefault()}
    >
      {items.map((item, i) => (
        <React.Fragment key={item.key}>
          {i > 0 && <div className="m-sel-toolbar__sep" />}
          <button
            type="button"
            className={`m-sel-toolbar__btn${item.accent ? " m-sel-toolbar__btn--accent" : ""}`}
            onClick={item.onClick}
          >
            {item.accent && <Icon name="chat-centered" size={13} />}
            <span>{item.label}</span>
          </button>
        </React.Fragment>
      ))}
    </div>
  );
}

// 一条批注。全部出自作者本人，所以不带身份区分，只用时间分层。
function CommentEntry({ entry, first }) {
  return (
    <div className="m-cmt-item">
      {first ? (
        <span className="m-avatar m-avatar--user">作</span>
      ) : (
        <span className="m-cmt-item__thread" />
      )}
      <div className="m-cmt-item__col">
        <div className="m-cmt-item__time">{entry.time}</div>
        <div className="m-cmt-item__text">{entry.text}</div>
      </div>
    </div>
  );
}

// 批注气泡。两种形态共用一张卡片：
//   draft   —— 刚选中文本，还没写批注
//   thread  —— 已有批注，展示笔记并可继续追加
function CommentPopover({
  mode,
  rect,
  quote,
  comment,
  draftText,
  onDraftChange,
  onSubmitDraft,
  replyText,
  onReplyChange,
  onSubmitReply,
  onResolve,
  onReopen,
  onDelete,
  onClose,
}) {
  const fieldRef = React.useRef(null);
  React.useEffect(() => {
    if (mode === "draft" && fieldRef.current) {
      fieldRef.current.focus();
    }
  }, [mode]);

  React.useEffect(() => {
    function onKey(e) {
      if (e.key === "Escape") {
        onClose();
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  if (!rect) {
    return null;
  }

  // 气泡宽 340，贴着视口边缘时把中心点收回来，避免被裁掉。
  const half = 170 + 16;
  const centerX = Math.min(
    Math.max(rect.left + rect.width / 2, half),
    window.innerWidth - half
  );
  // 选区下方放不下时翻到上方。
  const below = rect.bottom + 10;
  const flip = below + 260 > window.innerHeight;
  const style = flip
    ? { left: centerX, top: rect.top - 10, transform: "translate(-50%, -100%)" }
    : { left: centerX, top: below };

  const resolved = comment && comment.status === "resolved";

  return (
    <React.Fragment>
      <div className="m-cmt-scrim" onMouseDown={onClose} />
      <div className="m-cmt-pop" style={style}>
        <div className="m-cmt-pop__head">
          <Icon name="chat-centered" size={13} />
          <span>{mode === "draft" ? "新建批注" : resolved ? "批注 · 已解决" : "批注"}</span>
          <span className="m-cmt-pop__head-spacer" />
          {mode === "thread" && (
            <React.Fragment>
              <button
                className="m-icon-btn m-icon-btn--ghost"
                title={resolved ? "重新打开" : "标记为已解决"}
                onClick={resolved ? onReopen : onResolve}
              >
                <Icon name={resolved ? "arrow-counter-clockwise" : "check"} size={13} />
              </button>
              <button className="m-icon-btn m-icon-btn--ghost" title="删除批注" onClick={onDelete}>
                <Icon name="trash-simple" size={13} />
              </button>
            </React.Fragment>
          )}
          <button className="m-icon-btn m-icon-btn--ghost" title="关闭" onClick={onClose}>
            <Icon name="x" size={13} />
          </button>
        </div>

        <div className="m-cmt-quote">{quote}</div>

        <div className="m-cmt-pop__body">
          {mode === "draft" ? (
            <div className="m-cmt-compose">
              <textarea
                ref={fieldRef}
                className="m-cmt-compose__field"
                placeholder="写下你对这一段的想法…"
                value={draftText}
                onChange={(e) => onDraftChange(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
                    onSubmitDraft();
                  }
                }}
              />
              <div className="m-cmt-compose__row">
                <span className="m-cmt-compose__hint">⌘↩ 保存</span>
                <span className="m-cmt-compose__row-spacer" />
                <button type="button" className="m-btn m-btn--text m-btn--sm" onClick={onClose}>
                  取消
                </button>
                <button
                  type="button"
                  className="m-btn m-btn--primary m-btn--sm"
                  disabled={!draftText.trim()}
                  style={!draftText.trim() ? { opacity: 0.45, cursor: "default" } : undefined}
                  onClick={onSubmitDraft}
                >
                  批注
                </button>
              </div>
            </div>
          ) : (
            <React.Fragment>
              {comment.entries.map((entry, i) => (
                <CommentEntry key={i} entry={entry} first={i === 0} />
              ))}
              {!resolved && (
                <div className="m-cmt-reply">
                  <input
                    className="m-cmt-reply__field"
                    placeholder="再记一笔…"
                    value={replyText}
                    onChange={(e) => onReplyChange(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        onSubmitReply();
                      }
                    }}
                  />
                  <button
                    className="m-icon-btn"
                    title="保存"
                    disabled={!replyText.trim()}
                    style={!replyText.trim() ? { opacity: 0.4 } : undefined}
                    onClick={onSubmitReply}
                  >
                    <Icon name="paper-plane-tilt" size={15} />
                  </button>
                </div>
              )}
            </React.Fragment>
          )}
        </div>
      </div>
    </React.Fragment>
  );
}

Object.assign(window, {
  CHAPTER_COMMENTS,
  renderParagraphWithMarks,
  SelectionToolbar,
  CommentPopover,
});
