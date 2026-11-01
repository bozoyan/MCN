// screenplay/data.jsx — 剧本写作的 mock 数据。
// 剧本是 novel 的一种类型(novel.screenplay),三个样例:
//   sp1 剧集《夜航船》 单季(规划 8 集,实际 2 集) —— 季完全隐藏,左栏只有集列表
//   sp2 电影《山影渐落》 第一期暂不支持,保留作未来形态探索
//   sp3 剧集《旧河道》 两季 —— 季选择器 + 管理季,并覆盖「已超出规划」「未设定规划」
// 一个剧本作品保存整部剧集(ADR-0026),人物、地点、关系跨季共享,所以人物和关系
// 挂在 proj 上而不是季上。
// 全局名统一 SP_ 前缀,避免与其他原型脚本的全局名冲突。

/* ===================== 项目 ===================== */

const SP_PROJECTS = [
  {
    id: "sp1",
    title: "夜航船",
    subtitle: "Night Boat",
    kind: "series",          // 剧集
    genre: "历史 / 群像",
    // 来源作品指向作品库里那部同名小说(source_novel_id);为空就是原创。
    // 目标作品被删掉时不清空这个字段，只把来源标记成不可用。
    sourceId: "n1",
    // 只支持亚洲式一种格式，界面上不体现（views.jsx 里两处展示已注释掉）。
    format: "亚洲式",
    status: "writing",
    words: 12480,
    updated: "今天 15:04",
    cover: "ink",
    logline:
      "崇祯十六年冬，一艘从嘉兴开往南京的夜航船上，六个各怀心事的人被同一场大雾困了三天。",
  },
  {
    id: "sp2",
    title: "山影渐落",
    subtitle: "When the Mountains Fade",
    kind: "film",            // 电影
    // 第一期不支持电影剧本 —— 数据模型、创建流程和迁移都要单独设计。
    // 这条留在 mockup 里只作未来形态探索，界面上如实标出来，不假装能用。
    supported: false,
    genre: "文学 / 悬疑",
    sourceId: "n2",
    episodes: 1,
    format: "亚洲式",
    status: "planning",
    words: 3200,
    updated: "3 天前",
    cover: "mountains",
    logline:
      "一位退休制图师接到委托，为一座地图上不存在的山绘制等高线。",
  },
  {
    id: "sp3",
    title: "旧河道",
    subtitle: "The Old Riverbed",
    kind: "series",
    genre: "当代 / 家庭",
    sourceId: null,          // 原创，不改编
    format: "亚洲式",
    status: "writing",
    words: 41200,
    updated: "昨天 22:10",
    cover: "tree",
    logline:
      "一条填平了三十年的河道要重新挖开。泥翻上来的时候，沿岸四户人家的旧账也跟着翻上来了。",
  },
];

/* ===================== 季 ===================== */
// 季是持久化实体，但不强迫单季用户管理它：只有一季时 UI 完全隐藏季这一层，
// 唯一一季作为隐式当前季。planned 是本季规划集数，可为空；实际集数超过它
// 仍是有效状态，显示成 "5/4 集 · 已超出规划"，不阻断创作。
// 电影 sp2 没有季 —— 第一期不支持，也就不给它编数据。

const SP_SEASONS = [
  { id: "sn1",  proj: "sp1", no: 1, title: "",     planned: 8 },

  { id: "sn3a", proj: "sp3", no: 1, title: "淤沙", planned: 4 },   // 实际 5 集 → 已超出规划
  { id: "sn3b", proj: "sp3", no: 2, title: "开闸", planned: null }, // 未设定 → 只显示实际集数
];

/* ===================== 集 ===================== */
// 集号是季内位置，从 1 开始连续；跨季会从 1 重来，所以任何按集号显示的地方
// （出场矩阵列头、状态栏）都必须先限定在当前季内。

// outline 是这一集的大纲正文,整段 markdown 存在集上,由大纲页整段覆盖写回。
// 允许为空 —— 空的时候大纲页只显示提示文案,不造假内容。
const SP_EPISODES = [
  { id: "ep1", proj: "sp1", season: "sn1", label: "Ep 1", title: "登船", target: 45, state: "写作中",
    outline: [
      "## Logline",
      "开船前最后一刻登船的画师，和另外五个各有隐瞒的人一起被大雾困在船上。",
      "",
      "## 本集要做完的事",
      "- 六个人全部登场，各自的谎在这一集里只立不拆。",
      "- 江防图第一次出现，观众要知道它值钱，但不知道它为什么值钱。",
      "- 雾起、船停 —— 把「旅程」改写成「牢房」。",
      "",
      "## 人物弧光",
      "沈砚这一集只做一件事：不解释。他越沉默，画箱越重。",
      "周慎相反，他一路在说话，说的每一句都在替自己铺后路。",
      "",
      "## 主题",
      "同船的人不是同路的人。这一集先把「同」立起来，后面几集再逐层拆。",
    ].join("\n") },
  { id: "ep2", proj: "sp1", season: "sn1", label: "Ep 2", title: "雾锁", target: 45, state: "草稿",
    outline: [
      "## Logline",
      "雾第三天不散，船上的口粮开始要分配。",
      "",
      "## 待想清楚",
      "- 谁先提出分粮？由周慎提最省事，但也最早暴露他。",
    ].join("\n") },

  /* ---- sp3 第一季「淤沙」:规划 4 集,实际写到 5 集 ---- */
  { id: "e3a1", proj: "sp3", season: "sn3a", label: "Ep 1", title: "测量队",   target: 42, state: "定稿", outline: "" },
  { id: "e3a2", proj: "sp3", season: "sn3a", label: "Ep 2", title: "第一铲",   target: 42, state: "定稿", outline: "" },
  { id: "e3a3", proj: "sp3", season: "sn3a", label: "Ep 3", title: "水泥台阶", target: 42, state: "定稿", outline: "" },
  { id: "e3a4", proj: "sp3", season: "sn3a", label: "Ep 4", title: "旧照片",   target: 42, state: "定稿", outline: "" },
  { id: "e3a5", proj: "sp3", season: "sn3a", label: "Ep 5", title: "回南天",   target: 42, state: "定稿", outline: "" },

  /* ---- sp3 第二季「开闸」:未设定规划集数,在写第 3 集 ---- */
  { id: "e3b1", proj: "sp3", season: "sn3b", label: "Ep 1", title: "开闸",     target: 45, state: "定稿", outline: "" },
  { id: "e3b2", proj: "sp3", season: "sn3b", label: "Ep 2", title: "两本账",   target: 45, state: "修改中", outline: "" },
  { id: "e3b3", proj: "sp3", season: "sn3b", label: "Ep 3", title: "上游来水", target: 45, state: "写作中",
    outline: [
      "## Logline",
      "上游通知二十天后开闸。挖机停在砌死的那扇门前。",
      "",
      "## 结构",
      "- 前半集全是时间压力，后半集全是水声。",
      "- 门开不开这一集不给答案，但要让观众相信它一定会开。",
    ].join("\n") },
];

/* ===================== 场次 ===================== */
// pages 用八分之一页计数(制片行业惯例);minutes 为估算时长。
//
// 阶段 M 给场次补了四个字段(方案 §4.1),都可空:
//   title       事件短标题。列表、片段分组头和出场矩阵列头用它当显示名,
//               为空时回退显示 place —— 数据库里仍是空,不从 desc 截取回填。
//               **不进剧本正文**(§3.1):正文场次头保持「场号、地点 时间/内外」,
//               那是要导出给外部制作的标准剧本格式,不塞自造字段。
//   targetSecs  本场目标秒数(对应 target_duration_seconds)。与集目标、
//               正文估算 minutes、片段计划时长互不覆盖(§5.1)。null = 没填。
//   emotion     情绪标签数组
//   events      有序事件,每项 {title, summary, stateChange?}
//               events 里的 title 说的是「这个事件」,场次的 title 说的是「这一场」,
//               两个层级,不互相回填。
// emotion / events / title 是写后整理的产物:由「故事连续性维护」从本场完整正文
// 提取,作者可校正。所以还没写正文的场次(state 待写)这三项就是空的 —— 不能拿梗概
// 或大纲冒充已发生事实。targetSecs 是作者的创作意图,只手填。
// analysisStale: true 表示正文改过、整理结果还没重跑 —— 旧值保留并提示待核对。
//
// ie 增加第三取值「内外」(§3.1),用于一场戏连续覆盖室内与室外的行动。
// 它和「未指定」不是一回事:「内外」是明确选择。

