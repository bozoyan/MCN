// MapStudio — 地图工作台。NavRail「世界观 · 地图」进入，接管编辑器第二至第四列：
// 地图列表 + 地点树 / 画布 / 制图师面板。
// 整张地图由图像模型一次画完，中文地名直接画进像素。生成后再从成图读取全部
// 地名（包括国家/区域）的文字中心，作为透明点击区的位置。读不到就标成
// 「这张图上没有」，不硬塞坐标。
//
// 调试入口：?screen=map 直达本页，?screen=map&state=empty 看还没有地图的空态。
//   工具栏最右的甲虫按钮可以切到空态。

const MS_STATE = {
  READY: "ready",         // 有地图，正常编辑
  EMPTY: "empty",         // 这张地图还没画
  GENERATING: "generating",
  REVIEW: "review",       // 出图完成，等作者采用或重来
};

const MS_ZOOM = { min: 60, max: 220, step: 20, fit: 100 };

function msLoc(list, id) {
  return list.find((l) => l.id === id) || null;
}
function msType(id) {
  return MS_LOCATION_TYPES.find((t) => t.id === id) || MS_LOCATION_TYPES[MS_LOCATION_TYPES.length - 1];
}
function msChildren(list, parentId) {
  return list.filter((l) => l.parentId === parentId);
}
// 一个地点是否已经落到当前地图上 = MapLocations 里有没有它那一行。
function msPlaced(pins, id) {
  return !!pins[id];
}

