// data.jsx — 制作画布(每集一张)的 mock 数据。片段模型(2026-10-08):
//   · 片段 = 一次生成,时长按所选模型的能力由作者 / AI 设定;一段可以含多个镜头,镜头写在提示词里:
//     「Shot N(景别·角度·运镜·时长)」+【段内区间】+ 首帧 + [时间码] 节拍 + 结束状态,时间码由作者 / AI 手写
//   · 画布上的视频节点只有一种:带场次 + 场内顺序的是「片段节点」,进成片;不带的是「视频节点」,自由试验
//   · 片段只关联到场,不锚定剧本台词;成片顺序 = 场次顺序 + 场内 sort,和画布位置无关
//   · 视频节点可以替换某个片段 = 两个节点交换片段身份(场次、场内顺序),内容和历史都跟着节点走;
//     新片段的状态按它自己的采用结果定(有则已完成,无则待制作)
//   · 图片节点:生成或上传一张图,结果登记为图片资产,可以连给视频节点当参考图 / 首尾帧
//   · 剧本有一份比例 / 清晰度设置:新建视频 / 片段节点的默认规格,也是整集成片的画幅
//   · 剧集有一个全局风格;视频 / 图片节点默认跟随,也可以单独设置;上传的文件直接成为节点的采用结果;
//     上传一律先按内容去重保存进资产库,节点只引用资产 id
//   · 素材节点只引用统一资产(Assets):图片 / 视频 / 音频;导演输出也是普通资产,带工程与版本来源
//   · 生成输入 = 画布上的输入连线:来源是素材节点(固定 asset_id)或另一个视频 / 片段节点
//     (跟随它当前采用的结果,提交时解析成具体资产写进任务快照);同一节点里一个来源只承担一个用途;不允许成环
//   · 每次生成一个结果,重做明确发起;成功结果自动采用(片段同时标为已完成),历次任务与结果保留在节点上,
//     作者可以切回任意一次历史结果
// 资产与模型共享 screenplay/data.jsx(SP_ASSETS / SP_VIDEO_MODELS);片段与任务只在本页。全局名统一 DR_ / dr 前缀。
// 关联文件: drama/app.jsx, drama/board.jsx, drama/composer.jsx, screenplay/data.jsx

/* ===================== 本集 ===================== */

const DR_PROJECT = SP_PROJECTS.find((p) => p.id === "sp1");
const DR_EPISODE = SP_EPISODES.find((e) => e.id === "ep1");
const DR_SCENES = SP_SCENES.filter((s) => s.ep === "ep1").sort((a, b) => a.no - b.no);

// 片段制作状态:完成只由作者确认,任务成功不自动改。
const DR_SEG_STATUS = {
  todo:  { label: "待制作" },
  doing: { label: "制作中" },
  done:  { label: "已完成" },
};

/* ===================== 输入用途 ===================== */
// 可选用途由生成方式 + 模型能力决定;首尾帧模式不与普通参考混用。
const DR_ROLES = {
  ref_image: { label: "参考图",   accepts: "image", mode: "ref",    slot: "图片" },
  ref_video: { label: "参考视频", accepts: "video", mode: "ref",    slot: "视频" },
  ref_audio: { label: "参考音频", accepts: "audio", mode: "ref",    slot: "音频" },
  first:     { label: "首帧",     accepts: "image", mode: "frames", slot: "首帧" },
  last:      { label: "尾帧",     accepts: "image", mode: "frames", slot: "尾帧" },
};
const DR_ASSET_TYPES = {
  image:    { label: "图片",     icon: "image" },
  video:    { label: "视频",     icon: "film-strip" },
  audio:    { label: "音频",     icon: "waveform" },
  director: { label: "导演工程", icon: "cube" },
  style:    { label: "风格",     icon: "palette" },
  text:     { label: "文本",     icon: "file-text" },
};

/* ===================== 预设运镜 ===================== */
const DR_CAMERA_MOVES = [
  { id: "static", label: "固定" },
  { id: "push",   label: "推" },
  { id: "pull",   label: "拉" },
  { id: "pan",    label: "横摇" },
  { id: "tilt",   label: "竖摇" },
  { id: "track",  label: "跟随" },
  { id: "crane",  label: "升降" },
  { id: "orbit",  label: "环绕" },
];

/* ===================== 导演台运镜预设 ===================== */
// 导演台的运镜比视频节点细,但每一项都归到 DR_CAMERA_MOVES 的一类(base):
// 用某个预设录制预演后,视频节点提示词里的〔运镜〕标记就取 base,两边不会出现两套叫法。
const DR_DIR_MOVE_GROUPS = [
  { id: "basic",  label: "基础" },
  { id: "follow", label: "人物跟拍" },
  { id: "space",  label: "空间" },
];
const DR_DIR_MOVES = [
  { id: "static",     group: "basic",  base: "static", label: "固定",     desc: "机位与朝向不变" },
  { id: "pan_l",      group: "basic",  base: "pan",    label: "左摇",     desc: "机位不动，向左转" },
  { id: "pan_r",      group: "basic",  base: "pan",    label: "右摇",     desc: "机位不动，向右转" },
  { id: "tilt_u",     group: "basic",  base: "tilt",   label: "上摇",     desc: "机位不动，向上转" },
  { id: "tilt_d",     group: "basic",  base: "tilt",   label: "下摇",     desc: "机位不动，向下转" },
  { id: "dolly_in",   group: "basic",  base: "push",   label: "前推",     desc: "沿镜头方向推近" },
  { id: "dolly_out",  group: "basic",  base: "pull",   label: "后拉",     desc: "沿镜头方向拉远" },
  { id: "zoom_in",    group: "basic",  base: "push",   label: "变焦推",   desc: "机位不动，画面收紧" },
  { id: "follow_pan", group: "follow", base: "pan",    label: "跟摇",     desc: "机位不动，朝向跟住注视目标" },
  { id: "follow",     group: "follow", base: "track",  label: "跟拍",     desc: "随主体移动，保持构图" },
  { id: "lead",       group: "follow", base: "track",  label: "迎面后退", desc: "在主体前方同步后退" },
  { id: "orbit",      group: "follow", base: "orbit",  label: "环绕",     desc: "绕主体转 90°–360°" },
  { id: "crane_up",   group: "space",  base: "crane",  label: "升",       desc: "垂直升起，保持朝向" },
  { id: "crane_down", group: "space",  base: "crane",  label: "降",       desc: "垂直下降，保持朝向" },
  { id: "rise_out",   group: "space",  base: "crane",  label: "拉升离场", desc: "向后并向上离开主体" },
];

