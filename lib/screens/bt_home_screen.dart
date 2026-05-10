import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bt_models.dart';
import '../providers/bt_providers.dart';
import 'bt_device_detail_screen.dart';

/// Classic Bluetooth 장치 탐색 메인 화면.
///
/// 상단에 페어링된 장치 목록, 하단에 탐색으로 발견된 새 장치 목록을 표시한다.
/// BLE 화면([HomeScreen])과 다른 점:
/// - 페어링 개념이 있어 두 섹션으로 나뉜다.
/// - 탐색 속도가 느려 1.5초마다 장치가 나타난다.
/// - 연결 전 페어링이 필요하다.
class BTHomeScreen extends ConsumerWidget {
  const BTHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDiscovering = ref.watch(btIsDiscoveringProvider);
    final discoveredDevices = ref.watch(discoveredBTDevicesProvider);
    final pairedAsync = ref.watch(pairedBTDevicesProvider);
    final bleEnabled = ref.watch(btIsBluetoothEnabledProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Classic BT Scanner'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
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
          _StatusBar(
            isDiscovering: isDiscovering,
            deviceCount: discoveredDevices.length,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                // 섹션 1: 이미 페어링된 장치 목록
                _PairedSection(pairedAsync: pairedAsync),
                const SizedBox(height: 8),
                // 섹션 2: 탐색으로 발견된 장치 목록
                _DiscoveredSection(
                  devices: discoveredDevices,
                  isDiscovering: isDiscovering,
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        // IndexedStack이 두 탭을 동시에 마운트하므로 Hero 충돌 방지를 위해 null로 비활성화한다.
        heroTag: null,
        onPressed: () => _toggleDiscovery(ref, isDiscovering),
        icon: Icon(isDiscovering ? Icons.stop : Icons.search),
        label: Text(isDiscovering ? 'Stop' : 'Discover'),
        backgroundColor: isDiscovering ? Colors.red : null,
      ),
    );
  }

  /// 탐색 상태에 따라 startDiscovery 또는 stopDiscovery를 호출한다.
  void _toggleDiscovery(WidgetRef ref, bool isDiscovering) {
    if (isDiscovering) {
      ref.read(btDiscoveryNotifierProvider.notifier).stopDiscovery();
    } else {
      ref.read(btDiscoveryNotifierProvider.notifier).startDiscovery();
    }
  }
}

/// 탐색 진행 상태와 발견 장치 수를 표시하는 상단 고정 바.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.isDiscovering, required this.deviceCount});

  final bool isDiscovering;
  final int deviceCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDiscovering
          ? Colors.orange.withValues(alpha: 0.1)
          : Colors.grey.withValues(alpha: 0.1),
      child: Row(
        children: [
          if (isDiscovering) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            // Flexible로 감싸 남은 공간 안에서만 텍스트가 그려지도록 한다.
            const Flexible(child: Text('Discovering... (slower than BLE)', overflow: TextOverflow.ellipsis)),
          ] else ...[
            const Icon(Icons.check_circle, color: Colors.green, size: 16),
            const SizedBox(width: 8),
            const Text('Ready'),
          ],
          const Spacer(),
          Text('$deviceCount found'),
        ],
      ),
    );
  }
}

/// 페어링된 장치 섹션.
///
/// [pairedBTDevicesProvider]의 로딩/완료/오류 상태에 따라 다른 UI를 표시한다.
/// 페어링된 장치가 없으면 "No paired devices" 메시지를 보여준다.
class _PairedSection extends ConsumerWidget {
  const _PairedSection({required this.pairedAsync});

  final AsyncValue<List<BTDevice>> pairedAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          icon: Icons.link,
          title: 'Paired Devices',
          color: Colors.blue[700]!,
        ),
        const SizedBox(height: 4),
        pairedAsync.when(
          data: (devices) => devices.isEmpty
              ? const _EmptyMessage(message: 'No paired devices')
              : Column(
                  children: devices
                      .map((d) => _BTDeviceCard(device: d))
                      .toList(),
                ),
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Error: $e'),
        ),
      ],
    );
  }
}

