import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/image_document.dart';

/// 图片编辑画布：缩放 / 平移、分割线拖动、块点击选中与旋转预览。
///
/// 渲染分为两个独立图层：
/// * 图片图层：仅承载旋转后的图片画面，任意角度旋转只影响该图层；
/// * 辅助线图层：水平 / 竖直参考线与块选区，始终固定为屏幕正交方向，
///   完全不参与图片的旋转变换。
class SplitCanvas extends StatefulWidget {
  const SplitCanvas({
    super.key,
    required this.document,
    required this.image,
    required this.onMoveHorizontalCut,
    required this.onMoveVerticalCut,
    required this.onToggleCell,
    required this.onDeleteCut,
  });

  final ImageDocument document;
  final ui.Image image;
  final void Function(int index, double value) onMoveHorizontalCut;
  final void Function(int index, double value) onMoveVerticalCut;
  final void Function(int row, int column) onToggleCell;
  final void Function(CutAxis axis, int index) onDeleteCut;

  @override
  State<SplitCanvas> createState() => _SplitCanvasState();
}

class _CutHit {
  const _CutHit(this.axis, this.index);

  final CutAxis axis;
  final int index;

  @override
  bool operator ==(Object other) =>
      other is _CutHit && other.axis == axis && other.index == index;

  @override
  int get hashCode => Object.hash(axis, index);
}

class _SplitCanvasState extends State<SplitCanvas> {
  double _zoom = 1;
  Offset _pan = Offset.zero;

  Size _viewport = Size.zero;
  Size _baseSize = const Size(1, 1);
  ui.Image? _lastImage;

  _CutHit? _hoverCut;
  _CutHit? _draggingCut;
  ({int row, int column})? _hoverCell;

  final GlobalKey _hintKey = GlobalKey();
  bool _hintObscured = false;

  bool _panning = false;
  bool _tapCandidate = false;
  bool _moved = false;
  Offset _pointerDown = Offset.zero;

  Rect get _contentRect {
    final width = _baseSize.width * _zoom;
    final height = _baseSize.height * _zoom;
    return Rect.fromCenter(
      center: Offset(
        _viewport.width / 2 + _pan.dx,
        _viewport.height / 2 + _pan.dy,
      ),
      width: width,
      height: height,
    );
  }

  Offset get _viewportCenter =>
      Offset(_viewport.width / 2, _viewport.height / 2);

  void _fit() {
    setState(() {
      _zoom = 1;
      _pan = Offset.zero;
    });
  }

