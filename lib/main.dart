import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'services/theme_preferences.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeMode = await ThemePreferences.load();
  runApp(ImageSpliterApp(initialThemeMode: themeMode));
}

class ImageSpliterApp extends StatefulWidget {
  const ImageSpliterApp({
    super.key,
    this.initialThemeMode = ThemeMode.system,
    this.persistThemeMode,
  });

  final ThemeMode initialThemeMode;

  /// 主题偏好持久化回调，默认写入本地配置文件；测试可注入空实现。
  final Future<void> Function(ThemeMode mode)? persistThemeMode;

  @override
  State<ImageSpliterApp> createState() => _ImageSpliterAppState();
}

class _ImageSpliterAppState extends State<ImageSpliterApp> {
  late ThemeMode _themeMode = widget.initialThemeMode;

  void _setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;
    setState(() => _themeMode = mode);
    (widget.persistThemeMode ?? ThemePreferences.save)(mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ImageSpliter',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: _themeMode,
      home: HomePage(
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
      ),
    );
  }
}
