// director.jsx — DrDirector:3D 导演台(全屏覆盖在画布之上)。
// 布局:左侧图标栏 + 面板(对象 / 角色 / 动作 / 机位 / 运镜),中央视口(导演视角 / 机位视角、
// 方向球、底部工具 dock + AI 布景输入条),右侧顶部常驻机位预览 + 选中对象属性,底部关键帧时间轴。
// 暂不放场景背景,视口里只有地面网格、角色和机位。
// 与同类导演台的差异(来自调研取舍):
//   · 导演工程挂在场次上(ScreenplayStagings),机位绑定该场的片段,画幅 / 时长跟随片段的生成配置
//   · 角色造型取自资产库里的角色图,不另建一套素材
//   · AI 布景点开是通用的 agent 会话悬浮窗,agent 直接改布景,每次修改记一版历史,可撤销 / 恢复
//   · 运镜 / 动作预设套用到时间轴选区,而不是固定从第 0 帧开始
//   · 录制预演 / 导出构图图总是登记一条新的图片 / 视频资产,冻结当时已保存的工程版本;
//     已经被片段当作输入的旧输出不受之后的布景修改影响
// 视口是手写的针孔投影 SVG,只为定交互与信息布局,不代表渲染实现。
// 关联文件: drama/data.jsx, drama/app.jsx, drama/drama.css

/* ---------------- 投影 ---------------- */
function drSub(a, b) { return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]; }
function drDot(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
function drCross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]; }
function drNorm(a) { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0] / l, a[1] / l, a[2] / l]; }

function drMakeProjector(eye, target, focal, W, H) {
  const f = drNorm(drSub(target, eye));
  const r = drNorm(drCross(f, [0, 1, 0]));
  const u = drCross(r, f);
  const P = (p) => {
    const d = drSub(p, eye);
    const depth = drDot(d, f);
    const zc = Math.max(0.05, depth);
    return { x: W / 2 + (focal * drDot(d, r)) / zc, y: H / 2 - (focal * drDot(d, u)) / zc, z: zc, behind: depth < 0.2 };
  };
  P.right = r;
  // 线段按近裁剪面截断:视角压低或拉近时,镜头背后的网格不会被投成乱线
  P.seg = (a, b) => {
    const da = drDot(drSub(a, eye), f);
    const db = drDot(drSub(b, eye), f);
    const near = 0.2;
    if (da < near && db < near) return null;
    const cut = (p, q, dp, dq) => p.map((v, i) => v + (q[i] - v) * ((near - dp) / (dq - dp)));
    return [P(da < near ? cut(a, b, da, db) : a), P(db < near ? cut(b, a, db, da) : b)];
  };
  return P;
}