/// 탐색으로 발견된 장치 섹션.
///
/// 탐색 전이면 안내 메시지, 탐색 중이면 발견된 장치 목록을 표시한다.
class _DiscoveredSection extends StatelessWidget {
  const _DiscoveredSection({
    required this.devices,
    required this.isDiscovering,
  });

  final List<BTDevice> devices;
  final bool isDiscovering;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          icon: Icons.radar,
          title: 'Available Devices',
          color: Colors.orange[700]!,
        ),
        const SizedBox(height: 4),
        if (devices.isEmpty)
          _EmptyMessage(
            message: isDiscovering
                ? 'Searching nearby devices...'
                : 'Tap "Discover" to find devices',
          )
        else
          ...devices.map((d) => _BTDeviceCard(device: d)),
      ],
    );
  }
}

/// 섹션 헤더 (아이콘 + 제목 + 색상 구분선).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}

/// 장치가 없을 때 표시하는 안내 메시지.
class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Text(
        message,
        style: TextStyle(color: Colors.grey[500], fontSize: 13),
      ),
    );
  }
}

/// 개별 Classic BT 장치를 카드 형태로 표시하는 위젯.
///
/// BLE 카드와 달리 페어링 상태 뱃지와 프로파일 칩을 추가로 표시한다.
/// 페어링된 장치는 파란 뱃지, 미페어링 장치는 회색 뱃지를 표시한다.
class _BTDeviceCard extends ConsumerWidget {
  const _BTDeviceCard({required this.device});

  final BTDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectedDevices = ref.watch(connectedBTDevicesProvider);
    final isConnected = connectedDevices.contains(device.address);

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: _SignalIcon(rssi: device.rssi),
        title: Row(
          children: [
            Expanded(child: Text(device.name)),
            // 페어링 상태 뱃지
            _PairBadge(pairState: device.pairState),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device.address,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 4),
            // 지원 프로파일을 칩(태그) 형태로 나열한다.
            Wrap(
              spacing: 4,
              children: device.profiles
                  .map((p) => _ProfileChip(profile: p))
                  .toList(),
            ),
          ],
        ),
        // 연결 중이면 초록 "Connected" 뱃지, 아니면 화살표를 표시한다.
        trailing: isConnected
            ? const Chip(
                label: Text('Connected'),
                backgroundColor: Colors.green,
                labelStyle: TextStyle(color: Colors.white, fontSize: 11),
                padding: EdgeInsets.zero,
              )
            : const Icon(Icons.chevron_right),
        isThreeLine: true,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BTDeviceDetailScreen(device: device),
          ),
        ),
      ),
    );
  }
}

/// 페어링 상태를 색상 뱃지로 표시하는 위젯.
///
/// - paired:    파란 배경 + "Paired"
/// - pairing:   주황 배경 + "Pairing..."
/// - notPaired: 회색 배경 + "Not Paired"
class _PairBadge extends StatelessWidget {
  const _PairBadge({required this.pairState});

  final BTPairState pairState;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (pairState) {
      BTPairState.paired    => (Colors.blue, 'Paired'),
      BTPairState.pairing   => (Colors.orange, 'Pairing...'),
      BTPairState.notPaired => (Colors.grey, 'Not Paired'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// BT 프로파일 하나를 작은 칩으로 표시하는 위젯.
///
/// 프로파일 종류에 따라 색상을 다르게 해서 한눈에 구분할 수 있게 한다.
class _ProfileChip extends StatelessWidget {
  const _ProfileChip({required this.profile});

  final BTProfile profile;

  @override
  Widget build(BuildContext context) {
    final color = switch (profile) {
      BTProfile.spp  => Colors.teal,
      BTProfile.a2dp => Colors.purple,
      BTProfile.hfp  => Colors.indigo,
      BTProfile.hid  => Colors.brown,
      BTProfile.opp  => Colors.cyan,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        profile.displayName,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// RSSI 값을 색상 아이콘으로 표시하는 위젯.
class _SignalIcon extends StatelessWidget {
  const _SignalIcon({required this.rssi});

  final int rssi;

  @override
  Widget build(BuildContext context) {
    final color = rssi >= -60
        ? Colors.green
        : rssi >= -70
            ? Colors.orange
            : Colors.red;
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.15),
      child: Icon(Icons.bluetooth, color: color),
    );
  }
}
