import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/scan_history_model.dart';
import '../../data/models/user_profile_model.dart';
import '../../data/datasources/local/database_helper.dart';
import '../state/profile_controller.dart';
import '../state/history_controller.dart';
import 'found_object_screen.dart';
import 'edit_profile_screen.dart';

class DailyProgressScreen extends ConsumerStatefulWidget {
  final String? initialDate;

  const DailyProgressScreen({super.key, this.initialDate});

  @override
  ConsumerState<DailyProgressScreen> createState() => _DailyProgressScreenState();
}

class _DailyProgressScreenState extends ConsumerState<DailyProgressScreen> {
  late DateTime _selectedDate;
  List<ScanHistory> _dailyScans = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialDate != null) {
      try {
        _selectedDate = DateTime.parse(widget.initialDate!);
      } catch (_) {
        _selectedDate = DateTime.now();
      }
    } else {
      _selectedDate = DateTime.now();
    }
    _loadDailyScans();
  }

  String get _dateStr {
    final y = _selectedDate.year.toString().padLeft(4, '0');
    final m = _selectedDate.month.toString().padLeft(2, '0');
    final d = _selectedDate.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String get _dateDisplayStr {
    final now = DateTime.now();
    final isToday = now.year == _selectedDate.year &&
        now.month == _selectedDate.month &&
        now.day == _selectedDate.day;
    final d = _selectedDate.day.toString().padLeft(2, '0');
    final m = _selectedDate.month.toString().padLeft(2, '0');
    final y = _selectedDate.year;
    return isToday ? 'Hôm nay, $d/$m/$y' : '$d/$m/$y';
  }

  Future<void> _loadDailyScans() async {
    setState(() => _isLoading = true);
    final scans = await DatabaseHelper.instance.getDailyScans(_dateStr);
    if (mounted) {
      setState(() {
        _dailyScans = scans;
        _isLoading = false;
      });
    }
  }

  void _changeDate(int offsetDays) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: offsetDays));
    });
    _loadDailyScans();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.green,
              onPrimary: Colors.white,
              onSurface: Color(0xFF1B233A),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadDailyScans();
    }
  }

  // --- TÍNH TOÁN CÁC CHỈ SỐ THEO MỤC 2.1.1 (CÔNG THỨC 2.13 - 2.15) ---
  Map<String, double> _calculateIntake() {
    double totalEnergy = 0;
    double totalProtein = 0;
    double totalCarb = 0;
    double totalFat = 0;
    double totalFiber = 0;
    double totalSodium = 0;
    double totalSugar = 0;

    for (final scan in _dailyScans) {
      final actualRatio = scan.actualWeight / 100.0;
      final nutritionList = scan.decodedNutrition;

      for (final item in nutritionList) {
        final id = (item['id'] ?? '').toString().toLowerCase();
        final name = (item['name'] ?? '').toString().toLowerCase();
        final p100 = (item['per_100g'] as num?)?.toDouble() ?? 0.0;
        final actualVal = p100 * actualRatio;

        if (id == 'energy' || name.contains('năng lượng')) {
          totalEnergy += actualVal;
        } else if (id == 'protein' || name.contains('protein') || name.contains('chất đạm')) {
          totalProtein += actualVal;
        } else if (id == 'carb' || name.contains('chất bột đường') || name.contains('glucid')) {
          totalCarb += actualVal;
        } else if (id == 'total_fat' || name.contains('chất béo') || name.contains('lipid')) {
          totalFat += actualVal;
        } else if (id == 'fiber' || name.contains('chất xơ')) {
          totalFiber += actualVal;
        } else if (id == 'sodium' || name.contains('natri')) {
          totalSodium += actualVal;
        } else if (id == 'sugars' || name.contains('đường')) {
          totalSugar += actualVal;
        }
      }
    }

    return {
      'energy': totalEnergy,
      'protein': totalProtein,
      'carb': totalCarb,
      'fat': totalFat,
      'fiber': totalFiber,
      'sodium': totalSodium,
      'sugar': totalSugar,
    };
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);
    final profile = profileState.profile;

    final intake = _calculateIntake();

    // Mục tiêu chuẩn y khoa từ UserProfile (E_goal, G_j)
    final double targetEnergy = profile?.targetCalories ?? 2000.0;
    final double targetProtein = profile?.budgetProtein ?? 75.0;
    final double targetCarb = profile?.budgetCarb ?? 275.0;
    final double targetFat = profile?.budgetFat ?? 55.0;
    final double targetFiber = profile?.budgetFiber ?? 25.0;

    // Lượng còn thiếu R_j = max(0, G_j - Q^day_j) (Công thức 2.14)
    final double deficitEnergy = (targetEnergy - intake['energy']!).clamp(0.0, double.infinity);
    final double deficitProtein = (targetProtein - intake['protein']!).clamp(0.0, double.infinity);
    final double deficitCarb = (targetCarb - intake['carb']!).clamp(0.0, double.infinity);
    final double deficitFat = (targetFat - intake['fat']!).clamp(0.0, double.infinity);

    // Số phần chuẩn quy đổi tương đương để bù đắp (Công thức 2.15)
    final double equivProtein = deficitProtein / 7.0; // 1 phần đạm = 7g protein
    final double equivCarb = deficitCarb / 20.0;      // 1 phần carb = 20g carb
    final double equivFat = deficitFat / 5.0;        // 1 phần béo = 5g fat

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FB),
      appBar: AppBar(
        title: const Text(
          'Tiến trình Dinh dưỡng Ngày',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1B233A),
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Tải lại',
            onPressed: _loadDailyScans,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDailyScans,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. THANH ĐIỀU HƯỚNG CHỌN NGÀY
                    _buildDateSelector(),
                    const SizedBox(height: 14),

                    // Cảnh báo nếu chưa có hồ sơ dinh dưỡng
                    if (profile == null)
                      _buildNoProfileBanner()
                    else ...[
                      // 2. THẺ TỔNG NĂNG LƯỢNG (CALORIES)
                      _buildEnergyOverviewCard(
                        current: intake['energy']!,
                        target: targetEnergy,
                        remaining: deficitEnergy,
                      ),
                      const SizedBox(height: 14),

                      // 3. TIẾN TRÌNH CÁC CHẤT ĐA LƯỢNG (P - C - F - XƠ)
                      _buildMacroProgressCard(
                        intake: intake,
                        targetProtein: targetProtein,
                        targetCarb: targetCarb,
                        targetFat: targetFat,
                        targetFiber: targetFiber,
                      ),
                      const SizedBox(height: 14),

                      // 4. MA TRẬN BÙ ĐẮP KHẨU PHẦN CHUẨN (N_equiv)
                      _buildEquivSupplementCard(
                        equivProtein: equivProtein,
                        equivCarb: equivCarb,
                        equivFat: equivFat,
                        deficitEnergy: deficitEnergy,
                      ),
                      const SizedBox(height: 14),

                      // 5. CẢNH BÁO TRẦN Y KHOA (Natri, Đường, Đạm thận)
                      _buildCeilingAlerts(profile, intake),
                      const SizedBox(height: 14),
                    ],

                    // 6. DANH SÁCH CÁC BỮA ĂN ĐÃ QUÉT TRONG NGÀY
                    _buildDailyScansList(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  // --- 1. DATE SELECTOR WIDGET ---
  Widget _buildDateSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.green),
            onPressed: () => _changeDate(-1),
            tooltip: 'Ngày trước',
          ),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 16, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    _dateDisplayStr,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B233A),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.green),
            onPressed: () => _changeDate(1),
            tooltip: 'Ngày sau',
          ),
        ],
      ),
    );
  }

  // --- NO PROFILE BANNER ---
  Widget _buildNoProfileBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Column(
        children: [
          const Icon(Icons.info_outline, color: Colors.amber, size: 36),
          const SizedBox(height: 8),
          const Text(
            'Chưa thiết lập Hồ sơ cá nhân',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            'Vui lòng cập nhật thông số cơ thể để hệ thống tự động tính toán nhu cầu calo và chất dinh dưỡng theo chuẩn y khoa.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.black87),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              );
            },
            child: const Text('Thiết lập ngay'),
          ),
        ],
      ),
    );
  }

  // --- 2. ENERGY OVERVIEW CARD ---
  Widget _buildEnergyOverviewCard({
    required double current,
    required double target,
    required double remaining,
  }) {
    final double percent = target > 0 ? (current / target).clamp(0.0, 1.5) : 0.0;
    final bool isOver = current > target;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.local_fire_department, color: Colors.deepOrange, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Năng lượng nạp vào (Calories)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B233A),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isOver ? Colors.red.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${(percent * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isOver ? Colors.red.shade700 : Colors.green.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    current.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: isOver ? Colors.red.shade700 : const Color(0xFF1B233A),
                    ),
                  ),
                  Text(
                    'Đã nạp (kcal)',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    target.toStringAsFixed(0),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  Text(
                    'Mục tiêu E_goal',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isOver ? '+${(current - target).toStringAsFixed(0)}' : remaining.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isOver ? Colors.red : Colors.green,
                    ),
                  ),
                  Text(
                    isOver ? 'Vượt chỉ tiêu' : 'Còn thiếu (R_E)',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percent > 1.0 ? 1.0 : percent,
              minHeight: 10,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                isOver ? Colors.red : Colors.deepOrange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 3. MACRO PROGRESS CARD ---
  Widget _buildMacroProgressCard({
    required Map<String, double> intake,
    required double targetProtein,
    required double targetCarb,
    required double targetFat,
    required double targetFiber,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tiến trình các chất đa lượng (Q_day / G_j)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B233A)),
          ),
          const SizedBox(height: 14),
          _buildMacroRow(
            label: 'Chất đạm (Protein)',
            current: intake['protein']!,
            target: targetProtein,
            color: Colors.purple,
            unit: 'g',
          ),
          const Divider(height: 20),
          _buildMacroRow(
            label: 'Tinh bột (Carbohydrate)',
            current: intake['carb']!,
            target: targetCarb,
            color: Colors.blue,
            unit: 'g',
          ),
          const Divider(height: 20),
          _buildMacroRow(
            label: 'Chất béo (Lipid)',
            current: intake['fat']!,
            target: targetFat,
            color: Colors.orange,
            unit: 'g',
          ),
          const Divider(height: 20),
          _buildMacroRow(
            label: 'Chất xơ (Fiber)',
            current: intake['fiber']!,
            target: targetFiber,
            color: Colors.green,
            unit: 'g',
          ),
        ],
      ),
    );
  }

  Widget _buildMacroRow({
    required String label,
    required double current,
    required double target,
    required Color color,
    required String unit,
  }) {
    final double ratio = target > 0 ? (current / target).clamp(0.0, 1.5) : 0.0;
    final bool isOver = current > target;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            Text(
              '${current.toStringAsFixed(1)} / ${target.toStringAsFixed(0)} $unit',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isOver ? Colors.red.shade700 : color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio > 1.0 ? 1.0 : ratio,
            minHeight: 7,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(
              isOver ? Colors.red : color,
            ),
          ),
        ),
      ],
    );
  }

  // --- 4. MA TRẬN BÙ ĐẮP KHẨU PHẦN CHUẨN (N_equiv - Công thức 2.15) ---
  Widget _buildEquivSupplementCard({
    required double equivProtein,
    required double equivCarb,
    required double equivFat,
    required double deficitEnergy,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4), // light emerald
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.green, size: 18),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'GỢI Ý BÙ ĐẮP KHẨU PHẦN CHUẨN (N_equiv)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF166534),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            deficitEnergy > 0
                ? 'Để hoàn thành mục tiêu ngày hôm nay, các bữa ăn tiếp theo bạn nên bổ sung:'
                : 'Bạn đã đạt hoặc vượt chỉ tiêu calo trong ngày! Hãy kiểm soát các bữa tiếp theo thanh đạm và lành mạnh.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildEquivItem(
                  title: 'Phần Đạm',
                  count: equivProtein,
                  example: '≈ 1 quả trứng hoặc 80g tôm/thịt',
                  color: Colors.purple,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildEquivItem(
                  title: 'Phần Tinh bột',
                  count: equivCarb,
                  example: '≈ 1/2 bát cơm hoặc 1 củ khoai',
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildEquivItem(
                  title: 'Phần Béo',
                  count: equivFat,
                  example: '≈ 1 thìa dầu hoặc 10g hạt',
                  color: Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEquivItem({
    required String title,
    required double count,
    required String example,
    required Color color,
  }) {
    final double displayCount = count > 0 ? count : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            displayCount > 0 ? displayCount.toStringAsFixed(1) : 'Đủ',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: displayCount > 0 ? color : Colors.green,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            example,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  // --- 5. CẢNH BÁO TRẦN Y KHOA ---
  Widget _buildCeilingAlerts(UserProfile profile, Map<String, double> intake) {
    final alerts = <Widget>[];

    // Cảnh báo Natri
    if (intake['sodium']! > profile.ceilingSodium) {
      alerts.add(_buildAlertBanner(
        title: 'CẢNH BÁO: Vượt trần Natri (${intake['sodium']!.toStringAsFixed(0)} / ${profile.ceilingSodium.toStringAsFixed(0)} mg)',
        desc: 'Hàm lượng muối nạp trong ngày đã chạm hoặc vượt ngưỡng an toàn y tế. Hãy hạn chế chấm muối và nước chấm đậm trong các bữa còn lại.',
        color: Colors.red,
      ));
    }

    // Cảnh báo Đường
    if (intake['sugar']! > profile.ceilingSugar) {
      alerts.add(_buildAlertBanner(
        title: 'CẢNH BÁO: Vượt trần Đường (${intake['sugar']!.toStringAsFixed(1)} / ${profile.ceilingSugar.toStringAsFixed(1)} g)',
        desc: 'Lượng đường tự do nạp vào vượt mức khuyến nghị của WHO. Tránh uống nước ngọt, trà sữa hoặc đồ ngọt trong phần còn lại của ngày.',
        color: Colors.amber.shade900,
      ));
    }

    // Cảnh báo Bệnh Thận (KDIGO 2024)
    final bool hasKidney = profile.medicalFlags.length > 4 && profile.medicalFlags[4] == '1';
    if (hasKidney && intake['protein']! > profile.ceilingProteinKidney && profile.ceilingProteinKidney > 0) {
      alerts.add(_buildAlertBanner(
        title: 'CẢNH BÁO KDIGO: Vượt trần đạm bệnh Thận (${intake['protein']!.toStringAsFixed(1)} / ${profile.ceilingProteinKidney.toStringAsFixed(1)} g)',
        desc: 'Khuyến cáo KDIGO giới hạn 0.8g đạm/kg để tránh tăng áp lực lọc cầu thận. Vui lòng giảm lượng thịt, cá, trứng trong các bữa tiếp theo.',
        color: Colors.deepOrange,
      ));
    }

    if (alerts.isEmpty) return const SizedBox.shrink();

    return Column(
      children: alerts.map((a) => Padding(padding: const EdgeInsets.only(bottom: 8), child: a)).toList(),
    );
  }

  Widget _buildAlertBanner({
    required String title,
    required String desc,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 6. DANH SÁCH MÓN ĂN TRONG NGÀY ---
  Widget _buildDailyScansList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Thực phẩm đã ghi nhận (${_dailyScans.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B233A)),
            ),
            if (_dailyScans.isNotEmpty)
              Text(
                'Chạm vào món để xem chi tiết',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_dailyScans.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.restaurant_outlined, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 10),
                  Text(
                    'Chưa có món ăn nào trong ngày này',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hãy quét món ăn từ khay siêu thị hoặc nhãn dinh dưỡng',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _dailyScans.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final scan = _dailyScans[index];
              return _buildScanItemCard(scan);
            },
          ),
      ],
    );
  }

  Widget _buildScanItemCard(ScanHistory scan) {
    // Tìm năng lượng món
    double itemEnergy = 0;
    for (final item in scan.decodedNutrition) {
      final id = (item['id'] ?? '').toString().toLowerCase();
      final name = (item['name'] ?? '').toString().toLowerCase();
      if (id == 'energy' || name.contains('năng lượng')) {
        final p100 = (item['per_100g'] as num?)?.toDouble() ?? 0.0;
        itemEnergy = p100 * (scan.actualWeight / 100.0);
        break;
      }
    }

    Widget imageWidget = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.fastfood, color: Colors.grey),
    );

    if (scan.croppedFoodImage.isNotEmpty && File(scan.croppedFoodImage).existsSync()) {
      imageWidget = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(File(scan.croppedFoodImage), width: 52, height: 52, fit: BoxFit.cover),
      );
    } else if (scan.foodImageBase64 != null && scan.foodImageBase64!.isNotEmpty) {
      try {
        final bytes = base64Decode(scan.foodImageBase64!);
        imageWidget = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(bytes, width: 52, height: 52, fit: BoxFit.cover),
        );
      } catch (_) {}
    }

    final String timeStr = '${scan.createdAt.hour.toString().padLeft(2, '0')}:${scan.createdAt.minute.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FoundObjectScreen(resultData: scan)),
        );
        _loadDailyScans();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            imageWidget,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scan.foodName.isNotEmpty
                        ? '${scan.foodName[0].toUpperCase()}${scan.foodName.substring(1)}'
                        : 'Món ăn',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B233A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        'Ăn: ${scan.actualWeight.toStringAsFixed(0)}g',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.green,
                        ),
                      ),
                      if (scan.consumptionRatio < 1.0) ...[
                        const SizedBox(width: 4),
                        Text(
                          '(${((scan.consumptionRatio) * 100).round()}% khay)',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Text('• Lúc $timeStr', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                  if (scan.servingUnits != null && scan.servingUnits! > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '≈ ${scan.servingUnits!.toStringAsFixed(1)} phần chuẩn',
                      style: TextStyle(fontSize: 11, color: Colors.purple.shade700, fontWeight: FontWeight.w500),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${itemEnergy.toStringAsFixed(0)} kcal',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFD32F2F),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                  onPressed: () => _confirmDeleteScan(scan),
                  tooltip: 'Xóa món',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteScan(ScanHistory scan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa món "${scan.foodName}" khỏi nhật ký ngày này?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(historyControllerProvider.notifier).deleteRecords([scan]);
      _loadDailyScans();
    }
  }
}
