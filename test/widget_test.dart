import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_ble_mock/main.dart';

void main() {
  testWidgets('App renders BLE Scanner title', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: BleApp()));
    await tester.pumpAndSettle();
    expect(find.text('BLE Device Scanner'), findsOneWidget);
  });

  testWidgets('Start Scan button is visible', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: BleApp()));
    await tester.pumpAndSettle();
    expect(find.text('Start Scan'), findsOneWidget);
  });
}