  void _applyZoom(double targetZoom, Offset anchor) {
    final newZoom = targetZoom.clamp(0.15, 20.0).toDouble();
    if ((newZoom - _zoom).abs() < 0.0001) return;

    final rect = _contentRect;
    if (rect.width <= 0 || rect.height <= 0) return;
    final fx = (anchor.dx - rect.left) / rect.width;
    final fy = (anchor.dy - rect.top) / rect.height;

    final newWidth = _baseSize.width * newZoom;
    final newHeight = _baseSize.height * newZoom;
    final newCenter = Offset(
      anchor.dx - fx * newWidth + newWidth / 2,
      anchor.dy - fy * newHeight + newHeight / 2,
    );

    setState(() {
      _zoom = newZoom;
      _pan = newCenter - _viewportCenter;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        final bounds = rotatedBoundsFor(
          widget.image.width,
          widget.image.height,
          widget.document.rotationDegrees,
        );
        final boundsWidth = math.max(bounds.width, 1.0);
        final boundsHeight = math.max(bounds.height, 1.0);

        if (size != _viewport || widget.image != _lastImage) {
          _viewport = size;
          _lastImage = widget.image;
          _zoom = 1;
          _pan = Offset.zero;
        }

        const inset = 44.0;
        final availableWidth = math.max(size.width - inset * 2, 64.0);
        final availableHeight = math.max(size.height - inset * 2, 64.0);
        final fitScale = math.min(
          availableWidth / boundsWidth,
          availableHeight / boundsHeight,
        );
        _baseSize = Size(boundsWidth * fitScale, boundsHeight * fitScale);

        final rect = _contentRect;
        final colors = context.palette;
        final scheme = Theme.of(context).colorScheme;

        return Stack(
          children: [
            Positioned.fill(
              child: MouseRegion(
                cursor: _cursor(),
                onHover: (event) => _updateHover(event.localPosition),
                onExit: (_) => _clearHover(),
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: (_) => _resetPointerState(),
                  onPointerSignal: _onPointerSignal,
                  // 放大 / 平移后图片会超出画布范围，必须裁剪，
                  // 否则会覆盖左侧图片库与顶部工具栏。
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        RepaintBoundary(
                          child: CustomPaint(
                            painter: _ImageLayerPainter(
                              image: widget.image,
                              rotationRadians: widget.document.rotationRadians,
                              boundsWidth: boundsWidth,
                              boundsHeight: boundsHeight,
                              rect: rect,
                              shadowColor: scheme.shadow,
                              checkerDark: colors.surfaceAlt,
                              checkerLight: colors.surfaceHigh,
                            ),
                          ),
                        ),
                        RepaintBoundary(
                          child: CustomPaint(
                            painter: _GuideLayerPainter(
                              horizontalCuts: widget.document.horizontalCuts,
                              verticalCuts: widget.document.verticalCuts,
                              rowCount: widget.document.rowCount,
                              columnCount: widget.document.columnCount,
                              isSelected: widget.document.isCellSelected,
                              rect: rect,
                              hoverCut: _hoverCut,
                              activeCut: _draggingCut,
                              hoverCell: _hoverCell,
                              boundsWidth: boundsWidth,
                              boundsHeight: boundsHeight,
                              horizontalColor: colors.horizontalLine,
                              verticalColor: colors.verticalLine,
                              accentColor: colors.accent,
                              dimColor: scheme.scrim,
                              borderColor: colors.borderStrong,
                              labelBackground: colors.surfaceHigh,
                              labelTextColor: colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 16,
              top: 16,
              bottom: 16,
              child: Align(
                alignment: Alignment.centerRight,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: _buildToolRail(),
                ),
              ),
            ),
            if (size.width > 700)
              Positioned(
                left: 16,
                bottom: 16,
                // 鼠标靠近提示区域时淡出，避免遮挡画面与分割线操作。
                child: AnimatedOpacity(
                  key: _hintKey,
                  opacity: _hintObscured ? 0 : 1,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  child: _buildHint(),
                ),
              ),
            Positioned(
              right: 16,
              bottom: 16,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: _buildZoomBar(),
              ),
            ),
          ],
        );
      },
    );
  }

  MouseCursor _cursor() {
    if (_panning) return SystemMouseCursors.grabbing;
    final hit = _draggingCut ?? _hoverCut;
    if (hit != null) {
      return hit.axis == CutAxis.horizontal
          ? SystemMouseCursors.resizeUpDown
          : SystemMouseCursors.resizeLeftRight;
    }
    return SystemMouseCursors.grab;
  }

  BoxDecoration _overlayDecoration(BuildContext context) {
    final colors = context.palette;
    return BoxDecoration(
      color: colors.surfaceHigh,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: colors.borderStrong),
      boxShadow: [
        BoxShadow(
          color: Theme.of(
            context,
          ).colorScheme.shadow.withValues(alpha: 0.22),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  Widget _buildHint() {
    final colors = context.palette;
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: colors.surfaceHigh,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LegendDot(color: colors.horizontalLine),
            const SizedBox(width: 4),
            Text(
              '水平线',
              style: TextStyle(fontSize: 10.5, color: colors.textMuted),
            ),
            const SizedBox(width: 9),
            _LegendDot(color: colors.verticalLine),
            const SizedBox(width: 4),
            Text(
              '竖直线',
              style: TextStyle(fontSize: 10.5, color: colors.textMuted),
            ),
            const SizedBox(width: 12),
            Text(
              '拖动调位置 · 右键删除 · 点击块切换导出 · 滚轮缩放',
              style: TextStyle(fontSize: 10.5, color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  /// 悬浮在预览区右侧的竖直工具栏：旋转、分割线与复位。
  Widget _buildToolRail() {
    final document = widget.document;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: _overlayDecoration(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RailButton(
            icon: Icons.rotate_90_degrees_ccw_outlined,
            tooltip: '向左旋转 90°',
            onTap: () => document.rotate(clockwise: false),
          ),
          _RailButton(
            icon: Icons.rotate_90_degrees_cw_outlined,
            tooltip: '向右旋转 90°',
            onTap: () => document.rotate(),
          ),
          const _RailDivider(),
          _RailButton(
            icon: Icons.horizontal_rule_rounded,
            tooltip: '添加水平分割线',
            onTap: document.addHorizontalCut,
          ),
          _RailButton(
            icon: Icons.vertical_split_rounded,
            tooltip: '添加竖直分割线',
            onTap: document.addVerticalCut,
          ),
          const _RailDivider(),
          _RailButton(
            icon: Icons.restart_alt_rounded,
            tooltip: '复位旋转',
            onTap: document.isRotated ? document.resetRotation : null,
          ),
        ],
      ),
    );
  }

  Widget _buildZoomBar() {
    final colors = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      decoration: _overlayDecoration(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(
            icon: Icons.remove_rounded,
            tooltip: '缩小',
            onTap: () => _applyZoom(_zoom / 1.25, _viewportCenter),
          ),
          SizedBox(
            width: 46,
            child: Text(
              '${(_zoom * 100).round()}%',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ),
          _ZoomButton(
            icon: Icons.add_rounded,
            tooltip: '放大',
            onTap: () => _applyZoom(_zoom * 1.25, _viewportCenter),
          ),
          Container(width: 1, height: 16, color: colors.border),
          _ZoomButton(
            icon: Icons.fit_screen_outlined,
            tooltip: '适应窗口',
            onTap: _fit,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 指针交互（同时兼容鼠标、触摸与触控笔）
  // ---------------------------------------------------------------------------

  bool _isPrimaryPress(PointerDownEvent event) {
    if (event.buttons == kPrimaryMouseButton) return true;
    return event.kind == PointerDeviceKind.touch ||
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointerDown = event.localPosition;
    _moved = false;
    _tapCandidate = false;

    final isMouse = event.kind == PointerDeviceKind.mouse;
    if (isMouse && event.buttons == kSecondaryMouseButton) {
      final hit = _hitCut(event.localPosition);
      if (hit != null) {
        widget.onDeleteCut(hit.axis, hit.index);
        setState(() {
          _hoverCut = null;
          _hoverCell = null;
        });
      }
      return;
    }

    if (!_isPrimaryPress(event)) return;

    final hit = _hitCut(event.localPosition);
    if (hit != null) {
      setState(() {
        _draggingCut = hit;
        _hoverCut = hit;
        _hoverCell = null;
      });
      return;
    }

    setState(() {
      _panning = true;
      _tapCandidate = true;
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if ((event.localPosition - _pointerDown).distance > 3) _moved = true;

    final dragging = _draggingCut;
    if (dragging != null) {
      final rect = _contentRect;
      if (rect.width <= 0 || rect.height <= 0) return;
      final nx = ((event.localPosition.dx - rect.left) / rect.width)
          .clamp(0.0, 1.0)
          .toDouble();
      final ny = ((event.localPosition.dy - rect.top) / rect.height)
          .clamp(0.0, 1.0)
          .toDouble();
      if (dragging.axis == CutAxis.horizontal) {
        widget.onMoveHorizontalCut(dragging.index, ny);
      } else {
        widget.onMoveVerticalCut(dragging.index, nx);
      }
      return;
    }

    if (_panning) {
      setState(() => _pan += event.delta);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final shouldToggle = _tapCandidate && !_moved;
    _resetPointerState();
    if (shouldToggle) {
      final cell = _cellAt(event.localPosition);
      if (cell != null) widget.onToggleCell(cell.row, cell.column);
    }
    _updateHover(event.localPosition);
  }

  void _resetPointerState() {
    setState(() {
      _draggingCut = null;
      _panning = false;
      _tapCandidate = false;
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final factor = math.exp(-event.scrollDelta.dy * 0.0016);
    _applyZoom(_zoom * factor, event.localPosition);
  }

  void _updateHover(Offset position) {
    _updateHintProximity(position);
    if (_draggingCut != null || _panning) return;
    final cut = _hitCut(position);
    final cell = cut == null ? _cellAt(position) : null;
    if (cut != _hoverCut || cell != _hoverCell) {
      setState(() {
        _hoverCut = cut;
        _hoverCell = cell;
      });
    }
  }

  /// 提示条位于左下角，指针进入其外扩区域时隐藏。
  void _updateHintProximity(Offset position) {
    final box = _hintKey.currentContext?.findRenderObject();
    var obscured = false;
    if (box is RenderBox && box.hasSize) {
      final hintRect = Rect.fromLTWH(
        16,
        _viewport.height - 16 - box.size.height,
        box.size.width,
        box.size.height,
      );
      obscured = hintRect.inflate(24).contains(position);
    }
    if (obscured != _hintObscured) {
      setState(() => _hintObscured = obscured);
    }
  }

  void _clearHover() {
    if (_hintObscured) {
      setState(() => _hintObscured = false);
    }
    if (_draggingCut != null) return;
    if (_hoverCut == null && _hoverCell == null) return;
    setState(() {
      _hoverCut = null;
      _hoverCell = null;
    });
  }

  _CutHit? _hitCut(Offset position) {
    final rect = _contentRect;
    if (rect.width <= 0 || rect.height <= 0) return null;
    if (position.dx < rect.left - 12 ||
        position.dx > rect.right + 12 ||
        position.dy < rect.top - 12 ||
        position.dy > rect.bottom + 12) {
      return null;
    }

    _CutHit? best;
    var bestDistance = 9.0;
    final verticalCuts = widget.document.verticalCuts;
    for (var i = 0; i < verticalCuts.length; i++) {
      final x = rect.left + verticalCuts[i] * rect.width;
      final distance = (position.dx - x).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = _CutHit(CutAxis.vertical, i);
      }
    }
    final horizontalCuts = widget.document.horizontalCuts;
    for (var i = 0; i < horizontalCuts.length; i++) {
      final y = rect.top + horizontalCuts[i] * rect.height;
      final distance = (position.dy - y).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = _CutHit(CutAxis.horizontal, i);
      }
    }
    return best;
  }

  ({int row, int column})? _cellAt(Offset position) {
    final rect = _contentRect;
    if (rect.width <= 0 || rect.height <= 0) return null;
    if (!rect.contains(position)) return null;
    final nx = (position.dx - rect.left) / rect.width;
    final ny = (position.dy - rect.top) / rect.height;
    return (
      row: _bandIndex(ny, widget.document.horizontalCuts),
      column: _bandIndex(nx, widget.document.verticalCuts),
    );
  }

  static int _bandIndex(double value, List<double> cuts) {
    for (var i = 0; i < cuts.length; i++) {
      if (value < cuts[i]) return i;
    }
    return cuts.length;
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 16,
            color: context.palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(
            icon,
            size: 17,
            color: enabled
                ? colors.textSecondary
                : colors.textMuted.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

class _RailDivider extends StatelessWidget {
  const _RailDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: context.palette.border,
    );
  }
}

/// 图片图层：棋盘格背景、投影与旋转后的图片画面。
///
/// 只有这一层会应用 [rotationRadians] 变换。
class _ImageLayerPainter extends CustomPainter {
  _ImageLayerPainter({
    required this.image,
    required this.rotationRadians,
    required this.boundsWidth,
    required this.boundsHeight,
    required this.rect,
    required this.shadowColor,
    required this.checkerDark,
    required this.checkerLight,
  });

  final ui.Image image;
  final double rotationRadians;
  final double boundsWidth;
  final double boundsHeight;
  final Rect rect;
  final Color shadowColor;
  final Color checkerDark;
  final Color checkerLight;

  @override
  void paint(Canvas canvas, Size size) {
    if (rect.width <= 0 || rect.height <= 0) return;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.shift(const Offset(0, 8)),
        const Radius.circular(8),
      ),
      Paint()
        ..color = shadowColor.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );

    _paintCheckerboard(canvas, size);
    _paintImage(canvas);
  }

  void _paintCheckerboard(Canvas canvas, Size size) {
    final visible = rect.intersect(Offset.zero & size);
    if (visible.isEmpty) return;
    const cellSize = 16.0;

    canvas.save();
    canvas.clipRect(visible);
    final startX =
        rect.left + ((visible.left - rect.left) / cellSize).floor() * cellSize;
    final startY =
        rect.top + ((visible.top - rect.top) / cellSize).floor() * cellSize;
    final dark = Paint()..color = checkerDark;
    final light = Paint()..color = checkerLight;

    var rowIndex = ((startY - rect.top) / cellSize).round();
    for (var y = startY; y < visible.bottom; y += cellSize) {
      var columnIndex = ((startX - rect.left) / cellSize).round();
      for (var x = startX; x < visible.right; x += cellSize) {
        final paint = (rowIndex + columnIndex).isEven ? dark : light;
        canvas.drawRect(Rect.fromLTWH(x, y, cellSize, cellSize), paint);
        columnIndex++;
      }
      rowIndex++;
    }
    canvas.restore();
  }

  void _paintImage(Canvas canvas) {
    canvas.save();
    canvas.clipRect(rect);
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(rotationRadians);
    canvas.scale(rect.width / boundsWidth);
    canvas.drawImage(
      image,
      Offset(-image.width / 2, -image.height / 2),
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ImageLayerPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.rotationRadians != rotationRadians ||
      oldDelegate.boundsWidth != boundsWidth ||
      oldDelegate.boundsHeight != boundsHeight ||
      oldDelegate.rect != rect ||
      oldDelegate.shadowColor != shadowColor ||
      oldDelegate.checkerDark != checkerDark ||
      oldDelegate.checkerLight != checkerLight;
}

/// 辅助线图层：分割线、块选区与数值标签。
///
/// 所有元素都按屏幕坐标轴对齐绘制，不读取任何旋转信息，因此始终保持在
/// 绝对水平 / 垂直状态。
class _GuideLayerPainter extends CustomPainter {
  _GuideLayerPainter({
    required this.horizontalCuts,
    required this.verticalCuts,
    required this.rowCount,
    required this.columnCount,
    required this.isSelected,
    required this.rect,
    required this.hoverCut,
    required this.activeCut,
    required this.hoverCell,
    required this.boundsWidth,
    required this.boundsHeight,
    required this.horizontalColor,
    required this.verticalColor,
    required this.accentColor,
    required this.dimColor,
    required this.borderColor,
    required this.labelBackground,
    required this.labelTextColor,
  });

  final List<double> horizontalCuts;
  final List<double> verticalCuts;
  final int rowCount;
  final int columnCount;
  final bool Function(int row, int column) isSelected;
  final Rect rect;
  final _CutHit? hoverCut;
  final _CutHit? activeCut;
  final ({int row, int column})? hoverCell;
  final double boundsWidth;
  final double boundsHeight;
  final Color horizontalColor;
  final Color verticalColor;
  final Color accentColor;
  final Color dimColor;
  final Color borderColor;
  final Color labelBackground;
  final Color labelTextColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (rect.width <= 0 || rect.height <= 0) return;

    _paintCells(canvas);

    for (var i = 0; i < verticalCuts.length; i++) {
      final x = rect.left + verticalCuts[i] * rect.width;
      _paintCut(
        canvas,
        size,
        axis: CutAxis.vertical,
        index: i,
        start: Offset(x, rect.top),
        end: Offset(x, rect.bottom),
        color: verticalColor,
        label: 'X ${(verticalCuts[i] * boundsWidth).round()} px',
      );
    }
    for (var i = 0; i < horizontalCuts.length; i++) {
      final y = rect.top + horizontalCuts[i] * rect.height;
      _paintCut(
        canvas,
        size,
        axis: CutAxis.horizontal,
        index: i,
        start: Offset(rect.left, y),
        end: Offset(rect.right, y),
        color: horizontalColor,
        label: 'Y ${(horizontalCuts[i] * boundsHeight).round()} px',
      );
    }

    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = borderColor.withValues(alpha: 0.35)
        ..isAntiAlias = false,
    );
  }

  void _paintCells(Canvas canvas) {
    final xEdges = [0.0, ...verticalCuts, 1.0];
    final yEdges = [0.0, ...horizontalCuts, 1.0];
    final selectedPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.12);
    final dimPaint = Paint()..color = dimColor.withValues(alpha: 0.5);

    for (var row = 0; row < rowCount; row++) {
      for (var column = 0; column < columnCount; column++) {
        final cell = Rect.fromLTRB(
          rect.left + xEdges[column] * rect.width,
          rect.top + yEdges[row] * rect.height,
          rect.left + xEdges[column + 1] * rect.width,
          rect.top + yEdges[row + 1] * rect.height,
        );
        canvas.drawRect(
          cell,
          isSelected(row, column) ? selectedPaint : dimPaint,
        );
      }
    }

    final hovered = hoverCell;
    if (hovered != null) {
      final cell = Rect.fromLTRB(
        rect.left + xEdges[hovered.column] * rect.width,
        rect.top + yEdges[hovered.row] * rect.height,
        rect.left + xEdges[hovered.column + 1] * rect.width,
        rect.top + yEdges[hovered.row + 1] * rect.height,
      ).deflate(1);
      canvas.drawRect(
        cell,
        Paint()..color = labelTextColor.withValues(alpha: 0.06),
      );
      canvas.drawRect(
        cell,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = accentColor.withValues(alpha: 0.85),
      );
    }
  }

  void _paintCut(
    Canvas canvas,
    Size size, {
    required CutAxis axis,
    required int index,
    required Offset start,
    required Offset end,
    required Color color,
    required String label,
  }) {
    final hit = _CutHit(axis, index);
    final isActive = hit == activeCut || hit == hoverCut;

    if (isActive) {
      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = color.withValues(alpha: 0.22)
          ..strokeWidth = 9,
      );
    }

    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = color
        ..strokeWidth = isActive ? 2.4 : 1.5,
    );

    if (!isActive) return;

    final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    _paintHandle(canvas, center, color);
    _paintLabel(canvas, size, axis, center, label, color);
  }

  void _paintHandle(Canvas canvas, Offset center, Color color) {
    final handle = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 27, height: 15),
      const Radius.circular(7.5),
    );
    canvas.drawRRect(handle, Paint()..color = color);
    final dotPaint = Paint()..color = labelBackground;
    for (var offset = -5.0; offset <= 5.0; offset += 5.0) {
      canvas.drawCircle(center + Offset(offset, 0), 1.1, dotPaint);
    }
  }

  void _paintLabel(
    Canvas canvas,
    Size size,
    CutAxis axis,
    Offset center,
    String text,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          color: labelTextColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final chipWidth = painter.width + 16;
    final chipHeight = painter.height + 8;
    var left = axis == CutAxis.vertical
        ? center.dx - chipWidth / 2
        : rect.left + 10;
    var top = axis == CutAxis.vertical
        ? rect.top + 14
        : center.dy - chipHeight - 10;
    left = left
        .clamp(6.0, math.max(6.0, size.width - chipWidth - 6))
        .toDouble();
    top = top
        .clamp(6.0, math.max(6.0, size.height - chipHeight - 6))
        .toDouble();

    final chip = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, chipWidth, chipHeight),
      const Radius.circular(6),
    );
    canvas.drawRRect(chip, Paint()..color = labelBackground);
    canvas.drawRRect(
      chip,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.75),
    );
    painter.paint(canvas, Offset(left + 8, top + 4));
  }

  @override
  bool shouldRepaint(covariant _GuideLayerPainter oldDelegate) => true;
}
