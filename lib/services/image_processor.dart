import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:heic_native/heic_native.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../models/export_settings.dart';
import '../models/image_document.dart';

/// 是否为 HEIC / HEIF 图片。
bool isHeicFile(String path) {
  final extension = p.extension(path).toLowerCase();
  return extension == '.heic' || extension == '.heif';
}

/// 读取图片字节；HEIC / HEIF 通过原生 libheif 转换为无损 PNG 后再解码。
Future<Uint8List> readImageBytes(String path) async {
  if (isHeicFile(path)) {
    return HeicNative.convertToBytes(path, compressionLevel: 3);
  }
  return File(path).readAsBytes();
}

/// 读取文件并解码为全分辨率 [ui.Image]。
Future<ui.Image> decodeImageFile(String path) async {
  final bytes = await readImageBytes(path);
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}

final Map<String, Future<Uint8List?>> _thumbnailCache = {};

/// HEIC / HEIF 缩略图（小尺寸 JPEG）。普通格式返回 null，由调用方直接使用文件。
Future<Uint8List?> loadHeicThumbnail(String path) {
  if (!isHeicFile(path)) return Future.value(null);
  return _thumbnailCache.putIfAbsent(path, () => _createHeicThumbnail(path));
}

Future<Uint8List?> _createHeicThumbnail(String path) async {
  try {
    final pngBytes = await HeicNative.convertToBytes(
      path,
      compressionLevel: 1,
    );
    return compute(_resizeThumbnail, pngBytes);
  } catch (_) {
    return null;
  }
}

Uint8List? _resizeThumbnail(Uint8List pngBytes) {
  final decoded = img.decodeImage(pngBytes);
  if (decoded == null) return null;
  final thumbnail = img.copyResize(
    decoded,
    width: 192,
    interpolation: img.Interpolation.average,
  );
  return img.encodeJpg(thumbnail, quality: 82);
}

/// 归一化裁剪范围：以当前旋转方向为基准的像素矩形。
class CropRegion {
  const CropRegion({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int left;
  final int top;
  final int width;
  final int height;
}

/// 计算某个块在旋转后图片中的像素矩形（整数边界，保证相邻块无缝拼接）。
CropRegion? regionForCell({
  required int sourceWidth,
  required int sourceHeight,
  required double rotationDegrees,
  required List<double> horizontalCuts,
  required List<double> verticalCuts,
  required int row,
  required int column,
}) {
  final bounds = rotatedBoundsFor(sourceWidth, sourceHeight, rotationDegrees);
  final rotatedWidth = math.max(bounds.width, 1.0);
  final rotatedHeight = math.max(bounds.height, 1.0);

  final xEdges = [0.0, ...verticalCuts, 1.0];
  final yEdges = [0.0, ...horizontalCuts, 1.0];
  if (row < 0 || row >= yEdges.length - 1) return null;
  if (column < 0 || column >= xEdges.length - 1) return null;

  final maxX = rotatedWidth.round();
  final maxY = rotatedHeight.round();
  final left = (xEdges[column] * rotatedWidth).round().clamp(0, maxX);
  final right = (xEdges[column + 1] * rotatedWidth).round().clamp(left, maxX);
  final top = (yEdges[row] * rotatedHeight).round().clamp(0, maxY);
  final bottom = (yEdges[row + 1] * rotatedHeight).round().clamp(top, maxY);

  final width = right - left;
  final height = bottom - top;
  if (width <= 0 || height <= 0) return null;

  return CropRegion(left: left, top: top, width: width, height: height);
}

/// 从原图中裁出旋转后的指定区域。
///
/// 90° 整数倍使用精确平移与旋转，不会引入额外重采样；任意角度则以画面
/// 外接矩形中心为原点旋转后再采样，几何与预览完全一致。
/// JPEG 不支持透明，[flattenOnWhite] 为 true 时会先铺白底。
Future<ui.Image> cropRotatedRegion({
  required ui.Image source,
  required double rotationDegrees,
  required CropRegion region,
  required bool flattenOnWhite,
}) async {
  final width = math.max(1, region.width);
  final height = math.max(1, region.height);

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

  if (flattenOnWhite) {
    canvas.drawRect(
      ui.Rect.fromLTWH(
        0,
        0,
        region.width.toDouble(),
        region.height.toDouble(),
      ),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
  }

  final quarterAligned = (rotationDegrees % 90).abs() < 1e-6;
  final needsResample = !quarterAligned;
  if (quarterAligned) {
    final turns = (((rotationDegrees / 90).round() % 4) + 4) % 4;
    canvas.translate(-region.left.toDouble(), -region.top.toDouble());
    switch (turns) {
      case 1:
        canvas.translate(source.height.toDouble(), 0);
        canvas.rotate(math.pi / 2);
        break;
      case 2:
        canvas.translate(source.width.toDouble(), source.height.toDouble());
        canvas.rotate(math.pi);
        break;
      case 3:
        canvas.translate(0, source.width.toDouble());
        canvas.rotate(-math.pi / 2);
        break;
      default:
        break;
    }
  } else {
    final bounds = rotatedBoundsFor(
      source.width,
      source.height,
      rotationDegrees,
    );
    canvas.translate(-region.left.toDouble(), -region.top.toDouble());
    canvas.translate(bounds.width / 2, bounds.height / 2);
    canvas.rotate(rotationDegrees * math.pi / 180);
    canvas.translate(-source.width / 2, -source.height / 2);
  }

  canvas.drawImage(
    source,
    ui.Offset.zero,
    ui.Paint()
      ..isAntiAlias = needsResample
      ..filterQuality = needsResample
          ? ui.FilterQuality.high
          : ui.FilterQuality.none,
  );

  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

/// 把 [ui.Image] 转为原始 RGBA 字节，供后台 isolate 编码。
Future<Uint8List> imageToRgba(ui.Image image) async {
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  if (data == null) {
    throw StateError('无法读取图片像素数据');
  }
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// 传给编码 isolate 的任务，使用 [TransferableTypedData] 避免大块像素拷贝。
class EncodeJob {
  EncodeJob({
    required this.rgba,
    required this.width,
    required this.height,
    required this.format,
    required this.quality,
  });

  final TransferableTypedData rgba;
  final int width;
  final int height;
  final ExportFormat format;
  final int quality;
}

Future<Uint8List> encodeImage(EncodeJob job) => compute(_encodeImage, job);

Uint8List _encodeImage(EncodeJob job) {
  final data = job.rgba.materialize().asUint8List();
  final quality = job.quality.clamp(1, 100).toInt();
  final image = img.Image.fromBytes(
    width: job.width,
    height: job.height,
    bytes: data.buffer,
    bytesOffset: data.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );

  return switch (job.format) {
    ExportFormat.png => img.encodePng(image, level: 6),
    ExportFormat.jpeg => img.encodeJpg(image, quality: quality),
    ExportFormat.webp => img.encodeWebP(
      image,
      lossless: false,
      quality: quality,
      method: 4,
    ),
  };
}
