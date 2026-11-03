/// 支持的导出格式。
enum ExportFormat { png, jpeg, webp }

extension ExportFormatX on ExportFormat {
  String get label => switch (this) {
    ExportFormat.png => 'PNG',
    ExportFormat.jpeg => 'JPEG',
    ExportFormat.webp => 'WebP',
  };

  String get extension => switch (this) {
    ExportFormat.png => 'png',
    ExportFormat.jpeg => 'jpg',
    ExportFormat.webp => 'webp',
  };

  bool get isLossy => this != ExportFormat.png;

  String get hint => switch (this) {
    ExportFormat.png => '无损 · 支持透明',
    ExportFormat.jpeg => '有损 · 体积小',
    ExportFormat.webp => '有损 · 体积更小',
  };
}

class ExportSettings {
  const ExportSettings({
    required this.outputDirectory,
    required this.format,
    required this.quality,
  });

  final String outputDirectory;
  final ExportFormat format;

  /// 1 - 100，仅对 JPEG / WebP 生效。
  final int quality;
}

class ExportProgress {
  const ExportProgress({
    required this.completed,
    required this.total,
    required this.label,
  });

  final int completed;
  final int total;
  final String label;

  double get fraction => total <= 0 ? 0 : (completed / total).clamp(0.0, 1.0);
}

class ExportFailure {
  const ExportFailure({required this.sourceName, required this.reason});

  final String sourceName;
  final String reason;
}

class ExportReport {
  const ExportReport({
    required this.outputDirectory,
    required this.exportedFiles,
    required this.failures,
    required this.skippedDocuments,
  });

  final String outputDirectory;
  final List<String> exportedFiles;
  final List<ExportFailure> failures;

  /// 没有选中任何块、因此被跳过的图片数量。
  final int skippedDocuments;

  bool get hasFailures => failures.isNotEmpty;
}
