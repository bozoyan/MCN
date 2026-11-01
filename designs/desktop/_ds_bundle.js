/* @ds-bundle: {"format":3,"namespace":"RevericDesignSystem_74ac7e","components":[],"sourceHashes":{"AgentPanel.jsx":"6aaa8e8680d2","App.jsx":"e77cefa4a239","ChapterTree.jsx":"6a9a4f4c713a","ChatPanel.jsx":"79c7abfa68c9","ContextPanel.jsx":"e97102dabec6","EditorView.jsx":"aa03f2d26cdd","Icon.jsx":"4ba0eb0cb0d8","LibraryView.jsx":"a2b4928acaa0","ManuscriptEditor.jsx":"e9ee968415a9","NavRail.jsx":"8f87bb9d3806","RightRail.jsx":"f3f19e48512c","SettingsDialog.jsx":"41e4a789b9ff","Sidebar.jsx":"2cff5ba54356","WindowFrame.jsx":"6cc81f627e80","data.js":"25101b9e7338"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.RevericDesignSystem_74ac7e = window.RevericDesignSystem_74ac7e || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// AgentPanel.jsx
try { (() => {
// AgentPanel — agent workflow trace UI. This replaces the simple chat
// panel as the default right-pane in the editor. It shows the agent's
// task list, completion state, and collapsible reasoning between steps.

const AGENT_TRACE = [{
  id: "tasks",
  kind: "section",
  icon: "check-circle",
  title: "任务列表",
  progress: "5/5",
  done: true
}, {
  id: "t1",
  kind: "task",
  icon: "plus",
  title: "新建章节",
  subtitle: "新建  星河",
  state: "已完成"
}, {
  id: "r1",
  kind: "reasoning"
}, {
  id: "t2",
  kind: "task",
  icon: "list-checks",
  title: "已更新任务列表",
  subtitle: "0 pending todos",
  badge: "5"
}, {
  id: "r2",
  kind: "reasoning"
}, {
  id: "t3",
  kind: "task",
  icon: "paper-plane",
  title: "委派任务",
  subtitle: "委派给  内容核验",
  state: "已完成"
}, {
  id: "r3",
  kind: "reasoning"
}];
function AgentTaskCard({
  item,
  expanded,
  onToggle
}) {
  const isSection = item.kind === "section";
  return /*#__PURE__*/React.createElement("div", {
    className: "m-agent__card" + (isSection ? " m-agent__card--section" : "")
  }, /*#__PURE__*/React.createElement("button", {
    type: "button",
    className: "m-agent__card-head",
    onClick: onToggle
  }, /*#__PURE__*/React.createElement("span", {
    className: "m-agent__icon" + (item.done ? " is-done" : "")
  }, /*#__PURE__*/React.createElement(Icon, {
    name: item.icon,
    size: 14
  })), /*#__PURE__*/React.createElement("span", {
    className: "m-agent__title"
  }, /*#__PURE__*/React.createElement("span", {
    className: "m-agent__title-text"
  }, item.title), item.progress && /*#__PURE__*/React.createElement("span", {
    className: "m-agent__progress"
  }, item.progress), item.state && /*#__PURE__*/React.createElement("span", {
    className: "m-pill m-pill--ok"
  }, item.state), item.badge && /*#__PURE__*/React.createElement("span", {
    className: "m-agent__badge"
  }, item.badge)), /*#__PURE__*/React.createElement(Icon, {
    name: "caret-down",
    size: 14,
    style: {
      transform: `rotate(${expanded ? 0 : -90}deg)`,
      transition: "transform 180ms ease",
      opacity: 0.5
    }
  })), item.subtitle && /*#__PURE__*/React.createElement("div", {
    className: "m-agent__subtitle"
  }, item.subtitle));
}
function ReasoningCard({
  expanded,
  onToggle
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "m-agent__card m-agent__card--reasoning"
  }, /*#__PURE__*/React.createElement("button", {
    type: "button",
    className: "m-agent__card-head",
    onClick: onToggle
  }, /*#__PURE__*/React.createElement("span", {
    className: "m-agent__icon m-agent__icon--reasoning"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "circles-three",
    size: 14
  })), /*#__PURE__*/React.createElement("span", {
    className: "m-agent__title"
  }, /*#__PURE__*/React.createElement("span", {
    className: "m-agent__title-text",
    style: {
      color: "var(--text-muted)"
    }
  }, "\u63A8\u7406\u8FC7\u7A0B")), /*#__PURE__*/React.createElement(Icon, {
    name: "caret-down",
    size: 14,
    style: {
      transform: `rotate(${expanded ? 0 : -90}deg)`,
      transition: "transform 180ms ease",
      opacity: 0.5
    }
  })), expanded && /*#__PURE__*/React.createElement("div", {
    className: "m-agent__reasoning-body"
  }, /*#__PURE__*/React.createElement("p", null, "\u6839\u636E\u5F53\u524D\u7AE0\u8282\u5927\u7EB2\u548C\u5DF2\u6709\u7684\u4EBA\u7269\u6863\u6848\uFF0CAI \u9700\u8981\u5148\u786E\u5B9A\u7B2C\u4E00\u7AE0\u7684\u53D9\u4E8B\u8D77\u70B9\u3002\u6797\u8FDC\u662F\u4E3B\u89D2\uFF0C \u4ED6\u7684\u521D\u59CB\u72B6\u6001\u662F\u300C\u5931\u4E1A \xB7 \u81EA\u6211\u6000\u7591\u300D\uFF0C\u4F46\u4E0D\u80FD\u5728\u5F00\u7BC7\u5C31\u76F4\u63A5\u544A\u767D\u8FD9\u4E2A\u72B6\u6001\uFF0C\u9700\u8981\u901A\u8FC7\u73AF\u5883 \u548C\u7EC6\u8282\u8BA9\u8BFB\u8005\u81EA\u5DF1\u611F\u53D7\u5230\u3002"), /*#__PURE__*/React.createElement("p", null, "\u9009\u62E9\u4ECE\u300C\u7B2C\u5341\u4E03\u6B21\u5237\u65B0\u62DB\u8058\u7F51\u7AD9\u300D\u5165\u624B\uFF0C\u628A\u6570\u5B57\u4F5C\u4E3A\u53D9\u4E8B\u94A9\u5B50\uFF1B\u901A\u8FC7\u5BA4\u53CB\u72B6\u6001\u5BF9\u6BD4\u7684\u4E00\u53E5\u8BDD \u5B8C\u6210\u4E3B\u89D2\u5904\u5883\u7684\u5FEB\u901F\u4EA4\u4EE3\uFF1B\u518D\u7528\u9648\u6D69\u7684\u5FAE\u4FE1\u6253\u7834\u4ED6\u7684\u53D1\u5446\uFF0C\u8FDB\u5165\u4E3B\u7EBF\uFF08VR / \u6E38\u620F\uFF09\u3002")));
}
function AgentPanel({
  onClose
}) {
  const [expanded, setExpanded] = React.useState({
    tasks: true,
    t1: true,
    r1: false,
    t2: true,
    r2: false,
    t3: true,
    r3: false
  });
  const toggle = id => setExpanded(p => ({
    ...p,
    [id]: !p[id]
  }));
  return /*#__PURE__*/React.createElement("aside", {
    className: "m-agent"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-agent__head"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-agent__head-l"
  }, /*#__PURE__*/React.createElement("span", {
    className: "m-agent__head-icon"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "sparkle",
    size: 14
  })), /*#__PURE__*/React.createElement("div", {
    className: "m-agent__head-meta"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-agent__head-title"
  }, "\u5F00\u59CB\u5199\u7B2C\u4E00\u5377 + \u7B2C\u4E00\u7AE0"), /*#__PURE__*/React.createElement("div", {
    className: "m-agent__head-sub"
  }, "\u6700\u5F3A\u5199\u624B \xB7 ", "自定义供应商", " · ", "mimo\u2011v2.5\u2011\u2026"))), /*#__PURE__*/React.createElement("div", {
    className: "m-agent__head-r"
  }, /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    title: "\u5168\u5C4F"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "arrows-out",
    size: 14
  })), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    title: "\u7F16\u8F91\u63D0\u793A"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "pencil-simple",
    size: 14
  })), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    title: "\u5173\u95ED",
    onClick: onClose
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "x",
    size: 14
  })))), /*#__PURE__*/React.createElement("div", {
    className: "m-agent__scroll"
  }, AGENT_TRACE.map(item => item.kind === "reasoning" ? /*#__PURE__*/React.createElement(ReasoningCard, {
    key: item.id,
    expanded: expanded[item.id],
    onToggle: () => toggle(item.id)
  }) : /*#__PURE__*/React.createElement(AgentTaskCard, {
    key: item.id,
    item: item,
    expanded: expanded[item.id],
    onToggle: () => toggle(item.id)
  })), /*#__PURE__*/React.createElement("div", {
    className: "m-agent__md"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-agent__md-rule"
  }), /*#__PURE__*/React.createElement("h2", {
    className: "m-agent__md-h2"
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      color: "var(--success)"
    }
  }, "\u2713"), " \u7B2C\u4E00\u7AE0\u521B\u4F5C\u5B8C\u6210"), /*#__PURE__*/React.createElement("h3", {
    className: "m-agent__md-h3"
  }, "\u5DF2\u5B8C\u6210\u5185\u5BB9"), /*#__PURE__*/React.createElement("ul", {
    className: "m-agent__md-list"
  }, /*#__PURE__*/React.createElement("li", null, "\u7B2C\u4E00\u5377\u300A\u65B0\u4E16\u754C\u7684\u94A5\u5319\u300B\u5927\u7EB2\u5DF2\u5199\u5165"), /*#__PURE__*/React.createElement("li", null, "\u7B2C 01 \u7AE0\u300C\u65B0\u7684\u5F00\u59CB\u300D\u521D\u7A3F (4,210 \u5B57)"), /*#__PURE__*/React.createElement("li", null, "\u4E3B\u89D2\u6797\u8FDC\u7684\u89D2\u8272\u6863\u6848\u9996\u7248"), /*#__PURE__*/React.createElement("li", null, "VR \u8BBE\u5B9A\u4E0E\u6E38\u620F\u300C\u661F\u6CB3\u300D\u4E16\u754C\u57FA\u7EBF")))), /*#__PURE__*/React.createElement("div", {
    className: "m-composer m-composer--rail"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-composer__field"
  }, /*#__PURE__*/React.createElement("textarea", {
    className: "m-composer__input",
    rows: 2,
    placeholder: '继续指示——例如 "开始写第二章"…',
    spellCheck: false
  })), /*#__PURE__*/React.createElement("div", {
    className: "m-composer__toolbar"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-composer__tools"
  }, /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    title: "\u9644\u4EF6"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "paperclip",
    size: 14
  })), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    title: "\u667A\u80FD\u4F53\u6280\u80FD"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "magic-wand",
    size: 14
  }))), /*#__PURE__*/React.createElement("button", {
    className: "m-btn m-btn--primary m-btn--sm"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "paper-plane",
    size: 14
  }), "\u7EE7\u7EED"))));
}
Object.assign(window, {
  AgentPanel
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "AgentPanel.jsx", error: String((e && e.message) || e) }); }

