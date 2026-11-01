/* ============================================================
   地图 — 工作区「地图」tab + 地图工作台（全屏推入）
   对齐桌面 lib/desktop/features/map/ 的信息架构，骨架照搬移动端封面工作台
   （lib/mobile/features/cover_studio/）：
     全屏画布 + 顶栏（面包屑 / 地点 / 历史 / 导出）+ 常驻生成栏，
     出图参数收进「制图参数」抽屉，历史与地点树各自一个抽屉。
   桌面三栏的去处：左栏地点树 → 地点抽屉；右栏「生成」→ 参数抽屉；
   「地点」→ 画布浮卡；「历史」→ 历史抽屉。
   深链：?screen=workspace&section=map
         ?screen=mapStudio&state=selected|generating|empty|review&sheet=designer|history|places
   ============================================================ */

/* 世界与地点层级（桌面 LocationsService 的树；hasMap = 该地点有自己的地图记录） */
const MAP_WORLDS = [
  { id:'mw1', name:'明末江南', places:12, version:3, updated:'3 天前', hasMap:true,
    children:['苏州','松江府','太湖','嘉兴'] },
  { id:'mw2', name:'海外诸岛', places:4, version:0, updated:null, hasMap:false,
    children:['琉球','吕宋'] },
];

const MAP_TREE = [
  { id:'p1', name:'苏州', type:'城市', depth:0, hasMap:true, childCount:3, x:36, y:34 },
  { id:'lo1', name:'阊门', type:'城门', depth:1, x:30, y:30 },
  { id:'lo2', name:'夜泊处', type:'码头', depth:1, x:46, y:52 },
  { id:'lo3', name:'平江路', type:'街巷', depth:1, x:64, y:40 },
  { id:'p2', name:'太湖', type:'水域', depth:0, x:22, y:58 },
  { id:'p3', name:'嘉兴', type:'城市', depth:0, childCount:2, x:58, y:66 },
  { id:'p4', name:'松江府', type:'府城', depth:0, childCount:4, x:78, y:78 },
];

/* 世界图上的针位；进入苏州后换成城内地点 */
const MAP_PINS = {
  world: MAP_TREE.filter(p=>p.depth===0),
  city:  MAP_TREE.filter(p=>p.depth===1),
};

const MAP_STAGES = ['读地点','画地图','认地名','核对'];

const MAP_HISTORY = [
  { id:'h1', owner:'明末江南', version:3, time:'3 天前', spec:'古地图 · 2K · 高', current:true,
    prompt:'明末江南水网，运河自苏州南下至嘉兴、松江，太湖居西，城池以朱色标注……' },
  { id:'h2', owner:'明末江南', version:2, time:'5 天前', spec:'水墨 · 2K · 标准',
    prompt:'以淡墨绘制的江南水乡，运河与湖泊交织，城镇以小篆题名……' },
  { id:'h3', owner:'苏州', version:1, time:'1 周前', spec:'古地图 · 1K · 标准',
    prompt:'苏州城内，阊门在西，平江路沿河而北，夜泊处在城西河湾……' },
];

const MAP_STYLES = ['古地图','水墨','奇幻羊皮纸','等距俯视','自定义'];

/* 分享：kit 里没有，局部补一个（系统分享面板 = 手机上的「导出」） */
const IcShare = (p)=> <Ic {...p} d={<><path d="M12 3.5v11M8 7.5l4-4 4 4"/><path d="M6 11.5H5v8h14v-8h-1"/></>}/>;

