// 作品库：统一集合导航 + 网格。状态都在 LibraryView.jsx 里（样式见 library_collections.css），
// 这里只接 props、回调出去。NovelCover / StatusPill / WorkStats / workKindOf
// 来自 LibraryView.jsx 的顶层声明（Babel 非 module 脚本共享全局作用域）。
//
// 方案：docs/solutions/library-collections-and-filters.md 第 6 节。
//   · 全部 / 创作中 / 已完本 / 用户集合是同一层标签，全部固定第一；
//   · 标签和工具在同一行：左边集合，右边 搜索 · 分类 · 排序 · 草稿；
//   · 集合操作走右键（重命名 / 左移 / 右移 / 删除），全部不响应；标签可直接拖动排序；
//   · 作品归类走卡片菜单「加入集合」，没有多选。

// 状态徽标 —— HomeNovelStatusBadge：筹备/连载都归「创作中」，完结是「已完本」。
const CO_STATUS = {
  planning: { key: "active", label: "创作中", icon: "pencil-simple" },
  writing: { key: "active", label: "创作中", icon: "pencil-simple" },
  completed: { key: "finished", label: "已完本", icon: "check-circle" },
};
const coStatusOf = (novel) => CO_STATUS[novel.status] || CO_STATUS.writing;

// homeNovelWordCountLabel：一律以万字计，保留一位小数、去掉 .0 —— 不足一万就是「0 万字」。
const coWordsLabel = (words) => `${Number((words / 10000).toFixed(1))} 万字`;

const isManual = (collection) => !collection.builtin && !collection.rule;

// 集合的作品：全部 = 作品库所有作品（小说和剧本都在）；条件集合按规则现算；手动集合取成员。
function collectionWorks(collection, scoped) {
  if (collection.builtin) return scoped;
  if (collection.rule) return scoped.filter((novel) => coStatusOf(novel).key === collection.rule.status);
  return collection.workIds.map((id) => scoped.find((novel) => novel.id === id)).filter(Boolean);
}

// 一组作品在某个手动集合里的归属：全在 → checked，部分在 → mixed，都不在 → none。
function membershipOf(collection, workIds) {
  const hits = workIds.filter((id) => collection.workIds.includes(id)).length;
  if (hits === 0) return "none";
  return hits === workIds.length ? "checked" : "mixed";
}

function CoCheckbox({ state, disabled, onClick }) {
  const checked = state === "checked" || state === true;
  const mixed = state === "mixed";
  return (
    <span
      role="checkbox"
      aria-checked={mixed ? "mixed" : checked}
      className={"m-co-checkbox" + (checked || mixed ? " is-checked" : "") + (disabled ? " is-disabled" : "")}
      onClick={onClick}
    >
      {mixed ? <span className="m-co-checkbox__mixed" /> : checked ? <Icon name="check" size={12} /> : null}
    </span>
  );
}

// 勾选即生效的手动集合列表：勾一下就加入，再点一下就移出。条件集合不在这里 —— 它们的成员不能手动改。
function CollectionChecklist({ collections, workIds, onToggle, onCreate }) {
  const [creating, setCreating] = React.useState(false);
  const [name, setName] = React.useState("");
  const submit = () => {
    const trimmed = name.trim();
    if (!trimmed) return setCreating(false);
    onCreate(trimmed, workIds);
    setName("");
    setCreating(false);
  };
  return (
    <div className="m-co-check">
      {collections.length > 0 && (
        <div className="m-co-check__list">
          {collections.map((collection) => {
            const state = membershipOf(collection, workIds);
            return (
              <button
                key={collection.id}
                type="button"
                className="m-co-check__row"
                onClick={(event) => { event.stopPropagation(); onToggle(collection.id, workIds, state); }}
              >
                <CoCheckbox state={state} />
                <span className="m-co-check__name">{collection.name}</span>
              </button>
            );
          })}
        </div>
      )}
      {collections.length > 0 && <div className="m-workmenu__sep" />}
      {creating ? (
        <div className="m-co-check__new" onClick={(event) => event.stopPropagation()}>
          <input
            autoFocus
            className="m-input m-co-check__input"
            placeholder="集合名称"
            value={name}
            onChange={(event) => setName(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter") submit();
              if (event.key === "Escape") setCreating(false);
            }}
          />
          <button type="button" className="m-btn m-btn--primary m-btn--sm" onClick={submit}>创建</button>
        </div>
      ) : (
        <button
          type="button"
          className="m-co-check__row m-co-check__row--add"
          onClick={(event) => { event.stopPropagation(); setCreating(true); }}
        >
          <Icon name="plus" size={14} />
          <span className="m-co-check__name">新建集合</span>
        </button>
      )}
    </div>
  );
}

