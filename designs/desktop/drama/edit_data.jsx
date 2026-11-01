// edit_data.jsx — 多轨剪辑(drama/Editing.html)的 mock 数据与时间线小工具。全局名统一 ED_ / ed 前缀。
// 剪辑工程(每集一个):
//   · 首次进入时按成片顺序把片段的采用结果导入一次,之后是独立工程 —— 片段再换结果、改时长都不会同步过来;
//     要用新结果,从「素材」里拖到主轨替换。未采用的片段导入成「空缺」,导出为黑场。
//   · 主轨 V1 是磁吸轨:片段首尾相接,start 由顺序和时长派生;删除 / 裁剪会让后面的片段自动前移。
//     主轨上的衔接点可以设转场(叠化 / 黑场 / 闪白)。
//   · 其他轨道自由摆放:叠加 V2(视频 / 图片,带不透明度)、字幕 T1、对白 A1、音效 A2、音乐 A3。
//     一条轨道内片段不能重叠;音频片段可以在音频轨之间上下拖。
//   · 片段只引用资产 id(in / dur 是源内区间),不复制文件;对白、音效、音乐都是普通音频资产(生成或上传)。
// 关联文件: drama/editing.jsx, drama/edit_timeline.jsx, drama/edit_panels.jsx, drama/data.jsx, screenplay/data.jsx

const ED_FPS = 24;

// 采用结果的实际媒体规格(真实实现来自 FFprobe);mockup 里写死。
const DR_FILM_MEDIA = {
  r_11_1: { w: 720, h: 1280, fps: 24, audio: true },
  r_21_2: { w: 720, h: 1280, fps: 24, audio: true },
  r_22_2: { w: 720, h: 1280, fps: 30, audio: false },
};
// 成片尺寸:清晰度是短边,长边按剧本比例算,取偶数(同 Flutter ProductionSettings.dimensions)。
function drFilmSize(ratio, res) {
  const [a, b] = ratio.split(":").map(Number);
  const short = parseInt(res, 10);
  const long = Math.round((short * Math.max(a, b)) / Math.min(a, b) / 2) * 2;
  return a >= b ? [long, short] : [short, long];
}

// 剪辑里用到、但制片画布上还没有的音频资产(生成 · Seed Audio 1.0 或上传),登记进共享资产表。
SP_ASSETS.push(
  { id: "au_cui_1",   type: "audio", name: "对白 · 老崔 · 开船了，三倍", tone: "dusk", source: "生成 · Seed Audio 1.0", spec: "0:02 · WAV", secs: 1.8 },
  { id: "au_zhou_1",  type: "audio", name: "对白 · 周慎 · 拿笔的手",     tone: "umber", source: "生成 · Seed Audio 1.0", spec: "0:03 · WAV", secs: 2.6 },
  { id: "au_ahui_1",  type: "audio", name: "对白 · 阿茴 · 讨一盏灯",     tone: "rose", source: "生成 · Seed Audio 1.0", spec: "0:03 · WAV", secs: 2.4 },
  { id: "au_shen_1",  type: "audio", name: "对白 · 沈砚 · 拿去",         tone: "teal", source: "生成 · Seed Audio 1.0", spec: "0:01 · WAV", secs: 1.2 },
  { id: "au_river",   type: "audio", name: "江水拍船 · 夜",              tone: "teal", source: "生成 · Seed Audio 1.0", spec: "0:30 · WAV", secs: 30 },
  { id: "au_guqin",   type: "audio", name: "古琴 · 夜泊",                tone: "lamp", source: "生成 · Seed Audio 1.0", spec: "0:45 · WAV", secs: 45 },
);
// 源时长(秒)。视频取资产规格里的秒数;音频取 secs;图片没有源时长上限。
const ED_SRC_SECS = { a_haozi: 18 };
function edSrcSecs(assetId) {
  if (!assetId) return null;
  if (ED_SRC_SECS[assetId]) return ED_SRC_SECS[assetId];
  const a = spAsset(assetId);
  if (!a) return null;
  if (a.secs) return a.secs;
  if (a.type === "image") return null;
  const m = a.spec && a.spec.match(/(\d+)s/);
  return m ? Number(m[1]) : null;
}

/* ---------------- 轨道 ---------------- */
// kind: text | video | audio。main = 主轨(磁吸)。上下顺序 = 画面叠放顺序(上面的盖住下面的)。
const ED_TRACKS = [
  { id: "T1", kind: "text",  name: "字幕",  icon: "subtitles" },
  { id: "V2", kind: "video", name: "叠加",  icon: "stack" },
  { id: "V1", kind: "video", name: "主轨",  icon: "film-strip", main: true },
  { id: "A1", kind: "audio", name: "对白",  icon: "microphone", role: "dialogue" },
  { id: "A2", kind: "audio", name: "音效",  icon: "waveform",   role: "sfx" },
  { id: "A3", kind: "audio", name: "音乐",  icon: "music-notes", role: "music" },
];