// App.jsx
try { (() => {
// Top-level app — routes between Library and Editor.

function App() {
  const [view, setView] = React.useState("library");
  const [openNovel, setOpenNovel] = React.useState(null);
  const [showSettings, setShowSettings] = React.useState(false);
  const [activeTag, setActiveTag] = React.useState("all");
  const [sbExpanded, setSbExpanded] = React.useState({
    library: true,
    agents: false,
    subagents: false,
    skills: false,
    sessions: true
  });
  const onToggleSection = k => setSbExpanded(e => ({
    ...e,
    [k]: !e[k]
  }));
  const onOpenNovel = n => {
    setOpenNovel(n);
    setView("editor");
  };
  const onBackToLibrary = () => setView("library");
  return /*#__PURE__*/React.createElement(WindowFrame, null, /*#__PURE__*/React.createElement("div", {
    className: "m-app"
  }, view === "library" ? /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Sidebar, {
    activeTag: activeTag,
    onSelectTag: setActiveTag,
    onOpenSettings: () => setShowSettings(true),
    expanded: sbExpanded,
    onToggle: onToggleSection
  }), /*#__PURE__*/React.createElement(LibraryView, {
    tag: activeTag,
    onOpenNovel: onOpenNovel
  }), /*#__PURE__*/React.createElement(RightRail, {
    onOpenNovel: onOpenNovel
  })) : /*#__PURE__*/React.createElement(EditorView, {
    novel: openNovel,
    onBack: onBackToLibrary,
    onOpenSettings: () => setShowSettings(true)
  }), showSettings && /*#__PURE__*/React.createElement(SettingsDialog, {
    onClose: () => setShowSettings(false)
  })));
}
const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(/*#__PURE__*/React.createElement(App, null));
})(); } catch (e) { __ds_ns.__errors.push({ path: "App.jsx", error: String((e && e.message) || e) }); }

