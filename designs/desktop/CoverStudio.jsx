// CoverStudio — 封面工作台。NavRail「资料 · 封面」进入，接管编辑器
// 第二至第四列：生成记录 + 画布 + 封面设计师面板。
// 对应 docs/solutions/cover-studio-and-image-library.md（方案 B）。
//
// 三条与旧版原型不同的前提，都来自方案文档：
//   1. 书名由图像模型直接画进画面。工作台不做标题图层、不做版式后期切换；
//      「书名位置 / 字形气质」是写进提示词的倾向，不是保证，改书名必须重新出图。
//      字形对不对由作者自己放大看 —— 不做定位裁剪的校对模式：书名落在哪儿
//      只有模型知道，按请求的位置去裁，第一个裁错的就是模型没听话的那张。
//   2. 参考图全量随请求发出，提示词按 image 1/2/3 说明各自用途；
//      只有超过模型上限时才按 role 优先级截断，并明确告诉作者哪几张没发出去。
//   3. 停止只停"还没发出的请求"，在途请求仍会完成并入库，批次收敛为 partial / canceled。
//
// 数据模型：一次生成 = 一个批次(batch)，批次里有 4 张图(asset)。
//   批次有状态机 running / stopping / completed / partial / failed / canceled；
//   每张图带溯源（模型 / 尺寸 / 提示词 / 参考图 / 所属批次），对应 image_assets。
// 封面画面复用 assets/images/background/ 的四张水墨底图，不新画插画。
//
// 调试入口：?screen=cover 直达本页，?screen=cover&state=empty 看首次进入的空态。
//   工具栏最右的甲虫按钮里可以切生成结果（全成功 / 单张失败 / 全失败）与失败原因。

// ---- 生成配方 -----------------------------------------------------------

const CS_MODEL = "gpt-image-2";

const CS_IMAGES = [
  { id: "boat", file: "solitary_boat.webp", name: "夜航", motif: "船影入江" },
  { id: "mountains", file: "distant_mountains.webp", name: "远山", motif: "远山淡影" },
  { id: "tree", file: "withered_tree.webp", name: "寒枝", motif: "枯木剪影" },
  { id: "plum", file: "plum_blossom.webp", name: "暗香", motif: "疏影横斜" },
];

// 画面风格 → 画面处理；素纸对照方案固定用 paper，不进轮换。
const CS_TONE_BY_STYLE = {
  水墨写意: "night",
  版画质感: "duotone",
  极简文字: "wash",
  摄影写实: "photo",
  手绘插画: "wash",
};
const CS_TONE_CYCLE = ["night", "wash", "duotone", "photo"];
const CS_TONE_SHORT = { night: "水墨", wash: "淡彩", duotone: "版画", photo: "写实", paper: "素纸" };

// 书名位置是生成参数，写进提示词交给模型画，不是可以事后切换的图层。
// id 同时是 .m-cv-- 的修饰类名。
const CS_TITLE_SPOTS = [
  { id: "vertical", label: "右侧竖排", word: "竖排贴住右侧留白" },
  { id: "centered", label: "上方居中", word: "压在上方留白处" },
  { id: "bottom", label: "左下角", word: "沉在左下角" },
  { id: "typographic", label: "画面中央", word: "居中占住画面" },
];
const CS_TITLE_FONTS = [
  { id: "kai", label: "楷书端正", word: "楷书笔意，端正清晰" },
  { id: "li", label: "隶书古拙", word: "隶书笔意，横平竖阔" },
  { id: "xing", label: "行书洒脱", word: "行书笔意，连笔不失可读" },
  { id: "hei", label: "现代黑体", word: "现代黑体，硬边无衬线" },
];

const CS_STYLES = ["水墨写意", "版画质感", "极简文字", "摄影写实", "手绘插画"];

const CS_PALETTES = [
  { id: "ink", label: "墨与宣", rgb: "20 24 30", swatch: "linear-gradient(135deg, #F3EFE7 0%, #1F2A3D 100%)" },
  { id: "brass", label: "黄铜", rgb: "92 66 34", swatch: "linear-gradient(135deg, #E6CDA8 0%, #8B7355 100%)" },
  { id: "night", label: "夜航", rgb: "16 22 44", swatch: "linear-gradient(135deg, #4A5568 0%, #12161F 100%)" },
  { id: "cinnabar", label: "朱砂", rgb: "84 26 22", swatch: "linear-gradient(135deg, #D9A48F 0%, #A63F35 100%)" },
  { id: "grey", label: "素灰", rgb: "40 42 44", swatch: "linear-gradient(135deg, #FAF8F4 0%, #7E8698 100%)" },
];

const CS_COMPOSITIONS = ["中心构图", "三分构图", "留白构图", "对称构图"];
const CS_COMPOSITION_WORD = {
  中心构图: "主体居中，四周向内收拢",
  三分构图: "主体压在三分线上，另一侧留白",
  留白构图: "主体偏一侧，留出大片可放文字的暗部",
  对称构图: "左右对称，重心落在中轴",
};

// 参考图的用途。每张图挂一个，决定提示词里怎么说它。
// 全部随请求发出（image 1 / image 2 / …）；超过 CS_REF_LIMIT 才按优先级截断。
const CS_REF_ROLES = [
  { id: "style", label: "整体风格", hint: "取笔触与光感，不要它的内容", say: "取它的笔触与光感，不要它的内容" },
  { id: "palette", label: "色调", hint: "只取配色，画面自己重画", say: "只取它的配色，画面自己重画" },
  { id: "composition", label: "构图", hint: "取主体位置与留白", say: "取它的主体位置与留白关系" },
  { id: "character", label: "主角形象", hint: "跨批次保持同一个人", say: "是主角形象，保持同一个人" },
  { id: "base", label: "在此基础上改", hint: "把它当底图重绘", say: "作为底图重绘，保留大结构" },
];
// 只在超上限时用：谁先被留下。
const CS_REF_PRIORITY = ["base", "character", "composition", "style", "palette"];
// 前沿模型的实际上限远高于此：gpt-image-1 的 images/edits 是 16 张，
// Nano Banana Pro 14 张，Seedream 4.5 官方 10 张。6 是保守的产品占位值，
// 真实值由网关按 model 校验（见方案 5.4）。调试开关里可临时调低看截断提示。
const CS_REF_LIMIT = 6;
const CS_REF_LIMITS = [2, 3, 6, 10, 14];

// 参考图来源：图片库里的图，或作者本地拖进来的（原型里都用同一批底图模拟）。
const CS_LIBRARY = [
  { id: "lib-boat", src: "solitary_boat.webp", name: "孤舟", rgb: "20 24 30" },
  { id: "lib-mountains", src: "distant_mountains.webp", name: "远山", rgb: "40 42 44" },
  { id: "lib-tree", src: "withered_tree.webp", name: "枯木", rgb: "92 66 34" },
  { id: "lib-plum", src: "plum_blossom.webp", name: "疏梅", rgb: "84 26 22" },
];

// 尺寸按用途定，不按 provider 能出多大定。out 是模型实际出图尺寸，
// 出图后按重心裁到 px；不足目标尺寸也不做 upscale。
const CS_RATIOS = [
  { id: "portrait", label: "竖版", hint: "2:3", ratio: "2 / 3", px: "1440 × 2160", out: "1728 × 2304", use: "书库列表与详情页" },
  { id: "landscape", label: "横版", hint: "3:2", ratio: "3 / 2", px: "2160 × 1440", out: "2304 × 1728", use: "站内横幅" },
  { id: "square", label: "方版", hint: "1:1", ratio: "1 / 1", px: "1600 × 1600", out: "2048 × 2048", use: "分享卡片" },
];

// 100% 时主预览的宽度；缩放在这个基准上算实际宽度。
const CS_PAPER_WIDTH = 400;
// 书名画在像素里，字有没有画错只能靠放大看，所以上限要够得着 1:1：
// 100% 是 400px，成图 1440px 宽，360% 才是像素级 1:1，上限给到 400%。
const CS_ZOOM = { min: 40, max: 400, step: 20, fit: 100 };

// 按实际出图张数计费，不预扣、不退款。
const CS_COUNT = 4;

const CS_STATUS = {
  running: { label: "生成中", cls: "is-live" },
  stopping: { label: "收尾中", cls: "is-live" },
  completed: { label: null, cls: "" },
  partial: { label: "部分完成", cls: "is-warn" },
  canceled: { label: "已取消", cls: "is-muted" },
  failed: { label: "失败", cls: "is-bad" },
};