function msClock() {
  const d = new Date();
  return `今天 ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

// ---- 第二列：地图列表 + 地点树 -------------------------------------------

// 地图之间是父子关系：世界地图 → 区域图 → 城池图，对应 Location.meta.defaultChildMapId。
function MapListRow({ map, active, onOpen }) {
  const st = map.settings.version > 0;
  return (
    <button
      type="button"
      className={"m-ms-map" + (active ? " is-active" : "")}
      onClick={() => onOpen(map.id)}
    >
      <span className="m-ms-map__icon">
        <Icon name={map.type === "world" ? "globe" : map.type === "region" ? "mountains" : "city"} size={14} />
      </span>
      <span className="m-ms-map__meta">
        <span className="m-ms-map__name">{map.name}</span>
        <span className="m-ms-map__sub">
          {st ? `第 ${map.settings.version} 版 · ${map.stats.places} 个地点` : "还没画"}
        </span>
      </span>
      {!st && <span className="m-ms-map__flag">未画</span>}
    </button>
  );
}

function MapLocationTree({ locations, pins, selectedId, onSelect, query }) {
  const q = query.trim().toLowerCase();
  const match = (l) =>
    !q ||
    l.name.toLowerCase().includes(q) ||
    msType(l.type).label.toLowerCase().includes(q) ||
    (l.tags || []).some((t) => t.toLowerCase().includes(q));

  const renderNode = (loc, depth) => {
    const kids = msChildren(locations, loc.id);
    const rendered = kids.map((k) => renderNode(k, depth + 1)).filter(Boolean);
    if (!match(loc) && rendered.length === 0) return null;
    const placed = msPlaced(pins, loc.id);
    return (
      <React.Fragment key={loc.id}>
        <div
          className={"m-ms-node" + (selectedId === loc.id ? " is-active" : "")}
          style={{ paddingLeft: 8 + depth * 12 }}
          onClick={() => onSelect(loc.id)}
        >
          <Icon name={msType(loc.type).icon} size={14} />
          <span className="m-ms-node__name">{loc.name}</span>
          {placed ? (
            <Icon name="map-pin" size={11} className="m-ms-node__placed" />
          ) : (
            <span className="m-ms-node__todo">图上没有</span>
          )}
        </div>
        {rendered}
      </React.Fragment>
    );
  };

  return <div className="m-ms-tree">{msChildren(locations, "loc_world").map((l) => renderNode(l, 0))}</div>;
}

function MapRail({ maps, mapId, locations, pins, selectedId, onOpenMap, onSelect, novel, onBack }) {
  const [query, setQuery] = React.useState("");
  const unplaced = locations.filter((l) => !msPlaced(pins, l.id) && l.id !== "loc_world");

  return (
    <aside className="m-ctx">
      <PanelHeader onBack={onBack} onCollapse={() => {}} />
      <NovelSwitcher novel={novel} />

      <div className="m-ctx__sec-head">
        <span className="m-ctx__sec-title">地图</span>
        <span className="m-ctx__sec-count">{maps.length}</span>
        <button className="m-icon-btn m-icon-btn--ghost" title="新建地图">
          <Icon name="plus" size={12} />
        </button>
      </div>
      <div className="m-ms-maps">
        {maps.map((m) => (
          <MapListRow key={m.id} map={m} active={m.id === mapId} onOpen={onOpenMap} />
        ))}
      </div>

      <div className="m-ctx__sec-head" style={{ marginTop: 4 }}>
        <span className="m-ctx__sec-title">地点</span>
        <span className="m-ctx__sec-count">{locations.length - 1}</span>
      </div>
      <div className="m-ms-search">
        <Icon name="magnifying-glass" size={13} />
        <input
          className="m-ms-search__input"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="搜地点、类型或标签"
        />
      </div>

      <div className="m-ctx__list">
        <MapLocationTree
          locations={locations}
          pins={pins}
          selectedId={selectedId}
          onSelect={onSelect}
          query={query}
        />
        {unplaced.length > 0 && (
          <div className="m-ms-unplaced">
            <Icon name="info" size={12} />
            <span>
              还有 {unplaced.length} 个地点没画在这张图上。重画一张会把它们带上。
            </span>
          </div>
        )}
      </div>
    </aside>
  );
}

// ---- 第三列：画布 -------------------------------------------------------

function MapPin({ loc, pos, selected, hovered, onSelect, onHover }) {
  return (
    <div
      className={
        "m-ms-pin" +
        (selected ? " is-active" : "") +
        (hovered ? " is-hover" : "")
      }
      style={{ left: `${pos[0] * 100}%`, top: `${pos[1] * 100}%` }}
      onMouseEnter={() => onHover(loc.id)}
      onMouseLeave={() => onHover(null)}
      onClick={(e) => {
        e.stopPropagation();
        onSelect(loc.id);
      }}
      title={loc.name}
    >
      <span className="m-ms-pin__ring" />
    </div>
  );
}

// 生成中的占位：地图还没回来，先按目标比例留出画面，逐步推进四步管线。
function MapGenerating({ stage, spent, onStop }) {
  return (
    <div className="m-ms-overlay">
      <div className="m-ms-gen">
        <div className="m-ms-gen__sheen" />
        <div className="m-ms-gen__steps">
          {MS_STAGES.map((s, i) => (
            <div
              key={s.id}
              className={"m-ms-gen__step" + (i < stage ? " is-done" : i === stage ? " is-live" : "")}
            >
              <span className="m-ms-gen__mark">
                {i < stage ? <Icon name="check" size={11} /> : i === stage ? <Icon name="circle-notch" size={11} /> : null}
              </span>
              <span className="m-ms-gen__label">{s.label}</span>
              <span className="m-ms-gen__note">{s.note}</span>
            </div>
          ))}
        </div>
        <div className="m-ms-gen__foot">
          <span>已画 {spent} 张</span>
          <button className="m-btn m-btn--secondary m-btn--sm" type="button" onClick={onStop}>
            <Icon name="stop" size={13} />
            停止
          </button>
        </div>
      </div>
    </div>
  );
}

function MapEmpty({ onGenerate, onImport }) {
  return (
    <div className="m-ms-overlay">
      <div className="m-ms-empty">
        <span className="m-ms-empty__icon">
          <Icon name="map-trifold" size={22} />
        </span>
        <div className="m-ms-empty__title">这张地图还没画</div>
        <p className="m-ms-empty__body">
          制图师会读一遍世界观和地点，画出整张地图，地名直接写在画面上。
          画完之后各家疆域和图上的地点都能点。
        </p>
        <div className="m-ms-empty__acts">
          <button className="m-btn m-btn--primary m-btn--sm" type="button" onClick={onGenerate}>
            <Icon name="sparkle" size={14} />
            画一张地图
          </button>
          <button className="m-btn m-btn--secondary m-btn--sm" type="button" onClick={onImport}>
            <Icon name="image" size={14} />
            用我自己的图片
          </button>
        </div>
      </div>
    </div>
  );
}

// 出图并完成地点坐标识别后，确认这张要不要留。
function MapReview({ onApply, onRegen }) {
  return (
    <div className="m-ms-review">
      <span className="m-ms-review__icon">
        <Icon name="seal-check" size={16} />
      </span>
      <div className="m-ms-review__meta">
        <div className="m-ms-review__title">地图已画好</div>
        <div className="m-ms-review__note">
          图上认出了 15/16 个地点。采用后旧的那张仍留在版本记录里。
        </div>
      </div>
      <button className="m-btn m-btn--secondary m-btn--sm" type="button" onClick={onRegen}>
        <Icon name="arrow-clockwise" size={13} />
        重画一张
      </button>
      <button className="m-btn m-btn--primary m-btn--sm" type="button" onClick={onApply}>
        <Icon name="check" size={13} />
        采用这一张
      </button>
    </div>
  );
}

function MapDebug({ open, onOpen, onEmpty }) {
  return (
    <div className="m-ms-debug">
      <button
        className="m-icon-btn m-icon-btn--ghost"
        title="调试开关"
        onClick={() => onOpen(!open)}
      >
        <Icon name="bug-beetle" size={14} />
      </button>
      {open && (
        <div className="m-ms-debug__pop">
          <div className="m-ms-debug__label">调试状态</div>
          <button type="button" className="m-ms-debug__opt" onClick={onEmpty}>
            清空这张地图（看空态）
          </button>
        </div>
      )}
    </div>
  );
}

function MapCanvas({
  state, mapDoc, locations, pins, selectedId, hoverId, zoom, onZoom,
  onSelect, onHover,
  stage, spent, onStop, onGenerate, onImport, onApply, onRegen, debug,
}) {
  const stageRef = React.useRef(null);
  const hasImage = state !== MS_STATE.EMPTY && state !== MS_STATE.GENERATING;
  const hoverLoc = msLoc(locations, hoverId);

  return (
    <div className="m-editor">
      <div className="m-toolbar">
        <div className="m-segmented">
          <button className="m-segmented__item is-active" type="button">
            <Icon name="cursor-click" size={13} />
            选择
          </button>
          <button className="m-segmented__item" type="button" title="按住空格或中键也可拖动画布">
            <Icon name="arrows-out" size={13} />
            平移
          </button>
        </div>
        <span className="m-toolbar__spacer" />
        {hasImage && (
          <React.Fragment>
            <span className="m-ms-ver" title="这张地图的版本">
              第 {mapDoc.settings.version} 版 · {mapDoc.settings.style}
            </span>
            <span className="m-toolbar__sep" />
          </React.Fragment>
        )}
        <button className="m-icon-btn m-icon-btn--ghost" title="缩小" disabled={zoom <= MS_ZOOM.min}
          onClick={() => onZoom(Math.max(MS_ZOOM.min, zoom - MS_ZOOM.step))}>
          <Icon name="minus" size={14} />
        </button>
        <span className="m-ms-zoom">{zoom}%</span>
        <button className="m-icon-btn m-icon-btn--ghost" title="放大" disabled={zoom >= MS_ZOOM.max}
          onClick={() => onZoom(Math.min(MS_ZOOM.max, zoom + MS_ZOOM.step))}>
          <Icon name="plus" size={14} />
        </button>
        <button className="m-btn m-btn--text m-btn--sm" type="button" disabled={zoom === MS_ZOOM.fit}
          onClick={() => onZoom(MS_ZOOM.fit)}>
          适应画布
        </button>
        <span className="m-toolbar__sep" />
        <button className="m-btn m-btn--text m-btn--sm" type="button" disabled={!hasImage}>
          <Icon name="download-simple" size={14} />
          导出
        </button>
        <MapDebug {...debug} />
      </div>

      <div className="m-ms-stage" ref={stageRef}>
        <div
          className="m-ms-paper"
          style={{ width: `${zoom}%` }}
          onClick={() => onSelect(null)}
        >
          {hasImage && <img className="m-ms-paper__img" src={MS_MAP_IMAGE} alt="世界地图" draggable={false} />}
          {!hasImage && <div className="m-ms-paper__blank" />}

          {hasImage &&
            locations
              .filter((l) => pins[l.id])
              .map((l) => (
                <MapPin
                  key={l.id}
                  loc={l}
                  pos={pins[l.id]}
                  selected={selectedId === l.id}
                  hovered={hoverId === l.id}
                  onSelect={onSelect}
                  onHover={onHover}
                />
              ))}

          {state === MS_STATE.EMPTY && <MapEmpty onGenerate={onGenerate} onImport={onImport} />}
          {state === MS_STATE.GENERATING && <MapGenerating stage={stage} spent={spent} onStop={onStop} />}
        </div>
      </div>

      {state === MS_STATE.REVIEW && (
        <MapReview
          onApply={onApply}
          onRegen={onRegen}
        />
      )}

      <div className="m-ms-status">
        {hoverLoc ? (
          <span>
            {hoverLoc.name} · {msType(hoverLoc.type).label}
          </span>
        ) : null}
      </div>

    </div>
  );
}

// ---- 第四列：制图师面板（生成 / 地点） ----------------------------------

function MapGenerateTab({ novel, style, onStyle, size, onSize, extra, onExtra, sources, onSource,
  locations, promptOpen, onPromptOpen, prompt, busy, onGenerate }) {
  const regionCount = MS_REGIONS.length;
  const placeCount = locations.filter((l) => l.id !== "loc_world").length;

  return (
    <React.Fragment>
      <section className="m-ms-sec">
        <div className="m-ms-sec__head">
          <Icon name="book-open" size={14} color="var(--accent-warm)" />
          <span className="m-ms-sec__title">画什么</span>
        </div>
        <div className="m-ms-src">
          {[
            { id: "lore", label: "世界观设定", note: "12 条设定条目，取地理与气候那几条" },
            { id: "locations", label: "地点", note: `${regionCount} 个势力 / ${placeCount} 个地点` },
            { id: "routes", label: "地点关系", note: "5 条通路，决定道路怎么连" },
          ].map((s) => (
            <button
              key={s.id}
              type="button"
              className={"m-ms-src__row" + (sources[s.id] ? " is-on" : "")}
              onClick={() => onSource(s.id)}
            >
              <span className="m-ms-src__box">
                {sources[s.id] && <Icon name="check" size={10} />}
              </span>
              <span className="m-ms-src__meta">
                <span className="m-ms-src__label">{s.label}</span>
                <span className="m-ms-src__note">{s.note}</span>
              </span>
            </button>
          ))}
        </div>
        <div className="m-ms-note">勾上的内容会一起交给制图师。地名按原名写进画面。</div>
      </section>

      <section className="m-ms-sec">
        <div className="m-ms-sec__head">
          <Icon name="magic-wand" size={14} color="var(--accent-warm)" />
          <span className="m-ms-sec__title">画风</span>
        </div>
        <div className="m-ms-chips">
          {MS_STYLES.map((s) => (
            <button key={s} type="button" onClick={() => onStyle(s)}
              className={"m-chip" + (style === s ? " m-chip--brass" : "")}>
              {s}
            </button>
          ))}
        </div>
      </section>

      <section className="m-ms-sec">
        <div className="m-ms-sec__head">
          <Icon name="image-square" size={14} color="var(--accent-warm)" />
          <span className="m-ms-sec__title">尺寸</span>
        </div>
        <div className="m-ms-sizes">
          {MS_SIZES.map((s) => (
            <button key={s.id} type="button" onClick={() => onSize(s.id)}
              className={"m-ms-size" + (size === s.id ? " is-active" : "")}>
              <span className="m-ms-size__label">{s.label}</span>
              <span className="m-ms-size__px">{s.px}</span>
              <span className="m-ms-size__note">{s.note}</span>
            </button>
          ))}
        </div>
        <div className="m-ms-note">画得越大越慢。要放大看清地名就选 3K。</div>
      </section>

      <section className="m-ms-sec">
        <div className="m-ms-sec__head">
          <Icon name="note-pencil" size={14} color="var(--accent-warm)" />
          <span className="m-ms-sec__title">补充要求</span>
        </div>
        <textarea
          className="m-input m-ms-extra"
          rows={3}
          value={extra}
          onChange={(e) => onExtra(e.target.value)}
          placeholder="想强调的地貌、要避开的元素…"
        />
      </section>

      <section className="m-ms-sec">
        <div className="m-ms-sec__head">
          <Icon name="file-text" size={14} color="var(--accent-warm)" />
          <span className="m-ms-sec__title">提示词</span>
          <button className="m-ms-sec__link" type="button" onClick={() => onPromptOpen(!promptOpen)}>
            {promptOpen ? "收起" : "查看"}
          </button>
        </div>
        {promptOpen && <pre className="m-ms-prompt">{prompt}</pre>}
      </section>
    </React.Fragment>
  );
}

// 地点检查器：国家、区域与普通地点都走同一套字段。
function MapInspectorTab({ loc, locations, pins, onRename, onField, onPhotos, onOpenChildMap, onCreateChildMap }) {
  if (!loc) {
    return (
      <div className="m-ms-blank">
        <Icon name="cursor-click" size={18} />
        <div>在画面上点一个势力或地点</div>
        <p>没选中时这里显示这张地图的概况。</p>
        <div className="m-ms-blank__stats">
          <div>
            <span>势力</span>
            <strong>{MS_REGIONS.length}</strong>
          </div>
          <div>
            <span>图上的地点</span>
            <strong>{locations.filter((l) => pins[l.id]).length}</strong>
          </div>
          <div>
            <span>图上没有</span>
            <strong>{locations.filter((l) => !pins[l.id] && l.id !== "loc_world").length}</strong>
          </div>
        </div>
      </div>
    );
  }

  const parent = msLoc(locations, loc.parentId);
  const links = MS_CONNECTIONS.filter((c) => c.source === loc.id || c.target === loc.id);
  const childMap = loc.childMapId ? MS_MAPS.find((m) => m.id === loc.childMapId) : null;

  return (
    <React.Fragment>
      <section className="m-ms-sec">
        <div className="m-ms-sec__head">
          <Icon name={msType(loc.type).icon} size={14} color="var(--accent-warm)" />
          <span className="m-ms-sec__title">地点档案</span>
          <span className="m-ms-sec__from">世界观 · 地点</span>
        </div>
        <label className="m-ms-field">
          <span className="m-ms-field__label">名称</span>
          <input className="m-input" value={loc.name} onChange={(e) => onRename(loc.id, e.target.value)} />
        </label>
        <label className="m-ms-field">
          <span className="m-ms-field__label">类型</span>
          <select className="m-input" value={loc.type} onChange={(e) => onField(loc.id, "type", e.target.value)}>
            {MS_LOCATION_TYPES.map((t) => (
              <option key={t.id} value={t.id}>{t.label}</option>
            ))}
          </select>
        </label>
        <label className="m-ms-field">
          <span className="m-ms-field__label">上级</span>
          <select className="m-input" value={loc.parentId || ""} onChange={(e) => onField(loc.id, "parentId", e.target.value)}>
            {locations.filter((l) => l.id !== loc.id).map((l) => (
              <option key={l.id} value={l.id}>{l.name}</option>
            ))}
          </select>
        </label>
        <label className="m-ms-field">
          <span className="m-ms-field__label">描述</span>
          <textarea className="m-input" rows={2} value={loc.description}
            onChange={(e) => onField(loc.id, "description", e.target.value)} />
        </label>
        <div className="m-ms-field">
          <span className="m-ms-field__label">标签</span>
          <div className="m-ms-tags">
            {(loc.tags || []).map((t) => (
              <span key={t} className="m-tag">{t}</span>
            ))}
            <button className="m-chip" type="button">
              <Icon name="plus" size={11} />
              标签
            </button>
          </div>
        </div>
      </section>

      <MapLocationPhotos key={loc.id} photos={loc.photos || []} onChange={(next) => onPhotos(loc.id, next)} />

      <section className="m-ms-sec">
        <div className="m-ms-sec__head">
          <Icon name="path" size={14} color="var(--accent-warm)" />
          <span className="m-ms-sec__title">通路</span>
          <span className="m-ms-sec__count">{links.length}</span>
        </div>
        {links.length === 0 ? (
          <div className="m-ms-note">还没有与其他地点的通路。</div>
        ) : (
          links.map((c) => {
            const other = msLoc(locations, c.source === loc.id ? c.target : c.source);
            return (
              <div key={c.id} className="m-ms-link">
                <Icon name="arrow-right" size={12} />
                <span className="m-ms-link__name">{other ? other.name : "—"}</span>
                <span className="m-ms-link__meta">
                  {c.label} · {c.days} 天 · {c.difficulty}
                </span>
              </div>
            );
          })
        )}
        <div className="m-ms-note">通路记的是两地之间怎么走，画面上的道路是它画出来的样子。</div>
      </section>

      <section className="m-ms-sec">
        <div className="m-ms-sec__head">
          <Icon name="stack" size={14} color="var(--accent-warm)" />
          <span className="m-ms-sec__title">子地图</span>
        </div>
        {childMap ? (
          <button className="m-ms-child" type="button" onClick={() => onOpenChildMap(childMap.id)}>
            <Icon name={childMap.type === "region" ? "mountains" : "city"} size={14} />
            <span className="m-ms-child__name">{childMap.name}</span>
            <span className="m-ms-child__state">
              {childMap.settings.version > 0 ? `第 ${childMap.settings.version} 版` : "还没画"}
            </span>
            <Icon name="arrow-right" size={12} />
          </button>
        ) : (
          <button className="m-ms-child m-ms-child--new" type="button" onClick={() => onCreateChildMap(loc.id)}>
            <Icon name="plus" size={13} />
            为「{loc.name}」新建一张地图
          </button>
        )}
      </section>
    </React.Fragment>
  );
}

// 地点照片：增删、改名立即落库，不进「地点档案」的未保存判定。
// 照片条横向滚动；名称为空时显示「未命名」，点名称弹窗改名。
function MapLocationPhotos({ photos, onChange }) {
  const [renaming, setRenaming] = React.useState(null);
  const tints = ["#5E7A72", "#5E6E7D", "#6E6878", "#56685A"];

  function add() {
    onChange([...photos, { tint: tints[photos.length % tints.length], name: "" }]);
  }

  return (
    <section className="m-ms-sec">
      <div className="m-ms-sec__head">
        <Icon name="image-square" size={14} color="var(--accent-warm)" />
        <span className="m-ms-sec__title">照片</span>
        {photos.length > 0 && <span className="m-ms-sec__count">{photos.length}</span>}
      </div>
      <div className="m-ms-photos">
        {photos.map((p, i) => (
          <div key={i} className="m-ms-photo">
            <div className="m-ms-photo__img" style={{ background: p.tint }}>
              <button
                type="button"
                className="m-ms-photo__remove"
                title="移除照片"
                onClick={() => onChange(photos.filter((_, j) => j !== i))}
              >
                <Icon name="x" size={11} />
              </button>
            </div>
            <button
              type="button"
              className={"m-ms-photo__name" + (p.name ? "" : " is-empty")}
              title="重命名"
              onClick={() => setRenaming(i)}
            >
              {p.name || "未命名"}
            </button>
          </div>
        ))}
        <button type="button" className="m-ms-photo__add" onClick={add}>
          <Icon name="plus" size={16} />
          <span>添加</span>
        </button>
      </div>
      {renaming !== null && (
        <MapPhotoRenameDialog
          name={photos[renaming].name}
          onClose={() => setRenaming(null)}
          onSave={(name) => {
            onChange(photos.map((p, j) => (j === renaming ? { ...p, name: name.trim() } : p)));
            setRenaming(null);
          }}
        />
      )}
    </section>
  );
}

function MapPhotoRenameDialog({ name, onClose, onSave }) {
  const [value, setValue] = React.useState(name);
  return ReactDOM.createPortal(
    <div className="m-dialog-scrim">
      <div className="m-dialog m-dialog--confirm" role="dialog" aria-modal="true">
        <div className="m-taskform">
          <h2 className="m-heading" style={{ fontSize: 18 }}>重命名</h2>
          <label className="m-ms-field">
            <span className="m-ms-field__label">名称</span>
            <input
              className="m-input"
              autoFocus
              value={value}
              onChange={(e) => setValue(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && onSave(value)}
            />
          </label>
          <div className="m-taskform__actions">
            <button type="button" className="m-btn m-btn--text" onClick={onClose}>取消</button>
            <button type="button" className="m-btn m-btn--primary" onClick={() => onSave(value)}>保存</button>
          </div>
        </div>
      </div>
    </div>,
    document.body,
  );
}

function MapAssistant({ tab, onTab, selected, busy, onGenerate, onClose, genProps, inspectorProps }) {
  return (
    <aside className="m-agent m-ms-assistant">
      <div className="m-agent__head">
        <div className="m-agent__head-l">
          <span className="m-agent__head-icon">
            <Icon name="compass" size={16} />
          </span>
          <div className="m-agent__head-meta">
            <div className="m-agent__head-title">制图师</div>
            <div className="m-agent__head-sub">
              {busy ? "正在画…" : selected ? `选中 ${selected.name}` : "读一遍设定，画出整张地图"}
            </div>
          </div>
        </div>
        <div className="m-agent__head-r">
          <button className="m-icon-btn m-icon-btn--ghost" title="收起" onClick={onClose}>
            <Icon name="x" size={14} />
          </button>
        </div>
      </div>

      <div className="m-ms-tabs">
        {[
          { id: "generate", label: "生成" },
          { id: "inspector", label: "地点" },
        ].map((t) => (
          <button
            key={t.id}
            type="button"
            className={"m-ms-tab" + (tab === t.id ? " is-active" : "")}
            onClick={() => onTab(t.id)}
          >
            {t.label}
          </button>
        ))}
      </div>

      <div className="m-ms-assistant__scroll">
        {tab === "generate" ? <MapGenerateTab {...genProps} /> : <MapInspectorTab {...inspectorProps} />}
      </div>

      {tab === "generate" && (
        <div className="m-ms-assistant__foot">
          <button className="m-btn m-btn--primary" type="button" style={{ width: "100%" }}
            disabled={busy} onClick={onGenerate}>
            <Icon name="sparkle" size={16} />
            {busy ? "正在画…" : "画一张地图"}
          </button>
          <div className="m-ms-assistant__cost">
            一次只画一张，不满意再来。
          </div>
        </div>
      )}
    </aside>
  );
}

// ---- 组合 ---------------------------------------------------------------

function MapStudioView({ novel, onBack }) {
  // 深链：?screen=map&state=empty|generating|review 直接落到某一屏，
  // &sel=<地点 id> 打开检查器。评审时不用一步步点过去。
  const deep = React.useMemo(() => {
    const q = new URLSearchParams(window.location.search);
    return { state: q.get("state"), sel: q.get("sel") };
  }, []);

  const [mapId, setMapId] = React.useState("map_world");
  const [state, setState] = React.useState(
    Object.values(MS_STATE).includes(deep.state) ? deep.state : MS_STATE.READY
  );
  const [locations, setLocations] = React.useState(MS_LOCATIONS);
  // 位置来自生成，界面上不改它 —— 这里只读。
  const [pins] = React.useState(() => {
    const out = {};
    MS_LOCATIONS.forEach((l) => {
      if (l.pin) out[l.id] = l.pin.slice();
    });
    return out;
  });
  const [selectedId, setSelectedId] = React.useState(deep.sel || null);
  const [hoverId, setHoverId] = React.useState(null);
  const [zoom, setZoom] = React.useState(MS_ZOOM.fit);
  const [assistantOpen, setAssistantOpen] = React.useState(true);
  const [tab, setTab] = React.useState(deep.sel ? "inspector" : "generate");
  const [toast, setToast] = React.useState(null);

  // 生成参数
  const [style, setStyle] = React.useState(MS_STYLES[0]);
  const [size, setSize] = React.useState("3k");
  const [extra, setExtra] = React.useState("");
  const [sources, setSources] = React.useState({ lore: true, locations: true, routes: true });
  const [promptOpen, setPromptOpen] = React.useState(false);

  // 生成过程
  const [stage, setStage] = React.useState(deep.state === MS_STATE.GENERATING ? 3 : 0);
  const [spent, setSpent] = React.useState(deep.state === MS_STATE.GENERATING ? 1 : 0);
  const [debugOpen, setDebugOpen] = React.useState(false);
  const timers = React.useRef([]);

  React.useEffect(() => () => timers.current.forEach(clearTimeout), []);

  const say = (message) => setToast({ id: Date.now(), message });
  const mapDoc = MS_MAPS.find((m) => m.id === mapId) || MS_MAPS[0];
  const selected = selectedId ? msLoc(locations, selectedId) : null;
  const busy = state === MS_STATE.GENERATING;

  function select(id) {
    setSelectedId(id);
    if (id) setTab("inspector");
  }

  function renameLocation(id, name) {
    setLocations((list) => list.map((l) => (l.id === id ? { ...l, name } : l)));
  }
  function setField(id, key, value) {
    setLocations((list) => list.map((l) => (l.id === id ? { ...l, [key]: value } : l)));
  }

  // 生成：四步管线，只发一次图片请求。
  function generate() {
    if (busy) return;
    timers.current.forEach(clearTimeout);
    timers.current = [];
    setState(MS_STATE.GENERATING);
    setStage(0);
    setSpent(0);
    setSelectedId(null);
    MS_STAGES.forEach((s, i) => {
      timers.current.push(
        setTimeout(() => {
          setStage(i);
          if (s.cost) setSpent((n) => n + s.cost);
        }, 720 * i + 200)
      );
    });
    timers.current.push(
      setTimeout(() => {
        setState(MS_STATE.REVIEW);
        say("地图画好了，看看要不要采用");
      }, 720 * MS_STAGES.length + 400)
    );
  }

  function stopGenerate() {
    timers.current.forEach(clearTimeout);
    timers.current = [];
    setState(MS_STATE.EMPTY);
    say("已停止。已经画出来的那张仍会计费");
  }

  const prompt = [
    `绘制一张${style}风格的奇幻世界地图，横版${MS_SIZES.find((s) => s.id === size).px}。`,
    sources.locations
      ? `大陆上有四个势力：${MS_REGIONS.map((r) => msLoc(locations, r.locationId).name).join("、")}，各自占据一片相连但不重叠的疆域。`
      : "",
    sources.locations
      ? `标出城市与地标：${locations.filter((l) => pins[l.id]).map((l) => l.name).slice(0, 8).join("、")}。`
      : "",
    sources.routes ? "主要城市之间画出道路，海岸线沿用参考图的形状。" : "",
    sources.lore ? "北方常年封冻，南方是绿洲与商路，东方多山。" : "",
    "地名用中文楷体直接写在画面上，字要清楚、不要错字。",
    extra ? `补充：${extra}。` : "",
    "禁止：图框、水印、图例、比例尺、UI 元素。",
  ]
    .filter(Boolean)
    .join("\n");

  return (
    <React.Fragment>
      <MapRail
        maps={MS_MAPS}
        mapId={mapId}
        locations={locations}
        pins={pins}
        selectedId={selectedId}
        novel={novel}
        onBack={onBack}
        onOpenMap={(id) => {
          setMapId(id);
          setSelectedId(null);
          const m = MS_MAPS.find((x) => x.id === id);
          setState(m.settings.version > 0 ? MS_STATE.READY : MS_STATE.EMPTY);
          if (m.settings.version === 0) setTab("generate");
        }}
        onSelect={select}
        onDragStart={() => {}}
      />

      <MapCanvas
        state={state}
        mapDoc={mapDoc}
        locations={locations}
        pins={pins}
        selectedId={selectedId}
        hoverId={hoverId}
        zoom={zoom}
        onZoom={setZoom}
        onSelect={select}
        onHover={setHoverId}
        stage={stage}
        spent={spent}
        onStop={stopGenerate}
        onGenerate={generate}
        onImport={() => say("已用选中的图片作地图。图上有哪些地点还需要制图师认一遍")}
        onApply={() => {
          setState(MS_STATE.READY);
          say("已采用这张地图");
        }}
        onRegen={generate}
        debug={{
          open: debugOpen,
          onOpen: setDebugOpen,
          onEmpty: () => {
            setState(MS_STATE.EMPTY);
            setDebugOpen(false);
            setSelectedId(null);
          },
        }}
      />

      {assistantOpen ? (
        <MapAssistant
          tab={tab}
          onTab={setTab}
          selected={selected}
          busy={busy}
          onGenerate={generate}
          onClose={() => setAssistantOpen(false)}
          genProps={{
            novel, style, onStyle: setStyle, size, onSize: setSize, extra, onExtra: setExtra,
            sources, onSource: (id) => setSources((s) => ({ ...s, [id]: !s[id] })),
            locations, promptOpen, onPromptOpen: setPromptOpen, prompt, busy,
            onGenerate: generate,
          }}
          inspectorProps={{
            loc: selected, locations, pins,
            onRename: renameLocation,
            onField: setField,
            onPhotos: (id, photos) => setField(id, "photos", photos),
            onOpenChildMap: (id) => {
              setMapId(id);
              setSelectedId(null);
              const m = MS_MAPS.find((x) => x.id === id);
              setState(m.settings.version > 0 ? MS_STATE.READY : MS_STATE.EMPTY);
              setTab("generate");
            },
            onCreateChildMap: (id) => say(`已为「${msLoc(locations, id).name}」新建一张空地图`),
          }}
        />
      ) : (
        <button className="m-chat-fab" type="button" onClick={() => setAssistantOpen(true)} title="打开制图师">
          <Icon name="compass" size={18} />
        </button>
      )}

      {toast && (
        <div key={toast.id} className="m-ms-toast" onAnimationEnd={() => setToast(null)}>
          {toast.message}。
        </div>
      )}
    </React.Fragment>
  );
}

Object.assign(window, { MapStudioView });
