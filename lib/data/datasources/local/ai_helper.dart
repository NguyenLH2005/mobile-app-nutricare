import 'dart:isolate';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrTextLine {
  final String text;
  final Rect? box;

  const OcrTextLine({required this.text, this.box});
}

class AIHelper {
  String _removeDiacritics(String str) {
    var withDia = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ';
    var withoutDia = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyydAAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD';
    for (int i = 0; i < withDia.length; i++) {
      str = str.replaceAll(withDia[i], withoutDia[i]);
    }
    return str;
  }

  static final AIHelper instance = AIHelper._init();
  AIHelper._init();

  Interpreter? _cropInterpreter;
  Interpreter? _classifyInterpreter;

  static const List<String> labels = [
    'Bạch tuộc', 'Bắp cải', 'Bầu', 'Bí đỏ', 'Bơ', 
    'Cà chua', 'Cá điêu hồng', 'Cá hồi', 'Cá lóc', 'Cá ngừ', 
    'Cà rốt', 'Cá thu', 'Cải xanh', 'Cam', 'Chôm chôm', 
    'Chuối', 'Cua', 'Dâu tây', 'Đu đủ', 'Dưa hấu', 'Dưa leo', 
    'Ếch', 'Hạnh nhân', 'Khổ qua', 'Khoai lang', 'Khoai tây', 
    'Khóm', 'Lê', 'Mực', 'Nấm đùi gà', 'Nấm kim châm', 'Nấm rơm', 
    'Ngô', 'Nho', 'Óc chó', 'Ổi', 'Ớt chuông', 
    'Rau muống', 'Sầu riêng', 'Súp lơ', 'Táo', 'Thanh long', 
    'Thịt bò', 'Thịt gà', 'Thịt heo', 'Thịt vịt', 'Tôm', 'Trứng', 
    'Vải', 'Xoài'
  ];

  Future<void> init() async {
    _cropInterpreter ??= await Interpreter.fromAsset('assets/models/crop_model.tflite');
    _classifyInterpreter ??= await Interpreter.fromAsset('assets/models/classify_model.tflite');
  }

