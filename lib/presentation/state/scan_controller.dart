import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/usecases/analyze_food_usecase.dart';
import '../../data/models/scan_history_model.dart';
import '../../data/datasources/local/database_helper.dart';
import '../../data/repositories/food_repository.dart';

// Cung cấp Repository và UseCase
final foodRepositoryProvider = Provider((ref) => FoodRepository());
final analyzeUseCaseProvider = Provider((ref) {
  return AnalyzeFoodUseCase(ref.read(foodRepositoryProvider));
});

// Provider quản lý Lịch sử (Tự động load lại khi bị invalidate)
final historyProvider = FutureProvider<List<ScanHistory>>((ref) async {
  return await DatabaseHelper.instance.getAllScans();
});

// Định nghĩa các trạng thái của màn hình
enum ScanStatus { initial, loading, success, error }

class ScanState {
  final ScanStatus status;
  final ScanHistory? result;

  ScanState({this.status = ScanStatus.initial, this.result});
}

// Controller điều phối luồng chạy
class ScanController extends Notifier<ScanState> {
  @override
  ScanState build() => ScanState();

  Future<void> startAnalysis(String imagePath) async {
    // Chuyển UI sang trạng thái Loading
    state = ScanState(status: ScanStatus.loading);

    // Yield the thread so UI can draw the loading indicator
    await Future.delayed(const Duration(milliseconds: 100));

    final useCase = ref.read(analyzeUseCaseProvider);
    final result = await useCase.execute(imagePath);

    if (result != null) {
      // Đẩy kết quả sang màn hình FoundObjectScreen (chưa ghi vào nhật ký ngày cho tới khi bấm Thêm vào thực đơn)
      state = ScanState(status: ScanStatus.success, result: result);
    } else {
      state = ScanState(status: ScanStatus.error);
    }
  }
}

// Biến toàn cục để UI gọi đến Controller
final scanControllerProvider = NotifierProvider<ScanController, ScanState>(
  ScanController.new,
);