const SP_SCENES = [
  {
    id: "s1", proj: "sp1", ep: "ep1", no: 1, ie: "外", place: "嘉兴码头", time: "昏",
    pages: "1 6/8", minutes: 2, lines: 6, cast: ["沈砚", "船家老崔"],
    beat: "b1", state: "定稿",
    desc: "沈砚在开船前最后一刻登船，把一只画箱塞进舱底。老崔要价，他不还。",
    title: "登船", targetSecs: 150,
    emotion: ["紧迫", "戒备"],
    events: [
      { title: "最后一刻登船", summary: "沈砚在跳板收起前上船，画箱不离手。", stateChange: "沈砚离开陆地，这一集之后下不了船。", },
      { title: "不还价", summary: "老崔要三倍价钱，沈砚把银子放在船板上就走。", stateChange: "老崔记住了这个不还价的客人。", },
    ],
  },
  {
    id: "s2", proj: "sp1", ep: "ep1", no: 2, ie: "内", place: "客船前舱", time: "夜",
    pages: "2 4/8", minutes: 3, lines: 11, cast: ["沈砚", "周慎", "阿茴"],
    beat: "b2", state: "定稿",
    desc: "六人分坐前舱两侧。周慎认出沈砚的手，沈砚不认。阿茴替小姐讨一盏灯。",
    title: "认手", targetSecs: 210,
    emotion: ["试探", "克制"],
    events: [
      { title: "周慎认手", summary: "周慎从沈砚握杯的姿势认出那是拿笔的手。", stateChange: "沈砚的画师身份对周慎不再是秘密。", },
      { title: "讨一盏灯", summary: "阿茴替柳氏向前舱讨灯，沈砚递出一支短烛。", stateChange: "沈砚与阿茴之间第一次有来往。", },
    ],
  },
  {
    id: "s3", proj: "sp1", ep: "ep1", no: 3, ie: "内", place: "客船后舱", time: "同时",
    pages: "1 2/8", minutes: 1.5, lines: 4, cast: ["柳氏", "阿茴"],
    beat: "b2", state: "修改中",
    desc: "柳氏把嫁妆匣子推到床底，让阿茴对外只说是走亲戚。",
    title: "藏匣", targetSecs: null,
    emotion: ["慌乱", "隐瞒"],
    events: [
      { title: "推匣入床底", summary: "柳氏把嫁妆匣子推进床底。", stateChange: "匣子的位置只有柳氏和阿茴知道。", },
      { title: "对外的说法", summary: "柳氏教阿茴对外只说是走亲戚。", stateChange: "阿茴开始替柳氏撒谎。", },
    ],
    analysisStale: true,   // 正文在改，情绪与事件是上一版的结果，待核对
  },
  {
    id: "s4", proj: "sp1", ep: "ep1", no: 4, ie: "内", place: "客船前舱", time: "夜",
    pages: "3 1/8", minutes: 4, lines: 14, cast: ["沈砚", "周慎"],
    beat: "b3", state: "草稿",
    desc: "周慎摊开一张残破的江防图求沈砚补全，沈砚看出这不是民用的图。",
    title: "江防图", targetSecs: 240,
    emotion: ["试探", "警觉"],
    events: [
      { title: "摊开残图", summary: "周慎拿出一张残破的江防图，请沈砚补全缺的那一角。", },
      { title: "看出来路", summary: "沈砚认出这不是民用图，没有说破，只说画不了。", stateChange: "沈砚知道周慎的来路不干净。", },
    ],
  },
  {
    // 「内外」的样例：沈砚从舱里走到船舷，一场戏连续覆盖室内与室外，
    // 不因为跨了空间就拆成两场（§3.1）。具体怎么走写在动作描述里。
    id: "s5", proj: "sp1", ep: "ep1", no: 5, ie: "内外", place: "舱口与船舷", time: "拂晓",
    pages: "0 6/8", minutes: 1, lines: 2, cast: ["沈砚"],
    beat: "b3", state: "草稿",
    desc: "雾起。沈砚从舱里走到船舷，看船灯一盏一盏灭下去，只剩他舱口那一盏。",
    title: "灯灭", targetSecs: 60,
    emotion: ["压抑"],
    events: [
      { title: "雾起船停", summary: "江面起雾，船灯一盏一盏灭下去。", stateChange: "旅程变成困局。", },
    ],
  },
  {
    id: "s6", proj: "sp1", ep: "ep1", no: 6, ie: "内", place: "客船前舱", time: "日",
    pages: "2 0/8", minutes: 2.5, lines: 8, cast: ["沈砚", "周慎", "柳氏", "船家老崔"],
    beat: "b4", state: "待写",
    desc: "天亮，船没动。老崔说雾三天不散，谁也别想下船。",
    title: "封船", targetSecs: null,
    emotion: [],
    events: [],
  },
  {
    id: "s7", proj: "sp1", ep: "ep2", no: 1, ie: "内", place: "客船前舱", time: "日",
    pages: "4 2/8", minutes: 5, lines: 16, cast: ["沈砚", "周慎", "柳氏"],
    beat: "b5", state: "草稿",
    desc: "第二天，舱里开始分派口粮。周慎把自己那份让给柳氏，动机不明。",
    title: "让粮", targetSecs: null,
    emotion: ["猜疑"],
    events: [
      { title: "分派口粮", summary: "舱里按人头分粮，周慎把自己那份让给柳氏。", stateChange: "周慎开始在船上收买人。", },
    ],
  },
  {
    id: "s8", proj: "sp1", ep: "ep2", no: 2, ie: "外", place: "船头", time: "夜",
    pages: "4 0/8", minutes: 4, lines: 9, cast: ["沈砚", "阿茴"],
    beat: "b5", state: "待写",
    desc: "阿茴撞见沈砚在雾里烧一卷纸。",
    title: "", targetSecs: null,
    emotion: [],
    events: [],
  },

  /* ---- sp2 电影《山影渐落》:筹备中,只开了头三场,没有剧集层 ---- */
  {
    id: "f1", proj: "sp2", ep: null, no: 1, ie: "内", place: "制图室", time: "日",
    pages: "2 2/8", minutes: 2.5, lines: 5, cast: ["柯瓦奇", "邮差"],
    beat: "fb1", state: "草稿",
    desc: "柯瓦奇收到一封没有寄件人的委托，附一张空白的等高线纸。",
    title: "", targetSecs: null,
    emotion: [], events: [],
  },
  {
    id: "f2", proj: "sp2", ep: null, no: 2, ie: "外", place: "小镇邮局门口", time: "日",
    pages: "1 4/8", minutes: 1.5, lines: 3, cast: ["柯瓦奇", "邮差"],
    beat: "fb1", state: "待写",
    desc: "邮差记不清是谁交的信。柯瓦奇抬头看山，山在原来的位置。",
    title: "", targetSecs: null,
    emotion: [], events: [],
  },
  {
    id: "f3", proj: "sp2", ep: null, no: 3, ie: "内", place: "制图室", time: "夜",
    pages: "3 0/8", minutes: 3, lines: 2, cast: ["柯瓦奇"],
    beat: "fb2", state: "待写",
    desc: "他把镇上所有年份的地图铺开，一张一张对，找那座不在的山。",
    title: "", targetSecs: null,
    emotion: [], events: [],
  },

  /* ---- sp3《旧河道》第一季「淤沙」:已完结,每集两场 ---- */
  {
    id: "a11", proj: "sp3", ep: "e3a1", no: 1, ie: "外", place: "旧河堤", time: "日",
    pages: "2 2/8", minutes: 3, lines: 7, cast: ["陈立冬", "老赵"],
    beat: "a1b1", state: "定稿",
    desc: "陈立冬带测量仪回镇，站在填平的河道上找不到基准点。老赵说这底下埋着东西。",
    title: "找不到基准点", targetSecs: null,
    emotion: [], events: [],
  },
  {
    id: "a12", proj: "sp3", ep: "e3a1", no: 2, ie: "内", place: "周玉兰老屋堂屋", time: "昏",
    pages: "3 0/8", minutes: 4, lines: 12, cast: ["陈立冬", "周玉兰"],
    beat: "a1b2", state: "定稿",
    desc: "婶侄二十年后第一次同桌吃饭。周玉兰问他是回来量地还是回来拆房。",
    title: "回来量地还是拆房", targetSecs: null,
    emotion: [], events: [],
  },
  {
    id: "a21", proj: "sp3", ep: "e3a2", no: 1, ie: "外", place: "旧河堤", time: "晨",
    pages: "1 6/8", minutes: 2, lines: 5, cast: ["陈立冬", "吴国梁", "老赵"],
    beat: "a2b1", state: "定稿",
    desc: "开工第一铲。吴国梁来看，只说了一句「往下三米就别挖了」。",
    title: "第一铲", targetSecs: null,
    emotion: [], events: [],
  },
  {
    id: "a22", proj: "sp3", ep: "e3a2", no: 2, ie: "内", place: "五金店", time: "夜",
    pages: "2 4/8", minutes: 3, lines: 10, cast: ["陈立冬", "吴小满"],
    beat: "a2b2", state: "定稿",
    desc: "陈立冬来买卷尺。吴小满认出他，说你父亲当年也是在我家店里买的绳。",
    title: "你父亲买的绳", targetSecs: null,
    emotion: [], events: [],
  },
  {
    id: "a31", proj: "sp3", ep: "e3a3", no: 1, ie: "外", place: "河底", time: "日",
    pages: "2 0/8", minutes: 2.5, lines: 4, cast: ["陈立冬", "老赵"],
    beat: "a3b1", state: "定稿",
    desc: "挖到三米，露出一截水泥台阶——河道原本不该有台阶。",
    title: "水泥台阶", targetSecs: null,
    emotion: [], events: [],
  },
  {
    id: "a32", proj: "sp3", ep: "e3a3", no: 2, ie: "内", place: "水利站办公室", time: "夜",
    pages: "2 6/8", minutes: 3.5, lines: 11, cast: ["陈立冬", "吴国梁"],
    beat: "a3b2", state: "定稿",
    desc: "吴国梁带着当年的施工图来，图上没有台阶。两个人都知道对方知道。",
    title: "图上没有台阶", targetSecs: null,
    emotion: [], events: [],
  },
  {
    id: "a41", proj: "sp3", ep: "e3a4", no: 1, ie: "内", place: "周玉兰老屋堂屋", time: "日",
    pages: "1 4/8", minutes: 2, lines: 6, cast: ["周玉兰", "吴小满"],
    beat: "a4b1", state: "定稿",
    desc: "吴小满替父亲送米。周玉兰从相框背后抽出一张合影，上面站着四个人。",
    title: "四个人的合影", targetSecs: null,
    emotion: [], events: [],
  },
  {
    id: "a42", proj: "sp3", ep: "e3a4", no: 2, ie: "外", place: "旧河堤", time: "昏",
    pages: "2 2/8", minutes: 3, lines: 8, cast: ["陈立冬", "吴小满"],
    beat: "a4b2", state: "定稿",
    desc: "吴小满把合影给陈立冬看。第四个人他不认识，婶婶说那是他父亲的工友。",
    title: "第四个人", targetSecs: null,
    emotion: [], events: [],
  },
  {
    id: "a51", proj: "sp3", ep: "e3a5", no: 1, ie: "内", place: "五金店", time: "日",
    pages: "2 0/8", minutes: 2.5, lines: 9, cast: ["吴国梁", "吴小满"],
    beat: "a5b1", state: "定稿",
    desc: "回南天，墙在渗水。吴小满第一次直接问父亲：河底下埋的是不是人。",
    title: "回南天", targetSecs: null,
    emotion: [], events: [],
  },
  {
    id: "a52", proj: "sp3", ep: "e3a5", no: 2, ie: "外", place: "河底", time: "夜",
    pages: "1 2/8", minutes: 1.5, lines: 2, cast: ["陈立冬"],
    beat: "a5b2", state: "定稿",
    desc: "陈立冬一个人下到坑里，用手电照那截台阶，往下还有第二级。",
    title: "第二级", targetSecs: null,
    emotion: [], events: [],
  },

  /* ---- sp3 第二季「开闸」:当前季,在写第 3 集 ---- */
  {
    id: "b11", proj: "sp3", ep: "e3b1", no: 1, ie: "外", place: "旧河堤", time: "晨",
    pages: "2 4/8", minutes: 3, lines: 9, cast: ["陈立冬", "吴国梁", "老赵"],
    beat: "b1b1", state: "定稿",
    desc: "上游开闸放水，工期被压到二十天。吴国梁反过来催他快挖。",
    title: "二十天", targetSecs: null,
    emotion: [], events: [],
  },
  {
    id: "b12", proj: "sp3", ep: "e3b1", no: 2, ie: "内", place: "镇政府会议室", time: "日",
    pages: "3 2/8", minutes: 4, lines: 14, cast: ["陈立冬", "吴国梁", "周玉兰"],
    beat: "b1b2", state: "定稿",
    desc: "征迁听证会。周玉兰当众说老屋不搬，理由是屋底下压着她男人的坟。",
    title: "老屋不搬", targetSecs: null,
    emotion: [], events: [],
  },
  {
    id: "b13", proj: "sp3", ep: "e3b1", no: 3, ie: "内", place: "五金店", time: "夜",
    pages: "1 6/8", minutes: 2, lines: 7, cast: ["吴小满", "陈立冬"],
    beat: "b1b2", state: "定稿",
    desc: "吴小满把父亲当年的工资本拿出来：有一个月多领了四个人的钱。",
    title: "多领的那个月", targetSecs: null,
    emotion: [], events: [],
  },
  {
    id: "b21", proj: "sp3", ep: "e3b2", no: 1, ie: "内", place: "水利站办公室", time: "日",
    pages: "3 0/8", minutes: 3.5, lines: 12, cast: ["陈立冬", "老赵"],
    beat: "b2b1", state: "修改中",
    desc: "两本账对不上。老赵松口：当年填河那晚，他开的是运土车，来回跑了三趟。",
    title: "来回三趟", targetSecs: null,
    emotion: [], events: [],
  },
  {
    id: "b22", proj: "sp3", ep: "e3b2", no: 2, ie: "内", place: "周玉兰老屋堂屋", time: "夜",
    pages: "2 2/8", minutes: 3, lines: 10, cast: ["陈立冬", "周玉兰"],
    beat: "b2b2", state: "修改中",
    desc: "陈立冬把工资本推过去。周玉兰不看，只说你父亲不是失踪，是没上船。",
    title: "没上船", targetSecs: null,
    emotion: [], events: [],
  },
  {
    id: "b31", proj: "sp3", ep: "e3b3", no: 1, ie: "外", place: "河底", time: "日",
    pages: "2 0/8", minutes: 2.5, lines: 6, cast: ["陈立冬", "吴小满", "老赵"],
    beat: "b3b1", state: "草稿",
    desc: "第二级台阶下面是一道砌死的门。老赵不肯再挖，把机器熄了火。",
    title: "", targetSecs: null,
    emotion: [], events: [],
  },
  {
    id: "b32", proj: "sp3", ep: "e3b3", no: 2, ie: "外", place: "旧河堤", time: "昏",
    pages: "1 4/8", minutes: 2, lines: 4, cast: ["陈立冬", "吴国梁"],
    beat: "b3b2", state: "待写",
    desc: "上游的水已经到了。吴国梁站在堤上，问他挖到底想要什么。",
    title: "", targetSecs: null,
    emotion: [], events: [],
  },
];

