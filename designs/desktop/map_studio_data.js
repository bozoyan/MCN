// 地图工作台的演示数据。字段照抄 Flutter 侧的表结构，改名只为在原型里读着方便：
//   Locations(id/name/type/parentId/description/tags/meta/photos) → MS_LOCATIONS
//     photos 是 {path, name}，原型里 path 换成 tint 色块；name 可空，界面显示「未命名」
//   MapLocations(mapId/locationId/x/y)                      → location.pin（归一化 0~1）
//   LocationConnections(source/target/type/travelTimeDays)  → MS_CONNECTIONS
//   NovelMaps(id/name/type/width/height/settings)           → MS_MAPS
//
// assets/images/world_map.webp 取自精细版设计稿的地图画面。
// 它代表「AI 生成的整图」：地貌、纹理、中文地名都已经画进像素里，程序不再重绘。

const MS_MAP_IMAGE = "assets/images/world_map.webp";
// 地图原始像素。归一化坐标乘它得到像素位置，与 MapDocument 的 canvas.width/height 同义。
const MS_CANVAS = { width: 992, height: 604 };

const MS_MAPS = [
  {
    id: "map_world",
    name: "世界地图",
    type: "world",
    width: 3072,
    height: 1728,
    locationId: "loc_world",
    settings: {
      image: "images/maps/map_world/map-v3.webp",
      version: 3,
      style: "手绘羊皮纸",
      model: "gpt-image-2",
      generatedAt: "今天 10:24",
    },
    stats: { regions: 4, places: 11, routes: 7, unplaced: 3 },
  },
  {
    id: "map_north",
    name: "北境王国 · 区域图",
    type: "region",
    width: 2752,
    height: 1536,
    locationId: "loc_north",
    settings: { image: null, version: 0 },
    stats: { regions: 0, places: 0, routes: 0, unplaced: 6 },
  },
  {
    id: "map_hancheng",
    name: "寒城 · 城池图",
    type: "city",
    width: 2048,
    height: 2048,
    locationId: "loc_hancheng",
    settings: { image: null, version: 0 },
    stats: { regions: 0, places: 0, routes: 0, unplaced: 4 },
  },
];

// 这些地点在生成 prompt 中作为势力疆域描述，同时也和普通地点一样按 x/y 命中。
const MS_REGIONS = [
  { locationId: "loc_north" },
  { locationId: "loc_west" },
  { locationId: "loc_oasis" },
  { locationId: "loc_dawn" },
];

// 地点树。pin 为 null = 还没落到地图上：它在世界观里存在，但这张地图上没有它的
// MapLocation 行，得从地点树拖到画布上才有坐标。
const MS_LOCATIONS = [
  { id: "loc_world", name: "泰拉大陆", type: "world", parentId: null, tags: ["主世界"], pin: null,
    description: "四大势力共处的大陆，南北海路把它们连在一起。" },

  { id: "loc_north", name: "北境王国", type: "country", parentId: "loc_world", tags: ["势力", "北方"], pin: null,
    description: "严寒的北方王国，以骑士团和要塞闻名。", area: "186,400 km²", childMapId: "map_north" },
  { id: "loc_hancheng", name: "寒城", type: "city", parentId: "loc_north", tags: ["首都"], pin: [0.48, 0.384],
    description: "北境政治中心，人口 82 万。", childMapId: "map_hancheng",
    photos: [
      { tint: "#6F7F8E", name: "城门雪夜" },
      { tint: "#8A7A63", name: "王庭正殿" },
      { tint: "#4F5D52", name: "" },
    ] },
  { id: "loc_tielu", name: "铁炉要塞", type: "landmark", parentId: "loc_north", tags: ["军事"], pin: [0.85, 0.265],
    description: "守卫黑石峡谷的军事要塞。" },
  { id: "loc_beijing_fort", name: "北境要塞", type: "landmark", parentId: "loc_north", tags: ["军事", "关隘"], pin: [0.504, 0.616],
    description: "南下必经的关隘，三条主道在此汇合。" },
  { id: "loc_fengxi", name: "风息森林", type: "forest", parentId: "loc_north", tags: ["地貌"], pin: [0.403, 0.538],
    description: "常年无风的针叶林，猎人称它为哑林。" },
  { id: "loc_yongdong", name: "永冻荒原", type: "plain", parentId: "loc_north", tags: ["地貌"], pin: [0.407, 0.05],
    description: "北境以北的冻土，夏季只化开半尺。" },
  { id: "loc_heishi", name: "黑石峡谷", type: "landmark", parentId: "loc_north", tags: ["地貌", "要冲"], pin: [0.796, 0.434],
    description: "东境唯一的陆路缺口。" },

  { id: "loc_west", name: "西境联盟", type: "country", parentId: "loc_world", tags: ["势力", "商业"], pin: null,
    description: "由多个自由城邦组成的商业联盟。", area: "132,800 km²" },
  { id: "loc_qishi", name: "骑士港", type: "city", parentId: "loc_west", tags: ["港口"], pin: [0.19, 0.672],
    description: "连接西境与外海的重要港口。" },
  { id: "loc_fengyu", name: "风语群岛", type: "island", parentId: "loc_west", tags: ["地貌"], pin: [0.076, 0.434],
    description: "十九座礁岛，只在退潮时相连。" },

  { id: "loc_oasis", name: "绿洲帝国", type: "country", parentId: "loc_world", tags: ["势力", "商路"], pin: null,
    description: "南方富饶的大帝国，控制着重要商路。", area: "158,300 km²" },
  { id: "loc_feicui", name: "翡翠城", type: "city", parentId: "loc_oasis", tags: ["首都"], pin: [0.49, 0.858],
    description: "沙漠绿洲中的贸易枢纽。" },
  { id: "loc_leiming", name: "雷鸣平原", type: "plain", parentId: "loc_oasis", tags: ["地貌", "战场"], pin: [0.694, 0.659],
    description: "两次会战都发生在这片开阔地。" },

  { id: "loc_dawn", name: "黎明公国", type: "country", parentId: "loc_world", tags: ["势力", "东方"], pin: null,
    description: "东方的古老公国，魔法传统深厚。", area: "96,700 km²" },
  { id: "loc_limingcheng", name: "黎明城", type: "city", parentId: "loc_dawn", tags: ["首都"], pin: [0.879, 0.771],
    description: "公国王座与观星塔所在地。" },
  { id: "loc_guanxing", name: "观星台", type: "landmark", parentId: "loc_dawn", tags: ["秘境"], pin: null,
    description: "第 31 章出现的高塔，位置作者尚未定。" },
  { id: "loc_shengquan", name: "圣泉祠", type: "landmark", parentId: "loc_dawn", tags: ["秘境"], pin: null,
    description: "只在冬至开启的祠堂。" },

  { id: "loc_shenyuan", name: "深渊群岛", type: "island", parentId: "loc_world", tags: ["地貌", "未定"], pin: null,
    description: "航海图上标着但没人回来过的群岛。" },
];

