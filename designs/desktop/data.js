// Mock data — novels, chapters, AI sessions.
// Bilingual copy reflects the actual product (Chinese primary, English mix).

window.REVERIC_DATA = {
  novels: [
    {
      id: "n1",
      title: "夜航船",
      subtitle: "Night Boat",
      description:
        "明末江南，一艘逆流而上的客船载着失意的画师、逃婚的小姐、隐姓的旧官。每个人都怀着一桩不可对人言的心事，每个人都在等天亮。",
      category: "历史 / Historical",
      tags: ["长篇", "明末", "群像"],
      chapters: 42,
      words: 184320,
      updated: "今天 14:32",
      cover: "ink",
      authorName: "怀素",
      status: "writing",
    },
    {
      id: "n2",
      title: "山影渐落",
      subtitle: "When the Mountains Fade",
      description:
        "一位退休制图师在阿尔卑斯山脚下的小镇接到了一份奇怪的委托——为一座地图上没有的山绘制等高线。",
      category: "文学 / Literary",
      tags: ["中篇", "悬疑", "山"],
      chapters: 18,
      words: 62100,
      updated: "昨天",
      cover: "mountains",
      authorName: "怀素",
      status: "writing",
    },
    {
      id: "n3",
      title: "The Astronomer's Daughter",
      subtitle: "天文学家的女儿",
      description:
        "Lyon, 1893. Hélène inherits her father's telescope, his unfinished star catalogue, and his quarrel with the Académie. She inherits, too, the secret he never wrote down.",
      category: "Historical fiction",
      tags: ["novella", "demo"],
      chapters: 9,
      words: 28400,
      updated: "3 天前",
      cover: "stars",
      authorName: "M. Lemaire",
      status: "planning",
    },
    {
      id: "n4",
      title: "枯木集",
      subtitle: "Withered Tree Anthology",
      description: "一组以宋代山水画为线索的短篇集，每篇围绕一幅画展开。",
      category: "短篇集 / Short stories",
      tags: ["短篇", "宋代"],
      chapters: 7,
      words: 19800,
      updated: "上周",
      cover: "tree",
      authorName: "怀素",
      status: "completed",
    },
  ],

  homeAnnouncement: {
    title: "小说和剧本合到了同一个作品库",
    detail: "在作品区按类型筛选；集合里也可以同时放小说和剧本。",
  },

  agents: [
    {
      id: "a1",
      name: "主笔",
      subtitle: "Primary writing agent",
      icon: "pencil-line",
      emoji: "🖋️",
      role: "写作",
      description:
        "项目的主笔智能体。依据世界观、人物档案与大纲承担主要成稿，决定 AI 落笔时的身份与笔法。",
    },
  ],

  // Subagents — fuller shape mirrors lib/.../subagent_edit_panel.dart's form
  // (slug / name / description / mode / model / enabled / prompt).
  subagents: [
    {
      id: "s1",
      slug: "plot-architect",
      name: "情节顾问",
      subtitle: "情节顾问",
      icon: "tree-structure",
      emoji: "🗺️",
      mode: "council",
      model: "mimo-v2.5 · 默认",
      enabled: true,
      builtin: true,
      useCustomPrompt: false,
      description:
        "在议会模式中担任结构顾问，负责梳理主线、副线与转折节奏，指出大纲中悬而未决的伏笔与动机断层。",
      prompt:
        "你是一名长篇小说的情节顾问，专注结构而非文笔。\n\n职责：\n- 梳理主线 / 副线，标出每个转折的因果链；\n- 指出未回收的伏笔、动机断层、节奏塌陷；\n- 给出可执行的结构调整建议，而非替作者写句子。\n\n输出时先给三句话结论，再逐条展开。",
    },
    {
      id: "s2",
      slug: "character-voice",
      name: "人物声音",
      subtitle: "人物声音",
      icon: "mask-happy",
      emoji: "🎭",
      mode: "chat",
      model: "mimo-v2.5 · 默认",
      enabled: true,
      builtin: false,
      useCustomPrompt: true,
      description:
        "守护每个角色的语气一致性，根据人物档案校验对白是否符合身份、年龄与处境。",
      prompt:
        "你负责守护角色的「声音」一致性。\n\n给定一段对白与对应的人物档案，判断：\n- 用词、句长、语气是否符合身份与年龄；\n- 是否出现了角色不会知道的信息；\n- 情绪强度是否与当前处境匹配。\n\n只在确有偏离时提出修改，逐句给出替换建议。",
    },
    {
      id: "s3",
      slug: "worldbuilding-check",
      name: "世界观考据",
      subtitle: "世界观考据",
      icon: "compass",
      emoji: "🧭",
      mode: "chat",
      model: null,
      enabled: false,
      builtin: false,
      useCustomPrompt: true,
      description:
        "对照世界观设定与历史背景，核查正文中的地理、器物、制度、时间线是否前后自洽。",
      prompt:
        "你是世界观考据助手。对照已建立的世界设定，核查正文中的：\n- 地理与路线是否自洽；\n- 器物、服饰、制度是否符合设定年代；\n- 时间线与既有章节是否冲突。\n\n发现冲突时，引用设定原文与正文原文并列指出。",
    },
  ],

  // Skills — mirrors agent_skill_edit_panel.dart (name / whenToUse /
  // description / prompt / enabled).
  skills: [
    {
      id: "sk1",
      name: "章节扩写",
      subtitle: "Chapter expansion",
      enabled: true,
      builtin: true,
      whenToUse: "当一章只有大纲或寥寥数段，需要在保持既定情节节点的前提下扩展为完整初稿时使用。",
      description: "把章节大纲扩写为符合既定节奏与人物声音的完整初稿。",
      prompt:
        "根据提供的章节大纲、人物档案与世界观设定，扩写为完整章节初稿。\n\n要求：\n- 严格遵守大纲中的情节节点，不擅自新增重大转折；\n- 维持已有的叙事人称与语气；\n- 对白与描写交替，避免大段独白。",
    },
    {
      id: "sk2",
      name: "润色重写",
      subtitle: "Polish & rewrite",
      enabled: true,
      builtin: false,
      whenToUse: "初稿已完成、情节无需改动，只需打磨语言节奏、消除重复与口水句时使用。",
      description: "在不改动情节的前提下打磨语言：节奏、重复、冗词、标点。",
      prompt:
        "对给定段落做语言润色，不改变情节与信息：\n- 消除重复用词与口水句；\n- 调整句子长短，制造节奏；\n- 规范标点与对白格式。\n\n保留作者原有的措辞风格，改动以最小为度。",
    },
    {
      id: "sk3",
      name: "伏笔检查",
      subtitle: "Foreshadowing audit",
      enabled: true,
      builtin: false,
      whenToUse: "完成一卷或多章后，需要检查埋下的伏笔是否回收、是否过早暴露时使用。",
      description: "梳理全书已埋伏笔与其回收状态，标出悬而未决或暴露过早的线索。",
      prompt:
        "通读提供的章节，建立伏笔台账：\n- 每条伏笔的埋设位置与预期回收点；\n- 标出尚未回收、回收过早或自相矛盾的线索；\n- 给出建议的回收章节。\n\n以表格式条目输出，便于作者逐条核对。",
    },
  ],

  // Shortcuts — mirrors ai_shortcut_action_edit_panel.dart (name / prompt /
  // locations / builtin / enabled).
  shortcuts: [
    {
      id: "sc1",
      name: "扩写",
      subtitle: "Expand",
      builtin: true,
      enabled: true,
      description: "在选中段落的基础上扩展细节与描写，保持既定情节与语气不变。",
    },
    {
      id: "sc2",
      name: "润色",
      subtitle: "Polish",
      builtin: true,
      enabled: true,
      description: "打磨选中文字的节奏与措辞，消除重复与口水句，不改动情节。",
    },
    {
      id: "sc3",
      name: "续写",
      subtitle: "Continue",
      builtin: false,
      enabled: false,
      description: "顺着光标处的语气与情境往下写一段，承接当前的叙事节奏。",
    },
  ],

  recentSessions: [
    { id: "r1", title: "第三章·夜遇", time: "今天 14:20" },
    { id: "r2", title: "周清远的视角校验", time: "昨天" },
    { id: "r3", title: "明末江南漕运背景", time: "3 天前" },
  ],

  // Editor view — opening chapter of Night Boat
  chapters: {
    n1: {
      volumes: [
        {
          id: "v1",
          title: "卷一 · 河上人",
          chapters: [
            { id: "c1", number: "01", title: "夜入吴县", words: 4128, state: "已定稿" },
            { id: "c2", number: "02", title: "船头那盏灯", words: 3892, state: "已润色" },
            { id: "c3", number: "03", title: "三舱客", words: 4504, state: "草稿" },
            { id: "c4", number: "04", title: "周清远", words: 0, state: "大纲" },
          ],
        },
        {
          id: "v2",
          title: "卷二 · 雨中人",
          chapters: [
            { id: "c5", number: "05", title: "夜雨", words: 0, state: "大纲" },
            { id: "c6", number: "06", title: "未署名的信", words: 0, state: "未开始" },
          ],
        },
      ],
      world: [
        { id: "w1", icon: "compass", title: "明末江南漕运图" },
        { id: "w2", icon: "mountains", title: "苏州城地理" },
        { id: "w3", icon: "users", title: "船上六人小传" },
      ],
      activeChapterId: "c3",
      activeChapter: {
        number: "03",
        title: "三舱客",
        summary:
          "三个互不相识的客人各自上船，画师周清远暂以化名隐瞒身份；小姐凤瑶藏在男装下；旧官老沈带着一只看似普通的木匣。船未离岸，三个人的目光已经在舱中交错。",
        body: [
          "船家的灯笼挂在桅杆上，照见雨水沿着甲板的纹路缓缓淌下去。周清远把伞收好，伞骨在他袖中微微作响。他没有看身后那两人——他知道，越是不看，越是被看。",
          "“先生，”船家的声音从船尾传来，带着江浙口音的拐弯，“您是要去松江府的，是吧？”",
          "他点了点头，没出声。他的名字写在油纸伞柄上，是他自己刻的。今晚他不打算让任何人看见。",
          "船舱里很暗。三盏小油灯在低梁下摇晃，把每一张脸都照成了半张。坐在他对面的，是一个少年——细眉，唇线却太柔，像被人用过的笔尖一样收不住。少年的手指轻轻按在膝上，指甲很短，但不是男人的样子。",
          "周清远在心里记下了这一笔。",
          "另一个客人坐在最里头，靠着舱壁，怀里抱着一只乌木匣子。匣盖上嵌了一道银线，磨得很旧，但银线那一面，永远朝着他自己。老人闭着眼，嘴角紧抿。周清远见过这种紧抿——那是失意过的人才会有的，像伤疤一样长在脸上。",
          "舱外，雨势变密。船开始动了。",
        ],
        notes:
          "本章是“群像收束”的第一拍。三个人物的身份伏笔在这里同时埋下，必须做到：周清远的画师身份不能明说；凤瑶的女装伏笔通过指甲、唇线两个细节透露；老沈的木匣在第六章揭开，此处只交代“银线那一面朝着他自己”。",
      },
    },
  },

  chatMessages: [
    {
      role: "user",
      content: "我希望第三章的开头能更含蓄一些，三个人的身份伏笔不要一口气全部交代完。",
    },
    {
      role: "assistant",
      blocks: [
        {
          type: "activity",
          steps: [
            {
              kind: "thinking", status: "success",
              detail: { type: "thinking", label: "推理过程", text: "依据本章大纲与人物档案，确定三个身份伏笔的呈现顺序：把木匣线索推迟到周清远第二次抬头之后，避免点名式登场。" },
            },
            {
              verb: "读取", icon: "eye", target: "chapters / 第 03 章 · 三舱客", status: "success",
              detail: { type: "preview", label: "读取片段", text: "船舱里很暗，三个人各怀心事，画师、小姐、旧官的身份在第一段就交代清楚。" },
            },
            {
              verb: "搜索", icon: "magnifying-glass", target: "“老沈的木匣” · 命中 4 处", status: "success",
              detail: { type: "paths", label: "命中 4 处", items: ["chapters / 第 03 章 · 三舱客", "outline / 卷一 · 三舱客", "foreshadow / 乌木匣", "characters / 老沈.md"] },
            },
            {
              verb: "编辑", icon: "note-pencil", target: "第 03 章 · 第 1 段", status: "success", mono: false,
              detail: {
                type: "diff",
                old: "船舱里很暗，三个人各怀心事，画师、小姐、旧官的身份在第一段就交代清楚。",
                now: "船舱里很暗。三盏小油灯在低梁下摇晃，把每一张脸都照成了半张。周清远没有看身后那两人——他知道，越是不看，越是被看。",
              },
            },
            // —— 第二轮 LLM 响应（真实数据里是独立的另一条 assistant 消息）——
            // 与上一轮之间没有 text 等特殊 block，按预期合并进同一个活动卡：
            // thinking → 读取 → 搜索 → 编辑 → thinking → 编辑（出现第二个 thinking 检查点）。
            {
              kind: "thinking", status: "success",
              detail: { type: "thinking", label: "推理过程", text: "第一段已拆分，接着复核“老沈的木匣”这条线的落点——把它从首段移到周清远第二次抬头之后的第六、七段之间，让伏笔晚一拍出现。" },
            },
            {
              verb: "编辑", icon: "note-pencil", target: "第 03 章 · 第 6 段", status: "success", mono: false,
              detail: {
                type: "diff",
                old: "老沈把木匣往怀里又按了按，谁也没有多问。",
                now: "老沈的手始终没离开膝上那只乌木匣。周清远第二次抬头时，正看见他指节收紧——像是怕谁伸手，又像是怕自己松开。",
              },
            },
          ],
        },
        {
          type: "text",
          text: "理解。我把目前第一段拆成两段，并把“老沈的木匣”这条线推迟到周清远第二次抬头之后——也就是第六、第七段之间。这样三个人的身份分别落在三个独立的呼吸节奏里，不会像点名一样依次出场。",
        },
      ],
      reference: "对照参考：人物档案/周清远（画师，松江府）、凤瑶（女扮男装）、老沈（前苏州府同知）。",
    },
    {
      role: "user",
      content: "好。再把这章对白校一遍，并确认木匣伏笔的回收时机。",
    },
    {
      role: "assistant",
      blocks: [
        {
          type: "activity",
          steps: [
            {
              kind: "thinking", status: "success",
              detail: { type: "thinking", label: "推理过程", text: "对白校对需要先回读本章三人的语气基线，再交叉比对人物档案里的说话习惯；木匣伏笔则要核对第三章埋设与第六章回收的呼应。" },
            },
            {
              verb: "读取", icon: "eye", target: "chapters / 第 03 章 · 三舱客", status: "success",
              detail: { type: "preview", label: "读取片段", text: "凤瑶垂眸不语，指节泛白——那截太干净的手腕，藏在袖口里。老沈的手，始终按在膝上的乌木匣上。" },
            },
            {
              verb: "搜索", icon: "magnifying-glass", target: "“木匣” · 命中 4 处", status: "success",
              detail: { type: "paths", label: "命中 4 处", items: ["chapters / 第 03 章 · 三舱客", "chapters / 第 06 章 · 夜泊", "foreshadow / 乌木匣", "characters / 老沈.md"] },
            },
          ],
        },
        {
          type: "todo",
          items: [
            { text: "校对第三章三人对白语气", status: "doing" },
            { text: "确认木匣伏笔的回收时机", status: "todo" },
            { text: "统一卷一雨势描写用词", status: "closed" },
          ],
        },
        {
          type: "askUser",
          question: "木匣的交代时机关系到第六章的回收节奏，你希望：",
          options: [
            { label: "本章末尾暗示，第六章揭开" },
            { label: "本章完全不提，留作长线悬念" },
            { label: "本章直接点破" },
          ],
          hint: "或补充其他想法…",
        },
      ],
    },
    {
      role: "user",
      content: "本章末尾暗示，第六章揭开。",
    },
    {
      role: "assistant",
      streaming: true,
      blocks: [
        {
          type: "activity",
          steps: [
            {
              kind: "thinking", status: "running",
            },
          ],
        },
      ],
    },
  ],
};
