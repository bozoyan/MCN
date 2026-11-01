// Desktop works home — 小说和剧本同在一个作品库：问候 + 操作、继续写（上次停下的位置 +
// 最近几部）、公告、作品区（集合 · 搜索 · 类型 · 分类 · 排序 · 草稿）。
//
// 类型是作品的属性，不再是导航：剧本在卡片上带标记，作品区按类型筛选；
// 统计口径仍按类型走 —— 小说是「章 · 字数」，剧本是「季 · 集 · 场」。
// 首页不放今日目标、待办、建议这类仪表盘内容，第一屏只回答「接着写哪儿」。

const COVER_BG = {
  ink: { bg: "linear-gradient(160deg, #3E524C 0%, #2D3A36 55%, #1C2623 100%)", motif: "M40,220 Q120,140 200,180 T380,160" },
  mountains: { bg: "linear-gradient(180deg, #CDD6DB 0%, #7E8D99 60%, #3A4551 100%)", motif: "M20,260 L120,140 L180,200 L260,100 L380,260 Z" },
  stars: { bg: "linear-gradient(180deg, #2B2834 0%, #4B4558 100%)", motif: null },
  tree: { bg: "linear-gradient(160deg, #D3E0DA 0%, #6F9D8D 60%, #2E6656 100%)", motif: "M205,250 C185,175 225,120 200,40 M203,135 L145,90 M203,155 L270,110" },
};

const STATUS = {
  planning: { label: "筹备中", icon: "note-pencil" },
  writing: { label: "连载中", icon: "pencil-simple" },
  completed: { label: "已完结", icon: "seal-check" },
};

function formatWords(value) {
  return value >= 10000 ? `${(value / 10000).toFixed(1)} 万字` : `${value.toLocaleString()} 字`;
}

// 剧本作品由 screenplay/data.jsx 注入，带 novel.screenplay。没有这个字段就是小说。
function workKindOf(novel) {
  return novel.screenplay ? "screenplay" : "novel";
}

// 单季不显示季这一层，和剧本工作台的约定一致。
function workStats(novel) {
  if (!novel.screenplay) {
    return [
      { icon: "article", text: `${novel.chapters} 章` },
      { text: formatWords(novel.words) },
    ];
  }
  const project = novel.screenplay;
  const stats = typeof SP_STATS_OF === "function" ? SP_STATS_OF(project.id) : null;
  if (!stats) return [{ icon: "film-strip", text: "剧本" }];
  if (project.kind !== "series") {
    return [{ icon: "film-strip", text: "单本" }, { text: `${stats.scenes} 场` }];
  }
  const parts = [];
  if (stats.seasons > 1) parts.push({ icon: "stack", text: `${stats.seasons} 季` });
  parts.push({ icon: "film-strip", text: `${stats.episodes} 集` });
  parts.push({ text: `${stats.scenes} 场` });
  return parts;
}

function WorkStats({ novel }) {
  return workStats(novel).map((part, index) => (
    <span key={index}>
      {part.icon && <Icon name={part.icon} size={12} />}
      {part.text}
    </span>
  ));
}

function NovelCover({ novel, className = "m-cover" }) {
  const cover = COVER_BG[novel.cover] || COVER_BG.ink;
  return (
    <div className={className} style={{ background: cover.bg }}>
      {cover.motif && (
        <svg viewBox="0 0 400 280" preserveAspectRatio="xMidYMid slice">
          <path d={cover.motif} stroke="#F3F7F5" strokeWidth="1.5" fill="none" opacity="0.58" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      )}
      <div className="m-cover__shade" />
      <div className="m-cover__title">{novel.title}</div>
      <div className="m-cover__title-en">{novel.subtitle}</div>
    </div>
  );
}

function StatusPill({ status }) {
  const item = STATUS[status] || STATUS.planning;
  return (
    <span className={`m-status m-status--${status}`}>
      <Icon name={item.icon} size={12} />
      {item.label}
    </span>
  );
}

function greetingWord() {
  const hour = new Date().getHours();
  if (hour >= 5 && hour < 12) return "早上好";
  if (hour >= 12 && hour < 18) return "下午好";
  if (hour >= 18 && hour < 23) return "晚上好";
  return "夜深了";
}

