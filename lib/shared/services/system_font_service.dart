// 职责: 系统字体服务 — 通过平台通道读取桌面系统可用字体族。
// 关联文件:
//   lib/shared/providers/system_font_providers.dart
//   macos/Runner/MainFlutterWindow.swift
//   windows/runner/flutter_window.cpp
//   linux/runner/my_application.cc
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class SystemFontService {
  static const MethodChannel _channel = MethodChannel('reveric/system_fonts');

  Future<List<String>> listFontFamilies() async {
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
      return const [];
    }

    List<String>? rawFonts;
    try {
      rawFonts = await _channel.invokeListMethod<String>('listFontFamilies');
    } on MissingPluginException {
      rawFonts = null;
    } on PlatformException {
      rawFonts = null;
    }

    final fonts = _normalizeFontFamilies(rawFonts ?? const <String>[]);
    if (fonts.isNotEmpty) {
      return fonts;
    }

    if (Platform.isMacOS) {
      return _listMacOsFontFamiliesFromSystemProfiler();
    }

    return const [];
  }

  List<String> _normalizeFontFamilies(Iterable<String> rawFonts) {
    final uniqueFonts = <String>{};

    for (final font in rawFonts) {
      final normalized = font.trim();
      if (normalized.isNotEmpty) {
        uniqueFonts.add(normalized);
      }
    }

    final fonts = uniqueFonts.toList();
    fonts.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return fonts;
  }

  Future<List<String>> _listMacOsFontFamiliesFromSystemProfiler() async {
    try {
      final result = await Process.run('/usr/sbin/system_profiler', const [
        'SPFontsDataType',
        '-json',
      ]).timeout(const Duration(seconds: 10));

      if (result.exitCode != 0) {
        return const [];
      }

      final decoded = jsonDecode(result.stdout as String);
      if (decoded is! Map<String, dynamic>) {
        return const [];
      }

      final fontsData = decoded['SPFontsDataType'];
      if (fontsData is! List) {
        return const [];
      }

      final fontFamilies = <String>[];
      for (final fontData in fontsData) {
        if (fontData is! Map) {
          continue;
        }

        final typefaces = fontData['typefaces'];
        if (typefaces is! List) {
          continue;
        }

        for (final typeface in typefaces) {
          if (typeface is! Map) {
            continue;
          }

          final family = typeface['family'];
          if (family is String) {
            fontFamilies.add(family);
          }
        }
      }

      return _normalizeFontFamilies(fontFamilies);
    } on Object {
      return const [];
    }
  }
}