// ChapterTree.jsx
try { (() => {
// Chapter tree — left rail inside the novel editor.
// Mirrors lib/desktop/widgets/sidebar/chapter_tree.dart.

function ChapterTree({
  chapters,
  activeId,
  onSelect
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "m-tree"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-tree__head"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-ui-tiny-section"
  }, "\u7AE0\u8282"), /*#__PURE__*/React.createElement("div", {
    className: "m-tree__head-actions"
  }, /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn m-icon-btn--ghost",
    title: "\u65B0\u5EFA\u7AE0\u8282"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "plus",
    size: 14
  })), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn m-icon-btn--ghost",
    title: "\u6298\u53E0\u5168\u90E8"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "list",
    size: 14
  })))), /*#__PURE__*/React.createElement("div", {
    className: "m-tree__scroll"
  }, chapters.volumes.map(vol => /*#__PURE__*/React.createElement("div", {
    key: vol.id,
    className: "m-tree__vol"
  }, /*#__PURE__*/React.createElement("button", {
    className: "m-tree__vol-head",
    type: "button"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "caret-down",
    size: 12
  }), /*#__PURE__*/React.createElement(Icon, {
    name: "books",
    size: 14
  }), /*#__PURE__*/React.createElement("span", null, vol.title)), /*#__PURE__*/React.createElement("div", {
    className: "m-tree__vol-list"
  }, vol.chapters.map(c => /*#__PURE__*/React.createElement("button", {
    key: c.id,
    type: "button",
    onClick: () => onSelect(c.id),
    className: "m-tree__chapter" + (c.id === activeId ? " is-active" : "")
  }, /*#__PURE__*/React.createElement("span", {
    className: "m-tree__chapter-num"
  }, c.number), /*#__PURE__*/React.createElement("span", {
    className: "m-tree__chapter-title"
  }, c.title), /*#__PURE__*/React.createElement("span", {
    className: `m-state m-state--${c.state}`
  }, c.state)))))), /*#__PURE__*/React.createElement("div", {
    className: "m-tree__sep"
  }), /*#__PURE__*/React.createElement("div", {
    className: "m-tree__world"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-ui-tiny-section"
  }, "\u4E16\u754C\u89C2"), chapters.world.map(w => /*#__PURE__*/React.createElement("button", {
    key: w.id,
    type: "button",
    className: "m-tree__world-row"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: w.icon,
    size: 14
  }), /*#__PURE__*/React.createElement("span", null, w.title))))));
}
Object.assign(window, {
  ChapterTree
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ChapterTree.jsx", error: String((e && e.message) || e) }); }

// ChatPanel.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
// AI chat panel — docked to the right of the manuscript editor.
// Mirrors lib/desktop/widgets/ai/chat/panel.dart.

function ChatBubble({
  role,
  content,
  reference
}) {
  if (role === "user") {
    return /*#__PURE__*/React.createElement("div", {
      className: "m-bubble m-bubble--user"
    }, /*#__PURE__*/React.createElement("div", {
      className: "m-bubble__content"
    }, content));
  }
  return /*#__PURE__*/React.createElement("div", {
    className: "m-bubble m-bubble--ai"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-bubble__avatar"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "sparkle",
    size: 12
  })), /*#__PURE__*/React.createElement("div", {
    className: "m-bubble__col"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-ui-tiny",
    style: {
      marginBottom: 4
    }
  }, "\u4E3B\u7B14 \xB7 Primary agent"), /*#__PURE__*/React.createElement("div", {
    className: "m-bubble__content"
  }, content), reference && /*#__PURE__*/React.createElement("div", {
    className: "m-bubble__ref"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "file-text",
    size: 12
  }), /*#__PURE__*/React.createElement("span", null, reference)), /*#__PURE__*/React.createElement("div", {
    className: "m-bubble__actions"
  }, /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn m-icon-btn--ghost",
    title: "\u590D\u5236"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "copy",
    size: 12
  })), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn m-icon-btn--ghost",
    title: "\u518D\u8BD5\u4E00\u6B21"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "clock-counter-clockwise",
    size: 12
  })), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn m-icon-btn--ghost",
    title: "\u63D2\u5165\u7F16\u8F91\u5668"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "article",
    size: 12
  })))));
}
function ChatPanel({
  onClose
}) {
  const D = window.REVERIC_DATA;
  const [text, setText] = React.useState("");
  return /*#__PURE__*/React.createElement("aside", {
    className: "m-chat"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-chat__head"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-chat__head-l"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "chat-circle-text",
    size: 16
  }), /*#__PURE__*/React.createElement("span", {
    className: "m-ui-semibold"
  }, "\u5199\u4F5C\u52A9\u624B")), /*#__PURE__*/React.createElement("div", {
    className: "m-chat__head-r"
  }, /*#__PURE__*/React.createElement("button", {
    className: "m-chip m-chip--brass"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "tree-structure",
    size: 12
  }), /*#__PURE__*/React.createElement("span", null, "\u60C5\u8282\u987E\u95EE"), /*#__PURE__*/React.createElement(Icon, {
    name: "caret-down",
    size: 10
  })), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    title: "\u65B0\u4F1A\u8BDD"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "plus",
    size: 14
  })), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    title: "\u5386\u53F2"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "clock-counter-clockwise",
    size: 14
  })), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    title: "\u5173\u95ED",
    onClick: onClose
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "x",
    size: 14
  })))), /*#__PURE__*/React.createElement("div", {
    className: "m-chat__context"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "article",
    size: 12
  }), /*#__PURE__*/React.createElement("span", null, "\u5F53\u524D\u4E0A\u4E0B\u6587\uFF1A\u7B2C 03 \u7AE0 \xB7 \u4E09\u8231\u5BA2 \xB7 \u5468\u6E05\u8FDC\u89C6\u89D2")), /*#__PURE__*/React.createElement("div", {
    className: "m-chat__scroll"
  }, D.chatMessages.map((m, i) => /*#__PURE__*/React.createElement(ChatBubble, _extends({
    key: i
  }, m)))), /*#__PURE__*/React.createElement("div", {
    className: "m-composer"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-composer__slash"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "magic-wand",
    size: 12
  }), /*#__PURE__*/React.createElement("span", null, "/\u6DA6\u8272"), /*#__PURE__*/React.createElement(Icon, {
    name: "x",
    size: 10
  })), /*#__PURE__*/React.createElement("div", {
    className: "m-composer__field"
  }, /*#__PURE__*/React.createElement("textarea", {
    className: "m-composer__input",
    rows: 3,
    placeholder: "\u5BF9\u5F53\u524D\u7AE0\u8282\u63D0\u95EE\uFF0C\u6216\u63CF\u8FF0\u60F3\u8981\u7684\u4FEE\u6539\u2026",
    value: text,
    onChange: e => setText(e.target.value),
    spellCheck: false
  })), /*#__PURE__*/React.createElement("div", {
    className: "m-composer__toolbar"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-composer__tools"
  }, /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    title: "\u9644\u4EF6"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "paperclip",
    size: 14
  })), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    title: "\u9009\u4E2D\u6B63\u6587"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "article",
    size: 14
  })), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    title: "\u4EBA\u7269\u6863\u6848"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "users",
    size: 14
  }))), /*#__PURE__*/React.createElement("button", {
    className: "m-btn m-btn--primary m-btn--sm"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "paper-plane",
    size: 14
  }), "\u53D1\u9001"))));
}
Object.assign(window, {
  ChatPanel
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ChatPanel.jsx", error: String((e && e.message) || e) }); }

// ContextPanel.jsx
try { (() => {
// ContextPanel — the second rail. Two variants:
//  - LibraryContext: shows novel switcher + tag list + recent sessions
//  - ChapterContext: shows novel + chapter tree

function PanelHeader({
  onBack,
  onCollapse
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "m-ctx__head"
  }, onBack && /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    onClick: onBack,
    title: "\u8FD4\u56DE"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "arrow-left",
    size: 16
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    title: "\u6298\u53E0\u4FA7\u680F",
    onClick: onCollapse
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "arrows-in",
    size: 16
  })));
}
function NovelSwitcher({
  novel
}) {
  if (!novel) {
    return /*#__PURE__*/React.createElement("button", {
      className: "m-ctx__novel m-ctx__novel--empty",
      type: "button"
    }, /*#__PURE__*/React.createElement("span", {
      className: "m-avatar m-avatar--brand",
      style: {
        width: 36,
        height: 36
      }
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "books",
      size: 16
    })), /*#__PURE__*/React.createElement("span", {
      style: {
        flex: 1,
        textAlign: "left"
      }
    }, /*#__PURE__*/React.createElement("div", {
      className: "m-ui-medium",
      style: {
        color: "var(--text-primary)"
      }
    }, "\u9009\u62E9\u4F5C\u54C1"), /*#__PURE__*/React.createElement("div", {
      className: "m-ui-tiny"
    }, "\u672A\u6253\u5F00\u4EFB\u4F55\u5C0F\u8BF4")), /*#__PURE__*/React.createElement(Icon, {
      name: "caret-down",
      size: 12
    }));
  }
  return /*#__PURE__*/React.createElement("button", {
    className: "m-ctx__novel",
    type: "button"
  }, /*#__PURE__*/React.createElement("span", {
    className: "m-avatar m-avatar--user",
    style: {
      width: 36,
      height: 36
    }
  }, novel.title.slice(0, 1)), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      textAlign: "left",
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-ui-medium",
    style: {
      color: "var(--text-primary)",
      whiteSpace: "nowrap",
      overflow: "hidden",
      textOverflow: "ellipsis"
    }
  }, novel.title)), /*#__PURE__*/React.createElement(Icon, {
    name: "caret-down",
    size: 12
  }));
}
function LibraryContext({
  activeTag,
  onSelectTag,
  onBack
}) {
  const D = window.REVERIC_DATA;
  return /*#__PURE__*/React.createElement("aside", {
    className: "m-ctx"
  }, /*#__PURE__*/React.createElement(PanelHeader, {
    onCollapse: () => {}
  }), /*#__PURE__*/React.createElement(NovelSwitcher, {
    novel: null
  }), /*#__PURE__*/React.createElement("div", {
    className: "m-ctx__sec-head"
  }, /*#__PURE__*/React.createElement("span", {
    className: "m-ctx__sec-title"
  }, "\u6807\u7B7E"), /*#__PURE__*/React.createElement("span", {
    className: "m-ctx__sec-count"
  }, D.tags.length)), /*#__PURE__*/React.createElement("div", {
    className: "m-ctx__list"
  }, D.tags.map(t => /*#__PURE__*/React.createElement("button", {
    key: t.key,
    type: "button",
    className: "m-sb-tag" + (activeTag === t.key ? " is-selected" : ""),
    onClick: () => onSelectTag(t.key)
  }, /*#__PURE__*/React.createElement("span", {
    className: "m-dot"
  }), /*#__PURE__*/React.createElement("span", {
    className: "m-sb-tag__label"
  }, t.label), /*#__PURE__*/React.createElement("span", {
    className: "m-sb-tag__count"
  }, t.count)))), /*#__PURE__*/React.createElement("div", {
    className: "m-ctx__sec-head",
    style: {
      marginTop: 12
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "m-ctx__sec-title"
  }, "\u6700\u8FD1\u4F1A\u8BDD")), /*#__PURE__*/React.createElement("div", {
    className: "m-ctx__list"
  }, D.recentSessions.map(s => /*#__PURE__*/React.createElement("button", {
    key: s.id,
    type: "button",
    className: "m-sb-session"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "chat-centered",
    size: 14,
    style: {
      opacity: 0.55,
      marginTop: 2
    }
  }), /*#__PURE__*/React.createElement("div", {
    className: "m-sb-leaf__meta"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-sb-leaf__title"
  }, s.title), /*#__PURE__*/React.createElement("div", {
    className: "m-sb-leaf__sub"
  }, s.time))))));
}
function ChapterContext({
  novel,
  activeChapterId,
  onSelectChapter,
  onBack
}) {
  const D = window.REVERIC_DATA;
  const data = D.chapters[novel.id] || D.chapters.n1;
  const totalChapters = data.volumes.reduce((sum, v) => sum + v.chapters.length, 0);
  return /*#__PURE__*/React.createElement("aside", {
    className: "m-ctx"
  }, /*#__PURE__*/React.createElement(PanelHeader, {
    onBack: onBack,
    onCollapse: () => {}
  }), /*#__PURE__*/React.createElement(NovelSwitcher, {
    novel: novel
  }), /*#__PURE__*/React.createElement("div", {
    className: "m-ctx__sec-head"
  }, /*#__PURE__*/React.createElement("span", {
    className: "m-ctx__sec-title"
  }, "\u7AE0\u8282"), /*#__PURE__*/React.createElement("span", {
    className: "m-ctx__sec-count"
  }, totalChapters), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn m-icon-btn--ghost",
    title: "\u65B0\u589E\u7AE0\u8282"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "plus",
    size: 12
  }))), /*#__PURE__*/React.createElement("div", {
    className: "m-ctx__list m-ctx__list--chapters"
  }, data.volumes.flatMap(v => v.chapters).map(c => /*#__PURE__*/React.createElement("button", {
    key: c.id,
    type: "button",
    onClick: () => onSelectChapter(c.id),
    className: "m-ctx__chapter" + (c.id === activeChapterId ? " is-active" : "")
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "file-text",
    size: 14,
    style: {
      opacity: 0.6
    }
  }), /*#__PURE__*/React.createElement("span", {
    className: "m-ctx__chapter-title"
  }, "\u7B2C", parseInt(c.number), "\u7AE0 ", c.title), /*#__PURE__*/React.createElement(Icon, {
    name: "article",
    size: 12,
    style: {
      opacity: 0.4
    }
  }))), /*#__PURE__*/React.createElement("button", {
    type: "button",
    className: "m-ctx__add"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "plus",
    size: 14
  }), /*#__PURE__*/React.createElement("span", null, "\u65B0\u589E\u7AE0\u8282"))));
}
Object.assign(window, {
  LibraryContext,
  ChapterContext
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ContextPanel.jsx", error: String((e && e.message) || e) }); }

// EditorView.jsx
try { (() => {
// Editor view — NavRail + ChapterContext + ManuscriptEditor + AgentPanel.

function EditorView({
  novel,
  onBack,
  onOpenSettings
}) {
  const D = window.REVERIC_DATA;
  const data = D.chapters[novel.id] || D.chapters.n1;
  const [activeChapterId, setActiveChapterId] = React.useState(data.activeChapterId);
  const [agentOpen, setAgentOpen] = React.useState(true);
  const [navActive, setNavActive] = React.useState("chapters");

  // Always render the demo "active chapter" content regardless of selection,
  // since this is a static recreation.
  const chapter = data.activeChapter;
  return /*#__PURE__*/React.createElement("div", {
    className: "m-editor-page"
  }, /*#__PURE__*/React.createElement(NavRail, {
    activeId: navActive,
    onSelect: setNavActive,
    onOpenSettings: onOpenSettings
  }), /*#__PURE__*/React.createElement(ChapterContext, {
    novel: novel,
    activeChapterId: activeChapterId,
    onSelectChapter: setActiveChapterId,
    onBack: onBack
  }), /*#__PURE__*/React.createElement(ManuscriptEditor, {
    novel: novel,
    chapter: chapter
  }), agentOpen && /*#__PURE__*/React.createElement(AgentPanel, {
    onClose: () => setAgentOpen(false)
  }), !agentOpen && /*#__PURE__*/React.createElement("button", {
    className: "m-chat-fab",
    onClick: () => setAgentOpen(true),
    title: "\u6253\u5F00\u5199\u4F5C\u52A9\u624B"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "sparkle",
    size: 18
  })));
}
Object.assign(window, {
  EditorView
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "EditorView.jsx", error: String((e && e.message) || e) }); }

// Icon.jsx
try { (() => {
// Phosphor icon — fetches the SVG once and inlines it. Phosphor SVGs use
// `currentColor` on the stroke, so colors just work through normal CSS.
const __ICON_CACHE = new Map(); // name -> Promise<string>
function loadIconSvg(name) {
  if (!__ICON_CACHE.has(name)) {
    __ICON_CACHE.set(name, fetch(`assets/icons/phosphor/${name}.svg`).then(r => r.text()));
  }
  return __ICON_CACHE.get(name);
}
function Icon({
  name,
  size = 16,
  color,
  style,
  className
}) {
  const px = typeof size === "number" ? `${size}px` : size;
  const [svg, setSvg] = React.useState("");
  React.useEffect(() => {
    let active = true;
    loadIconSvg(name).then(s => {
      if (!active) return;
      // Force the SVG to fill the span and inherit currentColor.
      const sized = s.replace(/<svg([^>]*?)width="[^"]*"/, "<svg$1").replace(/<svg([^>]*?)height="[^"]*"/, "<svg$1").replace(/<svg/, '<svg width="100%" height="100%" preserveAspectRatio="xMidYMid meet"');
      setSvg(sized);
    });
    return () => {
      active = false;
    };
  }, [name]);
  return /*#__PURE__*/React.createElement("span", {
    className: "m-icon " + (className || ""),
    style: {
      display: "inline-flex",
      alignItems: "center",
      justifyContent: "center",
      flex: "none",
      width: px,
      height: px,
      color: color || "currentColor",
      verticalAlign: "middle",
      lineHeight: 0,
      ...style
    },
    "aria-hidden": "true",
    dangerouslySetInnerHTML: {
      __html: svg
    }
  });
}

// Reveric brand mark — rendered inline (no network) so the chrome titlebar
// can show it at any size.
function Mark({
  size = 18,
  style
}) {
  return /*#__PURE__*/React.createElement("svg", {
    width: size,
    height: size,
    viewBox: "0 0 1024 1024",
    fill: "none",
    xmlns: "http://www.w3.org/2000/svg",
    style: style,
    "aria-hidden": "true"
  }, /*#__PURE__*/React.createElement("g", {
    transform: "translate(72.05 72.05) scale(.7)"
  }, /*#__PURE__*/React.createElement("path", {
    d: "M334 620C334 512 436 465 579 423C749 372 882 326 923 248V429C923 510 836 540 718 577C550 633 338 722 338 811C334 803 334 792 334 781Z",
    fill: "#283B5E"
  }), /*#__PURE__*/React.createElement("path", {
    d: "M608 637C608 708 672 744 758 781C845 818 892 843 913 918C924 953 926 985 921 1009C862 949 744 935 626 925C507 915 415 891 415 816C415 752 490 691 608 637Z",
    fill: "#8797D2"
  })));
}
Object.assign(window, {
  Icon,
  Mark
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "Icon.jsx", error: String((e && e.message) || e) }); }

// LibraryView.jsx
try { (() => {
// Novel cards + library grid.

const COVER_BG = {
  ink: {
    bg: "linear-gradient(160deg, #3E524C 0%, #2D3A36 55%, #1C2623 100%)",
    motif: "M40,220 Q120,140 200,180 T380,160"
  },
  mountains: {
    bg: "linear-gradient(180deg, #CDD6DB 0%, #7E8D99 60%, #3A4551 100%)",
    motif: "M20,260 L120,140 L180,200 L260,100 L380,260 Z"
  },
  stars: {
    bg: "linear-gradient(180deg, #2B2834 0%, #4B4558 100%)",
    motif: null
  },
  tree: {
    bg: "linear-gradient(160deg, #D3E0DA 0%, #6F9D8D 60%, #2E6656 100%)",
    motif: "M200,260 L200,80 M200,140 L150,80 M200,140 L250,80 M200,200 L170,160 M200,200 L230,160"
  }
};
function NovelCover({
  kind,
  title
}) {
  const cov = COVER_BG[kind] || COVER_BG.ink;
  return /*#__PURE__*/React.createElement("div", {
    className: "m-cover",
    style: {
      background: cov.bg
    }
  }, kind === "stars" ? /*#__PURE__*/React.createElement("svg", {
    viewBox: "0 0 400 280",
    className: "m-cover__svg"
  }, Array.from({
    length: 22
  }).map((_, i) => /*#__PURE__*/React.createElement("circle", {
    key: i,
    cx: 20 + i * 71 % 380,
    cy: 20 + i * 53 % 220,
    r: Math.random() > 0.7 ? 1.6 : 0.9,
    fill: "#DCE6E1",
    opacity: 0.4 + Math.random() * 0.4
  })), /*#__PURE__*/React.createElement("path", {
    d: "M30,260 Q140,220 200,210 T380,230",
    stroke: "#8FB8A8",
    strokeWidth: "0.6",
    fill: "none",
    opacity: "0.5"
  })) : cov.motif && /*#__PURE__*/React.createElement("svg", {
    viewBox: "0 0 400 280",
    className: "m-cover__svg"
  }, /*#__PURE__*/React.createElement("path", {
    d: cov.motif,
    stroke: kind === "tree" ? "#1C2623" : "#F3F7F5",
    strokeWidth: kind === "tree" ? 2.2 : 1.4,
    fill: kind === "mountains" ? "rgba(28,38,35,0.35)" : "none",
    opacity: kind === "mountains" ? 1 : 0.55,
    strokeLinecap: "round",
    strokeLinejoin: "round"
  })), /*#__PURE__*/React.createElement("div", {
    className: "m-cover__title"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-cover__title-en"
  }, title)));
}
function NovelCard({
  novel,
  onOpen
}) {
  return /*#__PURE__*/React.createElement("article", {
    className: "m-novel-card",
    onClick: () => onOpen(novel),
    role: "button",
    tabIndex: 0
  }, /*#__PURE__*/React.createElement(NovelCover, {
    kind: novel.cover,
    title: novel.title
  }), /*#__PURE__*/React.createElement("div", {
    className: "m-novel-card__body"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-novel-card__head"
  }, /*#__PURE__*/React.createElement("h3", {
    className: "m-novel-card__title"
  }, novel.title), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn m-icon-btn--ghost",
    onClick: e => e.stopPropagation(),
    title: "\u66F4\u591A"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "dots-three",
    size: 16
  }))), /*#__PURE__*/React.createElement("div", {
    className: "m-novel-card__sub"
  }, novel.subtitle), /*#__PURE__*/React.createElement("p", {
    className: "m-novel-card__desc"
  }, novel.description), /*#__PURE__*/React.createElement("div", {
    className: "m-novel-card__tags"
  }, novel.tags.map(t => /*#__PURE__*/React.createElement("span", {
    key: t,
    className: "m-tag"
  }, t))), /*#__PURE__*/React.createElement("div", {
    className: "m-novel-card__foot"
  }, /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement(Icon, {
    name: "article",
    size: 12
  }), novel.chapters, " \u7AE0"), /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement(Icon, {
    name: "text-t",
    size: 12
  }), novel.words.toLocaleString(), " \u5B57"), /*#__PURE__*/React.createElement("span", {
    className: "m-novel-card__foot-spacer"
  }), /*#__PURE__*/React.createElement("span", {
    className: "m-novel-card__updated"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "clock",
    size: 12
  }), novel.updated))));
}
function LibraryView({
  tag,
  onOpenNovel
}) {
  const D = window.REVERIC_DATA;
  const tagLabel = D.tags.find(t => t.key === tag)?.label || "全部";
  const novels = tag === "all" ? D.novels : D.novels.filter(n => n.tags.some(nt => nt === tag || nt.toLowerCase() === tag));
  return /*#__PURE__*/React.createElement("div", {
    className: "m-main"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-main__head"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-main__head-l"
  }, /*#__PURE__*/React.createElement("h1", {
    className: "m-main__title"
  }, "\u56FE\u4E66\u9986"), /*#__PURE__*/React.createElement("span", {
    className: "m-main__sub"
  }, tagLabel, " \xB7 ", novels.length, " \u90E8\u4F5C\u54C1")), /*#__PURE__*/React.createElement("div", {
    className: "m-main__head-r"
  }, /*#__PURE__*/React.createElement("button", {
    className: "m-btn m-btn--secondary m-btn--sm"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "faders",
    size: 14
  }), "\u6392\u5E8F"), /*#__PURE__*/React.createElement("button", {
    className: "m-btn m-btn--primary m-btn--sm"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "plus",
    size: 14
  }), "\u65B0\u5EFA\u5C0F\u8BF4"))), /*#__PURE__*/React.createElement("div", {
    className: "m-novel-grid"
  }, novels.map(n => /*#__PURE__*/React.createElement(NovelCard, {
    key: n.id,
    novel: n,
    onOpen: onOpenNovel
  })), /*#__PURE__*/React.createElement("article", {
    className: "m-novel-card m-novel-card--empty",
    onClick: () => {}
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-novel-card__empty-inner"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "plus",
    size: 22
  }), /*#__PURE__*/React.createElement("div", {
    className: "m-novel-card__empty-title"
  }, "\u65B0\u5EFA\u5C0F\u8BF4"), /*#__PURE__*/React.createElement("div", {
    className: "m-novel-card__empty-sub"
  }, "\u4ECE\u7A7A\u767D\u5377\u5B97\u5F00\u59CB\uFF0C\u6216\u4ECE\u5927\u7EB2\u3001\u4EBA\u7269\u3001\u4E16\u754C\u89C2\u5148\u884C\u642D\u5EFA\u3002")))));
}
Object.assign(window, {
  NovelCard,
  NovelCover,
  LibraryView
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "LibraryView.jsx", error: String((e && e.message) || e) }); }

