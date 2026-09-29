import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/models.dart';
import '../services/session.dart';
import 'common.dart';

/// 키·몸무게·허리둘레 입력 + 신체지수
class ProfileScreen extends StatefulWidget {
  final bool first; // 첫 운동 전 입력 요청으로 열렸는지
  const ProfileScreen({super.key, this.first = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final s = Session.instance;
  late final _h = TextEditingController(text: _fmt(s.profile.heightCm));
  late final _w = TextEditingController(text: _fmt(s.profile.weightKg));
  late final _waist = TextEditingController(text: _fmt(s.profile.waistCm));
  late bool? _male = s.profile.male;

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  Profile? get _draft {
    final h = double.tryParse(_h.text);
    final w = double.tryParse(_w.text);
    final wa = double.tryParse(_waist.text);
    if (h == null || w == null || wa == null) return null;
    if (h < 100 || h > 230 || w < 25 || w > 250 || wa < 40 || wa > 200) {
      return null;
    }
    return Profile(heightCm: h, weightKg: w, waistCm: wa, male: _male);
  }

  Future<void> _save() async {
    final p = _draft;
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('키(100~230cm)·몸무게(25~250kg)·허리(40~200cm)를 확인해주세요.')));
      return;
    }
    await s.saveProfile(p);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    if (widget.first) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('저장했습니다.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _draft;
    final body = ListView(padding: const EdgeInsets.all(20), children: [
      const Text('신체 정보',
          style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2)),
      const SizedBox(height: 6),
      const Text('칼로리 계산에 몸무게가 쓰입니다. 운동 기록마다 그때의 신체 정보가 함께 저장됩니다.',
          style: TextStyle(color: muted)),
      const SizedBox(height: 20),
      _field('키', 'cm', _h),
      _field('몸무게', 'kg', _w),
      _field('허리둘레', 'cm', _waist),
      const SizedBox(height: 6),
      const Text('성별 (선택 · 체지방률 추정용)', style: labelStyle),
      const SizedBox(height: 8),
      SegmentedButton<bool?>(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: ink,
          selectedForegroundColor: Colors.white,
          shape: const RoundedRectangleBorder(),
        ),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: true, label: Text('남')),
          ButtonSegment(value: false, label: Text('여')),
          ButtonSegment(value: null, label: Text('선택 안 함')),
        ],
        selected: {_male},
        onSelectionChanged: (v) => setState(() => _male = v.first),
      ),
      const SizedBox(height: 22),
      SizedBox(
        height: 54,
        child: FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: ink, shape: const RoundedRectangleBorder()),
          onPressed: _save,
          child: const Text('저장',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
      ),
      const SizedBox(height: 28),
      if (p != null) ..._indices(p),
      if (!widget.first) ...[
        const SizedBox(height: 28),
        const Text('기록이 끊길 때', style: labelStyle),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              foregroundColor: ink, shape: const RoundedRectangleBorder()),
          onPressed: s.requestBatteryExemption,
          icon: const Icon(Icons.battery_saver),
          label: const Text('배터리 최적화에서 이 앱 제외하기'),
        ),
        const SizedBox(height: 6),
        const Text(
            '화면을 끈 채 운동하면 일부 폰(특히 삼성)은 절전 때문에 GPS 기록을 멈춥니다. '
            '위 버튼으로 제외하고, 설정 > 배터리 > 백그라운드 사용 제한에서 「절전 예외 앱」에 추가하세요.',
            style: TextStyle(color: muted, fontSize: 13)),
      ],
    ]);

    if (widget.first) {
      return Scaffold(appBar: AppBar(title: const Text('시작 전 입력')), body: body);
    }
    return SafeArea(child: body);
  }

  Widget _field(String label, String unit, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
          border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
          focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: ink, width: 2)),
          floatingLabelStyle: const TextStyle(color: ink),
        ),
      ),
    );
  }

  List<Widget> _indices(Profile p) {
    final bmi = p.bmi;
    // 대한비만학회 기준
    final bmiText = bmi < 18.5
        ? '저체중'
        : bmi < 23
            ? '정상'
            : bmi < 25
                ? '비만 전 단계'
                : bmi < 30
                    ? '1단계 비만'
                    : bmi < 35
                        ? '2단계 비만'
                        : '3단계 비만';
    final whtr = p.waistToHeight;
    final whtrText = whtr < 0.5 ? '양호' : (whtr < 0.6 ? '주의' : '위험');
    final waistLimit = p.male == false ? 85 : 90;
    final fat = p.bodyFatPercent;

    return [
      const Text('신체 지수', style: labelStyle),
      const SizedBox(height: 4),
      InfoRow(Icons.monitor_weight_outlined, 'BMI',
          '${bmi.toStringAsFixed(1)} · $bmiText'),
      InfoRow(Icons.straighten, '허리/키 비율',
          '${whtr.toStringAsFixed(2)} · $whtrText'),
      if (p.male != null)
        InfoRow(
            Icons.accessibility_new,
            '복부비만',
            p.waistCm >= waistLimit
                ? '해당 (기준 $waistLimit cm)'
                : '아님 (기준 $waistLimit cm)'),
      if (fat != null)
        InfoRow(Icons.pie_chart_outline, '체지방률(추정)',
            '${fat.toStringAsFixed(1)} %'),
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
            'BMI 기준: 대한비만학회 · 허리/키 0.5 이상은 복부비만 위험 · 체지방률은 키·허리둘레로 계산한 추정치(RFM)입니다.',
            style: TextStyle(color: muted, fontSize: 12)),
      ),
    ];
  }
}
