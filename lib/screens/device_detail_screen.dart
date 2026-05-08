import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ble_models.dart';
import '../providers/ble_providers.dart';

/// 선택한 BLE 장치의 상세 정보와 GATT 서비스 조작 화면.
///
/// 연결/해제 버튼, 장치 기본 정보(MAC 주소, 신호 강도), 서비스 목록을 표시한다.
/// ConsumerStatefulWidget을 사용하는 이유: 서비스 로드 여부([_servicesLoaded])라는
/// 로컬 상태가 필요하면서도 Riverpod Provider를 구독해야 하기 때문이다.
class DeviceDetailScreen extends ConsumerStatefulWidget {
  const DeviceDetailScreen({super.key, required this.device});

  /// HomeScreen에서 탭한 BLE 장치 객체. 스캔 시점의 스냅샷이다.
  final BLEDevice device;

  @override
  ConsumerState<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends ConsumerState<DeviceDetailScreen> {
  /// 서비스 탐색이 완료되어 목록을 표시할 준비가 됐는지 여부.
  ///
  /// connect() 성공 후 true로 전환되고, disconnect() 후 false로 초기화된다.
  /// false일 때는 [_ServicesSection]을 렌더링하지 않아 미연결 상태의 서비스 조회를 방지한다.
  bool _servicesLoaded = false;

  /// 화면 레이아웃을 구성한다.
  ///
  /// [connectedDevicesProvider]: 이 장치의 현재 연결 상태를 실시간으로 반영
  /// [bleConnectionNotifierProvider]: 연결 작업의 로딩 여부를 버튼에 반영
  ///
  /// 연결된 경우에만 [_ServicesSection]을 보여주어 미연결 시 서비스 탐색 시도를 막는다.
  @override
  Widget build(BuildContext context) {
    final connectedDevices = ref.watch(connectedDevicesProvider);
    final isConnected = connectedDevices.contains(widget.device.id);
    final connectionAsync = ref.watch(
      bleConnectionNotifierProvider,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DeviceInfoCard(device: widget.device, isConnected: isConnected),
          const SizedBox(height: 16),
          _ConnectionButton(
            isConnected: isConnected,
            // connectionAsync.isLoading: 연결/해제 작업이 진행 중이면 버튼을 로딩 인디케이터로 교체
            isLoading: connectionAsync.isLoading,
            onConnect: _connect,
            onDisconnect: _disconnect,
          ),
          const SizedBox(height: 16),
          // 연결되어 있고 서비스 로드 준비가 됐을 때만 서비스 섹션을 렌더링한다.
          if (isConnected && _servicesLoaded)
            _ServicesSection(deviceId: widget.device.id),
        ],
      ),
    );
  }

  /// BLE 연결을 시도하고 성공 시 서비스 목록 표시를 활성화한다.
  ///
  /// [bleConnectionNotifierProvider]의 connect()를 호출한 뒤
  /// [_servicesLoaded]를 true로 전환해 [_ServicesSection]이 렌더링되도록 한다.
  /// mounted 체크: 비동기 작업 완료 전에 화면이 pop되면 setState 호출을 방지한다.
  Future<void> _connect() async {
    await ref
        .read(bleConnectionNotifierProvider.notifier)
        .connect(widget.device.id);
    if (mounted) {
      setState(() => _servicesLoaded = true);
    }
  }

  /// BLE 연결을 해제하고 서비스 목록 표시를 비활성화한다.
  ///
  /// disconnect() 완료 후 [_servicesLoaded]를 false로 전환해
  /// 다음 연결 전까지 서비스 섹션이 보이지 않도록 한다.
  Future<void> _disconnect() async {
    await ref
        .read(bleConnectionNotifierProvider.notifier)
        .disconnect(widget.device.id);
    if (mounted) {
      setState(() => _servicesLoaded = false);
    }
  }
}

/// 장치의 기본 정보를 카드 형태로 표시하는 위젯.
///
/// 장치 이름, 연결 상태 뱃지, MAC 주소, 신호 강도(dBm), 신호 품질 문자열을 표시한다.
class _DeviceInfoCard extends StatelessWidget {
  const _DeviceInfoCard({required this.device, required this.isConnected});

