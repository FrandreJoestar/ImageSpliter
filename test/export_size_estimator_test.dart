import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:imagespliter/models/export_settings.dart';
import 'package:imagespliter/models/image_document.dart';
import 'package:imagespliter/services/export_size_estimator.dart';
import 'package:imagespliter/services/image_processor.dart';
import 'package:path/path.dart' as p;

Future<ImageDocument> _createDocument(
  Directory directory, {
  required String name,
  int width = 960,
  int height = 720,
}) async {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final nx = x / width;
      final ny = y / height;
      final noise = (x * 37 + y * 17) % 23 - 11;
      image.setPixelRgba(
        x,
        y,
        (120 + 90 * math.sin(nx * math.pi * 4) * math.cos(ny * math.pi * 3) + noise)
            .clamp(0, 255)
            .toInt(),
        (130 + 70 * math.sin((nx + ny) * math.pi * 3) + noise)
            .clamp(0, 255)
            .toInt(),
        (150 + 60 * math.cos(ny * math.pi * 5) + noise)
            .clamp(0, 255)
            .toInt(),
        255,
      );
    }
  }
  final file = File(p.join(directory.path, name))
    ..writeAsBytesSync(img.encodePng(image));
  return ImageDocument(
    id: name,
    path: file.path,
    fileName: name,
    width: width,
    height: height,
  );
}

Future<int> _actualEncodedBytes(
  ImageDocument document,
  ExportSettings settings,
) async {
  final source = await decodeImageFile(document.path);
  addTearDown(source.dispose);
  final region = regionForCell(
    sourceWidth: source.width,
    sourceHeight: source.height,
    rotationDegrees: document.rotationDegrees,
    horizontalCuts: document.horizontalCuts,
    verticalCuts: document.verticalCuts,
    row: 0,
    column: 0,
  )!;
  final cropped = await cropRotatedRegion(
    source: source,
    rotationDegrees: document.rotationDegrees,
    region: region,
    flattenOnWhite: settings.format == ExportFormat.jpeg,
  );
  addTearDown(cropped.dispose);
  final rgba = await imageToRgba(cropped);
  return (await encodeImage(
    EncodeJob(
      rgba: TransferableTypedData.fromList([rgba]),
      width: cropped.width,
      height: cropped.height,
      format: settings.format,
      quality: settings.quality,
    ),
  )).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PNG 预估与真实编码结果处于合理误差范围', () async {
    final directory = await Directory.systemTemp.createTemp('estimate_png');
    addTearDown(() => directory.delete(recursive: true));
    final document = await _createDocument(directory, name: 'png.png');

    const settings = ExportSettings(
      outputDirectory: '',
      format: ExportFormat.png,
      quality: 90,
    );
    final estimate = await ExportSizeEstimator.instance.estimate(
      documents: [document],
      settings: settings,
    );
    final actual = await _actualEncodedBytes(document, settings);

    expect(estimate.estimatedDocuments, 1);
    expect(estimate.failedDocuments, isEmpty);
    expect(estimate.totalBytes, greaterThan(actual * 0.6));
    expect(estimate.totalBytes, lessThan(actual * 1.6));
  });

  test('JPEG 预估随质量下降而减小，且低于 PNG', () async {
    final directory = await Directory.systemTemp.createTemp('estimate_jpeg');
    addTearDown(() => directory.delete(recursive: true));
    final document = await _createDocument(directory, name: 'jpeg.png');

    const png = ExportSettings(
      outputDirectory: '',
      format: ExportFormat.png,
      quality: 90,
    );
    const highJpeg = ExportSettings(
      outputDirectory: '',
      format: ExportFormat.jpeg,
      quality: 95,
    );
    const lowJpeg = ExportSettings(
      outputDirectory: '',
      format: ExportFormat.jpeg,
      quality: 30,
    );

    final pngEstimate = await ExportSizeEstimator.instance.estimate(
      documents: [document],
      settings: png,
    );
    final highEstimate = await ExportSizeEstimator.instance.estimate(
      documents: [document],
      settings: highJpeg,
    );
    final lowEstimate = await ExportSizeEstimator.instance.estimate(
      documents: [document],
      settings: lowJpeg,
    );

    expect(highEstimate.totalBytes, lessThan(pngEstimate.totalBytes));
    expect(lowEstimate.totalBytes, lessThan(highEstimate.totalBytes));
  });

  test('无法读取的图片被跳过且不影响其他图片', () async {
    final directory = await Directory.systemTemp.createTemp('estimate_error');
    addTearDown(() => directory.delete(recursive: true));
    final valid = await _createDocument(
      directory,
      name: 'valid.png',
      width: 320,
      height: 240,
    );
    final missing = ImageDocument(
      id: 'missing',
      path: p.join(directory.path, 'missing.png'),
      fileName: 'missing.png',
      width: 480,
      height: 360,
    );

    const settings = ExportSettings(
      outputDirectory: '',
      format: ExportFormat.png,
      quality: 90,
    );
    final estimate = await ExportSizeEstimator.instance.estimate(
      documents: [missing, valid],
      settings: settings,
    );

    expect(estimate.totalBytes, greaterThan(0));
    expect(estimate.estimatedDocuments, 1);
    expect(estimate.failedDocuments, contains('missing.png'));
  });
}