// 路线画在地图像素里，第一版不参与命中；这里只作为地点之间的语义关系存在。
const MS_CONNECTIONS = [
  { id: "cx1", source: "loc_hancheng", target: "loc_beijing_fort", type: "path_to", label: "北境主道", days: 6, difficulty: "常规" },
  { id: "cx2", source: "loc_beijing_fort", target: "loc_feicui", type: "path_to", label: "南下商路", days: 14, difficulty: "常规" },
  { id: "cx3", source: "loc_qishi", target: "loc_beijing_fort", type: "path_to", label: "西境次道", days: 9, difficulty: "雨季断路" },
  { id: "cx4", source: "loc_tielu", target: "loc_heishi", type: "adjacent", label: "峡谷守备线", days: 1, difficulty: "常规" },
  { id: "cx5", source: "loc_limingcheng", target: "loc_leiming", type: "path_to", label: "东境驿路", days: 8, difficulty: "常规" },
];

const MS_LOCATION_TYPES = [
  { id: "world", label: "世界", icon: "globe" },
  { id: "continent", label: "大陆", icon: "globe" },
  { id: "country", label: "国家 / 势力", icon: "shield" },
  { id: "region", label: "区域", icon: "mountains" },
  { id: "mountain", label: "山脉", icon: "mountains" },
  { id: "plain", label: "平原", icon: "mountains" },
  { id: "forest", label: "森林", icon: "tree-evergreen" },
  { id: "river", label: "河流", icon: "waves" },
  { id: "lake", label: "湖泊", icon: "waves" },
  { id: "sea", label: "海域", icon: "waves" },
  { id: "island", label: "岛屿", icon: "waves" },
  { id: "city", label: "城市", icon: "city" },
  { id: "village", label: "村镇", icon: "house" },
  { id: "building", label: "建筑", icon: "buildings" },
  { id: "landmark", label: "地标", icon: "map-pin" },
  { id: "generic", label: "未分类", icon: "circle" },
];

// 整条链路一次只出一张地图。图片贵，候选图挑选换成
// 「看一张，不满意再重来」。cost 为该步实际发出的图像请求数。
//
// 出图之后以成图为准，从画面里把全部地名（包括国家/区域）的文字中心读出来，
// 作为透明点击区的位置。
const MS_STAGES = [
  { id: "read", label: "读设定与地点", note: "收集这张图需要出现的地点", cost: 0 },
  { id: "image", label: "画地图", note: "3072 × 1728 · 地名直接写进画面", cost: 1 },
  { id: "locate", label: "认出画面上的地名", note: "按文字中心回写全部地点的位置", cost: 0 },
  { id: "verify", label: "核对地点坐标", note: "列出没有认出的地点", cost: 0 },
];

const MS_STYLES = ["手绘羊皮纸", "水墨舆图", "版画线描", "写实地形", "古籍插图"];
const MS_SIZES = [
  { id: "2k", label: "2K", px: "2752 × 1536", note: "画布浏览够用，出图最快" },
  { id: "3k", label: "3K", px: "3072 × 1728", note: "放大看地名仍清晰" },
];

// 单张地图的示意价格。

const MS_LEGEND = [
  { kind: "line", color: "#5B7FA6", label: "王国边界" },
  { kind: "line", color: "#8A6BA8", label: "势力边界" },
  { kind: "dash", color: "#3B5182", label: "主道路" },
  { kind: "dash", color: "#9B8877", label: "次要道路" },
  { kind: "line", color: "#6FA0C4", label: "河流" },
  { kind: "pin", color: "#3B5182", label: "主城 / 要塞" },
  { kind: "pin", color: "#7E8698", label: "地标 / 港口" },
];

Object.assign(window, {
  MS_MAP_IMAGE, MS_CANVAS, MS_MAPS, MS_REGIONS, MS_LOCATIONS,
  MS_CONNECTIONS, MS_LOCATION_TYPES, MS_STAGES, MS_STYLES, MS_SIZES,
  MS_LEGEND,
});
