// Chapter tree — left rail inside the novel editor.
// Mirrors lib/desktop/widgets/sidebar/chapter_tree.dart.

function ChapterTree({ chapters, activeId, onSelect }) {
  return (
    <div className="m-tree">
      <div className="m-tree__head">
        <div className="m-ui-tiny-section">章节</div>
        <div className="m-tree__head-actions">
          <button className="m-icon-btn m-icon-btn--ghost" title="新建章节">
            <Icon name="plus" size={14} />
          </button>
          <button className="m-icon-btn m-icon-btn--ghost" title="折叠全部">
            <Icon name="list" size={14} />
          </button>
        </div>
      </div>

      <div className="m-tree__scroll">
        {chapters.volumes.map((vol) => (
          <div key={vol.id} className="m-tree__vol">
            <button className="m-tree__vol-head" type="button">
              <Icon name="caret-down" size={12} />
              <Icon name="books" size={14} />
              <span>{vol.title}</span>
            </button>
            <div className="m-tree__vol-list">
              {vol.chapters.map((c) => (
                <button
                  key={c.id}
                  type="button"
                  onClick={() => onSelect(c.id)}
                  className={
                    "m-tree__chapter" + (c.id === activeId ? " is-active" : "")
                  }
                >
                  <span className="m-tree__chapter-num">{c.number}</span>
                  <span className="m-tree__chapter-title">{c.title}</span>
                  <span className={`m-state m-state--${c.state}`}>{c.state}</span>
                </button>
              ))}
            </div>
          </div>
        ))}

        <div className="m-tree__sep" />
        <div className="m-tree__world">
          <div className="m-ui-tiny-section">设定</div>
          {chapters.world.map((w) => (
            <button key={w.id} type="button" className="m-tree__world-row">
              <Icon name={w.icon} size={14} />
              <span>{w.title}</span>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { ChapterTree });
