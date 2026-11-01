/* ============================================================
   作品 tab —— 原首页与书架合并成一页（首页 tab 已去掉）。
   上半部分随内容滚动：问候 → 继续写 → 最近；
   下半部分是作品库：类型（全部/小说/剧本）→ 搜索 → 集合行（吸顶）→ 两列网格。
   小说和剧本混在同一个作品库里，类型降为筛选和卡片上的小标，集合也不再分类型。
   ============================================================ */

/* ---------- 最近编辑排序 ----------
   mock 里的 updated 是展示文案（今天 14:32 / 昨天 / 3 天前 / 06/14），这里折算成「多少分钟前」排序。
   「今天」按 6月21日 21:00 算，和问候栏的日期一致。 */
function mMinutesAgo(updated){
  const u = String(updated || '');
  let m;
  if((m = /^今天\s*(\d+):(\d+)/.exec(u))) return (21*60) - (Number(m[1])*60 + Number(m[2]));
  if((m = /^昨天(?:\s*(\d+):(\d+))?/.exec(u))) return 21*60 + (m[1] ? (24*60 - Number(m[1])*60 - Number(m[2])) : 12*60);
  if((m = /^(\d+)\s*天前/.exec(u))) return Number(m[1]) * 1440;
  if(u === '上周') return 7 * 1440;
  if((m = /^(\d+)\/(\d+)/.exec(u))) return (21 - Number(m[2])) * 1440 + 60;
  return 365 * 1440;
}

/* 作品库条目统一成一个形状：小说直接用 NOVELS，剧本用 m_screenplay.jsx 的 SP_MOBILE（带 proj）。 */
const mIsScreenplay = (w)=> Boolean(w.proj);

/* 继续写的落点：小说是「第 N 章 · 章名」+ 正文末句；剧本是「第 N 季 · 第 N 集 · 第 N 场」+ 场次说明。
   单季剧本不显示季这一层，和剧本工作台的约定一致。 */
function mResumeOf(w){
  if(!mIsScreenplay(w)){
    if(w.id === 'n1'){
      // 只取正文最后一句：够认出停在哪，又不至于在首页读起正文来。
      const para = ACTIVE_CHAPTER.body[ACTIVE_CHAPTER.body.length - 1];
      const sentences = para.split(/(?<=。)/).filter(Boolean);
      return { where: w.last, excerpt: sentences[sentences.length - 1] };
    }
    return { where: w.last || `共 ${w.chapters} 章 · ${mWordsLabel(w.words)}`, excerpt: w.desc || '' };
  }
  const p = w.proj;
  const seasons = spSeasonsOf(p.id);
  const seasonId = SP_CURRENT_SEASON[p.id] || (seasons[0] && seasons[0].id);
  const season = seasons.find(s=>s.id===seasonId);
  const eps = SP_EPISODES.filter(e=>e.proj===p.id && (!seasonId || e.season===seasonId));
  const scenes = SP_SCENES.filter(s=>s.proj===p.id && eps.some(e=>e.id===s.ep));
  const scene = scenes.find(s=>s.state!=='定稿') || scenes[scenes.length - 1];
  if(!scene) return { where: w.meta, excerpt: p.logline || '' };
  const epIndex = eps.findIndex(e=>e.id===scene.ep) + 1;
  const parts = [];
  if(seasons.length > 1 && season) parts.push(`第 ${season.no} 季`);
  if(p.kind === 'series') parts.push(`第 ${epIndex} 集`);
  parts.push(`第 ${scene.no} 场${scene.title ? ' · ' + scene.title : ''}`);
  return { where: parts.join(' · '), excerpt: scene.desc };
}

