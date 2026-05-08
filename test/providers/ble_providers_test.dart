import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ble_mock/models/ble_models.dart';
import 'package:flutter_ble_mock/providers/ble_providers.dart';
import 'package:flutter_ble_mock/repositories/mock_ble_repository.dart';

ProviderContainer makeContainer() {
  final container = ProviderContainer(
    overrides: [
      bleRepositoryProvider.overrideWithValue(MockBLERepository()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('isBluetoothEnabledProvider', () {
    test('returns true', () async {
      final container = makeContainer();
      final result = await container.read(isBluetoothEnabledProvider.future);
      expect(result, isTrue);
    });
  });

  group('bleIsScanningProvider', () {
    test('starts as false', () {
      final container = makeContainer();
      expect(container.read(bleIsScanningProvider), isFalse);
    });
  });

  group('discoveredDevicesProvider', () {
    test('starts empty', () {
      final container = makeContainer();
      expect(container.read(discoveredDevicesProvider), isEmpty);
    });
  });

  group('connectedDevicesProvider', () {
    test('starts empty', () {
      final container = makeContainer();
      expect(container.read(connectedDevicesProvider), isEmpty);
    });
  });

  group('bleScanNotifier', () {
    test('startScan sets isScanning to true', () async {
      final container = makeContainer();
      await container.read(bleScanNotifierProvider.notifier).startScan();
      expect(container.read(bleIsScanningProvider), isTrue);
      await container.read(bleScanNotifierProvider.notifier).stopScan();
    });

    test('stopScan sets isScanning to false', () async {
      final container = makeContainer();
      await container.read(bleScanNotifierProvider.notifier).startScan();
      await container.read(bleScanNotifierProvider.notifier).stopScan();
      expect(container.read(bleIsScanningProvider), isFalse);
    });

    test('devices are populated after scan', () async {
      final container = makeContainer();
      await container.read(bleScanNotifierProvider.notifier).startScan();
      await Future.delayed(const Duration(seconds: 3));

      final devices = container.read(discoveredDevicesProvider);
      expect(devices, isNotEmpty);
      await container.read(bleScanNotifierProvider.notifier).stopScan();
    });
  });

  group('bleConnectionNotifier', () {
    test('connect adds device to connectedDevices', () async {
      final container = makeContainer();
      await container
          .read(bleConnectionNotifierProvider.notifier)
          .connect('device_1');

      expect(container.read(connectedDevicesProvider), contains('device_1'));
      await container
          .read(bleConnectionNotifierProvider.notifier)
          .disconnect('device_1');
    });

    test('disconnect removes device from connectedDevices', () async {
      final container = makeContainer();
      await container
          .read(bleConnectionNotifierProvider.notifier)
          .connect('device_1');
      await container
          .read(bleConnectionNotifierProvider.notifier)
          .disconnect('device_1');

      expect(
        container.read(connectedDevicesProvider),
        isNot(contains('device_1')),
      );
    });

    test('multiple devices can be connected', () async {
      final container = makeContainer();
      await container
          .read(bleConnectionNotifierProvider.notifier)
          .connect('device_1');
      await container
          .read(bleConnectionNotifierProvider.notifier)
          .connect('device_2');

      final connected = container.read(connectedDevicesProvider);
      expect(connected, containsAll(['device_1', 'device_2']));

      await container
          .read(bleConnectionNotifierProvider.notifier)
          .disconnect('device_1');
      await container
          .read(bleConnectionNotifierProvider.notifier)
          .disconnect('device_2');
    });
  });

  group('bleServicesProvider', () {
    test('returns services for connected device', () async {
      final container = makeContainer();
      await container
          .read(bleConnectionNotifierProvider.notifier)
          .connect('device_1');

      final services =
          await container.read(bleServicesProvider('device_1').future);
      expect(services, isNotEmpty);

      await container
          .read(bleConnectionNotifierProvider.notifier)
          .disconnect('device_1');
    });
  });

  group('bleConnectionStateProvider', () {
    test('emits connected state after connect', () async {
      final container = makeContainer();
      final states = <BLEConnectionState>[];

      container.listen(
        bleConnectionStateProvider('device_1'),
        (_, next) => next.whenData(states.add),
      );

      await container
          .read(bleConnectionNotifierProvider.notifier)
          .connect('device_1');
      await container
          .read(bleConnectionNotifierProvider.notifier)
          .disconnect('device_1');

      expect(states, contains(BLEConnectionState.connected));
    });
  });
}