/* ===================== 导演台动作库 ===================== */
const DR_ACTION_GROUPS = [
  { id: "daily", label: "日常" },
  { id: "move",  label: "行走" },
  { id: "mood",  label: "情绪" },
  { id: "talk",  label: "对话" },
];
const DR_ACTIONS = [
  { id: "stand",     group: "daily", label: "站立" },
  { id: "sit",       group: "daily", label: "坐" },
  { id: "sit_write", group: "daily", label: "坐 · 写字" },
  { id: "stand_up",  group: "daily", label: "起身" },
  { id: "sit_down",  group: "daily", label: "坐下" },
  { id: "pass",      group: "daily", label: "递物" },
  { id: "walk_slow", group: "move",  label: "缓步走", moving: true },
  { id: "walk_fast", group: "move",  label: "快走",   moving: true },
  { id: "turn",      group: "move",  label: "转身" },
  { id: "stop",      group: "move",  label: "驻足" },
  { id: "look_up",   group: "mood",  label: "仰望" },
  { id: "look_down", group: "mood",  label: "低头" },
  { id: "look_back", group: "mood",  label: "回头" },
  { id: "sigh",      group: "mood",  label: "叹气" },
  { id: "gesture",   group: "talk",  label: "说话手势" },
  { id: "listen",    group: "talk",  label: "倾听点头" },
];

/* ===================== 运镜库(生成输入框) =====================
   运镜模板属于统一资产里的「动作 / 运镜 / 风格」模板。套用 = 把 text 作为可见编辑写进提示词,
   不另存运镜字段,生成时也不暗中叠加。base 复用 DR_CAMERA_MOVES 的分类图形。 */
const DR_CAM_GROUPS = [
  { id: "basic",   label: "基础控制" },
  { id: "follow",  label: "人物跟拍" },
  { id: "reveal",  label: "揭示转场" },
  { id: "emotion", label: "情绪强化" },
  { id: "aerial",  label: "空间航拍" },
];
const DR_CAM_TEMPLATES = [
  { id: "ct_static",  group: "basic",   base: "static", label: "固定镜头", desc: "建立冷静秩序", text: "固定机位，画面构图全程不变。" },
  { id: "ct_tilt_u",  group: "basic",   base: "tilt",   label: "镜头上摇", desc: "展示高度威压", text: "镜头由下向上缓慢摇起。" },
  { id: "ct_tilt_d",  group: "basic",   base: "tilt",   label: "镜头下摇", desc: "从环境落到人", text: "镜头由环境缓慢下摇，落到人物身上。" },
  { id: "ct_pan_l",   group: "basic",   base: "pan",    label: "镜头左摇", desc: "横向展示空间", text: "机位不动，镜头缓慢向左横摇。" },
  { id: "ct_pan_r",   group: "basic",   base: "pan",    label: "镜头右摇", desc: "引出画外信息", text: "机位不动，镜头缓慢向右横摇，引出画外。" },
  { id: "ct_push",    group: "basic",   base: "push",   label: "镜头前推", desc: "强调情绪靠近", text: "镜头缓慢向前推进。" },
  { id: "ct_pull",    group: "basic",   base: "pull",   label: "镜头后拉", desc: "展示人物孤独", text: "镜头缓慢后拉，人物在画面中变小。" },
  { id: "ct_zoom",    group: "basic",   base: "push",   label: "变焦推进", desc: "突出表情反应", text: "机位不动，镜头变焦推近到人物面部。" },
  { id: "ct_follow",  group: "follow",  base: "track",  label: "跟拍",     desc: "随人物移动",   text: "镜头跟随人物移动，保持人物在画面同一位置。" },
  { id: "ct_lead",    group: "follow",  base: "track",  label: "迎面后退", desc: "人物走向镜头", text: "镜头在人物前方同步后退，人物迎面走来。" },
  { id: "ct_orbit",   group: "follow",  base: "orbit",  label: "环绕",     desc: "围绕主体一周", text: "镜头围绕人物缓慢环绕半周。" },
  { id: "ct_over",    group: "follow",  base: "static", label: "过肩",     desc: "对话关系",     text: "过肩镜头，前景是一方肩部，焦点在对面人物。" },
  { id: "ct_door",    group: "reveal",  base: "pan",    label: "门帘揭示", desc: "从遮挡进入",   text: "起幅在遮挡物外，镜头缓慢移入，揭示后方空间。" },
  { id: "ct_rack",    group: "reveal",  base: "static", label: "焦点转移", desc: "前景转到后景", text: "焦点从前景缓慢转移到后景人物。" },
  { id: "ct_slow",    group: "emotion", base: "push",   label: "极慢推进", desc: "压迫感",       text: "镜头以几乎察觉不到的速度持续推进。" },
  { id: "ct_hand",    group: "emotion", base: "track",  label: "手持晃动", desc: "紧张不安",     text: "手持拍摄，画面轻微晃动。" },
  { id: "ct_rise",    group: "aerial",  base: "crane",  label: "拉升离场", desc: "交代全景",     text: "镜头向后并向上缓慢升起，离开人物，露出全景。" },
  { id: "ct_crane_d", group: "aerial",  base: "crane",  label: "俯冲下降", desc: "从全局聚焦",   text: "镜头从高处缓慢下降，聚焦到画面中心人物。" },
];

/* ===================== 画布节点 ===================== */
// kind:
//   asset     素材节点,只引用一条资产(assetId)
//   director  场次导演工程(登记在资产库,真源仍是 ScreenplayStagings)。不是可上传媒体,没有输出端口
//   video     视频节点:提示词 / 生成配置 / 采用结果都存在节点上。
//             带 sceneId + sort 的是片段节点(status 是它的制作状态);不带的是自由试验的视频节点
//             ai:AI 写入后还没审阅("new" 新增 / "edit" 修改),片段列表里逐段接受或回退
// 场次色带只是自动布局的整理,可以拖散,不是容器;片段属于哪一场看 sceneId,不看落在哪条色带里。
const DR_BANDS = [
  { sceneId: "s1", x: -40, y: -70, w: 1240, h: 330 },
  { sceneId: "s2", x: -40, y: 300, w: 1840, h: 640 },
];

// 提示词里引用另一个视频节点:身份是节点 id,label 只用来显示。
function drNodeRef(id, label) {
  return `<user-remind type='nodes' path='nodes/${id}' label='${label}'></user-remind>`;
}

