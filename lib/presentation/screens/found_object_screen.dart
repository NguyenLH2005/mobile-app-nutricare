import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/scan_history_model.dart';
import '../../domain/usecases/nutrition_suggestion_usecase.dart';

import '../state/scan_controller.dart';
import '../state/history_controller.dart';
import '../state/profile_controller.dart';
import '../state/sync_controller.dart';

import 'result_screen.dart';
import 'edit_profile_screen.dart';
import 'daily_progress_screen.dart';
import '../widgets/full_screen_image.dart';

class EggOption {
  final String id;
  final String displayName;
  final String csvSearchName;
  final double weightPerUnit;

  const EggOption({
    required this.id,
    required this.displayName,
    required this.csvSearchName,
    required this.weightPerUnit,
  });
}

const List<EggOption> standardEggOptions = [
  EggOption(
    id: 'chicken_egg',
    displayName: 'Trứng gà (công nghiệp)',
    csvSearchName: 'Trứng gà công nghiệp',
    weightPerUnit: 50.0,
  ),
  EggOption(
    id: 'local_chicken_egg',
    displayName: 'Trứng gà ta',
    csvSearchName: 'Trứng gà ta',
    weightPerUnit: 38.0,
  ),
  EggOption(
    id: 'duck_egg',
    displayName: 'Trứng vịt',
    csvSearchName: 'Trứng vịt',
    weightPerUnit: 60.0,
  ),
  EggOption(
    id: 'balut_egg',
    displayName: 'Trứng vịt lộn',
    csvSearchName: 'Trứng vịt lộn',
    weightPerUnit: 70.0,
  ),
];

class FoundObjectScreen extends ConsumerStatefulWidget {
  final ScanHistory resultData;
  final bool isFromScan;

  const FoundObjectScreen({
    super.key, 
    required this.resultData, 
    this.isFromScan = false,
  });

  @override
  ConsumerState<FoundObjectScreen> createState() => _FoundObjectScreenState();
}

class _FoundObjectScreenState extends ConsumerState<FoundObjectScreen> {
  late ScanHistory _currentData;
  String? _suggestionText;
  bool _isLoadingSuggestion = false;
  String? _suggestionError;

  bool get _isEggFood {
    final name = _currentData.foodName.toLowerCase();
    return name.contains('trứng') || name.contains('egg');
  }

  EggOption get _matchedEggOption {
    return standardEggOptions.firstWhere(
      (opt) => _currentData.foodName.toLowerCase().contains(opt.displayName.toLowerCase()) ||
               _currentData.foodName.toLowerCase().contains(opt.csvSearchName.toLowerCase()),
      orElse: () => standardEggOptions[0],
    );
  }

  int get _eggQuantity {
    if (_currentData.weight != null && _currentData.weight! > 0) {
      final qty = (_currentData.weight! / _matchedEggOption.weightPerUnit).round();
      return qty < 1 ? 1 : qty;
    }
    return 1;
  }

