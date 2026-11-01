// 职责: AI 聊天本地文本附件 — 选择、解码并校验 txt/md/csv 文件后生成内联上下文引用。
// 关联文件:
//   lib/shared/models/novel_workspace.dart
//   lib/shared/utils/text_file_decoder.dart
//   lib/desktop/widgets/ai/chat/composer.dart
//   lib/mobile/pages/novel_chat_page.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';

import '../../localization/locale_keys.dart';
import '../../logger/app_logger.dart';
import '../../models/novel_workspace.dart';
import '../../utils/text_file_decoder.dart';

const int chatContextFileMaxCharacters = 100000;
const int _maxUtf8BytesPerCharacter = 4;
const int _utf8BomByteCount = 3;

const chatContextFileTypeGroup = XTypeGroup(
  label: 'text',
  extensions: <String>['txt', 'md', 'csv'],
  mimeTypes: <String>['text/plain', 'text/markdown', 'text/csv'],
  uniformTypeIdentifiers: <String>[
    'public.text',
    'net.daringfireball.markdown',
    'public.comma-separated-values-text',
  ],
);

final _log = AppLogger.forModule('ChatContextFile');

enum ChatContextFileFailure { unsupportedType, empty, tooLarge, readFailed }

class ChatContextFileException implements Exception {
  const ChatContextFileException(this.failure);

  final ChatContextFileFailure failure;
}

String chatContextFileFailureLocaleKey(ChatContextFileFailure failure) {
  return switch (failure) {
    ChatContextFileFailure.unsupportedType =>
      LocaleKeys.aiContextFileUnsupported,
    ChatContextFileFailure.empty => LocaleKeys.aiContextFileEmpty,
    ChatContextFileFailure.tooLarge => LocaleKeys.aiContextFileTooLarge,
    ChatContextFileFailure.readFailed => LocaleKeys.aiContextFileReadFailed,
  };
}

Future<AiContextReference?> pickChatContextFile(
  Iterable<AiContextReference> existingReferences,
) async {
  try {
    final file = await openFile(
      acceptedTypeGroups: const [chatContextFileTypeGroup],
    );
    if (file == null) {
      return null;
    }
    return await loadChatContextFile(file, existingReferences);
  } on ChatContextFileException {
    rethrow;
  } catch (error, stackTrace) {
    _log.error(
      'failed to select chat context file',
      error: error,
      stackTrace: stackTrace,
    );
    throw const ChatContextFileException(ChatContextFileFailure.readFailed);
  }
}

Future<AiContextReference> loadChatContextFile(
  XFile file,
  Iterable<AiContextReference> existingReferences,
) async {
  final fileName = file.name.trim();
  if (!_isSupportedChatContextFile(fileName)) {
    throw const ChatContextFileException(
      ChatContextFileFailure.unsupportedType,
    );
  }

  try {
    final byteLength = await file.length();
    if (byteLength >
        chatContextFileMaxCharacters * _maxUtf8BytesPerCharacter +
            _utf8BomByteCount) {
      throw const ChatContextFileException(ChatContextFileFailure.tooLarge);
    }

    final bytes = await file.readAsBytes();
    final content = decodeImportedTextBytes(bytes);
    if (content.trim().isEmpty) {
      throw const ChatContextFileException(ChatContextFileFailure.empty);
    }

    final reference = AiContextReference.file(
      itemId: _chatContextFileId(file, bytes),
      label: fileName,
      content: content,
    );
    final currentCharacters = chatContextFileCharacterCount(
      existingReferences.where((item) => item != reference),
    );
    if (currentCharacters + content.runes.length >
        chatContextFileMaxCharacters) {
      throw const ChatContextFileException(ChatContextFileFailure.tooLarge);
    }
    return reference;
  } on ChatContextFileException {
    rethrow;
  } catch (error, stackTrace) {
    _log.error(
      'failed to read chat context file name=$fileName',
      error: error,
      stackTrace: stackTrace,
    );
    throw const ChatContextFileException(ChatContextFileFailure.readFailed);
  }
}

int chatContextFileCharacterCount(Iterable<AiContextReference> references) {
  return references
      .where((item) => item.kind == AiContextReferenceKind.file)
      .fold<int>(0, (total, item) => total + item.content.runes.length);
}

List<AiContextReference> upsertChatContextFileReference(
  Iterable<AiContextReference> references,
  AiContextReference attachment,
) {
  return [
    for (final reference in references)
      if (reference != attachment) reference,
    attachment,
  ];
}

bool _isSupportedChatContextFile(String fileName) {
  final normalized = fileName.toLowerCase();
  return normalized.endsWith('.txt') ||
      normalized.endsWith('.md') ||
      normalized.endsWith('.csv');
}

String _chatContextFileId(XFile file, List<int> bytes) {
  final path = file.path.trim();
  final identity = path.isEmpty
      ? '${file.name}:${sha256.convert(bytes)}'
      : path;
  return 'local_file_${sha256.convert(utf8.encode(identity))}';
}
