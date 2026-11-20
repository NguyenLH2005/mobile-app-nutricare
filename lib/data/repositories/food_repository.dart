
import 'package:flutter/services.dart';
import 'package:csv/csv.dart';

class FoodRepository {
  // Biến lưu trữ dữ liệu CSV trên RAM để tra cứu nhanh
  final List<Map<String, dynamic>> _allRows = [];
  final Map<String, Map<String, dynamic>> _rowsByCode = {};
  final Map<String, List<Map<String, dynamic>>> _rowsByLabel = {};

  // Hàm đọc file CSV (chỉ gọi 1 lần khi khởi động app)
  Future<void> loadCsvData() async {
    try {
      final rawData = await rootBundle.loadString(
        'assets/db/nutrition.csv',
      );

      final List<List<dynamic>> rowsAsListOfValues = Csv().decode(rawData);

      _allRows.clear();
      _rowsByCode.clear();
      _rowsByLabel.clear();

      if (rowsAsListOfValues.isNotEmpty) {
        final headers = rowsAsListOfValues.first.map((e) => e.toString().trim()).toList();

        for (int i = 1; i < rowsAsListOfValues.length; i++) {
          final row = rowsAsListOfValues[i];
          if (row.length == headers.length) {
            final rowMap = Map<String, dynamic>.fromIterables(headers, row);
            _allRows.add(rowMap);

            final codeKey = _normalizeString(rowMap['code']?.toString() ?? '');
            if (codeKey.isNotEmpty) {
              _rowsByCode[codeKey] = rowMap;
            }

            final labelKey = _normalizeString(rowMap['food_label']?.toString() ?? '');
            if (labelKey.isNotEmpty) {
              _rowsByLabel.putIfAbsent(labelKey, () => []).add(rowMap);
            }
          }
        }
      }
    } catch (_) {
      // Bỏ qua lỗi nạp dữ liệu nếu có sự cố IO
    }
  }

  // Bản đồ ánh xạ: Tên nhận diện từ AI -> Mã code chuẩn trong nutrition.csv
  static const Map<String, String> csvNameMapper = {
    'Bạch tuộc': 'BACH_TUOC',
    'Bắp cải': '4010',
    'Bầu': '4001',
    'Bí đỏ': '4003',
    'Bơ': '5042',
    'Cà chua': '4005',
    'Cá điêu hồng': '8062',
    'Cá hồi': '8011',
    'Cá lóc': '8022',
    'Cá ngừ': '8019',
    'Cà rốt': '4007',
    'Cá thu': '8026',
    'Cải xanh': '4016',
    'Cam': '5002',
    'Chôm chôm': '5004',
    'Chuối': '5007',
    'Cua': '8069',
    'Dâu tây': '5009',
    'Đu đủ': '5017',
    'Dưa hấu': '5011',
    'Dưa leo': '4027',
    'Ếch': '7080',
    'Hạnh nhân': '3042011',
    'Khổ qua': '4055',
    'Khoai lang': '2008',
    'Khoai tây': '2014',
    'Khóm': '5014',
    'Lê': '5023',
    'Mực': '8040',
    'Nấm đùi gà': 'NAM_DUI_GA',
    'Nấm kim châm': '4133',
    'Nấm rơm': '4129',
    'Ngô': '1007',
    'Nho': '5037',
    'Óc chó': '3043011',
    'Ổi': '5040',
    'Ớt chuông': '4061',
    'Rau muống': '4083',
    'Sầu riêng': '5048',
    'Súp lơ': '4100',
    'Táo': '5051',
    'Thanh long': '5044',
    'Thịt bò': '7005',
    'Thịt gà': '7089',
    'Thịt heo': '7017',
    'Thịt vịt': '7028',
    'Tôm': '8051',
    'Trứng': '9012',
    'Trứng gà': '9012',
    'Trứng gà (công nghiệp)': '9012',
    'Trứng gà ta': '9001',
    'Trứng vịt': '9004',
    'Trứng vịt lộn': '9010',
    'Vải': '5052',
    'Xoài': '5055',
  };

