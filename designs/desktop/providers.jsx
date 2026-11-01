// Faithful reproduction of the AI providers settings page (desktop two-column).
// Mirrors lib/shared/widgets/settings/ai_providers_section.dart +
// provider_config_panel.dart: provider list (left) + config panel (right).
// 全部是自带 key 的外部供应商，没有托管模型。

function ProvidersSection() {
  const [selectedId, setSelectedId] = React.useState(PROVIDERS[0].id);
  const selected = PROVIDERS.find((p) => p.id === selectedId) || PROVIDERS[0];
  return (
    <div className="sp-prov">
      <div className="sp-prov-list">
        <div className="sp-prov-list__scroll">
          {PROVIDERS.map((p) => (
            <button
              key={p.id}
              type="button"
              className={"sp-prov-item" + (p.id === selected.id ? " is-selected" : "")}
              onClick={() => setSelectedId(p.id)}
            >
              <span className="sp-prov-dot" style={{ background: p.valid ? "var(--addition-border)" : "var(--border)" }} />
              <span style={{ flex: 1, minWidth: 0 }}>
                <span className="sp-prov-item__name" style={{ display: "block", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{p.name}</span>
                {p.custom && <span className="sp-badge sp-badge--custom">自定义</span>}
              </span>
            </button>
          ))}
        </div>
        <div className="sp-prov-list__foot">
          <button type="button" className="sp-prov-add">
            <Icon name="plus" size={14} />添加自定义
          </button>
        </div>
      </div>
      <div className="sp-prov-divider" />
      <ProviderConfigPanel config={selected} />
    </div>
  );
}

function StatusBadge({ on }) {
  return (
    <span className={"sp-status-badge " + (on ? "sp-status-badge--on" : "sp-status-badge--off")}>
      {on ? "启用" : "未启用"}
    </span>
  );
}

function Switch({ on, onToggle }) {
  return (
    <button type="button" className={"sp-switch " + (on ? "sp-switch--on" : "sp-switch--off")} onClick={onToggle} aria-pressed={on}>
      <span className="sp-switch__knob" />
    </button>
  );
}

function ProviderConfigPanel({ config }) {
  const [enabled, setEnabled] = React.useState(config.enabled);
  React.useEffect(() => setEnabled(config.enabled), [config.id]);
  const valid = config.valid && enabled;

  return (
    <div className="sp-prov-panel">
      <div className="sp-prov-head">
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: "flex", alignItems: "center", gap: "var(--space-sm)" }}>
            <span className="sp-prov-head__title">{config.name}</span>
            <StatusBadge on={valid} />
          </div>
          <div className="sp-prov-head__type">{config.type}</div>
        </div>
        <Switch on={enabled} onToggle={() => setEnabled((v) => !v)} />
        {config.custom && (
          <button type="button" className="sp-icon-btn" title="删除"><Icon name="trash" size={18} /></button>
        )}
      </div>

      <div className="sp-prov-body">
        <EditableConfig config={config} />
      </div>
    </div>
  );
}

function Field({ label, value, hint, obscure, mono }) {
  return (
    <div className="sp-field">
      <label className="sp-field__label">{label}</label>
      <input className="m-input" defaultValue={value} type={obscure ? "password" : "text"}
        style={mono ? { fontFamily: "var(--font-mono)" } : null} readOnly />
      {hint && <div className="sp-field__hint">{hint}</div>}
    </div>
  );
}

function ReadOnlyField({ label, value }) {
  return (
    <div className="sp-field">
      <label className="sp-field__label">{label}</label>
      <div className="sp-readonly"><Icon name="lock-key" size={14} /><span style={{ flex: 1 }}>{value}</span></div>
    </div>
  );
}

function EditableConfig({ config }) {
  const effortOptions = ["默认", "低", "中", "高"];
  return (
    <div>
      {config.custom && (
        <React.Fragment>
          <Field label="名称" value={config.name} />
          <ReadOnlyField label="提供商类型" value={config.type} />
        </React.Fragment>
      )}

      <Field label="API 密钥" value={config.apiKey} obscure={!!config.apiKey} mono
        hint={!config.apiKey ? "填写 API Key 后才能启用该提供商。" : null} />

      {config.fixedBaseUrl
        ? <ReadOnlyField label="基础 URL" value={config.baseUrl} />
        : <Field label="基础 URL" value={config.baseUrl} mono />}

      {/* Models editor */}
      <div className="sp-field">
        <div className="sp-row-between" style={{ marginBottom: "var(--space-xs)" }}>
          <label className="sp-field__label" style={{ margin: 0 }}>聊天模型</label>
          {config.apiKey && (
            <button type="button" className="sp-fetch-btn"><Icon name="download-simple" size={14} />获取模型</button>
          )}
        </div>
        <div className="sp-models-box">
          {config.models.length === 0 && (
            <div className="sp-field__hint" style={{ marginTop: 0, marginBottom: "var(--space-sm)" }}>暂无模型，添加后才能启用默认模型选择。</div>
          )}
          {config.models.map((m) => (
            <div key={m} className="sp-models-row">
              <span className="sp-models-row__name">{m}</span>
              <button type="button" className="sp-icon-btn" style={{ width: 24, height: 24 }} title="删除模型"><Icon name="x" size={14} /></button>
            </div>
          ))}
          <div className="sp-models-add">
            <input className="m-input" placeholder="输入模型 ID，例如 gpt-4.1" readOnly />
            <button type="button" className="m-btn m-btn--secondary m-btn--sm">添加</button>
          </div>
        </div>
        {config.models.length === 0 && <div className="sp-field__hint">至少添加一个模型后才能启用该提供商。</div>}
      </div>

      {/* Temperature */}
      <div className="sp-field">
        <div className="sp-row-between"><label className="sp-field__label" style={{ margin: 0 }}>温度</label><span className="sp-value-accent">{config.temperature.toFixed(1)}</span></div>
        <div className="sp-slider"><div className="sp-slider__fill" style={{ width: `${(config.temperature / 2) * 100}%` }} /><div className="sp-slider__knob" style={{ left: `${(config.temperature / 2) * 100}%` }} /></div>
      </div>

      {/* Max tokens */}
      <div className="sp-field">
        <label className="sp-field__label">最大词元数</label>
        <div className="sp-maxtokens">
          <div className="sp-slider"><div className="sp-slider__fill" style={{ width: "70%" }} /><div className="sp-slider__knob" style={{ left: "70%" }} /></div>
          <input className="sp-maxtokens__field" defaultValue={config.maxTokens} readOnly />
        </div>
      </div>

      {/* Reasoning effort */}
      <div className="sp-field">
        <div className="sp-row-between"><label className="sp-field__label" style={{ margin: 0 }}>推理强度</label><span className="sp-value-accent">{config.reasoning}</span></div>
        <div className="sp-effort-chips">
          {effortOptions.map((o) => (
            <div key={o} className={"sp-effort-chip" + (o === config.reasoning ? " is-selected" : "")}>{o}</div>
          ))}
        </div>
      </div>

      {/* Proxy */}
      <div className="sp-subhead">代理</div>
      <Field label="代理 URL" value="" />
      <Field label="代理用户名" value="" />
      <Field label="代理密码" value="" obscure />
    </div>
  );
}

Object.assign(window, { ProvidersSection });
