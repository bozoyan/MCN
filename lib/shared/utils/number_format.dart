/// 首页作品卡片字数：中文统一为「万」为单位，英文沿用 [formatCompactWordCount]。
String formatHomeNovelWordCount(int count, {required String languageCode}) {
  final normalizedLanguageCode = languageCode.toLowerCase();
  if (normalizedLanguageCode.startsWith('zh')) {
    return _formatCompactValue(count / 10000);
  }
  return formatCompactWordCount(count, languageCode: languageCode);
}

String formatCompactWordCount(int count, {required String languageCode}) {
  if (count < 1000) {
    return '$count';
  }

  final normalizedLanguageCode = languageCode.toLowerCase();
  final isChinese = normalizedLanguageCode.startsWith('zh');

  if (isChinese) {
    if (count >= 10000) {
      return '${_formatCompactValue(count / 10000)}万';
    }
    return '${_formatCompactValue(count / 1000)}千';
  }

  if (count >= 1000000) {
    return '${_formatCompactValue(count / 1000000)}m';
  }
  return '${_formatCompactValue(count / 1000)}k';
}

String _formatCompactValue(double value) {
  final rounded = value.toStringAsFixed(1);
  return rounded.endsWith('.0')
      ? rounded.substring(0, rounded.length - 2)
      : rounded;
}

/// 中文序号数字（1 到 9999）；其余数值保留阿拉伯数字。
String formatChineseNumber(int value) {
  if (value <= 0) {
    return value.toString();
  }
  if (value >= 10000) {
    return value.toString();
  }

  const digits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
  const divisors = [1000, 100, 10, 1];
  const units = ['千', '百', '十', ''];
  final result = StringBuffer();
  var remaining = value;
  var needsZero = false;

  for (var index = 0; index < divisors.length; index++) {
    final divisor = divisors[index];
    final digit = remaining ~/ divisor;
    remaining %= divisor;
    if (digit == 0) {
      if (result.isNotEmpty && remaining > 0) {
        needsZero = true;
      }
    } else {
      if (needsZero) {
        result.write(digits[0]);
        needsZero = false;
      }
      result.write('${digits[digit]}${units[index]}');
    }
  }

  final text = result.toString();
  return text.startsWith('一十') ? text.substring(1) : text;
}
