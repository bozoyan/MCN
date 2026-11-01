// skills/views.jsx — AgentSkill Setup:小说编辑器 Main 区域的技能配置中枢。
// 对应方案 docs/solutions/agent-skill-library-and-novel-installations.md,
// 镜像 lib/desktop/pages/novel_editor.dart 的 _EditorContentSelection Main 区域。
//
// 结构:头部(标题 + 上下文动作) → 分页(已安装/技能库/官方目录/市场) → 各页内容。
// 安装冲突、升级确认、撤销、创建均为对话框。市场直接浏览,不需要账号。所有可视化仅为 mock,状态存在组件内,无真实持久化与网络。
//
// 复用:全局 Icon(Icon.jsx);其余原子(SkSwitch/SkTag/SkDialog…)在本文件内定义,
// 因为 text/babel 脚本各自独立作用域,不能引用 AgentEditPanel.jsx 里的 Switch。

/* ============================ atoms ============================ */

function SkSwitch({ on, onChange }) {
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

// 小标签 — 复用 management 的 meta tag 视觉。
function SkTag({ icon, children, tone }) {
  return (
    <span className={"m-mgmt-tag" + (tone ? " m-mgmt-tag--" + tone : "")}>
      {icon && <Icon name={icon} size={12} />}
      {children}
    </span>
  );
}

// 来源徽章 — novel_local / library / official / marketplace。
function SkSourceBadge({ kind }) {
  const b = SK_SOURCE_BADGE[kind];
  if (!b) {
    return null;
  }
  return (
    <SkTag icon={b.icon} tone={b.tone}>
      {b.label}
    </SkTag>
  );
}

function SkField({ label, hint, children }) {
  return (
    <label className="sk-field">
      <span className="sk-field__label">{label}</span>
      {children}
      {hint && <span className="sk-field__hint">{hint}</span>}
    </label>
  );
}

// 通用对话框外壳 — 复用 m-dialog-scrim + m-dialog。
function SkDialog({ title, sub, icon, width, onClose, children, foot }) {
  return (
    <div className="m-dialog-scrim" onClick={onClose}>
      <div
        className="m-dialog sk-dialog"
        style={{ width }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="sk-dialog__head">
          {icon && (
            <span className="sk-dialog__head-icon">
              <Icon name={icon} size={18} />
            </span>
          )}
          <div className="sk-dialog__head-meta">
            <div className="sk-dialog__title">{title}</div>
            {sub && <div className="sk-dialog__sub">{sub}</div>}
          </div>
          <button type="button" className="m-icon-btn" onClick={onClose}>
            <Icon name="x" size={16} />
          </button>
        </div>
        <div className="sk-dialog__body">{children}</div>
        {foot && <div className="sk-dialog__foot">{foot}</div>}
      </div>
    </div>
  );
}

/* ============================ installed list ============================ */

function SkInstalledRow({ item, kebabOpen, onToggle, onKebab, onAction, onUpgrade }) {
  const blocked = !!item.executionBlockedReason;
  return (
    <div className={"sk-row" + (blocked ? " is-blocked" : "")}>
      <div className="sk-row__grip">
        <Icon name="dots-three-vertical" size={16} />
      </div>
      <div className="sk-row__main">
        <div className="sk-row__title-line">
          <span className="sk-row__name">{item.name}</span>
          <code className="sk-row__call">{item.callName}</code>
          <SkSourceBadge kind={item.sourceKind} />
          {item.sourceVersion && (
            <SkTag icon="git-fork">v{item.sourceVersion}</SkTag>
          )}
        </div>
        <p className="sk-row__desc">{item.description}</p>
        {item.upgradeVersion && !blocked && (
          <button
            type="button"
            className="sk-upgrade"
            onClick={() => onUpgrade(item)}
          >
            <Icon name="arrow-clockwise" size={13} />
            可升级到 v{item.upgradeVersion}
          </button>
        )}
        {blocked && (
          <button
            type="button"
            className="sk-blocked"
            onClick={() => onAction("revoked", item)}
          >
            <Icon name="warning-circle" size={13} />
            已被撤销 · 运行时跳过执行
          </button>
        )}
      </div>
      <div className="sk-row__side">
        <SkSwitch on={item.enabled} onChange={() => onToggle(item.id)} />
        <div className="sk-kebab">
          <button
            type="button"
            className="m-icon-btn"
            onClick={() => onKebab(kebabOpen ? null : item.id)}
          >
            <Icon name="dots-three" size={16} />
          </button>
          {kebabOpen && (
            <div className="sk-kebab__menu" role="menu">
              <button type="button" onClick={() => onAction("saveLib", item)}>
                <Icon name="floppy-disk" size={15} />
                保存到技能库
              </button>
              <button type="button" onClick={() => onAction("rename", item)}>
                <Icon name="pencil-simple" size={15} />
                重命名调用名
              </button>
              <button
                type="button"
                className="is-danger"
                onClick={() => onAction("remove", item)}
              >
                <Icon name="trash-simple" size={15} />
                移除
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function SkInstalledList({ items, kebabOpen, onToggle, onKebab, onAction, onUpgrade, onCreate }) {
  if (items.length === 0) {
    return (
      <div className="sk-empty">
        <Icon name="stack" size={30} />
        <div className="sk-empty__title">未安装技能</div>
        <div className="sk-empty__text">
          这本小说还没有安装任何技能,仍可正常聊天与编辑。
          <br />
          从技能库、官方目录或市场安装,或直接创建一个本地技能。
        </div>
        <button type="button" className="m-btn m-btn--primary m-btn--sm" onClick={onCreate}>
          <Icon name="plus" size={14} />
          创建本地技能
        </button>
      </div>
    );
  }
  return (
    <div className="sk-list">
      <div className="sk-list__hint">
        <Icon name="info" size={13} />
        运行时只读取本小说中已启用、未被撤销的技能,按此处顺序组装。
      </div>
      {items.map((it) => (
        <SkInstalledRow
          key={it.id}
          item={it}
          kebabOpen={kebabOpen === it.id}
          onToggle={onToggle}
          onKebab={onKebab}
          onAction={onAction}
          onUpgrade={onUpgrade}
        />
      ))}
    </div>
  );
}

/* ============================ source browsers ============================ */

// 一张可安装来源卡片(技能库 / 官方目录)。
function SkSourceCard({ item, badge, version, onInstall }) {
  return (
    <article className="sk-card">
      <div className="sk-card__head">
        <span className="sk-card__badge">
          <Icon name={badge.icon} size={18} />
        </span>
        <div className="sk-card__title">{item.name}</div>
        {version && <SkTag icon="git-fork">v{version}</SkTag>}
      </div>
      <p className="sk-card__desc">{item.description}</p>
      <div className="sk-card__meta">
        {item.category && <SkTag icon="tag">{item.category}</SkTag>}
        {(item.tags || []).map((t) => (
          <SkTag key={t}>{t}</SkTag>
        ))}
      </div>
      <div className="sk-card__foot">
        {item.updatedAt && <span className="sk-card__stamp">更新于 {item.updatedAt}</span>}
        <span className="sk-card__foot-spacer" />
        <button type="button" className="m-btn m-btn--secondary m-btn--sm" onClick={() => onInstall(item)}>
          <Icon name="download-simple" size={14} />
          安装
        </button>
      </div>
    </article>
  );
}

// 市场卡片 — 点击进入详情;安装走详情页。
function SkMarketCard({ item, onOpen }) {
  return (
    <article className="sk-card sk-card--market" onClick={() => onOpen(item)} role="button" tabIndex={0}>
      <div className="sk-card__head">
        <span className="sk-card__badge">
          <Icon name="storefront" size={18} />
        </span>
        <div className="sk-card__title">{item.name}</div>
        <Icon name="caret-right" size={15} className="sk-card__go" />
      </div>
      <p className="sk-card__desc">{item.description}</p>
      <div className="sk-card__meta">
        {item.category && <SkTag icon="tag">{item.category}</SkTag>}
        {(item.tags || []).map((t) => (
          <SkTag key={t}>{t}</SkTag>
        ))}
      </div>
      <div className="sk-card__foot">
        <span className="sk-card__stamp">
          <Icon name="user" size={12} /> {item.author}
        </span>
        <span className="sk-card__stamp">
          <Icon name="download-simple" size={12} /> {item.installs.toLocaleString()}
        </span>
        <span className="sk-card__foot-spacer" />
        <SkTag icon="git-fork">v{item.version}</SkTag>
      </div>
    </article>
  );
}

function SkMarketDetail({ item, onBack, onInstall }) {
  return (
    <div className="sk-detail">
      <button type="button" className="sk-detail__back" onClick={onBack}>
        <Icon name="arrow-left" size={15} />
        返回市场
      </button>
      <div className="sk-detail__hero">
        <span className="sk-detail__badge">
          <Icon name="storefront" size={24} />
        </span>
        <div className="sk-detail__hero-meta">
          <div className="sk-detail__title">{item.name}</div>
          <div className="sk-detail__by">
            <Icon name="user" size={13} /> {item.author}
            <span className="sk-detail__dot">·</span>
            <Icon name="download-simple" size={13} /> {item.installs.toLocaleString()} 次安装
          </div>
        </div>
        <button type="button" className="m-btn m-btn--primary m-btn--sm" onClick={() => onInstall(item)}>
          <Icon name="download-simple" size={14} />
          安装当前版本 v{item.version}
        </button>
      </div>

      <div className="sk-detail__meta">
        {item.category && <SkTag icon="tag">{item.category}</SkTag>}
        {(item.tags || []).map((t) => (
          <SkTag key={t}>{t}</SkTag>
        ))}
      </div>

      <div className="sk-detail__sec-label">使用时机</div>
      <p className="sk-detail__prose">{item.whenToUse}</p>
      <div className="sk-detail__sec-label">描述</div>
      <p className="sk-detail__prose">{item.description}</p>

      <div className="sk-detail__sec-label">版本记录</div>
      <div className="sk-versions">
        {item.versions.map((v, i) => (
          <div key={v.version} className="sk-version">
            <div className="sk-version__tag">
              <Icon name="git-fork" size={13} />
              v{v.version}
              {i === 0 && v.status === "approved" && (
                <span className="sk-version__current">当前</span>
              )}
            </div>
            <div className="sk-version__meta">
              <span className="sk-version__note">{v.note}</span>
              <span className="sk-version__date">{v.date}</span>
            </div>
            {v.status === "revoked" && (
              <SkTag icon="warning-circle" tone="muted">
                已撤销
              </SkTag>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

/* ============================ dialogs ============================ */

function SkConflictDialog({ item, installed, onClose, onOverwrite, onRename }) {
  const [name, setName] = React.useState("");
  const existing = installed.find((n) => n.name === item.name);
  const taken = installed.some((n) => n.callName === name.trim());
  const invalid = !name.trim() || taken;
  return (
    <SkDialog
      icon="warning-circle"
      title="调用名冲突"
      sub={`本小说已存在调用名 “${existing ? existing.callName : ""}”`}
      width={440}
      onClose={onClose}
      foot={
        <React.Fragment>
          <button type="button" className="m-btn m-btn--text m-btn--sm" onClick={onClose}>
            取消
          </button>
          <button type="button" className="m-btn m-btn--secondary m-btn--sm" onClick={() => onOverwrite(item)}>
            覆盖现有
          </button>
          <button
            type="button"
            className="m-btn m-btn--primary m-btn--sm"
            disabled={invalid}
            onClick={() => onRename(item, name.trim())}
          >
            以新调用名安装
          </button>
        </React.Fragment>
      }
    >
      <p className="sk-dialog__note">
        覆盖会替换目标记录并解除旧来源关联;重命名会保留两条独立安装,重命名不影响后续升级。
      </p>
      <SkField
        label="新调用名"
        hint={taken ? "该调用名已被占用" : "本小说内唯一,是 Agent 工具的有效名称"}
      >
        <input
          className={"m-input" + (taken ? " is-error" : "")}
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="例如 lore_audit_2"
          spellCheck={false}
        />
      </SkField>
    </SkDialog>
  );
}

function SkUpgradeDialog({ item, onClose, onConfirm }) {
  return (
    <SkDialog
      icon="arrow-clockwise"
      title="升级技能"
      sub={item.name}
      width={420}
      onClose={onClose}
      foot={
        <React.Fragment>
          <button type="button" className="m-btn m-btn--text m-btn--sm" onClick={onClose}>
            取消
          </button>
          <button type="button" className="m-btn m-btn--primary m-btn--sm" onClick={() => onConfirm(item)}>
            确认升级
          </button>
        </React.Fragment>
      }
    >
      <div className="sk-verjump">
        <span className="sk-verjump__from">v{item.sourceVersion}</span>
        <Icon name="arrow-right" size={16} />
        <span className="sk-verjump__to">v{item.upgradeVersion}</span>
      </div>
      <p className="sk-dialog__note">
        确认后才会覆盖快照内容与来源版本,保留调用名、启用状态与排序。既有正文不受影响。
      </p>
    </SkDialog>
  );
}

function SkSaveLibDialog({ item, onClose, onConfirm }) {
  return (
    <SkDialog
      icon="floppy-disk"
      title="保存到技能库"
      sub={item.name}
      width={420}
      onClose={onClose}
      foot={
        <React.Fragment>
          <button type="button" className="m-btn m-btn--text m-btn--sm" onClick={onClose}>
            取消
          </button>
          <button type="button" className="m-btn m-btn--primary m-btn--sm" onClick={() => onConfirm(item)}>
            保存副本
          </button>
        </React.Fragment>
      }
    >
      <p className="sk-dialog__note">
        从当前快照创建一份独立副本到私有技能库。这是一次复制,不会修改原技能,也不建立双向同步。
      </p>
    </SkDialog>
  );
}

function SkRevokedDialog({ item, onClose }) {
  return (
    <SkDialog
      icon="warning-circle"
      title="该技能已被撤销"
      sub={item.name}
      width={460}
      onClose={onClose}
      foot={
        <button type="button" className="m-btn m-btn--primary m-btn--sm" onClick={onClose}>
          知道了
        </button>
      }
    >
      <p className="sk-dialog__note">{item.executionBlockedReason}</p>
      <p className="sk-dialog__note">
        本地内容已保留,你可以查看或另存到技能库,但运行时会跳过执行,直到安装一个未被撤销的版本。
      </p>
    </SkDialog>
  );
}

// 创建 / 编辑本地技能表单对话框。
function SkCreateDialog({ onClose, onConfirm }) {
  const [cat, setCat] = React.useState(SK_CATEGORIES[0]);
  return (
    <SkDialog
      icon="note-pencil"
      title="创建本地技能"
      sub="本地创建的技能直接安装到当前小说"
      width={600}
      onClose={onClose}
      foot={
        <React.Fragment>
          <button type="button" className="m-btn m-btn--text m-btn--sm" onClick={onClose}>
            取消
          </button>
          <button type="button" className="m-btn m-btn--primary m-btn--sm" onClick={onConfirm}>
            创建并安装
          </button>
        </React.Fragment>
      }
    >
      <div className="sk-form-grid">
        <SkField label="名称">
          <input className="m-input" placeholder="技能名称" />
        </SkField>
        <SkField label="调用名" hint="本小说内唯一,小写字母与下划线">
          <input className="m-input" placeholder="expand_scene" spellCheck={false} />
        </SkField>
      </div>
      <SkField label="使用时机">
        <textarea className="m-input m-textarea" rows={2} placeholder="描述什么情况下应该调用这个技能…" />
      </SkField>
      <SkField label="描述">
        <textarea className="m-input m-textarea" rows={2} placeholder="一句话说明这个技能做什么…" />
      </SkField>
      <SkField label="类别">
        <div className="sk-chips">
          {SK_CATEGORIES.map((c) => (
            <button
              key={c}
              type="button"
              className={"m-chip" + (cat === c ? " m-chip--brass" : "")}
              onClick={() => setCat(c)}
            >
              {c}
            </button>
          ))}
        </div>
      </SkField>
      <SkField label="提示词">
        <textarea
          className="m-input m-textarea sk-form-prompt"
          rows={7}
          placeholder="描述这个技能的执行步骤与输出要求…"
        />
      </SkField>
    </SkDialog>
  );
}

/* ============================ hub ============================ */

const SK_TABS = [
  { id: "installed", label: "已安装" },
  { id: "library", label: "技能库" },
  { id: "official", label: "官方目录" },
  { id: "market", label: "市场" },
];

function SkillSetup({ novel }) {
  // 无 novel = Home 入口:技能库/官方目录/市场都是设备级来源,
  // 不含小说绑定的“已安装”;安装到具体小说仍在小说编辑器内完成。
  const home = !novel;
  const tabs = home ? SK_TABS.filter((t) => t.id !== "installed") : SK_TABS;
  const [tab, setTab] = React.useState(home ? "library" : "installed");
  const [installed, setInstalled] = React.useState(() => SK_INSTALLED.map((s) => ({ ...s })));
  const [dialog, setDialog] = React.useState(null); // {type, item}
  const [marketDetail, setMarketDetail] = React.useState(null);
  const [kebabOpen, setKebabOpen] = React.useState(null);
  const [query, setQuery] = React.useState("");
  const [catFilter, setCatFilter] = React.useState("全部");
  const [toast, setToast] = React.useState(null);

  const novelTitle = (novel && novel.title) || "无题";

  React.useEffect(() => {
    if (!toast) {
      return;
    }
    const t = setTimeout(() => setToast(null), 2200);
    return () => clearTimeout(t);
  }, [toast]);

  const flash = (msg) => setToast(msg);
  const closeDialog = () => setDialog(null);

  // 安装:命中已装同名 → 冲突对话框;否则直接安装。
  // Home 入口没有目标小说,提示到小说编辑器内安装。
  const install = (item) => {
    if (home) {
      flash("在小说编辑器内可将其安装到具体小说。");
      return;
    }
    const collide = installed.some((n) => n.name === item.name);
    if (collide) {
      setDialog({ type: "conflict", item });
    } else {
      addInstalled(item, item.name);
      flash(`已安装“${item.name}”。`);
    }
  };
  const addInstalled = (item, name) => {
    setInstalled((list) => [
      ...list,
      {
        id: "nas-" + Math.random().toString(36).slice(2, 7),
        callName: (name || item.name).toString(),
        sourceKind: item.author ? "marketplace" : item.publicId ? "official" : "library",
        sourceDisplayName: item.name,
        sourceVersion: item.version,
        name: item.name,
        enabled: true,
        sortOrder: list.length,
        category: item.category,
        tags: item.tags,
        description: item.description,
        whenToUse: item.whenToUse,
      },
    ]);
  };

  const onOverwrite = (item) => {
    setInstalled((list) => list.map((n) => (n.name === item.name ? { ...n, sourceDisplayName: item.name, sourceVersion: item.version } : n)));
    closeDialog();
    flash(`已覆盖“${item.name}”。`);
  };
  const onRename = (item, call) => {
    addInstalled(item, call);
    closeDialog();
    flash(`已以调用名 ${call} 安装。`);
  };

  const toggleEnabled = (id) =>
    setInstalled((list) => list.map((n) => (n.id === id ? { ...n, enabled: !n.enabled } : n)));

  const onRowAction = (action, item) => {
    setKebabOpen(null);
    if (action === "remove") {
      setInstalled((list) => list.filter((n) => n.id !== item.id));
      flash(`已移除“${item.name}”。`);
    } else if (action === "saveLib") {
      setDialog({ type: "saveLib", item });
    } else if (action === "revoked") {
      setDialog({ type: "revoked", item });
    } else if (action === "rename") {
      flash("重命名调用名(mock)。");
    }
  };

  const onUpgrade = (item) => setDialog({ type: "upgrade", item });
  const confirmUpgrade = (item) => {
    setInstalled((list) =>
      list.map((n) =>
        n.id === item.id ? { ...n, sourceVersion: item.upgradeVersion, upgradeVersion: undefined } : n
      )
    );
    closeDialog();
    flash(`已升级到 v${item.upgradeVersion}。`);
  };

  const confirmSaveLib = (item) => {
    closeDialog();
    flash(`已保存“${item.name}”到技能库。`);
  };
  const confirmCreate = () => {
    closeDialog();
    flash("已创建本地技能。");
  };

  const onTab = (id) => {
    setMarketDetail(null);
    setTab(id);
  };

  // 分类 + 搜索过滤(浏览类页面)。
  const applyFilter = (arr) => {
    const q = query.trim().toLowerCase();
    return arr.filter((it) => {
      if (catFilter !== "全部" && it.category !== catFilter) {
        return false;
      }
      if (!q) {
        return true;
      }
      return [it.name, it.description, it.author].some((s) => s && s.toLowerCase().includes(q));
    });
  };

  const showBrowseTools = tab === "library" || tab === "official" || (tab === "market" && !marketDetail);
  const counts = {
    installed: installed.length,
    library: SK_LIBRARY.length,
    official: SK_OFFICIAL.length,
    market: SK_MARKET.length,
  };

  return (
    <div className="sk-setup" onClick={() => kebabOpen && setKebabOpen(null)}>
      <header className="sk-setup__head">
        <span className="sk-setup__head-icon">
          <Icon name="stack" size={20} />
        </span>
        <div className="sk-setup__head-meta">
          <div className="sk-setup__title">{home ? "技能库" : "智能体技能"}</div>
          <div className="sk-setup__sub">
            {home
              ? "管理可复用的技能来源,可在任意小说中安装"
              : `为《${novelTitle}》安装并管理可执行技能`}
          </div>
        </div>
        {tab === "installed" && (
          <button
            type="button"
            className="m-btn m-btn--primary m-btn--sm"
            onClick={() => setDialog({ type: "create" })}
          >
            <Icon name="plus" size={14} />
            创建本地技能
          </button>
        )}
      </header>

      <nav className="sk-tabs">
        {tabs.map((t) => (
          <button
            key={t.id}
            type="button"
            className={"sk-tab" + (tab === t.id ? " is-active" : "")}
            onClick={() => onTab(t.id)}
          >
            {t.label}
            <span className="sk-tab__count">{counts[t.id]}</span>
          </button>
        ))}
      </nav>

      {showBrowseTools && (
        <div className="sk-toolbar">
          <div className="sk-search">
            <Icon name="magnifying-glass" size={13} style={{ opacity: 0.5 }} />
            <input
              className="sk-search__input"
              placeholder="搜索技能"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              spellCheck={false}
            />
          </div>
          <div className="sk-filter">
            <Icon name="funnel" size={13} style={{ opacity: 0.6 }} />
            {["全部", ...SK_CATEGORIES].map((c) => (
              <button
                key={c}
                type="button"
                className={"m-chip" + (catFilter === c ? " m-chip--brass" : "")}
                onClick={() => setCatFilter(c)}
              >
                {c}
              </button>
            ))}
          </div>
        </div>
      )}

      <div className="sk-body">
        {tab === "installed" && (
          <SkInstalledList
            items={installed}
            kebabOpen={kebabOpen}
            onToggle={toggleEnabled}
            onKebab={setKebabOpen}
            onAction={onRowAction}
            onUpgrade={onUpgrade}
            onCreate={() => setDialog({ type: "create" })}
          />
        )}

        {tab === "library" && (
          <div className="sk-grid">
            {applyFilter(SK_LIBRARY).map((it) => (
              <SkSourceCard
                key={it.id}
                item={it}
                badge={{ icon: "stack" }}
                onInstall={install}
              />
            ))}
          </div>
        )}

        {tab === "official" && (
          <div className="sk-grid">
            {applyFilter(SK_OFFICIAL).map((it) => (
              <SkSourceCard
                key={it.id}
                item={it}
                badge={{ icon: "seal-check" }}
                version={it.version}
                onInstall={install}
              />
            ))}
          </div>
        )}

        {tab === "market" &&
          (marketDetail ? (
            <SkMarketDetail
              item={marketDetail}
              onBack={() => setMarketDetail(null)}
              onInstall={install}
            />
          ) : (
            <div className="sk-grid">
              {applyFilter(SK_MARKET).map((it) => (
                <SkMarketCard key={it.id} item={it} onOpen={setMarketDetail} />
              ))}
            </div>
          ))}

      </div>

      {dialog && dialog.type === "conflict" && (
        <SkConflictDialog
          item={dialog.item}
          installed={installed}
          onClose={closeDialog}
          onOverwrite={onOverwrite}
          onRename={onRename}
        />
      )}
      {dialog && dialog.type === "upgrade" && (
        <SkUpgradeDialog item={dialog.item} onClose={closeDialog} onConfirm={confirmUpgrade} />
      )}
      {dialog && dialog.type === "saveLib" && (
        <SkSaveLibDialog item={dialog.item} onClose={closeDialog} onConfirm={confirmSaveLib} />
      )}
      {dialog && dialog.type === "revoked" && (
        <SkRevokedDialog item={dialog.item} onClose={closeDialog} />
      )}
      {dialog && dialog.type === "create" && (
        <SkCreateDialog onClose={closeDialog} onConfirm={confirmCreate} />
      )}

      {toast && (
        <div className="sk-toast">
          <Icon name="check-circle" size={15} />
          {toast}
        </div>
      )}
    </div>
  );
}

Object.assign(window, { SkillSetup });