// 对齐 lib/desktop/widgets/novel_list.dart _showNovelActionsMenu：
// 编辑 / 阅读 / 改编 / 导出 / 加入集合 ─ 完结 / 归档 / 废弃 ─ 删除。
// 在手动集合里多一条「移出「X」」。点「加入集合」菜单原地换成勾选列表，带返回。
function CoWorkMenu({ novel, collections, inCollection, initialPage, onToggle, onCreate, onRemoveFromCurrent, onAdapt }) {
  const [open, setOpen] = React.useState(Boolean(initialPage));
  const [page, setPage] = React.useState(initialPage || "root");
  const close = () => { setOpen(false); setPage("root"); };
  const stop = (fn) => (event) => { event.stopPropagation(); fn(); };
  const finished = novel.status === "completed";
  const isNovel = workKindOf(novel) === "novel";
  return (
    <div className={"m-workmenu m-co-cardmenu" + (open ? " is-open" : "")}>
      <button
        className="m-co-cardmenu__btn"
        title="更多"
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={stop(() => (open ? close() : setOpen(true)))}
      >
        <Icon name="dots-three-vertical" size={16} />
      </button>
      {open && (
        <React.Fragment>
          <div className="m-workmenu__backdrop" onClick={stop(close)} />
          {page === "root" ? (
            <div className="m-workmenu__menu" role="menu">
              <button type="button" role="menuitem" onClick={stop(close)}><Icon name="pencil-simple" size={14} />编辑</button>
              {isNovel && <button type="button" role="menuitem" onClick={stop(close)}><Icon name="book-open" size={14} />阅读</button>}
              {isNovel && <button type="button" role="menuitem" onClick={stop(() => { close(); onAdapt(novel); })}><Icon name="film-strip" size={14} />改编</button>}
              <button type="button" role="menuitem" onClick={stop(close)}><Icon name="download-simple" size={14} />导出</button>
              <button type="button" role="menuitem" className="m-co-menu__sub" onClick={stop(() => setPage("collections"))}>
                <Icon name="stack" size={14} />
                <span className="m-co-menu__grow">加入集合</span>
                <Icon name="caret-right" size={14} />
              </button>
              {inCollection && (
                <button type="button" role="menuitem" onClick={stop(() => { close(); onRemoveFromCurrent(novel.id); })}>
                  <Icon name="minus" size={14} />移出「{inCollection.name}」
                </button>
              )}
              <div className="m-workmenu__sep" />
              {finished ? (
                <button type="button" role="menuitem" onClick={stop(close)}><Icon name="play" size={14} />恢复</button>
              ) : (
                <React.Fragment>
                  <button type="button" role="menuitem" onClick={stop(close)}><Icon name="check-circle" size={14} />完结</button>
                  <button type="button" role="menuitem" onClick={stop(close)}><Icon name="package" size={14} />归档</button>
                  <button type="button" role="menuitem" onClick={stop(close)}><Icon name="x-circle" size={14} />废弃</button>
                </React.Fragment>
              )}
              <div className="m-workmenu__sep" />
              <button type="button" role="menuitem" className="is-danger" onClick={stop(close)}><Icon name="trash" size={14} />删除</button>
            </div>
          ) : (
            <div className="m-workmenu__menu m-co-menu__panel" role="menu" onClick={(event) => event.stopPropagation()}>
              <button type="button" className="m-co-menu__back" onClick={stop(() => setPage("root"))}>
                <Icon name="caret-left" size={14} />
                <span>加入集合</span>
              </button>
              <CollectionChecklist collections={collections} workIds={[novel.id]} onToggle={onToggle} onCreate={onCreate} />
            </div>
          )}
        </React.Fragment>
      )}
    </div>
  );
}

