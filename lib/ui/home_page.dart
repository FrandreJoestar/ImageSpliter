import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../controllers/project_controller.dart';
import 'widgets/editor_panel.dart';
import 'widgets/export_dialog.dart';
import 'widgets/library_panel.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ProjectController _project = ProjectController();
  bool _importing = false;
  bool _dragActive = false;

  void _setDragActive(bool active) {
    if (active == _dragActive) return;
    setState(() => _dragActive = active);
  }

  void _handleDrop(List<DropItem> files) {
    final paths = [
      for (final file in files)
        if (file.path.isNotEmpty) file.path,
    ];
    if (paths.isEmpty) return;
    _runImport(() => _project.importPaths(paths));
  }

  Future<void> _runImport(Future<ImportSummary?> Function() action) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final summary = await action();
      if (!mounted || summary == null) return;
      _showImportSummary(summary);
    } catch (error) {
      if (mounted) _showMessage('导入失败：${_shortError(error)}');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showImportSummary(ImportSummary summary) {
    if (summary.isEmpty) {
      _showMessage('没有找到可导入的图片');
      return;
    }
    final parts = <String>[];
    if (summary.added > 0) parts.add('已导入 ${summary.added} 张图片');
    if (summary.duplicated > 0) parts.add('${summary.duplicated} 张已在项目中');
    if (summary.failed > 0) parts.add('${summary.failed} 项读取失败');
    if (parts.isEmpty) parts.add('没有新的图片');
    _showMessage(parts.join(' · '));
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  Future<void> _confirmClear() async {
    final count = _project.documents.length;
    if (count == 0) return;
    final colors = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '清空项目？',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        content: Text(
          '将移除 $count 张图片及其分割线、块选择与旋转设置，此操作不可撤销。',
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: colors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: colors.danger,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _project.clearProject();
      _showMessage('项目已清空');
    }
  }

  Future<void> _openExport() async {
    if (_project.totalSelectedBlocks == 0) {
      _showMessage('没有可导出的块，请先点击图片中的块进行选择');
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExportDialog(project: _project),
    );
  }

  String _shortError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
            _runImport(_project.pickImages),
        const SingleActivator(
          LogicalKeyboardKey.keyO,
          control: true,
          shift: true,
        ): () =>
            _runImport(_project.pickFolder),
        const SingleActivator(LogicalKeyboardKey.keyE, control: true):
            _openExport,
      },
      child: Focus(
        autofocus: true,
        child: DropTarget(
          onDragEntered: (_) => _setDragActive(true),
          onDragExited: (_) => _setDragActive(false),
          onDragDone: (details) {
            _setDragActive(false);
            _handleDrop(details.files);
          },
          child: Scaffold(
            body: Stack(
              children: [
                AnimatedBuilder(
                  animation: _project,
                  builder: (context, _) {
                    final colors = context.palette;
                    return Column(
                      children: [
                        _AppHeader(
                          project: _project,
                          importing: _importing,
                          themeMode: widget.themeMode,
                          onThemeModeChanged: widget.onThemeModeChanged,
                          onImportImages: () =>
                              _runImport(_project.pickImages),
                          onImportFolder: () =>
                              _runImport(_project.pickFolder),
                          onClear: _confirmClear,
                          onExport: _openExport,
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              SizedBox(
                                width: 272,
                                child: LibraryPanel(
                                  controller: _project,
                                  onImportImages: () =>
                                      _runImport(_project.pickImages),
                                  onImportFolder: () =>
                                      _runImport(_project.pickFolder),
                                ),
                              ),
                              Container(width: 1, color: colors.border),
                              Expanded(
                                child: EditorPanel(controller: _project),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (_dragActive)
                  const Positioned.fill(child: _DropOverlay()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({
    required this.project,
    required this.importing,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onImportImages,
    required this.onImportFolder,
    required this.onClear,
    required this.onExport,
  });

  final ProjectController project;
  final bool importing;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback onImportImages;
  final VoidCallback onImportFolder;
  final VoidCallback onClear;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final documents = project.documents;
    final totalBlocks = project.totalSelectedBlocks;
    final colors = context.palette;

    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colors.accent, colors.accentAlt],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.dashboard_customize_rounded,
              size: 18,
              color: colors.background,
            ),
          ),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Text(
                    'ImageSpliter',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: colors.border),
                    ),
                    child: Text(
                      '本地处理',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '图片分割 · 多格式导出',
                style: TextStyle(fontSize: 10, color: colors.textMuted),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_mosaic_outlined,
                  size: 13,
                  color: colors.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  '${documents.length} 张 · $totalBlocks 个块',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          if (importing) ...[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: colors.accent,
              ),
            ),
            const SizedBox(width: 10),
          ],
          OutlinedButton.icon(
            onPressed: importing ? null : onImportImages,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 15),
            label: const Text('导入图片'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: importing ? null : onImportFolder,
            icon: const Icon(Icons.folder_open_rounded, size: 15),
            label: const Text('导入文件夹'),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: '清空项目',
            child: IconButton(
              onPressed: documents.isEmpty ? null : onClear,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              color: colors.textMuted,
              style: IconButton.styleFrom(
                minimumSize: const Size(34, 34),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: totalBlocks == 0 ? null : onExport,
            icon: const Icon(Icons.file_download_outlined, size: 17),
            label: const Text('导出项目'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
          const SizedBox(width: 6),
          _ThemeModeButton(
            themeMode: themeMode,
            onChanged: onThemeModeChanged,
          ),
        ],
      ),
    );
  }
}

/// 拖放文件悬停在整个窗口上时的提示层。
class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: ColoredBox(
        color: scheme.scrim.withValues(alpha: 0.38),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 30),
            decoration: BoxDecoration(
              color: colors.surfaceHigh,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.accent, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 42,
                  color: colors.accent,
                ),
                const SizedBox(height: 14),
                Text(
                  '松开以导入图片',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '支持图片文件或包含图片的文件夹（含 HEIC / HEIF）',
                  style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 三种主题模式切换：跟随系统 / 浅色 / 深色。
class _ThemeModeButton extends StatelessWidget {
  const _ThemeModeButton({required this.themeMode, required this.onChanged});

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onChanged;

  IconData get _icon => switch (themeMode) {
    ThemeMode.light => Icons.light_mode_outlined,
    ThemeMode.dark => Icons.dark_mode_outlined,
    ThemeMode.system => Icons.brightness_auto_outlined,
  };

  String get _label => switch (themeMode) {
    ThemeMode.light => '浅色模式',
    ThemeMode.dark => '深色模式',
    ThemeMode.system => '跟随系统',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    const options = [
      (mode: ThemeMode.system, label: '跟随系统', icon: Icons.brightness_auto),
      (mode: ThemeMode.light, label: '浅色模式', icon: Icons.light_mode),
      (mode: ThemeMode.dark, label: '深色模式', icon: Icons.dark_mode),
    ];

    return PopupMenuButton<ThemeMode>(
      tooltip: '主题：$_label',
      initialValue: themeMode,
      onSelected: onChanged,
      icon: Icon(_icon, size: 18, color: colors.textSecondary),
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<ThemeMode>(
            value: option.mode,
            child: Row(
              children: [
                Icon(option.icon, size: 16, color: colors.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    option.label,
                    style: TextStyle(fontSize: 12.5, color: colors.textPrimary),
                  ),
                ),
                if (themeMode == option.mode)
                  Icon(Icons.check_rounded, size: 16, color: colors.accent),
              ],
            ),
          ),
      ],
    );
  }
}
