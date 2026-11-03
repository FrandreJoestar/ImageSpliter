import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app_theme.dart';
import '../../controllers/project_controller.dart';
import '../../models/export_settings.dart';
import '../../services/export_size_estimator.dart';
import '../../services/project_exporter.dart';

enum _ExportStage { configuring, exporting, done, error }

/// 导出设置弹窗：目录、格式、质量，以及导出进度与结果汇总。
class ExportDialog extends StatefulWidget {
  const ExportDialog({super.key, required this.project});

  final ProjectController project;

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  late String? _directory;
  late String _sampleBase;

  ExportFormat _format = ExportFormat.png;
  double _quality = 90;
  _ExportStage _stage = _ExportStage.configuring;
  ExportProgress? _progress;
  ExportReport? _report;
  String? _error;

  ExportSizeEstimate? _estimate;
  bool _estimating = false;
  int _estimateRequest = 0;
  Timer? _estimateDebounce;

  int get _totalBlocks => widget.project.totalSelectedBlocks;
  int get _imageCount => widget.project.exportableDocumentCount;

  @override
  void initState() {
    super.initState();
    _directory =
        widget.project.lastExportDirectory ?? _defaultOutputDirectory();
    final documents = widget.project.documents;
    _sampleBase = documents.isEmpty
        ? 'photo'
        : p.basenameWithoutExtension(documents.first.fileName);
    widget.project.addListener(_handleProjectChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleEstimate(immediate: true);
    });
  }

  @override
  void dispose() {
    _estimateDebounce?.cancel();
    _estimateRequest++;
    widget.project.removeListener(_handleProjectChanged);
    super.dispose();
  }

  void _handleProjectChanged() {
    if (!mounted) return;
    setState(() {
      final documents = widget.project.documents;
      _sampleBase = documents.isEmpty
          ? 'photo'
          : p.basenameWithoutExtension(documents.first.fileName);
    });
    _scheduleEstimate();
  }

  void _scheduleEstimate({bool immediate = false}) {
    _estimateDebounce?.cancel();
    if (immediate) {
      _runEstimate();
      return;
    }
    _estimateDebounce = Timer(const Duration(milliseconds: 260), _runEstimate);
  }

  Future<void> _runEstimate() async {
    final request = ++_estimateRequest;
    final documents = widget.project.documents
        .where((document) => document.hasSelection)
        .toList();
    final settings = ExportSettings(
      outputDirectory: _directory ?? '',
      format: _format,
      quality: _quality.round(),
    );
    if (mounted) setState(() => _estimating = true);

    final estimate = await ExportSizeEstimator.instance.estimate(
      documents: documents,
      settings: settings,
      isCancelled: () => request != _estimateRequest,
    );
    if (!mounted || request != _estimateRequest) return;
    setState(() {
      _estimate = estimate;
      _estimating = false;
    });
  }

  String? _defaultOutputDirectory() {
    final environment = Platform.environment;
    final home = environment['USERPROFILE'] ?? environment['HOME'];
    if (home == null) return null;
    final pictures = Directory(p.join(home, 'Pictures'));
    if (pictures.existsSync()) {
      return p.join(pictures.path, 'ImageSplitExport');
    }
    return home;
  }

  Future<void> _pickDirectory() async {
    final current = _directory;
    final initialDirectory = current != null && Directory(current).existsSync()
        ? current
        : null;
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: '选择导出文件夹',
      initialDirectory: initialDirectory,
    );
    if (path != null && mounted) {
      setState(() => _directory = path);
    }
  }

  Future<void> _startExport() async {
    final directory = _directory;
    if (directory == null) return;

    _estimateDebounce?.cancel();
    _estimateRequest++;

    setState(() {
      _stage = _ExportStage.exporting;
      _progress = ExportProgress(
        completed: 0,
        total: _totalBlocks,
        label: '准备中…',
      );
    });
    widget.project.lastExportDirectory = directory;

    try {
      final report = await ProjectExporter().export(
        documents: widget.project.documents,
        settings: ExportSettings(
          outputDirectory: directory,
          format: _format,
          quality: _quality.round(),
        ),
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _stage = _ExportStage.done;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _stage = _ExportStage.error;
      });
    }
  }

  Future<void> _openExportedFolder() async {
    final directory = _report?.outputDirectory ?? _directory;
    if (directory == null) return;
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [directory]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [directory]);
      } else {
        await Process.run('xdg-open', [directory]);
      }
    } catch (_) {
      // 打开资源管理器失败不影响导出结果。
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage != _ExportStage.exporting,
      child: Dialog(
        insetPadding: const EdgeInsets.all(36),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              const Divider(),
              Flexible(
                child: SingleChildScrollView(
                  child: switch (_stage) {
                    _ExportStage.configuring => _buildSettings(),
                    _ExportStage.exporting => _buildProgress(),
                    _ExportStage.done => _buildResult(),
                    _ExportStage.error => _buildError(),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final colors = context.palette;
    final (title, subtitle, icon, color) = switch (_stage) {
      _ExportStage.configuring => (
        '导出项目',
        '$_imageCount 张图片 · $_totalBlocks 个选中块',
        Icons.ios_share_rounded,
        colors.accent,
      ),
      _ExportStage.exporting => (
        '正在导出',
        '处理中，请保持窗口打开',
        Icons.downloading_rounded,
        colors.accent,
      ),
      _ExportStage.done => (
        _report?.hasFailures == true ? '导出完成，部分失败' : '导出完成',
        '成功导出 ${_report?.exportedFiles.length ?? 0} 个文件',
        _report?.hasFailures == true
            ? Icons.warning_amber_rounded
            : Icons.check_circle_rounded,
        _report?.hasFailures == true ? colors.danger : colors.success,
      ),
      _ExportStage.error => (
        '导出失败',
        '没有生成任何文件',
        Icons.error_outline_rounded,
        colors.danger,
      ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 18),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: color.withValues(alpha: 0.32)),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
              ],
            ),
          ),
          if (_stage != _ExportStage.exporting)
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: '关闭',
              iconSize: 18,
              color: colors.textMuted,
              style: IconButton.styleFrom(hoverColor: colors.surfaceHigh),
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
    );
  }

  Widget _buildSettings() {
    final colors = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildEstimateCard(colors),
              const SizedBox(height: 22),
              const _FieldLabel(label: '导出位置', hint: '所有选中的块会写入这个文件夹'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: colors.surfaceAlt,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: colors.border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.folder_open_rounded,
                            size: 15,
                            color: colors.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _directory ?? '请选择导出文件夹',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: _directory == null
                                    ? colors.textMuted
                                    : colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _pickDirectory,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 38),
                    ),
                    child: const Text('选择文件夹'),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const _FieldLabel(label: '导出格式', hint: '按当前旋转方向与选中块裁剪'),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final format in ExportFormat.values) ...[
                    Expanded(
                      child: _FormatOption(
                        format: format,
                        selected: _format == format,
                        onTap: () {
                          setState(() => _format = format);
                          _scheduleEstimate();
                        },
                      ),
                    ),
                    if (format != ExportFormat.values.last)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 22),
              _FieldLabel(
                label: '压缩质量',
                hint: _format.isLossy
                    ? '1 - 100，数值越高画质越好、文件越大'
                    : 'PNG 为无损格式，质量参数不适用',
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _quality,
                      min: 1,
                      max: 100,
                      divisions: 99,
                      onChanged: _format.isLossy
                          ? (value) {
                              setState(() => _quality = value);
                              _scheduleEstimate();
                            }
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 52,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.border),
                    ),
                    child: Text(
                      _format.isLossy ? '${_quality.round()}' : '无损',
                      style: TextStyle(
                        fontSize: _format.isLossy ? 12 : 10,
                        fontWeight: FontWeight.w600,
                        color: _format.isLossy
                            ? colors.textPrimary
                            : colors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.drive_file_rename_outline_rounded,
                          size: 13,
                          color: colors.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '文件命名',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_sampleBase}_1.${_format.extension} · '
                      '${_sampleBase}_2.${_format.extension}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '块序号按行优先编号；遇到同名文件时自动追加 _2、_3…',
                      style: TextStyle(fontSize: 10, color: colors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _directory == null ? null : _startExport,
                icon: const Icon(Icons.file_download_outlined, size: 17),
                label: const Text('开始导出'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEstimateCard(AppPalette colors) {
    final estimate = _estimate;
    final hasEstimate = estimate != null;
    final totalText = _estimating && !hasEstimate
        ? '计算中…'
        : _formatBytes(estimate?.totalBytes ?? 0);

    String? subtitle;
    if (hasEstimate) {
      final saved = estimate.originalBytes > 0 && estimate.totalBytes > 0
          ? (1 - estimate.totalBytes / estimate.originalBytes) * 100
          : 0.0;
      subtitle =
          '原始 ${_formatBytes(estimate.originalBytes)} · '
          '${estimate.estimatedDocuments} 张图片'
          '${saved > 0 ? ' · 预计节省 ${saved.round()}%' : ''}';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.compress_rounded, size: 18, color: colors.accent),
              const SizedBox(width: 8),
              Text(
                '预计压缩后总大小',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const Spacer(),
              if (_estimating)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: colors.accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            totalText,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: colors.accent,
              height: 1.1,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 10.5, color: colors.textMuted),
            ),
          ],
          if (hasEstimate && estimate.hasFailures) ...[
            const SizedBox(height: 8),
            Text(
              '${estimate.failedDocuments.length} 张图片无法读取，已跳过：'
              '${estimate.failedDocuments.take(3).join('、')}'
              '${estimate.failedDocuments.length > 3 ? ' 等' : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.4,
                color: colors.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgress() {
    final colors = context.palette;
    final progress =
        _progress ??
        ExportProgress(completed: 0, total: _totalBlocks, label: '');
    final percent = (progress.fraction * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$percent%',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w300,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.fraction,
              minHeight: 7,
              backgroundColor: colors.surfaceHigh,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                '${progress.completed} / ${progress.total} 个块',
                style: TextStyle(fontSize: 11, color: colors.textSecondary),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  progress.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            '正在逐张处理图片，导出期间请勿关闭窗口。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: colors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final colors = context.palette;
    final report = _report;
    if (report == null) return const SizedBox.shrink();
    final hasFailures = report.hasFailures;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '${report.exportedFiles.length}',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: colors.success,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '个文件已导出',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_open_rounded,
                      size: 14,
                      color: colors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        report.outputDirectory,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (report.skippedDocuments > 0) ...[
                const SizedBox(height: 10),
                Text(
                  '${report.skippedDocuments} 张图片未选择任何块，已跳过',
                  style: TextStyle(fontSize: 10.5, color: colors.textMuted),
                ),
              ],
              if (hasFailures) ...[
                const SizedBox(height: 16),
                Text(
                  '${report.failures.length} 项未能导出',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.danger,
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 148),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final failure in report.failures)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: colors.danger.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: colors.danger.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.error_outline_rounded,
                                    size: 12,
                                    color: colors.danger,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        failure.sourceName,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        failure.reason,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          height: 1.5,
                                          color: colors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _openExportedFolder,
                icon: const Icon(Icons.folder_open_rounded, size: 15),
                label: const Text('打开文件夹'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('完成'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    final colors = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Column(
            children: [
              Icon(Icons.error_outline_rounded, size: 30, color: colors.danger),
              const SizedBox(height: 12),
              Text(
                '导出过程中出现错误',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? '未知错误',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.6,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () =>
                    setState(() => _stage = _ExportStage.configuring),
                child: const Text('返回设置'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 人性化字节显示：B / KB / MB / GB。
String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 KB';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 ? 0 : (value >= 100 ? 0 : (value >= 10 ? 1 : 2));
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.hint});

  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: colors.textMuted),
          ),
        ),
      ],
    );
  }
}

class _FormatOption extends StatelessWidget {
  const _FormatOption({
    required this.format,
    required this.selected,
    required this.onTap,
  });

  final ExportFormat format;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.fromLTRB(11, 10, 10, 10),
        decoration: BoxDecoration(
          color: selected ? colors.accentSoft : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? colors.accent : colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  format.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? colors.textPrimary : colors.textSecondary,
                  ),
                ),
                const Spacer(),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 13,
                  color: selected ? colors.accent : colors.textMuted,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              format.hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9.5, color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