// 没封面时是灰底占位：小说用书本，剧本用胶片（Flutter 里是 menu_book / movie）。
function WorkCoverImage({ novel, className = "" }) {
  return novel.coverImage ? (
    <div className={"m-co-wcover " + className} style={{ backgroundImage: `url(${novel.coverImage})` }} />
  ) : (
    <div className={"m-co-wcover m-co-wcover--empty " + className}>
      <Icon name={workKindOf(novel) === "screenplay" ? "film-strip" : "book-open"} size={40} />
    </div>
  );
}

// 作品卡 —— 对齐 _NovelCard：竖版封面撑满，左上状态徽标，右上「⋮」悬停才出现；
// 下方 标题 / 类型 / 字数 / 更新时间 / 至多两个标签。
// 小说和剧本混在一个网格里，剧本在类型那一行前面多一个胶片标记；小说是默认类型，不加标记。
function CoNovelCard({ novel, onOpen, menu }) {
  const status = coStatusOf(novel);
  const isScreenplay = workKindOf(novel) === "screenplay";
  return (
    <article className="m-co-wcard" onClick={() => onOpen(novel)} role="button" tabIndex={0}>
      <div className="m-co-wcard__cover">
        <WorkCoverImage novel={novel} />
        <span className={`m-co-badge m-co-badge--${status.key}`}><Icon name={status.icon} size={12} />{status.label}</span>
      </div>
      {menu}
      <div className="m-co-wcard__body">
        <div className="m-co-wcard__title">{novel.title}</div>
        <div className="m-co-wcard__type">
          {isScreenplay && <span className="m-co-kind"><Icon name="film-strip" size={11} />剧本</span>}
          {novel.workType || "原创"}
        </div>
        {/* 剧本不显示字数：季 / 集 / 场才是它的计量单位，这一行换成简介。 */}
        <div className="m-co-wcard__words">{isScreenplay ? novel.description : coWordsLabel(novel.words)}</div>
        <div className="m-co-wcard__time">{novel.updated}</div>
        <div className="m-co-wcard__tags">
          {novel.tags.slice(0, 2).map((tag) => <span key={tag} className="m-co-wcard__tag">{tag}</span>)}
        </div>
      </div>
    </article>
  );
}

// 网格末尾的「新建」虚线卡 —— _CreateNovelCard，只在「全部」里出现。类型在新建对话框里选。
function CoCreateCard({ onCreate }) {
  return (
    <button type="button" className="m-co-wcard m-co-wcard--create" onClick={onCreate}>
      <span className="m-create-icon"><Icon name="plus" size={22} /></span>
      <span className="m-co-wcard__create-title">新建作品</span>
      <span className="m-co-wcard__create-sub">小说或剧本<br />从一个想法开始</span>
    </button>
  );
}

// SliverGridDelegateWithMaxCrossAxisExtent 的 CSS 版：列数 = ceil((宽 + 间距) / (上限 + 间距))。
function useMaxExtentColumns(maxExtent = 180, gap = 16) {
  const ref = React.useRef(null);
  const [columns, setColumns] = React.useState(5);
  React.useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return undefined;
    const update = () => {
      const style = getComputedStyle(el);
      const width = el.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
      setColumns(Math.max(1, Math.ceil((width + gap) / (maxExtent + gap))));
    };
    update();
    const observer = new ResizeObserver(update);
    observer.observe(el);
    return () => observer.disconnect();
  }, [maxExtent, gap]);
  return [ref, columns];
}

