import 'dart:convert';

class UserProfile {
  final int? id;
  final String dob;
  final double weight;
  final double height;
  final String gender;
  final double activityFactor;
  final String goal;
  final List<String> medicalConditions;
  final List<String> allergies; // Danh sách 6 dị ứng thực phẩm tuyệt đối
  final bool isObesityMode; // Bật/tắt chế độ can thiệp béo phì

  // Các trường tính toán sẵn lưu cố định trong CSDL
  // 6-bit string:
  // Bit 0: Tiểu đường
  // Bit 1: Huyết áp cao
  // Bit 2: Mỡ máu
  // Bit 3: Gout
  // Bit 4: Bệnh Thận
  // Bit 5: Tim mạch
  final String medicalFlags;
  final double bmr;
  final double tdee;
  final double targetCalories;
  final double budgetProtein;
  final double budgetCarb;
  final double budgetFat;
  final double budgetFiber;
  final double ceilingSugar;
  final double ceilingSodium;
  final double ceilingSatFat;
  final double ceilingProteinKidney;
  final int isSynced; // 0: chưa sync, 1: đã sync
  final String? updatedAt;

  static const List<String> standardAllergens = [
    'Đậu phộng (Lạc)',
    'Hải sản có vỏ (Tôm, Cua, Sò...)',
    'Hạt cây (Hạnh nhân, Óc chó, Điều...)',
    'Trứng',
    'Cá',
    'Đạm sữa bò',
  ];

  UserProfile({
    this.id,
    required this.dob,
    required this.weight,
    required this.height,
    required this.gender,
    required this.activityFactor,
    required this.goal,
    required this.medicalConditions,
    this.allergies = const [],
    this.isObesityMode = false,
    required this.medicalFlags,
    required this.bmr,
    required this.tdee,
    required this.targetCalories,
    required this.budgetProtein,
    required this.budgetCarb,
    required this.budgetFat,
    required this.budgetFiber,
    required this.ceilingSugar,
    required this.ceilingSodium,
    required this.ceilingSatFat,
    required this.ceilingProteinKidney,
    this.isSynced = 0,
    this.updatedAt,
  });

  static String encodeMedicalFlags(List<String> conditions) {
    final b0 = conditions.contains('Tiểu đường') ? '1' : '0';
    final b1 = conditions.contains('Huyết áp cao') ? '1' : '0';
    final b2 = (conditions.contains('Mỡ máu') || conditions.contains('Mỡ máu / Tim mạch')) ? '1' : '0';
    final b3 = conditions.contains('Gout') ? '1' : '0';
    final b4 = conditions.contains('Bệnh Thận') ? '1' : '0';
    final b5 = (conditions.contains('Tim mạch') || conditions.contains('Bệnh tim mạch')) ? '1' : '0';
    return '$b0$b1$b2$b3$b4$b5';
  }

  static List<String> decodeMedicalFlags(String flags) {
    final list = <String>[];
    if (flags.isNotEmpty && flags[0] == '1') list.add('Tiểu đường');
    if (flags.length > 1 && flags[1] == '1') list.add('Huyết áp cao');
    if (flags.length > 2 && flags[2] == '1') list.add('Mỡ máu');
    if (flags.length > 3 && flags[3] == '1') list.add('Gout');
    if (flags.length > 4 && flags[4] == '1') list.add('Bệnh Thận');
    if (flags.length > 5 && flags[5] == '1') list.add('Tim mạch');
    return list;
  }

  static int calculateAge(String dob) {
    final dobParts = dob.split('-');
    if (dobParts.length == 3) {
      final year = int.tryParse(dobParts[0]);
      final month = int.tryParse(dobParts[1]);
      final day = int.tryParse(dobParts[2]);
      if (year != null && month != null && day != null) {
        final dobDate = DateTime(year, month, day);
        final today = DateTime.now();
        int age = today.year - dobDate.year;
        if (today.month < dobDate.month || (today.month == dobDate.month && today.day < dobDate.day)) {
          age--;
        }
        return age;
      }
    }
    return 25;
  }

  int get age => calculateAge(dob);

  double get bmi {
    final heightInM = height / 100.0;
    return (heightInM > 0) ? (weight / (heightInM * heightInM)) : 0.0;
  }

