// 职责: 提供 A2UI 调试预览与测试共用的固定样例（消息 + 模拟事件处理方）。
// 关联文件:
//   lib/shared/widgets/a2ui/preview/preview_panel.dart
//   lib/shared/widgets/a2ui/session.dart
//   test/shared/widgets/a2ui/components_test.dart

import '../session.dart';

/// 一个预览样例。样例内容模拟插件提供的界面描述，不参与本地化。
class A2uiSample {
  const A2uiSample({
    required this.id,
    required this.title,
    required this.messages,
    this.respond,
  });

  final String id;
  final String title;
  final List<Map<String, Object?>> messages;

  /// 模拟插件 action：返回数据更新。
  final Future<List<A2uiDataUpdate>> Function(A2uiActionEvent event)? respond;
}

Map<String, Object?> _create(
  List<Map<String, Object?>> components, {
  Map<String, Object?> dataModel = const {},
}) => {
  'version': a2uiProtocolVersion,
  'createSurface': {
    'surfaceId': 'sample',
    'components': components,
    'dataModel': dataModel,
  },
};

Map<String, Object?> _text(String id, Object text, {String? variant}) => {
  'id': id,
  'component': 'Text',
  'text': text,
  'variant': ?variant,
};

Map<String, Object?> _path(String path) => {'@path': path};

Map<String, Object?> _required(String path, String message) => {
  'condition': {
    '@call': 'required',
    'args': {'value': _path(path)},
  },
  'message': message,
};

