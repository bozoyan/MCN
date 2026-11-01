/* ============================================================
   Screenplay — 剧本（移动端）
   数据复用 designs/desktop/screenplay/data.jsx（SP_* 全局，index.html 先加载）。
   本轮覆盖：书架「剧本」tab + 工作台外壳（横向 tab 沿用小说移动端顺序，
   加入 desktop 剧本专属创作入口）+ 概览分区（继续写 hero/统计/季·集列表，对齐 desktop
   SpOverview 与小说概览的 Ov_ContinueHero）+ 四个剧情分区内屏：
   剧本 / 大纲 / 节拍 / 场次（列表）。制作不在剧本里，移动端不提供制片界面。
   季/集不做第二层 tab：desktop 第二列的「季选择器 + 集列表」在移动端拆成两个入口 ——
   概览分区的季/集列表（选集进剧本）和标题栏作品名下方的季/集胶囊
   （点开 bottom sheet 切换），剧情分区不再常驻一条集 chip 行。
   四个分区的结构、文案和业务口径照抄 desktop screenplay/views.jsx，
   表现层按 mobile kit 重写；排版处理（△ 动作标、对话 42px 缩进折角、字幕居中、
   注释块）对照 desktop screenplay.css 逐项搬。
   电影（supported===false）第一期不支持：不进书架、不给任何入口。
   ============================================================ */

/* 封面底色：desktop data.jsx 的 cover 是命名风格，移动端 Cover 组件吃 hex。 */
const SPM_COVER_TINT = { ink:'#3E5A58', mountains:'#6B7D8C', tree:'#5E7F6A' };

/* 这三个过滤 helper 定义在 desktop screenplay/views.jsx 而不在 data.jsx，
   移动端不加载 views.jsx，在这里重定义同一份逻辑（逐行对齐 desktop）：
   集号在季内从 1 重来，凡是按集过滤的地方都要传 seasonId，不能跨季拼。 */
function spScenesOf(projId, epId){
  return SP_SCENES.filter((s)=>s.proj===projId && (epId ? s.ep===epId : true));
}
function spEpisodesOf(projId, seasonId){
  return SP_EPISODES.filter((e)=>e.proj===projId && (seasonId ? e.season===seasonId : true));
}
function spCharsOf(projId){
  return SP_CHARS.filter((c)=>c.proj===projId);
}

/* 场次四个新字段的 helper，逐行对齐 desktop views.jsx（阶段 M，方案 §4.1）：
   显示名有短标题用短标题、没有回退地点 —— 回退只在展示层，数据里仍是空串，
   不从梗概截取回填；短标题顶掉地点之后地点跟时间、内外一起降成次行。
   正文不走这两个函数：正文场次头永远显示 place，那是要导出的标准剧本格式（§3.1）。 */
function spSceneName(scene){
  return scene.title || scene.place;
}
function spSceneCond(scene){
  const cond = `${scene.time} / ${scene.ie}`;
  return scene.title ? `${scene.place} · ${cond}` : cond;
}
const SP_IE_VALUES = ['内','外','内外'];
function spSecsLabel(secs){
  if(secs == null) return null;
  if(secs < 60) return `${secs} 秒`;
  const m = Math.floor(secs/60), rest = secs%60;
  return rest ? `${m} 分 ${rest} 秒` : `${m} 分`;
}

/* 剧本项目 → 书架卡片视图模型。
   meta 用集/场（多季带季数），不用小说的章/字 —— 这是书架上区分两种作品的信号之一。 */
function spmCardOf(p){
  const seasons = spSeasonsOf(p.id);
  const stats = SP_STATS_OF(p.id);
  const parts = [];
  if(seasons.length > 1) parts.push(`${seasons.length} 季`);
  if(p.kind === 'series') parts.push(`${stats.episodes} 集`);
  parts.push(`${stats.scenes} 场`);
  return {
    id: p.id,
    title: p.title,
    tint: SPM_COVER_TINT[p.cover] || '#3E5A58',
    kindLabel: p.kind === 'series' ? '剧集' : '电影',
    genre: p.genre,
    meta: parts.join(' · '),
    updated: p.updated,
    status: p.status === 'writing' ? '创作中' : '筹备中',
    proj: p,
  };
}

const SP_MOBILE = SP_PROJECTS.filter((p)=>p.supported !== false).map(spmCardOf);

/* ============================ 通用小件（desktop views.jsx 的移动端对应） ============================ */

/* 八分之一页的带分数排版 —— "1 6/8" 必须一眼读成「一又八分之六」（对齐 SpPages）。 */
function SpmPages({value, unit='页', c}){
  const m = /(\d+)\s+(\d)\/8/.exec(value || '');
  const style = {display:'inline-flex', alignItems:'baseline', fontVariantNumeric:'tabular-nums', color:c};
  if(!m) return <span style={style}>{value}{unit && <span style={{marginLeft:3}}>{unit}</span>}</span>;
  const whole = Number(m[1]), num = Number(m[2]);
  return (
    <span style={style}>
      {(whole > 0 || num === 0) && <span>{whole}</span>}
      {num > 0 && (
        <span style={{marginLeft:3, fontSize:'0.86em', letterSpacing:'-0.02em'}}>
          <sup style={{fontSize:'0.78em', verticalAlign:'0.42em'}}>{num}</sup>⁄<sub style={{fontSize:'0.78em', verticalAlign:'-0.1em'}}>8</sub>
        </span>
      )}
      {unit && <span style={{marginLeft:3}}>{unit}</span>}
    </span>
  );
}

/* 场次状态（对齐 desktop .sp-state 的四个色） */
const SPM_SCENE_STATE = {
  '定稿':  {bg:'color-mix(in srgb, var(--success) 13%, transparent)',  c:'var(--success)'},
  '修改中':{bg:'color-mix(in srgb, var(--warning-text) 13%, transparent)',  c:'var(--warning)'},
  '草稿':  {bg:'var(--selected)',      c:'var(--text-secondary)'},
  '待写':  {bg:'var(--surface-dim)',   c:'var(--text-subtle)'},
};
/* 集的状态比场多一个「写作中」（当前正在写的那一集），其余沿用场景色口径。 */
const SPM_EP_STATE = {
  '写作中':{bg:'color-mix(in srgb, var(--accent) 16%, transparent)', c:'var(--accent-warm)'},
  ...SPM_SCENE_STATE,
};
function SpmState({state, states}){
  const map = states || SPM_SCENE_STATE;
  const t = map[state] || map['待写'] || map['草稿'];
  return <span style={{display:'inline-flex', alignItems:'center', height:20, padding:'0 8px',
    borderRadius:'var(--r-pill)', fontSize:10.5, fontWeight:600, background:t.bg, color:t.c}}>{state}</span>;
}

function SpmChip({icon, children, plain}){
  const Cmp = icon ? I[icon] : null;
  return (
    <span style={{display:'inline-flex', alignItems:'center', gap:4, height:22, padding:'0 8px',
      border:'1px solid '+(plain?'transparent':'var(--border-input)'),
      borderRadius:'var(--r-pill)', background:plain?'var(--surface-dim)':'var(--surface)',
      fontSize:10.5, fontWeight:500, color:'var(--text-muted)', whiteSpace:'nowrap'}}>
      {Cmp && <Cmp s={11}/>}
      {children}
    </span>
  );
}

/* 把「@沈砚 递出短烛」里的 @角色 渲染成提及 chip（desktop views.jsx 的 SpAtText）。
   镜头描述和提示词里会写 @角色，两端要读出同样的东西。 */
function SpmAtText({text, projId}){
  const chars = spCharsOf(projId);
  if(!chars.length) return <React.Fragment>{text}</React.Fragment>;
  const names = chars.map((c)=>c.name).sort((a,b)=>b.length-a.length);
  const re = new RegExp(`@(${names.join('|')})`, 'g');
  const out = [];
  let last = 0, m;
  while((m = re.exec(text)) !== null){
    if(m.index > last) out.push(text.slice(last, m.index));
    const char = chars.find((c)=>c.name===m[1]);
    out.push(
      <span key={`${m.index}-${m[1]}`} style={{display:'inline-flex', alignItems:'center',
        padding:'0 5px', margin:'0 1px', borderRadius:'var(--r-sm)',
        background:char.role==='主角'?'color-mix(in srgb, var(--warning-text) 12%, transparent)':'var(--selected)',
        fontFamily:'var(--sans)', fontSize:12, fontWeight:500,
        color:char.role==='主角'?'var(--warning)':'var(--text-secondary)'}}>@{m[1]}</span>
    );
    last = m.index + m[0].length;
  }
  if(last < text.length) out.push(text.slice(last));
  return <React.Fragment>{out}</React.Fragment>;
}

/* ---------------------------- AI 改动 ----------------------------
   口径与 desktop 完全一致：改动已经应用，标的是「AI 动过这一场」+ 可回退，
   不是「等你接受」；审阅单位是场次。 */
const SPM_CHANGE_TYPE = {
  create:  {label:'新增', icon:'plus',    color:'var(--accent-warm)'},
  rewrite: {label:'改写', icon:'pencil',  color:'var(--accent)'},
  expand:  {label:'扩写', icon:'pencil',  color:'var(--success)'},
  trim:    {label:'删减', icon:'scissors',color:'var(--error)'},
};

function SpmAiDot({sceneId}){
  const change = spAiChangeOf(sceneId);
  if(!change) return null;
  const t = SPM_CHANGE_TYPE[change.change] || SPM_CHANGE_TYPE.rewrite;
  return <span style={{flex:'none', width:6, height:6, borderRadius:'50%', background:t.color}}
    title={`AI ${t.label} · ${change.field}`}/>;
}