  final BLEDevice device;
  final bool isConnected;

  /// 연결 상태에 따라 상단 뱃지 색상과 텍스트를 다르게 렌더링한다.
  ///
  /// 연결 중: 초록 배경 + "Connected"
  /// 미연결: 회색 배경 + "Disconnected"
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    device.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                // 연결 상태 뱃지: 연결 여부에 따라 색상과 텍스트가 달라진다.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: isConnected
                        ? Colors.green.withOpacity(0.15)
                        : Colors.grey.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isConnected ? 'Connected' : 'Disconnected',
                    style: TextStyle(
                      color: isConnected ? Colors.green[700] : Colors.grey[600],
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _InfoRow(label: 'MAC', value: device.macAddress),
            _InfoRow(label: 'Signal', value: '${device.rssi} dBm'),
            _InfoRow(label: 'Quality', value: device.signalStrength),
          ],
        ),
      ),
    );
  }
}

/// 레이블과 값을 한 행으로 표시하는 재사용 가능한 정보 행 위젯.
///
/// 레이블은 60px 고정 너비로 왼쪽 정렬되고, 값은 그 오른쪽에 표시된다.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

/// 연결/해제 버튼 위젯.
///
/// 연결 작업이 진행 중이면([isLoading] == true) 버튼 대신 [CircularProgressIndicator]를 표시한다.
/// 연결 상태([isConnected])에 따라 버튼 텍스트, 아이콘, 색상이 달라진다.
class _ConnectionButton extends StatelessWidget {
  const _ConnectionButton({
    required this.isConnected,
    required this.isLoading,
    required this.onConnect,
    required this.onDisconnect,
  });

  final bool isConnected;

  /// true일 때 버튼을 숨기고 로딩 스피너를 표시한다. connect()/disconnect() 진행 중에 true가 된다.
  final bool isLoading;

  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  /// [isLoading]이면 스피너, 아니면 연결 상태에 맞는 버튼을 렌더링한다.
  ///
  /// 연결 중: 빨간 계열 "Disconnect" 버튼 (link_off 아이콘)
  /// 미연결: 기본 색 "Connect" 버튼 (link 아이콘)
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: isConnected ? onDisconnect : onConnect,
        icon: Icon(isConnected ? Icons.link_off : Icons.link),
        label: Text(isConnected ? 'Disconnect' : 'Connect'),
        style: ElevatedButton.styleFrom(
          backgroundColor: isConnected ? Colors.red[50] : null,
          foregroundColor: isConnected ? Colors.red : null,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

/// 연결된 장치의 GATT 서비스 목록을 표시하는 섹션 위젯.
///
/// [bleServicesProvider]를 구독해 서비스 탐색 결과를 받아온다.
/// FutureProvider이므로 로딩 중에는 스피너, 완료 후에는 서비스 카드 목록, 오류 시 메시지를 표시한다.
class _ServicesSection extends ConsumerWidget {
  const _ServicesSection({required this.deviceId});

  final String deviceId;

  /// [bleServicesProvider]의 AsyncValue 상태에 따라 세 가지 UI를 렌더링한다.
  ///
  /// - loading: 서비스 탐색 중 스피너
  /// - data: 서비스 카드 목록
  /// - error: 오류 메시지 텍스트
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(bleServicesProvider(deviceId));

    return servicesAsync.when(
      data: (services) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Services',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          ...services.map(
            (service) => _ServiceCard(deviceId: deviceId, service: service),
          ),
        ],
      ),
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

/// 단일 GATT 서비스를 확장/축소 가능한 카드로 표시하는 위젯.
///
/// [ExpansionTile]을 사용해 서비스 이름과 UUID를 헤더로 보여주고,
/// 탭하면 포함된 특성([_CharacteristicTile]) 목록이 펼쳐진다.
class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.deviceId, required this.service});

  final String deviceId;
  final BLEService service;

  /// 서비스 이름과 UUID를 헤더로 표시하고, 확장 시 특성 목록을 렌더링한다.
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: const Icon(Icons.settings_input_component),
        title: Text(service.name),
        // UUID는 작은 글씨로 표시해 이름 아래에 부가 정보로 보여준다.
        subtitle: Text(service.uuid, style: const TextStyle(fontSize: 11)),
        children: service.characteristics
            .map(
              (c) => _CharacteristicTile(
                deviceId: deviceId,
                serviceUuid: service.uuid,
                characteristic: c,
              ),
            )
            .toList(),
      ),
    );
  }
}