function GreetingHeader({ username, onQuickStart, onCreate, onImport }) {
  const headline = `${greetingWord()}，${username}`;
  return (
    <header className="m-home-greet">
      <div className="m-home-greet__l">
        <span className="m-home-greet__title">{headline}</span>
        <Icon name="sparkle" size={22} style={{ color: "var(--accent-amber)" }} />
      </div>
      <div className="m-home-greet__r">
        <button className="m-btn m-btn--secondary m-btn--sm" onClick={onImport}><Icon name="file-text" size={14} />导入 TXT</button>
        <button className="m-btn m-btn--secondary m-btn--sm" onClick={onCreate}><Icon name="plus" size={14} />新建作品</button>
        <button className="m-btn m-btn--primary m-btn--sm" onClick={onQuickStart}><Icon name="sparkle" size={14} />快速开书</button>
      </div>
    </header>
  );
}

// 继续写的落点。mock：真实数据取工作区记住的最后位置（小说是章，剧本是季 / 集 / 场）
// 和该处正文的最后一句；剧本的末句带说话人。
const RESUME = {
  sp1: { where: "第 1 季 · Ep 1 登船 · 第 1 场 嘉兴码头", speaker: "沈砚", excerpt: "明早我就不在了。" },
  n1: { where: "卷一 · 第 03 章 三舱客", excerpt: "舱外，雨势变密。船开始动了。" },
  sp3: { where: "第 2 季 · Ep 3 上游来水", excerpt: "闸门开到一半，河道里先下来的是一层浮木。" },
  n5: { where: "第 7 篇 · 河埠头", excerpt: "梅雨停了一夜，第二天又落下来，像谁忘了关窗。" },
  n2: { where: "第 18 章 · 等高线", excerpt: "她把最后一条线描完，山就在纸上站住了。" },
};
// 按最近编辑排好的顺序（mock 里 updated 是展示文案，排不了序）。?resume=<id> 把某部作品顶到第一位，截图用。
const RECENT_IDS = ["sp1", "n1", "sp3", "n5", "n2"];

function recentWorks(works) {
  const pinned = LIB_QS.get("resume");
  const ids = pinned ? [pinned, ...RECENT_IDS.filter((id) => id !== pinned)] : RECENT_IDS;
  return ids.map((id) => works.find((work) => work.id === id)).filter(Boolean);
}

function KindMark({ novel }) {
  if (workKindOf(novel) !== "screenplay") return null;
  return <span className="m-resume__kind"><Icon name="film-strip" size={12} />剧本</span>;
}

// 小封面：有图用图，没图用作品的底色渐变，不压标题（太小了读不清）。
function WorkThumb({ novel }) {
  const cover = COVER_BG[novel.cover] || COVER_BG.ink;
  return (
    <span
      className="m-resume__thumb"
      style={novel.coverImage ? { backgroundImage: `url(${novel.coverImage})` } : { background: cover.bg }}
    />
  );
}

