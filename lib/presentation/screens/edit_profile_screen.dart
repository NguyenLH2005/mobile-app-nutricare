import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/user_profile_model.dart';
import '../state/profile_controller.dart';
import '../state/sync_controller.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _dobController;
  late TextEditingController _weightController;
  late TextEditingController _heightController;

  String _gender = 'Nam';
  String _goal = 'Giữ dáng';
  List<String> _selectedDiseases = [];
  List<String> _selectedAllergens = [];
  double _activityFactor = 1.2;

  @override
  void initState() {
    super.initState();
    _dobController = TextEditingController();
    _weightController = TextEditingController();
    _heightController = TextEditingController();

    _weightController.addListener(() => setState(() {}));
    _heightController.addListener(() => setState(() {}));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profile = ref.read(profileProvider).profile;
      if (profile != null) {
        _dobController.text = profile.dobFormatted;
        _weightController.text = profile.weight.toString();
        _heightController.text = profile.height.toString();
        setState(() {
          _gender = profile.gender;
          _activityFactor = profile.activityFactor;
          _goal = profile.goal;
          _selectedDiseases = List.from(profile.medicalConditions);
          if (_selectedDiseases.contains('Mỡ máu / Tim mạch')) {
            _selectedDiseases.remove('Mỡ máu / Tim mạch');
            if (!_selectedDiseases.contains('Mỡ máu')) _selectedDiseases.add('Mỡ máu');
            if (!_selectedDiseases.contains('Tim mạch')) _selectedDiseases.add('Tim mạch');
          }
          _selectedAllergens = List.from(profile.allergies);
        });
      } else {
        // Mặc định ban đầu nếu chưa có hồ sơ
        _dobController.text = '01/01/2000';
        _weightController.text = '60.0';
        _heightController.text = '170.0';
      }
    });
  }

  @override
  void dispose() {
    _dobController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    DateTime initial = DateTime(2000, 1, 1);
    if (_dobController.text.isNotEmpty) {
      final text = _dobController.text.trim();
      if (text.contains('/')) {
        final parts = text.split('/');
        if (parts.length == 3) {
          final d = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          final y = int.tryParse(parts[2]);
          if (d != null && m != null && y != null) {
            initial = DateTime(y, m, d);
          }
        }
      } else {
        try {
          initial = DateTime.parse(text);
        } catch (_) {}
      }
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _dobController.text =
            "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
      });
    }
  }

  double? _calculateCurrentBmi() {
    final w = double.tryParse(_weightController.text);
    final h = double.tryParse(_heightController.text);
    if (w != null && h != null && h > 0) {
      final hm = h / 100.0;
      return w / (hm * hm);
    }
    return null;
  }

  void _saveProfile() {
    if (_formKey.currentState!.validate()) {
      final currentProfile = ref.read(profileProvider).profile;
      final bmi = _calculateCurrentBmi() ?? 22.0;

      // Nếu BMI < 23 thì obesity mode không bật
      bool isObesityMode = (currentProfile?.isObesityMode ?? false) && (bmi >= 23.0);

      final profile = UserProfile.create(
        id: currentProfile?.id,
        dob: _dobController.text,
        weight: double.parse(_weightController.text),
        height: double.parse(_heightController.text),
        gender: _gender,
        activityFactor: _activityFactor,
        goal: _goal,
        medicalConditions: _selectedDiseases,
        allergies: _selectedAllergens,
        isObesityMode: isObesityMode,
      );

      // 1. Lưu vào SQLite nội bộ
      ref.read(profileProvider.notifier).saveProfile(profile);

      // 2. Tự động đồng bộ sao lưu lên đám mây
      ref.read(syncProvider.notifier).syncNow();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lưu thông tin hồ sơ thành công!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentBmi = _calculateCurrentBmi();
    final bool isOverweightOrObese = currentBmi != null && currentBmi >= 23.0;
    final bool hasGoalConflict = isOverweightOrObese &&
        ((currentBmi >= 25.0 && _goal != 'Giảm cân') ||
         (currentBmi >= 23.0 && _goal == 'Tăng cân'));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Thiết Lập Hồ Sơ',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green,
        elevation: 1,
        actions: [
          TextButton(
            onPressed: _saveProfile,
            child: const Text(
              'LƯU',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Thông số cơ bản',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800,
                ),
              ),
              const SizedBox(height: 12),

              // Ngày sinh
              TextFormField(
                controller: _dobController,
                decoration: const InputDecoration(
                  labelText: 'Ngày sinh (DD/MM/YYYY)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.cake_outlined),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                readOnly: true,
                onTap: () => _selectDate(context),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Vui lòng chọn ngày sinh' : null,
              ),
              const SizedBox(height: 16),

              // Cân nặng & Chiều cao
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _weightController,
                      decoration: const InputDecoration(
                        labelText: 'Cân nặng (kg)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.monitor_weight_outlined),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (val) {
                        if (val == null || val.isEmpty) return 'Nhập cân nặng';
                        final num = double.tryParse(val);
                        if (num == null || num <= 0) return 'Không hợp lệ';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextFormField(
                      controller: _heightController,
                      decoration: const InputDecoration(
                        labelText: 'Chiều cao (cm)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.height_outlined),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (val) {
                        if (val == null || val.isEmpty) return 'Nhập chiều cao';
                        final num = double.tryParse(val);
                        if (num == null || num <= 0) return 'Không hợp lệ';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Giới tính
              DropdownButtonFormField<String>(
                initialValue: _gender,
                decoration: const InputDecoration(
                  labelText: 'Giới tính',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.wc_outlined),
                ),
                items: ['Nam', 'Nữ']
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (val) => setState(() => _gender = val!),
              ),
              const SizedBox(height: 24),

              Text(
                'Mục tiêu & Chế độ sinh hoạt',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800,
                ),
              ),
              const SizedBox(height: 12),

              // Mức độ vận động
              DropdownButtonFormField<double>(
                initialValue: _activityFactor,
                decoration: const InputDecoration(
                  labelText: 'Mức độ vận động thể chất',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.directions_run_outlined),
                ),
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: 1.2,
                    child: Text('Ít vận động (Làm việc văn phòng, tĩnh tại)'),
                  ),
                  DropdownMenuItem(
                    value: 1.375,
                    child: Text('Vận động nhẹ (Tập nhẹ 1-3 ngày/tuần)'),
                  ),
                  DropdownMenuItem(
                    value: 1.55,
                    child: Text('Vận động vừa (Tập vừa 3-5 ngày/tuần)'),
                  ),
                  DropdownMenuItem(
                    value: 1.725,
                    child: Text('Vận động nhiều (Tập nặng 6-7 ngày/tuần)'),
                  ),
                  DropdownMenuItem(
                    value: 1.9,
                    child: Text('Vận động rất nhiều (VĐV, tập 2 lần/ngày)'),
                  ),
                ],
                onChanged: (val) => setState(() => _activityFactor = val!),
              ),
              const SizedBox(height: 16),

              // Mục tiêu cá nhân
              DropdownButtonFormField<String>(
                initialValue: _goal,
                decoration: const InputDecoration(
                  labelText: 'Mục tiêu dinh dưỡng',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.track_changes_outlined),
                ),
                items: ['Giảm cân', 'Giữ dáng', 'Tăng cân']
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (val) => setState(() => _goal = val!),
              ),

              // Cảnh báo thể trạng nếu BMI cao mà chọn tăng cân / giữ dáng
              if (hasGoalConflict) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'CẢNH BÁO Y KHOA: Chỉ số BMI của bạn là ${currentBmi.toStringAsFixed(1)} (${currentBmi >= 25.0 ? 'Béo phì' : 'Tiền béo phì'}). Mục tiêu "$_goal" không được khuyến nghị. Bạn nên chọn mục tiêu "Giảm cân" để bảo vệ sức khỏe chuyển hóa.',
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontSize: 13,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Dị ứng thực phẩm (Tuyệt đối 0% tolerance)
              Row(
                children: [
                  Icon(Icons.no_food_outlined, color: Colors.orange.shade800, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Dị ứng thực phẩm (Tuyệt đối):',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Chọn các thành phần bạn bị dị ứng nghiêm trọng. NutriCare sẽ áp dụng lệnh VETO tuyệt đối (0% dung nạp) và cảnh báo đỏ ngay lập tức nếu phát hiện món ăn chứa chúng.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8.0,
                runSpacing: 6.0,
                children: UserProfile.standardAllergens.map((allergen) {
                  final isSelected = _selectedAllergens.contains(allergen);
                  return FilterChip(
                    label: Text(allergen),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedAllergens.add(allergen);
                        } else {
                          _selectedAllergens.remove(allergen);
                        }
                      });
                    },
                    selectedColor: Colors.orange.shade100,
                    checkmarkColor: Colors.deepOrange,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.deepOrange.shade900 : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // Tiền sử bệnh lý
              Row(
                children: [
                  Icon(Icons.health_and_safety_outlined, color: Colors.green.shade800, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Tiền sử bệnh lý (Nếu có):',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Chọn các bệnh lý để hệ thống tự động thiết lập trần an toàn dinh dưỡng (muối, đường, béo bão hòa, đạm thận).',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8.0,
                runSpacing: 6.0,
                children: [
                  'Tiểu đường',
                  'Huyết áp cao',
                  'Mỡ máu',
                  'Tim mạch',
                  'Gout',
                  'Bệnh Thận',
                ].map((disease) {
                  final isSelected = _selectedDiseases.contains(disease);
                  return FilterChip(
                    label: Text(disease),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedDiseases.add(disease);
                        } else {
                          _selectedDiseases.remove(disease);
                        }
                      });
                    },
                    selectedColor: Colors.green.shade100,
                    checkmarkColor: Colors.green.shade900,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.green.shade900 : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 36),

              // Nút Lưu
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _saveProfile,
                  icon: const Icon(Icons.save_outlined, color: Colors.white),
                  label: const Text(
                    'LƯU THAY ĐỔI',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
