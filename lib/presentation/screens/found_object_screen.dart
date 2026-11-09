import '../../data/datasources/local/database_helper.dart';
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
    displayName: 'Trá»©ng gÃ  cÃ´ng nghiá»‡p',
    csvSearchName: 'Trá»©ng gÃ  cÃ´ng nghiá»‡p',
    weightPerUnit: 50.0,
  ),
  EggOption(
    id: 'local_chicken_egg',
    displayName: 'Trá»©ng gÃ  ta',
    csvSearchName: 'Trá»©ng gÃ  ta',
    weightPerUnit: 38.0,
  ),
  EggOption(
    id: 'duck_egg',
    displayName: 'Trá»©ng vá»‹t',
    csvSearchName: 'Trá»©ng vá»‹t',
    weightPerUnit: 60.0,
  ),
  EggOption(
    id: 'balut_egg',
    displayName: 'Trá»©ng vá»‹t lá»™n',
    csvSearchName: 'Trá»©ng vá»‹t lá»™n',
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
  bool _isAddedToMenu = false;
  final TextEditingController _eggPortionController = TextEditingController();
  double _eggEatenCount = 1.0;

  bool get _isEggFood {
    final name = _currentData.foodName.toLowerCase();
    return name.contains('trá»©ng') || name.contains('egg');
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
    _isAddedToMenu = !widget.isFromScan && _currentData.id != null;
    if (_isEggFood) {
      _eggEatenCount = _eggQuantity * _currentData.consumptionRatio;
      if (_eggEatenCount <= 0) _eggEatenCount = 1.0;
      _eggPortionController.text = _eggEatenCount == _eggEatenCount.roundToDouble()
          ? _eggEatenCount.toInt().toString()
          : _eggEatenCount.toString();
    }
    if (widget.isFromScan) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (_isEggFood) {
          await _showEggSelectionModal();
        }
      });
    }
  }

  @override
  void dispose() {
    _eggPortionController.dispose();
    super.dispose();
  }

  void _onEggPortionChanged(String val) {
    final parsed = double.tryParse(val.trim().replaceAll(',', '.'));
    if (parsed != null && parsed > 0) {
      _eggEatenCount = parsed;
      final totalEggs = _eggQuantity.toDouble();
      final ratio = (parsed / totalEggs).clamp(0.01, 5.0);
      _setConsumptionRatio(ratio, fromEggInput: true);
    }
  }

  void _incrementEggPortion() {
    _eggEatenCount = _eggEatenCount + 0.5;
    _eggPortionController.text = _eggEatenCount == _eggEatenCount.roundToDouble()
        ? _eggEatenCount.toInt().toString()
        : _eggEatenCount.toString();
    final totalEggs = _eggQuantity.toDouble();
    final ratio = (_eggEatenCount / totalEggs).clamp(0.01, 5.0);
    _setConsumptionRatio(ratio, fromEggInput: true);
  }

  void _decrementEggPortion() {
    if (_eggEatenCount > 0.5) {
      _eggEatenCount = _eggEatenCount - 0.5;
      _eggPortionController.text = _eggEatenCount == _eggEatenCount.roundToDouble()
          ? _eggEatenCount.toInt().toString()
          : _eggEatenCount.toString();
      final totalEggs = _eggQuantity.toDouble();
      final ratio = (_eggEatenCount / totalEggs).clamp(0.01, 5.0);
      _setConsumptionRatio(ratio, fromEggInput: true);
    }
  }

  Future<void> _handleAddToMenu() async {
    try {
      if (_currentData.id == null) {
        final newId = await DatabaseHelper.instance.insertScan(_currentData);
        if (mounted) {
          setState(() {
            _currentData = _currentData.copyWith(id: newId);
            _isAddedToMenu = true;
          });
        }
      } else {
        await DatabaseHelper.instance.updateScan(_currentData);
        if (mounted) {
          setState(() {
            _isAddedToMenu = true;
          });
        }
      }
      ref.invalidate(historyProvider);
      ref.read(syncProvider.notifier).syncNow();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('âœ“ ÄÃ£ thÃªm "${_currentData.foodName}" vÃ o tiáº¿n trÃ¬nh dinh dÆ°á»¡ng hÃ´m nay!'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lá»—i: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _fetchSuggestion() async {
    if (_isLoadingSuggestion) return;

    final profileState = ref.read(profileProvider);
    if (profileState.tdee == null || profileState.profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Báº¡n cáº§n nháº­p thÃ´ng sá»‘ cÃ¡ nhÃ¢n Ä‘á»ƒ cÃ³ thá»ƒ nháº­n Ä‘Æ°á»£c gá»£i Ã½ dinh dÆ°á»¡ng.'),
          action: SnackBarAction(
            label: 'Nháº­p ngay',
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
        if (id == 'energy') fallbackData['NÄƒng lÆ°á»£ng'] = val;
        if (id == 'protein') fallbackData['Cháº¥t Ä‘áº¡m'] = val;
        if (id == 'fat') fallbackData['Cháº¥t bÃ©o (Fat)'] = val;
        if (id == 'carb') fallbackData['Cháº¥t bá»™t Ä‘Æ°á»ng'] = val;
        if (id == 'fiber') fallbackData['Cháº¥t xÆ¡'] = val;
      }
      if (fallbackData.isNotEmpty) {
        rawFoodData = fallbackData;
      }
    }

    if (rawFoodData == null) {
      if (mounted) {
        setState(() {
          _isLoadingSuggestion = false;
          _suggestionError = 'KhÃ´ng tÃ¬m tháº¥y dá»¯ liá»‡u gá»‘c cá»§a thá»±c pháº©m.';
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

      // LÆ°u vÄ©nh viá»…n gá»£i Ã½ vÃ o SQLite vÃ  Ä‘á»“ng bá»™ lÃªn Ä‘Ã¡m mÃ¢y
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
          _suggestionError = 'Lá»—i phÃ¢n tÃ­ch: $e';
          _isLoadingSuggestion = false;
        });
      }
    }
  }

  Future<void> _applyEggSelection(EggOption selectedEgg, int quantity) async {
    final double newWeight = quantity * selectedEgg.weightPerUnit;
    final foodData = ref.read(foodRepositoryProvider).findFoodByName(selectedEgg.csvSearchName);
    if (foodData == null) return;

    final String mainGroup = foodData['NhÃ³m Dinh DÆ°á»¡ng ChÃ­nh']?.toString().trim() ?? 'Protein, Cháº¥t bÃ©o';
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
        _eggEatenCount = quantity.toDouble();
        _eggPortionController.text = quantity.toString();
      });
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
                              'Chá»n Loáº¡i Trá»©ng & Sá»‘ LÆ°á»£ng',
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
                        'Vui lÃ²ng chá»n loáº¡i trá»©ng báº¡n sá»­ dá»¥ng Ä‘á»ƒ há»‡ thá»‘ng tá»± Ä‘á»™ng quy Ä‘á»•i khá»‘i lÆ°á»£ng vÃ  giÃ¡ trá»‹ dinh dÆ°á»¡ng chuáº©n xÃ¡c:',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
                      ),
                      const SizedBox(height: 14),

                      // 4 TÃ¹y chá»n trá»©ng (Bá» mÃ´ táº£ nháº¡t, thÃªm dáº¥u ~ vÃ o khá»‘i lÆ°á»£ng)
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
                                    '~${opt.weightPerUnit.toInt()}g/quáº£',
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

                      // Stepper + Text Input (Chá»‰ nháº­p sá»‘ nguyÃªn, cÃ³ thá»ƒ gÃµ trá»±c tiáº¿p bÃ n phÃ­m)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sá»‘ lÆ°á»£ng quáº£:',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B233A)),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Cháº¡m vÃ o sá»‘ Ä‘á»ƒ nháº­p bÃ n phÃ­m',
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

                      // Quy Ä‘á»•i khá»‘i lÆ°á»£ng trá»±c quan
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
                              'Quy Ä‘á»•i khá»‘i lÆ°á»£ng:',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFC65102)),
                            ),
                            Text(
                              '$quantity quáº£ Ã— ~${selectedOption.weightPerUnit.toInt()}g = ${currentWeight.toInt()}g',
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

                      // NÃºt Ãp dá»¥ng (KhÃ´ng ghi sá»‘ lÆ°á»£ng vÃ o nÃºt)
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
                            'ÃP Dá»¤NG',
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

  Future<void> _setConsumptionRatio(double newRatio, {bool fromEggInput = false}) async {
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

    if (_currentData.id != null && _isAddedToMenu) {
      await ref.read(historyControllerProvider.notifier).updateScan(updatedData);
      ref.read(syncProvider.notifier).syncNow();
    }

    setState(() {
      _currentData = updatedData;
      if (!fromEggInput && _isEggFood) {
        _eggEatenCount = _eggQuantity * newRatio;
        _eggPortionController.text = _eggEatenCount == _eggEatenCount.roundToDouble()
            ? _eggEatenCount.toInt().toString()
            : _eggEatenCount.toString();
      }
    });
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
            title: const Text('TÃ¹y chá»‰nh lÆ°á»£ng Äƒn thá»±c táº¿'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('Theo % khay', style: TextStyle(fontSize: 13))),
                        selected: mode == 0,
                        showCheckmark: false,
                        onSelected: (_) => setDialogState(() => mode = 0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text('Theo sá»‘ gam', style: TextStyle(fontSize: 13))),
                        selected: mode == 1,
                        showCheckmark: false,
                        onSelected: (_) => setDialogState(() => mode = 1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: textController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: mode == 0 ? 'Tá»· lá»‡ %' : 'Khá»‘i lÆ°á»£ng Äƒn',
                    hintText: mode == 0 ? 'VÃ­ dá»¥: 30' : 'VÃ­ dá»¥: 120',
                    suffixText: mode == 0 ? '%' : 'g',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tá»•ng khá»‘i lÆ°á»£ng trÃªn nhÃ£n: ${totalWeight.toStringAsFixed(0)}g',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 1.0),
                child: const Text('Äáº·t láº¡i 100%'),
              ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ÄÃ³ng')),
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
                child: const Text('Ãp dá»¥ng'),
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
      onSelected: (selected) {
        if (selected) {
          _setConsumptionRatio(ratio);
        } else {
          _setConsumptionRatio(1.0);
        }
      },
    );
  }

  Widget _buildCustomRatioChip() {
    final bool isStandard = [0.25, 0.50, 0.75, 1.0].any((r) => (_currentData.consumptionRatio - r).abs() < 0.02);
    return ActionChip(
      avatar: const Icon(Icons.edit, size: 14, color: Colors.blue),
      label: Text(
        isStandard ? 'TÃ¹y chá»‰nh...' : '${(_currentData.consumptionRatio * 100).round()}%',
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
        title: const Text('Nháº­p khá»‘i lÆ°á»£ng má»›i'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'VÃ­ dá»¥: 250'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Há»§y')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('LÆ°u')),
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
          child: const Center(child: Text('KhÃ´ng cÃ³ nhÃ£n', style: TextStyle(color: Colors.grey))),
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

    final servingUnits = ref.read(foodRepositoryProvider).calculateAllServingUnits(
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
        title: const Text('Káº¿t quáº£ quÃ©t', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.pie_chart_outline, color: Colors.green),
            tooltip: 'Tiáº¿n trÃ¬nh dinh dÆ°á»¡ng ngÃ y',
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
              // 1. áº¢nh hiá»ƒn thá»‹
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

              // 2. TÃªn mÃ³n Äƒn vÃ  Khá»‘i lÆ°á»£ng (Hiá»ƒn thá»‹ sá»‘ quáº£ trá»©ng á»Ÿ dÆ°á»›i khá»‘i lÆ°á»£ng)
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
                        if (!_isEggFood)
                          InkWell(
                            onTap: _editWeight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _currentData.formatWeight(
                                    fallback: '100 g',
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
                          ),
                      ],
                    ),
                    if (_isEggFood) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _showEggSelectionModal(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.egg_rounded, size: 18),
                          label: Text(
                            'Loáº¡i: ${_matchedEggOption.displayName} â€¢ $_eggQuantity quáº£',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 2.1. ÄÆ N Vá»Š KHáº¨U PHáº¦N CHUáº¨N (Hiá»ƒn thá»‹ táº¥t cáº£ quy Ä‘á»•i tá»« CSV, chá»‰ 1 dÃ²ng gá»n gÃ ng)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
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
                        children: servingUnits.map((su) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.5),
                          child: Text(
                            su.singleLineText,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade900,
                            ),
                          ),
                        )).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 2.2. THANH CHá»ŒN Há»† Sá» TIÃŠU THá»¤ THá»°C Táº¾ (gamma in (0, 1])
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
                            'Kháº©u pháº§n Äƒn thá»±c táº¿',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1B233A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (cRatio < 0.99 || (_isEggFood && _eggEatenCount != _eggQuantity)) ...[
                          InkWell(
                            onTap: () => _setConsumptionRatio(1.0),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.refresh, size: 14, color: Colors.grey),
                                  const SizedBox(width: 2),
                                  Text('Äáº·t láº¡i', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (_isEggFood) ...[
                      // Ã” nháº­p sá»‘ cho ngÆ°á»i dÃ¹ng tá»± nháº­p sá»‘ quáº£ thá»±c táº¿ (há»— trá»£ sá»‘ tháº­p phÃ¢n, nÃºt cá»™ng trá»« á»Ÿ bÃªn pháº£i)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _eggPortionController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                labelText: 'Sá»‘ quáº£ Äƒn thá»±c táº¿',
                                suffixText: 'quáº£',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onChanged: _onEggPortionChanged,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove, size: 18),
                                  onPressed: _decrementEggPortion,
                                  padding: const EdgeInsets.all(8),
                                  constraints: const BoxConstraints(),
                                ),
                                Container(width: 1, height: 24, color: Colors.grey.shade300),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 18),
                                  onPressed: _incrementEggPortion,
                                  padding: const EdgeInsets.all(8),
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Ä‚n ${_eggEatenCount.toStringAsFixed(1).replaceAll('.0', '')} quáº£ trá»©ng • g',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                      ),
                    ] else ...[
                      // CÃ¡c nÃºt chá»n pháº§n trÄƒm gá»n gÃ ng (khÃ´ng phÃ¢n sá»‘)
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _buildRatioChip(0.25, '25%'),
                          _buildRatioChip(0.50, '50%'),
                          _buildRatioChip(0.75, '75%'),
                          _buildRatioChip(1.00, '100%'),
                          _buildCustomRatioChip(),
                        ],
                      ),
                    ],

                    const SizedBox(height: 14),

                    // NÃºt ThÃªm vÃ o thá»±c Ä‘Æ¡n hÃ´m nay
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _handleAddToMenu,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isAddedToMenu ? Colors.green.shade700 : const Color(0xFF1B233A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        icon: Icon(_isAddedToMenu ? Icons.check_circle_outline : Icons.add_circle_outline, size: 18),
                        label: Text(
                          _isAddedToMenu ? 'ÄÃ£ cÃ³ trong thá»±c Ä‘Æ¡n hÃ´m nay' : 'ThÃªm vÃ o thá»±c Ä‘Æ¡n hÃ´m nay',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 3. Card NÄƒng lÆ°á»£ng
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: const Border(left: BorderSide(color: Colors.red, width: 4))),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Tá»•ng NÄƒng LÆ°á»£ng', style: TextStyle(fontSize: 14, color: Colors.black87)),
                        const SizedBox(height: 8),
                        Text('${(((energy['per_label'] as num?)?.toDouble() ?? 0) * cRatio).toStringAsFixed(0)} ${energy['unit'] == 'kcal' ? 'Kcal' : energy['unit']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFD32F2F))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 4. Grid 4 cháº¥t (ÄÃ£ nhÃ¢n há»‡ sá»‘ tiÃªu thá»¥ thá»±c táº¿ gamma)
              Row(
                children: [
                  Expanded(child: _buildNutrientCard('Protein', '${(((protein['per_label'] as num?)?.toDouble() ?? 0) * cRatio).toStringAsFixed(1)}${protein['unit']}', Colors.purple)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildNutrientCard('Cháº¥t bÃ©o (Fat)', '${(((fat['per_label'] as num?)?.toDouble() ?? 0) * cRatio).toStringAsFixed(1)}${fat['unit']}', Colors.orange)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildNutrientCard('Carb', '${(((carb['per_label'] as num?)?.toDouble() ?? 0) * cRatio).toStringAsFixed(1)}${carb['unit']}', Colors.blue)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildNutrientCard('Cháº¥t xÆ¡', '${(((fiber['per_label'] as num?)?.toDouble() ?? 0) * cRatio).toStringAsFixed(1)}${fiber['unit']}', Colors.green)),
                ],
              ),
              const SizedBox(height: 32),

              // 5. NÃºt xem chi tiáº¿t (Dáº¡ng chá»¯)
              TextButton(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => ResultScreen(resultData: _currentData)));
                },
                child: const Text('Xem chi tiáº¿t giÃ¡ trá»‹ dinh dÆ°á»¡ng >', style: TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 20),

              // 6. Gá»£i Ã½ tÆ° váº¥n dinh dÆ°á»¡ng
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TÆ¯ Váº¤N DINH DÆ¯á» NG',
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
                      'Cáº­p nháº­t',
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
                                'Báº¡n cáº§n nháº­p thÃ´ng sá»‘ cÃ¡ nhÃ¢n Ä‘á»ƒ cÃ³ thá»ƒ nháº­n Ä‘Æ°á»£c gá»£i Ã½ dinh dÆ°á»¡ng.',
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
                              'Äang káº¿t ná»‘i chuyÃªn gia AI Ä‘á»ƒ phÃ¢n tÃ­ch dinh dÆ°á»¡ng...',
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
                            label: const Text('Thá»­ láº¡i', style: TextStyle(color: Colors.white)),
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
                            'ChÆ°a táº£i lá»i khuyÃªn dinh dÆ°á»¡ng cho mÃ³n nÃ y.',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Nháº¥n nÃºt "Cáº­p nháº­t" á»Ÿ trÃªn Ä‘á»ƒ chuyÃªn gia AI phÃ¢n tÃ­ch thá»±c pháº©m theo thá»ƒ tráº¡ng vÃ  bá»‡nh lÃ½ cá»§a báº¡n.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54, fontSize: 13),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            onPressed: _fetchSuggestion,
                            icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                            label: const Text('Nháº­n tÆ° váº¥n tá»« ChuyÃªn gia AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

                  final bool isOffline = suggestionStr.contains('ðŸ“¶');
                  final bool hasVeto = suggestionStr.contains('â›”') || suggestionStr.contains('ðŸš¨');
                  final bool hasWarning = suggestionStr.contains('âš ï¸');
                  final Color borderColor = hasVeto 
                      ? Colors.red 
                      : (hasWarning ? Colors.orange : (isOffline ? Colors.grey : Colors.green));
                  final String headerTitle = hasVeto 
                      ? 'ðŸš¨ Cáº¢NH BÃO Y Táº¾ Äáº¶C BIá»†T' 
                      : (hasWarning 
                          ? 'âš ï¸ LÆ¯U Ã Sá»¨C KHá»ŽE' 
                          : (isOffline ? 'ðŸ“¶ CHÆ¯A CÃ“ Káº¾T Ná»I Máº NG' : 'ðŸ’¡ Lá»i khuyÃªn tá»« chuyÃªn gia AI'));
                  
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

              // NÃšT CHUYá»‚N SANG TIáº¾N TRÃŒNH DINH DÆ¯á» NG NGÃ€Y
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
                    'Xem Tiáº¿n trÃ¬nh Dinh dÆ°á»¡ng NgÃ y HÃ´m Nay',
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