/* ===================== 剧本正文(元素流) ===================== */
// t: scene 场次 / cast 出场人物 / action 动作 / char 角色 / paren 括号
//    dialog 对话 / trans 转场 / note 注释 / sub 字幕
//
// ---- 关于 sub(字幕):保留类型,但不按对齐拆类型。已考虑过,决定不做 ----
//
// 1) 工业软件里没有「字幕」这个元素类型。Final Draft 的元素集是 Scene Heading /
//    Action / Character / Parenthetical / Dialogue / Transition / Shot / General,
//    SUPER 就是一条顶格的 Action(`SUPER: "Daytona Beach, 1966"`),不居中,和动作
//    同一个左边距。Celtx / WriterDuet / Arc Studio 沿用同一套。Fountain 有居中,
//    但那是 `> text <` 这个排版标记,解析出来叫 "centered text" 而不是 "subtitle"
//    —— 名字本身就说明它描述对齐,和内容语义正交。
//
// 2) 我们仍然保留 sub 类型,因为中文的情况不同:年代戏/群像戏几乎每场都要标时空,
//    频率远高于美式;而且中文没有全大写这个手段,美式靠 `SUPER:` + 全大写既能肉眼
//    识别又能正则提取,中文写「字幕:」只是纯文本约定,手滑就混进正文。独立类型换来的
//    是导出可靠提取、AI 生成可明确指定、渲染统一 —— 是真实的下游需求。
//
// 3) 但不按对齐拆成两个类型。判据:下游有没有消费者只要居中字幕、不要不居中的?
//    没有 —— 后期要的是「所有上屏文字」,导出要的也是全部。拆了每个消费者都得查两个
//    类型。更根本的是,对齐是成片的属性不是剧本的属性:编剧写的是「这里上一条字幕,
//    内容是崇祯十六年冬」,它在屏幕上居中还是压左下角由导演和后期定。剧本记录意图,
//    不记录成片排版 —— Final Draft 让 SUPER 顶格就是这个道理。
//    长短不一交给渲染层自己判断(见 screenplay.css 的 .sp-el--sub),数据模型不参与。
//
// 4) 真正存在的区分是另外两个,都不是对齐,现在都不加:
//    - SUPER(叠在画面上) vs TITLE CARD(黑底独立卡):工业上确实不同,影响后期做法和
//      是否占片长。但这是属性(overBlack),不是类型。
//    - 对白译文字幕(角色说方言,底下走译文):语义确实不同 —— 绑定一条台词、有说话人、
//      与台词同时序。但它属于对白的属性,不是独立元素;当前用 paren 已能表达。
//    两个都没有下游消费者(没有导出格式要、没有 AI 工具要、没有统计要),按 AGENTS.md
//    第 4 条不提前抽象。等真要做后期交接单或 EDL 导出时再加,那时才知道该分几类。
//
// 5) Flutter 侧的代价也支持不拆:加一个元素类型 = enum + migration + 工具栏第 9 个
//    格子 + 快捷键,而工具栏现在 ⌘1–⌘8 正好八个。为一个纯渲染差异付这个代价不划算。