  /// 1. CHẠY MODEL NHẬN DIỆN VÀ CẮT ẢNH
  Future<Map<String, String?>> detectAndCrop(String imagePath) async {
    await init();

    // Tự động nhận diện kích thước đầu vào từ chính mô hình (ví dụ: [1, 3, 640, 640] -> 640)
    final inputShape = _cropInterpreter!.getInputTensor(0).shape;
    final int inputSize = inputShape.length >= 4 ? inputShape[2] : 640;
    
    // Đọc ảnh gốc và xử lý Tensor trên Isolate (Luồng nền) để không làm đơ UI
    final isolateResult = await Isolate.run(() {
      final File imageFile = File(imagePath);
      final img.Image? originalImage = img.decodeImage(imageFile.readAsBytesSync());
      if (originalImage == null) return {'error': 'Không thể đọc ảnh gốc'};

      final int origW = originalImage.width;
      final int origH = originalImage.height;
      
      img.Image resizedImage = img.copyResize(
        originalImage,
        width: inputSize,
        height: inputSize,
      );

      var input = List.generate(
        1,
        (i) => List.generate(
          3, 
          (c) => List.generate(
            inputSize,
            (y) => List.filled(inputSize, 0.0),
          ),
        ),
      );

      for (int y = 0; y < inputSize; y++) {
        for (int x = 0; x < inputSize; x++) {
          final pixel = resizedImage.getPixel(x, y);
          input[0][0][y][x] = pixel.r / 255.0; 
          input[0][1][y][x] = pixel.g / 255.0; 
          input[0][2][y][x] = pixel.b / 255.0; 
        }
      }
      
      return {
        'originalImage': originalImage,
        'origW': origW,
        'origH': origH,
        'input': input,
        'inputSize': inputSize,
      };
    });

    if (isolateResult.containsKey('error')) throw Exception(isolateResult['error']);

    final img.Image originalImage = isolateResult['originalImage'] as img.Image;
    final int origW = isolateResult['origW'] as int;
    final int origH = isolateResult['origH'] as int;
    final List<List<List<List<double>>>> input = isolateResult['input'] as List<List<List<List<double>>>>;


    // Lấy output tensor shape để tạo mảng chứa kết quả
    final outputShape = _cropInterpreter!.getOutputTensor(0).shape;
    var output = List.filled(outputShape.reduce((a, b) => a * b), 0.0).reshape(outputShape);

    // Chạy model
    _cropInterpreter!.run(input, output);

    // Xử lý output để tìm bounding box tốt nhất cho Food (class 0) và Label (class 1)
    double maxFoodProb = 0.0;
    int maxFoodIndex = -1;
    double maxLabelProb = 0.0;
    int maxLabelIndex = -1;

    bool isTransposed = outputShape[1] > outputShape[2]; // e.g. [1, 8400, 6]
    int numBoxes = isTransposed ? outputShape[1] : outputShape[2];

    for (int i = 0; i < numBoxes; i++) {
      double foodProb = isTransposed ? output[0][i][4] : output[0][4][i];
      double labelProb = isTransposed ? output[0][i][5] : output[0][5][i];
      
      if (foodProb > maxFoodProb) {
        maxFoodProb = foodProb;
        maxFoodIndex = i;
      }
      if (labelProb > maxLabelProb && labelProb > 0.20) {
        maxLabelProb = labelProb;
        maxLabelIndex = i;
      }
    }

    Future<String> saveCroppedImage({
      required int x,
      required int y,
      required int width,
      required int height,
      required String filePrefix,
    }) async {
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/${filePrefix}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await Isolate.run(() {
        final cropped = img.copyCrop(originalImage, x: x, y: y, width: width, height: height);
        File(path).writeAsBytesSync(img.encodeJpg(cropped));
      });

      return path;
    }

    // Hàm phụ trợ để giải mã tọa độ và cắt ảnh an toàn tuyệt đối
    Future<String> cropAndSave(int index) async {
      double xc = isTransposed ? output[0][index][0] : output[0][0][index];
      double yc = isTransposed ? output[0][index][1] : output[0][1][index];
      double w = isTransposed ? output[0][index][2] : output[0][2][index];
      double h = isTransposed ? output[0][index][3] : output[0][3][index];

      // Nếu model trả về tọa độ chuẩn hóa [0.0, 1.0], nhân lên tỷ lệ inputSize
      if (w <= 2.0 && h <= 2.0) {
        xc *= inputSize;
        yc *= inputSize;
        w *= inputSize;
        h *= inputSize;
      }

      final double x1 = xc - w / 2;
      final double y1 = yc - h / 2;

      final int cropX = (x1 / inputSize * origW).toInt().clamp(0, origW - 1);
      final int cropY = (y1 / inputSize * origH).toInt().clamp(0, origH - 1);
      final int cropW = (w / inputSize * origW).toInt().clamp(1, origW - cropX);
      final int cropH = (h / inputSize * origH).toInt().clamp(1, origH - cropY);

      return saveCroppedImage(
        x: cropX,
        y: cropY,
        width: cropW,
        height: cropH,
        filePrefix: 'crop_$index',
      );
    }

    // Hàm dự phòng cắt vùng trung tâm 85% ảnh nếu góc chụp mờ hoặc không vượt ngưỡng tin cậy
    Future<String> cropCenterFallback() async {
      final int cropW = (origW * 0.85).toInt().clamp(1, origW);
      final int cropH = (origH * 0.85).toInt().clamp(1, origH);
      final int cropX = ((origW - cropW) / 2).toInt().clamp(0, origW - 1);
      final int cropY = ((origH - cropH) / 2).toInt().clamp(0, origH - 1);

      return saveCroppedImage(
        x: cropX,
        y: cropY,
        width: cropW,
        height: cropH,
        filePrefix: 'crop_fallback',
      );
    }

    String croppedFoodPath;
    if (maxFoodIndex != -1 && maxFoodProb >= 0.08) {
      croppedFoodPath = await cropAndSave(maxFoodIndex);
    } else {
      // Cơ chế Fallback an toàn, không để văng Exception
      croppedFoodPath = await cropCenterFallback();
    }

    String? croppedLabelPath;
    if (maxLabelIndex != -1 && maxLabelProb > 0.20) {
      croppedLabelPath = await cropAndSave(maxLabelIndex);
    }

    return {
      'foodImagePath': croppedFoodPath,
      'labelImagePath': croppedLabelPath,
    };
  }

