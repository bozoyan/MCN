// approval.jsx — 制作助手的工具审批:审批卡、运行条、助手权限弹窗。对应 docs/solutions/tool-approval.md。
// 助手发起模型生成 / 读外部文件 / 删受管文件都走 Run;命令声明的权限能力(generation.image / video / audio、files.read / remove)
// 按 会话 → 分集 → 作品 → 全局 → 默认(每次询问) 查第一条规则,ask 时挂起请求、在对话里出审批卡。
// 审批卡展示冻结请求:用户批准时看到的渠道、模型、规格、参考、费用就是实际提交的那一份。
// 每张卡是独立请求:同一回合的多张卡各自批准 / 拒绝 / 取消,互不影响;重复点击只消费一次。
// 选了长期范围 = 允许本次 + 保存规则;规则保存失败时卡保持待审批并显示错误,不回报已允许。
// 批准后复核冻结目标:审批期间节点配置被改动 → conflict,不提交。
// 运行条在输入框上方,列出本会话发起的运行;等待授权的运行可以定位到卡、或取消(撤销审批请求)。
// 深链:&perm=1(打开助手权限) &approval=savefail(保存长期规则失败) &approval=conflict(批准后复核不一致)
//      &apd=<审批 id>(打开该审批的详情弹窗,如 apd=ap5 删除文件、apd=ap4 ffmpeg 读取)
// 关联文件: drama/chat.jsx, drama/app.jsx, ChatPanel.jsx

const DR_CAPS = [
  { id: "generation.image", label: "生成图片", icon: "image" },
  { id: "generation.video", label: "生成视频", icon: "film-strip" },
  { id: "generation.audio", label: "生成音频", icon: "waveform" },
  { id: "files.read", label: "读取文件", icon: "file-text" },
  { id: "files.remove", label: "删除文件", icon: "trash", danger: true },
];
const DR_DECISION = {
  allow: { label: "允许", tone: "allow" },
  ask: { label: "每次询问", tone: "ask" },
  deny: { label: "拒绝", tone: "deny" },
};
// 只列可信上下文里存在的范围:会话、分集(制片页总有当前集)、作品、全局。
const DR_SCOPES = [
  { id: "session", label: "本次对话" },
  { id: "episode", label: "本集" },
  { id: "work", label: "本作品" },
  { id: "global", label: "所有作品" },
];
const drCap = (id) => DR_CAPS.find((c) => c.id === id);

// 规则表的 mockup:作品级已允许生成视频,全局对读文件明确设了每次询问。
const DR_RULES = {
  session: {},
  episode: {},
  work: { "generation.video": "allow" },
  global: { "files.read": "ask" },
};

// 按 会话 → 分集 → 作品 → 全局 取第一条;都没有就是默认的每次询问。
function drEffective(rules, cap) {
  for (const s of DR_SCOPES) {
    const d = rules[s.id][cap];
    if (d) return { decision: d, source: s.label };
  }
  return { decision: "ask", source: "默认" };
}

