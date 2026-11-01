// 职责: 提供小说分类的通用候选及起点男女频主分类。
// 关联文件:
//   lib/desktop/widgets/novel_form_dialog.dart
//   lib/shared/models/novel_form_fields.dart
//   lib/shared/widgets/novel/category_field.dart

// 平台原名作为业务数据保留中文，不随界面语言翻译。
// 来源（2026-09-26 核对）：https://www.qidian.com/all/
// https://www.qidian.com/mm/all/
const qidianNovelCategories = {
  'male': [
    '玄幻',
    '奇幻',
    '武侠',
    '仙侠',
    '都市',
    '现实',
    '军事',
    '历史',
    '游戏',
    '体育',
    '科幻',
    '诸天无限',
    '悬疑灵异',
    '轻小说',
    '短篇',
  ],
  'female': [
    '古代言情',
    '仙侠奇缘',
    '现代言情',
    '浪漫青春',
    '玄幻言情',
    '悬疑推理',
    '短篇',
    '科幻空间',
    '游戏竞技',
    '轻小说',
    '现实生活',
  ],
};

const novelCategorySuggestions = [
  '玄幻',
  '仙侠',
  '修真',
  '都市',
  '言情',
  '历史',
  '科幻',
  '悬疑',
  '推理',
  '恐怖',
  '武侠',
  '游戏',
  '现实',
  '轻小说',
  '军事',
  '体育',
  '同人',
  '种田',
  '穿越',
  '重生',
  '末世',
  '校园',
  '商战',
  '宫斗',
];
