// 职责: 验证章节正文 DB 回流不会覆盖本地保存回声或尚未保存的用户输入。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/desktop/pages/novel_editor_support.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/pages/novel_editor.dart';

void main() {
  group('shouldApplyChapterContentStreamValue', () {
    test('rejects an in-flight local save echo while typing continues', () {
      expect(
        shouldApplyChapterContentStreamValue(
          incomingContent: 'saved snapshot',
          controllerContent: 'saved snapshot + still typing',
          lastSyncedContent: 'old content',
          pendingLocalSaveContent: 'saved snapshot',
          targetChanged: false,
        ),
        isFalse,
      );
    });

    test('rejects a delayed local save echo after the save completes', () {
      expect(
        shouldApplyChapterContentStreamValue(
          incomingContent: 'saved snapshot',
          controllerContent: 'saved snapshot + still typing',
          lastSyncedContent: 'saved snapshot',
          pendingLocalSaveContent: null,
          targetChanged: false,
        ),
        isFalse,
      );
    });

    test('applies an external update when the editor is clean', () {
      expect(
        shouldApplyChapterContentStreamValue(
          incomingContent: 'AI content',
          controllerContent: 'old content',
          lastSyncedContent: 'old content',
          pendingLocalSaveContent: null,
          targetChanged: false,
        ),
        isTrue,
      );
    });

    test('does not overwrite dirty editor content with an external update', () {
      expect(
        shouldApplyChapterContentStreamValue(
          incomingContent: 'AI content',
          controllerContent: 'local draft',
          lastSyncedContent: 'old content',
          pendingLocalSaveContent: null,
          targetChanged: false,
        ),
        isFalse,
      );
    });

    test('always applies content after switching chapters', () {
      expect(
        shouldApplyChapterContentStreamValue(
          incomingContent: 'other chapter',
          controllerContent: 'local draft',
          lastSyncedContent: 'old content',
          pendingLocalSaveContent: null,
          targetChanged: true,
        ),
        isTrue,
      );
    });
  });
}
