// Character profile page — 创作·人物 的主区。
// Mirrors lib/desktop/widgets/workspace/character_profile_editor.dart.
//
// IA：Hero（头像 / 名字 / 定位·性别·年龄 / 身份速览）+ 吸顶锚点栏 + 七个分组
// 连续滚动，带 scrollspy 双向联动；与移动端 CharacterDetail 同一套结构。
// 角色字段近年增得很多（identity/age/aliases/motivation/arc/appearance/
// description/biography/personality/behaviorTags/currentState/photos…），
// 原来的三个 tab 装不下，这里全部平铺，一次滚动看完。
//
// 关系（人物 / 势力 / 技能 / 物品）在本页只读概览，编辑走实体关系图。
// 人物宇宙沿用 entity_graph_data.js 里的沧澜剑派设定，保持两处一致。

const CHAR_SECTIONS = [
  { id: "identity",  label: "身份档案", icon: "user",           hint: "稳定的人物基础信息" },
  { id: "figure",    label: "形象",     icon: "image-square",   hint: "外观与图像资料" },
  { id: "biography", label: "人物小传", icon: "book-open",      hint: "创作初期设定，后续较少改动" },
  { id: "outward",   label: "外在表现", icon: "mask-happy",     hint: "他人可观察到的部分" },
  { id: "psyche",    label: "内在心理", icon: "heart",          hint: "动机、弧光与条件化行为" },
  { id: "story",     label: "剧情状态", icon: "waves",          hint: "随最新章节推进而变化" },
  { id: "relations", label: "关系网络", icon: "tree-structure", hint: "只读概览 · 编辑请前往关系图" },
];

const CHAR_ROLE_OPTIONS = [
  ["protagonist", "主角"], ["antagonist", "反派"],
  ["supporting", "配角"], ["minor", "龙套"],
];
const CHAR_GENDER_OPTIONS = [
  ["male", "男"], ["female", "女"],
  ["non_binary", "非二元"], ["other", "其他"], ["unknown", "未知"],
];
const charLabel = (opts, k) => (opts.find((o) => o[0] === k) || opts[0])[1];

