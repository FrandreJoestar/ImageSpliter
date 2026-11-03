import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 切割线方向。
enum CutAxis { horizontal, vertical }

/// 把任意角度环绕到 [-180, 180] 区间。
double wrapDegrees(double degrees) {
  var value = degrees % 360;
  if (value > 180) value -= 360;
  // Dart 的取模结果非负，负方向恰好转到 180° 时保留 -180° 语义。
  if (value == 180 && degrees < 0) return -180;
  return value;
}

/// 图片旋转任意角度后，其画面内容的轴对齐外接矩形尺寸（未取整）。
///
/// 预览布局与导出裁剪共用同一套几何计算，保证「所见即所得」。
({double width, double height}) rotatedBoundsFor(
  int width,
  int height,
  double degrees,
) {
  final radians = degrees * math.pi / 180;
  final cos = math.cos(radians).abs();
  final sin = math.sin(radians).abs();
  return (
    width: width * cos + height * sin,
    height: width * sin + height * cos,
  );
}

/// 一个待导出的块（行 / 列均为 0 基，[number] 为从 1 开始的块序号）。
class CellRef {
  const CellRef({
    required this.row,
    required this.column,
    required this.number,
  });

  final int row;
  final int column;
  final int number;
}

/// 单张图片的完整编辑状态，是画布、检查器与导出共同使用的唯一数据源。
///
/// 分割线位置统一使用 [0, 1] 的归一化坐标保存（以外接矩形为基准），
/// 这样窗口缩放、预览降采样都不会影响精度；旋转只作用于图片画面本身，
/// 分割线始终保持屏幕水平 / 垂直，不随旋转一起转动。
class ImageDocument extends ChangeNotifier {
  ImageDocument({
    required this.id,
    required this.path,
    required this.fileName,
    int width = 0,
    int height = 0,
  }) : _originalWidth = width,
       _originalHeight = height;

  final String id;
  final String path;
  final String fileName;

  /// 分割线不能贴到图片边缘，避免导出 0 像素的块。
  static const double _edgePadding = 0.004;

  /// 相邻分割线之间的最小归一化间距。
  static const double _minGap = 0.004;

  int _originalWidth;
  int _originalHeight;
  double _rotationDegrees = 0;

  final List<double> _horizontalCuts = [];
  final List<double> _verticalCuts = [];

  /// 选中的单元格，key = row * columnCount + column。
  final Set<int> _selectedCells = {0};

  int get originalWidth => _originalWidth;
  int get originalHeight => _originalHeight;
  bool get hasSize => _originalWidth > 0 && _originalHeight > 0;

  /// 当前旋转角度，范围 [-180, 180]，支持任意小数。
  double get rotationDegrees => _rotationDegrees;
  double get rotationRadians => _rotationDegrees * math.pi / 180;
  bool get isRotated => _rotationDegrees.abs() > 1e-6;

  /// 旋转后画面外接矩形的宽高（预览布局与导出共用）。
  double get rotatedWidth {
    if (!hasSize) return 1;
    final bounds = rotatedBoundsFor(
      _originalWidth,
      _originalHeight,
      _rotationDegrees,
    );
    return math.max(bounds.width, 1.0);
  }

  double get rotatedHeight {
    if (!hasSize) return 1;
    final bounds = rotatedBoundsFor(
      _originalWidth,
      _originalHeight,
      _rotationDegrees,
    );
    return math.max(bounds.height, 1.0);
  }

  List<double> get horizontalCuts => List.unmodifiable(_horizontalCuts);
  List<double> get verticalCuts => List.unmodifiable(_verticalCuts);

  int get rowCount => _horizontalCuts.length + 1;
  int get columnCount => _verticalCuts.length + 1;
  int get cellCount => rowCount * columnCount;
  int get selectedCount => _selectedCells.length;
  bool get hasSelection => _selectedCells.isNotEmpty;

  bool isCellSelected(int row, int column) =>
      _selectedCells.contains(row * columnCount + column);

  /// 从 1 开始的块序号，按行优先排列。
  int blockNumber(int row, int column) => row * columnCount + column + 1;

