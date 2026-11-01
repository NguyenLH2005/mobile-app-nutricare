import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/image_compress_helper.dart';
import '../../data/datasources/remote/api_service.dart';
import '../../data/datasources/local/database_helper.dart';
import '../../data/models/user_profile_model.dart';
import '../../data/models/scan_history_model.dart';
import 'scan_controller.dart';
import 'profile_controller.dart';

class AuthUserState {
  final bool isInitialized;
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final String? avatarUrl;
  final bool isSyncing;
  final String? syncMessage;

  AuthUserState({
    this.isInitialized = false,
    this.isLoggedIn = false,
    this.email,
    this.name,
    this.avatarUrl,
    this.isSyncing = false,
    this.syncMessage,
  });

  AuthUserState copyWith({
    bool? isInitialized,
    bool? isLoggedIn,
    String? email,
    String? name,
    String? avatarUrl,
    bool? isSyncing,
    String? syncMessage,
  }) {
    return AuthUserState(
      isInitialized: isInitialized ?? this.isInitialized,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      email: email ?? this.email,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isSyncing: isSyncing ?? this.isSyncing,
      syncMessage: syncMessage ?? this.syncMessage,
    );
  }
}

class SyncController extends Notifier<AuthUserState> {
  // Web Client ID lấy từ Google Cloud Console (Client ID for Web application)
  static const String googleClientId = '601892342101-l6hu54kc9g71rnkjaevar6fauum54lg3.apps.googleusercontent.com';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: googleClientId,
    scopes: ['email', 'profile'],
  );

  @override
  AuthUserState build() {
    _loadSavedUser();
    return AuthUserState();
  }

  Future<void> _loadSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_access_token');
    final userJson = prefs.getString('cached_user_profile');
    if (token != null && userJson != null) {
      try {
        final Map<String, dynamic> userMap = jsonDecode(userJson);
        state = state.copyWith(
          isInitialized: true,
          isLoggedIn: true,
          email: userMap['email'],
          name: userMap['name'],
          avatarUrl: userMap['avatarUrl'],
        );
        // Tự động kiểm tra và đồng bộ ngầm khi mở app
        syncNow();
        return;
      } catch (_) {}
    }

    // Nếu chưa có token cục bộ, thử đăng nhập ngầm qua Google (Silent Sign-in)
    try {
      final account = await _googleSignIn.signInSilently();
      if (account != null) {
        final auth = await account.authentication;
        if (auth.idToken != null) {
          final user = await ApiService.instance.loginWithGoogle(auth.idToken!);
          if (user != null) {
            await prefs.setString('cached_user_profile', jsonEncode(user));
            state = state.copyWith(
              isInitialized: true,
              isLoggedIn: true,
              email: user['email'],
              name: user['name'],
              avatarUrl: user['avatarUrl'],
            );
            syncNow();
            return;
          }
        }
      }
    } catch (_) {}

    state = state.copyWith(isInitialized: true, isLoggedIn: false);
  }

  // Đăng nhập bằng Google
  Future<bool> signInWithGoogle() async {
    state = state.copyWith(isSyncing: true, syncMessage: 'Đang kết nối tài khoản Google...');
    try {
      // Đảm bảo dọn dẹp phiên cũ tránh bị treo phiên trước
      try {
        await _googleSignIn.signOut();
      } catch (_) {}

      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) {
        state = state.copyWith(isSyncing: false, syncMessage: null);
        return false; // Người dùng hủy
      }

      final GoogleSignInAuthentication auth = await account.authentication;
      final String? idToken = auth.idToken;

      if (idToken == null) {
        state = state.copyWith(isSyncing: false, syncMessage: 'Không lấy được xác thực Google.');
        return false;
      }

      state = state.copyWith(syncMessage: 'Đang xác thực với máy chủ NutriCare...');
      final user = await ApiService.instance.loginWithGoogle(idToken);
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_user_profile', jsonEncode(user));

        state = state.copyWith(
          isInitialized: true,
          isLoggedIn: true,
          email: user['email'],
          name: user['name'],
          avatarUrl: user['avatarUrl'],
          isSyncing: false,
          syncMessage: 'Đăng nhập thành công!',
        );

        // Đăng nhập thành công -> Tự động khôi phục dữ liệu từ Cloud về máy
        await restoreFromCloud();
        return true;
      } else {
        state = state.copyWith(isSyncing: false, syncMessage: 'Máy chủ từ chối xác thực.');
        return false;
      }
    } catch (e) {
      String msg = 'Lỗi đăng nhập: $e';
      if (e.toString().contains('ApiException: 10') || e.toString().contains('10')) {
        msg = 'Lỗi ApiException 10: Cần thêm SHA-1 và Package name (com.example.nckh_app) trên Google Cloud Console.';
      }
      state = state.copyWith(isSyncing: false, syncMessage: msg);
      return false;
    }
  }

  // Kiểm tra xem có dữ liệu chưa sync trên local hay không
  Future<bool> hasUnsyncedData() async {
    return await DatabaseHelper.instance.hasUnsyncedData();
  }

  // Đăng xuất: Xóa sạch dữ liệu SQLite trên máy theo yêu cầu người dùng
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await ApiService.instance.clearAuthToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_user_profile');
    await prefs.remove('jwt_access_token');

    // Xóa sạch CSDL SQLite trên máy
    await DatabaseHelper.instance.clearAllLocalData();
    ref.invalidate(historyProvider);
    ref.read(profileProvider.notifier).loadProfile();

    state = AuthUserState(
      isInitialized: true,
      isLoggedIn: false,
      syncMessage: null,
    );
  }

  // Đồng bộ sao lưu (Backup)
  Future<void> syncNow() async {
    if (!state.isLoggedIn) return;

    final isOnline = await ApiService.instance.isNetworkConnected();
    if (!isOnline) {
      state = state.copyWith(syncMessage: 'Ngoại tuyến: Dữ liệu đã lưu nội bộ.');
      return;
    }

    state = state.copyWith(isSyncing: true, syncMessage: 'Đang sao lưu dữ liệu lên đám mây...');
    try {
      // 1. Lấy User Profile
      final profile = await DatabaseHelper.instance.getUserProfile();
      final Map<String, dynamic>? profileMap = profile?.toCloudMap();

      // 2. Lấy các món ăn chưa sync
      final unsyncedScans = await DatabaseHelper.instance.getUnsyncedScans();
      List<Map<String, dynamic>> scansList = [];
      for (var s in unsyncedScans) {
        String? origBase64 = s.originalImageBase64;
        String? foodBase64 = s.foodImageBase64;
        String? labelBase64 = s.labelImageBase64;

        bool needUpdateLocal = false;
        if (origBase64 == null && s.originalImage.isNotEmpty) {
          origBase64 = await ImageCompressHelper.compressAndEncodeBase64(s.originalImage);
          needUpdateLocal = true;
        }
        if (foodBase64 == null && s.croppedFoodImage.isNotEmpty) {
          foodBase64 = await ImageCompressHelper.compressAndEncodeBase64(s.croppedFoodImage);
          needUpdateLocal = true;
        }
        if (labelBase64 == null && s.croppedLabelImage != null && s.croppedLabelImage!.isNotEmpty) {
          labelBase64 = await ImageCompressHelper.compressAndEncodeBase64(s.croppedLabelImage);
          needUpdateLocal = true;
        }

        if (needUpdateLocal) {
          await DatabaseHelper.instance.updateScan(s.copyWith(
            originalImageBase64: origBase64,
            foodImageBase64: foodBase64,
            labelImageBase64: labelBase64,
          ));
        }

        scansList.add({
          'localId': s.id,
          'foodName': s.foodName,
          'weight': s.weight,
          'servingUnits': s.servingUnits,
          'consumptionRatio': s.consumptionRatio,
          'logDate': s.logDate,
          'nutritionData': s.decodedNutrition,
          'mainGroup': s.mainGroup,
          'originalImageBase64': origBase64,
          'foodImageBase64': foodBase64,
          'labelImageBase64': labelBase64,
          'aiSuggestion': s.aiSuggestion,
          'createdAt': s.createdAt.toIso8601String(),
        });
      }

      if (profileMap == null && scansList.isEmpty) {
        state = state.copyWith(isSyncing: false, syncMessage: 'Dữ liệu đã được đồng bộ mới nhất.');
        return;
      }

      final result = await ApiService.instance.backupData(
        profile: profileMap,
        scans: scansList.isNotEmpty ? scansList : null,
      );

      if (result['success'] == true) {
        if (profileMap != null) {
          await DatabaseHelper.instance.markProfileAsSynced();
        }
        if (unsyncedScans.isNotEmpty) {
          final ids = unsyncedScans.map((e) => e.id!).toList();
          await DatabaseHelper.instance.markScansAsSynced(ids);
        }
        state = state.copyWith(isSyncing: false, syncMessage: 'Đồng bộ đám mây thành công!');
      } else {
        state = state.copyWith(
          isSyncing: false,
          syncMessage: result['message'] ?? 'Đồng bộ thất bại, sẽ thử lại sau.',
        );
      }
    } catch (e) {
      state = state.copyWith(isSyncing: false, syncMessage: 'Lỗi đồng bộ: $e');
    }
  }

  // Khôi phục dữ liệu từ Cloud (Restore)
  Future<bool> restoreFromCloud() async {
    if (!state.isLoggedIn) return false;

    final isOnline = await ApiService.instance.isNetworkConnected();
    if (!isOnline) {
      state = state.copyWith(syncMessage: 'Ngoại tuyến: Không thể tải từ đám mây.');
      return false;
    }

    state = state.copyWith(isSyncing: true, syncMessage: 'Đang tải dữ liệu từ đám mây...');
    try {
      final data = await ApiService.instance.restoreData();
      if (data != null) {
        // 1. Phục hồi hồ sơ nếu có
        if (data['profile'] != null) {
          final profile = UserProfile.fromMap(
            Map<String, dynamic>.from(data['profile']),
            forceIsSynced: 1,
          );
          await DatabaseHelper.instance.saveUserProfile(profile);
          ref.read(profileProvider.notifier).loadProfile();
        }

        // 2. Phục hồi lịch sử quét nếu có
        if (data['scans'] != null && data['scans'] is List) {
          final scansList = data['scans'] as List;
          final existingScans = await DatabaseHelper.instance.getAllScans();
          final existingTimestamps = existingScans.map((e) => e.createdAt.toIso8601String()).toSet();

          for (var s in scansList) {
            final createdAtStr = s['created_at']?.toString();
            final createdAt = createdAtStr != null 
                ? DateTime.tryParse(createdAtStr) ?? DateTime.now() 
                : DateTime.now();

            if (createdAtStr != null && existingTimestamps.contains(createdAt.toIso8601String())) {
              continue; // Tránh trùng lặp nếu đã có món ăn này
            }

            final originalB64 = s['original_image_base64']?.toString() ?? s['originalImageBase64']?.toString();
            final foodB64 = s['food_image_base64']?.toString() ?? s['foodImageBase64']?.toString();
            final labelB64 = s['label_image_base64']?.toString() ?? s['labelImageBase64']?.toString();

            String localFoodPath = '';
            String localOrigPath = '';
            String? localLabelPath;

            try {
              final docDir = await getApplicationDocumentsDirectory();
              final restoreDir = Directory('${docDir.path}/restored_scans');
              if (!await restoreDir.exists()) {
                await restoreDir.create(recursive: true);
              }

              final timestamp = createdAt.millisecondsSinceEpoch;
              if (foodB64 != null && foodB64.isNotEmpty) {
                final saved = await ImageCompressHelper.saveBase64ToFile(foodB64, '${restoreDir.path}/food_$timestamp.jpg');
                if (saved != null) localFoodPath = saved;
              }
              if (originalB64 != null && originalB64.isNotEmpty) {
                final saved = await ImageCompressHelper.saveBase64ToFile(originalB64, '${restoreDir.path}/orig_$timestamp.jpg');
                if (saved != null) localOrigPath = saved;
              }
              if (labelB64 != null && labelB64.isNotEmpty) {
                final saved = await ImageCompressHelper.saveBase64ToFile(labelB64, '${restoreDir.path}/label_$timestamp.jpg');
                if (saved != null) localLabelPath = saved;
              }
            } catch (err) {
              debugPrint('Lỗi ghi file phục hồi: $err');
            }

            final scan = ScanHistory(
              originalImage: localOrigPath,
              croppedFoodImage: localFoodPath,
              croppedLabelImage: localLabelPath,
              originalImageBase64: originalB64,
              foodImageBase64: foodB64,
              labelImageBase64: labelB64,
              aiSuggestion: s['ai_suggestion'] ?? s['aiSuggestion'],
              foodName: s['food_name'] ?? s['foodName'] ?? 'Món ăn',
              weight: _parseNullableNum(s['weight']),
              servingUnits: _parseNullableNum(s['serving_units'] ?? s['servingUnits']),
              consumptionRatio: _parseNullableNum(s['consumption_ratio'] ?? s['consumptionRatio']) ?? 1.0,
              logDate: s['log_date'] ?? s['logDate'],
              nutritionData: s['nutrition_data'] is String 
                  ? s['nutrition_data'] 
                  : jsonEncode(s['nutrition_data'] ?? []),
              mainGroup: s['main_group'] ?? s['mainGroup'] ?? 'Khác',
              createdAt: createdAt,
              isSynced: 1,
              updatedAt: DateTime.now(),
            );
            await DatabaseHelper.instance.insertScan(scan);
          }
          ref.invalidate(historyProvider);
        }

        state = state.copyWith(isSyncing: false, syncMessage: 'Khôi phục đám mây thành công!');
        return true;
      }
    } catch (e) {
      state = state.copyWith(isSyncing: false, syncMessage: 'Lỗi khôi phục: $e');
    }
    state = state.copyWith(isSyncing: false);
    return false;
  }

  double? _parseNullableNum(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString());
  }
}

final syncProvider = NotifierProvider<SyncController, AuthUserState>(() {
  return SyncController();
});
