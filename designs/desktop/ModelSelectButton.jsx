// Compact model selector for chat composers — a small muted "model ⌄"
// button that opens an upward menu. Mirrors model_selector.dart
// ModelSelectorButton used at the bottom-right of composer.dart.
//
// Reasoning-capable models (model configuration includes reasoning-effort options)
// carry a per-model reasoning-effort choice: hover the model row and an
// effort submenu flies out to the side (right by default, auto-flips left
// when the docked panel leaves no room). Non-reasoning models select
// directly with no submenu.

// effort wire value -> zh label + one-line hint. Supported values:
// none / low / medium / high / xhigh / max.
const EFFORT_LABELS = {
  none: "关闭",
  low: "低",
  medium: "中",
  high: "高",
  xhigh: "极高",
  max: "最高",
};
const EFFORT_HINTS = {
  none: "不推理，直接作答",
  low: "更快、更省 token",
  medium: "速度与深度均衡",
  high: "更深入的推理",
  xhigh: "深度推理，较慢",
  max: "最强推理，最慢",
};

// `efforts` = the model's configured reasoning-effort levels, low→high order.
// Omitted = non-reasoning model.
const COMPOSER_MODELS = [
  { name: "mimo-v2.5 · 默认", provider: "自定义供应商", icon: "sparkle", efforts: ["low", "medium", "high"], defaultEffort: "medium" },
  { name: "DeepSeek-R1", provider: "DeepSeek", icon: "brain", efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "high" },
  { name: "Claude Sonnet 4.6", provider: "Anthropic", icon: "diamond", efforts: ["low", "medium", "high"], defaultEffort: "medium" },
  { name: "GPT-4o", provider: "OpenAI", icon: "robot" },
];

const SUBMENU_W = 208; // keep in sync with .m-cmodel__submenu width

// Small filled/empty bars conveying effort strength within a model's range.
function EffortBars({ total, level }) {
  return (
    <span className="m-cmodel__bars" aria-hidden="true">
      {Array.from({ length: total }).map((_, i) => (
        <span key={i} className={"m-cmodel__bar" + (i <= level ? " is-on" : "")} />
      ))}
    </span>
  );
}

function ComposerModelSelect({ initial }) {
  const match = COMPOSER_MODELS.find((m) => m.name === initial);
  const [selected, setSelected] = React.useState(match || COMPOSER_MODELS[0]);
  const [open, setOpen] = React.useState(false);
  // { index, flip } for the row whose effort submenu is showing.
  const [sub, setSub] = React.useState(null);
  // per-model effort choice, seeded from each model's default.
  const [effortByModel, setEffortByModel] = React.useState(() => {
    const m = {};
    COMPOSER_MODELS.forEach((mm) => {
      if (mm.efforts) m[mm.name] = mm.defaultEffort;
    });
    return m;
  });
  const ref = React.useRef(null);

  React.useEffect(() => {
    if (!open) return;
    const onDown = (e) => {
      if (ref.current && !ref.current.contains(e.target)) closeMenu();
    };
    document.addEventListener("mousedown", onDown);
    return () => document.removeEventListener("mousedown", onDown);
  }, [open]);

  const closeMenu = () => {
    setOpen(false);
    setSub(null);
  };

  const selectedEffort = selected.efforts ? effortByModel[selected.name] : null;

  const onHoverRow = (i, model, e) => {
    if (!model.efforts) {
      setSub(null);
      return;
    }
    // Open to the right; flip left when the submenu would overflow the viewport.
    const rect = e.currentTarget.getBoundingClientRect();
    const flip = rect.right + SUBMENU_W > window.innerWidth - 12;
    setSub({ index: i, flip });
  };

  const pickModel = (model) => {
    setSelected(model);
    closeMenu();
  };
  const pickEffort = (model, ef) => {
    setEffortByModel((p) => ({ ...p, [model.name]: ef }));
    setSelected(model);
    closeMenu();
  };

  return (
    <div className={"m-cmodel" + (open ? " is-open" : "")} ref={ref}>
      <button type="button" className="m-cmodel__btn" onClick={() => setOpen((o) => !o)}>
        <span className="m-cmodel__name">{selected.name}</span>
        {selectedEffort && (
          <span className="m-cmodel__effort-pill" title={"推理强度：" + EFFORT_LABELS[selectedEffort]}>
            <Icon name="lightning" size={11} />
            <span>{EFFORT_LABELS[selectedEffort]}</span>
          </span>
        )}
        <Icon name="caret-down" size={14} className="m-cmodel__caret" style={{ opacity: 0.6 }} />
      </button>
      {open && (
        <div className="m-cmodel__menu" role="menu" onMouseLeave={() => setSub(null)}>
          {COMPOSER_MODELS.map((m, i) => {
            const isSel = selected.name === m.name;
            const reasoning = !!m.efforts;
            const curEffort = reasoning ? effortByModel[m.name] : null;
            const showSub = reasoning && sub && sub.index === i;
            return (
              <div
                key={m.name}
                className={
                  "m-cmodel__item" +
                  (isSel ? " is-selected" : "") +
                  (reasoning ? " has-sub" : "") +
                  (showSub ? " is-hovered" : "")
                }
                role="menuitem"
                onMouseEnter={(e) => onHoverRow(i, m, e)}
                onClick={() => pickModel(m)}
              >
                <Icon name={m.icon} size={18} className="m-cmodel__item-icon" />
                <span className="m-cmodel__item-meta">
                  <span className="m-cmodel__item-name">{m.name}</span>
                  <span className="m-cmodel__item-provider">{m.provider}</span>
                </span>

                {reasoning ? (
                  <span className="m-cmodel__item-tail">
                    <span className="m-cmodel__effort-cur">{EFFORT_LABELS[curEffort]}</span>
                    <Icon name="caret-right" size={14} className="m-cmodel__sub-caret" />
                  </span>
                ) : (
                  isSel && <Icon name="check" size={18} className="m-cmodel__item-check" />
                )}

                {showSub && (
                  <div
                    className={"m-cmodel__submenu" + (sub.flip ? " is-flipped" : "")}
                    role="menu"
                    onClick={(e) => e.stopPropagation()}
                  >
                    <div className="m-cmodel__sub-head">
                      <Icon name="sliders-horizontal" size={13} />
                      <span>推理强度</span>
                    </div>
                    {m.efforts.map((ef, ei) => {
                      const on = curEffort === ef;
                      return (
                        <button
                          key={ef}
                          type="button"
                          className={"m-cmodel__sub-item" + (on ? " is-selected" : "")}
                          onClick={(e) => {
                            e.stopPropagation();
                            pickEffort(m, ef);
                          }}
                        >
                          <EffortBars total={m.efforts.length} level={ei} />
                          <span className="m-cmodel__sub-meta">
                            <span className="m-cmodel__sub-name">{EFFORT_LABELS[ef]}</span>
                            <span className="m-cmodel__sub-hint">{EFFORT_HINTS[ef]}</span>
                          </span>
                          {on && <Icon name="check" size={16} className="m-cmodel__item-check" />}
                        </button>
                      );
                    })}
                  </div>
                )}
              </div>
            );
          })}
          <div className="m-cmodel__divider" />
          <button type="button" className="m-cmodel__add" onClick={closeMenu}>
            添加模型
          </button>
        </div>
      )}
    </div>
  );
}

Object.assign(window, { ComposerModelSelect });
