import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'presentation/screens/main_screen.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/state/scan_controller.dart';
import 'presentation/state/sync_controller.dart';

void main() async {
  // Đảm bảo Flutter sẵn sàng trước khi load file
  WidgetsFlutterBinding.ensureInitialized();

  // Khởi tạo Riverpod Container để gọi hàm load CSV chạy ngầm
  final container = ProviderContainer();
  await container.read(foodRepositoryProvider).loadCsvData();

  runApp(
    // Bọc toàn bộ app bằng ProviderScope
    UncontrolledProviderScope(container: container, child: const MyApp()),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NutriCare',
      theme: ThemeData(primarySwatch: Colors.green, useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncProvider);

    // Chờ quá trình kiểm tra phiên đăng nhập ngầm hoàn tất
    if (!syncState.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(color: Colors.green, strokeWidth: 3),
              ),
              SizedBox(height: 16),
              Text(
                'Đang khởi tạo ứng dụng...',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    // Nếu đã đăng nhập hoặc đang dùng chế độ khách -> Vào màn hình chính
    if (syncState.isLoggedIn || syncState.isGuest) {
      return const MainScreen();
    }

    // Nếu chưa đăng nhập -> Hiển thị màn hình đăng nhập Google
    return const LoginScreen();
  }
}
