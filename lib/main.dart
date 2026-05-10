import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/bt_home_screen.dart';
import 'screens/home_screen.dart';

/// 앱 진입점.
///
/// [ProviderScope]로 전체 위젯 트리를 감싸야 Riverpod Provider를 어디서든 사용할 수 있다.
void main() {
  runApp(const ProviderScope(child: BleApp()));
}

/// 앱 루트 위젯.
///
/// [MaterialApp] 설정과 테마를 담당하며, 홈 화면으로 [MainScreen]을 지정한다.
class BleApp extends StatelessWidget {
  const BleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter BT Mock',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

/// BLE와 Classic BT 두 탭을 전환하는 메인 화면.
///
/// [BottomNavigationBar]로 탭을 전환하며,
/// [IndexedStack]으로 각 탭의 상태(스캔 결과, 연결 상태 등)를 유지한다.
///
/// IndexedStack을 사용하는 이유:
/// 일반 if/else로 탭을 교체하면 탭 전환 시 위젯이 재생성되어 상태가 초기화된다.
/// IndexedStack은 모든 탭을 메모리에 유지하고 보이기/숨기기만 전환한다.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  /// 현재 선택된 탭 인덱스. 0 = BLE, 1 = Classic BT
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack: 모든 탭을 동시에 메모리에 유지하고 선택된 것만 화면에 표시한다.
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          HomeScreen(),   // 탭 0: BLE 스캐너
          BTHomeScreen(), // 탭 1: Classic BT 스캐너
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.bluetooth),
            label: 'BLE',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bluetooth_audio),
            label: 'Classic BT',
          ),
        ],
      ),
    );
  }
}
