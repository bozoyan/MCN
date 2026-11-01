// 职责: 文本文件字节解码 — 为导入流程统一处理 UTF-8 BOM、UTF-8 与 GBK/GB2312 文本。
// 关联文件:
//   lib/shared/services/novel_import.dart
//   lib/shared/services/documents_service.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart';

String decodeImportedTextBytes(
  List<int> bytes, {
  void Function(Object error)? onGbkDecodeFailure,
}) {
  if (bytes.isEmpty) {
    return '';
  }
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  if (data.length >= 3 &&
      data[0] == 0xEF &&
      data[1] == 0xBB &&
      data[2] == 0xBF) {
    return utf8.decode(data.sublist(3), allowMalformed: true);
  }
  try {
    return utf8.decode(data);
  } on FormatException {
    try {
      return gbk.decode(data);
    } catch (error) {
      onGbkDecodeFailure?.call(error);
      return utf8.decode(data, allowMalformed: true);
    }
  }
}
