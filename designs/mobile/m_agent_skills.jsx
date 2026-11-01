/* ============================================================
   AgentSkill Setup — 移动端
   对齐方案 docs/solutions/agent-skill-library-and-novel-installations.md，
   镜像桌面端 designs/desktop/skills/。新的小说级技能模型:
     - 技能库(MSK_LIBRARY)   私有来源,永不可执行
     - 已安装(MSK_INSTALLED)  当前小说唯一可执行的快照
     - 官方目录 / 市场         可安装来源;市场含撤销状态
   两个入口:小说工作区「智能体技能」(novel 模式,含「已安装」);
            AI tab「技能库」(home 模式,设备级来源,不含「已安装」)。
   全部为 mock,状态存在组件内,无真实持久化与网络。
   ============================================================ */

/* ---------------- data ---------------- */
const MSK_CATEGORIES = ['扩写', '润色', '校对', '设定考据', '结构', '对白', '节奏', '文风'];

const MSK_SOURCE_BADGE = {
  novel_local: { icon: 'pencil', label: '本地' },
  library: { icon: 'save', label: '技能库' },
  official: { icon: 'shield', label: '官方' },
  marketplace: { icon: 'storefront', label: '市场' },
};

const MSK_INSTALLED = [
  { id: 'nas1', callName: 'expand_chapter', sourceKind: 'novel_local', name: '章节扩写', enabled: true,
    desc: '把章节大纲扩写为符合既定节奏与人物声音的完整初稿。' },
  { id: 'nas2', callName: 'polish', sourceKind: 'library', name: '润色重写', enabled: true,
    desc: '在不改动情节的前提下打磨语言:节奏、重复、冗词、标点。' },
  { id: 'nas3', callName: 'lore_audit', sourceKind: 'official', sourceVersion: '1.2.0', upgradeVersion: '1.4.0',
    name: '世界观考据', enabled: true, desc: '对照世界设定核查地理、器物、制度与时间线冲突。' },
  { id: 'nas4', callName: 'golden_three', sourceKind: 'marketplace', sourceVersion: '2.0.1',
    executionBlockedReason: '作者已撤下该版本(2.0.1),市场判定存在质量问题。已保留本地内容,但运行时会跳过执行。',
    name: '网文黄金三章', enabled: true, desc: '按黄金三章模型重排开篇节奏:悬念前置、爽点密度、章末钩子。' },
  { id: 'nas5', callName: 'multiline', sourceKind: 'marketplace', sourceVersion: '1.3.0', name: '多线叙事编排',
    enabled: false, desc: '梳理多线叙事的时间轴与交汇点,标出信息释放与视角切换节奏。' },
];

const MSK_LIBRARY = [
  { id: 'lib1', name: '润色重写', category: '润色', tags: ['语言', '节奏'], updatedAt: '3 天前',
    desc: '在不改动情节的前提下打磨语言:节奏、重复、冗词、标点。' },
  { id: 'lib2', name: '伏笔检查', category: '校对', tags: ['伏笔', '台账'], updatedAt: '1 周前',
    desc: '梳理全书已埋伏笔与回收状态,标出悬而未决或暴露过早的线索。' },
  { id: 'lib3', name: '人物弧光设计', category: '结构', tags: ['人物', '成长线'], updatedAt: '2 周前',
    desc: '以关键抉择为锚点,规划人物从初始状态到结局的成长弧线。' },
  { id: 'lib4', name: '战斗场面编排', category: '节奏', tags: ['动作', '张力'], updatedAt: '上个月',
    desc: '编排战斗的空间调度、招式节奏与情绪起伏,避免流水账。' },
];

const MSK_OFFICIAL = [
  { id: 'off1', name: '世界观考据', version: '1.4.0', category: '设定考据', tags: ['设定', '自洽'],
    desc: '对照世界设定核查地理、器物、制度与时间线冲突,并列引用设定与正文原文。' },
  { id: 'off2', name: '章节大纲扩写', version: '2.1.0', category: '扩写', tags: ['大纲', '初稿'],
    desc: '将粗章纲拆解为分场景大纲:场景目标、冲突、转折与出场人物。' },
  { id: 'off3', name: '对白自然化', version: '1.0.3', category: '对白', tags: ['对白', '语气'],
    desc: '按人物身份与处境调整对白语气、停顿与潜台词,让每个人说话有辨识度。' },
  { id: 'off4', name: '时间线校对', version: '1.1.0', category: '校对', tags: ['时间线', '连续性'],
    desc: '建立事件时间轴,标出与既有章节冲突的时间、年龄与季节错误。' },
];

