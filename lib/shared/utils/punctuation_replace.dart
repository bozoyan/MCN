// 职责: 章节复制前的标点替换规则模型与纯函数应用。
// 关联文件:
//   lib/shared/providers/chapter_copy_replace_rules_provider.dart
//   lib/shared/widgets/chapter_copy_replace_panel.dart

/// 单条标点替换规则：把正文中的 [from] 替换为 [to]。
class PunctuationReplaceRule {
  const PunctuationReplaceRule({required this.from, required this.to});

  final String from;
  final String to;

  Map<String, dynamic> toJson() => {'from': from, 'to': to};

  factory PunctuationReplaceRule.fromJson(Map<String, dynamic> json) {
    return PunctuationReplaceRule(
      from: json['from'] as String? ?? '',
      to: json['to'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PunctuationReplaceRule &&
        other.from == from &&
        other.to == to;
  }

  @override
  int get hashCode => Object.hash(from, to);
}

/// 首次使用时的默认规则（直引号转弯引号、半角标点转全角）。
const List<PunctuationReplaceRule> defaultPunctuationReplaceRules = [
  PunctuationReplaceRule(from: '"', to: '“”'),
  PunctuationReplaceRule(from: ':', to: '：'),
  PunctuationReplaceRule(from: '!', to: '！'),
  PunctuationReplaceRule(from: '?', to: '？'),
];

/// 按顺序应用规则。默认英文双引号规则会按左右引号交替替换。
String applyPunctuationReplace(
  String text,
  List<PunctuationReplaceRule> rules,
) {
  if (text.isEmpty || rules.isEmpty) {
    return text;
  }
  var result = text;
  for (final rule in rules) {
    if (rule.from.isEmpty) {
      continue;
    }
    result = _applySingleRule(result, rule);
  }
  return result;
}

String _applySingleRule(String text, PunctuationReplaceRule rule) {
  if (_isDefaultQuotationRule(rule)) {
    final open = rule.to[0];
    final close = rule.to[1];
    final from = rule.from;
    final buffer = StringBuffer();
    var useOpen = true;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == from) {
        buffer.write(useOpen ? open : close);
        useOpen = !useOpen;
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }
  return text.replaceAll(rule.from, rule.to);
}

bool _isDefaultQuotationRule(PunctuationReplaceRule rule) =>
    rule.from == '"' && rule.to == '“”';
