
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/scan_history_model.dart';
import '../state/scan_controller.dart';
import '../state/history_controller.dart';
import 'found_object_screen.dart';
import '../widgets/full_screen_image.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  bool isSelectionMode = false;
  Set<int> selectedIds = {};

  Widget _buildThumbnail(ScanHistory item) {
    final validFile = item.foodImageFile;
    final memoryBytes = validFile == null ? item.foodImageBytes : null;

    Widget content;
    if (validFile != null) {
      content = Image.file(
        validFile,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, stack) => _buildPlaceholder(),
      );
    } else if (memoryBytes != null) {
      content = Image.memory(
        memoryBytes,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, stack) => _buildPlaceholder(),
      );
    } else {
      content = _buildPlaceholder();
    }

    return GestureDetector(
      onTap: () {
        if (validFile != null || memoryBytes != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FullScreenImage(
                imageFile: validFile,
                imageBytes: memoryBytes,
              ),
            ),
          );
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: content,
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 60,
      height: 60,
      color: Colors.green.shade50,
      child: const Icon(
        Icons.fastfood,
        color: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final historyAsyncValue = ref.watch(historyProvider);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          isSelectionMode ? 'Đã chọn ${selectedIds.length}' : 'Lịch Sử Tra Cứu',
          style: const TextStyle(
            color: Colors.green,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 1,
        leading: isSelectionMode
            ? TextButton(
                onPressed: () {
                  setState(() {
                    isSelectionMode = false;
                    selectedIds.clear();
                  });
                },
                child: const Text(
                  'Hủy',
                  style: TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
        actions: isSelectionMode
            ? [
                TextButton(
                  onPressed: selectedIds.isEmpty
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Xác nhận xóa'),
                              content: Text(
                                'Bạn có chắc chắn muốn xóa ${selectedIds.length} mục đã chọn không?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text(
                                    'Không',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text(
                                    'Có',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            final itemsToDelete =
                                historyAsyncValue.value
                                    ?.where(
                                      (item) => selectedIds.contains(item.id),
                                    )
                                    .toList() ??
                                [];
                            await ref
                                .read(historyControllerProvider.notifier)
                                .deleteRecords(itemsToDelete);

                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Xóa thành công!'),
                              ),
                            );
                            setState(() {
                              isSelectionMode = false;
                              selectedIds.clear();
                            });
                          }
                        },
                  child: const Text(
                    'Xóa',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ]
            : null,
      ),
      body: historyAsyncValue.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: Colors.green)),
        error: (error, stack) => Center(child: Text('Lỗi tải dữ liệu: $error')),
        data: (data) {
          if (data.isEmpty) {
            return const Center(child: Text('Bạn chưa quét món ăn nào cả!'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: data.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = data[index];
              final isSelected = selectedIds.contains(item.id);

              final timeStr = DateFormat('HH:mm').format(item.createdAt);
              final dateStr = DateFormat('dd/MM/yyyy').format(item.createdAt);

              final nutritionList = item.decodedNutrition;
              final energyItem = nutritionList.firstWhere(
                (e) => e['id'] == 'energy',
                orElse: () => {'per_label': 0},
              );
              final double cRatio = item.consumptionRatio > 0 ? item.consumptionRatio : 1.0;
              final double rawKcal = (energyItem['per_label'] as num?)?.toDouble() ?? 0.0;
              final kcal = (rawKcal * cRatio).toStringAsFixed(0);

              return InkWell(
                onLongPress: () {
                  if (!isSelectionMode) {
                    setState(() {
                      isSelectionMode = true;
                      selectedIds.add(item.id!);
                    });
                  }
                },
                onTap: () {
                  if (isSelectionMode) {
                    setState(() {
                      if (isSelected) {
                        selectedIds.remove(item.id!);
                      } else {
                        selectedIds.add(item.id!);
                      }
                    });
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            FoundObjectScreen(resultData: item),
                      ),
                    );
                  }
                },
                child: Row(
                  children: [
                    if (isSelectionMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: isSelected
                              ? Colors.green
                              : Colors.grey.shade400,
                          size: 24,
                        ),
                      ),
                    Expanded(
                      child: Card(
                        elevation: 0,
                        color: isSelected ? Colors.green.shade50 : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isSelected
                                ? Colors.green
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              _buildThumbnail(item),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.foodName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    if (item.weight != null)
                                      Text(
                                        item.consumptionRatio < 0.99
                                            ? 'Ăn: ${item.actualWeight.toStringAsFixed(0)}g • ${(item.consumptionRatio * 100).round()}% khay'
                                            : item.formatWeight(spaceBeforeUnit: false),
                                        style: TextStyle(
                                          color: item.consumptionRatio < 0.99 ? Colors.green.shade700 : Colors.grey.shade600,
                                          fontWeight: item.consumptionRatio < 0.99 ? FontWeight.w600 : FontWeight.normal,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '$kcal kcal',
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$timeStr\n$dateStr',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