// image.dart 的 _userMessageFromServerMessage 归的五类，各配一句可操作的下一步。
const CS_ERRORS = {
  moderation: { title: "内容未过审", body: "提示词里有一处措辞触发了内容策略。改掉那处再重出这张，其余方案不受影响。" },
  rate: { title: "请求过于频繁", body: "网关限流，等十几秒再重出这张。" },
  key: { title: "密钥无效", body: "图像模型的 API Key 无效或已过期。去 AI 提供商里更新后，再重出这一批。" },
  size: { title: "尺寸不支持", body: "该模型出不了这个比例。换一个目标比例，或者接受最近尺寸后裁切。" },
  param: { title: "模型不支持该参数", body: "多参考图超出了这个模型的能力。减掉一张参考图再重出。" },
};
const CS_ERROR_LIST = ["moderation", "rate", "key", "size", "param"];

// 稿子当前的体量。读档案时记一份快照，之后拿来判断档案有没有过时。
// grown 是调试开关模拟的「后来又写了几章」。
const CS_STATS = { words: 18.4, chapters: 42 };
const CS_STATS_GROWN = { words: 21.6, chapters: 50 };
// 过时阈值：多写 5 章，或者字数涨了两成，就提示一次，但不自动重读。
const CS_STALE_CHAPTERS = 5;
const CS_STALE_WORDS = 0.2;

// CoverBriefService 读稿之后的结构化封面档案：意象必须带出处章节。
const CS_BRIEF = {
  category: "历史 · 群像",
  temperature: "冷灰为底，暖色只留给灯与印章",
  figure: "没有单一主角，建议以意象替代具体人物",
  era: "明末江南，避开现代器物与现代字体",
  motifs: [
    { text: "江面与渔火", from: "第 3 章 夜泊" },
    { text: "空舟系岸", from: "第 17 章 别渡" },
    { text: "残雪覆瓦", from: "第 31 章 归期" },
  ],
};

function csPalette(id) {
  return CS_PALETTES.find((p) => p.id === id) || CS_PALETTES[0];
}
function csRole(id) {
  return CS_REF_ROLES.find((r) => r.id === id) || CS_REF_ROLES[0];
}
function csSpot(id) {
  return CS_TITLE_SPOTS.find((s) => s.id === id) || CS_TITLE_SPOTS[0];
}
function csFont(id) {
  return CS_TITLE_FONTS.find((f) => f.id === id) || CS_TITLE_FONTS[0];
}
function csRatio(id) {
  return CS_RATIOS.find((r) => r.id === id) || CS_RATIOS[0];
}

// 参考图全发，超上限才按优先级留下前 N 张，其余明确告知未发送。
function csSplitRefs(refs, limit = CS_REF_LIMIT) {
  if (refs.length <= limit) return { sent: refs, dropped: [] };
  const ranked = [...refs].sort(
    (a, b) => CS_REF_PRIORITY.indexOf(a.role) - CS_REF_PRIORITY.indexOf(b.role)
  );
  return { sent: ranked.slice(0, limit), dropped: ranked.slice(limit) };
}

// 组装实际下发的提示词。评测断言全打在这段上：书名原文 / 位置 / 字形气质 /
// 禁项 / 参考图编号，所以原型里要让它可见。
// brief 为 null 表示还没读稿：品类 / 色温 / 意象 / 主角 / 时代这几行直接不写，
// 出图照常，不拿读稿挡住生成。
function csBuildPrompt({
  novel,
  style,
  palette,
  composition,
  extra,
  refs,
  titleSpot,
  titleFont,
  ratioId,
  brief = CS_BRIEF,
}) {
  const pal = csPalette(palette);
  const paletteRef = refs.find((r) => r.role === "palette");
  const spot = csSpot(titleSpot);
  const font = csFont(titleFont);
  const ratio = csRatio(ratioId);
  const lines = [];

  lines.push(`为长篇小说《${novel.title}》绘制封面。` + (brief ? `品类：${brief.category}。` : ""));
  lines.push(
    `画面：${style}。${paletteRef ? "配色跟随参考图" : `色调${pal.label}`}` +
      (brief
        ? `，${brief.temperature}。核心意象取「${brief.motifs[0].text}」（${brief.motifs[0].from}）。`
        : "。")
  );
  lines.push(
    `构图：${composition}，${CS_COMPOSITION_WORD[composition]}。` + (brief ? `${brief.figure}。` : "")
  );
  if (refs.length) {
    lines.push(
      `参考：${refs.map((r, i) => `image ${i + 1} ${csRole(r.role).say}`).join("；")}。`
    );
  }
  lines.push(
    `书名：把「${novel.title}」这几个字画进画面，${spot.word}，${font.word}，` +
      `字与画面的光影材质一致；作者署名「${novel.authorName} 著」以小字落在下缘。`
  );
  if (brief) lines.push(`时代：${brief.era}。`);
  if (extra) lines.push(`补充：${extra}。`);
  lines.push("禁止：水印、logo、除书名与署名外的任何文字、错别字与缺笔。");
  lines.push(`输出：${ratio.hint} ${ratio.label}。`);
  return lines.join("\n");
}

// 一批 4 张：三张走画面，第四张是素纸对照。
// seed 让每次生成的意象顺序错开，同样的参数不会给出一模一样的四张。
function csBuildScheme({ style, palette, composition, titleSpot, seed, i, refs, error }) {
  const pal = csPalette(palette);
  const paletteRef = refs.find((r) => r.role === "palette");
  const rgb = paletteRef ? paletteRef.rgb : pal.rgb;
  const baseRef = refs.find((r) => r.role === "base");

  if (error) {
    return { id: `${seed}-${i}-fail`, slot: i, status: "failed", error, name: `方案 ${i + 1}` };
  }

  if (i === 3) {
    return {
      id: `${seed}-plain`,
      slot: i,
      status: "ok",
      name: "素纸",
      image: null,
      tone: "paper",
      titleSpot: "typographic",
      palette: pal.id,
      rgb,
      note: `不用画面，书名${csSpot("typographic").word}`,
      brief: `${CS_TONE_SHORT.paper} · 素纸`,
    };
  }

  const toneStart = Math.max(0, CS_TONE_CYCLE.indexOf(CS_TONE_BY_STYLE[style] || "night"));
  const img = baseRef
    ? { id: baseRef.id, file: baseRef.src, name: baseRef.name, motif: "沿用参考图" }
    : CS_IMAGES[(seed + i) % CS_IMAGES.length];
  const tone = CS_TONE_CYCLE[(toneStart + i) % CS_TONE_CYCLE.length];
  return {
    id: `${seed}-${img.id}-${tone}-${i}`,
    slot: i,
    status: "ok",
    name: img.name,
    image: img.file,
    tone,
    titleSpot,
    palette: pal.id,
    rgb,
    note: `${img.motif}，书名${csSpot(titleSpot).word}`,
    brief: `${CS_TONE_SHORT[tone]} · ${img.name}`,
  };
}

function csBuildBatch(params) {
  const { style, palette, composition, extra, seed, when, label, refs = [], fail } = params;
  const pal = csPalette(palette);
  const paletteRef = refs.find((r) => r.role === "palette");
  const schemes = [0, 1, 2, 3].map((i) =>
    csBuildScheme({
      ...params,
      refs,
      i,
      error: fail && (fail.mode === "all" || (fail.mode === "one" && i === 1)) ? fail.code : null,
    })
  );
  return {
    id: `batch-${seed}`,
    when,
    label: label || null,
    status: "running",
    note:
      `${style} · ${paletteRef ? "参考图配色" : pal.label}` +
      (refs.length ? ` · ${refs.length} 张参考图` : "") +
      (extra ? " · 带补充要求" : ""),
    model: CS_MODEL,
    style,
    palette: pal.id,
    composition,
    titleSpot: params.titleSpot,
    titleFont: params.titleFont,
    ratioId: params.ratioId,
    extra: extra || "",
    // 这一批出图时用的是哪份档案：溯源里重算提示词要按当时的档案，不能按现在的。
    brief: params.brief === undefined ? CS_BRIEF : params.brief,
    refs,
    dropped: params.dropped || [],
    prompt: params.prompt || "",
    schemes,
  };
}