/// 단일 BLE 특성을 표시하고 Read/Write/Notify 조작을 수행하는 위젯.
///
/// 특성의 속성([BLECharacteristic.canRead], [canWrite], [canNotify])에 따라
/// 해당 버튼만 선택적으로 표시한다.
///
/// ConsumerStatefulWidget을 사용하는 이유:
/// - [_readValue]: 마지막으로 읽은 값을 로컬 상태로 보관
/// - [_isNotifying]: 알림 구독 여부를 로컬 상태로 보관
/// - ref: [bleRepositoryProvider]로 직접 readCharacteristic/writeCharacteristic 호출
class _CharacteristicTile extends ConsumerStatefulWidget {
  const _CharacteristicTile({
    required this.deviceId,
    required this.serviceUuid,
    required this.characteristic,
  });

  final String deviceId;
  final String serviceUuid;
  final BLECharacteristic characteristic;

  @override
  ConsumerState<_CharacteristicTile> createState() =>
      _CharacteristicTileState();
}

class _CharacteristicTileState extends ConsumerState<_CharacteristicTile> {
  /// Read 버튼으로 읽어온 마지막 값. null이면 아직 읽지 않은 상태다.
  List<int>? _readValue;

  /// 알림 구독 중 여부. true이면 [_NotifyValue] 위젯이 렌더링된다.
  bool _isNotifying = false;

