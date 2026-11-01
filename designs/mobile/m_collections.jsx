/* ============================================================
   作品集合（移动端）—— 方案见 docs/solutions/library-collections-and-filters.md 第 6 节，
   和桌面 designs/desktop/LibraryCollections.jsx 同一套规则：
   · 全部 / 创作中 / 已完本 / 用户集合是同一层标签，全部固定第一；
   · 小说和剧本在同一个作品库里，集合不分类型：一部小说和它改编的剧本可以放进同一个集合；
   · 作品页：问候 → 继续写 → 最近 → 类型（全部/小说/剧本）→ 搜索 → 集合行（横滑标签 + 右端筛选），集合行滚动时吸顶；
   · 长按集合标签 → 重命名 / 左移 / 右移 / 删除集合；全部不响应；
   · 长按作品 → 操作面板，「加入集合」勾选即生效；手动集合里多一条「移出」；没有多选；
   · 空的手动集合给「添加作品」。
   ============================================================ */

/* ---------- 集合 store ---------- */
const MCOL = {
  // 数组顺序就是导航顺序。builtin 只有全部；创作中 / 已完本是条件集合（按状态现算）；其余是手动集合。
  // 集合没有类型：手动集合可以同时收小说和剧本（江南系列里就有《夜航船》的剧本改编）。
  list: [
    { id:'collection:all',      name:'全部', builtin:true },
    { id:'collection:active',   name:'创作中', rule:{status:'创作中'} },
    { id:'collection:finished', name:'已完本', rule:{status:'已完本'} },
    { id:'mc-jiangnan', name:'江南系列', workIds:['n1','sp1','n4','n5'] },
    { id:'mc-long',     name:'长篇连载', workIds:['n5','n1','n2'] },
    { id:'mc-submit',   name:'投稿中',   workIds:['n2'] },
    { id:'mc-drills',   name:'练笔',     workIds:[] },
  ],
  listeners: new Set(),
  set(fn){ MCOL.list = fn(MCOL.list); MCOL.listeners.forEach(l=>l(MCOL.list)); },
};

const mIsManual = (c)=> !c.builtin && !c.rule;

// 集合里的作品：全部 = 传入的所有作品（已按类型筛过）；条件集合按状态现算；手动集合取成员。
function mCollectionWorks(c, works){
  if(c.builtin) return works;
  if(c.rule) return works.filter(n=>n.status===c.rule.status);
  return c.workIds.map(id=>works.find(n=>n.id===id)).filter(Boolean);
}

function useMCollections(){
  const [list, setList] = useState(MCOL.list);
  useEffect(()=>{ MCOL.listeners.add(setList); return ()=>MCOL.listeners.delete(setList); },[]);
  const api = {
    toggle(id, workIds, state){
      MCOL.set(l=>l.map(c=>c.id!==id ? c : {...c, workIds: state==='checked'
        ? c.workIds.filter(w=>!workIds.includes(w))
        : [...c.workIds, ...workIds.filter(w=>!c.workIds.includes(w))]}));
    },
    create(name, workIds=[]){
      const id = 'mc-'+Date.now();
      MCOL.set(l=>[...l, {id, name, workIds:[...workIds]}]);
      return id;
    },
    add(id, workIds){ MCOL.set(l=>l.map(c=>c.id!==id ? c : {...c, workIds:[...c.workIds, ...workIds.filter(w=>!c.workIds.includes(w))]})); },
    remove(id, workIds){ MCOL.set(l=>l.map(c=>c.id!==id ? c : {...c, workIds:c.workIds.filter(w=>!workIds.includes(w))})); },
    rename(id, name){ MCOL.set(l=>l.map(c=>c.id!==id ? c : {...c, name})); },
    drop(id){ MCOL.set(l=>l.filter(c=>c.id!==id)); },
    // 挪一位；全部固定第一，别的挪不到它前面。
    move(id, dir){
      MCOL.set(l=>{
        const next = l.slice(), i = next.findIndex(x=>x.id===id), j = i+dir;
        if(j<1 || j>=next.length) return l;
        [next[i], next[j]] = [next[j], next[i]];
        return next;
      });
    },
  };
  return [list, api];
}

