import 'package:flutter_test/flutter_test.dart';
import 'package:nckh_app/data/models/scan_history_model.dart';
import 'package:nckh_app/data/models/user_profile_model.dart';
import 'package:nckh_app/data/repositories/food_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('UserProfile encodes conditions and calculates BMI/ceilings correctly', () {
    final profile = UserProfile.create(
      dob: '01/01/2000',
      weight: 80,
      height: 170,
      gender: 'Nam',
      activityFactor: 1.55,
      goal: 'Giữ dáng',
      medicalConditions: ['Tiểu đường', 'Bệnh Thận'],
      isObesityMode: true,
    );

    expect(profile.hasDiabetes, isTrue);
    expect(profile.hasKidneyDisease, isTrue);
    expect(profile.hasHypertension, isFalse);
    expect(profile.isObesityMode, isTrue);
    expect(profile.goal, 'Giảm cân');
    expect(profile.budgetProtein, closeTo(64.0, 0.01));
    expect(UserProfile.calculateBmi(80, 170), closeTo(27.68, 0.05));
  });

  test('ScanHistory formats weight, date and effective consumption ratio', () {
    final scan = ScanHistory(
      originalImage: '',
      croppedFoodImage: '',
      foodName: 'thịt gà - Ức gà công nghiệp',
      weight: 200,
      consumptionRatio: 0.5,
      nutritionData: '[]',
      mainGroup: 'Chất đạm',
      createdAt: DateTime(2026, 11, 16, 12, 30),
    );

    expect(scan.actualWeight, 100.0);
    expect(scan.capitalizedFoodName, 'Thịt gà - Ức gà công nghiệp');
    expect(ScanHistory.formatDateYmd(scan.createdAt), '2026-11-16');
    expect(scan.formatWeight(), '200 g');
  });

  test('FoodRepository loads nutrition.csv and resolves display names without parentheses', () async {
    final repo = FoodRepository();
    await repo.loadCsvData();

    final chicken = repo.findFoodByName('Thịt gà');
    expect(chicken, isNotNull);
    final displayName = repo.formatDisplayName(chicken!);
    expect(displayName.contains('('), isFalse);

    final parts = repo.getPartsForLabel('Thịt gà');
    expect(parts.length, greaterThanOrEqualTo(2));
    expect(parts, isNot(contains('Đùi gà ta')));
    expect(repo.getPartsForLabel('Ngô'), isNot(contains('Ngô nếp')));
    expect(repo.getPartsForLabel('Thịt vịt'), ['Cả con']);

    expect(repo.findFoodByName('Hạnh nhân'), isNotNull);
    expect(repo.findFoodByName('Óc chó'), isNotNull);

    final octopus = repo.findFoodByName('Bạch tuộc');
    expect(octopus, isNotNull);

    final mushroom = repo.findFoodByName('Nấm đùi gà');
    expect(mushroom, isNotNull);
  });
}
