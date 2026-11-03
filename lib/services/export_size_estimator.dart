import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/export_settings.dart';
import '../models/image_document.dart';
import 'image_processor.dart';

/// 导出压缩后的体积预估结果。
class ExportSizeEstimate {
  const ExportSizeEstimate({
    required this.totalBytes,
    required this.originalBytes,
    required this.estimatedDocuments,
    required this.failedDocuments,
  });

  /// 所有选中块压缩后的预估总字节数。
  final int totalBytes;

  /// 可读取图片的原始文件总字节数。
  final int originalBytes;

  /// 成功参与预估的图片数量。
  final int estimatedDocuments;

  /// 无法读取或无法估算的图片文件名。
  final List<String> failedDocuments;

  bool get hasFailures => failedDocuments.isNotEmpty;
}

/// 基于原图采样块的压缩体积预估器。
///
/// 每张图片解码一次，从原始分辨率截取 1-2 个最多 512px 的采样块，用目标
/// 格式 / 质量真实编码采样块，得到「字节 / 像素」后按每个导出块的实际
/// 像素数外推。采样块保持原始分辨率，避免缩放平滑导致的压缩率偏差；
/// 编码在独立 isolate 中执行，解码与采样均为异步操作，不会阻塞界面。
class ExportSizeEstimator {
  ExportSizeEstimator._();

  static final ExportSizeEstimator instance = ExportSizeEstimator._();

  /// key = 路径 + 格式 + 质量，缩放比例变化时可直接复用。
  final Map<String, _ProxyStat> _proxyCache = {};

  /// key = 路径，采样块只与图片内容有关，参数变化时无需重新解码。
  final Map<String, _ImageSample> _sampleCache = {};

  Future<ExportSizeEstimate> estimate({
    required List<ImageDocument> documents,
    required ExportSettings settings,
    bool Function()? isCancelled,
  }) async {
    var totalBytes = 0;
    var originalBytes = 0;
    var estimatedDocuments = 0;
    final failed = <String>[];

    for (final document in documents) {
      if (isCancelled?.call() ?? false) break;
      if (!document.hasSelection) continue;

      try {
        final originalLength = await File(document.path).length();

        final stat = await _statFor(document.path, settings);
        if (isCancelled?.call() ?? false) break;
        document.updateSourceSize(stat.sourceWidth, stat.sourceHeight);

        var documentBytes = 0;
        var cells = 0;
        for (final cell in document.selectedCells) {
          if (isCancelled?.call() ?? false) break;
          final region = regionForCell(
            sourceWidth: stat.sourceWidth,
            sourceHeight: stat.sourceHeight,
            rotationDegrees: document.rotationDegrees,
            horizontalCuts: document.horizontalCuts,
            verticalCuts: document.verticalCuts,
            row: cell.row,
            column: cell.column,
          );
          if (region == null) continue;

          final width = math.max(1, region.width);
          final height = math.max(1, region.height);
          documentBytes += stat.estimateBytes(width * height);
          cells++;
        }

        if (cells == 0) {
          failed.add(document.fileName);
          continue;
        }
        totalBytes += documentBytes;
        originalBytes += originalLength;
        estimatedDocuments++;
      } catch (_) {
        failed.add(document.fileName);
      }
    }

    return ExportSizeEstimate(
      totalBytes: totalBytes,
      originalBytes: originalBytes,
      estimatedDocuments: estimatedDocuments,
      failedDocuments: failed,
    );
  }

  Future<_ProxyStat> _statFor(String path, ExportSettings settings) async {
    final qualityKey = settings.format.isLossy ? settings.quality : 0;
    final key = '$path|${settings.format.name}|$qualityKey';
    final cached = _proxyCache[key];
    if (cached != null) return cached;

    final sample = await _sampleFor(path);
    final encodedBytes = await compute(
      _encodeSampleTiles,
      _SampleEncodeJob(
        tiles: sample.tiles,
        formatIndex: settings.format.index,
        quality: settings.quality,
      ),
    );
    if (encodedBytes <= 0) {
      throw StateError('无法估算压缩体积');
    }

    final pixels = sample.tiles.fold<int>(
      0,
      (sum, tile) => sum + tile.width * tile.height,
    );
    if (pixels <= 0) {
      throw StateError('无法获取图片像素');
    }

    final stat = _ProxyStat(
      sourceWidth: sample.sourceWidth,
      sourceHeight: sample.sourceHeight,
      bytesPerPixel: encodedBytes / pixels,
    );
    if (_proxyCache.length > 128) _proxyCache.clear();
    _proxyCache[key] = stat;
    return stat;
  }

