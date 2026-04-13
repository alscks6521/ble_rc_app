import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  // HM-10 기본 서비스/특성 UUID
  static const String _serviceUuid = 'ffe0';
  static const String _characteristicUuid = 'ffe1';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _txCharacteristic;

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  final StreamController<String> _statusController =
      StreamController<String>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<String> get statusStream => _statusController.stream;
  bool get isConnected => _device != null && _txCharacteristic != null;

  // 디바이스 연결
  Future<bool> connect(BluetoothDevice device) async {
    try {
      _statusController.add('연결 중...');
      await device.connect(timeout: const Duration(seconds: 10));
      _device = device;

      // 연결 끊김 자동 감지
      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _txCharacteristic = null;
          _device = null;
          _connectionController.add(false);
          _statusController.add('연결 끊김');
        }
      });

      // 서비스 탐색
      await _discoverServices();
      return true;
    } catch (e) {
      _statusController.add('연결 실패: $e');
      return false;
    }
  }

  Future<void> _discoverServices() async {
    if (_device == null) return;

    final services = await _device!.discoverServices();
    for (final service in services) {
      if (service.uuid.toString().toLowerCase().contains(_serviceUuid)) {
        for (final char in service.characteristics) {
          if (char.uuid
              .toString()
              .toLowerCase()
              .contains(_characteristicUuid)) {
            _txCharacteristic = char;
            _connectionController.add(true);
            _statusController.add('연결됨');
            return;
          }
        }
      }
    }
    // UUID 매칭 실패 시 첫 번째 쓰기 가능 특성 사용 (호환 모듈 대응)
    for (final service in services) {
      for (final char in service.characteristics) {
        if (char.properties.write || char.properties.writeWithoutResponse) {
          _txCharacteristic = char;
          _connectionController.add(true);
          _statusController.add('연결됨 (호환 모드)');
          return;
        }
      }
    }
    _statusController.add('특성을 찾을 수 없음');
  }

  // 명령어 전송 (문자 1개)
  Future<void> sendCommand(String command) async {
    if (_txCharacteristic == null) return;
    try {
      final bytes = utf8.encode(command);
      await _txCharacteristic!.write(bytes, withoutResponse: true);
    } catch (e) {
      _statusController.add('전송 오류: $e');
    }
  }

  // 연결 해제
  Future<void> disconnect() async {
    await _device?.disconnect();
    _txCharacteristic = null;
    _device = null;
    _connectionController.add(false);
    _statusController.add('연결 해제됨');
  }

  void dispose() {
    _connectionController.close();
    _statusController.close();
  }
}
