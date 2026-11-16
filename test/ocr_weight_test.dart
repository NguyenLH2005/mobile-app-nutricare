import 'dart:ui' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:nckh_app/data/datasources/local/ai_helper.dart';

void main() {
  final ai = AIHelper.instance;

  test('Reads 2-column tilted BAPI Meat sticker as 0.308KG instead of 121G', () {
    // Mô phỏng tem BAPI Meat hơi nghiêng ~15 độ và bị tách cột theo TextBlock của ML Kit
    final lines = [
      const OcrTextLine(text: 'Ngày đóng gói', box: Rect.fromLTRB(40, 100, 180, 122)),
      const OcrTextLine(text: 'Hạn sử dụng:', box: Rect.fromLTRB(40, 128, 175, 150)),
      const OcrTextLine(text: 'T. Lượng (Kg):', box: Rect.fromLTRB(40, 158, 185, 180)),
      const OcrTextLine(text: 'Đơn giá (vnđ):', box: Rect.fromLTRB(40, 188, 185, 210)),
      const OcrTextLine(text: '23.08.2022', box: Rect.fromLTRB(210, 88, 315, 110)),
      const OcrTextLine(text: '0.308', box: Rect.fromLTRB(215, 146, 285, 168)),
      const OcrTextLine(text: '121.000', box: Rect.fromLTRB(218, 176, 305, 198)),
      const OcrTextLine(text: 'Thành tiền', box: Rect.fromLTRB(330, 80, 440, 104)),
      const OcrTextLine(text: '37.268 vnđ', box: Rect.fromLTRB(340, 110, 470, 136)),
      const OcrTextLine(text: '2 110010 003088', box: Rect.fromLTRB(160, 230, 420, 254)),
    ];

    expect(ai.extractWeightFromOcrLines(lines), '0.308KG');

    // Trường hợp xếp dọc tách dòng: Đơn giá -> 121.000 -> T. Lượng (Kg) -> 0.308
    expect(
      ai.extractWeightFromOcrLines([
        const OcrTextLine(text: 'Đơn giá (vnđ)'),
        const OcrTextLine(text: '121.000'),
        const OcrTextLine(text: 'T. Lượng (Kg):'),
        const OcrTextLine(text: '0.308'),
      ]),
      '0.308KG',
    );
  });

  test('Preserves .000 / .00 weights such as 1.00kg and T. Lượng (Kg): 1.000', () {
    expect(
      ai.extractWeightFromOcrLines([
        const OcrTextLine(text: 'Đơn giá: 85.000 d/kg'),
        const OcrTextLine(text: 'T. Lượng (Kg): 1.000'),
      ]),
      '1KG',
    );
    expect(
      ai.extractWeightFromOcrLines([
        const OcrTextLine(text: 'Thịt ba rọi 1.00kg'),
      ]),
      '1KG',
    );
    expect(
      ai.extractWeightFromOcrLines([
        const OcrTextLine(text: '0.500 kg'),
      ]),
      '0.5KG',
    );
  });

  test('Handles unit before number, inline price/weight mix, commas, and nutrition labels safely', () {
    expect(
      ai.extractWeightFromOcrLines([
        const OcrTextLine(text: 'Trọng lượng (g): 10'),
      ]),
      '10G',
    );
    expect(
      ai.extractWeightFromOcrLines([
        const OcrTextLine(text: 'Đơn giá: 120.000đ | KL: 350g'),
      ]),
      '350G',
    );
    expect(
      ai.extractWeightFromOcrLines([
        const OcrTextLine(text: 'KL: 250g | Đơn giá: 25.000d/100g'),
      ]),
      '250G',
    );
    expect(
      ai.extractWeightFromOcrLines([
        const OcrTextLine(text: 'T.Lượng (Kg): 0,450'),
      ]),
      '0.45KG',
    );
    expect(
      ai.extractWeightFromOcrLines([
        const OcrTextLine(text: 'Năng lượng: 150 kcal'),
      ]),
      isNull,
    );
  });
}