function SpmAiBar({sceneId}){
  const change = spAiChangeOf(sceneId);
  if(!change) return null;
  const t = SPM_CHANGE_TYPE[change.change] || SPM_CHANGE_TYPE.rewrite;
  const Cmp = I[t.icon];
  const isCreate = change.change === 'create';
  const btnStyle = {display:'inline-flex', alignItems:'center', gap:3, height:24, padding:'0 8px',
    border:'1px solid var(--border-input)', borderRadius:'var(--r-pill)', background:'var(--surface)',
    color:'var(--text-secondary)', fontSize:11, fontWeight:500, cursor:'pointer', flex:'none'};
  return (
    <div style={{display:'flex', alignItems:'center', flexWrap:'wrap', gap:8, padding:'8px 10px',
      marginBottom:12, borderRadius:'var(--r-lg)',
      background:isCreate?'color-mix(in srgb, var(--warning-text) 10%, transparent)':'var(--surface-dim)',
      fontSize:11.5, color:isCreate?'var(--warning)':'var(--text-muted)'}}>
      <Cmp s={13} c={t.color}/>
      <span style={{fontWeight:600, color:isCreate?'var(--warning)':'var(--text-secondary)'}}>AI {t.label} · {change.field}</span>
      <span style={{flex:1}}/>
      <button type="button" className="press" style={btnStyle}>查看变更</button>
      <button type="button" className="press" style={btnStyle}><I.undo s={12}/>回退</button>
      {/* 新建整场的回退后果和改一段正文不一样，必须说清楚；提示独占一行（对齐桌面）。 */}
      {change.hint && <span style={{flex:'0 0 100%', lineHeight:1.5}}>{change.hint}</span>}
    </div>
  );
}

/* ============================ 概览 ============================
   结构：hero（继续写作，样式对齐小说概览 Ov_ContinueHero 的渐变暖板）→ 统计卡
   → 季/集列表。desktop 的「每集进度」进度条在移动端并进每张集卡片
   （分钟/目标时长），不单独占一块。
   季/集列表同时是选集入口：点一集进入剧本分区接着写。多季按季分组（带集数进度），
   单季时季这一层不画（对齐 desktop：不是隐藏，是根本不存在）。 */

/* 一集的场次/篇幅/分钟汇总，概览卡片与切换 sheet 共用。 */
function spmEpStats(projId, epId){
  const scenes = spScenesOf(projId, epId);
  return {
    scenes,
    pages: spFormatEighths(scenes.reduce((sum, s)=>sum + spEighths(s.pages), 0)),
    minutes: Math.round(scenes.reduce((sum, s)=>sum + s.minutes, 0)),
  };
}

function SpmEpisodeMeta({proj, ep}){
  const st = spmEpStats(proj.id, ep.id);
  if(!st.scenes.length){
    return <span style={{fontSize:11.5, color:'var(--text-subtle)'}}>还没有场次 · 目标 {ep.target} 分钟</span>;
  }
  return (
    <span style={{fontSize:11.5, color:'var(--text-muted)'}}>
      {st.scenes.length} 场 · <SpmPages value={st.pages}/> · 约 {st.minutes} 分钟
    </span>
  );
}

/* 来源作品 chip（对齐 desktop SpSourceChip）：指得到标改编自，指不到标不可用，
   为空就是原创。移动端不在剧本工作台里往小说跳，先只做标识。 */
function SpmSourceChip({proj}){
  if(!proj.sourceId) return <SpmChip icon="pencil">原创</SpmChip>;
  const source = ((window.REVERIC_DATA||{}).novels || []).find((n)=>n.id===proj.sourceId)
    || (window.NOVELS || []).find((n)=>n.id===proj.sourceId);
  if(!source) return <SpmChip icon="warn">来源作品不可用</SpmChip>;
  return <SpmChip icon="books">改编自《{source.title}》</SpmChip>;
}

function SpmStat({label, value, unit}){
  return (
    <div className="col" style={{gap:2, minWidth:0}}>
      <span style={{fontSize:10.5, color:'var(--text-subtle)'}}>{label}</span>
      <span className="display" style={{fontSize:16, fontWeight:700, color:'var(--text-primary)',
        fontVariantNumeric:'tabular-nums'}}>
        {value}
        {unit && <span style={{marginLeft:2, fontSize:10.5, fontWeight:400,
          color:'var(--text-muted)'}}>{unit}</span>}
      </span>
    </div>
  );
}

function SpOverviewBody({proj, seasonId, epId, onOpenEpisode, onGoto, onScroll}){
  const seasons = spSeasonsOf(proj.id);
  const multi = seasons.length > 1;
  const stats = SP_STATS_OF(proj.id);
  const isSeries = proj.kind === 'series';
  const curEp = spEpisodesOf(proj.id, seasonId).find((e)=>e.id===epId) || null;

  return (
    <div className="viewport" onScroll={onScroll} style={{padding:'10px 20px 24px'}}>

      {/* hero：继续写作面板，版式逐项对齐小说概览的 Ov_ContinueHero ——
          白卡片、上次写到的位置、serif 预览（这里放 logline）、墨玉主按钮；
          来源/集数/更新这些事实 chips 收在分隔线后，不与动作区抢视觉。 */}
      <div className="card" style={{padding:18, marginBottom:14}}>
        <div className="row gap6">
          <I.leaf s={16} c="var(--accent-warm)"/>
          <span style={{fontSize:13.5, fontWeight:600, color:'var(--accent-warm)'}}>继续写作</span>
        </div>
        {curEp && (
          <div style={{fontSize:12, color:'var(--text-muted)', marginTop:12}}>
            上次写到 · {multi && `${spSeasonLabel(spSeasonById(seasonId))} · `}{curEp.label} · {curEp.title}
          </div>
        )}
        <div className="serif" style={{fontSize:15.5, fontWeight:500, lineHeight:1.7,
          color:'var(--text-primary)', marginTop:6}}>{proj.logline}</div>
        <button type="button" className="press" onClick={()=>onGoto('script')}
          style={{width:'100%', height:46, marginTop:16, border:'none', borderRadius:'var(--r-pill)',
            background:'var(--accent)', color:'var(--on-accent)', fontSize:14.5, fontWeight:600,
            cursor:'pointer', display:'flex', alignItems:'center', justifyContent:'center', gap:6}}>
          <I.pencil s={16} c="var(--surface)"/>继续写{curEp ? ` ${curEp.label}` : ''}
        </button>
        <div style={{height:1, background:'var(--border-subtle)', margin:'14px 0 12px'}}/>
        <div className="row" style={{flexWrap:'wrap', gap:6}}>
          <SpmSourceChip proj={proj}/>
          {isSeries && !multi && (
            <SpmChip icon="list">{spEpisodeCount(seasonId).text}</SpmChip>
          )}
          {isSeries && multi && (
            <SpmChip icon="list">{seasons.length} 季 · {stats.episodes} 集</SpmChip>
          )}
          <SpmChip icon="clock">更新于 {proj.updated}</SpmChip>
        </div>
      </div>

      {/* 统计卡：desktop sp-stats 同一组指标；固定 4 列 grid，列对齐，
          多季 9 项时末行只落「节拍」一格也不歪。 */}
      <div className="card" style={{padding:'12px 16px', marginBottom:14,
        display:'grid', gridTemplateColumns:'repeat(4, 1fr)', gap:'12px 8px'}}>
        {multi && <SpmStat label="季" value={stats.seasons} unit="季"/>}
        {isSeries && <SpmStat label="集" value={stats.episodes} unit="集"/>}
        <SpmStat label="场次" value={stats.scenes} unit="场"/>
        <SpmStat label="篇幅" value={<SpmPages value={stats.pages} unit=""/>} unit="页"/>
        <SpmStat label="估算时长" value={stats.minutes} unit="分钟"/>
        <SpmStat label="台词" value={stats.lines} unit="句"/>
        <SpmStat label="角色" value={stats.chars} unit="人"/>
        <SpmStat label="景地" value={stats.places} unit="处"/>
        <SpmStat label="节拍" value={stats.beats} unit="个"/>
      </div>

      {seasons.map((s)=>{
        const eps = spEpisodesOf(proj.id, s.id);
        const c = spEpisodeCount(s.id);
        return (
          <div key={s.id} style={{marginBottom:18}}>
            {multi && (
              <div className="row" style={{justifyContent:'space-between', alignItems:'baseline',
                padding:'0 4px 8px'}}>
                <span style={{fontFamily:'var(--display)', fontSize:14, fontWeight:700,
                  color:'var(--text-primary)'}}>{spSeasonLabel(s)}</span>
                <span style={{fontSize:11, color:'var(--text-muted)'}}>
                  {c.text}
                  {/* 超出规划是有效状态不是错误，只提示不拦（对齐 desktop）。 */}
                  {c.over && <span style={{color:'var(--warning)'}}> · 已超出规划</span>}
                </span>
              </div>
            )}
            <div className="col gap10">
              {eps.map((e)=>{
                const st = spmEpStats(proj.id, e.id);
                const pct = Math.min(100, Math.round((st.minutes / (e.target || 1)) * 100));
                return (
                <div key={e.id} className="card press" onClick={()=>onOpenEpisode(e)}
                  style={{padding:'12px 14px'}}>
                  <div className="row gap8" style={{alignItems:'center'}}>
                    <span className="display" style={{flex:1, minWidth:0, fontSize:14.5, fontWeight:700,
                      color:'var(--text-primary)', whiteSpace:'nowrap', overflow:'hidden',
                      textOverflow:'ellipsis'}}>{e.label} · {e.title}</span>
                    <SpmState state={e.state} states={SPM_EP_STATE}/>
                    <I.chevR s={15} c="var(--text-subtle)"/>
                  </div>
                  <div style={{marginTop:7}}><SpmEpisodeMeta proj={proj} ep={e}/></div>
                  {/* 每集进度（desktop 每集进度卡的口径：按目标时长算，超过 100% 截断）。 */}
                  {st.scenes.length > 0 && (
                    <div className="row gap8" style={{marginTop:10, alignItems:'center'}}>
                      <span style={{flex:1, height:3, borderRadius:2, overflow:'hidden',
                        background:'var(--surface-dim)'}}>
                        <span style={{display:'block', height:'100%', width:`${pct}%`,
                          borderRadius:2, background:'var(--accent-warm)'}}/>
                      </span>
                      <span style={{flex:'none', fontSize:10.5, color:'var(--text-subtle)',
                        fontVariantNumeric:'tabular-nums'}}>{st.minutes} / {e.target} 分钟</span>
                    </div>
                  )}
                </div>
                );
              })}
              {!eps.length && (
                <div style={{padding:'10px 4px', fontSize:12, color:'var(--text-subtle)'}}>这一季还没有集</div>
              )}
              <button type="button" className="press" style={{width:'100%', height:40,
                display:'flex', alignItems:'center', justifyContent:'center', gap:6,
                border:'1px dashed var(--border-input)', borderRadius:'var(--r-2xl)',
                background:'transparent', color:'var(--text-muted)', fontSize:12.5, fontWeight:600,
                cursor:'pointer'}}>
                <I.plus s={13}/>新增一集
              </button>
            </div>
          </div>
        );
      })}
      {/* 新增/管理季是低频操作：这一轮只留新增入口，改名/重排/删季后续再补。 */}
      <button type="button" className="press" style={{width:'100%', height:44,
        display:'flex', alignItems:'center', justifyContent:'center', gap:6,
        border:'1px dashed var(--border-input)', borderRadius:'var(--r-2xl)',
        background:'transparent', color:'var(--text-muted)', fontSize:13, fontWeight:600,
        cursor:'pointer'}}>
        <I.plus s={14}/>新增一季
      </button>
    </div>
  );
}