/* ---------------- 主轨(导入时的样子) ---------------- */
// 顺序即时间。gap = 导入时片段还没有采用结果,留作空缺(导出为黑场),seg 记住它原来是哪一段。
// 段 1-1 导入后剪掉了头 0.5 秒、尾 1 秒,用来示意「源比片段长」时的可拉回区间。
const ED_MAIN = [
  { id: "c1", seg: "v_s1_1", asset: "r_11_1", in: 0.5, dur: 13.5, vol: 0 },
  { id: "c2", seg: "v_s1_2", gap: true, dur: 5 },
  { id: "c3", seg: "v_s2_1", asset: "r_21_2", in: 0, dur: 12, vol: 0 },
  { id: "c4", seg: "v_s2_2", asset: "r_22_2", in: 0, dur: 11, vol: -6 },
  { id: "c5", seg: "v_s2_3", gap: true, dur: 6 },
];
// 转场挂在「前一个主轨片段」上:它和下一个之间怎么接。
const ED_TRANSITIONS = {
  c2: { type: "black", dur: 0.6 },
  c3: { type: "dissolve", dur: 0.5 },
};
const ED_TRANSITION_TYPES = [
  { value: "none", label: "无" },
  { value: "dissolve", label: "叠化" },
  { value: "black", label: "黑场" },
  { value: "white", label: "闪白" },
];

/* ---------------- 其他轨道 ---------------- */
// start / dur 是时间线上的位置;in 是源内起点。vol 单位 dB;fadeIn / fadeOut 秒。
// ai: true = 制作助手写入的(右栏「最近改动」可回退)。
const ED_CLIPS = [
  { id: "t0", track: "T1", start: 1.0,  dur: 3.0, text: "夜航船 · 第一集 登船", style: "title", pos: "center" },
  { id: "t1", track: "T1", start: 14.0, dur: 1.8, text: "老崔：开船了，三倍。", style: "sub", pos: "bottom", ai: true },
  { id: "t2", track: "T1", start: 23.5, dur: 2.6, text: "周慎：先生这手，是拿笔的手。", style: "sub", pos: "bottom", ai: true },
  { id: "t3", track: "T1", start: 36.4, dur: 2.4, text: "阿茴：我家小姐想讨一盏灯。", style: "sub", pos: "bottom", ai: true },
  { id: "t4", track: "T1", start: 43.4, dur: 1.2, text: "沈砚：拿去。", style: "sub", pos: "bottom", ai: true },

  { id: "o1", track: "V2", asset: "r_fog_1", start: 15.6, dur: 4.4, in: 0.3, opacity: 55, fadeIn: 1, fadeOut: 1.2, scale: 100 },

  { id: "d1", track: "A1", asset: "au_cui_1",  start: 14.0, dur: 1.8, in: 0, vol: 0 },
  { id: "d2", track: "A1", asset: "au_zhou_1", start: 23.5, dur: 2.6, in: 0, vol: 0 },
  { id: "d3", track: "A1", asset: "au_ahui_1", start: 36.4, dur: 2.4, in: 0, vol: 0 },
  { id: "d4", track: "A1", asset: "au_shen_1", start: 43.4, dur: 1.2, in: 0, vol: 0 },

  { id: "s1", track: "A2", asset: "a_haozi",  start: 0,    dur: 13.5, in: 2, vol: -6, fadeOut: 1.5 },
  { id: "s2", track: "A2", asset: "au_river", start: 18.5, dur: 29,   in: 0, vol: -10, fadeIn: 1 },

  { id: "m1", track: "A3", asset: "au_guqin", start: 18.0, dur: 29.5, in: 4, vol: -12, fadeIn: 2, fadeOut: 2, duck: true },
];

/* ---------------- 小工具 ---------------- */
// 主轨派生 start;返回带 start 的新数组。
function edLayoutMain(main) {
  let t = 0;
  return main.map((c) => {
    const x = { ...c, track: "V1", start: t };
    t += c.dur;
    return x;
  });
}
function edMainEnd(main) {
  return main.reduce((s, c) => s + c.dur, 0);
}
function edTotal(main, clips) {
  return Math.max(edMainEnd(main), ...clips.map((c) => c.start + c.dur), 0);
}
function edTrack(id) {
  return ED_TRACKS.find((t) => t.id === id);
}
// 00:23.12(秒.帧)
function edTc(t) {
  const f = Math.round(Math.max(0, t) * ED_FPS);
  const s = Math.floor(f / ED_FPS);
  const fr = f % ED_FPS;
  return `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}.${String(fr).padStart(2, "0")}`;
}
function edSecsLabel(t) {
  return (Math.round(t * 10) / 10).toFixed(1) + "s";
}
function edSnapFrame(t) {
  return Math.round(t * ED_FPS) / ED_FPS;
}
// 主轨片段显示名:段号 + 片段标题(片段取导入时的名字,之后不同步)。
function edSegOf(c) {
  return c.seg ? DR_NODES.find((n) => n.id === c.seg) : null;
}
function edClipLabel(c) {
  if (c.text) return c.text;
  const seg = edSegOf(c);
  if (seg) return `段 ${drSegNo(seg)} · ${seg.title}`;
  const a = c.asset && spAsset(c.asset);
  return a ? a.name.replace(/^对白 · /, "") : "片段";
}
function edClipTone(c) {
  const a = c.asset && spAsset(c.asset);
  return a ? a.tone : "empty";
}
// 片段落在哪一场(给第二栏高亮 / 刻度上的场次标记用)。
function edSceneOf(c) {
  const seg = edSegOf(c);
  return seg ? seg.sceneId : null;
}

Object.assign(window, {
  ED_FPS, ED_TRACKS, ED_MAIN, ED_TRANSITIONS, ED_TRANSITION_TYPES, ED_CLIPS,
  edSrcSecs, edLayoutMain, edMainEnd, edTotal, edTrack, edTc, edSecsLabel, edSnapFrame,
  edSegOf, edClipLabel, edClipTone, edSceneOf,
});
