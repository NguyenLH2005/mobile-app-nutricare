
import 'package:flutter/services.dart';
import 'package:csv/csv.dart';

class FoodRepository {
  // Biến lưu trữ dữ liệu CSV trên RAM dạng Map để tra cứu
  // Key: tên món ăn đã chuẩn hóa, Value: dữ liệu 1 dòng của món đó
  final Map<String, List<dynamic>> _foodData = {};
  List<String> _headers = [];

  // Hàm đọc file CSV (chỉ gọi 1 lần khi khởi động app)
  Future<void> loadCsvData() async {
    try {
      final rawData = await rootBundle.loadString(
        'assets/db/gia_tri_dinh_duong_thuc_pham.csv',
      );
      
      List<List<dynamic>> rowsAsListOfValues = Csv().decode(rawData);

      if (rowsAsListOfValues.isNotEmpty) {
        _headers = rowsAsListOfValues.first.map((e) => e.toString()).toList(); // Lấy dòng đầu làm tiêu đề

        for (int i = 1; i < rowsAsListOfValues.length; i++) {
          final row = rowsAsListOfValues[i];
          if (row.length > 1) {
            // Giả sử cột index 1 là Tên món ăn (name_vi)
            final String rawName = row[1].toString();
            final String normalizedName = _normalizeString(rawName);
            _foodData[normalizedName] = row;
          }
        }
      }
    } catch (_) {
      // Bỏ qua lỗi nạp dữ liệu nếu có sự cố IO
    }
  }

  // Bản đồ ánh xạ: Tên nhận diện từ AI -> Tên danh mục chuẩn trong file CSV
  static const Map<String, String> csvNameMapper = {
    'Bạch tuộc': 'mực, tươi',
    'Bắp cải': 'cải bắp trắng, tươi',
    'Bầu': 'quả bầu, tươi',
    'Bí đỏ': 'quả bí ngô, tươi',
    'Bơ': 'quả bơ vỏ xanh, tươi',
    'Cà chua': 'quả cà chua, tươi',
    'Cá điêu hồng': 'cá điêu hồng',
    'Cá hồi': 'cá hồi, tươi',
    'Cá lóc': 'cá quả, tươi',
    'Cá ngừ': 'cá ngừ, tươi',
    'Cà rốt': 'củ cà rốt, tươi',
    'Cá thu': 'cá thu, tươi',
    'Cải xanh': 'cải xanh, tươi',
    'Cam': 'cam, tươi',
    'Chôm chôm': 'chôm chôm, tươi',
    'Chuối': 'chuối tiêu, tươi',
    'Cua': 'Thịt cua',
    'Dâu tây': 'dâu tây, tươi',
    'Đu đủ': 'đu đủ chín, tươi',
    'Dưa hấu': 'dưa hấu, tươi',
    'Dưa leo': 'dưa chuột, tươi',
    'Ếch': 'ếch (thịt đùi), tươi',
    'Hạnh nhân': 'hạt hạnh nhân rang',
    'Khổ qua': 'mướp đắng, tươi',
    'Khoai lang': 'khoai lang, tươi',
    'Khoai tây': 'khoai tây, tươi',
    'Khóm': 'Dứa ta, tươi',
    'Lê': 'lê, tươi',
    'Mực': 'mực, tươi',
    'Nấm đùi gà': 'nấm thường, tươi',
    'Nấm kim châm': 'nấm kim châm',
    'Nấm rơm': 'nấm rơm, tươi',
    'Ngô': 'ngô, cả bắp, tươi',
    'Nho': 'nho ngọt, tươi',
    'Óc chó': 'hạt óc chó rang',
    'Ổi': 'ổi, quả chín, tươi',
    'Ớt chuông': 'ớt đỏ to, tươi',
    'Rau muống': 'rau muống, tươi',
    'Sầu riêng': 'sầu riêng, tươi',
    'Súp lơ': 'súp lơ xanh, tươi',
    'Táo': 'táo tây, tươi',
    'Thanh long': 'quả thanh long, tươi',
    'Thịt bò': 'thịt bò, bắp, sống',
    'Thịt gà': 'thịt gà ta, tươi',
    'Thịt heo': 'thịt lợn, nạc, tươi',
    'Thịt vịt': 'Thịt vịt, tươi',
    'Tôm': 'tôm biển, tươi',
    'Trứng': 'Trứng gà công nghiệp',
    'Trứng gà': 'Trứng gà công nghiệp',
    'Trứng gà (công nghiệp)': 'Trứng gà công nghiệp',
    'Trứng gà ta': 'Trứng gà ta',
    'Trứng vịt': 'Trứng vịt',
    'Trứng vịt lộn': 'Trứng vịt lộn',
    'Vải': 'vải, tươi',
    'Xoài': 'xoài chín, tươi',
  };

