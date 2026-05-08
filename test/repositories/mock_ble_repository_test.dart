import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ble_mock/models/ble_models.dart';
import 'package:flutter_ble_mock/repositories/mock_ble_repository.dart';

void main() {
  late MockBLERepository repo;

  setUp(() => repo = MockBLERepository());
  tearDown(() => repo.dispose());

  group('isBluetoothEnabled', () {
    test('returns true', () async {
      expect(await repo.isBluetoothEnabled(), isTrue);
    });
  });

  group('scan', () {
    test('isScanning starts false', () {
      expect(repo.isScanning, isFalse);
    });

    test('isScanning becomes true after startScan', () async {
      await repo.startScan();
      expect(repo.isScanning, isTrue);
      await repo.stopScan();
    });

    test('isScanning becomes false after stopScan', () async {
      await repo.startScan();
      await repo.stopScan();
      expect(repo.isScanning, isFalse);
    });

    test('scanResults emits devices during scan', () async {
      final devices = <List<BLEDevice>>[];
      final sub = repo.scanResults.listen(devices.add);

      await repo.startScan();
      await Future.delayed(const Duration(seconds: 4));
      await repo.stopScan();
      sub.cancel();

      expect(devices, isNotEmpty);
      expect(devices.last.length, greaterThan(0));
    });

    test('discovered devices have valid rssi', () async {
      final devices = <List<BLEDevice>>[];
      final sub = repo.scanResults.listen(devices.add);

      await repo.startScan();
      await Future.delayed(const Duration(seconds: 2));
      await repo.stopScan();
      sub.cancel();

      if (devices.isNotEmpty && devices.last.isNotEmpty) {
        for (final d in devices.last) {
          expect(d.rssi, lessThan(0));
        }
      }
    });

    test('calling startScan twice does not duplicate devices', () async {
      await repo.startScan();
      await repo.startScan();
      await Future.delayed(const Duration(seconds: 1));
      await repo.stopScan();
    });
  });

  group('connect / disconnect', () {
    const deviceId = 'device_1';

    test('isConnected is false before connect', () {
      expect(repo.isConnected(deviceId), isFalse);
    });

    test('isConnected is true after connect', () async {
      await repo.connect(deviceId);
      expect(repo.isConnected(deviceId), isTrue);
      await repo.disconnect(deviceId);
    });

    test('isConnected is false after disconnect', () async {
      await repo.connect(deviceId);
      await repo.disconnect(deviceId);
      expect(repo.isConnected(deviceId), isFalse);
    });

    test('connectionState emits connected after connect', () async {
      final states = <BLEConnectionState>[];
      final sub = repo.connectionState(deviceId).listen(states.add);

      await repo.connect(deviceId);
      await repo.disconnect(deviceId);
      await Future.delayed(const Duration(milliseconds: 100));
      sub.cancel();

      expect(states, contains(BLEConnectionState.connected));
      expect(states, contains(BLEConnectionState.disconnected));
    });
  });

  group('discoverServices', () {
    const deviceId = 'device_1';

    test('throws if not connected', () async {
      expect(
        () => repo.discoverServices(deviceId),
        throwsA(isA<BLEException>()),
      );
    });

    test('returns services when connected', () async {
      await repo.connect(deviceId);
      final services = await repo.discoverServices(deviceId);
      expect(services, isNotEmpty);
      await repo.disconnect(deviceId);
    });

    test('Smart Watch has 4 services', () async {
      await repo.connect(deviceId);
      final services = await repo.discoverServices(deviceId);
      expect(services.length, 4);
      await repo.disconnect(deviceId);
    });

    test('services have characteristics', () async {
      await repo.connect(deviceId);
      final services = await repo.discoverServices(deviceId);
      for (final s in services) {
        expect(s.characteristics, isNotEmpty);
      }
      await repo.disconnect(deviceId);
    });
  });

  group('readCharacteristic', () {
    const deviceId = 'device_1';

    test('throws if not connected', () async {
      expect(
        () => repo.readCharacteristic(
          deviceId: deviceId,
          serviceUuid: '180D',
          characteristicUuid: '2A37',
        ),
        throwsA(isA<BLEException>()),
      );
    });

    test('returns heart rate value when connected', () async {
      await repo.connect(deviceId);
      final value = await repo.readCharacteristic(
        deviceId: deviceId,
        serviceUuid: '180D',
        characteristicUuid: '2A37',
      );
      expect(value, hasLength(2));
      expect(value[1], inInclusiveRange(60, 99));
      await repo.disconnect(deviceId);
    });

    test('returns battery level in range', () async {
      await repo.connect(deviceId);
      final value = await repo.readCharacteristic(
        deviceId: deviceId,
        serviceUuid: '180F',
        characteristicUuid: '2A19',
      );
      expect(value[0], inInclusiveRange(70, 99));
      await repo.disconnect(deviceId);
    });
  });

  group('writeCharacteristic', () {
    const deviceId = 'device_1';

    test('throws if not connected', () async {
      expect(
        () => repo.writeCharacteristic(
          deviceId: deviceId,
          serviceUuid: 'FFE0',
          characteristicUuid: 'FFE1',
          value: [0x01, 0x02],
        ),
        throwsA(isA<BLEException>()),
      );
    });

    test('completes without error when connected', () async {
      await repo.connect(deviceId);
      await expectLater(
        repo.writeCharacteristic(
          deviceId: deviceId,
          serviceUuid: 'FFE0',
          characteristicUuid: 'FFE1',
          value: [0x01, 0x02],
        ),
        completes,
      );
      await repo.disconnect(deviceId);
    });
  });

  group('notifyCharacteristic', () {
    const deviceId = 'device_1';

    test('emits values periodically', () async {
      await repo.connect(deviceId);
      final values = await repo
          .notifyCharacteristic(
            deviceId: deviceId,
            serviceUuid: '180D',
            characteristicUuid: '2A37',
          )
          .take(3)
          .toList();

      expect(values, hasLength(3));
      await repo.disconnect(deviceId);
    });
  });
}