/* ===================== 风格 ===================== */
// 剧集存一个全局风格;视频 / 图片节点的 style 为空表示跟随剧集,"none" 表示这个节点不用风格,
// { custom } 是自定义风格提示词。风格提示词在提交时追加到实际发送文本末尾,提交预览里可见。
// 预览图没有真实素材,用渐变 + 剪影代画(art 是 CSS 背景)。
const DR_STYLE_CATS = [
  { id: "all",  label: "全部" },
  { id: "real", label: "真人" },
  { id: "2d",   label: "2D" },
  { id: "3d",   label: "3D" },
];
const DR_STYLES = [
  { id: "st_guzhuang", cat: "real", name: "精品古装偶像剧", figs: 2,
    art: "linear-gradient(160deg, #e9e4dc 0%, #b9b3ab 45%, #4b5a52 100%)",
    prompt: "精品古装偶像剧质感，柔光，高饱和但干净的服化，浅景深，人物肤质细腻。" },
  { id: "st_zhiguai", cat: "real", name: "中式志怪电影感", figs: 1,
    art: "linear-gradient(170deg, #7d8ea3 0%, #3b4757 55%, #1d232c 100%)",
    prompt: "中式志怪电影感，冷调雾气，低照度，强烈明暗对比，胶片颗粒。" },
  { id: "st_rouguang", cat: "real", name: "古偶柔光滤镜风", figs: 1,
    art: "radial-gradient(circle at 70% 30%, #fff1d6 0%, #e7b9a7 35%, #6d4a4a 100%)",
    prompt: "古偶柔光滤镜，暖色高光溢出，背景光斑，梦幻氛围。" },
  { id: "st_hist", cat: "real", name: "写实历史剧", figs: 2,
    art: "linear-gradient(165deg, #d79b55 0%, #7a4b26 50%, #241812 100%)",
    prompt: "写实历史剧质感，胶片颗粒，低饱和暖光，画面内不出现任何现代物件。" },
  { id: "st_campus", cat: "real", name: "日系校园清新", figs: 2,
    art: "linear-gradient(170deg, #dfeaf3 0%, #9fb7c9 50%, #2f3d4c 100%)",
    prompt: "日系校园清新，自然光，低对比，偏青的阴影，青春感。" },
  { id: "st_suspense", cat: "real", name: "都市悬疑冷调", figs: 1,
    art: "linear-gradient(160deg, #5b6b74 0%, #23313a 60%, #0c1216 100%)",
    prompt: "都市悬疑冷调，青蓝色调，硬光，压抑构图。" },
  { id: "st_cg", cat: "2d", name: "半写实精致 CG 渲染", figs: 1,
    art: "linear-gradient(150deg, #f2b7c6 0%, #a24d6b 50%, #2d1420 100%)",
    prompt: "半写实精致 CG 渲染，皮肤通透，细节锐利，戏剧化轮廓光。" },
  { id: "st_guoman2d", cat: "2d", name: "国风水墨动画", figs: 1,
    art: "linear-gradient(175deg, #efe9dd 0%, #c4baa6 55%, #5a5246 100%)",
    prompt: "国风水墨动画，宣纸纹理，留白构图，墨色晕染。" },
  { id: "st_anime", cat: "2d", name: "日式赛璐璐动画", figs: 2,
    art: "linear-gradient(160deg, #9fd3f5 0%, #5a8fd6 50%, #263a6b 100%)",
    prompt: "日式赛璐璐动画，平涂上色，清晰描线，高饱和天空。" },
  { id: "st_pixar", cat: "3d", name: "皮克斯3D卡通渲染", figs: 1,
    art: "linear-gradient(150deg, #c9a4f2 0%, #8a5fd1 45%, #f3b35c 100%)",
    prompt: "皮克斯风 3D 卡通渲染，圆润造型，柔和全局光照，夸张表情。" },
  { id: "st_guoman3d", cat: "3d", name: "国漫3D高清渲染风", figs: 1,
    art: "linear-gradient(160deg, #e6b46a 0%, #8b5a2b 50%, #2a1a10 100%)",
    prompt: "国漫 3D 高清渲染，华丽服饰材质，体积光，粒子特效。" },
  { id: "st_clay", cat: "3d", name: "黏土定格动画", figs: 2,
    art: "linear-gradient(165deg, #f1cfa3 0%, #c98a5a 55%, #5c3820 100%)",
    prompt: "黏土定格动画质感，手捏痕迹，微缩布景，略带抽帧。" },
];
function drStyle(id) {
  return DR_STYLES.find((x) => x.id === id) || null;
}
// 节点实际使用的风格:{ value, inherited, name, prompt, art }。value 为 null 表示无风格。
function drStyleOf(node, epStyle) {
  const raw = node && node.style !== undefined ? node.style : epStyle;
  const inherited = !node || node.style === undefined;
  if (!raw || raw === "none") return { value: null, inherited, name: "无风格", prompt: "" };
  if (raw.custom !== undefined) return { value: raw, inherited, name: "自定义风格", prompt: raw.custom, custom: true };
  const st = drStyle(raw);
  return { value: raw, inherited, name: st.name, prompt: st.prompt, art: st.art, figs: st.figs };
}

/* ===================== 图片模型 ===================== */
// 图片节点只走参考生成:输入只有参考图;每次生成一张,按张计费。
const DR_IMAGE_MODELS = [
  { id: "seedream4", name: "Seedream 4.0", channel: "我的火山方舟", adapter: "ark_image", image: true,
    modes: ["ref"], ratios: ["16:9", "21:9", "9:16", "4:3", "3:4", "1:1"], res: ["2K", "4K"],
    maxImages: 6, maxVideos: 0, maxAudios: 0, pricePerImage: 0.2 },
  { id: "qwenimg", name: "Qwen Image", channel: "阿里云百炼", adapter: "qwen_image", image: true,
    modes: ["ref"], ratios: ["16:9", "9:16", "4:3", "3:4", "1:1"], res: ["1K", "2K"],
    maxImages: 3, maxVideos: 0, maxAudios: 0, pricePerImage: 0.15 },
];
const DR_IMAGE_GEN = { model: "seedream4", mode: "ref", ratio: "16:9", res: "4K" };
// 比例图标的外框(宽, 高),弹层里画成小矩形。
const DR_RATIO_BOX = { "16:9": [22, 13], "21:9": [24, 10], "9:16": [13, 22], "4:3": [20, 15], "3:4": [15, 20], "1:1": [17, 17] };

// 图片节点的生成结果 / 上传文件登记成图片资产(只在本页,追加进共享资产表)。
SP_ASSETS.push(
  { id: "r_img_cabin_1", type: "image", name: "前舱 · 夜 · 宽景 · 结果 1", tone: "lamp", source: "生成 · Seedream 4.0", spec: "3840×2160" },
  { id: "r_img_cabin_2", type: "image", name: "前舱 · 夜 · 宽景 · 结果 2", tone: "umber", source: "生成 · Seedream 4.0", spec: "3840×2160" },
  { id: "u_img_ahui", type: "image", name: "阿茴 · 定妆照.jpg", char: "阿茴", tone: "rose", source: "上传", spec: "1080×1440" },
);

