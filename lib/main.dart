import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/home_screen.dart';

/// 앱 진입점.
///
/// [ProviderScope]로 전체 위젯 트리를 감싸야 Riverpod Provider를 어디서든 사용할 수 있다.
/// ProviderScope를 빠뜨리면 런타임에 ProviderNotFoundException이 발생한다.
void main() {
  runApp(const ProviderScope(child: BleApp()));
}

/// 앱 루트 위젯.
///
/// MaterialApp 설정(테마, 라우팅)을 담당하며, 앱 전체에 Material Design 3 스타일을 적용한다.
/// StatelessWidget을 사용하는 이유: 앱 루트는 상태를 직접 보유할 필요가 없고
/// 하위 Provider들이 상태를 관리하기 때문이다.
class BleApp extends StatelessWidget {
  const BleApp({super.key});

  /// [MaterialApp]을 구성하고 [HomeScreen]을 첫 화면으로 지정한다.
  ///
  /// [ColorScheme.fromSeed]: 파란색 시드로 Material 3 색상 팔레트를 자동 생성한다.
  /// [useMaterial3]: true로 설정해 최신 Material Design 3 컴포넌트 스타일을 활성화한다.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter BLE Mock',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
