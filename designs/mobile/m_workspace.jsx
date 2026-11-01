/* ============================================================
   Novel workspace — 作品工作区
   桌面端 NavRail 的「创作 / 世界观」分区在移动端折叠为：单页 + 顶部 tab 切换
   （对齐 lib/mobile/pages/novel_editor_page.dart 的 _SectionChips）：
   概览 / 章节 / 人物 / 设定 / 大纲 / 伏笔 / 图鉴 / 地图 / 素材 / 关系图谱
   图鉴承接势力 / 生物 / 物品 / 技能四类，与桌面端同一信息架构。
   实体详情、章节编辑器以全屏 overlay 推入（对齐 Flutter 的 MaterialPageRoute push）。
   ============================================================ */

/* 顶部 tab：四类内容实体收进一个「图鉴」入口，避免移动端横向导航继续膨胀。 */
const WORKSPACE_TABS = [
  {k:'overview',   label:'概览'},
  {k:'chapters',   label:'章节'},
  {k:'characters', label:'人物'},
  {k:'world',      label:'设定'},
  {k:'outline',    label:'大纲'},
  {k:'foreshadow', label:'伏笔'},
  {k:'compendium', label:'图鉴'},
  {k:'map',        label:'地图'},
  {k:'materials',  label:'素材'},
  {k:'graph',      label:'关系图谱'},
  {k:'progress',   label:'当前进度'},
];

/* 取一段正文的最后一句（用于概览「上次写到」预览） */
function lastSentenceOf(paragraphs){
  const text = (paragraphs||[]).join('').trim();
  if(!text) return null;
  // 去掉结尾标点后找最后一个句末标点，截取其后的内容作为最后一句。
  const body = text.replace(/[。！？”]+$/, '');
  let idx = -1;
  for(const p of ['。','！','？','”']){ idx = Math.max(idx, body.lastIndexOf(p)); }
  const tail = idx >= 0 ? text.slice(idx + 1) : text;
  return tail.trim() || text;
}

/* ============================================================
   WorkspaceScreen — 单页 + 顶部 tab 切换
   ============================================================ */