/* ===================== 剧本制作设置 ===================== */
// 剧本级(整部剧共用)的比例 / 清晰度,对应 Flutter ProductionSettings。新建的视频 / 片段节点以它为默认值
// (夹到所选模型支持的范围内),整集成片按它的比例导出;改它不回写已有节点,节点上的规格仍可单独改。
const DR_SPEC_RATIOS = ["21:9", "16:9", "4:3", "1:1", "3:4", "9:16"];
const DR_SPEC_RES = ["480P", "720P", "1080P", "2160P"];
const DR_SPEC = { ratio: "9:16", res: "720P" };
// 剧本设置 → 某个模型能用的比例 / 清晰度:模型不支持就退到它的第一个比例、最高清晰度。
function drFitSpec(model, spec) {
  return {
    ratio: model.ratios.includes(spec.ratio) ? spec.ratio : model.ratios[0],
    res: model.res.includes(spec.res) ? spec.res : model.res[model.res.length - 1],
  };
}

const DR_GEN = { model: "seedance25", mode: "ref", ...DR_SPEC };

const DR_NODES = [
  /* ---- 第 1 场 嘉兴码头 ---- */
  { id: "n_dock",   kind: "asset", assetId: "a_dock",   x: 0,   y: 0,   w: 220, h: 84 },
  { id: "n_shen_a", kind: "asset", assetId: "a_shen",   x: 0,   y: 96,  w: 220, h: 84 },
  { id: "n_haozi",  kind: "asset", assetId: "a_haozi",  x: 250, y: 150, w: 200, h: 64 },
  { id: "v_s1_1", kind: "video", sceneId: "s1", sort: 1, status: "done", x: 520, y: -20, w: 300, h: 196,
    title: "码头全貌", ms: 15000, adopted: "r_11_3", gen: DR_GEN,
    prompt:
      "Shot 1（远景·平视·固定机位·6s）\n【0-6s】\n" +
      "首帧：黄昏的江南码头远景，逆光，天色橙灰，江面泛冷光。场景参考 " + spRef("a_dock") + "，木跳板与缆绳横在前景，挑夫在中景来回穿行。\n" +
      "[0-6s] 挑夫扛货从左往右穿过画面，跳板随脚步轻微起伏，江面波光缓慢移动。\n" +
      "结束状态：远景不变，画面右侧人流让出一个空隙。\n\n" +
      "Shot 2（中景·平视·手持轻跟·5s）\n【6-11s】\n" +
      "首帧：中景，" + spRef("a_shen") + " 抱着旧木画箱从画面右侧的空隙走入，青衫下摆沾着水渍。\n" +
      "[6-9s] 逆人流向左缓步前行，肩膀被挑夫擦过，身体侧让一下，全程不与人对视。\n" +
      "[9-11s] 停步半拍，抬眼看向画外左侧的客船。\n" +
      "结束状态：中景，人物侧脸朝左，画箱抱在胸前。\n\n" +
      "Shot 3（全景·平视·固定机位·4s）\n【11-15s】\n" +
      "首帧：全景，客船停在画面左侧，人物在右侧前景走向船。\n" +
      "[11-15s] 人物向左走出画面，落幅停在客船船身上，船灯刚刚点亮。\n" +
      "结束状态：空镜，客船船身与船灯。\n\n" +
      "整体：写实历史剧质感，胶片颗粒，浅景深，画面内不出现任何现代物件。" },
  // 提示词可以先空着 —— 片段先占位，想清楚再写。
  { id: "v_s1_2", kind: "video", sceneId: "s1", sort: 2, status: "todo", x: 860, y: -20, w: 300, h: 196,
    title: "还价", ms: null, adopted: null, gen: { ...DR_GEN, mode: "text" }, prompt: "" },

  /* ---- 第 2 场 客船前舱 ---- */
  { id: "n_shen_b", kind: "asset", assetId: "a_shen",   x: 0,   y: 350, w: 220, h: 84 },
  { id: "n_zhou",   kind: "asset", assetId: "a_zhou",   x: 0,   y: 446, w: 220, h: 84 },
  { id: "n_ahui",   kind: "asset", assetId: "a_ahui",   x: 0,   y: 542, w: 220, h: 84 },
  { id: "n_cabin",  kind: "asset", assetId: "a_cabin",  x: 0,   y: 638, w: 220, h: 84 },
  { id: "n_candle", kind: "asset", assetId: "a_candle", x: 0,   y: 790, w: 220, h: 84 },

  { id: "n_dir_cabin", kind: "director", assetId: "a_stage_cabin", sceneId: "s2", x: 290, y: 350, w: 220, h: 112 },
  { id: "n_pv_face", kind: "asset", assetId: "a_pv_face", x: 290, y: 490, w: 220, h: 84 },
  { id: "n_pv_pan",  kind: "asset", assetId: "a_pv_pan2", x: 290, y: 600, w: 220, h: 84 },

  { id: "v_s2_1", kind: "video", sceneId: "s2", sort: 1, status: "doing", ai: "edit", x: 620, y: 330, w: 300, h: 196,
    title: "对坐 · 旧墨", ms: 12000, adopted: "r_21_s", gen: DR_GEN,
    prompt:
      "Shot 1（中景·平视·固定机位·4s）\n【0-4s】\n" +
      "首帧：夜间船舱内景，一盏油灯，暖光偏低。按 " + spRef("a_pv_face") + " 的构图：" +
      "左侧 " + spRef("a_zhou") + " 手中盘着念珠，右侧 " + spRef("a_shen") + " 半张脸落在灯影之外。\n" +
      "[0-2.5s] 念珠一颗一颗拨过，灯焰轻晃。\n" +
      "[2.5-4s] 周慎拨珠的手停住。\n" +
      "结束状态：两人对坐，构图不变。\n\n" +
      "Shot 2（近景·微仰·固定机位·4s）\n【4-8s】\n" +
      "首帧：周慎近景，灯光从下方照亮半张脸。\n" +
      "[4-5s] 抬眼看向画面右侧。\n" +
      "[5-7.5s] 低声、语速慢：「先生这手，是拿笔的手。」\n" +
      "[7.5-8s] 说完嘴唇合拢，视线不移。\n" +
      "结束状态：近景，周慎直视画面右侧。\n\n" +
      "Shot 3（特写·俯拍·固定机位·4s）\n【8-12s】\n" +
      "首帧：手部特写，右侧男子的手停在深色木案上，虎口有一道洗不掉的旧墨痕。浅景深，背景虚化。\n" +
      "[8-10s] 手指微微收拢。\n" +
      "[10-12s] 手缓缓收进袖中，案上只剩灯影。\n" +
      "结束状态：空木案特写。" },
  { id: "v_s2_2", kind: "video", sceneId: "s2", sort: 2, status: "done", x: 980, y: 330, w: 300, h: 196,
    title: "摇进前舱", ms: 11000, adopted: "r_22_s", gen: DR_GEN,
    // 出样片之后又改过提示词:成片仍按样片当时的内容生成。
    editedSinceSample: true,
    prompt:
      "Shot 1（全景·平视·横摇长镜·11s）\n【0-11s】\n" +
      "首帧：门帘外，帘缝透出暖光。机位运动与人物走位参考 " + spRef("a_pv_pan2") + "。\n" +
      "[0-4s] 镜头缓慢摇入 " + spRef("a_cabin") + "，舱内六人分坐两侧，人一动墙上影子就晃。\n" +
      "[4-8s] " + spRef("a_ahui") + " 起身，穿过画面走向舱梁。\n" +
      "[8-11s] 阿茴抬头，镜头跟着落到舱梁上悬着的油灯。摇速平稳，不加变速。\n" +
      "结束状态：油灯居中，阿茴在画面下沿。" },
  // 引用了 @短烛，但画布上还没有对应的输入连线 —— 节点里这枚 chip 显示失效并阻止提交。
  // 段 2-2 作为参考视频连进来:跟随它当前采用的结果,换采用后下次生成自动用新的。
  { id: "v_s2_3", kind: "video", sceneId: "s2", sort: 3, status: "todo", ai: "new", x: 1420, y: 330, w: 300, h: 196,
    title: "递烛", ms: 6000, adopted: null, gen: DR_GEN,
    prompt:
      "延续 " + drNodeRef("v_s2_2", "段 2-2") + " 落幅的光线与人物位置。\n\n" +
      "Shot 1（近景·平视·缓推·3s）\n【0-3s】\n" +
      "首帧：舱内两人之间的空隙，背景是油灯光晕。\n" +
      "[0-3s] 镜头持续向前推进，两侧人物的肩膀滑出画面。\n" +
      "结束状态：画面中央一只伸出的手。\n\n" +
      "Shot 2（特写·平视·缓推·3s）\n【3-6s】\n" +
      "首帧：一只递出 " + spRef("a_candle") + " 的手，烛火约占画面三分之一。\n" +
      "[3-5s] 烛火轻晃，持烛者的脸退出焦点。\n" +
      "[5-6s] 另一只手从画面右侧伸进来接住。暖光源来自烛火本身。\n" +
      "结束状态：两只手交接短烛的特写。" },

  /* ---- 视频节点:不进成片,自由试验;可以替换某个片段,也可以作为别的节点的参考 ---- */
  { id: "f_fog", kind: "video", x: 1340, y: -20, w: 300, h: 196,
    title: "空镜 · 江面夜雾", adopted: "r_fog_1",
    gen: { model: "wan30", mode: "text", ratio: "9:16", res: "720P" }, ms: 5000,
    prompt:
      "Shot 1（远景·平视·固定机位·5s）\n【0-5s】\n" +
      "首帧：夜色中的江面，薄雾贴水，远处一点渔火。无人物。\n" +
      "[0-5s] 薄雾缓慢向左流动，渔火忽明忽暗。写实质感，低饱和冷调。\n" +
      "结束状态：画面不变，渔火将灭未灭。" },
  /* ---- 图片节点:生成或上传一张图,可作为视频节点的参考图 / 首尾帧 ---- */
  { id: "i_cabin", kind: "image", x: 620, y: 700, w: 260, h: 196,
    title: "前舱 · 夜 · 宽景", adopted: "r_img_cabin_2", gen: DR_IMAGE_GEN, style: "st_hist",
    prompt: "夜间客船前舱宽景，一盏油灯悬在舱梁，两侧木凳，舱壁上有晃动的人影。参考 " + spRef("a_cabin") + " 的空间结构，无人物。" },
  { id: "i_ahui", kind: "image", x: 960, y: 700, w: 200, h: 196,
    title: "阿茴 · 定妆", adopted: "u_img_ahui", uploaded: true, gen: { ...DR_IMAGE_GEN, ratio: "3:4" }, prompt: "" },

  { id: "f_try", kind: "video", x: 1240, y: 700, w: 300, h: 196,
    title: "对坐 · 过肩重拍", adopted: "r_try_1", gen: DR_GEN, ms: 12000,
    prompt:
      "Shot 1（中景·平视·过肩固定·5s）\n【0-5s】\n" +
      "首帧：前景是 " + spRef("a_shen") + " 的肩背虚影，焦点在对面 " + spRef("a_zhou") + "，油灯在两人之间。\n" +
      "[0-5s] 周慎拨着念珠，目光越过灯焰看向前景。\n" +
      "结束状态：周慎直视前景。\n\n" +
      "Shot 2（近景·平视·反打·3s）\n【5-8s】\n" +
      "首帧：沈砚近景，半张脸在灯影里。\n" +
      "[5-8s] 画外周慎低声：「先生这手，是拿笔的手。」沈砚眼神不动。\n" +
      "结束状态：沈砚垂下眼。\n\n" +
      "Shot 3（特写·俯拍·固定机位·4s）\n【8-12s】\n" +
      "首帧：虎口旧墨痕的特写。\n" +
      "[8-12s] 手缓缓收进袖中。\n" +
      "结束状态：空木案特写。" },
];