const mMembership = (c, workIds)=>{
  const hits = workIds.filter(id=>c.workIds.includes(id)).length;
  return hits===0 ? 'none' : hits===workIds.length ? 'checked' : 'mixed';
};

/* 底部面板挂到手机外框上，盖住底部 tab 栏（真机上 modal sheet 也盖住导航栏）。
   宿主在挂载后再找：首帧就打开的面板（深链）渲染时 .device 还没进 DOM。 */
function useDeviceHost(){
  const [host, setHost] = useState(null);
  React.useLayoutEffect(()=>{ setHost(document.querySelector('.device')); },[]);
  return host;
}

function MPortalSheet(props){
  const host = useDeviceHost();
  return host ? ReactDOM.createPortal(<Sheet {...props}/>, host) : null;
}

function MToast({text}){
  const host = useDeviceHost();
  if(!text || !host) return null;
  const node = (
    <div style={{position:'absolute', left:'50%', bottom:112, transform:'translateX(-50%)', zIndex:80,
      padding:'10px 18px', borderRadius:'var(--r-pill)', background:'var(--text-primary)', color:'var(--surface)',
      fontSize:13, whiteSpace:'nowrap', boxShadow:'0 8px 24px color-mix(in srgb, var(--shadow-base) 22%, transparent)'}}>{text}</div>
  );
  return ReactDOM.createPortal(node, host);
}

function useMToast(){
  const [text, setText] = useState(null);
  useEffect(()=>{ if(!text) return; const t = setTimeout(()=>setText(null), 2000); return ()=>clearTimeout(t); },[text]);
  return [text, setText];
}

/* 长按 450ms 触发；触发后吞掉随之而来的 click。桌面浏览器里右键也算。 */
function useLongPress(onLongPress, onClick){
  const timer = useRef(null), fired = useRef(false);
  const clear = ()=>{ clearTimeout(timer.current); timer.current = null; };
  return {
    onPointerDown: ()=>{ fired.current = false; clear(); timer.current = setTimeout(()=>{ fired.current = true; onLongPress(); }, 450); },
    onPointerUp: clear, onPointerLeave: clear, onPointerCancel: clear,
    onContextMenu: (e)=>{ e.preventDefault(); clear(); fired.current = true; onLongPress(); },
    onClick: ()=>{ if(fired.current){ fired.current = false; return; } onClick(); },
  };
}

function MCheck({state, size=20}){
  const on = state===true || state==='checked', mixed = state==='mixed';
  return (
    <span style={{width:size, height:size, borderRadius:'var(--r-sm)', flex:'0 0 auto', display:'inline-flex', alignItems:'center', justifyContent:'center',
      border:'1.6px solid '+(on||mixed?'var(--accent)':'var(--border)'), background:on||mixed?'var(--accent)':'var(--surface)'}}>
      {on && <I.check s={size-6} c="var(--on-accent)" sw={2.4}/>}
      {mixed && <span style={{width:size-10, height:2, borderRadius:1, background:'var(--on-accent)'}}></span>}
    </span>
  );
}

