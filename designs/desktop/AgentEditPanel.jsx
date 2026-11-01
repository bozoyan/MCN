// Subagent / Skill edit panels — the home main-pane that replaces the
// library when a subagent or skill is selected in the sidebar.
// Mirrors lib/desktop/widgets/agent_management/subagent_edit_panel.dart
// and agent_skill_edit_panel.dart (header + hero + form fields).

const MODEL_OPTIONS = [
  { name: "mimo-v2.5 · 默认", provider: "自定义供应商", icon: "sparkle" },
  { name: "DeepSeek-V3", provider: "DeepSeek", icon: "brain" },
  { name: "Claude Sonnet 4.6", provider: "Anthropic", icon: "diamond" },
  { name: "GPT-4o", provider: "OpenAI", icon: "robot" },
];

function Switch({ on, onChange }) {
  return (
    <button
      type="button"
      className={"m-switch" + (on ? " is-on" : "")}
      onClick={() => onChange(!on)}
      role="switch"
      aria-checked={on}
    >
      <span className="m-switch__knob" />
    </button>
  );
}

function FieldLabel({ children }) {
  return <div className="m-edit__label">{children}</div>;
}

// Mode switch — 对话 / 议会. Mirrors SubAgentMode chat/council.
function ModeSegmented({ initial }) {
  const [mode, setMode] = React.useState(initial === "council" ? "council" : "chat");
  return (
    <div className="m-segmented m-edit__seg">
      <button
        type="button"
        className={"m-segmented__item" + (mode === "chat" ? " is-active" : "")}
        onClick={() => setMode("chat")}
      >
        <Icon name="chat-circle-text" size={14} />
        对话
      </button>
      <button
        type="button"
        className={"m-segmented__item" + (mode === "council" ? " is-active" : "")}
        onClick={() => setMode("council")}
      >
        <Icon name="users-three" size={14} />
        议会
      </button>
    </div>
  );
}

// Model selector — click to open, pick a model, close. Mirrors
// model_selector.dart ModelSelectorButton + _ModelMenuContent.
function ModelSelect({ initial }) {
  const match = MODEL_OPTIONS.find((m) => m.name === initial);
  const [selected, setSelected] = React.useState(match || (initial ? { name: initial } : null));
  const [open, setOpen] = React.useState(false);
  const ref = React.useRef(null);

  React.useEffect(() => {
    if (!open) return;
    const onDown = (e) => {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false);
    };
    document.addEventListener("mousedown", onDown);
    return () => document.removeEventListener("mousedown", onDown);
  }, [open]);

  return (
    <div className={"m-select-wrap" + (open ? " is-open" : "")} ref={ref}>
      <button type="button" className="m-select" onClick={() => setOpen((o) => !o)}>
        <span className={selected ? "" : "m-select__placeholder"}>
          {selected ? selected.name : "未选择模型"}
        </span>
        <Icon name="caret-down" size={14} className="m-select__caret" style={{ opacity: 0.5 }} />
      </button>
      {open && (
        <div className="m-select__menu" role="menu">
          {MODEL_OPTIONS.map((m) => {
            const isSel = selected && selected.name === m.name;
            return (
              <button
                key={m.name}
                type="button"
                className={"m-select__item" + (isSel ? " is-selected" : "")}
                onClick={() => {
                  setSelected(m);
                  setOpen(false);
                }}
              >
                <Icon name={m.icon} size={18} className="m-select__item-icon" />
                <span className="m-select__item-meta">
                  <span className="m-select__item-name">{m.name}</span>
                  <span className="m-select__item-provider">{m.provider}</span>
                </span>
                {isSel && <Icon name="check" size={18} className="m-select__item-check" />}
              </button>
            );
          })}
          <div className="m-select__divider" />
          <button type="button" className="m-select__add">添加模型</button>
        </div>
      )}
    </div>
  );
}