function useWidth() {
  const ref = React.useRef(null);
  const [width, setWidth] = React.useState(0);
  React.useLayoutEffect(() => {
    const observer = new ResizeObserver(([entry]) => setWidth(entry.contentRect.width));
    observer.observe(ref.current);
    return () => observer.disconnect();
  }, []);
  return [ref, width];
}

// ---- 集合导航 ----

function CollectionTab({ collection, count, active, dropSide, dragProps, onSelect, onContextMenu }) {
  return (
    <button
      type="button"
      data-collection={collection.id}
      className={"m-cnav__tab" + (active ? " is-active" : "") + (dropSide ? ` is-drop-${dropSide}` : "")}
      onClick={() => onSelect(collection.id)}
      onContextMenu={(event) => onContextMenu(event, collection)}
      {...dragProps}
    >
      <span className="m-cnav__name">{collection.name}</span>
      <span className="m-cnav__count">{count}</span>
    </button>
  );
}

// 右键菜单：落在指针处。全部不弹。
function CollectionContextMenu({ menu, collections, onClose, onRename, onMove, onDelete }) {
  const index = collections.findIndex((collection) => collection.id === menu.id);
  const collection = collections[index];
  const act = (fn) => () => { onClose(); fn(); };
  return (
    <React.Fragment>
      <div className="m-workmenu__backdrop" onClick={onClose} onContextMenu={(event) => { event.preventDefault(); onClose(); }} />
      <div className="m-workmenu__menu m-cnav__ctx" role="menu" style={{ left: menu.x, top: menu.y }}>
        <button type="button" role="menuitem" onClick={act(() => onRename(collection))}><Icon name="pencil-simple" size={14} />重命名</button>
        <button type="button" role="menuitem" disabled={index <= 1} onClick={act(() => onMove(collection.id, index - 1))}><Icon name="arrow-left" size={14} />左移</button>
        <button type="button" role="menuitem" disabled={index >= collections.length - 1} onClick={act(() => onMove(collection.id, index + 1))}><Icon name="arrow-right" size={14} />右移</button>
        <div className="m-workmenu__sep" />
        <button type="button" role="menuitem" className="is-danger" onClick={act(() => onDelete(collection))}><Icon name="trash" size={14} />删除集合</button>
      </div>
    </React.Fragment>
  );
}

// 深链 ?cmenu=<集合 id> 让该标签的右键菜单一打开就展开（截图用）。
const CNAV_QS = new URLSearchParams(window.location.search);
const MORE_WIDTH = 84;
const ADD_WIDTH = 36;
const TAB_GAP = 4;

