import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../dashboard/dashboard_screen.dart';
import '../more/more_screen.dart';
import '../sales/sales_screen.dart';
import '../time/time_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final _dashboardKey = GlobalKey<DashboardScreenState>();
  final _timeKey = GlobalKey<TimeScreenState>();
  final _salesKey = GlobalKey<SalesScreenState>();

  late final List<Widget> _screens = [
    DashboardScreen(key: _dashboardKey),
    TimeScreen(key: _timeKey),
    SalesScreen(key: _salesKey),
    const MoreScreen(),
  ];

  void _onSelect(int i) {
    setState(() => _index = i);
    switch (i) {
      case 0:
        _dashboardKey.currentState?.refresh();
      case 1:
        _timeKey.currentState?.refresh();
      case 2:
        _salesKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onSelect,
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primaryContainer,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: AppColors.primary),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: Icon(Icons.schedule_outlined),
            selectedIcon: Icon(Icons.schedule, color: AppColors.primary),
            label: 'الوقت',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_mall_outlined),
            selectedIcon: Icon(Icons.local_mall, color: AppColors.primary),
            label: 'المبيعات',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_outlined),
            selectedIcon: Icon(Icons.more_horiz, color: AppColors.primary),
            label: 'المزيد',
          ),
        ],
      ),
    );
  }
}
