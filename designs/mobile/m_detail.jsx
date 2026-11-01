/* ============================================================
   Novel content · 详情页（全屏 overlay 推入）
   优化「设定 / 大纲 / 伏笔 / 物品 / 势力 / 生物 / 地图 / 素材」的
   详情阅读页：统一的实体头图 + 结构化字段 + 正文 + 交叉引用 + AI 入口。
   对齐 lib/mobile/pages/entry_editor_page.dart / foreshadowing_editor_page.dart
   的字段模型；阅读型详情 + 顶部「编辑」按钮（与 CharacterDetail 一致）。
   ============================================================ */

/* ---- 交叉引用解析：{kind,id} → 渲染描述符 ---- */
const REF_KIND_META = {
  character: {icon:'user',    fallback:'#2D3A36'},
  world:     {icon:'globe',   fallback:'var(--info)'},
  item:      {icon:'diamond', fallback:'#6E5D6B'},
  faction:   {icon:'shield',  fallback:'var(--info)'},
  creature:  {icon:'leaf',    fallback:'#4E7F6E'},
  foreshadow:{icon:'flag',    fallback:'var(--accent-warm)'},
  location:  {icon:'map',     fallback:'var(--accent)'},
};

function findChapter(id){
  for(const v of VOLUMES){ for(const ch of v.items){ if(ch.id===id) return {...ch, volLabel:v.vol}; } }
  return null;
}

function resolveRef(ref){
  const km = REF_KIND_META[ref.kind] || {icon:'file', fallback:'var(--text-muted)'};
  let src, name, sub, tint = km.fallback, icon = km.icon;
  switch(ref.kind){
    case 'character': src = CHARACTERS.find(x=>x.id===ref.id); name=src?.name; sub=src?.role; tint=src?.tint||tint; break;
    case 'world':     src = WORLD.find(x=>x.id===ref.id);      name=src?.name; sub=src?.cat;  tint=src?.tint||tint; icon=src?.icon||icon; break;
    case 'item':      src = ITEMS.find(x=>x.id===ref.id);      name=src?.name; sub=src?.sub;  tint=src?.tint||tint; break;
    case 'faction':   src = FACTIONS.find(x=>x.id===ref.id);   name=src?.name; sub=src?.sub;  tint=src?.tint||tint; break;
    case 'creature':  src = CREATURES.find(x=>x.id===ref.id);  name=src?.name; sub=src?.sub;  tint=src?.tint||tint; break;
    case 'foreshadow':src = FORESHADOW.find(x=>x.id===ref.id); name=src?.name; sub=src?.status==='closed'?'已回收':'待回收'; tint='var(--accent-warm)'; break;
    case 'location':  src = LOCATIONS.find(x=>x.id===ref.id);  name=src?.name; sub=src?.region; tint=tint; break;
    default: break;
  }
  if(!src) return null;
  return {kind:ref.kind, id:ref.id, name, sub, tint, icon, src};
}

/* 引用行的前导视觉：人物用头像、物品用色块、其余用 EntityIcon */
function RefVisual({r, size=34}){
  if(r.kind==='character') return <Avatar label={r.name[0]} size={size} tint={r.tint} fs={size*0.4}/>;
  if(r.kind==='item') return <div style={{width:size,height:size,borderRadius:'var(--r-md)',flex:'0 0 auto',background:r.tint,boxShadow:'inset 0 0 0 1px rgba(255,255,255,.12)'}}></div>;
  return <EntityIcon icon={r.icon} hex={r.tint} s={size} is={size*0.5}/>;
}

