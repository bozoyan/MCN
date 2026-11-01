// 职责: 在异步流程结束后安全关闭当前页面，避免页面已被关闭时误关下层页面。
// 关联文件:
//   lib/mobile/pages/novel_chat_page.dart
//   lib/desktop/pages/novel_editor.dart

import 'package:flutter/widgets.dart';

/// 仅当 [context] 所在路由仍是栈顶时 pop；调用方在异步等待后先检查 `context.mounted`。
///
/// 异步等待（确认弹窗、暂停 AI）期间页面可能已被再次返回关闭；此时直接
/// `Navigator.pop` 会关掉下层页面，栈里没有 present route 时抛 `No element`。
void popIfRouteCurrent(BuildContext context) {
  if (ModalRoute.of(context)?.isCurrent == true) {
    Navigator.of(context).pop();
  }
}