const MSK_MARKET = [
  { id: 'mk1', name: '网文黄金三章', author: '老猫', installs: 3280, version: '2.1.0', category: '结构', tags: ['开篇', '留存'],
    whenToUse: '开篇前三章需要快速抓住读者、埋好钩子并建立追读动机时使用。',
    desc: '按黄金三章模型重排开篇节奏:悬念前置、爽点密度、章末钩子。适合男频长篇。',
    versions: [
      { version: '2.1.0', date: '2026-07-02', note: '补充女频开篇模板', status: 'approved' },
      { version: '2.0.1', date: '2026-05-18', note: '修正钩子密度过高的问题', status: 'revoked' },
      { version: '2.0.0', date: '2026-05-04', note: '重写为分场景指令', status: 'superseded' },
    ] },
  { id: 'mk2', name: '多线叙事编排', author: '青梧', installs: 1470, version: '1.3.0', category: '结构', tags: ['群像', '多线'],
    whenToUse: '多条故事线并行推进,需要安排交汇点与信息释放节奏时使用。',
    desc: '梳理多线叙事的时间轴与交汇点,标出信息释放与视角切换节奏。',
    versions: [
      { version: '1.3.0', date: '2026-06-20', note: '增加视角切换检查', status: 'approved' },
      { version: '1.2.0', date: '2026-04-11', note: '初版', status: 'superseded' },
    ] },
  { id: 'mk3', name: '悬疑埋雷器', author: '夜航船', installs: 962, version: '1.0.2', category: '结构', tags: ['悬疑', '反转'],
    whenToUse: '需要在前文埋设可回收的线索、并规划反转落点时使用。',
    desc: '为悬疑线规划线索埋设与回收点,校验反转是否有据可循、是否提前泄底。',
    versions: [{ version: '1.0.2', date: '2026-06-28', note: '修正线索台账格式', status: 'approved' }] },
  { id: 'mk4', name: '轻小说吐槽腔', author: '苏打水', installs: 2140, version: '1.1.0', category: '文风', tags: ['轻小说', '吐槽'],
    whenToUse: '需要写出日式轻小说的第一人称吐槽语气时使用。',
    desc: '调校第一人称叙述的吐槽节奏与自嘲密度,保留角色声音不油腻。',
    versions: [{ version: '1.1.0', date: '2026-07-08', note: '降低吐槽密度上限', status: 'approved' }] },
];

/* ---------------- atoms ---------------- */
function MSkTag({ icon, children, tone }) {
  const map = {
    accent: { c: 'var(--accent-warm)', bg: 'color-mix(in srgb, var(--accent) 13%, transparent)' },
    muted: { c: 'var(--text-muted)', bg: 'var(--surface-dim)' },
  };
  const s = map[tone] || map.muted;
  const Cmp = icon ? I[icon] : null;
  return (
    <span className="chip" style={{ height: 20, fontSize: 10.5, padding: '0 8px', gap: 4, flex: '0 0 auto',
      color: s.c, background: s.bg, fontWeight: 600 }}>
      {Cmp && <Cmp s={11} />}{children}
    </span>
  );
}

function MSkSourceBadge({ kind }) {
  const b = MSK_SOURCE_BADGE[kind];
  if (!b) { return null; }
  return <MSkTag icon={b.icon} tone={kind === 'official' ? 'accent' : 'muted'}>{b.label}</MSkTag>;
}

/* small toast */
function MSkToast({ text }) {
  return (
    <div className="pop-in" style={{ position: 'absolute', left: '50%', bottom: 'calc(env(safe-area-inset-bottom,0px) + 24px)',
      transform: 'translateX(-50%)', zIndex: 90, display: 'flex', alignItems: 'center', gap: 8,
      padding: '10px 16px', background: 'var(--text-primary)', color: 'var(--canvas)', borderRadius: 'var(--r-pill)',
      boxShadow: 'var(--shadow-float)', fontSize: 13, fontWeight: 600, maxWidth: '82%' }}>
      <I.checkCircle s={15} c="var(--accent-amber)" />{text}
    </div>
  );
}