/* ============================ 季 / 集 切换（标题栏 sheet） ============================
   标题栏作品名下方的季/集胶囊点开这里：多季时先一排季 chip（切换查看的季，
   不关闭 sheet），下面是该季的集列表，点集即切换。单季时季这一层不画。 */
function SpEpSwitcher({proj, seasonId, epId, onPick, onManage, onClose}){
  const seasons = spSeasonsOf(proj.id);
  const multi = seasons.length > 1;
  const [sid, setSid] = useState(seasonId);
  const eps = spEpisodesOf(proj.id, sid);

  return (
    <Sheet onClose={onClose}>
      <SheetHeader iconBox={<EntityIcon icon="books" hex="var(--accent)" s={36} is={18}/>}
        title="切换季 / 集"
        sub={multi ? `共 ${seasons.length} 季 · 人物与地点跨季共享` : `共 ${eps.length} 集`}/>
      {multi && (
        <div style={{display:'flex', gap:6, overflowX:'auto', alignItems:'center',
          padding:'10px 14px 2px', flex:'0 0 auto', scrollbarWidth:'none'}}>
          {seasons.map((s)=>{
            const on = s.id === sid;
            return (
              <button key={s.id} type="button" className="press" onClick={()=>setSid(s.id)}
                style={{flex:'0 0 auto', height:30, padding:'0 12px', borderRadius:'var(--r-pill)',
                  border:'1px solid '+(on?'var(--accent)':'var(--border-subtle)'),
                  background:on?'var(--accent)':'var(--surface)',
                  color:on?'var(--on-accent)':'var(--text-secondary)',
                  fontSize:12, fontWeight:600, whiteSpace:'nowrap', cursor:'pointer'}}>
                {spSeasonLabel(s)}
              </button>
            );
          })}
          {/* 管理季的唯一入口。改名 / 排序 / 删除是低频操作，不该占据 chip 行的宽度，
              所以收成一枚齿轮跟在季后面。点它会关掉这一层再开管理 sheet ——
              两层 bottom sheet 叠着，上面那层的标题会压住下面那层的标题。 */}
          <button type="button" className="press" aria-label="管理季" onClick={onManage}
            style={{flex:'0 0 auto', display:'flex', alignItems:'center', justifyContent:'center',
              width:30, height:30, borderRadius:'var(--r-pill)',
              border:'1px solid var(--border-subtle)', background:'var(--surface)',
              color:'var(--text-muted)', cursor:'pointer'}}>
            <I.gear s={15}/>
          </button>
        </div>
      )}
      <div className="viewport" style={{padding:'4px 14px 20px'}}>
        <div className="slist">
          {eps.map((e)=>{
            const on = sid === seasonId && e.id === epId;
            return (
              <div key={e.id} className="srow press" onClick={()=>onPick(sid, e.id)}>
                <div className="col" style={{flex:1, gap:2, minWidth:0}}>
                  <span style={{fontSize:14, fontWeight:600,
                    color:on?'var(--accent-warm)':'var(--text-primary)'}}>{e.label} · {e.title}</span>
                  <SpmEpisodeMeta proj={proj} ep={e}/>
                </div>
                <SpmState state={e.state} states={SPM_EP_STATE}/>
                {on && <I.check s={17} c="var(--accent)"/>}
              </div>
            );
          })}
          {!eps.length && (
            <div style={{padding:'10px 4px', fontSize:12, color:'var(--text-subtle)'}}>这一季还没有集</div>
          )}
          <div className="srow press" style={{color:'var(--text-muted)'}}>
            <I.plus s={15}/><span style={{fontSize:13, fontWeight:500}}>新增一集</span>
          </div>
        </div>
      </div>
    </Sheet>
  );
}

/* ============================ 管理季（合并后的单层 sheet） ============================
   早先移动端是两层：季选择 sheet 列一遍季，点「管理季」把它关掉，再弹一个管理
   sheet 又列一遍。两层做的是同一件事 —— 管理 sheet 里整行点击本来就等于切季。
   合并成一层之后，切季仍然是一次点击，改名 / 排序 / 删除就在同一行的右侧。

   390 宽放不下「季名 + 集数 + 四个操作」一行，所以摘要占一行、操作右对齐占一行。 */

/* 集数的三种态，和桌面 SpEpisodeCount 同一份规则：3 集 / 2/8 集 / 5/4 集 + 已超出规划。
   超出规划是有效状态，不是错误 —— 提示一下，不拦任何操作。 */
function SpmEpCount({seasonId}){
  const c = spEpisodeCount(seasonId);
  return (
    <span className="row" style={{alignItems:'center', gap:5, flexWrap:'wrap'}}>
      <span style={{fontFamily:'var(--mono)', fontSize:11.5, fontVariantNumeric:'tabular-nums',
        fontWeight:c.over?600:400, color:c.over?'var(--warning)':'var(--text-subtle)'}}>{c.text}</span>
      {c.over && (
        <span style={{display:'inline-flex', alignItems:'center', height:18, padding:'0 6px',
          borderRadius:'var(--r-sm)', background:'color-mix(in srgb, var(--warning-text) 13%, transparent)', color:'var(--warning)',
          fontSize:10, fontWeight:600}}>已超出规划</span>
      )}
    </span>
  );
}

function SpmSeasonAct({icon, label, disabled, danger, flip, onClick}){
  const Cmp = I[icon];
  return (
    <button type="button" className={disabled?'':'press'} aria-label={label} title={label}
      disabled={disabled} onClick={onClick}
      style={{display:'flex', alignItems:'center', justifyContent:'center', flex:'0 0 auto',
        width:36, height:36, padding:0, border:0, borderRadius:'var(--r-md)',
        background:'transparent', cursor:disabled?'default':'pointer', opacity:disabled?.32:1,
        color:danger?'var(--error)':'var(--text-secondary)'}}>
      <Cmp s={17} style={flip?{transform:'rotate(180deg)'}:undefined}/>
    </button>
  );
}

