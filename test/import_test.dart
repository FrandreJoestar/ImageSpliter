import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagespliter/controllers/project_controller.dart';
import 'package:imagespliter/services/image_processor.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('支持 HEIC / HEIF 扩展名识别', () {
    expect(isHeicFile('photo.HEIC'), isTrue);
    expect(isHeicFile('photo.heif'), isTrue);
    expect(isHeicFile('photo.jpg'), isFalse);
    expect(isHeicFile('photo'), isFalse);
    expect(
      ProjectController.supportedExtensions,
      containsAll(['heic', 'heif']),
    );
  });

  test('拖放导入按扩展名过滤文件与文件夹', () async {
    final directory = await Directory.systemTemp.createTemp(
      'imagespliter_import',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final heic = File(p.join(directory.path, 'photo.HEIC'))
      ..writeAsBytesSync([0, 1, 2]);
    File(p.join(directory.path, 'note.txt')).writeAsBytesSync([0]);
    final nested = Directory(p.join(directory.path, 'nested'))..createSync();
    File(p.join(nested.path, 'inner.heif')).writeAsBytesSync([0]);

    final controller = ProjectController();
    final summary = await controller.importPaths([
      heic.path,
      p.join(directory.path, 'note.txt'),
      nested.path,
    ]);

    expect(summary.added, 2);
    expect(summary.failed, 1);
    expect(
      controller.documents.map((document) => document.fileName),
      containsAll(['photo.HEIC', 'inner.heif']),
    );
    expect(
      controller.documents.any((document) => document.fileName == 'note.txt'),
      isFalse,
    );

    final again = await controller.importPaths([heic.path]);
    expect(again.added, 0);
    expect(again.duplicated, 1);
  });
}