/* ---------- 集合行：横滑标签 + 右端固定筛选 ---------- */
function MCollectionTab({c, count, active, onSelect, onLongPress}){
  const press = useLongPress(()=>{ if(!c.builtin) onLongPress(c); }, ()=>onSelect(c.id));
  return (
    <button {...press} data-collection={c.id} className="press" style={{position:'relative', flex:'0 0 auto', height:44, padding:'0 11px',
      display:'flex', alignItems:'center', gap:4, border:'none', background:'transparent', whiteSpace:'nowrap',
      userSelect:'none', WebkitUserSelect:'none',
      fontSize:14, fontWeight:active?700:500, color:active?'var(--text-primary)':'var(--text-muted)'}}>
      <span style={{maxWidth:120, overflow:'hidden', textOverflow:'ellipsis'}}>{c.name}</span>
      <span style={{fontSize:11, fontWeight:500, fontVariantNumeric:'tabular-nums', color:active?'var(--accent)':'var(--text-subtle)'}}>{count}</span>
      {active && <span style={{position:'absolute', left:11, right:11, bottom:0, height:2.5, borderRadius:'2px 2px 0 0', background:'var(--accent)'}}></span>}
    </button>
  );
}

function MCollectionRow({collections, counts, currentId, filterActive, onSelect, onLongPress, onCreate, onFilter}){
  const scrollRef = useRef(null);
  const [fade, setFade] = useState(false);
  const measure = ()=>{ const el = scrollRef.current; if(el) setFade(el.scrollLeft + el.clientWidth < el.scrollWidth - 1); };
  React.useLayoutEffect(measure, [collections, counts]);
  // 选中项滚进可见区。只动横向：scrollIntoView 会连带把外层作品页纵向滚到集合行，盖掉上方的继续写。
  useEffect(()=>{
    const box = scrollRef.current;
    const el = box && box.querySelector(`[data-collection="${currentId}"]`);
    if(!el) return;
    if(el.offsetLeft < box.scrollLeft) box.scrollLeft = el.offsetLeft;
    else if(el.offsetLeft + el.offsetWidth > box.scrollLeft + box.clientWidth) box.scrollLeft = el.offsetLeft + el.offsetWidth - box.clientWidth;
  },[currentId]);
  return (
    <div style={{position:'sticky', top:0, zIndex:5, background:'var(--canvas)', display:'flex', alignItems:'stretch',
      boxShadow:'inset 0 -1px 0 var(--border-subtle)'}}>
      <div ref={scrollRef} onScroll={measure} style={{flex:1, minWidth:0, display:'flex', overflowX:'auto', scrollbarWidth:'none', padding:'0 9px',
        maskImage: fade ? 'linear-gradient(to right, #000 calc(100% - 28px), transparent)' : 'none',
        WebkitMaskImage: fade ? 'linear-gradient(to right, #000 calc(100% - 28px), transparent)' : 'none'}}>
        {collections.map(c=>(
          <MCollectionTab key={c.id} c={c} count={counts[c.id]} active={c.id===currentId} onSelect={onSelect} onLongPress={onLongPress}/>
        ))}
        <button className="press" aria-label="新建集合" onClick={onCreate} style={{flex:'0 0 auto', width:44, height:44, border:'none', background:'transparent',
          display:'flex', alignItems:'center', justifyContent:'center', color:'var(--text-subtle)'}}><I.plus s={18}/></button>
      </div>
      <span style={{width:1, margin:'12px 0', background:'var(--border-subtle)'}}></span>
      <button className="press" aria-label="筛选与排序" onClick={onFilter} style={{position:'relative', flex:'0 0 auto', width:52, height:44, border:'none', background:'transparent',
        display:'flex', alignItems:'center', justifyContent:'center', color:filterActive?'var(--accent)':'var(--text-secondary)'}}>
        <I.sliders s={20}/>
        {filterActive && <span style={{position:'absolute', top:10, right:13, width:6, height:6, borderRadius:'50%', background:'var(--accent)'}}></span>}
      </button>
    </div>
  );
}

/* 长按集合标签 */
function MCollectionMenuSheet({collection, index, total, onClose, onRename, onMove, onDelete}){
  return (
    <MPortalSheet onClose={onClose}>
      <SheetHeader title={collection.name}/>
      <div style={{padding:'6px 0 28px'}}>
        <MSheetRow icon="pencil" label="重命名" onClick={onRename}/>
        <MSheetRow icon="arrowL" label="左移" disabled={index<=1} onClick={()=>onMove(-1)}/>
        <MSheetRow icon="arrowR" label="右移" disabled={index>=total-1} onClick={()=>onMove(1)}/>
        <MSheetDivider/>
        <MSheetRow icon="trash" label="删除集合" danger onClick={onDelete}/>
      </div>
    </MPortalSheet>
  );
}

