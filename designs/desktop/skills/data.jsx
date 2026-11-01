// skills/data.jsx — AgentSkill 技能库与小说级安装的 mock 数据。
// 对应方案 docs/solutions/agent-skill-library-and-novel-installations.md。
// 运行在 index.html 上下文:图标复用主应用 Icon(assets/icons/phosphor);
// 全局名一律加 SK_ 前缀,避免与其他原型脚本的共享全局作用域冲突。
//
// 领域模型速记:
//   AgentSkillLibraryEntry(SK_LIBRARY)  — 私有来源,永不可执行
//   NovelAgentSkill(SK_INSTALLED)       — 当前小说唯一可执行的快照
//   官方目录 / 市场(SK_OFFICIAL/SK_MARKET) — 可安装来源

// 本地类别候选，用于筛选与创建表单。
const SK_CATEGORIES = ["扩写", "润色", "校对", "设定考据", "结构", "对白", "节奏", "文风"];

// source_kind → 展示徽章(图标 + 文案 + 色调)。
const SK_SOURCE_BADGE = {
  novel_local: { icon: "note-pencil", label: "本地创建", tone: "muted" },
  library: { icon: "stack", label: "技能库", tone: "muted" },
  official: { icon: "seal-check", label: "官方", tone: "accent" },
  marketplace: { icon: "storefront", label: "市场", tone: "muted" },
};

// 当前小说已安装的可执行技能(NovelAgentSkill 快照)。
const SK_INSTALLED = [
  {
    id: "nas1",
    callName: "expand_chapter",
    sourceKind: "novel_local",
    name: "章节扩写",
    enabled: true,
    sortOrder: 0,
    category: "扩写",
    tags: ["初稿", "节奏"],
    whenToUse: "当一章只有大纲或寥寥数段,需要在保持既定情节节点的前提下扩展为完整初稿时使用。",
    description: "把章节大纲扩写为符合既定节奏与人物声音的完整初稿。",
  },
  {
    id: "nas2",
    callName: "polish",
    sourceKind: "library",
    sourceDisplayName: "润色重写",
    name: "润色重写",
    enabled: true,
    sortOrder: 1,
    category: "润色",
    tags: ["语言", "节奏"],
    whenToUse: "初稿已完成、情节无需改动,只需打磨语言节奏、消除重复与口水句时使用。",
    description: "在不改动情节的前提下打磨语言:节奏、重复、冗词、标点。",
  },
  {
    id: "nas3",
    callName: "lore_audit",
    sourceKind: "official",
    sourceDisplayName: "世界观考据",
    sourceVersion: "1.2.0",
    upgradeVersion: "1.4.0",
    name: "世界观考据",
    enabled: true,
    sortOrder: 2,
    category: "设定考据",
    tags: ["设定", "自洽"],
    whenToUse: "完成章节后,需要对照世界观设定核查地理、器物、制度、时间线是否自洽时使用。",
    description: "对照已建立的世界设定,核查正文中的地理、器物、制度与时间线冲突。",
  },
  {
    id: "nas4",
    callName: "golden_three",
    sourceKind: "marketplace",
    sourceDisplayName: "网文黄金三章",
    sourceVersion: "2.0.1",
    executionBlockedReason: "作者已撤下该版本(2.0.1),市场判定为存在质量问题。已保留本地内容,但运行时会跳过执行。",
    name: "网文黄金三章",
    enabled: true,
    sortOrder: 3,
    category: "结构",
    tags: ["开篇", "留存"],
    whenToUse: "开篇前三章需要快速抓住读者、埋好钩子并建立追读动机时使用。",
    description: "按网文黄金三章模型重排开篇节奏:悬念前置、爽点密度、章末钩子。",
  },
  {
    id: "nas5",
    callName: "multiline",
    sourceKind: "marketplace",
    sourceDisplayName: "多线叙事编排",
    sourceVersion: "1.3.0",
    name: "多线叙事编排",
    enabled: false,
    sortOrder: 4,
    category: "结构",
    tags: ["群像", "多线"],
    whenToUse: "多条故事线并行推进,需要安排交汇点与信息释放节奏时使用。",
    description: "梳理多线叙事的时间轴与交汇点,标出信息释放与视角切换节奏。",
  },
];

// 私有技能库(AgentSkillLibraryEntry)— 只是来源,不能直接执行。
const SK_LIBRARY = [
  {
    id: "lib1",
    name: "润色重写",
    category: "润色",
    tags: ["语言", "节奏"],
    updatedAt: "3 天前",
    whenToUse: "初稿已完成、情节无需改动,只需打磨语言节奏时使用。",
    description: "在不改动情节的前提下打磨语言:节奏、重复、冗词、标点。",
  },
  {
    id: "lib2",
    name: "伏笔检查",
    category: "校对",
    tags: ["伏笔", "台账"],
    updatedAt: "1 周前",
    whenToUse: "完成一卷或多章后,检查伏笔是否回收、是否过早暴露时使用。",
    description: "梳理全书已埋伏笔与回收状态,标出悬而未决或暴露过早的线索。",
  },
  {
    id: "lib3",
    name: "人物弧光设计",
    category: "结构",
    tags: ["人物", "成长线"],
    updatedAt: "2 周前",
    whenToUse: "为主要人物规划贯穿全书的转变与动机时使用。",
    description: "以关键抉择为锚点,规划人物从初始状态到结局的成长弧线。",
  },
  {
    id: "lib4",
    name: "战斗场面编排",
    category: "节奏",
    tags: ["动作", "张力"],
    updatedAt: "上个月",
    whenToUse: "需要写出有空间感、有张力、招式清晰的战斗段落时使用。",
    description: "编排战斗的空间调度、招式节奏与情绪起伏,避免流水账。",
  },
];

