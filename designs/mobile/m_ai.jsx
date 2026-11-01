/* ============================================================
   AI tab
   桌面端的聊天 / 智能体任务轨迹（AgentPanel）/ AI 模式（圆桌会议·独白·
   小剧场·角色扮演）/ 智能体·技能·提示词·快捷方式管理 全部收进此 tab。
   ============================================================ */

// `efforts` = 模型配置的 reasoning effort 级别，按 low→high 排列；
// 缺省表示非推理模型，不展示推理强度。
const MODEL_OPTIONS = [
  {name:'mimo-v2.5 · 默认', provider:'自定义供应商', icon:'spark', efforts:['low','medium','high'], defaultEffort:'medium'},
  {name:'Claude Opus 4.8', provider:'Anthropic', icon:'diamond', efforts:['low','medium','high','xhigh','max'], defaultEffort:'high'},
  {name:'DeepSeek-V3', provider:'DeepSeek', icon:'brain'},
  {name:'GPT-4o', provider:'OpenAI', icon:'robot'},
];

// effort wire 值 -> 中文标签 + 一行说明。已知值：none/low/medium/high/xhigh/max。
const EFFORT_LABELS = {none:'关闭', low:'低', medium:'中', high:'高', xhigh:'极高', max:'最高'};
const EFFORT_HINTS = {
  none:'不推理，直接作答',
  low:'更快、更省 token',
  medium:'速度与深度均衡',
  high:'更深入的推理',
  xhigh:'深度推理，较慢',
  max:'最强推理，最慢',
};

// 推理强度小竖条：填充到 level（含）为 accent，其余为浅色。
function EffortBars({total, level}){
  return (
    <span style={{display:'inline-flex', alignItems:'flex-end', gap:2, height:13}}>
      {Array.from({length:total}).map((_,i)=>(
        <span key={i} style={{width:3, height:4+i*2.4, borderRadius:1,
          background: i<=level ? 'var(--accent)' : 'var(--border-input)'}}/>
      ))}
    </span>
  );
}

/* ---------- model select (inline dropdown) ---------- */
function ModelSelect({value}){
  const [open, setOpen] = useState(false);
  const [sel, setSel] = useState(MODEL_OPTIONS.find(m=>m.name===value) || (value?{name:value}:MODEL_OPTIONS[0]));
  return (
    <div style={{position:'relative'}}>
      <div className="press" onClick={()=>setOpen(o=>!o)} style={{display:'flex', alignItems:'center', gap:9, height:44, padding:'0 13px',
        border:'1px solid '+(open?'var(--accent)':'var(--border-input)'), borderRadius:'var(--r-lg)', background:'var(--surface-high)'}}>
        <I.brain s={17} c="var(--accent)"/>
        <span style={{flex:1, fontSize:14, color:'var(--text-primary)'}}>{sel?sel.name:'未选择模型'}</span>
        <I.caretD s={15} c="var(--text-subtle)" style={{transform:open?'rotate(180deg)':'none', transition:'transform .15s'}}/>
      </div>
      {open && (
        <div className="pop-in" style={{position:'absolute', left:0, right:0, top:50, zIndex:30, padding:5, background:'var(--surface)', border:'1px solid var(--border)', borderRadius:'var(--r-lg)', boxShadow:'var(--shadow-float)'}}>
          {MODEL_OPTIONS.map(m=>{
            const Cmp = I[m.icon]||I.robot; const on = sel&&sel.name===m.name;
            return (
              <div key={m.name} className="press" onClick={()=>{setSel(m); setOpen(false);}} style={{display:'flex', alignItems:'center', gap:10, padding:'9px', borderRadius:'var(--r-md)', background:on?'var(--selected)':'transparent'}}>
                <span style={{width:30,height:30,borderRadius:'var(--r-md)',flex:'0 0 auto',background:'color-mix(in srgb, var(--accent) 13%, transparent)',color:'var(--accent)',display:'flex',alignItems:'center',justifyContent:'center'}}><Cmp s={16}/></span>
                <div className="col" style={{flex:1, gap:1}}>
                  <span style={{fontSize:13, fontWeight:600}}>{m.name}</span>
                  <span style={{fontSize:11, color:'var(--text-muted)'}}>{m.provider}</span>
                </div>
                {on && <I.checkCircle s={16} c="var(--accent)"/>}
              </div>
            );
          })}
          <div style={{borderTop:'1px solid var(--border-subtle)', marginTop:4, paddingTop:4}}>
            <div className="press" style={{padding:'8px 9px', fontSize:13, color:'var(--accent-warm)', fontWeight:600}}>添加模型…</div>
          </div>
        </div>
      )}
    </div>
  );
}

/* ============================================================
   以下子组件对齐真实 Flutter 实现：
   - 头像/气泡/消息轨道 → lib/shared/widgets/ai/chat/chat_message_view.dart
   - 思考卡/工具卡       → chat_message_parts.dart / tool_call_card.dart
   - 输入条              → lib/mobile/widgets/chat_composer.dart
   - 各模式气泡          → lib/mobile/pages/{council,monologue,theater,roleplay}_page_widgets.dart
   ============================================================ */

/* ---------- 头像（AI 主笔 / 用户）对齐 ChatMessageView ---------- */
function AiAvatar(){
  return <div style={{width:32,height:32,borderRadius:'50%',flex:'0 0 auto',background:'var(--surface-container)',
    border:'1px solid var(--border-subtle)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--accent)'}}><I.spark s={16}/></div>;
}
function UserAvatar(){
  return <div style={{width:32,height:32,borderRadius:'50%',flex:'0 0 auto',background:'var(--surface-container)',
    border:'1px solid var(--border-subtle)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--text-muted)'}}><I.user s={17}/></div>;
}

/* ---------- 用户消息：右对齐气泡(surfaceDim)+ 引用 chip + 右侧头像 ---------- */
function UserBubble({text, refs}){
  return (
    <div className="row" style={{justifyContent:'flex-end', alignItems:'flex-start', gap:10}}>
      <div className="col" style={{alignItems:'flex-end', gap:6, maxWidth:'78%'}}>
        <div style={{background:'var(--surface-dim)', borderRadius:'var(--r-2xl)', padding:'10px 16px'}}>
          <div className="col" style={{gap:8, alignItems:'flex-end'}}>
            {refs && refs.length>0 && (
              <div className="row" style={{flexWrap:'wrap', gap:6, justifyContent:'flex-end'}}>
                {refs.map((r,i)=>(
                  <span key={i} className="chip" style={{height:24,fontSize:11,padding:'0 9px',background:'var(--surface)',border:'1px solid var(--border)',color:'var(--text-secondary)'}}><I.link s={12}/>{r}</span>
                ))}
              </div>
            )}
            {text && <span style={{fontSize:14.5, color:'var(--text-primary)', lineHeight:1.55}}>{text}</span>}
          </div>
        </div>
        {/* 用户消息操作（对齐桌面端 ChatBubble）：复制 / 删除 / 回退 */}
        <div className="row" style={{gap:2}}>
          <span className="press" style={{padding:4, color:'var(--text-muted)'}}><I.copy s={15}/></span>
          <span className="press" aria-label="删除消息" style={{padding:4, color:'var(--text-muted)'}}><I.trash s={15}/></span>
          <span className="press" aria-label="回退到本轮对话发起前" style={{padding:4, color:'var(--text-muted)'}}><I.undo s={15}/></span>
        </div>
      </div>
      <UserAvatar/>
    </div>
  );
}

/* ---------- AI 消息轨道：左头像 + 内容列 ---------- */
function AiTrack({children}){
  return (
    <div className="row" style={{alignItems:'flex-start', gap:10}}>
      <AiAvatar/>
      <div className="col" style={{flex:1, minWidth:0, gap:8, maxWidth:'calc(100% - 42px)'}}>{children}</div>
    </div>
  );
}

/* ---------- 思考卡（可折叠「推理过程」）对齐 ThinkingBlockCard ---------- */
function ThinkingCard({content}){
  const [open, setOpen] = useState(false);
  return (
    <div style={{background:'var(--surface)', border:'1px solid var(--card-border)', borderRadius:'var(--r-xl)', boxShadow:'var(--shadow-card)'}}>
      <button className="press" onClick={()=>setOpen(o=>!o)} style={{width:'100%', display:'flex', alignItems:'center', gap:8, padding:'10px 14px', background:'transparent', border:'none', cursor:'pointer'}}>
        <I.brain s={16} c="var(--text-muted)"/>
        <span style={{flex:1, textAlign:'left', fontSize:12.5, color:'var(--text-muted)'}}>推理过程</span>
        <I.caretD s={16} c="var(--text-muted)" style={{transform:open?'rotate(180deg)':'none', transition:'transform .18s'}}/>
      </button>
      {open && <div style={{padding:'0 14px 12px', fontSize:12.5, color:'var(--text-muted)', lineHeight:1.6}}>{content}</div>}
    </div>
  );
}

/* ---------- AI 文本气泡（surface + border）对齐 CollapsibleTextBlock ---------- */
function TextBubble({children}){
  return (
    <div style={{background:'var(--surface)', border:'1px solid var(--card-border)', borderRadius:'var(--r-xl)', boxShadow:'var(--shadow-card)', padding:14, fontSize:14.5, color:'var(--text-primary)', lineHeight:1.6}}>{children}</div>
  );
}

/* ============================================================
   工具活动时间线（移动端优化）
   桌面端把每个工具调用渲染成一张完整边框卡（AiToolCardFrame），一轮多调用
   就堆成「卡片墙」。移动端窄列下改为：把一轮调用压成紧凑的步骤时间线，
   状态用圆点小图标承载（去掉重复的文字徽章），diff / 读取内容 / 命中列表
   等重内容收进底部 Sheet（复用 app 现成的 Sheet）。
   对齐真实实现：lib/shared/widgets/ai/tool_call_card.dart
                 lib/shared/widgets/ai/tools/tool_card_common.dart
   ============================================================ */

/* ---------- 步骤状态圆点（对齐 _statusIcon 的语义色）---------- */
function ToolStepDot({status='success'}){
  const map = {
    success: {bg:'color-mix(in srgb, var(--success) 14%, transparent)',  c:'var(--success)', icon:'check'},
    running: {bg:'color-mix(in srgb, var(--accent) 16%, transparent)', c:'var(--accent)',  icon:null},
    error:   {bg:'color-mix(in srgb, var(--error) 12%, transparent)',  c:'var(--error)',   icon:'warn'},
    pending: {bg:'var(--surface-dim)',    c:'var(--text-muted)', icon:'clock'},
  };
  const s = map[status] || map.success;
  return (
    <span style={{width:18,height:18,borderRadius:'50%',flex:'0 0 auto',background:s.bg,color:s.c,
      display:'flex',alignItems:'center',justifyContent:'center',position:'relative',zIndex:1}}>
      {status==='running'
        ? <span className="tspin" style={{width:11,height:11,borderRadius:'50%',border:'1.6px solid '+s.c,borderTopColor:'transparent'}}></span>
        : React.createElement(I[s.icon]||I.check,{s:11})}
    </span>
  );
}

/* ---------- 工具活动组：把 thinking + 多轮工具调用串成可折叠步骤时间线 ----------
   thinking 与 Read/Edit 等同属一个活动组；仅当 LLM 返回 text 才在外层切组。
   连续多个 LLM 响应（中间无 text 等特殊 block）也并入同一活动组，可跨多轮。 */