const SP_SCRIPT = {
  s1: [
    { t: "scene", no: 1, ie: "外", place: "嘉兴码头", time: "昏" },
    { t: "cast", names: ["沈砚", "船家老崔"] },
    // 两条字幕相邻不是凑数 —— 第一集开头本来就是「免责 + 定场」两条,同时也覆盖了
    // 字幕的两个渲染状态:长的折行后收成居中窄栏、文本左对齐,短的整行居中。
    { t: "sub", text: "本剧为虚构作品，剧中人物、机构、事件均属虚构，与史实无关" },
    { t: "sub", text: "崇祯十六年 冬" },
    {
      t: "action",
      text:
        "水面已经收了光。夜航船横在埠头，篷布上一层白霜。老崔蹲在船头数铜钱，数到一半停住——岸上来了个人，青布直裰，怀里抱着一只窄长的画箱，走得不快，也不看人。",
    },
    { t: "char", name: "船家老崔" },
    { t: "dialog", text: "客官，满了。" },
    { t: "action", text: "沈砚不答，把一小锭银子搁在船板上。" },
    { t: "char", name: "船家老崔" },
    { t: "paren", text: "不接" },
    { t: "dialog", text: "满了就是满了。您明早还有一班。" },
    { t: "char", name: "沈砚" },
    { t: "dialog", text: "明早我就不在了。" },
    {
      t: "action",
      text: "老崔抬头看他。沈砚已经跨了上来，自己找了个舱口坐下，画箱竖在膝间，两只手扣住箱角。",
    },
    { t: "note", text: "沈砚全场只说两句话。第一句报价，第二句不是解释，是通知。" },
    { t: "trans", text: "切至：" },
  ],
  s2: [
    { t: "scene", no: 2, ie: "内", place: "客船前舱", time: "夜" },
    { t: "cast", names: ["沈砚", "周慎", "阿茴", "柳氏（画外）"] },
    {
      t: "action",
      text:
        "前舱不到两丈，两侧各一条通铺。一盏油灯挂在梁上，人一动，影子就在舱壁上晃。周慎坐在最里，六十上下，官服早换了，手里盘一串已经磨得发白的念珠。",
    },
    { t: "char", name: "周慎" },
    { t: "dialog", text: "先生这手，是拿笔的手。" },
    { t: "action", text: "沈砚把手收进袖里。" },
    { t: "char", name: "沈砚" },
    { t: "dialog", text: "拿桨也是这双手。" },
    { t: "char", name: "周慎" },
    { t: "paren", text: "笑" },
    { t: "dialog", text: "拿桨的手不这么白。" },
    {
      t: "action",
      text: "舱门帘一掀，阿茴探进半个身子，十六七岁，头发用一根木簪别着。她看了一圈，径直朝梁上那盏灯去。",
    },
    { t: "char", name: "阿茴" },
    { t: "dialog", text: "这灯，能不能挪一盏到后舱？我家小姐怕黑。" },
    { t: "char", name: "周慎" },
    { t: "dialog", text: "一船就这一盏。" },
    { t: "action", text: "沈砚从画箱里取出一支短烛，递过去。阿茴没接，先看了周慎一眼。" },
    { t: "char", name: "沈砚" },
    { t: "dialog", text: "烧完了再来拿。" },
    { t: "note", text: "沈砚第一次主动给别人东西——给的是光。第 6 集他要收回这盏灯。" },
  ],
  s3: [
    { t: "scene", no: 3, ie: "内", place: "客船后舱", time: "同时" },
    { t: "cast", names: ["柳氏", "阿茴"] },
    {
      t: "action",
      text:
        "后舱只一张板床，柳氏跪在床边，把一只朱漆匣子往床底推。推到一半，手停了，又拉回来，打开，取出一支金簪塞进袖口，这才把匣子推到底。",
    },
    { t: "char", name: "柳氏" },
    { t: "dialog", text: "谁问，就说是回娘家。" },
    { t: "char", name: "阿茴" },
    { t: "dialog", text: "小姐，前头有位老先生，看着像见过官面的。" },
    { t: "char", name: "柳氏" },
    { t: "paren", text: "把短烛立在床头" },
    { t: "dialog", text: "见过官面的，都不问人从哪儿来。" },
  ],

  f1: [
    { t: "scene", no: 1, ie: "内", place: "制图室", time: "日" },
    { t: "cast", names: ["柯瓦奇", "邮差"] },
    {
      t: "action",
      text:
        "整面墙都是地图，压得平平整整，边角对齐。柯瓦奇七十岁，站在长桌前削一支铅笔，削了很久，笔尖已经够尖了他还在削。门被敲了两下。",
    },
    { t: "char", name: "邮差" },
    { t: "dialog", text: "柯瓦奇先生，挂号。" },
    { t: "action", text: "一只牛皮纸信封。柯瓦奇翻到背面——寄件人一栏是空的。他拆开，里面只有一张纸：印好了图廓、比例尺、图例，中间什么也没有。" },
    { t: "char", name: "柯瓦奇" },
    { t: "dialog", text: "谁交的？" },
    { t: "char", name: "邮差" },
    { t: "paren", text: "已经在下楼" },
    { t: "dialog", text: "早上就在筐里了。" },
    { t: "note", text: "全片第一个镜头到最后一个镜头，这面墙上的地图会少一张。" },
  ],

  /* ---- sp3 第二季:只有写过的几场有正文，其余留在「只有梗概」状态 ---- */
  b12: [
    { t: "scene", no: 2, ie: "内", place: "镇政府会议室", time: "日" },
    { t: "cast", names: ["陈立冬", "吴国梁", "周玉兰"] },
    {
      t: "action",
      text:
        "长条桌，二十来人。投影上是征迁范围图，红线从河堤压过老屋那一排。陈立冬坐在靠门的位置，手边摊着测量记录，没有翻。",
    },
    { t: "char", name: "吴国梁" },
    { t: "dialog", text: "补偿按新标准，一户不落。有意见现在提。" },
    { t: "action", text: "没有人说话。周玉兰把凳子往后推了半尺，站起来。" },
    { t: "char", name: "周玉兰" },
    { t: "dialog", text: "我那间不搬。" },
    { t: "char", name: "吴国梁" },
    { t: "paren", text: "没抬头" },
    { t: "dialog", text: "婶，钱不够可以谈。" },
    { t: "char", name: "周玉兰" },
    { t: "dialog", text: "不是钱。屋底下压着我男人。" },
    {
      t: "action",
      text: "投影的风扇在响。吴国梁翻页的手停了一下，又翻了过去。陈立冬这才抬起头，看的不是婶婶，是吴国梁那只手。",
    },
    { t: "note", text: "全场没有一个人问「压着」是什么意思——镇上没人需要问。" },
    { t: "trans", text: "切至：" },
  ],
  b21: [
    { t: "scene", no: 1, ie: "内", place: "水利站办公室", time: "日" },
    { t: "cast", names: ["陈立冬", "老赵"] },
    {
      t: "action",
      text:
        "两本工资册摊在图纸上，一本镇里的，一本工程队的。同一个月，工程队多发了四个人的工钱。老赵站在门口，没进来。",
    },
    { t: "char", name: "陈立冬" },
    { t: "dialog", text: "赵叔，八三年冬月，你开的是哪台车。" },
    { t: "char", name: "老赵" },
    { t: "dialog", text: "记不清了。" },
    { t: "action", text: "陈立冬把册子转了个方向，推到门口。老赵没有低头看。" },
    { t: "char", name: "陈立冬" },
    { t: "dialog", text: "那晚上运土，你跑了三趟。" },
    { t: "char", name: "老赵" },
    { t: "paren", text: "很久" },
    { t: "dialog", text: "……第三趟没装土。" },
    { t: "note", text: "这一句一说出口，第二季就没有回头路了。位置不能再往后挪。" },
  ],
  b31: [
    { t: "scene", no: 1, ie: "外", place: "河底", time: "日" },
    { t: "cast", names: ["陈立冬", "吴小满", "老赵"] },
    {
      t: "action",
      text:
        "坑已经挖到五米。第二级台阶下面露出一道砖墙，砌得整齐，中间是一扇封死的门框。吴小满蹲在坑沿上往下看，没有下来。",
    },
    { t: "char", name: "老赵" },
    { t: "dialog", text: "到这儿吧。" },
    { t: "action", text: "他把挖掘机熄了火。发动机停下来之后，坑里安静得能听见水声——上游的水已经在动了。" },
    { t: "char", name: "陈立冬" },
    { t: "dialog", text: "还有二十天。" },
    { t: "char", name: "老赵" },
    { t: "dialog", text: "水不等人。" },
  ],
};

