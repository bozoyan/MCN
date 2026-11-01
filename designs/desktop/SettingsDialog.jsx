// Settings dialog — modal overlay shown from sidebar gear icon.

function SettingsDialog({ onClose, section: sectionProp, setSection: setSectionProp, deepLink }) {
  const [localSection, setLocalSection] = React.useState("appearance");
  const section = sectionProp || localSection;
  const setSection = setSectionProp || setLocalSection;

  return (
    <div className="m-dialog-scrim" onClick={onClose}>
      <div
        className="m-dialog m-dialog--settings"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
      >
        <div className="m-dialog__head">
          <h2 className="m-heading">设置</h2>
          <button className="m-icon-btn" onClick={onClose} title="关闭">
            <Icon name="x" size={16} />
          </button>
        </div>

        <div className="m-dialog__body">
          <div className="m-settings-nav">
            {[
              { id: "appearance", icon: "palette", label: "外观" },
              { id: "usage", icon: "chart-bar", label: "用量" },
              { id: "providers", icon: "brain", label: "AI 提供商" },
              { id: "agents", icon: "robot", label: "智能体" },
              { id: "remote", icon: "squares-four", label: "远程控制" },
              { id: "shortcuts", icon: "cursor-click", label: "快捷键" },
              { id: "data", icon: "floppy-disk", label: "数据" },
              { id: "about", icon: "info", label: "关于" },
            ].map((s) => (
              <button
                key={s.id}
                type="button"
                className={"m-settings-nav__row" + (section === s.id ? " is-selected" : "")}
                onClick={() => setSection(s.id)}
              >
                <Icon name={s.icon} size={14} />
                <span>{s.label}</span>
              </button>
            ))}
          </div>

          <div className={"m-settings-panel" + (section === "providers" ? " m-settings-panel--bleed" : "")}>
            {section === "appearance" && <AppearancePanel />}
            {section === "usage" && (
              <UsageSection
                key={deepLink ? deepLink.sessionId || deepLink.tab : "usage"}
                initialTab={deepLink && deepLink.tab}
                initialSessionId={deepLink && deepLink.sessionId}
              />
            )}
            {section === "providers" && <ProvidersSection />}
            {section === "agents" && <PlaceholderPanel name="智能体" />}
            {section === "remote" && <RemotePanel />}
            {section === "shortcuts" && <PlaceholderPanel name="快捷键" />}
            {section === "data" && <PlaceholderPanel name="数据" />}
            {section === "about" && <AboutPanel />}
          </div>
        </div>
      </div>
    </div>
  );
}

// Mirrors lib/shared/widgets/settings/appearance_settings_section.dart:
// 主题模式 → 主题 → 应用背景. Palette / mode state lives in designs/theme.js.
const APPEARANCE_MODE_ICONS = { light: "sun-dim", dark: "moon-stars", system: "circle" };

function AppearanceSectionHeader({ title, desc }) {
  return (
    <div className="m-appearance__header">
      <div className="m-appearance__title">{title}</div>
      <div className="m-appearance__desc">{desc}</div>
    </div>
  );
}

function ThemePreview({ preview }) {
  return (
    <span className="m-theme-preview" style={{ background: preview.canvas }}>
      <span className="m-theme-preview__bar" style={{ background: preview.accent }} />
      <span className="m-theme-preview__body">
        <span className="m-theme-preview__surface" style={{ background: preview.surface }} />
        <span
          className="m-theme-preview__text"
          style={{ background: `color-mix(in srgb, ${preview.text} 30%, transparent)` }}
        />
      </span>
    </span>
  );
}