/* ---------- 生成出来的地图（占位：羊皮纸 + 水网，用 SVG 模拟一张 AI 出图） ---------- */
function MapArt({variant='world', dim=false}){
  const city = variant==='city';
  return (
    <svg viewBox="0 0 100 100" preserveAspectRatio="xMidYMid slice"
      style={{position:'absolute', inset:0, width:'100%', height:'100%', filter:dim?'saturate(.4) brightness(.96)':'none'}}>
      <defs>
        <radialGradient id={'mapvig-'+variant} cx="50%" cy="50%" r="75%">
          <stop offset="60%" stopColor="#EEF2EE"/><stop offset="100%" stopColor="#D6DED8"/>
        </radialGradient>
      </defs>
      <rect width="100" height="100" fill={'url(#mapvig-'+variant+')'}/>
      {city ? (
        <g>
          <rect x="18" y="18" width="62" height="58" rx="2" fill="none" stroke="#2D3A36" strokeWidth=".9" opacity=".7"/>
          <path d="M8 44 Q30 48 44 54 T96 60" fill="none" stroke="#6F8FA8" strokeWidth="2.4" opacity=".55"/>
          <path d="M60 10 Q62 40 66 58 T70 96" fill="none" stroke="#6F8FA8" strokeWidth="1.4" opacity=".5"/>
          {[26,36,46,56,66].map(y=><path key={y} d={`M20 ${y} H78`} stroke="#A9B6AE" strokeWidth=".35" opacity=".6"/>)}
          {[28,40,52,70].map(x=><path key={x} d={`M${x} 20 V74`} stroke="#A9B6AE" strokeWidth=".35" opacity=".6"/>)}
        </g>
      ) : (
        <g>
          <path d="M4 50 Q14 40 24 48 Q30 58 22 68 Q12 72 6 64 Z" fill="#7C9AB0" opacity=".38"/>
          <path d="M36 4 Q40 30 46 46 Q54 62 60 70 Q70 82 80 96" fill="none" stroke="#6F8FA8" strokeWidth="1.6" opacity=".6"/>
          <path d="M46 46 Q60 42 72 30 Q82 20 96 18" fill="none" stroke="#6F8FA8" strokeWidth="1" opacity=".5"/>
          <path d="M84 60 Q92 70 98 88 L100 100 L86 100 Q84 84 84 60Z" fill="#7C9AB0" opacity=".32"/>
          {[[12,18],[18,14],[24,20],[70,10],[76,14]].map(([x,y],i)=>(
            <path key={i} d={`M${x-4} ${y+3} L${x} ${y-3} L${x+4} ${y+3}`} fill="none" stroke="#2D3A36" strokeWidth=".7" opacity=".6"/>
          ))}
          <path d="M14 30 Q40 38 50 54 T84 80" fill="none" stroke="#2D3A36" strokeWidth=".5" strokeDasharray="1.5 2" opacity=".6"/>
        </g>
      )}
      <g transform="translate(88 12)" opacity=".55">
        <circle r="5" fill="none" stroke="#2D3A36" strokeWidth=".4"/>
        <path d="M0 -6 L1.2 0 L0 6 L-1.2 0Z" fill="#2D3A36"/>
      </g>
    </svg>
  );
}

/* ============================================================
   工作区「地图」tab：世界卡片（缩略图 / 未出图占位）
   地点树不再铺在这一层 —— 进工作台后从「地点」抽屉管理。
   ============================================================ */