/* ---------------- installed ---------------- */
function MSkInstalledCard({ item, onToggle, onActions, onUpgrade, onRevoked }) {
  const blocked = !!item.executionBlockedReason;
  return (
    <div className="card" style={{ padding: '13px 14px', ...(blocked ? { borderColor: 'var(--warning)', background: 'color-mix(in srgb, var(--warning-text) 5%, transparent)' } : {}) }}>
      <div className="row gap8" style={{ marginBottom: 6, alignItems: 'center' }}>
        <span className="display" style={{ flex: 1, minWidth: 0, fontSize: 14.5, fontWeight: 700, color: 'var(--text-primary)',
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{item.name}</span>
        <Switch on={item.enabled} onToggle={() => onToggle(item.id)} />
        <button className="press" onClick={() => onActions(item)} aria-label="更多"
          style={{ width: 30, height: 30, display: 'flex', alignItems: 'center', justifyContent: 'center',
            background: 'transparent', border: 'none', color: 'var(--text-muted)', flex: '0 0 auto' }}><I.dots s={18} /></button>
      </div>
      <div className="row" style={{ flexWrap: 'wrap', gap: 6, marginBottom: 8 }}>
        <span className="chip" style={{ height: 20, fontSize: 10.5, padding: '0 7px', flex: '0 0 auto',
          background: 'var(--surface-dim)', color: 'var(--text-secondary)', fontFamily: 'var(--mono)', fontWeight: 600 }}>{item.callName}</span>
        <MSkSourceBadge kind={item.sourceKind} />
        {item.sourceVersion && <MSkTag>v{item.sourceVersion}</MSkTag>}
      </div>
      <p style={{ margin: 0, fontSize: 12.5, color: 'var(--text-secondary)', lineHeight: 1.6,
        display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{item.desc}</p>
      {item.upgradeVersion && !blocked && (
        <button className="press" onClick={() => onUpgrade(item)}
          style={{ marginTop: 10, display: 'inline-flex', alignItems: 'center', gap: 5, padding: '5px 12px',
            border: 'none', borderRadius: 'var(--r-pill)', background: 'color-mix(in srgb, var(--accent) 14%, transparent)', color: 'var(--accent-warm)',
            fontSize: 12, fontWeight: 600 }}><I.refresh s={13} />可升级到 v{item.upgradeVersion}</button>
      )}
      {blocked && (
        <button className="press" onClick={() => onRevoked(item)}
          style={{ marginTop: 10, display: 'flex', width: '100%', alignItems: 'center', gap: 6, padding: '8px 10px',
            border: 'none', borderRadius: 'var(--r-md)', background: 'color-mix(in srgb, var(--warning-text) 12%, transparent)', color: 'var(--warning)',
            fontSize: 12, fontWeight: 600, textAlign: 'left' }}><I.warn s={14} />已被撤销 · 运行时跳过执行<I.chevR s={14} style={{ marginLeft: 'auto' }} /></button>
      )}
    </div>
  );
}

/* ---------------- source cards ---------------- */
function MSkSourceCard({ item, badgeIcon, version, onInstall }) {
  const Cmp = I[badgeIcon] || I.spark;
  return (
    <div className="card" style={{ padding: '13px 14px' }}>
      <div className="row gap10" style={{ marginBottom: 8, alignItems: 'center' }}>
        <div style={{ width: 34, height: 34, borderRadius: 'var(--r-md)', flex: '0 0 auto', background: 'color-mix(in srgb, var(--accent) 13%, transparent)',
          color: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Cmp s={17} /></div>
        <span className="display" style={{ flex: 1, minWidth: 0, fontSize: 14.5, fontWeight: 700, color: 'var(--text-primary)',
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{item.name}</span>
        {version && <MSkTag>v{version}</MSkTag>}
      </div>
      <p style={{ margin: '0 0 8px', fontSize: 12.5, color: 'var(--text-muted)', lineHeight: 1.6,
        display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{item.desc}</p>
      <div className="row" style={{ flexWrap: 'wrap', gap: 6, marginBottom: 11 }}>
        {item.category && <MSkTag icon="bookmark" tone="accent">{item.category}</MSkTag>}
        {(item.tags || []).map(t => <MSkTag key={t}>{t}</MSkTag>)}
      </div>
      <div className="row gap8">
        {item.updatedAt && <span style={{ fontSize: 11, color: 'var(--text-subtle)' }}>更新于 {item.updatedAt}</span>}
        <div style={{ flex: 1 }} />
        <button className="btn-accent press" onClick={() => onInstall(item)} style={{ height: 34, padding: '0 16px', fontSize: 13 }}>安装</button>
      </div>
    </div>
  );
}

function MSkMarketCard({ item, onOpen }) {
  return (
    <div className="card press" onClick={() => onOpen(item)} style={{ padding: '13px 14px' }}>
      <div className="row gap10" style={{ marginBottom: 8, alignItems: 'center' }}>
        <div style={{ width: 34, height: 34, borderRadius: 'var(--r-md)', flex: '0 0 auto', background: 'color-mix(in srgb, var(--accent) 13%, transparent)',
          color: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><I.storefront s={17} /></div>
        <span className="display" style={{ flex: 1, minWidth: 0, fontSize: 14.5, fontWeight: 700, color: 'var(--text-primary)',
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{item.name}</span>
        <I.chevR s={17} c="var(--text-subtle)" />
      </div>
      <p style={{ margin: '0 0 9px', fontSize: 12.5, color: 'var(--text-muted)', lineHeight: 1.6,
        display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{item.desc}</p>
      <div className="row gap12">
        <span className="row gap4" style={{ fontSize: 11, color: 'var(--text-subtle)' }}><I.user s={12} />{item.author}</span>
        <span className="row gap4" style={{ fontSize: 11, color: 'var(--text-subtle)' }}><I.history s={12} />{item.installs.toLocaleString()}</span>
        <div style={{ flex: 1 }} />
        <MSkTag>v{item.version}</MSkTag>
      </div>
    </div>
  );
}

function MSkMarketDetail({ item, onBack, onInstall }) {
  const [ref, scrolled] = useScrolled();
  return (
    <div className="screen fade-in" data-screen-label="agent-skill-market-detail">
      <PageHead title={item.name} onBack={onBack} scrolled={scrolled} center />
      <div className="viewport" ref={ref} style={{ padding: '10px 18px 28px' }}>
        <div className="row gap12" style={{ alignItems: 'center', marginBottom: 14 }}>
          <div style={{ width: 52, height: 52, borderRadius: 'var(--r-xl)', flex: '0 0 auto', background: 'color-mix(in srgb, var(--accent) 13%, transparent)',
            color: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><I.storefront s={26} /></div>
          <div className="col" style={{ flex: 1, gap: 3, minWidth: 0 }}>
            <span className="display" style={{ fontSize: 18, fontWeight: 700, color: 'var(--text-primary)' }}>{item.name}</span>
            <span className="row gap8" style={{ fontSize: 12, color: 'var(--text-muted)' }}>
              <span className="row gap4"><I.user s={12} />{item.author}</span>
              <span className="row gap4"><I.history s={12} />{item.installs.toLocaleString()} 次安装</span>
            </span>
          </div>
        </div>

        <button className="btn-accent press" onClick={() => onInstall(item)}
          style={{ width: '100%', height: 46, marginBottom: 18, fontSize: 14 }}>安装当前版本 v{item.version}</button>

        <div className="row" style={{ flexWrap: 'wrap', gap: 6, marginBottom: 18 }}>
          {item.category && <MSkTag icon="bookmark" tone="accent">{item.category}</MSkTag>}
          {(item.tags || []).map(t => <MSkTag key={t}>{t}</MSkTag>)}
        </div>

        <SectionLabel text="使用时机" />
        <p style={{ margin: '0 0 18px', fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.75 }}>{item.whenToUse}</p>
        <SectionLabel text="描述" />
        <p style={{ margin: '0 0 18px', fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.75 }}>{item.desc}</p>

        <SectionLabel text="版本记录" />
        <div className="col gap8">
          {item.versions.map((v, i) => (
            <div key={v.version} className="row gap10" style={{ padding: '10px 12px', background: 'var(--surface-container)',
              border: '1px solid var(--border-subtle)', borderRadius: 'var(--r-lg)', alignItems: 'flex-start' }}>
              <span style={{ fontSize: 12.5, fontWeight: 600, fontFamily: 'var(--mono)', color: 'var(--text-secondary)', flex: '0 0 auto' }}>v{v.version}</span>
              <div className="col" style={{ flex: 1, gap: 2, minWidth: 0 }}>
                <span style={{ fontSize: 12.5, color: 'var(--text-secondary)', lineHeight: 1.5 }}>{v.note}</span>
                <span style={{ fontSize: 11, color: 'var(--text-subtle)' }}>{v.date}</span>
              </div>
              {i === 0 && v.status === 'approved' && <MSkTag tone="accent">当前</MSkTag>}
              {v.status === 'revoked' && <MSkTag>已撤销</MSkTag>}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

/* ---------------- category filter strip ---------------- */
function MSkFilter({ value, onChange }) {
  return (
    <div style={{ display: 'flex', gap: 7, overflowX: 'auto', padding: '10px 16px 2px' }}>
      {['全部', ...MSK_CATEGORIES].map(c => {
        const on = value === c;
        return (
          <button key={c} className="press" onClick={() => onChange(c)}
            style={{ flex: '0 0 auto', height: 28, padding: '0 12px', borderRadius: 'var(--r-pill)', fontSize: 12, fontWeight: 600,
              background: on ? 'var(--selected)' : 'transparent', color: on ? 'var(--accent-warm)' : 'var(--text-muted)',
              border: '1px solid ' + (on ? 'var(--accent)' : 'var(--border-subtle)') }}>{c}</button>
        );
      })}
    </div>
  );
}

/* ---------------- sheets ---------------- */
function MSkConflictSheet({ item, installed, onClose, onOverwrite, onRename }) {
  const [name, setName] = useState('');
  const existing = installed.find(n => n.name === item.name);
  const taken = installed.some(n => n.callName === name.trim());
  const invalid = !name.trim() || taken;
  return (
    <Sheet onClose={onClose} max="70%">
      <SheetHeader
        iconBox={<div style={{ width: 34, height: 34, borderRadius: 'var(--r-md)', flex: '0 0 auto', background: 'color-mix(in srgb, var(--warning-text) 12%, transparent)', color: 'var(--warning)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><I.warn s={18} /></div>}
        title="调用名冲突" sub={`已存在调用名 “${existing ? existing.callName : ''}”`} />
      <div style={{ overflowY: 'auto', padding: '14px 18px calc(env(safe-area-inset-bottom,0px) + 20px)' }}>
        <p style={{ margin: '0 0 16px', fontSize: 12.5, color: 'var(--text-muted)', lineHeight: 1.65 }}>
          覆盖会替换目标记录并解除旧来源关联;重命名会保留两条独立安装,不影响后续升级。</p>
        <Field label="新调用名" hint={taken ? '该调用名已被占用' : '本小说内唯一,是 Agent 工具的有效名称'}>
          <input className="tinput" value={name} onChange={e => setName(e.target.value)} placeholder="例如 lore_audit_2"
            style={{ fontFamily: 'var(--mono)', borderColor: taken ? 'var(--error)' : undefined }} />
        </Field>
        <div className="col gap8" style={{ marginTop: 4 }}>
          <button className="btn-accent press" disabled={invalid} onClick={() => onRename(item, name.trim())}
            style={{ height: 46, opacity: invalid ? 0.5 : 1 }}>以新调用名安装</button>
          <button className="btn-ghost press" onClick={() => onOverwrite(item)} style={{ height: 44 }}>覆盖现有</button>
        </div>
      </div>
    </Sheet>
  );
}

function MSkConfirmSheet({ icon, iconColor, iconBg, title, sub, body, extra, confirmLabel, onConfirm, onClose }) {
  const Cmp = I[icon] || I.info;
  return (
    <Sheet onClose={onClose} max="72%">
      <SheetHeader
        iconBox={<div style={{ width: 34, height: 34, borderRadius: 'var(--r-md)', flex: '0 0 auto', background: iconBg || 'color-mix(in srgb, var(--accent) 13%, transparent)', color: iconColor || 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Cmp s={18} /></div>}
        title={title} sub={sub} />
      <div style={{ overflowY: 'auto', padding: '14px 18px calc(env(safe-area-inset-bottom,0px) + 20px)' }}>
        {body && <p style={{ margin: '0 0 14px', fontSize: 12.5, color: 'var(--text-muted)', lineHeight: 1.7 }}>{body}</p>}
        {extra}
        {onConfirm && (
          <button className="btn-accent press" onClick={onConfirm} style={{ width: '100%', height: 46, marginTop: 6 }}>{confirmLabel}</button>
        )}
      </div>
    </Sheet>
  );
}

function MSkCreateSheet({ onClose, onConfirm }) {
  const [cat, setCat] = useState(MSK_CATEGORIES[0]);
  return (
    <Sheet onClose={onClose} max="88%">
      <SheetHeader
        iconBox={<div style={{ width: 34, height: 34, borderRadius: 'var(--r-md)', flex: '0 0 auto', background: 'color-mix(in srgb, var(--accent) 13%, transparent)', color: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><I.pencil s={18} /></div>}
        title="创建本地技能" sub="本地创建的技能直接安装到当前小说"
        right={<button className="press" onClick={onConfirm} style={{ height: 32, padding: '0 16px', borderRadius: 'var(--r-pill)', background: 'var(--accent)', color: 'var(--on-accent)', border: 'none', fontSize: 13, fontWeight: 600 }}>创建</button>} />
      <div style={{ overflowY: 'auto', padding: '14px 18px calc(env(safe-area-inset-bottom,0px) + 20px)' }}>
        <Field label="名称"><input className="tinput" placeholder="技能名称" /></Field>
        <Field label="调用名" hint="本小说内唯一,小写字母与下划线"><input className="tinput" placeholder="expand_scene" style={{ fontFamily: 'var(--mono)' }} /></Field>
        <Field label="使用时机"><textarea className="tarea" rows={2} placeholder="描述什么情况下应该调用这个技能…" /></Field>
        <Field label="描述"><textarea className="tarea" rows={2} placeholder="一句话说明这个技能做什么…" /></Field>
        <Field label="类别">
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7 }}>
            {MSK_CATEGORIES.map(c => (
              <button key={c} className={'tchip press' + (cat === c ? ' on' : '')} onClick={() => setCat(c)}>{c}</button>
            ))}
          </div>
        </Field>
        <Field label="提示词" hint="技能被调用时注入主笔的指令。">
          <textarea className="tarea" rows={7} placeholder="描述这个技能的执行步骤与输出要求…" style={{ fontFamily: 'var(--mono)', fontSize: 13 }} />
        </Field>
      </div>
    </Sheet>
  );
}

function MSkRowActionsSheet({ item, onClose, onAction }) {
  const rows = [
    { k: 'saveLib', icon: 'save', label: '保存到技能库' },
    { k: 'rename', icon: 'pencil', label: '重命名调用名' },
    { k: 'remove', icon: 'trash', label: '移除', danger: true },
  ];
  return (
    <Sheet onClose={onClose} max="50%">
      <SheetHeader
        iconBox={<div style={{ width: 34, height: 34, borderRadius: 'var(--r-md)', flex: '0 0 auto', background: 'var(--surface-dim)', color: 'var(--text-secondary)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><I.spark s={18} /></div>}
        title={item.name} sub={item.callName} />
      <div style={{ padding: '6px 10px calc(env(safe-area-inset-bottom,0px) + 16px)' }}>
        {rows.map(r => {
          const Cmp = I[r.icon];
          return (
            <div key={r.k} className="srow press" onClick={() => onAction(r.k, item)}>
              <div className="sicon" style={{ background: r.danger ? 'color-mix(in srgb, var(--error) 10%, transparent)' : 'var(--surface-dim)', color: r.danger ? 'var(--error)' : 'var(--text-secondary)' }}><Cmp s={17} /></div>
              <span style={{ flex: 1, fontSize: 14.5, fontWeight: 500, color: r.danger ? 'var(--error)' : 'var(--text-primary)' }}>{r.label}</span>
            </div>
          );
        })}
      </div>
    </Sheet>
  );
}

/* ---------------- hub ---------------- */
const MSK_TABS = [
  { id: 'installed', label: '已安装' },
  { id: 'library', label: '技能库' },
  { id: 'official', label: '官方目录' },
  { id: 'market', label: '市场' },
];

function SkillSetupScreen({ novel, home, onBack }) {
  const tabs = home ? MSK_TABS.filter(t => t.id !== 'installed') : MSK_TABS;
  const [tab, setTab] = useState(home ? 'library' : 'installed');
  const [installed, setInstalled] = useState(() => MSK_INSTALLED.map(s => ({ ...s })));
  const [sheet, setSheet] = useState(null); // {type, item}
  const [detail, setDetail] = useState(null);
  const [cat, setCat] = useState('全部');
  const [toast, setToast] = useState(null);
  const [ref, scrolled] = useScrolled();

  const novelTitle = (novel && novel.title) || '夜航船';

  useEffect(() => {
    if (!toast) { return; }
    const t = setTimeout(() => setToast(null), 2200);
    return () => clearTimeout(t);
  }, [toast]);

  const flash = (m) => setToast(m);
  const close = () => setSheet(null);

  const install = (item) => {
    if (home) { flash('在作品内可将其安装到具体小说。'); return; }
    if (installed.some(n => n.name === item.name)) {
      setSheet({ type: 'conflict', item });
    } else {
      addInstalled(item, item.name);
      flash(`已安装“${item.name}”。`);
    }
  };
  const addInstalled = (item, name) => setInstalled(list => [...list, {
    id: 'nas-' + Math.random().toString(36).slice(2, 7), callName: (name || item.name).toString(),
    sourceKind: item.author ? 'marketplace' : item.version ? 'official' : 'library',
    sourceVersion: item.version, name: item.name, enabled: true, desc: item.desc,
  }]);
  const onOverwrite = (item) => { setInstalled(list => list.map(n => n.name === item.name ? { ...n, sourceVersion: item.version } : n)); close(); flash(`已覆盖“${item.name}”。`); };
  const onRename = (item, callN) => { addInstalled(item, callN); close(); flash(`已以调用名 ${callN} 安装。`); };

  const toggleEnabled = (id) => setInstalled(list => list.map(n => n.id === id ? { ...n, enabled: !n.enabled } : n));
  const onRowAction = (action, item) => {
    close();
    if (action === 'remove') { setInstalled(list => list.filter(n => n.id !== item.id)); flash(`已移除“${item.name}”。`); }
    else if (action === 'saveLib') { flash(`已保存“${item.name}”到技能库。`); }
    else if (action === 'rename') { flash('重命名调用名(示例)。'); }
  };

  const filtered = (arr) => cat === '全部' ? arr : arr.filter(x => x.category === cat);
  const browseTab = tab === 'library' || tab === 'official' || (tab === 'market' && !detail);

  const counts = { installed: installed.length, library: MSK_LIBRARY.length, official: MSK_OFFICIAL.length, market: MSK_MARKET.length };

  // market detail takes over the whole screen
  if (detail) {
    return <MSkMarketDetail item={detail} onBack={() => setDetail(null)} onInstall={(it) => { install(it); }} />;
  }

  return (
    <div className="screen fade-in" data-screen-label={home ? 'skill-library' : 'novel-agent-skills-setup'}>
      <PageHead title={home ? '技能库' : '智能体技能'} sub={home ? '可安装到任意小说' : `为《${novelTitle}》安装管理`}
        onBack={onBack} scrolled={scrolled} center
        right={!home && tab === 'installed'
          ? <IconBtn icon="plus" ariaLabel="创建本地技能" onClick={() => setSheet({ type: 'create' })} />
          : <div style={{ width: 38 }} />} />

      {/* tab strip */}
      <div style={{ display: 'flex', gap: 7, overflowX: 'auto', padding: '2px 16px 10px', flex: '0 0 auto',
        borderBottom: '1px solid var(--border-subtle)', background: 'var(--canvas)' }}>
        {tabs.map(t => {
          const on = tab === t.id;
          return (
            <button key={t.id} className="press" onClick={() => { setTab(t.id); setDetail(null); }}
              style={{ flex: '0 0 auto', height: 32, padding: '0 13px', borderRadius: 'var(--r-pill)', display: 'flex', alignItems: 'center', gap: 6,
                fontSize: 12.5, fontWeight: 600, background: on ? 'var(--selected)' : 'transparent',
                color: on ? 'var(--accent-warm)' : 'var(--text-muted)', border: '1px solid ' + (on ? 'var(--accent)' : 'var(--border-subtle)') }}>
              {t.label}<span style={{ fontSize: 10.5, opacity: 0.8 }}>{counts[t.id]}</span>
            </button>
          );
        })}
      </div>

      {browseTab && <MSkFilter value={cat} onChange={setCat} />}

      <div className="viewport" ref={ref} style={{ padding: browseTab ? '10px 16px 28px' : '14px 16px 28px' }}>
        {tab === 'installed' && (
          installed.length === 0 ? (
            <Empty icon="spark" text="未安装技能" sub="仍可正常聊天与编辑。从技能库、官方目录或市场安装,或创建一个本地技能。" />
          ) : (
            <React.Fragment>
              <p style={{ margin: '0 4px 12px', fontSize: 12, color: 'var(--text-muted)', lineHeight: 1.6 }}>
                运行时只读取本小说中已启用、未被撤销的技能。</p>
              <div className="col gap10">
                {installed.map(it => (
                  <MSkInstalledCard key={it.id} item={it} onToggle={toggleEnabled}
                    onActions={(i) => setSheet({ type: 'rowActions', item: i })}
                    onUpgrade={(i) => setSheet({ type: 'upgrade', item: i })}
                    onRevoked={(i) => setSheet({ type: 'revoked', item: i })} />
                ))}
              </div>
            </React.Fragment>
          )
        )}

        {tab === 'library' && (
          <div className="col gap10">
            {filtered(MSK_LIBRARY).map(it => (
              <MSkSourceCard key={it.id} item={it} badgeIcon="save" onInstall={install} />
            ))}
          </div>
        )}

        {tab === 'official' && (
          <div className="col gap10">
            {filtered(MSK_OFFICIAL).map(it => (
              <MSkSourceCard key={it.id} item={it} badgeIcon="shield" version={it.version} onInstall={install} />
            ))}
          </div>
        )}

        {tab === 'market' && (
          <div className="col gap10">
            {filtered(MSK_MARKET).map(it => <MSkMarketCard key={it.id} item={it} onOpen={setDetail} />)}
          </div>
        )}

      </div>

      {sheet && sheet.type === 'conflict' && (
        <MSkConflictSheet item={sheet.item} installed={installed} onClose={close} onOverwrite={onOverwrite} onRename={onRename} />
      )}
      {sheet && sheet.type === 'upgrade' && (
        <MSkConfirmSheet icon="refresh" title="升级技能" sub={sheet.item.name} confirmLabel="确认升级"
          body="确认后才会覆盖快照内容与来源版本,保留调用名、启用状态与排序。既有正文不受影响。"
          extra={<div className="row" style={{ justifyContent: 'center', gap: 12, padding: '4px 0 14px', fontFamily: 'var(--mono)', fontSize: 15 }}>
            <span style={{ color: 'var(--text-muted)' }}>v{sheet.item.sourceVersion}</span><I.arrowR s={16} c="var(--text-subtle)" /><span style={{ color: 'var(--accent)', fontWeight: 700 }}>v{sheet.item.upgradeVersion}</span></div>}
          onConfirm={() => { setInstalled(list => list.map(n => n.id === sheet.item.id ? { ...n, sourceVersion: sheet.item.upgradeVersion, upgradeVersion: undefined } : n)); close(); flash(`已升级到 v${sheet.item.upgradeVersion}。`); }}
          onClose={close} />
      )}
      {sheet && sheet.type === 'saveLib' && (
        <MSkConfirmSheet icon="save" title="保存到技能库" sub={sheet.item.name} confirmLabel="保存副本"
          body="从当前快照创建一份独立副本到私有技能库。这是一次复制,不会修改原技能,也不建立双向同步。"
          onConfirm={() => { close(); flash(`已保存“${sheet.item.name}”到技能库。`); }} onClose={close} />
      )}
      {sheet && sheet.type === 'revoked' && (
        <MSkConfirmSheet icon="warn" iconColor="var(--warning)" iconBg="color-mix(in srgb, var(--warning-text) 12%, transparent)" title="该技能已被撤销" sub={sheet.item.name}
          body={sheet.item.executionBlockedReason + ' 本地内容已保留,但运行时会跳过执行,直到安装一个未被撤销的版本。'}
          confirmLabel="知道了" onConfirm={close} onClose={close} />
      )}
      {sheet && sheet.type === 'create' && <MSkCreateSheet onClose={close} onConfirm={() => { close(); flash('已创建本地技能。'); }} />}
      {sheet && sheet.type === 'rowActions' && <MSkRowActionsSheet item={sheet.item} onClose={close} onAction={onRowAction} />}

      {toast && <MSkToast text={toast} />}
    </div>
  );
}

Object.assign(window, { SkillSetupScreen });
