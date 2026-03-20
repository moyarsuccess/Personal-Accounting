import 'package:flutter/material.dart';
import 'package:personal_accounting/screens/costs_tab.dart';
import 'package:personal_accounting/screens/overview_tab.dart';
import 'package:personal_accounting/widgets/import_qfx_button.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _tabs = const [
    CostsTab(),
    OverviewTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: _tabs,
          ),
          if (_currentIndex == 0)
            const Positioned(
              right: 16,
              bottom: 16,
              child: ImportQfxButton(),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: 'Costs',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.pie_chart_outline),
            label: 'Overview',
          ),
        ],
      ),
    );
  }
}