/* ---------- 继续写：最近编辑的一部作品，不分类型 ---------- */
function MResumeCard({work, onContinue}){
  const r = mResumeOf(work);
  return (
    <div className="card press fade-in" onClick={()=>onContinue(work)}
      style={{padding:16, display:'flex', gap:14, alignItems:'stretch', marginBottom:20}}>
      <div style={{flex:'0 0 auto'}}><Cover n={work} w={72} h={98} fs={13}/></div>
      <div className="col" style={{flex:1, gap:6, minWidth:0}}>
        <div className="row gap6" style={{color:'var(--accent-warm)'}}>
          <I.clock s={13}/><span style={{fontSize:11.5, fontWeight:600}}>上次写于 · {work.updated}</span>
        </div>
        <div className="display" style={{fontSize:18, fontWeight:700, color:'var(--text-primary)', lineHeight:1.2, letterSpacing:'-0.01em',
          whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{work.title}</div>
        <div className="row gap6" style={{fontSize:12, color:'var(--text-muted)', minWidth:0}}>
          {mIsScreenplay(work) && <MScreenplayMark/>}
          <span style={{whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{r.where}</span>
        </div>
        {r.excerpt && (
          <div className="serif" style={{fontSize:12.5, lineHeight:1.65, color:'var(--text-secondary)',
            display:'-webkit-box', WebkitLineClamp:2, WebkitBoxOrient:'vertical', overflow:'hidden'}}>{r.excerpt}</div>
        )}
        <button className="btn-accent press" style={{height:34, alignSelf:'flex-start', padding:'0 16px', marginTop:'auto'}}
          onClick={(e)=>{ e.stopPropagation(); onContinue(work); }}>
          <I.pencil s={15}/>继续写作</button>
      </div>
    </div>
  );
}

/* ---------- 最近：继续写之外的几部，横滑小封面 ---------- */
function MRecentStrip({works, onOpen}){
  if(!works.length) return null;
  return (
    <div style={{marginBottom:20}}>
      <SectionLabel text="最近"/>
      <div className="viewport" style={{display:'flex', gap:12, overflowX:'auto', overflowY:'hidden', margin:'0 -20px', padding:'2px 20px 4px'}}>
        {works.map(w=>(
          <div key={w.id} className="press" onClick={()=>onOpen(w)} style={{flex:'0 0 auto', width:76, display:'flex', flexDirection:'column', gap:6}}>
            <Cover n={w} w={76} h={102} fs={11}/>
            <span style={{fontSize:12, fontWeight:600, color:'var(--text-primary)', whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{w.title}</span>
            <span style={{fontSize:10.5, color:'var(--text-subtle)', marginTop:-3, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>
              {mIsScreenplay(w) && <I.film s={10} style={{verticalAlign:-1, marginRight:3}}/>}{w.updated}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

const M_TYPES = [['all','全部'],['novel','小说'],['screenplay','剧本']];

/* 深链（截图用）：?collection=<id> 选中集合；&type=novel|screenplay 落到对应类型（旧的 &shelf= 也认）；
   &q=<词> 预填搜索；&hero=<作品 id> 指定继续写那一部；
   &sheet=filter|cmenu|actions|add 打开对应面板（cmenu 针对当前集合，actions/add 针对第一部作品）。 */
function LibraryScreen({onOpenNovel, onOpenScreenplay, onContinue, initialCollection}){
  const [ref, scrolled] = useScrolled();
  const qs = new URLSearchParams(window.location.search);
  const [collections, api] = useMCollections();
  const [type, setType] = useState(()=> qs.get('type') || qs.get('shelf') || 'all');
  const [scope, setScope] = useState(()=> initialCollection || qs.get('collection') || collections[0].id);
  const [query, setQuery] = useState(qs.get('q') || '');
  const [category, setCategory] = useState(null);
  const [sort, setSort] = useState('updated');
  const [toast, setToast] = useMToast();
  const current = collections.find(c=>c.id===scope) || collections[0];

  // 草稿不在作品库里（顶栏按钮进草稿页）。小说和剧本按最近编辑合成一列，继续写 / 最近 也从这里取。
  const library = [...NOVELS.filter(n=>n.status!=='草稿'), ...SP_MOBILE]
    .sort((x, y)=> mMinutesAgo(x.updated) - mMinutesAgo(y.updated));
  const hero = library.find(w=>w.id===qs.get('hero')) || library[0];
  const recent = library.filter(w=>w!==hero).slice(0, 5);

  const works = type==='all' ? library : library.filter(w=> type==='screenplay' ? mIsScreenplay(w) : !mIsScreenplay(w));
  // 字数只对小说有意义；混着剧本时不给这一项，切过去时排序回到最近编辑。
  const sorts = type==='novel' ? M_SORTS : M_SORTS.filter(([k])=>k!=='words');
  const effectiveSort = sorts.some(([k])=>k===sort) ? sort : 'updated';
  const counts = Object.fromEntries(collections.map(c=>[c.id, mCollectionWorks(c, works).length]));
  const base = mCollectionWorks(current, works);
  const categoryOf = (n)=> (n.cat || n.genre || '').split(' · ')[0] || null;
  const catMap = {};
  base.forEach(n=>{ const k = categoryOf(n); if(k) catMap[k] = (catMap[k]||0)+1; });
  const categories = Object.entries(catMap).map(([key, count])=>({key, count}));
  const q = query.trim().toLowerCase();
  let visible = base.filter(n=>(!category || categoryOf(n)===category) && (!q || [n.title, n.en, ...(n.tags||[])].join(' ').toLowerCase().includes(q)));
  if(effectiveSort==='title') visible = visible.slice().sort((a,b)=>a.title.localeCompare(b.title,'zh'));
  if(effectiveSort==='words') visible = visible.slice().sort((a,b)=>parseFloat(b.words||0)-parseFloat(a.words||0));
  if(effectiveSort==='created') visible = visible.slice().reverse();

  // null | {t:'filter'} | {t:'cmenu', c} | {t:'rename', c} | {t:'delete', c} | {t:'create'} | {t:'picker'}
  //      | {t:'actions', novel} | {t:'add', workIds}
  const [sheet, setSheet] = useState(()=>{
    const s = qs.get('sheet');
    if(s==='filter') return {t:'filter'};
    if(s==='cmenu') return {t:'cmenu', c:current};
    if(s==='actions' && visible[0]) return {t:'actions', novel:visible[0]};
    if(s==='add' && visible[0]) return {t:'add', workIds:[visible[0].id]};
    return null;
  });
  const close = ()=>setSheet(null);

  // 切集合清掉分类筛选，搜索和排序沿用。
  const select = (id)=>{ if(id===current.id) return; setScope(id); setCategory(null); };
  // 切类型清掉分类筛选（分类口径随类型变），集合和搜索沿用。
  const switchType = (k)=>{ if(k===type) return; setType(k); setCategory(null); if(k!=='novel' && sort==='words') setSort('updated'); };
  const open = (n)=> mIsScreenplay(n) ? onOpenScreenplay(n.proj) : onOpenNovel(n);

  let body;
  if(!base.length && mIsManual(current)){
    body = (
      <div className="col" style={{alignItems:'center', gap:12, padding:'72px 0', color:'var(--text-muted)'}}>
        <I.books s={30} c="var(--text-subtle)"/>
        <span style={{fontSize:15, fontWeight:600, color:'var(--text-secondary)'}}>集合里还没有作品</span>
        <button className="press" onClick={()=>setSheet({t:'picker'})} style={{marginTop:6, height:40, padding:'0 18px', borderRadius:'var(--r-pill)', border:'none',
          background:'var(--accent)', color:'var(--on-accent)', fontSize:14, fontWeight:600}}>添加作品</button>
      </div>
    );
  } else if(!base.length){
    body = <div className="col" style={{alignItems:'center', gap:10, padding:'72px 0', color:'var(--text-muted)', fontSize:14}}><I.books s={28} c="var(--text-subtle)"/>没有作品</div>;
  } else if(!visible.length){
    body = (
      <div className="col" style={{alignItems:'center', gap:12, padding:'72px 0', color:'var(--text-muted)', fontSize:14}}>
        <I.search s={28} c="var(--text-subtle)"/>没有找到匹配的作品
        <button className="press" onClick={()=>{ setQuery(''); setCategory(null); }} style={{height:38, padding:'0 16px', borderRadius:'var(--r-pill)',
          border:'1px solid var(--border)', background:'var(--surface)', color:'var(--text-secondary)', fontSize:13.5}}>清除搜索和筛选</button>
      </div>
    );
  } else {
    body = <MNovelGrid novels={visible} onOpen={open} onLongPress={(n)=>setSheet({t:'actions', novel:n})}/>;
  }

  const index = sheet && sheet.c ? collections.findIndex(c=>c.id===sheet.c.id) : -1;
  // 搜索时收起上半部分，结果直接顶到搜索框下面。
  const showTop = !q;
  return (
    <div className="screen" data-screen-label="works">
      <div className={"appbar"+(scrolled?' scrolled':'')} style={{paddingTop:54}}>
        <div className="row" style={{justifyContent:'space-between', padding:'10px 20px 12px'}}>
          <div className="col gap4">
            <span style={{fontSize:12, color:'var(--text-subtle)', fontWeight:600, letterSpacing:.3}}>6月21日 · 周六</span>
            <span className="display" style={{fontSize:24, fontWeight:700, color:'var(--text-primary)', letterSpacing:'-0.02em'}}>晚上好，怀素</span>
          </div>
          <div className="row gap8">
            <button className="press" aria-label="草稿" style={{width:40,height:40,borderRadius:'50%',background:'var(--surface)',border:'1px solid var(--card-border)',boxShadow:'var(--shadow-card)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--text-secondary)'}}><I.file s={19}/></button>
            <button className="press" aria-label="新建" style={{width:40,height:40,borderRadius:'50%',background:'var(--accent)',border:'none',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--on-accent)'}}><I.plus s={22}/></button>
          </div>
        </div>
      </div>

      <div className="viewport" ref={ref} style={{paddingBottom:24}}>
        {showTop && (
          <div style={{padding:'4px 20px 0'}}>
            {hero && <MResumeCard work={hero} onContinue={onContinue}/>}
            <MRecentStrip works={recent} onOpen={open}/>
            <SectionLabel text="作品"/>
          </div>
        )}
        <div style={{padding:'0 20px 12px'}}>
          <div className="seg">
            {M_TYPES.map(([k,label])=>(
              <span key={k} className={"segopt press"+(type===k?' active':'')} onClick={()=>switchType(k)}>{label}</span>
            ))}
          </div>
        </div>
        <div style={{padding:'0 20px 6px'}}>
          <label className="row gap8" style={{height:42, padding:'0 14px', background:'var(--surface)', borderRadius:'var(--r-pill)',
            border:'1px solid '+(query?'var(--accent)':'var(--border-input)'), color:query?'var(--accent)':'var(--text-subtle)'}}>
            <I.search s={18}/>
            <input value={query} onChange={e=>setQuery(e.target.value)} placeholder="搜索作品"
              style={{flex:1, minWidth:0, border:'none', outline:'none', background:'transparent', fontSize:14.5, color:'var(--text-primary)'}}/>
            {query && <span className="press" onClick={()=>setQuery('')} style={{display:'flex', color:'var(--text-subtle)'}}><I.x s={16}/></span>}
          </label>
        </div>
        <MCollectionRow collections={collections} counts={counts} currentId={current.id}
          filterActive={Boolean(category) || effectiveSort!=='updated'}
          onSelect={select}
          onLongPress={(c)=>setSheet({t:'cmenu', c})}
          onCreate={()=>setSheet({t:'create'})}
          onFilter={()=>setSheet({t:'filter'})}/>
        <div style={{padding:'16px 20px 0'}}>{body}</div>
      </div>

      {sheet && sheet.t==='filter' && (
        <MFilterSheet categories={categories} category={category} onCategory={setCategory} sort={effectiveSort} onSort={setSort} sorts={sorts} onClose={close}/>
      )}
      {sheet && sheet.t==='cmenu' && (
        <MCollectionMenuSheet collection={sheet.c} index={index} total={collections.length} onClose={close}
          onRename={()=>setSheet({t:'rename', c:sheet.c})}
          onMove={(dir)=>{ api.move(sheet.c.id, dir); close(); }}
          onDelete={()=>setSheet({t:'delete', c:sheet.c})}/>
      )}
      {sheet && sheet.t==='rename' && (
        <MNameSheet title="重命名集合" initial={sheet.c.name} confirm="保存" onClose={close}
          onSubmit={(name)=>{ api.rename(sheet.c.id, name); close(); }}/>
      )}
      {sheet && sheet.t==='delete' && (
        <MConfirmDeleteSheet collection={sheet.c} count={counts[sheet.c.id]} onClose={close}
          onConfirm={()=>{ const c = sheet.c; api.drop(c.id); setToast(`已删除集合「${c.name}」`); close(); if(c.id===current.id) setScope(collections[0].id); }}/>
      )}
      {sheet && sheet.t==='create' && (
        <MNameSheet title="新建集合" confirm="创建" onClose={close}
          onSubmit={(name)=>{ const id = api.create(name); close(); setScope(id); setCategory(null); }}/>
      )}
      {sheet && sheet.t==='picker' && (
        <MWorkPickerSheet collection={current} novels={library} onClose={close}
          onAdd={(ids)=>{ api.add(current.id, ids); setToast(`已加入 ${ids.length} 部作品`); close(); }}/>
      )}
      {sheet && sheet.t==='actions' && (
        <MWorkActionsSheet novel={sheet.novel} inCollection={mIsManual(current) ? current : null} onClose={close}
          onAddToCollection={()=>setSheet({t:'add', workIds:[sheet.novel.id]})}
          onRemoveFromCollection={()=>{ api.remove(current.id, [sheet.novel.id]); setToast(`已从「${current.name}」移出`); close(); }}/>
      )}
      {sheet && sheet.t==='add' && (
        <MAddToCollectionSheet workIds={sheet.workIds} onToast={setToast} onClose={close}/>
      )}
      <MToast text={toast}/>
    </div>
  );
}

Object.assign(window, { LibraryScreen });
