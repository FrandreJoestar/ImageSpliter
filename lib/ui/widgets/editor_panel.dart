import 'dart:async';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../app_theme.dart';
import '../../controllers/project_controller.dart';
import '../../models/image_document.dart';
import '../../services/image_processor.dart';
import 'cuts_inspector.dart';
import 'split_canvas.dart';

/// 右侧编辑区：工具栏 + 画布 + 检查器，负责加载当前选中图片的预览。
class EditorPanel extends StatefulWidget {
  const EditorPanel({super.key, required this.controller});

  final ProjectController controller;

  @override
  State<EditorPanel> createState() => _EditorPanelState();
}

class _EditorPanelState extends State<EditorPanel> {
  ImageDocument? _document;
  ui.Image? _source;
  bool _loading = false;
  String? _error;
  int _requestId = 0;
  bool _inspectorOpen = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    final document = widget.controller.selectedDocument;
    _document = document;
    if (document != null) {
      _loading = true;
      _decode(document, ++_requestId);
    }
  }

  @override
  void didUpdateWidget(covariant EditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _loadSelected();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _requestId++;
    _source?.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    final selected = widget.controller.selectedDocument;
    if (selected?.id != _document?.id) {
      _loadSelected();
    } else if (mounted) {
      setState(() {});
    }
  }

  void _loadSelected() {
    final document = widget.controller.selectedDocument;
    final previous = _source;
    setState(() {
      _document = document;
      _source = null;
      _error = null;
      _loading = document != null;
    });
    previous?.dispose();
    if (document == null) return;
    _decode(document, ++_requestId);
  }

  Future<void> _decode(ImageDocument document, int request) async {
    try {
      final image = await decodeImageFile(document.path);
      if (!mounted || request != _requestId) {
        image.dispose();
        return;
      }
      document.updateSourceSize(image.width, image.height);
      setState(() {
        _source = image;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || request != _requestId) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _openInspector() {
    if (_inspectorOpen) return;
    setState(() => _inspectorOpen = true);
  }

  void _closeInspector() {
    if (!_inspectorOpen) return;
    setState(() => _inspectorOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    if (document == null) {
      return const _EmptyEditor();
    }

    return AnimatedBuilder(
      animation: document,
      builder: (context, _) {
        return Column(
          children: [
            _EditorToolbar(document: document),
            Expanded(child: _buildBody(document)),
          ],
        );
      },
    );
  }

  Widget _buildBody(ImageDocument document) {
    if (_loading) {
      return const _LoadingView();
    }
    if (_error != null) {
      return _ErrorView(
        message: _error!,
        path: document.path,
        onRetry: _loadSelected,
      );
    }
    final image = _source;
    if (image == null) {
      return const _LoadingView();
    }

    final colors = context.palette;
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: SplitCanvas(
                document: document,
                image: image,
                onMoveHorizontalCut: document.moveHorizontalCut,
                onMoveVerticalCut: document.moveVerticalCut,
                onToggleCell: document.toggleCell,
                onDeleteCut: (axis, index) {
                  if (axis == CutAxis.horizontal) {
                    document.removeHorizontalCut(index);
                  } else {
                    document.removeVerticalCut(index);
                  }
                },
              ),
            ),
            Container(height: 1, color: colors.border),
            _RotationBar(document: document),
          ],
        ),
        // 编辑面板默认收起，展开后悬浮在预览区之上，不占用画布空间。
        Positioned(
          top: 12,
          right: 12,
          bottom: 12,
          width: 296,
          child: TapRegion(
            onTapOutside: (_) => _closeInspector(),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0.12, 0),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: _inspectorOpen
                  ? _InspectorPanel(
                      document: document,
                      onClose: _closeInspector,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
        if (!_inspectorOpen)
          Positioned(
            right: 0,
            top: 16,
            child: _InspectorTab(onTap: _openInspector),
          ),
      ],
    );
  }
}