// Header bar — title left, 启用 switch + 删除 + 保存 right. Mirrors
// _buildHeader() in both Flutter panels.
function EditHead({ title, placeholder, enabled, onToggleEnabled, hasChanges, onCancel }) {
  return (
    <header className="m-edit__head">
      <div className="m-edit__head-title">{title || placeholder}</div>
      <span className="m-edit__head-spacer" />
      <span className="m-edit__head-enabled">启用</span>
      <Switch on={enabled} onChange={onToggleEnabled} />
      <button className="m-btn m-btn--text m-btn--sm m-edit__danger" type="button">
        <Icon name="trash-simple" size={14} />
        删除
      </button>
      {hasChanges && (
        <button className="m-btn m-btn--text m-btn--sm" type="button" onClick={onCancel}>
          取消
        </button>
      )}
      <button
        className="m-btn m-btn--primary m-btn--sm"
        type="button"
        disabled={!hasChanges}
      >
        保存
      </button>
    </header>
  );
}

// Avatar + display title + subtitle. Mirrors _buildHeaderInfo().
function EditHero({ avatar, title, placeholder, subtitle, actions }) {
  return (
    <div className="m-edit__hero">
      {avatar}
      <div className="m-edit__hero-meta">
        <div className="m-edit__hero-title">{title || placeholder}</div>
        <div className="m-edit__hero-sub">{subtitle}</div>
      </div>
      {actions}
    </div>
  );
}

function SubagentEditPanel({ entity, onBack }) {
  const isNew = !entity || entity.isNew;
  const a = entity || {};
  const [enabled, setEnabled] = React.useState(a.enabled !== false);
  const [useCustom, setUseCustom] = React.useState(a.useCustomPrompt !== false);
  const hasChanges = enabled !== (a.enabled !== false) || useCustom !== (a.useCustomPrompt !== false);
  const promptEditable = !a.builtin || useCustom;

  const avatar = (
    <div className="m-edit__avatar">
      {a.emoji ? <span className="m-edit__avatar-emoji">{a.emoji}</span> : <Icon name={a.icon || "robot"} size={26} />}
    </div>
  );

  return (
    <div className="m-edit">
      <EditHead
        title={a.name}
        placeholder="新建子智能体"
        enabled={enabled}
        onToggleEnabled={setEnabled}
        hasChanges={hasChanges}
        onCancel={onBack}
      />
      <div className="m-edit__body">
        <EditHero
          avatar={avatar}
          title={a.name}
          placeholder="新建子智能体"
          subtitle="编辑子智能体的身份、行为与提示词"
          actions={
            <div className="m-edit__hero-actions">
              <button className="m-btn m-btn--text m-btn--sm" type="button">
                <Icon name="image" size={14} />
                选择图片
              </button>
            </div>
          }
        />

        <div className="m-edit__row">
          <div className="m-edit__col">
            <FieldLabel>标识符</FieldLabel>
            <div className="m-input m-input--locked">
              <span>{a.slug || ""}</span>
              {!isNew && <Icon name="lock-simple" size={13} style={{ opacity: 0.5 }} />}
            </div>
          </div>
          <div className="m-edit__col">
            <FieldLabel>名称</FieldLabel>
            <input className="m-input" defaultValue={a.name || ""} placeholder="子智能体名称" />
          </div>
        </div>

        <FieldLabel>描述</FieldLabel>
        <textarea className="m-input m-textarea" rows={3} defaultValue={a.description || ""} />

        <div className="m-edit__row">
          <div className="m-edit__col">
            <FieldLabel>模式</FieldLabel>
            <ModeSegmented initial={a.mode} />
          </div>
          <div className="m-edit__col">
            <FieldLabel>模型</FieldLabel>
            <ModelSelect initial={a.model} />
          </div>
        </div>

        <div className="m-edit__prompt-head">
          <FieldLabel>提示词</FieldLabel>
          <span className="m-edit__head-spacer" />
          {a.builtin && (
            <React.Fragment>
              <span className="m-edit__custom-label">使用自定义提示词</span>
              <Switch on={useCustom} onChange={setUseCustom} />
              {useCustom && (
                <button className="m-btn m-btn--text m-btn--sm" type="button">
                  <Icon name="arrow-counter-clockwise" size={14} />
                  重置
                </button>
              )}
            </React.Fragment>
          )}
        </div>
        <textarea
          className="m-input m-textarea m-edit__prompt"
          rows={12}
          defaultValue={a.prompt || ""}
          disabled={!promptEditable}
          placeholder="描述这个子智能体的职责、输入与输出格式…"
        />
      </div>
    </div>
  );
}