// 主角完整档案；其余角色只给列表所需的最小字段。
const CHAR_PROFILE = {
  id: "shen",
  name: "沈砚之",
  role: "protagonist",
  gender: "male",
  age: "23",
  identity: "沧澜剑派内门弟子 · 沈氏旧主之子",
  aliases: ["砚之", "青冥峰那小子", "无名剑客"],
  tint: "#3E6A5C",
  photos: [
    { tint: "#3E6A5C", label: "下山那日" },
    { tint: "#4A5468", label: "幽冥渊口" },
    { tint: "#4C6E91", label: "剑心初成" },
  ],
  appearance:
    "身量偏瘦，肩背却压得很直，像常年提着比自己重的东西。\n\n" +
    "黑发束冠，鬓角有一缕被剑气烧过的灰白。左眉骨一道旧疤，笑起来会被牵得微微歪。" +
    "常年一身洗到发白的沧澜内门弟子服，袖口磨出了毛边也不肯换。",
  biography:
    "沈氏原是临安望族，十六年前幽冥教夜袭，满门尽灭，父亲沈鹤年尸骨无存，幼妹青鸢失踪。\n\n" +
    "砚之被老仆背上青冥峰，寄养在守峰人门下，靠替内门弟子磨剑换口粮长大。" +
    "十七岁那年，他在峰底捡到半截断刃——那是父亲佩剑的残片，也是他第一次听见「剑鸣」。\n\n" +
    "他没有把这件事告诉任何人，包括后来收他入内门的玄霜真人。",
  description:
    "说话慢，句尾常收半拍，像先在心里把话过一遍。\n\n" +
    "站着时右手总不自觉搭在腰侧空刀鞘上。生人面前不主动开口，一旦开口就直奔要害，" +
    "因此在同门中风评两极：有人说他稳，有人说他冷。",
  motivation: "查清十六年前的灭门旧案，把父亲的名字从「通魔」的卷宗里拿回来。",
  arc: "从怯懦躲闪的杂役少年，到肯替所有人挡在渊口的执剑人；代价是他先学会了杀人，才学会了谈判。",
  personality:
    "外冷内热。对「亏欠」极度敏感，别人给他一分好会记很久，也因此不肯欠人情。\n\n" +
    "判断快、下手更快，但事后会反复复盘；这种自我审判往往比对手更伤他。\n\n" +
    "在师门权威面前会本能退让半步——不是怕，是不想再连累任何人。",
  behaviorTags: [
    ["战斗中", "先手压制，宁可受伤也不让对手起势"],
    ["面对师门长辈", "沉默顺从，把反对意见留到事后独自消化"],
    ["被人道谢", "转身就走，用忙碌掩饰不自在"],
    ["同伴受伤时", "话变多、变硬，用命令口吻掩盖慌张"],
  ],
  firstChapter: "第 3 章 · 剑鸣",
  currentState:
    "身在幽冥渊第三层，右臂骨裂未愈，靠布带固定。\n\n" +
    "随身：断刃残片、玄霜真人给的半枚令牌、三粒续骨丹（已用两粒）。\n\n" +
    "**知识边界**：尚不知道鬼面就是燕无咎，也不知道青鸢还活着。目前认定的仇人仍是幽冥教全教。",
  relations: {
    characters: [
      ["师徒", "玄霜真人", "收他入内门，也瞒了他十六年"],
      ["宿敌", "燕无咎", "灭门案主谋（真面目未揭）"],
      ["恋人", "苏苓", "临安一别，再见已隔生死局"],
      ["兄妹", "沈青鸢", "灭门时失踪，生死成谜"],
      ["挚友", "裴照", "游方刀客，专破剑招"],
      ["同门", "凌霄", "师兄，剑快而意躁"],
      ["父", "沈鹤年", "已故 · 沈氏旧主"],
    ],
    factions: [["成员", "沧澜剑派"], ["成员", "沈氏"]],
    skills: [
      ["学习中", "青冥剑诀"], ["已学会", "御风步"],
      ["已精通", "沧澜十三式"], ["已学会", "听剑"],
    ],
    items: [["持有者", "沧澜剑"], ["使用者", "玄霜佩"]],
  },
};

const CHAR_LIST = [
  { id: "shen",        name: "沈砚之",   role: "protagonist", tint: "#3E6A5C", sub: "内门弟子" },
  { id: "suling",      name: "苏苓",     role: "supporting",  tint: "#7A4B57", sub: "天枢阁少阁主" },
  { id: "xuanshuang",  name: "玄霜真人", role: "supporting",  tint: "#4A5468", sub: "沧澜掌门" },
  { id: "peizhao",     name: "裴照",     role: "supporting",  tint: "#5E7060", sub: "游方刀客" },
  { id: "lingxiao",    name: "凌霄",     role: "supporting",  tint: "#4C6E91", sub: "首徒" },
  { id: "yanwujiu",    name: "燕无咎",   role: "antagonist",  tint: "#8C4A46", sub: "幽冥教主" },
  { id: "murongxue",   name: "慕容雪",   role: "antagonist",  tint: "#7A4B57", sub: "左护法" },
  { id: "qingyuan",    name: "沈青鸢",   role: "supporting",  tint: "#3B5182", sub: "失踪" },
  { id: "shenhe",      name: "沈鹤年",   role: "minor",       tint: "#9E9484", sub: "已故" },
];

// ---- 原子 ---------------------------------------------------------------

// 头像占位：首字 + 人物色。真实实现里是本地图片路径。
function CharAvatar({ name, tint, size = 104, radius = 20 }) {
  return (
    <div
      className="m-char-avatar"
      style={{ width: size, height: size, borderRadius: radius, background: tint, fontSize: size * 0.38 }}
    >
      {name[0]}
    </div>
  );
}

