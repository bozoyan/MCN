// 新建 / 编辑作品 dialog —— 对齐 lib/desktop/widgets/novel_form_dialog.dart 当前实现
// （作品类型下拉 + 类型联动的来源小说），并修掉实现里的四处 UI 问题：
//   1. 封面列下方的死白：两栏到底，作品类型与来源小说下沉到封面下方填满左栏。
//   2. 来源小说紧跟作品类型，不再落在表单最末（和 mobile 的落点对齐）。
//   3. 「必填」不再用 accent 色，避免读成可点链接。
//   4. 分类补 placeholder，空态不再像个坏掉的框。
// 类型规则：默认原创；改编只在剧本里可选；来源小说的 label 和空值文案跟随类型。
// 作品库不再分小说 / 剧本两个入口，新建统一叫「新建作品」，小说还是剧本在标题旁切换。
// 切换不变形：两种类型的差异都落在固定槽位里 —— 顶部横幅换内容不增删，
// 计划集数和作者名同一行（小说时作者名占满这一行），作品名占位文案跟着变。
// 从小说卡片「改编为剧本」进来时仍走只读来源条 + 继承项，类型锁定为改编。

const NFD_TYPES = [
  { id: "original", label: "原创" },
  { id: "adaptation", label: "改编", screenplayOnly: true },
  { id: "sequel", label: "续作" },
  { id: "fanfic", label: "同人" },
  { id: "material", label: "资料" },
];

const NFD_TYPE_DERIVATIVE = { id: "derivative", label: "二创" };

// 新建时改编只给剧本；编辑时要能显示历史数据里的二创和跨类型的旧作品。
function nfdTypesFor(isScreenplay, editing) {
  if (editing) return [...NFD_TYPES.slice(0, 4), NFD_TYPE_DERIVATIVE, NFD_TYPES[4]];
  return NFD_TYPES.filter((type) => !type.screenplayOnly || isScreenplay);
}

// 来源小说的说法跟着类型走 —— 「改编自小说」比通用的「来源小说」讲得清关系。
const NFD_SOURCE_COPY = {
  adaptation: { label: "改编自小说", none: "未选择原著" },
  sequel: { label: "续写自小说", none: "未选择前作" },
  fanfic: { label: "同人原作", none: "未选择原作" },
  derivative: { label: "二创来源", none: "未选择来源" },
};

const NFD_SOURCE_NOVELS = ["夜航船", "山影渐落", "The Astronomer's Daughter", "枯木集"];

const NFD_CATEGORIES = ["历史", "文学", "悬疑", "科幻", "当代"];

const NFD_TAG_POOL = ["穿越", "脑洞", "快节奏", "热血", "群像", "悬疑"];

// 表单顶部的引导横幅是固定槽位：小说给「快速开书」，剧本给「从小说改编」，
// 同高同位，切换类型时只换内容，下面的表单不跟着上下跳。
function NfdStartBanner({ isScreenplay, onAdapt }) {
  const copy = isScreenplay
    ? { icon: "film-strip", title: "从小说改编", sub: "选一部小说，带着人物和设定开始写剧本。", onClick: onAdapt }
    : { icon: "sparkle", title: "快速开书", sub: "暂时还不知道写什么？和 AI 先聊聊吧。", onClick: undefined };
  return (
    <button type="button" className="m-nfd-quickstart" onClick={copy.onClick}>
      <Icon name={copy.icon} size={18} className="m-nfd-quickstart__spark" />
      <span className="m-nfd-quickstart__text">
        <strong>{copy.title}</strong>
        <small>{copy.sub}</small>
      </span>
      <Icon name="caret-right" size={16} color="var(--text-muted)" />
    </button>
  );
}

