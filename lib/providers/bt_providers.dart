import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bt_models.dart';
import '../repositories/bt_repository.dart';
import '../repositories/mock_bt_repository.dart';

/// 앱 전체에서 사용하는 [BTRepository] 싱글턴 인스턴스를 제공하는 Provider.
///
/// 실제 기기 연동 시 `MockBTRepository()` 를
/// `FlutterBluetoothSerialRepository()` 로 교체하면 된다.
final btRepositoryProvider = Provider<BTRepository>((ref) {
  final repo = MockBTRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Classic BT용 블루투스 활성화 여부 Provider.
///
/// BLE의 [isBluetoothEnabledProvider]와 동일하게 동작하지만
/// [btRepositoryProvider]를 사용하므로 별도로 분리했다.
final btIsBluetoothEnabledProvider = FutureProvider<bool>((ref) {
  return ref.watch(btRepositoryProvider).isBluetoothEnabled();
});

/// 현재 Classic BT 탐색(Inquiry) 진행 여부
final btIsDiscoveringProvider = StateProvider<bool>((ref) => false);

/// 탐색 중 발견된 Classic BT 장치 목록
final discoveredBTDevicesProvider = StateProvider<List<BTDevice>>((ref) => []);

/// 스마트폰에 페어링된 장치 목록.
///
/// [FutureProvider]로 앱 시작 시 한 번 로드하며,
/// 페어링/페어링 해제 후에는 [ref.invalidate]로 갱신할 수 있다.
final pairedBTDevicesProvider = FutureProvider<List<BTDevice>>((ref) {
  return ref.watch(btRepositoryProvider).getPairedDevices();
});

/// 현재 SPP 연결된 장치 MAC 주소 집합
final connectedBTDevicesProvider = StateProvider<Set<String>>((ref) => {});

// ─── 탐색 Notifier ────────────────────────────────────────────────────────────

/// Classic BT 탐색 시작/중지를 제어하는 StateNotifier.
///
/// BLE의 [BleScanNotifier]와 동일한 패턴이지만
/// 탐색이 완료돼도 장치를 지우지 않는 점이 다르다(OS가 캐시 유지).
class BTDiscoveryNotifier extends StateNotifier<AsyncValue<void>> {
  BTDiscoveryNotifier(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;

  /// Classic BT 탐색을 시작한다.
  ///
  /// [BTRepository.discoveryResults] 스트림을 구독해
  /// 장치 발견 시마다 [discoveredBTDevicesProvider]를 갱신한다.
  Future<void> startDiscovery() async {
    state = const AsyncValue.loading();
    try {
      final repo = _ref.read(btRepositoryProvider);
      _ref.read(discoveredBTDevicesProvider.notifier).state = [];
      _ref.read(btIsDiscoveringProvider.notifier).state = true;

      repo.discoveryResults.listen((devices) {
        _ref.read(discoveredBTDevicesProvider.notifier).state = devices;
      });

      await repo.startDiscovery();
      state = const AsyncValue.data(null);
    } catch (e, st) {
      _ref.read(btIsDiscoveringProvider.notifier).state = false;
      state = AsyncValue.error(e, st);
    }
  }

  /// 진행 중인 탐색을 중단한다.
  Future<void> stopDiscovery() async {
    await _ref.read(btRepositoryProvider).stopDiscovery();
    _ref.read(btIsDiscoveringProvider.notifier).state = false;
    state = const AsyncValue.data(null);
  }
}

final btDiscoveryNotifierProvider =
    StateNotifierProvider<BTDiscoveryNotifier, AsyncValue<void>>(
  (ref) => BTDiscoveryNotifier(ref),
);

// ─── 페어링 Notifier ──────────────────────────────────────────────────────────

/// Classic BT 페어링/페어링 해제를 제어하는 StateNotifier.
///
/// BLE에는 없는 개념으로, Classic BT 전용이다.
/// pair/unpair 완료 후 [pairedBTDevicesProvider]를 무효화해 목록을 새로 로드한다.
class BTPairingNotifier extends StateNotifier<AsyncValue<void>> {
  BTPairingNotifier(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;

  /// 지정된 장치와 페어링을 시도한다.
  ///
  /// 완료 후 [pairedBTDevicesProvider]를 갱신해
  /// 페어링된 장치 목록이 자동으로 업데이트되도록 한다.
  Future<void> pair(String address) async {
    state = const AsyncValue.loading();
    try {
      await _ref.read(btRepositoryProvider).pair(address);
      // pairedBTDevicesProvider를 무효화해 다음 접근 시 재로드되도록 한다.
      _ref.invalidate(pairedBTDevicesProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 지정된 장치의 페어링을 해제한다.
  Future<void> unpair(String address) async {
    state = const AsyncValue.loading();
    try {
      await _ref.read(btRepositoryProvider).unpair(address);
      _ref.invalidate(pairedBTDevicesProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final btPairingNotifierProvider =
    StateNotifierProvider<BTPairingNotifier, AsyncValue<void>>(
  (ref) => BTPairingNotifier(ref),
);

// ─── 연결 Notifier ────────────────────────────────────────────────────────────

/// Classic BT SPP 연결/해제를 제어하는 StateNotifier.
class BTConnectionNotifier extends StateNotifier<AsyncValue<void>> {
  BTConnectionNotifier(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;

  /// 페어링된 장치에 SPP 소켓 연결을 시도한다.
  ///
  /// 성공 시 [connectedBTDevicesProvider]에 address를 추가한다.
  Future<void> connect(String address) async {
    state = const AsyncValue.loading();
    try {
      await _ref.read(btRepositoryProvider).connect(address);
      final connected = {..._ref.read(connectedBTDevicesProvider)}
        ..add(address);
      _ref.read(connectedBTDevicesProvider.notifier).state = connected;
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// SPP 소켓 연결을 해제한다.
  ///
  /// 완료 시 [connectedBTDevicesProvider]에서 address를 제거한다.
  Future<void> disconnect(String address) async {
    state = const AsyncValue.loading();
    try {
      await _ref.read(btRepositoryProvider).disconnect(address);
      final connected = {..._ref.read(connectedBTDevicesProvider)}
        ..remove(address);
      _ref.read(connectedBTDevicesProvider.notifier).state = connected;
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final btConnectionNotifierProvider =
    StateNotifierProvider<BTConnectionNotifier, AsyncValue<void>>(
  (ref) => BTConnectionNotifier(ref),
);

// ─── 스트림 Providers ─────────────────────────────────────────────────────────

/// 특정 장치의 연결 상태 변화를 실시간으로 제공하는 Provider.
///
/// 사용 예: `ref.watch(btConnectionStateProvider('00:11:22:33:44:55'))`
final btConnectionStateProvider =
    StreamProvider.family<BTConnectionState, String>((ref, address) {
  return ref.watch(btRepositoryProvider).connectionState(address);
});

/// 특정 장치의 페어링 상태 변화를 실시간으로 제공하는 Provider.
///
/// 사용 예: `ref.watch(btPairStateProvider('00:11:22:33:44:55'))`
final btPairStateProvider =
    StreamProvider.family<BTPairState, String>((ref, address) {
  return ref.watch(btRepositoryProvider).pairState(address);
});

/// 특정 장치에서 수신되는 SPP 메시지 스트림을 제공하는 Provider.
///
/// 장치가 데이터를 보낼 때마다 새 [BTMessage]가 방출된다.
/// 사용 예: `ref.watch(btReceiveDataProvider('00:11:22:33:44:55'))`
final btReceiveDataProvider =
    StreamProvider.family<BTMessage, String>((ref, address) {
  return ref.watch(btRepositoryProvider).receiveData(address);
});

/// 특정 장치와의 SPP 메시지 히스토리를 보관하는 Provider.
///
/// 스트림은 최신 값만 방출하므로, 이 Provider가 메시지를 누적 보관한다.
/// 연결이 끊기면 초기화되지 않으며, 다음 연결에도 이전 대화가 유지된다.
final btMessageHistoryProvider =
    StateProvider.family<List<BTMessage>, String>((ref, address) => []);
