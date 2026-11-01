// data.jsx — 无限画布(Canvas) mock data + shared atoms.
// 对应方案 docs/solutions/infinite-canvas.md 的模型:
//   canvases / canvas_nodes(reference|sticky) / canvas_edges(5 种类型化边)
// 节点位置 x/y/w/h 是「数据」不是样式;style(颜色)才是纯视觉。
//
// 命名全部带 Cv/CV_ 前缀 —— 原型脚本共享全局作用域(entity_graph 已占用 NODES 等),
// 顶层标识符不能撞名。

// 图标基路径:standalone 的 canvas/Canvas.html 设为 "../",嵌入 index.html 时为 ""。
window.CV_BASE = window.CV_BASE || "";

/* ---------------- CvIcon — phosphor SVG via CSS mask(可 currentColor 重着色) ---------------- */
function CvIcon({ name, size = 16, color = "currentColor", style }) {
  const url = `url(${window.CV_BASE}assets/icons/phosphor/${name}.svg)`;
  return (
    <span
      className="cv-icon"
      aria-hidden="true"
      style={{
        width: size, height: size, backgroundColor: color,
        WebkitMaskImage: url, maskImage: url,
        WebkitMaskRepeat: "no-repeat", maskRepeat: "no-repeat",
        WebkitMaskPosition: "center", maskPosition: "center",
        WebkitMaskSize: "contain", maskSize: "contain",
        ...style,
      }}
    />
  );
}

const cvTint = (c, pct) => `color-mix(in srgb, ${c} ${pct}%, transparent)`;

/* ---------------- 引用型节点:refType 元数据 ----------------
   refType 复用 aiResourceType 字符串,新增 workspace section 时自动可用。 */
const CV_REF_TYPES = {
  character:     { label: "人物",  icon: "user",           color: "var(--accent-warm)" },
  chapter:       { label: "章节",  icon: "book-open",      color: "var(--cv-edge-causal)" },
  foreshadowing: { label: "伏笔",  icon: "flag",           color: "var(--warning-text)" },
  outline:       { label: "大纲",  icon: "list-bullets",   color: "var(--text-muted)" },
  location:      { label: "地点",  icon: "map-pin",        color: "var(--cv-edge-timeline)" },
  item:          { label: "物品",  icon: "diamond",        color: "var(--accent)" },
  faction:       { label: "势力",  icon: "shield",         color: "var(--text-secondary)" },
  skill:         { label: "技能",  icon: "sparkle",        color: "var(--accent-amber)" },
  creature:      { label: "生物",  icon: "tree-evergreen", color: "var(--cv-edge-timeline)" },
  document:      { label: "文档",  icon: "file-text",      color: "var(--text-muted)" },
};

/* ---------------- 类型化边:5 种语义 ----------------
   directed=false 的类型不画箭头(视觉上无向),但底层仍是有向存储。 */
const CV_EDGE_TYPES = {
  relationship: {
    label: "人物关系", icon: "users", color: "var(--cv-edge-relationship)",
    dash: null, directed: false, desc: "谁和谁有关系,构思阶段无需证据",
  },
  causal: {
    label: "因果", icon: "lightning", color: "var(--cv-edge-causal)",
    dash: null, directed: true, desc: "前者导致后者发生",
  },
  timeline: {
    label: "时间线", icon: "clock", color: "var(--cv-edge-timeline)",
    dash: null, directed: true, desc: "先后次序,用于铺排节奏",
  },
  foreshadow_payoff: {
    label: "伏笔兑现", icon: "flag", color: "var(--cv-edge-foreshadow)",
    dash: "7 6", directed: true, desc: "起点为伏笔,终点为兑现章节",
  },
  association: {
    label: "通用关联", icon: "link", color: "var(--cv-edge-association)",
    dash: "2 6", directed: false, desc: "说不清但想放在一起的两样东西",
  },
};
const CV_EDGE_ORDER = ["relationship", "causal", "timeline", "foreshadow_payoff", "association"];

/* ---------------- 便签纸色 ---------------- */
const CV_STICKY_COLORS = [
  { key: "sand",  label: "米黄", value: "var(--cv-sticky-sand)" },
  { key: "sage",  label: "淡青", value: "var(--cv-sticky-sage)" },
  { key: "rose",  label: "淡绯", value: "var(--cv-sticky-rose)" },
  { key: "stone", label: "素灰", value: "var(--cv-sticky-stone)" },
];