/// 组件总览：首批组件各种变体。
final A2uiSample galleryA2uiSample = A2uiSample(
  id: 'gallery',
  title: 'Gallery / 组件总览',
  messages: [
    _create(
      dataModel: {
        'form': {
          'name': '',
          'age': '',
          'bio': '',
          'token': '',
          'genre': <String>[],
          'tags': <String>['悬疑'],
          'moods': <String>[],
          'agree': false,
          'notify': true,
        },
        'status': '尚未提交',
      },
      [
        {
          'id': 'root',
          'component': 'Column',
          'children': [
            'title',
            'intro',
            'display_card',
            'input_card',
            'actions',
            'status',
          ],
        },
        _text('title', '# 组件总览'),
        _text(
          'intro',
          '所有组件都包装 Reveric 设计系统组件。提交按钮在**必填项**填好前保持禁用。',
          variant: 'caption',
        ),
        {'id': 'display_card', 'component': 'Card', 'child': 'display'},
        {
          'id': 'display',
          'component': 'Column',
          'children': [
            'display_heading',
            'markdown',
            'divider',
            'icons',
            'loading',
          ],
        },
        _text('display_heading', '## 展示'),
        {
          'id': 'markdown',
          'component': 'Markdown',
          'text':
              '支持 **粗体**、`代码`、列表和链接：\n\n'
              '- 第一项\n- 第二项\n\n'
              '```js\nexport function apply(context) {}\n```',
        },
        {'id': 'divider', 'component': 'Divider'},
        {
          'id': 'icons',
          'component': 'Row',
          'children': [
            'icon_person',
            'icon_star',
            'icon_search',
            'icon_settings',
            'icon_warning',
          ],
        },
        {'id': 'icon_person', 'component': 'Icon', 'name': 'person'},
        {'id': 'icon_star', 'component': 'Icon', 'name': 'star'},
        {'id': 'icon_search', 'component': 'Icon', 'name': 'search'},
        {'id': 'icon_settings', 'component': 'Icon', 'name': 'settings'},
        {'id': 'icon_warning', 'component': 'Icon', 'name': 'warning'},
        {'id': 'loading', 'component': 'Loading', 'label': '正在加载人物…'},
        {'id': 'input_card', 'component': 'Card', 'child': 'inputs'},
        {
          'id': 'inputs',
          'component': 'Column',
          'children': [
            'input_heading',
            'name',
            'age_row',
            'bio',
            'token',
            'genre',
            'tags',
            'moods',
            'agree',
            'notify',
          ],
        },
        _text('input_heading', '## 输入'),
        {
          'id': 'name',
          'component': 'TextField',
          'label': '人物名称',
          'placeholder': '必填',
          'value': _path('/form/name'),
          'checks': [_required('/form/name', '请填写人物名称')],
        },
        {
          'id': 'age_row',
          'component': 'Row',
          'children': ['age', 'gap', 'name_echo'],
        },
        {
          'id': 'age',
          'component': 'TextField',
          'label': '年龄',
          'variant': 'number',
          'value': _path('/form/age'),
          'weight': 1,
        },
        {'id': 'gap', 'component': 'Gap', 'size': 'lg'},
        {
          'id': 'name_echo',
          'component': 'Text',
          'text': {
            '@call': 'formatString',
            'args': {'value': r'实时预览：${/form/name}'},
          },
          'weight': 1,
        },
        {
          'id': 'bio',
          'component': 'TextField',
          'label': '人物小传',
          'variant': 'longText',
          'value': _path('/form/bio'),
        },
        {
          'id': 'token',
          'component': 'TextField',
          'label': '访问令牌',
          'variant': 'obscured',
          'value': _path('/form/token'),
        },
        {
          'id': 'genre',
          'component': 'ChoicePicker',
          'label': '题材（单选）',
          'options': [
            {'label': '悬疑', 'value': 'mystery'},
            {'label': '科幻', 'value': 'scifi'},
            {'label': '武侠', 'value': 'wuxia'},
          ],
          'value': _path('/form/genre'),
          'checks': [_required('/form/genre', '请选择题材')],
        },
        {
          'id': 'tags',
          'component': 'ChoicePicker',
          'label': '标签（多选 chips）',
          'variant': 'multipleSelection',
          'displayStyle': 'chips',
          'options': [
            {'label': '悬疑', 'value': '悬疑'},
            {'label': '群像', 'value': '群像'},
            {'label': '成长', 'value': '成长'},
          ],
          'value': _path('/form/tags'),
        },
        {
          'id': 'moods',
          'component': 'ChoicePicker',
          'label': '基调（多选）',
          'variant': 'multipleSelection',
          'options': [
            {'label': '温暖', 'value': 'warm'},
            {'label': '冷峻', 'value': 'cold'},
          ],
          'value': _path('/form/moods'),
        },
        {
          'id': 'agree',
          'component': 'CheckBox',
          'label': '我已确认人物设定不与已有角色冲突',
          'value': _path('/form/agree'),
        },
        {
          'id': 'notify',
          'component': 'Switch',
          'label': '保存后通知我',
          'value': _path('/form/notify'),
        },
        {
          'id': 'actions',
          'component': 'Row',
          'children': ['submit', 'reset', 'more', 'link'],
        },
        _text('submit_label', '提交'),
        {
          'id': 'submit',
          'component': 'Button',
          'variant': 'primary',
          'child': 'submit_label',
          'checks': [
            _required('/form/name', '请填写人物名称'),
            _required('/form/genre', '请选择题材'),
          ],
          'action': {
            'event': {
              'name': 'submit',
              'context': {'form': _path('/form')},
            },
          },
        },
        _text('reset_label', '重置'),
        {
          'id': 'reset',
          'component': 'Button',
          'child': 'reset_label',
          'action': {
            'event': {'name': 'reset'},
          },
        },
        {'id': 'more_icon', 'component': 'Icon', 'name': 'moreHoriz'},
        {
          'id': 'more',
          'component': 'Button',
          'child': 'more_icon',
          'accessibility': {'label': '更多'},
          'action': {
            'event': {'name': 'more'},
          },
        },
        _text('link_label', '查看文档'),
        {
          'id': 'link',
          'component': 'Button',
          'variant': 'borderless',
          'child': 'link_label',
          'action': {
            'event': {'name': 'docs'},
          },
        },
        _text('status', _path('/status'), variant: 'caption'),
      ],
    ),
  ],
  respond: (event) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return switch (event.name) {
      'submit' => [
        A2uiDataUpdate(
          path: '/status',
          value: '已提交：${(event.context['form'] as Map?)?['name']}',
        ),
      ],
      'reset' => [
        const A2uiDataUpdate(
          path: '/form',
          value: {
            'name': '',
            'age': '',
            'bio': '',
            'token': '',
            'genre': <String>[],
            'tags': <String>[],
            'moods': <String>[],
            'agree': false,
            'notify': true,
          },
        ),
        const A2uiDataUpdate(path: '/status', value: '已重置'),
      ],
      _ => const [],
    };
  },
);

const _roles = ['主角', '配角', '反派', '导师'];