// 审批请求。runId 是登记的运行;brief / details / lists / command 是冻结请求的事实,不能再被 UI 或模型改。
// 卡片只放标题、对象和一行摘要(模型 · 规格 · 费用);完整事实在详情弹窗里看。
// lists 的 items 是冻结请求里的预览;只列了一部分时标签写明「部分」,总数放在 details 里。
// 删除不列文件明细:清单展开到每个文件(审批后新增的文件不会被删),审批时按文件夹汇总数量。
const DR_APPROVALS = [
  { id: "ap0", runId: "R-0207", cap: "generation.video", title: "生成视频",
    target: "段 2-2 · 递茶", state: "allowed", scope: "once",
    brief: "Seedance 2.5 · 9:16 · 11 秒 · 约 ¥11.00", details: [["渠道", "我的火山方舟"]] },
  { id: "ap1", runId: "R-0311", cap: "generation.image", title: "生成图片",
    target: "前舱 · 夜 · 宽景", nodeId: "i_cabin", state: "pending",
    brief: "Seedream 4.0 · 16:9 · 2K · 约 ¥0.20",
    details: [["渠道", "我的火山方舟"], ["风格", "历史写实"]], refs: ["a_cabin"] },
  { id: "ap2", runId: "R-0312", cap: "generation.image", title: "生成头像",
    target: "周慎", state: "pending",
    brief: "Seedream 4.0 · 1:1 · 2K · 约 ¥0.20",
    details: [["渠道", "我的火山方舟"]], refs: ["a_zhou"] },
  { id: "ap3", runId: "R-0313", cap: "files.read", title: "读取文件",
    target: "布光参考.jpg", state: "pending",
    brief: "桌面 · JPEG · 2.4 MB",
    details: [["位置", "~/Desktop/布光参考.jpg"], ["修改时间", "今天 15:20"]] },
  { id: "ap4", runId: "R-0314", cap: "files.read", title: "读取文件",
    target: "frame-%04d.png, list.txt, bgm.m4a", state: "pending",
    brief: "读取文件数 142 · 目录总数 12",
    details: [["读取文件数", "142"], ["目录总数", "12"]],
    command: "-framerate 24 -i frames/frame-%04d.png -f concat -i clips/list.txt -i audio/bgm.m4a -c:v libx264 -pix_fmt yuv420p -shortest preview.mp4",
    lists: [
      { label: "位置", items: ["frames/frame-%04d.png", "clips/list.txt", "audio/bgm.m4a"] },
      { label: "读取目录（部分）", items: ["~/Movies/渡口/clips/s2", "~/Movies/渡口/clips/s3", "~/Movies/渡口/clips/s4",
        "~/Movies/渡口/clips/s5", "~/Movies/渡口/clips/s6", "~/Movies/渡口/clips/s7", "~/Movies/渡口/frames",
        "~/Movies/渡口/audio"] },
    ] },
  { id: "ap5", runId: "R-0315", cap: "files.remove", title: "删除文件",
    target: "sessions/c81f/frames/**", state: "pending",
    brief: "匹配项数 903 · 包含子目录",
    details: [["匹配项数", "903"], ["包含子目录", ""]],
    groups: { label: "将删除", items: [
      ["sessions/c81f/frames/s2/", 301], ["sessions/c81f/frames/s3/", 301], ["sessions/c81f/frames/s4/", 301],
    ] } },
];

// 运行条里不由审批产生的运行(后台生成在跑)。
const DR_RUNS_EXTRA = [
  { id: "R-0207", label: "生成视频 · 段 2-2 · 递茶", state: "running", progress: 62 },
];

const DR_RUN_STATE = {
  waiting_approval: "待确认",
  queued: "排队中",
  running: "执行中",
  completed: "已完成",
  denied: "已拒绝",
  cancelled: "已取消",
  conflict: "配置已变更，未提交",
};

// 审批卡状态 → 运行状态。
function drRunOf(ap) {
  const map = { pending: "waiting_approval", resolving: "waiting_approval", allowed: "queued",
    denied: "denied", cancelled: "cancelled", conflict: "conflict" };
  return { id: ap.runId, label: `${ap.title} · ${ap.target}`, state: map[ap.state], approvalId: ap.id };
}

// 小号下拉:审批卡的适用范围、权限弹窗的单元格共用。
// 菜单挂到 body 上按按钮位置固定定位,不被聊天列表的滚动区裁掉;下方放不下就向上弹。
function DrMiniSelect({ value, options, onChange, disabled, align, quiet }) {
  const [pos, setPos] = React.useState(null);
  const btnRef = React.useRef(null);
  const cur = options.find((o) => o.value === value);
  // 菜单是固定定位:列表滚动或窗口缩放后位置就不对了,直接收起。
  React.useEffect(() => {
    if (!pos) return;
    const close = () => setPos(null);
    window.addEventListener("scroll", close, true);
    window.addEventListener("resize", close);
    return () => {
      window.removeEventListener("scroll", close, true);
      window.removeEventListener("resize", close);
    };
  }, [pos]);
  const toggle = () => {
    if (pos) return setPos(null);
    const r = btnRef.current.getBoundingClientRect();
    const menuH = options.length * 31 + 10;
    const up = r.bottom + 4 + menuH > window.innerHeight - 8;
    setPos({
      ...(up ? { bottom: window.innerHeight - r.top + 4 } : { top: r.bottom + 4 }),
      ...(align === "right" ? { right: window.innerWidth - r.right } : { left: r.left }),
    });
  };
  return (
    <span className={"dr-msel" + (pos ? " is-open" : "") + (quiet ? " is-quiet" : "")}>
      <button ref={btnRef} type="button" className={"dr-msel__btn" + (cur && cur.tone ? " is-" + cur.tone : "")} disabled={disabled}
        onClick={toggle}>
        <span>{cur ? cur.label : ""}</span>
        <Icon name="caret-down" size={11} />
      </button>
      {pos && ReactDOM.createPortal(
        <>
          <span className="dr-msel__scrim" onClick={() => setPos(null)} />
          <span className="dr-msel__menu" style={pos}>
            {options.map((o) => (
              <button type="button" key={o.value} className={"dr-msel__item" + (o.value === value ? " is-on" : "")}
                onClick={() => { onChange(o.value); setPos(null); }}>
                <span>{o.label}</span>
                {o.value === value && <Icon name="check" size={12} color="var(--accent)" />}
              </button>
            ))}
          </span>
        </>,
        document.body
      )}
    </span>
  );
}