  Future<_ImageSample> _sampleFor(String path) async {
    final cached = _sampleCache[path];
    if (cached != null) return cached;
    final sample = await _loadSample(path);
    if (_sampleCache.length > 24) _sampleCache.clear();
    _sampleCache[path] = sample;
    return sample;
  }

  Future<_ImageSample> _loadSample(String path) async {
    final bytes = await readImageBytes(path);
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      final source = frame.image;
      try {
        final width = source.width;
        final height = source.height;
        if (width <= 0 || height <= 0) {
          throw StateError('图片尺寸无效');
        }

        final tiles = <_SampleTile>[];
        const maxTile = 512;
        if (width <= maxTile && height <= maxTile) {
          tiles.add(await _renderTile(source, 0, 0, width, height));
        } else {
          final tileWidth = math.min(maxTile, width);
          final tileHeight = math.min(maxTile, height);
          final anchors = [
            (x: (width - tileWidth) / 2, y: (height - tileHeight) / 2),
            (x: (width - tileWidth) * 0.25, y: (height - tileHeight) * 0.75),
          ];
          for (final anchor in anchors) {
            tiles.add(
              await _renderTile(
                source,
                anchor.x.floor(),
                anchor.y.floor(),
                tileWidth,
                tileHeight,
              ),
            );
          }
        }

        return _ImageSample(
          sourceWidth: width,
          sourceHeight: height,
          tiles: tiles,
        );
      } finally {
        source.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  Future<_SampleTile> _renderTile(
    ui.Image source,
    int left,
    int top,
    int width,
    int height,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(
        left.toDouble(),
        top.toDouble(),
        width.toDouble(),
        height.toDouble(),
      ),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.none,
    );
    final picture = recorder.endRecording();
    final tileImage = await picture.toImage(width, height);
    picture.dispose();
    try {
      final byteData = await tileImage.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (byteData == null) {
        throw StateError('无法读取图片像素');
      }
      return _SampleTile(
        rgba: byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
        width: width,
        height: height,
      );
    } finally {
      tileImage.dispose();
    }
  }
}

class _ImageSample {
  const _ImageSample({
    required this.sourceWidth,
    required this.sourceHeight,
    required this.tiles,
  });

  final int sourceWidth;
  final int sourceHeight;
  final List<_SampleTile> tiles;
}

class _SampleTile {
  const _SampleTile({
    required this.rgba,
    required this.width,
    required this.height,
  });

  final Uint8List rgba;
  final int width;
  final int height;
}

class _ProxyStat {
  const _ProxyStat({
    required this.sourceWidth,
    required this.sourceHeight,
    required this.bytesPerPixel,
  });

  final int sourceWidth;
  final int sourceHeight;
  final double bytesPerPixel;

  int estimateBytes(int pixels) {
    if (pixels <= 0) return 0;
    return math.max(1, (pixels * bytesPerPixel).round());
  }
}

class _SampleEncodeJob {
  const _SampleEncodeJob({
    required this.tiles,
    required this.formatIndex,
    required this.quality,
  });

  final List<_SampleTile> tiles;
  final int formatIndex;
  final int quality;
}

int _encodeSampleTiles(_SampleEncodeJob job) {
  final format = ExportFormat.values[job.formatIndex];
  final quality = job.quality.clamp(1, 100);
  var total = 0;
  for (final tile in job.tiles) {
    final image = img.Image.fromBytes(
      width: tile.width,
      height: tile.height,
      bytes: tile.rgba.buffer,
      bytesOffset: tile.rgba.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    final bytes = switch (format) {
      ExportFormat.png => img.encodePng(image, level: 6),
      ExportFormat.jpeg => img.encodeJpg(image, quality: quality),
      ExportFormat.webp => img.encodeWebP(
        image,
        lossless: false,
        quality: quality,
        method: 4,
      ),
    };
    total += bytes.length;
  }
  return total;
}
