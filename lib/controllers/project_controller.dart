import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/image_document.dart';

class ImportSummary {
  const ImportSummary({
    required this.added,
    required this.duplicated,
    required this.failed,
    required this.found,
  });

  final int added;
  final int duplicated;
  final int failed;
  final int found;

  bool get isEmpty => added == 0 && duplicated == 0 && failed == 0;
}

/// 管理图片库与当前选中项。单张图片的编辑状态保存在 [ImageDocument] 内。
class ProjectController extends ChangeNotifier {
  static const List<String> supportedExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
    'bmp',
    'gif',
    'tif',
    'tiff',
    'heic',
    'heif',
  ];

  static bool isSupportedFile(String path) {
    final extension = p
        .extension(path)
        .replaceFirst('.', '')
        .toLowerCase();
    return supportedExtensions.contains(extension);
  }

  final List<ImageDocument> _documents = [];
  String? _selectedId;
  int _idSeed = 0;

  /// 最近一次使用的导出目录，仅在本次运行内记忆。
  String? lastExportDirectory;

  List<ImageDocument> get documents => List.unmodifiable(_documents);
  bool get isEmpty => _documents.isEmpty;

  ImageDocument? get selectedDocument {
    for (final document in _documents) {
      if (document.id == _selectedId) return document;
    }
    return null;
  }

  int get totalSelectedBlocks =>
      _documents.fold(0, (sum, document) => sum + document.selectedCount);

  int get exportableDocumentCount =>
      _documents.where((document) => document.hasSelection).length;

  void select(String id) {
    if (_selectedId == id) return;
    if (!_documents.any((document) => document.id == id)) return;
    _selectedId = id;
    notifyListeners();
  }

  Future<ImportSummary?> pickImages() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: '选择图片',
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
    );
    if (files.isEmpty) return null;
    final paths = [
      for (final file in files)
        if (file.path != null) file.path!,
    ];
    return _addPaths(paths);
  }

  Future<ImportSummary?> pickFolder() async {
    final directory = await FilePicker.getDirectoryPath(
      dialogTitle: '选择包含图片的文件夹',
    );
    if (directory == null) return null;

    final found = <String>[];
    try {
      await for (final entity in Directory(
        directory,
      ).list(followLinks: false)) {
        if (entity is! File) continue;
        if (isSupportedFile(entity.path)) {
          found.add(entity.path);
        }
      }
    } on FileSystemException {
      return ImportSummary(
        added: 0,
        duplicated: 0,
        failed: 1,
        found: found.length,
      );
    }

    found.sort(
      (a, b) =>
          p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase()),
    );
    return _addPaths(found);
  }

  /// 导入拖放或外部传入的文件 / 文件夹路径。
  ///
  /// 自动过滤不支持的扩展名，文件夹只收集其直接包含的图片。
  Future<ImportSummary> importPaths(Iterable<String> paths) async {
    final candidates = <String>{};
    var failed = 0;

    for (final path in paths) {
      final type = await FileSystemEntity.type(path);
      if (type == FileSystemEntityType.directory) {
        try {
          await for (final entity in Directory(
            path,
          ).list(followLinks: false)) {
            if (entity is File && isSupportedFile(entity.path)) {
              candidates.add(entity.path);
            }
          }
        } on FileSystemException {
          failed++;
        }
      } else if (type == FileSystemEntityType.file &&
          isSupportedFile(path)) {
        candidates.add(path);
      } else {
        failed++;
      }
    }

    final ordered = candidates.toList()
      ..sort(
        (a, b) =>
            p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase()),
      );
    final summary = _addPaths(ordered);
    return ImportSummary(
      added: summary.added,
      duplicated: summary.duplicated,
      failed: summary.failed + failed,
      found: ordered.length + failed,
    );
  }

  ImportSummary _addPaths(List<String> paths) {
    var added = 0;
    var duplicated = 0;
    var failed = 0;
    String? firstAddedId;

    for (final path in paths) {
      if (_containsPath(path)) {
        duplicated++;
        continue;
      }
      final fileName = p.basename(path);
      if (fileName.trim().isEmpty) {
        failed++;
        continue;
      }
      final document = ImageDocument(
        id: 'img_${_idSeed++}',
        path: path,
        fileName: fileName,
      );
      _documents.add(document);
      firstAddedId ??= document.id;
      added++;
    }

    if (_selectedId == null && firstAddedId != null) {
      _selectedId = firstAddedId;
    }
    if (added > 0) notifyListeners();

    return ImportSummary(
      added: added,
      duplicated: duplicated,
      failed: failed,
      found: paths.length,
    );
  }

  bool _containsPath(String path) {
    final normalized = path.toLowerCase();
    return _documents.any(
      (document) => document.path.toLowerCase() == normalized,
    );
  }

  void removeDocument(String id) {
    final index = _documents.indexWhere((document) => document.id == id);
    if (index == -1) return;
    _documents.removeAt(index);

    if (_selectedId == id) {
      if (_documents.isEmpty) {
        _selectedId = null;
      } else {
        _selectedId = _documents[index.clamp(0, _documents.length - 1)].id;
      }
    }
    notifyListeners();
  }

  void clearProject() {
    if (_documents.isEmpty) return;
    _documents.clear();
    _selectedId = null;
    notifyListeners();
  }
}