// 详情、拒绝、允许共用的披露与错误行;卡片和弹窗各放一份,文案一致。
const DR_DISCLOSURE = { "files.read": "文件信息或内容会发送给当前模型" };

// 审批详情弹窗:完整的冻结事实。键列定宽对齐;路径类事实按行列出,只列冻结预览,超出部分报「另有 N 项」。
// 底部与卡片同一组决策控件,看完可以直接决定;决定后弹窗关闭,卡片随之变成回执。
function DrApprovalDialog({ ap, scope, scopeOpts, onScope, onAllow, onDeny, onClose }) {
  const cap = drCap(ap.cap);
  const busy = ap.state === "resolving";
  return (
    <div className="m-dialog-scrim" onClick={onClose}>
      <div className="m-dialog dr-apd" onClick={(e) => e.stopPropagation()}>
        <div className="dr-apd__head">
          <span className={"dr-appr__tile" + (cap.danger ? " is-danger" : "")}><Icon name={cap.icon} size={16} /></span>
          <div className="dr-appr__text">
            <div className="dr-appr__title">{ap.title}</div>
            <div className="dr-apd__target" title={ap.target}>{ap.target}</div>
          </div>
          <button className="m-icon-btn" title="关闭" onClick={onClose}><Icon name="x" size={14} /></button>
        </div>
        <div className="dr-apd__body">
          {ap.details.length > 0 && (
            <dl className="dr-apd__facts">
              {/* 开关类事实开启时整行只写字段名 */}
              {ap.details.map(([k, v]) => (v === ""
                ? <dt key={k} className="dr-apd__flag">{k}</dt>
                : <React.Fragment key={k}><dt>{k}</dt><dd>{v}</dd></React.Fragment>))}
            </dl>
          )}
          {ap.command && (
            <section className="dr-apd__sec">
              <div className="dr-apd__label">参数</div>
              <pre className="dr-apd__code">{ap.command}</pre>
            </section>
          )}
          {(ap.lists || []).map((l) => (
            <section key={l.label} className="dr-apd__sec">
              <div className="dr-apd__label">{l.label}</div>
              <ul className={"dr-apd__list" + (cap.danger ? " is-danger" : "")}>
                {l.items.map((it) => <li key={it} title={it}>{it}</li>)}
              </ul>
            </section>
          ))}
          {ap.groups && (
            <section className="dr-apd__sec">
              <div className="dr-apd__label">{ap.groups.label}</div>
              <ul className={"dr-apd__list dr-apd__groups" + (cap.danger ? " is-danger" : "")}>
                {ap.groups.items.map(([dir, n]) => (
                  <li key={dir} title={dir}><span>{dir}</span><span className="dr-apd__n">{n} 项</span></li>
                ))}
              </ul>
            </section>
          )}
          {ap.refs && (
            <section className="dr-apd__sec">
              <div className="dr-apd__label">参考</div>
              <div className="dr-appr__refs">
                {ap.refs.map((id) => (
                  <span key={id} className="dr-appr__ref">
                    <DrAssetThumb asset={spAsset(id)} h={32} />
                    <span>{spAsset(id).name}</span>
                  </span>
                ))}
              </div>
            </section>
          )}
          {DR_DISCLOSURE[ap.cap] && <div className="dr-apd__note">{DR_DISCLOSURE[ap.cap]}</div>}
          {ap.saveFailed && <div className="dr-apd__err"><Icon name="warning-circle" size={13} />规则保存失败，本次未授权</div>}
        </div>
        <div className="dr-apd__foot">
          <DrMiniSelect value={scope} options={scopeOpts} onChange={onScope} disabled={busy} quiet />
          <span style={{ flex: 1 }} />
          <button type="button" className="m-btn m-btn--ghost m-btn--sm" disabled={busy} onClick={onDeny}>拒绝</button>
          <button type="button" className={"m-btn m-btn--sm " + (cap.danger ? "m-btn--danger" : "m-btn--primary")} disabled={busy} onClick={onAllow}>
            {busy && <span className="m-task__spinner dr-appr__spin" />}允许
          </button>
        </div>
      </div>
    </div>
  );
}