List<Map<String, Object?>> _characters(int count, {int seed = 0}) => [
  for (var i = 0; i < count; i++)
    {
      'name': '人物 ${i + 1 + seed}',
      'role': _roles[(i + seed) % _roles.length],
      'summary': '第 ${(i % 40) + 1} 章登场。',
    },
];

/// 模拟插件「人物整理」页面：数据模板列表、刷新与保存 action。
final A2uiSample characterOrganizerA2uiSample = A2uiSample(
  id: 'character_organizer',
  title: 'Character organizer / 人物整理',
  messages: [
    _create(
      dataModel: {
        'characters': _characters(6),
        'note': '',
        'status': '共 6 个人物',
      },
      [
        {
          'id': 'root',
          'component': 'Column',
          'children': ['header', 'note', 'character_list', 'status'],
        },
        {
          'id': 'header',
          'component': 'Row',
          'align': 'center',
          'children': ['heading', 'refresh'],
        },
        _text('heading', '## 人物整理'),
        _text('refresh_label', '刷新'),
        {
          'id': 'refresh',
          'component': 'Button',
          'child': 'refresh_label',
          'action': {
            'event': {'name': 'refresh'},
          },
        },
        {
          'id': 'note',
          'component': 'TextField',
          'label': '整理备注',
          'placeholder': '写下这次整理的想法',
          'value': _path('/note'),
        },
        {
          'id': 'character_list',
          'component': 'Column',
          'children': {'path': '/characters', 'componentId': 'character_card'},
        },
        {
          'id': 'character_card',
          'component': 'Card',
          'child': 'character_body',
        },
        {
          'id': 'character_body',
          'component': 'Row',
          'align': 'center',
          'children': ['character_text', 'character_save'],
        },
        {
          'id': 'character_text',
          'component': 'Column',
          'weight': 1,
          'children': ['character_name', 'character_summary'],
        },
        {
          'id': 'character_name',
          'component': 'Text',
          'text': {
            '@call': 'formatString',
            'args': {r'value': r'**${name}** · ${role}'},
          },
        },
        _text('character_summary', _path('summary'), variant: 'caption'),
        _text('character_save_label', '标记'),
        {
          'id': 'character_save',
          'component': 'Button',
          'variant': 'borderless',
          'child': 'character_save_label',
          'action': {
            'event': {
              'name': 'mark',
              'context': {'name': _path('name')},
            },
          },
        },
        _text('status', _path('/status'), variant: 'caption'),
      ],
    ),
  ],
  respond: (event) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    return switch (event.name) {
      'refresh' => [
        A2uiDataUpdate(path: '/characters', value: _characters(8, seed: 10)),
        const A2uiDataUpdate(path: '/status', value: '已刷新：共 8 个人物'),
      ],
      'mark' => [
        A2uiDataUpdate(path: '/status', value: '已标记 ${event.context['name']}'),
      ],
      _ => const [],
    };
  },
);

/// 长列表：根节点为 List，按需构建 300 个条目。
final A2uiSample longListA2uiSample = A2uiSample(
  id: 'long_list',
  title: 'Long list / 长列表',
  messages: [
    _create(
      dataModel: {'characters': _characters(300)},
      [
        {
          'id': 'root',
          'component': 'List',
          'children': {'path': '/characters', 'componentId': 'row'},
        },
        {
          'id': 'row',
          'component': 'Row',
          'align': 'center',
          'children': ['row_icon', 'row_name', 'row_role'],
        },
        {'id': 'row_icon', 'component': 'Icon', 'name': 'person'},
        _text('row_name', _path('name')),
        _text('row_role', _path('role'), variant: 'caption'),
      ],
    ),
  ],
);

/// 无效界面：引用了目录中不存在的组件，界面应显示局部错误。
final A2uiSample invalidA2uiSample = A2uiSample(
  id: 'invalid',
  title: 'Invalid / 无效界面',
  messages: [
    _create([
      {
        'id': 'root',
        'component': 'Column',
        'children': ['video'],
      },
      {'id': 'video', 'component': 'Video', 'url': 'https://example.com/a.mp4'},
    ]),
  ],
);

final List<A2uiSample> a2uiSamples = [
  galleryA2uiSample,
  characterOrganizerA2uiSample,
  longListA2uiSample,
  invalidA2uiSample,
];