// 输入连线(CanvasEdges 生成输入类型):来源节点 → 视频节点。role 用途;order 同一用途内的顺序。
// 来源是素材节点时 assetId 固定那条资产;来源是视频节点时不存 assetId,提交时取它当前采用的结果。
// 画布连线和节点输入面板编辑的是同一条。
const DR_EDGES = [
  { id: "e1", from: "n_dock",   to: "v_s1_1", type: "input", assetId: "a_dock",   role: "ref_image", order: 1 },
  { id: "e2", from: "n_shen_a", to: "v_s1_1", type: "input", assetId: "a_shen",   role: "ref_image", order: 2 },
  { id: "e3", from: "n_haozi",  to: "v_s1_1", type: "input", assetId: "a_haozi",  role: "ref_audio", order: 1, bow: 30 },

  { id: "e20", from: "n_pv_face", to: "v_s2_1", type: "input", assetId: "a_pv_face", role: "ref_image", order: 1 },
  { id: "e21", from: "n_zhou",    to: "v_s2_1", type: "input", assetId: "a_zhou",    role: "ref_image", order: 2, bow: 30 },
  { id: "e22", from: "n_shen_b",  to: "v_s2_1", type: "input", assetId: "a_shen",    role: "ref_image", order: 3, bow: -30 },
  { id: "e23", from: "n_shen_b",  to: "f_try",  type: "input", assetId: "a_shen",    role: "ref_image", order: 1, bow: 40 },
  { id: "e28", from: "n_zhou",    to: "f_try",  type: "input", assetId: "a_zhou",    role: "ref_image", order: 2, bow: 30 },
  { id: "e24", from: "n_pv_pan",  to: "v_s2_2", type: "input", assetId: "a_pv_pan2", role: "ref_video", order: 1, bow: 40 },
  { id: "e25", from: "n_cabin",   to: "v_s2_2", type: "input", assetId: "a_cabin",   role: "ref_image", order: 1, bow: 70 },
  { id: "e26", from: "n_ahui",    to: "v_s2_2", type: "input", assetId: "a_ahui",    role: "ref_image", order: 2, bow: 90 },
  { id: "e29", from: "n_cabin",   to: "i_cabin", type: "input", assetId: "a_cabin",   role: "ref_image", order: 1, bow: -40 },
  { id: "e27", from: "v_s2_2",    to: "v_s2_3", type: "input", role: "ref_video", order: 1 },
];