// ManuscriptEditor.jsx
try { (() => {
// Manuscript editor — top breadcrumb toolbar, chapter meta, 章节大纲
// summary card, body, status bar. Matches the actual Reveric editor view.

function EditorToolbar({
  novelTitle,
  chapter,
  onSave
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "m-editor__topbar"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-editor__crumbs"
  }, /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn m-icon-btn--ghost",
    style: {
      marginRight: 6
    },
    title: "\u6298\u53E0\u7AE0\u8282\u4FA7\u680F"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "caret-left",
    size: 14
  })), /*#__PURE__*/React.createElement("span", {
    className: "m-crumb"
  }, novelTitle), /*#__PURE__*/React.createElement(Icon, {
    name: "caret-right",
    size: 12,
    style: {
      opacity: 0.4
    }
  }), /*#__PURE__*/React.createElement("span", {
    className: "m-crumb"
  }, "\u7AE0\u8282"), /*#__PURE__*/React.createElement(Icon, {
    name: "caret-right",
    size: 12,
    style: {
      opacity: 0.4
    }
  }), /*#__PURE__*/React.createElement("span", {
    className: "m-crumb m-crumb--active"
  }, "\u7B2C", parseInt(chapter.number), "\u7AE0 \xB7 ", chapter.title)), /*#__PURE__*/React.createElement("div", {
    className: "m-editor__topbar-r"
  }, /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    title: "\u5386\u53F2"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "clock-counter-clockwise",
    size: 16
  })), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    title: "\u7AE0\u8282\u8BBE\u7F6E"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "gear-six",
    size: 16
  })), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    title: "\u9884\u89C8"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "eye",
    size: 16
  })), /*#__PURE__*/React.createElement("button", {
    className: "m-btn m-btn--primary m-btn--sm",
    onClick: onSave
  }, "\u4FDD\u5B58")));
}
function ChapterStatePill({
  state
}) {
  return /*#__PURE__*/React.createElement("button", {
    type: "button",
    className: `m-state-pill m-state-pill--${state}`
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "pencil-simple",
    size: 11
  }), /*#__PURE__*/React.createElement("span", null, state));
}
function OutlineCard({
  outline,
  expanded,
  onToggle
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "m-outline-card"
  }, /*#__PURE__*/React.createElement("button", {
    type: "button",
    className: "m-outline-card__head",
    onClick: onToggle
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "trend-up",
    size: 14
  }), /*#__PURE__*/React.createElement("span", {
    className: "m-outline-card__title"
  }, "\u7AE0\u8282\u5927\u7EB2"), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn m-icon-btn--ghost",
    title: "\u5C55\u5F00"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "arrows-out",
    size: 12
  })), /*#__PURE__*/React.createElement(Icon, {
    name: "caret-down",
    size: 14,
    style: {
      transform: `rotate(${expanded ? 0 : -90}deg)`,
      transition: "transform 180ms ease",
      opacity: 0.6
    }
  })), expanded && outline && /*#__PURE__*/React.createElement("div", {
    className: "m-outline-card__body"
  }, outline));
}
function ManuscriptEditor({
  novel,
  chapter
}) {
  const [outlineOpen, setOutlineOpen] = React.useState(false);
  const wordCount = (chapter.body || []).join("").length;
  const minutes = Math.max(1, Math.round(wordCount / 200));
  return /*#__PURE__*/React.createElement("div", {
    className: "m-editor"
  }, /*#__PURE__*/React.createElement(EditorToolbar, {
    novelTitle: novel.title,
    chapter: chapter
  }), /*#__PURE__*/React.createElement("div", {
    className: "m-editor__scroll"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-editor__inner"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-editor__meta"
  }, /*#__PURE__*/React.createElement("span", {
    className: "m-chapter-num"
  }, "\u7B2C", parseInt(chapter.number), "\u7AE0"), /*#__PURE__*/React.createElement(ChapterStatePill, {
    state: "\u8349\u7A3F"
  })), /*#__PURE__*/React.createElement("h1", {
    className: "m-editor__title",
    contentEditable: "true",
    suppressContentEditableWarning: true
  }, chapter.title), /*#__PURE__*/React.createElement(OutlineCard, {
    outline: chapter.summary,
    expanded: outlineOpen,
    onToggle: () => setOutlineOpen(o => !o)
  }), /*#__PURE__*/React.createElement("div", {
    className: "m-editor__body",
    contentEditable: "true",
    suppressContentEditableWarning: true
  }, (chapter.body || []).map((p, i) => /*#__PURE__*/React.createElement("p", {
    key: i
  }, p))))), /*#__PURE__*/React.createElement("div", {
    className: "m-editor__statusbar"
  }, /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement(Icon, {
    name: "floppy-disk",
    size: 12
  }), " \u5DF2\u542F\u7528\u81EA\u52A8\u4FDD\u5B58"), /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement(Icon, {
    name: "text-t",
    size: 12
  }), " \u5B57\u6570 ", (wordCount / 1000).toFixed(1), "\u5343"), /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement(Icon, {
    name: "clock",
    size: 12
  }), " \u9884\u8BA1\u9605\u8BFB ", minutes, " \u5206\u949F"), /*#__PURE__*/React.createElement("span", {
    className: "m-editor__statusbar-spacer"
  }), /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement(Icon, {
    name: "article",
    size: 12
  }), " \u683C\u5F0F\u5316"), /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement(Icon, {
    name: "clock-counter-clockwise",
    size: 12
  }), " \u5386\u53F2")));
}
Object.assign(window, {
  ManuscriptEditor
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ManuscriptEditor.jsx", error: String((e && e.message) || e) }); }

// NavRail.jsx
try { (() => {
// NavRail — leftmost icon + label nav.
// Sections: 系统 · 创作 · 世界观 · 资料 · AI. Bottom: brand row "幻界".

const NAV_SECTIONS = [{
  label: "系统",
  items: [{
    id: "overview",
    icon: "squares-four",
    label: "概览"
  }, {
    id: "graph",
    icon: "tree-structure",
    label: "实体关系图"
  }, {
    id: "search",
    icon: "magnifying-glass",
    label: "搜索"
  }]
}, {
  label: "创作",
  items: [{
    id: "chapters",
    icon: "book-open",
    label: "章节"
  }, {
    id: "outline",
    icon: "list",
    label: "大纲"
  }, {
    id: "characters",
    icon: "users",
    label: "人物"
  }, {
    id: "foreshadowing",
    icon: "flag",
    label: "伏笔"
  }]
}, {
  label: "世界观",
  items: [{
    id: "world",
    icon: "globe",
    label: "设定"
  }, {
    id: "map",
    icon: "map-trifold",
    label: "地图"
  }, {
    id: "factions",
    icon: "shield",
    label: "势力"
  }, {
    id: "creatures",
    icon: "tree-evergreen",
    label: "生物"
  }, {
    id: "items",
    icon: "diamond",
    label: "物品"
  }, {
    id: "skills",
    icon: "sparkle",
    label: "技能"
  }]
}, {
  label: "资料",
  items: [{
    id: "materials",
    icon: "folder",
    label: "素材"
  }]
}, {
  label: "AI",
  items: [{
    id: "chat",
    icon: "chat-centered",
    label: "聊天"
  }, {
    id: "rules",
    icon: "shield",
    label: "智能体规则"
  }, {
    id: "council",
    icon: "users-three",
    label: "圆桌会议"
  }, {
    id: "monologue",
    icon: "user",
    label: "独白"
  }, {
    id: "theater",
    icon: "mask-happy",
    label: "小剧场"
  }, {
    id: "roleplay",
    icon: "chat-circle-text",
    label: "角色扮演"
  }]
}];
function NavRail({
  activeId,
  onSelect,
  onOpenSettings
}) {
  return /*#__PURE__*/React.createElement("nav", {
    className: "m-navrail"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-navrail__scroll"
  }, NAV_SECTIONS.map(sec => /*#__PURE__*/React.createElement("div", {
    key: sec.label,
    className: "m-navrail__sec"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-navrail__sec-label"
  }, sec.label), /*#__PURE__*/React.createElement("div", {
    className: "m-navrail__sec-items"
  }, sec.items.map(it => /*#__PURE__*/React.createElement("button", {
    key: it.id,
    type: "button",
    className: "m-navrail__row" + (activeId === it.id ? " is-active" : ""),
    onClick: () => onSelect(it.id)
  }, /*#__PURE__*/React.createElement(Icon, {
    name: it.icon,
    size: 16
  }), /*#__PURE__*/React.createElement("span", null, it.label))))))), /*#__PURE__*/React.createElement("button", {
    type: "button",
    className: "m-navrail__brand",
    onClick: onOpenSettings,
    title: "\u8BBE\u7F6E \xB7 \u955C\u754C\u5199\u4F5C"
  }, /*#__PURE__*/React.createElement("span", {
    className: "m-avatar m-avatar--user",
    style: {
      width: 22,
      height: 22
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "user",
    size: 12
  })), /*#__PURE__*/React.createElement("span", {
    className: "m-navrail__brand-name"
  }, "\u955C\u754C\u5199\u4F5C")));
}
Object.assign(window, {
  NavRail
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "NavRail.jsx", error: String((e && e.message) || e) }); }

// RightRail.jsx
try { (() => {
// Right rail — global AI quick‑chat composer.
// Mirrors lib/desktop/widgets/home_right_rail.dart and the global floating chat.

function RightRail({
  onOpenNovel
}) {
  const D = window.REVERIC_DATA;
  return /*#__PURE__*/React.createElement("aside", {
    className: "m-right"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-right__head"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "sparkle",
    size: 14
  }), /*#__PURE__*/React.createElement("span", {
    className: "m-ui-semibold"
  }, "\u5199\u4F5C\u52A9\u624B"), /*#__PURE__*/React.createElement("span", {
    className: "m-ui-tiny",
    style: {
      marginLeft: "auto",
      opacity: 0.6
    }
  }, "Claude 3.5 Sonnet")), /*#__PURE__*/React.createElement("div", {
    className: "m-right__body"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-right__hint"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "lightbulb",
    size: 14,
    style: {
      marginTop: 2
    }
  }), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    className: "m-ui-medium",
    style: {
      marginBottom: 4
    }
  }, "\u9009\u62E9\u4E00\u90E8\u4F5C\u54C1\u5F00\u59CB"), /*#__PURE__*/React.createElement("div", {
    className: "m-ui-small"
  }, "\u8FDB\u5165\u5C0F\u8BF4\u540E\uFF0C\u53EF\u4EE5\u8BA9 AI \u57FA\u4E8E\u5DF2\u6709\u4E16\u754C\u89C2\u3001\u4EBA\u7269\u6863\u6848\u4E0E\u524D\u6587\u8FDB\u884C\u6269\u5199\u3001\u6DA6\u8272\u3001\u4F0F\u7B14\u68C0\u67E5\u3002"))), /*#__PURE__*/React.createElement("div", {
    className: "m-right__section"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-ui-tiny-section"
  }, "\u6700\u8FD1\u4F1A\u8BDD"), /*#__PURE__*/React.createElement("div", {
    className: "m-right__sessions"
  }, D.recentSessions.map((s, i) => /*#__PURE__*/React.createElement("button", {
    key: s.id,
    type: "button",
    className: "m-right__session"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "chat-centered",
    size: 14,
    style: {
      opacity: 0.55
    }
  }), /*#__PURE__*/React.createElement("div", {
    className: "m-right__session-meta"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-ui-medium",
    style: {
      color: "var(--text-primary)"
    }
  }, s.title), /*#__PURE__*/React.createElement("div", {
    className: "m-ui-tiny"
  }, s.time)))))), /*#__PURE__*/React.createElement("div", {
    className: "m-right__section"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-ui-tiny-section"
  }, "\u5728\u7528\u667A\u80FD\u4F53"), /*#__PURE__*/React.createElement("div", {
    className: "m-right__agents"
  }, D.subagents.map(a => /*#__PURE__*/React.createElement("div", {
    key: a.id,
    className: "m-chip"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: a.icon,
    size: 12
  }), /*#__PURE__*/React.createElement("span", null, a.name)))))), /*#__PURE__*/React.createElement("div", {
    className: "m-composer m-composer--rail"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-composer__field"
  }, /*#__PURE__*/React.createElement("textarea", {
    className: "m-composer__input",
    rows: 3,
    placeholder: "\u8BE2\u95EE\u4E00\u4E2A\u7AE0\u8282\u6784\u601D\uFF0C\u6216\u7C98\u8D34\u7247\u6BB5\u8BF7\u6C42\u6DA6\u8272\u2026",
    spellCheck: false
  })), /*#__PURE__*/React.createElement("div", {
    className: "m-composer__toolbar"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-composer__tools"
  }, /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    title: "\u9644\u4EF6"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "paperclip",
    size: 14
  })), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    title: "\u667A\u80FD\u4F53\u6280\u80FD"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "magic-wand",
    size: 14
  })), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    title: "\u5386\u53F2"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "clock-counter-clockwise",
    size: 14
  }))), /*#__PURE__*/React.createElement("button", {
    className: "m-btn m-btn--primary m-btn--sm"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "paper-plane",
    size: 14
  }), "\u53D1\u9001"))));
}
Object.assign(window, {
  RightRail
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "RightRail.jsx", error: String((e && e.message) || e) }); }