function NfdCoverPane({ editing, inherited }) {
  const hasCover = editing || inherited;
  return (
    <div className="m-nfd-cover">
      <span className="m-field__label">封面</span>
      <div
        className="m-nfd-cover__preview"
        style={hasCover ? { background: "linear-gradient(160deg, #3E524C 0%, #2D3A36 55%, #1C2623 100%)" } : undefined}
      >
        {!hasCover && (
          <span className="m-nfd-cover__empty">
            <Icon name="image-square" size={22} />
            <span>未选择封面</span>
          </span>
        )}
        {inherited && <span className="m-nfd-cover__inherited">沿用原作</span>}
      </div>
      <div className="m-nfd-cover__actions">
        <button type="button" className="m-btn m-btn--secondary m-btn--sm">
          <Icon name="image-square" size={14} />
          {hasCover ? "更换封面" : "选择封面"}
        </button>
      </div>
      {editing && (
        <div className="m-nfd-cover__actions">
          <button type="button" className="m-btn m-btn--secondary m-btn--sm m-nfd-cover__remove">
            <Icon name="x" size={13} />移除封面
          </button>
        </div>
      )}
    </div>
  );
}

function NfdField({ label, required, children }) {
  return (
    <div className="m-field">
      <span className="m-field__label">
        {label}
        {required && <em className="m-nfd-req">必填</em>}
      </span>
      {children}
    </div>
  );
}

function NfdTypeSelect({ value, onChange, types, locked }) {
  if (locked) {
    return (
      <div className="m-input m-input--locked">
        <span>改编</span>
        <Icon name="lock-simple" size={13} color="var(--text-subtle)" />
      </div>
    );
  }
  return (
    <div className="m-nfd-selectwrap">
      <Icon name="book" size={15} className="m-nfd-selectwrap__lead" />
      <select
        className="m-input m-nfd-select m-nfd-select--lead"
        value={value}
        onChange={(event) => onChange(event.target.value)}
      >
        {types.map((type) => <option key={type.id} value={type.id}>{type.label}</option>)}
      </select>
      <Icon name="caret-down" size={14} className="m-nfd-selectwrap__caret" />
    </div>
  );
}

function NfdSourceSelect({ value, onChange, noneLabel }) {
  return (
    <div className="m-nfd-selectwrap">
      <select
        className="m-input m-nfd-select"
        value={value}
        onChange={(event) => onChange(event.target.value)}
      >
        <option value="">{noneLabel}</option>
        {NFD_SOURCE_NOVELS.map((title) => <option key={title} value={title}>{title}</option>)}
      </select>
      <Icon name="caret-down" size={14} className="m-nfd-selectwrap__caret" />
    </div>
  );
}

function NfdCategoryInput() {
  return (
    <React.Fragment>
      <input className="m-input" list="nfd-categories" placeholder="如：都市、玄幻" />
      <datalist id="nfd-categories">
        {NFD_CATEGORIES.map((category) => <option key={category} value={category} />)}
      </datalist>
    </React.Fragment>
  );
}

function NfdTags({ tags, setTags }) {
  return (
    <div className="m-nfd-tags">
      {tags.map((tag) => (
        <span key={tag} className="m-nfd-tag">
          {tag}
          <button
            type="button"
            className="m-nfd-tag__x"
            aria-label={"移除 " + tag}
            onClick={() => setTags(tags.filter((item) => item !== tag))}
          >
            <Icon name="x" size={10} />
          </button>
        </span>
      ))}
      <button
        type="button"
        className="m-nfd-tag-add"
        onClick={() => {
          const next = NFD_TAG_POOL.find((tag) => !tags.includes(tag));
          if (next) setTags([...tags, next]);
        }}
      >
        <Icon name="plus" size={12} />添加标签
      </button>
    </div>
  );
}

function NfdSourceBar({ source, inherit, setInherit }) {
  const options = [
    { id: "characters", label: "人物档案", count: 12 },
    { id: "world", label: "世界观设定", count: 8 },
    { id: "outline", label: "大纲（转为节拍初稿）", count: 42 },
  ];
  return (
    <section className="m-nfd-source">
      <div className="m-nfd-source__head">
        <Icon name="git-fork" size={16} />
        <span className="m-nfd-source__title">改编自《{source.title}》</span>
        <span className="m-nfd-source__lock" title="来源创建后不可更改">
          <Icon name="lock-simple" size={13} color="var(--text-subtle)" />
        </span>
      </div>
      <div className="m-nfd-source__opts">
        {options.map((option) => {
          const on = inherit.has(option.id);
          return (
            <button
              key={option.id}
              type="button"
              role="checkbox"
              aria-checked={on}
              className={"m-nfd-inherit" + (on ? " is-on" : "")}
              onClick={() => setInherit((previous) => {
                const next = new Set(previous);
                if (next.has(option.id)) next.delete(option.id);
                else next.add(option.id);
                return next;
              })}
            >
              <span className="m-nfd-inherit__box">{on && <Icon name="check" size={11} />}</span>
              <span>{option.label}</span>
              <small>{option.count}</small>
            </button>
          );
        })}
      </div>
    </section>
  );
}