// VideoTasks:来源统一是节点(source_type = canvas_node)。每次明确重做新增一个任务;历史按节点查询。
// 任务状态独立于片段制作状态。替换片段时任务跟着节点走,不改写来源。
//   state 见 SP_TASK_STATE
// sample:true 是 480P 样片,expires 为可转成片的截止时间(提交后 7 天);fromSample 指向成片的来源样片任务。
// 演示「今天」= 10月21日。?completing=1 让段 2-2 的样片进入「成片生成中」。
const DR_TASKS = [
  { id: "T-2100", source: { type: "node", id: "v_s2_1" }, state: "succeeded", result: "r_21_s",
    at: "10月12日 20:10", model: "seedance25", secs: 12, fee: 3.6, sample: true, expires: "10月19日 20:10", expired: true },
  { id: "T-1101", source: { type: "node", id: "v_s1_1" }, state: "succeeded", result: "r_11_1",
    at: "昨天 21:10", model: "seedance25", secs: 15, fee: 15.0 },
  { id: "T-1102", source: { type: "node", id: "v_s1_1" }, state: "succeeded", result: "r_11_s",
    at: "昨天 21:40", model: "seedance25", secs: 15, fee: 4.5, sample: true, expires: "10月27日 21:40" },
  { id: "T-1103", source: { type: "node", id: "v_s1_1" }, state: "succeeded", result: "r_11_3",
    at: "昨天 22:05", model: "seedance25", secs: 15, fee: 24.0, fromSample: "T-1102" },
  { id: "T-2101", source: { type: "node", id: "v_s2_1" }, state: "succeeded", result: "r_21_1",
    at: "今天 10:02", model: "seedance25", secs: 12, fee: 12.0 },
  { id: "T-2102", source: { type: "node", id: "v_s2_1" }, state: "succeeded", result: "r_21_2",
    at: "今天 10:40", model: "seedance25", secs: 12, fee: 12.0 },
  { id: "T-2103", source: { type: "node", id: "v_s2_1" }, state: "failed", result: null,
    at: "今天 11:02", model: "seedance25", secs: 12, fee: 0, error: "供应商拒绝：参考图含真人面部，需更换素材" },
  { id: "T-2104", source: { type: "node", id: "v_s2_1" }, state: "running", result: null,
    at: "今天 16:12", model: "seedance25", secs: 12, fee: 12.0, progress: 62 },
  { id: "T-2201", source: { type: "node", id: "v_s2_2" }, state: "succeeded", result: "r_22_1",
    at: "今天 14:20", model: "seedance25", secs: 11, fee: 11.0 },
  { id: "T-2202", source: { type: "node", id: "v_s2_2" }, state: "succeeded", result: "r_22_2",
    at: "今天 16:05", model: "seedance25", secs: 11, fee: 11.0 },
  { id: "T-2203", source: { type: "node", id: "v_s2_2" }, state: "succeeded", result: "r_22_s",
    at: "今天 17:20", model: "seedance25", secs: 11, fee: 3.3, sample: true, expires: "10月28日 17:20" },
  ...(new URLSearchParams(location.search).get("completing") === "1" ? [
    { id: "T-2204", source: { type: "node", id: "v_s2_2" }, state: "running", result: null,
      at: "今天 17:42", model: "seedance25", secs: 11, fee: 17.6, fromSample: "T-2203", progress: 38 },
  ] : []),
  { id: "T-9001", source: { type: "node", id: "f_fog" }, state: "succeeded", result: "r_fog_1",
    at: "今天 09:30", model: "wan30", secs: 5, fee: 3.5 },
  { id: "T-9002", source: { type: "node", id: "f_fog" }, state: "download_failed", result: null,
    at: "今天 15:48", model: "wan30", secs: 5, fee: 3.5, error: "下载中断，已保留上游任务，可只重新下载" },
  { id: "T-9101", source: { type: "node", id: "f_try" }, state: "succeeded", result: "r_try_1",
    at: "今天 16:30", model: "seedance25", secs: 12, fee: 12.0 },
  { id: "T-I101", source: { type: "node", id: "i_cabin" }, state: "succeeded", result: "r_img_cabin_1",
    at: "今天 13:10", model: "seedream4", secs: 0, fee: 0.2 },
  { id: "T-I102", source: { type: "node", id: "i_cabin" }, state: "succeeded", result: "r_img_cabin_2",
    at: "今天 13:22", model: "seedream4", secs: 0, fee: 0.2 },
];

