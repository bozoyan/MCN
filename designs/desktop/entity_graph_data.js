// Mock entity-graph world for the Relations view.
// Modeled on lib/shared/entity_graph (EntityNodeData / EntityEdgeData) and the
// entity/relation type constants in novel_content_database.dart — NOT the Flutter
// UI. Seven entity types, character roles, and the full relation-category set are
// all represented so the graph reads like a real, dense story bible.
//
// node.key === `${type}_${id}` (entityGraphEntityKey). Edges reference keys.

(function () {
  // ---- Entity type → ring color (entity_graph/colors.dart) -------------
  const ENTITY_TYPES = {
    character: { zh: "人物", icon: "user", color: "#283C5F" },
    faction: { zh: "势力", icon: "shield", color: "#5B8DB8" },
    skill: { zh: "技能", icon: "sparkle", color: "#9B6FB0" },
    item: { zh: "物品", icon: "diamond", color: "#8897D1" },
    location: { zh: "地点", icon: "map-pin", color: "#6BA07A" },
    creature: { zh: "生物", icon: "tree-evergreen", color: "#B07A5B" },
  };

  const CHARACTER_ROLES = {
    protagonist: "主角",
    antagonist: "反派",
    supporting: "配角",
    minor: "次要",
  };

  // ---- Relation type → { zh label, category } --------------------------
  // category drives edge color; mirrors the semantic grouping in
  // entity_graph/colors.dart getRelationColor().
  const RELATIONS = {
    // character ↔ character
    family: { zh: "亲族", cat: "kin" },
    parent: { zh: "父 / 子", cat: "kin", directed: true },
    sibling: { zh: "手足", cat: "kin" },
    grandparent: { zh: "祖辈", cat: "kin", directed: true },
    friend: { zh: "挚友", cat: "bond" },
    colleague: { zh: "同门", cat: "bond" },
    lover: { zh: "情缘", cat: "lover" },
    enemy: { zh: "仇敌", cat: "enemy" },
    master_disciple: { zh: "师徒", cat: "master", directed: true },
    subordinate: { zh: "属下", cat: "faction", directed: true },
    alter_ego: { zh: "化身", cat: "alter" },
    // character ↔ faction
    member: { zh: "门人", cat: "faction" },
    leader: { zh: "掌门", cat: "faction" },
    founder: { zh: "开派祖师", cat: "faction" },
    ally: { zh: "盟友", cat: "bond" },
    // character ↔ skill
    learned: { zh: "已习", cat: "skill" },
    mastering: { zh: "修习中", cat: "skill" },
    mastered: { zh: "已大成", cat: "skill" },
    creator: { zh: "创功者", cat: "skill", directed: true },
    // character ↔ item
    owner: { zh: "持有", cat: "item" },
    user: { zh: "使用", cat: "item" },
    former_owner: { zh: "旧主", cat: "item" },
    // faction ↔ faction
    f_ally: { zh: "结盟", cat: "bond" },
    f_enemy: { zh: "敌对", cat: "enemy" },
    f_subordinate: { zh: "下属", cat: "faction", directed: true },
    // skill ↔ skill / item ↔ item
    prerequisite: { zh: "前置", cat: "evolve", directed: true },
    evolves_to: { zh: "进化为", cat: "evolve", directed: true },
    branch: { zh: "分支", cat: "evolve" },
    // creature ↔ creature
    prey: { zh: "猎物", cat: "enemy", directed: true },
    predator: { zh: "天敌", cat: "enemy", directed: true },
  };

  // category → edge color, within the brand palette.
  const REL_CAT_COLOR = {
    kin: "#D4845A",
    bond: "#6BA07A",
    lover: "#D48BA0",
    enemy: "#C25B5B",
    master: "#9B6FB0",
    faction: "#5B8DB8",
    item: "#D4A45A",
    skill: "#9B6FB0",
    alter: "#5A9E9E",
    evolve: "#5A9E9E",
    other: "#9E9484",
  };

  // ---- Nodes -----------------------------------------------------------
  // characters carry role + initials; non-characters render a type glyph.
  const C = (id, name, en, role, desc) => ({
    type: "character", id, name, en, role, desc,
  });
  const E = (type, id, name, en, desc) => ({ type, id, name, en, desc });

  const NODES = [
    // —— 人物 ——
    C("shen", "沈砚之", "Shen Yanzhi", "protagonist",
      "沧澜剑派内门弟子。背负灭门旧案，自青冥峰下山，剑心未成而执念已深。"),
    C("suling", "苏苓", "Su Ling", "supporting",
      "天枢阁少阁主，亦医亦商。与沈砚之自临安一别，再见已隔生死局。"),
    C("xuanshuang", "玄霜真人", "Master Xuanshuang", "supporting",
      "沧澜剑派现任掌门，沈砚之之师。三十年前曾入幽冥渊，归来后封剑不出。"),
    C("lingxiao", "凌霄", "Lingxiao", "supporting",
      "玄霜真人首徒，沈砚之师兄。心高气傲，剑快而意躁。"),
    C("peizhao", "裴照", "Pei Zhao", "supporting",
      "游方刀客，与沈砚之结为生死之交。一身横练，专破剑招。"),
    C("shenhe", "沈鹤年", "Shen Henian", "minor",
      "沈砚之之父，沈氏旧主。十六年前死于幽冥教夜袭，尸骨无存。"),
    C("qingyuan", "沈青鸢", "Shen Qingyuan", "supporting",
      "沈砚之之妹，灭门时失踪。生死成谜，是全书最大的线头。"),
    C("baitan", "白檀", "Bai Tan", "minor",
      "天枢阁药师，苏苓副手。一手青囊回春,救人无数,从不问因果。"),
    C("yanwujiu", "燕无咎", "Yan Wujiu", "antagonist",
      "幽冥教教主，沧澜灭门案的主谋。修噬魂大法，以剑入魔。"),
    C("guimian", "鬼面", "The Masked One", "antagonist",
      "江湖传言的无面杀手。无人见其真容,实为燕无咎的另一重身份。"),
    C("murongxue", "慕容雪", "Murong Xue", "antagonist",
      "幽冥教左护法，燕无咎门下。心狠手辣,却对师门忠诚至死。"),
    C("xiaoyi", "萧逸", "Xiao Yi", "minor",
      "三百年前的剑道宗师,沧澜剑派开派祖师。青冥剑诀的创立者。"),
    C("gulang", "顾长卿", "Gu Changqing", "supporting",
      "临安城知府,亦是天枢阁暗桩。庙堂与江湖之间的摆渡人。"),

    // —— 势力 ——
    E("faction", "canglan", "沧澜剑派", "Canglan Sword Sect",
      "青冥峰上的正道剑宗,以青冥剑诀立派三百年。如今只剩老弱十余人。"),
    E("faction", "youming", "幽冥教", "Youming Cult",
      "盘踞幽冥渊的魔道势力。以噬魂之术控人,近年大举北上。"),
    E("faction", "tianshu", "天枢阁", "Tianshu Pavilion",
      "江湖第一情报与货殖商号,中立不偏。买卖消息,也买卖人心。"),
    E("faction", "shenshi", "沈氏", "House of Shen",
      "临安书香门第,沈砚之的本家。灭门后仅余兄妹二人流落在外。"),

    // —— 技能 ——
    E("skill", "qingmingjue", "青冥剑诀", "Qingming Sword Art",
      "沧澜剑派镇派剑法,讲究以静制动、剑心通明。入门易,大成难。"),
    E("skill", "liuguang", "流光剑意", "Liuguang Sword Intent",
      "青冥剑诀的至高一重,剑随心动、光过无痕。三百年间无人练成。"),
    E("skill", "yufengbu", "御风步", "Wind-Riding Step",
      "沧澜轻身法,踏风而行。习青冥剑诀前的必修根基。"),
    E("skill", "xuanshuangjue", "玄霜诀", "Xuanshuang Frost Art",
      "玄霜真人自创的护体心法,以霜寒锁魂,正是噬魂大法的一物降一物。"),
    E("skill", "shihun", "噬魂大法", "Soul-Devouring Art",
      "幽冥教不传之秘,夺人神魂以壮己身。修者得寸进尺,终为魔噬。"),

    // —— 物品 ——
    E("item", "canglanjian", "沧澜剑", "Canglan Sword",
      "沧澜剑派历代掌门信物,通体如水。认主而鸣,非剑心通明者不能驭。"),
    E("item", "xuanshuangpei", "玄霜佩", "Frost Pendant",
      "玄霜真人贴身玉佩,内封一缕霜诀真意。后赠予沈砚之傍身。"),
    E("item", "shihunfan", "噬魂幡", "Soul Banner",
      "幽冥教法器,可收摄亡魂炼为傀儡。燕无咎成名之物。"),
    E("item", "qingnang", "青囊", "Green Satchel",
      "天枢阁秘传药囊,百毒可解、九死能回。白檀随身不离。"),

    // —— 地点 ——
    E("location", "qingmingfeng", "青冥峰", "Qingming Peak",
      "沧澜剑派所在,云海之上的孤峰。剑冢与藏经阁皆在峰顶。"),
    E("location", "youmingyuan", "幽冥渊", "Youming Abyss",
      "西陲万丈深渊,终年不见天日。幽冥教总坛,亦是噬魂之术的源头。"),
    E("location", "linan", "临安城", "Lin'an City",
      "江南繁华之地,沈氏故宅与天枢阁分号皆在此。全书的人间锚点。"),

    // —— 生物 ——
    E("creature", "xuanbingjiao", "玄冰蛟", "Black-Ice Jiao",
      "幽冥渊寒潭中的上古蛟属,吐息成霜。玄霜诀的灵感所自。"),
    E("creature", "shihungu", "噬魂蛊", "Soul Gu",
      "幽冥教豢养的食魂之蛊,需以活人神魂饲之。蛊成则术成。"),
    E("creature", "baize", "白泽", "Baize",
      "传说中的祥瑞灵兽,通晓万物因果。青鸢失踪前最后所见之物。"),
  ];

  // ---- Edges -----------------------------------------------------------
  // r(source, target, relationType)
  const R = (s, t, type) => ({ s, t, type });
  const REL = [
    // 沈砚之 的关系网（主角中心）
    R("shen", "shenhe", "parent"),         // 父子（source 为父）→ reversed below
    R("qingyuan", "shen", "sibling"),
    R("shen", "suling", "lover"),
    R("shen", "peizhao", "friend"),
    R("shen", "lingxiao", "colleague"),
    R("xuanshuang", "shen", "master_disciple"),
    R("shen", "yanwujiu", "enemy"),
    R("shen", "canglan", "member"),
    R("shen", "shenshi", "member"),
    R("shen", "qingmingjue", "mastering"),
    R("shen", "yufengbu", "learned"),
    R("shen", "canglanjian", "owner"),
    R("shen", "xuanshuangpei", "user"),

    // 沈鹤年 / 沈青鸢 / 沈氏
    R("shenhe", "shenshi", "leader"),
    R("qingyuan", "shenshi", "member"),
    R("qingyuan", "baize", "owner"),       // 青鸢与白泽（线索）
    R("shenhe", "yanwujiu", "enemy"),

    // 师门
    R("xuanshuang", "canglan", "leader"),
    R("lingxiao", "canglan", "member"),
    R("xuanshuang", "lingxiao", "master_disciple"),
    R("xiaoyi", "canglan", "founder"),
    R("xiaoyi", "qingmingjue", "creator"),
    R("xuanshuang", "xuanshuangjue", "creator"),
    R("xuanshuang", "xuanshuangpei", "former_owner"),
    R("xuanshuang", "canglanjian", "former_owner"),
    R("lingxiao", "qingmingjue", "mastered"),

    // 技能演化树
    R("qingmingjue", "liuguang", "evolves_to"),
    R("yufengbu", "qingmingjue", "prerequisite"),
    R("xuanshuangjue", "shihun", "branch"),   // 一物降一物的对照

    // 天枢阁 / 苏苓 / 白檀 / 顾长卿
    R("suling", "tianshu", "leader"),
    R("baitan", "tianshu", "member"),
    R("suling", "baitan", "colleague"),
    R("baitan", "qingnang", "owner"),
    R("baitan", "qingnang", "user"),
    R("gulang", "tianshu", "ally"),
    R("gulang", "linan", "owner"),            // 知府"治"临安
    R("tianshu", "canglan", "f_ally"),

    // 幽冥教 阵营
    R("yanwujiu", "youming", "leader"),
    R("murongxue", "youming", "member"),
    R("yanwujiu", "murongxue", "master_disciple"),
    R("yanwujiu", "guimian", "alter_ego"),
    R("yanwujiu", "shihun", "mastered"),
    R("murongxue", "shihun", "mastering"),
    R("yanwujiu", "shihunfan", "owner"),
    R("yanwujiu", "shihunfan", "creator"),
    R("youming", "canglan", "f_enemy"),
    R("youming", "shenshi", "f_enemy"),

    // 地点归属
    R("canglan", "qingmingfeng", "owner"),
    R("youming", "youmingyuan", "owner"),
    R("shenshi", "linan", "owner"),
    R("tianshu", "linan", "owner"),

    // 生物 / 演化 / 捕食
    R("shihungu", "shihun", "prerequisite"),  // 蛊成则术成
    R("youming", "shihungu", "owner"),
    R("xuanbingjiao", "youmingyuan", "owner"),
    R("xuanbingjiao", "shihungu", "predator"),
    R("shihungu", "xuanbingjiao", "prey"),
  ];

  // parent is directional with source=父; flip so the arrow reads 父→子 visually.
  // We keep data as authored and let the renderer respect `directed`.

  window.EG_DATA = {
    novel: { title: "青冥引", en: "The Qingming Tether", chapters: 38, words: 156200 },
    entityTypes: ENTITY_TYPES,
    characterRoles: CHARACTER_ROLES,
    relations: RELATIONS,
    relCatColor: REL_CAT_COLOR,
    nodes: NODES,
    edges: REL,
    // default focus = protagonist (resolveDefaultCenterEntityKey behavior).
    defaultCenter: "character_shen",
  };
})();