function AppearancePanel() {
  const RT = window.RevericTheme;
  const current = RT.useTheme();

  return (
    <div className="m-form m-appearance">
      <div className="m-appearance__section">
        <AppearanceSectionHeader title="主题模式" desc="选择浅色、深色或跟随系统。" />
        <div className="m-theme-list">
          {RT.MODES.map((m) => {
            const on = current.mode === m.key;
            return (
              <button
                key={m.key}
                type="button"
                className={"m-theme-card" + (on ? " is-active" : "")}
                onClick={() => RT.set({ mode: m.key })}
              >
                <Icon name={APPEARANCE_MODE_ICONS[m.key]} size={24} className="m-theme-card__icon" />
                <span className="m-theme-card__label">{m.label}</span>
                {on && <Icon name="check-circle" size={20} className="m-theme-card__check" />}
              </button>
            );
          })}
        </div>
      </div>

      <div className="m-appearance__section">
        <AppearanceSectionHeader title="主题" desc="选择应用主题风格。" />
        <div className="m-theme-list">
          {RT.PALETTES.map((p) => {
            const on = current.palette === p.key;
            return (
              <button
                key={p.key}
                type="button"
                className={"m-theme-card" + (on ? " is-active" : "")}
                onClick={() => RT.set({ palette: p.key })}
              >
                <ThemePreview preview={p.preview} />
                <span className="m-theme-card__meta">
                  <span className="m-theme-card__label">{p.label}</span>
                  <span className="m-theme-card__desc">{p.desc}</span>
                </span>
                {on && <Icon name="check-circle" size={20} className="m-theme-card__check" />}
              </button>
            );
          })}
        </div>
      </div>

      <div className="m-appearance__section">
        <AppearanceSectionHeader title="应用背景" desc="为整个应用设置互斥的纯色或图片背景。" />
        <div className="m-bg-grid">
          {[
            "distant_mountains",
            "plum_blossom",
            "solitary_boat",
            "withered_tree",
          ].map((k, i) => (
            <button key={k} type="button" className={"m-bg-tile" + (i === 0 ? " is-active" : "")}>
              <img src={`assets/images/background/${k}.webp`} alt={k} />
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

function ProvidersPanel() {
  const providers = [
    { name: "Anthropic", model: "Claude 3.5 Sonnet", state: "已连接", state_kind: "ok" },
    { name: "OpenAI", model: "GPT‑4o", state: "已连接", state_kind: "ok" },
    { name: "Google", model: "Gemini 1.5 Pro", state: "未配置密钥", state_kind: "warn" },
    { name: "Local · Ollama", model: "Qwen2.5 32B", state: "已连接", state_kind: "ok" },
  ];
  return (
    <div className="m-form">
      <h3 className="m-heading" style={{ fontSize: 18 }}>AI 提供商</h3>
      <p className="m-body-small">主笔智能体会从下列已连接的提供商中按你设定的优先级选择模型。</p>

      <div className="m-provider-list">
        {providers.map((p) => (
          <div key={p.name} className="m-provider-row">
            <div className="m-provider-row__l">
              <div className="m-avatar m-avatar--brand">
                <Icon name="brain" size={16} />
              </div>
              <div>
                <div className="m-ui-medium" style={{ color: "var(--text-primary)" }}>{p.name}</div>
                <div className="m-ui-tiny">{p.model}</div>
              </div>
            </div>
            <div className="m-provider-row__r">
              <span className={"m-pill m-pill--" + p.state_kind}>{p.state}</span>
              <button className="m-btn m-btn--secondary m-btn--sm">配置</button>
            </div>
          </div>
        ))}
      </div>

      <button className="m-btn m-btn--secondary" style={{ marginTop: 16 }}>
        <Icon name="plus" size={14} />
        添加自定义提供商
      </button>
    </div>
  );
}

function PlaceholderPanel({ name }) {
  return (
    <div className="m-form">
      <h3 className="m-heading" style={{ fontSize: 18 }}>{name}</h3>
      <p className="m-body-small">
        本设计系统恢复的设置项仅展示外观与提供商部分，其他面板可参考 Reveric 源码 lib/desktop/pages/settings/ 进一步实现。
      </p>
    </div>
  );
}

function AboutPanel() {
  return (
    <div className="m-form" style={{ alignItems: "center", textAlign: "center" }}>
      <div style={{ marginTop: 12, marginBottom: 12 }}>
        <Mark size={64} />
      </div>
      <h3 className="m-heading">Reveric</h3>
      <p className="m-body-small" style={{ maxWidth: 360 }}>
        AI 辅助小说创作软件。让 AI 承担可自动化的生成与润色工作，让作者专注于创意决策与质量把控。
      </p>
      <div className="m-ui-tiny" style={{ marginTop: 12 }}>版本 0.4.2 · build 1126</div>
    </div>
  );
}

function RemotePanel() {
  const [remoteState, setRemoteState] = React.useState("idle"); // idle | qr | connected
  const [isRunning, setIsRunning] = React.useState(true);

  const handleLogin = () => setRemoteState("qr");
  const handleLogout = () => { setRemoteState("idle"); setIsRunning(false); };
  const handleToggle = () => setIsRunning(!isRunning);

  return (
    <div className="m-form">
      <div className="section-header">
        <div className="section-header__title">远程控制</div>
        <div className="section-header__desc">连接微信，即可在手机上与助手对话、查看任务进度。</div>
      </div>

      {remoteState === "idle" && (
        <div className="remote-feature-card">
          <div className="remote-feature-card__hero">
            <div className="remote-feature-card__icon-group">
              <div className="remote-feature-card__device">
                <div className="remote-feature-card__device-screen">
                  <Icon name="gear-six" size={16} />
                </div>
              </div>
              <div className="remote-feature-card__connection-line"></div>
              <div className="remote-feature-card__wechat-icon">
                <Icon name="chat-centered" size={28} color="white" />
              </div>
            </div>
          </div>
          <div className="remote-feature-card__body">
            <div className="remote-feature-card__title">微信登录</div>
            <div className="remote-feature-card__desc">扫描二维码，将电脑端助手连接到你的微信，随时随地接收消息。</div>
            <div className="remote-feature-card__actions">
              <button className="m-btn m-btn--primary" onClick={handleLogin}>
                <Icon name="chat-centered" size={14} />
                微信登录
              </button>
            </div>
          </div>
        </div>
      )}

      {remoteState === "qr" && (
        <div className="remote-qr-card">
          <div className="remote-qr-card__qr">
            <div className="remote-qr-card__qr-pattern">
              {Array.from({ length: 64 }).map((_, i) => (
                <div key={i} className={Math.random() > 0.5 ? "remote-qr-cell" : "remote-qr-cell--empty"} />
              ))}
            </div>
          </div>
          <div className="remote-qr-card__info">
            <div className="remote-qr-card__title">
              微信扫码登录
              <span className="remote-qr-card__badge">扫码连接</span>
            </div>
            <div className="remote-qr-card__steps">
              <div className="remote-step">
                <span className="remote-step__num">1</span>
                打开手机微信
              </div>
              <div className="remote-step">
                <span className="remote-step__num">2</span>
                扫描左侧二维码
              </div>
              <div className="remote-step">
                <span className="remote-step__num">3</span>
                在手机上确认登录
              </div>
            </div>
            <div style={{ marginTop: "var(--space-2xl)" }}>
              <button className="m-btn m-btn--secondary m-btn--sm" onClick={() => setRemoteState("connected")}>
                模拟连接成功
              </button>
            </div>
          </div>
        </div>
      )}

      {remoteState === "connected" && (
        <div className="remote-connected-card">
          <div className="remote-connected-card__status">
            <div className={"remote-connected-card__dot" + (isRunning ? " is-active" : "")}></div>
            <div className="remote-connected-card__meta">
              <div className="remote-connected-card__label">已连接</div>
              <div className="remote-connected-card__sub">
                {isRunning ? "远程桥接运行中" : "桥接已停止"}
              </div>
            </div>
            <div className={"toggle" + (isRunning ? " is-on" : "")} onClick={handleToggle}>
              <div className="toggle__knob"></div>
            </div>
          </div>
          <div className="remote-connected-card__detail">
            <div className="remote-connected-card__info-row">
              <Icon name="clock" size={14} />
              <span>上次同步：</span>
              <span className="remote-connected-card__info-value">2 分钟前</span>
            </div>
            <div className="remote-connected-card__info-row">
              <Icon name="gear-six" size={14} />
              <span>设备：</span>
              <span className="remote-connected-card__info-value">iPhone 15 Pro</span>
            </div>
          </div>
          <div className="remote-connected-card__footer">
            <button className="m-btn m-btn--text" style={{ color: "var(--text-muted)" }} onClick={handleLogout}>
              退出登录
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

Object.assign(window, { SettingsDialog });