  int horizontalCutPixels(int index) {
    if (!hasSize) return 0;
    return (_horizontalCuts[index] * rotatedHeight).round();
  }

  int verticalCutPixels(int index) {
    if (!hasSize) return 0;
    return (_verticalCuts[index] * rotatedWidth).round();
  }

  /// 预览解码完成后回填真实像素尺寸（EXIF 方向已由解码器处理）。
  void updateSourceSize(int width, int height) {
    if (width <= 0 || height <= 0) return;
    if (width == _originalWidth && height == _originalHeight) return;
    _originalWidth = width;
    _originalHeight = height;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 块选择
  // ---------------------------------------------------------------------------

  void toggleCell(int row, int column) {
    if (row < 0 || row >= rowCount || column < 0 || column >= columnCount) {
      return;
    }
    final key = row * columnCount + column;
    if (!_selectedCells.remove(key)) {
      _selectedCells.add(key);
    }
    notifyListeners();
  }

  void selectAllCells() {
    _selectedCells
      ..clear()
      ..addAll(List<int>.generate(cellCount, (index) => index));
    notifyListeners();
  }

  void clearCellSelection() {
    if (_selectedCells.isEmpty) return;
    _selectedCells.clear();
    notifyListeners();
  }

  void invertCellSelection() {
    final inverted = <int>{
      for (var i = 0; i < cellCount; i++)
        if (!_selectedCells.contains(i)) i,
    };
    _selectedCells
      ..clear()
      ..addAll(inverted);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 分割线增删改
  // ---------------------------------------------------------------------------

  /// 在最大的空白区间中点添加一条水平分割线。
  void addHorizontalCut() {
    final value = _largestGapMidpoint(_horizontalCuts);
    final insertAt = _insertionIndex(_horizontalCuts, value);
    final oldRows = rowCount;
    final cols = columnCount;
    final oldSelection = Set<int>.of(_selectedCells);

    _horizontalCuts.insert(insertAt, value);
    _selectedCells.clear();
    for (var row = 0; row < oldRows; row++) {
      for (var column = 0; column < cols; column++) {
        if (!oldSelection.contains(row * cols + column)) continue;
        if (row < insertAt) {
          _selectedCells.add(row * cols + column);
        } else if (row == insertAt) {
          // 被切开的那一格：上下两半都继承选中状态。
          _selectedCells.add(row * cols + column);
          _selectedCells.add((row + 1) * cols + column);
        } else {
          _selectedCells.add((row + 1) * cols + column);
        }
      }
    }
    notifyListeners();
  }

  void addVerticalCut() {
    final value = _largestGapMidpoint(_verticalCuts);
    final insertAt = _insertionIndex(_verticalCuts, value);
    final oldCols = columnCount;
    final rows = rowCount;
    final oldSelection = Set<int>.of(_selectedCells);

    _verticalCuts.insert(insertAt, value);
    final newCols = oldCols + 1;
    _selectedCells.clear();
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < oldCols; column++) {
        if (!oldSelection.contains(row * oldCols + column)) continue;
        if (column < insertAt) {
          _selectedCells.add(row * newCols + column);
        } else if (column == insertAt) {
          _selectedCells.add(row * newCols + column);
          _selectedCells.add(row * newCols + column + 1);
        } else {
          _selectedCells.add(row * newCols + column + 1);
        }
      }
    }
    notifyListeners();
  }

  void moveHorizontalCut(int index, double value) {
    if (index < 0 || index >= _horizontalCuts.length) return;
    final lower = index == 0
        ? _edgePadding
        : _horizontalCuts[index - 1] + _minGap;
    final upper = index == _horizontalCuts.length - 1
        ? 1 - _edgePadding
        : _horizontalCuts[index + 1] - _minGap;
    if (upper < lower) return;
    final next = value.clamp(lower, upper).toDouble();
    if ((_horizontalCuts[index] - next).abs() < 1e-9) return;
    _horizontalCuts[index] = next;
    notifyListeners();
  }