const M_SORTS = [['updated','最近编辑'],['created','创建时间'],['title','标题'],['words','字数']];

/* 筛选与排序：分类是临时筛选，只作用于当前集合；排序是页面状态，切集合沿用。
   sorts 由作品页按类型给：字数只对小说有意义，混着剧本时不给这一项。 */
function MFilterSheet({categories, category, onCategory, sort, onSort, sorts = M_SORTS, onClose}){
  const chip = (key, label, count)=>{
    const on = category===key;
    return (
      <span key={label} className="press" onClick={()=>onCategory(key)} style={{height:34, padding:'0 14px', borderRadius:'var(--r-pill)', display:'inline-flex', alignItems:'center', gap:5,
        fontSize:13.5, fontWeight:on?600:500, background:on?'color-mix(in srgb, var(--accent) 14%, transparent)':'var(--surface)', color:on?'var(--accent)':'var(--text-secondary)',
        border:'1px solid '+(on?'var(--accent)':'var(--border-subtle)')}}>
        {label}<span style={{fontSize:11, opacity:.7}}>{count}</span>
      </span>
    );
  };
  const total = categories.reduce((s,c)=>s+c.count, 0);
  const dirty = category || sort!=='updated';
  return (
    <MPortalSheet onClose={onClose}>
      <SheetHeader title="筛选与排序"
        right={dirty && <button className="press" onClick={()=>{ onCategory(null); onSort('updated'); }} style={{height:36, padding:'0 6px', border:'none', background:'transparent', color:'var(--accent)', fontSize:14, fontWeight:600}}>重置</button>}/>
      <div style={{padding:'14px 20px 4px', fontSize:12.5, fontWeight:600, color:'var(--text-muted)'}}>分类</div>
      <div style={{display:'flex', flexWrap:'wrap', gap:8, padding:'4px 20px 10px'}}>
        {chip(null, '全部', total)}
        {categories.map(c=>chip(c.key, c.key, c.count))}
      </div>
      <div style={{padding:'10px 20px 4px', fontSize:12.5, fontWeight:600, color:'var(--text-muted)'}}>排序</div>
      <div style={{padding:'0 0 28px'}}>
        {sorts.map(([k,label])=>(
          <div key={k} className="press" onClick={()=>onSort(k)} style={{display:'flex', alignItems:'center', height:48, padding:'0 20px', fontSize:15,
            color:sort===k?'var(--accent)':'var(--text-primary)', fontWeight:sort===k?600:400}}>
            <span style={{flex:1}}>{label}</span>
            {sort===k && <I.check s={18} c="var(--accent)"/>}
          </div>
        ))}
      </div>
    </MPortalSheet>
  );
}

/* ---------- 作品网格：对齐 _NovelGridItem —— 2 列，封面 3:4，标题 / 字数 / 状态 ---------- */
const mWordsLabel = (w)=> `${Number(String(w).replace('万',''))} 万字`;

function MStatusDot({status}){
  const c = status==='已完本' ? 'var(--success)' : status==='草稿' ? 'var(--text-muted)' : 'var(--accent-warm)';
  return (
    <span style={{alignSelf:'flex-start', display:'inline-flex', alignItems:'center', gap:4, padding:'2px 8px', borderRadius:'var(--r-pill)',
      background:status==='已完本'?'color-mix(in srgb, var(--success) 13%, transparent)':status==='草稿'?'var(--surface-dim)':'color-mix(in srgb, var(--accent-warm) 13%, transparent)',
      fontSize:11, fontWeight:600, color:c}}>
      <span style={{width:5, height:5, borderRadius:'50%', background:c}}></span>{status}
    </span>
  );
}

