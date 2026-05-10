import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bt_models.dart';
import '../providers/bt_providers.dart';

/// Classic BT 장치 상세 화면.
///
/// BLE의 [DeviceDetailScreen]과 달리 세 단계 조작이 필요하다:
///   1. 페어링 (처음 한 번만)
///   2. 연결 (매번)
///   3. 데이터 송수신 (SPP 프로파일만)
///
/// SPP 프로파일을 지원하는 장치는 연결 후 채팅 터미널이 표시된다.
/// HID, A2DP 등은 연결만 보여주고 터미널은 표시하지 않는다.
class BTDeviceDetailScreen extends ConsumerStatefulWidget {
  const BTDeviceDetailScreen({super.key, required this.device});

  final BTDevice device;

  @override
  ConsumerState<BTDeviceDetailScreen> createState() =>
      _BTDeviceDetailScreenState();
}

class _BTDeviceDetailScreenState extends ConsumerState<BTDeviceDetailScreen> {
  /// SPP 터미널 표시 여부. connect() 성공 후 SPP 지원 장치에 한해 true가 된다.
  bool _terminalVisible = false;

  @override
  Widget build(BuildContext context) {
    final connectedDevices = ref.watch(connectedBTDevicesProvider);
    final isConnected = connectedDevices.contains(widget.device.address);
    final connectionAsync = ref.watch(btConnectionNotifierProvider);
    final pairingAsync = ref.watch(btPairingNotifierProvider);

    final isLoading = connectionAsync.isLoading || pairingAsync.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 장치 기본 정보 카드 (MAC, 프로파일, 페어링/연결 상태)
          _DeviceInfoCard(device: widget.device, isConnected: isConnected),
          const SizedBox(height: 16),

          // 페어링 버튼 (미페어링 장치에만 표시)
          if (!widget.device.isPaired) ...[
            _PairButton(
              isLoading: isLoading,
              onPair: _pair,
            ),
            const SizedBox(height: 12),
          ],

          // 연결/해제 버튼 (페어링된 장치에만 표시)
          if (widget.device.isPaired) ...[
            _ConnectionButton(
              isConnected: isConnected,
              isLoading: isLoading,
              onConnect: _connect,
              onDisconnect: _disconnect,
            ),
            const SizedBox(height: 16),
          ],

          // SPP 터미널 (SPP 지원 + 연결 완료 상태에만 표시)
          if (isConnected && _terminalVisible && widget.device.supportsSPP)
            _SPPTerminal(address: widget.device.address),
        ],
      ),
    );
  }

  /// 장치와 페어링을 시도한다.
  ///
  /// 성공 후 화면의 [widget.device]는 스캔 시점의 스냅샷이므로
  /// UI 갱신을 위해 [setState]로 강제 리빌드한다.
  Future<void> _pair() async {
    await ref
        .read(btPairingNotifierProvider.notifier)
        .pair(widget.device.address);
    if (mounted) setState(() {});
  }

  /// SPP 소켓 연결을 시도한다.
  ///
  /// 성공 후 SPP 지원 장치이면 터미널을 표시한다.
  Future<void> _connect() async {
    await ref
        .read(btConnectionNotifierProvider.notifier)
        .connect(widget.device.address);
    if (mounted) {
      setState(() => _terminalVisible = widget.device.supportsSPP);
    }
  }

  /// SPP 소켓 연결을 해제한다.
  Future<void> _disconnect() async {
    await ref
        .read(btConnectionNotifierProvider.notifier)
        .disconnect(widget.device.address);
    if (mounted) {
      setState(() => _terminalVisible = false);
    }
  }
}

/// 장치 기본 정보를 카드 형태로 표시하는 위젯.
///
/// MAC 주소, 신호 강도, 지원 프로파일, 페어링 상태, 연결 상태를 보여준다.
class _DeviceInfoCard extends StatelessWidget {
  const _DeviceInfoCard({required this.device, required this.isConnected});

