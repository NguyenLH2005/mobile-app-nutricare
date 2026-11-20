import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'scan_screen.dart';
import 'daily_progress_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';
import '../state/sync_controller.dart';

class MainScreen extends ConsumerStatefulWidget {
  final int initialIndex;

  const MainScreen({super.key, this.initialIndex = 0});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  late int _currentIndex;

  // Danh sách 4 màn hình chính tương ứng với 4 Tab
  final List<Widget> _screens = const [
    ScanScreen(),
    DailyProgressScreen(),
    HistoryScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  Widget _buildTabIcon(IconData icon, {bool locked = false}) {
    if (!locked) return Icon(icon);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        Positioned(
          right: -6,
          top: -4,
          child: Container(
            padding: const EdgeInsets.all(1.5),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lock, size: 11, color: Colors.orange.shade700),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isLocked = !ref.watch(syncProvider).isLoggedIn;

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Tra cứu',
          ),
          BottomNavigationBarItem(
            icon: _buildTabIcon(Icons.pie_chart_outline, locked: isLocked),
            label: 'Tiến trình',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Lịch sử',
          ),
          BottomNavigationBarItem(
            icon: _buildTabIcon(Icons.person, locked: isLocked),
            label: 'Hồ sơ',
          ),
        ],
      ),
    );
  }
}