/* ===================== 导演台:前舱布景 ===================== */
// 坐标单位米,原点在舱门内侧;x 向右(左舷→右舷),z 向里(门 → 舱尾)。
// 暂不放场景背景:导演台里只有角色和机位,room 只用来定地面网格的范围。
const DR_STAGE = {
  id: "n_dir_cabin", sceneId: "s2",
  name: "前舱布景",
  room: { w: 4.2, d: 7.0 },
  // acts = 动作轨道上的片段(来自动作库),keys = 走位关键帧,rots = 旋转关键帧(角度,ry 即朝向);三者独立编辑。
  actors: [
    { id: "a_shen", name: "沈砚", look: "n_shen_b", color: "var(--dr-actor-1)",
      keys: [{ t: 0, x: 3.1, z: 3.2, pose: "坐" }],
      rots: [{ t: 0, rx: 0, ry: -40, rz: 0 }],
      acts: [{ act: "sit_write", a: 0, b: 11 }] },
    { id: "a_zhou", name: "周慎", look: "n_zhou", color: "var(--dr-actor-2)",
      keys: [{ t: 0, x: 1.0, z: 5.6, pose: "坐" }],
      rots: [{ t: 0, rx: 0, ry: 140, rz: 0 }],
      acts: [{ act: "sit", a: 0, b: 11 }] },
    { id: "a_ahui", name: "阿茴", look: "n_ahui", color: "var(--dr-actor-3)",
      keys: [
        { t: 0,   x: 2.1, z: 0.3, pose: "站" },
        { t: 3.5, x: 1.9, z: 2.0, pose: "走" },
        { t: 8.0, x: 2.0, z: 3.6, pose: "停" },
      ],
      rots: [
        { t: 0,   rx: 0, ry: 0,  rz: 0 },
        { t: 8.0, rx: 0, ry: -5, rz: 0 },
        { t: 9.5, rx: 0, ry: 70, rz: 0 },
      ],
      acts: [{ act: "stand", a: 0, b: 3.5 }, { act: "walk_slow", a: 3.5, b: 8 }, { act: "look_up", a: 8, b: 11 }] },
  ],
  // lookAt = 注视目标(角色 id),设了之后朝向由目标位置算出,朝向关键帧不生效。
  // moves = 运镜轨道上的片段(来自运镜预设)。
  cameras: [
    { id: "cam_face", name: "机位 A · 对坐", short: "机位 A", seg: "v_s2_1", lens: 35, lookAt: null,
      keys: [{ t: 0, x: 2.1, z: 2.0, yaw: 20, h: 1.1 }],
      moves: [{ move: "static", a: 0, b: 11 }] },
    { id: "cam_pan", name: "机位 B · 摇进前舱", short: "机位 B", seg: "v_s2_2", lens: 24, lookAt: "a_ahui",
      keys: [
        { t: 0,  x: 2.6, z: -0.6, yaw: -38, h: 1.3 },
        { t: 11, x: 2.6, z: -0.6, yaw: 6,   h: 1.3 },
      ],
      moves: [{ move: "follow_pan", a: 0, b: 11 }] },
  ],
  duration: 11,
  // 导演输出:每次录制/导出都登记一条新的图片或视频资产,冻结当时已保存的工程版本。
  // usedBy 是当前把这条资产连为输入的片段节点(由输入连线反查,这里写死只为 mockup)。
  exports: [
    { id: "x_face_1", asset: "a_pv_face", camera: "cam_face", kind: "still",  v: 1, at: "今天 10:30", usedBy: ["v_s2_1"] },
    { id: "x_pan_1",  asset: "a_pv_pan1", camera: "cam_pan",  kind: "motion", v: 1, at: "今天 14:05", usedBy: [], ratio: "9:16", secs: 11 },
    { id: "x_pan_2",  asset: "a_pv_pan2", camera: "cam_pan",  kind: "motion", v: 2, at: "今天 15:58", usedBy: ["v_s2_2"], ratio: "9:16", secs: 11, current: true },
  ],
};

/* ===================== 导演台:AI 布景 ===================== */
// AI 布景走 agent 会话:剧本场次原文 + 本场各片段提示词 + 画布造型节点 + 当前布景由 agent 自己读,
// 作者只说要求。agent 直接改布景,每次修改记一条历史,可以恢复到任意一版;
// 作者手动调过的对象 agent 默认不动。
// 步骤与 ChatPanel 的 ToolActivity 同构(verb / target / detail);edits 是这一轮写进布景的改动。
const DR_AI_STAGE_COST = 4;
const DR_AI_CHAT = {
  steps: {
    scene: [
      { kind: "thinking", detail: { label: "推理过程", text: "第 2 场三人同框：沈砚、周慎对坐，阿茴从舱门进。先读剧本和三个片段的提示词，再对照当前布景，只改需要动的对象。" } },
      { verb: "读取剧本", target: "第 2 场 · 客船前舱 · 夜 · 11 行",
        detail: { label: "摘录", text: "六人分坐前舱两侧。周慎认出沈砚的手，沈砚不认。阿茴替小姐讨一盏灯。" } },
      { verb: "读取片段", target: "段 2-1 ～ 2-3 · 3 段" },
      { verb: "读取布景", target: "3 个角色 · 2 个机位",
        detail: { label: "手动调过", text: "阿茴 · 走位（今天 15:40）" } },
      { verb: "修改布景", target: "沈砚 · 周慎" },
    ],
    shot: [
      { kind: "thinking", detail: { label: "推理过程", text: "只动段 2-2：机位 B 和阿茴。其他片段的机位不碰。" } },
      { verb: "读取片段", target: "段 2-2 · 摇进前舱 · 11s" },
      { verb: "读取布景", target: "机位 B · 阿茴",
        detail: { label: "手动调过", text: "阿茴 · 走位（今天 15:40）" } },
      { verb: "修改布景", target: "机位 B · 阿茴" },
    ],
  },
  reply: {
    scene: "改好了：沈砚转向周慎，周慎 2–6 秒加了倾听点头。阿茴的走位你手动调过，没有动。",
    shot: "段 2-2 改好了：机位 B 换成跟拍，阿茴最后 3 秒改成驻足。阿茴的走位你手动调过，没有动。",
  },
  edits: {
    scene: {
      rots: [["a_shen", -60], ["a_zhou", 115]],
      acts: [["a_zhou", { act: "listen", a: 2, b: 6 }]],
      moves: [],
    },
    shot: {
      rots: [],
      acts: [["a_ahui", { act: "stop", a: 8, b: 11 }]],
      moves: [["cam_pan", { move: "follow", a: 0, b: 11 }]],
    },
  },
};
// 布景历史:进入导演台时已有的几版(snap 由 director.jsx 用初始布景补上)
const DR_STAGE_HISTORY = [
  { id: "h1", at: "今天 14:02", by: "ai", label: "按第 2 场生成整场布景" },
  { id: "h2", at: "今天 15:40", by: "manual", label: "手动调整 · 阿茴走位" },
];

