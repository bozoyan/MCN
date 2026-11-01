// NovelOverview — 系统·概览。镜像 Flutter
// lib/desktop/widgets/workspace/novel_overview.dart + hero.dart:
//   标题/状态/标签 → 继续写作 hero → 作品简介 + 创作片段便签 → 写作入口四卡。
// 由 EditorView 在 navActive === "overview" 时渲染进 .m-editor 主区。
// onSelectSection(navId) 复用 EditorView 的 handleNavSelect 做栏目跳转。

// 封面渐变(取自 LibraryView 的 COVER_BG;此处仅需 bg,故内联一份精简映射)。
const OV_COVER_BG = {
  ink: "linear-gradient(160deg, #3E524C 0%, #2D3A36 55%, #1C2623 100%)",
  mountains: "linear-gradient(180deg, #CDD6DB 0%, #7E8D99 60%, #3A4551 100%)",
  stars: "linear-gradient(180deg, #2B2834 0%, #4B4558 100%)",
  tree: "linear-gradient(160deg, #D3E0DA 0%, #6F9D8D 60%, #2E6656 100%)",
};

function OvStat({ label, value }) {
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
      <span style={{ fontSize: 12, color: "var(--text-muted)" }}>{label}</span>
      <span style={{ fontSize: 12, fontWeight: 600, color: "var(--text-primary)" }}>{value}</span>
    </span>
  );
}

function OvSecondaryAction({ icon, label, onClick }) {
  return (
    <button
      type="button"
      onClick={onClick}
      style={{
        display: "inline-flex", alignItems: "center", gap: 6,
        padding: "6px 12px", borderRadius: "var(--radius-button)",
        background: "color-mix(in srgb, var(--surface) 70%, transparent)",
        border: "1px solid var(--border-subtle)", cursor: "pointer",
        color: "var(--text-secondary)", font: "500 12px/1.3 var(--font-sans)",
      }}
    >
      <Icon name={icon} size={14} color="var(--text-muted)" />
      {label}
    </button>
  );
}

