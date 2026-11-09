import '../../data/models/user_profile_model.dart';
import '../../data/datasources/remote/api_service.dart';

class NutritionSuggestionUseCase {
  static const String offlineMessage = '⚠️ Cần kết nối Internet để nhận lời khuyên dinh dưỡng từ chuyên gia AI.';

  static bool _matchesAllergen(String foodNameLower, String allergen) {
    if (allergen.contains('Đậu phộng') || allergen.contains('Lạc')) {
      return foodNameLower.contains('lạc') ||
          foodNameLower.contains('đậu phộng') ||
          foodNameLower.contains('bơ đậu phộng') ||
          foodNameLower.contains('peanut');
    }
    if (allergen.contains('Hải sản có vỏ')) {
      return foodNameLower.contains('tôm') ||
          foodNameLower.contains('cua') ||
          foodNameLower.contains('sò') ||
          foodNameLower.contains('ốc') ||
          foodNameLower.contains('nghêu') ||
          foodNameLower.contains('ngao') ||
          foodNameLower.contains('hàu') ||
          foodNameLower.contains('ghẹ') ||
          foodNameLower.contains('hến') ||
          foodNameLower.contains('tôm khô') ||
          foodNameLower.contains('mắm tôm') ||
          foodNameLower.contains('shrimp') ||
          foodNameLower.contains('crab') ||
          foodNameLower.contains('shellfish');
    }
    if (allergen.contains('Hạt cây')) {
      return foodNameLower.contains('hạnh nhân') ||
          foodNameLower.contains('óc chó') ||
          foodNameLower.contains('hạt điều') ||
          foodNameLower.contains('hạt dẻ') ||
          foodNameLower.contains('macca') ||
          foodNameLower.contains('mắc ca') ||
          foodNameLower.contains('hạt phỉ') ||
          foodNameLower.contains('almond') ||
          foodNameLower.contains('walnut') ||
          foodNameLower.contains('cashew');
    }
    if (allergen.contains('Trứng')) {
      return foodNameLower.contains('trứng') ||
          foodNameLower.contains('egg') ||
          foodNameLower.contains('lòng đỏ') ||
          foodNameLower.contains('lòng trắng');
    }
    if (allergen.contains('Cá')) {
      return foodNameLower.contains('cá ') ||
          foodNameLower.startsWith('cá') ||
          foodNameLower.contains('chả cá') ||
          foodNameLower.contains('cá lóc') ||
          foodNameLower.contains('cá hồi') ||
          foodNameLower.contains('cá ngừ') ||
          foodNameLower.contains('cá thu') ||
          foodNameLower.contains('cá ba sa') ||
          foodNameLower.contains('cá nục') ||
          foodNameLower.contains('cá diêu hồng') ||
          foodNameLower.contains('cá chép') ||
          foodNameLower.contains('fish');
    }
    if (allergen.contains('Sữa')) {
      return foodNameLower.contains('sữa bò') ||
          foodNameLower.contains('sữa tươi') ||
          foodNameLower.contains('phô mai') ||
          foodNameLower.contains('pho mát') ||
          foodNameLower.contains('bơ sữa') ||
          foodNameLower.contains('váng sữa') ||
          foodNameLower.contains('sữa chua') ||
          foodNameLower.contains('milk') ||
          foodNameLower.contains('cheese') ||
          foodNameLower.contains('dairy');
    }
    return false;
  }

