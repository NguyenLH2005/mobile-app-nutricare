import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/user_profile_model.dart';
import '../state/profile_controller.dart';
import '../state/sync_controller.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  // Quản lý trạng thái mở rộng độc lập cho từng chỉ số
  final Set<String> _expandedKeys = {};

  void _toggleExpanded(String key) {
    setState(() {
      if (_expandedKeys.contains(key)) {
        _expandedKeys.remove(key);
      } else {
        _expandedKeys.add(key);
      }
    });
  }

  Future<void> _handleSignOut() async {
    final hasUnsynced = await ref.read(syncProvider.notifier).hasUnsyncedData();

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              hasUnsynced ? Icons.warning_amber_rounded : Icons.logout_rounded,
              color: hasUnsynced ? Colors.orange : Colors.red,
            ),
            const SizedBox(width: 8),
            Text(hasUnsynced ? 'Cảnh báo dữ liệu' : 'Đăng xuất tài khoản'),
          ],
        ),
        content: Text(
          hasUnsynced
              ? 'Bạn có một số dữ liệu (lịch sử quét hoặc thông tin hồ sơ) CHƯA được sao lưu lên đám mây.\n\nNếu tiếp tục đăng xuất, toàn bộ dữ liệu trên thiết bị này sẽ bị xóa sạch và không thể khôi phục lại.\n\nBạn có chắc chắn muốn đăng xuất không?'
              : 'Dữ liệu của bạn đã được sao lưu an toàn trên đám mây. Bạn có chắc chắn muốn đăng xuất khỏi tài khoản Google không?',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              elevation: 0,
            ),
            child: Text(
              hasUnsynced ? 'Vẫn đăng xuất' : 'Đăng xuất',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(syncProvider.notifier).signOut();
    }
  }

  String _getActivityFactorText(double factor) {
    if (factor <= 1.2) return 'Ít vận động - Làm việc văn phòng';
    if (factor <= 1.375) return 'Vận động nhẹ - Tập 1-3 ngày/tuần';
    if (factor <= 1.55) return 'Vận động vừa - Tập 3-5 ngày/tuần';
    if (factor <= 1.725) return 'Vận động nhiều - Tập 6-7 ngày/tuần';
    return 'Vận động rất nhiều - Tập nặng 2 lần/ngày';
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);
    final syncState = ref.watch(syncProvider);
    final profile = profileState.profile;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text(
          'Hồ Sơ Cá Nhân',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Chỉnh sửa hồ sơ',
            icon: const Icon(Icons.edit_outlined, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Thẻ Tài khoản Google (Bỏ icon đã đồng bộ)
            _buildUserAccountCard(syncState),
            const SizedBox(height: 16),

            // 2. Nếu chưa có hồ sơ -> Cảnh báo thiết lập
            if (profile == null) ...[
              _buildEmptyProfileBanner(context),
              const SizedBox(height: 24),
            ] else ...[
              // 3. Thể trạng & Thể hình (Hiển thị theo hàng + BMI có nút xổ xuống + Chế độ béo phì)
              _buildBodyMetricsCard(profile, profileState.age),
              const SizedBox(height: 16),

              // 4. Chỉ số Chuyển hóa & Năng lượng (Hiển thị theo hàng + màu nhã nhặn + mũi tên xổ xuống)
              _buildMetabolicCard(profile),
              const SizedBox(height: 16),

              // 5. Ngân sách dinh dưỡng
              _buildMacroBudgetsCard(profile),
              const SizedBox(height: 16),

              // 6. Cảnh báo Y khoa & Trần Giới hạn An toàn & Dị ứng
              _buildMedicalCeilingsCard(profile),
              const SizedBox(height: 28),
            ],

            // 7. Nút Đăng xuất ở dưới cùng của trang
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _handleSignOut,
                icon: const Icon(Icons.logout_rounded, color: Colors.red),
                label: const Text(
                  'Đăng Xuất Tài Khoản',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.shade300, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // 1. Thẻ Tài khoản Google: Chỉ hiển thị Avatar, Tên và Email (đã bỏ icon đồng bộ)
  Widget _buildUserAccountCard(AuthUserState syncState) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.green.shade50,
            backgroundImage:
                syncState.avatarUrl != null ? NetworkImage(syncState.avatarUrl!) : null,
            child: syncState.avatarUrl == null
                ? const Icon(Icons.person, color: Colors.green, size: 28)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  syncState.name ?? 'Người dùng NutriCare',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF1B233A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  syncState.email ?? '',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyProfileBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        children: [
          const Icon(Icons.assignment_ind_outlined, size: 48, color: Colors.deepOrange),
          const SizedBox(height: 12),
          const Text(
            'Chưa có Thông tin Hồ sơ!',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Colors.deepOrange,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Hãy bổ sung Chiều cao, Cân nặng và Mục tiêu để AI có thể phân tích chính xác lời khuyên y khoa dành riêng cho bạn.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black87, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              );
            },
            icon: const Icon(Icons.add, color: Colors.white, size: 18),
            label: const Text(
              'Thiết lập Hồ sơ ngay',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // 2. Thể trạng & Thể hình (Hiển thị theo từng hàng + BMI có nút xổ xuống + Chế độ béo phì)
  Widget _buildBodyMetricsCard(UserProfile profile, int? age) {
    final double weight = profile.weight;
    final double height = profile.height;
    final double bmi = profile.bmi;

    String bmiCategory = 'Bình thường';
    Color bmiColor = Colors.green.shade700;
    if (bmi < 18.5) {
      bmiCategory = 'Gầy / Thiếu cân';
      bmiColor = Colors.blue.shade700;
    } else if (bmi >= 23.0 && bmi < 25.0) {
      bmiCategory = 'Tiền béo phì';
      bmiColor = Colors.orange.shade800;
    } else if (bmi >= 25.0) {
      bmiCategory = 'Béo phì';
      bmiColor = Colors.red.shade700;
    }

    final bool canEnableObesity = bmi >= 23.0;
    final bool isObesityOn = profile.isObesityMode;
    final bool hasGoalWarning = canEnableObesity &&
        !isObesityOn &&
        ((bmi >= 25.0 && profile.goal != 'Giảm cân') ||
         (bmi >= 23.0 && profile.goal == 'Tăng cân'));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.accessibility_new_rounded, color: Colors.green.shade700, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Thể Trạng & Thể Hình',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Divider(height: 20),

          // Hàng 1: Giới tính, Tuổi, Ngày sinh (rộng rãi, không bị rớt dòng ngày sinh)
          Row(
            children: [
              _buildMetricItem('Giới tính', profile.gender),
              _buildMetricItem('Tuổi', age != null ? '$age tuổi' : profile.dobFormatted),
              _buildMetricItem('Ngày sinh', profile.dobFormatted),
            ],
          ),
          const SizedBox(height: 12),
          // Hàng 2: Chiều cao, Cân nặng
          Row(
            children: [
              _buildMetricItem('Chiều cao', '${height.toStringAsFixed(0)} cm'),
              _buildMetricItem('Cân nặng', '${weight.toStringAsFixed(1)} kg'),
              const Expanded(child: SizedBox()),
            ],
          ),
          const Divider(height: 24),

          // Hàng 2: Mức độ vận động
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.directions_run_outlined, color: Colors.grey.shade700, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                    children: [
                      const TextSpan(
                        text: 'Mức độ vận động: ',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(
                        text: '${_getActivityFactorText(profile.activityFactor)} • Hệ số vận động: ${profile.activityFactor}',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Hàng 3: Mục tiêu
          Row(
            children: [
              Icon(Icons.track_changes_outlined, color: Colors.grey.shade700, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                    children: [
                      const TextSpan(
                        text: 'Mục tiêu: ',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(
                        text: profile.goal,
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade800),
                      ),
                      if (isObesityOn)
                        TextSpan(
                          text: ' • Khóa chế độ giảm cân',
                          style: TextStyle(fontSize: 12, color: Colors.orange.shade800, fontStyle: FontStyle.italic),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Hàng 4: Chỉ số BMI (có nút mũi tên xổ xuống giải thích)
          _buildExpandableMetricRow(
            title: 'Chỉ số BMI',
            subtitle: 'Chỉ số khối cơ thể',
            value: '${bmi.toStringAsFixed(1)} • $bmiCategory',
            valueColor: bmiColor,
            explanationKey: 'bmi',
            definitionText: 'BMI là chỉ số đo lường mức độ tương quan giữa chiều cao và cân nặng để đánh giá độ gầy béo của cơ thể.',
            usageText: 'BMI dùng để xác định nhanh thể trạng của bạn đang thiếu cân, bình thường, tiền béo phì hay béo phì theo chuẩn WHO dành cho người châu Á.',
          ),

          // Cảnh báo thể trạng đỏ nếu BMI cao mà chọn tăng cân / giữ dáng
          if (hasGoalWarning) ...[
            Container(
              margin: const EdgeInsets.only(top: 6, bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'CẢNH BÁO THỂ TRẠNG: Bạn đang ở mức $bmiCategory (BMI = ${bmi.toStringAsFixed(1)}). Mục tiêu "${profile.goal}" không phù hợp với sức khỏe chuyển hóa. Hãy bật "Chế độ kiểm soát béo phì" dưới đây để áp dụng thâm hụt năng lượng an toàn.',
                      style: TextStyle(
                        color: Colors.red.shade900,
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Chế độ kiểm soát béo phì (Toggle Switch)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isObesityOn
                  ? Colors.green.shade50.withValues(alpha: 0.6)
                  : (canEnableObesity ? Colors.grey.shade50 : Colors.grey.shade100),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isObesityOn ? Colors.green.shade300 : Colors.grey.shade300,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.monitor_heart_outlined,
                  color: isObesityOn
                      ? Colors.green.shade700
                      : (canEnableObesity ? Colors.grey.shade700 : Colors.grey.shade400),
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chế độ kiểm soát béo phì',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: canEnableObesity ? const Color(0xFF1B233A) : Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        canEnableObesity
                            ? (isObesityOn
                                ? 'Đang bật: Thâm hụt 500 kcal, trần đường <= 5%'
                                : 'Gợi ý bật để can thiệp giảm mỡ và cân bằng chuyển hóa')
                            : 'Vô hiệu hóa: Chỉ khả dụng khi BMI >= 23 • Tiền béo phì / Béo phì',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: canEnableObesity ? Colors.grey.shade700 : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isObesityOn,
                  activeThumbColor: Colors.green.shade700,
                  onChanged: canEnableObesity
                      ? (val) async {
                          await ref.read(profileProvider.notifier).toggleObesityMode(val);
                          await ref.read(syncProvider.notifier).syncNow();
                        }
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 3. Chỉ số Chuyển hóa & Năng lượng (Theo hàng + màu nhã nhặn + mũi tên xổ xuống)
  Widget _buildMetabolicCard(UserProfile profile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_fire_department_rounded, color: Colors.orange.shade700, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Chỉ Số Chuyển Hóa & Năng Lượng',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Divider(height: 20),

          // 1. Hàng BMR
          _buildExpandableMetricRow(
            title: 'BMR',
            subtitle: 'Năng lượng chuyển hóa cơ bản',
            value: '${profile.bmr.toStringAsFixed(0)} kcal/ngày',
            explanationKey: 'bmr',
            definitionText: 'Năng lượng tối thiểu cơ thể cần để duy trì sự sống khi nghỉ ngơi suốt 24 giờ.',
            usageText: 'Ngưỡng sàn calo an toàn, tuyệt đối không ăn dưới mức này để tránh suy nhược và hạ trao đổi chất.',
          ),

          // 2. Hàng TDEE
          _buildExpandableMetricRow(
            title: 'TDEE',
            subtitle: 'Tổng năng lượng tiêu hao mỗi ngày',
            value: '${profile.tdee.toStringAsFixed(0)} kcal/ngày',
            explanationKey: 'tdee',
            definitionText: 'Tổng lượng calo cơ thể đốt cháy mỗi ngày, gồm BMR, vận động và tiêu hóa thức ăn.',
            usageText: 'Mốc calo chuẩn để giữ nguyên cân nặng hiện tại.',
          ),

          // 3. Hàng Calo Mục Tiêu
          _buildExpandableMetricRow(
            title: 'Calo Mục Tiêu',
            subtitle: 'Lượng calo nạp theo kế hoạch',
            value: '${profile.targetCalories.toStringAsFixed(0)} kcal/ngày',
            explanationKey: 'target',
            valueColor: Colors.green.shade800,
            definitionText: 'Lượng calo nạp vào mỗi ngày theo kế hoạch thể hình của bạn.',
            usageText: 'Tạo mức thâm hụt để giảm cân hoặc thặng dư calo để tăng cân an toàn so với TDEE.',
          ),
        ],
      ),
    );
  }

  // Widget hiển thị từng hàng chỉ số có mũi tên xổ xuống độc lập
  Widget _buildExpandableMetricRow({
    required String title,
    required String value,
    required String explanationKey,
    required String definitionText,
    required String usageText,
    String? subtitle,
    Color? valueColor,
  }) {
    final isExpanded = _expandedKeys.contains(explanationKey);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isExpanded ? Colors.green.shade300 : Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _toggleExpanded(explanationKey),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1B233A),
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: valueColor ?? const Color(0xFF1B233A),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.grey.shade600,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50.withValues(alpha: 0.4),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    definitionText,
                    style: const TextStyle(fontSize: 13, height: 1.45, color: Colors.black87),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    usageText,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Colors.green.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 4. Ngân sách dinh dưỡng
  Widget _buildMacroBudgetsCard(UserProfile profile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pie_chart_rounded, color: Colors.teal.shade700, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Ngân sách dinh dưỡng',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            children: [
              _buildMacroTile('Chất Đạm (Protein)', '${profile.budgetProtein.toStringAsFixed(1)} g', Colors.purple),
              const SizedBox(width: 10),
              _buildMacroTile('Chất Bột Đường', '${profile.budgetCarb.toStringAsFixed(1)} g', Colors.blue),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildMacroTile('Chất Béo (Fat)', '${profile.budgetFat.toStringAsFixed(1)} g', Colors.orange),
              const SizedBox(width: 10),
              _buildMacroTile('Chất Xơ (Fiber)', '${profile.budgetFiber.toStringAsFixed(1)} g', Colors.green),
            ],
          ),
        ],
      ),
    );
  }

  // 5. Cảnh báo Y khoa & Trần Giới hạn An toàn & Dị ứng
  Widget _buildMedicalCeilingsCard(UserProfile profile) {
    final List<String> conditions = profile.medicalConditions;
    final List<String> allergies = profile.allergies;
    final flags = profile.medicalFlags;
    final hasDiabetes = flags.isNotEmpty && flags[0] == '1';
    final hasHypertension = flags.length > 1 && flags[1] == '1';
    final hasLipid = flags.length > 2 && flags[2] == '1';
    final hasGout = flags.length > 3 && flags[3] == '1';
    final hasKidney = profile.ceilingProteinKidney > 0;
    final hasCardio = flags.length > 5 && flags[5] == '1';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.health_and_safety_outlined, color: Colors.red.shade700, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Trần Giới Hạn Y Khoa & Dị Ứng',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Divider(height: 20),

          // 1. Dị ứng thực phẩm tuyệt đối
          Row(
            children: [
              Icon(Icons.no_food_outlined, color: Colors.orange.shade800, size: 16),
              const SizedBox(width: 6),
              const Text(
                'Dị ứng thực phẩm tuyệt đối (0% dung nạp):',
                style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (allergies.isEmpty)
            const Text(
              'Không ghi nhận dị ứng thực phẩm.',
              style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 13),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: allergies.map((a) {
                return Chip(
                  avatar: const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.deepOrange),
                  label: Text(
                    a,
                    style: TextStyle(fontSize: 12, color: Colors.deepOrange.shade900, fontWeight: FontWeight.w600),
                  ),
                  backgroundColor: Colors.orange.shade50,
                  side: BorderSide(color: Colors.orange.shade200),
                  padding: const EdgeInsets.all(2),
                );
              }).toList(),
            ),
          const Divider(height: 22),

          // 2. Bệnh lý ghi nhận
          const Text('Bệnh lý ghi nhận:', style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (conditions.isEmpty)
            const Text(
              'Không ghi nhận tiền sử bệnh lý.',
              style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 13),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: conditions.map((c) {
                return Chip(
                  label: Text(c, style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600)),
                  backgroundColor: Colors.red.shade50,
                  side: BorderSide(color: Colors.red.shade200),
                  padding: const EdgeInsets.all(2),
                );
              }).toList(),
            ),
          const SizedBox(height: 14),

          // 3. Trần an toàn y tế & vi chất dinh dưỡng
          const Text(
            'Ngưỡng dinh dưỡng & Trần an toàn:',
            style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          // Đường
          _buildCeilingRow(
            label: 'Đường tự do (Free Sugars)',
            value: '<= ${profile.ceilingSugar.toStringAsFixed(1)} g/ngày',
            isAffected: hasDiabetes || profile.isObesityMode,
            reason: hasDiabetes
                ? 'Do bạn mắc bệnh Tiểu đường • Khống chế <= 5% calo'
                : (profile.isObesityMode ? 'Do chế độ kiểm soát béo phì • Khống chế <= 5% calo' : null),
          ),
          const Divider(height: 12),

          // Natri
          _buildCeilingRow(
            label: 'Natri / Muối',
            value: '<= ${profile.ceilingSodium.toStringAsFixed(0)} mg/ngày',
            isAffected: hasHypertension || hasCardio,
            reason: (hasHypertension && hasCardio)
                ? 'Do bạn mắc bệnh Tăng huyết áp & Tim mạch'
                : (hasHypertension
                    ? 'Do bạn mắc bệnh Tăng huyết áp'
                    : (hasCardio ? 'Do bạn mắc bệnh Tim mạch' : null)),
          ),
          const Divider(height: 12),

          // Béo bão hòa
          _buildCeilingRow(
            label: 'Chất béo bão hòa (Saturated Fat)',
            value: '<= ${profile.ceilingSatFat.toStringAsFixed(1)} g/ngày',
            isAffected: hasLipid,
            reason: hasLipid ? 'Do bạn mắc bệnh Rối loạn lipid máu/Mỡ máu • Dưới 7% calo' : null,
          ),
          const Divider(height: 12),

          // Kali
          _buildCeilingRow(
            label: 'Kali (Potassium)',
            value: hasKidney ? '<= 2000 mg/ngày' : '3500 - 4700 mg/ngày',
            isAffected: hasKidney,
            reason: hasKidney ? 'Do bạn mắc bệnh Thận mạn • Giảm khả năng bài tiết Kali' : null,
          ),
          const Divider(height: 12),

          // Photpho
          _buildCeilingRow(
            label: 'Photpho (Phosphorus)',
            value: hasKidney ? '<= 800 mg/ngày' : '700 - 1000 mg/ngày',
            isAffected: hasKidney,
            reason: hasKidney ? 'Do bạn mắc bệnh Thận mạn • Ngừa lắng đọng khoáng chất' : null,
          ),

          // Đạm thận (nếu có bệnh thận)
          if (hasKidney) ...[
            const Divider(height: 12),
            _buildCeilingRow(
              label: 'Chất đạm (Protein)',
              value: '<= ${profile.ceilingProteinKidney.toStringAsFixed(1)} g/ngày',
              isAffected: true,
              reason: 'Do bạn mắc bệnh Thận mạn • Kiểm soát 0.8g/kg/ngày theo KDIGO 2024',
            ),
          ],

          // Trần Đạm/Purine cho người bệnh Gout
          if (hasGout) ...[
            const Divider(height: 12),
            _buildCeilingRow(
              label: 'Đạm giàu Purine - Bệnh Gout',
              value: '<= 25 g/bữa ăn',
              isAffected: true,
              reason: 'Do bạn mắc bệnh Gout • Hạn chế thịt đỏ, hải sản vỏ cứng để tránh kích hoạt cơn Gout cấp',
            ),
          ],

          // Nhu cầu Chất xơ chuẩn hóa theo Viện Dinh Dưỡng & WHO
          const Divider(height: 12),
          _buildCeilingRow(
            label: 'Chất xơ (Dietary Fiber)',
            value: '>= ${profile.budgetFiber.toStringAsFixed(0)} g/ngày',
            isAffected: profile.isObesityMode || hasDiabetes || hasLipid,
            reason: (profile.isObesityMode || hasDiabetes || hasLipid)
                ? 'Khuyến nghị tăng cường chất xơ giúp ổn định đường huyết, kiểm soát cân nặng & giảm mỡ máu'
                : 'Mức khuyến nghị tối thiểu bảo vệ hệ tiêu hóa của Viện Dinh Dưỡng NIN',
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildMacroTile(String name, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildCeilingRow({
    required String label,
    required String value,
    String? reason,
    bool isAffected = false,
  }) {
    final textWeight = isAffected ? FontWeight.bold : FontWeight.normal;
    final textColor = Colors.black87;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: textColor,
                    fontWeight: textWeight,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  color: textColor,
                  fontWeight: textWeight,
                ),
              ),
            ],
          ),
          if (isAffected && reason != null) ...[
            const SizedBox(height: 2),
            Text(
              '• $reason',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.grey.shade700,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