  void moveVerticalCut(int index, double value) {
    if (index < 0 || index >= _verticalCuts.length) return;
    final lower = index == 0
        ? _edgePadding
        : _verticalCuts[index - 1] + _minGap;
    final upper = index == _verticalCuts.length - 1
        ? 1 - _edgePadding
        : _verticalCuts[index + 1] - _minGap;
    if (upper < lower) return;
    final next = value.clamp(lower, upper).toDouble();
    if ((_verticalCuts[index] - next).abs() < 1e-9) return;
    _verticalCuts[index] = next;
    notifyListeners();
  }

  void setHorizontalCutPixels(int index, int pixels) {
    if (!hasSize || index < 0 || index >= _horizontalCuts.length) return;
    moveHorizontalCut(index, pixels / rotatedHeight);
  }

  void setVerticalCutPixels(int index, int pixels) {
    if (!hasSize || index < 0 || index >= _verticalCuts.length) return;
    moveVerticalCut(index, pixels / rotatedWidth);
  }

  void removeHorizontalCut(int index) {
    if (index < 0 || index >= _horizontalCuts.length) return;
    final oldRows = rowCount;
    final cols = columnCount;
    final oldSelection = Set<int>.of(_selectedCells);
    final newRows = oldRows - 1;

    _horizontalCuts.removeAt(index);
    final next = <int>{};
    for (var row = 0; row < oldRows; row++) {
      for (var column = 0; column < cols; column++) {
        if (!oldSelection.contains(row * cols + column)) continue;
        final target = row < index ? row : (row <= index + 1 ? index : row - 1);
        if (target < newRows) next.add(target * cols + column);
      }
    }
    _selectedCells
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void removeVerticalCut(int index) {
    if (index < 0 || index >= _verticalCuts.length) return;
    final oldCols = columnCount;
    final rows = rowCount;
    final oldSelection = Set<int>.of(_selectedCells);
    final newCols = oldCols - 1;

    _verticalCuts.removeAt(index);
    final next = <int>{};
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < oldCols; column++) {
        if (!oldSelection.contains(row * oldCols + column)) continue;
        final target = column < index
            ? column
            : (column <= index + 1 ? index : column - 1);
        if (target < newCols) next.add(row * newCols + target);
      }
    }
    _selectedCells
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 旋转（任意角度，仅作用于图片画面，辅助线保持固定正交）
  // ---------------------------------------------------------------------------

  /// 设置旋转角度（度），会收敛到 [-180, 180] 区间。
  ///
  /// 只改变图片画面的旋转角度，分割线与选中块的数据保持不变。
  void setRotationDegrees(double degrees) {
    final next = degrees.clamp(-180.0, 180.0).toDouble();
    if ((next - _rotationDegrees).abs() < 1e-6) return;
    _rotationDegrees = next;
    notifyListeners();
  }

  /// 以 90° 为步进旋转，角度自动环绕到 [-180, 180]。
  void rotate({bool clockwise = true}) {
    setRotationDegrees(wrapDegrees(_rotationDegrees + (clockwise ? 90 : -90)));
  }

  /// 复位到 0°。
  void resetRotation() {
    setRotationDegrees(0);
  }

  // ---------------------------------------------------------------------------
  // 导出
  // ---------------------------------------------------------------------------

  /// 当前选中的块，按块序号升序排列。
  List<CellRef> get selectedCells {
    final cols = columnCount;
    final keys = _selectedCells.toList()..sort();
    return [
      for (final key in keys)
        CellRef(row: key ~/ cols, column: key % cols, number: key + 1),
    ];
  }

  List<double> get horizontalEdges => [0, ..._horizontalCuts, 1];
  List<double> get verticalEdges => [0, ..._verticalCuts, 1];

  static int _insertionIndex(List<double> cuts, double value) {
    for (var i = 0; i < cuts.length; i++) {
      if (cuts[i] > value) return i;
    }
    return cuts.length;
  }

  static double _largestGapMidpoint(List<double> cuts) {
    var bestMidpoint = 0.5;
    var bestGap = -1.0;
    var previous = 0.0;
    for (final cut in [...cuts, 1.0]) {
      final gap = cut - previous;
      if (gap > bestGap) {
        bestGap = gap;
        bestMidpoint = previous + gap / 2;
      }
      previous = cut;
    }
    return bestMidpoint.clamp(_edgePadding, 1 - _edgePadding).toDouble();
  }
}
