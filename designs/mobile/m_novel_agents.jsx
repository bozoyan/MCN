/* ============================================================
   小说级智能体规则 / 技能 — 移动端
   对齐桌面端 lib/desktop/widgets/agent_management/ 下的
   AgentRuleEditPanel / AgentRulesEmptyState / AgentSkillList /
   AgentSkillEditPanel，以及 rail 的 AI 分区入口。
   数据：NOVEL_AGENT_RULES（作品库）、NOVEL_AGENT_SKILLS（全局库 scope=novel）。
   ============================================================ */

/* ---------- 通用：启用/停用小徽章 ---------- */
function EnableChip({enabled}){
  return <span className="chip" style={{height:20, fontSize:10.5, padding:'0 8px', flex:'0 0 auto',
    color:enabled?'var(--success)':'var(--text-subtle)',
    background:enabled?'color-mix(in srgb, var(--success) 12%, transparent)':'var(--surface-dim)', fontWeight:600}}>
    {enabled?'已启用':'已停用'}</span>;
}

/* ============================================================
   智能体规则 — 列表
   ============================================================ */
function NovelAgentRulesScreen({onBack, onOpenEdit}){
  const [ref, scrolled] = useScrolled();
  const [deleted, setDeleted] = useState([]);
  const del = (id)=> setDeleted(d=> d.includes(id)?d:[...d,id]);
  const items = NOVEL_AGENT_RULES.filter(r=>!deleted.includes(r.id));

  return (
    <div className="screen fade-in" data-screen-label="novel-agent-rules">
      <PageHead title="智能体规则" onBack={onBack} scrolled={scrolled} center
        right={<IconBtn icon="plus" ariaLabel="新建规则" onClick={()=>onOpenEdit({isNew:true})}/>}/>
      <div className="viewport" ref={ref} style={{padding:'12px 18px 28px'}}>
        <p style={{margin:'0 4px 14px', fontSize:12.5, color:'var(--text-muted)', lineHeight:1.65}}>
          为《夜航船》设定主笔必须遵守的规则，会作为系统约束注入每次对话。</p>

        {items.length===0 ? (
          <Empty icon="shield" text="还没有规则"
            sub="规则用于约束文风、视角、考据底线等。新建一条规则开始约束主笔。"/>
        ) : (
          <div className="col gap10">
            {items.map(r=>(
              <SwipeRow key={r.id} onDelete={()=>del(r.id)}>
                <div className="card press" onClick={()=>onOpenEdit(r)} style={{padding:'13px 14px'}}>
                  <div className="row gap8" style={{marginBottom:6}}>
                    <I.shield s={16} c="var(--accent-warm)"/>
                    <span className="display" style={{flex:1, fontSize:14.5, fontWeight:700, color:'var(--text-primary)'}}>{r.name}</span>
                    <EnableChip enabled={r.enabled}/>
                  </div>
                  <p style={{margin:0, fontSize:12.5, color:'var(--text-secondary)', lineHeight:1.6,
                    display:'-webkit-box', WebkitLineClamp:3, WebkitBoxOrient:'vertical', overflow:'hidden'}}>{r.content}</p>
                </div>
              </SwipeRow>
            ))}
          </div>
        )}

        <button className="btn-ghost press" onClick={()=>onOpenEdit({isNew:true})}
          style={{width:'100%', height:44, marginTop:14, borderStyle:'dashed', color:'var(--accent-warm)', fontWeight:600}}>
          <I.plus s={16}/>新建规则</button>
      </div>
    </div>
  );
}