// 「继续写作」hero —— 上次写到的句子 + 继续写按钮 + 次要入口。
function OvContinueHero({ lastWroteLabel, lastSentence, continueLabel, onSelectSection }) {
  return (
    <div style={{
      position: "relative", overflow: "hidden",
      background: "var(--surface)", border: "1px solid var(--card-border)",
      boxShadow: "var(--shadow-card)", borderRadius: "var(--radius-2xl)", padding: 28,
    }}>
      {/* 装饰光晕 */}
      <div style={{
        position: "absolute", right: -40, top: -30, width: 240, height: 240,
        borderRadius: "50%", pointerEvents: "none",
        background: "radial-gradient(circle, color-mix(in srgb, var(--accent-amber) 18%, transparent) 0%, transparent 70%)",
      }} />
      <div style={{ position: "relative" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <Icon name="plant" size={18} color="var(--accent-warm)" />
          <span style={{ font: "600 13px/1.4 var(--font-sans)", color: "var(--accent-warm)" }}>继续写作</span>
        </div>
        <div style={{ marginTop: 16, fontSize: 12, color: "var(--text-muted)" }}>{lastWroteLabel}</div>
        <div style={{
          marginTop: 8, font: "700 22px/1.5 var(--font-serif)", color: "var(--text-primary)",
        }}>
          {lastSentence}
        </div>
        <div style={{ marginTop: 8, fontSize: 12, color: "var(--text-muted)" }}>
          慢慢写，让故事自然生长吧。
        </div>
        <div style={{ marginTop: 20, display: "flex", alignItems: "center", gap: 16, flexWrap: "wrap" }}>
          <button
            type="button"
            onClick={() => onSelectSection("chapters")}
            style={{
              display: "inline-flex", alignItems: "center", gap: 8,
              padding: "10px 20px", borderRadius: "var(--radius-button)", border: 0,
              background: "var(--accent)", color: "var(--on-accent)",
              font: "600 13px/1.4 var(--font-sans)", cursor: "pointer",
            }}
          >
            <Icon name="pencil-simple" size={16} />
            {continueLabel}
          </button>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <OvSecondaryAction icon="list" label="查看大纲" onClick={() => onSelectSection("outline")} />
            <OvSecondaryAction icon="globe" label="翻看设定" onClick={() => onSelectSection("world")} />
            <OvSecondaryAction icon="file-text" label="打开草稿" onClick={() => onSelectSection("chapters")} />
          </div>
        </div>
      </div>
    </div>
  );
}

// 作品简介卡 —— 封面缩略图 + 简介 + 统计条。
function OvProjectIntro({ novel, stats }) {
  return (
    <div style={{
      background: "var(--surface)", border: "1px solid var(--card-border)",
      boxShadow: "var(--shadow-card)", borderRadius: "var(--radius-2xl)", padding: 20,
    }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 12 }}>
        <Icon name="book-open" size={16} color="var(--accent-warm)" />
        <span style={{ font: "600 13px/1.4 var(--font-sans)", color: "var(--text-primary)", flex: 1 }}>作品简介</span>
        {novel.description && (
          <button className="m-icon-btn m-icon-btn--ghost" title="复制">
            <Icon name="copy" size={14} color="var(--text-muted)" />
          </button>
        )}
      </div>
      <div style={{ display: "flex", gap: 16 }}>
        <div style={{
          flex: "0 0 auto", width: 84, height: 116, borderRadius: "var(--radius-large)",
          background: OV_COVER_BG[novel.cover] || OV_COVER_BG.ink,
          border: "1px solid var(--border-subtle)",
        }} />
        <div style={{
          flex: 1, minWidth: 0, maxHeight: 116, overflow: "auto",
          font: "400 14px/1.7 var(--font-serif)", color: "var(--text-secondary)",
        }}>
          {novel.description || "暂无简介"}
        </div>
      </div>
      <div style={{
        marginTop: 16, padding: "8px 16px", borderRadius: "var(--radius-large)",
        background: "var(--surface)", border: "1px solid var(--border-subtle)",
        display: "flex", flexWrap: "wrap", gap: 20,
      }}>
        <OvStat label="章节" value={stats.chapters} />
        <OvStat label="设定" value={stats.settings} />
        <OvStat label="人物" value={stats.characters} />
        <OvStat label="伏笔" value={stats.notes} />
      </div>
    </div>
  );
}

// 便签卡片(带轻微旋转,呼应 Flutter 的 _StickyNoteCard)。
function OvStickyNote({ note, background, accent, angle }) {
  return (
    <div style={{
      flex: "1 1 180px", maxWidth: 240, minWidth: 160, height: 168,
      transform: `rotate(${angle}deg)`,
      padding: 16, borderRadius: "var(--radius-large)", background,
      boxShadow: "0 4px 12px color-mix(in srgb, var(--shadow-base) 6%, transparent)",
      display: "flex", flexDirection: "column",
    }}>
      <div style={{
        flex: 1, overflow: "hidden", font: "400 13px/1.5 var(--font-sans)", color: "var(--text-primary)",
        display: "-webkit-box", WebkitLineClamp: 4, WebkitBoxOrient: "vertical",
      }}>
        {note.body}
      </div>
      <div style={{
        marginTop: 8, textAlign: "right",
        font: "500 11px/1.3 var(--font-sans)", color: accent,
      }}>
        — {note.tag}
      </div>
    </div>
  );
}

// 创作片段 / 灵感便签。
function OvSnippets({ notes, onSelectSection }) {
  const palettes = [
    { bg: "color-mix(in srgb, var(--accent-amber) 18%, var(--surface))", tint: "var(--accent-amber)" },
    { bg: "color-mix(in srgb, var(--accent) 12%, var(--surface))", tint: "var(--accent)" },
    { bg: "color-mix(in srgb, var(--accent-warm) 16%, var(--surface))", tint: "var(--accent-warm)" },
  ];
  const angles = [-2.3, 1.1, -0.9];
  return (
    <div style={{
      background: "var(--surface)", border: "1px solid var(--card-border)",
      boxShadow: "var(--shadow-card)", borderRadius: "var(--radius-2xl)", padding: 20,
    }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 16 }}>
        <Icon name="sparkle" size={16} color="var(--accent-warm)" />
        <span style={{ font: "600 13px/1.4 var(--font-sans)", color: "var(--text-primary)", flex: 1 }}>
          创作片段 / 灵感便签
        </span>
        <button
          type="button"
          onClick={() => onSelectSection("foreshadowing")}
          style={{
            display: "inline-flex", alignItems: "center", gap: 2, padding: 4,
            background: "transparent", border: 0, cursor: "pointer",
            font: "500 12px/1.3 var(--font-sans)", color: "var(--accent-warm)",
          }}
        >
          查看更多
          <Icon name="caret-right" size={14} color="var(--accent-warm)" />
        </button>
      </div>
      <div style={{ display: "flex", gap: 12, justifyContent: "space-evenly", alignItems: "center" }}>
        {notes.map((n, i) => (
          <OvStickyNote
            key={i}
            note={n}
            background={palettes[i % palettes.length].bg}
            accent={palettes[i % palettes.length].tint}
            angle={angles[i % angles.length]}
          />
        ))}
      </div>
    </div>
  );
}