  /// Gợi ý nguyên liệu thực phẩm bổ sung theo nhóm còn thiếu (chỉ gợi ý thực phẩm, không áp đặt số lượng)
  static List<Map<String, String>> _calculateSuggestedSupplements({
    required List<String> missingGroups,
    required UserProfile profile,
  }) {
    final List<Map<String, String>> result = [];
    final allergies = profile.allergies.map((a) => a.toLowerCase()).toList();
    final flags = profile.medicalFlags;
    final bool hasKidney = flags.length > 4 && flags[4] == '1';
    final bool hasGout = flags.length > 3 && flags[3] == '1';
    final bool hasDiabetes = flags.isNotEmpty && flags[0] == '1';
    final bool hasLipid = flags.length > 2 && flags[2] == '1';

    for (final group in missingGroups) {
      final gLower = group.toLowerCase();

      // 1. Nhóm Đạm
      if (gLower.contains('đạm') || gLower.contains('protein')) {
        final List<String> options = [];
        final bool canEgg = !allergies.any((a) => a.contains('trứng') || a.contains('egg'));
        final bool canFish = !allergies.any((a) => a.contains('cá') || a.contains('fish'));
        final bool canShrimp = !allergies.any((a) => a.contains('hải sản') || a.contains('tôm'));

        if (canEgg && !hasKidney) {
          options.add('Trứng gà');
        }
        if (canShrimp && !hasGout && !hasKidney) {
          options.add('Tôm biển tươi');
        }
        if (!hasGout && !hasKidney) {
          options.add('Thịt gà ta tươi');
        }
        if (options.isEmpty || hasKidney || hasGout || hasLipid) {
          if (canFish && !hasGout) {
            options.add('Cá lóc tươi');
          } else {
            options.add('Đậu phụ tươi');
          }
        }
        result.add({
          'group': 'Chất đạm',
          'recommendation': options.take(2).join(' hoặc '),
        });
      }

      // 2. Nhóm Tinh bột
      else if (gLower.contains('tinh bột') || gLower.contains('carb') || gLower.contains('bột đường')) {
        final List<String> options = [];
        options.add('Khoai lang tươi');
        if (!hasDiabetes) {
          options.add('Ngô tươi');
        } else {
          options.add('Yến mạch thô');
        }
        result.add({
          'group': 'Tinh bột',
          'recommendation': options.join(' hoặc '),
        });
      }

      // 3. Nhóm Chất xơ
      else if (gLower.contains('chất xơ') || gLower.contains('fiber')) {
        result.add({
          'group': 'Chất xơ',
          'recommendation': 'Rau muống tươi hoặc Cải xanh tươi',
        });
      }

      // 4. Nhóm Vitamin và khoáng chất
      else if (gLower.contains('vitamin') || gLower.contains('khoáng')) {
        final List<String> options = [];
        if (!hasKidney) {
          options.add('Cà chua tươi hoặc Ớt chuông tươi');
        } else {
          options.add('Quả bầu tươi hoặc Dưa chuột tươi');
        }
        result.add({
          'group': 'Vitamin và khoáng chất',
          'recommendation': options.first,
        });
      }

      // 5. Nhóm Chất béo (Lipid)
      else if (gLower.contains('chất béo') || gLower.contains('fat') || gLower.contains('lipid')) {
        final List<String> options = [];
        final bool canNuts = !allergies.any((a) => a.contains('hạt') || a.contains('nut'));
        if (canNuts && !hasLipid) {
          options.add('Hạt điều hoặc Hạnh nhân thô');
        } else {
          options.add('Dầu ô liu nguyên chất');
        }
        result.add({
          'group': 'Chất béo',
          'recommendation': options.first,
        });
      }
    }

    return result;
  }

