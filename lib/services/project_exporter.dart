import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

import '../models/export_settings.dart';
import '../models/image_document.dart';
import 'image_processor.dart';

typedef ExportProgressCallback = void Function(ExportProgress progress);

/// 逐张图片解码、按当前旋转与分割线裁剪、编码并写入目标目录。
///
/// 单张图片解码失败会记录为失败项并继续导出其余图片；
/// 单个块写入失败也只记录该块的失败原因。
class ProjectExporter {
  Future<ExportReport> export({
    required List<ImageDocument> documents,
    required ExportSettings settings,
    required ExportProgressCallback onProgress,
  }) async {
    final outputDirectory = Directory(settings.outputDirectory);
    await outputDirectory.create(recursive: true);

    final targets = documents
        .where((document) => document.hasSelection)
        .toList();
    final skippedDocuments = documents.length - targets.length;
    final total = targets.fold<int>(
      0,
      (sum, document) => sum + document.selectedCount,
    );

    final usedNames = <String>{};
    final exportedFiles = <String>[];
    final failures = <ExportFailure>[];
    var completed = 0;

    for (final document in targets) {
      final cells = document.selectedCells;
      ui.Image? source;
      try {
        source = await decodeImageFile(document.path);
        document.updateSourceSize(source.width, source.height);
      } catch (error) {
        failures.add(
          ExportFailure(
            sourceName: document.fileName,
            reason: '无法读取或解码图片：${_shortReason(error)}',
          ),
        );
        completed += cells.length;
        onProgress(
          ExportProgress(
            completed: completed,
            total: total,
            label: document.fileName,
          ),
        );
        continue;
      }

      final image = source;

      for (final cell in cells) {
        try {
          final region = regionForCell(
            sourceWidth: image.width,
            sourceHeight: image.height,
            rotationDegrees: document.rotationDegrees,
            horizontalCuts: document.horizontalCuts,
            verticalCuts: document.verticalCuts,
            row: cell.row,
            column: cell.column,
          );
          if (region == null) {
            throw StateError('该块宽或高为 0，已跳过');
          }

          final cropped = await cropRotatedRegion(
            source: image,
            rotationDegrees: document.rotationDegrees,
            region: region,
            flattenOnWhite: settings.format == ExportFormat.jpeg,
          );
          final rgba = await imageToRgba(cropped);
          final width = cropped.width;
          final height = cropped.height;
          cropped.dispose();

          final bytes = await encodeImage(
            EncodeJob(
              rgba: TransferableTypedData.fromList([rgba]),
              width: width,
              height: height,
              format: settings.format,
              quality: settings.quality,
            ),
          );

          final filePath = _uniquePath(
            directory: outputDirectory.path,
            sourceFileName: document.fileName,
            blockNumber: cell.number,
            format: settings.format,
            usedNames: usedNames,
          );
          await File(filePath).writeAsBytes(bytes, flush: true);
          usedNames.add(p.basename(filePath).toLowerCase());
          exportedFiles.add(filePath);
        } catch (error) {
          failures.add(
            ExportFailure(
              sourceName: '${document.fileName} · 块 ${cell.number}',
              reason: _shortReason(error),
            ),
          );
        }

        completed++;
        onProgress(
          ExportProgress(
            completed: completed,
            total: total,
            label: document.fileName,
          ),
        );
        // 让出事件循环，保证进度条可以刷新。
        await Future<void>.delayed(Duration.zero);
      }

      image.dispose();
    }

    return ExportReport(
      outputDirectory: outputDirectory.path,
      exportedFiles: exportedFiles,
      failures: failures,
      skippedDocuments: skippedDocuments,
    );
  }

  /// 命名规则：原文件名_块序号.ext；重名时追加 `_2`、`_3`……
  String _uniquePath({
    required String directory,
    required String sourceFileName,
    required int blockNumber,
    required ExportFormat format,
    required Set<String> usedNames,
  }) {
    final baseName = p.basenameWithoutExtension(sourceFileName);
    final extension = format.extension;

    var candidate = p.join(directory, '${baseName}_$blockNumber.$extension');
    var suffix = 2;
    while (usedNames.contains(p.basename(candidate).toLowerCase()) ||
        File(candidate).existsSync()) {
      candidate = p.join(
        directory,
        '${baseName}_${blockNumber}_$suffix.$extension',
      );
      suffix++;
    }
    return candidate;
  }

  String _shortReason(Object error) {
    final message = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return message.length > 160 ? '${message.substring(0, 160)}…' : message;
  }
}