function MapBody({onScroll, onOpenStudio}){
  return (
    <div className="viewport" onScroll={onScroll} style={{padding:'14px 18px 28px'}}>
      <div className="col gap12">
        {MAP_WORLDS.map(w=>(
          <div key={w.id} className="card press" onClick={()=>onOpenStudio && onOpenStudio(w)}
            style={{padding:0, overflow:'hidden'}}>
            <div style={{position:'relative', width:'100%', aspectRatio:'16 / 10', background:'var(--surface-dim)'}}>
              {w.hasMap ? <MapArt variant="world"/> : (
                <div style={{position:'absolute', inset:10, borderRadius:'var(--r-xl)', border:'1.5px dashed var(--border)',
                  display:'flex', alignItems:'center', justifyContent:'center'}}>
                  <I.map s={30} c="var(--text-subtle)"/>
                </div>
              )}
              {w.hasMap && (
                <span className="chip" style={{position:'absolute', right:10, top:10, height:22, fontSize:10.5,
                  background:'color-mix(in srgb, var(--canvas) 88%, transparent)', color:'var(--text-secondary)'}}>v{w.version}</span>
              )}
            </div>
            <div className="row gap10" style={{padding:'12px 14px'}}>
              <div className="col" style={{flex:1, minWidth:0, gap:3}}>
                <span className="display" style={{fontSize:15.5, fontWeight:700}}>{w.name}</span>
                <span style={{fontSize:11.5, color:'var(--text-muted)', whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>
                  {w.places} 个地点 · {w.children.join(' · ')}
                </span>
              </div>
              {w.hasMap
                ? <span style={{fontSize:11, color:'var(--text-subtle)'}}>{w.updated}</span>
                : <span className="chip" style={{height:24, background:'color-mix(in srgb, var(--accent-warm) 12%, transparent)', color:'var(--accent-warm)', fontWeight:600}}>
                    <I.spark s={12}/>生成地图</span>}
              <I.chevR s={15} c="var(--text-subtle)"/>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

/* ============================================================
   地图工作台
   ============================================================ */
function MapStudioScreen({world, initialState='viewing', initialSheet=null, onBack, onEditLocation}){
  const w = world || MAP_WORLDS[0];
  const empty0 = initialState==='empty';
  // owner = 画布这张图属于谁；trail 是面包屑
  const [owner, setOwner] = useState(null);
  const [phase, setPhase] = useState(
    initialState==='generating' ? 'generating' : initialState==='review' ? 'review' : 'viewing');
  const [hasImage, setHasImage] = useState(!empty0);
  const [selected, setSelected] = useState(initialState==='selected' ? 'p1' : null);
  const [sheet, setSheet] = useState(initialSheet);
  const [stage, setStage] = useState(1);
  // 深链直落「生成中」时定格在第 2 阶段，方便截图；点生成才自动推进
  const [auto, setAuto] = useState(initialState!=='generating');

  const ownerNode = owner && MAP_TREE.find(p=>p.id===owner);
  const trail = ownerNode ? [w.name, ownerNode.name] : [w.name];
  const pins = ownerNode ? MAP_PINS.city : MAP_PINS.world;
  const sel = selected && MAP_TREE.find(p=>p.id===selected);
  const version = ownerNode ? 1 : w.version || 0;

  // 生成中：4 阶段自动推进（mockup 用定时器模拟）
  useEffect(()=>{
    if(phase!=='generating' || !auto) return;
    const t = setInterval(()=>setStage(s=>{
      if(s>=3){ setPhase('viewing'); setHasImage(true); return 0; }
      return s+1;
    }), 2600);
    return ()=>clearInterval(t);
  }, [phase, auto]);

  const generate = ()=>{ setAuto(true); setSheet(null); setSelected(null); setStage(0); setPhase('generating'); };
  const enterMap = (id)=>{ setOwner(id); setSelected(null); };

  return (
    <div className="screen fade-in" data-screen-label="map-studio" style={{background:'var(--canvas)'}}>
      {/* 顶栏 */}
      <div className="appbar" style={{paddingTop:54, borderBottom:'1px solid var(--border-subtle)'}}>
        <div className="row" style={{padding:'8px 8px 8px 12px', gap:2}}>
          <IconBtn icon="chevL" size={24} onClick={onBack}/>
          <div className="col" style={{flex:1, minWidth:0, gap:1, paddingLeft:2}}>
            <div className="row gap4" style={{minWidth:0}}>
              {trail.map((t,i)=>{
                const last = i===trail.length-1;
                return (
                  <React.Fragment key={i}>
                    {i>0 && <I.chevR s={12} c="var(--text-subtle)"/>}
                    <span className={'display'+(last?'':' press')} onClick={last?undefined:()=>enterMap(null)}
                      style={{fontSize:last?15.5:13.5, fontWeight:last?700:500,
                        color:last?'var(--text-primary)':'var(--text-muted)',
                        whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis',
                        flexShrink:last?1:2, minWidth:0}}>{t}</span>
                  </React.Fragment>
                );
              })}
            </div>
            <span style={{fontSize:11, color:'var(--text-muted)'}}>
              {hasImage ? `v${version} · ` : ''}{pins.length} 个地点
            </span>
          </div>
          <IconBtn icon="list" ariaLabel="地点" onClick={()=>setSheet('places')}/>
          <IconBtn icon="history" ariaLabel="历史" onClick={()=>setSheet('history')}/>
          <IconBtn icon={IcShare} ariaLabel="导出" c={hasImage?'var(--text-secondary)':'var(--text-subtle)'}/>
        </div>
      </div>

      {/* 画布 */}
      <div style={{flex:1, position:'relative', minHeight:0, overflow:'hidden', background:'var(--surface-dim)'}}
        onClick={()=>setSelected(null)}>
        {hasImage ? (
          <>
            <MapArt variant={ownerNode?'city':'world'} dim={phase==='generating'}/>
            {phase!=='generating' && pins.map(p=>(
              <MapPin key={p.id} pin={p} on={selected===p.id}
                onTap={(e)=>{ e.stopPropagation(); setSelected(p.id); }}/>
            ))}
          </>
        ) : phase==='generating' ? null : (
          <MapEmpty name={trail[trail.length-1]} count={pins.length}/>
        )}
        {phase==='generating' && (
          <div style={{position:'absolute', inset:0, display:'flex', alignItems:'center', justifyContent:'center'}}>
            <div className="card" style={{padding:'10px 16px', display:'flex', alignItems:'center', gap:10, boxShadow:'var(--shadow-float)'}}>
              <div className="tspin" style={{width:14, height:14, borderRadius:'50%',
                border:'2px solid var(--border)', borderTopColor:'var(--accent)'}}></div>
              <span style={{fontSize:13, fontWeight:600, color:'var(--text-secondary)'}}>{MAP_STAGES[stage]}…</span>
            </div>
          </div>
        )}

        {/* 选中地点浮卡：贴在生成栏上方，不遮挡 */}
        {sel && phase==='viewing' && (
          <div className="pop-in" onClick={e=>e.stopPropagation()}
            style={{position:'absolute', left:12, right:12, bottom:12, zIndex:5}}>
            <MapPlaceCard place={sel}
              onClose={()=>setSelected(null)}
              onEdit={()=>onEditLocation && onEditLocation(sel)}
              onEnter={()=>enterMap(sel.id)}/>
          </div>
        )}
      </div>

      {/* 常驻底栏 */}
      <MapBottomBar phase={phase} stage={stage} hasImage={hasImage} empty={pins.length===0}
        onOpenDesigner={()=>setSheet('designer')} onGenerate={generate}
        onStop={()=>setPhase('viewing')}
        onAdopt={()=>setPhase('viewing')} onRedo={generate}/>

      {sheet==='designer' && <MapDesignerSheet target={trail[trail.length-1]} hasImage={hasImage}
        isSub={!!ownerNode} onClose={()=>setSheet(null)} onGenerate={generate}/>}
      {sheet==='history' && <MapHistorySheet onClose={()=>setSheet(null)}
        onPick={()=>{ setSheet(null); setSelected(null); setPhase('review'); }}/>}
      {sheet==='places' && <MapPlacesSheet world={w} owner={owner} onClose={()=>setSheet(null)}
        onPick={(p)=>{ setSheet(null); if(p.depth===1 && owner!=='p1') setOwner('p1'); setSelected(p.id); }}
        onEnter={(p)=>{ setSheet(null); enterMap(p.id); }}/>}
    </div>
  );
}

/* 地点针：视觉 10px 圆点 + 名签，命中区 44px */
function MapPin({pin, on, onTap}){
  return (
    <button onClick={onTap} aria-label={pin.name} className="press"
      style={{position:'absolute', left:pin.x+'%', top:pin.y+'%', width:44, height:44, marginLeft:-22, marginTop:-22,
        background:'transparent', border:'none', padding:0, cursor:'pointer', zIndex:on?3:2}}>
      <span style={{position:'absolute', left:17, top:17, width:10, height:10, borderRadius:'50%',
        background:on?'var(--accent)':'#2A9C78', border:'2px solid var(--canvas)',
        boxShadow:'0 1px 3px color-mix(in srgb, var(--shadow-base) 30%, transparent)', animation:on?'pulseRing 1.8s infinite':'none'}}></span>
      <span className="display" style={{position:'absolute', left:31, top:13, whiteSpace:'nowrap',
        fontSize:12, fontWeight:on?700:600, color:on?'var(--accent-warm)':'var(--text-secondary)',
        padding:'1px 6px', borderRadius:'var(--r-sm)', background:on?'color-mix(in srgb, var(--canvas) 92%, transparent)':'color-mix(in srgb, var(--canvas) 60%, transparent)'}}>{pin.name}</span>
    </button>
  );
}

function MapPlaceCard({place, onClose, onEdit, onEnter}){
  const hasChildren = !!place.childCount;
  return (
    <div className="card" style={{padding:'12px 12px 12px 14px', boxShadow:'var(--shadow-float)'}}>
      <div className="row gap10">
        <div style={{width:36, height:36, borderRadius:'var(--r-xl)', background:'color-mix(in srgb, var(--accent-warm) 12%, transparent)',
          display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0}}>
          <I.flag s={17} c="var(--accent-warm)"/>
        </div>
        <div className="col" style={{flex:1, minWidth:0, gap:2}}>
          <span className="display" style={{fontSize:15.5, fontWeight:700}}>{place.name}</span>
          <span style={{fontSize:11.5, color:'var(--text-muted)'}}>
            {place.type}{hasChildren ? ` · ${place.childCount} 个下级地点` : ''}
          </span>
        </div>
        <IconBtn icon="x" size={18} c="var(--text-subtle)" onClick={onClose} ariaLabel="关闭"/>
      </div>
      <div className="row gap8" style={{marginTop:10}}>
        <button className="btn-ghost press" onClick={onEdit} style={{flex:1, height:36}}>
          <I.pencil s={14}/>编辑</button>
        {hasChildren && (
          <button className="btn-ghost press" onClick={onEnter}
            style={{flex:1, height:36, color:'var(--accent-warm)', borderColor:'color-mix(in srgb, var(--accent-warm) 45%, transparent)'}}>
            <I.map s={14}/>{place.hasMap ? '进入地图' : '新建地图'}</button>
        )}
      </div>
    </div>
  );
}

function MapEmpty({name, count}){
  return (
    <div style={{position:'absolute', inset:16, borderRadius:'var(--r-2xl)', border:'1.5px dashed var(--border)',
      display:'flex', flexDirection:'column', alignItems:'center', justifyContent:'center', gap:10}}>
      <I.map s={40} c="var(--text-subtle)"/>
      <span className="display" style={{fontSize:16, fontWeight:700, color:'var(--text-secondary)'}}>{name}</span>
      <span style={{fontSize:12, color:'var(--text-muted)'}}>{count} 个地点</span>
    </div>
  );
}

/* 常驻底栏：viewing = 参数入口 + 生成脚；generating = 4 阶段进度 + 停止；review = 采用 / 重画 */
function MapBottomBar({phase, stage, hasImage, empty, onOpenDesigner, onGenerate, onStop, onAdopt, onRedo}){
  return (
    <div style={{flex:'0 0 auto', background:'var(--surface)', borderTop:'1px solid var(--border)',
      padding:'12px 18px calc(env(safe-area-inset-bottom,0px) + 18px)'}}>
      {phase==='generating' ? (
        <div className="col gap10">
          <div className="row gap6">
            {MAP_STAGES.map((s,i)=>(
              <div key={s} className="col gap6" style={{flex:1}}>
                <div style={{height:4, borderRadius:2, overflow:'hidden', position:'relative',
                  background:i<stage?'var(--accent)':'var(--border-subtle)'}}>
                  {i===stage && <div style={{position:'absolute', inset:0, width:'40%', background:'var(--accent)',
                    borderRadius:2, animation:'barSlide 1.4s ease-in-out infinite'}}></div>}
                </div>
                <span style={{fontSize:11, textAlign:'center',
                  fontWeight:i===stage?700:500,
                  color:i===stage?'var(--accent-warm)':i<stage?'var(--text-secondary)':'var(--text-subtle)'}}>{s}</span>
              </div>
            ))}
          </div>
          <div className="row" style={{justifyContent:'space-between'}}>
            <span style={{fontSize:12, color:'var(--text-muted)'}}>{stage+1} / 4 · 已用 1 次出图</span>
            <button className="btn-ghost press" onClick={onStop} style={{height:34, padding:'0 16px'}}>
              <span style={{width:9, height:9, borderRadius:2, background:'currentColor'}}></span>停止</button>
          </div>
        </div>
      ) : phase==='review' ? (
        <div className="col gap10">
          <span style={{fontSize:12, color:'var(--text-muted)'}}>v2 · 5 天前 · 水墨 · 2K</span>
          <div className="row gap8">
            <button className="btn-ghost press" onClick={onRedo} style={{flex:1, height:44}}>
              <I.refresh s={15}/>重画</button>
            <button className="btn-accent press" onClick={onAdopt} style={{flex:1.4, height:44}}>
              <I.check s={16}/>采用这一版</button>
          </div>
        </div>
      ) : (
        <div className="col gap8">
          <button className="btn-ghost press" onClick={onOpenDesigner} style={{width:'100%', height:40}}>
            <I.sliders s={15}/>制图参数</button>
          <MapGenerateFooter label={hasImage?'重新生成':'生成地图'} disabled={empty} onGenerate={onGenerate}/>
        </div>
      )}
    </div>
  );
}

/* 共享生成脚（对应 shared 的 MapGenerateFooter） */
function MapGenerateFooter({label, disabled, onGenerate}){
  return (
    <div className="row gap12">
      <button className="btn-accent press" disabled={disabled} onClick={onGenerate}
        style={{flex:1, height:44, padding:'0 22px', opacity:disabled?.45:1}}>
        <I.spark s={16}/>{label}</button>
    </div>
  );
}

/* ---------- 制图参数抽屉（桌面「生成」tab） ---------- */
function MapDesignerSheet({target, hasImage, isSub, onClose, onGenerate}){
  const [style, setStyle] = useState('古地图');
  const [res, setRes] = useState('2K');
  const [quality, setQuality] = useState('高');
  const [src, setSrc] = useState({places:true, current:false, parent:true});
  const toggle = (k)=> setSrc(s=>({...s, [k]:!s[k]}));
  const sources = [
    {k:'places', label:'包含地点'},
    hasImage && {k:'current', label:'参考当前图'},
    isSub && {k:'parent', label:'参考上层地图'},
  ].filter(Boolean);
  return (
    <Sheet onClose={onClose} max="88%">
      <SheetHeader title="制图参数" sub={target}/>
      <div className="viewport" style={{flex:1, minHeight:0, padding:'16px 18px 8px'}}>
        <MapField label="来源">
          <div className="row gap8" style={{flexWrap:'wrap'}}>
            {sources.map(s=>(
              <button key={s.k} className={'tchip'+(src[s.k]?' on':'')} onClick={()=>toggle(s.k)}>
                {src[s.k] && <I.check s={13}/>}{s.label}</button>
            ))}
          </div>
        </MapField>
        <MapField label="画风">
          <div className="row gap8" style={{flexWrap:'wrap'}}>
            {MAP_STYLES.map(s=>(
              <button key={s} className={'tchip'+(style===s?' on':'')} onClick={()=>setStyle(s)}>{s}</button>
            ))}
          </div>
        </MapField>
        <div className="row gap16">
          <MapField label="分辨率" grow>
            <div className="seg">
              {['1K','2K','4K'].map(r=>(
                <button key={r} className="press" onClick={()=>setRes(r)} style={segBtn(res===r)}>{r}</button>
              ))}
            </div>
          </MapField>
          <MapField label="质量" grow>
            <div className="seg">
              {['标准','高'].map(q=>(
                <button key={q} className="press" onClick={()=>setQuality(q)} style={segBtn(quality===q)}>{q}</button>
              ))}
            </div>
          </MapField>
        </div>
        <MapField label="提示词" right={
          <button className="press" style={{border:'none', background:'transparent', color:'var(--text-muted)',
            fontSize:12, display:'inline-flex', alignItems:'center', gap:4}}><I.undo s={13}/>重置</button>}>
          <textarea className="tarea" rows={6} style={{width:'100%', resize:'none', lineHeight:1.6}}
            defaultValue={`${target}：明末江南水网，运河自苏州南下至嘉兴、松江，太湖居西。城池以朱色标注，河道以淡青描边，古地图风格，纸面有岁月痕迹。`}/>
        </MapField>
      </div>
      <div style={{flex:'0 0 auto', padding:'12px 18px calc(env(safe-area-inset-bottom,0px) + 18px)',
        borderTop:'1px solid var(--border-subtle)', background:'var(--surface)'}}>
        <MapGenerateFooter label={hasImage?'重新生成':'生成地图'} onGenerate={onGenerate}/>
      </div>
    </Sheet>
  );
}

const segBtn = (on)=>({flex:1, height:30, border:'none', borderRadius:'var(--r-pill)', fontSize:12.5,
  fontWeight:on?600:500, background:on?'var(--surface)':'transparent',
  color:on?'var(--text-primary)':'var(--text-muted)', boxShadow:on?'var(--shadow-card)':'none', cursor:'pointer'});

function MapField({label, right, grow, children}){
  return (
    <div style={{marginBottom:18, flex:grow?1:undefined}}>
      <div className="row" style={{marginBottom:8, justifyContent:'space-between'}}>
        <span style={{fontSize:12.5, fontWeight:600, color:'var(--text-secondary)'}}>{label}</span>
        {right}
      </div>
      {children}
    </div>
  );
}

/* ---------- 历史抽屉（桌面「历史」tab；点一张进入 review） ---------- */
function MapHistorySheet({onClose, onPick}){
  return (
    <Sheet onClose={onClose} max="72%">
      <SheetHeader title="出图记录" sub={`${MAP_HISTORY.length} 张`}/>
      <div className="viewport" style={{flex:1, minHeight:0, padding:'8px 12px 24px'}}>
        {MAP_HISTORY.map(h=>(
          <div key={h.id} className="row gap12 press" onClick={h.current?undefined:onPick}
            style={{padding:'10px 6px', borderBottom:'1px solid var(--border-subtle)', alignItems:'flex-start'}}>
            <div style={{position:'relative', width:84, height:58, borderRadius:'var(--r-lg)', overflow:'hidden', flexShrink:0,
              border:'1px solid var(--border-subtle)'}}>
              <MapArt variant={h.owner==='苏州'?'city':'world'}/>
            </div>
            <div className="col" style={{flex:1, minWidth:0, gap:3}}>
              <div className="row gap6">
                <span className="display" style={{fontSize:14, fontWeight:700}}>{h.owner} · v{h.version}</span>
                {h.current && <span className="chip" style={{height:20, fontSize:10.5, padding:'0 7px',
                  background:'color-mix(in srgb, var(--accent-warm) 12%, transparent)', color:'var(--accent-warm)', fontWeight:600}}>当前</span>}
              </div>
              <span style={{fontSize:11, color:'var(--text-muted)'}}>{h.time} · {h.spec}</span>
              <span style={{fontSize:11.5, color:'var(--text-secondary)', lineHeight:1.5,
                display:'-webkit-box', WebkitLineClamp:2, WebkitBoxOrient:'vertical', overflow:'hidden'}}>{h.prompt}</span>
            </div>
          </div>
        ))}
      </div>
    </Sheet>
  );
}

/* ---------- 地点抽屉（桌面左栏地点树；左滑删除沿用 MobileMapsPanel） ---------- */
function MapPlacesSheet({world, owner, onClose, onPick, onEnter}){
  return (
    <Sheet onClose={onClose} max="78%">
      <SheetHeader title={world.name} sub={`${world.places} 个地点`}
        right={<IconBtn icon="plus" ariaLabel="新建地点"/>}/>
      <div className="viewport" style={{flex:1, minHeight:0, padding:'6px 0 24px'}}>
        {MAP_TREE.map(p=>(
          <div key={p.id} className="row press" onClick={()=>onPick(p)}
            style={{minHeight:48, padding:'0 8px 0 '+(18+p.depth*18)+'px', gap:10,
              background:owner===p.id?'var(--selected)':'transparent'}}>
            {p.depth===0 && p.childCount
              ? <I.caretD s={13} c="var(--text-subtle)" style={{transform:p.id==='p1'?'none':'rotate(-90deg)'}}/>
              : <span style={{width:13}}></span>}
            <div className="col" style={{flex:1, minWidth:0, gap:1}}>
              <span style={{fontSize:14, fontWeight:p.depth===0?600:500}}>{p.name}</span>
              <span style={{fontSize:11, color:'var(--text-subtle)'}}>{p.type}</span>
            </div>
            {p.childCount && (
              <button className="press" onClick={(e)=>{ e.stopPropagation(); onEnter(p); }} aria-label="进入地图"
                style={{width:44, height:44, border:'none', background:'transparent', display:'flex',
                  alignItems:'center', justifyContent:'center'}}>
                <I.map s={17} c={p.hasMap?'var(--accent-warm)':'var(--text-subtle)'}/>
              </button>
            )}
          </div>
        ))}
      </div>
    </Sheet>
  );
}