  // Hàm chuẩn hóa chuỗi (chữ thường, bỏ khoảng trắng thừa)
  String _normalizeString(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Tra cứu dòng CSV từ code, tên nhãn, tên phần (Trứng...), hoặc tên hiển thị.
  Map<String, dynamic>? findFoodByName(String name) {
    final norm = _normalizeString(name);
    if (norm.isEmpty) return null;

    // 1. Kiểm tra ánh xạ trực tiếp từ nhãn AI -> code
    for (final entry in csvNameMapper.entries) {
      if (_normalizeString(entry.key) == norm) {
        final byCode = _rowsByCode[_normalizeString(entry.value)];
        if (byCode != null) return byCode;
      }
    }

    // 2. Tra cứu trực tiếp theo mã code
    final byCode = _rowsByCode[norm];
    if (byCode != null) return byCode;

    // 3. Khớp theo tên hiển thị định dạng hoặc part_name (như 4 loại Trứng)
    for (final row in _allRows) {
      if (_normalizeString(formatDisplayName(row)) == norm) return row;
      final partNorm = _normalizeString(row['part_name']?.toString() ?? '');
      if (partNorm.isNotEmpty && partNorm == norm) return row;
    }

    // 4. Khớp theo food_label
    final labelRows = _rowsByLabel[norm];
    if (labelRows != null && labelRows.isNotEmpty) {
      return labelRows.first;
    }

    // 5. Dự phòng: khớp tiền tố food_label cho dữ liệu lịch sử cũ
    String? bestPrefixLabel;
    for (final key in _rowsByLabel.keys) {
      if (norm.startsWith(key) && (bestPrefixLabel == null || key.length > bestPrefixLabel.length)) {
        bestPrefixLabel = key;
      }
    }
    if (bestPrefixLabel != null) {
      return findFoodByName(bestPrefixLabel);
    }

    return null;
  }

  // Đóng gói mảng dinh dưỡng theo khối lượng (g) chuẩn xác
  List<Map<String, dynamic>> buildNutritionArray(Map<String, dynamic> foodData, double weightInGrams) {
    final ratio = weightInGrams / 100.0;
    final double energy100g = double.tryParse(foodData['Năng lượng']?.toString() ?? '0') ?? 0;
    final double protein100g = double.tryParse(foodData['Chất đạm']?.toString() ?? '0') ?? 0;
    final double fat100g = double.tryParse(foodData['Chất béo (Fat)']?.toString() ?? '0') ?? 0;
    final double carb100g = double.tryParse(foodData['Chất bột đường']?.toString() ?? '0') ?? 0;
    final double fiber100g = double.tryParse(foodData['Chất xơ']?.toString() ?? '0') ?? 0;

    final String proteinUnit = foodData['Chất đạm_unit']?.toString().trim() ?? 'g';
    final String fatUnit = foodData['Chất béo (Fat)_unit']?.toString().trim() ?? 'g';
    final String carbUnit = foodData['Chất bột đường_unit']?.toString().trim() ?? 'g';
    final String fiberUnit = foodData['Chất xơ_unit']?.toString().trim() ?? 'g';

    final List<Map<String, dynamic>> nutritionArray = [
      {
        "id": "energy",
        "name": "Năng lượng",
        "per_100g": energy100g,
        "per_label": double.parse((energy100g * ratio).toStringAsFixed(1)),
        "unit": "kcal",
      },
      {
        "id": "protein",
        "name": "Protein",
        "per_100g": protein100g,
        "per_label": double.parse((protein100g * ratio).toStringAsFixed(1)),
        "unit": proteinUnit.isNotEmpty ? proteinUnit : 'g',
      },
      {
        "id": "total_fat",
        "name": "Chất béo (Fat)",
        "per_100g": fat100g,
        "per_label": double.parse((fat100g * ratio).toStringAsFixed(1)),
        "unit": fatUnit.isNotEmpty ? fatUnit : 'g',
      },
      {
        "id": "carb",
        "name": "Carb",
        "per_100g": carb100g,
        "per_label": double.parse((carb100g * ratio).toStringAsFixed(1)),
        "unit": carbUnit.isNotEmpty ? carbUnit : 'g',
      },
      {
        "id": "fiber",
        "name": "Chất xơ",
        "per_100g": fiber100g,
        "per_label": double.parse((fiber100g * ratio).toStringAsFixed(1)),
        "unit": fiberUnit.isNotEmpty ? fiberUnit : 'g',
      },
    ];

    final coreKeys = [
      'code', 'name_vi', 'food_label', 'part_name',
      'Nhóm Dinh Dưỡng Chính', 'category',
      'Năng lượng', 'Chất đạm', 'Chất béo (Fat)', 'Chất bột đường', 'Chất xơ'
    ];
    
    for (var entry in foodData.entries) {
      final key = entry.key;
      final value = entry.value;
      if (coreKeys.contains(key) || key.endsWith('_unit')) {
        continue;
      }
      final numValue = double.tryParse(value?.toString() ?? '') ?? 0.0;
      if (numValue > 0) {
        final unitKey = '${key}_unit';
        final unitStr = foodData[unitKey]?.toString().trim() ?? '';
        nutritionArray.add({
          "id": key,
          "name": key,
          "per_100g": numValue,
          "per_label": double.parse((numValue * ratio).toStringAsFixed(2)),
          "unit": unitStr,
        });
      }
    }
    return nutritionArray;
  }

  static ({double protein, double carb, double fat}) extractMacrosPer100g(List<dynamic> nutritionList) {
    double p100 = 0, c100 = 0, f100 = 0;
    for (final item in nutritionList) {
      final id = item['id'];
      if (id == 'protein') p100 = (item['per_100g'] as num?)?.toDouble() ?? 0.0;
      if (id == 'carb') c100 = (item['per_100g'] as num?)?.toDouble() ?? 0.0;
      if (id == 'fat' || id == 'total_fat') f100 = (item['per_100g'] as num?)?.toDouble() ?? 0.0;
    }
    return (protein: p100, carb: c100, fat: f100);
  }

  List<ServingUnitInfo> calculateAllServingUnits({
    required String mainGroup,
    required double p100,
    required double c100,
    required double f100,
    required double actualWeight,
  }) {
    final List<ServingUnitInfo> results = [];
    final groupLower = mainGroup.toLowerCase();

    void addStandardUnit(double servingWeight, String shortName) {
      results.add(ServingUnitInfo(
        servingWeight: servingWeight,
        servingCount: actualWeight / servingWeight,
        groupShortName: shortName,
      ));
    }

    // 1. Nhóm đạm: 1 phần chuẩn cung cấp 7g Protein (Công thức 2.7)
    if (p100 >= 3.0 || groupLower.contains('đạm') || groupLower.contains('protein') || groupLower.contains('thịt') || groupLower.contains('cá') || groupLower.contains('trứng') || groupLower.contains('hải sản')) {
      if (p100 > 0) addStandardUnit(700.0 / p100, 'đạm');
    }

    // 2. Nhóm tinh bột / bột đường: 1 phần chuẩn cung cấp 20g Carbohydrate (Công thức 2.8)
    if (c100 >= 5.0 || groupLower.contains('đường') || groupLower.contains('bột') || groupLower.contains('carb') || groupLower.contains('khoai') || groupLower.contains('ngô') || groupLower.contains('trái cây') || groupLower.contains('chuối')) {
      if (c100 > 0) addStandardUnit(2000.0 / c100, 'tinh bột');
    }

    // 3. Nhóm chất béo: 1 phần chuẩn cung cấp 5g Lipid (Công thức 2.9)
    if (f100 >= 3.0 || groupLower.contains('béo') || groupLower.contains('fat') || groupLower.contains('lipid') || groupLower.contains('hạt') || groupLower.contains('dầu') || groupLower.contains('trứng')) {
      if (f100 > 0) addStandardUnit(500.0 / f100, 'béo');
    }

    // 4. Mặc định nếu không có nhóm đa lượng nào ở trên: quy chuẩn rau củ 80g
    if (results.isEmpty) {
      addStandardUnit(80.0, 'rau củ');
    }

    return results;
  }

  double calculatePrimaryServingCount(
    List<dynamic> nutritionList,
    String mainGroup,
    double actualWeight,
  ) {
    final macros = extractMacrosPer100g(nutritionList);
    return calculateAllServingUnits(
      mainGroup: mainGroup,
      p100: macros.protein,
      c100: macros.carb,
      f100: macros.fat,
      actualWeight: actualWeight,
    ).first.servingCount;
  }

  // =========================================================================
  // TRA CỨU PHẦN THỨC ĂN (từ food_label, part_name)
  // =========================================================================

  String _mapToCsvLabel(String displayLabel) {
    final norm = _normalizeString(displayLabel);
    if (norm.startsWith('trứng')) return 'Trứng';
    return displayLabel.trim();
  }

  List<Map<String, dynamic>> _rowsForDisplayLabel(String displayLabel) {
    final key = _normalizeString(_mapToCsvLabel(displayLabel));
    return _rowsByLabel[key] ?? const [];
  }

  /// Xác định nhãn gốc (50 món AI) từ tên hiển thị trong ScanHistory (hỗ trợ cả dữ liệu cũ và định dạng mới).
  String resolveDisplayLabel(String foodName) {
    final norm = _normalizeString(foodName);

    final matchedRow = resolveRowFromFoodName(foodName);
    final csvLabel = matchedRow?['food_label']?.toString().trim() ?? '';
    if (csvLabel.isNotEmpty) return csvLabel;

    // Fallback khớp tiền tố theo danh sách nhãn AI
    String? bestKey;
    for (final key in csvNameMapper.keys) {
      final keyNorm = _normalizeString(key);
      if (norm == keyNorm || norm.startsWith('$keyNorm -') || norm.startsWith('$keyNorm (')) {
        if (bestKey == null || keyNorm.length > bestKey.length) {
          bestKey = key;
        }
      }
    }
    return bestKey ?? foodName.trim();
  }

  /// Tra cứu dòng CSV tương ứng với bản ghi ScanHistory (hỗ trợ cả dữ liệu cũ từng gắn hậu tố ngoặc).
  Map<String, dynamic>? resolveRowFromFoodName(String foodName) {
    final norm = _normalizeString(foodName);
    if (norm.isEmpty) return null;

    // Tương thích ngược nếu bản ghi lịch sử cũ từng lưu hậu tố "(Chế biến)" ở cuối
    final strippedNorm = norm.replaceAll(RegExp(r'\s*\([^)]*\)$'), '').trim();

    for (final row in _allRows) {
      final displayNorm = _normalizeString(formatDisplayName(row));
      if (displayNorm == norm || displayNorm == strippedNorm) {
        return row;
      }
    }

    // Fallback theo code, nhãn gốc, part_name hoặc tiền tố food_label
    return findFoodByName(strippedNorm.isNotEmpty ? strippedNorm : foodName);
  }

  /// Danh sách các phần/biến thể của một nhãn thực phẩm (đưa phần mặc định lên đầu tiên).
  List<String> getPartsForLabel(String displayLabel) {
    final rows = _rowsForDisplayLabel(displayLabel);
    if (rows.isEmpty) return const [];

    final List<String> parts = [];
    for (final r in rows) {
      final part = r['part_name']?.toString().trim() ?? '';
      if (part.isNotEmpty && !parts.contains(part)) {
        parts.add(part);
      }
    }
    if (parts.length <= 1) return parts;

    // Đưa phần mặc định (khớp csvNameMapper) lên vị trí đầu tiên
    final mappedCsvName = csvNameMapper[displayLabel] ?? csvNameMapper[resolveDisplayLabel(displayLabel)];
    if (mappedCsvName != null) {
      final defRow = findFoodByName(mappedCsvName);
      final defPart = defRow?['part_name']?.toString().trim() ?? '';
      if (defPart.isNotEmpty && parts.contains(defPart)) {
        parts.remove(defPart);
        parts.insert(0, defPart);
      }
    }
    return parts;
  }

  /// Tra cứu dòng CSV duy nhất tương ứng với cặp (nhãn, phần).
  Map<String, dynamic>? findRowForPart(String displayLabel, String partName) {
    final rows = _rowsForDisplayLabel(displayLabel);
    final partTarget = partName.trim();
    for (final row in rows) {
      if ((row['part_name']?.toString().trim() ?? '') == partTarget) {
        return row;
      }
    }
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Định dạng tên hiển thị chuẩn cho món ăn.
  String formatDisplayName(Map<String, dynamic> row, {String? overrideLabel}) {
    final csvLabel = row['food_label']?.toString().trim() ?? '';
    final part = row['part_name']?.toString().trim() ?? '';

    if (csvLabel == 'Trứng' && part.isNotEmpty) {
      return part;
    }

    final label = (overrideLabel != null && overrideLabel.trim().isNotEmpty)
        ? overrideLabel.trim()
        : (csvLabel.isNotEmpty ? csvLabel : (row['code']?.toString().trim() ?? 'Món ăn'));

    if (part.isNotEmpty) {
      if (_normalizeString(part).startsWith(_normalizeString(label))) {
        return part;
      }
      return '$label - $part';
    }

    return label;
  }
}

class ServingUnitInfo {
  final double servingWeight;
  final double servingCount;
  final String groupShortName;

  const ServingUnitInfo({
    required this.servingWeight,
    required this.servingCount,
    required this.groupShortName,
  });
}
