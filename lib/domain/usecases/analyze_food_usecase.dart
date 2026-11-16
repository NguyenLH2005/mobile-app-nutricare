import 'package:flutter/foundation.dart';
import 'dart:convert';

import '../../core/utils/image_compress_helper.dart';
import '../../data/models/scan_history_model.dart';
import '../../data/repositories/food_repository.dart';
import '../../data/datasources/local/ai_helper.dart';

class AnalyzeFoodUseCase {
  final FoodRepository repository;

  AnalyzeFoodUseCase(this.repository);

  // Hàm phân tích chính
  Future<ScanHistory?> execute(String imagePath) async {
    try {
      // 1. CHẠY AI THẬT
      // Bước 1: Dò và cắt ảnh
      final croppedImages = await AIHelper.instance.detectAndCrop(imagePath);
      final String croppedFoodImage = croppedImages['foodImagePath']!;
      final String? croppedLabelImage = croppedImages['labelImagePath'];

      // Bước 2: Phân loại món ăn từ ảnh thịt đã cắt
      String detectedName = await AIHelper.instance.classifyFood(croppedFoodImage);

      // Nếu nhận diện là Trứng, mặc định là Trứng gà (công nghiệp) 1 quả (50g)
      final bool isEgg = detectedName.toLowerCase() == 'trứng' || detectedName.toLowerCase() == 'egg';
      if (isEgg) {
        detectedName = 'Trứng gà (công nghiệp)';
      }

      final String searchString = FoodRepository.csvNameMapper[detectedName] ?? detectedName;

      // Bước 3: Đọc khối lượng từ tem (OCR)
      double? rawWeightValue;
      String rawWeightUnit = "g"; // Đơn vị mặc định

      if (croppedLabelImage != null) {
        final String? weightString = await AIHelper.instance.readLabelWeight(croppedLabelImage);
        if (weightString != null) {
          // weightString có dạng "250G" hoặc "1.5KG"
          final match = RegExp(r'([\d\.]+)(KG|G)').firstMatch(weightString);
          if (match != null) {
            rawWeightValue = double.tryParse(match.group(1)!);
            rawWeightUnit = match.group(2)!.toLowerCase(); // 'g' hoặc 'kg'
          }
        }
      }
      
      // Chuẩn hóa khối lượng về gram (Nếu có khối lượng)
      double? detectedWeightInGrams;
      if (rawWeightValue != null) {
        detectedWeightInGrams = _normalizeToGrams(rawWeightValue, rawWeightUnit);
      } else if (isEgg) {
        // Mặc định trứng là 1 quả (50g)
        detectedWeightInGrams = 50.0;
      }

      // 2. TRA CỨU TỪ ĐIỂN CSV
      final foodData = repository.findFoodByName(searchString);
      if (foodData == null) {
        throw Exception("Không tìm thấy '$detectedName' trong cơ sở dữ liệu!");
      }

      final String displayFoodName = repository.formatDisplayName(
        foodData,
        overrideLabel: isEgg ? null : detectedName,
      );
      final String? initialCooking = foodData['cooking_method']?.toString().trim();
      final String mainGroup = foodData['Nhóm Dinh Dưỡng Chính']?.toString().trim() ?? 'Chưa phân loại';

      // 3. TÍNH TOÁN & ĐÓNG GÓI JSON
      final double targetWeight = detectedWeightInGrams ?? 100.0;
      final List<Map<String, dynamic>> nutritionArray = repository.buildNutritionArray(foodData, targetWeight);

      // Đóng gói thành chuỗi TEXT
      final String jsonNutritionData = jsonEncode(nutritionArray);

      // Nén 3 ảnh về chuẩn 550px và chuyển sang Base64 để sao lưu Cloud an toàn
      final String? originalBase64 = await ImageCompressHelper.compressAndEncodeBase64(imagePath, maxDimension: 550, quality: 75);
      final String? foodBase64 = await ImageCompressHelper.compressAndEncodeBase64(croppedFoodImage, maxDimension: 550, quality: 75);
      final String? labelBase64 = await ImageCompressHelper.compressAndEncodeBase64(croppedLabelImage, maxDimension: 550, quality: 75);

      // 4. TÍNH KHẨU PHẦN CHUẨN & NGÀY TIÊU THỤ
      final double servingUnits = repository.calculatePrimaryServingCount(
        nutritionArray,
        mainGroup,
        targetWeight,
      );

      final now = DateTime.now();
      final dateStr = ScanHistory.formatDateYmd(now);

      // 5. TRẢ VỀ ĐỐI TƯỢNG LỊCH SỬ HOÀN CHỈNH
      return ScanHistory(
        originalImage: imagePath,
        croppedFoodImage: croppedFoodImage,
        croppedLabelImage: croppedLabelImage,
        originalImageBase64: originalBase64,
        foodImageBase64: foodBase64,
        labelImageBase64: labelBase64,
        foodName: displayFoodName,
        weight: detectedWeightInGrams,
        servingUnits: servingUnits,
        consumptionRatio: 1.0,
        logDate: dateStr,
        cookingMethod: (initialCooking != null && initialCooking.isNotEmpty) ? initialCooking : null,
        nutritionData: jsonNutritionData,
        mainGroup: mainGroup,
        createdAt: now,
      );
    } catch (e) {
      debugPrint('Lỗi phân tích: $e');
      return null;
    }
  }

  // Hàm chuẩn hóa mọi đơn vị khối lượng về Gram (g)
  double _normalizeToGrams(double value, String unit) {
    switch (unit.toLowerCase()) {
      case 'kg':
      case 'kilogram':
        return value * 1000;
      case 'mg':
      case 'milligram':
        return value / 1000;
      case 'g':
      case 'gram':
      default:
        // Mặc định coi như là gram nếu không xác định được
        return value;
    }
  }
}