/* ===================== 节拍 ===================== */

const SP_BEATS = [
  { id: "b1", proj: "sp1", ep: "ep1", act: "第一幕", title: "登船", scenes: [1], pages: "1 6/8",
    desc: "把主角放进一个他不能退出的空间。沈砚不问价、不还价，说明他在赶时间。" },
  { id: "b2", proj: "sp1", ep: "ep1", act: "第一幕", title: "六个人各据一角", scenes: [2, 3], pages: "3 6/8",
    desc: "一次性交代全部人物与各自的谎。给观众六个问题，一个也不答。" },
  { id: "b3", proj: "sp1", ep: "ep1", act: "第二幕", title: "第一张图", scenes: [4, 5], pages: "3 7/8",
    desc: "周慎摊开江防图 —— 全剧的麦高芬第一次出现。雾同时起，退路关闭。" },
  { id: "b4", proj: "sp1", ep: "ep1", act: "第二幕", title: "船不动了", scenes: [6], pages: "2 0/8",
    desc: "把封闭空间坐实。观众此刻应当明白：这不是一趟旅程，是一间牢房。" },
  { id: "b5", proj: "sp1", ep: "ep2", act: "第二幕", title: "口粮与人情", scenes: [1, 2], pages: "8 2/8",
    desc: "资源开始有限，善意开始有价。周慎让粮，是第一次收买。" },

  { id: "fb1", proj: "sp2", ep: null, act: "第一幕", title: "空白的委托", scenes: [1, 2], pages: "3 6/8",
    desc: "一份没有寄件人的委托。观众和主角同时拿到唯一的线索：一张什么都没画的图。" },
  { id: "fb2", proj: "sp2", ep: null, act: "第一幕", title: "对不上的地图", scenes: [3], pages: "3 0/8",
    desc: "他开始核对。这里要让观众先于主角一步怀疑：不是山不存在，是地图被人动过。" },

  /* ---- sp3 第一季「淤沙」 ---- */
  { id: "a1b1", proj: "sp3", ep: "e3a1", act: "第一幕", title: "找不到基准点", scenes: [1], pages: "2 2/8",
    desc: "回乡的人第一件事是量地，结果连量的起点都没了。开篇就把「地形被改过」摆在明面上。" },
  { id: "a1b2", proj: "sp3", ep: "e3a1", act: "第二幕", title: "一顿饭", scenes: [2], pages: "3 0/8",
    desc: "婶侄二十年后第一次同桌。这一场只交代关系，不交代真相。" },
  { id: "a2b1", proj: "sp3", ep: "e3a2", act: "第一幕", title: "往下三米", scenes: [1], pages: "1 6/8",
    desc: "反派第一次出场就给了确切数字。观众会记住三米，这是全季的倒计时。" },
  { id: "a2b2", proj: "sp3", ep: "e3a2", act: "第二幕", title: "买绳的人", scenes: [2], pages: "2 4/8",
    desc: "第二条线接上：父亲当年也来过这家店。用一件日用品把两代人扣在一起。" },
  { id: "a3b1", proj: "sp3", ep: "e3a3", act: "第一幕", title: "第一级台阶", scenes: [1], pages: "2 0/8",
    desc: "三米到了。台阶是全剧第一个不能用巧合解释的东西。" },
  { id: "a3b2", proj: "sp3", ep: "e3a3", act: "第二幕", title: "图上没有", scenes: [2], pages: "2 6/8",
    desc: "两个人都知道对方知道，谁也不说破。这一场决定了后面所有对手戏的打法。" },
  { id: "a4b1", proj: "sp3", ep: "e3a4", act: "第一幕", title: "相框背后", scenes: [1], pages: "1 4/8",
    desc: "四个人的合影。第四个人是本季最后一颗扣子，这里只让观众看一眼。" },
  { id: "a4b2", proj: "sp3", ep: "e3a4", act: "第二幕", title: "他是谁", scenes: [2], pages: "2 2/8",
    desc: "问出口，但不给答案。答案压到第二季第 2 集的工资本。" },
  { id: "a5b1", proj: "sp3", ep: "e3a5", act: "第一幕", title: "回南天", scenes: [1], pages: "2 0/8",
    desc: "女儿第一次直接问父亲。墙在渗水，人也一样，藏不住了。" },
  { id: "a5b2", proj: "sp3", ep: "e3a5", act: "第二幕", title: "第二级", scenes: [2], pages: "1 2/8",
    desc: "季终不给答案，给一个更深的坑。规划里本来没有这一集，写到这儿才发现停不住。" },

  /* ---- sp3 第二季「开闸」:第 3 集排到第四幕,幕数不设上限 ---- */
  { id: "b1b1", proj: "sp3", ep: "e3b1", act: "第一幕", title: "二十天", scenes: [1], pages: "2 4/8",
    desc: "上游开闸，外部时钟启动。这一季所有人的动作都被这个数字推着走。" },
  { id: "b1b2", proj: "sp3", ep: "e3b1", act: "第二幕", title: "屋底下压着人", scenes: [2, 3], pages: "5 0/8",
    desc: "听证会当众说破，五金店私下补一刀。公开场合的沉默比对峙更有信息量。" },
  { id: "b2b1", proj: "sp3", ep: "e3b2", act: "第一幕", title: "第三趟没装土", scenes: [1], pages: "3 0/8",
    desc: "本季的不可逆点。老赵松口之后，故事不能再退回「也许是误会」。" },
  { id: "b2b2", proj: "sp3", ep: "e3b2", act: "第二幕", title: "没上船", scenes: [2], pages: "2 2/8",
    desc: "婶婶把二十年前那句话改了一个字。观众要在这里重新理解第一季的每一场。" },
  { id: "b3b1", proj: "sp3", ep: "e3b3", act: "第一幕", title: "熄火", scenes: [1], pages: "2 0/8",
    desc: "砌死的门。挖机停下来那一秒，声音全部让给水。" },
  { id: "b3b2", proj: "sp3", ep: "e3b3", act: "第二幕", title: "水到了", scenes: [2], pages: "1 4/8",
    desc: "反派问的问题主角答不上来——他确实不知道自己要什么。" },
  { id: "b3b3", proj: "sp3", ep: "e3b3", act: "第三幕", title: "开门", scenes: [], pages: "0 0/8",
    desc: "开门要花多少篇幅还没定。也可能整集都不开，把门留到下一集。" },
  { id: "b3b4", proj: "sp3", ep: "e3b3", act: "第四幕", title: "谁在门后", scenes: [], pages: "0 0/8",
    desc: "先占位。第四幕存不存在取决于上一拍怎么落。" },
];