  // Hàm chuẩn hóa chuỗi (chữ thường, bỏ khoảng trắng thừa)
  String _normalizeString(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  // Hàm tra cứu gần đúng (Substring matching), ưu tiên tên ngắn nhất
  Map<String, dynamic>? findFoodByName(String name) {
    final mappedName = csvNameMapper[name] ?? name;
    final searchName = _normalizeString(mappedName);
    
    String? bestMatchKey;
    
    for (String key in _foodData.keys) {
      if (key.contains(searchName)) {
        if (bestMatchKey == null || key.length < bestMatchKey.length) {
          bestMatchKey = key;
        }
      }
    }

    if (bestMatchKey != null) {
      final rowData = _foodData[bestMatchKey]!;
      // Ghép Header với Dữ liệu thành một Map cho dễ lấy
      return Map.fromIterables(_headers, rowData);
    }

    // Dự phòng: nếu mappedName khác name mà không tìm ra, thử tìm theo name gốc
    if (mappedName != name) {
      final rawSearchName = _normalizeString(name);
      for (String key in _foodData.keys) {
        if (key.contains(rawSearchName)) {
          if (bestMatchKey == null || key.length < bestMatchKey.length) {
            bestMatchKey = key;
          }
        }
      }
      if (bestMatchKey != null) {
        final rowData = _foodData[bestMatchKey]!;
        return Map.fromIterables(_headers, rowData);
      }
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
      'code', 'name_vi', 'category', 
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

  List<ServingUnitInfo> calculateAllServingUnits({
    required String mainGroup,
    required double p100,
    required double c100,
    required double f100,
    required double actualWeight,
  }) {
    final List<ServingUnitInfo> results = [];
    final groupLower = mainGroup.toLowerCase();

    // 1. Nhóm đạm: 1 phần chuẩn cung cấp 7g Protein (Công thức 2.7)
    if (p100 >= 3.0 || groupLower.contains('đạm') || groupLower.contains('protein') || groupLower.contains('thịt') || groupLower.contains('cá') || groupLower.contains('trứng') || groupLower.contains('hải sản')) {
      if (p100 > 0) {
        final double mServing = 700.0 / p100;
        final double count = actualWeight / mServing;
        results.add(ServingUnitInfo(
          servingWeight: mServing,
          servingCount: count,
          groupName: 'Chất đạm',
          groupShortName: 'đạm',
          standardNutrient: '7g đạm',
          standardDesc: '1 phần chuẩn = ${mServing.toStringAsFixed(0)}g (cung cấp 7g Đạm)',
          summaryText: '≈ ${count.toStringAsFixed(1)} phần đạm chuẩn (1 phần = 7g đạm = ${mServing.toStringAsFixed(0)}g)',
        ));
      }
    }

    // 2. Nhóm tinh bột / bột đường: 1 phần chuẩn cung cấp 20g Carbohydrate (Công thức 2.8)
    if (c100 >= 5.0 || groupLower.contains('đường') || groupLower.contains('bột') || groupLower.contains('carb') || groupLower.contains('khoai') || groupLower.contains('ngô') || groupLower.contains('trái cây') || groupLower.contains('chuối')) {
      if (c100 > 0) {
        final double mServing = 2000.0 / c100;
        final double count = actualWeight / mServing;
        results.add(ServingUnitInfo(
          servingWeight: mServing,
          servingCount: count,
          groupName: 'Chất bột đường',
          groupShortName: 'tinh bột',
          standardNutrient: '20g tinh bột',
          standardDesc: '1 phần chuẩn = ${mServing.toStringAsFixed(0)}g (cung cấp 20g Tinh bột)',
          summaryText: '≈ ${count.toStringAsFixed(1)} phần tinh bột chuẩn (1 phần = 20g tinh bột = ${mServing.toStringAsFixed(0)}g)',
        ));
      }
    }

    // 3. Nhóm chất béo: 1 phần chuẩn cung cấp 5g Lipid (Công thức 2.9)
    if (f100 >= 3.0 || groupLower.contains('béo') || groupLower.contains('fat') || groupLower.contains('lipid') || groupLower.contains('hạt') || groupLower.contains('dầu') || groupLower.contains('trứng')) {
      if (f100 > 0) {
        final double mServing = 500.0 / f100;
        final double count = actualWeight / mServing;
        results.add(ServingUnitInfo(
          servingWeight: mServing,
          servingCount: count,
          groupName: 'Chất béo',
          groupShortName: 'béo',
          standardNutrient: '5g chất béo',
          standardDesc: '1 phần chuẩn = ${mServing.toStringAsFixed(0)}g (cung cấp 5g Chất béo)',
          summaryText: '≈ ${count.toStringAsFixed(1)} phần béo chuẩn (1 phần = 5g chất béo = ${mServing.toStringAsFixed(0)}g)',
        ));
      }
    }

    // 4. Mặc định nếu không có nhóm đa lượng nào ở trên: quy chuẩn rau củ 80g
    if (results.isEmpty) {
      final double mServing = 80.0;
      final double count = actualWeight / mServing;
      results.add(ServingUnitInfo(
        servingWeight: mServing,
        servingCount: count,
        groupName: 'Rau củ quả',
        groupShortName: 'rau củ',
        standardNutrient: '80g rau củ',
        standardDesc: '1 phần chuẩn = 80g',
        summaryText: '≈ ${count.toStringAsFixed(1)} phần rau củ chuẩn (1 phần = 80g)',
      ));
    }

    return results;
  }

  ServingUnitInfo calculateServingUnit({
    required String mainGroup,
    required double p100,
    required double c100,
    required double f100,
    required double actualWeight,
  }) {
    final list = calculateAllServingUnits(
      mainGroup: mainGroup,
      p100: p100,
      c100: c100,
      f100: f100,
      actualWeight: actualWeight,
    );
    return list.first;
  }
}

class ServingUnitInfo {
  final double servingWeight;
  final double servingCount;
  final String groupName;
  final String groupShortName;
  final String standardNutrient;
  final String standardDesc;
  final String summaryText;

  const ServingUnitInfo({
    required this.servingWeight,
    required this.servingCount,
    required this.groupName,
    required this.groupShortName,
    required this.standardNutrient,
    required this.standardDesc,
    required this.summaryText,
  });

  String get singleLineText => summaryText;
}