  /// 특성 정보, 읽기 값, 알림 값을 한 행에 표시한다.
  ///
  /// 왼쪽: 특성 이름, UUID, 마지막 읽기 값 또는 실시간 알림 값
  /// 오른쪽: 속성에 따라 Read(다운로드), Write(업로드), Notify(벨) 버튼 표시
  @override
  Widget build(BuildContext context) {
    final c = widget.characteristic;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      title: Text(c.name, style: const TextStyle(fontSize: 14)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.uuid, style: const TextStyle(fontSize: 11)),
          // _read()로 읽어온 값이 있으면 HEX/ASCII 형식으로 표시한다.
          if (_readValue != null)
            Text(
              _formatValue(_readValue!),
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: Colors.blue,
              ),
            ),
          // _isNotifying이 true이면 실시간 알림 값을 표시하는 위젯을 추가한다.
          if (_isNotifying)
            _NotifyValue(
              deviceId: widget.deviceId,
              serviceUuid: widget.serviceUuid,
              characteristicUuid: c.uuid,
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // read 속성이 있는 특성에만 Read 버튼을 표시한다.
          if (c.canRead)
            IconButton(
              icon: const Icon(Icons.download, size: 20),
              tooltip: 'Read',
              onPressed: _read,
            ),
          // write 속성이 있는 특성에만 Write 버튼을 표시한다.
          if (c.canWrite)
            IconButton(
              icon: const Icon(Icons.upload, size: 20),
              tooltip: 'Write',
              onPressed: _showWriteDialog,
            ),
          // notify 속성이 있는 특성에만 Notify 버튼을 표시한다.
          // 구독 중이면 주황색 활성 아이콘, 미구독이면 기본 벨 아이콘을 표시한다.
          if (c.canNotify)
            IconButton(
              icon: Icon(
                _isNotifying ? Icons.notifications_active : Icons.notifications,
                size: 20,
                color: _isNotifying ? Colors.orange : null,
              ),
              tooltip: _isNotifying ? 'Unsubscribe' : 'Subscribe',
              onPressed: () =>
                  setState(() => _isNotifying = !_isNotifying),
            ),
        ],
      ),
    );
  }

  /// GATT Read 절차로 특성 값을 한 번 읽어 [_readValue]에 저장한다.
  ///
  /// Provider가 아닌 [bleRepositoryProvider]를 직접 read하는 이유:
  /// 버튼 탭마다 새로 읽어야 하며, 값을 전역 상태로 공유할 필요가 없기 때문이다.
  /// 실패 시 SnackBar로 오류 메시지를 표시한다.
  Future<void> _read() async {
    try {
      final value = await ref
          .read(bleRepositoryProvider)
          .readCharacteristic(
            deviceId: widget.deviceId,
            serviceUuid: widget.serviceUuid,
            characteristicUuid: widget.characteristic.uuid,
          );
      if (mounted) setState(() => _readValue = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Read failed: $e')));
      }
    }
  }

  /// Write 값 입력 다이얼로그를 표시한다.
  ///
  /// 사용자가 입력한 문자열을 UTF-8 코드 유닛으로 변환해 [_write]에 전달한다.
  void _showWriteDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Write to ${widget.characteristic.name}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter value (e.g. hello)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // 입력 문자열을 바이트 배열(UTF-8 코드 유닛)로 변환해 전송한다.
              _write(controller.text.codeUnits);
            },
            child: const Text('Write'),
          ),
        ],
      ),
    );
  }

  /// GATT Write 절차로 지정된 바이트 배열을 특성에 전송한다.
  ///
  /// 성공 시 "Write successful" SnackBar, 실패 시 오류 메시지 SnackBar를 표시한다.
  Future<void> _write(List<int> value) async {
    try {
      await ref.read(bleRepositoryProvider).writeCharacteristic(
            deviceId: widget.deviceId,
            serviceUuid: widget.serviceUuid,
            characteristicUuid: widget.characteristic.uuid,
            value: value,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Write successful')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Write failed: $e')));
      }
    }
  }

  /// 바이트 배열을 HEX와 ASCII 이중 형식의 문자열로 변환한다.
  ///
  /// HEX: 각 바이트를 2자리 16진수로, 소문자, 공백으로 구분
  /// ASCII: 출력 가능한 문자(32~126)는 그대로, 나머지는 '.'으로 대체
  ///
  /// 예시 출력: "HEX: 3a 2b 4f  |  ASCII: :+O"
  String _formatValue(List<int> value) {
    final hex = value.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    final ascii = value
        .map((b) => b >= 32 && b < 127 ? String.fromCharCode(b) : '.')
        .join();
    return 'HEX: $hex  |  ASCII: $ascii';
  }
}

/// 특성 알림(Notify) 값을 실시간으로 표시하는 위젯.
///
/// [bleNotifyCharacteristicProvider]를 구독해 장치가 새 값을 보낼 때마다 UI를 갱신한다.
/// 이 위젯이 트리에서 제거되면(구독 취소 시) Provider 구독도 자동으로 해제된다.
class _NotifyValue extends ConsumerWidget {
  const _NotifyValue({
    required this.deviceId,
    required this.serviceUuid,
    required this.characteristicUuid,
  });

  final String deviceId;
  final String serviceUuid;
  final String characteristicUuid;

  /// [bleNotifyCharacteristicProvider]의 AsyncValue 상태에 따라 렌더링한다.
  ///
  /// - loading: "Waiting for notification..." 회색 텍스트 (첫 값 도착 전)
  /// - data: 수신된 바이트 배열을 HEX 형식의 주황색 텍스트로 표시
  /// - error: 오류 메시지를 빨간색 텍스트로 표시
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifyAsync = ref.watch(bleNotifyCharacteristicProvider((
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
    )));

    return notifyAsync.when(
      data: (value) {
        // 수신된 바이트 배열을 2자리 16진수 공백 구분 형식으로 변환한다.
        final hex =
            value.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        return Text(
          'NOTIFY: $hex',
          style: const TextStyle(
            fontSize: 11,
            color: Colors.orange,
            fontFamily: 'monospace',
          ),
        );
      },
      loading: () => const Text(
        'Waiting for notification...',
        style: TextStyle(fontSize: 11, color: Colors.grey),
      ),
      error: (e, _) => Text(
        'Error: $e',
        style: const TextStyle(fontSize: 11, color: Colors.red),
      ),
    );
  }
}