  /// 2. CHẠY MODEL PHÂN LOẠI MÓN ĂN
  Future<String> classifyFood(String croppedImagePath) async {
    await init();

    final isolateResult = await Isolate.run(() {
      final File imageFile = File(croppedImagePath);
      final img.Image? originalImage = img.decodeImage(imageFile.readAsBytesSync());
      if (originalImage == null) return null;
  
      final int inputSize = 224;
      img.Image resizedImage = img.copyResize(originalImage, width: inputSize, height: inputSize);
  
      return List.generate(
        1,
        (i) => List.generate(
          inputSize,
          (y) => List.generate(
            inputSize,
            (x) {
              final pixel = resizedImage.getPixel(x, y);
              return [
                pixel.r.toDouble(),
                pixel.g.toDouble(),
                pixel.b.toDouble(),
              ];
            },
          ),
        ),
      );
    });

    if (isolateResult == null) throw Exception("Không thể đọc ảnh để phân loại");
    var input = isolateResult;

    var output = List.filled(1 * labels.length, 0.0).reshape([1, labels.length]);
    _classifyInterpreter!.run(input, output);

    double maxProb = -double.infinity;
    int maxIndex = 0;
    for (int i = 0; i < labels.length; i++) {
      if (output[0][i] > maxProb) {
        maxProb = output[0][i];
        maxIndex = i;
      }
    }

    return labels[maxIndex];
  }

  static final RegExp _weightKeywordRegex = RegExp(
    r'(?:khoi\s*luong(?:\s*tinh)?|trong\s*luong(?:\s*tinh)?|t[\s\.]*luong|tr[\s\.]*luong|kl(?:\s*tinh)?|tl(?:\s*tinh)?|net\s*w(?:eigh)?t)\b(?:(?:\s*\(\s*|\s+)(kg|gram|gr|g)\b\s*\)?)?[^\d\n]{0,15}?(\d+(?:[.,]\d+)?)\s*(kg|gram|gr|g|k)?',
    caseSensitive: false,
  );
  static final RegExp _weightHeaderRegex = RegExp(
    r'(?:khoi\s*luong(?:\s*tinh)?|trong\s*luong(?:\s*tinh)?|t[\s\.]*luong|tr[\s\.]*luong|\bkl\b|\btl\b|net\s*w(?:eigh)?t)(?:(?:\s*\(\s*|\s+)(kg|gram|gr|g)\b\s*\)?)?',
    caseSensitive: false,
  );
  static final RegExp _priceOrDateRowRegex = RegExp(
    r'\b(?:don\s*gia|thanh\s*tien|tong\s*tien|tien\s*hang|gia\s*ban|ngay\s*dong\s*goi|ngay\s*sx|nsx|hsd|han\s*su\s*dung)\b',
    caseSensitive: false,
  );