// 写作入口四卡。
function OvEntryCard({ spec, onClick }) {
  return (
    <button
      type="button"
      onClick={onClick}
      style={{
        textAlign: "left", cursor: "pointer", padding: 20,
        borderRadius: "var(--radius-2xl)", border: "1px solid var(--card-border)",
        background: `linear-gradient(135deg, color-mix(in srgb, ${spec.tint} 14%, transparent), color-mix(in srgb, ${spec.tint} 4%, transparent))`,
        display: "flex", flexDirection: "column", gap: 12,
      }}
    >
      <span style={{
        width: 36, height: 36, borderRadius: "var(--radius-large)",
        background: "color-mix(in srgb, var(--surface) 85%, transparent)",
        display: "inline-flex", alignItems: "center", justifyContent: "center",
      }}>
        <Icon name={spec.icon} size={20} color={spec.tint} />
      </span>
      <div style={{ font: "600 14px/1.4 var(--font-sans)", color: "var(--text-primary)" }}>{spec.title}</div>
      <div style={{
        font: "400 12px/1.5 var(--font-sans)", color: "var(--text-muted)",
        display: "-webkit-box", WebkitLineClamp: 2, WebkitBoxOrient: "vertical", overflow: "hidden",
      }}>
        {spec.hint}
      </div>
      <span style={{
        alignSelf: "flex-end", width: 28, height: 28, borderRadius: "50%",
        background: "color-mix(in srgb, var(--surface) 85%, transparent)",
        display: "inline-flex", alignItems: "center", justifyContent: "center",
      }}>
        <Icon name="arrow-right" size={14} color={spec.tint} />
      </span>
    </button>
  );
}

function OvWritingEntries({ onSelectSection }) {
  const entries = [
    { icon: "note-pencil", title: "正文创作", hint: "沉浸写作，流畅记录故事的每一步。", tint: "var(--accent-amber)", section: "chapters" },
    { icon: "globe", title: "设定", hint: "先约束规则、历史与势力，避免后续冲突。", tint: "var(--accent)", section: "world" },
    { icon: "list", title: "大纲与剧情", hint: "梳理故事脉络，安排冲突与转折。", tint: "var(--accent-warm)", section: "outline" },
    { icon: "users", title: "人物管理", hint: "塑造立体角色，记录人物关系与成长。", tint: "var(--accent)", section: "characters" },
  ];
  return (
    <div>
      <div style={{ font: "700 20px/1.3 var(--font-display)", letterSpacing: "-0.01em", color: "var(--text-primary)", marginBottom: 12 }}>
        写作入口
      </div>
      <div style={{
        display: "grid", gap: 12,
        gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))",
      }}>
        {entries.map((e) => (
          <OvEntryCard key={e.section} spec={e} onClick={() => onSelectSection(e.section)} />
        ))}
      </div>
    </div>
  );
}

