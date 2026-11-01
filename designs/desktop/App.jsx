// Top-level app — routes between Library, Editor, and inline content panels.
// Content selection mirrors Flutter's _HomeContentSelection sealed class.

const CONTENT = {
  LIBRARY: "library",          // 作品（小说与剧本同库）
  // Edit-panel selections (a single entity).
  SUBAGENT: "subagent",
  SKILL: "skill",
  AGENT_PROFILE: "agentProfile",
  SHORTCUT: "shortcut",
  // Management-grid selections (a flat AI nav target).
  AGENT_PROFILE_LIST: "agentProfileList",
  SUBAGENT_LIST: "subagentList",
  SKILL_LIST: "skillList",
  SHORTCUT_LIST: "shortcutList",
  // AgentSkill 技能库(Home 入口)— 复用 SkillSetup 的 home 模式。
  SKILL_LIBRARY: "skillLibrary",
  // 「智能体」拆分:模型设置(内置对话 subagent 配模型) + 专家团(官方/自定义/广场)。
  MODEL_SETTINGS: "modelSettings",
  EXPERT_TEAM: "expertTeam",
};

// nav kind ↔ the list type its grid opens, and the entity type its cards open.
const NAV_KINDS = {
  agentProfile: { list: CONTENT.AGENT_PROFILE_LIST, entity: CONTENT.AGENT_PROFILE },
  subagent: { list: CONTENT.SUBAGENT_LIST, entity: CONTENT.SUBAGENT },
  skill: { list: CONTENT.SKILL_LIST, entity: CONTENT.SKILL },
  shortcut: { list: CONTENT.SHORTCUT_LIST, entity: CONTENT.SHORTCUT },
};

// Which sidebar nav owns a given content selection (highlights the nav item).
function navKindOf(type) {
  switch (type) {
    case CONTENT.AGENT_PROFILE_LIST:
    case CONTENT.AGENT_PROFILE:
      return "agentProfile";
    case CONTENT.SUBAGENT_LIST:
    case CONTENT.SUBAGENT:
      return "subagent";
    case CONTENT.SKILL_LIST:
    case CONTENT.SKILL:
    case CONTENT.SKILL_LIBRARY:
      return "skill";
    case CONTENT.SHORTCUT_LIST:
    case CONTENT.SHORTCUT:
      return "shortcut";
    default:
      return null;
  }
}

// ?novel=n1 直接落到该作品的编辑器 —— 独立路由页(画布 / 剧本制作)返回时用,
// 免得从整页跳回来只能回到作品库。
const DEEP_NOVEL = new URLSearchParams(window.location.search).get("novel");
// ?nav=script 再指定编辑器落在哪个栏目（剧本项目分区多，单独看某一屏时用）。
const DEEP_NAV = new URLSearchParams(window.location.search).get("nav");