/* ---------------- 画布本体 ---------------- */
const CV_CANVAS = {
  id: "cv_1",
  novelId: "n1",
  novel: "夜航船",
  name: "第一卷 · 人物与伏笔",
  desc: "重逢线与青铜钥匙这条伏笔的脉络，先铺开看结构。",
};

/* ---------------- 本小说的可引用资源(引用节点选择器数据源) ----------------
   deleted:true 的资源用于演示「引用失效」:画布节点保留,渲染为失效态。 */
const CV_RESOURCES = [
  { id: "ch_linye",   type: "character", title: "林夜",  sub: "主角 · 更夫" },
  { id: "ch_shenzy",  type: "character", title: "沈知意", sub: "旧友 · 药师" },
  { id: "ch_chumh",   type: "character", title: "楚明河", sub: "同门 · 河监" },
  { id: "ch_guhan",   type: "character", title: "顾寒",  sub: "旧识 · 押船人" },
  { id: "ch_luting",  type: "character", title: "陆听澜", sub: "已删除", deleted: true },
  { id: "cp_12", type: "chapter", title: "第 12 章 · 雨夜重逢", sub: "1,318 字" },
  { id: "cp_15", type: "chapter", title: "第 15 章 · 河监",     sub: "1,042 字" },
  { id: "cp_19", type: "chapter", title: "第 19 章 · 钥匙的用途", sub: "草稿" },
  { id: "fs_key",  type: "foreshadowing", title: "青铜钥匙", sub: "已埋设 · 待兑现" },
  { id: "fs_scar", type: "foreshadowing", title: "左腕的旧疤", sub: "已埋设" },
  { id: "lo_bar",  type: "location", title: "渡口酒馆", sub: "夜航船 · 起点" },
  { id: "lo_riv",  type: "location", title: "青河渡",   sub: "" },
  { id: "ol_v1",   type: "outline",  title: "第一卷大纲", sub: "24 节" },
  { id: "it_key",  type: "item",     title: "青铜钥匙（实物）", sub: "" },
  { id: "fa_hejian", type: "faction", title: "河监司", sub: "" },
];
const cvResource = (id) => CV_RESOURCES.find((r) => r.id === id);

/* ---------------- 节点(初始状态,agent 运行前) ----------------
   ref 节点固定 196×62;sticky 自带尺寸。title 是引用资源标题的缓存副本
   （打开画布时由 refreshReferenceTitlesForCanvas 校准）。 */
const CV_NODE_W = 196;
const CV_NODE_H = 62;

const CV_INITIAL_NODES = [
  { id: "n_linye",  kind: "reference", refType: "character",     refId: "ch_linye",  title: "林夜",  x: 40,  y: 150, w: CV_NODE_W, h: CV_NODE_H },
  { id: "n_shenzy", kind: "reference", refType: "character",     refId: "ch_shenzy", title: "沈知意", x: 40,  y: 280, w: CV_NODE_W, h: CV_NODE_H },
  { id: "n_c12",    kind: "reference", refType: "chapter",       refId: "cp_12",     title: "第 12 章 · 雨夜重逢", x: 350, y: 120, w: CV_NODE_W, h: CV_NODE_H },
  { id: "n_c19",    kind: "reference", refType: "chapter",       refId: "cp_19",     title: "第 19 章 · 钥匙的用途", x: 350, y: 330, w: CV_NODE_W, h: CV_NODE_H },
  { id: "n_bar",    kind: "reference", refType: "location",      refId: "lo_bar",    title: "渡口酒馆", x: 660, y: 40,  w: CV_NODE_W, h: CV_NODE_H },
  { id: "n_key",    kind: "reference", refType: "foreshadowing", refId: "fs_key",    title: "青铜钥匙", x: 660, y: 300, w: CV_NODE_W, h: CV_NODE_H },
  { id: "n_luting", kind: "reference", refType: "character",     refId: "ch_luting", title: "陆听澜", x: 980, y: 300, w: CV_NODE_W, h: CV_NODE_H },
  {
    id: "n_note1", kind: "sticky", color: "sand", author: "作者",
    title: "留白提醒",
    text: "重逢这场戏要压住。别让读者在第 12 章就猜到背叛——钥匙只给一个侧写，不解释。",
    x: 660, y: 430, w: 240, h: 152,
  },
];

