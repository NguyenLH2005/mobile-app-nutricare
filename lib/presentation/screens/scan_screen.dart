import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'found_object_screen.dart';

import '../state/scan_controller.dart';

// Đổi thành ConsumerStatefulWidget để dùng Riverpod
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  void _clearImage() {
    setState(() {
      _selectedImage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 1. THEO DÕI TRẠNG THÁI: Bất cứ khi nào Controller đổi state, biến này sẽ cập nhật
    final scanState = ref.watch(scanControllerProvider);
    final isLoading = scanState.status == ScanStatus.loading;

    // 2. LẮNG NGHE SỰ KIỆN: Dùng để show thông báo hoặc chuyển trang mà không làm lỗi giao diện
    ref.listen<ScanState>(scanControllerProvider, (previous, next) {
      if (next.status == ScanStatus.success && next.result != null) {
        // Xóa ảnh cũ đi
        setState(() {
          _selectedImage = null;
        });

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FoundObjectScreen(
              resultData: next.result!,
              isFromScan: true,
            ),
          ),
        );
      } else if (next.status == ScanStatus.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lỗi phân tích hình ảnh, vui lòng thử lại!')),
        );
      }
    });

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Tra Cứu Thực Phẩm',
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Khung chứa ảnh
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: _selectedImage == null
                      ? Border.all(color: Colors.grey, style: BorderStyle.solid)
                      : null,
                  image: _selectedImage != null
                      ? DecorationImage(
                          image: FileImage(_selectedImage!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _selectedImage == null
                    ? const Center(
                        child: Icon(
                          Icons.image_outlined,
                          size: 50,
                          color: Colors.grey,
                        ),
                      )
                    : Stack(
                        children: [
                          // Nếu đang loading thì ẩn cái nút X đi để người dùng không bấm xóa ngang
                          if (!isLoading)
                            Positioned(
                              top: 10,
                              right: 10,
                              child: GestureDetector(
                                onTap: _clearImage,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),

            // Hai nút Camera và Thư viện (Mờ đi khi đang loading)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isLoading
                        ? null
                        : () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Máy ảnh'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green,
                      disabledForegroundColor: Colors.grey,
                      side: BorderSide(
                        color: isLoading ? Colors.grey : Colors.green,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isLoading
                        ? null
                        : () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Thư viện'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green,
                      disabledForegroundColor: Colors.grey,
                      side: BorderSide(
                        color: isLoading ? Colors.grey : Colors.green,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),

            // Khu vực Nút TRA CỨU hoặc Vòng xoay Loading
            SizedBox(
              width: double.infinity,
              height: 55, // Fix cứng chiều cao để không bị giật UI khi đổi nút
              child: isLoading
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.green,
                            strokeWidth: 3,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Hệ thống đang phân tích...',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    )
                  : ElevatedButton(
                      onPressed: _selectedImage != null
                          ? () {
                              // GỌI CONTROLLER CHẠY LOGIC
                              ref
                                  .read(scanControllerProvider.notifier)
                                  .startAnalysis(_selectedImage!.path);
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: Text(
                        'TRA CỨU',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _selectedImage != null
                              ? Colors.white
                              : Colors.grey.shade500,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}