/// 收起状态下贴在预览区右边缘的展开标签。
class _InspectorTab extends StatelessWidget {
  const _InspectorTab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: '展开编辑面板',
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 36,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: colors.surfaceHigh,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(10),
              ),
              border: Border(
                left: BorderSide(color: colors.borderStrong),
                top: BorderSide(color: colors.borderStrong),
                bottom: BorderSide(color: colors.borderStrong),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chevron_left_rounded,
                  size: 18,
                  color: colors.textSecondary,
                ),
                const SizedBox(height: 8),
                RotatedBox(
                  quarterTurns: 1,
                  child: Text(
                    '编辑面板',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.5,
                      color: colors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 悬浮编辑面板：内容沿用 [CutsInspector]，外层加上标题栏与收起按钮。
class _InspectorPanel extends StatelessWidget {
  const _InspectorPanel({required this.document, required this.onClose});

  final ImageDocument document;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.borderStrong),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(-6, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.only(left: 14, right: 4),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, size: 15, color: colors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  '编辑面板',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: colors.textSecondary,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: '收起面板',
                  child: IconButton(
                    onPressed: onClose,
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    constraints: const BoxConstraints.tightFor(
                      width: 30,
                      height: 30,
                    ),
                    style: IconButton.styleFrom(
                      foregroundColor: colors.textSecondary,
                      hoverColor: colors.surfaceHigh,
                    ),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: CutsInspector(document: document)),
        ],
      ),
    );
  }
}

