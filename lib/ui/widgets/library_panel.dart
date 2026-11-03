import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../controllers/project_controller.dart';
import '../../models/image_document.dart';
import '../../services/image_processor.dart';

/// 左侧图片库：缩略图列表 + 选中态 + 移除操作。
class LibraryPanel extends StatelessWidget {
  const LibraryPanel({
    super.key,
    required this.controller,
    required this.onImportImages,
    required this.onImportFolder,
  });

  final ProjectController controller;
  final VoidCallback onImportImages;
  final VoidCallback onImportFolder;

  @override
  Widget build(BuildContext context) {
    final documents = controller.documents;
    final colors = context.palette;
    return Container(
      color: colors.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
            child: Row(
              children: [
                Text(
                  '图片库',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.accentSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${documents.length}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: colors.accent,
                    ),
                  ),
                ),
                const Spacer(),
                _HeaderAction(
                  tooltip: '导入图片',
                  icon: Icons.add_photo_alternate_outlined,
                  onTap: onImportImages,
                ),
                const SizedBox(width: 2),
                _HeaderAction(
                  tooltip: '导入文件夹',
                  icon: Icons.create_new_folder_outlined,
                  onTap: onImportFolder,
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: documents.isEmpty
                ? _EmptyLibrary(
                    onImportImages: onImportImages,
                    onImportFolder: onImportFolder,
                  )
                : Scrollbar(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      itemCount: documents.length,
                      itemBuilder: (context, index) {
                        final document = documents[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _LibraryTile(
                            document: document,
                            selected:
                                controller.selectedDocument?.id == document.id,
                            onTap: () => controller.select(document.id),
                            onRemove: () =>
                                controller.removeDocument(document.id),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          if (documents.isNotEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  Text(
                    '共 ${documents.length} 张',
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
                  const Spacer(),
                  Text(
                    '${controller.totalSelectedBlocks} 个块待导出',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 17, color: colors.textSecondary),
        ),
      ),
    );
  }
}

class _LibraryTile extends StatefulWidget {
  const _LibraryTile({
    required this.document,
    required this.selected,
    required this.onTap,
    required this.onRemove,
  });

  final ImageDocument document;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<_LibraryTile> createState() => _LibraryTileState();
}

class _LibraryTileState extends State<_LibraryTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    final selected = widget.selected;
    final hasSelection = document.hasSelection;
    final colors = context.palette;

    final borderColor = selected
        ? colors.accent.withValues(alpha: 0.75)
        : _hovered
        ? colors.borderStrong
        : Colors.transparent;
    final backgroundColor = selected
        ? colors.accent.withValues(alpha: 0.09)
        : _hovered
        ? colors.surfaceAlt
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.fromLTRB(8, 7, 6, 7),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: selected
                        ? colors.accent.withValues(alpha: 0.5)
                        : colors.border,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Transform.scale(
                  // 稍微放大，保证任意角度旋转后缩略图四角不露出空白。
                  scale: 1.45,
                  child: Transform.rotate(
                    angle: document.rotationRadians,
                    child: _LibraryThumbnail(
                      document: document,
                      colors: colors,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      document.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected
                            ? colors.textPrimary
                            : colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '横 ${document.horizontalCuts.length} · 竖 ${document.verticalCuts.length}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: colors.textMuted,
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          width: 2,
                          height: 2,
                          decoration: BoxDecoration(
                            color: colors.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          hasSelection
                              ? '${document.selectedCount}/${document.cellCount} 块'
                              : '未选块',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: hasSelection
                                ? colors.textSecondary
                                : colors.verticalLine,
                          ),
                        ),
                        if (document.isRotated) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.rotate_90_degrees_cw_outlined,
                            size: 11,
                            color: colors.textMuted,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 140),
                opacity: _hovered || selected ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !(_hovered || selected),
                  child: Tooltip(
                    message: '从项目移除',
                    child: InkWell(
                      onTap: widget.onRemove,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 缩略图：普通格式直接使用文件；HEIC / HEIF 走原生解码生成小尺寸预览。
class _LibraryThumbnail extends StatelessWidget {
  const _LibraryThumbnail({required this.document, required this.colors});

  final ImageDocument document;
  final AppPalette colors;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: colors.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(
        Icons.broken_image_outlined,
        size: 16,
        color: colors.textMuted,
      ),
    );

    if (!isHeicFile(document.path)) {
      return Image.file(
        File(document.path),
        fit: BoxFit.cover,
        cacheWidth: 160,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }

    return FutureBuilder<Uint8List?>(
      future: loadHeicThumbnail(document.path),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null) {
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            cacheWidth: 160,
            gaplessPlayback: true,
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            color: colors.surfaceAlt,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          );
        }
        return fallback;
      },
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.onImportImages,
    required this.onImportFolder,
  });

  final VoidCallback onImportImages;
  final VoidCallback onImportFolder;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.border),
              ),
              child: Icon(
                Icons.photo_library_outlined,
                size: 26,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '还没有图片',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '导入图片、整个文件夹，或直接把图片拖入窗口\n支持 JPG / PNG / WebP / BMP / GIF / TIFF / HEIC',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.6,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onImportImages,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                label: const Text('导入图片'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onImportFolder,
                icon: const Icon(Icons.folder_open_rounded, size: 16),
                label: const Text('导入文件夹'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