function NfdMoreToggle({ open, onToggle }) {
  return (
    <button
      type="button"
      className={"m-nfd-more" + (open ? " is-open" : "")}
      onClick={onToggle}
    >
      <Icon name="caret-right" size={14} className="m-nfd-more__caret" />
      更多信息
      <small>简介、分类、标签</small>
    </button>
  );
}

function NfdTweaks({ mode, setMode }) {
  const [open, setOpen] = React.useState(true);
  return (
    <div className="m-nfd-tweaks" onMouseDown={(event) => event.stopPropagation()}>
      <button type="button" className="m-nfd-tweaks__toggle" onClick={() => setOpen((on) => !on)}>
        <Icon name="faders" size={13} />Tweaks
      </button>
      {open && (
        <div className="m-nfd-tweaks__body">
          <div className="m-nfd-tweaks__row">
            <span className="m-nfd-tweaks__label">模式</span>
            <div className="m-nfd-tweaks__seg">
              <button type="button" className={mode === "create" ? "is-on" : ""} onClick={() => setMode("create")}>新建</button>
              <button type="button" className={mode === "edit" ? "is-on" : ""} onClick={() => setMode("edit")}>编辑</button>
            </div>
          </div>
          <p className="m-nfd-tweaks__note">
            两栏到底：作品类型与来源小说在封面下方，填满左栏。<br />
            默认原创（无来源）；改编只在剧本里可选；选到续作 / 同人会在类型下方带出来源，文案跟着类型变。
          </p>
        </div>
      )}
    </div>
  );
}

