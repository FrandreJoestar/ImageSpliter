import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagespliter/app_theme.dart';
import 'package:imagespliter/main.dart';
import 'package:imagespliter/models/image_document.dart';
import 'package:imagespliter/ui/widgets/split_canvas.dart';

Future<ui.Image> _createImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3366CC),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

void _setWindow(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  testWidgets('空状态在不同窗口尺寸下正常显示', (tester) async {
    _setWindow(tester, const Size(1280, 800));
    await tester.pumpWidget(const ImageSpliterApp());

    expect(find.text('选择一张图片开始编辑'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1024, 640);
    await tester.pump();
    expect(find.text('选择一张图片开始编辑'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('画布在临界与任意角度下正常渲染且辅助线保持正交', (tester) async {
    _setWindow(tester, const Size(1200, 800));

    final image = await _createImage(400, 200);
    addTearDown(image.dispose);

    final document = ImageDocument(
      id: 'img',
      path: 'mock.png',
      fileName: 'mock.png',
      width: 400,
      height: 200,
    );
    document.addHorizontalCut();
    document.addVerticalCut();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SplitCanvas(
            document: document,
            image: image,
            onMoveHorizontalCut: (index, value) {},
            onMoveVerticalCut: (index, value) {},
            onToggleCell: (row, column) {},
            onDeleteCut: (axis, index) {},
          ),
        ),
      ),
    );

    // 记录 0° 时的分割线与选择状态，旋转后应完全不变。
    final horizontal = document.horizontalCuts;
    final vertical = document.verticalCuts;
    final selected = document.selectedCount;

    for (final angle in [0.0, 90.0, 180.0, -90.0, -45.0, 37.5]) {
      document.setRotationDegrees(angle);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'angle=$angle');
      expect(document.horizontalCuts, horizontal, reason: 'angle=$angle');
      expect(document.verticalCuts, vertical, reason: 'angle=$angle');
      expect(document.selectedCount, selected, reason: 'angle=$angle');
    }
  });

  testWidgets('鼠标靠近左下角提示时提示自动隐藏', (tester) async {
    _setWindow(tester, const Size(1200, 800));

    final image = await _createImage(400, 200);
    addTearDown(image.dispose);

    final document = ImageDocument(
      id: 'hint',
      path: 'mock.png',
      fileName: 'mock.png',
      width: 400,
      height: 200,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SplitCanvas(
            document: document,
            image: image,
            onMoveHorizontalCut: (index, value) {},
            onMoveVerticalCut: (index, value) {},
            onToggleCell: (row, column) {},
            onDeleteCut: (axis, index) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final hint = find.textContaining('拖动调位置');
    expect(hint, findsOneWidget);

    AnimatedOpacity hintOpacity() => tester.widget<AnimatedOpacity>(
      find.ancestor(of: hint, matching: find.byType(AnimatedOpacity)),
    );

    expect(hintOpacity().opacity, 1);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(600, 400));
    await tester.pump();

    // 靠近左下角提示区域：提示淡出。
    await mouse.moveTo(const Offset(60, 760));
    await tester.pumpAndSettle();
    expect(hintOpacity().opacity, 0);

    // 移回画布中央：提示恢复显示。
    await mouse.moveTo(const Offset(600, 400));
    await tester.pumpAndSettle();
    expect(hintOpacity().opacity, 1);

    await mouse.removePointer();
  });

  testWidgets('旋转与分割线按钮悬浮在画布右侧并可操作', (tester) async {
    _setWindow(tester, const Size(1200, 800));

    final image = await _createImage(400, 200);
    addTearDown(image.dispose);

    final document = ImageDocument(
      id: 'rail',
      path: 'mock.png',
      fileName: 'mock.png',
      width: 400,
      height: 200,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: document,
            builder: (context, _) => SplitCanvas(
              document: document,
              image: image,
              onMoveHorizontalCut: (index, value) {},
              onMoveVerticalCut: (index, value) {},
              onToggleCell: (row, column) {},
              onDeleteCut: (axis, index) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('向左旋转 90°'), findsOneWidget);
    expect(find.byTooltip('向右旋转 90°'), findsOneWidget);
    expect(find.byTooltip('添加水平分割线'), findsOneWidget);
    expect(find.byTooltip('添加竖直分割线'), findsOneWidget);
    expect(find.byTooltip('复位旋转'), findsOneWidget);

    await tester.tap(find.byTooltip('向右旋转 90°'));
    await tester.pump();
    expect(document.rotationDegrees, 90);

    await tester.tap(find.byTooltip('向左旋转 90°'));
    await tester.pump();
    expect(document.rotationDegrees, 0);

    await tester.tap(find.byTooltip('添加水平分割线'));
    await tester.pump();
    expect(document.horizontalCuts.length, 1);

    await tester.tap(find.byTooltip('添加竖直分割线'));
    await tester.pump();
    expect(document.verticalCuts.length, 1);

    await tester.tap(find.byTooltip('向右旋转 90°'));
    await tester.pump();
    expect(document.rotationDegrees, 90);

    await tester.tap(find.byTooltip('复位旋转'));
    await tester.pump();
    expect(document.rotationDegrees, 0);
  });

  testWidgets('小尺寸窗口下画布仍能完成布局', (tester) async {
    _setWindow(tester, const Size(480, 360));

    final image = await _createImage(120, 260);
    addTearDown(image.dispose);

    final document = ImageDocument(
      id: 'small',
      path: 'mock.png',
      fileName: 'mock.png',
      width: 120,
      height: 260,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SplitCanvas(
            document: document,
            image: image,
            onMoveHorizontalCut: (index, value) {},
            onMoveVerticalCut: (index, value) {},
            onToggleCell: (row, column) {},
            onDeleteCut: (axis, index) {},
          ),
        ),
      ),
    );

    document.setRotationDegrees(90);
    await tester.pump();

    expect(find.byType(SplitCanvas), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('亮色 / 暗色主题均使用 Material 3 默认色彩体系', () {
    final light = buildLightTheme();
    final dark = buildDarkTheme();
    final expectedLight = ColorScheme.fromSeed(seedColor: kMaterial3Seed);
    final expectedDark = ColorScheme.fromSeed(
      seedColor: kMaterial3Seed,
      brightness: Brightness.dark,
    );

    expect(light.useMaterial3, isTrue);
    expect(dark.useMaterial3, isTrue);
    expect(light.colorScheme.brightness, Brightness.light);
    expect(dark.colorScheme.brightness, Brightness.dark);
    expect(light.colorScheme.primary, expectedLight.primary);
    expect(dark.colorScheme.primary, expectedDark.primary);
    expect(light.colorScheme.surface, expectedLight.surface);
    expect(dark.colorScheme.surface, expectedDark.surface);
    expect(light.extension<AppPalette>(), isNotNull);
    expect(dark.extension<AppPalette>(), isNotNull);
    expect(
      light.snackBarTheme.backgroundColor,
      expectedLight.surfaceContainerHigh,
    );
    expect(
      dark.snackBarTheme.backgroundColor,
      expectedDark.surfaceContainerHigh,
    );
    expect(
      light.snackBarTheme.backgroundColor,
      isNot(dark.snackBarTheme.backgroundColor),
    );
  });

  testWidgets('主题切换实时生效并支持三种模式', (tester) async {
    _setWindow(tester, const Size(1280, 800));
    final persisted = <ThemeMode>[];

    await tester.pumpWidget(
      ImageSpliterApp(
        initialThemeMode: ThemeMode.system,
        persistThemeMode: (mode) async => persisted.add(mode),
      ),
    );
    await tester.pumpAndSettle();

    MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
    Brightness brightnessOfApp() => Theme.of(
      tester.element(find.text('选择一张图片开始编辑')),
    ).brightness;

    expect(app().themeMode, ThemeMode.system);

    await tester.tap(find.byTooltip('主题：跟随系统'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();

    expect(app().themeMode, ThemeMode.dark);
    expect(persisted, [ThemeMode.dark]);
    expect(brightnessOfApp(), Brightness.dark);

    await tester.tap(find.byTooltip('主题：深色模式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('浅色模式'));
    await tester.pumpAndSettle();

    expect(app().themeMode, ThemeMode.light);
    expect(persisted, [ThemeMode.dark, ThemeMode.light]);
    expect(brightnessOfApp(), Brightness.light);

    await tester.tap(find.byTooltip('主题：浅色模式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跟随系统'));
    await tester.pumpAndSettle();

    expect(app().themeMode, ThemeMode.system);
    expect(persisted, [ThemeMode.dark, ThemeMode.light, ThemeMode.system]);
  });

  testWidgets('已显示的 SnackBar 在主题切换后同步换色', (tester) async {
    _setWindow(tester, const Size(1000, 700));
    final mode = ValueNotifier<ThemeMode>(ThemeMode.light);
    addTearDown(mode.dispose);

    await tester.pumpWidget(
      ValueListenableBuilder<ThemeMode>(
        valueListenable: mode,
        builder: (context, value, _) => MaterialApp(
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: value,
          home: const _SnackBarHarness(),
        ),
      ),
    );

    await tester.tap(find.text('显示提示'));
    await tester.pumpAndSettle();

    Color snackColor() => tester
        .widgetList<Material>(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Material),
          ),
        )
        .first
        .color!;

    expect(snackColor(), buildLightTheme().snackBarTheme.backgroundColor);

    mode.value = ThemeMode.dark;
    await tester.pumpAndSettle();

    expect(snackColor(), buildDarkTheme().snackBarTheme.backgroundColor);
  });
}

class _SnackBarHarness extends StatelessWidget {
  const _SnackBarHarness();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('主题提示')),
            ),
            child: const Text('显示提示'),
          ),
        ),
      ),
    );
  }
}