  /// 3. CHẠY MODEL ML KIT ĐỂ ĐỌC CHỮ VÀ BÓC TÁCH KHỐI LƯỢNG
  Future<String?> readLabelWeight(String labelImagePath) async {
    final inputImage = InputImage.fromFilePath(labelImagePath);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      final List<OcrTextLine> ocrLines = [];
      for (final TextBlock block in recognizedText.blocks) {
        for (final TextLine line in block.lines) {
          ocrLines.add(OcrTextLine(text: line.text, box: line.boundingBox));
        }
      }
      return extractWeightFromOcrLines(ocrLines);
    } catch (_) {
      return null;
    } finally {
      textRecognizer.close();
    }
  }

  /// Tách khối lượng tịnh từ danh sách dòng OCR (hỗ trợ ghép hàng theo tọa độ boundingBox
  /// cho tem chia cột và lọc ngữ cảnh tiền tệ/ngày/mã vạch an toàn).
  @visibleForTesting
  String? extractWeightFromOcrLines(List<OcrTextLine> ocrLines) {
    if (ocrLines.isEmpty) return null;

    final List<String> rows = _groupIntoVisualRows(ocrLines);
    final List<String> cleanedRows = rows
        .map((r) => _sanitizeNonWeightText(_removeDiacritics(r).toLowerCase()))
        .toList();

    // 1. Ưu tiên cao nhất: Từ khóa khối lượng (KL, TL, T.Lượng, Khối lượng, Trọng lượng) trên cùng hàng
    for (final row in cleanedRows) {
      final kwMatch = _extractByKeyword(row);
      if (kwMatch != null) return _postProcessWeightToken(kwMatch);
    }

    // 2. Trường hợp tem bị nghiêng/tách dòng: từ khóa ở hàng i, số ở hàng i+1 (đã loại giá/ngày)
    for (int i = 0; i < cleanedRows.length; i++) {
      final headerMatch = _weightHeaderRegex.firstMatch(cleanedRows[i]);
      if (headerMatch == null) continue;

      final String? headerUnit = headerMatch.group(1);
      final int end = min(cleanedRows.length, i + 3);
      for (int j = i; j < end; j++) {
        if (j > i && _priceOrDateRowRegex.hasMatch(rows[j])) continue;
        final unitMatch = _extractByUnit(cleanedRows[j], fallbackUnit: headerUnit);
        if (unitMatch != null) return _postProcessWeightToken(unitMatch);
      }
      for (int j = i; j < end; j++) {
        if (j > i && _priceOrDateRowRegex.hasMatch(rows[j])) continue;
        final numMatch = _extractBareNumber(cleanedRows[j], forcedUnit: headerUnit);
        if (numMatch != null) return _postProcessWeightToken(numMatch);
      }
    }

    // 3. Fallback toàn tem: ưu tiên chuỗi có đơn vị (g/kg), sau đó mới vét số trơn trên các hàng không phải giá/ngày
    final String joinedCleaned = cleanedRows.join(' ');
    final String? byKeywordJoined = _extractByKeyword(joinedCleaned);
    if (byKeywordJoined != null) return _postProcessWeightToken(byKeywordJoined);

    final String? byUnitJoined = _extractByUnit(joinedCleaned);
    if (byUnitJoined != null) return _postProcessWeightToken(byUnitJoined);

    for (int i = 0; i < cleanedRows.length; i++) {
      // Nếu hàng trước là tiêu đề giá/ngày đứng trơ một mình (không kèm số), bỏ qua số trơ ngay hàng kế tiếp
      if (i > 0 &&
          _priceOrDateRowRegex.hasMatch(_removeDiacritics(rows[i - 1]).toLowerCase()) &&
          !RegExp(r'\d').hasMatch(rows[i - 1]) &&
          !_weightHeaderRegex.hasMatch(cleanedRows[i])) {
        continue;
      }
      final String? byNumber = _extractBareNumber(cleanedRows[i]);
      if (byNumber != null) return _postProcessWeightToken(byNumber);
    }

    return null;
  }

  List<String> _groupIntoVisualRows(List<OcrTextLine> lines) {
    final bool hasBoxes = lines.every((l) => l.box != null);
    if (!hasBoxes) {
      return lines.map((l) => l.text.trim()).where((t) => t.isNotEmpty).toList();
    }

    final sorted = List<OcrTextLine>.from(lines)
      ..sort((a, b) {
        final dy = a.box!.center.dy.compareTo(b.box!.center.dy);
        return dy != 0 ? dy : a.box!.left.compareTo(b.box!.left);
      });

    final List<List<OcrTextLine>> rowGroups = [];
    for (final line in sorted) {
      if (line.text.trim().isEmpty) continue;
      bool placed = false;
      for (final group in rowGroups) {
        final anchor = group.first.box!;
        final box = line.box!;
        final maxH = max(anchor.height, box.height);
        final overlapX = min(anchor.right, box.right) - max(anchor.left, box.left);
        final minW = min(anchor.width, box.width);
        final isHorizontallyStacked = minW > 0 && overlapX > minW * 0.25;
        final tolerance = isHorizontallyStacked ? max(6.0, maxH * 0.45) : max(10.0, maxH * 0.85);
        if ((box.center.dy - anchor.center.dy).abs() <= tolerance) {
          group.add(line);
          placed = true;
          break;
        }
      }
      if (!placed) {
        rowGroups.add([line]);
      }
    }

    return rowGroups.map((group) {
      group.sort((a, b) => a.box!.left.compareTo(b.box!.left));
      return group.map((l) => l.text.trim()).join(' ');
    }).toList();
  }

  String _sanitizeNonWeightText(String normalizedText) {
    if (normalizedText.isEmpty) return '';
    String clean = normalizedText;
    // 1. Loại ngày tháng (dd.mm.yyyy, dd/mm/yyyy, yyyy-mm-dd...)
    clean = clean.replaceAll(RegExp(r'\b\d{1,2}[./-]\d{1,2}[./-]\d{2,4}\b'), ' ');
    clean = clean.replaceAll(RegExp(r'\b\d{4}[./-]\d{1,2}[./-]\d{1,2}\b'), ' ');
    // 2. Loại mã vạch dài / cụm mã EAN nhiều nhóm (VD: 2 110010 003088)
    clean = clean.replaceAll(RegExp(r'\b\d{1,2}\s+\d{5,}\s+\d{5,}\b'), ' ');
    clean = clean.replaceAll(RegExp(r'\b\d{6,}\b'), ' ');
    // 3. Loại đơn giá kèm đơn vị tính (VD: 25.000 d/100g, 120.000/kg)
    clean = clean.replaceAll(
      RegExp(r'(?:don\s*gia|gia)?[^\w\n]{0,5}\d+(?:[.,]\d+)?\s*(?:d|vnd|dong)?\s*/\s*(?:100\s*g|kg|g)\b'),
      ' ',
    );
    // 4. Loại số tiền và chỉ số không phải khối lượng (VD: 37.268 vnd, 150 kcal, 12%)
    clean = clean.replaceAll(RegExp(r'\b\d+(?:[.,]\d+)?\s*(?:vnd|dong|kcal|cal|calo|kj)\b'), ' ');
    clean = clean.replaceAll(RegExp(r'\b\d+(?:[.,]\d+)?\s*%'), ' ');
    // 5. Loại đúng 1 giá trị tiền/ngày đứng ngay sau từ khóa giá/thành tiền/ngày (không nuốt sang phần KL)
    clean = clean.replaceAll(
      RegExp(
        r'\b(?:don\s*gia|thanh\s*tien|tong\s*tien|tien\s*hang|gia\s*ban|ngay\s*dong\s*goi|ngay\s*sx|nsx|hsd|han\s*su\s*dung)\b[^\d\n]{0,15}(?:\d+(?:[.,]\d+)?\s*(?:vnd|dong|d\b)?\s*(?:/\s*(?:100\s*g|kg|g)\b)?)?',
      ),
      ' ',
    );
    return clean;
  }

  String? _extractByKeyword(String text) {
    for (final m in _weightKeywordRegex.allMatches(text)) {
      final numRaw = m.group(2) ?? '';
      final numStr = numRaw.replaceAll(',', '.');
      if ('.'.allMatches(numStr).length > 1) continue;
      double? val = double.tryParse(numStr);
      if (val == null) continue;

      if (!numRaw.contains('.') && !numRaw.contains(',') && numStr.length >= 4 && numStr.startsWith('0')) {
        val = val / 1000.0;
      }
      if (val >= 0.001 && val <= 50000) {
        final String? explicitUnit = m.group(3) ?? m.group(1);
        return _formatWeightToken(val, _resolveUnitToken(val, explicitUnit));
      }
    }
    return null;
  }

  String? _extractByUnit(String text, {String? fallbackUnit}) {
    final patternUnit = RegExp(r'(?<![a-zA-Z])(\d+(?:[.,]\d+)?)\s*(kg|gram|gr|g|k)(?![a-zA-Z])', caseSensitive: false);
    for (final m in patternUnit.allMatches(text)) {
      final numStr = m.group(1)!.replaceAll(',', '.');
      if ('.'.allMatches(numStr).length > 1) continue;
      final double? val = double.tryParse(numStr);
      if (val == null || val < 0.01 || val > 50000) continue;

      final rawUnit = m.group(2);
      if (rawUnit != null && rawUnit.toLowerCase() == 'k' && val >= 15) {
        // Tránh nhầm giá tiền dạng "25k" thành 25KG
        continue;
      }
      return _formatWeightToken(val, _resolveUnitToken(val, rawUnit ?? fallbackUnit));
    }
    return null;
  }

  String? _extractBareNumber(String text, {String? forcedUnit}) {
    final numbers = RegExp(r'(?<![a-zA-Z])(\d+(?:[.,]\d+)?)(?![a-zA-Z])').allMatches(text);
    for (final m in numbers) {
      final rawToken = m.group(1)!;
      final numStr = rawToken.replaceAll(',', '.');
      if ('.'.allMatches(numStr).length > 1) continue;
      double? val = double.tryParse(numStr);
      if (val == null) continue;

      if (val > 1000 && rawToken.endsWith('9') && rawToken.length <= 4) {
        val = (val - 9) / 10;
      }
      if (val > 0 && val <= 5000) {
        if (rawToken.length == 3 && rawToken.startsWith('0') && val < 100) {
          val = val / 100.0;
        }
        return _formatWeightToken(val, _resolveUnitToken(val, forcedUnit));
      }
    }
    return null;
  }

  String _postProcessWeightToken(String token) {
    return token.replaceAll(RegExp(r'9G$', caseSensitive: false), 'G');
  }

  String _formatWeightToken(double value, String unit) {
    final valStr = (value == value.toInt())
        ? value.toInt().toString()
        : value.toString().replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
    return '$valStr$unit';
  }

  String _resolveUnitToken(double value, String? rawUnit) {
    if (rawUnit == null) return (value < 15) ? 'KG' : 'G';
    final upper = rawUnit.toUpperCase();
    if (upper == 'K' || upper == 'KG') return 'KG';
    if (upper == 'GR' || upper == 'GRAM' || upper == 'G') return 'G';
    return upper;
  }
}