// SettingsDialog.jsx
try { (() => {
// Settings dialog — modal overlay shown from sidebar gear icon.

function SettingsDialog({
  onClose
}) {
  const [section, setSection] = React.useState("appearance");
  return /*#__PURE__*/React.createElement("div", {
    className: "m-dialog-scrim",
    onClick: onClose
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-dialog m-dialog--settings",
    onClick: e => e.stopPropagation(),
    role: "dialog",
    "aria-modal": "true"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-dialog__head"
  }, /*#__PURE__*/React.createElement("h2", {
    className: "m-heading"
  }, "\u8BBE\u7F6E"), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    onClick: onClose,
    title: "\u5173\u95ED"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "x",
    size: 16
  }))), /*#__PURE__*/React.createElement("div", {
    className: "m-dialog__body"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-settings-nav"
  }, [{
    id: "appearance",
    icon: "palette",
    label: "外观"
  }, {
    id: "providers",
    icon: "brain",
    label: "AI 提供商"
  }, {
    id: "agents",
    icon: "robot",
    label: "智能体"
  }, {
    id: "shortcuts",
    icon: "cursor-click",
    label: "快捷键"
  }, {
    id: "data",
    icon: "floppy-disk",
    label: "数据"
  }, {
    id: "about",
    icon: "info",
    label: "关于"
  }].map(s => /*#__PURE__*/React.createElement("button", {
    key: s.id,
    type: "button",
    className: "m-settings-nav__row" + (section === s.id ? " is-selected" : ""),
    onClick: () => setSection(s.id)
  }, /*#__PURE__*/React.createElement(Icon, {
    name: s.icon,
    size: 14
  }), /*#__PURE__*/React.createElement("span", null, s.label)))), /*#__PURE__*/React.createElement("div", {
    className: "m-settings-panel"
  }, section === "appearance" && /*#__PURE__*/React.createElement(AppearancePanel, null), section === "providers" && /*#__PURE__*/React.createElement(ProvidersPanel, null), section === "agents" && /*#__PURE__*/React.createElement(PlaceholderPanel, {
    name: "\u667A\u80FD\u4F53"
  }), section === "shortcuts" && /*#__PURE__*/React.createElement(PlaceholderPanel, {
    name: "\u5FEB\u6377\u952E"
  }), section === "data" && /*#__PURE__*/React.createElement(PlaceholderPanel, {
    name: "\u6570\u636E"
  }), section === "about" && /*#__PURE__*/React.createElement(AboutPanel, null)))));
}
function AppearancePanel() {
  const themes = [{
    key: "reveric",
    label: "Reveric",
    swatch: "#C4956A",
    desc: "默认 · 暖色羊皮纸"
  }, {
    key: "cartographer",
    label: "Cartographer",
    swatch: "#8B7355",
    desc: "墨色羊皮纸 · 偏深"
  }, {
    key: "ink-wash",
    label: "水墨",
    swatch: "#A63F35",
    desc: "宣纸 · 朱砂红"
  }, {
    key: "ember",
    label: "炉火",
    swatch: "#F59E0B",
    desc: "暖琥珀"
  }, {
    key: "classic",
    label: "Classic",
    swatch: "#000000",
    desc: "黑白极简"
  }, {
    key: "verdant",
    label: "Verdant",
    swatch: "#4ADE80",
    desc: "晨园绿意"
  }];
  const [active, setActive] = React.useState("reveric");
  return /*#__PURE__*/React.createElement("div", {
    className: "m-form"
  }, /*#__PURE__*/React.createElement("h3", {
    className: "m-heading",
    style: {
      fontSize: 18
    }
  }, "\u4E3B\u9898\u8272\u677F"), /*#__PURE__*/React.createElement("p", {
    className: "m-body-small"
  }, "\u5341\u79CD\u8272\u677F\u4E0E\u5404\u81EA\u7684\u6D45\u8272 / \u6DF1\u8272\u53D8\u4F53\u3002\u6240\u6709\u8272\u677F\u5171\u4EAB\u76F8\u540C\u7684\u8BED\u4E49\u4EE4\u724C\u2014\u2014\u9009\u62E9\u4F1A\u540C\u6B65\u5F71\u54CD\u6BB5\u843D\u4E2D\u7684\u5F15\u7528\u3001\u5BF9\u8BDD\u6C14\u6CE1\u8FB9\u6846\u3001\u9009\u4E2D\u6001\u3002"), /*#__PURE__*/React.createElement("div", {
    className: "m-theme-grid"
  }, themes.map(t => /*#__PURE__*/React.createElement("button", {
    key: t.key,
    type: "button",
    className: "m-theme-card" + (active === t.key ? " is-active" : ""),
    onClick: () => setActive(t.key)
  }, /*#__PURE__*/React.createElement("span", {
    className: "m-theme-card__swatch",
    style: {
      background: t.swatch
    }
  }), /*#__PURE__*/React.createElement("div", {
    className: "m-theme-card__meta"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-ui-medium"
  }, t.label), /*#__PURE__*/React.createElement("div", {
    className: "m-ui-tiny"
  }, t.desc)), active === t.key && /*#__PURE__*/React.createElement(Icon, {
    name: "check-circle",
    size: 14
  })))), /*#__PURE__*/React.createElement("h3", {
    className: "m-heading",
    style: {
      fontSize: 18,
      marginTop: 24
    }
  }, "\u660E\u6697"), /*#__PURE__*/React.createElement("div", {
    className: "m-segmented"
  }, [{
    v: "light",
    icon: "sun-dim",
    label: "浅色"
  }, {
    v: "auto",
    icon: "circle",
    label: "跟随系统"
  }, {
    v: "dark",
    icon: "moon-stars",
    label: "深色"
  }].map((m, i) => /*#__PURE__*/React.createElement("button", {
    key: m.v,
    type: "button",
    className: "m-segmented__item" + (i === 0 ? " is-active" : "")
  }, /*#__PURE__*/React.createElement(Icon, {
    name: m.icon,
    size: 14
  }), /*#__PURE__*/React.createElement("span", null, m.label)))), /*#__PURE__*/React.createElement("h3", {
    className: "m-heading",
    style: {
      fontSize: 18,
      marginTop: 24
    }
  }, "\u5E94\u7528\u80CC\u666F"), /*#__PURE__*/React.createElement("div", {
    className: "m-bg-grid"
  }, ["distant_mountains", "plum_blossom", "solitary_boat", "withered_tree"].map((k, i) => /*#__PURE__*/React.createElement("button", {
    key: k,
    type: "button",
    className: "m-bg-tile" + (i === 0 ? " is-active" : "")
  }, /*#__PURE__*/React.createElement("img", {
    src: `assets/images/background/${k}.webp`,
    alt: k
  })))));
}
function ProvidersPanel() {
  const providers = [{
    name: "Anthropic",
    model: "Claude 3.5 Sonnet",
    state: "已连接",
    state_kind: "ok"
  }, {
    name: "OpenAI",
    model: "GPT‑4o",
    state: "已连接",
    state_kind: "ok"
  }, {
    name: "Google",
    model: "Gemini 1.5 Pro",
    state: "未配置密钥",
    state_kind: "warn"
  }, {
    name: "Local · Ollama",
    model: "Qwen2.5 32B",
    state: "已连接",
    state_kind: "ok"
  }];
  return /*#__PURE__*/React.createElement("div", {
    className: "m-form"
  }, /*#__PURE__*/React.createElement("h3", {
    className: "m-heading",
    style: {
      fontSize: 18
    }
  }, "AI \u63D0\u4F9B\u5546"), /*#__PURE__*/React.createElement("p", {
    className: "m-body-small"
  }, "\u4E3B\u7B14\u667A\u80FD\u4F53\u4F1A\u4ECE\u4E0B\u5217\u5DF2\u8FDE\u63A5\u7684\u63D0\u4F9B\u5546\u4E2D\u6309\u4F60\u8BBE\u5B9A\u7684\u4F18\u5148\u7EA7\u9009\u62E9\u6A21\u578B\u3002"), /*#__PURE__*/React.createElement("div", {
    className: "m-provider-list"
  }, providers.map(p => /*#__PURE__*/React.createElement("div", {
    key: p.name,
    className: "m-provider-row"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-provider-row__l"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-avatar m-avatar--brand"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "brain",
    size: 16
  })), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    className: "m-ui-medium",
    style: {
      color: "var(--text-primary)"
    }
  }, p.name), /*#__PURE__*/React.createElement("div", {
    className: "m-ui-tiny"
  }, p.model))), /*#__PURE__*/React.createElement("div", {
    className: "m-provider-row__r"
  }, /*#__PURE__*/React.createElement("span", {
    className: "m-pill m-pill--" + p.state_kind
  }, p.state), /*#__PURE__*/React.createElement("button", {
    className: "m-btn m-btn--secondary m-btn--sm"
  }, "\u914D\u7F6E"))))), /*#__PURE__*/React.createElement("button", {
    className: "m-btn m-btn--secondary",
    style: {
      marginTop: 16
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "plus",
    size: 14
  }), "\u6DFB\u52A0\u81EA\u5B9A\u4E49\u63D0\u4F9B\u5546"));
}
function PlaceholderPanel({
  name
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "m-form"
  }, /*#__PURE__*/React.createElement("h3", {
    className: "m-heading",
    style: {
      fontSize: 18
    }
  }, name), /*#__PURE__*/React.createElement("p", {
    className: "m-body-small"
  }, "\u672C\u8BBE\u8BA1\u7CFB\u7EDF\u6062\u590D\u7684\u8BBE\u7F6E\u9879\u4EC5\u5C55\u793A\u5916\u89C2\u4E0E\u63D0\u4F9B\u5546\u90E8\u5206\uFF0C\u5176\u4ED6\u9762\u677F\u53EF\u53C2\u8003 Reveric \u6E90\u7801 lib/desktop/pages/settings/ \u8FDB\u4E00\u6B65\u5B9E\u73B0\u3002"));
}
function AboutPanel() {
  return /*#__PURE__*/React.createElement("div", {
    className: "m-form",
    style: {
      alignItems: "center",
      textAlign: "center"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 12,
      marginBottom: 12
    }
  }, /*#__PURE__*/React.createElement(Mark, {
    size: 64
  })), /*#__PURE__*/React.createElement("h3", {
    className: "m-heading"
  }, "Reveric"), /*#__PURE__*/React.createElement("p", {
    className: "m-body-small",
    style: {
      maxWidth: 360
    }
  }, "AI \u8F85\u52A9\u5C0F\u8BF4\u521B\u4F5C\u8F6F\u4EF6\u3002\u8BA9 AI \u627F\u62C5\u53EF\u81EA\u52A8\u5316\u7684\u751F\u6210\u4E0E\u6DA6\u8272\u5DE5\u4F5C\uFF0C\u8BA9\u4F5C\u8005\u4E13\u6CE8\u4E8E\u521B\u610F\u51B3\u7B56\u4E0E\u8D28\u91CF\u628A\u63A7\u3002"), /*#__PURE__*/React.createElement("div", {
    className: "m-ui-tiny",
    style: {
      marginTop: 12
    }
  }, "\u7248\u672C 0.4.2 \xB7 build 1126"));
}
Object.assign(window, {
  SettingsDialog
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "SettingsDialog.jsx", error: String((e && e.message) || e) }); }