// 进入页面时已有的三批，最新的一批就是当前批次。
function csSeedBatch(overrides) {
  return csBuildBatch({
    titleSpot: "vertical",
    titleFont: "kai",
    ratioId: "portrait",
    extra: "",
    refs: [],
    ...overrides,
  });
}
const CS_INITIAL_BATCHES = [
  { ...csSeedBatch({ style: "水墨写意", palette: "ink", composition: "留白构图", seed: 0, when: "今天 14:32" }), status: "completed" },
  {
    ...csSeedBatch({ style: "摄影写实", palette: "night", composition: "中心构图", titleSpot: "centered", seed: 1, when: "昨天 21:10" }),
    status: "partial",
    note: "摄影写实 · 夜航 · 中途停止，保留 3 张",
  },
  { ...csSeedBatch({ style: "手绘插画", palette: "cinnabar", composition: "三分构图", titleSpot: "bottom", seed: 2, when: "6 月 26 日" }), status: "completed" },
];
CS_INITIAL_BATCHES[1].schemes = CS_INITIAL_BATCHES[1].schemes.slice(0, 3);

function csClock() {
  const d = new Date();
  return `今天 ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

// 读完一遍的产物：档案本身，加上「按哪一版稿子读的」的快照。
function csReadBrief(stats, when) {
  return { ...CS_BRIEF, when: when || csClock(), words: stats.words, chapters: stats.chapters };
}

// 档案过时与否只按体量判断，不去猜内容改了什么。
function csBriefStale(brief, stats) {
  if (!brief) return false;
  return (
    stats.chapters - brief.chapters >= CS_STALE_CHAPTERS ||
    stats.words / brief.words - 1 >= CS_STALE_WORDS
  );
}

// ---- 封面画面 -----------------------------------------------------------

// 书名与作者是模型画进画面的一部分；原型用衬线体模拟它，字号按封面宽度
// 换算（1em ≈ 宽度/26），缩略图与大画布共用同一套渲染，不各写一份。
function CoverArt({ scheme, novel, width, ratio = "2 / 3" }) {
  return (
    <div
      className={`m-cv m-cv--${scheme.tone} m-cv--${scheme.titleSpot}`}
      style={{
        fontSize: `${width / 26}px`,
        aspectRatio: ratio,
        "--cv-rgb": scheme.rgb || csPalette(scheme.palette).rgb,
      }}
    >
      {scheme.image && (
        <img className="m-cv__img" src={`assets/images/background/${scheme.image}`} alt="" />
      )}
      <div className="m-cv__scrim" />
      <div className="m-cv__lockup">
        <div className="m-cv__title">{novel.title}</div>
        <div className="m-cv__rule" />
        <div className="m-cv__sub">{novel.subtitle}</div>
      </div>
      <div className="m-cv__author">{novel.authorName} 著</div>
    </div>
  );
}

// 生成中的占位：按最终封面的比例留位，扫光表示这一张还在画。
function CoverSkeleton({ ratio = "2 / 3", label }) {
  return (
    <div className="m-cs-skeleton" style={{ aspectRatio: ratio }}>
      <span className="m-cs-skeleton__sheen" />
      {label && <span className="m-cs-skeleton__label">{label}</span>}
    </div>
  );
}

// 单张失败：只影响这一张，写清是哪一类错、下一步做什么。
function CoverFailure({ scheme, ratio = "2 / 3", onRework, busy }) {
  const err = CS_ERRORS[scheme.error] || CS_ERRORS.moderation;
  return (
    <div className="m-cs-fail" style={{ aspectRatio: ratio }}>
      <span className="m-cs-fail__icon">
        <Icon name="warning" size={20} />
      </span>
      <div className="m-cs-fail__title">{err.title}</div>
      <p className="m-cs-fail__body">{err.body}</p>
      <button className="m-btn m-btn--secondary m-btn--sm" type="button" disabled={busy} onClick={onRework}>
        <Icon name="arrow-clockwise" size={14} />
        重出这张
      </button>
    </div>
  );
}

// ---- 方案缩略图：贴在主预览旁边的一竖排 ---------------------------------

// 竖排贴着大图放，不另开一列、也不占画布高度 —— 竖版封面的瓶颈是高度，
// 而大图两侧的宽度本来就是富余的。点一张就换主预览。
function CoverFilmstrip({ novel, slots, activeId, appliedId, reworkAt, onSelect }) {
  return (
    <div className="m-cs-films">
      {slots.map((scheme, i) => {
        if (reworkAt === i) {
          return (
            <div key={`rework-${i}`} className="m-cs-film is-pending">
              <CoverSkeleton />
              <span className="m-cs-film__num">{i + 1}</span>
            </div>
          );
        }
        if (!scheme) {
          return (
            <div key={`slot-${i}`} className="m-cs-film is-pending">
              <CoverSkeleton />
              <span className="m-cs-film__num">{i + 1}</span>
            </div>
          );
        }
        if (scheme.status === "failed") {
          return (
            <button
              key={scheme.id}
              type="button"
              title={`方案 ${i + 1} · ${(CS_ERRORS[scheme.error] || {}).title}`}
              onClick={() => onSelect(scheme.id)}
              className={"m-cs-film is-failed" + (scheme.id === activeId ? " is-active" : "")}
            >
              <span className="m-cs-film__fail">
                <Icon name="warning" size={14} />
              </span>
              <span className="m-cs-film__num">{i + 1}</span>
            </button>
          );
        }
        return (
          <button
            key={scheme.id}
            type="button"
            title={`方案 ${i + 1} · ${scheme.name} — ${scheme.brief}`}
            onClick={() => onSelect(scheme.id)}
            className={"m-cs-film" + (scheme.id === activeId ? " is-active" : "")}
          >
            <CoverArt scheme={scheme} novel={novel} width={64} />
            <span className="m-cs-film__num">{i + 1}</span>
            {scheme.rework && <span className="m-cs-film__redo" title="重出的一张" />}
            {scheme.id === appliedId && (
              <span className="m-cs-film__applied" title="当前封面">
                <Icon name="check" size={10} />
              </span>
            )}
          </button>
        );
      })}
    </div>
  );
}

// ---- 第二列：生成记录 ---------------------------------------------------

function CoverRail({ novel, batches, batch, busy, onSelectBatch, onReuse, onBack }) {
  return (
    <aside className="m-ctx">
      <PanelHeader onBack={onBack} onCollapse={() => {}} />
      <NovelSwitcher novel={novel} />

      <div className="m-ctx__sec-head">
        <span className="m-ctx__sec-title">生成记录</span>
        <span className="m-ctx__sec-count">{batches.length}</span>
      </div>

      <div className="m-cs-rail__list">
        {batches.length === 0 && <div className="m-cs-rail__blank">生成后会记在这里</div>}
        {batches.map((b) => {
          const st = CS_STATUS[b.status] || CS_STATUS.completed;
          return (
            <div
              key={b.id}
              className={"m-cs-batch" + (batch && b.id === batch.id ? " is-current" : "")}
            >
              <button type="button" className="m-cs-batch__main" onClick={() => onSelectBatch(b.id)}>
                <Icon name="clock-counter-clockwise" size={14} />
                <span className="m-cs-batch__meta">
                  <span className="m-cs-batch__when">
                    <span className="m-cs-batch__time">{b.when}</span>
                    <span className="m-cs-batch__count">{b.schemes.length} 张</span>
                    {st.label && (
                      <span className={"m-cs-batch__state " + st.cls}>{st.label}</span>
                    )}
                    {b.label && <span className="m-cs-batch__label">{b.label}</span>}
                  </span>
                  <span className="m-cs-batch__note">{b.note}</span>
                  {b.refs && b.refs.length > 0 && (
                    <span className="m-cs-batch__refs">
                      {b.refs.map((r) => (
                        <img key={r.id} src={`assets/images/background/${r.src}`} alt="" />
                      ))}
                    </span>
                  )}
                </span>
              </button>
              <button
                className="m-icon-btn m-icon-btn--ghost m-cs-batch__reuse"
                title="按这批参数再来一次"
                disabled={busy}
                onClick={() => onReuse(b.id)}
              >
                <Icon name="arrow-clockwise" size={12} />
              </button>
            </div>
          );
        })}
      </div>
    </aside>
  );
}

// ---- 第三列：画布 -------------------------------------------------------

// 画布底下的一条工具带。溯源与缩放原本一个在文档流里、一个浮在画布上，
// 两者在同一带高度里互相压着；合成一条后只剩一个落点。
// children 是缩放那一组；不给就只剩一个溯源。
function CoverMetaBar({ children, traceOpen, onTrace }) {
  return (
    <div className="m-cs-meta__bar">
      <button
        className={"m-cs-meta__btn" + (traceOpen ? " is-on" : "")}
        type="button"
        onClick={onTrace}
        aria-expanded={traceOpen}
      >
        <Icon name={traceOpen ? "caret-down" : "caret-right"} size={12} />
        溯源
      </button>
      {children && (
        <React.Fragment>
          <span className="m-cs-meta__sep" />
          {children}
        </React.Fragment>
      )}
    </div>
  );
}

function CoverZoom({ zoom, onZoom }) {
  return (
    <React.Fragment>
      <button
        className="m-icon-btn m-icon-btn--ghost"
        type="button"
        title="缩小"
        disabled={zoom <= CS_ZOOM.min}
        onClick={() => onZoom(Math.max(CS_ZOOM.min, zoom - CS_ZOOM.step))}
      >
        <Icon name="arrows-in" size={14} />
      </button>
      <span className="m-cs-meta__value">{zoom}%</span>
      <button
        className="m-icon-btn m-icon-btn--ghost"
        type="button"
        title="放大到能看清字"
        disabled={zoom >= CS_ZOOM.max}
        onClick={() => onZoom(Math.min(CS_ZOOM.max, zoom + CS_ZOOM.step))}
      >
        <Icon name="arrows-out" size={14} />
      </button>
      <span className="m-cs-meta__sep" />
      <button
        className="m-cs-meta__btn"
        type="button"
        disabled={zoom === CS_ZOOM.fit}
        onClick={() => onZoom(CS_ZOOM.fit)}
      >
        适应画布
      </button>
    </React.Fragment>
  );
}

// 溯源：这一张来自哪次调用、什么提示词、哪个模型。对应 image_assets 的一行。
function CoverTrace({ novel, scheme, batch, ratio, open, onToggle, children }) {
  const prompt = batch.prompt || csBuildPrompt({ novel, ...batch, ratioId: batch.ratioId });
  return (
    <React.Fragment>
      <CoverMetaBar traceOpen={open} onTrace={onToggle}>
        {children}
      </CoverMetaBar>
      {open && (
        <div className="m-cs-trace__body">
          <div className="m-cs-trace__row">
            <span>模型</span>
            <code>{batch.model}</code>
          </div>
          <div className="m-cs-trace__row">
            <span>尺寸</span>
            <code>
              {ratio.out} → 按重心裁到 {ratio.px}
            </code>
          </div>
          <div className="m-cs-trace__row">
            <span>批次</span>
            <code>
              {batch.id} · {batch.when} · 第 {scheme.slot + 1} 张
            </code>
          </div>
          <div className="m-cs-trace__row">
            <span>参考图</span>
            <code>
              {batch.refs.length
                ? batch.refs.map((r, i) => `image ${i + 1} ${r.name}（${csRole(r.role).label}）`).join("　")
                : "无"}
            </code>
          </div>
          {scheme.previous && (
            <div className="m-cs-trace__row">
              <span>重出自</span>
              <span className="m-cs-trace__prev">
                <code>{scheme.previous.name}</code>
                {scheme.previous.image && (
                  <img src={`assets/images/background/${scheme.previous.image}`} alt="" />
                )}
              </span>
            </div>
          )}
          <div className="m-cs-trace__row m-cs-trace__row--block">
            <span>提示词</span>
            <pre className="m-cs-prompt">{prompt}</pre>
          </div>
        </div>
      )}
    </React.Fragment>
  );
}

function CoverDebug({ open, onOpen, fail, onFail, error, onError, limit, onLimit, grown, onGrown, onClear }) {
  return (
    <div className="m-cs-debug">
      <button
        className={"m-icon-btn m-icon-btn--ghost" + (fail !== "none" ? " is-on" : "")}
        title="调试开关"
        onClick={() => onOpen(!open)}
      >
        <Icon name="bug-beetle" size={14} />
      </button>
      {open && (
        <div className="m-cs-debug__pop">
          <div className="m-cs-debug__label">下一批的生成结果</div>
          {[
            { id: "none", label: "全部成功" },
            { id: "one", label: "第 2 张失败" },
            { id: "all", label: "全部失败" },
          ].map((o) => (
            <button
              key={o.id}
              type="button"
              className={"m-cs-debug__opt" + (fail === o.id ? " is-on" : "")}
              onClick={() => onFail(o.id)}
            >
              {o.label}
            </button>
          ))}
          <div className="m-cs-debug__label">失败原因</div>
          <select className="m-cs-ref__role" value={error} onChange={(e) => onError(e.target.value)}>
            {CS_ERROR_LIST.map((id) => (
              <option key={id} value={id}>
                {CS_ERRORS[id].title}
              </option>
            ))}
          </select>
          <div className="m-cs-debug__label">参考图上限（网关按 model 定）</div>
          <select
            className="m-cs-ref__role"
            value={limit}
            onChange={(e) => onLimit(Number(e.target.value))}
          >
            {CS_REF_LIMITS.map((n) => (
              <option key={n} value={n}>
                {n} 张
              </option>
            ))}
          </select>
          <div className="m-cs-debug__label">读完档案之后稿子的变化</div>
          {[
            { id: false, label: "没再写" },
            { id: true, label: "又写了 8 章（档案过时）" },
          ].map((o) => (
            <button
              key={String(o.id)}
              type="button"
              className={"m-cs-debug__opt" + (grown === o.id ? " is-on" : "")}
              onClick={() => onGrown(o.id)}
            >
              {o.label}
            </button>
          ))}
          <button type="button" className="m-cs-debug__opt" onClick={onClear}>
            清空记录与档案（看空态）
          </button>
        </div>
      )}
    </div>
  );
}

function CoverCanvas({
  novel,
  scheme,
  index,
  batch,
  slots,
  activeId,
  appliedId,
  reworkAt,
  onSelectScheme,
  ratioId,
  onRatio,
  zoom,
  onZoom,
  applied,
  busy,
  progress,
  stopping,
  traceOpen,
  onTrace,
  onApply,
  onRework,
  onSeedFrom,
  onGenerate,
  debug,
}) {
  const ratio = csRatio(ratioId);
  const empty = !scheme && !busy && !batch;
  const failed = scheme && scheme.status === "failed";
  const paperWidth = Math.round(CS_PAPER_WIDTH * (zoom / 100));

  return (
    <div className="m-editor">
      <div className="m-toolbar">
        <div className="m-segmented">
          {CS_RATIOS.map((r) => (
            <button
              key={r.id}
              type="button"
              onClick={() => onRatio(r.id)}
              className={"m-segmented__item" + (r.id === ratioId ? " is-active" : "")}
            >
              <Icon name={r.id === "landscape" ? "image" : "image-square"} size={14} />
              {r.label}
              <span className="m-cs-canvas__ratio">{r.hint}</span>
            </button>
          ))}
        </div>
        <div className="m-toolbar__spacer" />
        <button className="m-btn m-btn--text m-btn--sm" type="button" disabled={!scheme || failed}>
          <Icon name="download-simple" size={14} />
          导出
        </button>
        <CoverDebug {...debug} />
      </div>

      <div className="m-cs-stage">
        <div className="m-cs-stage__col">
          {/* 主列宽度锁在画面宽度上：展开溯源不会把这一列撑宽、把缩略图推离主图 */}
          <div className="m-cs-stage__main" style={{ width: Math.max(CS_PAPER_WIDTH, paperWidth) }}>
            {empty ? (
              <div className="m-cs-empty">
                <span className="m-cs-empty__icon">
                  <Icon name="palette" size={22} />
                </span>
                <div className="m-cs-empty__title">还没有为《{novel.title}》做过封面</div>
                <p className="m-cs-empty__body">
                  在右侧挑一个画面风格与色调，设计师会读一遍全稿，一次给出四个方向。
                  书名由模型直接画进画面，出图后放大看一眼字有没有画错。
                </p>
                <button className="m-btn m-btn--primary m-btn--sm" type="button" onClick={onGenerate}>
                  <Icon name="sparkle" size={14} />
                  生成 {CS_COUNT} 个方案
                </button>
              </div>
            ) : reworkAt === index ? (
              <React.Fragment>
                <div className="m-cs-stage__paper m-cs-stage__paper--pending">
                  <CoverSkeleton ratio={ratio.ratio} label={`正在重出第 ${index + 1} 张`} />
                </div>
                <div className="m-cs-stage__caption">沿用这一批的参数与参考图，只重跑这一张。</div>
              </React.Fragment>
            ) : !scheme ? (
              <React.Fragment>
                <div className="m-cs-stage__paper m-cs-stage__paper--pending">
                  <CoverSkeleton
                    ratio={ratio.ratio}
                    label={stopping ? "在途的一张还在画" : `正在画第 ${progress.done + 1} 张`}
                  />
                </div>
                <div className="m-cs-stage__caption">
                  {stopping
                    ? "已停止发起新请求。已经发出去的这张会画完、计费并入库。"
                    : `按「${batch.style} · ${csPalette(batch.palette).label} · ${batch.composition}」生成`}
                  {!stopping && batch.refs && batch.refs.length > 0
                    ? `，参考 ${batch.refs
                        .map((r, i) => `image ${i + 1}（${csRole(r.role).label}）`)
                        .join("、")}`
                    : ""}
                  {!stopping && batch.extra ? `，并照顾到「${batch.extra}」` : ""}
                </div>
              </React.Fragment>
            ) : failed ? (
              <React.Fragment>
                <div className="m-cs-stage__paper m-cs-stage__paper--pending">
                  <CoverFailure scheme={scheme} ratio={ratio.ratio} onRework={onRework} busy={busy} />
                </div>
                <div className="m-cs-stage__caption">
                  第 {index + 1} 张失败，其余方案已照常出图。
                </div>
              </React.Fragment>
            ) : (
              <React.Fragment>
                {/* 缩放改画面宽度而不是 transform：transform 不占布局，
                    放大后会盖住下面的说明与工具带。 */}
                <div className="m-cs-stage__paper" style={{ width: paperWidth }}>
                  <CoverArt scheme={scheme} novel={novel} width={paperWidth} ratio={ratio.ratio} />
                </div>
                <div className="m-cs-stage__caption">
                  <span className="m-cs-stage__caption-name">
                    方案 {index + 1} · {scheme.name}
                  </span>
                  <span className="m-cs-stage__caption-note">{scheme.note}</span>
                </div>
                {batch && (
                  <CoverTrace
                    novel={novel}
                    scheme={scheme}
                    batch={batch}
                    ratio={ratio}
                    open={traceOpen}
                    onToggle={onTrace}
                  >
                    <CoverZoom zoom={zoom} onZoom={onZoom} />
                  </CoverTrace>
                )}
              </React.Fragment>
            )}
          </div>

          {slots.length > 0 && (
            <CoverFilmstrip
              novel={novel}
              slots={slots}
              activeId={activeId}
              appliedId={appliedId}
              reworkAt={reworkAt}
              onSelect={onSelectScheme}
            />
          )}
        </div>

      </div>

      <div className="m-cs-actions">
        <div className="m-cs-actions__group">
          <button
            className="m-btn m-btn--secondary m-btn--sm"
            type="button"
            disabled={!scheme || busy}
            onClick={onRework}
          >
            <Icon name="arrow-clockwise" size={14} />
            重出这张
          </button>
          <button
            className="m-btn m-btn--secondary m-btn--sm"
            type="button"
            disabled={!scheme || failed || busy}
            onClick={onSeedFrom}
          >
            <Icon name="stack" size={14} />
            以此为参考再来一批
          </button>
        </div>
        <div className="m-toolbar__spacer" />
        <span
          className="m-cs-actions__meta"
          title={`目标尺寸 ${ratio.px}。模型出 ${ratio.out}，按重心裁到目标尺寸，不做放大`}
        >
          {ratio.px} · {ratio.use}
        </span>
        <button
          className="m-btn m-btn--primary m-btn--sm"
          type="button"
          disabled={!scheme || failed || applied}
          onClick={onApply}
        >
          <Icon name={applied ? "check-circle" : "check"} size={14} />
          {applied ? "已是作品封面" : "设为作品封面"}
        </button>
      </div>
    </div>
  );
}

// ---- 参考图 -------------------------------------------------------------

// 一张参考图 + 一个用途。全部随请求发出，编号与提示词里的 image N 对齐；
// 只有超过模型上限时才有「未发送」。
function CoverRefRow({ item, num, onRole, onRemove }) {
  const role = csRole(item.role);
  return (
    <div className={"m-cs-ref" + (num ? "" : " is-dropped")}>
      <span className="m-cs-ref__thumb">
        <img src={`assets/images/background/${item.src}`} alt="" />
        <span className={"m-cs-ref__num" + (num ? "" : " is-dropped")}>
          {num ? `image ${num}` : "未发送"}
        </span>
      </span>
      <div className="m-cs-ref__meta">
        <div className="m-cs-ref__head">
          <span className="m-cs-ref__name">{item.name}</span>
          <button
            className="m-icon-btn m-icon-btn--ghost"
            title="移除"
            onClick={() => onRemove(item.id)}
          >
            <Icon name="x" size={12} />
          </button>
        </div>
        <select
          className="m-cs-ref__role"
          value={item.role}
          onChange={(e) => onRole(item.id, e.target.value)}
        >
          {CS_REF_ROLES.map((r) => (
            <option key={r.id} value={r.id}>
              {r.label}
            </option>
          ))}
        </select>
        <div className="m-cs-ref__hint">{role.hint}</div>
      </div>
    </div>
  );
}

function CoverRefs({ refs, limit, picking, onPicking, onAdd, onRole, onRemove }) {
  const { sent, dropped } = csSplitRefs(refs, limit);
  const ordered = [...sent, ...dropped];
  return (
    <section className="m-cs-sec">
      <div className="m-cs-sec__head">
        <Icon name="image-square" size={14} color="var(--accent-warm)" />
        <span className="m-cs-sec__title">参考图</span>
        <button className="m-cs-sec__link" type="button" onClick={() => onPicking(!picking)}>
          {picking ? "收起" : "添加"}
        </button>
      </div>

      {refs.length === 0 && !picking && (
        <button className="m-cs-ref__drop" type="button" onClick={() => onPicking(true)}>
          <Icon name="image" size={16} />
          <span>拖入图片，或从图片库选</span>
        </button>
      )}

      {ordered.map((item) => (
        <CoverRefRow
          key={item.id}
          item={item}
          num={sent.indexOf(item) >= 0 ? sent.indexOf(item) + 1 : null}
          onRole={onRole}
          onRemove={onRemove}
        />
      ))}

      {picking && (
        <div className="m-cs-picker">
          <div className="m-cs-picker__label">图片库</div>
          <div className="m-cs-picker__grid">
            {CS_LIBRARY.map((item) => (
              <button
                key={item.id}
                type="button"
                className="m-cs-picker__tile"
                title={item.name}
                onClick={() => onAdd(item)}
              >
                <img src={`assets/images/background/${item.src}`} alt="" />
              </button>
            ))}
          </div>
        </div>
      )}

      {dropped.length > 0 && (
        <div className="m-cs-alert">
          <Icon name="warning" size={13} />
          <span>
            这个模型一次最多接受 {limit} 张参考图。已保留 image 1–{limit}，
            {dropped.map((d) => `「${d.name}（${csRole(d.role).label}）」`).join("")}
            这次不会发出。
          </span>
        </div>
      )}

      {refs.length > 0 && dropped.length === 0 && (
        <div className="m-cs-ref__note">
          参考图全部随请求发出，提示词按 image 1/2/3 说明各自用途。
        </div>
      )}
    </section>
  );
}

// ---- 第四列：封面设计师 -------------------------------------------------

// 封面档案的四态：未读 / 读取中 / 已读 / 已读但稿子后来长了。
// 读稿只在两种时候发生：首次进来还没有档案时自动读一遍，之后全靠作者手动重读。
// 不每次进页面重读——稿子天天在变，重读既花钱又会让同样的参数给出不同的调子。
function CoverBrief({ brief, scan, stats, stale, onRead }) {
  return (
    <section className="m-cs-sec">
      <div className="m-cs-sec__head">
        <Icon name="lightbulb" size={14} color="var(--accent-warm)" />
        <span className="m-cs-sec__title">封面档案</span>
        {brief && !scan && (
          <button className="m-cs-sec__link" type="button" onClick={onRead}>
            重新读一遍
          </button>
        )}
      </div>

      {scan ? (
        <div className="m-cs-brief m-cs-brief--scan">
          <div className="m-cs-progress">
            <div className="m-cs-progress__bar" style={{ width: `${(scan.done / scan.total) * 100}%` }} />
          </div>
          <div className="m-cs-brief__scan">
            正在读第 {scan.done} / {scan.total} 章
          </div>
          <div className="m-cs-brief__note">
            读的是章节摘要与首尾章原文，抽出品类、色温、主角与时代；意象要能指回具体章节才留下。
          </div>
        </div>
      ) : !brief ? (
        <div className="m-cs-brief m-cs-brief--blank">
          <div className="m-cs-brief__note">
            还没读过这部稿子。读一遍才有品类、色温与意象；不读也能出图，只是提示词里少这几行。
          </div>
          <button className="m-btn m-btn--secondary m-btn--sm" type="button" onClick={onRead}>
            <Icon name="book-open" size={14} />
            读一遍全稿
          </button>
        </div>
      ) : (
        <React.Fragment>
          {stale && (
            <div className="m-cs-alert">
              <Icon name="warning" size={13} />
              <span>
                这份档案是按 {brief.chapters} 章 {brief.words} 万字读的，现在已经是 {stats.chapters} 章{" "}
                {stats.words} 万字。后面写的还没算进来。
              </span>
            </div>
          )}
          <div className="m-cs-brief">
            {[
              { k: "品类", v: brief.category },
              { k: "色温", v: brief.temperature },
              { k: "主角", v: brief.figure },
              { k: "时代", v: brief.era },
            ].map((row) => (
              <div key={row.k} className="m-cs-brief__row">
                <span className="m-cs-brief__k">{row.k}</span>
                <span className="m-cs-brief__v">{row.v}</span>
              </div>
            ))}
          </div>
          <ul className="m-cs-notes">
            {brief.motifs.map((m) => (
              <li key={m.text} className="m-cs-notes__item">
                {m.text}
                <span className="m-cs-notes__from">{m.from}</span>
              </li>
            ))}
          </ul>
          <div className="m-cs-brief__foot">
            <Icon name="clock" size={12} />
            {brief.when} 读的 · 当时 {brief.words} 万字 {brief.chapters} 章
          </div>
        </React.Fragment>
      )}
    </section>
  );
}

function CoverAssistant({
  novel,
  cover,
  stats,
  brief,
  briefScan,
  briefStale,
  onReadBrief,
  style,
  onStyle,
  customStyle,
  onCustomStyle,
  palette,
  onPalette,
  composition,
  onComposition,
  titleSpot,
  onTitleSpot,
  titleFont,
  onTitleFont,
  refs,
  refLimit,
  picking,
  onPicking,
  onAddRef,
  onRefRole,
  onRemoveRef,
  extra,
  onExtra,
  prompt,
  promptOpen,
  onPromptOpen,
  busy,
  stopping,
  progress,
  onGenerate,
  onStop,
  onClose,
}) {
  const custom = style === "自定义";
  const canGenerate = !custom || customStyle.trim().length > 0;
  const paletteRef = refs.find((r) => r.role === "palette");

  return (
    <aside className="m-agent m-cs-assistant">
      <div className="m-agent__head">
        <div className="m-agent__head-l">
          <span className="m-agent__head-icon">
            <Icon name="palette" size={16} />
          </span>
          <div className="m-agent__head-meta">
            <div className="m-agent__head-title">封面设计师</div>
            <div className="m-agent__head-sub">
              {briefScan
                ? "正在读全稿…"
                : brief
                ? "读过全稿，按作品的调子给方案"
                : "还没读稿，先按你选的参数出图"}
            </div>
          </div>
        </div>
        <div className="m-agent__head-r">
          <button className="m-icon-btn m-icon-btn--ghost" title="收起" onClick={onClose}>
            <Icon name="x" size={14} />
          </button>
        </div>
      </div>

      <div className="m-cs-assistant__scroll">
        <section className="m-cs-sec">
          <div className="m-cs-sec__head">
            <Icon name="book-open" size={14} color="var(--accent-warm)" />
            <span className="m-cs-sec__title">作品</span>
          </div>
          <div className="m-cs-work">
            <span className="m-cs-work__thumb">
              {cover ? (
                <CoverArt scheme={cover} novel={novel} width={58} />
              ) : (
                <span className="m-cs-work__blank">未设置</span>
              )}
            </span>
            <div className="m-cs-work__meta">
              <div className="m-cs-work__title">{novel.title}</div>
              <div className="m-cs-work__sub">
                {novel.authorName} · {novel.category}
              </div>
              <div className="m-cs-work__tags">
                {novel.tags.map((t) => (
                  <span key={t} className="m-tag">
                    {t}
                  </span>
                ))}
              </div>
              <div className="m-cs-work__stat">
                {stats.words} 万字 · {stats.chapters} 章
              </div>
            </div>
          </div>
        </section>

        <CoverBrief brief={brief} scan={briefScan} stats={stats} stale={briefStale} onRead={onReadBrief} />

        <CoverRefs
          refs={refs}
          limit={refLimit}
          picking={picking}
          onPicking={onPicking}
          onAdd={onAddRef}
          onRole={onRefRole}
          onRemove={onRemoveRef}
        />

        <section className="m-cs-sec">
          <div className="m-cs-sec__head">
            <Icon name="magic-wand" size={14} color="var(--accent-warm)" />
            <span className="m-cs-sec__title">画面风格</span>
          </div>
          <div className="m-cs-chips">
            {CS_STYLES.map((s) => (
              <button
                key={s}
                type="button"
                onClick={() => onStyle(s)}
                className={"m-chip" + (style === s ? " m-chip--brass" : "")}
              >
                {s}
              </button>
            ))}
            <button
              type="button"
              onClick={() => onStyle("自定义")}
              className={"m-chip" + (custom ? " m-chip--brass" : "")}
            >
              <Icon name="pencil-simple" size={12} />
              自定义
            </button>
          </div>
          {custom && (
            <input
              className="m-input"
              value={customStyle}
              onChange={(e) => onCustomStyle(e.target.value)}
              placeholder="用一两个词描述想要的画面，例如：宋人小景"
            />
          )}
        </section>

        <section className="m-cs-sec">
          <div className="m-cs-sec__head">
            <Icon name="drop" size={14} color="var(--accent-warm)" />
            <span className="m-cs-sec__title">色调</span>
          </div>
          {paletteRef && (
            <div className="m-cs-follow">
              <span className="m-cs-follow__chip">
                <span
                  className="m-cs-swatch__chip"
                  style={{ background: `rgb(${paletteRef.rgb})` }}
                />
                跟随参考图
              </span>
              <span className="m-cs-follow__hint">点色卡可覆盖</span>
            </div>
          )}
          <div className={"m-cs-swatches" + (paletteRef ? " is-secondary" : "")}>
            {CS_PALETTES.map((p) => (
              <button
                key={p.id}
                type="button"
                title={p.label}
                onClick={() => onPalette(p.id)}
                className={"m-cs-swatch" + (palette === p.id ? " is-active" : "")}
              >
                <span className="m-cs-swatch__chip" style={{ background: p.swatch }} />
                <span className="m-cs-swatch__label">{p.label}</span>
              </button>
            ))}
          </div>
        </section>

        <section className="m-cs-sec">
          <div className="m-cs-sec__head">
            <Icon name="grid-nine" size={14} color="var(--accent-warm)" />
            <span className="m-cs-sec__title">构图</span>
          </div>
          <div className="m-cs-chips">
            {CS_COMPOSITIONS.map((c) => (
              <button
                key={c}
                type="button"
                onClick={() => onComposition(c)}
                className={"m-chip" + (composition === c ? " m-chip--brass" : "")}
              >
                {c}
              </button>
            ))}
          </div>
        </section>

        <section className="m-cs-sec">
          <div className="m-cs-sec__head">
            <Icon name="text-t" size={14} color="var(--accent-warm)" />
            <span className="m-cs-sec__title">书名</span>
          </div>
          <div className="m-cs-title">
            <span className="m-cs-title__text">{novel.title}</span>
            <span className="m-cs-title__from">取自作品名</span>
          </div>
          <div className="m-cs-field">
            <span className="m-cs-field__label">位置</span>
            <div className="m-cs-chips">
              {CS_TITLE_SPOTS.map((s) => (
                <button
                  key={s.id}
                  type="button"
                  onClick={() => onTitleSpot(s.id)}
                  className={"m-chip" + (titleSpot === s.id ? " m-chip--brass" : "")}
                >
                  {s.label}
                </button>
              ))}
            </div>
          </div>
          <div className="m-cs-field">
            <span className="m-cs-field__label">字形气质</span>
            <div className="m-cs-chips">
              {CS_TITLE_FONTS.map((f) => (
                <button
                  key={f.id}
                  type="button"
                  onClick={() => onTitleFont(f.id)}
                  className={"m-chip" + (titleFont === f.id ? " m-chip--brass" : "")}
                >
                  {f.label}
                </button>
              ))}
            </div>
          </div>
          <div className="m-cs-ref__note">
            书名由模型直接画进画面，与光影材质长在一起。位置、字形、书名本身有任何改动，
            都要重新出图。位置与字形是给模型的倾向，不是保证，以实际出图为准；
            画好后放大看一眼有没有错字、缺笔。
          </div>
        </section>

        <section className="m-cs-sec">
          <div className="m-cs-sec__head">
            <Icon name="note-pencil" size={14} color="var(--accent-warm)" />
            <span className="m-cs-sec__title">补充要求</span>
          </div>
          <textarea
            className="m-input m-cs-extra"
            rows={3}
            value={extra}
            onChange={(e) => onExtra(e.target.value)}
            placeholder="想强调的意象、要避开的元素…"
          />
        </section>

        <section className="m-cs-sec">
          <div className="m-cs-sec__head">
            <Icon name="file-text" size={14} color="var(--accent-warm)" />
            <span className="m-cs-sec__title">提示词</span>
            <button className="m-cs-sec__link" type="button" onClick={() => onPromptOpen(!promptOpen)}>
              {promptOpen ? "收起" : "查看"}
            </button>
          </div>
          {promptOpen && <pre className="m-cs-prompt">{prompt}</pre>}
        </section>
      </div>

      <div className="m-cs-assistant__foot">
        {busy ? (
          <React.Fragment>
            <div className="m-cs-progress">
              <div
                className="m-cs-progress__bar"
                style={{ width: `${(progress.done / progress.total) * 100}%` }}
              />
            </div>
            <button
              className="m-btn m-btn--secondary"
              type="button"
              disabled={stopping}
              onClick={onStop}
              style={{ width: "100%" }}
            >
              <Icon name="stop" size={14} />
              {stopping ? `收尾中（${progress.done}/${progress.total}）` : `停止生成（${progress.done}/${progress.total}）`}
            </button>
            <div className="m-cs-assistant__cost">
              {stopping
                ? "不再发新请求。在途的这张会画完并计费。"
                : "画完一张出一张，停止只停还没发出去的请求。"}
            </div>
          </React.Fragment>
        ) : (
          <React.Fragment>
            <button
              className="m-btn m-btn--primary"
              type="button"
              style={{ width: "100%" }}
              disabled={!canGenerate}
              onClick={onGenerate}
            >
              <Icon name="sparkle" size={16} />
              生成 {CS_COUNT} 个方案
            </button>
            <div className="m-cs-assistant__cost">
              {canGenerate
                ? "每个方案出一张图，停止只停还没发出的请求"
                : "先写一句自定义风格"}
            </div>
          </React.Fragment>
        )}
      </div>
    </aside>
  );
}

// ---- 组合 ---------------------------------------------------------------

function CoverStudioView({ novel, onBack }) {
  const startEmpty = React.useMemo(
    () => new URLSearchParams(window.location.search).get("state") === "empty",
    []
  );

  const [batches, setBatches] = React.useState(startEmpty ? [] : CS_INITIAL_BATCHES);
  const [batchId, setBatchId] = React.useState(startEmpty ? null : CS_INITIAL_BATCHES[0].id);
  const [activeId, setActiveId] = React.useState(
    startEmpty ? null : CS_INITIAL_BATCHES[0].schemes[0].id
  );
  const [appliedId, setAppliedId] = React.useState(
    startEmpty ? null : CS_INITIAL_BATCHES[0].schemes[0].id
  );

  const [ratioId, setRatioId] = React.useState("portrait");
  const [zoom, setZoom] = React.useState(100);
  const [style, setStyle] = React.useState("水墨写意");
  const [customStyle, setCustomStyle] = React.useState("");
  const [palette, setPalette] = React.useState("ink");
  const [composition, setComposition] = React.useState("留白构图");
  const [titleSpot, setTitleSpot] = React.useState("vertical");
  const [titleFont, setTitleFont] = React.useState("kai");
  const [extra, setExtra] = React.useState("");
  const [refs, setRefs] = React.useState([]);
  const [picking, setPicking] = React.useState(false);
  const [promptOpen, setPromptOpen] = React.useState(false);
  const [traceOpen, setTraceOpen] = React.useState(false);
  const [assistantOpen, setAssistantOpen] = React.useState(true);
  const [toast, setToast] = React.useState(null);

  // 封面档案：首次进来没有就自动读一遍，之后只有作者点「重新读一遍」才重读。
  const [brief, setBrief] = React.useState(() =>
    startEmpty ? null : csReadBrief(CS_STATS, "今天 14:20")
  );
  const [briefScan, setBriefScan] = React.useState(null);

  // 调试开关：下一批的生成结果与失败原因。
  const [debugOpen, setDebugOpen] = React.useState(false);
  const [grown, setGrown] = React.useState(false);
  const [failMode, setFailMode] = React.useState("none");
  const [failCode, setFailCode] = React.useState("moderation");
  const [refLimit, setRefLimit] = React.useState(CS_REF_LIMIT);

  // 生成中的那一批：schemes 逐张补齐；stopping 表示已停止发新请求。
  const [pending, setPending] = React.useState(null);
  const [reworkAt, setReworkAt] = React.useState(null);
  const timers = React.useRef([]);
  const seed = React.useRef(CS_INITIAL_BATCHES.length - 1);

  React.useEffect(() => () => timers.current.forEach((t) => clearTimeout(t.id)), []);

  // 读稿与出图是两条独立的耗时任务：停止生成、批次收尾都不该打断正在读的稿。
  const clearTimers = ({ keepBrief = true } = {}) => {
    timers.current = timers.current.filter((t) => {
      if (keepBrief && t.i === -3) return true;
      clearTimeout(t.id);
      return false;
    });
  };

  const stats = grown ? CS_STATS_GROWN : CS_STATS;
  const briefStale = csBriefStale(brief, stats);

  // 读一遍全稿：逐章推进，读完落一份带体量快照的档案。
  // 读稿期间照常可以出图，只是提示词里暂时没有档案那几行。
  function readBrief() {
    if (briefScan) return;
    const total = stats.chapters;
    const ticks = 12;
    setBriefScan({ done: 0, total });
    for (let k = 1; k <= ticks; k += 1) {
      const id = setTimeout(() => {
        if (k < ticks) {
          setBriefScan({ done: Math.round((total * k) / ticks), total });
          return;
        }
        timers.current = timers.current.filter((t) => t.i !== -3);
        setBrief(csReadBrief(stats));
        setBriefScan(null);
        say(`已读完 ${total} 章，封面档案已更新`);
      }, 160 * k);
      timers.current.push({ i: -3, id });
    }
  }

  // 首次进入且还没有档案时自动读一遍，这是唯一不用作者动手的时机。
  React.useEffect(() => {
    if (!brief) readBrief();
  }, []);

  const batch = pending || batches.find((b) => b.id === batchId) || null;
  const slots = pending
    ? pending.schemes.concat(Array(Math.max(0, pending.total - pending.schemes.length)).fill(null))
    : batch
    ? batch.schemes
    : [];

  const index = Math.max(0, slots.findIndex((s) => s && s.id === activeId));
  const scheme = slots[index] || null;
  const cover =
    batches
      .concat(pending ? [pending] : [])
      .flatMap((b) => b.schemes)
      .find((s) => s.id === appliedId) || null;

  const busy = !!pending || reworkAt !== null;
  const say = (message) => setToast({ id: Date.now(), message });

  const activeRefs = React.useMemo(() => csSplitRefs(refs, refLimit).sent, [refs, refLimit]);
  const resolvedStyle = style === "自定义" ? customStyle.trim() || "自定义" : style;
  const prompt = csBuildPrompt({
    novel,
    style: resolvedStyle,
    palette,
    composition,
    extra,
    refs: activeRefs,
    titleSpot,
    titleFont,
    ratioId,
    brief,
  });

  function finalize(p, { stopped } = {}) {
    const ok = p.schemes.filter((s) => s.status === "ok").length;
    const bad = p.schemes.filter((s) => s.status === "failed").length;
    let status = "completed";
    if (ok === 0) status = stopped ? "canceled" : "failed";
    else if (stopped || bad > 0) status = "partial";
    const done = {
      ...p,
      status,
      note: p.note + (stopped ? " · 中途停止" : bad > 0 ? ` · ${bad} 张失败` : ""),
    };
    setBatches((list) => [done, ...list]);
    setBatchId(done.id);
    setPending(null);
    clearTimers();
    if (status === "completed") say(`已生成 ${ok} 张`);
    else if (status === "canceled") say("已停止，这一批没有留下产物");
    else if (status === "failed") say(`本批全部失败：${CS_ERRORS[failCode].title}`);
    else say(`批次部分完成，保留 ${ok} 张`);
  }

  // 生成一批：逐张返回，出一张扣一张，不预扣。
  function generate({ label, refsOverride, from } = {}) {
    if (busy) return;
    const useRefs = csSplitRefs(refsOverride || refs, refLimit);
    const src = from || {
      style: resolvedStyle,
      palette,
      composition,
      titleSpot,
      titleFont,
      extra,
      brief,
      refs: useRefs.sent,
      dropped: useRefs.dropped,
    };
    const nextSeed = (seed.current += 1);
    const built = csBuildBatch({
      ...src,
      ratioId,
      seed: nextSeed,
      when: csClock(),
      label,
      fail: failMode === "none" ? null : { mode: failMode, code: failCode },
      prompt: from
        ? csBuildPrompt({ novel, ...from, ratioId })
        : csBuildPrompt({ novel, ...src, refs: useRefs.sent, ratioId }),
    });

    setActiveId(null);
    setPending({ ...built, schemes: [], total: built.schemes.length, stopping: false });

    built.schemes.forEach((s, i) => {
      const id = setTimeout(() => {
        timers.current = timers.current.filter((t) => t.i !== i);
        setPending((p) => {
          if (!p) return p;
          const next = { ...p, schemes: [...p.schemes, s] };
          if (p.schemes.length === 0) setActiveId(s.id);
          const last = i === built.schemes.length - 1;
          if (last || p.stopping) {
            const t2 = setTimeout(() => finalize(next, { stopped: !!p.stopping }), 420);
            timers.current.push({ i: -1, id: t2 });
          }
          return next;
        });
      }, 760 * (i + 1));
      timers.current.push({ i, id });
    });
  }

  // 停止：只清掉还没发出的请求，最早那个在途的留着让它画完。
  function stopGenerate() {
    setPending((p) => {
      if (!p || p.stopping) return p;
      const inFlight = p.schemes.length;
      timers.current = timers.current.filter((t) => {
        if (t.i === inFlight || t.i === -1 || t.i === -3) return true;
        clearTimeout(t.id);
        return false;
      });
      say(`已停止发起新请求，第 ${inFlight + 1} 张仍在生成`);
      return { ...p, status: "stopping", stopping: true, total: inFlight + 1 };
    });
  }

  // 单张重出：沿用同批参数与参考图，只重跑这一张，按单张计费。
  function rework() {
    if (!scheme || busy || !batch || pending) return;
    const at = index;
    const target = batch;
    const old = scheme;
    setReworkAt(at);
    const nextSeed = (seed.current += 1);
    const id = setTimeout(() => {
      const fresh = csBuildScheme({
        style: target.style,
        palette: target.palette,
        composition: target.composition,
        titleSpot: target.titleSpot,
        refs: target.refs,
        seed: nextSeed,
        i: at,
      });
      const replacement = {
        ...fresh,
        slot: at,
        rework: true,
        previous: old.status === "failed" ? { name: `方案 ${at + 1}`, image: null } : old,
      };
      setBatches((list) =>
        list.map((b) =>
          b.id !== target.id
            ? b
            : {
                ...b,
                status: b.status === "failed" ? "partial" : b.status,
                schemes: b.schemes.map((s, i) => (i === at ? replacement : s)),
              }
        )
      );
      setActiveId(replacement.id);
      setReworkAt(null);
      say(`第 ${at + 1} 张已重出`);
    }, 900);
    timers.current.push({ i: -2, id });
  }

  // 以当前这张为底图再来一批：进图片库的「以此为参考图新建生成」同一条路。
  function seedFrom() {
    if (!scheme || busy) return;
    if (!scheme.image) {
      say("素纸方案没有画面，换一张再试");
      return;
    }
    const ref = {
      id: `ref-${scheme.id}`,
      src: scheme.image,
      name: scheme.name,
      rgb: scheme.rgb,
      role: "base",
    };
    const next = [ref, ...refs.filter((r) => r.src !== scheme.image)];
    setRefs(next);
    generate({ label: "以图生图", refsOverride: next });
  }

  function reuseBatch(id) {
    const b = batches.find((x) => x.id === id);
    if (!b || busy) return;
    generate({
      label: "重跑",
      from: {
        style: b.style,
        palette: b.palette,
        composition: b.composition,
        titleSpot: b.titleSpot,
        titleFont: b.titleFont,
        extra: b.extra,
        brief: b.brief,
        refs: b.refs,
        dropped: b.dropped,
      },
    });
  }

  function applyCover() {
    if (!scheme) return;
    setAppliedId(scheme.id);
    say(`已把「${scheme.name}」设为《${novel.title}》的封面`);
  }

  return (
    <React.Fragment>
      <CoverRail
        novel={novel}
        batches={batches}
        batch={batch}
        busy={busy}
        onSelectBatch={(id) => {
          if (busy) return;
          const b = batches.find((x) => x.id === id);
          if (!b) return;
          setBatchId(id);
          setActiveId(b.schemes[0].id);
        }}
        onReuse={reuseBatch}
        onBack={onBack}
      />
      <CoverCanvas
        novel={novel}
        scheme={scheme}
        index={index}
        batch={batch}
        slots={slots}
        activeId={activeId}
        appliedId={appliedId}
        reworkAt={reworkAt}
        onSelectScheme={setActiveId}
        ratioId={ratioId}
        onRatio={setRatioId}
        zoom={zoom}
        onZoom={setZoom}
        applied={!!scheme && scheme.id === appliedId}
        busy={busy}
        progress={{ done: pending ? pending.schemes.length : 0, total: pending ? pending.total : CS_COUNT }}
        stopping={!!(pending && pending.stopping)}
        traceOpen={traceOpen}
        onTrace={() => setTraceOpen((v) => !v)}
        onApply={applyCover}
        onRework={rework}
        onSeedFrom={seedFrom}
        onGenerate={() => generate()}
        debug={{
          open: debugOpen,
          onOpen: setDebugOpen,
          fail: failMode,
          onFail: setFailMode,
          error: failCode,
          onError: setFailCode,
          limit: refLimit,
          onLimit: setRefLimit,
          grown,
          onGrown: setGrown,
          onClear: () => {
            clearTimers({ keepBrief: false });
            setPending(null);
            setBatches([]);
            setBatchId(null);
            setActiveId(null);
            setAppliedId(null);
            setBrief(null);
            setBriefScan(null);
            setGrown(false);
            setDebugOpen(false);
          },
        }}
      />
      {assistantOpen ? (
        <CoverAssistant
          novel={novel}
          cover={cover}
          stats={stats}
          brief={brief}
          briefScan={briefScan}
          briefStale={briefStale}
          onReadBrief={readBrief}
          style={style}
          onStyle={setStyle}
          customStyle={customStyle}
          onCustomStyle={setCustomStyle}
          palette={palette}
          onPalette={setPalette}
          composition={composition}
          onComposition={setComposition}
          titleSpot={titleSpot}
          onTitleSpot={setTitleSpot}
          titleFont={titleFont}
          onTitleFont={setTitleFont}
          refs={refs}
          refLimit={refLimit}
          picking={picking}
          onPicking={setPicking}
          onAddRef={(item) => {
            setRefs((list) =>
              list.some((r) => r.src === item.src)
                ? list
                : [...list, { ...item, id: `${item.id}-${list.length}`, role: "style" }]
            );
            setPicking(false);
          }}
          onRefRole={(id, role) =>
            setRefs((list) => list.map((r) => (r.id === id ? { ...r, role } : r)))
          }
          onRemoveRef={(id) => setRefs((list) => list.filter((r) => r.id !== id))}
          extra={extra}
          onExtra={setExtra}
          prompt={prompt}
          promptOpen={promptOpen}
          onPromptOpen={setPromptOpen}
          busy={!!pending}
          stopping={!!(pending && pending.stopping)}
          progress={{ done: pending ? pending.schemes.length : 0, total: pending ? pending.total : CS_COUNT }}
          onGenerate={() => generate()}
          onStop={stopGenerate}
          onClose={() => setAssistantOpen(false)}
        />
      ) : (
        <button
          className="m-chat-fab"
          type="button"
          onClick={() => setAssistantOpen(true)}
          title="打开封面设计师"
        >
          <Icon name="palette" size={18} />
        </button>
      )}
      {toast && (
        <div key={toast.id} className="m-cs-toast" onAnimationEnd={() => setToast(null)}>
          {toast.message}。
        </div>
      )}
    </React.Fragment>
  );
}

Object.assign(window, { CoverStudioView, CoverArt });