  factory UserProfile.create({
    int? id,
    required String dob,
    required double weight,
    required double height,
    required String gender,
    required double activityFactor,
    required String goal,
    required List<String> medicalConditions,
    List<String> allergies = const [],
    bool isObesityMode = false,
    int isSynced = 0,
    String? updatedAt,
  }) {
    final int age = calculateAge(dob);

    // BMI theo chuẩn Châu Á của WHO
    final heightInM = height / 100.0;
    final bmi = (heightInM > 0) ? (weight / (heightInM * heightInM)) : 0.0;

    // Chế độ kiểm soát béo phì chỉ kích hoạt được khi BMI >= 23 (tiền béo phì hoặc béo phì)
    bool effectiveObesityMode = isObesityMode && (bmi >= 23.0);

    // 1. BMR theo Mifflin-St Jeor
    double bmr;
    if (gender == 'Nam') {
      bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5;
    } else {
      bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161;
    }

    // 2. TDEE
    double tdee = bmr * activityFactor;

    // 3. Target Calories & Goal
    // Nếu bật Chế độ kiểm soát béo phì: Mục tiêu khóa chặt là "Giảm cân", thâm hụt 500 kcal
    String effectiveGoal = effectiveObesityMode ? 'Giảm cân' : goal;
    double targetCalories = tdee;
    if (effectiveObesityMode) {
      targetCalories = tdee - 500;
    } else if (effectiveGoal == 'Giảm cân') {
      targetCalories = tdee - 500;
    } else if (effectiveGoal == 'Tăng cân') {
      targetCalories = tdee + 500;
    }

    if (targetCalories < 1000) targetCalories = 1000;

    // 4. Macro ratios theo mục tiêu (NIN / CDC)
    double ratioP = 0.20;
    double ratioC = 0.50;
    double ratioF = 0.30;
    if (effectiveObesityMode) {
      // Phân bổ macro tối ưu cho người béo phì giảm mỡ (30% P, 40% C, 30% F)
      ratioP = 0.30;
      ratioC = 0.40;
      ratioF = 0.30;
    } else if (effectiveGoal == 'Giảm cân') {
      ratioP = 0.30;
      ratioC = 0.40;
      ratioF = 0.30;
    } else if (effectiveGoal == 'Tăng cân') {
      ratioP = 0.20;
      ratioC = 0.55;
      ratioF = 0.25;
    }

    double budgetProtein = (targetCalories * ratioP) / 4;
    double budgetCarb = (targetCalories * ratioC) / 4;
    double budgetFat = (targetCalories * ratioF) / 9;
    double budgetFiber = 30.0;

    final flags = encodeMedicalFlags(medicalConditions);

    // 5. Ceilings y khoa cá nhân hóa
    // Đường: <= 10% TDEE người thường; <= 5% TDEE tiểu đường hoặc béo phì (WHO/ADA)
    double ceilingSugar = (flags[0] == '1' || effectiveObesityMode)
        ? (targetCalories * 0.05) / 4
        : (targetCalories * 0.10) / 4;

    // Natri: 2000mg người thường; 1500mg nếu Huyết áp cao (Bit 1) HOẶC Tim mạch (Bit 5) (WHO/AHA)
    double ceilingSodium = (flags[1] == '1' || (flags.length > 5 && flags[5] == '1')) ? 1500.0 : 2000.0;

    // Béo bão hòa: < 10% TDEE người thường; < 7% TDEE mỡ máu (Bit 2) (AHA 2024)
    double ceilingSatFat = (flags[2] == '1')
        ? (targetCalories * 0.07) / 9
        : (targetCalories * 0.10) / 9;

    // Bệnh thận (Bit 4): trần đạm = weight * 0.8g (KDIGO 2024)
    final bool hasKidneyDisease = flags.length > 4 && flags[4] == '1';
    double ceilingProteinKidney = hasKidneyDisease ? (weight * 0.8) : -1.0;

    // GIẢI QUYẾT XUNG ĐỘT PROTEIN THẬN & TÁI PHÂN BỔ CALO BẢO TOÀN NĂNG LƯỢNG (Mục 2.1.2 & Bảng 4.3):
    if (hasKidneyDisease) {
      budgetProtein = ceilingProteinKidney; // Trần đạm KDIGO 2024
      final double caloFromProtein = budgetProtein * 4;
      final double caloRemain = targetCalories - caloFromProtein;
      if (caloRemain > 0) {
        // Tái phân bổ calo còn lại: 65% Carb và 35% Fat để bảo toàn tổng Target Calories
        budgetCarb = (caloRemain * 0.65) / 4;
        budgetFat = (caloRemain * 0.35) / 9;
      }
    }

    return UserProfile(
      id: id,
      dob: dob,
      weight: weight,
      height: height,
      gender: gender,
      activityFactor: activityFactor,
      goal: effectiveGoal,
      medicalConditions: medicalConditions,
      allergies: allergies,
      isObesityMode: effectiveObesityMode,
      medicalFlags: flags,
      bmr: bmr,
      tdee: tdee,
      targetCalories: targetCalories,
      budgetProtein: budgetProtein,
      budgetCarb: budgetCarb,
      budgetFat: budgetFat,
      budgetFiber: budgetFiber,
      ceilingSugar: ceilingSugar,
      ceilingSodium: ceilingSodium,
      ceilingSatFat: ceilingSatFat,
      ceilingProteinKidney: ceilingProteinKidney,
      isSynced: isSynced,
      updatedAt: updatedAt ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> map = {
      'dob': dob,
      'weight': weight,
      'height': height,
      'gender': gender,
      'activity_factor': activityFactor,
      'goal': goal,
      'medical_conditions': jsonEncode(medicalConditions),
      'medical_flags': medicalFlags,
      'allergies': jsonEncode(allergies),
      'is_obesity_mode': isObesityMode ? 1 : 0,
      'bmr': bmr,
      'tdee': tdee,
      'target_calories': targetCalories,
      'budget_protein': budgetProtein,
      'budget_carb': budgetCarb,
      'budget_fat': budgetFat,
      'budget_fiber': budgetFiber,
      'ceiling_sugar': ceilingSugar,
      'ceiling_sodium': ceilingSodium,
      'ceiling_sat_fat': ceilingSatFat,
      'ceiling_protein_kidney': ceilingProteinKidney,
      'is_synced': isSynced,
      'updated_at': updatedAt ?? DateTime.now().toIso8601String(),
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  Map<String, dynamic> toCloudMap() {
    return {
      'dob': dob,
      'weight': weight,
      'height': height,
      'gender': gender,
      'activityFactor': activityFactor,
      'goal': goal,
      'medicalConditions': medicalConditions,
      'medicalFlags': medicalFlags,
      'bmr': bmr,
      'tdee': tdee,
      'targetCalories': targetCalories,
      'budgetProtein': budgetProtein,
      'budgetCarb': budgetCarb,
      'budgetFat': budgetFat,
      'budgetFiber': budgetFiber,
      'ceilingSugar': ceilingSugar,
      'ceilingSodium': ceilingSodium,
      'ceilingSatFat': ceilingSatFat,
      'ceilingProteinKidney': ceilingProteinKidney,
      'allergies': allergies,
      'isObesityMode': isObesityMode,
    };
  }

  static double _parseDouble(dynamic val, double defaultVal) {
    if (val == null) return defaultVal;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? defaultVal;
  }

  static List<String> _parseStringList(dynamic raw, List<String> fallback) {
    if (raw == null) return fallback;
    if (raw is String) {
      try {
        return List<String>.from(jsonDecode(raw));
      } catch (_) {
        return fallback;
      }
    }
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return fallback;
  }

  factory UserProfile.fromMap(Map<String, dynamic> map, {int? forceIsSynced}) {
    final flags = (map['medical_flags'] ?? map['medicalFlags'])?.toString() ?? '000000';
    final rawConditions = map['medical_conditions'] ?? map['medicalConditions'];
    return UserProfile(
      id: map['id'] is int ? map['id'] : null,
      dob: map['dob']?.toString() ?? '2000-01-01',
      weight: _parseDouble(map['weight'], 60.0),
      height: _parseDouble(map['height'], 170.0),
      gender: map['gender']?.toString() ?? 'Nam',
      activityFactor: _parseDouble(map['activity_factor'] ?? map['activityFactor'], 1.2),
      goal: map['goal']?.toString() ?? 'Giữ dáng',
      medicalConditions: _parseStringList(rawConditions, decodeMedicalFlags(flags)),
      allergies: _parseStringList(map['allergies'], const []),
      isObesityMode: map['is_obesity_mode'] == 1 ||
          map['is_obesity_mode'] == true ||
          map['isObesityMode'] == true,
      medicalFlags: flags,
      bmr: _parseDouble(map['bmr'], 0.0),
      tdee: _parseDouble(map['tdee'], 0.0),
      targetCalories: _parseDouble(map['target_calories'] ?? map['targetCalories'], 0.0),
      budgetProtein: _parseDouble(map['budget_protein'] ?? map['budgetProtein'], 0.0),
      budgetCarb: _parseDouble(map['budget_carb'] ?? map['budgetCarb'], 0.0),
      budgetFat: _parseDouble(map['budget_fat'] ?? map['budgetFat'], 0.0),
      budgetFiber: _parseDouble(map['budget_fiber'] ?? map['budgetFiber'], 30.0),
      ceilingSugar: _parseDouble(map['ceiling_sugar'] ?? map['ceilingSugar'], 0.0),
      ceilingSodium: _parseDouble(map['ceiling_sodium'] ?? map['ceilingSodium'], 2000.0),
      ceilingSatFat: _parseDouble(map['ceiling_sat_fat'] ?? map['ceilingSatFat'], 0.0),
      ceilingProteinKidney: _parseDouble(
        map['ceiling_protein_kidney'] ?? map['ceilingProteinKidney'],
        -1.0,
      ),
      isSynced: forceIsSynced ?? (map['is_synced'] ?? 0),
      updatedAt: (map['updated_at'] ?? map['updatedAt'])?.toString(),
    );
  }
}
