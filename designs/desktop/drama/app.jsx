// app.jsx — DramaProductionPage:「制片」页,一集的片段与制作画布(状态唯一持有者)。
// app 内页面,不全屏:NavRail + 第二栏(作品、剧集、场次,照搬场次页)+ 主区 + 制作助手。
// 主区顶栏左侧(标题旁)切换三个视图:分镜 | 画布 | 列表。分镜 = 按场次的片段列表(通读、改提示词);
// 画布 = 节点与连线;列表 = 画布上全部节点的卡片网格,点卡片回画布定位。
// 顶栏右侧是剧集全局风格:视频 / 图片节点默认跟随它,也可以在节点输入框里单独设置;
// 旁边是剧本制作设置(比例 / 清晰度,整部剧共用):新建视频节点的默认规格、整集成片的画幅,弹层与节点输入框的比例 / 清晰度同一个。
// 画布视图需要更多空间时,用第二栏顶部的折叠按钮收起整个左侧栏(同 Flutter:NavRail 缩成 48px 图标栏,第二栏隐藏)。
//   NavRail「制片」                      → drama/Drama.html             默认分镜视图
//   NavRail 其他栏目 / 查看原文            → ../index.html?novel=sp1&nav=…&scene=…
// 流程:先在「片段」视图让 AI 拆分段、通读修改,再去「画布」连参考、生成视频。AI 改动直接生效,回退在右栏「最近改动」。
// 两个 tab 读写同一份片段:片段节点 = 带场次 + 场内顺序的视频节点;左栏按成片顺序列出它们,两个 tab 共用。
// 视频节点自由试验,不进成片;它的结果登记为资产,片段可以从资产库选来采用,也可以连给别的节点当参考。
// 节点上存:位置/大小、提示词、生成配置、采用结果,片段再加场次、顺序、制作状态;输入连线另存(edges)。
// 任务(tasks)按节点查。
// 其他深链(便于截图核对):&ctx=0(左侧栏折叠) &tab=story|canvas|grid &seg=<nodeId>(分镜定位) &sel=<nodeId> &dialog=submit|export|lib|add|style|spec &pop=style|spec|plus(选中节点输入框里的弹层) &edge=<edgeId> &scene=<id> &chat=0 &director=1 &assets=1
//   画布视图的 AI 悬浮球:&float=1(展开浮动面板) &busy=1(助手执行中) &unread=1(有新回复)
//   工具审批(approval.jsx):&perm=1(助手权限) &approval=savefail|conflict
// 分镜 / 列表视图右栏是制作助手(聊天);画布视图不留右栏,助手收成右下角 Agent 头像悬浮球,
// 展开是浮在画布上的同一个聊天面板。进画布默认收起;画布里把事交给助手(或助手开始执行)时自动展开。
// 画布视图没有右栏时,主区顶栏就是最右侧的 chrome:Windows 下顶栏右侧要避让系统窗口按钮(本 mockup 只画 macOS 外框)。
// 节点编辑是画布上的浮层(composer.jsx)。
// 关联文件: drama/board.jsx, drama/composer.jsx, drama/approval.jsx, drama/grid.jsx, drama/data.jsx

const DR_Q = new URLSearchParams(location.search);

function drGoEditor(nav, params) {
  const q = new URLSearchParams({ novel: DR_PROJECT.id, ...(nav ? { nav } : {}), ...(params || {}) });
  window.location.href = `../index.html?${q.toString()}`;
}

