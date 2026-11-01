// grid.jsx — 制片页「列表」视图:画布上全部节点平铺成卡片网格,按类型筛选。
// 和画布读写同一批节点,不是第二份数据;点卡片回到画布并选中、定位这个节点。
// 排序:片段按成片顺序在前,其后视频、图片、素材、导演工程。还没有结果的视频 / 图片卡片上可以直接上传。
// 关联文件: drama/app.jsx, drama/board.jsx, drama/data.jsx, drama/drama.css

const DR_GRID_FILTERS = [
  { id: "all",   label: "全部" },
  { id: "seg",   label: "片段" },
  { id: "video", label: "视频" },
  { id: "image", label: "图片" },
  { id: "asset", label: "素材" },
];

function drGridKind(n) {
  if (drIsSeg(n)) return "seg";
  if (n.kind === "video" || n.kind === "image") return n.kind;
  return "asset";
}

function DrGridCard({ node, tasks, edges, onOpen, onUpload, taskActs }) {
  const kind = drGridKind(node);
  const gen = drIsGen(node);
  const asset = gen ? node.adopted && spAsset(node.adopted) : node.assetId && spAsset(node.assetId);
  const task = gen ? drLastTask(tasks, { type: "node", id: node.id }) : null;
  // 进行中的任务角标在画面上;失败提醒放底栏,和画布卡片同一套「状态 + 动作 + 关闭」。
  const ts = task && task.state !== "succeeded" && !DR_TASK_FAIL[task.state] ? SP_TASK_STATE[task.state] : null;
  const ratio = gen ? node.gen.ratio : "1:1";
  const model = gen ? drModel(node.gen.model) : null;
  const uses = edges.filter((e) => e.from === node.id).length;

  let badge;
  let title;
  let meta;
  if (kind === "seg") { badge = `段 ${drSegNo(node)}`; title = node.title; }
  else if (gen) { badge = node.kind === "image" ? "图片" : "视频"; title = node.title; }
  else if (node.kind === "director") { badge = "导演"; title = asset ? asset.name : "空布景"; }
  else { badge = DR_ASSET_TYPES[asset ? asset.type : node.mediaType].label; title = asset ? asset.name : "空素材"; }
  if (gen) {
    const parts = [node.uploaded ? "上传" : model.name];
    if (node.kind === "video") parts.push(drSecs(node.ms) ? `${drSecs(node.ms)}s` : "—");
    parts.push(node.kind === "image" ? `${node.gen.ratio} · ${node.gen.res}` : node.gen.ratio);
    if (node.style !== undefined) parts.push(drStyleOf(node, null).name);
    meta = parts.join(" · ");
  } else meta = asset ? asset.spec || asset.source : "还没有内容";

  return (
    <div className="dr-gcard" role="button" tabIndex={0} onClick={() => onOpen(node)}>
      <div className="dr-gcard__pv">
        {asset
          ? (asset.type === "audio" || asset.type === "director"
            ? (asset.type === "audio" ? <DrAssetThumb asset={asset} h={56} /> : <CvIcon name="cube" size={30} color="var(--dr-director)" />)
            : <DrFrame tone={asset.tone} ratio={gen ? ratio : (asset.spec && asset.spec.startsWith("1920") ? "16:9" : asset.spec && asset.spec.startsWith("720") ? "9:16" : "1:1")}
                h={124} figures={asset.char ? 1 : asset.type === "video" ? 2 : 0} play={asset.type === "video"} />)
          : gen
            ? <span onClick={(e) => e.stopPropagation()}><DrUploadSlot image={node.kind === "image"} w={node.kind === "image" ? 120 : 70} h={124} onUpload={() => onUpload(node)} /></span>
            : <CvIcon name={node.kind === "director" ? "cube" : DR_ASSET_TYPES[node.mediaType || "image"].icon} size={26} color="var(--text-subtle)" />}
        {ts && <span className={"dr-gcard__task dr-tstate dr-tstate--" + ts.tone}>{task.state === "running" ? `生成中 ${task.progress}%` : ts.label}</span>}
      </div>
      <div className="dr-gcard__body">
        <div className="dr-gcard__head">
          <span className={"dr-shotno" + (kind === "seg" ? "" : " dr-shotno--free")}>{badge}</span>
          <span className="dr-gcard__title">{title}</span>
        </div>
        <div className="dr-gcard__meta">{meta}</div>
        <div className="dr-gcard__foot">
          {kind === "seg" && (
            <span className={"dr-pstatus dr-pstatus--" + node.status}><span className="dr-pstatus__dot" />{DR_SEG_STATUS[node.status].label}</span>
          )}
          {task && DR_TASK_FAIL[task.state] && <DrTaskLine task={task} hasResult={!!asset} {...taskActs} />}
          {uses > 0 && <span className="dr-gcard__uses"><CvIcon name="flow-arrow" size={11} color="currentColor" />{uses}</span>}
        </div>
      </div>
    </div>
  );
}

function DrNodeGrid({ nodes, edges, tasks, onOpen, onUpload, onCreate, toast, taskActs }) {
  const [filter, setFilter] = React.useState("all");
  const rank = { seg: 0, video: 1, image: 2, asset: 3 };
  const segOrder = drOrderedSegs(nodes).map((n) => n.id);
  const sorted = [...nodes].sort((a, b) => {
    const ka = drGridKind(a);
    const kb = drGridKind(b);
    if (ka !== kb) return rank[ka] - rank[kb];
    if (ka === "seg") return segOrder.indexOf(a.id) - segOrder.indexOf(b.id);
    return 0;
  });
  const count = (id) => (id === "all" ? nodes.length : nodes.filter((n) => drGridKind(n) === id).length);
  const list = sorted.filter((n) => filter === "all" || drGridKind(n) === filter);
  return (
    <div className="dr-grid">
      <div className="dr-grid__bar">
        {DR_GRID_FILTERS.map((f) => (
          <button key={f.id} type="button" className={"dr-drawer__tab" + (filter === f.id ? " is-on" : "")} onClick={() => setFilter(f.id)}>
            {f.label}<span className="dr-grid__count">{count(f.id)}</span>
          </button>
        ))}
        <span className="cv-spacer" />
        <button type="button" className="cv-btn cv-btn--outline" onClick={onCreate}>
          <CvIcon name="plus" size={13} />添加节点
        </button>
      </div>
      <div className="dr-grid__scroll">
        <div className="dr-grid__cards">
          {list.map((n) => <DrGridCard key={n.id} node={n} tasks={tasks} edges={edges} onOpen={onOpen} onUpload={onUpload} taskActs={taskActs} />)}
        </div>
      </div>
      {toast && <div className="dr-toast">{toast}</div>}
    </div>
  );
}

Object.assign(window, { DrNodeGrid });
