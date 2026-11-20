import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/sync_controller.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Logo / Icon thương hiệu
                Container(
                  width: 116,
                  height: 116,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withValues(alpha: 0.16),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 2. Tên Ứng dụng & Khẩu hiệu
                const Text(
                  'NutriCare',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B233A),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Dinh Dưỡng Thông Minh & Cá Nhân Hóa',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 36),

                // 3. Thông báo lỗi hoặc tiến trình
                if (syncState.syncMessage != null && syncState.syncMessage!.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: syncState.syncMessage!.contains('Lỗi') || syncState.syncMessage!.contains('thất bại')
                          ? Colors.red.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: syncState.syncMessage!.contains('Lỗi') || syncState.syncMessage!.contains('thất bại')
                            ? Colors.red.shade200
                            : Colors.green.shade200,
                      ),
                    ),
                    child: Text(
                      syncState.syncMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: syncState.syncMessage!.contains('Lỗi') || syncState.syncMessage!.contains('thất bại')
                            ? Colors.red.shade800
                            : Colors.green.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],

                // 4. Nút bấm Đăng nhập với Google
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: syncState.isSyncing
                        ? null
                        : () => ref.read(syncProvider.notifier).signInWithGoogle(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      elevation: 2,
                      shadowColor: Colors.black.withValues(alpha: 0.15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                        side: BorderSide(color: Colors.grey.shade300, width: 1.2),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    child: syncState.isSyncing
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Đang xử lý...',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.network(
                                'https://fonts.gstatic.com/s/i/productlogos/googleg/v6/24px.svg',
                                width: 22,
                                height: 22,
                                errorBuilder: (context, error, stackTrace) => const Icon(
                                  Icons.account_circle,
                                  color: Colors.blue,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Text(
                                'Đăng nhập với Google',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 12),

                // 5. Nút dùng thử không cần đăng nhập (Chế độ Khách)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: syncState.isSyncing
                        ? null
                        : () => ref.read(syncProvider.notifier).continueAsGuest(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green.shade800,
                      side: BorderSide(color: Colors.green.shade300, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    icon: const Icon(Icons.person_outline_rounded, size: 20),
                    label: const Text(
                      'Tiếp tục không cần đăng nhập',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 6. Ghi chú phân quyền tính năng
                Text(
                  'Không đăng nhập vẫn dùng được Tra cứu thực phẩm và Lịch sử trên máy. Đăng nhập Google để mở khóa Tư vấn AI, Hồ sơ, Tiến trình ngày và đồng bộ đám mây.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