// 官方目录(guest 可浏览与安装当前版本)。
const SK_OFFICIAL = [
  {
    id: "off1",
    publicId: "official-lore-audit",
    name: "世界观考据",
    version: "1.4.0",
    category: "设定考据",
    tags: ["设定", "自洽"],
    whenToUse: "对照世界观设定核查地理、器物、制度、时间线是否前后自洽时使用。",
    description: "对照已建立的世界设定,核查正文中的地理、器物、制度与时间线冲突,并列引用设定与正文原文。",
  },
  {
    id: "off2",
    publicId: "official-outline-expand",
    name: "章节大纲扩写",
    version: "2.1.0",
    category: "扩写",
    tags: ["大纲", "初稿"],
    whenToUse: "把一句话章纲扩展为分场景的详细大纲时使用。",
    description: "将粗章纲拆解为分场景大纲:场景目标、冲突、转折与出场人物。",
  },
  {
    id: "off3",
    publicId: "official-dialogue",
    name: "对白自然化",
    version: "1.0.3",
    category: "对白",
    tags: ["对白", "语气"],
    whenToUse: "对白读起来生硬、每个人说话都像同一个人时使用。",
    description: "按人物身份与处境调整对白语气、停顿与潜台词,让每个人说话有辨识度。",
  },
  {
    id: "off4",
    publicId: "official-timeline",
    name: "时间线校对",
    version: "1.1.0",
    category: "校对",
    tags: ["时间线", "连续性"],
    whenToUse: "多章之后需要核对事件先后、人物年龄与季节是否连续时使用。",
    description: "建立事件时间轴,标出与既有章节冲突的时间、年龄与季节错误。",
  },
];

// 市场目录(浏览与安装当前 approved 版本)。
const SK_MARKET = [
  {
    id: "mk1",
    publicId: "mkt-golden-three",
    name: "网文黄金三章",
    author: "老猫",
    installs: 3280,
    version: "2.1.0",
    category: "结构",
    tags: ["开篇", "留存"],
    whenToUse: "开篇前三章需要快速抓住读者、埋好钩子并建立追读动机时使用。",
    description: "按网文黄金三章模型重排开篇节奏:悬念前置、爽点密度、章末钩子。适合起点、番茄类男频长篇。",
    versions: [
      { version: "2.1.0", date: "2026-07-02", note: "补充女频开篇模板", status: "approved" },
      { version: "2.0.1", date: "2026-05-18", note: "修正钩子密度过高的问题", status: "revoked" },
      { version: "2.0.0", date: "2026-05-04", note: "重写为分场景指令", status: "superseded" },
    ],
  },
  {
    id: "mk2",
    publicId: "mkt-multiline",
    name: "多线叙事编排",
    author: "青梧",
    installs: 1470,
    version: "1.3.0",
    category: "结构",
    tags: ["群像", "多线"],
    whenToUse: "多条故事线并行推进,需要安排交汇点与信息释放节奏时使用。",
    description: "梳理多线叙事的时间轴与交汇点,标出信息释放与视角切换节奏。",
    versions: [
      { version: "1.3.0", date: "2026-06-20", note: "增加视角切换检查", status: "approved" },
      { version: "1.2.0", date: "2026-04-11", note: "初版", status: "superseded" },
    ],
  },
  {
    id: "mk3",
    publicId: "mkt-mystery",
    name: "悬疑埋雷器",
    author: "夜航船",
    installs: 962,
    version: "1.0.2",
    category: "结构",
    tags: ["悬疑", "反转"],
    whenToUse: "需要在前文埋设可回收的线索、并规划反转落点时使用。",
    description: "为悬疑线规划线索埋设与回收点,校验反转是否有据可循、是否提前泄底。",
    versions: [
      { version: "1.0.2", date: "2026-06-28", note: "修正线索台账格式", status: "approved" },
    ],
  },
  {
    id: "mk4",
    publicId: "mkt-light-novel",
    name: "轻小说吐槽腔",
    author: "苏打水",
    installs: 2140,
    version: "1.1.0",
    category: "文风",
    tags: ["轻小说", "吐槽"],
    whenToUse: "需要写出日式轻小说的第一人称吐槽语气时使用。",
    description: "调校第一人称叙述的吐槽节奏与自嘲密度,保留角色声音不油腻。",
    versions: [
      { version: "1.1.0", date: "2026-07-08", note: "降低吐槽密度上限", status: "approved" },
    ],
  },
];

Object.assign(window, {
  SK_CATEGORIES,
  SK_SOURCE_BADGE,
  SK_INSTALLED,
  SK_LIBRARY,
  SK_OFFICIAL,
  SK_MARKET,
});