/// 角度显示：整数不显示小数，其余保留一位小数。
String _formatDegrees(double value) {
  final rounded = value.roundToDouble();
  if ((value - rounded).abs() < 1e-6) return rounded.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

/// 预览区底部的旋转控制条：-180° ~ 180° 连续滑块 + 精准数值输入。
///
/// 滑块拖动期间用一个 16ms 的合并防抖把高频指针事件收敛到帧率级别，
/// 避免每来一个指针事件就触发一次整棵编辑面板重建；松手时立即提交。
class _RotationBar extends StatefulWidget {
  const _RotationBar({required this.document});

  final ImageDocument document;

  @override
  State<_RotationBar> createState() => _RotationBarState();
}

class _RotationBarState extends State<_RotationBar> {
  Timer? _coalesceTimer;
  double? _pendingAngle;

  @override
  void dispose() {
    _coalesceTimer?.cancel();
    super.dispose();
  }

  void _handleSliderChanged(double value) {
    _pendingAngle = value;
    _coalesceTimer ??= Timer(const Duration(milliseconds: 16), () {
      _coalesceTimer = null;
      _commitPending();
    });
  }

  void _commitPending() {
    final next = _pendingAngle;
    _pendingAngle = null;
    if (next != null) widget.document.setRotationDegrees(next);
  }

  /// 拖动结束：取消待执行的合并任务并立刻提交最终角度。
  void _flush() {
    _coalesceTimer?.cancel();
    _coalesceTimer = null;
    _commitPending();
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    final angle = document.rotationDegrees;
    final colors = context.palette;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: colors.surface),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          return Row(
            children: [
              Icon(
                Icons.rotate_right_rounded,
                size: 16,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                '旋转',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 12),
                const _AngleBound(label: '-180°'),
              ],
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                  ),
                  child: Slider(
                    value: angle.clamp(-180.0, 180.0).toDouble(),
                    min: -180,
                    max: 180,
                    onChanged: _handleSliderChanged,
                    onChangeEnd: (_) => _flush(),
                    semanticFormatterCallback: (value) =>
                        '旋转 ${value.round()} 度',
                  ),
                ),
              ),
              if (!compact) ...[
                const _AngleBound(label: '180°'),
                const SizedBox(width: 12),
              ],
              SizedBox(
                width: 76,
                child: _AngleField(
                  value: angle,
                  onChanged: document.setRotationDegrees,
                ),
              ),
              const SizedBox(width: 2),
              Tooltip(
                message: '复位到 0°',
                child: IconButton(
                  onPressed: document.isRotated
                      ? () => document.setRotationDegrees(0)
                      : null,
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  style: IconButton.styleFrom(
                    foregroundColor: colors.textSecondary,
                    disabledForegroundColor: colors.textMuted.withValues(
                      alpha: 0.4,
                    ),
                    hoverColor: colors.surfaceHigh,
                  ),
                  icon: const Icon(Icons.restart_alt_rounded),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AngleBound extends StatelessWidget {
  const _AngleBound({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(fontSize: 10, color: context.palette.textMuted),
    );
  }
}

/// 精准角度输入框：输入时防抖提交，滑块变化时同步回填。
class _AngleField extends StatefulWidget {
  const _AngleField({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_AngleField> createState() => _AngleFieldState();
}

class _AngleFieldState extends State<_AngleField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatDegrees(widget.value));
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _AngleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.value != oldWidget.value) {
      _setText(_formatDegrees(widget.value));
    }
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) _commit();
  }

  void _setText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _handleChanged(String text) {
    final parsed = double.tryParse(text.trim());
    if (parsed == null || !parsed.isFinite) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      widget.onChanged(parsed.clamp(-180.0, 180.0).toDouble());
    });
  }

  void _commit() {
    _debounce?.cancel();
    _debounce = null;
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null || !parsed.isFinite) {
      _setText(_formatDegrees(widget.value));
      return;
    }
    final clamped = parsed.clamp(-180.0, 180.0).toDouble();
    widget.onChanged(clamped);
    _setText(_formatDegrees(clamped));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    return SizedBox(
      height: 30,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        textAlign: TextAlign.right,
        style: TextStyle(fontSize: 11.5, color: colors.textPrimary),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]')),
        ],
        onChanged: _handleChanged,
        onSubmitted: (_) => _commit(),
        onTapOutside: (_) => _focusNode.unfocus(),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 7,
          ),
          suffixText: '°',
          suffixStyle: TextStyle(fontSize: 9.5, color: colors.textMuted),
        ),
      ),
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({required this.document});

  final ImageDocument document;

  @override
  Widget build(BuildContext context) {
    final dimensions = document.hasSize
        ? '${document.rotatedWidth.round()} × '
              '${document.rotatedHeight.round()} px'
        : '读取尺寸中…';
    final colors = context.palette;

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: Icon(
              Icons.image_outlined,
              size: 16,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  document.isRotated
                      ? '$dimensions · 已旋转 '
                            '${_formatDegrees(document.rotationDegrees)}°'
                      : dimensions,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: colors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: document.hasSelection
                  ? colors.accentSoft
                  : colors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: document.hasSelection
                    ? colors.accent.withValues(alpha: 0.35)
                    : colors.danger.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.grid_view_rounded,
                  size: 12,
                  color: document.hasSelection ? colors.accent : colors.danger,
                ),
                const SizedBox(width: 5),
                Text(
                  '${document.selectedCount}/${document.cellCount} 块',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: document.hasSelection
                        ? colors.accent
                        : colors.danger,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyEditor extends StatelessWidget {
  const _EmptyEditor();

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colors.surfaceHigh, colors.surfaceAlt],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: colors.border),
            ),
            child: Icon(
              Icons.auto_awesome_mosaic_outlined,
              size: 36,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            '选择一张图片开始编辑',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '添加水平 / 竖直分割线，自由选择需要导出的块\n支持任意角度旋转，辅助线始终保持水平 / 垂直',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.7,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: 14),
          Text(
            '正在解码图片…',
            style: TextStyle(fontSize: 11.5, color: context.palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.path,
    required this.onRetry,
  });

  final String message;
  final String path;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 34, color: colors.danger),
            const SizedBox(height: 14),
            Text(
              '无法加载这张图片',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: colors.textMuted),
            ),
            const SizedBox(height: 6),
            Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: colors.textMuted),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text('重新加载'),
            ),
          ],
        ),
      ),
    );
  }
}