  @override
  void initState() {
    super.initState();
    _currentData = widget.resultData;
    _suggestionText = _currentData.aiSuggestion;
    if (widget.isFromScan) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (_isEggFood) {
          await _showEggSelectionModal();
        }
        if (_suggestionText == null && !_isLoadingSuggestion) {
          _fetchSuggestion();
        }
      });
    }
  }

  Future<void> _fetchSuggestion() async {
    if (_isLoadingSuggestion) return;

    final profileState = ref.read(profileProvider);
    if (profileState.tdee == null || profileState.profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Bạn cần nhập thông số cá nhân để có thể nhận được gợi ý dinh dưỡng.'),
          action: SnackBarAction(
            label: 'Nhập ngay',
            textColor: Colors.amber,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              );
            },
          ),
        ),
      );
      return;
    }

    setState(() {
      _isLoadingSuggestion = true;
      _suggestionError = null;
    });

    var rawFoodData = ref.read(foodRepositoryProvider).findFoodByName(_currentData.foodName);
    if (rawFoodData == null) {
      final decoded = _currentData.decodedNutrition;
      final Map<String, dynamic> fallbackData = {};
      for (var item in decoded) {
        final id = item['id'];
        final val = item['per_100g'] ?? item['per_label'] ?? 0;
        if (id == 'energy') fallbackData['Năng lượng'] = val;
        if (id == 'protein') fallbackData['Chất đạm'] = val;
        if (id == 'fat') fallbackData['Chất béo (Fat)'] = val;
        if (id == 'carb') fallbackData['Chất bột đường'] = val;
        if (id == 'fiber') fallbackData['Chất xơ'] = val;
      }
      if (fallbackData.isNotEmpty) {
        rawFoodData = fallbackData;
      }
    }

    if (rawFoodData == null) {
      if (mounted) {
        setState(() {
          _isLoadingSuggestion = false;
          _suggestionError = 'Không tìm thấy dữ liệu gốc của thực phẩm.';
        });
      }
      return;
    }

    try {
      final suggestion = await NutritionSuggestionUseCase.generateSuggestion(
        profile: profileState.profile!,
        mainGroupStr: _currentData.mainGroup,
        foodName: _currentData.foodName,
        rawFoodData: rawFoodData,
        weight: _currentData.actualWeight,
      );
      if (mounted) {
        setState(() {
          _suggestionText = suggestion;
          _isLoadingSuggestion = false;
        });
      }

      // Lưu vĩnh viễn gợi ý vào SQLite và đồng bộ lên đám mây
      final updatedData = _currentData.copyWith(
        aiSuggestion: suggestion,
        isSynced: 0,
        updatedAt: DateTime.now(),
      );
      if (_currentData.id != null) {
        await ref.read(historyControllerProvider.notifier).updateScan(updatedData);
        ref.read(syncProvider.notifier).syncNow();
      }
      if (mounted) {
        setState(() {
          _currentData = updatedData;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _suggestionError = 'Lỗi phân tích: $e';
          _isLoadingSuggestion = false;
        });
      }
    }
  }

  Future<void> _applyEggSelection(EggOption selectedEgg, int quantity) async {
    final double newWeight = quantity * selectedEgg.weightPerUnit;
    final foodData = ref.read(foodRepositoryProvider).findFoodByName(selectedEgg.csvSearchName);
    if (foodData == null) return;

    final String mainGroup = foodData['Nhóm Dinh Dưỡng Chính']?.toString().trim() ?? 'Protein, Chất béo';
    final List<Map<String, dynamic>> nutritionArray = 
        ref.read(foodRepositoryProvider).buildNutritionArray(foodData, newWeight);

    final updatedData = _currentData.copyWith(
      foodName: selectedEgg.displayName,
      weight: newWeight,
      nutritionData: jsonEncode(nutritionArray),
      mainGroup: mainGroup,
      isSynced: 0,
      updatedAt: DateTime.now(),
    );

    if (_currentData.id != null) {
      await ref.read(historyControllerProvider.notifier).updateScan(updatedData);
      ref.read(syncProvider.notifier).syncNow();
    }

    if (mounted) {
      setState(() {
        _currentData = updatedData;
      });
      _fetchSuggestion();
    }
  }

  Future<void> _showEggSelectionModal() async {
    EggOption selectedOption = _matchedEggOption;
    int quantity = _eggQuantity;

    final TextEditingController qtyController = TextEditingController(text: quantity.toString());

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final double currentWeight = quantity * selectedOption.weightPerUnit;

            void updateQuantity(int newQty) {
              if (newQty < 1) newQty = 1;
              setModalState(() {
                quantity = newQty;
                qtyController.text = quantity.toString();
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(bottomSheetContext).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Icon(Icons.egg_outlined, color: Colors.orange.shade800, size: 24),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Chọn Loại Trứng & Số Lượng',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1B233A),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.grey),
                            onPressed: () => Navigator.pop(bottomSheetContext),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Vui lòng chọn loại trứng bạn sử dụng để hệ thống tự động quy đổi khối lượng và giá trị dinh dưỡng chuẩn xác:',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
                      ),
                      const SizedBox(height: 14),

                      // 4 Tùy chọn trứng (Bỏ mô tả nhạt, thêm dấu ~ vào khối lượng)
                      ...standardEggOptions.map((opt) {
                        final isSelected = opt.id == selectedOption.id;
                        return InkWell(
                          onTap: () {
                            setModalState(() {
                              selectedOption = opt;
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.green.shade50.withValues(alpha: 0.6) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? Colors.green.shade600 : Colors.grey.shade200,
                                width: isSelected ? 1.8 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                  color: isSelected ? Colors.green.shade700 : Colors.grey.shade400,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    opt.displayName,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? Colors.green.shade900 : const Color(0xFF1B233A),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.green.shade100 : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '~${opt.weightPerUnit.toInt()}g/quả',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? Colors.green.shade800 : Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),

                      const SizedBox(height: 10),
                      const Divider(),
                      const SizedBox(height: 8),

                      // Stepper + Text Input (Chỉ nhập số nguyên, có thể gõ trực tiếp bàn phím)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Số lượng quả:',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B233A)),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Chạm vào số để nhập bàn phím',
                                style: TextStyle(fontSize: 11.5, color: Colors.grey),
                              ),
                            ],
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove, size: 20),
                                  onPressed: quantity > 1 ? () => updateQuantity(quantity - 1) : null,
                                  color: Colors.green.shade800,
                                  disabledColor: Colors.grey.shade300,
                                ),
                                SizedBox(
                                  width: 60,
                                  child: TextField(
                                    controller: qtyController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.green),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                                      border: InputBorder.none,
                                    ),
                                    onChanged: (val) {
                                      final parsed = int.tryParse(val);
                                      if (parsed != null && parsed >= 1) {
                                        setModalState(() {
                                          quantity = parsed;
                                        });
                                      }
                                    },
                                    onSubmitted: (val) {
                                      final parsed = int.tryParse(val);
                                      if (parsed == null || parsed < 1) {
                                        updateQuantity(1);
                                      }
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 20),
                                  onPressed: () => updateQuantity(quantity + 1),
                                  color: Colors.green.shade800,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Quy đổi khối lượng trực quan
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Quy đổi khối lượng:',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFC65102)),
                            ),
                            Text(
                              '$quantity quả × ~${selectedOption.weightPerUnit.toInt()}g = ${currentWeight.toInt()}g',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFC65102),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Nút Áp dụng (Không ghi số lượng vào nút)
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(bottomSheetContext);
                            _applyEggSelection(selectedOption, quantity);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          child: const Text(
                            'ÁP DỤNG',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _setConsumptionRatio(double newRatio) async {
    final list = _currentData.decodedNutrition;
    double p100 = 0, c100 = 0, f100 = 0;
    for (var item in list) {
      if (item['id'] == 'protein') p100 = (item['per_100g'] as num?)?.toDouble() ?? 0.0;
      if (item['id'] == 'carb') c100 = (item['per_100g'] as num?)?.toDouble() ?? 0.0;
      if (item['id'] == 'fat' || item['id'] == 'total_fat') f100 = (item['per_100g'] as num?)?.toDouble() ?? 0.0;
    }
    final actualW = (_currentData.weight ?? 100.0) * newRatio;
    final servingInfo = ref.read(foodRepositoryProvider).calculateServingUnit(
      mainGroup: _currentData.mainGroup,
      p100: p100,
      c100: c100,
      f100: f100,
      actualWeight: actualW,
    );

    final updatedData = _currentData.copyWith(
      consumptionRatio: newRatio,
      servingUnits: servingInfo.servingCount,
      isSynced: 0,
      updatedAt: DateTime.now(),
    );

    if (_currentData.id != null) {
      await ref.read(historyControllerProvider.notifier).updateScan(updatedData);
      ref.read(syncProvider.notifier).syncNow();
    }

    setState(() {
      _currentData = updatedData;
    });
    _fetchSuggestion();
  }

  Future<void> _showCustomRatioDialog() async {
    final textController = TextEditingController();
    int mode = 0; // 0: %, 1: g

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final totalWeight = _currentData.weight ?? 100.0;
          return AlertDialog(
            title: const Text('Tùy chỉnh lượng ăn thực tế'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Theo % khay'),
                      selected: mode == 0,
                      onSelected: (_) => setDialogState(() => mode = 0),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Theo số gam (g)'),
                      selected: mode == 1,
                      onSelected: (_) => setDialogState(() => mode = 1),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: textController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: mode == 0 ? 'Tỷ lệ % (1 - 100)' : 'Khối lượng ăn (g)',
                    hintText: mode == 0 ? 'Ví dụ: 30' : 'Ví dụ: 120',
                    suffixText: mode == 0 ? '%' : 'g',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tổng khối lượng trên nhãn: ${totalWeight.toStringAsFixed(0)}g',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                onPressed: () {
                  final val = double.tryParse(textController.text.trim().replaceAll(',', '.'));
                  if (val == null || val <= 0) return;
                  if (mode == 0) {
                    final ratio = (val / 100.0).clamp(0.01, 1.0);
                    Navigator.pop(ctx, ratio);
                  } else {
                    final ratio = (val / totalWeight).clamp(0.01, 2.0);
                    Navigator.pop(ctx, ratio);
                  }
                },
                child: const Text('Áp dụng'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null && result > 0) {
      await _setConsumptionRatio(result);
    }
  }

  Widget _buildRatioChip(double ratio, String label) {
    final bool isSelected = (_currentData.consumptionRatio - ratio).abs() < 0.02;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: Colors.green.shade100,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.green.shade900 : Colors.black87,
      ),
      onSelected: (_) => _setConsumptionRatio(ratio),
    );
  }

  Widget _buildCustomRatioChip() {
    final bool isStandard = [0.25, 0.50, 0.75, 1.0].any((r) => (_currentData.consumptionRatio - r).abs() < 0.02);
    return ActionChip(
      avatar: const Icon(Icons.edit, size: 14, color: Colors.blue),
      label: Text(
        isStandard ? 'Tùy chỉnh...' : '${(_currentData.consumptionRatio * 100).round()}%',
        style: TextStyle(
          fontSize: 12,
          fontWeight: isStandard ? FontWeight.normal : FontWeight.bold,
          color: Colors.blue.shade900,
        ),
      ),
      backgroundColor: isStandard ? Colors.blue.shade50 : Colors.blue.shade100,
      onPressed: _showCustomRatioDialog,
    );
  }

  Future<void> _editWeight() async {
    TextEditingController controller = TextEditingController(text: _currentData.weight?.toString() ?? '100');
    final newWeightStr = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nhập khối lượng mới (g)'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Ví dụ: 250'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Lưu')),
        ],
      ),
    );

    if (newWeightStr != null && newWeightStr.isNotEmpty) {
      double? newWeight = double.tryParse(newWeightStr);
      if (newWeight != null && newWeight > 0) {
        List<dynamic> jsonArr = jsonDecode(_currentData.nutritionData);
        for (var item in jsonArr) {
          if (item['per_100g'] != null) {
            item['per_label'] = double.parse(((item['per_100g'] as num) * (newWeight / 100)).toStringAsFixed(1));
          }
        }
        
        final updatedData = _currentData.copyWith(
          weight: newWeight,
          nutritionData: jsonEncode(jsonArr),
          isSynced: 0,
          updatedAt: DateTime.now(),
        );

        await ref.read(historyControllerProvider.notifier).updateScan(updatedData);
        ref.read(syncProvider.notifier).syncNow();

        setState(() {
          _currentData = updatedData;
        });
        _fetchSuggestion();
      }
    }
  }

  Widget _buildFoodImageWidget() {
    final validFile = _currentData.foodImageFile;
    final memoryBytes = validFile == null ? _currentData.foodImageBytes : null;

    Widget imageContent;
    if (validFile != null) {
      imageContent = Image.file(validFile, height: 120, fit: BoxFit.cover);
    } else if (memoryBytes != null) {
      imageContent = Image.memory(memoryBytes, height: 120, fit: BoxFit.cover);
    } else {
      imageContent = Container(
        height: 120,
        color: Colors.grey.shade200,
        child: const Center(child: Icon(Icons.fastfood, color: Colors.grey, size: 36)),
      );
    }

    final tag = _currentData.croppedFoodImage.isNotEmpty 
        ? _currentData.croppedFoodImage 
        : 'food_img_${_currentData.id ?? _currentData.createdAt.millisecondsSinceEpoch}';

    return GestureDetector(
      onTap: () {
        if (validFile != null || memoryBytes != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FullScreenImage(
                imageFile: validFile,
                imageBytes: memoryBytes,
                heroTag: tag,
              ),
            ),
          );
        }
      },
      child: Hero(
        tag: tag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: imageContent,
        ),
      ),
    );
  }

  Widget _buildLabelImageWidget() {
    final validFile = _currentData.labelImageFile;
    final memoryBytes = validFile == null ? _currentData.labelImageBytes : null;

    if (validFile == null && memoryBytes == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 120,
          color: Colors.grey.shade200,
          child: const Center(child: Text('Không có nhãn', style: TextStyle(color: Colors.grey))),
        ),
      );
    }

    Widget imageContent = validFile != null
        ? Image.file(validFile, height: 120, fit: BoxFit.cover)
        : Image.memory(memoryBytes!, height: 120, fit: BoxFit.cover);

    final tag = _currentData.croppedLabelImage ?? 'label_img_${_currentData.id ?? _currentData.createdAt.millisecondsSinceEpoch}';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FullScreenImage(
              imageFile: validFile,
              imageBytes: memoryBytes,
              heroTag: tag,
            ),
          ),
        );
      },
      child: Hero(
        tag: tag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: imageContent,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nutritionList = _currentData.decodedNutrition;
    final double cRatio = _currentData.consumptionRatio > 0 ? _currentData.consumptionRatio : 1.0;
    final double actualW = _currentData.actualWeight;

    Map<String, dynamic> energy = {'per_label': 0, 'unit': 'kcal'};
    Map<String, dynamic> protein = {'per_label': 0, 'unit': 'g'};
    Map<String, dynamic> fat = {'per_label': 0, 'unit': 'g'};
    Map<String, dynamic> carb = {'per_label': 0, 'unit': 'g'};
    Map<String, dynamic> fiber = {'per_label': 0, 'unit': 'g'};

    double p100 = 0, c100 = 0, f100 = 0;
    for (var item in nutritionList) {
      if (item['id'] == 'energy') energy = item;
      if (item['id'] == 'protein') {
        protein = item;
        p100 = (item['per_100g'] as num?)?.toDouble() ?? 0.0;
      }
      if (item['id'] == 'fat' || item['id'] == 'total_fat') {
        fat = item;
        f100 = (item['per_100g'] as num?)?.toDouble() ?? 0.0;
      }
      if (item['id'] == 'carb') {
        carb = item;
        c100 = (item['per_100g'] as num?)?.toDouble() ?? 0.0;
      }
      if (item['id'] == 'fiber') fiber = item;
    }

    final servingInfo = ref.read(foodRepositoryProvider).calculateServingUnit(
      mainGroup: _currentData.mainGroup,
      p100: p100,
      c100: c100,
      f100: f100,
      actualWeight: actualW,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Kết quả quét', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.pie_chart_outline, color: Colors.green),
            tooltip: 'Tiến trình dinh dưỡng ngày',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DailyProgressScreen(initialDate: _currentData.logDate),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Ảnh hiển thị
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildFoodImageWidget(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: _buildLabelImageWidget(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 2. Tên món ăn và Khối lượng (Hiển thị số quả trứng ở dưới khối lượng)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                decoration: BoxDecoration(
                  color: Colors.white, 
                  borderRadius: BorderRadius.circular(12), 
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _currentData.foodName.isNotEmpty ? '${_currentData.foodName[0].toUpperCase()}${_currentData.foodName.substring(1)}' : '',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1B233A)),
                          ),
                        ),
                        InkWell(
                          onTap: _editWeight,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _currentData.formatWeight(
                                      fallback: _isEggFood ? '50 g' : '100 g',
                                    ),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.edit, color: Colors.green, size: 18),
                                ],
                              ),
                              if (_isEggFood) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '($_eggQuantity quả)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green.shade800,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_isEggFood) ...[
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: () => _showEggSelectionModal(),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.egg_outlined, size: 16, color: Colors.amber.shade900),
                              const SizedBox(width: 6),
                              Text(
                                'Đổi loại trứng & số lượng quả',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.tune_rounded, size: 14, color: Colors.amber.shade900),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 2.1. ĐƠN VỊ KHẨU PHẦN CHUẨN (Standard Food Serving Unit - Công thức 2.7 - 2.9)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.scale_outlined, color: Colors.green, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'QUY ĐỔI KHẨU PHẦN CHUẨN (${servingInfo.groupName.toUpperCase()})',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            servingInfo.summaryText,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            servingInfo.standardDesc,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 2.2. THANH CHỌN HỆ SỐ TIÊU THỤ THỰC TẾ (gamma in (0, 1] - Công thức 2.10 - 2.12)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 3)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.pie_chart_outline, size: 18, color: Color(0xFF1B233A)),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'Khẩu phần tiêu thụ thực tế (γ)',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1B233A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Ăn ${actualW.toStringAsFixed(0)}g (${(cRatio * 100).round()}%)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildRatioChip(0.25, '1/4 (25%)'),
                        _buildRatioChip(0.50, '1/2 (50%)'),
                        _buildRatioChip(0.75, '3/4 (75%)'),
                        _buildRatioChip(1.00, 'Hết khay (100%)'),
                        _buildCustomRatioChip(),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 3. Card Năng lượng
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: const Border(left: BorderSide(color: Colors.red, width: 4))),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Tổng Năng Lượng', style: TextStyle(fontSize: 14, color: Colors.black87)),
                        const SizedBox(height: 8),
                        Text('${(((energy['per_label'] as num?)?.toDouble() ?? 0) * cRatio).toStringAsFixed(0)} ${energy['unit'] == 'kcal' ? 'Kcal' : energy['unit']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFD32F2F))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 4. Grid 4 chất (Đã nhân hệ số tiêu thụ thực tế gamma)
              Row(
                children: [
                  Expanded(child: _buildNutrientCard('Protein', '${(((protein['per_label'] as num?)?.toDouble() ?? 0) * cRatio).toStringAsFixed(1)}${protein['unit']}', Colors.purple)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildNutrientCard('Chất béo (Fat)', '${(((fat['per_label'] as num?)?.toDouble() ?? 0) * cRatio).toStringAsFixed(1)}${fat['unit']}', Colors.orange)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildNutrientCard('Carb', '${(((carb['per_label'] as num?)?.toDouble() ?? 0) * cRatio).toStringAsFixed(1)}${carb['unit']}', Colors.blue)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildNutrientCard('Chất xơ', '${(((fiber['per_label'] as num?)?.toDouble() ?? 0) * cRatio).toStringAsFixed(1)}${fiber['unit']}', Colors.green)),
                ],
              ),
              const SizedBox(height: 32),

              // 5. Nút xem chi tiết (Dạng chữ)
              TextButton(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => ResultScreen(resultData: _currentData)));
                },
                child: const Text('Xem chi tiết giá trị dinh dưỡng >', style: TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 20),

              // 6. Gợi ý tư vấn dinh dưỡng
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TƯ VẤN DINH DƯỠNG',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                  TextButton.icon(
                    onPressed: _isLoadingSuggestion ? null : _fetchSuggestion,
                    icon: _isLoadingSuggestion
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green),
                          )
                        : const Icon(Icons.refresh, size: 18, color: Colors.green),
                    label: const Text(
                      'Cập nhật',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      backgroundColor: Colors.green.withValues(alpha: 0.08),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Builder(
                builder: (ctx) {
                  final profileState = ref.watch(profileProvider);
                  if (profileState.tdee == null || profileState.profile == null) {
                    return InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.orange.shade800, size: 24),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Bạn cần nhập thông số cá nhân để có thể nhận được gợi ý dinh dưỡng.',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFC65102),
                                  height: 1.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.arrow_forward_ios, size: 14, color: Colors.orange.shade800),
                          ],
                        ),
                      ),
                    );
                  }

                  if (_isLoadingSuggestion) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              'Đang kết nối chuyên gia AI để phân tích dinh dưỡng...',
                              style: TextStyle(fontSize: 14, color: Colors.black54),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  if (_suggestionError != null) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_suggestionError!, style: const TextStyle(color: Colors.red, fontSize: 14)),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            onPressed: _fetchSuggestion,
                            icon: const Icon(Icons.refresh, size: 16, color: Colors.white),
                            label: const Text('Thử lại', style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          ),
                        ],
                      ),
                    );
                  }

                  final suggestionStr = _suggestionText;
                  if (suggestionStr == null || suggestionStr.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.psychology_outlined, size: 40, color: Colors.green.shade600),
                          const SizedBox(height: 10),
                          const Text(
                            'Chưa tải lời khuyên dinh dưỡng cho món này.',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Nhấn nút "Cập nhật" ở trên để chuyên gia AI phân tích thực phẩm theo thể trạng và bệnh lý của bạn.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54, fontSize: 13),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            onPressed: _fetchSuggestion,
                            icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
                            label: const Text('Tra cứu tư vấn dinh dưỡng', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final bool isOffline = suggestionStr.contains('📶');
                  final bool hasVeto = suggestionStr.contains('⛔') || suggestionStr.contains('🚨');
                  final bool hasWarning = suggestionStr.contains('⚠️');
                  final Color borderColor = hasVeto 
                      ? Colors.red 
                      : (hasWarning ? Colors.orange : (isOffline ? Colors.grey : Colors.green));
                  final String headerTitle = hasVeto 
                      ? '🚨 CẢNH BÁO Y TẾ ĐẶC BIỆT' 
                      : (hasWarning 
                          ? '⚠️ LƯU Ý SỨC KHỎE' 
                          : (isOffline ? '📶 CHƯA CÓ KẾT NỐI MẠNG' : '💡 Lời khuyên từ chuyên gia AI'));
                  
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: hasVeto ? Colors.red.shade50 : (isOffline ? Colors.grey.shade50 : Colors.white),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor.withValues(alpha: 0.7), width: hasVeto ? 1.5 : 1.0),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(headerTitle, style: TextStyle(fontWeight: FontWeight.bold, color: borderColor, fontSize: 16)),
                        const SizedBox(height: 12),
                        Text(suggestionStr, style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87)),
                      ],
                    ),
                  );
                }
              ),
              const SizedBox(height: 20),

              // NÚT CHUYỂN SANG TIẾN TRÌNH DINH DƯỠNG NGÀY
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DailyProgressScreen(initialDate: _currentData.logDate),
                      ),
                    );
                  },
                  icon: const Icon(Icons.pie_chart_outline),
                  label: const Text(
                    'Xem Tiến trình Dinh dưỡng Ngày Hôm Nay',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNutrientCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(color: color, width: 4))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, color: Colors.black87)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