// 卡片:标题说要做什么 + 对象 + 一行摘要,不在消息流里展开;「详情」打开弹窗看完整事实。
// 「仅这一次 ▾」选长期范围 = 允许本次并在该范围内不再询问,标签本身说清楚覆盖范围,不另加说明。
// 删除类能力:图标方块和「允许」用危险色,其余卡片保持中性。
function DrApprovalCard({ ap, focused, onAllow, onDeny }) {
  const [scope, setScope] = React.useState("once");
  const [open, setOpen] = React.useState(DR_Q.get("apd") === ap.id);
  const cap = drCap(ap.cap);
  const busy = ap.state === "resolving";
  const pending = ["pending", "resolving"].includes(ap.state);
  // 决定后弹窗随卡片一起收掉。
  React.useEffect(() => { if (!pending) setOpen(false); }, [pending]);

  // 已处理:收成一行回执。
  if (!pending) {
    const done = {
      allowed: { icon: "check", tone: "allow", text: "已允许" },
      denied: { icon: "prohibit", tone: "deny", text: "已拒绝" },
      cancelled: { icon: "x", tone: "muted", text: "已取消" },
      conflict: { icon: "warning", tone: "warn", text: "配置已变更，未提交" },
    }[ap.state];
    return (
      <div className={"dr-appr dr-appr--done is-" + done.tone} data-approval={ap.id}>
        <Icon name={cap.icon} size={13} color="var(--text-muted)" />
        <span className="dr-appr__done-target">{ap.title} · {ap.target}</span>
        <span className="dr-appr__done-state"><Icon name={done.icon} size={12} />{done.text}</span>
      </div>
    );
  }

  const scopeOpts = [{ value: "once", label: "仅这一次" },
    ...DR_SCOPES.map((s) => ({ value: s.id, label: `${s.label}不再询问` }))];
  return (
    <div className={"dr-appr" + (focused ? " is-focused" : "")} data-approval={ap.id}>
      <div className="dr-appr__main">
        <span className={"dr-appr__tile" + (cap.danger ? " is-danger" : "")}><Icon name={cap.icon} size={16} /></span>
        <div className="dr-appr__text">
          <div className="dr-appr__title">{ap.title}</div>
          <div className="dr-appr__target" title={ap.target}>{ap.target}</div>
          <div className="dr-appr__briefrow">
            <span className="dr-appr__brief">{ap.brief}</span>
            <button type="button" className="dr-appr__more" onClick={() => setOpen(true)}>
              详情<Icon name="caret-right" size={10} />
            </button>
          </div>
        </div>
      </div>
      {DR_DISCLOSURE[ap.cap] && <div className="dr-appr__note">{DR_DISCLOSURE[ap.cap]}</div>}
      {ap.saveFailed && <div className="dr-appr__err"><Icon name="warning-circle" size={13} />规则保存失败，本次未授权</div>}
      <div className="dr-appr__actions">
        <DrMiniSelect value={scope} options={scopeOpts} onChange={setScope} disabled={busy} quiet />
        <span style={{ flex: 1 }} />
        <button type="button" className="m-btn m-btn--ghost m-btn--sm" disabled={busy} onClick={() => onDeny(ap.id)}>拒绝</button>
        <button type="button" className={"m-btn m-btn--sm " + (cap.danger ? "m-btn--danger" : "m-btn--primary")} disabled={busy} onClick={() => onAllow(ap.id, scope)}>
          {busy && <span className="m-task__spinner dr-appr__spin" />}允许
        </button>
      </div>
      {open && ReactDOM.createPortal(
        <DrApprovalDialog ap={ap} scope={scope} scopeOpts={scopeOpts} onScope={setScope}
          onAllow={() => onAllow(ap.id, scope)} onDeny={() => onDeny(ap.id)} onClose={() => setOpen(false)} />,
        document.body
      )}
    </div>
  );
}