function WorkspaceScreen({novel, onExit, onOpenChat,
                          onOpenChapter, onOpenCharDetail, onOpenEntity, onEditNovel,
                          onOpenAgentRules, onOpenAgentSkills, onOpenMapStudio, initialSection}){
  const [section, setSection] = useState(initialSection || 'overview');
  const [scrolled, setScrolled] = useState(false);
  const onScroll = (e)=> setScrolled(e.target.scrollTop > 4);
  const select = (k)=>{ setSection(k); setScrolled(false); };

  const tabs = WORKSPACE_TABS;
  const tab = tabs.find(t=>t.k===section) || tabs[0];
  const subtitle = section==='overview' ? novel.cat : tab.label;

  // 顶部右侧操作随分区变化：概览=更多；章节/列表=新建；关系图=展开。
  let right;
  if(section==='overview' || section==='progress'){
    right = <IconBtn icon="dots" ariaLabel="更多"/>;
  } else if(section==='graph'){
    right = <IconBtn icon="arrowsOut" ariaLabel="展开"/>;
  } else {
    right = <IconBtn icon="plus" ariaLabel="新建"/>;
  }

  const body = (()=>{
    switch(section){
      case 'overview':   return <OverviewBody novel={novel} onScroll={onScroll}
        onOpenSection={select} onContinueWriting={()=>onOpenChapter({id:'c3', n:'03'})}
        onOpenChat={onOpenChat} onEditNovel={onEditNovel}
        onOpenAgentRules={onOpenAgentRules} onOpenAgentSkills={onOpenAgentSkills}/>;
      case 'chapters':   return <ChaptersBody onScroll={onScroll} onOpenChapter={onOpenChapter}/>;
      case 'characters': return <CharactersBody onScroll={onScroll} onOpenDetail={onOpenCharDetail}/>;
      case 'world':      return <WorldBody onScroll={onScroll} onOpenDetail={(e)=>onOpenEntity('world', e)}/>;
      case 'outline':    return <OutlineBody onScroll={onScroll} onOpenDetail={(ch)=>onOpenEntity('outline', ch)}/>;
      case 'foreshadow': return <ForeshadowBody onScroll={onScroll} onOpenDetail={(f)=>onOpenEntity('foreshadow', f)}/>;
      case 'compendium': return <CompendiumBody onScroll={onScroll} onOpenDetail={onOpenEntity}/>;
      case 'map':        return <MapBody onScroll={onScroll} onOpenStudio={onOpenMapStudio}/>;
      case 'materials':  return <MaterialsBody onScroll={onScroll} onOpenDetail={(m)=>onOpenEntity('material', m)}/>;
      case 'graph':      return <GraphBody/>;
      case 'progress':
        return <div className="viewport" onScroll={onScroll} style={{padding:'24px 20px', color:'var(--text-muted)'}}>
          「{tab.label}」内页待设计
        </div>;
      default:           return null;
    }
  })();

  return (
    <div className="screen fade-in" data-screen-label="novel-workspace">
      <div className={"appbar"+(scrolled?' scrolled':'')} style={{paddingTop:54}}>
        <div className="row" style={{justifyContent:'space-between', padding:'8px 12px 8px', gap:6}}>
          <IconBtn icon="chevL" size={24} onClick={onExit}/>
          <div className="col" style={{alignItems:'center', flex:1, minWidth:0}}>
            <span className="display" style={{fontSize:15.5, fontWeight:700, color:'var(--text-primary)',
              whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis', maxWidth:'100%'}}>{novel.title}</span>
            <span style={{fontSize:11, color:'var(--text-muted)'}}>{subtitle}</span>
          </div>
          {right}
        </div>
        <WorkspaceTabs section={section} onSelect={select} tabs={tabs}/>
      </div>
      {body}
    </div>
  );
}

/* 横向滚动 tab chips（对齐 Flutter _SectionChips） */
function WorkspaceTabs({section, onSelect, tabs = WORKSPACE_TABS}){
  return (
    <div className="viewport" style={{flex:'0 0 auto', overflowY:'hidden', overflowX:'auto',
      display:'flex', gap:6, padding:'0 16px 10px'}}>
      {tabs.map(t=>{
        const on = t.k===section;
        return (
          <button key={t.k} className="press" onClick={()=>onSelect(t.k)}
            style={{flex:'0 0 auto', height:32, padding:'0 16px', borderRadius:'var(--r-pill)',
              border:'1px solid '+(on?'var(--accent)':'var(--border-subtle)'),
              background:on?'var(--accent)':'var(--surface)',
              color:on?'var(--on-accent)':'var(--text-secondary)',
              fontSize:13, fontWeight:600, whiteSpace:'nowrap', cursor:'pointer'}}>{t.label}</button>
        );
      })}
    </div>
  );
}

/* ============================================================
   概览 OverviewBody — 镜像 lib/mobile/widgets/mobile_overview_panel.dart
   标题/状态/标签 → 继续写作 hero → 项目简介 → 灵感片段 → 写作入口
   ============================================================ */
function OverviewBody({novel, onScroll, onOpenSection, onContinueWriting, onOpenChat, onEditNovel,
                        onOpenAgentRules, onOpenAgentSkills}){
  const agentConfigRef = useRef(null);
  const scrollToAgentConfig = ()=>{
    agentConfigRef.current?.scrollIntoView({behavior:'smooth', block:'start'});
  };
  return (
    <div className="viewport" onScroll={onScroll} style={{padding:'14px 20px 32px'}}>
      <Ov_Title novel={novel} onEditNovel={onEditNovel}/>
      <div style={{height:18}}></div>
      <Ov_ContinueHero novel={novel} onContinueWriting={onContinueWriting} onOpenSection={onOpenSection}
        onOpenChat={onOpenChat} onScrollToAgentConfig={scrollToAgentConfig}/>
      <div style={{height:18}}></div>
      <Ov_ProjectIntro novel={novel}/>
      <div style={{height:18}}></div>
      <Ov_Snippets onOpenSection={onOpenSection}/>
      <div style={{height:18}}></div>
      <Ov_WritingEntries onOpenSection={onOpenSection}/>
      <div style={{height:18}}></div>
      <div ref={agentConfigRef}>
        <Ov_AgentConfig onOpenAgentRules={onOpenAgentRules} onOpenAgentSkills={onOpenAgentSkills}/>
      </div>
    </div>
  );
}

/* AI 配置 — 本作品级智能体规则与技能入口（对齐桌面端 rail 的 AI 分区） */
function Ov_AgentConfig({onOpenAgentRules, onOpenAgentSkills}){
  const rows = [
    {icon:'shield', bg:'color-mix(in srgb, var(--accent-warm) 14%, transparent)', c:'var(--accent-warm)',
      label:'智能体规则', hint:'约束主笔的文风、视角与底线', val:NOVEL_AGENT_RULES.length+' 条', onTap:onOpenAgentRules},
    {icon:'spark', bg:'color-mix(in srgb, var(--accent) 13%, transparent)', c:'var(--accent)',
      label:'智能体技能', hint:'本作品专属的可调用技能', val:NOVEL_AGENT_SKILLS.length+' 个', onTap:onOpenAgentSkills},
  ];
  return (
    <div className="col" style={{gap:12}}>
      <span className="display" style={{fontSize:18, fontWeight:700, color:'var(--text-primary)', letterSpacing:'-0.01em'}}>AI 配置</span>
      <div className="slist">
        {rows.map(r=>{
          const Cmp = I[r.icon];
          return (
            <div key={r.label} className="srow press" onClick={r.onTap}>
              <div className="sicon" style={{background:r.bg, color:r.c}}><Cmp s={18}/></div>
              <div className="col" style={{flex:1, gap:2}}>
                <span style={{fontSize:14, fontWeight:500, color:'var(--text-primary)'}}>{r.label}</span>
                <span style={{fontSize:11.5, color:'var(--text-subtle)'}}>{r.hint}</span>
              </div>
              <span style={{fontSize:13, color:'var(--text-muted)'}}>{r.val}</span>
              <I.chevR s={18} c="var(--text-subtle)"/>
            </div>
          );
        })}
      </div>
    </div>
  );
}

/* 标题 + 编辑 + 状态徽章 + 标签 */
function Ov_Title({novel, onEditNovel}){
  return (
    <div className="col" style={{gap:10}}>
      <div className="row" style={{gap:6}}>
        <span className="display" style={{flex:1, fontSize:26, fontWeight:700, color:'var(--text-primary)', letterSpacing:'-0.02em'}}>{novel.title}</span>
        <button className="press" onClick={onEditNovel} style={{width:34,height:34,display:'flex',alignItems:'center',
          justifyContent:'center',color:'var(--text-secondary)',background:'transparent',border:'none'}}><I.pencil s={20}/></button>
      </div>
      <div><StatusChip status={novel.status}/></div>
      {(novel.tags||[]).length>0 && (
        <div className="row gap8" style={{flexWrap:'wrap'}}>
          {(novel.tags||[]).map(t=>(
            <span key={t} className="chip" style={{height:24, fontSize:11.5, padding:'0 11px',
              background:'var(--surface-container)', color:'var(--text-secondary)', border:'1px solid var(--border-subtle)'}}>{t}</span>
          ))}
        </div>
      )}
    </div>
  );
}

/* 继续写作 hero — 上次写到预览 + 写作/AI 双入口 + 次要入口 */
function Ov_ContinueHero({novel, onContinueWriting, onOpenSection, onOpenChat, onScrollToAgentConfig}){
  const last = lastSentenceOf(ACTIVE_CHAPTER.body);
  const continueLabel = '继续写第 4 章';
  // 一键进 AI 对话（作品级），不必再钻进章节；点 chip 带不同意图进同一对话。
  const quickPrompts = ['接着第 4 章写', '理一理后续剧情', '挑一处设定漏洞'];
  return (
    <div className="card" style={{padding:18}}>
      <div className="row gap6">
        <I.leaf s={16} c="var(--accent-warm)"/>
        <span style={{fontSize:13.5, fontWeight:600, color:'var(--accent-warm)'}}>继续写作</span>
      </div>
      <div style={{fontSize:12, color:'var(--text-muted)', marginTop:12}}>上次写到 · 第 3 章</div>
      <div className="serif" style={{fontSize:16.5, fontWeight:500, color:'var(--text-primary)', lineHeight:1.6, marginTop:6}}>{last}</div>
      <div style={{fontSize:12, color:'var(--text-muted)', marginTop:6}}>接着这里写下去，或让 AI 帮你。</div>

      {/* 自己写：主按钮 */}
      <button className="press" onClick={onContinueWriting} style={{width:'100%', height:46, marginTop:16,
        border:'none', borderRadius:'var(--r-pill)', background:'var(--accent)', color:'var(--on-accent)',
        fontSize:14.5, fontWeight:600, display:'flex', alignItems:'center', justifyContent:'center', gap:6, cursor:'pointer'}}>
        <I.pencil s={16} c="var(--surface)"/>{continueLabel}</button>

      {/* 让 AI 写：仿输入条，一键进作品级对话 */}
      <div className="press" onClick={onOpenChat} style={{display:'flex', alignItems:'center', gap:9, marginTop:12,
        padding:'0 6px 0 14px', height:46, borderRadius:'var(--r-pill)',
        background:'var(--surface)', border:'1px solid var(--border-input)'}}>
        <I.spark s={17} c="var(--accent)"/>
        <span style={{flex:1, fontSize:13.5, color:'var(--text-subtle)'}}>问 AI，或让它接着写…</span>
        <span style={{width:34, height:34, borderRadius:'50%', flex:'0 0 auto', background:'var(--accent)',
          display:'flex', alignItems:'center', justifyContent:'center', color:'var(--on-accent)'}}><I.send s={16}/></span>
      </div>
      <div className="row gap6" style={{flexWrap:'wrap', marginTop:10}}>
        {quickPrompts.map(p=>(
          <span key={p} className="press" onClick={onOpenChat} style={{height:28, padding:'0 11px', display:'inline-flex', alignItems:'center',
            borderRadius:'var(--r-pill)', background:'var(--selected)', border:'1px solid transparent',
            fontSize:12, color:'var(--accent-warm)', fontWeight:600}}>{p}</span>
        ))}
      </div>

      <div style={{height:1, background:'var(--border-subtle)', margin:'16px 0 14px'}}></div>

      {/* 次要入口 */}
      <div className="row gap8" style={{flexWrap:'wrap'}}>
        <Ov_SecondaryAction icon="list" label="查看大纲" onTap={()=>onOpenSection('outline')}/>
        <Ov_SecondaryAction icon="globe" label="浏览设定" onTap={()=>onOpenSection('world')}/>
        <Ov_SecondaryAction icon="spark" label="AI 配置" onTap={onScrollToAgentConfig}/>
      </div>
    </div>
  );
}

function Ov_SecondaryAction({icon, label, onTap}){
  const Cmp = I[icon]||I.file;
  return (
    <button className="press" onClick={onTap} style={{height:34, padding:'0 14px', display:'flex', alignItems:'center', gap:6,
      borderRadius:'var(--r-pill)', border:'1px solid var(--border)', background:'var(--surface)',
      color:'var(--text-secondary)', fontSize:12.5, cursor:'pointer'}}>
      <Cmp s={14} c="var(--text-muted)"/>{label}</button>
  );
}

/* 项目简介 — 封面 + 简介 + 统计 */
function Ov_ProjectIntro({novel}){
  const stats = [['章节',novel.chapters],['设定',WORLD.length],['角色',CHARACTERS.length],['笔记',FORESHADOW.length]];
  return (
    <div className="card" style={{padding:16}}>
      <div className="row gap6">
        <I.books s={16} c="var(--accent-warm)"/>
        <span style={{flex:1, fontSize:14, fontWeight:600, color:'var(--text-primary)'}}>项目简介</span>
        <I.copy s={14} c="var(--text-muted)"/>
      </div>
      <div className="row gap12" style={{marginTop:14, alignItems:'flex-start'}}>
        <Cover n={novel} w={80} h={112} fs={14}/>
        <div style={{flex:1, fontSize:12.5, color:'var(--text-secondary)', lineHeight:1.6,
          display:'-webkit-box', WebkitLineClamp:6, WebkitBoxOrient:'vertical', overflow:'hidden'}}>{novel.desc||'尚无简介'}</div>
      </div>
      <div className="row" style={{flexWrap:'wrap', gap:'8px 18px', marginTop:14, padding:'11px 14px',
        borderRadius:'var(--r-xl)', background:'var(--surface-container)'}}>
        {stats.map(([label,val])=>(
          <span key={label} className="row gap4">
            <span style={{fontSize:12.5, color:'var(--text-muted)'}}>{label}</span>
            <span style={{fontSize:12.5, fontWeight:600, color:'var(--text-primary)'}}>{val}</span>
          </span>
        ))}
      </div>
    </div>
  );
}

/* 灵感片段 — 伏笔 setup + 世界观正文，便签卡片堆叠 */
function Ov_Snippets({onOpenSection}){
  const tones = [
    {bg:'color-mix(in srgb, var(--accent-warm) 18%, transparent)', c:'var(--accent-amber)', tag:'灵感'},
    {bg:'color-mix(in srgb, var(--accent) 12%, transparent)', c:'var(--accent)', tag:'设定'},
    {bg:'color-mix(in srgb, var(--accent-warm) 16%, transparent)', c:'var(--accent-warm)', tag:'关系'},
  ];
  const notes = [];
  for(const f of FORESHADOW){ if(notes.length>=3) break; if(f.note) notes.push(f.note); }
  for(const w of WORLD){ if(notes.length>=3) break; if(w.desc) notes.push(w.desc); }
  return (
    <div className="card" style={{padding:16}}>
      <div className="row gap6">
        <I.spark s={16} c="var(--accent-warm)"/>
        <span style={{flex:1, fontSize:14, fontWeight:600, color:'var(--text-primary)'}}>灵感片段</span>
        <button className="press" onClick={()=>onOpenSection('foreshadow')} style={{display:'flex', alignItems:'center', gap:2,
          background:'transparent', border:'none', color:'var(--accent-warm)', fontSize:12.5, cursor:'pointer'}}>
          查看更多<I.chevR s={14} c="var(--accent-warm)"/></button>
      </div>
      <div className="col gap10" style={{marginTop:14}}>
        {notes.map((body,i)=>{
          const t = tones[i%tones.length];
          return (
            <div key={i} style={{padding:14, borderRadius:'var(--r-xl)', background:t.bg}}>
              <div style={{fontSize:12.5, color:'var(--text-primary)', lineHeight:1.55,
                display:'-webkit-box', WebkitLineClamp:3, WebkitBoxOrient:'vertical', overflow:'hidden'}}>{body}</div>
              <div style={{textAlign:'right', marginTop:8, fontSize:11, fontWeight:600, color:t.c}}>— {t.tag}</div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

/* 写作入口 — 4 张卡片（2×2） */
function Ov_WritingEntries({onOpenSection}){
  const entries = [
    {icon:'fileEdit', title:'正文写作', hint:'打开当前章节，接着写下去', hex:'var(--accent-amber)', k:'chapters'},
    {icon:'globe',    title:'设定',   hint:'地理、制度、历史与器物设定', hex:'var(--accent)', k:'world'},
    {icon:'scroll',   title:'大纲剧情', hint:'卷章脉络与情节节点', hex:'var(--accent-warm)', k:'outline'},
    {icon:'users',    title:'人物',     hint:'角色档案、关系与弧光', hex:'var(--info)', k:'characters'},
  ];
  return (
    <div className="col" style={{gap:12}}>
      <span className="display" style={{fontSize:18, fontWeight:700, color:'var(--text-primary)', letterSpacing:'-0.01em'}}>写作入口</span>
      <div style={{display:'grid', gridTemplateColumns:'1fr 1fr', gap:10}}>
        {entries.map(e=>{
          const Cmp = I[e.icon]||I.file;
          return (
            <div key={e.k} className="card press" onClick={()=>onOpenSection(e.k)}
              style={{padding:14}}>
              <div style={{width:36, height:36, borderRadius:'var(--r-lg)', background:tint(e.hex,.12),
                display:'flex', alignItems:'center', justifyContent:'center', color:e.hex}}><Cmp s={20}/></div>
              <div style={{fontSize:14, fontWeight:600, color:'var(--text-primary)', marginTop:12}}>{e.title}</div>
              <div style={{fontSize:11.5, color:'var(--text-muted)', lineHeight:1.5, marginTop:4,
                display:'-webkit-box', WebkitLineClamp:2, WebkitBoxOrient:'vertical', overflow:'hidden'}}>{e.hint}</div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

/* ============================================================
   分区 body（嵌入 WorkspaceScreen，无独立 PageHead）
   ============================================================ */

/* 左滑露出删除按钮（对齐 Flutter flutter_slidable 的 endActionPane） */
function SwipeRow({onDelete, children}){
  const [dx, setDx] = useState(0);
  const drag = useRef(null);
  const dxRef = useRef(0);          // 始终持有最新 dx，避免 end 闭包取到旧 state
  const REVEAL = 76;
  const child = React.Children.only(children);
  const childTap = child.props.onClick;   // 子项原本的点击行为（进入详情）
  const begin = (e)=>{
    e.currentTarget.setPointerCapture(e.pointerId);   // 手指移出元素也继续收事件
    drag.current = {x: e.clientX, base: dxRef.current, moved: false};
  };
  const move = (e)=>{
    if(!drag.current) return;
    const d = e.clientX - drag.current.x;
    if(Math.abs(d) > 4) drag.current.moved = true;
    const next = Math.max(-REVEAL, Math.min(0, drag.current.base + d));
    dxRef.current = next;
    setDx(next);
  };
  // setPointerCapture 会吞掉触摸端补发的 click，因此点击行为统一由 pointerup 驱动，不依赖原生 click
  const end = (e)=>{
    if(!drag.current) return;
    const moved = drag.current.moved;
    drag.current = null;
    if(moved){                                        // 拖动过：吸附到展开或收回
      const snap = dxRef.current < -REVEAL/2 ? -REVEAL : 0;
      dxRef.current = snap;
      setDx(snap);
      return;
    }
    if(dxRef.current !== 0){                           // 已露出时点击：先收回，不进入详情
      dxRef.current = 0;
      setDx(0);
      return;
    }
    if(childTap) childTap(e);                          // 收起状态点击：进入详情
  };
  // 左滑时直接把子元素（.card / .srow）右侧两角覆盖为直角，连同边框一起拉直，与红色删除区严丝合缝
  const open = dx < 0;
  const content = React.cloneElement(child, {
    onClick: undefined,                               // 点击由 pointerup 统一处理，避免重复触发
    style: {
      ...(child.props.style || {}),
      borderTopRightRadius: open ? 0 : child.props.style?.borderTopRightRadius,
      borderBottomRightRadius: open ? 0 : child.props.style?.borderBottomRightRadius,
    },
  });
  return (
    // 外层铺实心红底：行身左滑时整块红色直接贴着卡片露出，不会出现淡色似缝隙的区域；
    // 收起时不铺，免得红色从卡片圆角的抗锯齿边缘透出来
    <div style={{position:'relative', overflow:'hidden', borderRadius:'var(--r-2xl)', background:open?'var(--error)':'transparent', boxShadow:'var(--shadow-card)'}}>
      {/* 删除按钮固定在行身后，左滑露出；实心红底由外层提供，图标文字用白色 */}
      <button onClick={onDelete} style={{position:'absolute', top:0, right:0, bottom:0, width:REVEAL, border:'none',
        background:'transparent', color:'var(--on-accent)', display:'flex', flexDirection:'column',
        alignItems:'center', justifyContent:'center', gap:3, cursor:'pointer'}}>
        <I.trash s={18}/><span style={{fontSize:11, fontWeight:600}}>删除</span>
      </button>
      <div
        onPointerDown={begin}
        onPointerMove={move}
        onPointerUp={end}
        onPointerCancel={end}
        // 行身透明平移，右侧随子元素一起拉直；overflow 防止 .card 阴影/圆角溢出
        style={{transform:`translateX(${dx}px)`, transition: drag.current?'none':'transform .22s ease',
          touchAction:'pan-y', background:'var(--surface)', overflow:'hidden',
          borderRadius: open ? 'var(--r-2xl) 0 0 var(--r-2xl)' : 'var(--r-2xl)'}}>
        {content}
      </div>
    </div>
  );
}

/* ---------- 章节列表 ---------- */
function ChaptersBody({onScroll, onOpenChapter}){
  const [deleted, setDeleted] = useState([]);
  const del = (id)=> setDeleted(d=> d.includes(id) ? d : [...d, id]);
  return (
    <div className="viewport" onScroll={onScroll} style={{padding:'10px 18px 28px'}}>
      {VOLUMES.map(vol=>{
        const items = vol.items.filter(ch=>!deleted.includes(ch.id));
        if(items.length===0) return null;
        return (
          <div key={vol.vol} style={{marginBottom:14}}>
            <div className="row gap6" style={{padding:'4px 4px 8px'}}>
              <I.books s={13} c="var(--text-subtle)"/>
              <span style={{fontSize:11.5, fontWeight:700, color:'var(--text-subtle)', letterSpacing:.5}}>{vol.vol}</span>
            </div>
            <div className="col gap8">
              {items.map(ch=>(
                <SwipeRow key={ch.id} onDelete={()=>del(ch.id)}>
                  <div className="card press" onClick={()=>onOpenChapter(ch)} style={{padding:'12px 14px', display:'flex', alignItems:'center', gap:12}}>
                    <span className="display" style={{width:30, textAlign:'center', fontSize:16, fontWeight:700, color:ch.active?'var(--accent-warm)':'var(--text-subtle)', flex:'0 0 auto'}}>{ch.n}</span>
                    <div className="col" style={{flex:1, gap:3, minWidth:0}}>
                      <span className="display" style={{fontSize:15, fontWeight:700, color:ch.words?'var(--text-primary)':'var(--text-subtle)'}}>{ch.t}</span>
                      <span style={{fontSize:11.5, color:'var(--text-subtle)'}}>{ch.words?fmt(ch.words)+' 字':'尚未开始'}</span>
                    </div>
                    <StateChip state={ch.state} small/>
                    <I.chevR s={16} c="var(--text-subtle)"/>
                  </div>
                </SwipeRow>
              ))}
            </div>
          </div>
        );
      })}
    </div>
  );
}

/* ---------- 大纲（作品级条目列表，对齐 outlines_panel.dart） ---------- */
function OutlineBody({onScroll, onOpenDetail}){
  const [deleted, setDeleted] = useState([]);
  const del = (id)=> setDeleted(d=> d.includes(id) ? d : [...d, id]);
  const items = OUTLINES.filter(o=>!deleted.includes(o.id));
  return (
    <div className="viewport" onScroll={onScroll} style={{padding:'12px 18px 28px'}}>
      <div className="col gap10">
        {items.map(o=>{
          const st = OUTLINE_STATUS[o.status] || OUTLINE_STATUS.pending;
          return (
            <SwipeRow key={o.id} onDelete={()=>del(o.id)}>
              <div className="card press" onClick={()=>onOpenDetail && onOpenDetail(o)} style={{padding:'13px 14px'}}>
                <div className="row gap8" style={{marginBottom:7}}>
                  <span style={{width:8,height:8,borderRadius:'50%',background:st.hex,flex:'0 0 auto'}}></span>
                  <span className="display" style={{flex:1, fontSize:15, fontWeight:700, color:'var(--text-primary)'}}>{o.title}</span>
                  <span style={{fontSize:11.5, color:st.hex, fontWeight:600}}>{st.label}</span>
                </div>
                <p style={{margin:0, fontSize:12.5, color:'var(--text-muted)', lineHeight:1.6,
                  display:'-webkit-box', WebkitLineClamp:2, WebkitBoxOrient:'vertical', overflow:'hidden'}}>{o.content}</p>
                <div className="row gap6" style={{marginTop:9, alignItems:'center'}}>
                  <I.list s={13} c="var(--text-subtle)"/>
                  <span style={{flex:1, fontSize:11, color:'var(--text-subtle)'}}>{o.beats.length} 个节奏点</span>
                  <I.chevR s={15} c="var(--text-subtle)"/>
                </div>
              </div>
            </SwipeRow>
          );
        })}
      </div>
    </div>
  );
}

/* ---------- 人物列表 ---------- */
function CharactersBody({onScroll, onOpenDetail}){
  const [deleted, setDeleted] = useState([]);
  const del = (id)=> setDeleted(d=> d.includes(id) ? d : [...d, id]);
  const items = CHARACTERS.filter(ch=>!deleted.includes(ch.id));
  return (
    <div className="viewport" onScroll={onScroll} style={{padding:'12px 18px 28px'}}>
      <div className="col gap10">
        {items.map(ch=>(
          <SwipeRow key={ch.id} onDelete={()=>del(ch.id)}>
            <div className="card press" onClick={()=>onOpenDetail(ch)} style={{padding:'13px 14px', display:'flex', gap:12, alignItems:'center'}}>
              <Avatar label={ch.name[0]} size={46} tint={ch.tint} fs={19}/>
              <div className="col" style={{flex:1, gap:3, minWidth:0}}>
                <div className="row gap6">
                  <span className="display" style={{fontSize:15.5, fontWeight:700}}>{ch.name}</span>
                  {ch.tag && <span className="chip" style={{height:18,fontSize:10,padding:'0 7px',background:'color-mix(in srgb, var(--accent) 12%, transparent)',color:'var(--accent-warm)'}}>{ch.tag}</span>}
                </div>
                <span style={{fontSize:11.5, color:'var(--text-muted)'}}>{ch.role}</span>
                <span style={{fontSize:12, color:'var(--text-secondary)', lineHeight:1.5, marginTop:1,
                  display:'-webkit-box', WebkitLineClamp:1, WebkitBoxOrient:'vertical', overflow:'hidden'}}>{ch.one}</span>
              </div>
              <I.chevR s={16} c="var(--text-subtle)"/>
            </div>
          </SwipeRow>
        ))}
      </div>
    </div>
  );
}

/* ---------- 设定列表 ---------- */
function WorldBody({onScroll, onOpenDetail}){
  const [deleted, setDeleted] = useState([]);
  const del = (id)=> setDeleted(d=> d.includes(id) ? d : [...d, id]);
  const items = WORLD.filter(w=>!deleted.includes(w.id));
  return (
    <div style={{flex:1, display:'flex', flexDirection:'column', minHeight:0}}>
      <div className="viewport" onScroll={onScroll} style={{flex:1, padding:'12px 18px 28px'}}>
        <div className="col gap10">
          {items.map(w=>(
            <SwipeRow key={w.id} onDelete={()=>del(w.id)}>
              <div className="card press" onClick={()=>onOpenDetail(w)} style={{padding:'13px 14px', display:'flex', gap:12, alignItems:'center'}}>
                <EntityIcon icon={w.icon} hex={w.tint} s={42} is={21}/>
                <div className="col" style={{flex:1, gap:3, minWidth:0}}>
                  <div className="row gap6"><span className="display" style={{fontSize:14.5, fontWeight:700}}>{w.name}</span>
                    <span className="chip" style={{height:18,fontSize:10,padding:'0 7px',background:'var(--surface-dim)',color:'var(--text-muted)'}}>{w.cat}</span></div>
                  <span style={{fontSize:12, color:'var(--text-muted)', lineHeight:1.5,
                    display:'-webkit-box', WebkitLineClamp:2, WebkitBoxOrient:'vertical', overflow:'hidden'}}>{w.desc}</span>
                </div>
              </div>
            </SwipeRow>
          ))}
        </div>
      </div>
      <div style={{flex:'0 0 auto', padding:'0 18px calc(env(safe-area-inset-bottom,0px) + 18px)'}}>
        <button className="btn-ghost press" style={{width:'100%', height:44, borderStyle:'dashed', color:'var(--accent-warm)', fontWeight:600}}>
          <I.plus s={16}/>导入设定</button>
      </div>
    </div>
  );
}

/* ---------- 伏笔台账 ---------- */
function ForeshadowBody({onScroll, onOpenDetail}){
  const tone = (s)=> s==='closed'?{c:'var(--success)',bg:'color-mix(in srgb, var(--success) 12%, transparent)',t:'已回收'}:{c:'var(--warning)',bg:'color-mix(in srgb, var(--warning-text) 12%, transparent)',t:'待回收'};
  const [deleted, setDeleted] = useState([]);
  const del = (id)=> setDeleted(d=> d.includes(id) ? d : [...d, id]);
  const items = FORESHADOW.filter(f=>!deleted.includes(f.id));
  return (
    <div className="viewport" onScroll={onScroll} style={{padding:'12px 18px 28px'}}>
      <div className="col gap10">
        {items.map(f=>{
          const tn = tone(f.status);
          return (
            <SwipeRow key={f.id} onDelete={()=>del(f.id)}>
              <div className="card press" onClick={()=>onOpenDetail && onOpenDetail(f)} style={{padding:'13px 14px'}}>
                <div className="row gap8" style={{marginBottom:8}}>
                  <I.flag s={16} c={tn.c}/>
                  <span className="display" style={{fontSize:14.5, fontWeight:700, flex:1}}>{f.name}</span>
                  <span className="chip" style={{height:20,fontSize:10.5,padding:'0 8px',color:tn.c,background:tn.bg,fontWeight:600}}>{tn.t}</span>
                </div>
                <div className="row gap6" style={{marginBottom:8}}>
                  <span className="chip" style={{height:20,fontSize:10.5,padding:'0 8px',background:'var(--surface-dim)',color:'var(--text-muted)'}}>埋设 {f.plant}</span>
                  <I.arrowR s={13} c="var(--text-subtle)"/>
                  <span className="chip" style={{height:20,fontSize:10.5,padding:'0 8px',background:'var(--surface-dim)',color:'var(--text-muted)'}}>回收 {f.payoff}</span>
                </div>
                <p style={{margin:0, fontSize:12.5, color:'var(--text-secondary)', lineHeight:1.65}}>{f.note}</p>
              </div>
            </SwipeRow>
          );
        })}
      </div>
    </div>
  );
}

/* ---------- 图鉴（势力 / 生物 / 物品 / 技能） ---------- */
const COMPENDIUM_GROUPS = [
  {k:'faction', label:'势力', icon:'shield', tint:'var(--info)', entries:FACTIONS},
  {k:'creature', label:'生物', icon:'leaf', tint:'#4E7F6E', entries:CREATURES},
  {k:'item', label:'物品', icon:'diamond', tint:'#6E5D6B', entries:ITEMS},
  {k:'skill', label:'技能', icon:'spark', tint:'var(--accent)', entries:COMPENDIUM_SKILLS},
];

function CompendiumBody({onScroll, onOpenDetail}){
  const [filter, setFilter] = useState('all');
  const [query, setQuery] = useState('');
  const [expanded, setExpanded] = useState([]);
  const total = COMPENDIUM_GROUPS.reduce((n,g)=>n+g.entries.length,0);
  const visibleGroups = filter==='all' ? COMPENDIUM_GROUPS : COMPENDIUM_GROUPS.filter(g=>g.k===filter);
  const chooseFilter = (k)=>{
    setFilter(k);
    if(k!=='all') setExpanded([k]);
  };
  const toggleGroup = (k)=>setExpanded(xs=>xs.includes(k)?xs.filter(x=>x!==k):[...xs,k]);

  return (
    <div className="viewport" onScroll={onScroll} style={{padding:'12px 18px 32px'}} data-screen-label="compendium-list">
      <label style={{height:44, display:'flex', alignItems:'center', gap:9, padding:'0 4px 0 12px',
        border:'1px solid var(--border-input)', borderRadius:'var(--r-pill)', background:'var(--surface-high)'}}>
        <I.search s={17} c="var(--text-subtle)"/>
        <input value={query} onChange={e=>setQuery(e.target.value)} placeholder="搜索图鉴"
          style={{flex:1, minWidth:0, border:'none', outline:'none', background:'transparent',
            color:'var(--text-primary)', font:'13.5px var(--sans)'}}/>
        {query && <button className="press" onClick={()=>setQuery('')} aria-label="清除搜索"
          style={{width:44,height:44,border:0,background:'transparent',color:'var(--text-subtle)',display:'grid',placeItems:'center'}}><I.x s={15}/></button>}
      </label>

      <div style={{display:'flex', gap:6, overflowX:'auto', padding:'12px 0 14px', scrollbarWidth:'none'}}>
        {[{k:'all',label:'全部',entries:{length:total}}, ...COMPENDIUM_GROUPS].map(g=>{
          const on=filter===g.k;
          return <button key={g.k} className="press" onClick={()=>chooseFilter(g.k)}
            style={{flex:'0 0 auto',height:44,padding:'0 14px',borderRadius:'var(--r-pill)',
              border:'1px solid '+(on?'var(--accent)':'var(--border-subtle)'),background:on?'var(--accent)':'var(--surface)',
              color:on?'var(--on-accent)':'var(--text-secondary)',font:'600 12px var(--sans)',cursor:'pointer'}}>
            {g.label} <span style={{opacity:on ? .78 : .62, marginLeft:2}}>{g.entries.length}</span>
          </button>;
        })}
      </div>

      <div className="slist">
        {visibleGroups.map((g,groupIndex)=>{
          const matches=g.entries.filter(e=>!query.trim() || (e.name+' '+e.desc+' '+(e.sub||'')).toLowerCase().includes(query.trim().toLowerCase()));
          if(!matches.length) return null;
          const open=expanded.includes(g.k) || !!query.trim();
          const Cmp=I[g.icon];
          return <React.Fragment key={g.k}>
            <button className="srow press" onClick={()=>toggleGroup(g.k)}
              style={{width:'100%',border:0,borderTop:groupIndex?'1px solid var(--border-subtle)':'none',background:'var(--surface)',fontFamily:'var(--sans)'}}>
              <span style={{width:30,height:30,borderRadius:'var(--r-md)',display:'grid',placeItems:'center',background:tint(g.tint,.12),color:g.tint}}><Cmp s={16}/></span>
              <span style={{flex:1,textAlign:'left',fontSize:14,fontWeight:650,color:'var(--text-primary)'}}>{g.label}</span>
              <span style={{fontSize:12,color:'var(--text-muted)'}}>{matches.length}</span>
              <I.chevR s={16} c="var(--text-subtle)" style={{transform:open?'rotate(90deg)':'none',transition:'transform .16s'}}/>
            </button>
            {open && matches.map(e=><div key={e.id} className="press" onClick={()=>onOpenDetail(g.k,e)}
              style={{minHeight:58,display:'flex',alignItems:'center',gap:11,padding:'9px 12px 9px 18px',
                borderTop:'1px solid var(--border-subtle)',background:'var(--surface-high)'}}>
              <span style={{width:3,height:30,borderRadius:2,background:g.tint,opacity:.65}}></span>
              <div style={{flex:1,minWidth:0}}>
                <div className="row gap6"><span className="display" style={{fontSize:14,fontWeight:700}}>{e.name}</span>
                  {e.sub && <span style={{fontSize:10.5,color:'var(--text-muted)'}}>{e.sub}</span>}</div>
                <div style={{fontSize:11.5,color:'var(--text-muted)',whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis',marginTop:3}}>{e.desc}</div>
              </div>
              <I.chevR s={15} c="var(--text-subtle)"/>
            </div>)}
          </React.Fragment>;
        })}
        {visibleGroups.every(g=>!g.entries.some(e=>!query.trim() || (e.name+' '+e.desc+' '+(e.sub||'')).toLowerCase().includes(query.trim().toLowerCase()))) &&
          <Empty icon="search" text="没有匹配的图鉴条目" sub="换一个名称或关键词试试"/>}
      </div>
    </div>
  );
}

/* ---------- 通用设定实体列表 ---------- */
function EntityListBody({onScroll, list, onOpenDetail}){
  const [deleted, setDeleted] = useState([]);
  const del = (id)=> setDeleted(d=> d.includes(id) ? d : [...d, id]);
  const items = list.filter(e=>!deleted.includes(e.id));
  return (
    <div className="viewport" onScroll={onScroll} style={{padding:'12px 18px 28px'}}>
      <div className="col gap10">
        {items.map(e=>(
          <SwipeRow key={e.id} onDelete={()=>del(e.id)}>
            <div className="card press" onClick={()=>onOpenDetail && onOpenDetail(e)} style={{padding:'13px 14px', display:'flex', gap:12, alignItems:'center'}}>
              <div style={{width:42,height:42,borderRadius:'var(--r-lg)',flex:'0 0 auto',background:e.tint,boxShadow:'inset 0 0 0 1px rgba(255,255,255,.12)'}}></div>
              <div className="col" style={{flex:1, gap:3, minWidth:0}}>
                <div className="row gap6"><span className="display" style={{fontSize:14.5, fontWeight:700}}>{e.name}</span>
                  {e.sub && <span className="chip" style={{height:18,fontSize:10,padding:'0 7px',background:'var(--surface-dim)',color:'var(--text-muted)'}}>{e.sub}</span>}</div>
                <span style={{fontSize:12, color:'var(--text-muted)', lineHeight:1.5}}>{e.desc}</span>
              </div>
              <I.chevR s={16} c="var(--text-subtle)"/>
            </div>
          </SwipeRow>
        ))}
      </div>
    </div>
  );
}

/* ---------- 素材 ---------- */
function MaterialsBody({onScroll, onOpenDetail}){
  const [deleted, setDeleted] = useState([]);
  const del = (id)=> setDeleted(d=> d.includes(id) ? d : [...d, id]);
  const items = MATERIALS.filter(m=>!deleted.includes(m.id));
  return (
    <div style={{flex:1, display:'flex', flexDirection:'column', minHeight:0}}>
      <div className="viewport" onScroll={onScroll} style={{flex:1, padding:'12px 18px 28px'}}>
        <div className="slist">
          {items.map(m=>{
            const Cmp = I[m.icon]||I.file;
            return (
              <SwipeRow key={m.id} onDelete={()=>del(m.id)}>
                <div className="srow" onClick={()=>onOpenDetail && onOpenDetail(m)}>
                  <div className="sicon" style={{background:'color-mix(in srgb, var(--accent) 13%, transparent)', color:'var(--accent-warm)'}}><Cmp s={18}/></div>
                  <div className="col" style={{flex:1}}>
                    <span style={{fontSize:14, fontWeight:500}}>{m.name}</span>
                    <span style={{fontSize:11.5, color:'var(--text-subtle)'}}>{m.sub}</span>
                  </div>
                  <I.chevR s={16} c="var(--text-subtle)"/>
                </div>
              </SwipeRow>
            );
          })}
        </div>
      </div>
      <div style={{flex:'0 0 auto', padding:'0 18px calc(env(safe-area-inset-bottom,0px) + 18px)'}}>
        <button className="btn-ghost press" style={{width:'100%', height:44, borderStyle:'dashed', color:'var(--accent-warm)', fontWeight:600}}>
          <I.plus s={16}/>导入素材</button>
      </div>
    </div>
  );
}

/* 地图 tab 的 MapBody 在 m_map.jsx */

/* ---------- 关系图谱 ---------- */
function GraphBody(){
  const [sel, setSel] = useState(null);
  const nodeById = (id)=> GRAPH.nodes.find(n=>n.id===id);
  const selNode = sel ? nodeById(sel) : null;
  return (
    <div style={{flex:1, position:'relative', minHeight:0, background:'var(--surface-dim)',
      backgroundImage:'radial-gradient(var(--border) 1px, transparent 1px)', backgroundSize:'22px 22px', overflow:'hidden'}}>
      <svg viewBox="0 0 100 100" preserveAspectRatio="xMidYMid meet" style={{position:'absolute', inset:0, width:'100%', height:'100%'}}>
        {GRAPH.edges.map((e,i)=>{
          const a=nodeById(e.a), b=nodeById(e.b);
          const active = sel && (e.a===sel||e.b===sel);
          return (
            <g key={i}>
              <line x1={a.x} y1={a.y} x2={b.x} y2={b.y} stroke={active?'var(--accent)':'var(--text-subtle)'} strokeWidth={active?'0.7':'0.4'}/>
              <text x={(a.x+b.x)/2} y={(a.y+b.y)/2 - 0.8} fontSize="2.4" textAnchor="middle"
                fill={active?'var(--accent-warm)':'var(--text-subtle)'} style={{fontFamily:'var(--sans)'}}>{e.label}</text>
            </g>
          );
        })}
      </svg>
      {GRAPH.nodes.map(n=>{
        const km = KIND_META[n.kind];
        const Cmp = I[km.icon]||I.user;
        const on = sel===n.id;
        const d = n.r*1.0;
        return (
          <button key={n.id} className="press" onClick={()=>setSel(on?null:n.id)} style={{position:'absolute',
            left:n.x+'%', top:n.y+'%', transform:'translate(-50%,-50%)', width:d, height:d, borderRadius:'50%',
            background:n.tint, border:'2px solid '+(on?'var(--accent)':'rgba(255,255,255,.6)'),
            boxShadow:on?'0 0 0 4px color-mix(in srgb, var(--accent) 25%, transparent), var(--shadow-card)':'var(--shadow-card)',
            display:'flex', flexDirection:'column', alignItems:'center', justifyContent:'center', gap:1, color:'#fff', cursor:'pointer'}}>
            <Cmp s={d*0.34}/>
            <span style={{fontSize:Math.max(8,d*0.16), fontWeight:700, fontFamily:'var(--display)', lineHeight:1}}>{n.label}</span>
          </button>
        );
      })}
      <div className="row gap8" style={{position:'absolute', left:14, top:12, flexWrap:'wrap', maxWidth:'70%'}}>
        {Object.entries(KIND_META).map(([k,m])=>(
          <span key={k} className="chip" style={{height:22,fontSize:10.5,padding:'0 8px',background:'color-mix(in srgb, var(--canvas) 86%, transparent)',color:'var(--text-secondary)'}}>{m.label}</span>
        ))}
      </div>
      {selNode && (
        <div className="pop-in" style={{position:'absolute', left:14, right:14, bottom:'calc(env(safe-area-inset-bottom,0px) + 16px)', zIndex:25}}>
          <div className="card" style={{padding:'13px 14px', display:'flex', gap:12, alignItems:'center', boxShadow:'var(--shadow-float)'}}>
            <Avatar label={selNode.label[0]} size={42} tint={selNode.tint} fs={17}/>
            <div className="col" style={{flex:1, gap:2}}>
              <span className="display" style={{fontSize:15, fontWeight:700}}>{selNode.label}</span>
              <span style={{fontSize:11.5, color:'var(--text-muted)'}}>{KIND_META[selNode.kind].label} · {GRAPH.edges.filter(e=>e.a===selNode.id||e.b===selNode.id).length} 个关系</span>
            </div>
            <button className="btn-ghost press" style={{height:34, padding:'0 12px'}}>查看 <I.chevR s={14}/></button>
          </div>
        </div>
      )}
    </div>
  );
}

/* ============================================================
   章节编辑器（全屏 overlay 推入）
   ============================================================ */
function EditorScreen({novel, chapter, onBack, onOpenChat}){
  const [ref, scrolled] = useScrolled();
  const [showToc, setShowToc] = useState(false);
  const [outlineOpen, setOutlineOpen] = useState(true);
  const c = chapter || ACTIVE_CHAPTER;

  return (
    <div className="screen fade-in" data-screen-label="chapter-editor">
      <div className={"appbar"+(scrolled?' scrolled':'')} style={{paddingTop:54}}>
        <div className="row" style={{justifyContent:'space-between', padding:'8px 12px 8px', gap:6}}>
          <IconBtn icon="chevL" size={24} onClick={onBack}/>
          <div className="col" style={{alignItems:'center', flex:1, minWidth:0}}>
            <span className="display" style={{fontSize:14.5, fontWeight:700, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis', maxWidth:'100%'}}>{novel.title}</span>
            <span style={{fontSize:11, color:'var(--text-muted)'}}>第 {parseInt(c.n)} 章 · 已保存</span>
          </div>
          <IconBtn icon="history" onClick={()=>{}}/>
          <IconBtn icon="list" onClick={()=>setShowToc(true)}/>
        </div>
      </div>

      <div className="viewport" ref={ref} style={{padding:'14px 22px 120px'}}>
        <div className="row gap8" style={{marginBottom:8}}>
          <span className="chip" style={{background:'color-mix(in srgb, var(--accent-warm) 12%, transparent)', color:'var(--accent-warm)', height:24}}>卷一 · 河上人</span>
          <StateChip state={c.state}/>
        </div>
        <input defaultValue={c.t} className="display"
          style={{border:'none', outline:'none', background:'transparent', width:'100%', fontSize:26, fontWeight:700, color:'var(--text-primary)', padding:'2px 0 12px', letterSpacing:'-0.02em'}}/>

        {/* 章节大纲 card */}
        <div className="card" style={{padding:0, overflow:'hidden', marginBottom:18}}>
          <button className="press" onClick={()=>setOutlineOpen(o=>!o)} style={{width:'100%', display:'flex', alignItems:'center', gap:8, padding:'11px 13px', background:'var(--surface-container)', border:'none', cursor:'pointer'}}>
            <I.chart s={14} c="var(--accent-warm)"/>
            <span style={{fontSize:12.5, fontWeight:700, color:'var(--text-secondary)', flex:1, textAlign:'left'}}>章节大纲</span>
            <I.caretD s={14} c="var(--text-subtle)" style={{transform:outlineOpen?'none':'rotate(-90deg)', transition:'transform .18s'}}/>
          </button>
          {outlineOpen && <div style={{padding:'12px 14px', fontSize:13, color:'var(--text-muted)', lineHeight:1.7, borderTop:'1px solid var(--border-subtle)'}}>{c.summary}</div>}
        </div>

        <div className="reading">
          <p className="sel" contentEditable suppressContentEditableWarning>{(c.body||[])[0]}</p>
          {(c.body||[]).slice(1).map((p,i)=>(<p key={i} contentEditable suppressContentEditableWarning>{p}</p>))}
        </div>
      </div>

      {/* bottom toolbar */}
      <div style={{position:'absolute', left:0, right:0, bottom:0, zIndex:20,
        background:'color-mix(in srgb, var(--surface-high) 94%, transparent)', backdropFilter:'blur(18px)', WebkitBackdropFilter:'blur(18px)',
        borderTop:'1px solid var(--border-subtle)', padding:'10px 16px calc(env(safe-area-inset-bottom,0px) + 12px)'}}>
        <div className="row" style={{justifyContent:'space-between'}}>
          <div className="col gap4">
            <span style={{fontSize:13, fontWeight:700, color:'var(--text-primary)'}}>{fmt(c.words)} 字</span>
            <span style={{fontSize:11, color:'var(--text-subtle)'}}>约 {Math.max(1,Math.round(c.words/200))} 分钟 · 自动保存于 21:23</span>
          </div>
          <div className="row gap8">
            <button className="press" style={{width:42,height:42,borderRadius:'50%',background:'var(--surface)',border:'1px solid var(--border)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--text-secondary)'}}><I.eye s={20}/></button>
            <button className="press" style={{width:42,height:42,borderRadius:'50%',background:'var(--surface)',border:'1px solid var(--border)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--text-secondary)'}}><I.text s={20}/></button>
            <button className="btn-accent press" onClick={onOpenChat} style={{height:42, padding:'0 18px'}}><I.spark s={18}/>AI 助手</button>
          </div>
        </div>
      </div>

      {showToc && (
        <Sheet onClose={()=>setShowToc(false)} max="78%">
          <SheetHeader iconBox={<EntityIcon icon="list" hex="var(--accent)" s={36} is={18}/>} title="目录"
            right={<span className="row gap6 press" style={{color:'var(--accent-warm)', fontSize:13, fontWeight:600}}><I.plus s={16}/>新建</span>}/>
          <div className="viewport" style={{padding:'8px 12px 28px'}}>
            {VOLUMES.map(vol=>(
              <div key={vol.vol} style={{marginBottom:8}}>
                <div style={{fontSize:11, fontWeight:700, color:'var(--text-subtle)', letterSpacing:.5, padding:'10px 10px 6px'}}>{vol.vol}</div>
                {vol.items.map(ch=>(
                  <div key={ch.id} className="press" onClick={()=>setShowToc(false)}
                    style={{display:'flex', alignItems:'center', gap:11, padding:'11px 10px', borderRadius:'var(--r-lg)', background:ch.active?'var(--selected)':'transparent'}}>
                    <span style={{width:26, textAlign:'center', fontSize:12, fontWeight:700, color:ch.active?'var(--accent-warm)':'var(--text-subtle)', fontFamily:'var(--display)'}}>{ch.n}</span>
                    <div className="col" style={{flex:1, gap:2}}>
                      <span className="display" style={{fontSize:14.5, fontWeight:ch.active?700:600, color:ch.words?'var(--text-primary)':'var(--text-subtle)'}}>{ch.t}</span>
                      <span style={{fontSize:11, color:'var(--text-subtle)'}}>{ch.words?fmt(ch.words)+' 字':'未开始'}</span>
                    </div>
                    <StateChip state={ch.state} small/>
                  </div>
                ))}
              </div>
            ))}
          </div>
        </Sheet>
      )}
    </div>
  );
}

/* ============================================================
   人物档案（全屏 overlay 推入）
   IA：折叠 Hero + 吸顶锚点栏 + 七个分组连续滚动。
   字段全部平铺可见，不再藏进 tab；与桌面 CharacterProfile 同一套分组。
   对齐 lib/mobile/pages/character_editor_page.dart 的字段模型。
   ============================================================ */
const CHAR_SECTIONS = [
  {id:'identity',  label:'身份档案', icon:'user',  hint:'稳定的人物基础信息'},
  {id:'figure',    label:'形象',     icon:'image', hint:'外观与图像资料'},
  {id:'bio',       label:'人物小传', icon:'books', hint:'创作初期设定，后续较少改动'},
  {id:'outward',   label:'外在表现', icon:'mask',  hint:'他人可观察到的部分'},
  {id:'psyche',    label:'内在心理', icon:'brain', hint:'动机、弧光与条件化行为'},
  {id:'story',     label:'剧情状态', icon:'path',  hint:'随最新章节推进而变化'},
  {id:'relations', label:'关系网络', icon:'hub',   hint:'只读概览 · 编辑请前往关系图'},
];

const CHAR_ROLES   = [['protagonist','主角'],['antagonist','反派'],['supporting','配角'],['minor','龙套']];
const CHAR_GENDERS = [['male','男'],['female','女'],['non_binary','非二元'],['other','其他'],['unknown','未知']];
const labelOf = (pairs, k) => (pairs.find(p=>p[0]===k)||pairs[0])[1];

/* 分组标题 */
function CharSecHead({icon, title, hint, right}){
  const Cmp = I[icon];
  return (
    <div className="row" style={{gap:9, marginBottom:14}}>
      <span style={{width:24,height:24,borderRadius:'var(--r-md)',background:'var(--selected)',color:'var(--accent-warm)',
        display:'flex',alignItems:'center',justifyContent:'center',flex:'0 0 auto'}}><Cmp s={14}/></span>
      <span className="display" style={{fontSize:16.5, fontWeight:700, color:'var(--text-primary)'}}>{title}</span>
      {hint && <span style={{fontSize:10.5, color:'var(--text-subtle)'}}>{hint}</span>}
      {right && <span style={{marginLeft:'auto'}}>{right}</span>}
    </div>
  );
}

/* 标签在上、值在下的可编辑字段 */
function CharField({label, children}){
  return (
    <div className="col gap4" style={{marginBottom:12}}>
      <span style={{fontSize:12, color:'var(--text-muted)', fontWeight:500}}>{label}</span>
      {children}
    </div>
  );
}

/* 自动增高的长文编辑区 */
function CharProse({value, dense}){
  const ref = useRef(null);
  const [v, setV] = useState(value||'');
  const fit = ()=>{ const el=ref.current; if(!el) return; el.style.height='auto'; el.style.height=el.scrollHeight+'px'; };
  useEffect(fit, []);
  return <textarea ref={ref} className="charprose" value={v} rows={dense?2:3}
    style={dense?{fontSize:14, lineHeight:1.7, padding:'10px 12px'}:null}
    onChange={e=>{ setV(e.target.value); fit(); }}/>;
}

/* 只读关系分组 */
function CharRelGroup({icon, title, items}){
  const Cmp = I[icon];
  return (
    <div style={{marginBottom:16}}>
      <div className="row" style={{gap:6, marginBottom:8}}>
        <span style={{color:'var(--text-muted)', display:'flex'}}><Cmp s={13}/></span>
        <span style={{fontSize:13, fontWeight:600, color:'var(--text-secondary)'}}>{title}</span>
        <span className="chip" style={{height:16, fontSize:10, padding:'0 6px', background:'var(--surface-dim)', color:'var(--text-muted)'}}>{items.length}</span>
        <span className="press row gap2" style={{marginLeft:'auto', fontSize:11.5, fontWeight:600, color:'var(--accent-warm)'}}>
          关系图<I.chevR s={12}/></span>
      </div>
      <div className="row" style={{flexWrap:'wrap', gap:6}}>
        {items.map(([type,name])=>(
          <span key={name} className="relchip press">
            <em>{type}</em>{name}
          </span>
        ))}
      </div>
    </div>
  );
}

function CharacterDetail({entity, onBack, onOpenChat}){
  const vpRef = useRef(null);
  const barRef = useRef(null);
  const [scrolled, setScrolled] = useState(false);
  const [active, setActive] = useState('identity');
  const ch = entity;
  const p = ch.profile;

  /* 无完整档案的次要角色仍走原来的简表 */
  if(!p) return <CharacterDetailLite entity={ch} onBack={onBack} onOpenChat={onOpenChat}/>;

  const [aliases, setAliases] = useState(p.aliases);
  const [tags, setTags] = useState(p.behavior);

  useEffect(()=>{
    const el = vpRef.current; if(!el) return;
    const onScroll = ()=>{
      setScrolled(el.scrollTop > 132);
      if(el.scrollTop + el.clientHeight >= el.scrollHeight - 8){
        return setActive(CHAR_SECTIONS[CHAR_SECTIONS.length-1].id);
      }
      const top = el.getBoundingClientRect().top + 128;
      let cur = CHAR_SECTIONS[0].id;
      for(const s of CHAR_SECTIONS){
        const n = el.querySelector(`[data-sec="${s.id}"]`);
        if(n && n.getBoundingClientRect().top <= top) cur = s.id;
      }
      setActive(cur);
    };
    el.addEventListener('scroll', onScroll);
    return ()=>el.removeEventListener('scroll', onScroll);
  },[]);

  /* 当前分组的锚点始终留在可视范围内 */
  useEffect(()=>{
    const bar = barRef.current;
    const chip = bar && bar.querySelector(`[data-anchor="${active}"]`);
    if(!chip) return;
    bar.scrollTo({left:Math.max(0, chip.offsetLeft - (bar.clientWidth - chip.offsetWidth)/2), behavior:'smooth'});
  },[active]);

  const jump = (id)=>{
    const el = vpRef.current;
    const n = el && el.querySelector(`[data-sec="${id}"]`);
    if(n) el.scrollTo({top:n.offsetTop - 96, behavior:'smooth'});
  };

  return (
    <div className="screen fade-in" data-screen-label="character-detail">
      <PageHead title={ch.name} sub={scrolled ? `${labelOf(CHAR_ROLES,p.roleKey)} · ${labelOf(CHAR_GENDERS,p.genderKey)} · ${p.age}` : null}
        onBack={onBack} scrolled={scrolled} center
        right={<div className="row"><IconBtn icon="undo" size={18}/><IconBtn icon="dots" size={18}/></div>}/>

      <div className="viewport" ref={vpRef}>
        {/* Hero */}
        <div className="col" style={{alignItems:'center', gap:8, padding:'10px 24px 20px'}}>
          <div style={{position:'relative'}}>
            <Avatar label={ch.name[0]} size={88} tint={ch.tint} fs={34}/>
            {/* 头像是正圆，按钮贴 45° 切点才不会像被咬了一口 */}
            <button className="press" style={{position:'absolute', right:2, bottom:2, width:26, height:26, borderRadius:'50%',
              border:'2px solid var(--canvas)', background:'var(--surface)', color:'var(--text-secondary)',
              display:'flex', alignItems:'center', justifyContent:'center'}}><I.image s={12}/></button>
          </div>
          <input className="charname" defaultValue={ch.name}/>
          <div className="row gap6" style={{flexWrap:'wrap', justifyContent:'center'}}>
            <span className="chip" style={{background:'var(--accent)', color:'var(--on-accent)', fontWeight:600}}>{labelOf(CHAR_ROLES,p.roleKey)}</span>
            <span className="chip" style={{background:'var(--selected)', color:'var(--text-secondary)'}}>{labelOf(CHAR_GENDERS,p.genderKey)}</span>
            <span className="chip" style={{background:'var(--selected)', color:'var(--text-secondary)'}}>{p.age} 岁</span>
          </div>
          <p style={{margin:'4px 0 0', fontFamily:'var(--sans)', fontSize:12.5, color:'var(--text-muted)', lineHeight:1.55, textAlign:'center'}}>{p.identity}</p>
          <span className="row gap4" style={{fontSize:11, color:'var(--success)'}}><I.check s={11}/>已保存 · 今天 14:26</span>
        </div>

        {/* 吸顶锚点栏 */}
        <div className="charanchors">
          <div className="charanchors__scroll" ref={barRef}>
            {CHAR_SECTIONS.map(s=>(
              <button key={s.id} data-anchor={s.id} onClick={()=>jump(s.id)}
                className={"charanchor"+(active===s.id?' is-on':'')}>{s.label}</button>
            ))}
          </div>
        </div>

        <div style={{padding:'0 20px 72px'}}>
          {/* 身份档案 */}
          <section className="charsec" data-sec="identity">
            <CharSecHead icon="user" title="身份档案" hint="稳定的人物基础信息"/>
            <CharField label="角色定位">
              <select className="tinput" defaultValue={p.roleKey}>
                {CHAR_ROLES.map(([v,l])=><option key={v} value={v}>{l}</option>)}
              </select>
            </CharField>
            <CharField label="性别">
              <select className="tinput" defaultValue={p.genderKey}>
                {CHAR_GENDERS.map(([v,l])=><option key={v} value={v}>{l}</option>)}
              </select>
            </CharField>
            <CharField label="年龄"><input className="tinput" defaultValue={p.age}/></CharField>
            <CharField label="身份 / 称号"><input className="tinput" defaultValue={p.identity}/></CharField>
            <CharField label="别名">
              <div className="chipfield">
                {aliases.map(a=>(
                  <span key={a} className="chip aliaschip">{a}
                    <button className="press" onClick={()=>setAliases(aliases.filter(x=>x!==a))}
                      style={{border:'none', background:'transparent', color:'var(--text-subtle)', padding:2, display:'flex'}}><I.x s={11}/></button>
                  </span>
                ))}
                <input className="chipfield__input" placeholder="回车添加"/>
              </div>
            </CharField>
          </section>

          {/* 形象 */}
          <section className="charsec" data-sec="figure">
            <CharSecHead icon="image" title="形象" hint="外观与图像资料"
              right={<span className="press row gap4" style={{fontSize:11.5, fontWeight:600, color:'var(--accent-warm)'}}><I.spark s={13}/>AI 生成</span>}/>
            <CharProse value={p.appearance}/>
            <SectionLabel text="头像与照片"/>
            <div className="row gap10" style={{flexWrap:'wrap'}}>
              {p.photos.map(ph=>(
                <div key={ph.label} className="col gap4" style={{width:84}}>
                  <div style={{width:84, height:84, borderRadius:'var(--r-xl)', background:ph.tint,
                    boxShadow:'inset 0 0 0 1px rgba(255,255,255,.16)'}}></div>
                  <span style={{fontSize:10.5, color:'var(--text-subtle)', textAlign:'center'}}>{ph.label}</span>
                </div>
              ))}
              <button className="press col" style={{width:84, height:84, borderRadius:'var(--r-xl)', border:'1px dashed var(--border-input)',
                background:'transparent', color:'var(--text-muted)', alignItems:'center', justifyContent:'center', gap:3, fontSize:10.5}}>
                <I.plus s={16}/>添加</button>
            </div>
          </section>

          {/* 人物小传 */}
          <section className="charsec" data-sec="bio">
            <CharSecHead icon="books" title="人物小传" hint="创作初期设定，后续较少改动"/>
            <CharProse value={p.biography}/>
          </section>

          {/* 外在表现 */}
          <section className="charsec" data-sec="outward">
            <CharSecHead icon="mask" title="外在表现" hint="他人可观察到的部分"/>
            <CharProse value={p.description}/>
          </section>

          {/* 内在心理 */}
          <section className="charsec" data-sec="psyche">
            <CharSecHead icon="brain" title="内在心理" hint="动机、弧光与条件化行为"/>
            <CharField label="核心动机"><CharProse value={p.motivation} dense/></CharField>
            <CharField label="人物弧光"><CharProse value={p.arc} dense/></CharField>
            <SectionLabel text="性格"/>
            <CharProse value={p.personality}/>
            <div style={{height:16}}></div>
            <SectionLabel text="情境行为"/>
            <div className="col gap6">
              {tags.map(([ctx,body],i)=>(
                <div key={i} className="btag">
                  <span className="btag__ctx">{ctx}</span>
                  <span className="btag__body">{body}</span>
                  <button className="press" onClick={()=>setTags(tags.filter((_,j)=>j!==i))}
                    style={{border:'none', background:'transparent', color:'var(--text-subtle)', padding:2, display:'flex'}}><I.x s={12}/></button>
                </div>
              ))}
              <button className="press btag btag--add" onClick={()=>setTags([...tags,['新情境','描述该情境下的行为倾向']])}>
                <I.plus s={13}/>添加情境行为</button>
            </div>
          </section>

          {/* 剧情状态 */}
          <section className="charsec" data-sec="story">
            <CharSecHead icon="path" title="剧情状态" hint="随最新章节推进而变化"/>
            <div className="slist" style={{marginBottom:12}}>
              <div className="srow">
                <span className="row gap6" style={{fontSize:12.5, color:'var(--text-muted)'}}><I.bookmark s={14}/>首次登场</span>
                <span className="row gap2" style={{marginLeft:'auto', fontSize:13.5, fontWeight:600, color:'var(--accent-warm)'}}>
                  {p.firstChapter}<I.chevR s={14}/></span>
              </div>
            </div>
            <div className="charcallout">
              <I.spark s={14}/>
              <span>该段落由 AI 随剧情自动维护，手动修改会在下次同步时被覆盖。</span>
            </div>
            <CharProse value={p.state}/>
          </section>

          {/* 关系网络 */}
          <section className="charsec" data-sec="relations">
            <CharSecHead icon="hub" title="关系网络" hint="只读概览 · 编辑请前往关系图"/>
            <CharRelGroup icon="users" title="人物关系" items={p.relations.characters}/>
            <CharRelGroup icon="flag"  title="所属势力" items={p.relations.factions}/>
            <CharRelGroup icon="magic" title="技能"     items={p.relations.skills}/>
            <CharRelGroup icon="diamond" title="物品"   items={p.relations.items}/>
          </section>

          <button className="btn-ghost press" onClick={onOpenChat} style={{width:'100%', height:42, borderColor:'var(--accent)', color:'var(--accent-warm)', fontWeight:600}}>
            <I.spark s={16} c="var(--accent)"/>用 AI 丰富这个角色</button>
        </div>
      </div>
    </div>
  );
}

/* 次要角色的简表详情（数据里没有完整档案时） */
function CharacterDetailLite({entity, onBack, onOpenChat}){
  const [ref, scrolled] = useScrolled();
  const ch = entity;
  return (
    <div className="screen fade-in" data-screen-label="character-detail-lite">
      <PageHead title={ch.name} sub={ch.role} onBack={onBack} scrolled={scrolled} center right={<IconBtn icon="pencil"/>}/>
      <div className="viewport" ref={ref} style={{padding:'8px 20px 28px'}}>
        <div className="col" style={{alignItems:'center', gap:10, padding:'8px 0 20px'}}>
          <Avatar label={ch.name[0]} size={76} tint={ch.tint} fs={30}/>
          <div className="col" style={{alignItems:'center', gap:4}}>
            <span className="display" style={{fontSize:21, fontWeight:700, letterSpacing:'-0.02em'}}>{ch.name}</span>
            <span style={{fontSize:12.5, color:'var(--text-muted)'}}>{ch.role}</span>
          </div>
          <p style={{margin:0, fontSize:13.5, color:'var(--text-secondary)', lineHeight:1.7, textAlign:'center', maxWidth:300}}>{ch.one}</p>
        </div>
        <div className="slist" style={{marginBottom:18}}>
          {ch.fields.map(([k,v])=>(
            <div key={k} className="srow" style={{cursor:'default'}}>
              <span style={{fontSize:13, color:'var(--text-muted)', width:64, flex:'0 0 auto'}}>{k}</span>
              <span style={{flex:1, fontSize:14, color:'var(--text-primary)', textAlign:'right'}}>{v}</span>
            </div>
          ))}
        </div>
        <button className="btn-ghost press" onClick={onOpenChat} style={{width:'100%', height:42, borderColor:'var(--accent)', color:'var(--accent-warm)', fontWeight:600}}>
          <I.spark s={16} c="var(--accent)"/>用 AI 丰富这个角色</button>
      </div>
    </div>
  );
}

Object.assign(window, {
  WorkspaceScreen, EditorScreen, CharacterDetail, SwipeRow, WorkspaceTabs, CompendiumBody,
});