/* ===================== 制作共享:资产、视频模型、提示词引用 ===================== */

// 片段与任务只在制片页(drama/data.jsx);这里是剧本与制片共用的资产库、视频模型和提示词引用格式。
// prompt 里的资源引用沿用聊天的 <user-remind> 标签，界面渲染成 @chip(见 spPromptParts)。
// 引用身份是 path 里的资产 ID，label 只用来显示 —— 资产改名不影响引用。
// 实际生成输入由画布上的输入连线持有，引用只说明「这个参考在句子里干什么」。
function spRef(assetId) {
  const a = SP_ASSETS.find((x) => x.id === assetId);
  return `<user-remind type='assets' path='assets/${assetId}' label='${a ? a.name : assetId}'></user-remind>`;
}

// 统一资产库(AppDatabase.Assets)的 mock：剧本与制作画布共用这一份。
// 角色仍是剧本人物，这里登记的是「角色图」这类可上传的图片资产。
// source 记录来源；导演输出是普通图片/视频资产，带上工程与版本。
const SP_ASSETS = [
  { id: "a_shen",   type: "image", name: "沈砚 · 青衫",   char: "沈砚", tone: "teal",  source: "导入", spec: "1024×1024" },
  { id: "a_zhou",   type: "image", name: "周慎 · 旧便袍", char: "周慎", tone: "umber", source: "生图", spec: "1024×1024" },
  { id: "a_ahui",   type: "image", name: "阿茴 · 木簪",   char: "阿茴", tone: "rose",  source: "生图", spec: "1024×1024" },
  { id: "a_dock",   type: "image", name: "嘉兴码头 · 昏", tone: "dusk",  source: "导入", spec: "1920×1080" },
  { id: "a_cabin",  type: "image", name: "客船前舱 · 夜", tone: "lamp",  source: "生图", spec: "1920×1080" },
  { id: "a_candle", type: "image", name: "短烛",          tone: "lamp",  source: "导入", spec: "1024×1024" },
  { id: "a_pv_face", type: "image", name: "构图 · 对坐", tone: "lamp",  source: "导演输出 · 前舱布景 · 机位 A v1", spec: "720×1280" },
  { id: "a_pv_pan1", type: "video", name: "预演 · 摇进前舱 v1", tone: "lamp", source: "导演输出 · 前舱布景 · 机位 B v1", spec: "720×1280 · 11s" },
  { id: "a_pv_pan2", type: "video", name: "预演 · 摇进前舱 v2", tone: "lamp2", source: "导演输出 · 前舱布景 · 机位 B v2", spec: "720×1280 · 11s" },
  { id: "a_haozi",  type: "audio", name: "船夫号子 · 录音", tone: "dusk", source: "导入", spec: "0:18 · AAC" },
  { id: "a_style_hist", type: "style", name: "写实历史剧", tone: "lamp", source: "模板",
    text: "写实历史剧质感，胶片颗粒，低饱和暖光，画面内不出现任何现代物件。" },
  { id: "a_stage_cabin", type: "director", name: "前舱布景", tone: "lamp", source: "第 2 场导演工程", spec: "3 人 · 2 机位" },
  // 生成结果：每次成功生成登记一个视频资产(VideoTasks.result_asset_id)。
  { id: "r_11_1", type: "video", name: "段 1-1 · 结果 1", tone: "dusk",  source: "生成 · Seedance 2.5", spec: "720×1280 · 15s" },
  { id: "r_21_1", type: "video", name: "段 2-1 · 结果 1", tone: "lamp",  source: "生成 · Seedance 2.5", spec: "720×1280 · 12s" },
  { id: "r_21_2", type: "video", name: "段 2-1 · 结果 2", tone: "lamp2", source: "生成 · Seedance 2.5", spec: "720×1280 · 12s" },
  { id: "r_22_1", type: "video", name: "段 2-2 · 结果 1", tone: "lamp",  source: "生成 · Seedance 2.5", spec: "720×1280 · 11s" },
  { id: "r_22_2", type: "video", name: "段 2-2 · 结果 2", tone: "lamp2", source: "生成 · Seedance 2.5", spec: "720×1280 · 11s" },
  { id: "r_22_s", type: "video", name: "段 2-2 · 样片 3", tone: "lamp", source: "生成 · Seedance 2.5 样片", spec: "480×854 · 11s", sample: true },
  { id: "r_11_s", type: "video", name: "段 1-1 · 样片 2", tone: "dusk", source: "生成 · Seedance 2.5 样片", spec: "480×854 · 15s", sample: true },
  { id: "r_11_3", type: "video", name: "段 1-1 · 成片 3", tone: "dusk", source: "生成 · Seedance 2.5", spec: "1080×1920 · 15s" },
  { id: "r_21_s", type: "video", name: "段 2-1 · 样片 1", tone: "umber", source: "生成 · Seedance 2.5 样片", spec: "480×854 · 10s", sample: true },
  { id: "r_try_1", type: "video", name: "对坐 · 过肩重拍 · 结果 1", tone: "umber", source: "生成 · Seedance 2.5", spec: "720×1280 · 12s" },
  { id: "r_fog_1", type: "video", name: "空镜 · 江面夜雾 · 结果 1", tone: "teal", source: "生成 · Wan 3.0", spec: "720×1280 · 5s" },
];