/* ---------- 智能体规则 — 编辑 ---------- */
function NovelAgentRuleEditScreen({entity, onBack}){
  const isNew = !entity || entity.isNew;
  const e = entity||{};
  const [enabled, setEnabled] = useState(e.enabled!==false);
  const [ref, scrolled] = useScrolled();

  return (
    <div className="screen fade-in" data-screen-label="novel-agent-rule-edit">
      <PageHead title={isNew?'新建规则':e.name} onBack={onBack} scrolled={scrolled} center
        right={<button className="press" style={{height:32, padding:'0 16px', borderRadius:'var(--r-pill)',
          background:'var(--accent)', color:'var(--on-accent)', border:'none', fontSize:13, fontWeight:600}}>保存</button>}/>
      <div className="viewport" ref={ref} style={{padding:'14px 20px 28px'}}>
        {/* hero */}
        <div className="row gap12" style={{marginBottom:18, alignItems:'center'}}>
          <div style={{width:60,height:60,borderRadius:'var(--r-2xl)',flex:'0 0 auto',background:'color-mix(in srgb, var(--accent-warm) 14%, transparent)',
            display:'flex',alignItems:'center',justifyContent:'center',color:'var(--accent-warm)'}}><I.shield s={28}/></div>
          <div className="col" style={{flex:1, gap:4, minWidth:0}}>
            <span className="display" style={{fontSize:18, fontWeight:700, color:'var(--text-primary)'}}>{isNew?'新建规则':e.name}</span>
            <span style={{fontSize:12, color:'var(--text-muted)'}}>编辑规则的约束内容</span>
          </div>
        </div>

        {/* enable toggle */}
        <div className="card" style={{padding:'12px 14px', display:'flex', alignItems:'center', gap:10, marginBottom:18}}>
          <div className="col" style={{flex:1, gap:2}}>
            <span style={{fontSize:14, fontWeight:600, color:'var(--text-primary)'}}>启用</span>
            <span style={{fontSize:11.5, color:'var(--text-muted)'}}>停用后该规则不会注入对话</span>
          </div>
          <Switch on={enabled} onToggle={()=>setEnabled(v=>!v)}/>
        </div>

        <Field label="名称">
          <input className="tinput" defaultValue={e.name||''} placeholder="规则名称，如「文风约束」"/>
        </Field>

        <Field label="规则内容" hint="用自然语言描述主笔必须遵守的约束。保存后可拖拽到对话框即时生效。">
          <textarea className="tarea" rows={9} defaultValue={e.content||''}
            style={{fontFamily:'var(--mono)', fontSize:13}}
            placeholder="例：正文以白描为主，少用形容词堆叠……"/>
        </Field>

        {!isNew && (
          <button className="btn-ghost press" style={{width:'100%', height:44, marginTop:8,
            color:'var(--error)', borderColor:'color-mix(in srgb, var(--error) 40%, transparent)'}}>
            <I.trash s={16}/>删除规则</button>
        )}
      </div>
    </div>
  );
}

/* ============================================================
   智能体技能 — 列表（本作品技能 + 全局技能）
   ============================================================ */