const CV_INITIAL_EDGES = [
  { id: "e1", from: "n_linye",  to: "n_shenzy", type: "relationship",      label: "旧友 · 互相隐瞒" },
  { id: "e2", from: "n_shenzy", to: "n_c12",    type: "causal",            label: "促成重逢" },
  { id: "e3", from: "n_c12",    to: "n_c19",    type: "timeline",          label: "七日后" },
  { id: "e4", from: "n_key",    to: "n_c19",    type: "foreshadow_payoff", label: "埋设 → 兑现" },
  { id: "e5", from: "n_bar",    to: "n_c12",    type: "association",       label: "" },
  { id: "e6", from: "n_luting", to: "n_key",    type: "association",       label: "曾持有" },
];

/* ---------------- Agent 共创剧本 ----------------
   每一步 = 一条聊天消息或一次工具调用;工具调用同时改画布 state,
   演示「agent 写入 → DB → stream → 画布实时出现」这条链路。 */
const CV_AGENT_SCRIPT = [
  { at: 0, kind: "user", text: "把主角团的关系画到画布上，顺便标一下谁和谁互相猜忌。" },
  { at: 500, kind: "tool", name: "CanvasGetContent", detail: "7 个节点 · 6 条边", ok: true },
  {
    at: 1200, kind: "ai",
    text: "画布上已经有林夜和沈知意。我把楚明河、顾寒补上，再把三条人物关系连起来。",
  },
  {
    at: 2200, kind: "tool", name: "CanvasAddNode", detail: "character · 楚明河",
    addNode: {
      id: "n_chumh", kind: "reference", refType: "character", refId: "ch_chumh",
      title: "楚明河", x: 40, y: 410, w: CV_NODE_W, h: CV_NODE_H, byAgent: true,
    },
  },
  {
    at: 3000, kind: "tool", name: "CanvasAddNode", detail: "character · 顾寒",
    addNode: {
      id: "n_guhan", kind: "reference", refType: "character", refId: "ch_guhan",
      title: "顾寒", x: 40, y: 540, w: CV_NODE_W, h: CV_NODE_H, byAgent: true,
    },
  },
  {
    at: 3800, kind: "tool", name: "CanvasAddEdge", detail: "relationship · 沈知意 → 楚明河",
    addEdge: { id: "ea1", from: "n_shenzy", to: "n_chumh", type: "relationship", label: "同门", byAgent: true },
  },
  {
    at: 4500, kind: "tool", name: "CanvasAddEdge", detail: "relationship · 楚明河 → 顾寒",
    addEdge: { id: "ea2", from: "n_chumh", to: "n_guhan", type: "relationship", label: "上下级", byAgent: true },
  },
  {
    at: 5200, kind: "tool", name: "CanvasAddEdge", detail: "relationship · 林夜 → 顾寒",
    addEdge: { id: "ea3", from: "n_linye", to: "n_guhan", type: "relationship", label: "互相猜忌", bow: 150, byAgent: true },
  },
  {
    at: 6000, kind: "tool", name: "CanvasAddNode", detail: "sticky · 猜忌的落点",
    addNode: {
      id: "n_note2", kind: "sticky", color: "sage", author: "编年史官",
      title: "猜忌的落点",
      text: "三个人的猜忌都绕着青铜钥匙。建议在第 15 章前后各给一次暗示，别把话说破。",
      x: 350, y: 560, w: 240, h: 136, byAgent: true,
    },
  },
  {
    at: 6900, kind: "ai",
    text: "已放上 3 个节点、3 条人物关系边。「互相猜忌」标在林夜 ↔ 顾寒这条上。\n\n画布上的连线只是构思用的视觉组织，不会进入实体关系图；想把某条关系正典化，用 CreateRelation 单独写入。",
  },
];

Object.assign(window, {
  CvIcon, cvTint,
  CV_REF_TYPES, CV_EDGE_TYPES, CV_EDGE_ORDER, CV_STICKY_COLORS,
  CV_CANVAS, CV_RESOURCES, cvResource,
  CV_NODE_W, CV_NODE_H, CV_INITIAL_NODES, CV_INITIAL_EDGES, CV_AGENT_SCRIPT,
});
