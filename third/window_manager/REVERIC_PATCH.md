# Reveric patch

This is `window_manager` 0.5.2 with one Windows compatibility patch for
Flutter's native multi-window support.

`WindowManagerPlugin::HandleWindowProc` is registered as a top-level window
procedure delegate. In a multi-window engine Flutter invokes that delegate for
secondary windows too, while the plugin state belongs only to the main window.
The patch ignores messages from other top-level window handles so the main
window's hidden-title-bar configuration cannot remove a secondary window's
native frame during resize or maximize.
