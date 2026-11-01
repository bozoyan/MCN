// 职责: 首次启动随机生成「AI 怎么称呼您」的默认称呼。
// 关联文件:
//   lib/shared/hooks/use_onboarding_setup.dart
import 'dart:math';
import 'dart:ui';

const _zhPrefixes = [
  '听雨',
  '晚风',
  '南山',
  '星河',
  '云间',
  '竹林',
  '墨池',
  '松间',
  '白露',
  '秋水',
  '青灯',
  '远山',
];
const _zhSuffixes = ['客', '君', '行者'];

const _enAdjectives = [
  'Quiet',
  'Wandering',
  'Midnight',
  'Silver',
  'Amber',
  'Distant',
  'Gentle',
  'Restless',
];
const _enNouns = ['Scribe', 'Dreamer', 'Wanderer', 'Quill', 'Poet'];

/// 按界面语言生成一个笔名式称呼，如「听雨客」「Midnight Scribe」。
String randomAiNickname(Locale locale, {Random? random}) {
  final rng = random ?? Random();
  T pick<T>(List<T> items) => items[rng.nextInt(items.length)];
  if (locale.languageCode.toLowerCase().startsWith('zh')) {
    return '${pick(_zhPrefixes)}${pick(_zhSuffixes)}';
  }
  return '${pick(_enAdjectives)} ${pick(_enNouns)}';
}