/* ===================== 小工具 ===================== */
function drIsSeg(n) {
  return !!n && n.kind === "video" && !!n.sceneId;
}
// 段号:场次号-场内顺序,如 2-3(派生值,不落库)
function drSegNo(n) {
  const sc = SP_SCENES.find((s) => s.id === n.sceneId);
  return `${sc ? sc.no : "?"}-${n.sort}`;
}
function drVideoLabel(n) {
  return drIsSeg(n) ? `段 ${drSegNo(n)}` : n.title;
}
function drSegsOf(nodes, sceneId) {
  return nodes.filter((n) => drIsSeg(n) && n.sceneId === sceneId).sort((a, b) => a.sort - b.sort);
}
// 成片顺序:场次顺序 + 场内 sort。
function drOrderedSegs(nodes) {
  return DR_SCENES.flatMap((sc) => drSegsOf(nodes, sc.id));
}
function drModel(id) {
  return spVideoModel(id) || DR_IMAGE_MODELS.find((m) => m.id === id);
}
// 能生成的节点:视频(含片段)与图片。两者都有提示词、生成配置、结果历史和采用结果。
function drIsGen(n) {
  return !!n && (n.kind === "video" || n.kind === "image");
}
// 节点 + 其资产的显示字段(title / tone),导演台读角色造型时也用这一份。
function drNode(id) {
  const n = DR_NODES.find((x) => x.id === id);
  if (!n) return null;
  const a = n.assetId && spAsset(n.assetId);
  return a ? { ...n, title: a.name, tone: a.tone, sub: a.source } : n;
}
function drSecs(ms) {
  return ms == null ? null : Math.round(ms / 1000);
}
// 当前生成方式允许的用途,再按模型上限过滤
function drRolesFor(model, mode) {
  return Object.entries(DR_ROLES).filter(([, r]) => {
    if (r.mode !== mode) return false;
    if (r.accepts === "video" && !model.maxVideos) return false;
    if (r.accepts === "audio" && !model.maxAudios) return false;
    if (r.accepts === "image" && mode === "ref" && !model.maxImages) return false;
    return true;
  }).map(([k]) => k);
}
// 本次请求的输入:按用途分组、组内按 order,得到模型的媒体槽(图片1、图片2、视频1…)。
// 来源是视频节点时解析成它当前采用的结果;还没采用就是 pending,提交被挡住。
// key = 输入身份(资产 id 或来源节点 id),提示词里的引用按 key 对应。
function drInputsOf(edges, nodeId, nodes) {
  const ins = edges.filter((e) => e.type === "input" && e.to === nodeId);
  const ordered = Object.keys(DR_ROLES).flatMap((role) =>
    ins.filter((e) => e.role === role).sort((a, b) => a.order - b.order));
  const counts = {};
  return ordered.map((e) => {
    const r = DR_ROLES[e.role];
    counts[r.slot] = (counts[r.slot] || 0) + 1;
    const slot = r.slot === "首帧" || r.slot === "尾帧" ? r.slot : `${r.slot}${counts[r.slot]}`;
    if (e.assetId) {
      const asset = spAsset(e.assetId);
      return { ...e, slot, key: e.assetId, asset, name: asset.name, pending: false };
    }
    const src = nodes.find((n) => n.id === e.from);
    const asset = src && src.adopted ? spAsset(src.adopted) : null;
    return { ...e, slot, key: e.from, src, asset, assetId: asset ? asset.id : null,
      name: `${drVideoLabel(src)} · ${asset ? "采用结果" : "未采用"}`, pending: !asset };
  });
}
// 缩略图用:未采用的视频来源画一个空帧。
function drInputAsset(input) {
  const image = input.src && input.src.kind === "image";
  return input.asset || { type: image ? "image" : "video", tone: "empty", name: input.name, source: image ? "图片节点" : "视频节点" };
}
// 连线不允许成环:目标节点已经是来源的上游(或就是来源本身)时拒绝。
function drWouldCycle(edges, fromId, toId) {
  const seen = new Set();
  const stack = [fromId];
  while (stack.length) {
    const id = stack.pop();
    if (id === toId) return true;
    if (seen.has(id)) continue;
    seen.add(id);
    edges.filter((e) => e.to === id).forEach((e) => stack.push(e.from));
  }
  return false;
}
// 提交前校验:未连接的引用、未采用的视频来源、超出模型上限、模式不支持的用途、空提示词。
function drValidate(cfg, inputs) {
  const model = drModel(cfg.gen.model);
  const issues = [];
  if (!cfg.prompt && !(model.image && inputs.length)) issues.push({ level: "error", text: "提示词为空" });
  const keys = new Set(inputs.map((i) => i.key));
  spPromptParts(cfg.prompt).filter((p) => p.ref && !keys.has(p.ref.assetId)).forEach((p) =>
    issues.push({ level: "error", ref: p.ref.assetId,
      text: `@${p.ref.label} 没有对应的输入连线 —— 连上输入或从提示词中移除` }));
  inputs.filter((i) => i.pending).forEach((i) =>
    issues.push({ level: "error", text: `${drVideoLabel(i.src)} 还没有采用结果 —— 先在它的结果里采用一个，或断开这条参考` }));
  const allowed = drRolesFor(model, cfg.gen.mode);
  inputs.filter((i) => !allowed.includes(i.role)).forEach((i) =>
    issues.push({ level: "error", text: `${model.name} 的${SP_GEN_MODES[cfg.gen.mode]}不接受「${DR_ROLES[i.role].label}」：${i.name}` }));
  const n = (acc) => inputs.filter((i) => DR_ROLES[i.role].accepts === acc && DR_ROLES[i.role].mode === "ref").length;
  if (cfg.gen.mode === "ref" && n("image") > model.maxImages) issues.push({ level: "error", text: `参考图超出上限 ${model.maxImages}` });
  if (cfg.gen.mode === "ref" && n("video") > model.maxVideos) issues.push({ level: "error", text: `参考视频超出上限 ${model.maxVideos}` });
  return issues;
}

// 节点当前采用的是不是样片;是的话给出来源任务、序号、是否过期、是否已有成片在生成。
function drSampleOf(node, tasks) {
  if (!node || !node.adopted) return null;
  const history = tasks.filter((t) => t.source.type === "node" && t.source.id === node.id);
  const task = history.find((t) => t.sample && t.result === node.adopted);
  if (!task) return null;
  const completing = history.find((t) => t.fromSample === task.id && !["succeeded", "failed"].includes(t.state));
  return { task, n: history.indexOf(task) + 1, expired: !!task.expired, completing,
    canComplete: !task.expired && !completing };
}

Object.assign(window, {
  DR_PROJECT, DR_EPISODE, DR_SCENES, DR_SEG_STATUS, DR_ROLES, DR_ASSET_TYPES,
  DR_CAMERA_MOVES, DR_DIR_MOVE_GROUPS, DR_DIR_MOVES, DR_CAM_GROUPS, DR_CAM_TEMPLATES,
  DR_ACTION_GROUPS, DR_ACTIONS, DR_AI_CHAT, DR_AI_STAGE_COST, DR_STAGE_HISTORY, DR_BANDS,
  DR_NODES, DR_EDGES, DR_TASKS, DR_STAGE,
  DR_STYLE_CATS, DR_STYLES, DR_IMAGE_MODELS, DR_IMAGE_GEN, DR_RATIO_BOX, drStyle, drStyleOf, drIsGen,
  DR_SPEC_RATIOS, DR_SPEC_RES, DR_SPEC, drFitSpec,
  drIsSeg, drSegNo, drVideoLabel, drSegsOf, drOrderedSegs, drNodeRef,
  drNode, drModel, drSecs, drRolesFor, drInputsOf, drInputAsset, drWouldCycle, drValidate, drSampleOf,
});