// 视频模型只来自用户自配渠道(方案 2026-10-07 范围调整)。能力按具体模型表达。
const SP_VIDEO_MODELS = [
  { id: "seedance25", name: "Seedance 2.5", channel: "我的火山方舟", adapter: "ark_video",
    modes: ["ref", "frames", "text"], secs: [4, 15], ratios: ["9:16", "16:9", "1:1"], res: ["480P", "720P", "1080P"],
    maxImages: 4, maxVideos: 1, maxAudios: 1, pricePerSec: 1.0,
    // 样片:480P 低价预览,7 天内可按样片 ID 另付费出 1080P 成片(沿用提示词、输入、时长、画幅)。
    sample: { res: "480P", finalRes: "1080P", days: 7, pricePerSec: 0.3, finalPricePerSec: 1.6 } },
  { id: "h3", name: "MiniMax H3", channel: "MiniMax 账户", adapter: "minimax_video_v2",
    modes: ["frames", "text"], secs: [6, 10], ratios: ["9:16", "16:9"], res: ["768P", "1080P"],
    maxImages: 1, maxVideos: 0, maxAudios: 0, pricePerSec: 0.6 },
  { id: "wan30", name: "Wan 3.0", channel: "阿里云百炼", adapter: "wan_video",
    modes: ["ref", "frames", "text"], secs: [5, 10], ratios: ["9:16", "16:9", "1:1"], res: ["480P", "720P", "1080P"],
    maxImages: 3, maxVideos: 0, maxAudios: 1, pricePerSec: 0.7 },
];
const SP_GEN_MODES = { ref: "参考生成", frames: "首尾帧", text: "纯文本" };
// VideoTasks 的任务状态(制片页 drama/data.jsx 的任务读这一份)。
const SP_TASK_STATE = {
  queued:           { label: "排队中",   tone: "muted" },
  running:          { label: "生成中",   tone: "run" },
  downloading:      { label: "下载中",   tone: "run" },
  download_failed:  { label: "下载失败", tone: "err" },
  register_pending: { label: "待登记",   tone: "warn" },
  succeeded:        { label: "生成成功", tone: "ok" },
  failed:           { label: "失败",     tone: "err" },
};

function spAsset(id) {
  return SP_ASSETS.find((a) => a.id === id);
}
function spVideoModel(id) {
  return SP_VIDEO_MODELS.find((m) => m.id === id);
}
// 把 prompt 拆成「文本 / 引用」交错的片段，保留引用在句子里的位置。
// 不能复用聊天展示的解析器 —— 那个会剥掉标签、把引用提成单独列表。
function spPromptParts(prompt) {
  const re = /<user-remind type='([^']*)' path='([^']*)' label='([^']*)'><\/user-remind>/g;
  const out = [];
  let last = 0;
  let m;
  while ((m = re.exec(prompt || "")) !== null) {
    if (m.index > last) out.push({ text: prompt.slice(last, m.index) });
    out.push({ ref: { type: m[1], path: m[2], label: m[3], assetId: m[2].split("/")[1] } });
    last = m.index + m[0].length;
  }
  if (last < (prompt || "").length) out.push({ text: prompt.slice(last) });
  return out;
}
// 可读纯文本：复制、导出、一行预览用 —— 引用显示成 @名称。
function spPromptPlain(prompt) {
  return spPromptParts(prompt).map((p) => (p.ref ? "@" + p.ref.label : p.text)).join("");
}

/* ===================== 人物 ===================== */

const SP_CHARS = [
  { id: "c1", proj: "sp1", name: "沈砚", role: "主角", scenes: ["s1", "s2", "s4", "s5", "s6", "s7", "s8"],
    lines: 34, note: "失意画师。全剧台词最少，动作最多。" },
  { id: "c2", proj: "sp1", name: "周慎", role: "对手", scenes: ["s2", "s4", "s6", "s7"],
    lines: 41, note: "革职的旧官。念珠是他的节拍器，慌了就停。" },
  { id: "c3", proj: "sp1", name: "柳氏", role: "配角", scenes: ["s3", "s6", "s7"],
    lines: 18, note: "逃婚的小姐。开口即撒谎，越冷静谎越大。" },
  { id: "c4", proj: "sp1", name: "阿茴", role: "配角", scenes: ["s2", "s3", "s8"],
    lines: 22, note: "丫鬟。全船唯一不怕黑的人。" },
  { id: "c5", proj: "sp1", name: "船家老崔", role: "功能", scenes: ["s1", "s6"],
    lines: 9, note: "只在开船与封船时出现，两次都在报价。" },

  { id: "fc1", proj: "sp2", name: "柯瓦奇", role: "主角", scenes: ["f1", "f2", "f3"],
    lines: 6, note: "退休制图师。削铅笔的时间比画线长。" },
  { id: "fc2", proj: "sp2", name: "邮差", role: "功能", scenes: ["f1", "f2"],
    lines: 4, note: "两场都在说记不清，第二次是真的记不清。" },

  /* ---- sp3:人物跨季共享,一个作品保存整部剧集 ---- */
  { id: "sc1", proj: "sp3", name: "陈立冬", role: "主角",
    scenes: ["a11", "a12", "a21", "a22", "a31", "a32", "a42", "a52", "b11", "b12", "b13", "b21", "b22", "b31", "b32"],
    lines: 96, note: "水利局的测量员，本地人，二十年没回来。量得越准，越量到自家。" },
  { id: "sc2", proj: "sp3", name: "吴国梁", role: "对手",
    scenes: ["a21", "a32", "a51", "b11", "b12", "b32"],
    lines: 58, note: "当年填河的包工头。他从不否认，只是把话题换成钱。" },
  { id: "sc3", proj: "sp3", name: "周玉兰", role: "配角",
    scenes: ["a12", "a41", "b12", "b22"],
    lines: 37, note: "陈立冬的婶婶。守着老屋不搬，二十年只改过一句话里的一个字。" },
  { id: "sc4", proj: "sp3", name: "吴小满", role: "配角",
    scenes: ["a22", "a41", "a42", "a51", "b13", "b31"],
    lines: 44, note: "吴国梁的女儿，镇上开五金店。递证据的人，也是最不想拿到答案的人。" },
  { id: "sc5", proj: "sp3", name: "老赵", role: "功能",
    scenes: ["a11", "a21", "a31", "b11", "b21", "b31"],
    lines: 21, note: "挖掘机司机。台词最少，两次熄火各推动一季。" },
];