function App() {
  // ?screen=cover 直接落到封面工作台，方便单独看这一屏。
  const coverDemo = React.useMemo(
    () => new URLSearchParams(window.location.search).get("screen") === "cover",
    []
  );
  // ?screen=comments 直接落到章节正文，看选区批注这一条链路。
  const commentsDemo = React.useMemo(
    () => new URLSearchParams(window.location.search).get("screen") === "comments",
    []
  );
  // ?screen=map 直接落到地图工作台；再加 &state=empty 看还没有底图的空态。
  const mapDemo = React.useMemo(
    () => new URLSearchParams(window.location.search).get("screen") === "map",
    []
  );
  const [view, setView] = React.useState(
    coverDemo || commentsDemo || mapDemo || DEEP_NOVEL ? "editor" : "library"
  );
  const [openNovel, setOpenNovel] = React.useState(() => {
    if (coverDemo || commentsDemo || mapDemo) return window.REVERIC_DATA.novels[0];
    if (!DEEP_NOVEL) return null;
    return (
      window.REVERIC_DATA.novels.find((n) => n.id === DEEP_NOVEL) ||
      window.REVERIC_DATA.novels[0]
    );
  });
  // ?screen=settings&section=subscription 直接打开设置的某一页，沿用上面的深链约定。
  const settingsDemo = React.useMemo(() => {
    const q = new URLSearchParams(window.location.search);
    return q.get("screen") === "settings" ? (q.get("section") || "appearance") : null;
  }, []);
  const [showSettings, setShowSettings] = React.useState(!!settingsDemo);
  const [settingsSection, setSettingsSection] = React.useState(settingsDemo || "appearance");
  // 深链到某个 section 内部的初始状态（用量页的 tab / 选中的会话）。
  const [settingsDeepLink, setSettingsDeepLink] = React.useState(null);

  // 入口既可能是「设置」按钮（收到 click 事件），也可能是聊天面板的用量 chip
  // （收到 {section, tab, sessionId}）。
  const openSettings = (target) => {
    if (target && typeof target === "object" && target.section) {
      setSettingsSection(target.section);
      setSettingsDeepLink(target);
    } else {
      setSettingsDeepLink(null);
    }
    setShowSettings(true);
  };

  // Mirrors home.dart's _HomeContentSelection sealed class.
  const [selection, setSelection] = React.useState({
    type: CONTENT.LIBRARY,
    tag: null,
    entity: null,
  });

  const selectContent = (next) => {
    setSelection((prev) => {
      if (prev.type === next.type && prev.entity?.id === next.entity?.id && prev.tag === next.tag) {
        return prev;
      }
      return next;
    });
  };

  const onOpenNovel = (n) => {
    setOpenNovel(n);
    setView("editor");
  };
  const onBackToLibrary = () => setView("library");

  // Sidebar callbacks
  const onSelectHomeContent = (type) =>
    selectContent({ type, tag: null, entity: null });
  // Sidebar AI nav → open the kind's management grid.
  // “智能体技能”改为打开 AgentSkill 技能库(Home 模式的 SkillSetup)。
  const onOpenList = (kind) => {
    if (kind === "skill") {
      selectContent({ type: CONTENT.SKILL_LIBRARY, tag: null, entity: null });
      return;
    }
    selectContent({ type: NAV_KINDS[kind].list, tag: null, entity: null });
  };
  // Grid card tap / 新建 → open the entity edit panel.
  const onOpenEntity = (sel) => selectContent(sel);
  // Edit-panel back → return to the kind's grid (mirrors onBack in home.dart).
  const backToList = (entityType) => {
    const kind = navKindOf(entityType);
    selectContent({ type: NAV_KINDS[kind].list, tag: null, entity: null });
  };

  // Main content rendering — mirrors Flutter's switch expression
  let mainContent;
  if (selection.type === CONTENT.MODEL_SETTINGS) {
    mainContent = (
      <div className="m-main">
        <ModelSettingsPage
          onGotoExperts={() =>
            selectContent({ type: CONTENT.EXPERT_TEAM, tag: null, entity: null })
          }
        />
      </div>
    );
  } else if (selection.type === CONTENT.EXPERT_TEAM) {
    mainContent = (
      <div className="m-main">
        <ExpertTeamPage />
      </div>
    );
  } else if (selection.type === CONTENT.SKILL_LIBRARY) {
    // Home 的“智能体技能”入口 → AgentSkill 技能库(SkillSetup home 模式)。
    mainContent = (
      <div className="m-main">
        <SkillSetup />
      </div>
    );
  } else if (
    selection.type === CONTENT.AGENT_PROFILE_LIST ||
    selection.type === CONTENT.SUBAGENT_LIST ||
    selection.type === CONTENT.SKILL_LIST ||
    selection.type === CONTENT.SHORTCUT_LIST
  ) {
    mainContent = (
      <div className="m-main">
        <ManagementGridView
          kind={navKindOf(selection.type)}
          onOpen={(entity) =>
            selectContent({ type: NAV_KINDS[navKindOf(selection.type)].entity, entity })
          }
          onCreate={onOpenEntity}
        />
      </div>
    );
  } else if (selection.type === CONTENT.SUBAGENT && selection.entity) {
    mainContent = (
      <div className="m-main">
        <SubagentEditPanel
          entity={selection.entity}
          onBack={() => backToList(CONTENT.SUBAGENT)}
        />
      </div>
    );
  } else if (selection.type === CONTENT.SKILL && selection.entity) {
    mainContent = (
      <div className="m-main">
        <SkillEditPanel
          entity={selection.entity}
          onBack={() => backToList(CONTENT.SKILL)}
        />
      </div>
    );
  } else if (selection.type === CONTENT.AGENT_PROFILE && selection.entity) {
    mainContent = (
      <div className="m-main">
        <AgentEditPanel
          entity={selection.entity}
          variant="agentProfile"
          onBack={() => backToList(CONTENT.AGENT_PROFILE)}
        />
      </div>
    );
  } else if (selection.type === CONTENT.SHORTCUT && selection.entity) {
    mainContent = (
      <div className="m-main">
        <AgentEditPanel
          entity={selection.entity}
          variant="shortcut"
          onBack={() => backToList(CONTENT.SHORTCUT)}
        />
      </div>
    );
  } else {
    mainContent = <LibraryView onOpenNovel={onOpenNovel} />;
  }

  return (
    <WindowFrame>
      <div className="m-app">
        {view === "library" ? (
          <React.Fragment>
            <Sidebar
              activeContent={selection.type}
              onSelect={onSelectHomeContent}
              onOpenSettings={openSettings}
            />
            {mainContent}
          </React.Fragment>
        ) : (
          <EditorView
            novel={openNovel}
            onBack={onBackToLibrary}
            onOpenSettings={openSettings}
            initialSection={
              coverDemo ? "cover" : mapDemo ? "map" : commentsDemo ? "chapters" : DEEP_NAV
            }
          />
        )}
        {showSettings && (
          <SettingsDialog
            onClose={() => setShowSettings(false)}
            section={settingsSection}
            setSection={(sec) => { setSettingsSection(sec); setSettingsDeepLink(null); }}
            deepLink={settingsDeepLink}
          />
        )}
      </div>
    </WindowFrame>
  );
}

const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App />);