function NovelFormDialog({ kind = "novel", source = null, onClose, onCreated }) {
  const adapting = !!source;
  const [workKind, setWorkKind] = React.useState(adapting ? "screenplay" : kind);
  const isScreenplay = workKind === "screenplay";
  // ?mode=edit / ?more=off / ?type=sequel 可直接落到某一态，方便单独看这一屏。
  const params = new URLSearchParams(window.location.search);
  const [mode, setMode] = React.useState(params.get("mode") === "edit" ? "edit" : "create");
  const [title, setTitle] = React.useState(adapting ? source.title : "");
  const [author, setAuthor] = React.useState("怀素");
  const [episodes, setEpisodes] = React.useState("");
  const [type, setType] = React.useState(adapting ? "adaptation" : (params.get("type") || "original"));
  const [sourceNovel, setSourceNovel] = React.useState("");
  const [tags, setTags] = React.useState(["穿越", "脑洞"]);
  const [more, setMore] = React.useState(params.get("more") !== "off");
  const [inherit, setInherit] = React.useState(new Set(["characters", "world"]));

  const editing = mode === "edit";
  const types = nfdTypesFor(isScreenplay, editing);
  const sourceCopy = NFD_SOURCE_COPY[type];
  const showSource = !adapting && !!sourceCopy;

  React.useEffect(() => {
    function onKeyDown(event) {
      if (event.key === "Escape") onClose();
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [onClose]);

  const heading = editing ? "编辑作品" : adapting ? "改编为剧本" : "新建作品";
  const pickKind = !editing && !adapting;

  // 切回小说时改编不可选，落回原创。
  function handleKind(next) {
    setWorkKind(next);
    if (next === "novel" && type === "adaptation") handleType("original");
  }

  function handleType(next) {
    setType(next);
    if (!NFD_SOURCE_COPY[next]) setSourceNovel("");
  }

  return (
    <div
      className="m-dialog-scrim"
      onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}
    >
      <NfdTweaks mode={mode} setMode={setMode} />
      <div
        className="m-dialog m-dialog--nfd"
        role="dialog"
        aria-modal="true"
        aria-labelledby="nfd-title"
        data-screen-label={heading}
      >
        <header className="m-nfd-head">
          <h2 id="nfd-title" className="m-nfd-head__title">{heading}</h2>
          {pickKind && (
            <div className="m-segmented m-nfd-head__kind" role="tablist" aria-label="小说或剧本">
              {[["novel", "book-open", "小说"], ["screenplay", "film-strip", "剧本"]].map(([key, icon, label]) => (
                <button key={key} type="button" role="tab" aria-selected={workKind === key}
                  className={"m-segmented__item" + (workKind === key ? " is-active" : "")}
                  onClick={() => handleKind(key)}>
                  <Icon name={icon} size={14} />{label}
                </button>
              ))}
            </div>
          )}
          <button type="button" className="m-icon-btn" aria-label="关闭" onClick={onClose}>
            <Icon name="x" size={16} />
          </button>
        </header>

        <main className="m-nfd-body">
          <div className="m-nfd-step">
            {!editing && !adapting && (
              <NfdStartBanner isScreenplay={isScreenplay} onAdapt={() => { handleType("adaptation"); setMore(true); }} />
            )}
            {adapting && <NfdSourceBar source={source} inherit={inherit} setInherit={setInherit} />}

            <div className="m-nfd-form">
              <div className="m-nfd-aside">
                <NfdCoverPane editing={editing} inherited={adapting} />
                {/* 类型 / 来源同属「更多信息」，跟着一起收起，否则收起态左栏会比右栏高出一大截 */}
                {more && (
                  <div className="m-nfd-aside__meta">
                    <NfdField label="作品类型">
                      <NfdTypeSelect value={type} onChange={handleType} types={types} locked={adapting} />
                    </NfdField>
                    {showSource && (
                      <NfdField label={sourceCopy.label}>
                        <NfdSourceSelect value={sourceNovel} onChange={setSourceNovel} noneLabel={sourceCopy.none} />
                      </NfdField>
                    )}
                  </div>
                )}
              </div>

              <div className="m-nfd-fields">
                <NfdField label="作品名称" required>
                  <input
                    className="m-input"
                    value={title}
                    onChange={(event) => setTitle(event.target.value)}
                    placeholder={isScreenplay ? "剧名" : "书名"}
                    autoFocus
                  />
                </NfdField>

                {isScreenplay && !editing ? (
                  <div className="m-nfd-row">
                    <NfdField label="作者名">
                      <input className="m-input" value={author} onChange={(event) => setAuthor(event.target.value)} />
                    </NfdField>
                    <NfdField label="计划集数">
                      <input
                        className="m-input"
                        value={episodes}
                        onChange={(event) => setEpisodes(event.target.value.replace(/\D/g, ""))}
                        placeholder="例如 8"
                        inputMode="numeric"
                      />
                    </NfdField>
                  </div>
                ) : (
                  <NfdField label="作者名">
                    <input className="m-input" value={author} onChange={(event) => setAuthor(event.target.value)} />
                  </NfdField>
                )}

                <NfdMoreToggle open={more} onToggle={() => setMore((open) => !open)} />

                {more && (
                  <div className="m-nfd-more__body">
                    <NfdField label="简介描述">
                      <textarea className="m-input m-input--area" rows={3} placeholder="一句话说清这本书讲什么" />
                    </NfdField>
                    <NfdField label="分类">
                      <NfdCategoryInput />
                    </NfdField>
                    <NfdField label="标签">
                      <NfdTags tags={tags} setTags={setTags} />
                    </NfdField>
                  </div>
                )}
              </div>
            </div>
          </div>
        </main>

        <footer className="m-nfd-foot">
          <button type="button" className="m-btn m-btn--text" onClick={onClose}>取消</button>
          <button
            type="button"
            className="m-btn m-btn--primary"
            disabled={!title.trim()}
            onClick={() => onCreated(workKind)}
          >
            {editing ? "保存" : "创建并开始写"}
            {!editing && <Icon name="arrow-right" size={14} />}
          </button>
        </footer>
      </div>
    </div>
  );
}

Object.assign(window, { NovelFormDialog });
