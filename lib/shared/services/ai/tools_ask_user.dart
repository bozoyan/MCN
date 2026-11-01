// 职责: AskUser 工具实现 — 允许 AI 向用户提问并等待回复
// 关联文件:
//   lib/shared/agent/tools.dart
//   lib/shared/models/ask_user_models.dart
//   lib/shared/models/ai_message_block.dart
//   lib/desktop/widgets/ai/chat/panel.dart
// ignore_for_file: use_null_aware_elements
part of 'tools.dart';

const _askUserInputSchema = {
  'type': 'object',
  'properties': {
    'questions': {
      'type': 'array',
      'description': '问题列表。只问一个问题时也用数组。',
      'items': {
        'type': 'object',
        'properties': {
          'id': {'type': 'string', 'description': '问题的稳定标识符，方便读取返回的 answers'},
          'question': {'type': 'string', 'description': '问题内容'},
          'options': {
            'type': 'array',
            'description': '可选项列表。提供后用户可从中选择。',
            'items': {
              'type': 'object',
              'properties': {
                'label': {'type': 'string', 'description': '选项标签'},
                'description': {'type': 'string', 'description': '选项描述（可选）'},
                'recommended': {
                  'type': 'boolean',
                  'description': '是否推荐此选项（可选）',
                },
              },
              'required': ['label'],
            },
          },
          'allow_free_text': {
            'type': 'boolean',
            'description': '是否允许用户自由输入自定义回复，默认 true',
          },
          'multi_select': {
            'type': 'boolean',
            'description':
                '是否允许多选，默认 false。true 时返回的 selected_options 含全部选中的 label。',
          },
        },
        'required': ['question'],
      },
    },
  },
  'required': ['questions'],
};

// AskUser 工具描述
const String _askUserDescription = '''向用户提问并等待回复。

把选项放进本工具的 options，详情写进每个选项的 description；不要在聊天正文用编号列表罗列多个方向、再问「你倾向哪个」。

写法要求：
- 选项的 label 一眼能分辨，description 说清选它意味着什么，不要只是把 label 换个说法。
- 确认类问题给安全的那一项标 recommended: true。
- 用户可能有你没列到的想法时保持 allow_free_text 默认开启；只有选项确实穷尽了取值才关掉。
- 要用户一次挑出多项时（「哪几条线索保留」「同时改哪几章」）设 multi_select: true。

返回 answers 数组，每项含 question_id、selected_options（选中的 label 列表，单选也是列表）、answer（用户自由输入的文本）。按 question_id 对回问题，不要按顺序假定。

示例：
{
  "questions": [
    {
      "id": "crossover_hook",
      "question": "你更倾向哪种穿越设定？选定后我再写具体段落。",
      "options": [
        {
          "label": "系统崩溃穿越",
          "description": "诱因是写作平台崩溃；乱码与穿越后要做的 AI 工具形成因果闭环。"
        },
        {
          "label": "断更穿越",
          "description": "因断更收到神秘私信；「回去填坑」比「回去发财」更有张力。"
        }
      ]
    }
  ]
}''';