function SkillEditPanel({ entity, onBack }) {
  const s = entity || {};
  const [enabled, setEnabled] = React.useState(s.enabled !== false);
  const hasChanges = enabled !== (s.enabled !== false);

  const avatar = (
    <div className="m-edit__avatar">
      <Icon name="sparkle" size={26} />
    </div>
  );

  return (
    <div className="m-edit">
      <EditHead
        title={s.name}
        placeholder="新建技能"
        enabled={enabled}
        onToggleEnabled={setEnabled}
        hasChanges={hasChanges}
        onCancel={onBack}
      />
      <div className="m-edit__body">
        <EditHero
          avatar={avatar}
          title={s.name}
          placeholder="新建技能"
          subtitle="编辑技能的触发时机与提示词"
        />

        <FieldLabel>名称</FieldLabel>
        <input className="m-input" defaultValue={s.name || ""} placeholder="技能名称" />

        <FieldLabel>使用时机</FieldLabel>
        <textarea className="m-input m-textarea" rows={2} defaultValue={s.whenToUse || ""} />

        <FieldLabel>描述</FieldLabel>
        <textarea className="m-input m-textarea" rows={3} defaultValue={s.description || ""} />

        <FieldLabel>提示词</FieldLabel>
        <textarea
          className="m-input m-textarea m-edit__prompt"
          rows={12}
          defaultValue={s.prompt || ""}
          placeholder="描述这个技能的执行步骤与输出要求…"
        />
      </div>
    </div>
  );
}

// Agent profile (提示词) + shortcut (快捷方式) edit panel. Mirrors
// agent_profile_edit_panel.dart / ai_shortcut_action_edit_panel.dart — both
// are identity + prompt forms, with a 触发位置 row for shortcuts.
function AgentEditPanel({ entity, onBack, variant }) {
  const e = entity || {};
  const isShortcut = variant === "shortcut";
  const [enabled, setEnabled] = React.useState(e.enabled !== false);
  const hasChanges = enabled !== (e.enabled !== false);
  const placeholder = isShortcut ? "新建快捷方式" : "新建提示词";

  const avatar = (
    <div className="m-edit__avatar">
      {e.emoji ? (
        <span className="m-edit__avatar-emoji">{e.emoji}</span>
      ) : (
        <Icon name={isShortcut ? "cursor-click" : e.icon || "tree-structure"} size={26} />
      )}
    </div>
  );

  return (
    <div className="m-edit">
      <EditHead
        title={e.name}
        placeholder={placeholder}
        enabled={enabled}
        onToggleEnabled={setEnabled}
        hasChanges={hasChanges}
        onCancel={onBack}
      />
      <div className="m-edit__body">
        <EditHero
          avatar={avatar}
          title={e.name}
          placeholder={placeholder}
          subtitle={
            isShortcut
              ? "编辑快捷方式的触发位置与提示词"
              : "编辑提示词智能体的身份与笔法"
          }
        />

        <FieldLabel>名称</FieldLabel>
        <input
          className="m-input"
          defaultValue={e.name || ""}
          placeholder={isShortcut ? "快捷方式名称" : "提示词名称"}
        />

        {!isShortcut && (
          <React.Fragment>
            <FieldLabel>描述</FieldLabel>
            <textarea
              className="m-input m-textarea"
              rows={3}
              defaultValue={e.description || ""}
            />
          </React.Fragment>
        )}

        {isShortcut && (
          <React.Fragment>
            <FieldLabel>触发位置</FieldLabel>
            <div className="m-segmented m-edit__seg">
              <button type="button" className="m-segmented__item is-active">
                <Icon name="text-t" size={14} />
                选中文字
              </button>
              <button type="button" className="m-segmented__item">
                <Icon name="note-pencil" size={14} />
                编辑器
              </button>
            </div>
          </React.Fragment>
        )}

        <FieldLabel>提示词</FieldLabel>
        <textarea
          className="m-input m-textarea m-edit__prompt"
          rows={12}
          defaultValue={e.prompt || ""}
          placeholder={
            isShortcut
              ? "描述这个快捷方式对选中文字要做什么…"
              : "描述这个提示词智能体的身份、笔法与边界…"
          }
        />
      </div>
    </div>
  );
}

Object.assign(window, { SubagentEditPanel, SkillEditPanel, AgentEditPanel });