function ToolActivity({steps, onOpenDetail, defaultOpen=true}){
  const [open, setOpen] = useState(defaultOpen);
  const running = steps.some(s=>s.status==='running');
  const labelOf = (s)=> s.kind==='thinking' ? (s.status==='running'?'思考中':'推理过程') : s.verb;
  return (
    <div style={{background:'var(--surface)', border:'1px solid var(--card-border)', borderRadius:'var(--r-xl)', boxShadow:'var(--shadow-card)', overflow:'hidden'}}>
      <button className="press" onClick={()=>setOpen(o=>!o)} style={{width:'100%', display:'flex', alignItems:'center', gap:8, padding:'9px 12px', background:'transparent', border:'none', cursor:'pointer'}}>
        <I.magic s={15} c="var(--accent)"/>
        <span style={{flex:1, textAlign:'left', fontSize:12.5, fontWeight:600, color:'var(--text-secondary)'}}>执行过程</span>
        <span className="chip" style={{height:18,fontSize:10,padding:'0 7px',background:running?'color-mix(in srgb, var(--accent) 14%, transparent)':'var(--surface-dim)',color:running?'var(--accent-warm)':'var(--text-muted)',fontWeight:600}}>{running?'运行中':steps.length+' 步'}</span>
        <I.caretD s={15} c="var(--text-muted)" style={{transform:open?'rotate(180deg)':'none', transition:'transform .18s', flex:'0 0 auto'}}/>
      </button>
      {open ? (
        <div style={{padding:'0 12px 8px'}}>
          <div style={{position:'relative'}}>
            {steps.length>1 && <div style={{position:'absolute', left:8.25, top:17, bottom:17, width:1.5, background:'var(--border-subtle)'}}></div>}
            {steps.map((st,i)=>{
              const isThinking = st.kind==='thinking';
              const expandable = !!st.detail;
              return (
                <div key={i} className={expandable?'press':''} onClick={()=>expandable&&onOpenDetail(st)}
                  style={{display:'flex', alignItems:'center', gap:10, padding:'7px 0', minHeight:34, cursor:expandable?'pointer':'default'}}>
                  <ToolStepDot status={st.status}/>
                  {isThinking && <I.brain s={13} c="var(--text-muted)" style={{flex:'0 0 auto'}}/>}
                  <span style={{fontSize:13, fontWeight:600, color:isThinking?'var(--text-secondary)':'var(--text-primary)', flex:'0 0 auto'}}>{labelOf(st)}</span>
                  {!isThinking && <span style={{flex:1, minWidth:0, fontSize:12.5, color:'var(--text-muted)', fontFamily:st.mono?'var(--mono)':'var(--sans)', whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{st.target}</span>}
                  {expandable && <I.chevR s={15} c="var(--text-subtle)" style={{flex:'0 0 auto'}}/>}
                </div>
              );
            })}
          </div>
        </div>
      ) : (
        <div style={{padding:'0 12px 10px'}}>
          <span style={{display:'block', fontSize:12, color:'var(--text-muted)', whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{steps.map(labelOf).join(' · ')}</span>
        </div>
      )}
    </div>
  );
}

/* ---------- 工具详情底部 Sheet：diff / 读取片段 / 命中列表 ---------- */
function ToolDiffDetail({old, now}){
  return (
    <div className="col" style={{gap:10}}>
      <div style={{background:'color-mix(in srgb, var(--error) 6%, transparent)', borderRadius:'var(--r-lg)', padding:'10px 12px'}}>
        <div style={{fontSize:10.5, fontWeight:700, color:'var(--error)', letterSpacing:.4, marginBottom:5}}>原文</div>
        <div className="serif" style={{fontSize:14, color:'var(--text-muted)', lineHeight:1.8, textDecoration:'line-through', textDecorationColor:'color-mix(in srgb, var(--error) 40%, transparent)'}}>{old}</div>
      </div>
      <div style={{background:'color-mix(in srgb, var(--success) 7%, transparent)', borderRadius:'var(--r-lg)', padding:'10px 12px'}}>
        <div style={{fontSize:10.5, fontWeight:700, color:'var(--success)', letterSpacing:.4, marginBottom:5}}>改为</div>
        <div className="serif" style={{fontSize:14, color:'var(--text-primary)', lineHeight:1.8}}>{now}</div>
      </div>
    </div>
  );
}
function ToolTextDetail({label, text, mono}){
  return (
    <div style={{background:'var(--surface-dim)', borderRadius:'var(--r-lg)', padding:'10px 12px'}}>
      <div style={{fontSize:10.5, fontWeight:600, color:'var(--text-muted)', letterSpacing:.3, marginBottom:5}}>{label}</div>
      <div style={{fontSize:13, color:'var(--text-primary)', lineHeight:1.7, fontFamily:mono?'var(--mono)':'var(--sans)', whiteSpace:'pre-wrap'}}>{text}</div>
    </div>
  );
}
function ToolPathsDetail({label, items}){
  return (
    <div style={{background:'var(--surface-dim)', borderRadius:'var(--r-lg)', padding:'10px 12px'}}>
      <div style={{fontSize:10.5, fontWeight:600, color:'var(--text-muted)', letterSpacing:.3, marginBottom:7}}>{label}</div>
      <div className="col" style={{gap:6}}>
        {items.map((p,i)=>(
          <div key={i} className="row gap8">
            <I.file s={13} c="var(--text-subtle)" style={{flex:'0 0 auto'}}/>
            <span style={{flex:1, minWidth:0, fontSize:12.5, color:'var(--text-secondary)', fontFamily:'var(--mono)', whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{p}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
function ToolDetailSheet({step, onClose}){
  const Cmp = I[step.icon]||I.file;
  const d = step.detail;
  return (
    <Sheet onClose={onClose} max="80%">
      <SheetHeader
        iconBox={<div style={{width:34,height:34,borderRadius:'var(--r-md)',flex:'0 0 auto',background:'var(--surface-dim)',color:'var(--text-secondary)',display:'flex',alignItems:'center',justifyContent:'center'}}><Cmp s={17}/></div>}
        title={step.verb} sub={step.target}
        right={<span className="chip" style={{height:20,fontSize:10,padding:'0 8px',color:'var(--success)',background:'color-mix(in srgb, var(--success) 12%, transparent)',fontWeight:600,flex:'0 0 auto'}}>已完成</span>}/>
      <div style={{overflowY:'auto', padding:'14px 18px calc(env(safe-area-inset-bottom,0px) + 26px)'}}>
        {d.type==='diff'    && <ToolDiffDetail old={d.old} now={d.now}/>}
        {d.type==='preview' && <ToolTextDetail label={d.label} text={d.text} mono={d.mono}/>}
        {d.type==='paths'   && <ToolPathsDetail label={d.label} items={d.items}/>}
      </div>
    </Sheet>
  );
}

/* ---------- 消息操作栏（对齐桌面端 ChatBubble 的 m-bubble__actions：反馈 / 分叉） ---------- */
function MsgActions(){
  return (
    <div className="row" style={{gap:4, marginTop:2}}>
      <span className="press" style={{padding:4, color:'var(--text-muted)'}} aria-label="反馈"><I.warn s={15}/></span>
      <span className="press" style={{padding:4, color:'var(--text-muted)'}} aria-label="分叉会话"><I.path s={15}/></span>
    </div>
  );
}

/* ---------- AskUser 内联卡（对齐 AskUserCard）— 问题 + 单选项 + 补充输入 ---------- */
function AskUserInline({question, options, hint}){
  const [picked, setPicked] = useState(null);
  const [extra, setExtra] = useState('');
  return (
    <div style={{background:'var(--surface)', border:'1px solid var(--card-border)', borderRadius:'var(--r-xl)', boxShadow:'var(--shadow-card)', padding:'12px 13px'}}>
      <div className="row gap8" style={{marginBottom:8}}>
        <I.info s={15} c="var(--accent-warm)"/>
        <span style={{fontSize:12.5, fontWeight:600, color:'var(--text-primary)'}}>需要你确认</span>
      </div>
      <div style={{fontSize:13, color:'var(--text-secondary)', lineHeight:1.5, marginBottom:9}}>{question}</div>
      <div className="col" style={{gap:7, marginBottom:9}}>
        {options.map((o,i)=>{
          const on = picked===i;
          return (
            <div key={i} className="press" onClick={()=>setPicked(i)}
              style={{display:'flex', alignItems:'center', gap:9, padding:'9px 11px', borderRadius:'var(--r-md)',
                border:'1px solid '+(on?'var(--accent)':'var(--border-subtle)'), background:on?'color-mix(in srgb, var(--accent) 8%, transparent)':'var(--surface)'}}>
              <span style={{width:15, height:15, borderRadius:'50%', flex:'0 0 auto', border:'1.5px solid '+(on?'var(--accent)':'var(--border-input)'),
                background:on?'radial-gradient(circle, var(--accent) 0 4px, transparent 5px)':'var(--surface)'}}/>
              <span style={{flex:1, fontSize:13, color:'var(--text-primary)'}}>{o}</span>
            </div>
          );
        })}
      </div>
      <input value={extra} onChange={e=>setExtra(e.target.value)} placeholder={hint}
        style={{width:'100%', boxSizing:'border-box', padding:'9px 11px', marginBottom:9, border:'1px solid var(--border-input)', borderRadius:'var(--r-md)', background:'var(--surface-dim)', fontSize:13, color:'var(--text-primary)'}}/>
      <div className="row" style={{justifyContent:'flex-end', gap:8}}>
        <button className="btn-ghost press" style={{height:34, padding:'0 14px', fontSize:13}}>取消</button>
        <button className="press" style={{height:34, padding:'0 16px', borderRadius:'var(--r-pill)', background:'var(--accent)', color:'var(--on-accent)', border:'none', fontSize:13, fontWeight:600, opacity:(picked===null?0.5:1)}}>确认</button>
      </div>
    </div>
  );
}

/* ---------- 折叠待办面板（对齐桌面端 TopTodoPanel：状态图标 + 优先级点 + 内容） ---------- */
const TODO_PRIO = {high:'var(--error)', medium:'var(--accent-warm)', low:'var(--text-muted)'};
const CHAT_TODOS = [
  {t:'读取第三章并定位首段', done:true, priority:'medium'},
  {t:'拆分首段，把木匣线索后置', done:true, priority:'high'},
  {t:'委派「人物声音」校验对白', done:true, priority:'high'},
  {t:'确认木匣伏笔的回收时机', done:false, priority:'medium'},
  {t:'统一卷一雨势描写用词', done:false, priority:'low'},
];
function TodoBar(){
  const [open, setOpen] = useState(false);
  const done = CHAT_TODOS.filter(t=>t.done).length;
  const pending = CHAT_TODOS.filter(t=>!t.done).length;
  const allDone = pending===0;
  return (
    <div style={{margin:'0 16px 14px', background:'var(--surface)', border:'1px solid var(--card-border)', borderRadius:'var(--r-xl)', boxShadow:'var(--shadow-card)', overflow:'hidden'}}>
      <button className="press" onClick={()=>setOpen(o=>!o)} style={{width:'100%', display:'flex', alignItems:'center', gap:8, padding:'10px 14px', background:'transparent', border:'none', cursor:'pointer'}}>
        <I.checks s={16} c={allDone?'var(--success)':'var(--text-muted)'}/>
        <span style={{flex:1, textAlign:'left', fontSize:12.5, fontWeight:600, color:'var(--text-secondary)'}}>任务列表</span>
        <span className="chip" style={{height:18,fontSize:10,padding:'0 7px',background:allDone?'color-mix(in srgb, var(--success) 12%, transparent)':'color-mix(in srgb, var(--accent) 14%, transparent)',color:allDone?'var(--success)':'var(--accent)',fontWeight:600}}>{done}/{CHAT_TODOS.length}</span>
        <I.caretD s={15} c="var(--text-muted)" style={{transform:open?'rotate(180deg)':'none', transition:'transform .18s'}}/>
      </button>
      {open && (
        <div style={{padding:'0 14px 10px'}}>
          {CHAT_TODOS.map((t,i)=>(
            <div key={i} className="row gap8" style={{padding:'4px 0'}}>
              {t.done
                ? <span style={{width:16,height:16,borderRadius:'var(--r-sm)',flex:'0 0 auto',background:'color-mix(in srgb, var(--success) 13%, transparent)',color:'var(--success)',display:'flex',alignItems:'center',justifyContent:'center'}}><I.check s={11}/></span>
                : <span style={{width:16,height:16,borderRadius:'50%',flex:'0 0 auto',border:'1.5px solid var(--border)',display:'flex',alignItems:'center',justifyContent:'center'}}/>}
              <span style={{width:6,height:6,borderRadius:'50%',flex:'0 0 auto',background:TODO_PRIO[t.priority]||TODO_PRIO.medium,marginTop:5}}></span>
              <span style={{fontSize:12.5, color:t.done?'var(--text-muted)':'var(--text-primary)', textDecoration:t.done?'line-through':'none'}}>{t.t}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/* ---------- 最近变更日志（替代原"待确认卡"）----------
   默认接受后 AI 改动已自动应用，输入条上方不再是"接受吗"的决策门，而是收成
   一条窄屏友好的 bar：「AI 改了 N 处 · 已自动应用 · 查看」。点「查看」开全屏
   review sheet，逐条/全部回退。去掉行数 +X -Y，改用改动类型标签（新增/改写/
   扩写/删减）。对齐方案 docs/solutions/chat-changes-rework.md（决策一/二 + PR-7）。 */
const CHANGE_TYPE = {
  create:  {label:'新增', color:'var(--accent-warm)'},
  rewrite: {label:'改写', color:'var(--accent)'},
  expand:  {label:'扩写', color:'var(--success)'},
  trim:    {label:'删减', color:'var(--error)'},
};
const RECENT_CHANGES = [
  {title:'第 03 章 · 三舱客', sub:'正文', change:'rewrite'},
  {title:'凤瑶', sub:'简介', change:'create'},
];

function ChangeTypeTag({change}){
  const t = CHANGE_TYPE[change] || CHANGE_TYPE.rewrite;
  return (
    <span style={{flex:'0 0 auto', height:18, padding:'0 7px', display:'inline-flex', alignItems:'center',
      borderRadius:'var(--r-pill)', border:'1px solid '+t.color, color:t.color, fontSize:10, fontWeight:600}}>{t.label}</span>
  );
}

/* ---------- 折叠 bar：挂在输入条上方，点击开 review sheet ---------- */
function RecentChangesBar({onView}){
  return (
    <div className="press" onClick={onView}
      style={{margin:'0 16px 10px', display:'flex', alignItems:'center', gap:9, padding:'10px 14px',
        background:'var(--surface)', border:'1px solid var(--card-border)', borderRadius:'var(--r-xl)', boxShadow:'var(--shadow-card)'}}>
      <I.history s={16} c="var(--accent)"/>
      <span style={{flex:1, minWidth:0, fontSize:12.5, fontWeight:600, color:'var(--text-secondary)', whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>AI 改了 {RECENT_CHANGES.length} 处 · 已自动应用</span>
      <span style={{fontSize:12.5, color:'var(--accent)', fontWeight:600}}>查看</span>
      <I.chevR s={15} c="var(--text-subtle)"/>
    </div>
  );
}

/* ---------- 全屏 review sheet：逐条改动 + 类型标签 + 回退；底部全部回退 ---------- */
function ChangesReviewSheet({onClose}){
  return (
    <Sheet onClose={onClose} max="80%">
      <SheetHeader
        iconBox={<div style={{width:34,height:34,borderRadius:'var(--r-md)',flex:'0 0 auto',background:'var(--surface-dim)',color:'var(--text-secondary)',display:'flex',alignItems:'center',justifyContent:'center'}}><I.history s={18}/></div>}
        title="最近改动" sub={RECENT_CHANGES.length+' 处 · 已自动应用'}/>
      <div style={{overflowY:'auto', padding:'4px 18px calc(env(safe-area-inset-bottom,0px) + 20px)'}}>
        <div style={{fontSize:12, color:'var(--text-muted)', lineHeight:1.5, padding:'4px 0 8px'}}>AI 改动已自动应用，如需撤销可逐条或全部回退。</div>
        {RECENT_CHANGES.map((c,i)=>{
          const create = c.change==='create';
          const Cmp = create ? I.plus : I.fileEdit;
          return (
            <div key={i} className="row gap8" style={{padding:'12px 0', borderTop:i?'1px solid var(--border-subtle)':'none'}}>
              <Cmp s={18} c={create?'var(--accent-warm)':'var(--text-muted)'} style={{flex:'0 0 auto'}}/>
              <div className="col" style={{flex:1, gap:2, minWidth:0}}>
                <span style={{fontSize:14, fontWeight:600, color:'var(--text-primary)', whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{c.title}</span>
                {c.sub && <span style={{fontSize:11.5, color:'var(--text-subtle)'}}>{c.sub}</span>}
              </div>
              <ChangeTypeTag change={c.change}/>
              <button className="btn-ghost press" style={{height:32, padding:'0 12px', fontSize:12.5}}><I.undo s={14}/>回退</button>
            </div>
          );
        })}
        <button className="btn-ghost press" style={{width:'100%', height:42, marginTop:14}}><I.undo s={15}/>全部回退</button>
      </div>
    </Sheet>
  );
}

/* ---------- 后台子任务条（挂在输入条上方）----------
   对齐 lib/shared/widgets/ai/chat/background_agents.dart，与桌面端 .m-bga 同构。
   子 Agent 的实时动态在消息流的活动卡里已经完整呈现，这条只保留面板独有的两
   件价值：跨滚动位置可见、控制入口。

   一个任务一行尽显，不出汇总行 —— 只有一项时没有可折叠的内容。两个以上收成
   「N 个后台任务 · 名字」+ 折叠箭头，展开后才出现「全部停止」。task 原文不上
   条：详情页里有完整版，条上永远只是截断的半句话。
   「重启后未在运行」不属于这里 —— 条上只列当前 runtime 里活着的后台 run，那
   个状态由消息流里的活动卡表达。 */
const BG_RUNS = [
  {id:'r1', name:'猫腻', agent:'内容核验', emoji:'🔍', activity:'查看 大纲 · 全书总纲', elapsed:134},
  {id:'r2', name:'江南', agent:'情节推演', emoji:'🧭', activity:'深度思考', elapsed:41},
];
const fmtElapsed = t => Math.floor(t/60) + ':' + String(t%60).padStart(2,'0');
const BG_BTN = {width:40, height:40, flex:'0 0 auto', display:'flex', alignItems:'center',
  justifyContent:'center', border:'none', background:'transparent', borderRadius:'var(--r-md)'};

function BgAgentRow({run, onStop}){
  const done = run.status==='done', stopping = run.status==='stopping';
  return (
    <div className="row" style={{gap:8, minHeight:48, padding:'0 4px 0 12px'}}>
      <span style={{width:22, height:22, flex:'0 0 auto', borderRadius:'50%', display:'flex',
        alignItems:'center', justifyContent:'center', fontSize:12,
        background: done?'color-mix(in srgb, var(--success) 14%, transparent)':'var(--surface-dim)',
        color:'var(--success)',
        boxShadow: done?'none':'0 0 0 1.5px color-mix(in srgb, var(--accent) 45%, transparent)'}}>
        {done ? <I.check s={13}/> : run.emoji}
      </span>
      {/* agent 类型名（内容核验）退到详情页，一行只留子 agent 的名字 */}
      <span style={{flex:'0 0 auto', maxWidth:88, fontSize:13.5, fontWeight:600, color:'var(--text-primary)',
        whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{run.name}</span>
      <span style={{flex:1, minWidth:0, fontSize:12,
        color: done?'var(--success)':stopping?'var(--text-subtle)':'var(--text-muted)',
        whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>
        {done ? '已完成 · 查看结果' : stopping ? '停止中…' : run.activity}
      </span>
      {/* 等宽 + tabular 数字，秒数跳动时右侧控件不左右抖 */}
      {!done && <span style={{flex:'0 0 auto', fontSize:11, fontFamily:'var(--mono)',
        color:'var(--text-subtle)', fontVariantNumeric:'tabular-nums'}}>{fmtElapsed(run.elapsed)}</span>}
      <button className="press" style={{...BG_BTN, color:'var(--text-muted)'}}><I.arrowsOut s={17}/></button>
      {/* 停止而非暂停 —— cancelRun 不可恢复，图标和文案都不该说「暂停」。
          完成后停止键撤掉，留等宽空槽，详情键不横向跳位。 */}
      {done ? (
        <span style={{width:40, height:40, flex:'0 0 auto'}}/>
      ) : (
        <button className="press" onClick={()=>!stopping && onStop(run.id)}
          style={{...BG_BTN, color: stopping?'var(--border)':'var(--text-muted)'}}>
          {/* 实心方块 —— pause 的两根竖线会暗示可恢复，而 cancelRun 不可恢复 */}
          <span style={{width:10, height:10, borderRadius:2, background:'currentColor'}}/>
        </button>
      )}
    </div>
  );
}

function BackgroundAgentsBar(){
  const [runs, setRuns] = useState(()=>BG_RUNS.map(r=>({...r, status:'running'})));
  const [open, setOpen] = useState(true);
  // 原型里让时长自己走；真实实现按 run.startedAt 算差值，不存计数器。
  useEffect(()=>{
    const t = setInterval(()=>setRuns(rs=>rs.map(r=>r.status==='running'?{...r, elapsed:r.elapsed+1}:r)), 1000);
    return ()=>clearInterval(t);
  }, []);
  const stop = (id)=>{
    // StopAgent 的返回只确认请求已接收，最终状态以任务实际结束为准。
    setRuns(rs=>rs.map(r=>r.id===id?{...r, status:'stopping'}:r));
    setTimeout(()=>setRuns(rs=>rs.map(r=>r.id===id?{...r, status:'done'}:r)), 1200);
    // 完成项留 6 秒给用户一个回执再移除，结果本身留在消息流里。
    setTimeout(()=>setRuns(rs=>rs.filter(r=>r.id!==id)), 7200);
  };
  if(runs.length===0) return null;
  const live = runs.filter(r=>r.status!=='done');
  const multi = runs.length>1;
  return (
    <div style={{margin:'0 16px 10px', background:'var(--surface)',
      border:'1px solid var(--card-border)', borderRadius:'var(--r-xl)', boxShadow:'var(--shadow-card)', overflow:'hidden'}}>
      {multi && (
        <div className="row press" onClick={()=>setOpen(o=>!o)}
          style={{gap:8, minHeight:44, padding:'0 4px 0 12px',
            borderBottom: open?'1px solid var(--border-subtle)':'none'}}>
          {/* 左右 4px 外边距凑成 22px，与行内头像同宽，名字列对齐。
              全部停止后到完成项移除之前，live 是 0 —— 那时候不该继续转圈报 0 个。 */}
          {live.length > 0 ? (
            <span className="tspin" style={{width:14, height:14, flex:'0 0 auto', margin:'0 4px',
              borderRadius:'50%', border:'1.8px solid color-mix(in srgb, var(--accent) 35%, transparent)', borderTopColor:'var(--accent)'}}/>
          ) : (
            <span style={{width:22, height:22, flex:'0 0 auto', borderRadius:'50%', display:'flex',
              alignItems:'center', justifyContent:'center',
              background:'color-mix(in srgb, var(--success) 14%, transparent)', color:'var(--success)'}}><I.check s={13}/></span>
          )}
          <span style={{flex:'0 0 auto', fontSize:13.5, fontWeight:600, color:'var(--text-secondary)'}}>
            {live.length > 0 ? live.length + ' 个后台任务' : '后台任务已结束'}
          </span>
          <span style={{flex:1, minWidth:0, fontSize:12, color:'var(--text-muted)',
            whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>
            {open ? '' : '· ' + runs.map(r=>r.name).join('、')}
          </span>
          {/* 停止不可逆，所以「全部停止」只在展开后出现 */}
          {open && live.length>1 && (
            <button className="press" onClick={(e)=>{ e.stopPropagation(); live.forEach(r=>stop(r.id)); }}
              style={{flex:'0 0 auto', border:'none', background:'transparent', color:'var(--text-muted)',
                fontSize:12.5, fontWeight:500, padding:'8px', borderRadius:'var(--r-md)'}}>全部停止</button>
          )}
          <I.caretD s={16} c="var(--text-muted)" style={{flex:'0 0 auto',
            transform: open?'rotate(180deg)':'none', transition:'transform 180ms ease'}}/>
        </div>
      )}
      {/* 4 行起列表内部滚动，不再按屏高 30% 吃聊天区 */}
      {(!multi || open) && (
        <div style={{maxHeight:148, overflowY:'auto'}}>
          {runs.map((r,i)=>(
            <div key={r.id} style={{borderTop: i?'1px solid var(--border-subtle)':'none'}}>
              <BgAgentRow run={r} onStop={stop}/>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/* ---------- 输入条（对齐桌面端 m-composer：引用 chip + 多行输入 + 模型选择 + 发送） ---------- */
function Composer({value, onChange, modelLabel, effort, onPickModel}){
  const [refs, setRefs] = useState(['人物 / 周清远','人物 / 凤瑶']);
  return (
    <div style={{flex:'0 0 auto', padding:'8px 16px calc(env(safe-area-inset-bottom,0px) + 12px)'}}>
      <div style={{background:'var(--surface)', border:'1px solid var(--card-border)', borderRadius:'var(--r-2xl)', boxShadow:'var(--shadow-card)', padding:'8px 12px'}}>
        {/* 引用 chip（对齐桌面端 m-composer__refs） */}
        {refs.length>0 && (
          <div className="row" style={{flexWrap:'wrap', gap:6, marginBottom:6}}>
            {refs.map((r,i)=>(
              <span key={i} className="chip press" style={{height:24,fontSize:11,padding:'0 9px',gap:4,background:'color-mix(in srgb, var(--accent) 10%, transparent)',border:'1px solid color-mix(in srgb, var(--accent) 25%, transparent)',color:'var(--accent-warm)'}}>
                <I.link s={11}/>{r}<I.x s={11} style={{marginLeft:2,cursor:'pointer'}} onClick={()=>setRefs(rs=>rs.filter((_,j)=>j!==i))}/>
              </span>
            ))}
          </div>
        )}
        {/* 模型 + 推理强度（推理模型才显示 effort 段） */}
        <div className="press" onClick={onPickModel} style={{display:'inline-flex', alignItems:'center', gap:6, maxWidth:260, padding:'3px 10px', borderRadius:'var(--r-pill)', background:'var(--surface)', border:'1px solid var(--border-subtle)'}}>
          <span style={{fontSize:12.5, color:'var(--text-secondary)', whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis', minWidth:0}}>{modelLabel}</span>
          {effort && (
            <React.Fragment>
              <span style={{width:1, height:11, background:'var(--border)', flex:'0 0 auto'}}/>
              <span className="row" style={{gap:4, flex:'0 0 auto'}}>
                <EffortBars total={effort.total} level={effort.level}/>
                <span style={{fontSize:12, fontWeight:600, color:'var(--accent-warm)'}}>{effort.label}</span>
              </span>
            </React.Fragment>
          )}
          <I.caretD s={14} c="var(--text-muted)"/>
        </div>
        <textarea value={value} onChange={e=>onChange(e.target.value)} rows={1} placeholder="向助手提问，输入 / 使用命令…"
          style={{width:'100%', border:'none', outline:'none', resize:'none', background:'transparent', fontFamily:'var(--sans)', fontSize:14.5, color:'var(--text-primary)', lineHeight:1.5, padding:'8px 2px', margin:'4px 0'}}/>
        <div className="row">
          <button className="press" style={{width:40,height:40,borderRadius:'50%',background:'var(--surface)',border:'1px solid var(--border-subtle)',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--text-secondary)'}}><I.plus s={20}/></button>
          <div style={{flex:1}}></div>
          <button className="press" style={{width:40,height:40,borderRadius:'50%',background:'var(--accent)',border:'none',display:'flex',alignItems:'center',justifyContent:'center',color:'var(--on-accent)'}}><I.send s={18}/></button>
        </div>
      </div>
    </div>
  );
}

/* ---------- slash 建议条（动态匹配子智能体）对齐 _SlashSuggestions ---------- */
function SlashList({matches, onSelect}){
  return (
    <div style={{margin:'0 16px 8px', background:'var(--surface)', border:'1px solid var(--card-border)', borderRadius:'var(--r-xl)', boxShadow:'var(--shadow-card)', overflow:'hidden', maxHeight:200, overflowY:'auto'}}>
      {matches.map((a,i)=>(
        <div key={a.id} className="press" onClick={()=>onSelect(a)} style={{display:'flex', alignItems:'center', gap:8, padding:'10px 16px', borderTop:i?'1px solid var(--border-subtle)':'none'}}>
          <I.spark s={16} c="var(--accent)"/>
          <span style={{fontSize:13, fontWeight:600, color:'var(--text-primary)'}}>/{a.name.replace(/ /g,'_')}</span>
        </div>
      ))}
    </div>
  );
}

/* ---------- 模型选择底部弹窗（对齐 _showModelSelector） ----------
   两级：模型列表 → 推理模型可下钻「推理强度」（对齐桌面端 hover 级联子菜单）。
   点模型行 = 直接选中并关闭；点右侧强度胶囊 = 下钻调 effort（选 effort 时一并选中该模型）。*/
function ModelSheet({selected, effortByModel, onPick, onPickEffort, onClose}){
  const [cfg, setCfg] = useState(null); // 正在配置 effort 的推理模型；null=模型列表层

  // —— 第二级：推理强度 ——
  if(cfg){
    const cur = effortByModel[cfg.name];
    return (
      <Sheet onClose={onClose} max="70%">
        <SheetHeader
          iconBox={<button className="press" onClick={()=>setCfg(null)} aria-label="返回"
            style={{width:34,height:34,borderRadius:'var(--r-md)',flex:'0 0 auto',background:'var(--surface-dim)',color:'var(--text-secondary)',border:'none',display:'flex',alignItems:'center',justifyContent:'center'}}><I.arrowL s={19}/></button>}
          title="推理强度" sub={cfg.name}/>
        <div className="slide-in" style={{overflowY:'auto', padding:'6px 8px 12px'}}>
          {cfg.efforts.map((ef,ei)=>{
            const on = cur===ef;
            return (
              <div key={ef} className="press" onClick={()=>{onPickEffort(cfg.name, ef); onClose();}}
                style={{display:'flex', alignItems:'center', gap:12, padding:'11px 12px', borderRadius:'var(--r-lg)', background:on?'var(--selected)':'transparent'}}>
                <span style={{width:30, display:'flex', justifyContent:'center', flex:'0 0 auto'}}><EffortBars total={cfg.efforts.length} level={ei}/></span>
                <div className="col" style={{flex:1, gap:2, minWidth:0}}>
                  <span style={{fontSize:14, fontWeight:600, color:on?'var(--accent)':'var(--text-primary)'}}>{EFFORT_LABELS[ef]}</span>
                  <span style={{fontSize:11.5, color:'var(--text-muted)'}}>{EFFORT_HINTS[ef]}</span>
                </div>
                {on && <I.checkCircle s={18} c="var(--accent)"/>}
              </div>
            );
          })}
        </div>
      </Sheet>
    );
  }

  // —— 第一级：模型列表 ——
  return (
    <Sheet onClose={onClose} max="64%">
      <SheetHeader
        iconBox={<div style={{width:34,height:34,borderRadius:'var(--r-md)',flex:'0 0 auto',background:'color-mix(in srgb, var(--accent) 13%, transparent)',color:'var(--accent)',display:'flex',alignItems:'center',justifyContent:'center'}}><I.brain s={18}/></div>}
        title="选择模型" sub="作用于当前会话"/>
      <div style={{overflowY:'auto', padding:'6px 8px 10px'}}>
        {MODEL_OPTIONS.map(m=>{
          const on = m.name===selected;
          const Cmp = I[m.icon]||I.robot;
          const reasoning = !!m.efforts;
          const cur = reasoning ? effortByModel[m.name] : null;
          return (
            <div key={m.name} className="press" onClick={()=>{onPick(m.name); onClose();}} style={{display:'flex', alignItems:'center', gap:11, padding:'10px 12px', borderRadius:'var(--r-lg)', background:on?'var(--selected)':'transparent'}}>
              <div style={{width:32,height:32,borderRadius:'var(--r-md)',flex:'0 0 auto',background:'color-mix(in srgb, var(--accent) 13%, transparent)',color:'var(--accent)',display:'flex',alignItems:'center',justifyContent:'center'}}><Cmp s={16}/></div>
              <div className="col" style={{flex:1, gap:1, minWidth:0}}>
                <span style={{fontSize:13.5, fontWeight:600, color:'var(--text-primary)'}}>{m.name}</span>
                <span style={{fontSize:11.5, color:'var(--text-muted)'}}>{m.provider}</span>
              </div>
              {reasoning ? (
                <button className="press" onClick={(e)=>{e.stopPropagation(); setCfg(m);}} aria-label="推理强度"
                  style={{display:'flex', alignItems:'center', gap:6, flex:'0 0 auto', padding:'5px 8px',
                    border:'1px solid '+(on?'color-mix(in srgb, var(--accent) 35%, transparent)':'var(--border-subtle)'), borderRadius:'var(--r-pill)',
                    background:on?'color-mix(in srgb, var(--accent) 10%, transparent)':'var(--surface)'}}>
                  <EffortBars total={m.efforts.length} level={m.efforts.indexOf(cur)}/>
                  <span style={{fontSize:12, fontWeight:600, color:'var(--accent-warm)'}}>{EFFORT_LABELS[cur]}</span>
                  <I.chevR s={14} c="var(--text-subtle)"/>
                </button>
              ) : (
                on && <I.checkCircle s={18} c="var(--accent)"/>
              )}
            </div>
          );
        })}
        <div style={{borderTop:'1px solid var(--border-subtle)', margin:'6px 4px 0', paddingTop:6}}>
          <div className="press" style={{padding:'9px 8px', fontSize:13, color:'var(--accent-warm)', fontWeight:600}}>添加模型…</div>
        </div>
      </div>
    </Sheet>
  );
}

/* ---------- 各模式历史会话（mock；对齐 showAiSessionHistorySheet） ---------- */
const MODE_SESSIONS = {
  chat: SESSIONS,
  council: [
    {id:'cc1', title:'第三章群像收束讨论', time:'今天 15:02'},
    {id:'cc2', title:'木匣伏笔回收时机', time:'昨天'},
    {id:'cc3', title:'卷一节奏复盘', time:'3 天前'},
  ],
  monologue: [
    {id:'mo1', title:'周清远 · 登船前夜', time:'今天 11:20'},
    {id:'mo2', title:'凤瑶 · 逃婚那夜', time:'06/20'},
  ],
  theater: [
    {id:'th1', title:'三舱客 · 初遇', time:'昨天'},
    {id:'th2', title:'雨中对峙', time:'06/18'},
  ],
  roleplay: [
    {id:'rp1', title:'与凤瑶 · 试探身份', time:'今天 09:40'},
  ],
};

/* ---------- 历史会话底部弹窗（对齐 showAiSessionHistorySheet） ---------- */
function HistorySheet({modeKey, modeLabel, onClose}){
  const sessions = MODE_SESSIONS[modeKey] || [];
  const currentId = sessions.length ? sessions[0].id : null;
  return (
    <Sheet onClose={onClose} max="72%">
      <SheetHeader
        iconBox={<div style={{width:34,height:34,borderRadius:'var(--r-md)',flex:'0 0 auto',background:'var(--surface-dim)',color:'var(--text-muted)',display:'flex',alignItems:'center',justifyContent:'center'}}><I.history s={18}/></div>}
        title="历史会话" sub={modeLabel+' · '+sessions.length+' 条'}/>
      {sessions.length===0 ? (
        <div style={{padding:'18px 18px 28px', fontSize:13, color:'var(--text-muted)'}}>暂无历史会话</div>
      ) : (
        <div style={{overflowY:'auto', padding:'6px 8px 10px'}}>
          {sessions.map(s=>{
            const cur = s.id===currentId;
            return (
              <div key={s.id} className="press" onClick={onClose} style={{display:'flex', alignItems:'center', gap:12, padding:'11px 12px', borderRadius:'var(--r-lg)', background:cur?'var(--selected)':'transparent'}}>
                <I.history s={18} c={cur?'var(--accent)':'var(--text-muted)'}/>
                <div className="col" style={{flex:1, gap:2, minWidth:0}}>
                  <span style={{fontSize:14, color:'var(--text-primary)', fontWeight:cur?600:400, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{s.title}</span>
                  <span style={{fontSize:12, color:'var(--text-muted)'}}>{s.time}</span>
                </div>
                {cur && <I.check s={18} c="var(--accent)"/>}
              </div>
            );
          })}
        </div>
      )}
    </Sheet>
  );
}

/* ---------- 非对话模式的底部操作栏（对齐各模式 idle bar） ---------- */
function ModeActionBar({primaryIcon, primaryLabel}){
  const Cmp = I[primaryIcon]||I.plus;
  return (
    <div style={{flex:'0 0 auto', background:'var(--surface)', borderTop:'1px solid var(--border-subtle)', padding:'14px 16px calc(env(safe-area-inset-bottom,0px) + 14px)'}}>
      <div className="row gap8">
        <button className="btn-ghost press" style={{flex:1, height:42}}><Cmp s={16}/>{primaryLabel}</button>
        <button className="btn-ghost press" style={{flex:1, height:42}}><I.pencil s={16}/>切换写作模式</button>
      </div>
    </div>
  );
}

/* ---------- 圆桌会议：单轮卡片（对齐 _RoundSection / _MessageBubble） ---------- */
const COUNCIL_TINTS = {'情节顾问':'#56708A','人物声音':'#6E5868','世界观考据':'#4E7F6E'};
const COUNCIL_DESC = {
  '情节顾问':'结构顾问 · 主线/副线与节奏',
  '人物声音':'守护角色语气一致性',
  '世界观考据':'核查地理/器物/时间线',
};
const COUNCIL_SAY = [
  '从结构看，三人同框在第三章是「群像收束」的第一拍，建议把木匣线索后置半页，让周清远先单独完成一次抬头。',
  '对白方面，凤瑶此刻不宜出声——一开口语气就会暴露身份，先用动作交代她的警觉。',
  '考据上，明末夜航船多在阊门外夜泊，可补一句停泊地点强化真实感。',
];
function CouncilRound(){
  const members = AI_MODES.find(m=>m.k==='council').members;
  return (
    <div style={{background:'var(--surface-dim)', border:'1px solid var(--border-subtle)', borderRadius:'var(--r-2xl)', padding:16}}>
      <div className="row" style={{gap:8, marginBottom:14}}>
        <span className="chip" style={{height:22,fontSize:11,padding:'0 10px',background:'var(--surface)',color:'var(--text-muted)',fontWeight:600}}>第 1 轮</span>
        <div className="row" style={{flex:1, justifyContent:'flex-end', gap:4}}>
          {members.map(m=><Avatar key={m} label={m[0]} size={20} tint={COUNCIL_TINTS[m]} fs={10}/>)}
        </div>
      </div>
      {members.map((m,i)=>(
        <div key={m}>
          {i>0 && <div style={{height:1, background:'var(--border-subtle)', margin:'14px 0'}}></div>}
          <div className="row" style={{alignItems:'flex-start', gap:12}}>
            <Avatar label={m[0]} size={36} tint={COUNCIL_TINTS[m]} fs={15}/>
            <div className="col" style={{flex:1, gap:2, minWidth:0}}>
              <span style={{fontSize:14, fontWeight:700, color:COUNCIL_TINTS[m]}}>{m}</span>
              <span style={{fontSize:11.5, color:'var(--text-muted)'}}>{COUNCIL_DESC[m]}</span>
              <div style={{marginTop:6, fontSize:14, color:'var(--text-primary)', lineHeight:1.6}}>{COUNCIL_SAY[i]}</div>
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

/* ---------- 独白卡片（对齐 _MonologueCard：内心活动 / 接下来的行动） ---------- */
function MonologueCard(){
  return (
    <div className="row" style={{alignItems:'flex-start', gap:12}}>
      <Avatar label="周" size={36} tint="#2D3A36" fs={15}/>
      <div className="col" style={{flex:1, gap:8, minWidth:0}}>
        <span style={{fontSize:14, fontWeight:700, color:'var(--accent)'}}>周清远</span>
        <div style={{background:'var(--surface)', borderRadius:'var(--r-2xl)', padding:12}}>
          <div className="row gap6" style={{marginBottom:6}}><I.brain s={14} c="var(--accent)"/><span style={{fontSize:12.5, fontWeight:600, color:'var(--accent)'}}>内心活动</span></div>
          <div className="serif" style={{fontSize:14.5, color:'var(--text-primary)', lineHeight:1.75}}>我把伞收好。十年了，我学会的第一件事，就是不去看别人——越是不看，越是被看。可这舱里有双眼睛，从我上船起，就没移开过。</div>
          <div className="row gap6" style={{margin:'12px 0 6px'}}><I.arrowR s={14} c="var(--accent-warm)"/><span style={{fontSize:12.5, fontWeight:600, color:'var(--accent-warm)'}}>接下来的行动</span></div>
          <div style={{fontSize:14.5, color:'var(--text-primary)', lineHeight:1.7}}>压低斗笠，借递茶的动作，余光确认那只乌木匣的朝向。</div>
        </div>
      </div>
    </div>
  );
}

/* ---------- 小剧场台词（对齐 _TheaterLineCard：舞台指示 + 台词） ---------- */
const THEATER_TINTS = {'周清远':'#2D3A36','凤瑶':'#6E5868','老沈':'#4A5468'};
const THEATER_LINES = [
  {name:'周清远', turn:1, stage:'没有回头', line:'……雨大，先生坐稳。'},
  {name:'凤瑶', turn:1, stage:'压低声音', line:'你也去松江府？'},
  {name:'老沈', turn:1, stage:'手按住木匣', line:'各人有各人的去处。'},
];
function TheaterLines(){
  return (
    <div className="col" style={{gap:16}}>
      {THEATER_LINES.map((l,i)=>(
        <div key={i} className="row" style={{alignItems:'flex-start', gap:12}}>
          <Avatar label={l.name[0]} size={36} tint={THEATER_TINTS[l.name]} fs={15}/>
          <div className="col" style={{flex:1, gap:8, minWidth:0}}>
            <div className="row gap8"><span style={{fontSize:14, fontWeight:700, color:'var(--accent-warm)'}}>{l.name}</span><span style={{fontSize:11, color:'var(--text-subtle)'}}>第 {l.turn} 幕</span></div>
            <div style={{background:'var(--surface)', borderRadius:'var(--r-2xl)', padding:12}}>
              <div style={{fontSize:13, color:'var(--text-muted)', fontStyle:'italic', lineHeight:1.6, marginBottom:4}}>（{l.stage}）</div>
              <div className="serif" style={{fontSize:14.5, color:'var(--text-primary)', lineHeight:1.7}}>「{l.line}」</div>
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

/* ---------- 角色扮演气泡（对齐 _RoleplayMessageBubble：用户右 / 角色左） ---------- */
function RoleplaySample(){
  return (
    <div className="col" style={{gap:16}}>
      <div className="row" style={{alignItems:'flex-start', gap:12}}>
        <div className="col" style={{flex:1, alignItems:'flex-end', gap:6}}>
          <span style={{fontSize:12.5, fontWeight:600, color:'var(--accent)'}}>我</span>
          <div style={{background:'color-mix(in srgb, var(--accent) 8%, transparent)', borderRadius:'var(--r-2xl)', padding:12, maxWidth:'88%'}}>
            <div className="serif" style={{fontSize:14.5, color:'var(--text-primary)', lineHeight:1.7}}>（压低声音）你怀里抱的，是什么？</div>
          </div>
        </div>
        <Avatar label="我" size={32} fs={13}/>
      </div>
      <div className="row" style={{alignItems:'flex-start', gap:12}}>
        <Avatar label="凤" size={32} tint="#6E5868" fs={13}/>
        <div className="col" style={{flex:1, gap:6, minWidth:0}}>
          <span style={{fontSize:14, fontWeight:700, color:'var(--accent-warm)'}}>凤瑶</span>
          <div style={{background:'var(--surface)', borderRadius:'var(--r-2xl)', padding:12}}>
            <div className="serif" style={{fontSize:14.5, color:'var(--text-primary)', lineHeight:1.7}}>「与先生无关。」她把袖口往下拉了拉，盖住那截太干净的手腕。</div>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ---------- Chat / Mode screen ---------- */
/* ---------- 下一步建议条（对齐桌面端 m-nextact / NextActionBar） ----------
   来源是模型的 SuggestNextAction 工具调用，不是客户端规则：
   1. 模型没挂建议 → 整条不渲染，不占高度（第一行 early return），不做本地兜底；
   2. label 是模型运行时给的，不走 i18n，所以这里写成贴合当前章节的样子；
   3. kind=prompt 点了填进输入框（不自动发送）；kind=feature 点了 pushReplacement
      到对应模式页，seed 预填目标页的议题 / 场景。移动端无封面工作台，
      ai_cover_studio 走既有的 cover handoff prompt。 */
const NEXT_ACTION_ICON = {prompt:'bulb', ai_council:'users3', ai_theater:'mask', ai_cover_studio:'image'};

const NEXT_ACTIONS_SAMPLE = [
  {kind:'prompt',  label:'核对第 03 章的时间线与老沈行踪'},
  {kind:'feature', feature:'ai_council', label:'木匣的交代时机去圆桌听几个视角'},
  {kind:'feature', feature:'ai_theater', label:'先把三舱对峙演一遍'},
];

function NextActionBar({actions, onPick}){
  // 没有建议就什么都不显示 —— 对齐 NextActionBar 的 SizedBox.shrink()。
  if(!actions || actions.length===0) return null;
  return (
    <div style={{flex:'0 0 auto', padding:'0 16px 8px'}}>
      <div className="row" style={{gap:5, marginBottom:6}}>
        <I.bulb s={12} c="var(--text-subtle)"/>
        <span style={{fontSize:11, fontWeight:500, color:'var(--text-subtle)'}}>下一步</span>
      </div>
      {/* 横向滚动，不换行：移动端窄，chip 换行会把输入区顶下去 */}
      <div style={{display:'flex', gap:6, overflowX:'auto', paddingBottom:2, scrollbarWidth:'none'}}>
        {actions.map((a,i)=>{
          const goto = a.kind==='feature';
          const Ico = I[NEXT_ACTION_ICON[goto?a.feature:'prompt']];
          return (
            <button key={i} className="press" onClick={()=>onPick&&onPick(a)}
              style={{display:'inline-flex', alignItems:'center', gap:5, flex:'0 0 auto', maxWidth:250,
                height:30, padding:'0 11px', borderRadius:'var(--r-pill)',
                background:'var(--surface)', color:'var(--text-secondary)',
                border:'1px solid var(--border-input)', borderStyle: goto?'dashed':'solid',
                fontFamily:'var(--sans)', fontSize:12.5, fontWeight:500}}>
              <Ico s={13} c={goto?'var(--accent)':'var(--text-muted)'}/>
              <span style={{whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis', minWidth:0}}>{a.label}</span>
              {goto && <I.chevR s={12} c="var(--text-subtle)"/>}
            </button>
          );
        })}
      </div>
    </div>
  );
}

/* ---------- 空会话欢迎态（对齐桌面端 AssistantEmptyState） ----------
   空会话时一次模型调用都还没发生，这四条来自客户端固定目录，不是模型给的。
   封面那条只在「没封面 + 书名简介已确认 + 已配图像模型」时出现。 */
const EMPTY_STATE_ACTIONS = [
  {kind:'prompt',  icon:'checks', title:'规划今天的工作',       sub:'围绕接下来三章安排今日写作。'},
  {kind:'feature', feature:'ai_council',      icon:'users3', title:'和多位专家讨论剧情',   sub:'换几个视角看看这段该往哪走。'},
  {kind:'feature', feature:'ai_theater',      icon:'mask',   title:'不知道怎么写？先演一遍', sub:'让角色把这场戏演出来，再决定怎么落笔。'},
  {kind:'feature', feature:'ai_cover_studio', icon:'image',  title:'给作品做一张封面',     sub:'书名和简介都齐了，配张封面上书架。'},
];

function ChatEmptyState({actions, onPick}){
  return (
    <div className="col fade-in" style={{gap:0, padding:'20px 0 8px'}}>
      <div style={{display:'flex', justifyContent:'center', marginBottom:20}}>
        <div style={{width:84, height:84, borderRadius:'50%', display:'flex', alignItems:'center', justifyContent:'center',
          background:'var(--surface-container)', border:'1px solid var(--border-subtle)'}}>
          <I.books s={32} c="var(--accent)"/>
        </div>
      </div>
      <div style={{fontSize:15, fontWeight:600, lineHeight:1.55, textAlign:'center', whiteSpace:'pre-line',
        color:'var(--text-primary)', marginBottom:24}}>
        {'慢慢写，我会陪你一起\n整理灵感与情节。'}
      </div>
      <div style={{fontSize:13, fontWeight:600, color:'var(--text-primary)', marginBottom:10}}>你可以这样开始</div>
      <div className="col" style={{gap:10}}>
        {actions.map((a,i)=>{
          const Ico = I[a.icon];
          return (
            <div key={i} className="card press" onClick={()=>onPick&&onPick(a)}
              style={{padding:13, display:'flex', gap:12, alignItems:'center'}}>
              <div style={{width:36, height:36, flex:'0 0 auto', borderRadius:'var(--r-xl)',
                display:'flex', alignItems:'center', justifyContent:'center',
                background:'var(--selected)', border:'none'}}>
                <Ico s={17} c="var(--accent)"/>
              </div>
              <div className="col" style={{flex:1, gap:3, minWidth:0}}>
                <span style={{fontSize:13, fontWeight:600, color:'var(--text-primary)'}}>{a.title}</span>
                <span style={{fontSize:11.5, color:'var(--text-muted)', lineHeight:1.5}}>{a.sub}</span>
              </div>
              <I.chevR s={17} c="var(--text-subtle)"/>
            </div>
          );
        })}
      </div>
    </div>
  );
}

/* mockup 专用：三态对照，真实产品里没有这个控件。 */
const DEMO_STATES = [{id:'suggest', label:'有建议'}, {id:'none', label:'无建议'}, {id:'empty', label:'空会话'}];

function DemoSwitch({value, onChange}){
  return (
    <div className="row" style={{gap:5, padding:'6px 16px', borderBottom:'1px dashed var(--border-subtle)',
      background:'repeating-linear-gradient(45deg,transparent,transparent 6px,color-mix(in srgb, var(--text-muted) 4.5%, transparent) 6px,color-mix(in srgb, var(--text-muted) 4.5%, transparent) 12px)'}}>
      <span style={{fontSize:11, fontWeight:500, color:'var(--text-subtle)', marginRight:2}}>演示态</span>
      {DEMO_STATES.map(s=>(
        <button key={s.id} className="press" onClick={()=>onChange(s.id)}
          style={{padding:'2px 9px', borderRadius:'var(--r-pill)', cursor:'pointer',
            border:'1px solid '+(value===s.id?'var(--accent)':'var(--border-subtle)'),
            background:value===s.id?'var(--selected)':'transparent',
            color:value===s.id?'var(--text-primary)':'var(--text-muted)',
            fontFamily:'var(--sans)', fontSize:11, fontWeight:500}}>
          {s.label}
        </button>
      ))}
    </div>
  );
}

function ChatScreen({modeKey='chat', novelTitle='夜航船', embedded, onBack, onOpenManage}){
  // 进入时的模式作为初值，模式切换条在屏内切换样例。
  const [curMode, setCurMode] = useState(modeKey);
  const mode = AI_MODES.find(m=>m.k===curMode) || AI_MODES[0];
  const isChat = curMode==='chat';
  const freeChat = isChat || curMode==='roleplay';
  const [text, setText] = useState('');
  const [model, setModel] = useState(MODEL_OPTIONS[0].name);
  // 每个推理模型各记一个 effort，初值取模型默认。
  const [effortByModel, setEffortByModel] = useState(()=>{
    const o = {};
    MODEL_OPTIONS.forEach(m=>{ if(m.efforts) o[m.name] = m.defaultEffort; });
    return o;
  });
  const [pickModel, setPickModel] = useState(false);
  const [history, setHistory] = useState(false);
  const [toolDetail, setToolDetail] = useState(null);
  const [reviewChanges, setReviewChanges] = useState(false);
  // mockup 专用：有建议 / 无建议 / 空会话 三态对照。
  const [demo, setDemo] = useState('suggest');
  const emptySession = isChat && demo==='empty';
  const nextActions = isChat && demo==='suggest' ? NEXT_ACTIONS_SAMPLE : [];
  // 点建议：prompt 类填进输入框（不自动发送）；feature 类在真实产品里会跳走。
  const pickAction = (a)=>{ if(a.kind==='prompt') setText(a.label); };

  // 当前选中模型的 effort 展示元数据（非推理模型为 null）。
  const curModelObj = MODEL_OPTIONS.find(m=>m.name===model);
  const curEffort = curModelObj?.efforts ? {
    label: EFFORT_LABELS[effortByModel[model]],
    total: curModelObj.efforts.length,
    level: curModelObj.efforts.indexOf(effortByModel[model]),
  } : null;

  // 工具活动样例（步骤时间线，重内容收进底部 Sheet）— thinking 与 tool call 同组；
  // 同时演示「跨响应合并」：第二轮 LLM 响应（真实数据里是独立 assistant 消息）
  // 与上一轮间无 text，按预期并入同一活动卡，故含两个 thinking 检查点。
  const editSteps = [
    {kind:'thinking', verb:'推理过程', status:'success',
      detail:{type:'preview', label:'推理过程', text:'依据本章大纲与人物档案，确定三个身份伏笔的呈现顺序：把木匣线索推迟到周清远第二次抬头之后，避免点名式登场。'}},
    {verb:'读取', icon:'eye', target:'chapters / 第 03 章', status:'success',
      detail:{type:'preview', label:'读取片段', text:'船舱里很暗，三个人各怀心事，画师、小姐、旧官的身份在第一段就交代清楚。'}},
    {verb:'编辑', icon:'fileEdit', target:'第 03 章 · 第 1 段', status:'success',
      detail:{type:'diff',
        old:'船舱里很暗，三个人各怀心事，画师、小姐、旧官的身份在第一段就交代清楚。',
        now:'船舱里很暗。三盏小油灯在低梁下摇晃，把每一张脸都照成了半张。周清远没有看身后那两人——他知道，越是不看，越是被看。'}},
    // —— 第二轮 LLM 响应：与上一轮间无 text，合并进同一活动卡 ——
    {kind:'thinking', verb:'推理过程', status:'success',
      detail:{type:'preview', label:'推理过程', text:'第一段已拆分，接着把“老沈的木匣”从首段移到周清远第二次抬头之后的第六、七段之间，让伏笔晚一拍出现。'}},
    {verb:'编辑', icon:'fileEdit', target:'第 03 章 · 第 6 段', status:'success',
      detail:{type:'diff',
        old:'老沈把木匣往怀里又按了按，谁也没有多问。',
        now:'老沈的手始终没离开膝上那只乌木匣。周清远第二次抬头时，正看见他指节收紧——像是怕谁伸手，又像是怕自己松开。'}},
  ];
  const charSteps = [
    {kind:'thinking', verb:'推理过程', status:'success',
      detail:{type:'preview', label:'推理过程', text:'凤瑶的简介需紧扣身份破绽（唇线、指甲、手腕），先全库搜索出场再起草，避免与既有设定冲突。'}},
    {verb:'读取', icon:'eye', target:'chapters / 第 03 章 · 三舱客', status:'success',
      detail:{type:'preview', label:'读取片段', text:'三舱客各有来历，凤瑶垂眸不语，指节泛白——那截太干净的手腕，藏在袖口里。'}},
    {verb:'搜索', icon:'search', target:'“凤瑶” · 全库命中 6 处', status:'success',
      detail:{type:'paths', label:'命中 6 处', items:['characters / 凤瑶.md','chapters / 第 01 章','chapters / 第 03 章','outline / 卷一 · 三舱客','foreshadow / 乌木匣','locations / 夜航船']}},
    {verb:'写入', icon:'file', target:'人物 / 凤瑶 / Synopsis.md', status:'success',
      detail:{type:'preview', label:'写入内容', text:'凤瑶 — 苏州府官家小姐，女扮男装逃婚。唇线与指甲是身份的破绽，开口即露怯，故惜字如金。'}},
  ];

  // slash 建议：以 / 开头且无空格时，匹配已启用子智能体（对齐 novel_chat_page）。
  const q = text.trim();
  const showSlash = isChat && q.startsWith('/') && !q.includes(' ');
  const slashMatches = showSlash
    ? SUBAGENTS.filter(a=>a.enabled && ('/'+a.name.replace(/ /g,'_')).startsWith(q))
    : [];

  // 标题：chat = 作品名；其它模式 = 模式名 + 上下文副标题。
  const MODE_SUBTITLE = {
    council:'3 位智能体 · 第 1 轮',
    monologue:'周清远 · 第一人称',
    theater:'3 位角色 · 第 1 幕',
    roleplay:'与 凤瑶 对戏',
  };
  const title = isChat ? novelTitle : mode.label;
  const subtitle = isChat ? null : MODE_SUBTITLE[curMode];
  const newLabel = isChat ? '新会话' : (curMode==='council'?'新讨论':curMode==='theater'?'新表演':'新会话');

  return (
    <div className="screen fade-in" data-screen-label={"chat-"+curMode} style={{background:'var(--canvas)'}}>
      {/* AppBar：返回 + 标题 + 历史/新建 + 模式切换条 + 分隔线 */}
      <div className="appbar" style={{paddingTop:54}}>
        <div className="row" style={{padding:'6px 4px 6px', gap:0}}>
          {!embedded ? <IconBtn icon="chevL" size={24} onClick={onBack}/> : <div style={{width:MOBILE_ICON_BUTTON_SIZE,flexShrink:0}}></div>}
          <div className="col" style={{flex:1, minWidth:0, alignItems:'flex-start', paddingLeft:2}}>
            <span className="display" style={{fontSize:16, fontWeight:700, color:'var(--text-primary)', whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis', maxWidth:'100%'}}>{title}</span>
            {subtitle && <span style={{fontSize:11.5, color:'var(--text-muted)'}}>{subtitle}</span>}
          </div>
          <IconBtn icon="history" ariaLabel="历史会话" onClick={()=>setHistory(true)}/>
          <IconBtn icon="plus" ariaLabel={newLabel} onClick={()=>{}}/>
        </div>
        {/* 模式切换条 */}
        <div style={{display:'flex', gap:7, overflowX:'auto', padding:'2px 12px 10px'}}>
          {AI_MODES.map(m=>{
            const on = m.k===curMode;
            const Cmp = I[m.icon]||I.chat;
            return (
              <button key={m.k} className="press" onClick={()=>{ setCurMode(m.k); setText(''); }}
                style={{flex:'0 0 auto', height:30, padding:'0 12px', borderRadius:'var(--r-pill)', display:'flex', alignItems:'center', gap:6,
                  fontSize:12.5, fontWeight:600, cursor:'pointer',
                  background:on?'var(--selected)':'transparent', color:on?'var(--accent-warm)':'var(--text-muted)',
                  border:'1px solid '+(on?'var(--accent)':'var(--border-subtle)')}}>
                <Cmp s={14}/>{m.label}
              </button>
            );
          })}
        </div>
        <div style={{height:1, background:'var(--border-subtle)'}}></div>
      </div>

      {/* mockup 专用：切换「有建议 / 无建议 / 空会话」三态对照 */}
      {isChat && <DemoSwitch value={demo} onChange={setDemo}/>}

      {/* 上下文条（对齐桌面端 m-chat__context：当前章节/角色上下文） */}
      {isChat && (
        <div style={{display:'flex', alignItems:'center', gap:7, padding:'8px 16px', background:'var(--surface-dim)', borderBottom:'1px solid var(--border-subtle)'}}>
          <I.file s={13} c="var(--text-muted)"/>
          <span style={{fontSize:12, color:'var(--text-muted)'}}>当前上下文：第 03 章 · 三舱客 · 周清远视角</span>
        </div>
      )}

      {/* chat 模式顶部待办面板（对齐 TodoPanel，挂在列表之上） */}
      {isChat && !emptySession && <div style={{paddingTop:14}}><TodoBar/></div>}

      <div className="viewport" style={{padding:isChat?'2px 0 12px':'16px 0 12px'}}>
        <div style={{padding:'0 16px'}}>
          {emptySession ? (
            <ChatEmptyState actions={EMPTY_STATE_ACTIONS} onPick={pickAction}/>
          ) : isChat ? (
            <div className="col" style={{gap:16}}>
              <UserBubble text={CHAT_MSGS[0].content} refs={['人物 / 周清远','人物 / 凤瑶']}/>

              <AiTrack>
                {/* thinking 已并入活动时间线，不再单独渲染 ThinkingCard */}
                <ToolActivity steps={editSteps} onOpenDetail={setToolDetail}/>
                <TextBubble>{CHAT_MSGS[1].content}</TextBubble>
                <MsgActions/>
              </AiTrack>

              <UserBubble text="/人物声音 为凤瑶生成一页人物简介"/>

              <AiTrack>
                <ToolActivity steps={charSteps} onOpenDetail={setToolDetail}/>
                <TextBubble>已起草并保存到 <b>人物 / 凤瑶</b>。</TextBubble>
                <div className="press" style={{background:'var(--surface)', border:'1px solid var(--card-border)', borderRadius:'var(--r-xl)', boxShadow:'var(--shadow-card)', padding:'12px 13px', display:'flex', gap:11, alignItems:'center'}}>
                  <Avatar label="凤" size={40} tint="#6E5868" fs={16}/>
                  <div className="col" style={{flex:1, gap:3, minWidth:0}}>
                    <span className="display" style={{fontSize:13, fontWeight:700}}>凤瑶 — 人物简介</span>
                    <span style={{fontSize:11.5, color:'var(--text-muted)', lineHeight:1.5}}>苏州府官家小姐，女扮男装逃婚，唇线与指甲是身份的破绽……</span>
                  </div>
                  <I.chevR s={18} c="var(--text-subtle)"/>
                </div>
                <MsgActions/>
              </AiTrack>

              <UserBubble text="木匣里到底装的什么？我不确定要不要现在就交代。"/>

              {/* 第 3 轮：AskUser 交互卡 + 尾部 thinking 进行中（streaming tail） */}
              <AiTrack>
                <AskUserInline
                  question="木匣的交代时机关系到第六章的回收节奏，你希望："
                  options={['本章末尾暗示，第六章揭开','本章完全不提，留作长线悬念','本章直接点破']}
                  hint="或补充其他想法…"
                />
                <ToolActivity steps={[{kind:'thinking', verb:'思考中', status:'running'}]} onOpenDetail={setToolDetail}/>
              </AiTrack>
            </div>
          ) : curMode==='council' ? (
            <div className="col" style={{gap:16}}>
              <UserBubble text="议题：第三章三人同场，如何收束群像而不显刻意？"/>
              <CouncilRound/>
            </div>
          ) : curMode==='monologue' ? (
            <MonologueCard/>
          ) : curMode==='theater' ? (
            <TheaterLines/>
          ) : (
            <RoleplaySample/>
          )}
        </div>
      </div>

      {/* slash 建议条 */}
      {slashMatches.length>0 && (
        <SlashList matches={slashMatches} onSelect={(a)=>setText('/'+a.name.replace(/ /g,'_')+' ')}/>
      )}

      {/* chat 模式：输入条上方的最近变更日志 bar（点「查看」开全屏 review sheet） */}
      {isChat && !emptySession && <RecentChangesBar onView={()=>setReviewChanges(true)}/>}

      {/* 输入条正上方。无建议时 NextActionBar 自己返回 null，这里不留占位。 */}
      <NextActionBar actions={nextActions} onPick={pickAction}/>

      {/* 输入条正上方。没有后台任务时自己返回 null。 */}
      {freeChat && <BackgroundAgentsBar/>}

      {/* 底部：chat / 角色扮演 用输入条；回合制模式用操作栏 */}
      {freeChat ? (
        <Composer value={text} onChange={setText} modelLabel={model} effort={curEffort} onPickModel={()=>setPickModel(true)}/>
      ) : curMode==='monologue' ? (
        <ModeActionBar primaryIcon="plus" primaryLabel="继续独白"/>
      ) : (
        <ModeActionBar primaryIcon="plus" primaryLabel="追加一轮"/>
      )}

      {pickModel && <ModelSheet
        selected={model}
        effortByModel={effortByModel}
        onPick={(name)=>setModel(name)}
        onPickEffort={(name,ef)=>{ setEffortByModel(p=>({...p,[name]:ef})); setModel(name); }}
        onClose={()=>setPickModel(false)}/>}
      {history && <HistorySheet modeKey={curMode} modeLabel={mode.label} onClose={()=>setHistory(false)}/>}
      {toolDetail && <ToolDetailSheet step={toolDetail} onClose={()=>setToolDetail(null)}/>}
      {reviewChanges && <ChangesReviewSheet onClose={()=>setReviewChanges(false)}/>}
    </div>
  );
}

/* ---------- AI hub (tab landing) ---------- */
function AIHub({onOpenChat, onOpenMode, onOpenManage}){
  const [ref, scrolled] = useScrolled();
  return (
    <div className="screen" data-screen-label="ai-hub">
      <PageHead title="AI" big scrolled={scrolled}
        right={<IconBtn icon="plus" ariaLabel="新会话"/>}/>
      <div className="viewport" ref={ref} style={{padding:'4px 20px 24px'}}>
        {/* primary chat entry */}
        <div className="card press fade-in" onClick={()=>onOpenChat('chat')} style={{padding:14, display:'flex', gap:13, alignItems:'center', marginBottom:18}}>
          <Avatar label="" size={48} fs={0}><I.spark s={22} c="var(--on-accent)"/></Avatar>
          <div className="col" style={{flex:1, gap:3}}>
            <span className="display" style={{fontSize:17, fontWeight:700}}>写作助手</span>
            <span style={{fontSize:12, color:'var(--text-muted)'}}>AI · mimo-v2.5 · 作用于《夜航船》</span>
          </div>
          <button className="btn-accent press" style={{height:36, padding:'0 14px'}}><I.chat s={15}/>对话</button>
        </div>

        {/* AI modes */}
        <SectionLabel text="AI 模式"/>
        <div style={{display:'grid', gridTemplateColumns:'1fr 1fr', gap:10, marginBottom:20}}>
          {AI_MODES.filter(m=>m.k!=='chat').map(m=>{
            const Cmp = I[m.icon]||I.chat;
            return (
              <div key={m.k} className="card press" onClick={()=>onOpenMode(m.k)} style={{padding:'13px 13px'}}>
                <div className="row gap8" style={{marginBottom:7}}>
                  <span style={{width:32,height:32,borderRadius:'var(--r-md)',background:m.tint,color:m.tint.startsWith('var(')?'var(--on-accent)':'#fff',display:'flex',alignItems:'center',justifyContent:'center'}}><Cmp s={17}/></span>
                  <span style={{fontSize:14, fontWeight:700}}>{m.label}</span>
                </div>
                <p style={{margin:0, fontSize:11.5, color:'var(--text-muted)', lineHeight:1.55,
                  display:'-webkit-box', WebkitLineClamp:2, WebkitBoxOrient:'vertical', overflow:'hidden'}}>{m.desc}</p>
              </div>
            );
          })}
        </div>

        {/* manage */}
        <SectionLabel text="智能体与技能"/>
        <div className="slist" style={{marginBottom:20}}>
          {[['prompts','提示词','hub','主笔'],
            ['subagents','智能体','robot', SUBAGENTS.length+' 个'],
            ['shortcuts','快捷方式','cursor', SHORTCUTS.length+' 个'],
            ['skills','智能体技能','spark', SKILLS.length+' 个']].map(([k,label,icon,val])=>{
            const Cmp = I[icon]||I.robot;
            return (
              <div key={k} className="srow" onClick={()=>onOpenManage(k)}>
                <div className="sicon" style={{background:'color-mix(in srgb, var(--accent) 13%, transparent)', color:'var(--accent-warm)'}}><Cmp s={18}/></div>
                <span style={{flex:1, fontSize:14.5, fontWeight:500}}>{label}</span>
                <span style={{fontSize:13, color:'var(--text-muted)'}}>{val}</span>
                <I.chevR s={18} c="var(--text-subtle)"/>
              </div>
            );
          })}
        </div>

        {/* recent sessions */}
        <SectionLabel text="最近对话"/>
        <div className="col gap10">
          {SESSIONS.map(s=>(
            <div key={s.id} className="card press" onClick={()=>onOpenChat('chat')} style={{padding:'12px 14px', display:'flex', gap:11, alignItems:'center'}}>
              <div style={{width:34,height:34,borderRadius:'var(--r-md)',flex:'0 0 auto',background:'var(--surface-dim)',color:'var(--text-muted)',display:'flex',alignItems:'center',justifyContent:'center'}}><I.chat s={17}/></div>
              <div className="col" style={{flex:1, gap:2, minWidth:0}}>
                <span style={{fontSize:13.5, fontWeight:600}}>{s.title}</span>
                <span style={{fontSize:11.5, color:'var(--text-subtle)', whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{s.preview}</span>
              </div>
              <span style={{fontSize:11, color:'var(--text-subtle)', flex:'0 0 auto'}}>{s.time}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

/* ---------- 管理列表 ---------- */
function ManageScreen({kind, onBack, onOpenEdit}){
  const [ref, scrolled] = useScrolled();
  const cfg = {
    subagents:{title:'智能体', list:SUBAGENTS, render:'sub'},
    skills:{title:'智能体技能', list:SKILLS, render:'skill'},
    prompts:{title:'提示词', list:[PRIMARY_AGENT], render:'prompt'},
    shortcuts:{title:'快捷方式', list:SHORTCUTS, render:'shortcut'},
  }[kind] || {title:'', list:[], render:'sub'};

  return (
    <div className="screen fade-in" data-screen-label={"manage-"+kind}>
      <PageHead title={cfg.title} onBack={onBack} scrolled={scrolled} center
        right={(kind==='subagents'||kind==='skills'||kind==='shortcuts')?<IconBtn icon="plus" onClick={()=>onOpenEdit(kind,{isNew:true})}/>:<div style={{width:MOBILE_ICON_BUTTON_SIZE,flexShrink:0}}></div>}/>
      <div className="viewport" ref={ref} style={{padding:'12px 18px 28px'}}>
        <div className="col gap10">
          {cfg.list.map((e,i)=>(
            <div key={e.id||i} className="card press" onClick={()=>cfg.render!=='prompt'&&onOpenEdit(kind,e)} style={{padding:'13px 14px', display:'flex', gap:12, alignItems:'center'}}>
              <div style={{width:42,height:42,borderRadius:'var(--r-lg)',flex:'0 0 auto',background:'color-mix(in srgb, var(--accent) 13%, transparent)',display:'flex',alignItems:'center',justifyContent:'center',fontSize:20}}>
                {e.emoji ? e.emoji : React.createElement(I[e.icon]||I.robot,{s:20,c:'var(--accent)'})}
              </div>
              <div className="col" style={{flex:1, gap:3, minWidth:0}}>
                <div className="row gap6">
                  <span className="display" style={{fontSize:14.5, fontWeight:700}}>{e.name}</span>
                  {e.builtin && <span className="chip" style={{height:17,fontSize:9.5,padding:'0 6px',background:'var(--surface-dim)',color:'var(--text-subtle)'}}>内置</span>}
                  {cfg.render==='sub' && <span className="chip" style={{height:17,fontSize:9.5,padding:'0 6px',background:e.mode==='council'?'color-mix(in srgb, var(--info) 12%, transparent)':'color-mix(in srgb, var(--accent) 12%, transparent)',color:e.mode==='council'?'var(--info)':'var(--accent-warm)'}}>{e.mode==='council'?'议会':'对话'}</span>}
                </div>
                <span style={{fontSize:12, color:'var(--text-muted)', lineHeight:1.5,
                  display:'-webkit-box', WebkitLineClamp:2, WebkitBoxOrient:'vertical', overflow:'hidden'}}>{e.desc||e.when||e.en||'—'}</span>
              </div>
              {cfg.render!=='prompt' && (e.enabled!==undefined
                ? <span className="chip" style={{height:20,fontSize:10,padding:'0 8px',color:e.enabled?'var(--success)':'var(--text-subtle)',background:e.enabled?'color-mix(in srgb, var(--success) 12%, transparent)':'var(--surface-dim)',flex:'0 0 auto'}}>{e.enabled?'已启用':'已停用'}</span>
                : <I.chevR s={16} c="var(--text-subtle)"/>)}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

/* ---------- 编辑：子智能体 / 技能 ---------- */
function EditPanel({kind, entity, onBack}){
  const isNew = !entity || entity.isNew;
  const isSkill = kind==='skills';
  const isShortcut = kind==='shortcuts';
  const e = entity || {};
  const [enabled, setEnabled] = useState(e.enabled!==false);
  const [mode, setMode] = useState(e.mode==='council'?'council':'chat');
  const [useCustom, setUseCustom] = useState(e.useCustom!==false);
  const [ref, scrolled] = useScrolled();
  const title = isSkill?'技能':isShortcut?'快捷方式':'子智能体';

  return (
    <div className="screen fade-in" data-screen-label={"edit-"+kind}>
      <PageHead title={isNew?('新建'+title):e.name} onBack={onBack} scrolled={scrolled} center
        right={<button className="press" style={{height:32, padding:'0 16px', borderRadius:'var(--r-pill)', background:'var(--accent)', color:'var(--on-accent)', border:'none', fontSize:13, fontWeight:600}}>保存</button>}/>
      <div className="viewport" ref={ref} style={{padding:'14px 20px 28px'}}>
        {/* hero */}
        <div className="row gap12" style={{marginBottom:18, alignItems:'center'}}>
          <div style={{width:60,height:60,borderRadius:'var(--r-2xl)',flex:'0 0 auto',background:'color-mix(in srgb, var(--accent) 13%, transparent)',display:'flex',alignItems:'center',justifyContent:'center',fontSize:28}}>
            {e.emoji ? e.emoji : React.createElement(isSkill?I.spark:I.robot,{s:28,c:'var(--accent)'})}
          </div>
          <div className="col" style={{flex:1, gap:4}}>
            <span className="display" style={{fontSize:18, fontWeight:700}}>{isNew?('新建'+title):e.name}</span>
            <span style={{fontSize:12, color:'var(--text-muted)'}}>{isSkill?'编辑技能的触发时机与提示词':'编辑身份、行为与提示词'}</span>
          </div>
        </div>

        {/* enable toggle row */}
        {!isShortcut && (
          <div className="card" style={{padding:'12px 14px', display:'flex', alignItems:'center', gap:10, marginBottom:18}}>
            <div className="col" style={{flex:1, gap:2}}>
              <span style={{fontSize:14, fontWeight:600}}>启用</span>
              <span style={{fontSize:11.5, color:'var(--text-muted)'}}>停用后不会出现在助手的可选列表中</span>
            </div>
            <Switch on={enabled} onToggle={()=>setEnabled(v=>!v)}/>
          </div>
        )}

        {!isSkill && !isShortcut && (
          <div className="row gap10" style={{marginBottom:0}}>
            <div style={{flex:1}}>
              <Field label="标识符">
                <div className="row gap6" style={{height:44, padding:'0 13px', borderRadius:'var(--r-lg)', border:'1px solid var(--border-input)', background:'var(--surface-dim)'}}>
                  <span style={{flex:1, fontSize:13.5, color:'var(--text-muted)', fontFamily:'var(--mono)'}}>{e.slug||'new-subagent'}</span>
                  {!isNew && <I.bookmark s={13} c="var(--text-subtle)"/>}
                </div>
              </Field>
            </div>
          </div>
        )}

        <Field label="名称"><input className="tinput" defaultValue={e.name||''} placeholder={title+'名称'}/></Field>

        {isSkill && <Field label="使用时机" hint="描述何时应当触发此技能。"><textarea className="tarea" rows={2} defaultValue={e.when||''}/></Field>}

        <Field label="描述"><textarea className="tarea" rows={3} defaultValue={e.desc||''} placeholder="一句话说明它的职责"/></Field>

        {!isSkill && !isShortcut && (
          <div className="row gap10" style={{alignItems:'flex-start'}}>
            <div style={{flex:1}}>
              <Field label="模式">
                <div className="seg">
                  <div className={"segopt"+(mode==='chat'?' active':'')} onClick={()=>setMode('chat')}><I.chat s={14}/>对话</div>
                  <div className={"segopt"+(mode==='council'?' active':'')} onClick={()=>setMode('council')}><I.users3 s={14}/>议会</div>
                </div>
              </Field>
            </div>
          </div>
        )}

        {!isShortcut && <Field label="模型"><ModelSelect value={e.model}/></Field>}

        {!isShortcut && (
          <Field label="提示词" right={e.builtin?(
            <span className="row gap8">
              <span style={{fontSize:11.5, color:'var(--text-muted)'}}>自定义</span>
              <Switch on={useCustom} onToggle={()=>setUseCustom(v=>!v)}/>
            </span>):null}>
            <textarea className="tarea" rows={9} defaultValue={e.prompt||''} disabled={e.builtin&&!useCustom}
              style={{fontFamily:'var(--mono)', fontSize:13, opacity:(e.builtin&&!useCustom)?.55:1}}
              placeholder="描述职责、输入与输出格式…"/>
          </Field>
        )}

        {isShortcut && (
          <Field label="命令" hint="在聊天框输入 / 即可唤起此快捷方式。">
            <input className="tinput" defaultValue={e.name?('/'+e.en?.toLowerCase()):''} placeholder="/command"/>
          </Field>
        )}

        {!isNew && (
          <button className="btn-ghost press" style={{width:'100%', height:44, marginTop:8, color:'var(--error)', borderColor:'color-mix(in srgb, var(--error) 40%, transparent)'}}>
            <I.trash s={16}/>删除{title}</button>
        )}
      </div>
    </div>
  );
}

Object.assign(window, { ChatScreen, AIHub, ManageScreen, EditPanel, ModelSelect });