// 继续写的大封面：有封面图用图；没有就用作品底色 + 书名，和网格卡片的灰底占位区分开 ——
// 这里是第一屏的主角，不能是一块空灰。
function ResumeCover({ novel }) {
  const cover = COVER_BG[novel.cover] || COVER_BG.ink;
  if (novel.coverImage) {
    return <div className="m-resume__cover" style={{ backgroundImage: `url(${novel.coverImage})` }} />;
  }
  return (
    <div className="m-resume__cover m-resume__cover--plain" style={{ background: cover.bg }}>
      {cover.motif && (
        <svg viewBox="0 0 400 280" preserveAspectRatio="xMidYMid slice">
          <path d={cover.motif} stroke="#F3F7F5" strokeWidth="1.5" fill="none" opacity="0.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      )}
      <span className="m-resume__cover-title">{novel.title}</span>
      {novel.subtitle && <span className="m-resume__cover-sub">{novel.subtitle}</span>}
    </div>
  );
}

// 继续写：左边是上次停下的那部作品 —— 停在哪、最后一句是什么；右边是另外几部最近的。
// 小说和剧本一视同仁，按最近编辑取，不再是「小说页才有 hero」。
function ResumeSection({ works, onOpenNovel }) {
  const [current, ...rest] = recentWorks(works);
  if (!current) return null;
  const resume = RESUME[current.id] || {};
  const others = rest.slice(0, 3);
  return (
    <section className="m-resume">
      <article className="m-resume__main">
        <ResumeCover novel={current} />
        <div className="m-resume__body">
          <div className="m-resume__eyebrow">继续写<KindMark novel={current} /></div>
          <div className="m-resume__title">{current.title}</div>
          {resume.where && (
            <div className="m-resume__where"><Icon name="map-pin" size={14} />{resume.where}</div>
          )}
          {resume.excerpt && (
            <blockquote className="m-resume__excerpt">
              {resume.speaker && <span className="m-resume__speaker">{resume.speaker}</span>}
              {resume.excerpt}
            </blockquote>
          )}
          <div className="m-resume__foot">
            <span className="m-resume__stats"><WorkStats novel={current} /><span>上次写于 {current.updated}</span></span>
            <span className="m-hero__foot-spacer" />
            <button className="m-btn m-btn--secondary m-btn--sm" title="更多"><Icon name="dots-three" size={14} /></button>
            <button className="m-btn m-btn--primary m-btn--sm" onClick={() => onOpenNovel(current)}><Icon name="pencil-simple" size={14} />继续写作</button>
          </div>
        </div>
      </article>
      {others.length > 0 && (
        <aside className="m-resume__recent" aria-label="最近编辑">
          <div className="m-resume__recent-head">最近</div>
          {others.map((work) => (
            <button key={work.id} type="button" className="m-resume__item" onClick={() => onOpenNovel(work)}>
              <WorkThumb novel={work} />
              <span className="m-resume__item-meta">
                <span className="m-resume__item-title">{work.title}<KindMark novel={work} /></span>
                <span className="m-resume__item-where">{(RESUME[work.id] && RESUME[work.id].where) || work.updated}</span>
              </span>
              <span className="m-resume__item-time">{work.updated}</span>
            </button>
          ))}
        </aside>
      )}
    </section>
  );
}

function AnnouncementBanner() {
  const announcement = window.REVERIC_DATA.homeAnnouncement;
  return (
    <button type="button" className="m-home-announcement">
      <Icon name="warning-circle" size={16} />
      <span className="m-home-announcement__title">{announcement.title}</span>
      <span className="m-home-announcement__detail">{announcement.detail}</span>
      <Icon name="caret-right" size={16} />
    </button>
  );
}

function ScreenplayEmptyState({ onCreate }) {
  return (
    <div className="m-sp-empty">
      <span className="m-sp-empty__icon"><Icon name="film-strip" size={26} /></span>
      <h3>还没有剧本</h3>
      <p>剧本按季与集组织，和小说的卷章是两套结构。<br />也可以在小说卡片的更多菜单里选「改编」，带着人物和设定开始。</p>
      <button type="button" className="m-btn m-btn--primary m-btn--sm" onClick={onCreate}><Icon name="plus" size={14} />新建剧本</button>
    </div>
  );
}

const SORTS = [
  { key: "updated", label: "最近编辑" },
  { key: "created", label: "创建时间" },
  { key: "title", label: "标题" },
  { key: "words", label: "字数" },
];

const TYPES = [
  { key: "all", label: "全部类型" },
  { key: "novel", label: "小说" },
  { key: "screenplay", label: "剧本" },
];

// 字数只是小说的口径；混排或只看剧本时不给这个排序。
const sortsFor = (type) => SORTS.filter((item) => item.key !== "words" || type === "novel");

// 作品区那一行：左边集合标签，右边 搜索 · 类型 · 分类 · 排序 · 草稿。窄了先把搜索收成图标。
function LibraryBar({ nav, query, onQuery, type, typeCounts, onType, categories, category, onCategory, sort, onSort, drafts, showDrafts, onToggleDrafts }) {
  const [ref, width] = useWidth();
  const categoryTotal = categories.reduce((sum, item) => sum + item.count, 0);
  const sorts = sortsFor(type);
  return (
    <div className="m-libbar" ref={ref}>
      {nav}
      <div className="m-libbar__tools">
        <WorksSearch
          value={query}
          onChange={onQuery}
          compact={width < 1080}
          placeholder="搜索作品"
        />
        <ToolMenu
          title="类型"
          label={TYPES.find((item) => item.key === type).label}
          active={type !== "all"}
          items={TYPES.map((item, index) => [
            { key: item.key, label: item.label, count: typeCounts[item.key], selected: type === item.key, onSelect: () => onType(item.key) },
            ...(index === 0 ? ["sep"] : []),
          ]).flat()}
        />
        {(categories.length > 1 || category) && (
          <ToolMenu
            label={category || "全部分类"}
            active={Boolean(category)}
            items={[
              { key: "all", label: "全部分类", count: categoryTotal, selected: !category, onSelect: () => onCategory(null) },
              "sep",
              ...categories.map((item) => ({ key: item.key, label: item.key, count: item.count, selected: category === item.key, onSelect: () => onCategory(item.key) })),
            ]}
          />
        )}
        <ToolMenu
          title="排序"
          label={(sorts.find((item) => item.key === sort) || sorts[0]).label}
          items={sorts.map((item) => ({ key: item.key, label: item.label, selected: sort === item.key, onSelect: () => onSort(item.key) }))}
        />
        {drafts > 0 && (
          <button type="button" className={"m-tool m-co-tool--icon" + (showDrafts ? " m-co-tool--on" : "")} title="草稿箱" onClick={onToggleDrafts}>
            <Icon name="package" size={16} />
          </button>
        )}
      </div>
    </div>
  );
}

function sortWorks(list, sort) {
  const copy = list.slice();
  // mock 的 updated 是展示文案，最近编辑按 RECENT_IDS 排在前面，其余保持数据顺序。
  if (sort === "updated") {
    const rank = (novel) => { const i = RECENT_IDS.indexOf(novel.id); return i < 0 ? RECENT_IDS.length : i; };
    copy.sort((a, b) => rank(a) - rank(b));
  }
  if (sort === "title") copy.sort((a, b) => a.title.localeCompare(b.title, "zh"));
  if (sort === "words") copy.sort((a, b) => b.words - a.words);
  if (sort === "created") copy.reverse();
  return copy;
}

// 深链（便于截图）：?collection=<id> 选中集合；&q=<词> 预填搜索；&type=novel|screenplay 类型筛选；&category=<分类>；
// &cmenu=<id> 展开该集合的右键菜单；&menu=collections 让第一张卡片展开「加入集合」；&picker=1 打开添加作品；
// &resume=<作品 id> 让继续写落在这部作品上。
const LIB_QS = new URLSearchParams(window.location.search);

function LibraryView({ onOpenNovel }) {
  const allWorks = window.REVERIC_DATA.novels;
  // 草稿不在书架里，只从草稿箱看；mockup 里借两部作品充当草稿。
  const drafts = allWorks.filter((novel) => ["n3", "n12"].includes(novel.id));
  // null | {} | {source}；?screen=new-novel 直接打开新建作品 dialog，沿用 ?screen= 深链约定。
  const [creating, setCreating] = React.useState(() => (LIB_QS.get("screen") === "new-novel" ? {} : null));
  const [collections, setCollections] = React.useState(() => window.COLLECTIONS_SEED.map((c) => ({ ...c, workIds: c.workIds && [...c.workIds] })));
  const allId = collections.find((c) => c.builtin).id;
  const [scope, setScope] = React.useState(() => LIB_QS.get("collection") || allId);
  const [query, setQuery] = React.useState(() => LIB_QS.get("q") || "");
  const [type, setType] = React.useState(() => (TYPES.some((t) => t.key === LIB_QS.get("type")) ? LIB_QS.get("type") : "all"));
  const [category, setCategory] = React.useState(() => LIB_QS.get("category"));
  const [sort, setSort] = React.useState("updated");
  const [showDrafts, setShowDrafts] = React.useState(false);
  // null | {kind:"create"} | {kind:"rename", collection} | {kind:"delete", collection} | {kind:"picker"}
  const [dialog, setDialog] = React.useState(() => (LIB_QS.get("picker") === "1" ? { kind: "picker" } : null));
  const [toast, setToast] = React.useState(null);
  const [contentRef, columns] = useMaxExtentColumns(180, 16);

  React.useEffect(() => {
    if (!toast) return undefined;
    const timer = setTimeout(() => setToast(null), 2200);
    return () => clearTimeout(timer);
  }, [toast]);

  const shelf = collections;
  const current = shelf.find((collection) => collection.id === scope) || shelf[0];
  const manual = shelf.filter(isManual);
  const ofType = (list) => (type === "all" ? list : list.filter((novel) => workKindOf(novel) === type));
  // 集合计数跟着类型筛选走，标签上的数字和网格里看到的一致。
  const typed = ofType(allWorks.filter((novel) => !drafts.includes(novel)));
  const counts = Object.fromEntries(shelf.map((c) => [c.id, collectionWorks(c, typed).length]));
  const inDrafts = current.builtin && showDrafts && drafts.length > 0;
  const base = inDrafts ? ofType(drafts) : collectionWorks(current, typed);
  // 类型菜单里的数字按当前集合算，不受类型自身影响。
  const untyped = inDrafts ? drafts : collectionWorks(current, allWorks.filter((novel) => !drafts.includes(novel)));
  const typeCounts = {
    all: untyped.length,
    novel: untyped.filter((novel) => workKindOf(novel) === "novel").length,
    screenplay: untyped.filter((novel) => workKindOf(novel) === "screenplay").length,
  };

  const categoryMap = {};
  base.forEach((novel) => { if (novel.categoryLabel) categoryMap[novel.categoryLabel] = (categoryMap[novel.categoryLabel] || 0) + 1; });
  const categories = Object.entries(categoryMap).map(([key, count]) => ({ key, count }));
  const normalizedQuery = query.trim().toLowerCase();
  const visible = sortWorks(base.filter((novel) =>
    (!category || novel.categoryLabel === category) &&
    (!normalizedQuery || [novel.title, novel.subtitle, novel.authorName, ...novel.tags].join(" ").toLowerCase().includes(normalizedQuery))
  ), sort);
  const openCreate = () => setCreating({});

  // 切集合清掉临时分类筛选，搜索和类型保留、继续在新集合里用。
  const select = (id) => {
    if (id === current.id) return;
    setScope(id);
    setCategory(null);
    setShowDrafts(false);
  };

  // 换类型时分类可能不再存在，清掉；离开小说时字数排序失效，回到最近编辑。
  const changeType = (next) => {
    setType(next);
    setCategory(null);
    if (!sortsFor(next).some((item) => item.key === sort)) setSort("updated");
  };

  const moveCollection = (id, to) => {
    setCollections((list) => {
      const moving = list.find((c) => c.id === id);
      const next = list.filter((c) => c.id !== id);
      next.splice(Math.max(1, Math.min(to, next.length)), 0, moving);
      return next;
    });
  };
  const updateWorks = (collectionId, fn) =>
    setCollections((list) => list.map((c) => (c.id === collectionId ? { ...c, workIds: fn(c.workIds) } : c)));
  const toggleMembership = (collectionId, workIds, state) => {
    const name = collections.find((c) => c.id === collectionId).name;
    if (state === "checked") {
      updateWorks(collectionId, (ids) => ids.filter((id) => !workIds.includes(id)));
      setToast(`已从「${name}」移出`);
    } else {
      updateWorks(collectionId, (ids) => [...ids, ...workIds.filter((id) => !ids.includes(id))]);
      setToast(`已加入「${name}」`);
    }
  };
  const createCollection = (name, workIds = []) => {
    const id = `c-${Date.now()}`;
    setCollections((list) => [...list, { id, name, workIds: [...workIds] }]);
    setToast(workIds.length ? `已新建「${name}」并加入 ${workIds.length} 部作品` : `已新建「${name}」`);
    return id;
  };

  const menuFor = (novel, index) => (
    <CoWorkMenu
      novel={novel}
      collections={manual}
      inCollection={isManual(current) ? current : null}
      initialPage={index === 0 ? LIB_QS.get("menu") : null}
      onToggle={toggleMembership}
      onCreate={createCollection}
      onRemoveFromCurrent={(id) => {
        updateWorks(current.id, (ids) => ids.filter((x) => x !== id));
        setToast(`已从「${current.name}」移出`);
      }}
      onAdapt={(source) => setCreating({ source })}
    />
  );

  const clearFilters = () => { setQuery(""); setCategory(null); changeType("all"); };
  let works;
  if (current.builtin && !inDrafts && type === "screenplay" && base.length === 0) {
    works = <ScreenplayEmptyState onCreate={openCreate} />;
  } else if (!base.length && isManual(current)) {
    works = <CollectionEmpty onAddWorks={() => setDialog({ kind: "picker" })} />;
  } else if (!base.length) {
    works = <div className="m-home-empty"><Icon name="stack" size={24} /><span>没有作品</span></div>;
  } else if (!visible.length) {
    works = (
      <div className="m-home-empty">
        <Icon name="magnifying-glass" size={24} />
        <span>没有找到匹配的作品</span>
        <button type="button" className="m-btn m-btn--secondary m-btn--sm" onClick={clearFilters}>清除搜索和筛选</button>
      </div>
    );
  } else {
    works = (
      <div className="m-co-grid" style={{ gridTemplateColumns: `repeat(${columns}, minmax(0, 1fr))` }}>
        {visible.map((novel, index) => (
          <CoNovelCard key={novel.id} novel={novel} onOpen={onOpenNovel} menu={menuFor(novel, index)} />
        ))}
        {current.builtin && !inDrafts && <CoCreateCard onCreate={openCreate} />}
      </div>
    );
  }

  return (
    <main className="m-main">
      <div className="m-home m-home--library"><div ref={contentRef} className="m-home__content">
        <GreetingHeader username="怀素" onQuickStart={() => {}} onCreate={openCreate} onImport={() => {}} />
        <ResumeSection works={allWorks} onOpenNovel={onOpenNovel} />
        <AnnouncementBanner />
        <section className="m-home__works">
          <LibraryBar
            nav={
              <CollectionNav
                collections={shelf}
                counts={counts}
                currentId={current.id}
                onSelect={select}
                onCreate={() => setDialog({ kind: "create" })}
                onRename={(collection) => setDialog({ kind: "rename", collection })}
                onMove={moveCollection}
                onDelete={(collection) => setDialog({ kind: "delete", collection })}
              />
            }
            query={query}
            onQuery={setQuery}
            type={type}
            typeCounts={typeCounts}
            onType={changeType}
            categories={categories}
            category={category}
            onCategory={setCategory}
            sort={sort}
            onSort={setSort}
            drafts={current.builtin ? drafts.length : 0}
            showDrafts={inDrafts}
            onToggleDrafts={() => { setShowDrafts(!inDrafts); setCategory(null); }}
          />
          {works}
        </section>
      </div></div>

      {creating && (
        <NovelFormDialog
          kind={creating.source || type === "screenplay" ? "screenplay" : "novel"}
          source={creating.source || null}
          onClose={() => setCreating(null)}
          onCreated={() => setCreating(null)}
        />
      )}
      {dialog && dialog.kind === "create" && (
        <NameDialog
          title="新建集合"
          confirmLabel="创建"
          onClose={() => setDialog(null)}
          onSubmit={(name) => {
            const id = createCollection(name);
            setDialog(null);
            select(id);
          }}
        />
      )}
      {dialog && dialog.kind === "rename" && (
        <NameDialog
          title="重命名集合"
          initial={dialog.collection.name}
          confirmLabel="保存"
          onClose={() => setDialog(null)}
          onSubmit={(name) => {
            setCollections((list) => list.map((c) => (c.id === dialog.collection.id ? { ...c, name } : c)));
            setDialog(null);
          }}
        />
      )}
      {dialog && dialog.kind === "delete" && (
        <CollectionDeleteDialog
          collection={dialog.collection}
          count={counts[dialog.collection.id]}
          onClose={() => setDialog(null)}
          onConfirm={() => {
            const target = dialog.collection;
            setCollections((list) => list.filter((c) => c.id !== target.id));
            setToast(`已删除集合「${target.name}」`);
            setDialog(null);
            // 删的是当前集合才回到全部；删别的不动当前选择。
            if (target.id === current.id) select(allId);
          }}
        />
      )}
      {dialog && dialog.kind === "picker" && isManual(current) && (
        <WorkPickerDialog
          collection={current}
          novels={allWorks.filter((novel) => !drafts.includes(novel))}
          onClose={() => setDialog(null)}
          onAdd={(ids) => {
            updateWorks(current.id, (list) => [...list, ...ids]);
            setToast(`已加入 ${ids.length} 部作品`);
            setDialog(null);
          }}
        />
      )}
      {toast && <div className="m-toast">{toast}</div>}
    </main>
  );
}

Object.assign(window, { LibraryView });