// 剧本小标：小说和剧本混排时区分类型，跟在封面下的信息行前面。不压在封面上 —— 封面左上是书名。
function MScreenplayMark(){
  return (
    <span style={{flex:'0 0 auto', display:'inline-flex', alignItems:'center', gap:3, height:17, padding:'0 6px', borderRadius:'var(--r-pill)',
      background:'color-mix(in srgb, var(--accent-warm) 13%, transparent)', color:'var(--accent-warm)', fontSize:10.5, fontWeight:600}}>
      <I.film s={11}/>剧本
    </span>
  );
}

// 剧本没有字数，这一行换成 集 / 场。
function MNovelGridItem({n, onOpen, onLongPress}){
  const press = useLongPress(onLongPress, ()=>onOpen(n));
  return (
    <div className="press fade-in" {...press} style={{display:'flex', flexDirection:'column', minWidth:0, userSelect:'none', WebkitUserSelect:'none'}}>
      <div style={{position:'relative', aspectRatio:'3/4', borderRadius:'var(--r-lg)'}}>
        <Cover n={n} w="100%" h="100%" fs={16}/>
      </div>
      <span style={{marginTop:8, fontSize:13.5, fontWeight:600, color:'var(--text-primary)', whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{n.title}</span>
      <span style={{marginTop:4, display:'flex', alignItems:'center', gap:6, fontSize:11, color:'var(--text-muted)', whiteSpace:'nowrap', minWidth:0}}>
        {n.proj && <MScreenplayMark/>}
        <span style={{overflow:'hidden', textOverflow:'ellipsis'}}>{n.words ? mWordsLabel(n.words) : n.meta}</span>
      </span>
      <span style={{marginTop:4, display:'flex'}}><MStatusDot status={n.status}/></span>
    </div>
  );
}

function MNovelGrid({novels, onOpen, onLongPress}){
  return (
    <div style={{display:'grid', gridTemplateColumns:'1fr 1fr', columnGap:16, rowGap:18}}>
      {novels.map(n=>(
        <MNovelGridItem key={n.id} n={n} onOpen={onOpen} onLongPress={()=>onLongPress(n)}/>
      ))}
    </div>
  );
}

/* ---------- 长按作品操作面板 ---------- */
function MSheetRow({icon, label, onClick, danger, disabled, trail}){
  const Cmp = I[icon];
  return (
    <div className="press" onClick={disabled ? undefined : onClick} style={{display:'flex', alignItems:'center', gap:14, padding:'0 20px', height:50,
      color:danger?'var(--error)':'var(--text-primary)', fontSize:15, opacity:disabled?.38:1}}>
      <Cmp s={20} c={danger?'var(--error)':'var(--text-secondary)'}/>
      <span style={{flex:1}}>{label}</span>
      {trail}
    </div>
  );
}
const MSheetDivider = ()=> <div style={{height:1, background:'var(--border-subtle)', margin:'4px 0'}}></div>;

function MWorkActionsSheet({novel, inCollection, onClose, onAddToCollection, onRemoveFromCollection}){
  const finished = novel.status==='已完本';
  return (
    <MPortalSheet onClose={onClose}>
      <SheetHeader title={novel.title} sub={novel.words ? `${novel.cat || ''} · ${mWordsLabel(novel.words)}` : novel.meta}/>
      <div style={{padding:'6px 0 28px', overflowY:'auto'}}>
        <MSheetRow icon="pencil" label="编辑" onClick={onClose}/>
        <MSheetRow icon="books" label="阅读" onClick={onClose}/>
        {!novel.proj && <MSheetRow icon="film" label="改编" onClick={onClose}/>}
        <MSheetRow icon="arrowsOut" label="导出" onClick={onClose}/>
        <MSheetRow icon="folder" label="加入集合" onClick={onAddToCollection} trail={<I.chevR s={18} c="var(--text-subtle)"/>}/>
        {inCollection && <MSheetRow icon="minus" label={`移出「${inCollection.name}」`} onClick={onRemoveFromCollection}/>}
        <MSheetDivider/>
        {finished
          ? <MSheetRow icon="play" label="恢复" onClick={onClose}/>
          : <React.Fragment>
              <MSheetRow icon="checkCircle" label="完结" onClick={onClose}/>
              <MSheetRow icon="archive" label="归档" onClick={onClose}/>
              <MSheetRow icon="slash" label="废弃" onClick={onClose}/>
            </React.Fragment>}
        <MSheetDivider/>
        <MSheetRow icon="trash" label="删除" danger onClick={onClose}/>
      </div>
    </MPortalSheet>
  );
}

/* ---------- 加入集合：只列手动集合，勾选即生效，底部一行直接新建 ---------- */
function MAddToCollectionSheet({workIds, onClose, onToast}){
  const [list, api] = useMCollections();
  const manual = list.filter(mIsManual);
  const [creating, setCreating] = useState(false);
  const [name, setName] = useState('');
  const submit = ()=>{
    const t = name.trim(); if(!t) return;
    api.create(t, workIds);
    onToast(`已新建「${t}」并加入`);
    setName(''); setCreating(false);
  };
  return (
    <MPortalSheet onClose={onClose} lift={creating ? 300 : 0}>
      <SheetHeader title="加入集合"
        right={<button className="press" onClick={onClose} style={{height:36, padding:'0 6px', border:'none', background:'transparent', color:'var(--accent)', fontSize:14, fontWeight:600}}>完成</button>}/>
      <div style={{padding:'6px 0 24px', overflowY:'auto'}}>
        {manual.map(c=>{
          const state = mMembership(c, workIds);
          return (
            <div key={c.id} className="press" onClick={()=>{ api.toggle(c.id, workIds, state); onToast(state==='checked' ? `已从「${c.name}」移出` : `已加入「${c.name}」`); }}
              style={{display:'flex', alignItems:'center', gap:14, padding:'0 20px', height:52}}>
              <MCheck state={state}/>
              <span style={{flex:1, fontSize:15, color:'var(--text-primary)'}}>{c.name}</span>
            </div>
          );
        })}
        {manual.length>0 && <MSheetDivider/>}
        {creating ? (
          <div className="row gap8" style={{padding:'8px 16px'}}>
            <input autoFocus value={name} onChange={e=>setName(e.target.value)} onKeyDown={e=>{ if(e.key==='Enter') submit(); }}
              placeholder="集合名称" style={{flex:1, height:44, padding:'0 14px', borderRadius:'var(--r-lg)', border:'1px solid var(--accent)',
              background:'var(--surface)', fontSize:15, outline:'none', color:'var(--text-primary)'}}/>
            <button className="press" onClick={submit} disabled={!name.trim()} style={{height:44, padding:'0 18px', borderRadius:'var(--r-pill)', border:'none',
              background:'var(--accent)', color:'var(--on-accent)', fontSize:14, fontWeight:600, opacity:name.trim()?1:.45}}>创建</button>
          </div>
        ) : (
          <div className="press" onClick={()=>setCreating(true)} style={{display:'flex', alignItems:'center', gap:14, padding:'0 20px', height:52, color:'var(--accent)', fontSize:15, fontWeight:600}}>
            <I.plus s={20}/>新建集合
          </div>
        )}
      </div>
    </MPortalSheet>
  );
}

/* ---------- 新建 / 重命名 / 删除 ---------- */
function MNameSheet({title, initial='', confirm, onClose, onSubmit}){
  const [name, setName] = useState(initial);
  const t = name.trim();
  return (
    <MPortalSheet onClose={onClose} lift={300}>
      <SheetHeader title={title}/>
      <div style={{padding:'16px 18px 22px'}}>
        <input autoFocus value={name} onChange={e=>setName(e.target.value)} onKeyDown={e=>{ if(e.key==='Enter' && t) onSubmit(t); }}
          placeholder="如：江南系列、投稿中" style={{width:'100%', boxSizing:'border-box', height:46, padding:'0 14px', borderRadius:'var(--r-lg)',
          border:'1px solid var(--accent)', background:'var(--surface)', fontSize:15, outline:'none', color:'var(--text-primary)'}}/>
        <button className="press" disabled={!t} onClick={()=>onSubmit(t)} style={{marginTop:14, width:'100%', height:46, borderRadius:'var(--r-pill)', border:'none',
          background:'var(--accent)', color:'var(--on-accent)', fontSize:15, fontWeight:600, opacity:t?1:.45}}>{confirm}</button>
      </div>
    </MPortalSheet>
  );
}

function MConfirmDeleteSheet({collection, count, onClose, onConfirm}){
  return (
    <MPortalSheet onClose={onClose}>
      <div style={{padding:'8px 22px 26px', display:'flex', flexDirection:'column', gap:8}}>
        <span className="display" style={{fontSize:17, fontWeight:700}}>删除集合「{collection.name}」？</span>
        <span style={{fontSize:13, color:'var(--text-muted)'}}>集合里的 {count} 部作品不会被删除。</span>
        <button className="press" onClick={onConfirm} style={{marginTop:10, height:46, borderRadius:'var(--r-pill)', border:'none', background:'var(--error)', color:'#fff', fontSize:15, fontWeight:600}}>删除</button>
        <button className="press" onClick={onClose} style={{height:46, borderRadius:'var(--r-pill)', border:'1px solid var(--border)', background:'var(--surface)', color:'var(--text-secondary)', fontSize:15}}>取消</button>
      </div>
    </MPortalSheet>
  );
}

/* ---------- 空手动集合的「添加作品」：全高面板 ---------- */
function MWorkPickerSheet({collection, novels, onClose, onAdd}){
  const [picked, setPicked] = useState([]);
  const toggle = (id)=> setPicked(l=>l.includes(id) ? l.filter(x=>x!==id) : [...l, id]);
  return (
    <MPortalSheet onClose={onClose} max="92%">
      <SheetHeader title={`添加到「${collection.name}」`}
        right={<button className="press" disabled={!picked.length} onClick={()=>onAdd(picked)} style={{height:36, padding:'0 6px', border:'none', background:'transparent',
          color:'var(--accent)', fontSize:14, fontWeight:600, opacity:picked.length?1:.4}}>添加{picked.length ? ` ${picked.length}` : ''}</button>}/>
      <div style={{padding:'4px 0 28px', overflowY:'auto'}}>
        {novels.map(n=>(
          <div key={n.id} className="press" onClick={()=>toggle(n.id)} style={{display:'flex', alignItems:'center', gap:12, padding:'8px 18px'}}>
            <MCheck state={picked.includes(n.id)}/>
            <Cover n={n} w={36} h={48} fs={9}/>
            <div className="col" style={{flex:1, minWidth:0, gap:3}}>
              <span style={{fontSize:14.5, fontWeight:600, color:'var(--text-primary)'}}>{n.title}</span>
              <span style={{fontSize:11.5, color:'var(--text-muted)'}}>{n.words ? mWordsLabel(n.words) : n.meta} · {n.status}</span>
            </div>
          </div>
        ))}
      </div>
    </MPortalSheet>
  );
}

Object.assign(window, {
  useMCollections, mIsManual, mCollectionWorks, useMToast, MToast,
  MCollectionRow, MCollectionMenuSheet, MFilterSheet, M_SORTS, MNovelGrid, MScreenplayMark,
  MWorkActionsSheet, MAddToCollectionSheet, MNameSheet, MConfirmDeleteSheet, MWorkPickerSheet,
});