// 导演视角 = 绕 target 的轨道相机:yaw 水平转角,pitch 俯角,dist 距离(米)
const DR_VIEW_HOME = { target: [2.1, 0.4, 3.0], yaw: 139.2, pitch: 34.5, dist: 10.6 };
function drOrbitEye(v) {
  const y = (v.yaw * Math.PI) / 180;
  const p = (v.pitch * Math.PI) / 180;
  return [v.target[0] + v.dist * Math.cos(p) * Math.sin(y), v.target[1] + v.dist * Math.sin(p),
    v.target[2] + v.dist * Math.cos(p) * Math.cos(y)];
}
const drPts = (arr) => arr.map((p) => `${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(" ");

// 关键帧线性插值
function drAt(keys, t) {
  if (t <= keys[0].t) return keys[0];
  for (let i = 1; i < keys.length; i++) {
    if (t <= keys[i].t) {
      const a = keys[i - 1];
      const b = keys[i];
      const s = (t - a.t) / (b.t - a.t);
      const out = { ...b };
      ["x", "z", "yaw", "h", "rx", "ry", "rz"].forEach((k) => {
        if (a[k] != null) out[k] = a[k] + (b[k] - a[k]) * s;
      });
      out.pose = s < 1 ? a.pose === "站" && b.pose === "走" ? "走" : a.pose : b.pose;
      return out;
    }
  }
  return keys[keys.length - 1];
}
function drYawDir(yaw) {
  const r = (yaw * Math.PI) / 180;
  return [Math.sin(r), 0, Math.cos(r)];
}

// 注视目标在 t 时刻的地面位置
function drTargetAt(id, t) {
  if (!id) return null;
  const a = DR_STAGE.actors.find((x) => x.id === id);
  return a ? drAt(a.keys, t) : null;
}
function drTargetName(id) {
  if (!id) return "无";
  return DR_STAGE.actors.find((x) => x.id === id).name;
}
// 旋转关键帧写入:当前时刻已有关键帧就改它,否则按插值补一帧(自动关键帧)
function drSetRot(keys, t, axis, v) {
  const hit = keys.find((k) => Math.abs(k.t - t) < 0.05);
  if (hit) return keys.map((k) => (k === hit ? { ...k, [axis]: v } : k));
  const cur = drAt(keys, t);
  return [...keys, { t: Math.round(t * 10) / 10, rx: cur.rx, ry: cur.ry, rz: cur.rz, [axis]: v }]
    .sort((a, b) => a.t - b.t);
}
const drDeg = (v) => ((Math.round(v) % 360) + 540) % 360 - 180;
// 机位在 t 时刻的位姿;设了注视目标时朝向由目标算出
function drCamAt(cam, lookAt, t) {
  const k = drAt(cam.keys, t);
  const tg = drTargetAt(lookAt, t);
  if (!tg) return k;
  return { ...k, yaw: (Math.atan2(tg.x - k.x, tg.z - k.z) * 180) / Math.PI };
}
const drCam = (id) => DR_STAGE.cameras.find((c) => c.id === id);
const drActor = (id) => DR_STAGE.actors.find((a) => a.id === id);
const drMove = (id) => DR_DIR_MOVES.find((m) => m.id === id);
const drAction = (id) => DR_ACTIONS.find((m) => m.id === id);
const drFmt = (s) => s.toFixed(1);

/* ---------------- 视口 ---------------- */
// mode: "free" 导演视角 / "camera" 某个机位的取景;pip 时只画取景内容,不画遮罩和标签。
// rots = 各角色的旋转关键帧;tool = "rotate" 时按住角色或它脚下的旋转环拖动即改 ry。
function DrViewport({ mode, camId, look, rots, t, selected, onSelect, size, pip, bare, tool, onRotate, view = DR_VIEW_HOME }) {
  const { w: W, h: H } = size;
  if (!W || !H) return null;
  if (bare) {
    const P0 = drMakeProjector(drOrbitEye(view), view.target, H * 0.95, W, H);
    const lines = [];
    for (let v = -6; v <= 13; v += 0.7) {
      lines.push([[v, 0, -6], [v, 0, 13]]);
      lines.push([[-6, 0, v], [13, 0, v]]);
    }
    return (
      <svg className="dr-vp__svg" width={W} height={H}>
        {lines.map(([a, b], i) => {
          const sg = P0.seg(a, b);
          return sg && <line key={i} x1={sg[0].x} y1={sg[0].y} x2={sg[1].x} y2={sg[1].y} className="dr-vp__grid" />;
        })}
      </svg>
    );
  }
  const st = DR_STAGE;
  const viewCam = drCam(camId);
  const camNow = drCamAt(viewCam, look[viewCam.id], t);

  let P;
  if (mode === "camera") {
    const eye = [camNow.x, camNow.h, camNow.z];
    const dir = drYawDir(camNow.yaw);
    const focal = pip ? (H * viewCam.lens) / 30 : (H * 0.92 * viewCam.lens) / 30;
    P = drMakeProjector(eye, [eye[0] + dir[0], eye[1] - 0.05, eye[2] + dir[2]], focal, W, H);
  } else {
    P = drMakeProjector(drOrbitEye(view), view.target, H * 0.95, W, H);
  }

  const { w: RW, d: RD } = st.room;
  const grid = [];
  for (let x = -6; x <= RW + 6; x += 0.7) grid.push([[x, 0, -6], [x, 0, RD + 6]]);
  for (let z = -6; z <= RD + 6; z += 0.7) grid.push([[-6, 0, z], [RW + 6, 0, z]]);

  const ahui = drActor("a_ahui");
  const actors = st.actors.map((a) => {
    const k = drAt(a.keys, t);
    const ry = drAt(rots[a.id], t).ry;
    const tall = k.pose === "坐" ? 1.15 : 1.6;
    const foot = P([k.x, 0, k.z]);
    const head = P([k.x, tall, k.z]);
    // 半径沿镜头右向量量,侧视时身体不会被压成一条线
    const rad = P([k.x + P.right[0] * 0.22, tall, k.z + P.right[2] * 0.22]);
    // 朝向:脚下一枚指向 ry 的三角
    const d = drYawDir(ry);
    const n = [d[2], 0, -d[0]];
    const nose = [[k.x + d[0] * 0.55, 0.01, k.z + d[2] * 0.55],
      [k.x + d[0] * 0.3 + n[0] * 0.12, 0.01, k.z + d[2] * 0.3 + n[2] * 0.12],
      [k.x + d[0] * 0.3 - n[0] * 0.12, 0.01, k.z + d[2] * 0.3 - n[2] * 0.12]].map(P);
    return { a, k, ry, foot, head, nose, r: Math.abs(rad.x - head.x) || 6 };
  }).filter((x) => !x.foot.behind && !x.head.behind).sort((p, q) => q.foot.z - p.foot.z);

  // 旋转环:地面上半径 0.9 m 的圆,手柄在当前朝向上
  const ringOf = (k, ry) => {
    const ring = Array.from({ length: 49 }, (_, i) => {
      const r = (i / 48) * Math.PI * 2;
      return P([k.x + Math.sin(r) * 0.9, 0.01, k.z + Math.cos(r) * 0.9]);
    });
    const d = drYawDir(ry);
    return { ring, handle: P([k.x + d[0] * 0.9, 0.01, k.z + d[2] * 0.9]) };
  };
  // 拖动手柄:取屏幕上与指针方向最接近的朝向,透视下也不会转反
  const dragRing = (e, id, k) => {
    e.stopPropagation();
    e.preventDefault();
    const svg = e.currentTarget.ownerSVGElement.getBoundingClientRect();
    const c = P([k.x, 0, k.z]);
    const cands = Array.from({ length: 72 }, (_, i) => {
      const yaw = i * 5 - 180;
      const d = drYawDir(yaw);
      const q = P([k.x + d[0], 0, k.z + d[2]]);
      return { yaw, ang: Math.atan2(q.y - c.y, q.x - c.x) };
    });
    const move = (ev) => {
      const ang = Math.atan2(ev.clientY - svg.top - c.y, ev.clientX - svg.left - c.x);
      const diff = (x) => Math.abs(Math.atan2(Math.sin(x - ang), Math.cos(x - ang)));
      onRotate(id, cands.reduce((m, x) => (diff(x.ang) < diff(m.ang) ? x : m)).yaw);
    };
    const up = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };

  const path = ahui.keys.map((k) => P([k.x, 0.02, k.z]));

  const frustum = (k, len) => {
    const o = [k.x, k.h, k.z];
    const half = 0.55;
    const d = drYawDir(k.yaw);
    const r = [d[2], 0, -d[0]];
    const c = [o[0] + d[0] * len, o[1], o[2] + d[2] * len];
    const corners = [[-1, 1], [1, 1], [1, -1], [-1, -1]].map(([sx, sy]) =>
      P([c[0] + r[0] * half * sx * len * 0.6, c[1] + sy * half * len * 0.5, c[2] + r[2] * half * sx * len * 0.6]));
    return { o: P(o), corners };
  };

  const isCam = mode === "camera";
  const frameW = H * 9 / 16 * 0.92;
  const frameH = H * 0.92;

  return (
    <svg className="dr-vp__svg" width={W} height={H}>
      {grid.map(([a, b], i) => {
        const sg = P.seg(a, b);
        return sg && <line key={i} x1={sg[0].x} y1={sg[0].y} x2={sg[1].x} y2={sg[1].y} className="dr-vp__grid" />;
      })}

      {!isCam && !path.some((p) => p.behind) && (
        <g>
          <polyline points={drPts(path)} className="dr-vp__path" />
          {ahui.keys.map((k, i) => (
            <g key={i}>
              <rect x={path[i].x - 5} y={path[i].y - 5} width={10} height={10}
                transform={`rotate(45 ${path[i].x} ${path[i].y})`} className="dr-vp__key" />
              <text x={path[i].x + 10} y={path[i].y + 16} className="dr-vp__keylabel">{k.t}s · {k.pose}</text>
            </g>
          ))}
        </g>
      )}

      {actors.map(({ a, k, ry, foot, head, nose, r }) => {
        const bodyW = r * 1.9;
        const on = selected === a.id;
        const rotating = !isCam && tool === "rotate";
        return (
          <g key={a.id} className={"dr-vp__actor" + (on ? " is-on" : "") + (rotating ? " is-rotate" : "")}
            onPointerDown={(e) => {
              e.stopPropagation();
              onSelect(a.id);
              if (rotating) dragRing(e, a.id, k);
            }}>
            <ellipse cx={foot.x} cy={foot.y} rx={bodyW * 0.8} ry={bodyW * 0.28} className="dr-vp__shadow" />
            {!isCam && <polygon points={drPts(nose)} style={{ fill: a.color }} className="dr-vp__nose" />}

            <rect x={foot.x - bodyW / 2} y={head.y + r * 1.2} width={bodyW}
              height={Math.max(4, foot.y - head.y - r * 1.2)} rx={bodyW / 2}
              style={{ fill: a.color }} className="dr-vp__body" />
            <circle cx={head.x} cy={head.y + r * 0.2} r={r * 0.95} style={{ fill: a.color }} className="dr-vp__body" />
            {!isCam && (
              <text x={head.x} y={head.y - r * 1.2} textAnchor="middle" className="dr-vp__name">{a.name}</text>
            )}
          </g>
        );
      })}

      {/* 旋转环画在角色之上,手柄不会被身体挡住 */}
      {!isCam && tool === "rotate" && actors.filter((x) => x.a.id === selected).map(({ a, k, ry }) => {
        const ring = ringOf(k, ry);
        return (
          <g key={a.id + "-ring"} className="dr-vp__ringg" onPointerDown={(e) => dragRing(e, a.id, k)}>
            <polyline points={drPts(ring.ring)} className="dr-vp__ringhit" />
            <polyline points={drPts(ring.ring)} className="dr-vp__ring" />
            <circle cx={ring.handle.x} cy={ring.handle.y} r={8} className="dr-vp__ringhandle" />
            <text x={ring.handle.x + 12} y={ring.handle.y + 4} className="dr-vp__ringlabel">{drDeg(ry)}°</text>
          </g>
        );
      })}

      {!isCam && st.cameras.map((c) => {
        const on = c.id === selected;
        const k0 = drCamAt(c, look[c.id], t);
        const f = frustum(k0, 1.1);
        if (f.o.behind || f.corners.some((p) => p.behind)) return null;
        const tg = drTargetAt(look[c.id], t);
        const tp = tg && P([tg.x, 1.3, tg.z]);
        return (
          <g key={c.id} className={"dr-vp__cam" + (on ? " is-on" : "")}
            onPointerDown={(e) => { e.stopPropagation(); onSelect(c.id); }}>
            {tp && on && <line x1={f.o.x} y1={f.o.y} x2={tp.x} y2={tp.y} className="dr-vp__look" />}
            {f.corners.map((p, i) => (
              <line key={i} x1={f.o.x} y1={f.o.y} x2={p.x} y2={p.y} className="dr-vp__frustum" />
            ))}
            <polygon points={drPts(f.corners)} className="dr-vp__frustum-face" />
            <rect x={f.o.x - 9} y={f.o.y - 6} width={18} height={12} rx={2} className="dr-vp__camicon" />
            <text x={f.o.x} y={f.o.y - 12} textAnchor="middle" className="dr-vp__name">{c.short}</text>
          </g>
        );
      })}

      {isCam && !pip && (
        <g>
          <path className="dr-vp__mask" fillRule="evenodd"
            d={`M0 0H${W}V${H}H0Z M${(W - frameW) / 2} ${(H - frameH) / 2}h${frameW}v${frameH}h${-frameW}Z`} />
          <rect x={(W - frameW) / 2} y={(H - frameH) / 2} width={frameW} height={frameH} className="dr-vp__frame" />
          <text x={(W - frameW) / 2 + 8} y={(H + frameH) / 2 - 10} className="dr-vp__framelabel">
            9:16 · {drVideoLabel(drNode(viewCam.seg))} · {t.toFixed(1)}s
          </text>
        </g>
      )}
    </svg>
  );
}

/* ---------------- 小件 ---------------- */
// 逐项关键帧按钮:on = 当前时刻有关键帧;anim = 有动画但当前不在关键帧上;off = 无动画
function DrKeyBtn({ state = "off", disabled, title }) {
  return (
    <button type="button" disabled={disabled} title={title}
      className={"dr-keybtn dr-keybtn--" + state}>
      <span className="dr-keybtn__d" />
    </button>
  );
}
function drKeyState(times, t) {
  if (times.length < 2) return "off";
  return times.some((x) => Math.abs(x - t) < 0.05) ? "on" : "anim";
}

// 下拉:点开列出选项,选中即关闭
function DrPick({ value, options, onChange, icon }) {
  const [open, setOpen] = React.useState(false);
  const cur = options.find((o) => o.value === value);
  return (
    <span className="dr-pick">
      <button type="button" className="dr-select dr-pick__btn" onClick={() => setOpen(!open)}>
        <span className="dr-pick__val">{icon && <CvIcon name={icon} size={12} />}{cur ? cur.label : "—"}</span>
        <CvIcon name="caret-down" size={11} color="var(--text-muted)" />
      </button>
      {open && (
        <span className="dr-pick__menu">
          {options.map((o) => (
            <button key={String(o.value)} type="button"
              className={"dr-pick__opt" + (o.value === value ? " is-on" : "")}
              onClick={() => { onChange(o.value); setOpen(false); }}>
              {o.swatch && <span className="dr-dl__swatch" style={{ background: o.swatch, width: 8, height: 8 }} />}
              {o.label}
            </button>
          ))}
        </span>
      )}
    </span>
  );
}

// 三轴数值输入:失焦或回车提交,提交的值落到当前时刻的关键帧上
function DrXyzInput({ values, onCommit, unit }) {
  return (
    <span className="dr-xyz dr-xyz--input">
      {["X", "Y", "Z"].map((ax, i) => (
        <label key={ax + values[i]} className="dr-xyz__cell">
          <span className="dr-xyz__ax">{ax}</span>
          <input type="text" inputMode="numeric" defaultValue={values[i]}
            onBlur={(e) => onCommit(i, Number(e.target.value) || 0)}
            onKeyDown={(e) => { if (e.key === "Enter") e.target.blur(); }} />
          {unit && <span className="dr-xyz__unit">{unit}</span>}
        </label>
      ))}
    </span>
  );
}

// 预设套用目标:选中的对象 + 时间轴选区
function DrTarget({ name, color, icon, range }) {
  return (
    <div className="dr-target">
      <span className="dr-target__lbl">应用到</span>
      {color && <span className="dr-dl__swatch" style={{ background: color, width: 8, height: 8 }} />}
      {icon && <CvIcon name={icon} size={12} />}
      <span className="dr-target__name">{name}</span>
      <span className="dr-target__range">{drFmt(range.a)}–{drFmt(range.b)}s</span>
    </div>
  );
}

/* ---------------- 左栏 ---------------- */
const DR_DIR_TABS = [
  { id: "objects", label: "对象", icon: "tree-structure" },
  { id: "actors",  label: "角色", icon: "user" },
  { id: "actions", label: "动作", icon: "person-simple-walk" },
  { id: "cameras", label: "机位", icon: "video-camera" },
  { id: "moves",   label: "运镜", icon: "path" },
];
const DR_CAM_PRESETS = [
  "当前视角", "正面中景", "正面特写", "侧面近景", "过肩 · 左", "过肩 · 右",
  "45° 俯拍", "低角度仰拍", "鸟瞰", "荷兰角",
];

function DrObjRow({ icon, color, name, sub, on, hidden, locked, onClick }) {
  return (
    <div className={"dr-obj" + (on ? " is-on" : "") + (hidden ? " is-hidden" : "")} onClick={onClick}>
      {color ? <span className="dr-dl__swatch" style={{ background: color, width: 9, height: 9 }} />
        : <CvIcon name={icon} size={13} />}
      <span className="dr-obj__name">{name}</span>
      {sub && <span className="dr-obj__sub">{sub}</span>}
      <span className="dr-obj__tools">
        <CvIcon name={hidden ? "eye-slash" : "eye"} size={13} />
        <CvIcon name="lock-simple" size={13} style={{ opacity: locked ? 1 : 0.35 }} />
      </span>
    </div>
  );
}

function DrDirLeft({ tab, setTab, selected, onSelect, range, acts, moves, onApplyAct, onApplyMove }) {
  const st = DR_STAGE;
  const [actGroup, setActGroup] = React.useState("all");
  const selActor = drActor(selected);
  const selCam = drCam(selected);
  const coverAt = (segs) => segs.find((s) => s.a <= range.a + 0.01 && s.b >= range.b - 0.01);
  return (
    <div className="dr-dl">
      <nav className="dr-dl__rail">
        {DR_DIR_TABS.map((t) => (
          <button key={t.id} type="button"
            className={"dr-dl__tab" + (tab === t.id ? " is-on" : "")} onClick={() => setTab(t.id)}>
            <CvIcon name={t.icon} size={17} />
            <span className="dr-dl__tablbl">{t.label}</span>
          </button>
        ))}
      </nav>
      <div className="dr-dl__panel">
        {tab === "objects" && (
          <React.Fragment>
            <div className="dr-dl__search"><CvIcon name="magnifying-glass" size={12} />搜索对象</div>
            <div className="dr-dl__title">角色</div>
            {st.actors.map((a) => (
              <DrObjRow key={a.id} color={a.color} name={a.name} on={selected === a.id}
                onClick={() => onSelect(a.id)} />
            ))}
            <div className="dr-dl__title" style={{ marginTop: 12 }}>机位</div>
            {st.cameras.map((c) => (
              <DrObjRow key={c.id} icon="video-camera" name={c.short} sub={drVideoLabel(drNode(c.seg))}
                on={selected === c.id} onClick={() => onSelect(c.id)} />
            ))}
          </React.Fragment>
        )}

        {tab === "actors" && (
          <React.Fragment>
            <div className="dr-dl__title">角色</div>
            {st.actors.map((a) => {
              const look = drNode(a.look);
              return (
                <button key={a.id} type="button"
                  className={"dr-dl__item" + (selected === a.id ? " is-on" : "")} onClick={() => onSelect(a.id)}>
                  <span className="dr-dl__swatch" style={{ background: a.color }} />
                  <span className="dr-dl__itemtext">
                    <span>{a.name}</span>
                    <span className="dr-dl__itemsub">{look.title.split(" · ")[1]} · {a.keys.length} 个关键帧</span>
                  </span>
                </button>
              );
            })}
            <button type="button" className="cv-btn cv-btn--outline" style={{ marginTop: 8, width: "100%" }}>
              <CvIcon name="plus" size={13} />从画布造型添加
            </button>
          </React.Fragment>
        )}

        {tab === "actions" && (
          <React.Fragment>
            {selActor
              ? <DrTarget name={selActor.name} color={selActor.color} range={range} />
              : <div className="dr-target is-empty">选中一个角色</div>}
            <div className="dr-chips">
              {[{ id: "all", label: "全部" }, ...DR_ACTION_GROUPS].map((g) => (
                <button key={g.id} type="button" className={"dr-chip" + (actGroup === g.id ? " is-on" : "")}
                  onClick={() => setActGroup(g.id)}>{g.label}</button>
              ))}
            </div>
            <div className="dr-aiact">
              <CvIcon name="sparkle" size={13} color="var(--accent-warm)" />
              <span className="dr-aiact__input">描述动作，如「扶着舱壁慢慢走」</span>
              <button type="button" className="cv-btn cv-btn--outline dr-aiact__go">生成</button>
            </div>
            {DR_ACTION_GROUPS.filter((g) => actGroup === "all" || actGroup === g.id).map((g) => {
              const cur = selActor && coverAt(acts[selActor.id]);
              return (
                <React.Fragment key={g.id}>
                  <div className="dr-dl__title" style={{ marginTop: 10 }}>{g.label}</div>
                  <div className="dr-acts">
                    {DR_ACTIONS.filter((m) => m.group === g.id).map((m) => (
                      <button key={m.id} type="button" disabled={!selActor}
                        className={"dr-act" + (cur && cur.act === m.id ? " is-on" : "")}
                        onClick={() => onApplyAct(selActor.id, m.id)}>
                        <CvIcon name={m.moving ? "person-simple-walk" : "user"} size={14} />
                        {m.label}
                      </button>
                    ))}
                  </div>
                </React.Fragment>
              );
            })}
          </React.Fragment>
        )}

        {tab === "cameras" && (
          <React.Fragment>
            <div className="dr-dl__title">机位</div>
            {st.cameras.map((c) => {
              const seg = drNode(c.seg);
              return (
                <button key={c.id} type="button"
                  className={"dr-dl__item" + (selected === c.id ? " is-on" : "")} onClick={() => onSelect(c.id)}>
                  <CvIcon name="video-camera" size={14} />
                  <span className="dr-dl__itemtext">
                    <span>{c.name}</span>
                    <span className="dr-dl__itemsub">{drVideoLabel(seg)} · {c.lens}mm</span>
                  </span>
                </button>
              );
            })}
            <div className="dr-dl__title" style={{ marginTop: 14 }}>添加机位</div>
            <div className="dr-dl__presets">
              {DR_CAM_PRESETS.map((p) => (
                <button key={p} type="button" className="dr-dl__preset">
                  <CvIcon name="video-camera" size={15} />{p}
                </button>
              ))}
            </div>
          </React.Fragment>
        )}

        {tab === "moves" && (
          <React.Fragment>
            {selCam
              ? <DrTarget name={selCam.short} icon="video-camera" range={range} />
              : <div className="dr-target is-empty">选中一个机位</div>}
            {DR_DIR_MOVE_GROUPS.map((g) => {
              const cur = selCam && coverAt(moves[selCam.id]);
              return (
                <React.Fragment key={g.id}>
                  <div className="dr-dl__title" style={{ marginTop: 10 }}>{g.label}</div>
                  <div className="dr-presets2">
                    {DR_DIR_MOVES.filter((m) => m.group === g.id).map((m) => (
                      <button key={m.id} type="button" disabled={!selCam}
                        className={"dr-preset2" + (cur && cur.move === m.id ? " is-on" : "")}
                        onClick={() => onApplyMove(selCam.id, m.id)}>
                        <span className="dr-preset2__head">
                          <span className={"dr-move__glyph dr-move__glyph--" + m.base} />
                          <span className="dr-preset2__name">{m.label}</span>
                          <span className="dr-preset2__base">
                            {DR_CAMERA_MOVES.find((b) => b.id === m.base).label}
                          </span>
                        </span>
                        <span className="dr-preset2__desc">{m.desc}</span>
                      </button>
                    ))}
                  </div>
                </React.Fragment>
              );
            })}
          </React.Fragment>
        )}

      </div>
    </div>
  );
}

/* ---------------- 右栏 ---------------- */
function DrPip({ camId, setCamId, look, rots, t }) {
  const st = DR_STAGE;
  const cam = drCam(camId);
  const PH = 210;
  const FH = PH;
  const FW = Math.round((FH * 9) / 16);
  return (
    <div className="dr-pip">
      <div className="dr-pip__head">
        <span className="dr-dr__sub" style={{ margin: 0 }}>机位预览</span>
        <span className="cv-spacer" />
        <DrSeg value={camId} onChange={setCamId}
          options={st.cameras.map((c) => ({ value: c.id, label: c.short }))} />
      </div>
      <div className="dr-pip__box" style={{ height: PH }}>
        <div className="dr-pip__frame" style={{ width: FW, height: FH }}>
          <DrViewport mode="camera" camId={camId} look={look} rots={rots} t={t} selected={null}
            onSelect={() => {}} size={{ w: FW, h: FH }} pip />
        </div>
        <span className="dr-pip__lbl">{drVideoLabel(drNode(cam.seg))} · 9:16</span>
        <span className="dr-pip__time">{t.toFixed(1)}s</span>
      </div>
    </div>
  );
}

function DrCamProps({ cam, look, setLook, moves, t, onGoMoves, onRegenShot }) {
  const st = DR_STAGE;
  const seg = drNode(cam.seg);
  const now = drCamAt(cam, look, t);
  const times = cam.keys.map((k) => k.t);
  const exports = st.exports.filter((x) => x.camera === cam.id).slice().reverse();
  const curMove = moves.find((m) => t >= m.a && t <= m.b) || moves[0];
  const mv = curMove && drMove(curMove.move);
  const lookOpts = [{ value: null, label: "无 · 按朝向关键帧" },
    ...st.actors.map((a) => ({ value: a.id, label: a.name, swatch: a.color }))];
  return (
    <React.Fragment>
      <div className="dr-dr__title"><CvIcon name="video-camera" size={14} />{cam.name}</div>
      <label className="dr-field"><span className="dr-field__label">片段</span>
        <DrSelect value={`${drVideoLabel(seg)} · ${seg.title}`} /></label>
      <div className="dr-grid2">
        <label className="dr-field"><span className="dr-field__label">时长</span>
          <span className="dr-static">{st.duration.toFixed(1)} 秒</span></label>
        <label className="dr-field"><span className="dr-field__label">画幅</span>
          <span className="dr-static">9:16</span></label>
      </div>
      <label className="dr-field"><span className="dr-field__label">片段提示词</span>
        <span className="dr-intent">{spPromptPlain(seg.prompt)}</span></label>

      <div className="dr-dr__sub">变换</div>
      <div className="dr-krow">
        <span className="dr-krow__lbl">位置</span>
        <span className="dr-xyz">{[now.x, now.h, now.z].map((v, i) => <span key={i}>{v.toFixed(1)}</span>)}</span>
        <DrKeyBtn state="off" title="位置关键帧" />
      </div>
      <div className="dr-krow">
        <span className="dr-krow__lbl">朝向</span>
        <span className={"dr-static dr-krow__val" + (look ? " is-driven" : "")}>
          {look && <CvIcon name="crosshair-simple" size={12} />}{now.yaw.toFixed(0)}°
        </span>
        <DrKeyBtn state={look ? "off" : drKeyState(times, t)} disabled={!!look} title="朝向关键帧" />
      </div>
      <div className="dr-krow">
        <span className="dr-krow__lbl">焦距</span>
        <span className="dr-static dr-krow__val">{cam.lens} mm</span>
        <DrKeyBtn state="off" title="焦距关键帧" />
      </div>

      <label className="dr-field"><span className="dr-field__label">注视目标</span>
        <DrPick value={look} options={lookOpts} onChange={setLook} icon="crosshair-simple" /></label>

      <label className="dr-field"><span className="dr-field__label">运镜</span>
        <button type="button" className="dr-select dr-movebtn" onClick={onGoMoves}>
          <span className="dr-pick__val">
            {mv && <span className={"dr-move__glyph dr-move__glyph--" + mv.base} />}
            {mv ? mv.label : "—"}
            {curMove && <span className="dr-movebtn__range">{drFmt(curMove.a)}–{drFmt(curMove.b)}s</span>}
          </span>
          <CvIcon name="caret-right" size={11} color="var(--text-muted)" />
        </button>
      </label>

      <button type="button" className="cv-btn cv-btn--outline dr-dr__wide"><CvIcon name="video-camera" size={13} />机位对齐当前视图</button>
      <button type="button" className="cv-btn cv-btn--outline dr-dr__wide" onClick={onRegenShot}>
        <CvIcon name="sparkle" size={13} />AI 重排这一段
      </button>

      {exports.length > 0 && <div className="dr-dr__sub">导出版本</div>}
      {exports.map((x) => (
        <div key={x.id} className="dr-ver">
          <DrFrame tone="lamp" w={34} figures={0} play={x.kind === "motion"} />
          <span className="dr-ver__text">
            <span className="dr-ver__name">{x.kind === "motion" ? "预演" : "静帧"} v{x.v}{x.current && <span className="dr-ver__cur">当前</span>}</span>
            <span className="dr-ver__sub">{x.at}{x.usedBy.length ? ` · ${x.usedBy.map((id) => drVideoLabel(drNode(id))).join("、")} 作为输入` : " · 未被使用"}</span>
          </span>
        </div>
      ))}
    </React.Fragment>
  );
}

function DrActorProps({ actor, acts, rots, setRot, t, range, onPickSeg, onGoActions }) {
  const now = drAt(actor.keys, t);
  const times = actor.keys.map((k) => k.t);
  const rot = drAt(rots, t);
  return (
    <React.Fragment>
      <div className="dr-dr__title">
        <span className="dr-dl__swatch" style={{ background: actor.color }} />{actor.name}
      </div>
      <label className="dr-field"><span className="dr-field__label">造型</span>
        <DrSelect value={drNode(actor.look).title} /></label>

      <div className="dr-dr__sub">变换</div>
      <div className="dr-krow">
        <span className="dr-krow__lbl">位置</span>
        <span className="dr-xyz">{[now.x, 0, now.z].map((v, i) => <span key={i}>{v.toFixed(1)}</span>)}</span>
        <DrKeyBtn state={drKeyState(times, t)} title="位置关键帧" />
      </div>
      <div className="dr-krow">
        <span className="dr-krow__lbl">旋转</span>
        <DrXyzInput values={[rot.rx, rot.ry, rot.rz].map(drDeg)} unit="°"
          onCommit={(i, v) => setRot(["rx", "ry", "rz"][i], drDeg(v))} />
        <DrKeyBtn state={drKeyState(rots.map((k) => k.t), t)} title="旋转关键帧" />
      </div>

      <div className="dr-dr__sub">动作片段</div>
      <div className="dr-segs">
        {acts.map((s, i) => {
          const live = t >= s.a && t < s.b;
          const picked = Math.abs(range.a - s.a) < 0.01 && Math.abs(range.b - s.b) < 0.01;
          return (
            <button key={i} type="button"
              className={"dr-segrow" + (picked ? " is-on" : "") + (live ? " is-live" : "")}
              onClick={() => onPickSeg(s)}>
              <CvIcon name={drAction(s.act).moving ? "person-simple-walk" : "user"} size={12} />
              <span className="dr-segrow__name">{drAction(s.act).label}</span>
              <span className="dr-segrow__range">{drFmt(s.a)}–{drFmt(s.b)}s</span>
            </button>
          );
        })}
      </div>
      <button type="button" className="cv-btn cv-btn--outline dr-dr__wide" onClick={onGoActions}>
        <CvIcon name="plus" size={13} />从动作库添加
      </button>
    </React.Fragment>
  );
}

function DrDirRight({ selected, viewCam, setViewCam, look, setLook, acts, moves, rots, setRot, t, range, onPickSeg, setTab, onRegenShot }) {
  const actor = drActor(selected);
  const cam = drCam(selected);
  return (
    <div className="dr-dr">
      <DrPip camId={viewCam} setCamId={setViewCam} look={look} rots={rots} t={t} />
      <div className="dr-dr__body">
        {actor && (
          <DrActorProps actor={actor} acts={acts[actor.id]} rots={rots[actor.id]}
            setRot={(axis, v) => setRot(actor.id, axis, v)} t={t} range={range}
            onPickSeg={(s) => onPickSeg(actor.id, s)} onGoActions={() => setTab("actions")} />
        )}
        {cam && (
          <DrCamProps cam={cam} look={look[cam.id]} setLook={(v) => setLook(cam.id, v)}
            moves={moves[cam.id]} t={t} onGoMoves={() => setTab("moves")} onRegenShot={onRegenShot} />
        )}
      </div>
    </div>
  );
}

/* ---------------- 时间轴 ---------------- */
function DrSequencer({ t, setT, playing, setPlaying, selected, onSelect, range, onPickSeg, look, acts, moves, rots }) {
  const st = DR_STAGE;
  const D = st.duration;
  const pct = (s) => `${(s / D) * 100}%`;
  const seek = (ev) => {
    const r = ev.currentTarget.getBoundingClientRect();
    setT(Math.max(0, Math.min(D, ((ev.clientX - r.left) / r.width) * D)));
  };

  const rows = [];
  st.cameras.filter((c) => c.id === "cam_pan").forEach((c) => {
    rows.push({ id: c.id, owner: c.id, label: c.short, head: true, icon: "video-camera" });
    rows.push({ id: c.id + "-move", owner: c.id, label: "运镜", sub: true,
      segs: moves[c.id].map((m) => ({ ...m, name: drMove(m.move).label, kind: "move" })) });
    rows.push(look[c.id]
      ? { id: c.id + "-yaw", owner: c.id, label: "朝向", sub: true, value: `${drCamAt(c, look[c.id], t).yaw.toFixed(0)}°`,
          driven: `注视 · ${drTargetName(look[c.id])}` }
      : { id: c.id + "-yaw", owner: c.id, label: "朝向", sub: true, value: `${drAt(c.keys, t).yaw.toFixed(0)}°`,
          keys: c.keys.map((k) => k.t) });
  });
  // 展开的角色排在前面,收起的角色只占一行
  [...st.actors].sort((x, y) => (y.id === "a_ahui") - (x.id === "a_ahui")).forEach((a) => {
    const open = a.id === "a_ahui";
    rows.push({ id: a.id, owner: a.id, label: a.name, head: true, color: a.color, open,
      segs: open ? null : acts[a.id].map((s) => ({ ...s, name: drAction(s.act).label, kind: "act" })) });
    if (open) {
      rows.push({ id: a.id + "-pos", owner: a.id, label: "位置", sub: true,
        value: (() => { const k = drAt(a.keys, t); return `${k.x.toFixed(1)}, ${k.z.toFixed(1)}`; })(),
        keys: a.keys.map((k) => k.t) });
      rows.push({ id: a.id + "-rot", owner: a.id, label: "旋转", sub: true,
        value: `${drDeg(drAt(rots[a.id], t).ry)}°`, keys: rots[a.id].map((k) => k.t) });
      rows.push({ id: a.id + "-act", owner: a.id, label: "动作", sub: true,
        segs: acts[a.id].map((s) => ({ ...s, name: drAction(s.act).label, kind: "act", moving: drAction(s.act).moving })) });
    }
  });

  // 关键帧跳转:选中对象的全部关键帧时刻
  const selKeys = (() => {
    const c = drCam(selected);
    const a = drActor(selected);
    const ts = c ? c.keys.map((k) => k.t) : a ? [...a.keys, ...rots[a.id]].map((k) => k.t) : [];
    return [...new Set(ts)].sort((x, y) => x - y);
  })();
  const jump = (dir) => {
    const next = dir > 0 ? selKeys.find((k) => k > t + 0.01) : [...selKeys].reverse().find((k) => k < t - 0.01);
    if (next != null) setT(next);
  };

  return (
    <div className="dr-seq">
      <div className="dr-seq__bar">
        <div className="dr-seq__ctl">
          <button type="button" className="dr-seq__btn" title="上一关键帧" onClick={() => jump(-1)}>
            <CvIcon name="skip-back" size={12} />
          </button>
          <button type="button" className="dr-seq__btn" onClick={() => setPlaying(!playing)}>
            <CvIcon name={playing ? "pause" : "play"} size={13} />
          </button>
          <button type="button" className="dr-seq__btn" title="下一关键帧" onClick={() => jump(1)}>
            <CvIcon name="skip-forward" size={12} />
          </button>
          <span className="dr-seq__time">{t.toFixed(2)}s</span>
          <span className="dr-seq__time is-dim">{D.toFixed(2)}s</span>
          <span className="cv-spacer" />
          <button type="button" className="dr-seq__tool"><CvIcon name="plus" size={12} />新建轨道</button>
        </div>
        <div className="dr-seq__ruler" onPointerDown={seek}>
          <span className="dr-seq__range" style={{ left: pct(range.a), width: pct(range.b - range.a) }} />
          {Array.from({ length: D + 1 }).map((_, i) => (
            <span key={i} className="dr-seq__tick" style={{ left: pct(i) }}>{i % 2 === 0 ? `${i}s` : ""}</span>
          ))}
          <span className="dr-seq__head" style={{ left: pct(t) }} />
        </div>
      </div>
      <div className="dr-seq__rows">
        {rows.map((r) => (
          <div key={r.id} className={"dr-seq__row" + (r.head ? " is-head" : "") + (r.sub ? " is-sub" : "")
            + (r.owner === selected ? " is-sel" : "")}>
            <div className="dr-seq__label" onClick={() => onSelect(r.owner)}>
              {r.head && <CvIcon name={r.open || r.icon ? "caret-down" : "caret-right"} size={10} />}
              {r.color && <span className="dr-dl__swatch" style={{ background: r.color, width: 8, height: 8 }} />}
              {r.icon && <CvIcon name={r.icon} size={12} />}
              <span>{r.label}</span>
              {r.value && <span className="dr-seq__value">{r.value}</span>}
            </div>
            <div className="dr-seq__lane" onPointerDown={seek}>
              <span className="dr-seq__rangebg" style={{ left: pct(range.a), width: pct(range.b - range.a) }} />
              {r.driven && (
                <span className="dr-seq__driven" style={{ left: 0, width: "100%" }}>
                  <CvIcon name="crosshair-simple" size={10} />{r.driven}
                </span>
              )}
              {r.segs && r.segs.map((s, i) => {
                const picked = Math.abs(range.a - s.a) < 0.01 && Math.abs(range.b - s.b) < 0.01 && r.owner === selected;
                return (
                  <span key={i}
                    className={"dr-seq__seg dr-seq__seg--" + (s.kind === "move" ? "cam" : s.moving ? "move" : "hold")
                      + (picked ? " is-on" : "")}
                    style={{ left: pct(s.a), width: pct(s.b - s.a) }}
                    onPointerDown={(e) => { e.stopPropagation(); onPickSeg(r.owner, s); }}>
                    {s.kind === "move" && <span className={"dr-move__glyph dr-move__glyph--" + drMove(s.move).base} />}
                    {s.name}
                  </span>
                );
              })}
              {r.keys && r.keys.map((k) => (
                <span key={k} className="dr-seq__key" style={{ left: pct(k) }} />
              ))}
              {r.keys && r.keys.length > 1 && (
                <span className="dr-seq__span" style={{ left: pct(r.keys[0]), width: pct(r.keys[r.keys.length - 1] - r.keys[0]) }} />
              )}
              <span className="dr-seq__playline" style={{ left: pct(t) }} />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

/* ---------------- AI 布景 ---------------- */
// 输入条:收起时是会话入口,展开后就是会话的输入框;没有对话时浮窗只有这一条
function DrAiInput({ live, busy, onFocus, onSend }) {
  const [text, setText] = React.useState("");
  const ref = React.useRef(null);
  React.useEffect(() => { if (live && ref.current) ref.current.focus(); }, [live]);
  const submit = () => {
    if (!text.trim() || busy) return;
    onSend(text.trim());
    setText("");
  };
  return (
    <div className={"dr-aibar" + (live ? " is-live" : "")} onClick={live ? undefined : onFocus}>
      <button type="button" className="dr-aibar__plus" title="参考图"><CvIcon name="plus" size={16} /></button>
      <input ref={ref} className="dr-aibar__input" value={text} placeholder="描述你想搭建的场景"
        onFocus={onFocus} onChange={(e) => setText(e.target.value)}
        onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) submit(); }} />
      <button type="button" className="dr-aibar__go" disabled={busy || (live && !text.trim())} onClick={submit}>
        {busy ? "生成中" : "生成场景"}<CvIcon name="sparkle" size={12} />{DR_AI_STAGE_COST}
      </button>
    </div>
  );
}

// 会话消息:复用 ChatPanel 的 ChatBubble / ToolActivity;每轮跑完直接改布景,回复下可撤销
function DrAiThread({ runs, onUndo, onNew, onClose }) {
  const bodyRef = React.useRef(null);
  React.useEffect(() => {
    if (bodyRef.current) bodyRef.current.scrollTop = bodyRef.current.scrollHeight;
  }, [runs]);
  return (
    <div className="dr-aichat">
      <div className="dr-aichat__head">
        <CvIcon name="sparkle" size={14} color="var(--accent-warm)" />
        <span className="dr-aichat__title">AI 布景</span>
        <span className="cv-spacer" />
        <button type="button" className="cv-iconbtn" title="新会话" onClick={onNew}><CvIcon name="plus" size={14} /></button>
        <button type="button" className="cv-iconbtn" title="收起" onClick={onClose}><CvIcon name="caret-down" size={14} /></button>
      </div>
      <div className="dr-aichat__body" ref={bodyRef}>
        {runs.map((run) => {
          const all = DR_AI_CHAT.steps[run.scope];
          const done = run.step >= all.length;
          const steps = all.slice(0, run.step + 1).map((x, i) => ({ ...x, status: i < run.step ? "done" : "running" }));
          return (
            <React.Fragment key={run.id}>
              <ChatBubble role="user" content={run.ask} />
              <ChatBubble role="ai" streaming={!done}
                blocks={[{ type: "activity", steps }, ...(done ? [{ type: "text", text: DR_AI_CHAT.reply[run.scope] }] : [])]} />
              {done && run.hist && (
                <div className="dr-aichat__applied">
                  <CvIcon name="check" size={12} color="var(--success)" />
                  <span>已修改布景 · 记入历史</span>
                  {run.undone
                    ? <span className="dr-aichat__undone">已撤销</span>
                    : <button type="button" className="dr-aichat__undo" onClick={() => onUndo(run)}>撤销</button>}
                </div>
              )}
            </React.Fragment>
          );
        })}
      </div>
    </div>
  );
}

// 布景历史:每次 AI 修改 / 手动调整记一版,恢复即把布景换回那一版(恢复本身也记一版)
function DrAiHistory({ history, cur, onRestore, onClose }) {
  return (
    <div className="dr-aihist">
      <div className="dr-aihist__head">
        <span className="dr-aichat__title">布景历史</span>
        <span className="cv-spacer" />
        <button type="button" className="cv-iconbtn" title="关闭" onClick={onClose}><CvIcon name="x" size={13} /></button>
      </div>
      <div className="dr-aihist__list">
        {[...history].reverse().map((h) => (
          <div key={h.id} className={"dr-aihist__row" + (h.id === cur ? " is-cur" : "")}>
            <CvIcon name={h.by === "ai" ? "sparkle" : h.by === "restore" ? "arrow-counter-clockwise" : "user"} size={13}
              color={h.by === "ai" ? "var(--accent-warm)" : "var(--text-muted)"} />
            <span className="dr-aihist__text">
              <span className="dr-aihist__label">{h.label}</span>
              <span className="dr-aihist__at">{h.at}</span>
            </span>
            {h.id === cur
              ? <span className="dr-aihist__cur">当前</span>
              : <button type="button" className="cv-btn cv-btn--outline dr-aihist__btn" onClick={() => onRestore(h)}>恢复</button>}
          </div>
        ))}
      </div>
    </div>
  );
}

/* ---------------- 方向球 ---------------- */
// 跟随导演视角转动:三根轴按当前相机朝向投到屏幕上,背向镜头的轴画在后面
function DrGizmo({ view, onReset }) {
  const eye = drOrbitEye(view);
  const f = drNorm(drSub(view.target, eye));
  const r = drNorm(drCross(f, [0, 1, 0]));
  const u = drCross(r, f);
  const axes = [["x", [1, 0, 0]], ["y", [0, 1, 0]], ["z", [0, 0, 1]]]
    .map(([id, a]) => ({ id, dx: drDot(a, r), dy: -drDot(a, u), depth: drDot(a, f) }))
    .sort((a, b) => b.depth - a.depth);
  return (
    <div className="dr-vp__gizmowrap" onPointerDown={(e) => e.stopPropagation()}>
      <div className="dr-vp__gizmo">
        <svg className="dr-vp__gizmosvg" width={64} height={64}>
          {axes.map((a) => (
            <line key={a.id} x1={32} y1={32} x2={32 + a.dx * 22} y2={32 + a.dy * 22}
              className={"dr-vp__gizmoline dr-vp__gizmoline--" + a.id} />
          ))}
        </svg>
        {axes.map((a) => (
          <span key={a.id} className={"dr-vp__axis dr-vp__axis--" + a.id}
            style={{ left: 32 + a.dx * 22 - 9, top: 32 + a.dy * 22 - 9, opacity: a.depth > 0.3 ? 0.55 : 1 }}>
            {a.id.toUpperCase()}
          </span>
        ))}
      </div>
      <button type="button" className="dr-vp__reset" onClick={onReset}>
        <CvIcon name="arrow-counter-clockwise" size={13} />重置视角
      </button>
    </div>
  );
}

/* ---------------- 导演台 ---------------- */
// 片段替换:新片段覆盖选区,和它重叠的旧片段被裁掉,不重叠的保留
function drReplaceSeg(segs, seg) {
  const out = [];
  segs.forEach((s) => {
    if (s.b <= seg.a || s.a >= seg.b) { out.push(s); return; }
    if (s.a < seg.a) out.push({ ...s, b: seg.a });
    if (s.b > seg.b) out.push({ ...s, a: seg.b });
  });
  out.push(seg);
  return out.sort((x, y) => x.a - y.a);
}

function DrDirector({ onClose, onApply, empty: startEmpty, name }) {
  const qs = new URLSearchParams(location.search);
  const initTab = qs.get("dirtab") || "moves";
  const actorFirst = initTab === "actions" || qs.get("dirtool") === "rotate";
  const [tab, setTab] = React.useState(initTab);
  // stage: ready = 正常编辑;empty = 新建导演台还没有布景
  const [stage, setStage] = React.useState(startEmpty || qs.get("dirstate") === "empty" ? "empty" : "ready");
  const [mode, setMode] = React.useState(() => qs.get("dirview") === "camera" ? "camera" : "free");
  const [tool, setTool] = React.useState(qs.get("dirtool") === "rotate" ? "rotate" : "select");
  const [selected, setSelected] = React.useState(actorFirst ? "a_ahui" : "cam_pan");
  const [range, setRange] = React.useState(actorFirst ? { a: 3.5, b: 8 } : { a: 0, b: 11 });
  const [viewCam, setViewCam] = React.useState("cam_pan");
  const [look, setLookMap] = React.useState(() =>
    Object.fromEntries(DR_STAGE.cameras.map((c) => [c.id, c.lookAt])));
  // 布景本体:动作 / 运镜 / 旋转三组轨道,AI 修改与历史恢复都整体替换这三组
  const init = React.useMemo(() => ({
    acts: Object.fromEntries(DR_STAGE.actors.map((a) => [a.id, a.acts])),
    moves: Object.fromEntries(DR_STAGE.cameras.map((c) => [c.id, c.moves])),
    rots: Object.fromEntries(DR_STAGE.actors.map((a) => [a.id, a.rots])),
  }), []);
  const [acts, setActs] = React.useState(init.acts);
  const [moves, setMoves] = React.useState(init.moves);
  const [rots, setRots] = React.useState(init.rots);
  const [history, setHistory] = React.useState(() => DR_STAGE_HISTORY.map((h) => ({ ...h, snap: init })));
  const [histCur, setHistCur] = React.useState(DR_STAGE_HISTORY[DR_STAGE_HISTORY.length - 1].id);
  const [histOpen, setHistOpen] = React.useState(qs.get("aihist") === "1");
  // 会话:runs = 本次会话的各轮 { id, scope, ask, step, hist };step 推进到步骤数即这一轮结束
  const [aiOpen, setAiOpen] = React.useState(!!qs.get("aipanel") || stage === "empty");
  const [runs, setRuns] = React.useState([]);
  const [t, setT] = React.useState(5.2);
  const [playing, setPlaying] = React.useState(false);
  const [size, setSize] = React.useState({ w: 0, h: 0 });
  const [view, setView] = React.useState(DR_VIEW_HOME);
  const [orbiting, setOrbiting] = React.useState(false);
  const vpRef = React.useRef(null);

  // 导演视角的 3D 导航:左键拖空白处环绕,中键 / Shift + 左键平移,滚轮缩放;没拖动的单击仍是点选空白
  const onVpDown = (e) => {
    if (mode !== "free" || (e.button !== 0 && e.button !== 1)) { select("cam_pan"); return; }
    e.preventDefault();
    const pan = e.button === 1 || e.shiftKey;
    const x0 = e.clientX;
    const y0 = e.clientY;
    const v0 = view;
    const eye = drOrbitEye(v0);
    const f = drNorm(drSub(v0.target, eye));
    const r = drNorm(drCross(f, [0, 1, 0]));
    const u = drCross(r, f);
    const k = v0.dist / (size.h * 0.95);
    let moved = false;
    const move = (ev) => {
      const dx = ev.clientX - x0;
      const dy = ev.clientY - y0;
      if (!moved && Math.hypot(dx, dy) < 3) return;
      moved = true;
      setOrbiting(true);
      if (pan) {
        setView({ ...v0, target: v0.target.map((c, i) => c - r[i] * dx * k + u[i] * dy * k) });
      } else {
        setView({ ...v0, yaw: v0.yaw - dx * 0.4, pitch: Math.max(5, Math.min(85, v0.pitch + dy * 0.3)) });
      }
    };
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      setOrbiting(false);
      if (!moved) select("cam_pan");
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };
  React.useEffect(() => {
    const el = vpRef.current;
    if (!el || mode !== "free") return;
    const wheel = (e) => {
      e.preventDefault();
      setView((v) => ({ ...v, dist: Math.max(3, Math.min(30, v.dist * Math.exp(e.deltaY * 0.0015))) }));
    };
    el.addEventListener("wheel", wheel, { passive: false });
    return () => el.removeEventListener("wheel", wheel);
  }, [mode, stage === "empty"]);

  React.useEffect(() => {
    const el = vpRef.current;
    const ro = new ResizeObserver(() => setSize({ w: el.clientWidth, h: el.clientHeight }));
    ro.observe(el);
    setSize({ w: el.clientWidth, h: el.clientHeight });
    return () => ro.disconnect();
  }, [stage === "empty"]);

  React.useEffect(() => {
    if (!playing) return;
    let raf;
    let last = performance.now();
    const step = (now) => {
      setT((v) => {
        const n = v + (now - last) / 1000;
        return n >= DR_STAGE.duration ? 0 : n;
      });
      last = now;
      raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, [playing]);

  const snapNow = () => ({ acts, moves, rots });
  const loadSnap = (sn) => { setActs(sn.acts); setMoves(sn.moves); setRots(sn.rots); };
  const record = (by, label, snap) => {
    const id = "h" + Date.now();
    const now = new Date();
    const at = `今天 ${now.getHours()}:${String(now.getMinutes()).padStart(2, "0")}`;
    setHistory((hs) => [...hs, { id, at, by, label, snap }]);
    setHistCur(id);
    return id;
  };

  // 这一轮的改动直接写进布景,同时记一版历史
  const applyEdits = (scope) => {
    const e = DR_AI_CHAT.edits[scope];
    const next = {
      acts: { ...acts }, moves: { ...moves }, rots: { ...rots },
    };
    e.acts.forEach(([id, seg]) => { next.acts[id] = drReplaceSeg(next.acts[id], seg); });
    e.moves.forEach(([id, seg]) => { next.moves[id] = drReplaceSeg(next.moves[id], seg); });
    e.rots.forEach(([id, ry]) => { next.rots[id] = next.rots[id].map((k) => ({ ...k, ry })); });
    loadSnap(next);
    return { next, prev: histCur };
  };

  // agent 一步步跑完,最后一步改布景
  const running = runs.find((r) => r.step < DR_AI_CHAT.steps[r.scope].length);
  React.useEffect(() => {
    if (!running) return;
    const timer = setTimeout(() => {
      const step = running.step + 1;
      let patch = { step };
      if (step >= DR_AI_CHAT.steps[running.scope].length) {
        const { next, prev } = applyEdits(running.scope);
        patch = { step, prev, hist: record("ai", running.ask, next) };
        if (stage === "empty") setStage("ready");
      }
      setRuns((rs) => rs.map((r) => (r.id === running.id ? { ...r, ...patch } : r)));
    }, 650);
    return () => clearTimeout(timer);
  }, [running && running.id, running && running.step]);

  const send = (ask, scope = "scene") => {
    setRuns((rs) => [...rs, { id: "r" + Date.now(), scope, ask, step: 0 }]);
    setAiOpen(true);
    setHistOpen(false);
  };
  const restore = (h) => {
    loadSnap(h.snap);
    record("restore", `恢复到「${h.label}」`, h.snap);
  };
  const undo = (run) => {
    const prev = history.find((h) => h.id === run.prev);
    if (prev) restore(prev);
    setRuns((rs) => rs.map((r) => (r.id === run.id ? { ...r, undone: true } : r)));
  };

  const select = (id) => {
    setSelected(id);
    if (drCam(id)) setViewCam(id);
  };
  const pickSeg = (owner, s) => {
    select(owner);
    setRange({ a: s.a, b: s.b });
  };
  const setLook = (camId, v) => setLookMap((m) => ({ ...m, [camId]: v }));
  const setRot = (actorId, axis, v) => setRots((m) => ({ ...m, [actorId]: drSetRot(m[actorId], t, axis, v) }));
  const applyAct = (actorId, actId) =>
    setActs((m) => ({ ...m, [actorId]: drReplaceSeg(m[actorId], { act: actId, a: range.a, b: range.b }) }));
  const applyMove = (camId, moveId) =>
    setMoves((m) => ({ ...m, [camId]: drReplaceSeg(m[camId], { move: moveId, a: range.a, b: range.b }) }));

  const nextV = DR_STAGE.exports.filter((x) => x.camera === "cam_pan").length + 1;
  const regenShot = () => send("重新编排段 2-2", "shot");
  const empty = stage === "empty";

  // 视口底部:工具 dock + AI 布景(输入条,有对话时上方长出消息区)+ 历史
  const bottom = (
    <div className="dr-vp__bottom" onPointerDown={(e) => e.stopPropagation()}>
      {!empty && (
        <div className="dr-vp__dock">
          {[["select", "cursor", "选择 / 移动"], ["rotate", "arrows-clockwise", "旋转"]].map(([v, ic, l]) => (
            <button key={v} type="button" title={l} className={"dr-vp__dockbtn" + (tool === v ? " is-on" : "")}
              onClick={() => setTool(v)}>
              <CvIcon name={ic} size={15} />
            </button>
          ))}
        </div>
      )}
      <div className={"dr-vp__aislot" + (aiOpen && runs.length ? " is-thread" : "")}>
        {aiOpen && runs.length > 0 && (
          <DrAiThread runs={runs} onUndo={undo} onNew={() => setRuns([])} onClose={() => setAiOpen(false)} />
        )}
        <DrAiInput live={aiOpen} busy={!!running} onFocus={() => setAiOpen(true)} onSend={(x) => send(x)} />
      </div>
      {!empty && (
        <span className="dr-vp__histanchor">
          <button type="button" className={"dr-vp__histbtn" + (histOpen ? " is-on" : "")} title="布景历史"
            onClick={() => setHistOpen(!histOpen)}>
            <CvIcon name="clock-counter-clockwise" size={17} />
          </button>
          {histOpen && <DrAiHistory history={history} cur={histCur} onRestore={restore} onClose={() => setHistOpen(false)} />}
        </span>
      )}
    </div>
  );

  return (
    <div className="dr-director">
      <div className="dr-director__top">
        {/* 位置(作品 › 制片 › 导演台名)由工作区面包屑显示,这里只留关闭和保存状态。 */}
        <button type="button" className="cv-iconbtn" title="关闭" onClick={onClose}><CvIcon name="x" size={15} /></button>
        <span className="dr-director__saved">已保存</span>
        <span className="cv-spacer" />
        <button type="button" className="cv-btn cv-btn--outline" disabled={empty}><CvIcon name="image-square" size={13} />导出构图静帧</button>
        <button type="button" className="cv-btn cv-btn--primary" disabled={empty || !!running} onClick={onApply}>
          <CvIcon name="film-strip" size={14} />录制预演 v{nextV}
        </button>
      </div>
      {empty && (
        <div className="dr-director__body">
          <div className="dr-vp" ref={vpRef}>
            <DrViewport bare size={size} view={view} />
            <button type="button" className="dr-vp__manual" onClick={() => setStage("ready")}>手动搭建</button>
            {bottom}
          </div>
        </div>
      )}
      {!empty && (
      <div className="dr-director__body">
        <DrDirLeft tab={tab} setTab={setTab} selected={selected} onSelect={select} range={range}
          acts={acts} moves={moves} onApplyAct={applyAct} onApplyMove={applyMove} />
        <div className={"dr-vp" + (mode === "free" ? " is-orbit" : "") + (orbiting ? " is-orbiting" : "")}
          ref={vpRef} onPointerDown={onVpDown}>
          <DrViewport mode={mode} camId={viewCam} look={look} rots={rots} t={t} selected={selected} onSelect={select}
            size={size} tool={tool} onRotate={(id, v) => setRot(id, "ry", v)} view={view} />
          <div className="dr-vp__modes" onPointerDown={(e) => e.stopPropagation()}>
            {[["free", "导演视角"], ["camera", "机位视角"]].map(([v, l]) => (
              <button key={v} type="button" className={"dr-vp__mode" + (mode === v ? " is-on" : "")}
                onClick={() => setMode(v)}>{l}</button>
            ))}
          </div>
          {mode === "free" && <DrGizmo view={view} onReset={() => setView(DR_VIEW_HOME)} />}
          {bottom}
        </div>
        <DrDirRight selected={selected} viewCam={viewCam} setViewCam={setViewCam} look={look} setLook={setLook}
          acts={acts} moves={moves} rots={rots} setRot={setRot} t={t} range={range} onPickSeg={pickSeg}
          setTab={setTab} onRegenShot={regenShot} />
      </div>
      )}
      {!empty && <DrSequencer t={t} setT={setT} playing={playing} setPlaying={setPlaying} selected={selected}
        onSelect={select} range={range} onPickSeg={pickSeg} look={look} acts={acts} moves={moves} rots={rots} />}
    </div>
  );
}

Object.assign(window, { DrDirector });