function CharSecHead({ icon, title, hint, action }) {
  return (
    <div className="m-char-sec__head">
      <span className="m-char-sec__icon"><Icon name={icon} size={15} /></span>
      <h3 className="m-char-sec__title">{title}</h3>
      {hint && <span className="m-char-sec__hint">{hint}</span>}
      {action && <div className="m-char-sec__action">{action}</div>}
    </div>
  );
}

// 标签在左、值就地编辑；hover 才浮出边框，静态时让位给内容。
function CharRow({ label, children, wide, top }) {
  return (
    <label className={"m-char-row" + (wide ? " is-wide" : "") + (top ? " is-top" : "")}>
      <span className="m-char-row__label">{label}</span>
      {children}
    </label>
  );
}

function CharInput({ value }) {
  const [v, setV] = React.useState(value);
  return <input className="m-char-input" value={v} onChange={(e) => setV(e.target.value)} />;
}

function CharSelect({ value, options }) {
  const [v, setV] = React.useState(value);
  return (
    <span className="m-char-select">
      <select value={v} onChange={(e) => setV(e.target.value)}>
        {options.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
      </select>
      <Icon name="caret-down" size={13} />
    </span>
  );
}

// 长文：Georgia 正文 + 自动增高，不做固定高度的滚动窗。
function CharProse({ value, dense, rows = 3 }) {
  const ref = React.useRef(null);
  const [v, setV] = React.useState(value);
  const fit = () => {
    const el = ref.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = el.scrollHeight + "px";
  };
  React.useEffect(fit, []);
  return (
    <textarea
      ref={ref}
      rows={rows}
      className={"m-char-prose" + (dense ? " is-dense" : "")}
      value={v}
      onChange={(e) => { setV(e.target.value); fit(); }}
    />
  );
}

// 动机 / 弧光这类「比一行长、比一段短」的字段，单行输入会截断。
function CharProseField({ label, value }) {
  return (
    <div className="m-char-pfield">
      <span className="m-char-pfield__label">{label}</span>
      <CharProse value={value} dense rows={2} />
    </div>
  );
}

function CharAliases({ initial }) {
  const [list, setList] = React.useState(initial);
  const [draft, setDraft] = React.useState("");
  const commit = () => {
    const v = draft.trim();
    if (v && !list.includes(v)) setList([...list, v]);
    setDraft("");
  };
  return (
    <div className="m-char-chipfield">
      {list.map((a) => (
        <span key={a} className="m-char-alias">
          {a}
          <button type="button" onClick={() => setList(list.filter((x) => x !== a))}>
            <Icon name="x" size={11} />
          </button>
        </span>
      ))}
      <input
        className="m-char-chipfield__input"
        value={draft}
        placeholder={list.length ? "" : "曾用名、称号、昵称，回车添加"}
        onChange={(e) => setDraft(e.target.value)}
        onKeyDown={(e) => e.key === "Enter" && (e.preventDefault(), commit())}
        onBlur={commit}
      />
    </div>
  );
}

// 情境行为：写作时最常被 AI 引用的一段，情境与行为成对呈现。
function CharBehaviorTags({ initial }) {
  const [list, setList] = React.useState(initial);
  return (
    <div className="m-char-btags">
      {list.map(([ctx, body], i) => (
        <div key={i} className="m-char-btag">
          <span className="m-char-btag__ctx">{ctx}</span>
          <span className="m-char-btag__body">{body}</span>
          <button type="button" onClick={() => setList(list.filter((_, j) => j !== i))}>
            <Icon name="x" size={12} />
          </button>
        </div>
      ))}
      <button
        type="button"
        className="m-char-btag m-char-btag--add"
        onClick={() => setList([...list, ["新情境", "描述该情境下的行为倾向"]])}
      >
        <Icon name="plus" size={13} />
        添加情境行为
      </button>
    </div>
  );
}

// 主角的关系可以有几十条，全平铺会把整页撑爆；默认只出前 N 条。
const REL_PREVIEW_CAP = 6;

function CharRelGroup({ icon, title, items }) {
  const [expanded, setExpanded] = React.useState(false);
  const overflow = items.length - REL_PREVIEW_CAP;
  const shown = expanded ? items : items.slice(0, REL_PREVIEW_CAP);
  return (
    <div className="m-char-relgroup">
      <div className="m-char-relgroup__head">
        <Icon name={icon} size={14} style={{ opacity: 0.6 }} />
        <span className="m-char-relgroup__title">{title}</span>
        <span className="m-char-relgroup__count">{items.length}</span>
        <button type="button" className="m-char-link">
          在关系图中查看 <Icon name="caret-right" size={12} />
        </button>
      </div>
      <div className="m-char-relgroup__body">
        {shown.map(([type, name, note]) => (
          <button key={name} type="button" className="m-char-relchip">
            <span className="m-char-relchip__type">{type}</span>
            <span className="m-char-relchip__name">{name}</span>
            {note && <span className="m-char-relchip__note">{note}</span>}
          </button>
        ))}
        {overflow > 0 && (
          <button
            type="button"
            className="m-char-relchip m-char-relchip--more"
            onClick={() => setExpanded(!expanded)}
          >
            {expanded ? "收起" : `还有 ${overflow} 条`}
            <Icon name={expanded ? "caret-up" : "caret-down"} size={12} />
          </button>
        )}
      </div>
    </div>
  );
}

// ---- 第二列：人物列表（替代人物栏目下的章节树） -------------------------
function CharacterContext({ novel, activeId, onSelect, onBack }) {
  return (
    <aside className="m-ctx">
      <PanelHeader onBack={onBack} onCollapse={() => {}} />
      <NovelSwitcher novel={novel} />

      <div className="m-ctx__sec-head">
        <span className="m-ctx__sec-title">人物</span>
        <span className="m-ctx__sec-count">{CHAR_LIST.length}</span>
        <button className="m-icon-btn m-icon-btn--ghost" title="新建人物">
          <Icon name="plus" size={12} />
        </button>
      </div>

      <div className="m-ctx__list">
        {CHAR_LIST.map((c) => (
          <button
            key={c.id}
            type="button"
            onClick={() => onSelect(c.id)}
            className={"m-char-listitem" + (c.id === activeId ? " is-active" : "")}
          >
            <CharAvatar name={c.name} tint={c.tint} size={26} radius={8} />
            <span className="m-char-listitem__meta">
              <span className="m-char-listitem__name">{c.name}</span>
              <span className="m-char-listitem__sub">{c.sub}</span>
            </span>
            <span className={"m-char-dot m-char-dot--" + c.role} />
          </button>
        ))}
        <button type="button" className="m-ctx__add">
          <Icon name="plus" size={14} />
          <span>新建人物</span>
        </button>
      </div>
    </aside>
  );
}

// ---- 主区：左身份栏 + 右分组滚动 ----------------------------------------
function CharacterProfileView() {
  const scrollRef = React.useRef(null);
  const anchorsRef = React.useRef(null);
  const [active, setActive] = React.useState("identity");
  const c = CHAR_PROFILE;
  const relCount =
    c.relations.characters.length + c.relations.factions.length +
    c.relations.skills.length + c.relations.items.length;

  const counts = {
    figure: c.photos.length,
    psyche: c.behaviorTags.length,
    relations: relCount,
  };

  const onScroll = () => {
    const box = scrollRef.current;
    if (!box) return;
    // 末尾分组永远到不了顶部，滚到底时直接收敛到最后一项。
    if (box.scrollTop + box.clientHeight >= box.scrollHeight - 8) {
      return setActive(CHAR_SECTIONS[CHAR_SECTIONS.length - 1].id);
    }
    // 吸顶锚点栏遮住的那一条不算「已到顶」。
    const top = box.getBoundingClientRect().top + 108;
    let cur = CHAR_SECTIONS[0].id;
    for (const s of CHAR_SECTIONS) {
      const el = box.querySelector(`[data-sec="${s.id}"]`);
      if (el && el.getBoundingClientRect().top <= top) cur = s.id;
    }
    setActive(cur);
  };

  const jump = (id) => {
    const box = scrollRef.current;
    const el = box && box.querySelector(`[data-sec="${id}"]`);
    if (el) box.scrollTo({ top: el.offsetTop - 56, behavior: "smooth" });
  };

  // 当前分组的锚点始终留在可视范围内。
  React.useEffect(() => {
    const bar = anchorsRef.current;
    const chip = bar && bar.querySelector(`[data-anchor="${active}"]`);
    if (!chip) return;
    bar.scrollTo({
      left: Math.max(0, chip.offsetLeft - (bar.clientWidth - chip.offsetWidth) / 2),
      behavior: "smooth",
    });
  }, [active]);

  return (
    <div className="m-char-page">
      <div className="m-char-scroll" ref={scrollRef} onScroll={onScroll}>
        <header className="m-char-topbar">
          <span className="m-char-saved">
            <Icon name="check" size={12} /> 已保存 · 今天 14:26
          </span>
          <button className="m-icon-btn m-icon-btn--ghost" title="撤销"><Icon name="arrow-counter-clockwise" size={15} /></button>
          <button className="m-icon-btn m-icon-btn--ghost" title="重做"><Icon name="arrow-clockwise" size={15} /></button>
          <button type="button" className="m-btn m-btn--secondary m-btn--sm">
            <Icon name="sparkle" size={13} /> AI 补全档案
          </button>
        </header>

        {/* Hero — 只做身份速览，可编辑的同名字段在「身份档案」分组里 */}
        <div className="m-char-hero">
          <div className="m-char-hero__avatar">
            <CharAvatar name={c.name} tint={c.tint} size={88} radius={22} />
            <button type="button" className="m-char-hero__avatar-btn" title="更换头像">
              <Icon name="image-square" size={13} />
            </button>
          </div>
          <input className="m-char-hero__name" defaultValue={c.name} />
          <div className="m-char-hero__badges">
            <span className="m-char-badge m-char-badge--role">{charLabel(CHAR_ROLE_OPTIONS, c.role)}</span>
            <span className="m-char-badge">{charLabel(CHAR_GENDER_OPTIONS, c.gender)}</span>
            <span className="m-char-badge">{c.age} 岁</span>
          </div>
          <p className="m-char-hero__identity">{c.identity}</p>
        </div>

        {/* 吸顶锚点栏 */}
        <div className="m-char-anchors">
          <div className="m-char-anchors__scroll" ref={anchorsRef}>
            {CHAR_SECTIONS.map((s) => (
              <button
                key={s.id}
                type="button"
                data-anchor={s.id}
                onClick={() => jump(s.id)}
                className={"m-char-anchor" + (active === s.id ? " is-active" : "")}
              >
                <Icon name={s.icon} size={14} />
                {s.label}
                {counts[s.id] != null && <em>{counts[s.id]}</em>}
              </button>
            ))}
          </div>
        </div>

        <div className="m-char-inner">
          {/* 身份档案 */}
          <section className="m-char-sec" data-sec="identity">
            <CharSecHead icon="user" title="身份档案" hint="稳定的人物基础信息" />
            <div className="m-char-grid m-char-grid--3">
              <CharRow label="定位"><CharSelect value={c.role} options={CHAR_ROLE_OPTIONS} /></CharRow>
              <CharRow label="性别"><CharSelect value={c.gender} options={CHAR_GENDER_OPTIONS} /></CharRow>
              <CharRow label="年龄"><CharInput value={c.age} /></CharRow>
            </div>
            <div className="m-char-grid" style={{ marginTop: 12 }}>
              <CharRow label="身份 / 称号" wide><CharInput value={c.identity} /></CharRow>
              <CharRow label="别名" wide top><CharAliases initial={c.aliases} /></CharRow>
            </div>
          </section>

          {/* 形象 */}
          <section className="m-char-sec" data-sec="figure">
            <CharSecHead
              icon="image-square" title="形象" hint="外观与图像资料"
              action={
                <button type="button" className="m-btn m-btn--secondary m-btn--sm">
                  <Icon name="sparkle" size={13} /> AI 生成
                </button>
              }
            />
            <CharProse value={c.appearance} />
            <div className="m-char-sub">
              <span className="m-ui-tiny-section">头像与照片</span>
              <div className="m-char-photos">
                {c.photos.map((p) => (
                  <div key={p.label} className="m-char-photo">
                    <span className="m-char-photo__img" style={{ background: p.tint }} />
                    <span className="m-char-photo__cap">{p.label}</span>
                  </div>
                ))}
                <button type="button" className="m-char-photo__add">
                  <Icon name="plus" size={16} />
                  <span>添加</span>
                </button>
              </div>
            </div>
          </section>

          {/* 人物小传 */}
          <section className="m-char-sec" data-sec="biography">
            <CharSecHead icon="book-open" title="人物小传" hint="创作初期设定，后续较少改动" />
            <CharProse value={c.biography} rows={6} />
          </section>

          {/* 外在表现 */}
          <section className="m-char-sec" data-sec="outward">
            <CharSecHead icon="mask-happy" title="外在表现" hint="他人可观察到的部分" />
            <CharProse value={c.description} rows={4} />
          </section>

          {/* 内在心理 */}
          <section className="m-char-sec" data-sec="psyche">
            <CharSecHead icon="heart" title="内在心理" hint="动机、弧光与条件化行为" />
            {/* 动机与弧光都会自增高，并排放底边永远对不齐；与小传/性格一致走通栏。 */}
            <div className="m-char-stack">
              <CharProseField label="核心动机" value={c.motivation} />
              <CharProseField label="人物弧光" value={c.arc} />
            </div>
            <div className="m-char-sub">
              <span className="m-ui-tiny-section">性格</span>
              <CharProse value={c.personality} rows={4} />
            </div>
            <div className="m-char-sub">
              <span className="m-ui-tiny-section">
                情境行为 <em>写作时最常被 AI 引用的一段</em>
              </span>
              <CharBehaviorTags initial={c.behaviorTags} />
            </div>
          </section>

          {/* 剧情状态 */}
          <section className="m-char-sec" data-sec="story">
            <CharSecHead icon="waves" title="剧情状态" hint="随最新章节推进而变化" />
            <div className="m-char-linkrow">
              <span><Icon name="map-pin" size={14} /> 首次登场</span>
              <button type="button">{c.firstChapter} <Icon name="caret-right" size={13} /></button>
            </div>
            <div className="m-char-callout">
              <Icon name="sparkle" size={14} />
              <span>该段落由 AI 随剧情自动维护，手动修改会在下次同步时被覆盖。</span>
            </div>
            <CharProse value={c.currentState} rows={5} />
          </section>

          {/* 关系网络 */}
          <section className="m-char-sec" data-sec="relations">
            <CharSecHead icon="tree-structure" title="关系网络" hint="只读概览 · 编辑请前往关系图" />
            <CharRelGroup icon="users" title="人物关系" items={c.relations.characters} />
            <CharRelGroup icon="flag" title="所属势力" items={c.relations.factions} />
            <CharRelGroup icon="magic-wand" title="技能" items={c.relations.skills} />
            <CharRelGroup icon="cube" title="物品" items={c.relations.items} />
          </section>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { CharacterProfileView, CharacterContext, CHAR_LIST });