// Sidebar.jsx
try { (() => {
// Left sidebar — search + collapsible Works/AI/Settings sections.
// Mirrors lib/desktop/pages/home.dart _buildSidebar()

function SectionGroupHeader({
  children
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "m-sb-group-header"
  }, children);
}
function CollapsibleHeader({
  icon,
  title,
  expanded,
  onToggle,
  trailing
}) {
  return /*#__PURE__*/React.createElement("button", {
    className: "m-sb-row m-sb-row--header",
    onClick: onToggle,
    type: "button"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: icon,
    size: 16
  }), /*#__PURE__*/React.createElement("span", {
    className: "m-sb-row__title"
  }, title), /*#__PURE__*/React.createElement("span", {
    className: "m-sb-row__spacer"
  }), trailing, /*#__PURE__*/React.createElement(Icon, {
    name: "caret-right",
    size: 14,
    style: {
      transform: `rotate(${expanded ? 90 : 0}deg)`,
      transition: "transform 180ms ease",
      opacity: 0.6
    }
  }));
}
function LeafItem({
  icon,
  title,
  onClick,
  trailing
}) {
  return /*#__PURE__*/React.createElement("button", {
    className: "m-sb-row m-sb-row--header",
    onClick: onClick,
    type: "button"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: icon,
    size: 16
  }), /*#__PURE__*/React.createElement("span", {
    className: "m-sb-row__title"
  }, title), /*#__PURE__*/React.createElement("span", {
    className: "m-sb-row__spacer"
  }), trailing || /*#__PURE__*/React.createElement(Icon, {
    name: "caret-right",
    size: 14,
    style: {
      opacity: 0.5
    }
  }));
}
function TagRow({
  tag,
  selected,
  onSelect
}) {
  return /*#__PURE__*/React.createElement("button", {
    type: "button",
    className: "m-sb-tag" + (selected ? " is-selected" : ""),
    onClick: () => onSelect(tag.key)
  }, /*#__PURE__*/React.createElement("span", {
    className: "m-dot"
  }), /*#__PURE__*/React.createElement("span", {
    className: "m-sb-tag__label"
  }, tag.label), /*#__PURE__*/React.createElement("span", {
    className: "m-sb-tag__count"
  }, tag.count));
}
function Sidebar({
  activeTag,
  onSelectTag,
  onOpenSettings,
  expanded,
  onToggle
}) {
  const D = window.REVERIC_DATA;
  return /*#__PURE__*/React.createElement("aside", {
    className: "m-sidebar"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-sb-search"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "magnifying-glass",
    size: 14,
    style: {
      opacity: 0.55
    }
  }), /*#__PURE__*/React.createElement("input", {
    className: "m-sb-search__input",
    placeholder: "\u641C\u7D22\u4F5C\u54C1",
    spellCheck: false
  })), /*#__PURE__*/React.createElement("div", {
    className: "m-sb-scroll"
  }, /*#__PURE__*/React.createElement(SectionGroupHeader, null, "\u521B\u4F5C"), /*#__PURE__*/React.createElement(CollapsibleHeader, {
    icon: "book-open",
    title: "\u4F5C\u54C1",
    expanded: expanded.library,
    onToggle: () => onToggle("library")
  }), expanded.library && /*#__PURE__*/React.createElement("div", {
    className: "m-sb-section"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-sb-subhead"
  }, "\u6807\u7B7E"), /*#__PURE__*/React.createElement("div", {
    className: "m-sb-tags"
  }, D.tags.map(t => /*#__PURE__*/React.createElement(TagRow, {
    key: t.key,
    tag: t,
    selected: activeTag === t.key,
    onSelect: onSelectTag
  })))), /*#__PURE__*/React.createElement(SectionGroupHeader, null, "AI"), /*#__PURE__*/React.createElement(CollapsibleHeader, {
    icon: "tree-structure",
    title: "\u63D0\u793A\u8BCD",
    expanded: expanded.agents,
    onToggle: () => onToggle("agents")
  }), expanded.agents && /*#__PURE__*/React.createElement("div", {
    className: "m-sb-section m-sb-section--padded"
  }, D.agents.map(a => /*#__PURE__*/React.createElement("button", {
    key: a.id,
    type: "button",
    className: "m-sb-leaf"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: a.icon,
    size: 14
  }), /*#__PURE__*/React.createElement("span", null, a.name)))), /*#__PURE__*/React.createElement(CollapsibleHeader, {
    icon: "robot",
    title: "\u667A\u80FD\u4F53",
    expanded: expanded.subagents,
    onToggle: () => onToggle("subagents"),
    trailing: /*#__PURE__*/React.createElement("span", {
      className: "m-sb-add",
      title: "\u65B0\u5EFA"
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "plus",
      size: 12
    }))
  }), expanded.subagents && /*#__PURE__*/React.createElement("div", {
    className: "m-sb-section m-sb-section--padded"
  }, D.subagents.map(a => /*#__PURE__*/React.createElement("button", {
    key: a.id,
    type: "button",
    className: "m-sb-leaf"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: a.icon,
    size: 14
  }), /*#__PURE__*/React.createElement("div", {
    className: "m-sb-leaf__meta"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-sb-leaf__title"
  }, a.name), /*#__PURE__*/React.createElement("div", {
    className: "m-sb-leaf__sub"
  }, a.subtitle))))), /*#__PURE__*/React.createElement(CollapsibleHeader, {
    icon: "sparkle",
    title: "\u667A\u80FD\u4F53\u6280\u80FD",
    expanded: expanded.skills,
    onToggle: () => onToggle("skills"),
    trailing: /*#__PURE__*/React.createElement("span", {
      className: "m-sb-add",
      title: "\u65B0\u5EFA"
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "plus",
      size: 12
    }))
  }), expanded.skills && /*#__PURE__*/React.createElement("div", {
    className: "m-sb-section m-sb-section--padded"
  }, D.skills.map(s => /*#__PURE__*/React.createElement("button", {
    key: s.id,
    type: "button",
    className: "m-sb-leaf"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "magic-wand",
    size: 14
  }), /*#__PURE__*/React.createElement("div", {
    className: "m-sb-leaf__meta"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-sb-leaf__title"
  }, s.name), /*#__PURE__*/React.createElement("div", {
    className: "m-sb-leaf__sub"
  }, s.subtitle))))), /*#__PURE__*/React.createElement(CollapsibleHeader, {
    icon: "chat-circle-text",
    title: "\u6700\u8FD1\u5BF9\u8BDD",
    expanded: expanded.sessions,
    onToggle: () => onToggle("sessions")
  }), expanded.sessions && /*#__PURE__*/React.createElement("div", {
    className: "m-sb-section m-sb-section--padded"
  }, D.recentSessions.map(s => /*#__PURE__*/React.createElement("button", {
    key: s.id,
    type: "button",
    className: "m-sb-session"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "chat-centered",
    size: 14,
    style: {
      opacity: 0.55
    }
  }), /*#__PURE__*/React.createElement("div", {
    className: "m-sb-leaf__meta"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-sb-leaf__title"
  }, s.title), /*#__PURE__*/React.createElement("div", {
    className: "m-sb-leaf__sub"
  }, s.time))))), /*#__PURE__*/React.createElement(SectionGroupHeader, null, "\u8BBE\u7F6E"), /*#__PURE__*/React.createElement(LeafItem, {
    icon: "gear-six",
    title: "\u8BBE\u7F6E",
    onClick: onOpenSettings
  })), /*#__PURE__*/React.createElement("div", {
    className: "m-sb-user"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-avatar m-avatar--user"
  }, /*#__PURE__*/React.createElement("span", null, "\u6000")), /*#__PURE__*/React.createElement("div", {
    className: "m-sb-user__meta"
  }, /*#__PURE__*/React.createElement("div", {
    className: "m-sb-user__name"
  }, "\u6000\u7D20"), /*#__PURE__*/React.createElement("div", {
    className: "m-sb-user__sub"
  }, "\u672C\u5730\u8D26\u6237")), /*#__PURE__*/React.createElement("button", {
    className: "m-icon-btn",
    title: "\u4E3B\u9898"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "sun-dim",
    size: 16
  }))));
}
Object.assign(window, {
  Sidebar
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "Sidebar.jsx", error: String((e && e.message) || e) }); }