function DramaProductionPage() {
  const [nodes, setNodes] = React.useState(DR_NODES);
  const [edges, setEdges] = React.useState(DR_EDGES);
  const [tasks, setTasks] = React.useState(DR_TASKS);
  const [selectedId, setSelectedId] = React.useState(DR_Q.get("edge") ? null : DR_Q.get("sel") || "v_s2_2");
  const [selectedEdge, setSelectedEdge] = React.useState(DR_Q.get("edge"));
  const [cam, setCam] = React.useState({ x: 0, y: 0, k: 1 });
  const [size, setSize] = React.useState({ w: 0, h: 0 });
  // director:false | { nodeId, empty, name }。新建的导演工程打开时是空布景。
  const [director, setDirector] = React.useState(DR_Q.get("director") === "1" ? {} : false);
  const [dlg, setDlg] = React.useState(() => {
    const d = DR_Q.get("dialog");
    if (d === "lib") return { type: "lib", mode: "place" };
    if (d === "add") return { type: "add" };
    if (d === "style" || d === "spec") return null;
    return d ? { type: d } : null;
  });
  const [toast, setToast] = React.useState(null);
  const [chatOpen, setChatOpen] = React.useState(DR_Q.get("chat") !== "0");
  // 画布视图的浮动面板单独记开关:离开画布回到分镜 / 列表,右栏恢复进画布前的样子。
  const [floatOpen, setFloatOpen] = React.useState(DR_Q.get("float") === "1");
  const agentBusy = DR_Q.get("busy") === "1";
  const agentUnread = DR_Q.get("unread") === "1";
  const [drawerOpen, setDrawerOpen] = React.useState(DR_Q.get("assets") === "1");
  const [ctxOpen, setCtxOpen] = React.useState(DR_Q.get("ctx") !== "0");
  const fitted = React.useRef(false);
  // 剧集全局风格:风格 id / "none" / { custom }。
  const [epStyle, setEpStyle] = React.useState("st_guzhuang");
  const [styleOpen, setStyleOpen] = React.useState(DR_Q.get("dialog") === "style");
  // 剧本制作设置(比例 / 清晰度),整部剧共用。
  const [spec, setSpec] = React.useState(DR_SPEC);
  const [specOpen, setSpecOpen] = React.useState(DR_Q.get("dialog") === "spec");
  // 默认先看分镜;带了画布相关深链就直接进画布。
  const [tab, setTab] = React.useState(DR_Q.get("tab") || (DR_Q.get("sel") || DR_Q.get("edge") || (DR_Q.get("dialog") && !["style", "spec"].includes(DR_Q.get("dialog"))) ? "canvas" : "story"));
  const [listFocus, setListFocus] = React.useState({ seg: DR_Q.get("seg"), scene: DR_Q.get("scene") });
  const pendingFocus = React.useRef(null);

  const say = (t) => {
    setToast(t);
    window.clearTimeout(say.timer);
    say.timer = window.setTimeout(() => setToast(null), 2600);
  };

  // 工具审批:审批请求、权限规则、本会话运行。审批卡、运行条、悬浮球、权限弹窗共用这一份。
  const [approvals, setApprovals] = React.useState(DR_APPROVALS);
  const [rules, setRules] = React.useState(DR_RULES);
  const [permOpen, setPermOpen] = React.useState(DR_Q.get("perm") === "1");
  const [apprFocus, setApprFocus] = React.useState(null);
  const [runsExtra, setRunsExtra] = React.useState(DR_RUNS_EXTRA);
  const apprDemo = DR_Q.get("approval");
  const patchAp = (id, p) => setApprovals((as) => as.map((a) => (a.id === id ? { ...a, ...p } : a)));
  const allowAp = (id, scope) => {
    const ap = approvals.find((a) => a.id === id);
    if (ap.state !== "pending") return;
    patchAp(id, { state: "resolving", saveFailed: false });
    window.setTimeout(() => {
      // 长期规则保存失败:保持待审批并显示错误,不回报已允许。
      if (scope !== "once" && apprDemo === "savefail") return patchAp(id, { state: "pending", saveFailed: true });
      if (scope !== "once") setRules((r) => ({ ...r, [scope]: { ...r[scope], [ap.cap]: "allow" } }));
      // 批准后复核冻结目标:审批期间节点配置被改,返回 conflict,不提交。
      if (apprDemo === "conflict" && ap.nodeId) return patchAp(id, { state: "conflict" });
      patchAp(id, { state: "allowed", scope });
    }, 600);
  };
  const denyAp = (id) => patchAp(id, { state: "denied" });
  const cancelRun = (r) => {
    if (r.approvalId) return patchAp(r.approvalId, { state: "cancelled" });
    setRunsExtra((rs) => rs.map((x) => (x.id === r.id ? { ...x, state: "cancelled" } : x)));
  };
  const runs = [...runsExtra, ...approvals.filter((a) => a.id !== "ap0").map(drRunOf)];
  const waitingCount = approvals.filter((a) => a.state === "pending" || a.state === "resolving").length;
  const locateAp = (id) => {
    setApprFocus(id);
    const el = document.querySelector(`[data-approval="${id}"]`);
    if (el) el.scrollIntoView({ behavior: "smooth", block: "center" });
    window.setTimeout(() => setApprFocus(null), 1600);
  };
  const appr = { items: approvals, runs, focus: apprFocus, onAllow: allowAp, onDeny: denyAp,
    onCancelRun: cancelRun, onLocate: locateAp, onOpenPerms: () => setPermOpen(true) };

  const onSize = React.useCallback((s) => setSize((p) => (p.w === s.w && p.h === s.h ? p : s)), []);

  const focusNode = (n, sz = size) => {
    if (!n || !sz.w) return;
    const pad = { ...n, x: n.x - 200, y: n.y - 120, w: n.w + 400, h: n.h + 420 };
    setCam(cvFitView([pad], sz));
  };
  const focusScene = (sceneId) => {
    const b = DR_BANDS.find((x) => x.sceneId === sceneId);
    if (b && size.w) setCam(cvFitView([{ ...b, id: sceneId }], size));
  };

  React.useEffect(() => {
    if (fitted.current || !size.w) return;
    fitted.current = true;
    const sceneParam = DR_Q.get("scene");
    const first = nodes.find((n) => n.id === selectedId);
    if (first && !sceneParam) {
      focusNode(first, size);
      return;
    }
    const b = DR_BANDS.find((x) => x.sceneId === (sceneParam || "s2"));
    setCam(cvFitView([{ ...b, id: b.sceneId }], size));
  }, [size]);

  // 从分镜 / 列表切到画布:画布重新挂载、报完尺寸后再选中并定位节点。
  React.useEffect(() => {
    if (tab !== "canvas" || !size.w || !pendingFocus.current) return;
    const n = nodes.find((x) => x.id === pendingFocus.current);
    pendingFocus.current = null;
    fitted.current = true;
    if (!n) return;
    setSelectedId(n.id);
    setSelectedEdge(null);
    focusNode(n);
  }, [tab, size]);
  const toCanvas = (nodeId) => {
    pendingFocus.current = nodeId || null;
    setSize({ w: 0, h: 0 });
    setTab("canvas");
  };
  // 失败提醒的动作:重新下载 / 打开这个节点的「结果」看原因 / 关闭提醒。分镜、列表、画布共用。
  // resReq.n 每次递增,让节点浮条重新挂载并直接展开「结果」。
  const [resReq, setResReq] = React.useState(DR_Q.get("pop") === "res" && DR_Q.get("sel") ? { id: DR_Q.get("sel"), n: 0 } : null);
  React.useEffect(() => {
    if (resReq && resReq.id !== selectedId) setResReq(null);
  }, [selectedId]);
  const redownload = (id) => {
    setTasks((ts) => ts.map((t) => (t.id === id ? { ...t, state: "downloading", error: null } : t)));
    say("只重新下载，不会再次计费");
  };
  const taskActs = {
    onRedownload: redownload,
    onDismiss: (id) => setTasks((ts) => ts.map((t) => (t.id === id ? { ...t, dismissed: true } : t))),
    onOpenResults: (nodeId) => {
      setResReq((r) => ({ id: nodeId, n: (r ? r.n : 0) + 1 }));
      if (tab === "canvas") { setSelectedId(nodeId); setSelectedEdge(null); }
      else toCanvas(nodeId);
    },
  };
  const toList = (nodeId, sceneId) => {
    setListFocus({ seg: nodeId || null, scene: sceneId || null });
    setTab("story");
  };
  const switchTab = (v) => {
    if (v === tab) return;
    if (v === "canvas") return toCanvas(tab === "story" ? listFocus.seg : selectedId);
    if (v === "story") return toList(sel && drIsSeg(sel) ? sel.id : null, null);
    setTab(v);
  };
  // AI 改动已生效,只能回退(右栏「最近改动」):回退新增 = 软删这个片段节点,回退修改在 mockup 里只清标记。
  const revertSeg = (n) => {
    if (n.ai === "new") setNodes((ns) => ns.filter((x) => x.id !== n.id));
    else setNodes((ns) => ns.map((x) => (x.id === n.id ? { ...x, ai: undefined } : x)));
    say(`已回退段 ${drSegNo(n)} 的 AI 改动`);
  };
  const aiSegs = drOrderedSegs(nodes).filter((n) => n.ai);
  // 分镜视图「新增片段」:排在这一场末尾,节点放进这一场色带的空处。
  const addSeg = (sceneId) => {
    const band = DR_BANDS.find((b) => b.sceneId === sceneId) || DR_BANDS[0];
    const sort = drSegsOf(nodes, sceneId).length + 1;
    const id = "seg_" + Date.now();
    setNodes((ns) => [...ns, { id, kind: "video", sceneId, sort, status: "todo", title: "新片段", prompt: "", ms: null, adopted: null,
      gen: { model: "seedance25", mode: "text", ratio: "9:16", res: "720P" }, x: band.x + band.w - 340, y: band.y + band.h - 230, w: 300, h: 196 }]);
    setListFocus({ seg: id, scene: null });
    say(`已新建段 ${SP_SCENES.find((x) => x.id === sceneId).no}-${sort} · 画布上同时有了它的节点`);
  };

  const moveNode = React.useCallback((id, x, y) => {
    setNodes((ns) => ns.map((n) => (n.id === id ? { ...n, x, y } : n)));
  }, []);

  const labelOf = (n) => (n.kind === "video" ? drVideoLabel(n) : n.title);
  // 上传(mockup 不弹系统选择器):登记为一条「上传」资产。
  // 实现:所有上传入口(添加菜单、＋ 菜单、节点上传、工具条、资产抽屉)都先把文件保存进资产库,按内容哈希去重 ——
  // 同一文件再次上传复用已有资产,不重复复制、不新建资产;节点结果 / 输入连线只引用资产 id。界面上不解释这一步。
  const fakeUpload = (type, name) => {
    const id = "u_" + Date.now();
    SP_ASSETS.push({ id, type, name, tone: type === "image" ? "rose" : "teal", source: "上传",
      spec: type === "image" ? "1080×1440" : "720×1280 · 8s" });
    return id;
  };
  // 上传文件直接成为节点的结果:登记资产并采用,不产生任务、不计费。
  const uploadResult = (n) => {
    const image = n.kind === "image";
    const id = fakeUpload(image ? "image" : "video", image ? "本地图片.jpg" : "本地视频.mp4");
    setNodes((ns) => ns.map((x) => (x.id === n.id ? { ...x, adopted: id, uploaded: true } : x)));
    setSelectedId(n.id);
    say("已上传");
  };
  // 上传文件作为输入:在节点左侧放素材节点并连一条参考图输入。
  const uploadInput = (n) => {
    const id = fakeUpload("image", "上传参考图.jpg");
    addInput(ensureAssetNode(id, n), n.id, id, "ref_image");
    say("已上传");
  };
  const patchNode = (n) => (p) => setNodes((ns) => ns.map((x) => (x.id === n.id ? { ...x, ...p } : x)));

  // 连线来源的显示:素材节点是资产本身;视频节点是它采用的结果,还没采用就是空帧。
  const sourceOf = (n) => {
    if (!drIsGen(n)) return { asset: spAsset(n.assetId), label: spAsset(n.assetId).name };
    const res = n.adopted && spAsset(n.adopted);
    const label = drVideoLabel(n);
    const image = n.kind === "image";
    return { asset: res ? { ...res, name: label } : { type: image ? "image" : "video", tone: "empty", name: label, source: image ? "图片节点" : "视频节点" }, label };
  };

  // assetId 为空表示来源是视频节点:不固定资产,跟随它的采用结果。
  const addInput = (fromId, toId, assetId, role) => {
    setEdges((es) => {
      const key = assetId || fromId;
      if (es.some((e) => e.to === toId && (e.assetId || e.from) === key)) return es;
      const order = es.filter((e) => e.to === toId && e.role === role).length + 1;
      return [...es, { id: "e" + Date.now(), from: fromId, to: toId, type: "input", ...(assetId ? { assetId } : {}), role, order }];
    });
  };
  // 资产没在画布上就在目标节点左侧放一个素材节点,再连线 —— 输入总是一条看得见的线。
  const ensureAssetNode = (assetId, near) => {
    const exist = nodes.find((n) => n.assetId === assetId && n.kind === "asset");
    if (exist) return exist.id;
    const id = "n_" + assetId + "_" + Date.now();
    const count = edges.filter((e) => e.to === near.id).length;
    setNodes((ns) => [...ns, { id, kind: "asset", assetId, x: near.x - 280, y: near.y + 210 + count * 10, w: 220, h: 84 }]);
    return id;
  };
  const insertRef = (n, ref, role) => {
    const tag = ref.type === "nodes" ? drNodeRef(ref.id, ref.label) : spRef(ref.id);
    patchNode(n)({ prompt: (n.prompt || "") + tag });
    if (role) {
      addInput(ensureAssetNode(ref.id, n), n.id, ref.id, role);
      say(`已引用 @${ref.label}，并补了一条「${DR_ROLES[role].label}」输入`);
    }
  };

  const sel = nodes.find((n) => n.id === selectedId);
  const isGen = drIsGen;
  // 浮层按屏幕像素定位(不随画布缩放),工具条贴节点上沿,输入框贴节点下沿,超出画布就夹回来。
  // 视频节点底栏比图片多时长 / 生成方式 / 运镜,输入框更宽;窄画布时夹到画布宽度内。
  // 输入框左右都要让:左边是缩放 + 工具那一列(16 + 40),右边是展开的浮动 AI 面板。
  const floatPanelW = Math.min(360, size.w - 32);
  const reservedLeft = (drawerOpen ? 316 : 16) + 40;
  const reservedRight = floatOpen ? floatPanelW + 16 : 0;
  const composerW = (n) => Math.max(320, Math.min(n.kind === "image" ? 620 : 800, size.w - reservedLeft - reservedRight - 24));
  const barStyle = (n) => ({
    left: cam.x + (n.x + n.w / 2) * cam.k,
    top: Math.max(8, cam.y + n.y * cam.k - 46),
  });
  const composerStyle = (n) => ({
    width: composerW(n),
    left: Math.max(12, Math.min(Math.max(reservedLeft + 12, cam.x + (n.x + n.w / 2) * cam.k - composerW(n) / 2), size.w - reservedRight - composerW(n) - 12)),
    top: Math.min(cam.y + (n.y + n.h) * cam.k + 14, size.h - 236),
  });
  const selEdge = edges.find((e) => e.id === selectedEdge);
  const zoom = (d) => setCam((v) => {
    const k = Math.min(CV_ZOOM_MAX, Math.max(CV_ZOOM_MIN, v.k * (d > 0 ? 1.25 : 1 / 1.25)));
    const cx = size.w / 2;
    const cy = size.h / 2;
    return { k, x: cx - (cx - v.x) * (k / v.k), y: cy - (cy - v.y) * (k / v.k) };
  });

  const goScript = (sceneId) => drGoEditor("script", { scene: sceneId });
  const closeDirector = () => setDirector(false);

  // 「添加」直接在画布上新建节点。落点:双击处;从底部「＋」打开时取画布中心。
  const createNode = (kind, at) => {
    const board = document.querySelector(".cv-board");
    const r = board ? board.getBoundingClientRect() : { left: 0, top: 0 };
    const sx = at && !at.dock ? at.x - r.left : size.w / 2;
    const sy = at && !at.dock ? at.y - r.top : size.h / 2;
    const p = { x: (sx - cam.x) / cam.k, y: (sy - cam.y) / cam.k };
    const id = kind.slice(0, 2) + "_" + Date.now();
    const blank = { prompt: "", gen: { model: "seedance25", mode: "text", ...drFitSpec(drModel("seedance25"), spec) }, ms: null, adopted: null };
    const bandAt = DR_BANDS.find((b) => p.x >= b.x && p.x <= b.x + b.w && p.y >= b.y && p.y <= b.y + b.h);
    if (kind === "seg") {
      // 片段属于落点所在色带的那一场;落在色带外就归第一场。排在这一场末尾。
      const sceneId = (bandAt || DR_BANDS[0]).sceneId;
      const sort = drSegsOf(nodes, sceneId).length + 1;
      setNodes((ns) => [...ns, { id, kind: "video", sceneId, sort, status: "todo", title: "新片段", ...blank,
        x: p.x - 150, y: p.y - 98, w: 300, h: 196 }]);
      say(`已新建段 ${SP_SCENES.find((x) => x.id === sceneId).no}-${sort}`);
    } else if (kind === "video") {
      setNodes((ns) => [...ns, { id, kind: "video", title: "视频", ...blank, x: p.x - 150, y: p.y - 98, w: 300, h: 196 }]);
    } else if (kind === "image") {
      setNodes((ns) => [...ns, { id, kind: "image", title: "图片", prompt: "", gen: DR_IMAGE_GEN, adopted: null,
        x: p.x - 130, y: p.y - 98, w: 260, h: 196 }]);
    } else if (kind === "director") {
      // 一场一个导演工程:落点所在的场次色带决定场次;这一场已有就定位原节点。
      const band = bandAt || DR_BANDS[0];
      const sc = SP_SCENES.find((x) => x.id === band.sceneId);
      const exist = nodes.find((n) => n.kind === "director" && n.sceneId === band.sceneId);
      if (exist) {
        setSelectedId(exist.id);
        focusNode(exist);
        say(`第 ${sc.no} 场已有导演工程，一场一个`);
        return;
      }
      setNodes((ns) => [...ns, { id, kind: "director", assetId: null, sceneId: band.sceneId, x: p.x - 110, y: p.y - 56, w: 220, h: 112 }]);
      setDirector({ nodeId: id, empty: true, name: `第 ${sc.no} 场布景` });
    } else {
      setNodes((ns) => [...ns, { id, kind: "asset", assetId: null, mediaType: kind === "clip" ? "video" : kind, x: p.x - 110, y: p.y - 42, w: 220, h: 84 }]);
    }
    setSelectedId(id);
    setSelectedEdge(null);
  };

  const focusSeg = tab === "story" ? nodes.find((n) => n.id === listFocus.seg) : sel;
  const chatContext = focusSeg && isGen(focusSeg) ? (drIsSeg(focusSeg) ? `${labelOf(focusSeg)} · ${focusSeg.title}` : focusSeg.title) : null;

  const submitNode = dlg && dlg.type === "submit" && sel && isGen(sel) ? sel : null;
  const confirmSubmit = () => {
    const secs = drSecs(submitNode.ms);
    const model = drModel(submitNode.gen.model);
    const sample = !!dlg.sample;
    setTasks((ts) => [...ts, { id: "T-" + Date.now(), source: { type: "node", id: submitNode.id }, state: "queued", result: null, at: "刚刚",
      model: model.id, secs: secs || 0, sample, expires: sample ? "10月28日" : undefined,
      fee: model.image ? model.pricePerImage : secs * (sample ? model.sample.pricePerSec : model.pricePerSec) }]);
    // 任务建好后片段自动转为制作中;成功结果登记后自动采用并标为已完成(mockup 不模拟回调)。
    if (drIsSeg(submitNode)) patchNode(submitNode)({ status: "doing" });
    setDlg(null);
    say(sample ? "样片已提交 · 满意后 7 天内可转成片" : "已提交 · 关闭页面也会继续，结果保存在本机");
  };

  // 样片转成片:?dialog=complete 直接打开段 2-2 的样片。back="export" 时确认后回到导出提醒。
  const completeNode = dlg && dlg.type === "complete" ? nodes.find((n) => n.id === (dlg.nodeId || "v_s2_2")) : null;
  const completeTask = completeNode ? tasks.find((t) => t.id === (dlg.taskId || "T-2203")) : null;
  const confirmComplete = () => {
    const model = drModel(completeTask.model);
    setTasks((ts) => [...ts, { id: "T-" + Date.now(), source: completeTask.source, state: "running", result: null, at: "刚刚",
      model: model.id, secs: completeTask.secs, fee: completeTask.secs * model.sample.finalPricePerSec, fromSample: completeTask.id, progress: 0 }]);
    setDlg(dlg.back ? { type: dlg.back } : null);
    say(`${labelOf(completeNode)} 成片已提交 · 完成后自动采用，样片保留在结果里`);
  };
  const sampleRows = drOrderedSegs(nodes).map((node) => ({ node, info: drSampleOf(node, tasks) })).filter((r) => r.info);
  const exportSegs = () => {
    const segs = drOrderedSegs(nodes);
    const skipped = segs.filter((n) => !n.adopted);
    setDlg(null);
    say(`已导出到 ~/Movies/夜航船/production-Ep1 · ${segs.length - skipped.length} 个视频 + prompts.md / prompts.csv`
      + (skipped.length ? ` · 未采用的 ${skipped.length} 段已跳过` : ""));
  };

  // 拖线松手:来源是素材或视频节点;不允许连到自己的上游(成环)。
  const connect = (fromId, toId, at) => {
    if (drWouldCycle(edges, fromId, toId)) {
      say("不能这样连：目标节点已经是来源的上游，会形成循环");
      return;
    }
    setDlg({ type: "role", from: nodes.find((n) => n.id === fromId), to: nodes.find((n) => n.id === toId), at });
  };
  const edgeInfo = (e) => {
    const from = nodes.find((n) => n.id === e.from);
    const src = drIsGen(from) ? sourceOf(from) : { asset: spAsset(e.assetId), label: spAsset(e.assetId).name };
    return { ...e, asset: src.asset, fromLabel: src.label, toLabel: labelOf(nodes.find((n) => n.id === e.to)) };
  };

  // 左侧栏折叠/展开只改画布宽度,DrBoard 自己重新量尺寸,镜头保持不动。
  const toggleCtx = () => setCtxOpen(!ctxOpen);
  // 第二栏高亮的场次:分镜视图跟定位的场次 / 片段走,画布视图跟选中节点或刚点的场次走。
  const [canvasScene, setCanvasScene] = React.useState(DR_Q.get("scene"));
  const listSeg = nodes.find((n) => n.id === listFocus.seg);
  const railScene = tab === "story" ? listFocus.scene || (listSeg && listSeg.sceneId) : (sel && sel.sceneId) || canvasScene;

  return (
    <div className="m-editor-page dr-page">
      <NavRail activeId="production" screenplay hrefBase="../" collapsed={!ctxOpen} onExpand={toggleCtx}
        onSelect={(id) => drGoEditor(id)} onOpenSettings={() => say("设置在主窗口打开")} />

      {ctxOpen && (
        <DrEpisodeRail sceneId={railScene}
          onCollapse={toggleCtx} onBack={() => (window.location.href = "../index.html")}
          onSelectEp={(e) => (e.id === DR_EPISODE.id ? null : say(`切到 ${e.label} · mockup 只有 ${DR_EPISODE.label} 的片段数据`))}
          onSelectScene={(sceneId) => {
            if (tab !== "canvas") return setListFocus({ seg: null, scene: sceneId });
            setSelectedId(null);
            setSelectedEdge(null);
            setCanvasScene(sceneId);
            focusScene(sceneId);
          }} />
      )}

      <div className="dr-main">
      <div className="sp-top">
        <div className="sp-seg">
          {[["story", "分镜", "list-numbers"], ["canvas", "画布", "flow-arrow"], ["grid", "列表", "squares-four"]].map(([v, l, ic]) => (
            <button key={v} type="button" className={"sp-seg__opt" + (tab === v ? " is-active" : "")} onClick={() => switchTab(v)}>
              <Icon name={ic} size={14} /><span>{l}</span>
            </button>
          ))}
        </div>
        <span className="sp-top__spacer" />
        <DrEpisodeStyle value={epStyle} open={styleOpen} onOpen={setStyleOpen}
          onChange={(v) => {
            setEpStyle(v);
            setStyleOpen(false);
            const own = nodes.filter((n) => drIsGen(n) && n.style !== undefined).length;
            say(`剧集风格改为「${drStyleOf(null, v).name}」` + (own ? ` · ${own} 个单独设置风格的节点不受影响` : ""));
          }} />
        <span className="dr-top__sep" />
        <DrProductionSpec value={spec} open={specOpen} onOpen={setSpecOpen}
          onChange={(p) => {
            const next = { ...spec, ...p };
            setSpec(next);
            say(`剧本比例 / 清晰度改为 ${next.ratio} · ${next.res}，已有节点不变`);
          }} />
        <span className="dr-top__sep" />
        {/* 成片只从本集剪辑导出;制片页只导出分镜:采用的视频按成片顺序各存一个文件,附 prompts.md / prompts.csv。
            有分镜在用 480P 样片时先弹样片提醒。 */}
        {tab === "story" && (
          <button type="button" className="m-icon-btn" title="导出分镜"
            onClick={() => (sampleRows.length ? setDlg({ type: "export" }) : exportSegs())}>
            <Icon name="download-simple" size={16} />
          </button>
        )}
        <a className="m-icon-btn" title="剪辑" href="Editing.html">
          <Icon name="scissors" size={16} />
        </a>
      </div>

      <div className="cv-body">
        {tab === "story" && (
          <DrSegmentList nodes={nodes} edges={edges} tasks={tasks} focus={listFocus}
            onPatch={patchNode} onToCanvas={toCanvas} onAdd={addSeg} taskActs={taskActs}
            onGoScript={goScript}
            onAsk={(scene) => say(`已发到右侧对话：「把第 ${scene.no} 场拆成片段」· 写入后直接出现在列表里`)}
            toast={toast} />
        )}

        {tab === "grid" && (
          <DrNodeGrid nodes={nodes} edges={edges} tasks={tasks} epStyle={epStyle}
            onOpen={(n) => toCanvas(n.id)} onUpload={uploadResult} taskActs={taskActs}
            onCreate={() => { toCanvas(null); setDlg({ type: "add" }); }}
            toast={toast} />
        )}

        {tab === "canvas" && (
        <div style={{ position: "relative", flex: 1, minWidth: 0, display: "flex" }}>
          <DrBoard nodes={nodes} edges={edges} tasks={tasks} view={cam} setView={setCam}
            onSize={onSize} selectedId={selectedId} onSelect={setSelectedId}
            selectedEdge={selectedEdge} onSelectEdge={setSelectedEdge}
            onMoveNode={moveNode} onOpenDirector={() => setDirector({})} onUpload={uploadResult}
            onCanvasMenu={(at) => setDlg({ type: "add", at })}
            onConnect={connect} taskActs={taskActs} />
          {selEdge && (
            <DrEdgeBar edge={edgeInfo(selEdge)}
              onRole={(role) => setEdges((es) => es.map((e) => (e.id === selEdge.id ? { ...e, role } : e)))}
              onUnlink={() => { setEdges((es) => es.filter((e) => e.id !== selEdge.id)); setSelectedEdge(null); say("已断开 · 这条输入的用途和顺序不再保留"); }}
              onClose={() => setSelectedEdge(null)} />
          )}
          {sel && (
            <DrNodeBar key={"bar-" + sel.id + (resReq && resReq.id === sel.id ? "-res" + resReq.n : "")} node={sel}
              initialPop={resReq && resReq.id === sel.id ? "res" : null} edges={edges} nodes={nodes} tasks={tasks}
              style={barStyle(sel)}
              onPatch={patchNode(sel)}
              onCompleteSample={(t) => setDlg({ type: "complete", nodeId: sel.id, taskId: t.id })}
              onAdopt={(assetId, n) => {
                // 切回历史结果只改采用指针,不改制作状态,也不重新生成。
                patchNode(sel)({ adopted: assetId });
                const downstream = edges.filter((e) => e.from === sel.id).length;
                say(`已改用第 ${n} 次的结果` + (downstream ? ` · ${downstream} 个下游节点下次生成用这个结果` : ""));
              }}
              onRedownload={redownload}
              onGoScript={goScript}
              onGoList={(n) => toList(n.id, null)}
              onPickAdopt={() => setDlg({ type: "lib", mode: "adopt", tab: sel.kind === "image" ? "image" : "video", node: sel })}
              onUploadResult={() => uploadResult(sel)}
              onOpenDirector={() => setDirector(sel.kind === "director" && !sel.assetId
                ? { nodeId: sel.id, empty: true, name: `第 ${SP_SCENES.find((x) => x.id === sel.sceneId).no} 场布景` } : {})}
              onFill={(n) => setDlg({ type: "lib", mode: "fill", tab: n.mediaType, node: n })}
              onImport={() => say("已上传")}
              onSelectNode={(id) => { setSelectedId(id); focusNode(nodes.find((n) => n.id === id)); }}
              onPlaceAsset={(assetId) => {
                const id = "n_" + assetId;
                setNodes((ns) => [...ns, { id, kind: "asset", assetId, x: sel.x, y: sel.y + 360, w: 220, h: 84 }]);
                setSelectedId(id);
              }} />
          )}
          {sel && isGen(sel) && (
            <DrComposer key={"cmp-" + sel.id} node={sel} nodes={nodes} edges={edges} tasks={tasks} epStyle={epStyle}
              onUploadInput={uploadInput}
              style={composerStyle(sel)}
              onPatch={patchNode(sel)} onEdges={setEdges} onInsertRef={insertRef}
              onAddInput={(n) => setDlg({ type: "lib", mode: "input", node: n })}
              onSubmit={(sample) => setDlg({ type: "submit", sample })} />
          )}
          {drawerOpen && (
            <DrAssetDrawer nodes={nodes} onClose={() => setDrawerOpen(false)}
              onImport={() => say("已上传")}
              onPlace={(assetId) => {
                const a = spAsset(assetId);
                const id = "n_" + assetId + "_" + Date.now();
                const p = { x: (size.w / 2 - cam.x) / cam.k, y: (size.h / 2 - cam.y) / cam.k };
                const isDir = a.type === "director";
                setNodes((ns) => [...ns, { id, kind: isDir ? "director" : "asset", assetId, sceneId: "s2",
                  x: p.x - 110, y: p.y - 42, w: 220, h: isDir ? 112 : 84 }]);
                setSelectedId(id);
              }} />
          )}
          <DrCanvasStack drawerOpen={drawerOpen}>
            <DrZoomCluster zoom={Math.round(cam.k * 100)} onZoom={zoom}
              onFit={() => setCam(cvFitView(DR_BANDS.map((b) => ({ ...b, id: b.sceneId })), size))} />
            <DrCanvasTools drawerOpen={drawerOpen} onToggleDrawer={() => setDrawerOpen(!drawerOpen)}
              onImport={() => say("已上传")}
              onLayout={() => say("已按场次整理节点 · 可撤销")} />
          </DrCanvasStack>
          <DrAddDock addOpen={!!(dlg && dlg.type === "add")}
            onAdd={(at) => setDlg(dlg && dlg.type === "add" ? null : { type: "add", at })} />
          {floatOpen && (
            <DrChatPanel floating onClose={() => setFloatOpen(false)} context={chatContext} aiSegs={aiSegs} onRevert={revertSeg}
              style={{ width: floatPanelW }} appr={appr} />
          )}
          <DrAgentFab open={floatOpen} busy={agentBusy} progress="3 / 4" unread={agentUnread} waiting={waitingCount}
            onToggle={() => setFloatOpen(!floatOpen)} />
          {toast && <div className="dr-toast">{toast}</div>}
        </div>
        )}

      </div>
      </div>

      {tab !== "canvas" && (chatOpen
        ? <DrChatPanel onClose={() => setChatOpen(false)} context={chatContext} aiSegs={aiSegs} onRevert={revertSeg} appr={appr} />
        : <DrChatRail onExpand={() => setChatOpen(true)} />)}

      {director && <DrDirector key={director.nodeId || "stage"} empty={director.empty} name={director.name}
        onClose={closeDirector} onApply={closeDirector} />}
      {dlg && dlg.type === "add" && (
        <DrAddMenu at={dlg.at} onClose={() => setDlg(null)}
          onCreate={(kind) => { createNode(kind, dlg.at); setDlg(null); }}
          onImport={() => { setDlg(null); say("已上传"); }} />
      )}
      {dlg && dlg.type === "lib" && (
        <DrAssetPicker mode={dlg.mode} initialTab={dlg.tab}
          target={dlg.node && (dlg.mode === "input" || dlg.mode === "adopt") ? { cfg: dlg.node, label: labelOf(dlg.node) } : null}
          onClose={() => setDlg(null)}
          onPlace={(ids) => {
            const base = { x: (size.w / 2 - cam.x) / cam.k, y: (size.h / 2 - cam.y) / cam.k };
            setNodes((ns) => [...ns, ...ids.map((assetId, i) => ({ id: "n_" + assetId + "_" + i + Date.now(), kind: spAsset(assetId).type === "director" ? "director" : "asset",
              assetId, sceneId: "s2", x: base.x + i * 24, y: base.y + i * 96, w: 220, h: spAsset(assetId).type === "director" ? 112 : 84 }))]);
            setDlg(null);
          }}
          onFill={(assetId) => {
            // adopt:只改采用指针,不伪造任务、不自动标完成;fill:给空素材节点填内容。
            const patch = dlg.mode === "adopt" ? { adopted: assetId } : { assetId };
            setNodes((ns) => ns.map((n) => (n.id === dlg.node.id ? { ...n, ...patch } : n)));
            if (dlg.mode === "adopt") say(`已采用 ${spAsset(assetId).name} · 制作状态不自动改`);
            setDlg(null);
          }}
          onAddInput={(assetId, role) => {
            addInput(ensureAssetNode(assetId, dlg.node), dlg.node.id, assetId, role);
            setDlg(null);
          }} />
      )}
      {dlg && dlg.type === "role" && (
        <DrRolePopover at={dlg.at} asset={sourceOf(dlg.from).asset}
          target={{ cfg: dlg.to, label: labelOf(dlg.to) }}
          existing={edges.find((e) => e.to === dlg.to.id && (e.assetId || e.from) === (drIsGen(dlg.from) ? dlg.from.id : dlg.from.assetId))}
          onClose={() => setDlg(null)}
          onPick={(role) => {
            addInput(dlg.from.id, dlg.to.id, drIsGen(dlg.from) ? null : dlg.from.assetId, role);
            setSelectedId(dlg.to.id);
            setDlg(null);
          }} />
      )}
      {submitNode && (
        <DrSubmitDialog label={labelOf(submitNode)} cfg={submitNode} epStyle={epStyle} inputs={drInputsOf(edges, submitNode.id, nodes)}
          sample={!!dlg.sample} onClose={() => setDlg(null)} onConfirm={confirmSubmit} />
      )}
      {completeNode && completeTask && (
        <DrCompleteSampleDialog label={labelOf(completeNode)} cfg={completeNode} task={completeTask}
          n={tasks.filter((t) => t.source.id === completeNode.id).indexOf(completeTask) + 1}
          onClose={() => setDlg(dlg.back ? { type: dlg.back } : null)} onConfirm={confirmComplete} />
      )}
      {dlg && dlg.type === "export" && (
        <DrExportSamplesDialog rows={sampleRows} onClose={() => setDlg(null)} onExport={exportSegs}
          onComplete={(node, info) => setDlg({ type: "complete", nodeId: node.id, taskId: info.task.id, back: "export" })} />
      )}
      {permOpen && (
        <DrPermDialog rules={rules} onClose={() => setPermOpen(false)}
          onChange={(scope, cap, v) => setRules((r) => {
            const next = { ...r[scope] };
            if (v) next[cap] = v; else delete next[cap];
            return { ...r, [scope]: next };
          })} />
      )}
    </div>
  );
}

function DramaEntry() {
  return (
    <WindowFrame>
      <div className="m-app">
        <DramaProductionPage />
      </div>
    </WindowFrame>
  );
}

Object.assign(window, { DramaProductionPage, DramaEntry });
