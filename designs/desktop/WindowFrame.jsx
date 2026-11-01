// macOS-style desktop window frame — traffic lights on the left, draggable
// titlebar inset. This matches DesktopWindowFrame from
// lib/desktop/widgets/desktop_window_frame.dart, which the Reveric app
// requires for every page root.
function WindowFrame({ children, title }) {
  return (
    <div className="reveric-window">
      <div className="reveric-titlebar">
        <div className="reveric-traffic">
          <span className="tl tl-close"></span>
          <span className="tl tl-min"></span>
          <span className="tl tl-zoom"></span>
        </div>
        <div className="reveric-titlebar-spacer"></div>
      </div>
      {children}
    </div>
  );
}

Object.assign(window, { WindowFrame });
