import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ble_models.dart';
import '../providers/ble_providers.dart';
import 'device_detail_screen.dart';

/// BLE 장치 스캔 메인 화면.
///
/// 블루투스 스캔 시작/중지, 발견된 장치 목록 표시,
/// 장치 상세 화면 이동 진입점 역할을 담당한다.
/// ConsumerWidget을 상속해 Riverpod Provider 구독이 가능하다.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// 화면 전체 레이아웃을 구성한다.
  ///
  /// - [bleIsScanningProvider]: 현재 스캔 중인지 여부를 구독
  /// - [discoveredDevicesProvider]: 발견된 BLE 장치 목록을 구독
  /// - [isBluetoothEnabledProvider]: 블루투스 활성화 상태를 구독 (FutureProvider)
  ///
  /// Provider 값이 바뀔 때마다 build가 재호출되어 UI가 자동으로 갱신된다.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isScanning = ref.watch(bleIsScanningProvider);
    final devices = ref.watch(discoveredDevicesProvider);
    final bleEnabled = ref.watch(isBluetoothEnabledProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Device Scanner'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // bleEnabled는 FutureProvider이므로 .when()으로 로딩/성공/오류 분기 처리한다.
          // 블루투스가 켜져 있으면 파란 아이콘, 꺼져 있으면 회색 비활성 아이콘을 표시한다.
          bleEnabled.when(
            data: (enabled) => Icon(
              enabled ? Icons.bluetooth : Icons.bluetooth_disabled,
              color: enabled ? Colors.blue : Colors.grey,
            ),
            loading: () => const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (_, __) => const Icon(Icons.bluetooth_disabled),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // 화면 상단 고정 상태 바: 스캔 진행 여부와 발견 장치 수를 표시한다.
          _StatusBar(isScanning: isScanning, deviceCount: devices.length),
          Expanded(
            // 장치가 없으면 안내 메시지(_EmptyState), 있으면 목록(_DeviceList)을 표시한다.
            child: devices.isEmpty
                ? _EmptyState(isScanning: isScanning)
                : _DeviceList(devices: devices),
          ),
        ],
      ),
      // 우측 하단 스캔 토글 버튼: 스캔 중이면 빨간 Stop, 대기 중이면 기본색 Start로 표시한다.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _toggleScan(ref, isScanning),
        icon: Icon(isScanning ? Icons.stop : Icons.search),
        label: Text(isScanning ? 'Stop Scan' : 'Start Scan'),
        backgroundColor: isScanning ? Colors.red : null,
      ),
    );
  }

  /// 스캔 상태를 토글한다.
  ///
  /// [isScanning]이 true면 [bleScanNotifierProvider]의 stopScan()을 호출해 스캔을 중단하고,
  /// false면 startScan()을 호출해 주변 BLE 장치 탐색을 시작한다.
  /// ref.read()를 사용하는 이유: 버튼 클릭 시 일회성 액션이므로
  /// 상태 변화를 지속적으로 구독(watch)할 필요가 없기 때문이다.
  void _toggleScan(WidgetRef ref, bool isScanning) {
    if (isScanning) {
      ref.read(bleScanNotifierProvider.notifier).stopScan();
    } else {
      ref.read(bleScanNotifierProvider.notifier).startScan();
    }
  }
}

/// 화면 상단에 고정되는 스캔 상태 표시 바.
///
/// 스캔 중일 때는 초록 배경 + 스피너 + "Scanning..." 텍스트,
/// 대기 중일 때는 회색 배경 + 체크 아이콘 + "Ready" 텍스트를 보여준다.
/// 오른쪽 끝에는 발견된 장치 수를 항상 표시한다.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.isScanning, required this.deviceCount});

  final bool isScanning;
  final int deviceCount;

  /// 스캔 상태에 따라 배경색과 좌측 인디케이터를 다르게 렌더링한다.
  ///
  /// spread 연산자([...])로 조건부 위젯 목록을 Row children에 삽입하며,
  /// [Spacer]로 좌측 인디케이터와 우측 장치 수 텍스트를 양 끝으로 배치한다.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isScanning
          ? Colors.green.withOpacity(0.1)
          : Colors.grey.withOpacity(0.1),
      child: Row(
        children: [
          if (isScanning) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            const Text('Scanning...'),
          ] else ...[
            const Icon(Icons.check_circle, color: Colors.green, size: 16),
            const SizedBox(width: 8),
            const Text('Ready'),
          ],
          const Spacer(),
          // deviceCount가 1일 때는 "device", 2 이상일 때는 "devices"로 단수/복수를 구분한다.
          Text('$deviceCount device${deviceCount != 1 ? 's' : ''} found'),
        ],
      ),
    );
  }
}

