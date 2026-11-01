// ContextPanel — the second rail. Two variants:
//  - LibraryContext: shows novel switcher + tag list + recent sessions
//  - ChapterContext: shows novel + chapter tree

// 对齐 Flutter ContextColumnScaffold:左 chevron 返回,右 collapse.svg 折叠整个左侧栏。
// 折叠由 EditorView 经 SidebarCollapseCtx 提供,调用方不用各自接 onCollapse。
const SidebarCollapseCtx = React.createContext(null);

function PanelHeader({ onBack, onCollapse }) {
  const collapse = React.useContext(SidebarCollapseCtx) || onCollapse;
  return (
    <div className="m-ctx__head">
      {onBack && (
        <button className="m-icon-btn" onClick={onBack} title="返回">
          <Icon name="caret-left" size={16} />
        </button>
      )}
      <span style={{ flex: 1 }} />
      <button className="m-icon-btn" title="折叠侧栏" onClick={collapse}>
        <SidebarCollapseIcon />
      </button>
    </div>
  );
}

function NovelSwitcher({ novel }) {
  if (!novel) {
    return (
      <button className="m-ctx__novel m-ctx__novel--empty" type="button">
        <span className="m-avatar m-avatar--brand" style={{ width: 36, height: 36 }}>
          <Icon name="books" size={16} />
        </span>
        <span style={{ flex: 1, textAlign: "left" }}>
          <div className="m-ui-medium" style={{ color: "var(--text-primary)" }}>选择作品</div>
          <div className="m-ui-tiny">未打开任何小说</div>
        </span>
        <Icon name="caret-down" size={12} />
      </button>
    );
  }
  return (
    <button className="m-ctx__novel" type="button">
      <span className="m-avatar m-avatar--user" style={{ width: 36, height: 36 }}>
        {novel.title.slice(0, 1)}
      </span>
      <span style={{ flex: 1, textAlign: "left", minWidth: 0 }}>
        <div className="m-ui-medium" style={{
          color: "var(--text-primary)",
          whiteSpace: "nowrap",
          overflow: "hidden",
          textOverflow: "ellipsis"
        }}>{novel.title}</div>
      </span>
      <Icon name="caret-down" size={12} />
    </button>
  );
}

function LibraryContext({ activeTag, onSelectTag, onBack }) {
  const D = window.REVERIC_DATA;
  return (
    <aside className="m-ctx">
      <PanelHeader onCollapse={() => {}} />
      <NovelSwitcher novel={null} />

      <div className="m-ctx__sec-head">
        <span className="m-ctx__sec-title">标签</span>
        <span className="m-ctx__sec-count">{D.tags.length}</span>
      </div>
      <div className="m-ctx__list">
        {D.tags.map((t) => (
          <button
            key={t.key}
            type="button"
            className={"m-sb-tag" + (activeTag === t.key ? " is-selected" : "")}
            onClick={() => onSelectTag(t.key)}
          >
            <span className="m-dot"></span>
            <span className="m-sb-tag__label">{t.label}</span>
            <span className="m-sb-tag__count">{t.count}</span>
          </button>
        ))}
      </div>

      <div className="m-ctx__sec-head" style={{ marginTop: 12 }}>
        <span className="m-ctx__sec-title">最近会话</span>
      </div>
      <div className="m-ctx__list">
        {D.recentSessions.map((s) => (
          <button key={s.id} type="button" className="m-sb-session">
            <Icon name="chat-centered" size={14} style={{ opacity: 0.55, marginTop: 2 }} />
            <div className="m-sb-leaf__meta">
              <div className="m-sb-leaf__title">{s.title}</div>
              <div className="m-sb-leaf__sub">{s.time}</div>
            </div>
          </button>
        ))}
      </div>
    </aside>
  );
}

function ChapterContext({ novel, activeChapterId, onSelectChapter, onBack }) {
  const D = window.REVERIC_DATA;
  const data = D.chapters[novel.id] || D.chapters.n1;
  const totalChapters = data.volumes.reduce((sum, v) => sum + v.chapters.length, 0);

  return (
    <aside className="m-ctx">
      <PanelHeader onBack={onBack} onCollapse={() => {}} />
      <NovelSwitcher novel={novel} />

      <div className="m-ctx__sec-head">
        <span className="m-ctx__sec-title">章节</span>
        <span className="m-ctx__sec-count">{totalChapters}</span>
        <button className="m-icon-btn m-icon-btn--ghost" title="新增章节">
          <Icon name="plus" size={12} />
        </button>
      </div>

      <div className="m-ctx__list m-ctx__list--chapters">
        {data.volumes.flatMap((v) => v.chapters).map((c) => (
          <button
            key={c.id}
            type="button"
            onClick={() => onSelectChapter(c.id)}
            className={"m-ctx__chapter" + (c.id === activeChapterId ? " is-active" : "")}
          >
            <Icon name="file-text" size={14} style={{ opacity: 0.6 }} />
            <span className="m-ctx__chapter-title">第{parseInt(c.number)}章 {c.title}</span>
            <Icon name="article" size={12} style={{ opacity: 0.4 }} />
          </button>
        ))}
        <button type="button" className="m-ctx__add">
          <Icon name="plus" size={14} />
          <span>新增章节</span>
        </button>
      </div>
    </aside>
  );
}

Object.assign(window, { LibraryContext, ChapterContext, SidebarCollapseCtx });