function SpmSeasonManageSheet({proj, seasonId, onEnterSeason, onClose}){
  const seasons = spSeasonsOf(proj.id);
  const [editing, setEditing] = useState(null);   // null = 列表态，否则是正在改的那一季
  const [kb, setKb] = useState(false);            // 键盘是否弹起
  const editSeason = editing ? spSeasonById(editing) : null;
  const only = seasons.length === 1;

  const leaveEdit = ()=>{ setKb(false); setEditing(null); };

  return (
    <React.Fragment>
    <Sheet onClose={onClose} max="78%" lift={kb ? SPM_KEYBOARD_H : 0}>
      <SheetHeader iconBox={<EntityIcon icon="books" hex="var(--accent)" s={36} is={18}/>}
        title={editSeason ? '本季设置' : '管理季'}
        sub={editSeason ? spSeasonLabel(editSeason) : `共 ${seasons.length} 季 · 人物与地点跨季共享`}
        right={<IconBtn icon="x" size={19} c="var(--text-muted)" ariaLabel="关闭"
          onClick={editSeason ? leaveEdit : onClose}/>}/>

      {editSeason ? (
        <React.Fragment>
          <div className="viewport" style={{padding:'14px 16px 4px'}}>
            <SpmField label="季标题" hint="留空就只显示季号">
              <div contentEditable suppressContentEditableWarning onFocus={()=>setKb(true)}
                style={{...SPM_BOX, fontFamily:'var(--display)', fontSize:14}}>{editSeason.title}</div>
            </SpmField>
            {/* 规划是作者给自己定的目标，不是上限 —— 写超了只提示，不拦。 */}
            <SpmField label="规划集数" hint="留空就只显示实际集数">
              <div contentEditable suppressContentEditableWarning onFocus={()=>setKb(true)}
                style={{...SPM_BOX, width:110, fontFamily:'var(--mono)', fontSize:14,
                  fontVariantNumeric:'tabular-nums',
                  color:editSeason.planned!=null?'var(--text-primary)':'var(--text-subtle)'}}>
                {editSeason.planned == null ? '' : editSeason.planned}
              </div>
            </SpmField>
          </div>
          {/* 提交条贴在键盘上沿，不随内容滚走 —— 改完一个数字还要往回滚才能按保存是最烦的。 */}
          <div className="row" style={{justifyContent:'flex-end', gap:8, flex:'0 0 auto',
            padding:'10px 16px 14px', borderTop:'1px solid var(--border-subtle)'}}>
            <button type="button" className="btn-ghost press" onClick={leaveEdit}
              style={{height:38, padding:'0 16px'}}>取消</button>
            <button type="button" className="btn-accent press" onClick={leaveEdit}
              style={{height:38, padding:'0 20px'}}>保存</button>
          </div>
        </React.Fragment>
      ) : (
        <React.Fragment>
          <div className="viewport" style={{padding:'12px 14px 4px'}}>
            <div className="col gap8">
              {seasons.map((s, i)=>{
                const on = s.id === seasonId;
                return (
                  <div key={s.id} style={{background:on?'var(--selected)':'var(--surface)',
                    border:'1px solid '+(on?'var(--accent)':'var(--border-subtle)'),
                    borderRadius:'var(--r-2xl)'}}>
                    {/* 整块摘要就是「进入这一季」—— 管理季时最常做的事仍然是换一季去写。
                        长按这一块拖动可以排序，和上移 / 下移是同一件事的两条路径。 */}
                    <div className="press" onClick={()=>onEnterSeason(s.id)}
                      style={{display:'flex', flexDirection:'column', gap:6, padding:'12px 14px 8px',
                        cursor:'pointer'}}>
                      <span style={{fontSize:14, fontWeight:on?600:500,
                        color:on?'var(--accent-warm)':'var(--text-primary)'}}>{spSeasonLabel(s)}</span>
                      <SpmEpCount seasonId={s.id}/>
                    </div>
                    <div className="row" style={{justifyContent:'flex-end', gap:2,
                      padding:'0 8px 6px'}}>
                      <SpmSeasonAct icon="caretD" label="上移" flip disabled={i === 0}/>
                      <SpmSeasonAct icon="caretD" label="下移" disabled={i === seasons.length - 1}/>
                      <SpmSeasonAct icon="pencil" label="本季设置" onClick={()=>setEditing(s.id)}/>
                      {/* 删一季会连着这一季的集、节拍、场次和正文一起删，第一期没有回收站，
                          所以删除只留在这里，AI 不给这条路径。唯一一季没有删除入口。 */}
                      <SpmSeasonAct icon="trash" label={only?'至少保留一季':'删除这一季'}
                        danger disabled={only}/>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
          {/* 新增一季固定在底部，季多了往下滚也不会把它挤出视口。
              点了会关掉 sheet 并直接跳进新的一季 —— 新增之后要写的是那一季的第一集。 */}
          <div className="row" style={{justifyContent:'flex-end', flex:'0 0 auto',
            padding:'10px 16px 14px', borderTop:'1px solid var(--border-subtle)'}}>
            <button type="button" className="btn-accent press" onClick={onClose}
              style={{height:38, padding:'0 16px', display:'inline-flex', alignItems:'center', gap:6}}>
              <I.plus s={15}/>新增一季
            </button>
          </div>
        </React.Fragment>
      )}
    </Sheet>
    {kb && <SpmFakeKeyboard/>}
    </React.Fragment>
  );
}

/* 键盘占位 —— 只为了在设计稿上看清「保存」没有被挡住，不是要画一块 iOS 键盘。
   真机上这段高度来自 MediaQuery.viewInsets.bottom。 */
const SPM_KEYBOARD_H = 252;
function SpmFakeKeyboard(){
  return (
    <div style={{position:'absolute', left:0, right:0, bottom:0, height:SPM_KEYBOARD_H,
      zIndex:55, background:'color-mix(in srgb, var(--surface-dim) 82%, var(--text-muted))', borderTop:'1px solid var(--border)',
      display:'flex', alignItems:'center', justifyContent:'center'}}>
      <span style={{fontSize:11, letterSpacing:'.08em', color:'color-mix(in srgb, var(--shadow-base) 38%, transparent)'}}>键盘</span>
    </div>
  );
}

/* ============================ 剧本正文 ============================
   元素排版逐项对照 desktop screenplay.css 的 .sp-el--*：
   动作带 △ 悬挂标、对话 42px 缩进 + 折角引线、字幕居中 letter-spacing、
   注释是「注」前缀的侧条块。桌面的 ⌘1-8 在移动端无意义，元素条收成
   底部一排等宽图标按钮；点正文里的元素会点亮对应类型（对齐 onFocus）。 */
const SPM_ELEMENTS = [
  {id:'scene',  label:'场次', icon:'grid'},
  {id:'action', label:'动作', icon:'waves'},
  {id:'char',   label:'角色', icon:'user'},
  {id:'paren',  label:'括号', icon:'quote'},
  {id:'dialog', label:'对话', icon:'chat'},
  {id:'trans',  label:'转场', icon:'arrowR'},
  {id:'note',   label:'注释', icon:'pencil'},
  {id:'sub',    label:'字幕', icon:'text'},
];

/* 正文场次头右侧那一块：情绪 badge（贴最右）。
   整块 userSelect:none —— 它是界面元件，不是正文。选不中、复制不走，
   导出的 screenplay.md 里也没有它，正文本身仍是「场号、地点 时间/内外」。
   情绪能进正文而场次短标题不能：短标题长得就像正文的一部分，
   情绪是 sans 小号 accent chip，一眼看得出不是稿子里的字（§3.1）。
   390 宽放不下两个 badge，正文里只露一个情绪。
   没有「属性」按钮：场次头本身可点，点了就开场次属性 —— 一行里既有可点的标题、
   又有一个干同样事的按钮，是两个入口一件事。 */
function SpmHeadingMeta({scene}){
  if(!scene) return null;
  return (
    <span contentEditable={false} className="row" style={{marginLeft:'auto', paddingLeft:10,
      gap:8, alignItems:'center', flex:'none', userSelect:'none', WebkitUserSelect:'none'}}>
      <SpmEmoBadges scene={scene} max={1}/>
    </span>
  );
}

function SpmElement({el, first, caret, onFocus, scene, onSceneProps}){
  const active = caret === el;
  const wrap = (style, children) => (
    <div onClick={()=>onFocus(el)} style={{position:'relative', cursor:'text',
      marginTop:first?0:10, ...style}}>
      {active && <span style={{position:'absolute', left:-12, top:2, bottom:2, width:2,
        borderRadius:1, background:'var(--accent)'}}/>}
      {children}
    </div>
  );

  switch(el.t){
    case 'scene':
      // 场次头是结构化元素，不是自由文本：地点是地点实体的引用（属性里是下拉 +
      // 「新建地点」），内外景是枚举。所以这一行不进元素编辑，点一下开场次属性。
      return (
        <div onClick={()=>scene && onSceneProps(scene)}
          style={{position:'relative', cursor:'pointer', marginTop:first?0:32,
            fontFamily:'var(--serif)', fontSize:17, fontWeight:700, lineHeight:1.5,
            color:'var(--text-primary)', display:'flex', alignItems:'baseline'}}>
          <span style={{color:'var(--text-muted)', fontVariantNumeric:'tabular-nums'}}>{el.no}、</span>
          <span>{el.place}</span>
          <span style={{marginLeft:14}}>
            {el.time}<span style={{margin:'0 5px', color:'var(--text-subtle)', fontWeight:400}}>/</span>{el.ie}
          </span>
          <SpmHeadingMeta scene={scene}/>
        </div>
      );
    case 'cast':
      return wrap({marginTop:first?0:4, fontFamily:'var(--serif)', fontSize:13.5, lineHeight:1.6,
        color:'var(--text-muted)'},
        <React.Fragment>出场人物：<span style={{color:'var(--text-secondary)'}}>{el.names.join('、')}</span></React.Fragment>);
    case 'action':
      return wrap({paddingLeft:22, fontFamily:'var(--serif)', fontSize:15.5, lineHeight:1.8,
        color:'var(--text-primary)'},
        <React.Fragment>
          <span style={{position:'absolute', left:0, top:'0.35em', fontSize:11, lineHeight:1,
            color:'var(--text-subtle)'}}>△</span>
          {el.text}
        </React.Fragment>);
    case 'char':
      return wrap({marginTop:first?0:16, fontFamily:'var(--serif)', fontSize:15.5, fontWeight:700,
        lineHeight:1.6, color:'var(--text-primary)'},
        <React.Fragment>
          {el.name}
          {el.cont && <span style={{fontWeight:400, fontSize:13, color:'var(--text-muted)'}}>（续）</span>}：
        </React.Fragment>);
    case 'paren':
      return wrap({marginTop:first?0:2, paddingLeft:42, fontFamily:'var(--serif)', fontSize:13.5,
        lineHeight:1.6, color:'var(--text-muted)'}, `（${el.text}）`);
    case 'dialog':
      return wrap({marginTop:first?0:2, paddingLeft:42, fontFamily:'var(--serif)', fontSize:15.5,
        lineHeight:1.8, color:'var(--text-primary)'},
        <React.Fragment>
          <span style={{position:'absolute', left:22, top:'0.45em', width:10, height:9,
            borderLeft:'1px solid var(--border-input)', borderBottom:'1px solid var(--border-input)',
            borderBottomLeftRadius:3}}/>
          {el.text}
        </React.Fragment>);
    case 'trans':
      return wrap({marginTop:first?0:20, textAlign:'right', fontFamily:'var(--serif)', fontSize:13.5,
        fontWeight:700, lineHeight:1.6, letterSpacing:2, color:'var(--text-secondary)'}, el.text);
    case 'sub':
      return wrap({marginTop:first?0:18, marginBottom:18, textAlign:'center', fontFamily:'var(--serif)',
        fontSize:15.5, fontWeight:700, lineHeight:1.7, color:'var(--text-secondary)'},
        <span style={{display:'inline-block', maxWidth:'22em', textAlign:'left', letterSpacing:4,
          marginRight:-4}}>{el.text}</span>);
    case 'note':
      return wrap({marginTop:first?0:12, padding:'8px 12px', borderLeft:'2px solid var(--accent-warm)',
        background:'var(--surface-dim)', borderRadius:'0 var(--r-md) var(--r-md) 0',
        fontFamily:'var(--sans)', fontSize:12.5, lineHeight:1.7, color:'var(--text-muted)'},
        <React.Fragment>
          <span style={{marginRight:8, fontWeight:600, color:'var(--accent-warm)'}}>注</span>
          {el.text}
        </React.Fragment>);
    default:
      return null;
  }
}

function SpScriptBody({proj, epId, jump, onScroll, onSceneProps}){
  const scenes = spScenesOf(proj.id, epId);
  const [element, setElement] = useState('action');
  const [caret, setCaret] = useState(null);
  const viewportRef = useRef(null);

  // 场次列表点一场 → 切到剧本分区并滚到那一场（对齐 desktop 左栏点场次的联动）。
  useEffect(()=>{
    if(!jump || !viewportRef.current) return;
    const node = viewportRef.current.querySelector(`[data-scene="${jump.id}"]`);
    if(node) node.scrollIntoView({block:'start', behavior:'smooth'});
  }, [jump]);

  // 状态栏跟着正文走 —— 正文只显示当前这一集，统计就不能拿全剧的（对齐 desktop）。
  const epPages = spFormatEighths(scenes.reduce((sum, s)=>sum + spEighths(s.pages), 0));
  const epMinutes = Math.round(scenes.reduce((sum, s)=>sum + s.minutes, 0));
  const epLines = scenes.reduce((sum, s)=>sum + s.lines, 0);

  function focusElement(el, type){ setCaret(el); setElement(type); }

  return (
    <React.Fragment>
      <div className="viewport" ref={viewportRef} onScroll={onScroll} style={{padding:'6px 20px 20px'}}>
        <div style={{display:'flex', justifyContent:'center', flexWrap:'wrap', gap:10,
          padding:'0 0 12px', fontSize:10.5, color:'var(--text-subtle)'}}>
          <span>已启用自动保存</span>
          <span><SpmPages value={epPages}/></span>
          <span>约 {epMinutes} 分钟</span>
          <span>{scenes.length} 场</span>
          <span>{epLines} 句台词</span>
        </div>

        {scenes.map((s, si)=>{
          const body = SP_SCRIPT[s.id];
          const hasAi = !!spAiChangeOf(s.id);
          return (
            <div key={s.id} data-scene={s.id}
              style={hasAi ? {borderLeft:'2px solid var(--accent)', paddingLeft:12, marginLeft:-14} : {}}>
              <SpmAiBar sceneId={s.id}/>
              {body ? body.map((el, i)=>(
                <SpmElement key={i} el={el} first={si===0 && i===0} caret={caret}
                  scene={s} onSceneProps={onSceneProps}
                  onFocus={(e)=>focusElement(e, e.t)}/>
              )) : (
                <React.Fragment>
                  <SpmElement first={si===0} caret={caret} onFocus={(e)=>focusElement(e,'scene')}
                    scene={s} onSceneProps={onSceneProps}
                    el={{t:'scene', no:s.no, place:s.place, time:s.time, ie:s.ie}}/>
                  <SpmElement caret={caret} onFocus={(e)=>focusElement(e,'cast')}
                    el={{t:'cast', names:s.cast}}/>
                  <SpmElement caret={caret} onFocus={(e)=>focusElement(e,'note')}
                    el={{t:'note', text:s.desc}}/>
                  <button type="button" className="btn-ghost press"
                    style={{height:34, padding:'0 14px', marginTop:12, fontSize:12.5}}>
                    <I.pencil s={14}/>从梗概写这一场
                  </button>
                </React.Fragment>
              )}
            </div>
          );
        })}
      </div>

      {/* 元素类型条：桌面是正文栏上方的 ⌘1-8 按钮组，移动端收成底部等宽一排。 */}
      <div style={{flex:'0 0 auto', borderTop:'1px solid var(--border-subtle)',
        background:'var(--surface-container)',
        padding:'6px 8px calc(env(safe-area-inset-bottom,0px) + 6px)'}}>
        <div style={{display:'flex', gap:2}}>
          {SPM_ELEMENTS.map((el)=>{
            const Cmp = I[el.icon];
            const on = element === el.id;
            return (
              <button key={el.id} type="button" className="press" onClick={()=>setElement(el.id)}
                style={{flex:1, minWidth:0, display:'flex', flexDirection:'column', alignItems:'center',
                  gap:3, padding:'6px 0', borderRadius:'var(--r-lg)', cursor:'pointer',
                  border:'1px solid '+(on?'var(--border-input)':'transparent'),
                  background:on?'var(--selected)':'transparent',
                  color:on?'var(--text-primary)':'var(--text-muted)'}}>
                <Cmp s={16}/>
                <span style={{fontSize:10, fontWeight:on?600:500}}>{el.label}</span>
              </button>
            );
          })}
        </div>
      </div>
    </React.Fragment>
  );
}

/* ============================ 大纲 ============================
   每集一份 markdown 文档 + 这一集的只读结构节拍（真源在节拍板，
   这里只做行不做卡片，只给「去节拍板编辑」一个出口 —— 对齐 desktop）。 */
function SpmOutlineDoc({text}){
  if(!text){
    return (
      <div style={{padding:'16px 18px 20px', fontFamily:'var(--serif)', fontSize:13.5,
        lineHeight:1.9, color:'var(--text-subtle)'}}>
        把这一集的 Logline、Synopsis、人物弧光、主题写在这里……
      </div>
    );
  }
  return (
    <div contentEditable suppressContentEditableWarning
      style={{padding:'16px 18px 20px', outline:'none'}}>
      {text.split('\n').map((line, i)=>{
        if(!line.trim()) return <div key={i} style={{height:10}}/>;
        if(line.startsWith('## ')) return <div key={i} style={{margin:i===0?'0 0 8px':'16px 0 8px',
          fontFamily:'var(--serif)', fontSize:16.5, fontWeight:700, lineHeight:1.5,
          color:'var(--text-primary)'}}>{line.slice(3)}</div>;
        if(line.startsWith('- ')) return <div key={i} style={{position:'relative', paddingLeft:12,
          fontFamily:'var(--serif)', fontSize:13.5, lineHeight:1.9, color:'var(--text-secondary)'}}>
          <span style={{position:'absolute', left:2, color:'var(--text-subtle)'}}>·</span>{line.slice(2)}</div>;
        return <div key={i} style={{fontFamily:'var(--serif)', fontSize:13.5, lineHeight:1.9,
          color:'var(--text-secondary)'}}>{line}</div>;
      })}
    </div>
  );
}

const SPM_ACT_ORDER = ['第一幕','第二幕','第三幕','第四幕','第五幕','第六幕'];

function SpOutlineBody({proj, epId, onScroll, onGotoBeat}){
  const ep = spEpisodesOf(proj.id).find((e)=>e.id===epId);
  const barBtn = (icon, label)=>{
    const Cmp = I[icon];
    return <button key={icon} type="button" className="press" title={label}
      style={{width:32, height:32, display:'flex', alignItems:'center', justifyContent:'center',
        background:'transparent', border:'none', color:'var(--text-secondary)', cursor:'pointer',
        borderRadius:'var(--r-md)'}}><Cmp s={15}/></button>;
  };

  if(!ep){
    return <div className="viewport" onScroll={onScroll}>
      <Empty icon="listNumbers" text="还没有大纲" sub="先在上方选一集，大纲按集写。"/></div>;
  }

  const beats = SP_BEATS.filter((b)=>b.proj===proj.id && b.ep===ep.id);
  const acts = SPM_ACT_ORDER.filter((a)=>beats.some((b)=>b.act===a));

  return (
    <div className="viewport" onScroll={onScroll} style={{padding:'8px 20px 24px'}}>
      <div className="card" style={{padding:0, overflow:'hidden'}}>
        <div className="row" style={{gap:2, padding:'4px 8px', borderBottom:'1px solid var(--border-subtle)',
          background:'var(--surface-dim)'}}>
          {barBtn('text','标题')}{barBtn('textB','加粗')}{barBtn('textItalic','斜体')}
          <span style={{width:1, height:16, margin:'0 6px', background:'var(--border-subtle)'}}/>
          {barBtn('list','无序列表')}{barBtn('listNumbers','有序列表')}{barBtn('quote','引用')}
          <span style={{flex:1}}/>
          <span style={{display:'inline-flex', alignItems:'center', gap:5, marginRight:4,
            fontSize:10.5, color:'var(--text-subtle)'}}><I.save s={12}/>自动保存</span>
          {barBtn('copy','复制全文')}
        </div>
        <SpmOutlineDoc text={ep.outline}/>
      </div>

      <div style={{marginTop:24}}>
        <div className="row" style={{justifyContent:'space-between', padding:'0 4px 4px'}}>
          <span className="row gap6" style={{fontSize:13, fontWeight:600, color:'var(--text-primary)'}}>
            <I.path s={14} c="var(--text-muted)"/>结构节拍
          </span>
          <span className="press" onClick={onGotoBeat}
            style={{fontSize:12, color:'var(--accent-warm)', fontWeight:600}}>去节拍板编辑</span>
        </div>
        {!beats.length && <div style={{padding:'12px 4px', fontSize:12.5, color:'var(--text-muted)'}}>还没有节拍</div>}
        {acts.map((act)=>(
          <React.Fragment key={act}>
            <div style={{marginTop:12, paddingBottom:6, paddingLeft:4, fontSize:11.5, fontWeight:600,
              color:'var(--text-muted)'}}>{act}</div>
            {beats.filter((b)=>b.act===act).map((b)=>(
              <div key={b.id} className="press" onClick={onGotoBeat}
                style={{padding:'12px 4px', borderBottom:'1px solid var(--border-subtle)'}}>
                <div className="row" style={{alignItems:'baseline', gap:8}}>
                  <span style={{flex:1, fontFamily:'var(--display)', fontSize:14, fontWeight:700,
                    lineHeight:1.4, color:'var(--text-primary)'}}>{b.title}</span>
                  <span style={{fontFamily:'var(--mono)', fontSize:10.5, color:'var(--text-subtle)'}}>
                    <SpmPages value={b.pages}/>
                  </span>
                </div>
                <div style={{marginTop:6, fontFamily:'var(--serif)', fontSize:13, lineHeight:1.7,
                  color:'var(--text-secondary)'}}>{b.desc}</div>
                {b.scenes.length>0 && (
                  <div className="row" style={{flexWrap:'wrap', gap:6, marginTop:8}}>
                    {b.scenes.map((no)=>(<SpmChip key={no} plain>第 {no} 场</SpmChip>))}
                  </div>
                )}
              </div>
            ))}
          </React.Fragment>
        ))}
      </div>
    </div>
  );
}

/* ============================ 节拍 ============================
   桌面是横排幕栏（260px 一栏横向滚），移动端收成纵向：每幕一组，
   组内节拍卡竖排。幕数由这一集实际排出来的节拍决定，不设上限。 */
function SpBeatBody({proj, epId, onScroll}){
  const beats = SP_BEATS.filter((b)=>b.proj===proj.id && (epId ? b.ep===epId : true));
  const used = new Set(beats.map((b)=>b.act));
  const acts = SPM_ACT_ORDER.filter((a)=>used.has(a));
  // 一集还没有任何节拍时，先给第一幕一个空组，让「添加节拍」有地方落。
  if(!acts.length) acts.push('第一幕');

  return (
    <div className="viewport" onScroll={onScroll} style={{padding:'8px 20px 24px'}}>
      {acts.map((act)=>{
        const list = beats.filter((b)=>b.act===act);
        return (
          <div key={act} style={{marginBottom:20}}>
            <div className="row gap6" style={{padding:'2px 4px 10px'}}>
              <I.path s={14} c="var(--text-muted)"/>
              <span style={{fontFamily:'var(--display)', fontSize:14, fontWeight:700,
                color:'var(--text-primary)'}}>{act}</span>
              <span style={{marginLeft:'auto', fontFamily:'var(--mono)', fontSize:10.5,
                color:'var(--text-subtle)'}}>{list.length}</span>
            </div>
            {list.map((b)=>(
              <div key={b.id} className="card press" style={{padding:'12px 14px', marginBottom:10}}>
                <div className="row" style={{alignItems:'baseline', gap:8}}>
                  <span style={{flex:1, fontFamily:'var(--display)', fontSize:14, fontWeight:700,
                    lineHeight:1.4, color:'var(--text-primary)'}}>{b.title}</span>
                  <span style={{fontFamily:'var(--mono)', fontSize:10.5, color:'var(--text-subtle)'}}>
                    <SpmPages value={b.pages}/>
                  </span>
                </div>
                <div style={{marginTop:8, fontFamily:'var(--serif)', fontSize:13, lineHeight:1.7,
                  color:'var(--text-secondary)'}}>{b.desc}</div>
                {b.scenes.length>0 && (
                  <div className="row" style={{flexWrap:'wrap', gap:6, marginTop:10}}>
                    {b.scenes.map((no)=>(<SpmChip key={no} plain>第 {no} 场</SpmChip>))}
                  </div>
                )}
              </div>
            ))}
            <button type="button" className="press" style={{width:'100%', height:40,
              border:'1px dashed var(--border-input)', borderRadius:'var(--r-2xl)',
              background:'transparent', color:'var(--text-muted)', fontSize:12.5, fontWeight:500,
              cursor:'pointer'}}>+ 添加节拍</button>
          </div>
        );
      })}
      <button type="button" className="press" style={{width:'100%', height:46,
        display:'flex', alignItems:'center', justifyContent:'center', gap:6,
        border:'1px dashed var(--border-input)', borderRadius:'var(--r-2xl)',
        background:'transparent', color:'var(--text-muted)', fontSize:13, fontWeight:600,
        cursor:'pointer'}}>
        <I.plus s={14}/>新增一幕
      </button>
    </div>
  );
}

/* ============================ 场次（列表） ============================
   对应 desktop SpSceneRow：场次头 + 梗概 + meta chips。
   桌面一行是「190px 场次头 | 梗概」的左右布局，390 宽摆不下，收成纵向卡片。
   点卡片 = 去剧本分区看这一场正文（desktop 是左栏点场次的联动，移动端没有双栏，
   用分区切换 + 滚动定位代替）。场次板 / 出场矩阵两个视图这一轮不做。 */
/* 情绪 badge —— 跟在场次标题后面，用 accent 色（对齐 desktop .sp-emo）。
   它跟状态徽章靠位置区分：状态永远在 meta 行，情绪永远在标题行，
   所以两者可以共用 --selected 底而不会看混。
   stale 表示正文改过、整理结果还没重跑，旧值照显示。 */
function SpmEmo({children, stale, more}){
  return <span style={{display:'inline-flex', alignItems:'center', height:19, padding:'0 6px',
    borderRadius:'var(--r-sm)', fontSize:10, fontWeight: more ? 500 : 600,
    background: stale ? 'color-mix(in srgb, var(--warning-text) 13%, transparent)' : 'var(--selected)',
    color: stale ? 'var(--warning)' : (more ? 'var(--text-subtle)' : 'var(--accent-warm)'),
    whiteSpace:'nowrap'}}>{children}</span>;
}

// 最多露两个，其余收成 +N —— 一场戏的主导情绪就那么一两个。
function SpmEmoBadges({scene, max=2}){
  const tags = scene.emotion || [];
  if(!tags.length && !scene.analysisStale) return null;
  const shown = tags.slice(0, max);
  const rest = tags.length - shown.length;
  return (
    <span className="row" style={{flex:'none', gap:4, marginLeft:6}}>
      {shown.map((t)=><SpmEmo key={t}>{t}</SpmEmo>)}
      {rest > 0 && <SpmEmo more>+{rest}</SpmEmo>}
      {scene.analysisStale && <SpmEmo stale>待核对</SpmEmo>}
    </span>
  );
}

function SpScenesBody({proj, epId, onScroll, onOpenScene, onOpenScript}){
  const scenes = spScenesOf(proj.id, epId);

  if(!scenes.length){
    return <div className="viewport" onScroll={onScroll}>
      <Empty icon="grid" text="这一集还没有场次" sub="先建一场，再补梗概和正文。"/>
    </div>;
  }

  return (
    <div className="viewport" onScroll={onScroll} style={{padding:'8px 20px 24px'}}>
      <div className="col gap10">
        {scenes.map((s)=>{
          const beat = SP_BEATS.find((b)=>b.id===s.beat);
          return (
            <div key={s.id} className="card press" onClick={()=>onOpenScene(s)}
              style={{padding:'12px 14px'}}>
              {/* 主行是事件短标题（没写就回退地点），地点·时间/内外降为次行 ——
                  一集里三场都叫「客船前舱」时，单行只有地点读不出哪场是哪场。 */}
              <div className="row gap6" style={{alignItems:'baseline'}}>
                <span style={{flex:1, minWidth:0, fontFamily:'var(--display)', fontSize:14.5,
                  fontWeight:700, color:'var(--text-primary)', fontVariantNumeric:'tabular-nums',
                  whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>
                  <span style={{color:'var(--text-subtle)', fontWeight:400}}>{s.no}、</span>{spSceneName(s)}
                </span>
                <SpmEmoBadges scene={s}/>
                <SpmAiDot sceneId={s.id}/>
                <I.chevR s={15} c="var(--text-subtle)"/>
              </div>
              <div style={{marginTop:2, fontSize:11, color:'var(--text-subtle)'}}>{spSceneCond(s)}</div>
              <div style={{marginTop:7, fontFamily:'var(--serif)', fontSize:13, lineHeight:1.7,
                color:'var(--text-secondary)', display:'-webkit-box', WebkitLineClamp:2,
                WebkitBoxOrient:'vertical', overflow:'hidden'}}>{s.desc}</div>
              <div className="row" style={{flexWrap:'wrap', gap:6, marginTop:10}}>
                <SpmState state={s.state}/>
                {beat && <SpmChip icon="path">{beat.title}</SpmChip>}
                <SpmChip icon="clock"><SpmPages value={s.pages}/></SpmChip>
                <SpmChip icon="user">{s.cast.length} 人</SpmChip>
                <span style={{flex:1}}/>
                {/* 点卡片进场次属性，读正文是另一件事 —— 两个入口分开，
                    不让最高频的「去看这一场写成什么样」多绕一层。 */}
                <button type="button" className="press"
                  onClick={(e)=>{ e.stopPropagation(); onOpenScript(s); }}
                  style={{display:'inline-flex', alignItems:'center', gap:3, height:22,
                    padding:'0 8px', border:'none', borderRadius:'var(--r-md)',
                    background:'transparent', color:'var(--text-muted)', fontSize:11,
                    fontWeight:600, cursor:'pointer'}}>
                  <I.scroll s={11}/>正文
                </button>
              </div>
            </div>
          );
        })}
        <button type="button" className="press" style={{width:'100%', height:44,
          display:'flex', alignItems:'center', justifyContent:'center', gap:6,
          border:'1px dashed var(--border-input)', borderRadius:'var(--r-2xl)',
          background:'transparent', color:'var(--text-muted)', fontSize:12.5, fontWeight:600,
          cursor:'pointer'}}>
          <I.plus s={14}/>新增场次
        </button>
      </div>
    </div>
  );
}

/* ============================ 场次详情 ============================
   阶段 M 给场次补的四个字段（短标题、目标时长、情绪、事件）加“内外”取值都在这一屏。
   真实实现不是新建的一屏 —— 移动端 scenes_page.dart 的 _SceneEditSheet 已经在做
   地点、内外景、阶段、节拍和梗概，M 是在那一屏上再扩四项，不另开第二个编辑入口。
   390 宽放不下桌面那种两列表单，改成单列纵向；事件默认折叠，只留标题。 */

function SpmField({label, hint, children}){
  return (
    <div style={{marginBottom:16}}>
      <div className="row gap6" style={{alignItems:'baseline', marginBottom:6}}>
        <span style={{fontSize:12, fontWeight:600, color:'var(--text-secondary)'}}>{label}</span>
        {hint && <span style={{fontSize:11, color:'var(--text-subtle)'}}>{hint}</span>}
      </div>
      {children}
    </div>
  );
}

const SPM_BOX = {padding:'9px 12px', border:'1px solid var(--border-input)',
  borderRadius:'var(--r-lg)', background:'var(--surface)', outline:0};

/* 有序事件。每项 title / summary / stateChange，折叠后只留 title。
   stateChange 说的是「这件事改变了什么」，为空是正常的：不是每件事都改变状态。 */
function SpmSceneEvents({scene}){
  const events = scene.events || [];
  const [open, setOpen] = useState(events.length ? 0 : null);

  if(!events.length){
    return (
      <div className="col gap8" style={{padding:12, border:'1px dashed var(--border-input)',
        borderRadius:'var(--r-lg)', fontSize:11.5, lineHeight:1.6, color:'var(--text-subtle)'}}>
        <span>{scene.state === '待写'
          ? '这一场还没有正文，事件等正文写完由故事连续性维护整理。'
          : '还没有整理过这一场的事件。'}</span>
        <button type="button" className="press" style={{alignSelf:'flex-start',
          display:'inline-flex', alignItems:'center', gap:4, height:26, padding:'0 9px',
          border:'1px solid var(--border-input)', borderRadius:'var(--r-md)',
          background:'var(--surface)', color:'var(--text-secondary)', fontSize:11.5,
          fontWeight:600, cursor:'pointer'}}>
          <I.magic s={12}/>整理这一场
        </button>
      </div>
    );
  }

  return (
    <div className="col gap6">
      {events.map((e, i)=>(
        <div key={i} style={{border:'1px solid '+(open===i?'var(--border-input)':'var(--border-subtle)'),
          borderRadius:'var(--r-lg)', background:'var(--surface-high)'}}>
          <div className="row gap6 press" onClick={()=>setOpen(open===i?null:i)}
            style={{alignItems:'center', padding:'8px 10px', cursor:'pointer'}}>
            <span style={{flex:'none', width:14, fontFamily:'var(--mono)', fontSize:10.5,
              fontWeight:600, color:'var(--text-subtle)'}}>{i+1}</span>
            <span style={{flex:1, minWidth:0, fontFamily:'var(--display)', fontSize:13.5,
              fontWeight:700, color:'var(--text-primary)', whiteSpace:'nowrap',
              overflow:'hidden', textOverflow:'ellipsis'}}>{e.title}</span>
            {e.stateChange && (
              <span style={{flex:'none', padding:'1px 5px', borderRadius:'var(--r-sm)',
                background:'var(--selected)', color:'var(--text-subtle)', fontSize:10}}>状态</span>
            )}
            <I.caretD s={11} c="var(--text-subtle)"
              style={open===i?undefined:{transform:'rotate(-90deg)'}}/>
          </div>
          {open===i && (
            <div style={{padding:'0 10px 10px 28px'}}>
              <div contentEditable suppressContentEditableWarning
                style={{outline:0, fontFamily:'var(--serif)', fontSize:13, lineHeight:1.7,
                  color:'var(--text-secondary)'}}>{e.summary}</div>
              {e.stateChange ? (
                <div className="row gap6" style={{alignItems:'flex-start', marginTop:8, paddingTop:8,
                  borderTop:'1px solid var(--border-subtle)', fontSize:12, lineHeight:1.6}}>
                  <span style={{flex:'none', fontWeight:600, color:'var(--text-subtle)'}}>状态变化</span>
                  <span contentEditable suppressContentEditableWarning
                    style={{outline:0, color:'var(--text-secondary)'}}>{e.stateChange}</span>
                </div>
              ) : (
                <button type="button" className="press" style={{marginTop:8, display:'inline-flex',
                  alignItems:'center', gap:3, padding:'2px 6px', border:'none',
                  borderRadius:'var(--r-sm)', background:'transparent', color:'var(--text-subtle)',
                  fontSize:11.5, fontWeight:600, cursor:'pointer'}}>
                  <I.plus s={10}/>记一条状态变化
                </button>
              )}
            </div>
          )}
        </div>
      ))}
      <button type="button" className="press" style={{height:32, border:'1px dashed var(--border-input)',
        borderRadius:'var(--r-pill)', background:'transparent', color:'var(--text-muted)',
        fontSize:11.5, fontWeight:600, cursor:'pointer'}}>
        <I.plus s={12}/> 新增事件
      </button>
    </div>
  );
}

function SpmSceneDetail({scene, proj, onBack, onOpenScript}){
  const target = spSecsLabel(scene.targetSecs);
  const emotion = scene.emotion || [];

  return (
    <div className="screen fade-in" data-screen-label="场次属性"
      style={{position:'absolute', inset:0, zIndex:55, background:'var(--canvas)'}}>
      <div className="appbar" style={{paddingTop:54}}>
        <div className="row" style={{justifyContent:'space-between', padding:'8px 12px', gap:6}}>
          <IconBtn icon="chevL" size={24} onClick={onBack}/>
          <div className="col" style={{alignItems:'center', flex:1, minWidth:0}}>
            <span className="display" style={{fontSize:15, fontWeight:700, color:'var(--text-primary)',
              whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis', maxWidth:'100%'}}>
              {scene.no}、{spSceneName(scene)}
            </span>
            <span style={{fontSize:11, color:'var(--text-muted)'}}>{spSceneCond(scene)}</span>
          </div>
          <IconBtn icon="dots" ariaLabel="更多"/>
        </div>
      </div>

      {/* 正文改过之后整理结果就旧了 —— 旧值保留，只标待核对，不清空也不自动重跑。 */}
      {scene.analysisStale && (
        <div className="row gap6" style={{flex:'0 0 auto', alignItems:'center', padding:'7px 20px',
          background:'color-mix(in srgb, var(--warning-text) 10%, transparent)', color:'var(--warning)', fontSize:11.5, lineHeight:1.5}}>
          <I.warn s={13}/>
          <span style={{flex:1}}>正文改过，下面的情绪与事件还是上一版的结果。</span>
          <button type="button" className="press" style={{display:'inline-flex', alignItems:'center',
            gap:3, border:'none', background:'transparent', color:'var(--warning)', fontSize:11.5,
            fontWeight:600, cursor:'pointer'}}><I.refresh s={12}/>重新整理</button>
        </div>
      )}

      <div className="viewport" style={{padding:'14px 20px 24px'}}>
        <SpmField label="事件短标题" hint="为空就显示地点，不会拿梗概去凑">
          <div contentEditable suppressContentEditableWarning
            style={{...SPM_BOX, fontFamily:'var(--display)', fontSize:15, fontWeight:700,
              color: scene.title ? 'var(--text-primary)' : 'var(--text-subtle)'}}>
            {scene.title || scene.place}
          </div>
        </SpmField>

        <div className="row gap10" style={{alignItems:'flex-start'}}>
          <div style={{flex:1}}>
            <SpmField label="地点">
              <div contentEditable suppressContentEditableWarning
                style={{...SPM_BOX, fontSize:14}}>{scene.place}</div>
            </SpmField>
          </div>
          <div style={{flex:'0 0 96px'}}>
            <SpmField label="时间">
              <div contentEditable suppressContentEditableWarning
                style={{...SPM_BOX, fontSize:14}}>{scene.time}</div>
            </SpmField>
          </div>
        </div>

        {/* 「内外」是明确选项，和「未指定」不是一回事，所以这里是四个格子。 */}
        <SpmField label="内外景">
          <div className="row gap6">
            {SP_IE_VALUES.concat(['未指定']).map((v)=>{
              const on = v === '未指定' ? !scene.ie : scene.ie === v;
              return (
                <button key={v} type="button" className="press" style={{flex: v==='未指定'?1.3:1,
                  height:34, border:'1px solid '+(on?'var(--accent)':'var(--border-input)'),
                  borderRadius:'var(--r-pill)', background:on?'var(--selected)':'var(--surface)',
                  color:on?'var(--text-primary)':(v==='未指定'?'var(--text-subtle)':'var(--text-muted)'),
                  fontSize:13, fontWeight:500, cursor:'pointer'}}>{v}</button>
              );
            })}
          </div>
        </SpmField>

        <SpmField label="本场目标时长" hint="不填就是没定">
          <div className="row gap8" style={{alignItems:'center'}}>
            <div contentEditable suppressContentEditableWarning
              style={{...SPM_BOX, width:96, fontFamily:'var(--mono)', fontSize:14,
                fontVariantNumeric:'tabular-nums',
                color: scene.targetSecs != null ? 'var(--text-primary)' : 'var(--text-subtle)'}}>
              {scene.targetSecs != null ? scene.targetSecs : ''}
            </div>
            <span style={{fontSize:12.5, color:'var(--text-muted)'}}>秒</span>
          </div>
          {/* 两种时长并排，看得出它们互不覆盖：目标是意图，估算来自正文排版算法。
              哪个空就是哪个没有（§5.1）。 */}
          <div className="row" style={{flexWrap:'wrap', gap:12, marginTop:7, fontSize:11,
            color:'var(--text-subtle)', fontVariantNumeric:'tabular-nums'}}>
            <span>目标 {target || '—'}</span>
            <span>估算 约 {scene.minutes} 分钟</span>
          </div>
        </SpmField>

        <SpmField label="梗概" hint="这一场要做什么，和事件不是一回事">
          <div contentEditable suppressContentEditableWarning
            style={{...SPM_BOX, minHeight:76, fontFamily:'var(--serif)', fontSize:14,
              lineHeight:1.8, color:'var(--text-primary)'}}>{scene.desc}</div>
        </SpmField>

        <SpmField label="情绪" hint="从正文整理，作者可改">
          <div className="row" style={{flexWrap:'wrap', gap:6}}>
            {emotion.map((t)=>(
              <span key={t} className="row" style={{alignItems:'center', gap:3, height:26,
                padding:'0 7px 0 10px', border:'1px solid var(--border-input)',
                borderRadius:'var(--r-md)', background:'var(--surface)',
                fontSize:12, fontWeight:500, color:'var(--text-secondary)'}}>
                {t}<I.x s={10} c="var(--text-subtle)"/>
              </span>
            ))}
            <button type="button" className="press" style={{display:'inline-flex', alignItems:'center',
              gap:3, height:26, padding:'0 10px', border:'1px dashed var(--border-input)',
              borderRadius:'var(--r-md)', background:'transparent', color:'var(--text-subtle)',
              fontSize:12, fontWeight:500, cursor:'pointer'}}>
              <I.plus s={11}/>{emotion.length ? '加一个' : '添加情绪'}
            </button>
          </div>
        </SpmField>

        <SpmField label="事件" hint="按发生顺序">
          <SpmSceneEvents scene={scene}/>
        </SpmField>

        <div className="col gap8" style={{marginTop:4}}>
          <button type="button" className="press" onClick={()=>onOpenScript(scene)}
            style={{width:'100%', height:40, display:'flex', alignItems:'center',
              justifyContent:'center', gap:6, border:'1px solid var(--border)',
              borderRadius:'var(--r-pill)', background:'var(--surface)',
              color:'var(--text-secondary)', fontSize:12.5, fontWeight:600, cursor:'pointer'}}>
            <I.pencil s={14}/>编辑正文
          </button>
        </div>
      </div>

      <div style={{flex:'0 0 auto', display:'flex', alignItems:'center', gap:10,
        padding:'8px 20px calc(env(safe-area-inset-bottom,0px) + 8px)',
        borderTop:'1px solid var(--border-subtle)', background:'var(--surface-container)',
        fontSize:11, color:'var(--text-muted)'}}>
        <span>已启用自动保存</span>
        <span style={{flex:1}}/>
        <button type="button" className="press" style={{display:'inline-flex', alignItems:'center',
          gap:4, height:28, padding:'0 10px', border:'1px solid var(--border-input)',
          borderRadius:'var(--r-md)', background:'var(--surface)', color:'var(--text-secondary)',
          fontSize:11.5, fontWeight:600, cursor:'pointer'}}><I.undo s={12}/>撤回本场修改</button>
      </div>
    </div>
  );
}

/* ============================ 剧本工作台外壳 ============================ */
/* 沿用小说移动端的「概览 → 正文 → 人物 → 设定 → 大纲 → 素材 → 关系图」顺序。
   正文换成剧本，伏笔换成节拍 / 场次；图鉴同小说拆成物品 / 势力 / 生物。
   桌面系统工具、AI 与灵感入口不铺进移动端顶部 tab。 */
const SP_WORKSPACE_TABS = [
  {k:'overview',   label:'概览'},
  {k:'script',     label:'剧本'},
  {k:'characters', label:'人物'},
  {k:'world',      label:'设定'},
  {k:'outline',    label:'大纲'},
  {k:'beat',       label:'节拍'},
  {k:'scenes',     label:'场次'},
  {k:'items',      label:'物品'},
  {k:'factions',   label:'势力'},
  {k:'creatures',  label:'生物'},
  {k:'skills',     label:'技能'},
  {k:'map',        label:'地图'},
  {k:'materials',  label:'素材'},
  {k:'relations',  label:'关系图谱'},
  {k:'progress',   label:'当前进度'},
];

/* 剧情分区带季/集上下文（标题栏副标题可切换）；其余分区（含桌面也还没做的
   那几屏）没有集上下文，先空态。 */
const SP_PLOT_SECTIONS = ['script','outline','beat','scenes'];

function SpWorkspaceScreen({proj, onBack}){
  const seasons = spSeasonsOf(proj.id);
  const multi = seasons.length > 1;
  // 当前季是本机工作区状态不是业务字段（desktop SP_CURRENT_SEASON 的同一语义）。
  const [seasonId, setSeasonId] = useState(SP_CURRENT_SEASON[proj.id] || (seasons[0]||{}).id);
  // 默认落在「写作中」的那一集，没有就第一集 —— 进来就是接着写的地方。
  const firstEpOf = (sid)=>{
    const eps = spEpisodesOf(proj.id, sid);
    return (eps.find((e)=>e.state==='写作中') || eps[0] || {}).id || null;
  };
  const [epId, setEpId] = useState(()=>firstEpOf(seasonId));
  const [section, setSection] = useState('overview');
  const [jump, setJump] = useState(null);   // {id, ts} 场次列表 → 剧本分区的滚动定位
  const [switcher, setSwitcher] = useState(false);  // 标题栏季/集切换 sheet
  // 管理季是切换层的下一站，不是叠在它上面的第二层 —— 开管理就先关切换。
  const [seasonMgr, setSeasonMgr] = useState(false);
  // 场次属性页。场次列表和正文场次标题两处都推这一个，不各写一份。
  const [propScene, setPropScene] = useState(null);
  const [scrolled, setScrolled] = useState(false);
  const onScroll = (e)=> setScrolled(e.target.scrollTop > 4);

  const select = (k)=>{ setSection(k); setScrolled(false); };
  const pickEpisode = (sid, eid)=>{ setSeasonId(sid); setEpId(eid); setSwitcher(false); };
  // 切季之后要写的是那一季的第一集，所以换季连着换集，管理层一起收起。
  const enterSeason = (sid)=>{ setSeasonId(sid); setEpId(firstEpOf(sid)); setSeasonMgr(false); };
  // 概览点一集 → 带着那一集进剧本分区，回到「接着写」的地方。
  const openEpisode = (e)=>{ setSeasonId(e.season); setEpId(e.id); select('script'); };
  const openScript = (s)=>{ setPropScene(null); setJump({id:s.id, ts:Date.now()}); setSection('script'); };

  const isPlot = SP_PLOT_SECTIONS.includes(section);
  const tab = SP_WORKSPACE_TABS.find((t)=>t.k===section) || SP_WORKSPACE_TABS[0];
  const curEp = spEpisodesOf(proj.id, seasonId).find((e)=>e.id===epId) || null;
  const subtitle = section==='overview'
    ? [proj.kind==='series'?'剧集':'电影', proj.genre].join(' · ')
    : tab.label;

  const body = (()=>{
    const ctx = {proj, epId, onScroll};
    switch(section){
      case 'overview': return <SpOverviewBody proj={proj} seasonId={seasonId} epId={epId}
        onScroll={onScroll} onOpenEpisode={openEpisode} onGoto={select}/>;
      case 'script':  return <SpScriptBody {...ctx} jump={jump} onSceneProps={setPropScene}/>;
      case 'outline': return <SpOutlineBody {...ctx} onGotoBeat={()=>select('beat')}/>;
      case 'beat':    return <SpBeatBody {...ctx}/>;
      case 'scenes':  return <SpScenesBody {...ctx} onOpenScene={setPropScene} onOpenScript={openScript}/>;
      default:
        return (
          <div className="viewport" onScroll={onScroll}>
            <Empty icon="scroll" text={`「${tab.label}」还没设计`}
              sub="本轮 mockup 覆盖书架「剧本」tab、概览（季/集）与剧本/大纲/节拍/场次四个分区，其余分区后续轮次补齐。"/>
          </div>
        );
    }
  })();

  return (
    <div className="screen fade-in" data-screen-label="screenplay-workspace">
      <div className={"appbar"+(scrolled?' scrolled':'')} style={{paddingTop:54}}>
        <div className="row" style={{justifyContent:'space-between', padding:'8px 12px 8px', gap:6}}>
          <IconBtn icon="chevL" size={24} onClick={onBack}/>
          <div className="col" style={{alignItems:'center', flex:1, minWidth:0}}>
            <span className="display" style={{fontSize:15.5, fontWeight:700, color:'var(--text-primary)',
              whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis', maxWidth:'100%'}}>{proj.title}</span>
            {isPlot && curEp ? (
              /* 季/集胶囊：作品名的副标题，点开 bottom sheet 切换。 */
              <button type="button" className="press" onClick={()=>setSwitcher(true)}
                style={{display:'inline-flex', alignItems:'center', gap:3, maxWidth:'100%',
                  marginTop:1, padding:'1px 6px', border:'none', borderRadius:'var(--r-md)',
                  background:'transparent', cursor:'pointer',
                  fontSize:11, color:'var(--text-muted)'}}>
                <span style={{overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap'}}>
                  {multi && `${spSeasonLabel(spSeasonById(seasonId))} · `}{curEp.label} · {curEp.title}
                </span>
                <I.caretD s={10}/>
              </button>
            ) : (
              <span style={{fontSize:11, color:'var(--text-muted)'}}>{subtitle}</span>
            )}
          </div>
          <IconBtn icon="dots" ariaLabel="更多"/>
        </div>
        <WorkspaceTabs section={section} onSelect={select} tabs={SP_WORKSPACE_TABS}/>
      </div>
      {body}
      {switcher && curEp && (
        <SpEpSwitcher proj={proj} seasonId={seasonId} epId={epId}
          onPick={pickEpisode} onClose={()=>setSwitcher(false)}
          onManage={()=>{ setSwitcher(false); setSeasonMgr(true); }}/>
      )}
      {seasonMgr && (
        <SpmSeasonManageSheet proj={proj} seasonId={seasonId}
          onEnterSeason={enterSeason} onClose={()=>setSeasonMgr(false)}/>
      )}
      {/* 场次属性 —— 短标题、目标时长、内外、情绪、事件都在这里改（§4.1）。 */}
      {propScene && (
        <SpmSceneDetail scene={propScene} proj={proj}
          onBack={()=>setPropScene(null)}
          onOpenScript={openScript}/>
      )}
    </div>
  );
}

Object.assign(window, { SP_MOBILE, SP_WORKSPACE_TABS, SpWorkspaceScreen,
  spScenesOf, spEpisodesOf, spCharsOf });
