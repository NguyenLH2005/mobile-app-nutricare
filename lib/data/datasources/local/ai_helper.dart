import 'dart:isolate';
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class AIHelper {
  String removeDiacritics(String str) {
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
    _cropInterpreter ??= await Interpreter.fromAsset('assets/models/yolo26_safe_int8.tflite');
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

      double x1 = xc - w / 2;
      double y1 = yc - h / 2;

      int cropX = (x1 / inputSize * origW).toInt();
      int cropY = (y1 / inputSize * origH).toInt();
      int cropW = (w / inputSize * origW).toInt();
      int cropH = (h / inputSize * origH).toInt();

      // Bảo vệ biên chống tràn và chống số âm (crash-proof clamping)
      cropX = cropX.clamp(0, origW - 1);
      cropY = cropY.clamp(0, origH - 1);
      cropW = cropW.clamp(1, origW - cropX);
      cropH = cropH.clamp(1, origH - cropY);

      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/crop_${DateTime.now().millisecondsSinceEpoch}_$index.jpg';
      
      await Isolate.run(() {
        img.Image cropped = img.copyCrop(originalImage, x: cropX, y: cropY, width: cropW, height: cropH);
        File(path).writeAsBytesSync(img.encodeJpg(cropped));
      });

      return path;
    }

    // Hàm dự phòng cắt vùng trung tâm 85% ảnh nếu góc chụp mờ hoặc không vượt ngưỡng tin cậy
    Future<String> cropCenterFallback() async {
      final int cropW = (origW * 0.85).toInt().clamp(1, origW);
      final int cropH = (origH * 0.85).toInt().clamp(1, origH);
      final int cropX = ((origW - cropW) / 2).toInt().clamp(0, origW - 1);
      final int cropY = ((origH - cropH) / 2).toInt().clamp(0, origH - 1);

      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/crop_fallback_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      await Isolate.run(() {
        img.Image cropped = img.copyCrop(originalImage, x: cropX, y: cropY, width: cropW, height: cropH);
        File(path).writeAsBytesSync(img.encodeJpg(cropped));
      });

      return path;
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

  /// 3. CHẠY MODEL ML KIT ĐỂ ĐỌC CHỮ VÀ BÓC TÁCH KHỐI LƯỢNG
  Future<String?> readLabelWeight(String labelImagePath) async {
    final inputImage = InputImage.fromFilePath(labelImagePath);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      
      List<String> lines = [];
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          lines.add(line.text);
        }
      }
      
      if (lines.isEmpty) return null;
      String fullText = lines.join(" ");
      String normalizedText = removeDiacritics(fullText).toLowerCase();
      List<String> normalizedLines = lines.map((l) => removeDiacritics(l).toLowerCase()).toList();
      
      int klIndex = -1;
      int donGiaIndex = -1;
      
      for (int i = 0; i < lines.length; i++) {
        final word = normalizedLines[i];
        if (RegExp(r'kl|khoi|trong').hasMatch(word)) {
          klIndex = i;
        }
        if (RegExp(r'don\s*gia|gi.').hasMatch(word)) {
          donGiaIndex = i;
        }
      }

      if (donGiaIndex != -1 && (klIndex == donGiaIndex || (klIndex - donGiaIndex).abs() <= 1)) {
        klIndex = -1;
      }

      String? weightCandidate;
      String context = "";

      // Logic 1: Tìm từ vị trí KL
      if (klIndex != -1) {
        int end = min(lines.length, klIndex + 5);
        context = lines.sublist(max(0, klIndex), end).join(" ");
        
        final match = RegExp(r'(\d+[\.,]?\d*)\s*(g|kg|gram)', caseSensitive: false).firstMatch(context);
        if (match != null) {
          String numStr = match.group(1)!.replaceAll(',', '.');
          try {
            double val = double.parse(numStr);
            if ('.'.allMatches(numStr).length <= 1) {
               if (!numStr.contains('.') && !numStr.contains(',') && numStr.length >= 4 && numStr.startsWith('0')) {
                   val = val / 1000;
               }
               if (val >= 0.001 && val <= 5000) {
                 String valStr = (val == val.toInt()) ? val.toInt().toString() : val.toString().replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
                 weightCandidate = '$valStr${match.group(2)!.toUpperCase()}';
               }
            }
          } catch (_) {}
        }
      }

      // Logic 2: Theo Bảng 2.5 Mục 2.4.3, các số liệu thuộc khu vực Đơn giá (VD: 25.000 d/100g)
      // là đơn vị tính giá, tuyệt đối KHÔNG lấy làm khối lượng tịnh của sản phẩm.
      // Do đó, ta loại trừ toàn bộ ngữ cảnh đơn giá khỏi tập ứng viên khối lượng.

      // Logic 3: Chạy Regex vét máng
      weightCandidate ??= _extractByRegex(normalizedText);

      // Logic 4: Fallback số đơn lẻ quanh khu vực KL
      if (weightCandidate == null && klIndex != -1) {
        final matches = RegExp(r'(\d+[\.,]?\d*)').allMatches(context);
        for (final m in matches) {
           String numStr = m.group(1)!.replaceAll(',', '.');
           try {
              double val = double.parse(numStr);
              if ('.'.allMatches(numStr).length <= 1 && val > 0 && val <= 5000) {
                 if (val > 1000 && numStr.endsWith('9') && numStr.length <= 4) {
                    val = (val - 9) / 10;
                 }
                 String dv = (val < 15) ? 'KG' : 'G';
                 String valStr = (val == val.toInt()) ? val.toInt().toString() : val.toString().replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
                 weightCandidate = '$valStr$dv';
                 break;
              }
           } catch (_) {}
        }
      }

      if (weightCandidate != null) {
          weightCandidate = weightCandidate.replaceAll(RegExp(r'9G$', caseSensitive: false), 'G');
      }

      return weightCandidate;
    } catch (_) {
      return null;
    } finally {
      textRecognizer.close();
    }
  }

  String? _extractByRegex(String vanBanTho) {
    if (vanBanTho.isEmpty) return null;

    String vanBanSach = vanBanTho.replaceAll(RegExp(r'\b\d+[.,]\d+[.,]\d+\b'), '');
    vanBanSach = vanBanSach.replaceAll(RegExp(r'\b\d{6,}\b'), '');
    // Loại trừ đơn giá kèm quy cách tính (VD: 25000d/100g hoặc /kg) theo Bảng 2.5 Mục 2.4.3
    vanBanSach = vanBanSach.replaceAll(RegExp(r'(?:don\s*gia|gia)?[^\w]{0,5}\d+[.,\d]*\s*(?:d|vnd|dong)?\s*/\s*(?:100g|kg|g)', caseSensitive: false), '');

    final patternKw = RegExp(r'(?:khoi luong|trong luong|kl|tl)\s*(?:tinh)?[^\d]{0,15}?(\d+(?:[.,]\d+)?)\s*(g|kg|gr|k)?', caseSensitive: false);
    for (final m in patternKw.allMatches(vanBanSach)) {
      try {
        double so = double.parse(m.group(1)!.replaceAll(',', '.'));
        if (so > 0 && so <= 50000) {
           String dv = (so < 15) ? 'KG' : 'G';
           if (m.groupCount >= 2 && m.group(2) != null) {
              dv = (m.group(2)!.toUpperCase() == 'K') ? 'KG' : m.group(2)!.toUpperCase();
           }
           String soStr = (so == so.toInt()) ? so.toInt().toString() : so.toString().replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
           return '$soStr$dv';
        }
      } catch (_) {}
    }

    final patternUnit = RegExp(r'(?<![a-zA-Z])(\d+(?:[.,]\d+)?)\s*(g|kg|gr|k)(?![a-zA-Z])', caseSensitive: false);
    for (final m in patternUnit.allMatches(vanBanSach)) {
      try {
        double so = double.parse(m.group(1)!.replaceAll(',', '.'));
        if (so >= 0.01 && so <= 50000) {
           String dv = (so < 15) ? 'KG' : 'G';
           if (m.groupCount >= 2 && m.group(2) != null) {
              dv = (m.group(2)!.toUpperCase() == 'K') ? 'KG' : m.group(2)!.toUpperCase();
           }
           String soStr = (so == so.toInt()) ? so.toInt().toString() : so.toString().replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
           return '$soStr$dv';
        }
      } catch (_) {}
    }

    final numbers = RegExp(r'(?<![a-zA-Z])(\d+(?:[.,]\d+)?)(?![a-zA-Z])').allMatches(vanBanSach);
    for (final m in numbers) {
      try {
        double val = double.parse(m.group(1)!.replaceAll(',', '.'));
        if (val > 1000 && m.group(1)!.endsWith('9') && m.group(1)!.length <= 4) {
           val = (val - 9) / 10;
        }

        if (val > 0 && val <= 5000) {
           if (m.group(1)!.length == 3 && m.group(1)!.startsWith('0') && val < 100) {
              val = val / 100.0;
           }
           String dv = (val < 15) ? 'KG' : 'G';
           String valStr = (val == val.toInt()) ? val.toInt().toString() : val.toString().replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
           return '$valStr$dv';
        }
      } catch (_) {}
    }

    return null;
  }
}