function NovelAgentSkillsScreen({onBack, onOpenEdit}){
  const [ref, scrolled] = useScrolled();
  const [deleted, setDeleted] = useState([]);
  const del = (id)=> setDeleted(d=> d.includes(id)?d:[...d,id]);
  const novelItems = NOVEL_AGENT_SKILLS.filter(s=>!deleted.includes(s.id));

  return (
    <div className="screen fade-in" data-screen-label="novel-agent-skills">
      <PageHead title="智能体技能" onBack={onBack} scrolled={scrolled} center
        right={<IconBtn icon="plus" ariaLabel="新建技能" onClick={()=>onOpenEdit({isNew:true})}/>}/>
      <div className="viewport" ref={ref} style={{padding:'12px 18px 28px'}}>
        <p style={{margin:'0 4px 14px', fontSize:12.5, color:'var(--text-muted)', lineHeight:1.65}}>
          本作品专属的可调用技能；全局技能在所有作品中共享。</p>

        <SectionLabel text="本作品技能" right={
          <button className="press" onClick={()=>onOpenEdit({isNew:true})} style={{background:'transparent', border:'none',
            color:'var(--accent-warm)', fontSize:12.5, fontWeight:600, display:'flex', alignItems:'center', gap:2, cursor:'pointer'}}>
            <I.plus s={14}/>新建</button>}/>

        {novelItems.length===0 ? (
          <Empty icon="spark" text="还没有作品技能"
            sub="为本作品新建一个技能，描述它的触发时机与提示词。"/>
        ) : (
          <div className="col gap10" style={{marginBottom:22}}>
            {novelItems.map(s=>(
              <SwipeRow key={s.id} onDelete={()=>del(s.id)}>
                <div className="card press" onClick={()=>onOpenEdit(s)} style={{padding:'13px 14px'}}>
                  <div className="row gap8" style={{marginBottom:6}}>
                    <I.spark s={16} c="var(--accent)"/>
                    <span className="display" style={{flex:1, fontSize:14.5, fontWeight:700, color:'var(--text-primary)'}}>{s.name}</span>
                    <span className="chip" style={{height:18, fontSize:10, padding:'0 7px', flex:'0 0 auto',
                      background:'color-mix(in srgb, var(--accent) 12%, transparent)', color:'var(--accent-warm)', fontWeight:600}}>本作品</span>
                    <EnableChip enabled={s.enabled}/>
                  </div>
                  <p style={{margin:0, fontSize:12.5, color:'var(--text-secondary)', lineHeight:1.6,
                    display:'-webkit-box', WebkitLineClamp:2, WebkitBoxOrient:'vertical', overflow:'hidden'}}>{s.desc}</p>
                </div>
              </SwipeRow>
            ))}
          </div>
        )}

        <SectionLabel text="全局技能" right={
          <span style={{fontSize:11.5, color:'var(--text-subtle)'}}>在「AI」tab 管理</span>}/>
        <div className="col gap10">
          {SKILLS.map(s=>(
            <div key={s.id} className="card" style={{padding:'13px 14px'}}>
              <div className="row gap8" style={{marginBottom:6}}>
                <I.spark s={16} c="var(--text-muted)"/>
                <span className="display" style={{flex:1, fontSize:14.5, fontWeight:700, color:'var(--text-primary)'}}>{s.name}</span>
                {s.builtin && <span className="chip" style={{height:18, fontSize:10, padding:'0 7px', flex:'0 0 auto',
                  background:'var(--surface-dim)', color:'var(--text-subtle)'}}>内置</span>}
                <span className="chip" style={{height:18, fontSize:10, padding:'0 7px', flex:'0 0 auto',
                  background:'var(--surface-dim)', color:'var(--text-muted)'}}>全局</span>
              </div>
              <p style={{margin:0, fontSize:12.5, color:'var(--text-muted)', lineHeight:1.6,
                display:'-webkit-box', WebkitLineClamp:2, WebkitBoxOrient:'vertical', overflow:'hidden'}}>{s.desc}</p>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

/* ---------- 智能体技能 — 编辑 ---------- */
function NovelAgentSkillEditScreen({entity, onBack}){
  const isNew = !entity || entity.isNew;
  const e = entity||{};
  const [enabled, setEnabled] = useState(e.enabled!==false);
  const [ref, scrolled] = useScrolled();

  return (
    <div className="screen fade-in" data-screen-label="novel-agent-skill-edit">
      <PageHead title={isNew?'新建技能':e.name} onBack={onBack} scrolled={scrolled} center
        right={<button className="press" style={{height:32, padding:'0 16px', borderRadius:'var(--r-pill)',
          background:'var(--accent)', color:'var(--on-accent)', border:'none', fontSize:13, fontWeight:600}}>保存</button>}/>
      <div className="viewport" ref={ref} style={{padding:'14px 20px 28px'}}>
        {/* hero */}
        <div className="row gap12" style={{marginBottom:18, alignItems:'center'}}>
          <div style={{width:60,height:60,borderRadius:'var(--r-2xl)',flex:'0 0 auto',background:'color-mix(in srgb, var(--accent) 13%, transparent)',
            display:'flex',alignItems:'center',justifyContent:'center',color:'var(--accent)'}}><I.spark s={28}/></div>
          <div className="col" style={{flex:1, gap:4, minWidth:0}}>
            <span className="display" style={{fontSize:18, fontWeight:700, color:'var(--text-primary)'}}>{isNew?'新建技能':e.name}</span>
            <span style={{fontSize:12, color:'var(--text-muted)'}}>编辑触发时机与提示词</span>
          </div>
        </div>

        {/* enable toggle */}
        <div className="card" style={{padding:'12px 14px', display:'flex', alignItems:'center', gap:10, marginBottom:18}}>
          <div className="col" style={{flex:1, gap:2}}>
            <span style={{fontSize:14, fontWeight:600, color:'var(--text-primary)'}}>启用</span>
            <span style={{fontSize:11.5, color:'var(--text-muted)'}}>停用后不会出现在主笔的可调用列表中</span>
          </div>
          <Switch on={enabled} onToggle={()=>setEnabled(v=>!v)}/>
        </div>

        <Field label="名称">
          <input className="tinput" defaultValue={e.name||''} placeholder="技能名称，如「漕运术语校对」"/>
        </Field>

        <Field label="使用时机" hint="描述何时应当触发此技能。">
          <textarea className="tarea" rows={2} defaultValue={e.when||''}
            placeholder="当……时使用。"/>
        </Field>

        <Field label="描述">
          <textarea className="tarea" rows={3} defaultValue={e.desc||''} placeholder="一句话说明它的职责"/>
        </Field>

        <Field label="提示词" hint="技能被调用时注入主笔的指令。">
          <textarea className="tarea" rows={9} defaultValue={e.prompt||''}
            style={{fontFamily:'var(--mono)', fontSize:13}}
            placeholder="描述职责、输入与输出格式…"/>
        </Field>

        {!isNew && (
          <button className="btn-ghost press" style={{width:'100%', height:44, marginTop:8,
            color:'var(--error)', borderColor:'color-mix(in srgb, var(--error) 40%, transparent)'}}>
            <I.trash s={16}/>删除技能</button>
        )}
      </div>
    </div>
  );
}

Object.assign(window, {
  NovelAgentRulesScreen, NovelAgentRuleEditScreen,
  NovelAgentSkillsScreen, NovelAgentSkillEditScreen,
});
