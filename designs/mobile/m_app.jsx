/* ============================================================
   App shell — 底部 3 tab + 全屏导航栈（push/pop overlay）
   tabs: 作品 / AI / 设置。原首页和书架合成「作品」：继续写、最近在作品库上方。
   作品工作区、章节编辑器、聊天、管理与编辑等以全屏 overlay 推入。
   ============================================================ */

function TabBar({tab, setTab}){
  const tabs = [
    {k:'library', label:'作品', icon:I.books},
    {k:'ai', label:'AI', icon:I.spark},
    {k:'settings', label:'设置', icon:I.gear},
  ];
  return (
    <div className="tabbar">
      {tabs.map(t=>{
        const Icon = t.icon; const active = tab===t.k || (t.k==='library' && tab!=='ai' && tab!=='settings');
        return (
          <div key={t.k} className={"tab press"+(active?' active':'')} onClick={()=>setTab(t.k)}>
            <Icon s={24} sw={active?2:1.6}/>
            <span>{t.label}</span>
          </div>
        );
      })}
    </div>
  );
}

// ?screen=usage 直接落到该页，方便单独看这一屏；?screen=locationDetail&id=lo2 落到地点详情。
const DEEP_SCREEN = new URLSearchParams(window.location.search).get('screen');

function App(){
  // ?tab=ai|settings 直接落到对应 tab；?screen=collection&id=<集合 id> 落到作品 tab 并选中该集合（集合不再有单独页面）。
  const DEEP_QS = new URLSearchParams(window.location.search);
  const DEEP_COLLECTION = DEEP_SCREEN==='collection' ? DEEP_QS.get('id') : null;
  const [tab, setTab] = useState(DEEP_COLLECTION ? 'library' : DEEP_QS.get('tab') || (DEEP_SCREEN ? 'settings' : 'library'));
  const [stack, setStack] = useState(DEEP_SCREEN && !DEEP_COLLECTION ? [{t: DEEP_SCREEN, id: DEEP_QS.get('id'), novel: DEEP_SCREEN==='workspace' ? NOVELS[0] : undefined,
    section: DEEP_QS.get('section'), state: DEEP_QS.get('state'), sheet: DEEP_QS.get('sheet')}] : []); // array of route objects

  const push = (route)=> setStack(s=>[...s, route]);
  const pop = ()=> setStack(s=>s.slice(0,-1));

  const openNovel = (novel)=> push({t:'workspace', novel});

  // 打开章节编辑器（c3 用 ACTIVE_CHAPTER，其余给占位正文）。
  const openChapter = (novel, ch)=> push({
    t:'editor', novel,
    chapter: ch.id==='c3' ? ACTIVE_CHAPTER : {...ch, summary:'（本章大纲待补充）', body:['（开始写作本章…）']},
  });

  // current novel for chat context (best-effort from stack)
  const currentNovel = [...stack].reverse().find(r=>r.novel)?.novel || NOVELS[0];

  // 打开某类内容实体的详情页（图鉴四类/设定/伏笔/大纲/地图/素材）
  const openEntity = (kind, entity, novel)=>{
    switch(kind){
      case 'world':                       return push({t:'worldDetail', entity});
      case 'item': case 'faction': case 'creature': case 'skill':
                                          return push({t:'entityDetail', kind, entity});
      case 'foreshadow':                  return push({t:'foreshadowDetail', entity});
      case 'outline':                     return push({t:'outlineDetail', entity, novel:novel||currentNovel});
      case 'location':                    return push({t:'locationDetail', entity});
      case 'material':                    return push({t:'materialDetail', entity});
      case 'character':                   return push({t:'charDetail', entity, novel:novel||currentNovel});
      default: return null;
    }
  };

  // 交叉引用跳转：{kind,id} → 解析为实体后打开对应详情（chapter → 章节编辑器）
  const openRef = (ref)=>{
    if(ref.kind==='chapter'){
      for(const v of VOLUMES){ const ch = v.items.find(c=>c.id===ref.id); if(ch){ openChapter(currentNovel, ch); return; } }
      return;
    }
    const lookup = {world:WORLD, item:ITEMS, faction:FACTIONS, creature:CREATURES,
      foreshadow:FORESHADOW, location:LOCATIONS, character:CHARACTERS}[ref.kind];
    const entity = lookup && lookup.find(x=>x.id===ref.id);
    if(entity) openEntity(ref.kind, entity);
  };

  // root content per tab
  let root;
  // 未知 tab（含旧深链 ?tab=home / ?tab=library）都落到作品 tab。
  if(tab==='ai'){
    root = <AIHub
      onOpenChat={(mk)=>push({t:'chat', modeKey:mk, novel:NOVELS[0]})}
      onOpenMode={(mk)=>push({t:'chat', modeKey:mk, novel:NOVELS[0]})}
      onOpenManage={(kind)=> kind==='skills' ? push({t:'agentSkills', home:true}) : push({t:'manage', kind})}/>;
  } else if(tab==='settings'){
    root = <SettingsScreen onOpen={(kind)=>push({t:kind})}/>;
  } else {
    // 继续写：小说直接进上次写到的章节，剧本进剧本工作台（工作台自己恢复到当前季 / 场）。
    root = <LibraryScreen onOpenNovel={openNovel} onOpenScreenplay={(p)=>push({t:'screenplay', proj:p})}
      onContinue={(w)=> w.proj ? push({t:'screenplay', proj:w.proj}) : openChapter(w, {id:'c3', n:'03'})}
      initialCollection={DEEP_COLLECTION}/>;
  }

  // top overlay route
  const renderRoute = (r)=>{
    switch(r.t){
      case 'workspace':
        return <WorkspaceScreen novel={r.novel} onExit={pop}
          onOpenChat={()=>push({t:'chat', modeKey:'chat', novel:r.novel})}
          onOpenChapter={(ch)=>openChapter(r.novel, ch)}
          onOpenCharDetail={(e)=>push({t:'charDetail', entity:e, novel:r.novel})}
          onOpenEntity={(kind, e)=>openEntity(kind, e, r.novel)}
          onEditNovel={()=>{}}
          onOpenAgentRules={()=>push({t:'novelRules'})}
          onOpenAgentSkills={()=>push({t:'agentSkills', novel:r.novel})}
          onOpenMapStudio={(w)=>push({t:'mapStudio', world:w})}
          initialSection={r.section}/>;
      // 地图工作台：?screen=mapStudio&state=selected|generating|empty|review&sheet=designer|history|places
      case 'mapStudio':
        return <MapStudioScreen world={r.world} initialState={r.state} initialSheet={r.sheet} onBack={pop}
          onEditLocation={(p)=>{ const lo = LOCATIONS.find(x=>x.name===p.name); if(lo) push({t:'locationDetail', entity:lo}); }}/>;
      case 'editor':
        return <EditorScreen novel={r.novel} chapter={r.chapter} onBack={pop}
          onOpenChat={()=>push({t:'chat', modeKey:'chat', novel:r.novel})}/>;
      case 'charDetail':  return <CharacterDetail entity={r.entity} onBack={pop} onOpenChat={()=>push({t:'chat', modeKey:'chat', novel:r.novel})}/>;
      case 'worldDetail': return <WorldDetail entity={r.entity} onBack={pop} onOpenRef={openRef} onOpenChat={()=>push({t:'chat', modeKey:'chat', novel:currentNovel})}/>;
      case 'entityDetail':return <EntityDetail kind={r.kind} entity={r.entity} onBack={pop} onOpenRef={openRef} onOpenChat={()=>push({t:'chat', modeKey:'chat', novel:currentNovel})}/>;
      case 'foreshadowDetail': return <ForeshadowDetail entity={r.entity} onBack={pop} onOpenRef={openRef} onOpenChat={()=>push({t:'chat', modeKey:'chat', novel:currentNovel})}/>;
      case 'outlineDetail':return <OutlineDetail entity={r.entity} onBack={pop} onOpenChat={()=>push({t:'chat', modeKey:'chat', novel:r.novel||currentNovel})}/>;
      case 'locationDetail': return <LocationDetail entity={r.entity || LOCATIONS.find(x=>x.id===r.id) || LOCATIONS[0]} onBack={pop} onOpenRef={openRef} onOpenChat={()=>push({t:'chat', modeKey:'chat', novel:currentNovel})}/>;
      case 'materialDetail': return <MaterialDetail entity={r.entity} onBack={pop} onOpenRef={openRef} onOpenChat={()=>push({t:'chat', modeKey:'chat', novel:currentNovel})}/>;
      case 'chat':        return <ChatScreen modeKey={r.modeKey} novelTitle={(r.novel||currentNovel).title} onBack={pop}/>;
      // 剧本工作台（作品库里的剧本卡片进入），外壳与分区见 m_screenplay.jsx
      case 'screenplay':  return <SpWorkspaceScreen proj={r.proj} onBack={pop}/>;
      case 'manage':      return <ManageScreen kind={r.kind} onBack={pop} onOpenEdit={(kind,e)=>push({t:'edit', kind, entity:e})}/>;
      case 'edit':        return <EditPanel kind={r.kind} entity={r.entity} onBack={pop}/>;
      case 'providers':   return <ProvidersScreen onBack={pop}/>;
      case 'usage':       return <UsageScreen onBack={pop}/>;
      case 'language':    return <LanguageDetail onBack={pop}/>;
      case 'appearance':  return <AppearanceDetail onBack={pop}/>;
      case 'editorSettings': return <EditorDetail onBack={pop}/>;
      case 'novelRules':  return <NovelAgentRulesScreen onBack={pop} onOpenEdit={(e)=>push({t:'novelRuleEdit', entity:e})}/>;
      case 'novelRuleEdit': return <NovelAgentRuleEditScreen entity={r.entity} onBack={pop}/>;
      case 'novelSkills': return <NovelAgentSkillsScreen onBack={pop} onOpenEdit={(e)=>push({t:'novelSkillEdit', entity:e})}/>;
      case 'novelSkillEdit': return <NovelAgentSkillEditScreen entity={r.entity} onBack={pop}/>;
      case 'agentSkills': return <SkillSetupScreen novel={r.novel} home={r.home} onBack={pop}/>;
      default:            return null;
    }
  };

  const top = stack[stack.length-1];

  return (
    <div className="stage">
      <div className="device">
        <div className="notch"></div>
        <StatusBar/>
        {top ? (
          <div className="slide-in" style={{position:'absolute', inset:0, zIndex:10}}>{renderRoute(top)}</div>
        ) : (
          <div style={{position:'absolute', inset:0, display:'flex', flexDirection:'column'}}>
            <div style={{flex:1, position:'relative', minHeight:0}}>{root}</div>
            <TabBar tab={tab} setTab={setTab}/>
          </div>
        )}
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
