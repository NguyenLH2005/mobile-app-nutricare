import 'package:flutter/material.dart';
import '../../data/models/scan_history_model.dart';
import 'full_screen_image.dart';

/// Displays a square thumbnail for a [ScanHistory] item from local file or Base64 bytes.
class ScanThumbnail extends StatelessWidget {
  final ScanHistory item;
  final double size;
  final bool openFullScreenOnTap;

  const ScanThumbnail({
    super.key,
    required this.item,
    this.size = 56,
    this.openFullScreenOnTap = false,
  });

  Widget _buildPlaceholder() {
    return Container(
      width: size,
      height: size,
      color: Colors.green.shade50,
      child: const Icon(Icons.fastfood, color: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final validFile = item.foodImageFile;
    final memoryBytes = validFile == null ? item.foodImageBytes : null;

    Widget content;
    if (validFile != null) {
      content = Image.file(
        validFile,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    } else if (memoryBytes != null) {
      content = Image.memory(
        memoryBytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    } else {
      content = _buildPlaceholder();
    }

    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: content,
    );

    if (!openFullScreenOnTap) return clipped;

    return GestureDetector(
      onTap: () {
        if (validFile != null || memoryBytes != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FullScreenImage(
                imageFile: validFile,
                imageBytes: memoryBytes,
              ),
            ),
          );
        }
      },
      child: clipped,
    );
  }
}