// 一行集合标签：先量出每个标签的真实宽度，放不下的收进「更多」；当前集合总是可见 ——
// 它若落在溢出里，就顶掉最后一个可见位。拖动只在可见标签之间进行，全部不能拖、也不能被放到它前面。
function CollectionNav({ collections, counts, currentId, onSelect, onCreate, onRename, onMove, onDelete }) {
  const wrapRef = React.useRef(null);
  const measureRef = React.useRef(null);
  const [fit, setFit] = React.useState(collections.length);
  const [moreOpen, setMoreOpen] = React.useState(false);
  const [menu, setMenu] = React.useState(null);
  const [drag, setDrag] = React.useState(null); // { id, over, side }

  React.useLayoutEffect(() => {
    const measure = () => {
      const wrap = wrapRef.current;
      const widths = [...measureRef.current.children].map((el) => el.offsetWidth);
      const available = wrap.clientWidth - ADD_WIDTH;
      const total = widths.reduce((sum, w, i) => sum + w + (i ? TAB_GAP : 0), 0);
      if (total <= available) return setFit(widths.length);
      let used = MORE_WIDTH;
      let count = 0;
      for (const w of widths) {
        if (used + w + TAB_GAP > available) break;
        used += w + TAB_GAP;
        count += 1;
      }
      setFit(Math.max(1, count));
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(wrapRef.current);
    return () => observer.disconnect();
  }, [collections, counts]);

  React.useLayoutEffect(() => {
    const id = CNAV_QS.get("cmenu");
    if (!id) return;
    const el = wrapRef.current.querySelector(`[data-collection="${id}"]`);
    if (!el) return;
    const rect = el.getBoundingClientRect();
    setMenu({ id, x: rect.left + 12, y: rect.bottom + 4 });
  }, []);

  let visible = collections.slice(0, fit);
  if (fit < collections.length && !visible.some((c) => c.id === currentId)) {
    const current = collections.find((c) => c.id === currentId);
    if (current) visible = [...visible.slice(0, -1), current];
  }
  const hidden = collections.filter((c) => !visible.includes(c));

  const openMenu = (event, collection) => {
    event.preventDefault();
    if (collection.builtin) return;
    setMoreOpen(false);
    setMenu({ id: collection.id, x: event.clientX, y: event.clientY });
  };

  const dragProps = (collection) => {
    if (collection.builtin) {
      return { onDragOver: (event) => event.preventDefault() };
    }
    return {
      draggable: true,
      onDragStart: (event) => { event.dataTransfer.effectAllowed = "move"; setDrag({ id: collection.id }); },
      onDragEnd: () => setDrag(null),
      onDragOver: (event) => {
        event.preventDefault();
        if (!drag || drag.id === collection.id) return;
        const rect = event.currentTarget.getBoundingClientRect();
        const side = event.clientX < rect.left + rect.width / 2 ? "before" : "after";
        if (drag.over !== collection.id || drag.side !== side) setDrag({ ...drag, over: collection.id, side });
      },
      onDrop: (event) => {
        event.preventDefault();
        if (!drag || !drag.over) return setDrag(null);
        const ids = collections.map((c) => c.id).filter((id) => id !== drag.id);
        let to = ids.indexOf(drag.over) + (drag.side === "after" ? 1 : 0);
        onMove(drag.id, Math.max(1, to));
        setDrag(null);
      },
    };
  };

  return (
    <nav className="m-cnav" ref={wrapRef} aria-label="集合">
      <div className="m-cnav__measure" ref={measureRef} aria-hidden="true">
        {collections.map((c) => (
          <span key={c.id} className="m-cnav__tab"><span className="m-cnav__name">{c.name}</span><span className="m-cnav__count">{counts[c.id]}</span></span>
        ))}
      </div>
      {visible.map((collection) => (
        <CollectionTab
          key={collection.id}
          collection={collection}
          count={counts[collection.id]}
          active={collection.id === currentId}
          dropSide={drag && drag.over === collection.id ? drag.side : null}
          dragProps={dragProps(collection)}
          onSelect={onSelect}
          onContextMenu={openMenu}
        />
      ))}
      {hidden.length > 0 && (
        <div className="m-workmenu">
          <button type="button" className={"m-cnav__tab m-cnav__more" + (moreOpen ? " is-open" : "")} onClick={() => setMoreOpen((v) => !v)}>
            更多<span className="m-cnav__count">{hidden.length}</span><Icon name="caret-down" size={12} />
          </button>
          {moreOpen && (
            <React.Fragment>
              <div className="m-workmenu__backdrop" onClick={() => setMoreOpen(false)} />
              <div className="m-workmenu__menu m-cnav__overflow" role="menu">
                {hidden.map((collection) => (
                  <button
                    key={collection.id}
                    type="button"
                    role="menuitem"
                    onClick={() => { setMoreOpen(false); onSelect(collection.id); }}
                    onContextMenu={(event) => openMenu(event, collection)}
                  >
                    <span className="m-co-menu__grow">{collection.name}</span>
                    <span className="m-cnav__count">{counts[collection.id]}</span>
                  </button>
                ))}
              </div>
            </React.Fragment>
          )}
        </div>
      )}
      <button type="button" className="m-cnav__add" title="新建集合" onClick={onCreate}><Icon name="plus" size={14} /></button>
      {menu && (
        <CollectionContextMenu
          menu={menu}
          collections={collections}
          onClose={() => setMenu(null)}
          onRename={onRename}
          onMove={onMove}
          onDelete={onDelete}
        />
      )}
    </nav>
  );
}

// ---- 右侧工具 ----

// 工具栏下拉：选中非默认项时整颗高亮，这就是筛选生效的提示，不另起一行标记。
function ToolMenu({ label, active, title, items }) {
  const [open, setOpen] = React.useState(false);
  return (
    <div className="m-workmenu">
      <button type="button" className={"m-tool m-libbar__menu" + (active ? " m-co-tool--on" : "")} title={title} onClick={() => setOpen((v) => !v)}>
        <span className="m-libbar__menu-label">{label}</span><Icon name="caret-down" size={12} />
      </button>
      {open && (
        <React.Fragment>
          <div className="m-workmenu__backdrop" onClick={() => setOpen(false)} />
          <div className="m-workmenu__menu" role="menu">
            {items.map((item, index) => item === "sep" ? (
              <div key={index} className="m-workmenu__sep" />
            ) : (
              <button key={item.key} type="button" role="menuitemradio" aria-checked={item.selected} className={item.selected ? "is-selected" : ""} onClick={() => { setOpen(false); item.onSelect(); }}>
                <span className="m-co-menu__grow">{item.label}</span>
                {item.count != null && <span className="m-cnav__count">{item.count}</span>}
                <span className="m-libbar__check">{item.selected && <Icon name="check" size={14} />}</span>
              </button>
            ))}
          </div>
        </React.Fragment>
      )}
    </div>
  );
}

// 搜索：宽的时候常驻输入框；窄了收成图标，点开或有内容时展开。
function WorksSearch({ value, onChange, compact, placeholder }) {
  const [open, setOpen] = React.useState(false);
  const expanded = !compact || open || value;
  if (!expanded) {
    return <button type="button" className="m-tool m-co-tool--icon" title="搜索" onClick={() => setOpen(true)}><Icon name="magnifying-glass" size={16} /></button>;
  }
  return (
    <label className={"m-libsearch" + (value ? " is-active" : "")}>
      <Icon name="magnifying-glass" size={14} />
      <input
        autoFocus={compact && open}
        value={value}
        placeholder={placeholder}
        onChange={(event) => onChange(event.target.value)}
        onBlur={() => setOpen(false)}
        onKeyDown={(event) => { if (event.key === "Escape") { onChange(""); setOpen(false); } }}
        spellCheck={false}
      />
      {value && <button type="button" className="m-libsearch__clear" title="清除搜索" onMouseDown={(event) => event.preventDefault()} onClick={() => onChange("")}><Icon name="x" size={12} /></button>}
    </label>
  );
}

function CollectionEmpty({ onAddWorks }) {
  return (
    <div className="m-sp-empty">
      <span className="m-sp-empty__icon"><Icon name="stack" size={26} /></span>
      <h3>集合里还没有作品</h3>
      {onAddWorks && <button type="button" className="m-btn m-btn--primary m-btn--sm" onClick={onAddWorks}><Icon name="plus" size={14} />添加作品</button>}
    </div>
  );
}

function NameDialog({ title, initial = "", confirmLabel, onClose, onSubmit }) {
  const [name, setName] = React.useState(initial);
  const trimmed = name.trim();
  return (
    <div className="m-dialog-scrim" onClick={onClose}>
      <div className="m-dialog m-dialog--task" onClick={(event) => event.stopPropagation()}>
        <div className="m-dialog__head"><span className="m-co-dialog__title">{title}</span></div>
        <div className="m-taskform">
          <label className="m-field">
            <span className="m-field__label">名称</span>
            <input
              autoFocus
              className="m-input"
              value={name}
              placeholder="如：江南系列、投稿中"
              onChange={(event) => setName(event.target.value)}
              onKeyDown={(event) => { if (event.key === "Enter" && trimmed) onSubmit(trimmed); }}
            />
          </label>
          <div className="m-taskform__actions">
            <button type="button" className="m-btn m-btn--secondary m-btn--sm" onClick={onClose}>取消</button>
            <button type="button" className="m-btn m-btn--primary m-btn--sm" disabled={!trimmed} onClick={() => onSubmit(trimmed)}>{confirmLabel}</button>
          </div>
        </div>
      </div>
    </div>
  );
}

function CollectionDeleteDialog({ collection, count, onClose, onConfirm }) {
  return (
    <div className="m-dialog-scrim" onClick={onClose}>
      <div className="m-dialog m-dialog--confirm" onClick={(event) => event.stopPropagation()}>
        <div className="m-taskform">
          <span className="m-co-dialog__title">删除集合「{collection.name}」？</span>
          <p className="m-co-dialog__text">集合里的 {count} 部作品不会被删除。</p>
          <div className="m-taskform__actions">
            <button type="button" className="m-btn m-btn--secondary m-btn--sm" onClick={onClose}>取消</button>
            <button type="button" className="m-btn m-btn--danger m-btn--sm" onClick={onConfirm}>删除</button>
          </div>
        </div>
      </div>
    </div>
  );
}

// 空手动集合的「添加作品」：从当前类型的全部作品里挑。
function WorkPickerDialog({ collection, novels, onClose, onAdd }) {
  const [query, setQuery] = React.useState("");
  const [picked, setPicked] = React.useState([]);
  const normalized = query.trim().toLowerCase();
  const visible = novels.filter((novel) => !normalized || [novel.title, novel.subtitle].join(" ").toLowerCase().includes(normalized));
  const toggle = (id) => setPicked((list) => (list.includes(id) ? list.filter((item) => item !== id) : [...list, id]));
  return (
    <div className="m-dialog-scrim" onClick={onClose}>
      <div className="m-dialog m-co-picker" onClick={(event) => event.stopPropagation()}>
        <div className="m-dialog__head">
          <span className="m-co-dialog__title">添加作品到「{collection.name}」</span>
          <button type="button" className="m-icon-btn m-icon-btn--ghost" onClick={onClose}><Icon name="x" size={16} /></button>
        </div>
        <div className="m-co-picker__search">
          <Icon name="magnifying-glass" size={16} />
          <input autoFocus placeholder="搜索作品…" value={query} onChange={(event) => setQuery(event.target.value)} />
        </div>
        <div className="m-co-picker__list">
          {visible.map((novel) => (
            <button
              key={novel.id}
              type="button"
              className={"m-co-picker__row" + (picked.includes(novel.id) ? " is-picked" : "")}
              onClick={() => toggle(novel.id)}
            >
              <CoCheckbox state={picked.includes(novel.id)} />
              <NovelCover novel={novel} className="m-cover m-row__cover m-co-picker__cover" />
              <span className="m-co-picker__body">
                <span className="m-co-picker__title">{novel.title}</span>
                <span className="m-co-picker__meta"><StatusPill status={novel.status} /><WorkStats novel={novel} /></span>
              </span>
              <span className="m-co-picker__updated">{novel.updated}</span>
            </button>
          ))}
          {!visible.length && <div className="m-home-empty"><Icon name="magnifying-glass" size={22} /><span>没有找到匹配的作品</span></div>}
        </div>
        <div className="m-co-picker__foot">
          <span className="m-co-picker__picked">{picked.length ? `已选 ${picked.length} 部` : ""}</span>
          <button type="button" className="m-btn m-btn--secondary m-btn--sm" onClick={onClose}>取消</button>
          <button type="button" className="m-btn m-btn--primary m-btn--sm" disabled={!picked.length} onClick={() => onAdd(picked)}>添加</button>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, {
  coStatusOf, isManual, collectionWorks, membershipOf, CoCheckbox, CollectionChecklist, CoWorkMenu,
  CoNovelCard, CoCreateCard, useMaxExtentColumns, useWidth, CollectionNav, ToolMenu, WorksSearch,
  CollectionEmpty, NameDialog, CollectionDeleteDialog, WorkPickerDialog,
});