function NovelOverview({ novel, onSelectSection }) {
  const D = window.REVERIC_DATA;
  const data = D.chapters[novel.id] || D.chapters.n1;
  const chapters = data.volumes.flatMap((v) => v.chapters);
  const totalChapters = chapters.length;
  const active = data.activeChapter;

  // 继续写作:latest = 章号最大的章;上次写到的句子取活动章正文末段。
  const latestNum = Math.max(...chapters.map((c) => parseInt(c.number, 10)));
  const activeNum = parseInt(active.number, 10);
  const continueLabel = `继续写第 ${latestNum} 章`;
  const lastWroteLabel =
    activeNum !== latestNum ? `你上次写到（第 ${activeNum} 章）：` : "你上次写到：";
  const body = active.body || [];
  const lastSentence = body.length > 0 ? body[body.length - 1] : "新章节空空如也，从一句话开始吧。";

  // 便签:活动章创作笔记(灵感) + 世界观条目(设定 / 角色关系)。
  const world = data.world || [];
  const notes = [
    { tag: "灵感", body: active.notes },
    world[0] && { tag: "设定", body: `${world[0].title} —— 漕运航道、税关与船帮势力分布，用于校验行船路线与时间线。` },
    world[2] && { tag: "角色关系", body: `${world[2].title} —— 船上六人的身份、诉求与彼此牵连，群像收束的底稿。` },
  ].filter(Boolean);

  const stats = {
    chapters: totalChapters,
    settings: world.length,
    characters: 6,
    notes: notes.length,
  };

  return (
    <div className="m-editor">
      {/* 顶部面包屑(概览无保存/历史等操作,对齐 _showsHeaderActions=false) */}
      <div style={{
        display: "flex", alignItems: "center", gap: 6, padding: "10px 24px",
        borderBottom: "1px solid var(--border-subtle)", flex: "0 0 auto",
        background: "var(--surface-container)",
      }}>
        <button className="m-icon-btn m-icon-btn--ghost" style={{ marginRight: 6 }} title="折叠章节侧栏">
          <Icon name="caret-left" size={14} />
        </button>
        <span style={{ fontSize: 13, color: "var(--text-secondary)" }}>{novel.title}</span>
        <Icon name="caret-right" size={12} style={{ opacity: 0.4 }} />
        <span style={{ fontSize: 13, fontWeight: 600, color: "var(--text-primary)" }}>概览</span>
      </div>

      <div style={{ flex: 1, minHeight: 0, overflow: "auto" }}>
        <div style={{
          maxWidth: 900, margin: "0 auto", padding: "32px 40px 80px",
          display: "flex", flexDirection: "column", gap: 24,
        }}>
          {/* 标题 + 状态 + 标签 */}
          <div>
            <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
              <div style={{ font: "700 28px/1.3 var(--font-display)", letterSpacing: "-0.02em", color: "var(--text-primary)" }}>{novel.title}</div>
              <button className="m-icon-btn m-icon-btn--ghost" title="编辑作品信息">
                <Icon name="pencil-simple" size={16} color="var(--text-muted)" />
              </button>
            </div>
            <div style={{ marginTop: 10, display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
              <span style={{
                display: "inline-flex", alignItems: "center", gap: 6, padding: "3px 10px",
                borderRadius: "var(--radius-pill)",
                background: "color-mix(in srgb, var(--accent-warm) 16%, transparent)",
                border: "1px solid color-mix(in srgb, var(--accent-warm) 50%, transparent)",
                font: "600 11px/1.3 var(--font-sans)", color: "var(--accent-warm)",
              }}>
                <span style={{ width: 6, height: 6, borderRadius: "50%", background: "var(--accent-warm)" }} />
                创作中
              </span>
              {(novel.tags || []).map((t) => (
                <span key={t} style={{
                  padding: "3px 10px", borderRadius: "var(--radius-pill)",
                  background: "var(--surface-container)", border: "1px solid var(--border-subtle)",
                  font: "400 11px/1.3 var(--font-sans)", color: "var(--text-secondary)",
                }}>
                  {t}
                </span>
              ))}
            </div>
          </div>

          <OvContinueHero
            lastWroteLabel={lastWroteLabel}
            lastSentence={lastSentence}
            continueLabel={continueLabel}
            onSelectSection={onSelectSection}
          />
          <OvProjectIntro novel={novel} stats={stats} />
          <OvSnippets notes={notes} onSelectSection={onSelectSection} />
          <OvWritingEntries onSelectSection={onSelectSection} />
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { NovelOverview, OV_COVER_BG });
