// 作品库补充数据。原 data.js 只有 4 部小说，撑不起集合书架和 5 列网格 ——
// 这里追加 8 部。小说和剧本同在一个作品库，集合不分类型：手动集合是标签式的，
// 一部作品可以在多个集合里，小说和它改编的剧本也能放进同一个集合；删集合不删作品。
(function () {
  const extra = [
    {
      id: "n5", title: "吴门旧事", subtitle: "Tales of Wumen",
      description: "苏州城里的七个短篇，写茶馆、裱画铺和河埠头，时间都在同一个梅雨季。",
      tags: ["短篇集", "江南"], chapters: 7, words: 46210, updated: "昨天 21:08",
      cover: "tree", authorName: "怀素", status: "completed",
    },
    {
      id: "n6", title: "漕船志", subtitle: "Grain Barge Chronicle",
      description: "《夜航船》的前传：二十年前那艘漕船沉在瓜洲渡口，船上少了一本账。",
      tags: ["长篇", "明末"], chapters: 9, words: 38400, updated: "3 天前",
      cover: "ink", authorName: "怀素", status: "planning",
    },
    {
      id: "n7", title: "雪夜访戴", subtitle: "A Snowy Night Visit",
      description: "一夜的事：王子猷乘兴而行，兴尽而返。改写成三个视角。",
      tags: ["短篇", "练笔"], chapters: 3, words: 9860, updated: "上周",
      cover: "stars", authorName: "怀素", status: "completed",
    },
    {
      id: "n8", title: "高原纪行", subtitle: "Plateau Notes",
      description: "从西宁到拉萨的一路笔记，散文体，写给十年后的自己。",
      tags: ["散文"], chapters: 14, words: 52300, updated: "上周",
      cover: "mountains", authorName: "怀素", status: "writing",
    },
    {
      id: "n9", title: "对白练习 · 三十则", subtitle: "Dialogue Drills",
      description: "每天一段纯对白，不写动作不写环境，只靠说话推情节。",
      tags: ["练笔"], chapters: 30, words: 21400, updated: "2 周前",
      cover: "tree", authorName: "怀素", status: "writing",
    },
    {
      id: "n10", title: "长夜将尽", subtitle: "The Long Night Ends",
      description: "末日后的第三个冬天，一座图书馆里住着最后十一个读书人。",
      tags: ["长篇", "科幻"], chapters: 26, words: 118900, updated: "上月",
      cover: "stars", authorName: "怀素", status: "writing",
    },
    {
      id: "n11", title: "秦淮灯影", subtitle: "Lanterns on Qinhuai",
      description: "投稿版，按杂志要求压到两万字以内。",
      tags: ["中篇", "江南"], chapters: 6, words: 19800, updated: "上月",
      cover: "ink", authorName: "怀素", status: "completed",
    },
    {
      id: "n12", title: "河神", subtitle: "River God",
      description: "一个捞尸人的自述。想写成长篇，现在只有开头。",
      tags: ["悬疑"], chapters: 2, words: 6100, updated: "2 个月前",
      cover: "mountains", authorName: "怀素", status: "planning",
    },
  ];
  window.REVERIC_DATA.novels.push(...extra);

  // 对齐 Flutter _NovelCard：竖版封面（没有就是灰底书本占位）+ 类型（原创 / 同人）。
  // 封面是 assets/covers 下的竖版占位图，只为看清网格与堆叠效果。
  const covers = {
    n1: "7273678437762468927", n2: "7419244602172902425", n3: "7431516294974819353",
    n5: "7460844307990187033", n6: "7473792313399970840", n8: "7481108346636864536",
    n10: "7484566994277125145", n11: "7489293284141976638",
  };
  const fanfic = new Set(["n7", "n12"]);
  // 分类：data.js 里是「中文 / English」，这里只取中文部分；补充作品按内容给一个。
  const categories = {
    n1: "历史", n2: "文学", n3: "历史", n4: "短篇集", n5: "短篇集", n6: "历史",
    n7: "文学", n8: "散文", n9: "文学", n10: "科幻", n11: "文学", n12: "悬疑",
  };
  window.REVERIC_DATA.novels.forEach((novel) => {
    novel.coverImage = covers[novel.id] ? `assets/covers/${covers[novel.id]}.jpg` : null;
    novel.workType = fanfic.has(novel.id) ? "同人" : "原创";
    novel.categoryLabel = categories[novel.id] || null;
  });

  // 所有集合都是真实记录，数组顺序就是导航顺序（管理里拖动改的就是它）。
  // builtin 只有「全部」；创作中 / 已完本是初始化写入的条件集合，可改名、可删；
  // 其余是用户的手动集合，成员存在 workIds。
  window.COLLECTIONS_SEED = [
    { id: "collection:all", name: "全部", builtin: true },
    { id: "collection:active", name: "创作中", rule: { status: "active" } },
    { id: "collection:finished", name: "已完本", rule: { status: "finished" } },
    { id: "c-jiangnan", name: "江南系列", workIds: ["n1", "sp1", "n5", "n6", "n11"] },
    { id: "c-longform", name: "长篇连载", workIds: ["n10", "n2", "n1"] },
    { id: "c-drills", name: "练笔", workIds: ["n7", "n9"] },
    { id: "c-submit", name: "投稿中", workIds: ["n11", "n3"] },
    { id: "c-autumn", name: "今年秋天要改完的", workIds: [] },
  ];
})();