  static Future<String?> generateSuggestion({
    required UserProfile profile,
    required String mainGroupStr, // VD: "Protein, Chất béo"
    required String foodName,
    required Map<String, dynamic> rawFoodData,
    double? weight,
  }) async {
    final double calo100g = double.tryParse(rawFoodData['Năng lượng']?.toString() ?? '0') ?? 0;
    if (calo100g <= 0) return null;

    final double sugars100 = double.tryParse(rawFoodData['Sugars, total']?.toString() ?? '0') ?? 0;
    final double sodium100 = double.tryParse(rawFoodData['Natri']?.toString() ?? '0') ?? 0;
    final double satFat100 = double.tryParse(rawFoodData['Axit béo bão hòa tổng số']?.toString() ?? '0') ?? 0;
    final double transFat100 = double.tryParse(rawFoodData['Fatty acids, total trans']?.toString() ?? '0') ?? 0;
    final double protein100 = double.tryParse(rawFoodData['Chất đạm']?.toString() ?? '0') ?? 0;
    final double carb100 = double.tryParse(rawFoodData['Chất bột đường']?.toString() ?? '0') ?? 0;
    final double fat100 = double.tryParse(rawFoodData['Chất béo (Fat)']?.toString() ?? '0') ?? 0;
    final double fiber100 = double.tryParse(rawFoodData['Chất xơ']?.toString() ?? '0') ?? 0;
    final double potassium100 = double.tryParse(rawFoodData['Kali']?.toString() ?? '0') ?? 0;
    final double phosphorus100 = double.tryParse(rawFoodData['Photpho']?.toString() ?? '0') ?? 0;

    final flags = profile.medicalFlags; // Chuỗi 6-bit
    final bool hasDiabetes = flags.isNotEmpty && flags[0] == '1';
    final bool hasHypertension = flags.length > 1 && flags[1] == '1';
    final bool hasLipid = flags.length > 2 && flags[2] == '1';
    final bool hasGout = flags.length > 3 && flags[3] == '1';
    final bool hasKidney = flags.length > 4 && flags[4] == '1';
    final bool hasCardio = flags.length > 5 && flags[5] == '1';

    final String foodNameLower = foodName.toLowerCase();
    final double userWeight = (weight != null && weight > 0) ? weight : 100.0;

    // Tính dưỡng chất thực tế nạp theo khối lượng khẩu phần thực tế m_actual
    final double portionRatio = userWeight / 100.0;
    final double actualEnergy = calo100g * portionRatio;
    final double actualPotassium = potassium100 * portionRatio;
    final double actualPhosphorus = phosphorus100 * portionRatio;
    final double actualSodium = sodium100 * portionRatio;
    final double actualSugars = sugars100 * portionRatio;
    final double actualSatFat = satFat100 * portionRatio;
    final double actualTransFat = transFat100 * portionRatio;
    final double actualProtein = protein100 * portionRatio;
    final double actualCarb = carb100 * portionRatio;
    final double actualFat = fat100 * portionRatio;
    final double actualFiber = fiber100 * portionRatio;

    // 1. Kiểm tra Lệnh cấm tuyệt đối (Medical Hard Veto & Absolute Allergies)
    String? vetoReason;

    // A. Dị ứng thực phẩm tuyệt đối
    if (profile.allergies.isNotEmpty) {
      for (final allergen in profile.allergies) {
        if (_matchesAllergen(foodNameLower, allergen)) {
          vetoReason = 'Bạn có tiền sử dị ứng tuyệt đối với "$allergen". Thực phẩm "$foodName" có chứa thành phần này, nguy cơ gây sốc phản vệ hoặc biến chứng dị ứng nguy hiểm.';
          break;
        }
      }
    }

    // B. Veto bệnh lý mãn tính nghiêm trọng dựa trên lượng thực tế tiêu thụ
    if (vetoReason == null) {
      if (hasKidney && (actualPotassium >= 600.0 || actualPhosphorus >= 400.0)) {
        vetoReason = 'Bạn đang mắc bệnh Thận mạn. Khẩu phần "$foodName" ${userWeight.toStringAsFixed(0)}g cung cấp tới ${actualPotassium.toStringAsFixed(0)}mg Kali hoặc ${actualPhosphorus.toStringAsFixed(0)}mg Photpho • Vượt 30% trần an toàn cả ngày, có nguy cơ gây quá tải bài tiết cầu thận và rối loạn nhịp tim nguy hiểm.';
      } else if (hasDiabetes && actualSugars >= (profile.ceilingSugar * 0.5) && actualFiber < 1.0) {
        vetoReason = 'Bạn đang mắc bệnh Tiểu đường. Khẩu phần "$foodName" chứa lượng đường quá cao (${actualSugars.toStringAsFixed(1)}g • Chiếm >= 50% trần an toàn ngày) nhưng thiếu chất xơ tự nhiên làm chậm hấp thu, có nguy cơ làm tăng đột ngột đường huyết cấp tính.';
      } else if (hasHypertension && (actualSodium >= (profile.ceilingSodium * 0.5) || actualSodium >= 1000.0)) {
        vetoReason = 'Bạn đang mắc bệnh Tăng huyết áp. Khẩu phần này chứa lượng Natri quá lớn (${actualSodium.toStringAsFixed(0)}mg • Chiếm >= 50% trần muối an toàn cả ngày), có nguy cơ kích hoạt cơn tăng huyết áp đột ngột.';
      } else if (hasCardio && (actualSodium >= (profile.ceilingSodium * 0.5) || actualSodium >= 1000.0)) {
        vetoReason = 'Bạn đang mắc bệnh Tim mạch. Khẩu phần này chứa lượng Natri quá lớn (${actualSodium.toStringAsFixed(0)}mg), có nguy cơ gây giữ nước và tăng áp lực tuần hoàn cấp tính cho tim.';
      } else if (hasLipid && (actualTransFat >= 0.5 || actualSatFat >= (profile.ceilingSatFat * 0.5))) {
        vetoReason = 'Bạn đang mắc bệnh Rối loạn lipid máu/Mỡ máu. Khẩu phần chứa Trans fat (${actualTransFat.toStringAsFixed(1)}g) hoặc Axit béo bão hòa vượt ngưỡng an toàn (${actualSatFat.toStringAsFixed(1)}g), gây tổn thương thành mạch và tăng mạnh cholesterol xấu.';
      } else if (hasGout) {
        final bool isPurineRich = foodNameLower.contains('bò') || foodNameLower.contains('heo') || 
                                  foodNameLower.contains('cừu') || foodNameLower.contains('tôm') || 
                                  foodNameLower.contains('cua') || foodNameLower.contains('mực') || 
                                  foodNameLower.contains('tuộc') || foodNameLower.contains('hải sản') ||
                                  foodNameLower.contains('vịt');
        if (isPurineRich && actualProtein >= 35.0) {
          vetoReason = 'Bạn đang mắc bệnh Gout. Khẩu phần thực phẩm giàu Purine/Đạm động vật này chứa tới ${actualProtein.toStringAsFixed(1)}g đạm động vật đậm đặc trong một bữa ăn, có nguy cơ kích hoạt cơn đau Gout cấp tính dữ dội.';
        }
      }
    }

    if (vetoReason != null) {
      return '⛔ CẢNH BÁO Y KHOA ĐẶC BIỆT:\n$vetoReason\n\n👉 KHUYẾN NGHỊ: Bạn TUYỆT ĐỐI KHÔNG ĐƯỢC DÙNG thực phẩm này để bảo vệ sức khỏe an toàn.';
    }

    // 2. Tính toán các chỉ số thực tế cho JSON gửi AI Gemini
    final double caloPercentRaw = (profile.targetCalories > 0)
        ? (actualEnergy / profile.targetCalories) * 100
        : 0.0;
    final double caloriesPercent = double.parse(caloPercentRaw.toStringAsFixed(1));

    // Chuẩn hóa nhóm dinh dưỡng chính và tính % theo khẩu phần thực tế
    List<String> rawGroups = mainGroupStr
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (rawGroups.isEmpty) rawGroups = ['Chất đạm'];

    final List<Map<String, dynamic>> mainGroupsPercent = [];
    for (String g in rawGroups) {
      final gLower = g.toLowerCase();
      if (gLower.contains('protein') || gLower.contains('đạm')) {
        final double p = (profile.budgetProtein > 0) ? (actualProtein / profile.budgetProtein) * 100 : 0.0;
        mainGroupsPercent.add({'group': 'Chất đạm', 'percent': double.parse(p.toStringAsFixed(1))});
      } else if (gLower.contains('tinh bột') || gLower.contains('carb')) {
        final double p = (profile.budgetCarb > 0) ? (actualCarb / profile.budgetCarb) * 100 : 0.0;
        mainGroupsPercent.add({'group': 'Tinh bột', 'percent': double.parse(p.toStringAsFixed(1))});
      } else if (gLower.contains('chất béo') || gLower.contains('fat')) {
        final double p = (profile.budgetFat > 0) ? (actualFat / profile.budgetFat) * 100 : 0.0;
        mainGroupsPercent.add({'group': 'Chất béo', 'percent': double.parse(p.toStringAsFixed(1))});
      } else if (gLower.contains('chất xơ') || gLower.contains('fiber')) {
        final double p = (profile.budgetFiber > 0) ? (actualFiber / profile.budgetFiber) * 100 : 0.0;
        mainGroupsPercent.add({'group': 'Chất xơ', 'percent': double.parse(p.toStringAsFixed(1))});
      }
    }

    // Tính diseaseImpact theo khẩu phần thực tế
    final List<Map<String, dynamic>> diseaseImpact = [];
    if (hasDiabetes && actualSugars > 0 && profile.ceilingSugar > 0) {
      final double pct = (actualSugars / profile.ceilingSugar) * 100;
      diseaseImpact.add({
        'disease': 'Tiểu đường',
        'nutrient': 'Đường tự do',
        'percentCeiling': double.parse(pct.toStringAsFixed(1)),
      });
    }
    if (hasHypertension && actualSodium > 0 && profile.ceilingSodium > 0) {
      final double pct = (actualSodium / profile.ceilingSodium) * 100;
      diseaseImpact.add({
        'disease': 'Huyết áp cao',
        'nutrient': 'Natri',
        'percentCeiling': double.parse(pct.toStringAsFixed(1)),
      });
    }
    if (hasCardio && actualSodium > 0 && profile.ceilingSodium > 0 && !hasHypertension) {
      final double pct = (actualSodium / profile.ceilingSodium) * 100;
      diseaseImpact.add({
        'disease': 'Tim mạch',
        'nutrient': 'Natri',
        'percentCeiling': double.parse(pct.toStringAsFixed(1)),
      });
    }
    if (hasLipid && actualSatFat > 0 && profile.ceilingSatFat > 0) {
      final double pct = (actualSatFat / profile.ceilingSatFat) * 100;
      diseaseImpact.add({
        'disease': 'Mỡ máu',
        'nutrient': 'Chất béo bão hòa',
        'percentCeiling': double.parse(pct.toStringAsFixed(1)),
      });
    }
    if (hasKidney) {
      if (actualPotassium > 0) {
        final double pct = (actualPotassium / 2000.0) * 100;
        diseaseImpact.add({
          'disease': 'Bệnh Thận',
          'nutrient': 'Kali',
          'percentCeiling': double.parse(pct.toStringAsFixed(1)),
        });
      }
      if (actualPhosphorus > 0) {
        final double pct = (actualPhosphorus / 800.0) * 100;
        diseaseImpact.add({
          'disease': 'Bệnh Thận',
          'nutrient': 'Photpho',
          'percentCeiling': double.parse(pct.toStringAsFixed(1)),
        });
      }
      if (actualProtein > 0 && profile.ceilingProteinKidney > 0) {
        final double pct = (actualProtein / profile.ceilingProteinKidney) * 100;
        diseaseImpact.add({
          'disease': 'Bệnh Thận',
          'nutrient': 'Chất đạm',
          'percentCeiling': double.parse(pct.toStringAsFixed(1)),
        });
      }
    }
    if (hasGout && actualProtein > 0) {
      if (foodNameLower.contains('bò') || foodNameLower.contains('heo') || foodNameLower.contains('cừu') || 
          foodNameLower.contains('tôm') || foodNameLower.contains('cua') || foodNameLower.contains('mực') || 
          foodNameLower.contains('tuộc') || foodNameLower.contains('hải sản')) {
        final double pct = (profile.budgetProtein > 0) ? (actualProtein / profile.budgetProtein) * 100 : 0.0;
        diseaseImpact.add({
          'disease': 'Gout',
          'nutrient': 'Purine / Đạm động vật',
          'percentCeiling': double.parse(pct.toStringAsFixed(1)),
        });
      }
    }
    if (profile.isObesityMode && actualSugars > 0 && profile.ceilingSugar > 0 && !hasDiabetes) {
      final double pct = (actualSugars / profile.ceilingSugar) * 100;
      diseaseImpact.add({
        'disease': 'Kiểm soát béo phì',
        'nutrient': 'Đường tự do',
        'percentCeiling': double.parse(pct.toStringAsFixed(1)),
      });
    }

    // Tìm các nhóm nguyên liệu còn thiếu từ 5 nhóm nguyên liệu cơ bản
    const fundamentalGroups = ['Chất đạm', 'Tinh bột', 'Chất béo', 'Chất xơ', 'Vitamin và khoáng chất'];
    final List<String> missingGroups = [];
    for (String fg in fundamentalGroups) {
      final fgLower = fg.toLowerCase();
      final bool hasGroup = rawGroups.any((g) {
        final gLower = g.toLowerCase();
        if (gLower.contains(fgLower)) return true;
        if (fg == 'Chất đạm' && gLower.contains('protein')) return true;
        if (fg == 'Tinh bột' && gLower.contains('carb')) return true;
        if (fg == 'Chất béo' && gLower.contains('fat')) return true;
        if (fg == 'Chất xơ' && gLower.contains('fiber')) return true;
        if (fg == 'Vitamin và khoáng chất' && (gLower.contains('vitamin') || gLower.contains('khoáng'))) return true;
        return false;
      });
      if (!hasGroup) {
        missingGroups.add(fg);
      }
    }

    // Gợi ý nguyên liệu bổ sung (chỉ gợi ý thực phẩm)
    final suggestedSupplements = _calculateSuggestedSupplements(
      missingGroups: missingGroups,
      profile: profile,
    );

    final double actualWRounded = double.parse(userWeight.toStringAsFixed(1));

    // Đóng gói JSON Payload chuẩn gửi AI
    final Map<String, dynamic> payload = {
      'user': {
        'medicalConditions': profile.medicalConditions,
        'allergies': profile.allergies,
      },
      'food': {
        'name': foodName,
        'holdingWeight_g': actualWRounded,
        'actualWeight_g': actualWRounded,
        'mainGroups': rawGroups,
        'missingGroups': missingGroups,
        'suggestedSupplements': suggestedSupplements,
        'metrics100g': {
          'caloriesPercent': caloriesPercent,
          'mainGroupsPercent': mainGroupsPercent,
          'diseaseImpact': diseaseImpact,
        },
        'metricsActual': {
          'caloriesPercent': caloriesPercent,
          'mainGroupsPercent': mainGroupsPercent,
          'diseaseImpact': diseaseImpact,
        },
      },
    };

    // Gửi lên Máy chủ Backend gọi Google Gemini AI
    final aiSuggestion = await ApiService.instance.getNutritionSuggestion(
      payload: payload,
    );

    if (aiSuggestion == null) {
      return offlineMessage;
    }

    return aiSuggestion;
  }
}
