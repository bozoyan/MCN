// 职责: 流式增量的 UTF-16 边界缓冲 — 挂起悬空高代理，避免半个 emoji 进入渲染。
// 关联文件:
//   lib/shared/agent/agent.dart
//   lib/shared/agent/client/_sanitize.dart

/// 逐 delta 累积文本时的代理对边界缓冲。
///
/// provider 可能把一个 emoji 拆在两个 text delta 里（前一个 delta 以高代理结尾，
/// 后一个以低代理开头）。上层是裸拼接后立即渲染，拼接结果在两拍之间就带着落单
/// 代理，`ParagraphBuilder.addText` 会抛
/// `Invalid argument(s): string is not well-formed UTF-16`。
///
/// [take] 把尾部的悬空高代理留到下一拍，emoji 晚一个 delta 完整出现；既不崩，
/// 也不像直接替换成 U+FFFD 那样把字符永久损坏。
class SurrogateCarry {
  String _pending = '';

  /// 是否还挂着一个等待配对的高代理。
  bool get hasPending => _pending.isNotEmpty;

  /// 返回可安全下发的部分；尾部悬空高代理被扣下，留到下次调用时前置。
  String take(String delta) {
    if (delta.isEmpty && _pending.isEmpty) return '';
    final merged = _pending + delta;
    _pending = '';
    if (merged.isEmpty) return '';
    final last = merged.codeUnitAt(merged.length - 1);
    if (last >= 0xD800 && last <= 0xDBFF) {
      _pending = merged.substring(merged.length - 1);
      return merged.substring(0, merged.length - 1);
    }
    return merged;
  }

  /// 流结束时仍有挂起的高代理 —— 上游确实截断了，落 U+FFFD 而不是丢字符。
  String flush() {
    if (_pending.isEmpty) return '';
    _pending = '';
    return '�';
  }
}
