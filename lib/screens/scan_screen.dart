import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ble_service.dart';
import 'controller_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final BleService _bleService = BleService();
  final List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  StreamSubscription? _scanSub;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<void> _startScan() async {
    setState(() {
      _scanResults.clear();
      _isScanning = true;
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        for (final r in results) {
          final idx = _scanResults
              .indexWhere((e) => e.device.remoteId == r.device.remoteId);
          if (idx >= 0) {
            _scanResults[idx] = r;
          } else {
            _scanResults.add(r);
          }
        }
        // HM-10 계열 이름 우선 정렬
        _scanResults.sort((a, b) {
          final aName = a.device.platformName.toLowerCase();
          final bName = b.device.platformName.toLowerCase();
          final aIsHm = aName.contains('hm') ||
              aName.contains('ble') ||
              aName.contains('at-09') ||
              aName.contains('cc41');
          final bIsHm = bName.contains('hm') ||
              bName.contains('ble') ||
              bName.contains('at-09') ||
              bName.contains('cc41');
          if (aIsHm && !bIsHm) return -1;
          if (!aIsHm && bIsHm) return 1;
          return 0;
        });
      });
    });

    await Future.delayed(const Duration(seconds: 6));
    await FlutterBluePlus.stopScan();
    setState(() => _isScanning = false);
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() => _isConnecting = true);
    final success = await _bleService.connect(device);
    setState(() => _isConnecting = false);

    if (success && mounted) {
      await _scanSub?.cancel();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ControllerScreen(bleService: _bleService),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('연결에 실패했습니다. 다시 시도해 주세요.')),
      );
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              // 헤더
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.directions_car_rounded,
                        color: Color(0xFF60A5FA), size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('RC Car Controller',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                      Text('HM-10 BLE 디바이스 검색',
                          style: TextStyle(
                              fontSize: 13, color: Color(0xFF94A3B8))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // 스캔 버튼
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isScanning || _isConnecting ? null : _startScan,
                  icon: _isScanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.bluetooth_searching_rounded),
                  label: Text(_isScanning ? '스캔 중...' : 'BLE 검색 시작'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 결과 헤더
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '발견된 디바이스 (${_scanResults.length})',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF94A3B8)),
                  ),
                  if (_scanResults.isNotEmpty)
                    const Text('탭하여 연결',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF60A5FA))),
                ],
              ),
              const SizedBox(height: 12),

              // 디바이스 목록
              Expanded(
                child: _scanResults.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        itemCount: _scanResults.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) =>
                            _buildDeviceTile(_scanResults[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bluetooth_disabled_rounded,
              size: 48, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            _isScanning ? '디바이스를 찾고 있습니다...' : '검색 버튼을 눌러 시작하세요',
            style:
                TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(ScanResult result) {
    final name = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : '이름 없음';
    final id = result.device.remoteId.toString();
    final rssi = result.rssi;
    final isHm10 = name.toLowerCase().contains('hm') ||
        name.toLowerCase().contains('ble') ||
        name.toLowerCase().contains('at-09');

    return GestureDetector(
      onTap: _isConnecting ? null : () => _connectToDevice(result.device),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isHm10
              ? const Color(0xFF1E3A5F).withOpacity(0.6)
              : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isHm10
                ? const Color(0xFF2563EB).withOpacity(0.6)
                : Colors.white.withOpacity(0.06),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isHm10
                    ? const Color(0xFF2563EB).withOpacity(0.2)
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isHm10
                    ? Icons.bluetooth_connected_rounded
                    : Icons.bluetooth_rounded,
                color:
                    isHm10 ? const Color(0xFF60A5FA) : const Color(0xFF64748B),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(name,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: isHm10
                                  ? Colors.white
                                  : const Color(0xFFCBD5E1))),
                      if (isHm10) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB).withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('HM-10',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF93C5FD),
                                  fontWeight: FontWeight.w500)),
                        ),
                      ]
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(id,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF64748B))),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(
                  rssi > -60
                      ? Icons.signal_cellular_alt_rounded
                      : rssi > -80
                          ? Icons.signal_cellular_alt_2_bar_rounded
                          : Icons.signal_cellular_alt_1_bar_rounded,
                  size: 16,
                  color: rssi > -60
                      ? const Color(0xFF4ADE80)
                      : rssi > -80
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFFF87171),
                ),
                Text('$rssi dBm',
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF64748B))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
