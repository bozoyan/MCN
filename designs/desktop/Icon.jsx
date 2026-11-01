// Phosphor icon — fetches the SVG once and inlines it. Phosphor SVGs use
// `currentColor` on the stroke, so colors just work through normal CSS.
const __ICON_CACHE = new Map();   // name -> Promise<string>
function loadIconSvg(name) {
  if (!__ICON_CACHE.has(name)) {
    __ICON_CACHE.set(
      name,
      fetch(`assets/icons/phosphor/${name}.svg`).then((r) => r.text())
    );
  }
  return __ICON_CACHE.get(name);
}

function Icon({ name, size = 16, color, style, className }) {
  const px = typeof size === "number" ? `${size}px` : size;
  const [svg, setSvg] = React.useState("");
  React.useEffect(() => {
    let active = true;
    loadIconSvg(name).then((s) => {
      if (!active) return;
      // Force the SVG to fill the span and inherit currentColor.
      const sized = s
        .replace(/<svg([^>]*?)width="[^"]*"/, "<svg$1")
        .replace(/<svg([^>]*?)height="[^"]*"/, "<svg$1")
        .replace(
          /<svg/,
          '<svg width="100%" height="100%" preserveAspectRatio="xMidYMid meet"'
        );
      setSvg(sized);
    });
    return () => {
      active = false;
    };
  }, [name]);

  return (
    <span
      className={"m-icon " + (className || "")}
      style={{
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        flex: "none",
        width: px,
        height: px,
        color: color || "currentColor",
        verticalAlign: "middle",
        lineHeight: 0,
        ...style,
      }}
      aria-hidden="true"
      dangerouslySetInnerHTML={{ __html: svg }}
    />
  );
}

// Reveric brand mark — rendered inline (no network) so the chrome titlebar
// can show it at any size.
function Mark({ size = 18, style }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 1024 1024"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      style={style}
      aria-hidden="true"
    >
      <g transform="translate(72.05 72.05) scale(.7)">
        <path d="M334 620C334 512 436 465 579 423C749 372 882 326 923 248V429C923 510 836 540 718 577C550 633 338 722 338 811C334 803 334 792 334 781Z" fill="#283B5E"/>
        <path d="M608 637C608 708 672 744 758 781C845 818 892 843 913 918C924 953 926 985 921 1009C862 949 744 935 626 925C507 915 415 891 415 816C415 752 490 691 608 637Z" fill="#8797D2"/>
      </g>
    </svg>
  );
}

Object.assign(window, { Icon, Mark });