// WindowFrame.jsx
try { (() => {
// macOS-style desktop window frame — traffic lights on the left, draggable
// titlebar inset. This matches DesktopWindowFrame from
// lib/desktop/widgets/desktop_window_frame.dart, which the Reveric app
// requires for every page root.
function WindowFrame({
  children,
  title
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "reveric-window"
  }, /*#__PURE__*/React.createElement("div", {
    className: "reveric-titlebar"
  }, /*#__PURE__*/React.createElement("div", {
    className: "reveric-traffic"
  }, /*#__PURE__*/React.createElement("span", {
    className: "tl tl-close"
  }), /*#__PURE__*/React.createElement("span", {
    className: "tl tl-min"
  }), /*#__PURE__*/React.createElement("span", {
    className: "tl tl-zoom"
  })), /*#__PURE__*/React.createElement("div", {
    className: "reveric-titlebar-spacer"
  })), children);
}
Object.assign(window, {
  WindowFrame
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "WindowFrame.jsx", error: String((e && e.message) || e) }); }

// data.js
try { (() => {
// Mock data — novels, chapters, AI sessions.
// Bilingual copy reflects the actual product (Chinese primary, English mix).

window.REVERIC_DATA = {
  novels: [{
    id: "n1",
    title: "夜航船",
    subtitle: "Night Boat",
    description: "明末江南，一艘逆流而上的客船载着失意的画师、逃婚的小姐、隐姓的旧官。每个人都怀着一桩不可对人言的心事，每个人都在等天亮。",
    category: "历史 / Historical",
    tags: ["长篇", "明末", "群像"],
    chapters: 42,
    words: 184320,
    updated: "今天 14:32",
    cover: "ink"
  }, {
    id: "n2",
    title: "山影渐落",
    subtitle: "When the Mountains Fade",
    description: "一位退休制图师在阿尔卑斯山脚下的小镇接到了一份奇怪的委托——为一座地图上没有的山绘制等高线。",
    category: "文学 / Literary",
    tags: ["中篇", "悬疑", "山"],
    chapters: 18,
    words: 62100,
    updated: "昨天",
    cover: "mountains"
  }, {
    id: "n3",
    title: "The Astronomer's Daughter",
    subtitle: "天文学家的女儿",
    description: "Lyon, 1893. Hélène inherits her father's telescope, his unfinished star catalogue, and his quarrel with the Académie. She inherits, too, the secret he never wrote down.",
    category: "Historical fiction",
    tags: ["novella", "demo"],
    chapters: 9,
    words: 28400,
    updated: "3 天前",
    cover: "stars"
  }, {
    id: "n4",
    title: "枯木集",
    subtitle: "Withered Tree Anthology",
    description: "一组以宋代山水画为线索的短篇集，每篇围绕一幅画展开。",
    category: "短篇集 / Short stories",
    tags: ["短篇", "宋代"],
    chapters: 7,
    words: 19800,
    updated: "上周",
    cover: "tree"
  }],
  tags: [{
    key: "all",
    label: "全部",
    count: 4
  }, {
    key: "长篇",
    label: "长篇",
    count: 1
  }, {
    key: "中篇",
    label: "中篇",
    count: 1
  }, {
    key: "短篇",
    label: "短篇",
    count: 1
  }, {
    key: "novella",
    label: "novella",
    count: 1
  }, {
    key: "demo",
    label: "demo",
    count: 1
  }],
  agents: [{
    id: "a1",
    name: "主笔",
    subtitle: "Primary writing agent",
    icon: "pencil-line"
  }],
  subagents: [{
    id: "s1",
    name: "情节顾问",
    subtitle: "\u60C5\u8282\u987E\u95EE",
    icon: "tree-structure"
  }, {
    id: "s2",
    name: "人物声音",
    subtitle: "\u4EBA\u7269\u58F0\u97F3",
    icon: "mask-happy"
  }, {
    id: "s3",
    name: "世界观考据",
    subtitle: "\u4E16\u754C\u89C2\u8003\u636E",
    icon: "compass"
  }],
  skills: [{
    id: "sk1",
    name: "章节扩写",
    subtitle: "Chapter expansion"
  }, {
    id: "sk2",
    name: "润色重写",
    subtitle: "Polish & rewrite"
  }, {
    id: "sk3",
    name: "伏笔检查",
    subtitle: "Foreshadowing audit"
  }],
  recentSessions: [{
    id: "r1",
    title: "第三章·夜遇",
    time: "今天 14:20"
  }, {
    id: "r2",
    title: "周清远的视角校验",
    time: "昨天"
  }, {
    id: "r3",
    title: "明末江南漕运背景",
    time: "3 天前"
  }],
  // Editor view — opening chapter of Night Boat
  chapters: {
    n1: {
      volumes: [{
        id: "v1",
        title: "卷一 · 河上人",
        chapters: [{
          id: "c1",
          number: "01",
          title: "夜入吴县",
          words: 4128,
          state: "已定稿"
        }, {
          id: "c2",
          number: "02",
          title: "船头那盏灯",
          words: 3892,
          state: "已润色"
        }, {
          id: "c3",
          number: "03",
          title: "三舱客",
          words: 4504,
          state: "草稿"
        }, {
          id: "c4",
          number: "04",
          title: "周清远",
          words: 0,
          state: "大纲"
        }]
      }, {
        id: "v2",
        title: "卷二 · 雨中人",
        chapters: [{
          id: "c5",
          number: "05",
          title: "夜雨",
          words: 0,
          state: "大纲"
        }, {
          id: "c6",
          number: "06",
          title: "未署名的信",
          words: 0,
          state: "未开始"
        }]
      }],
      world: [{
        id: "w1",
        icon: "compass",
        title: "明末江南漕运图"
      }, {
        id: "w2",
        icon: "mountains",
        title: "苏州城地理"
      }, {
        id: "w3",
        icon: "users",
        title: "船上六人小传"
      }],
      activeChapterId: "c3",
      activeChapter: {
        number: "03",
        title: "三舱客",
        summary: "三个互不相识的客人各自上船，画师周清远暂以化名隐瞒身份；小姐凤瑶藏在男装下；旧官老沈带着一只看似普通的木匣。船未离岸，三个人的目光已经在舱中交错。",
        body: ["船家的灯笼挂在桅杆上，照见雨水沿着甲板的纹路缓缓淌下去。周清远把伞收好，伞骨在他袖中微微作响。他没有看身后那两人——他知道，越是不看，越是被看。", "“先生，”船家的声音从船尾传来，带着江浙口音的拐弯，“您是要去松江府的，是吧？”", "他点了点头，没出声。他的名字写在油纸伞柄上，是他自己刻的。今晚他不打算让任何人看见。", "船舱里很暗。三盏小油灯在低梁下摇晃，把每一张脸都照成了半张。坐在他对面的，是一个少年——细眉，唇线却太柔，像被人用过的笔尖一样收不住。少年的手指轻轻按在膝上，指甲很短，但不是男人的样子。", "周清远在心里记下了这一笔。", "另一个客人坐在最里头，靠着舱壁，怀里抱着一只乌木匣子。匣盖上嵌了一道银线，磨得很旧，但银线那一面，永远朝着他自己。老人闭着眼，嘴角紧抿。周清远见过这种紧抿——那是失意过的人才会有的，像伤疤一样长在脸上。", "舱外，雨势变密。船开始动了。"],
        notes: "本章是“群像收束”的第一拍。三个人物的身份伏笔在这里同时埋下，必须做到：周清远的画师身份不能明说；凤瑶的女装伏笔通过指甲、唇线两个细节透露；老沈的木匣在第六章揭开，此处只交代“银线那一面朝着他自己”。"
      }
    }
  },
  chatMessages: [{
    role: "user",
    content: "我希望第三章的开头能更含蓄一些，三个人的身份伏笔不要一口气全部交代完。"
  }, {
    role: "assistant",
    content: "理解。我把目前第一段拆成两段，并把“老沈的木匣”这条线推迟到周清远第二次抬头之后——也就是第六、第七段之间。这样三个人的身份分别落在三个独立的呼吸节奏里，不会像点名一样依次出场。",
    reference: "对照参考：人物档案/周清远（画师，松江府）、凤瑶（女扮男装）、老沈（前苏州府同知）。"
  }, {
    role: "user",
    content: "好。把改稿放进编辑器，但保留我原来的版本作为对照。"
  }]
};
})(); } catch (e) { __ds_ns.__errors.push({ path: "data.js", error: String((e && e.message) || e) }); }

})();
