import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../widgets/joystick.dart';

class ControllerScreen extends StatefulWidget {
  final BleService bleService;
  const ControllerScreen({super.key, required this.bleService});

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  int _speedLevel = 7; // 0~9 속도 단계 (최종 파워에 곱해짐)
  double _leftPower = 0.0; // -1.0 ~ 1.0
  double _rightPower = 0.0;
  bool _isConnected = true;
  String _status = '연결됨';

  Timer? _sendTimer; // 100ms 간격 반복 전송
  double _pendingLeft = 0.0;
  double _pendingRight = 0.0;

  @override
  void initState() {
    super.initState();
    widget.bleService.connectionStream.listen((connected) {
      if (mounted) setState(() => _isConnected = connected);
      if (!connected && mounted) Navigator.of(context).pop();
    });
    widget.bleService.statusStream.listen((status) {
      if (mounted) setState(() => _status = status);
    });
  }

  // 조이스틱 콜백 — 새 파워값이 올 때마다 호출
  void _onJoystick(double left, double right) {
    // 속도 단계 적용 (0~9 → 0.0~1.0 배율)
    final scale = _speedLevel / 9.0;
    final l = left * scale;
    final r = right * scale;

    if (mounted)
      setState(() {
        _leftPower = l;
        _rightPower = r;
      });

    _pendingLeft = l;
    _pendingRight = r;

    // 정지 명령은 즉시 + 타이머 중단
    if (l == 0.0 && r == 0.0) {
      _sendTimer?.cancel();
      _sendTimer = null;
      widget.bleService.sendCommand('S');
      return;
    }

    // 주행 중: 타이머가 없으면 시작, 있으면 그냥 둠 (100ms마다 최신값 전송)
    _sendMotor(l, r);
    _sendTimer ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
      _sendMotor(_pendingLeft, _pendingRight);
    });
  }

  // 프로토콜: "Lxxx Rxxx\n"  (xxx = 0~255, 128=정지, 255=전진최대, 0=후진최대)
  // 아두이노에서 파싱: L값>128 전진, L값<128 후진
  void _sendMotor(double left, double right) {
    // -1.0~1.0 → 0~255 변환 (128 = 정지)
    final l = (left * 127 + 128).round().clamp(0, 255);
    final r = (right * 127 + 128).round().clamp(0, 255);
    widget.bleService.sendCommand('L${l}R$r\n');
  }

  void _setSpeed(int level) {
    setState(() => _speedLevel = level);
    // 현재 주행 중이면 즉시 새 속도 반영
    _onJoystick(_leftPower / ((_speedLevel == 0 ? 1 : _speedLevel) / 9.0),
        _rightPower / ((_speedLevel == 0 ? 1 : _speedLevel) / 9.0));
  }

  // 현재 상태를 텍스트로 표현
  String get _dirLabel {
    final l = _leftPower, r = _rightPower;
    if (l == 0 && r == 0) return '정지';
    if (l > 0.05 && r > 0.05) {
      if ((l - r).abs() < 0.15) return '전진';
      return l > r ? '전진 우회전' : '전진 좌회전';
    }
    if (l < -0.05 && r < -0.05) {
      if ((l - r).abs() < 0.15) return '후진';
      return l.abs() < r.abs() ? '후진 우회전' : '후진 좌회전';
    }
    if (l > 0.05 && r < -0.05) return '제자리 우회전';
    if (l < -0.05 && r > 0.05) return '제자리 좌회전';
    if (l > 0.05) return '완만한 우회전';
    if (r > 0.05) return '완만한 좌회전';
    return '조향 중';
  }

  Color get _dirColor {
    final l = _leftPower, r = _rightPower;
    if (l == 0 && r == 0) return const Color(0xFF64748B);
    if (l > 0 && r > 0) return const Color(0xFF4ADE80);
    if (l < 0 && r < 0) return const Color(0xFFF87171);
    return const Color(0xFFFBBF24);
  }

  @override
  void dispose() {
    _sendTimer?.cancel();
    widget.bleService.sendCommand('S');
    widget.bleService.disconnect();
    widget.bleService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              _buildTopBar(),
              const SizedBox(height: 16),
              _buildStatusCard(),
              const Spacer(),
              Center(
                child: SizedBox(
                  width: 270,
                  height: 270,
                  child: JoystickController(onChanged: _onJoystick),
                ),
              ),
              const Spacer(),
              _buildSpeedControl(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        GestureDetector(
          onTap: () async {
            _sendTimer?.cancel();
            await widget.bleService.disconnect();
            if (mounted) Navigator.of(context).pop();
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back_rounded,
                color: Color(0xFF94A3B8), size: 20),
          ),
        ),
        const SizedBox(width: 12),
        const Text('RC Car Controller',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _isConnected
                ? const Color(0xFF166534).withOpacity(0.4)
                : const Color(0xFF7F1D1D).withOpacity(0.4),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isConnected
                  ? const Color(0xFF4ADE80).withOpacity(0.4)
                  : const Color(0xFFF87171).withOpacity(0.4),
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _isConnected
                      ? const Color(0xFF4ADE80)
                      : const Color(0xFFF87171),
                  shape: BoxShape.circle,
                )),
            const SizedBox(width: 6),
            Text(_isConnected ? '연결됨' : '연결 끊김',
                style: TextStyle(
                    fontSize: 12,
                    color: _isConnected
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFFF87171))),
          ]),
        ),
      ],
    );
  }

  Widget _buildStatusCard() {
    // 모터 파워 바 (좌/우 각각)
    final lPct = ((_leftPower + 1) / 2 * 100).round(); // 0~100%
    final rPct = ((_rightPower + 1) / 2 * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_dirLabel,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500, color: _dirColor)),
          Text(
            _status,
            style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 10),
          // 좌측 모터
          _buildMotorBar('L', _leftPower, lPct),
          const SizedBox(height: 6),
          // 우측 모터
          _buildMotorBar('R', _rightPower, rPct),
        ],
      ),
    );
  }

  Widget _buildMotorBar(String label, double power, int pct) {
    final isForward = power > 0.05;
    final isBackward = power < -0.05;
    final barColor = isForward
        ? const Color(0xFF4ADE80)
        : isBackward
            ? const Color(0xFFF87171)
            : const Color(0xFF475569);
    // 바 너비: 50% = 정지, 0%=최대후진, 100%=최대전진
    final barWidth = (power + 1) / 2; // 0.0 ~ 1.0

    return Row(children: [
      SizedBox(
          width: 14,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500))),
      const SizedBox(width: 8),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(children: [
            // 트랙
            Container(height: 6, color: Colors.white.withOpacity(0.06)),
            // 중앙선
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.center,
                child:
                    Container(width: 1, color: Colors.white.withOpacity(0.15)),
              ),
            ),
            // 채우기
            FractionallySizedBox(
              widthFactor: barWidth,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 60),
                height: 6,
                color: barColor.withOpacity(0.7),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
          width: 34,
          child: Text('$pct%',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: barColor))),
    ]);
  }

  Widget _buildSpeedControl() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('최대 속도',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF94A3B8))),
            Row(
                children: List.generate(10, (i) {
              final active = i <= _speedLevel;
              return GestureDetector(
                onTap: () => _setSpeed(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 17,
                  height: 22,
                  margin: const EdgeInsets.only(left: 3),
                  decoration: BoxDecoration(
                    color: active
                        ? Color.lerp(const Color(0xFF2563EB),
                            const Color(0xFF4ADE80), i / 9)
                        : Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            })),
          ],
        ),
        const SizedBox(height: 10),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFF2563EB),
            inactiveTrackColor: Colors.white.withOpacity(0.08),
            thumbColor: Colors.white,
            overlayColor: const Color(0xFF2563EB).withOpacity(0.2),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
          ),
          child: Slider(
            value: _speedLevel.toDouble(),
            min: 0,
            max: 9,
            divisions: 9,
            onChanged: (v) => _setSpeed(v.round()),
          ),
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('저속',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            Text('고속',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          ],
        ),
      ]),
    );
  }
}
