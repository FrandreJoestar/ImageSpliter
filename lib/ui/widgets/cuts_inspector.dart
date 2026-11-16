import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../app_theme.dart';
import '../../models/image_document.dart';

/// 角度显示：整数不显示小数，其余保留一位小数。
String _formatAngle(double value) {
  final rounded = value.roundToDouble();
  if ((value - rounded).abs() < 1e-6) return rounded.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

/// 右侧检查器：块选择小地图、分割线的像素级调整、旋转状态。
class CutsInspector extends StatelessWidget {
  const CutsInspector({super.key, required this.document});

  final ImageDocument document;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    return Container(
      color: colors.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Section(
              title: '导出块',
              trailing: _CountChip(
                '${document.selectedCount} / ${document.cellCount}',
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BlockMiniMap(document: document),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _MiniAction(
                          label: '全选',
                          onTap: document.selectAllCells,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _MiniAction(
                          label: '反选',
                          onTap: document.invertCellSelection,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _MiniAction(
                          label: '清空',
                          onTap: document.clearCellSelection,
                        ),
                      ),
                    ],
                  ),
                  if (!document.hasSelection) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colors.danger.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: colors.danger,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              '未选择任何块，该图片不会被导出',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: colors.danger,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),
            _Section(
              title: '分割线',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CutGroup(
                    label: '水平分割线',
                    color: colors.horizontalLine,
                    pixelValues: [
                      for (var i = 0; i < document.horizontalCuts.length; i++)
                        document.horizontalCutPixels(i),
                    ],
                    onAdd: document.addHorizontalCut,
                    onRemove: document.removeHorizontalCut,
                    onChange: document.setHorizontalCutPixels,
                  ),
                  const SizedBox(height: 16),
                  _CutGroup(
                    label: '竖直分割线',
                    color: colors.verticalLine,
                    pixelValues: [
                      for (var i = 0; i < document.verticalCuts.length; i++)
                        document.verticalCutPixels(i),
                    ],
                    onAdd: document.addVerticalCut,
                    onRemove: document.removeVerticalCut,
                    onChange: document.setVerticalCutPixels,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '拖动分割线调整位置，右键可直接删除；\n也可以在上方输入精确像素值。',
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.6,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _Section(
              title: '方向',
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.rotate_90_degrees_cw_outlined,
                          size: 14,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '旋转 ${_formatAngle(document.rotationDegrees)}°',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${document.rotatedWidth.round()} × '
                      '${document.rotatedHeight.round()} px',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                  if (document.isRotated)
                    TextButton(
                      onPressed: document.resetRotation,
                      child: const Text('复位'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              '快捷键  Ctrl+O 导入 · Ctrl+Shift+O 文件夹 · Ctrl+E 导出',
              style: TextStyle(
                fontSize: 10,
                height: 1.6,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.trailing, required this.child});

  final String title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: colors.textSecondary,
              ),
            ),
            const Spacer(),
            ?trailing,
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.accent.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: colors.accent,
        ),
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 28),
        padding: EdgeInsets.zero,
        textStyle: const TextStyle(fontSize: 11),
      ),
      child: Text(label),
    );
  }
}

class _BlockMiniMap extends StatelessWidget {
  const _BlockMiniMap({required this.document});

  final ImageDocument document;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    final aspect = document.hasSize
        ? document.rotatedWidth / document.rotatedHeight
        : 1.5;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        var mapHeight = maxWidth / aspect;
        if (mapHeight > 168) mapHeight = 168;
        if (mapHeight < 58) mapHeight = 58;
        var mapWidth = mapHeight * aspect;
        if (mapWidth > maxWidth) {
          mapWidth = maxWidth;
          mapHeight = mapWidth / aspect;
        }