const SP_RELATIONS = [
  { proj: "sp1", a: "c1", b: "c2", type: "试探", note: "周慎认得沈砚的手，沈砚不认" },
  { proj: "sp1", a: "c1", b: "c4", type: "递光", note: "第 2 场一支短烛，第 6 集要回来" },
  { proj: "sp1", a: "c3", b: "c4", type: "主仆", note: "柳氏教阿茴撒谎，阿茴学得很快" },
  { proj: "sp1", a: "c2", b: "c3", type: "收买", note: "第 2 集让粮" },
  { proj: "sp1", a: "c1", b: "c5", type: "交易", note: "只发生过一次，用银子" },
  { proj: "sp2", a: "fc1", b: "fc2", type: "线索", note: "唯一见过寄件人的人，什么都记不清" },

  { proj: "sp3", a: "sc1", b: "sc2", type: "对峙", note: "第一季只交换数字，第二季才交换实话" },
  { proj: "sp3", a: "sc1", b: "sc3", type: "婶侄", note: "二十年没同桌，第一顿饭就问拆不拆房" },
  { proj: "sp3", a: "sc1", b: "sc4", type: "递证据", note: "工资本是她拿出来的，代价是拆自己家" },
  { proj: "sp3", a: "sc2", b: "sc4", type: "父女", note: "回南天那场，女儿第一次直接问" },
  { proj: "sp3", a: "sc2", b: "sc5", type: "旧账", note: "八三年冬月那三趟车，两个人都在场" },
  { proj: "sp3", a: "sc1", b: "sc5", type: "撬开", note: "赵叔第三趟没装土——第二季的不可逆点" },
];

/* ===================== AI 改动待审阅 ===================== */
// 审阅单位是场次，不是元素：AI 改一场里的三处也只出现一条。
// 改动立即生效并保留原值，卡片是「本会话最近改了哪些」+ 回退，
// 不是「接受吗」的决策门 —— 与章节侧 ChatPanel 的最近改动卡同一套约定。
// change 取值与 kit.css 的 CHANGE_TYPE 对齐：create / rewrite / expand / trim。
// create 单独一种：AI 新建的整场，回退掉这一条整场就没了。

const SP_AI_CHANGES = [
  { proj: "sp3", scene: "b31", change: "create", field: "整场",
    hint: "AI 新建的场次。回退这一条会连正文一起撤掉，场次不再保留。" },
  { proj: "sp3", scene: "b21", change: "rewrite", field: "正文" },
  { proj: "sp3", scene: "b22", change: "expand", field: "梗概" },
];

function spAiChangesOf(projId, sceneIds) {
  const list = SP_AI_CHANGES.filter((c) => c.proj === projId);
  if (!sceneIds) return list;
  return list.filter((c) => sceneIds.includes(c.scene));
}
function spAiChangeOf(sceneId) {
  return SP_AI_CHANGES.find((c) => c.scene === sceneId) || null;
}

/* ===================== 当前季(本机工作区状态) ===================== */
// 当前季不是剧本的业务字段，是本机为这个作品记住的编辑器选择 —— 换台机器
// 不同步，也不等于最新季。这里就照这个语义放在项目数据之外。
// 单季作品也有这一条，只是 UI 从不显示它。

const SP_CURRENT_SEASON = {
  sp1: "sn1",
  sp3: "sn3b",   // 停在第二季「开闸」
};

/* ===================== 季 / 集 小工具 ===================== */

function spSeasonsOf(projId) {
  return SP_SEASONS.filter((s) => s.proj === projId);
}
function spSeasonById(seasonId) {
  return SP_SEASONS.find((s) => s.id === seasonId) || null;
}
function spSeasonLabel(season) {
  if (!season) return "";
  return season.title ? `第 ${season.no} 季 · ${season.title}` : `第 ${season.no} 季`;
}
// 集数的三种显示态，规则只写这一份：
//   规划已设定且没超  → "2/8 集"
//   规划已设定且超了  → "5/4 集"，并标「已超出规划」（不阻断）
//   规划未设定        → "3 集"
function spEpisodeCount(seasonId) {
  const actual = SP_EPISODES.filter((e) => e.season === seasonId).length;
  const season = spSeasonById(seasonId);
  const planned = season ? season.planned : null;
  return {
    actual,
    planned,
    over: planned != null && actual > planned,
    text: planned != null ? `${actual}/${planned} 集` : `${actual} 集`,
  };
}

/* ===================== 统计(按项目算,不写死) ===================== */

// 八分之一页:场次的 pages 形如 "2 4/8"。
function spEighths(pages) {
  const m = /(\d+)\s+(\d)\/8/.exec(pages || "");
  return m ? Number(m[1]) * 8 + Number(m[2]) : 0;
}
function spFormatEighths(total) {
  return `${Math.floor(total / 8)} ${total % 8}/8`;
}

// seasonId 为空 = 整部剧集;传了就只算这一季。人物是跨季共享的，
// 按季看时统计的是「本季有出场的人物」，不是作品的人物总数。
function SP_STATS_OF(projId, seasonId) {
  const epIds = seasonId
    ? SP_EPISODES.filter((e) => e.season === seasonId).map((e) => e.id)
    : null;
  const scenes = SP_SCENES.filter(
    (s) => s.proj === projId && (!epIds || epIds.includes(s.ep))
  );
  const sceneIds = scenes.map((s) => s.id);
  const eighths = scenes.reduce((sum, s) => sum + spEighths(s.pages), 0);
  const chars = SP_CHARS.filter(
    (c) => c.proj === projId && (!epIds || c.scenes.some((id) => sceneIds.includes(id)))
  );
  return {
    seasons: spSeasonsOf(projId).length,
    episodes: seasonId
      ? epIds.length
      : SP_EPISODES.filter((e) => e.proj === projId).length,
    scenes: scenes.length,
    pages: spFormatEighths(eighths),
    minutes: Math.round(scenes.reduce((sum, s) => sum + s.minutes, 0)),
    chars: chars.length,
    places: new Set(scenes.map((s) => s.place)).size,
    beats: SP_BEATS.filter(
      (b) => b.proj === projId && (!epIds || epIds.includes(b.ep))
    ).length,
    lines: scenes.reduce((sum, s) => sum + s.lines, 0),
  };
}

/* ===================== 分镜进度 ===================== */
// 场次 → [已采用, 分镜总数]。只有第 1 集开始拆分镜；没有条目的场次就是还没拆。
const SP_CLIP_STATS = {
  s1: [3, 3],
  s2: [2, 4],
  s3: [0, 2],
};

/* ===================== 注入作品库 ===================== */
// 剧本项目以「剧本型 novel」进作品库,点卡片走 EditorView 的 isScreenplay 分支,
// 所以不用改 data.js。

SP_PROJECTS.forEach((p) => {
  const stats = SP_STATS_OF(p.id);
  const seasons = spSeasonsOf(p.id);
  // 集数用实际记录算，不写死 —— 规划集数是季上的可选元数据，不是作品的集数。
  const episodes = p.kind === "series" ? stats.episodes : p.episodes;
  const tags = [
    p.kind === "series" ? `${episodes} 集` : "单本",
    p.genre.split(" / ")[0],
  ];
  if (seasons.length > 1) tags.splice(1, 0, `${seasons.length} 季`);
  if (p.supported === false) tags.push("第一期暂不支持");
  window.REVERIC_DATA.novels.push({
    id: p.id,
    title: p.title,
    subtitle: p.subtitle,
    description: p.logline,
    category: p.kind === "series" ? "剧集 / Series" : "电影 / Feature",
    tags,
    chapters: p.kind === "series" ? episodes : stats.scenes,
    words: p.words,
    updated: p.updated,
    cover: p.cover,
    authorName: "怀素",
    status: p.status,
    screenplay: p,
  });
});

Object.assign(window, {
  SP_PROJECTS, SP_SEASONS, SP_EPISODES, SP_SCENES, SP_SCRIPT, SP_BEATS,
  SP_ASSETS, SP_VIDEO_MODELS, SP_GEN_MODES, SP_TASK_STATE,
  spAsset, spVideoModel, spRef, spPromptParts, spPromptPlain,
  SP_CHARS, SP_RELATIONS, SP_AI_CHANGES, SP_CURRENT_SEASON,
  SP_STATS_OF, SP_CLIP_STATS, spEighths, spFormatEighths,
  spSeasonsOf, spSeasonById, spSeasonLabel, spEpisodeCount,
  spAiChangesOf, spAiChangeOf,
});
