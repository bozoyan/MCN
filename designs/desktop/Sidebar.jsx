// Home sidebar — mirrors lib/desktop/pages/home.dart _buildSidebar().
// The desktop home uses one navigation column: search, Works, AI entries,
// recent sessions, then Settings. Editor-only rails stay in EditorView.

function SectionGroupHeader({ children }) {
  return <div className="m-sb-group-header">{children}</div>;
}

function LeafItem({ icon, title, active, onClick }) {
  return (
    <button
      type="button"
      className={"m-sb-nav" + (active ? " is-selected" : "")}
      onClick={onClick}
    >
      <Icon name={icon} size={16} className="m-sb-nav__icon" />
      <span className="m-sb-nav__title">{title}</span>
      <Icon name="caret-right" size={16} className="m-sb-nav__go" />
    </button>
  );
}

function RecentSessions({ sessions }) {
  const [expanded, setExpanded] = React.useState(true);
  if (!sessions.length) return null;

  return (
    <div className="m-sb-recent">
      <button
        type="button"
        className="m-sb-row m-sb-row--header"
        onClick={() => setExpanded((value) => !value)}
      >
        <Icon name="chat-centered" size={16} />
        <span className="m-sb-row__title">最近对话</span>
        <span className="m-sb-row__spacer" />
        <Icon
          name="caret-right"
          size={14}
          style={{ transform: `rotate(${expanded ? 90 : 0}deg)`, opacity: 0.6 }}
        />
      </button>
      {expanded && (
        <div className="m-sb-section m-sb-section--padded">
          {sessions.map((session) => (
            <button key={session.id} type="button" className="m-sb-session">
              <Icon name="chat-centered" size={14} style={{ opacity: 0.55 }} />
              <div className="m-sb-leaf__meta">
                <span className="m-sb-leaf__title">{session.title}</span>
                <span className="m-sb-session__time">{session.time}</span>
              </div>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function Sidebar({ activeContent, onSelect, onOpenSettings }) {
  const sessions = window.REVERIC_DATA.recentSessions;

  return (
    <aside className="m-sidebar">
      {/* 作品搜索挪到了书库作品区那一行（只搜当前集合），侧栏不再放。 */}
      <div className="m-sidebar__scroll">
        <SectionGroupHeader>创作</SectionGroupHeader>
        {/* 小说和剧本合在一个作品库里：类型是作品的属性，在作品区按类型筛选，
            不再各占一个入口。 */}
        <LeafItem
          icon="books"
          title="作品"
          active={activeContent === "library"}
          onClick={() => onSelect("library")}
        />

        <SectionGroupHeader>AI</SectionGroupHeader>
        <LeafItem
          icon="sliders-horizontal"
          title="模型设置"
          active={activeContent === "modelSettings"}
          onClick={() => onSelect("modelSettings")}
        />
        <LeafItem
          icon="sparkle"
          title="智能体技能"
          active={activeContent === "skillLibrary" || activeContent === "skillList" || activeContent === "skill"}
          onClick={() => onSelect("skillLibrary")}
        />
        <LeafItem
          icon="users-three"
          title="专家团"
          active={activeContent === "expertTeam" || activeContent === "subagent"}
          onClick={() => onSelect("expertTeam")}
        />
        <LeafItem
          icon="paper-plane-tilt"
          title="快捷方式"
          active={activeContent === "shortcutList" || activeContent === "shortcut"}
          onClick={() => onSelect("shortcutList")}
        />

        <RecentSessions sessions={sessions} />

        <SectionGroupHeader>设置</SectionGroupHeader>
        <LeafItem icon="gear-six" title="设置" onClick={onOpenSettings} />
      </div>
    </aside>
  );
}

Object.assign(window, { Sidebar });