        return Center(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTapUp: (details) {
                final nx = (details.localPosition.dx / mapWidth)
                    .clamp(0.0, 0.999)
                    .toDouble();
                final ny = (details.localPosition.dy / mapHeight)
                    .clamp(0.0, 0.999)
                    .toDouble();
                final row = _bandIndex(ny, document.horizontalCuts);
                final column = _bandIndex(nx, document.verticalCuts);
                document.toggleCell(row, column);
              },
              child: CustomPaint(
                size: Size(mapWidth, mapHeight),
                painter: _MiniMapPainter(
                  document: document,
                  background: colors.surfaceAlt,
                  selected: colors.accent,
                  idle: colors.border,
                  border: colors.borderStrong,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static int _bandIndex(double value, List<double> cuts) {
    for (var i = 0; i < cuts.length; i++) {
      if (value < cuts[i]) return i;
    }
    return cuts.length;
  }
}

class _MiniMapPainter extends CustomPainter {
  _MiniMapPainter({
    required this.document,
    required this.background,
    required this.selected,
    required this.idle,
    required this.border,
  });

  final ImageDocument document;
  final Color background;
  final Color selected;
  final Color idle;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final borderRRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    canvas.drawRRect(borderRRect, Paint()..color = background);

    final xEdges = document.verticalEdges;
    final yEdges = document.horizontalEdges;
    final selectedPaint = Paint()..color = selected.withValues(alpha: 0.88);
    final idlePaint = Paint()..color = idle;

    for (var row = 0; row < document.rowCount; row++) {
      for (var column = 0; column < document.columnCount; column++) {
        final cell = Rect.fromLTRB(
          xEdges[column] * size.width,
          yEdges[row] * size.height,
          xEdges[column + 1] * size.width,
          yEdges[row + 1] * size.height,
        ).deflate(1);
        if (cell.width <= 0 || cell.height <= 0) continue;
        final radius = Radius.circular(mathMin(3, cell.shortestSide / 2));
        canvas.drawRRect(
          RRect.fromRectAndRadius(cell, radius),
          document.isCellSelected(row, column) ? selectedPaint : idlePaint,
        );
      }
    }

    canvas.drawRRect(
      borderRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = border,
    );
  }

  double mathMin(double a, double b) => a < b ? a : b;

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) => true;
}

class _CutGroup extends StatelessWidget {
  const _CutGroup({
    required this.label,
    required this.color,
    required this.pixelValues,
    required this.onAdd,
    required this.onRemove,
    required this.onChange,
  });

  final String label;
  final Color color;
  final List<int> pixelValues;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;
  final void Function(int index, int value) onChange;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${pixelValues.length}',
              style: TextStyle(fontSize: 10.5, color: colors.textMuted),
            ),
            const Spacer(),
            SizedBox(
              height: 26,
              child: TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 14),
                label: const Text('添加'),
                style: TextButton.styleFrom(
                  foregroundColor: color,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 26),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (pixelValues.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 10, top: 2),
            child: Text(
              '暂无$label',
              style: TextStyle(fontSize: 10.5, color: colors.textMuted),
            ),
          )
        else
          for (var i = 0; i < pixelValues.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colors.border),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _PixelField(
                      value: pixelValues[i],
                      onSubmitted: (value) => onChange(i, value),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: '删除该分割线',
                    child: InkWell(
                      onTap: () => onRemove(i),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          size: 15,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _PixelField extends StatefulWidget {
  const _PixelField({required this.value, required this.onSubmitted});

  final int value;
  final ValueChanged<int> onSubmitted;

  @override
  State<_PixelField> createState() => _PixelFieldState();
}

class _PixelFieldState extends State<_PixelField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _PixelField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.value != oldWidget.value) {
      _setText('${widget.value}');
    }
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _commit();
    }
  }

  void _setText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null) {
      _setText('${widget.value}');
      return;
    }
    widget.onSubmitted(parsed);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.right,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontSize: 11.5),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _commit(),
        onTapOutside: (_) => _focusNode.unfocus(),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          suffixText: 'px',
        ),
      ),
    );
  }
}
