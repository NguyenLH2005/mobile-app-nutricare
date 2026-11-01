import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/scan_history_model.dart';

class ResultScreen extends StatelessWidget {
  final ScanHistory resultData;

  const ResultScreen({super.key, required this.resultData});

  @override
  Widget build(BuildContext context) {
    final nutritionList = resultData.decodedNutrition;
    final timeString = DateFormat('HH:mm dd/MM/yyyy').format(resultData.createdAt);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'Chi Tiết Dinh Dưỡng',
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.green),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 1. KHU VỰC TỔNG QUAN
            Container(
              color: Colors.white,
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      timeString,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    resultData.foodName.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  if (resultData.weight != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        resultData.consumptionRatio < 1.0
                            ? 'Khối lượng tiêu thụ: ${resultData.actualWeight.toStringAsFixed(0)}g (ăn ${(resultData.consumptionRatio * 100).round()}% khay)'
                            : 'Khối lượng nhận diện: ${resultData.formatWeight(spaceBeforeUnit: false)}',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 2. KHU VỰC BẢNG THÀNH PHẦN DINH DƯỠNG
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Thành phần dinh dưỡng',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // Tiêu đề các cột
                  Row(
                    children: [
                      const Expanded(
                        flex: 2,
                        child: Text(
                          'Dưỡng chất',
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          'Trên 100g',
                          textAlign: TextAlign.right,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                      if (resultData.weight != null)
                        Expanded(
                          flex: 1,
                          child: Text(
                            resultData.consumptionRatio < 1.0
                                ? 'Trên ${resultData.actualWeight.toStringAsFixed(0)}g'
                                : 'Trên ${resultData.formatWeight(spaceBeforeUnit: false)}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 24, thickness: 1),

                  // Danh sách các chất (Lặp từ JSON ra)
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: nutritionList.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 24),
                    itemBuilder: (context, index) {
                      final item = nutritionList[index];
                      return Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              item['name'],
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              '${item['per_100g']} ${item['unit']}',
                              textAlign: TextAlign.right,
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ),
                          if (resultData.weight != null)
                            Expanded(
                              flex: 1,
                              child: Text(
                                '${(((item['per_label'] as num?)?.toDouble() ?? 0.0) * (resultData.consumptionRatio > 0 ? resultData.consumptionRatio : 1.0)).toStringAsFixed(1)} ${item['unit']}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