  final BTDevice device;
  final bool isConnected;

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
                // 연결 상태 뱃지
                _StatusBadge(
                  label: isConnected ? 'Connected' : 'Disconnected',
                  color: isConnected ? Colors.green : Colors.grey,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(label: 'MAC', value: device.address),
            _InfoRow(label: 'Signal', value: '${device.rssi} dBm  •  ${device.signalStrength}'),
            _InfoRow(
              label: 'Pairing',
              value: switch (device.pairState) {
                BTPairState.paired    => 'Paired ✓',
                BTPairState.pairing   => 'Pairing...',
                BTPairState.notPaired => 'Not Paired',
              },
            ),
            const SizedBox(height: 8),
            // 지원 프로파일 목록
            const Text(
              'Profiles',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: device.profiles.map((p) {
                final color = switch (p) {
                  BTProfile.spp  => Colors.teal,
                  BTProfile.a2dp => Colors.purple,
                  BTProfile.hfp  => Colors.indigo,
                  BTProfile.hid  => Colors.brown,
                  BTProfile.opp  => Colors.cyan,
                };
                return Chip(
                  label: Text(p.displayName),
                  backgroundColor: color.withValues(alpha: 0.12),
                  labelStyle: TextStyle(color: color, fontSize: 12),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

/// 레이블과 값을 한 행으로 표시하는 정보 행.
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
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

/// 색상 배경의 상태 뱃지 위젯.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// 페어링 버튼 위젯.
///
/// 미페어링 장치에만 표시되며, 탭하면 PIN 교환 및 페어링 절차가 시작된다.
class _PairButton extends StatelessWidget {
  const _PairButton({required this.isLoading, required this.onPair});

  final bool isLoading;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPair,
        icon: const Icon(Icons.link),
        label: const Text('Pair Device'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          backgroundColor: Colors.blue[50],
          foregroundColor: Colors.blue[700],
        ),
      ),
    );
  }
}

/// 연결/해제 토글 버튼 위젯.
///
/// 연결 상태에 따라 버튼 스타일이 달라진다:
/// - 미연결: 기본 "Connect" 버튼
/// - 연결 중: 빨간 "Disconnect" 버튼
class _ConnectionButton extends StatelessWidget {
  const _ConnectionButton({
    required this.isConnected,
    required this.isLoading,
    required this.onConnect,
    required this.onDisconnect,
  });

  final bool isConnected;
  final bool isLoading;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

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
        label: Text(isConnected ? 'Disconnect' : 'Connect (SPP)'),
        style: ElevatedButton.styleFrom(
          backgroundColor: isConnected ? Colors.red[50] : null,
          foregroundColor: isConnected ? Colors.red : null,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

/// SPP 직렬 통신 터미널 위젯.
///
/// 장치에서 수신된 메시지와 앱에서 송신한 메시지를 채팅 형태로 표시한다.
/// 수신 메시지는 왼쪽(회색), 송신 메시지는 오른쪽(파란색)으로 정렬된다.
///
/// [btReceiveDataProvider] 스트림을 구독해 새 메시지 도착 시 자동으로 목록에 추가한다.
class _SPPTerminal extends ConsumerStatefulWidget {
  const _SPPTerminal({required this.address});

  final String address;

  @override
  ConsumerState<_SPPTerminal> createState() => _SPPTerminalState();
}

class _SPPTerminalState extends ConsumerState<_SPPTerminal> {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 수신 스트림을 구독해 새 메시지가 올 때마다 히스토리에 추가한다.
    ref.listenManual(
      btReceiveDataProvider(widget.address),
      (_, next) {
        next.whenData((msg) {
          ref
              .read(btMessageHistoryProvider(widget.address).notifier)
              .state = [
            ...ref.read(btMessageHistoryProvider(widget.address)),
            msg,
          ];
          // 새 메시지 도착 시 목록 맨 아래로 스크롤한다.
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        });
      },
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  /// 메시지 목록을 맨 아래로 스크롤한다.
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  /// 입력창의 텍스트를 바이트로 변환해 장치로 전송하고 히스토리에 추가한다.
  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    final data = '$text\r\n'.codeUnits; // 줄 끝에 CR+LF 추가 (시리얼 통신 관례)
    _inputController.clear();

    try {
      await ref.read(btRepositoryProvider).sendData(widget.address, data);
      // 송신 메시지도 히스토리에 추가해 채팅처럼 표시한다.
      ref.read(btMessageHistoryProvider(widget.address).notifier).state = [
        ...ref.read(btMessageHistoryProvider(widget.address)),
        BTMessage(
          data: data,
          timestamp: DateTime.now(),
          isFromDevice: false,
        ),
      ];
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Send failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(btMessageHistoryProvider(widget.address));

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 터미널 헤더
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 16, color: Colors.teal),
                const SizedBox(width: 8),
                const Text(
                  'SPP Terminal',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
                const Spacer(),
                // 메시지 히스토리를 지우는 버튼
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Clear',
                  onPressed: () => ref
                      .read(btMessageHistoryProvider(widget.address).notifier)
                      .state = [],
                  color: Colors.teal,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          // 메시지 목록
          SizedBox(
            height: 280,
            child: messages.isEmpty
                ? const Center(
                    child: Text(
                      'Waiting for data...',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => _MessageBubble(message: messages[i]),
                  ),
          ),
          const Divider(height: 1),
          // 입력창 + 전송 버튼
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    decoration: const InputDecoration(
                      hintText: 'Type a command...',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                  style: IconButton.styleFrom(backgroundColor: Colors.teal),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 단일 SPP 메시지를 채팅 버블 형태로 표시하는 위젯.
///
/// [BTMessage.isFromDevice]에 따라 정렬 방향과 색상이 달라진다:
/// - 수신 (isFromDevice == true):  왼쪽 정렬, 회색 배경
/// - 송신 (isFromDevice == false): 오른쪽 정렬, 파란색 배경
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final BTMessage message;

  @override
  Widget build(BuildContext context) {
    final isFromDevice = message.isFromDevice;
    final time = '${message.timestamp.hour.toString().padLeft(2, '0')}:'
        '${message.timestamp.minute.toString().padLeft(2, '0')}:'
        '${message.timestamp.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: isFromDevice
            ? MainAxisAlignment.start  // 수신: 왼쪽
            : MainAxisAlignment.end,   // 송신: 오른쪽
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isFromDevice
                    ? Colors.grey[200]
                    : Colors.teal.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: isFromDevice
                    ? null
                    : Border.all(color: Colors.teal.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: isFromDevice
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                children: [
                  // 디바이스 레이블 또는 "You" 레이블
                  Text(
                    isFromDevice ? '📡 Device' : '📱 You',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // 메시지 본문 (ASCII 텍스트로 표시)
                  Text(
                    message.text.isNotEmpty ? message.text : message.hex,
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 2),
                  // 타임스탬프
                  Text(
                    time,
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
