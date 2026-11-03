import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:imagespliter/models/image_document.dart';
import 'package:imagespliter/services/image_processor.dart';

Future<ui.Image> _createSource(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFF0000),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('wrapDegrees', () {
    test('区间内角度保持不变', () {
      expect(wrapDegrees(0), 0);
      expect(wrapDegrees(45), 45);
      expect(wrapDegrees(-90), -90);
      expect(wrapDegrees(180), 180);
      expect(wrapDegrees(-180), -180);
    });

    test('越界角度自动环绕', () {
      expect(wrapDegrees(270), -90);
      expect(wrapDegrees(-270), 90);
      expect(wrapDegrees(450), 90);
      expect(wrapDegrees(-540), -180);
    });
  });

  group('rotatedBoundsFor 外接矩形', () {
    test('0° / 90° / 180° 临界角度', () {
      final zero = rotatedBoundsFor(400, 200, 0);
      expect(zero.width, closeTo(400, 1e-9));
      expect(zero.height, closeTo(200, 1e-9));

      final quarter = rotatedBoundsFor(400, 200, 90);
      expect(quarter.width, closeTo(200, 1e-9));
      expect(quarter.height, closeTo(400, 1e-9));

      final negQuarter = rotatedBoundsFor(400, 200, -90);
      expect(negQuarter.width, closeTo(200, 1e-9));
      expect(negQuarter.height, closeTo(400, 1e-9));

      final half = rotatedBoundsFor(400, 200, 180);
      expect(half.width, closeTo(400, 1e-9));
      expect(half.height, closeTo(200, 1e-9));
    });

    test('45° 按外接矩形计算', () {
      final bounds = rotatedBoundsFor(400, 200, 45);
      final expected = (400 + 200) / math.sqrt2;
      expect(bounds.width, closeTo(expected, 1e-6));
      expect(bounds.height, closeTo(expected, 1e-6));
    });
  });

  group('ImageDocument 旋转', () {
    ImageDocument build() => ImageDocument(
      id: 'img',
      path: 'mock.png',
      fileName: 'mock.png',
      width: 400,
      height: 200,
    );

    test('默认 0°，支持连续角度', () {
      final document = build();
      expect(document.rotationDegrees, 0);
      expect(document.isRotated, isFalse);

      document.setRotationDegrees(37.5);
      expect(document.rotationDegrees, closeTo(37.5, 1e-9));
      expect(document.isRotated, isTrue);

      document.setRotationDegrees(-172.25);
      expect(document.rotationDegrees, closeTo(-172.25, 1e-9));
    });

    test('角度限制在 -180° ~ 180°', () {
      final document = build();
      document.setRotationDegrees(240);
      expect(document.rotationDegrees, 180);
      document.setRotationDegrees(-240);
      expect(document.rotationDegrees, -180);
    });

    test('90° 步进旋转自动环绕并支持复位', () {
      final document = build();
      document.rotate();
      expect(document.rotationDegrees, 90);
      document.rotate();
      expect(document.rotationDegrees, 180);
      document.rotate();
      expect(document.rotationDegrees, -90);
      document.rotate(clockwise: false);
      expect(document.rotationDegrees, -180);
      document.resetRotation();
      expect(document.rotationDegrees, 0);
    });

    test('旋转不改变分割线与块选择（辅助线独立于图片）', () {
      final document = build();
      document.addHorizontalCut();
      document.addHorizontalCut();
      document.addVerticalCut();
      document.toggleCell(0, 0);

      final horizontal = document.horizontalCuts;
      final vertical = document.verticalCuts;
      final rowCount = document.rowCount;
      final columnCount = document.columnCount;
      final selected = [
        for (var row = 0; row < rowCount; row++)
          for (var column = 0; column < columnCount; column++)
            document.isCellSelected(row, column),
      ];

      document.setRotationDegrees(45);
      document.rotate();

      expect(document.horizontalCuts, horizontal);
      expect(document.verticalCuts, vertical);
      expect(document.rowCount, rowCount);
      expect(document.columnCount, columnCount);
      for (var row = 0; row < rowCount; row++) {
        for (var column = 0; column < columnCount; column++) {
          expect(
            document.isCellSelected(row, column),
            selected[row * columnCount + column],
          );
        }
      }
    });

    test('旋转后像素坐标基于外接矩形', () {
      final document = build();
      document.addHorizontalCut();
      expect(document.horizontalCutPixels(0), 100);

      document.setRotationDegrees(90);
      expect(document.rotatedWidth, closeTo(200, 1e-6));
      expect(document.rotatedHeight, closeTo(400, 1e-6));
      expect(document.horizontalCutPixels(0), 200);

      document.setRotationDegrees(180);
      expect(document.rotatedWidth, closeTo(400, 1e-6));
      expect(document.rotatedHeight, closeTo(200, 1e-6));
      expect(document.horizontalCutPixels(0), 100);
    });
  });

  group('导出区域计算', () {
    test('临界角度下块区域完整覆盖外接矩形', () {
      for (final angle in [0.0, 90.0, -90.0, 180.0]) {
        final region = regionForCell(
          sourceWidth: 400,
          sourceHeight: 200,
          rotationDegrees: angle,
          horizontalCuts: const [0.5],
          verticalCuts: const [],
          row: 0,
          column: 0,
        );
        expect(region, isNotNull, reason: 'angle=$angle');
        final bounds = rotatedBoundsFor(400, 200, angle);
        expect(region!.left, 0);
        expect(region.top, 0);
        expect(region.width, closeTo(bounds.width, 1));
        expect(region.height, closeTo(bounds.height / 2, 1));
      }
    });

    test('任意角度仍可切分且相邻块边界连续', () {
      final first = regionForCell(
        sourceWidth: 400,
        sourceHeight: 200,
        rotationDegrees: 37.5,
        horizontalCuts: const [0.4],
        verticalCuts: const [],
        row: 0,
        column: 0,
      );
      final second = regionForCell(
        sourceWidth: 400,
        sourceHeight: 200,
        rotationDegrees: 37.5,
        horizontalCuts: const [0.4],
        verticalCuts: const [],
        row: 1,
        column: 0,
      );
      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first!.top + first.height, second!.top);
    });

    for (final angle in [0.0, 90.0, 180.0, -90.0, 37.5]) {
      test('$angle° 裁剪输出与区域尺寸一致', () async {
        final source = await _createSource(400, 200);
        addTearDown(source.dispose);

        final region = regionForCell(
          sourceWidth: 400,
          sourceHeight: 200,
          rotationDegrees: angle,
          horizontalCuts: const [0.5],
          verticalCuts: const [0.5],
          row: 0,
          column: 0,
        );
        expect(region, isNotNull);

        final cropped = await cropRotatedRegion(
          source: source,
          rotationDegrees: angle,
          region: region!,
          flattenOnWhite: true,
        );
        addTearDown(cropped.dispose);

        expect(cropped.width, region.width);
        expect(cropped.height, region.height);
      });
    }
  });
}