// 输入框上方的运行条:本会话发起的运行。只有一条时不出汇总行。
function DrRunStrip({ runs, onLocate, onCancel }) {
  const [open, setOpen] = React.useState(true);
  if (!runs.length) return null;
  const waiting = runs.filter((r) => r.state === "waiting_approval").length;
  const live = runs.filter((r) => ["waiting_approval", "queued", "running"].includes(r.state)).length;
  const multi = runs.length > 1;
  return (
    <div className="m-bga dr-runs">
      {multi && (
        <div className={"m-bga__head" + (open ? " is-open" : "")} onClick={() => setOpen(!open)}>
          {waiting ? <Icon name="shield-check" size={14} color="var(--accent-warm)" /> : live ? <span className="m-bga__spin" /> : <Icon name="check" size={13} color="var(--text-muted)" />}
          <span className="m-bga__title">{live ? `${live} 项任务` : "任务已结束"}</span>
          <span className="m-bga__names">{waiting ? `· ${waiting} 项待确认` : ""}</span>
          <Icon name="caret-down" size={14} className={"m-bga__caret" + (open ? " is-open" : "")} />
        </div>
      )}
      {(!multi || open) && (
        <div className="m-bga__list">
          {runs.map((r) => {
            const wait = r.state === "waiting_approval";
            const active = wait || r.state === "queued" || r.state === "running";
            return (
              <div key={r.id} className="m-bga__row">
                <span className={"dr-runs__dot is-" + r.state}>
                  {r.state === "running" || r.state === "queued" ? <span className="m-task__spinner" />
                    : <Icon name={{ waiting_approval: "shield-check", completed: "check", denied: "prohibit", cancelled: "x", conflict: "warning" }[r.state]} size={11} />}
                </span>
                <span className="m-bga__name dr-runs__label" title={r.label}>{r.label}</span>
                <span className={"m-bga__act dr-runs__state is-" + r.state}>
                  {DR_RUN_STATE[r.state]}{r.state === "running" && r.progress != null ? ` · ${r.progress}%` : ""}
                </span>
                {wait ? (
                  <button type="button" className="m-bga__btn" title="查看" onClick={() => onLocate(r.approvalId)}>
                    <Icon name="arrow-up" size={13} />
                  </button>
                ) : <span className="m-bga__slot" />}
                {active ? (
                  <button type="button" className="m-bga__btn m-bga__btn--stop" title="取消" onClick={() => onCancel(r)}>
                    <span className="m-bga__stopmark" />
                  </button>
                ) : <span className="m-bga__slot" />}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

// 助手权限:能力 × 范围的规则矩阵。单元格选「跟随上级」= 恢复继承(软删这一行规则);
// 「所有作品」的空值就是默认的每次询问。
function DrPermDialog({ rules, onChange, onClose }) {
  const scopeName = { session: "本次对话", episode: `本集 · ${DR_EPISODE.label}`, work: `本作品 · ${DR_PROJECT.title}`, global: "所有作品" };
  return (
    <div className="m-dialog-scrim" onClick={onClose}>
      <div className="m-dialog dr-perm" onClick={(e) => e.stopPropagation()}>
        <div className="m-dialog__head">
          <div className="m-chat__head-l">
            <Icon name="shield-check" size={16} />
            <span className="m-ui-semibold">助手权限</span>
          </div>
          <button className="m-icon-btn" title="关闭" onClick={onClose}><Icon name="x" size={14} /></button>
        </div>
        <div className="dr-perm__body">
          <table className="dr-perm__grid">
            <thead>
              <tr>
                <th />
                {DR_SCOPES.map((s) => <th key={s.id}>{scopeName[s.id]}</th>)}
                <th>结果</th>
              </tr>
            </thead>
            <tbody>
              {DR_CAPS.map((c) => {
                const eff = drEffective(rules, c.id);
                return (
                  <tr key={c.id}>
                    <th>
                      <span className="dr-perm__cap"><Icon name={c.icon} size={14} />{c.label}</span>
                    </th>
                    {DR_SCOPES.map((s) => {
                      const v = rules[s.id][c.id] || "inherit";
                      const opts = [
                        { value: "inherit", label: s.id === "global" ? "每次询问" : "跟随上级", tone: "inherit" },
                        ...Object.entries(DR_DECISION).map(([k, d]) => ({ value: k, label: d.label, tone: d.tone })),
                      ];
                      return (
                        <td key={s.id}>
                          <DrMiniSelect value={v} options={opts} align={s.id === "global" ? "right" : null}
                            onChange={(nv) => onChange(s.id, c.id, nv === "inherit" ? null : nv)} />
                        </td>
                      );
                    })}
                    <td>
                      <span className={"dr-perm__eff is-" + DR_DECISION[eff.decision].tone}>{DR_DECISION[eff.decision].label}</span>
                      <span className="dr-perm__src">{eff.source}</span>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, {
  DR_CAPS, DR_SCOPES, DR_RULES, DR_APPROVALS, DR_RUNS_EXTRA, drCap, drEffective, drRunOf,
  DrApprovalCard, DrApprovalDialog, DrRunStrip, DrPermDialog, DrMiniSelect,
});
