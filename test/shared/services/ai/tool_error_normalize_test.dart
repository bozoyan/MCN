// 职责: 验证工具失败结果归一化与匿名诊断输入清洗
// 关联文件:
//   lib/shared/services/ai/tool_error_normalize.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/ai/tool_error_normalize.dart';

void main() {
  group('collectionFromToolPath', () {
    test('extracts first segment and agents_rules', () {
      expect(collectionFromToolPath('/chapters/abc/title'), 'chapters');
      expect(collectionFromToolPath('/.agents/rules/foo'), 'agents_rules');
      expect(collectionFromToolPath('/'), isNull);
    });
  });

  group('inferEnumField', () {
    test('maps Invalid field labels to enum_field', () {
      expect(
        inferEnumField('Invalid novel status: "连载". Valid values...'),
        'novel_status',
      );
      expect(inferEnumField('Invalid character role: "主角".'), 'character_role');
      expect(inferEnumField('Invalid entity type: "npc".'), 'entity_type');
      expect(inferEnumField('Chapter not found: abc'), isNull);
    });
  });

  group('normalizeToolFailureResult', () {
    test('keeps an explicit error_code and fills collection', () {
      final normalized = normalizeToolFailureResult({
        'error': 'Chapter not found: abc',
        'error_code': ToolErrorCode.not_found.name,
        'path': '/chapters/abc',
      });
      expect(normalized['ok'], isFalse);
      expect(normalized['error_code'], 'not_found');
      expect(normalized['collection'], 'chapters');
    });

    test('does not guess a category from bare error text', () {
      // 文案只给模型看；没有显式 error_code 的失败一律归 internal。
      final normalized = normalizeToolFailureResult({
        'error': 'Unknown chapter field: foo',
        'path': '/chapters/abc/foo',
      });
      expect(normalized['error_code'], 'internal');
      expect(normalized['collection'], 'chapters');
    });

    test('infers enum_field without changing the category', () {
      final normalized = normalizeToolFailureResult({
        'error': 'Invalid novel status: "bad". Valid values...',
        'error_code': ToolErrorCode.invalid_argument.name,
        'path': '/novel/status',
      });
      expect(normalized['error_code'], 'invalid_argument');
      expect(normalized['enum_field'], 'novel_status');
      expect(normalized['collection'], 'novel');
    });

    test('uses input path when result has no path', () {
      final normalized = normalizeToolFailureResult(
        {'error': 'Not found: x', 'error_code': ToolErrorCode.not_found.name},
        input: {'path': '/outlines/main'},
      );
      expect(normalized['error_code'], 'not_found');
      expect(normalized['collection'], 'outlines');
    });

    test(
      'classifies legacy, unchanged and control-flow payloads consistently',
      () {
        for (final raw in <Map<String, dynamic>>[
          {'updated': false},
          {'created': true},
          {'error': ''},
          {
            'content': {
              'ok': false,
              'error': 'business text',
              'cancelled': true,
            },
          },
          {
            'exit_code': 3,
            'results': [
              {'ok': false},
            ],
          },
        ]) {
          final normalized = normalizeToolFailureResult(raw);
          expect(normalized['ok'], isTrue);
          expect(toolResultIsSuccess(normalized), isTrue);
          for (final entry in raw.entries) {
            expect(normalized[entry.key], entry.value);
          }
        }
        for (final raw in <Map<String, dynamic>>[
          {'ok': false},
          {'ok': true, 'error': 'failed'},
          {'cancelled': true},
          {'skipped': true},
          {'rejected': true},
        ]) {
          final normalized = normalizeToolFailureResult(raw);
          expect(normalized['ok'], isFalse);
          expect(toolResultIsSuccess(normalized), isFalse);
        }
      },
    );

    test('leaves success untouched', () {
      final ok = {'ok': true, 'content': 'hi'};
      expect(normalizeToolFailureResult(ok), same(ok));
    });

    test('classifies cancellation as normal control flow', () {
      final normalized = normalizeToolFailureResult({
        'ok': false,
        'cancelled': true,
      });

      expect(normalized, {
        'ok': false,
        'cancelled': true,
        'error': 'User cancelled',
        'error_code': 'user_cancelled',
      });
    });

    test('preserves a more specific cancellation code', () {
      final normalized = normalizeToolFailureResult({
        'ok': false,
        'cancelled': true,
        'error_code': 'login_cancelled',
      });

      expect(normalized['error_code'], 'login_cancelled');
    });
  });

  group('sanitizeToolInput', () {
    test(
      'Write reports bounded shapes, never values or a raw resource path',
      () {
        final encoded = sanitizeToolInput(
          'Write',
          {
            'path': '/chapters/private-id/outline',
            'value': null,
            'fields': {
              'outline': '',
              'content': 'private body',
              'events': [
                {'text': 'nested private body'},
              ],
              'private field name': 'secret',
              for (var i = 0; i < 100; i++) 'extra_$i': 'secret',
            },
          },
          result: {
            'missing_fields': ['outline'],
            'required_fields': ['outline'],
          },
        );
        final input = jsonDecode(encoded);
        expect(input['fields_shape'], 'object');
        expect(input['value_shape'], 'null');
        expect(input['field_shapes']['outline'], 'empty_string');
        expect(input['field_shapes']['content'], 'string');
        expect(input['field_shapes']['events'], 'array');
        expect(input['field_names'], hasLength(32));
        expect(input['field_count'], 104);
        expect(input['missing_fields'], ['outline']);
        expect(input['required_fields'], ['outline']);
        for (final private in [
          'private-id',
          'private body',
          'private field name',
          'secret',
        ]) {
          expect(encoded, isNot(contains(private)));
        }
        expect(encoded.length, lessThan(2500));
      },
    );

    test(
      'Write distinguishes omitted, null and malformed field containers',
      () {
        for (final (arguments, expected) in <(Map<String, dynamic>, String)>[
          ({}, 'absent'),
          ({'fields': null}, 'null'),
          ({'fields': 'private JSON text'}, 'string'),
          ({'fields': []}, 'array'),
          ({'fields': {}}, 'object'),
        ]) {
          final encoded = sanitizeToolInput('Write', arguments);
          expect(jsonDecode(encoded)['fields_shape'], expected);
          expect(encoded, isNot(contains('private JSON text')));
        }
      },
    );

    test('Edit result diagnostics use a typed allowlist', () {
      final encoded = sanitizeToolInput(
        'Edit',
        {
          'path': '/chapters/chp_x/content',
          'old_text': 'private old body',
          'new_text': 'private new body',
        },
        result: {
          '_metadata': {
            'edit_diagnostics': {
              'match_reason': 'no_matching_anchor',
              'source_length': 100,
              'old_text_length': 'private body',
              'divergence_offset': -1,
              'source': 'private body',
              'fingerprint': 'private hash',
            },
          },
        },
      );
      expect(jsonDecode(encoded), {
        'collection': 'chapters',
        'field': 'content',
        'path': '/chapters/chp_x/content',
        'match_reason': 'no_matching_anchor',
        'source_length': 100,
      });
      expect(encoded, isNot(contains('private')));
    });

    test('keeps AgentSkill canonical name but drops unrelated input', () {
      final input = jsonDecode(
        sanitizeToolInput('AgentSkill', {
          'name': 'outline-review',
          'secret': 'do not upload',
        }),
      );

      expect(input, {'agent_skill_name': 'outline-review'});
    });

    test('keeps legacy AgentSkill aliases in diagnostics', () {
      expect(
        jsonDecode(
          sanitizeToolInput('AgentSkill', {'agent_skill_name': 'legacy'}),
        ),
        {'agent_skill_name': 'legacy'},
      );
      expect(
        jsonDecode(sanitizeToolInput('AgentSkill', {'skill': 'fallback'})),
        {'agent_skill_name': 'fallback'},
      );
    });

    test('keeps Create path and field values for failure diagnostics', () {
      final input = jsonDecode(
        sanitizeToolInput('Create', {
          'path': '/materials/私密资料',
          'fields': {'title': '用户标题', 'status': 'draft'},
        }),
      );

      expect(input, {
        'collection': 'materials',
        'path': '/materials/私密资料',
        'top_level_keys': ['path', 'fields'],
        'fields_shape': 'object',
        'field_names': ['title', 'status'],
        'fields': {'title': '用户标题', 'status': 'draft'},
      });
    });

    test('distinguishes missing fields from flat arguments', () {
      // missing_required_fields 时仅凭 field_names 无法区分「完全没传 fields」
      // 与「传了被 schema 忽略的扁平字段」；top_level_keys 保留入参形状。
      final missing = jsonDecode(
        sanitizeToolInput('Create', {'path': '/characters'}),
      );
      expect(missing['top_level_keys'], ['path']);
      expect(missing['fields_shape'], 'absent');
      expect(missing['field_names'], isEmpty);

      final flat =
          jsonDecode(
                sanitizeToolInput('Create', {
                  'path': '/characters',
                  'name': 'flat field',
                  'fields': 'not an object',
                }),
              )
              as Map<String, dynamic>;
      expect(flat['top_level_keys'], ['path', 'name', 'fields']);
      expect(flat['fields_shape'], 'string');
      expect(flat['field_names'], isEmpty);
      expect(flat.containsKey('fields'), isFalse);
    });

    test('truncates full chapter content on missing_required_fields', () {
      // Create /chapters 缺 title 同样报 missing_required_fields，此时
      // fields.content 是整章正文，必须截断而不是原样进入匿名上报。
      final input =
          jsonDecode(
                sanitizeToolInput('Create', {
                  'path': '/chapters',
                  'fields': {'content': '正文' * 5000},
                }),
              )
              as Map<String, dynamic>;

      final fields = input['fields'] as Map<String, dynamic>;
      expect(fields['content'], endsWith('...[truncated]'));
      expect((fields['content'] as String).length, lessThan(200));
      expect(input['top_level_keys'], ['path', 'fields']);
      expect(input['fields_shape'], 'object');
      expect(input['field_names'], ['content']);
    });

    test('truncates long Create field values', () {
      final input =
          jsonDecode(
                sanitizeToolInput('Create', {
                  'path': '/characters',
                  'fields': {'role': 'x' * 101},
                }),
              )
              as Map<String, dynamic>;

      expect(input['fields'], {'role': '${'x' * 100}...[truncated]'});
    });

    test('keeps Edit path without old or new text', () {
      final input = jsonDecode(
        sanitizeToolInput('Edit', {
          'path': '/chapters/第一章/content',
          'old_text': '旧正文',
          'new_text': '新正文',
        }),
      );

      expect(input, {
        'collection': 'chapters',
        'field': 'content',
        'path': '/chapters/第一章/content',
      });
    });

    test('records Edit path shape when path is missing', () {
      // 线上 invalid_path 连 collection 都解析不出，需区分缺失与非字符串。
      final input = jsonDecode(
        sanitizeToolInput('Edit', {'old_text': 'a', 'new_text': 'b'}),
      );

      expect(input, {'field': '', 'path_shape': 'absent'});
    });

    test('records truncated raw prefix when Create fields is a string', () {
      // 线上 invalid_fields 只报 fields_shape=string，看不到模型到底传了什么，
      // 无法归因。前缀与长度是下一批上报的归因依据。
      final input =
          jsonDecode(
                sanitizeToolInput('Create', {
                  'path': '/factions',
                  'fields': '{"title": "人族",}${'x' * 200}',
                }),
              )
              as Map<String, dynamic>;

      expect(input['fields_shape'], 'string');
      expect(input['fields_raw_length'], 216);
      expect(input['fields_raw_prefix'], endsWith('...[truncated]'));
      expect(input['fields_raw_prefix'], startsWith('{"title": "人族",}'));
    });
  });
}