/* 单条交叉引用行（注意：prop 不能命名为 ref，React 会拦截） */
function RefRow({rel, badge, onOpenRef}){
  const r = resolveRef(rel);
  if(!r) return null;
  return (
    <div className="card press" onClick={()=>onOpenRef && onOpenRef(rel)} style={{padding:'10px 12px', display:'flex', gap:10, alignItems:'center'}}>
      <RefVisual r={r}/>
      <div className="col" style={{flex:1, minWidth:0, gap:2}}>
        <span className="display" style={{fontSize:13.5, fontWeight:700, color:'var(--text-primary)', whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{r.name}</span>
        {r.sub && <span style={{fontSize:11, color:'var(--text-muted)'}}>{r.sub}</span>}
      </div>
      {badge && <span className="chip" style={{height:20,fontSize:10.5,padding:'0 8px',background:'var(--surface-dim)',color:'var(--text-muted)'}}>{badge}</span>}
      <I.chevR s={15} c="var(--text-subtle)"/>
    </div>
  );
}

/* 出现章节行 */
function ChapterRefRow({id, onOpenRef}){
  const ch = findChapter(id);
  if(!ch) return null;
  return (
    <div className="card press" onClick={()=>onOpenRef && onOpenRef({kind:'chapter', id})} style={{padding:'10px 12px', display:'flex', gap:11, alignItems:'center'}}>
      <span className="display" style={{width:26, textAlign:'center', fontSize:15, fontWeight:700, color:'var(--accent-warm)', flex:'0 0 auto'}}>{ch.n}</span>
      <div className="col" style={{flex:1, minWidth:0, gap:2}}>
        <span className="display" style={{fontSize:13.5, fontWeight:700, color:'var(--text-primary)'}}>{ch.t}</span>
        <span style={{fontSize:11, color:'var(--text-subtle)'}}>{ch.volLabel}</span>
      </div>
      <StateChip state={ch.state} small/>
      <I.chevR s={15} c="var(--text-subtle)"/>
    </div>
  );
}

/* 结构化字段表（slist） */
function MetaList({rows}){
  const items = (rows||[]).filter(Boolean);
  if(items.length===0) return null;
  return (
    <div className="slist" style={{marginBottom:18}}>
      {items.map(([k,v],i)=>(
        <div key={i} className="srow" style={{cursor:'default', minHeight:46}}>
          <span style={{fontSize:13, color:'var(--text-muted)', width:64, flex:'0 0 auto'}}>{k}</span>
          <span style={{flex:1, fontSize:13.5, color:'var(--text-primary)', textAlign:'right'}}>{v}</span>
        </div>
      ))}
    </div>
  );
}

/* 正文阅读区 */
function ReadingBody({paragraphs, fontSize=14.5}){
  const ps = (paragraphs||[]).filter(p=>p && p.trim());
  if(ps.length===0) return null;
  return (
    <div className="reading" style={{fontSize, lineHeight:1.85, marginBottom:18}}>
      {ps.map((p,i)=>(<p key={i} style={{marginBottom:14}}>{p}</p>))}
    </div>
  );
}

/* 交叉引用分组 */
function RefSection({title, count, children}){
  return (
    <div style={{marginBottom:18}}>
      <SectionLabel text={count!=null ? `${title} · ${count}` : title}/>
      <div className="col gap8">{children}</div>
    </div>
  );
}

/* AI 入口（次按钮） */
function AIAction({label, onClick}){
  return (
    <button className="btn-ghost press" onClick={onClick}
      style={{width:'100%', height:44, borderColor:'var(--accent)', color:'var(--accent-warm)', fontWeight:600, marginTop:2}}>
      <I.spark s={16} c="var(--accent)"/>{label}</button>
  );
}

/* ============================================================
   设定详情（优化版，替换原 WorldDetail）
   ============================================================ */
function WorldDetail({entity, onBack, onOpenRef, onOpenChat}){
  const [ref, scrolled] = useScrolled();
  const e = entity;
  return (
    <div className="screen fade-in" data-screen-label="world-detail">
      <PageHead title={e.name} sub={e.cat} onBack={onBack} scrolled={scrolled} center right={<IconBtn icon="pencil"/>}/>
      <div className="viewport" ref={ref} style={{padding:'8px 20px 28px'}}>
        <div className="col" style={{alignItems:'center', gap:10, padding:'8px 0 20px'}}>
          <EntityIcon icon={e.icon} hex={e.tint} s={68} is={34}/>
          <div className="col" style={{alignItems:'center', gap:6}}>
            <span className="display" style={{fontSize:21, fontWeight:700, letterSpacing:'-0.02em'}}>{e.name}</span>
            <span className="chip" style={{height:22, fontSize:11, padding:'0 10px', background:tint(e.tint,.13), color:e.tint, fontWeight:600}}>{e.cat}</span>
          </div>
        </div>
        <MetaList rows={e.fields}/>
        <SectionLabel text="设定正文"/>
        <ReadingBody paragraphs={e.body || [e.desc]}/>
        <AIAction label="用 AI 丰富这条设定" onClick={onOpenChat}/>
      </div>
    </div>
  );
}

/* ============================================================
   通用实体详情（图鉴：势力 / 生物 / 物品 / 技能）
   ============================================================ */
const ENTITY_KIND_META = {
  item:     {label:'物品', icon:'diamond', ai:'用 AI 补全这件物品'},
  faction:  {label:'势力', icon:'shield',  ai:'用 AI 梳理这股势力'},
  creature: {label:'生物', icon:'leaf',    ai:'用 AI 丰富这个生物'},
  skill:    {label:'技能', icon:'spark',   ai:'用 AI 完善这项技能'},
};
function EntityDetail({kind, entity, onBack, onOpenRef, onOpenChat}){
  const [ref, scrolled] = useScrolled();
  const e = entity;
  const km = ENTITY_KIND_META[kind] || ENTITY_KIND_META.item;
  const isItem = kind==='item';
  return (
    <div className="screen fade-in" data-screen-label={kind+"-detail"}>
      <PageHead title={e.name} sub={km.label} onBack={onBack} scrolled={scrolled} center right={<IconBtn icon="pencil"/>}/>
      <div className="viewport" ref={ref} style={{padding:'8px 20px 28px'}}>
        <div className="col" style={{alignItems:'center', gap:10, padding:'8px 0 20px'}}>
          {isItem
            ? <div style={{width:68,height:68,borderRadius:'var(--r-2xl)',background:e.tint,boxShadow:'inset 0 0 0 1px rgba(255,255,255,.16), 0 4px 14px color-mix(in srgb, var(--shadow-base) 16%, transparent)'}}></div>
            : <EntityIcon icon={km.icon} hex={e.tint} s={68} is={34}/>}
          <div className="col" style={{alignItems:'center', gap:6}}>
            <span className="display" style={{fontSize:21, fontWeight:700, letterSpacing:'-0.02em'}}>{e.name}</span>
            {e.sub && <span className="chip" style={{height:22, fontSize:11, padding:'0 10px', background:tint(e.tint,.14), color:e.tint, fontWeight:600}}>{e.sub}</span>}
          </div>
        </div>
        <MetaList rows={e.fields}/>
        <SectionLabel text="设定正文"/>
        <ReadingBody paragraphs={e.body || [e.desc]}/>
        <AIAction label={km.ai} onClick={onOpenChat}/>
      </div>
    </div>
  );
}

/* ============================================================
   伏笔详情 — 状态 + 埋设/回收章节 + 铺垫/兑现 + 关联
   对齐 foreshadowing_editor_page.dart 的字段模型
   ============================================================ */
function ForeshadowDetail({entity, onBack, onOpenRef, onOpenChat}){
  const [ref, scrolled] = useScrolled();
  const [tab, setTab] = useState('setup');
  const f = entity;
  const closed = f.status==='closed';
  const tn = closed ? {c:'var(--success)', bg:'color-mix(in srgb, var(--success) 13%, transparent)', t:'已回收'} : {c:'var(--warning)', bg:'color-mix(in srgb, var(--warning-text) 13%, transparent)', t:'待回收'};
  return (
    <div className="screen fade-in" data-screen-label="foreshadow-detail">
      <PageHead title={f.name} sub="伏笔" onBack={onBack} scrolled={scrolled} center right={<IconBtn icon="pencil"/>}/>
      <div className="viewport" ref={ref} style={{padding:'8px 20px 28px'}}>
        <div className="col" style={{alignItems:'center', gap:10, padding:'8px 0 18px'}}>
          <EntityIcon icon="flag" hex={tn.c} s={62} is={30}/>
          <div className="col" style={{alignItems:'center', gap:8}}>
            <span className="display" style={{fontSize:20, fontWeight:700, letterSpacing:'-0.02em', textAlign:'center'}}>{f.name}</span>
            <span className="chip" style={{height:24, fontSize:11.5, padding:'0 11px', color:tn.c, background:tn.bg, fontWeight:600}}>
              <span style={{width:6,height:6,borderRadius:'50%',background:tn.c}}></span>{tn.t}</span>
          </div>
        </div>

        {/* 埋设 → 回收 链路 */}
        <div className="card" style={{padding:'12px 14px', marginBottom:18}}>
          <div className="row" style={{justifyContent:'space-between', gap:8}}>
            <div className="col" style={{gap:4, flex:1}}>
              <span style={{fontSize:11, color:'var(--text-subtle)', letterSpacing:.4}}>埋设</span>
              <span style={{fontSize:13.5, fontWeight:600, color:'var(--text-primary)'}}>{f.plant}</span>
            </div>
            <div className="row" style={{alignItems:'center', flex:'0 0 auto', color:'var(--text-subtle)'}}><I.arrowR s={18}/></div>
            <div className="col" style={{gap:4, flex:1, alignItems:'flex-end'}}>
              <span style={{fontSize:11, color:'var(--text-subtle)', letterSpacing:.4}}>回收</span>
              <span style={{fontSize:13.5, fontWeight:600, color:closed?'var(--success)':'var(--text-primary)'}}>{f.payoff}</span>
            </div>
          </div>
        </div>

        {/* 铺垫 / 兑现 分段正文 */}
        <div className="seg" style={{marginBottom:12}}>
          <div className={"segopt"+(tab==='setup'?' active':'')} onClick={()=>setTab('setup')}>铺垫</div>
          <div className={"segopt"+(tab==='payoff'?' active':'')} onClick={()=>setTab('payoff')}>兑现</div>
        </div>
        <div className="reading fade-in" key={tab} style={{fontSize:14.5, lineHeight:1.85, marginBottom:18}}>
          <p style={{margin:0}}>{tab==='setup' ? (f.setupText||f.note) : (f.payoffText||f.note)}</p>
        </div>

        {(f.related||[]).length>0 && (
          <RefSection title="关联条目" count={f.related.length}>
            {f.related.map((rf,i)=><RefRow key={i} rel={rf} onOpenRef={onOpenRef}/>)}
          </RefSection>
        )}
        <AIAction label="用 AI 检查这条伏笔" onClick={onOpenChat}/>
      </div>
    </div>
  );
}

/* ============================================================
   大纲详情 — 作品级大纲条目：状态 + 正文 + 节奏点(beats)时间线
   对齐 outline_editor_page.dart：OutlineDraft（title/status/content/beats），
   beat 含 status + chapterCount（计划章数）。大纲是整部/卷级，而非单章。
   ============================================================ */
function OutlineDetail({entity, onBack, onOpenChat}){
  const [ref, scrolled] = useScrolled();
  const o = entity;
  const st = OUTLINE_STATUS[o.status] || OUTLINE_STATUS.pending;
  const beats = o.beats || [];
  const planned = beats.reduce((s,b)=>s+(b.chapterCount||0), 0);
  return (
    <div className="screen fade-in" data-screen-label="outline-detail">
      <PageHead title={o.title} sub="大纲" onBack={onBack} scrolled={scrolled} center right={<IconBtn icon="pencil"/>}/>
      <div className="viewport" ref={ref} style={{padding:'12px 20px 28px'}}>
        <div className="col" style={{alignItems:'center', gap:10, padding:'4px 0 18px'}}>
          <EntityIcon icon="list" hex={st.hex} s={62} is={30}/>
          <div className="col" style={{alignItems:'center', gap:8}}>
            <span className="display" style={{fontSize:20, fontWeight:700, letterSpacing:'-0.02em', textAlign:'center'}}>{o.title}</span>
            <div className="row gap6">
              <span className="chip" style={{height:22, fontSize:11, padding:'0 10px', color:st.hex, background:tint(st.hex,.14), fontWeight:600}}>
                <span style={{width:6,height:6,borderRadius:'50%',background:st.hex}}></span>{st.label}</span>
              <span className="chip" style={{height:22, fontSize:11, padding:'0 10px', background:'var(--surface-dim)', color:'var(--text-muted)'}}>
                {beats.length} 节奏点 · 计划 {planned} 章</span>
            </div>
          </div>
        </div>

        <SectionLabel text="大纲正文"/>
        <ReadingBody paragraphs={[o.content]}/>

        {beats.length>0 && (
          <div style={{marginBottom:18}}>
            <SectionLabel text={`节奏点 · ${beats.length}`}/>
            <div style={{position:'relative', paddingLeft:18}}>
              <div style={{position:'absolute', left:5, top:6, bottom:6, width:1.5, background:'var(--border)'}}></div>
              {beats.map((b,i)=>{
                const bs = OUTLINE_STATUS[b.status] || OUTLINE_STATUS.pending;
                return (
                  <div key={b.id||i} className="card" style={{position:'relative', marginBottom:10, padding:'12px 13px'}}>
                    <span style={{position:'absolute', left:-17, top:16, width:11, height:11, borderRadius:'50%', background:bs.hex, border:'2px solid var(--canvas)', boxShadow:'0 0 0 1.5px '+bs.hex}}></span>
                    <div className="row gap6" style={{marginBottom:5, alignItems:'center'}}>
                      <span style={{fontSize:11.5, fontWeight:700, color:'var(--text-subtle)', flex:'0 0 auto'}}>{i+1}.</span>
                      <span className="display" style={{flex:1, fontSize:14, fontWeight:700, color:'var(--text-primary)'}}>{b.title}</span>
                      <span className="chip" style={{height:19, fontSize:10, padding:'0 7px', color:bs.hex, background:tint(bs.hex,.13), fontWeight:600}}>{bs.label}</span>
                      <span className="chip" style={{height:19, fontSize:10, padding:'0 7px', background:'var(--surface-dim)', color:'var(--text-muted)'}}>{b.chapterCount} 章</span>
                    </div>
                    <p style={{margin:0, fontSize:12.5, color:'var(--text-muted)', lineHeight:1.6}}>{b.content}</p>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        <AIAction label="用 AI 梳理这条大纲" onClick={onOpenChat}/>
      </div>
    </div>
  );
}

/* ============================================================
   地图地点详情 — 小地图（高亮针位）+ 区域 + 描述 + 出现章节 + 关联
   ============================================================ */
function LocationDetail({entity, onBack, onOpenRef, onOpenChat}){
  const [ref, scrolled] = useScrolled();
  const lo = entity;
  return (
    <div className="screen fade-in" data-screen-label="location-detail">
      <PageHead title={lo.name} sub="地点" onBack={onBack} scrolled={scrolled} center right={<IconBtn icon="pencil"/>}/>
      <div className="viewport" ref={ref} style={{padding:'14px 20px 28px'}}>
        <div className="card" style={{padding:0, overflow:'hidden', marginBottom:18}}>
          <div style={{position:'relative', width:'100%', aspectRatio:'16/10', background:'linear-gradient(160deg,#EEF3F0,#DCE6E1)'}}>
            <svg viewBox="0 0 100 64" style={{position:'absolute', inset:0, width:'100%', height:'100%'}}>
              <path d="M14 22 Q40 28 50 36 T84 52" fill="none" stroke="#9DB2A9" strokeWidth="0.8" strokeDasharray="2 3" opacity=".6"/>
              {LOCATIONS.map(p=>{
                const on = p.id===lo.id;
                const x=p.x, y=p.y*0.64;
                return (
                  <g key={p.id} opacity={on?1:.42}>
                    <circle cx={x} cy={y} r={on?'2.6':'1.8'} fill="#2A9C78"/>
                    {on && <circle cx={x} cy={y} r="5" fill="none" stroke="#2A9C78" strokeWidth=".7" opacity=".6"/>}
                    <text x={x+3.4} y={y+1} fontSize="3" fill={on?'#1C2623':'#5F6B66'} fontWeight={on?700:400} style={{fontFamily:'var(--display)'}}>{p.name}</text>
                  </g>
                );
              })}
            </svg>
            <div style={{position:'absolute', left:12, top:12, padding:'4px 10px', borderRadius:'var(--r-pill)', background:'color-mix(in srgb, var(--canvas) 86%, transparent)', fontSize:11, fontWeight:600, color:'var(--text-secondary)'}}>{lo.region}</div>
          </div>
        </div>

        <div className="col" style={{alignItems:'center', gap:6, marginBottom:18}}>
          <span className="display" style={{fontSize:21, fontWeight:700, letterSpacing:'-0.02em'}}>{lo.name}</span>
          <span className="row gap4" style={{fontSize:12, color:'var(--text-muted)'}}><I.map s={14} c="var(--accent)"/>{lo.region}</span>
        </div>

        <LocationPhotos key={lo.id} initial={lo.photos||[]}/>

        <SectionLabel text="地点描述"/>
        <ReadingBody paragraphs={[lo.desc]}/>

        {(lo.appearsIn||[]).length>0 && (
          <RefSection title="出现章节" count={lo.appearsIn.length}>
            {lo.appearsIn.map(id=><ChapterRefRow key={id} id={id} onOpenRef={onOpenRef}/>)}
          </RefSection>
        )}
        {(lo.related||[]).length>0 && (
          <RefSection title="关联条目" count={lo.related.length}>
            {lo.related.map((rf,i)=><RefRow key={i} rel={rf} onOpenRef={onOpenRef}/>)}
          </RefSection>
        )}
        <AIAction label="用 AI 补全这处场景" onClick={onOpenChat}/>
      </div>
    </div>
  );
}

/* 地点照片：横向一行，角上 × 移除，点名称弹底部抽屉改名；增删改名立即生效。
   名称为空显示「未命名」。尺寸与角色编辑页照片行一致（80 + 44 名称触控高度）。 */
function LocationPhotos({initial}){
  const [photos, setPhotos] = useState(initial);
  const [renaming, setRenaming] = useState(null);
  const [draft, setDraft] = useState('');
  const tints = ['#7D8A85','#5E6E7D','#6E5D6B','#5A7A6E'];
  const save = ()=>{
    setPhotos(photos.map((p,j)=> j===renaming ? {...p, name:draft.trim()} : p));
    setRenaming(null);
  };
  return (
    <div style={{marginBottom:18}}>
      <SectionLabel text="照片"/>
      <div className="row gap8" style={{overflowX:'auto', alignItems:'flex-start', paddingBottom:2}}>
        {photos.map((p,i)=>(
          <div key={i} className="col" style={{width:80, flex:'0 0 auto'}}>
            <div style={{position:'relative', width:80, height:80, borderRadius:'var(--r-xl)', background:p.tint,
              boxShadow:'inset 0 0 0 1px rgba(255,255,255,.16)'}}>
              <button className="press" aria-label="移除照片" onClick={()=>setPhotos(photos.filter((_,j)=>j!==i))}
                style={{position:'absolute', top:4, right:4, width:22, height:22, borderRadius:'50%', border:'none',
                  background:'rgba(20,26,24,.55)', display:'flex', alignItems:'center', justifyContent:'center', padding:0}}>
                <I.x s={12} c="#fff"/>
              </button>
            </div>
            <button className="press" onClick={()=>{ setDraft(p.name); setRenaming(i); }}
              style={{height:44, border:'none', background:'transparent', padding:'0 2px', fontSize:12,
                color: p.name ? 'var(--text-secondary)' : 'var(--text-subtle)',
                whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>
              {p.name || '未命名'}
            </button>
          </div>
        ))}
        <button className="press col" onClick={()=>setPhotos([...photos, {tint:tints[photos.length%tints.length], name:''}])}
          style={{width:80, height:80, flex:'0 0 auto', borderRadius:'var(--r-xl)', border:'1px dashed var(--border-input)',
            background:'transparent', color:'var(--text-muted)', alignItems:'center', justifyContent:'center', gap:3, fontSize:11}}>
          <I.plus s={18}/>添加</button>
      </div>
      {renaming!==null && (
        <Sheet onClose={()=>{}} max="60%">
          <SheetHeader title="重命名"/>
          <div style={{padding:'16px 18px'}}>
            <Field label="名称"><input className="tinput" autoFocus value={draft}
              onChange={e=>setDraft(e.target.value)} onKeyDown={e=>e.key==='Enter' && save()}/></Field>
          </div>
          <div className="row gap8" style={{padding:'0 18px 22px', justifyContent:'flex-end'}}>
            <button className="btn-ghost press" onClick={()=>setRenaming(null)} style={{height:44, padding:'0 18px'}}>取消</button>
            <button className="btn-accent press" onClick={save} style={{height:44, padding:'0 18px'}}>保存</button>
          </div>
        </Sheet>
      )}
    </div>
  );
}

/* ============================================================
   素材详情 — 文件头 + 类型/来源 + 描述 + 摘录 + 被引用于
   ============================================================ */
function MaterialDetail({entity, onBack, onOpenRef, onOpenChat}){
  const [ref, scrolled] = useScrolled();
  const m = entity;
  const Cmp = I[m.icon]||I.file;
  return (
    <div className="screen fade-in" data-screen-label="material-detail">
      <PageHead title={m.name} sub="素材" onBack={onBack} scrolled={scrolled} center right={<IconBtn icon="dots"/>}/>
      <div className="viewport" ref={ref} style={{padding:'8px 20px 28px'}}>
        <div className="col" style={{alignItems:'center', gap:10, padding:'8px 0 20px'}}>
          <div style={{width:68,height:68,borderRadius:'var(--r-2xl)',background:'color-mix(in srgb, var(--accent) 13%, transparent)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--accent-warm)'}}><Cmp s={32}/></div>
          <div className="col" style={{alignItems:'center', gap:6}}>
            <span className="display" style={{fontSize:20, fontWeight:700, letterSpacing:'-0.02em', textAlign:'center'}}>{m.name}</span>
            <span style={{fontSize:12, color:'var(--text-muted)'}}>{m.sub}</span>
          </div>
        </div>

        <MetaList rows={[['类型', m.type||'文本'], ['来源', m.source||'—']]}/>

        <SectionLabel text="说明"/>
        <ReadingBody paragraphs={[m.desc]}/>

        {m.excerpt && (
          <div style={{marginBottom:18}}>
            <SectionLabel text="摘录"/>
            <div className="card" style={{padding:'13px 14px', background:'var(--surface-container)', boxShadow:'none', borderLeft:'3px solid var(--blockquote-border)'}}>
              <p className="serif" style={{margin:0, fontSize:13.5, color:'var(--text-secondary)', lineHeight:1.75}}>{m.excerpt}</p>
            </div>
          </div>
        )}

        <AIAction label="在对话中引用此素材" onClick={onOpenChat}/>
      </div>
    </div>
  );
}

Object.assign(window, {
  resolveRef, findChapter, RefRow, ChapterRefRow, MetaList, ReadingBody, RefSection, AIAction,
  WorldDetail, EntityDetail, ForeshadowDetail, OutlineDetail, LocationDetail, MaterialDetail,
});