/// 발견된 장치가 없을 때 표시되는 안내 위젯.
///
/// 스캔 중([isScanning] == true)이면 레이더 아이콘과 "Searching..." 메시지를,
/// 스캔 전/후 대기 상태이면 블루투스 탐색 아이콘과 사용 안내 문구를 표시한다.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isScanning});

  final bool isScanning;

  /// [isScanning] 값에 따라 아이콘, 메인 문구, 부가 안내 문구를 다르게 렌더링한다.
  ///
  /// 스캔 중이 아닐 때만 "Tap Start Scan..." 안내 문구를 추가로 보여준다.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isScanning ? Icons.radar : Icons.bluetooth_searching,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            isScanning ? 'Searching for devices...' : 'No devices found',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          if (!isScanning) ...[
            const SizedBox(height: 8),
            Text(
              'Tap "Start Scan" to discover BLE devices',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[500],
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 발견된 BLE 장치 목록을 스크롤 가능한 리스트로 렌더링하는 위젯.
///
/// 각 항목 사이에 4px 간격을 두고 [_DeviceCard]로 개별 장치를 표시한다.
class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.devices});

  final List<BLEDevice> devices;

  /// [ListView.separated]를 사용해 항목 사이에 일정 간격을 자동으로 삽입한다.
  ///
  /// [itemBuilder]: 인덱스에 해당하는 [BLEDevice]를 [_DeviceCard]로 변환한다.
  /// [separatorBuilder]: 항목 사이에 4px 높이의 빈 공간을 삽입한다.
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: devices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) => _DeviceCard(device: devices[index]),
    );
  }
}

/// 개별 BLE 장치 하나를 카드 형태로 표시하는 위젯.
///
/// 장치 이름, MAC 주소, RSSI(신호 강도), 신호 품질을 보여주고
/// 현재 연결 상태에 따라 오른쪽에 "Connected" 뱃지 또는 화살표 아이콘을 표시한다.
/// 탭하면 [DeviceDetailScreen]으로 이동한다.
class _DeviceCard extends ConsumerWidget {
  const _DeviceCard({required this.device});

  final BLEDevice device;

  /// [connectedDevicesProvider]를 구독해 이 장치의 연결 상태를 실시간으로 반영한다.
  ///
  /// [connectedDevicesProvider]는 현재 연결된 장치 ID들의 Set<String>이며,
  /// device.id가 포함되어 있으면 연결 중으로 판단한다.
  /// 연결 상태가 바뀌면 이 카드만 선택적으로 리빌드된다.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectedDevices = ref.watch(connectedDevicesProvider);
    final isConnected = connectedDevices.contains(device.id);

    return Card(
      child: ListTile(
        // 왼쪽: RSSI 값에 따라 색상이 달라지는 신호 강도 아이콘
        leading: _SignalIcon(rssi: device.rssi),
        title: Text(device.name),
        // MAC 주소를 첫 줄에, RSSI와 신호 품질 텍스트를 두 번째 줄에 표시한다.
        subtitle: Text('${device.macAddress}\n${device.rssi} dBm  •  ${device.signalStrength}'),
        // 오른쪽: 연결 중이면 초록 뱃지, 미연결이면 진입 화살표를 표시한다.
        trailing: isConnected
            ? const Chip(
                label: Text('Connected'),
                backgroundColor: Colors.green,
                labelStyle: TextStyle(color: Colors.white, fontSize: 12),
              )
            : const Icon(Icons.chevron_right),
        // 탭 시 해당 장치의 상세 화면으로 이동한다. device 객체를 그대로 전달한다.
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DeviceDetailScreen(device: device),
          ),
        ),
      ),
    );
  }
}

/// RSSI 값을 색상으로 변환해 신호 강도를 시각적으로 표시하는 아이콘 위젯.
///
/// RSSI(Received Signal Strength Indicator)는 음수 dBm 단위이며
/// 0에 가까울수록 신호가 강하다.
class _SignalIcon extends StatelessWidget {
  const _SignalIcon({required this.rssi});

  final int rssi;

  /// RSSI 범위에 따라 아이콘 색상을 결정한다.
  ///
  /// - -60 dBm 이상 (Strong): 초록색
  /// - -70 dBm 이상 (Medium): 주황색
  /// - -70 dBm 미만 (Weak):   빨간색
  ///
  /// 배경은 해당 색상의 15% 불투명도로 설정해 아이콘을 부드럽게 강조한다.
  @override
  Widget build(BuildContext context) {
    final color = rssi >= -60
        ? Colors.green
        : rssi >= -70
            ? Colors.orange
            : Colors.red;
    return CircleAvatar(
      backgroundColor: color.withOpacity(0.15),
      child: Icon(Icons.signal_cellular_alt, color: color),
    );
  }
}
