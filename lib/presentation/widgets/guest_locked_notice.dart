import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/sync_controller.dart';

/// Thẻ thông báo tính năng bị khóa khi dùng chế độ không đăng nhập và nút đăng nhập Google tại chỗ.
class GuestLockedNotice extends ConsumerWidget {
  final String title;
  final String description;
  final List<String> lockedItems;
  final bool compact;
  final Future<void> Function()? onSignedIn;

  const GuestLockedNotice({
    super.key,
    required this.title,
    required this.description,
    this.lockedItems = const [],
    this.compact = false,
    this.onSignedIn,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncProvider);
    final hasErrorMessage = syncState.syncMessage != null &&
        syncState.syncMessage!.isNotEmpty &&
        (syncState.syncMessage!.contains('Lỗi') ||
            syncState.syncMessage!.contains('thất bại') ||
            syncState.syncMessage!.contains('từ chối'));

    final card = Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 18 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 48 : 64,
            height: compact ? 48 : 64,
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.lock_outline_rounded,
              size: compact ? 26 : 34,
              color: Colors.green.shade700,
            ),
          ),
          SizedBox(height: compact ? 12 : 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 15.5 : 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1B233A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 13 : 13.5,
              color: Colors.grey.shade700,
              height: 1.45,
            ),
          ),
          if (lockedItems.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: lockedItems
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_circle_outline, size: 16, color: Colors.green.shade600),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item,
                                style: const TextStyle(fontSize: 12.5, color: Color(0xFF1B233A), height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          if (hasErrorMessage) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                syncState.syncMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Colors.red.shade800),
              ),
            ),
          ],
          SizedBox(height: compact ? 14 : 18),
          SizedBox(
            width: double.infinity,
            height: compact ? 44 : 48,
            child: ElevatedButton.icon(
              onPressed: syncState.isSyncing
                  ? null
                  : () async {
                      final ok = await ref.read(syncProvider.notifier).signInWithGoogle();
                      if (ok && onSignedIn != null) {
                        await onSignedIn!();
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: syncState.isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.login_rounded, size: 20),
              label: Text(
                syncState.isSyncing ? 'Đang đăng nhập...' : 'Đăng nhập với Google',
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );

    if (compact) return card;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: card,
      ),
    );
  }
}
