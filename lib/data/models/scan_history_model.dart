import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

class ScanHistory {
  final int? id;
  final String originalImage;
  final String croppedFoodImage;
  final String? croppedLabelImage;
  final String? originalImageBase64;
  final String? foodImageBase64;
  final String? labelImageBase64;
  final String? aiSuggestion;
  final String foodName;
  final double? weight;
  final double? servingUnits; // Số đơn vị khẩu phần chuẩn quy đổi (S_j)
  final double consumptionRatio; // Hệ số tiêu thụ gamma (mặc định 1.0)
  final String? logDate; // Ngày tiêu thụ dạng YYYY-MM-DD
  final String nutritionData;
  final String mainGroup; // Nhóm dinh dưỡng chính (từ CSV)
  final DateTime createdAt;
  final int isSynced; // 0: chưa sync, 1: đã sync
  final DateTime? updatedAt;

  ScanHistory({
    this.id,
    required this.originalImage,
    required this.croppedFoodImage,
    this.croppedLabelImage,
    this.originalImageBase64,
    this.foodImageBase64,
    this.labelImageBase64,
    this.aiSuggestion,
    required this.foodName,
    this.weight,
    this.servingUnits,
    this.consumptionRatio = 1.0,
    this.logDate,
    required this.nutritionData,
    required this.mainGroup,
    required this.createdAt,
    this.isSynced = 0,
    this.updatedAt,
  });

  /// Khối lượng thực phẩm thực tế ăn vào: m_consumed = gamma * m_label
  double get actualWeight => (weight ?? 100.0) * (consumptionRatio > 0 ? consumptionRatio : 1.0);

  Map<String, dynamic> toMap() {
    final effectiveDate = logDate ?? createdAt.toIso8601String().substring(0, 10);
    return {
      'id': id,
      'original_image': originalImage,
      'cropped_food_image': croppedFoodImage,
      'cropped_label_image': croppedLabelImage,
      'original_image_base64': originalImageBase64,
      'food_image_base64': foodImageBase64,
      'label_image_base64': labelImageBase64,
      'ai_suggestion': aiSuggestion,
      'food_name': foodName,
      'weight': weight,
      'serving_units': servingUnits,
      'consumption_ratio': consumptionRatio,
      'log_date': effectiveDate,
      'nutrition_data': nutritionData,
      'main_group': mainGroup,
      'created_at': createdAt.toIso8601String(),
      'is_synced': isSynced,
      'updated_at': (updatedAt ?? createdAt).toIso8601String(),
    };
  }

  factory ScanHistory.fromMap(Map<String, dynamic> map) {
    DateTime created;
    try {
      created = map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now();
    } catch (_) {
      created = DateTime.now();
    }

    return ScanHistory(
      id: map['id'],
      originalImage: map['original_image'] ?? '',
      croppedFoodImage: map['cropped_food_image'] ?? '',
      croppedLabelImage: map['cropped_label_image'],
      originalImageBase64: map['original_image_base64'],
      foodImageBase64: map['food_image_base64'],
      labelImageBase64: map['label_image_base64'],
      aiSuggestion: map['ai_suggestion'] ?? map['aiSuggestion'],
      foodName: map['food_name'] ?? 'Món ăn',
      weight: map['weight'] != null ? (map['weight'] as num).toDouble() : null,
      servingUnits: map['serving_units'] != null ? (map['serving_units'] as num).toDouble() : null,
      consumptionRatio: map['consumption_ratio'] != null ? (map['consumption_ratio'] as num).toDouble() : 1.0,
      logDate: map['log_date'] ?? created.toIso8601String().substring(0, 10),
      nutritionData: map['nutrition_data'] ?? '[]',
      mainGroup: map['main_group'] ?? 'Chưa phân loại',
      createdAt: created,
      isSynced: map['is_synced'] ?? 0,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at']) : null,
    );
  }

  ScanHistory copyWith({
    int? id,
    String? originalImage,
    String? croppedFoodImage,
    String? croppedLabelImage,
    String? originalImageBase64,
    String? foodImageBase64,
    String? labelImageBase64,
    String? aiSuggestion,
    String? foodName,
    double? weight,
    double? servingUnits,
    double? consumptionRatio,
    String? logDate,
    String? nutritionData,
    String? mainGroup,
    DateTime? createdAt,
    int? isSynced,
    DateTime? updatedAt,
  }) {
    return ScanHistory(
      id: id ?? this.id,
      originalImage: originalImage ?? this.originalImage,
      croppedFoodImage: croppedFoodImage ?? this.croppedFoodImage,
      croppedLabelImage: croppedLabelImage ?? this.croppedLabelImage,
      originalImageBase64: originalImageBase64 ?? this.originalImageBase64,
      foodImageBase64: foodImageBase64 ?? this.foodImageBase64,
      labelImageBase64: labelImageBase64 ?? this.labelImageBase64,
      aiSuggestion: aiSuggestion ?? this.aiSuggestion,
      foodName: foodName ?? this.foodName,
      weight: weight ?? this.weight,
      servingUnits: servingUnits ?? this.servingUnits,
      consumptionRatio: consumptionRatio ?? this.consumptionRatio,
      logDate: logDate ?? this.logDate,
      nutritionData: nutritionData ?? this.nutritionData,
      mainGroup: mainGroup ?? this.mainGroup,
      createdAt: createdAt ?? this.createdAt,
      isSynced: isSynced ?? this.isSynced,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  List<dynamic> get decodedNutrition {
    try {
      return jsonDecode(nutritionData);
    } catch (_) {
      return [];
    }
  }

  static String formatWeightValue(double weight, {bool spaceBeforeUnit = true}) {
    final sep = spaceBeforeUnit ? ' ' : '';
    if (weight >= 1000) {
      final val = (weight / 1000)
          .toStringAsFixed(2)
          .replaceAll(RegExp(r'0*$'), '')
          .replaceAll(RegExp(r'\.$'), '');
      return '$val${sep}kg';
    }
    final val = weight
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0*$'), '')
        .replaceAll(RegExp(r'\.$'), '');
    return '$val${sep}g';
  }

  String formatWeight({String fallback = '100 g', bool spaceBeforeUnit = true}) {
    if (weight == null) return fallback;
    return formatWeightValue(weight!, spaceBeforeUnit: spaceBeforeUnit);
  }

  File? get foodImageFile {
    if (croppedFoodImage.isNotEmpty && File(croppedFoodImage).existsSync()) {
      return File(croppedFoodImage);
    }
    if (originalImage.isNotEmpty && File(originalImage).existsSync()) {
      return File(originalImage);
    }
    return null;
  }

  Uint8List? get foodImageBytes {
    final b64 = (foodImageBase64 != null && foodImageBase64!.isNotEmpty)
        ? foodImageBase64
        : originalImageBase64;
    if (b64 != null && b64.isNotEmpty) {
      try {
        return base64Decode(b64);
      } catch (_) {}
    }
    return null;
  }

  File? get labelImageFile {
    if (croppedLabelImage != null && croppedLabelImage!.isNotEmpty && File(croppedLabelImage!).existsSync()) {
      return File(croppedLabelImage!);
    }
    return null;
  }

  Uint8List? get labelImageBytes {
    if (labelImageBase64 != null && labelImageBase64!.isNotEmpty) {
      try {
        return base64Decode(labelImageBase64!);
      } catch (_) {}
    }
    return null;
  }

}
