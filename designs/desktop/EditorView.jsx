// Editor view — NavRail + ChapterContext + main + AgentPanel.
// 普通 novel:概览(overview)渲染 NovelOverview 落地页(镜像 Flutter novel_overview.dart);
// 其余同名栏目进编辑器/列表。

function EditorView({ novel, onBack, onOpenSettings, initialSection = null }) {
  const D = window.REVERIC_DATA;
  const data = D.chapters[novel.id] || D.chapters.n1;
  const [activeChapterId, setActiveChapterId] = React.useState(data.activeChapterId);
  const [agentOpen, setAgentOpen] = React.useState(true);
  // 左侧栏折叠(对齐 Flutter sidebarCollapsed):NavRail 缩成 48px 图标栏,第二栏隐藏。
  const [sidebarCollapsed, setSidebarCollapsed] = React.useState(false);
  const [rightPane, setRightPane] = React.useState("agent"); // 'chat' | 'agent'
  // 两种 novel 都以概览为落地页(对齐 Flutter WorkspaceSelection.overview 默认值)。
  const [navActive, setNavActive] = React.useState(
    initialSection || "overview"
  );
  const [activeCharacterId, setActiveCharacterId] = React.useState("shen");
  // 剧本型 novel(novel.screenplay):当前季 + 当前集 + 当前场次由这里持有,
  // 第二列(ScreenplayContext)与主区(ScreenplayWorkspace)共用同一份。
  // 当前季是本机记住的工作区选择,重开作品时恢复上次那一季;失效就落到第一季。
  const [spSeason, setSpSeason] = React.useState(() => {
    if (!novel.screenplay) return null;
    const seasons = spSeasonsOf(novel.screenplay.id);
    const saved = SP_CURRENT_SEASON[novel.screenplay.id];
    if (saved && seasons.some((s) => s.id === saved)) return saved;
    return seasons.length ? seasons[0].id : null;
  });
  // ?scene=s2 深链(制作画布「查看原文」/返回)：落到该场所在的集与场次。
  const deepScene = React.useMemo(() => {
    if (!novel.screenplay) return null;
    const id = new URLSearchParams(window.location.search).get("scene");
    return SP_SCENES.find((s) => s.id === id && s.proj === novel.screenplay.id) || null;
  }, [novel]);
  const [spEp, setSpEp] = React.useState(() => {
    if (!novel.screenplay) return null;
    if (deepScene) return deepScene.ep;
    const saved = SP_CURRENT_SEASON[novel.screenplay.id];
    const first = spEpisodesOf(novel.screenplay.id, saved)[0];
    return first ? first.id : null;
  });
  const [spSceneId, setSpSceneId] = React.useState(() => {
    if (!novel.screenplay) return null;
    if (deepScene) return deepScene.id;
    const saved = SP_CURRENT_SEASON[novel.screenplay.id];
    const firstEp = spEpisodesOf(novel.screenplay.id, saved)[0];
    const first = spScenesOf(novel.screenplay.id, firstEp ? firstEp.id : null)[0];
    return first ? first.id : null;
  });

  const chapter = data.activeChapter;
  const isAgentSkills = navActive === "agentSkills";
  const isGraph = navActive === "graph";
  // 资料·封面 → 封面工作台，自己接管方案栏 / 画布 / 设计师面板三列。
  const isCover = navActive === "cover";
  // 世界观·地图 → 地图工作台，同样接管后三列：地图列表+地点树 / 画布 / 制图师。
  const isMap = navActive === "map";
  // 普通 novel 的 创作·人物 → 人物档案页（第二列换成人物列表）。
  const isCharacters = navActive === "characters";
  // 剧本型 novel:第二列换成 剧集+场次,主区换成剧本工作区,右侧 AI 助手不变。
  const isScreenplay = !!novel.screenplay;

  function handleNavSelect(id) {
    setNavActive(id);
    if (id === "overview") {
      setAgentOpen(true);
      setRightPane("agent");
    }
  }

  // 换一集 → 场次列表跟着换，当前场次落到该集第一场。
  function handleSelectEp(id) {
    setSpEp(id);
    const first = spScenesOf(novel.screenplay.id, id)[0];
    setSpSceneId(first ? first.id : null);
  }

  // 换一季 → 当前集和当前场都要跟着落到新季里，否则主区会拿着上一季的集号渲染。
  function handleSelectSeason(id) {
    setSpSeason(id);
    const firstEp = spEpisodesOf(novel.screenplay.id, id)[0];
    setSpEp(firstEp ? firstEp.id : null);
    const firstScene = spScenesOf(novel.screenplay.id, firstEp ? firstEp.id : null)[0];
    setSpSceneId(firstScene ? firstScene.id : null);
  }

  return (
    <SidebarCollapseCtx.Provider value={() => setSidebarCollapsed(true)}>
    <div className={"m-editor-page" + (sidebarCollapsed ? " is-sidebar-collapsed" : "")}>
      <NavRail
        collapsed={sidebarCollapsed}
        onExpand={() => setSidebarCollapsed(false)}
        activeId={navActive}
        onSelect={handleNavSelect}
        onOpenSettings={onOpenSettings}
        screenplay={isScreenplay}
      />
      {isCover ? (
        <CoverStudioView novel={novel} onBack={onBack} />
      ) : isScreenplay ? (
        <React.Fragment>
          {/* 概览是整部作品的视图，不挂剧集/场次中栏；分集列表在概览正文里。 */}
          {navActive !== "overview" && (
            <ScreenplayContext
              novel={novel}
              seasonId={spSeason}
              onSelectSeason={handleSelectSeason}
              epId={spEp}
              onSelectEp={handleSelectEp}
              sceneId={spSceneId}
              onSelectScene={setSpSceneId}
              onBack={onBack}
            />
          )}
          <ScreenplayWorkspace
            novel={novel}
            section={navActive}
            seasonId={spSeason}
            onSelectSeason={handleSelectSeason}
            epId={spEp}
            onSelectEp={handleSelectEp}
            sceneId={spSceneId}
            onSelectScene={setSpSceneId}
            onGoto={handleNavSelect}
          />
          {agentOpen ? (
            rightPane === "chat" ? (
              <ChatPanel
                onClose={() => setAgentOpen(false)}
                onSwitchPane={() => setRightPane("agent")}
                onOpenUsage={(sessionId) =>
                  onOpenSettings({ section: "usage", tab: "sessions", sessionId })
                }
              />
            ) : (
              <AgentPanel
                onClose={() => setAgentOpen(false)}
                onSwitchPane={() => setRightPane("chat")}
              />
            )
          ) : (
            <button
              className="m-chat-fab"
              onClick={() => setAgentOpen(true)}
              title="打开写作助手"
            >
              <Icon name="sparkle" size={18} />
            </button>
          )}
        </React.Fragment>
      ) : isGraph ? (
        <EntityGraphView />
      ) : isMap ? (
        <MapStudioView novel={novel} onBack={onBack} />
      ) : (
        <React.Fragment>
          {isAgentSkills ? null : isCharacters ? (
            <CharacterContext
              novel={novel}
              activeId={activeCharacterId}
              onSelect={setActiveCharacterId}
              onBack={onBack}
            />
          ) : (
            <ChapterContext
              novel={novel}
              activeChapterId={activeChapterId}
              onSelectChapter={setActiveChapterId}
              onBack={onBack}
            />
          )}
          {isAgentSkills ? (
            <SkillSetup novel={novel} />
          ) : navActive === "overview" ? (
            <NovelOverview novel={novel} onSelectSection={handleNavSelect} />
          ) : isCharacters ? (
            <CharacterProfileView />
          ) : (
            <ManuscriptEditor
              novel={novel}
              chapter={chapter}
            />
          )}
          {!isAgentSkills && agentOpen && (rightPane === "chat" ? (
            <ChatPanel
              onClose={() => setAgentOpen(false)}
              onSwitchPane={() => setRightPane("agent")}
              onOpenUsage={(sessionId) =>
                onOpenSettings({ section: "usage", tab: "sessions", sessionId })
              }
            />
          ) : (
            <AgentPanel
              onClose={() => setAgentOpen(false)}
              onSwitchPane={() => setRightPane("chat")}
            />
          ))}
          {!isAgentSkills && !agentOpen && (
            <button
              className="m-chat-fab"
              onClick={() => setAgentOpen(true)}
              title="打开写作助手"
            >
              <Icon name="sparkle" size={18} />
            </button>
          )}
        </React.Fragment>
      )}
    </div>
    </SidebarCollapseCtx.Provider>
  );
}

Object.assign(window, { EditorView });
