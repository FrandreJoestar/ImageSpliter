import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// 主题偏好的本地持久化：写入用户配置目录下的 settings.json。
abstract final class ThemePreferences {
  static const String _fileName = 'settings.json';
  static const String _themeModeKey = 'themeMode';

  static Future<File> _settingsFile() async {
    final environment = Platform.environment;
    final base =
        environment['APPDATA'] ??
        environment['XDG_CONFIG_HOME'] ??
        environment['HOME'] ??
        Directory.current.path;
    final directory = Directory(p.join(base, 'ImageSpliter'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, _fileName));
  }

  static Future<ThemeMode> load() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) return ThemeMode.system;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return ThemeMode.system;
      return switch (decoded[_themeModeKey]) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      // 配置损坏或不可读时回退到跟随系统。
      return ThemeMode.system;
    }
  }

  static Future<void> save(ThemeMode mode) async {
    try {
      final file = await _settingsFile();
      var settings = <String, dynamic>{};
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) settings = decoded;
      }
      settings[_themeModeKey] = switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
      await file.writeAsString(jsonEncode(settings), flush: true);
    } catch (_) {
      // 持久化失败不影响当前会话的主题切换。
    }
  }
}
