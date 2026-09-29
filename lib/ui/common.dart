import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../engine/models.dart';

const ink = Colors.black;
const muted = Color(0xFF6B6B6B);
const line = Color(0xFFE6E6E6);
const paceBlue = Color(0xFF2F80ED);
const elevGreen = Color(0xFF22C55E);

/// 큰 숫자(안드로이드 기본 Roboto Condensed)
TextStyle numStyle(double size) => TextStyle(
      fontFamily: 'sans-serif-condensed',
      fontSize: size,
      fontWeight: FontWeight.w900,
      height: 1.0,
      letterSpacing: -0.5,
      color: ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

const labelStyle = TextStyle(
  fontSize: 12.5,
  color: muted,
  letterSpacing: 2,
  fontWeight: FontWeight.w500,
);

/// 숫자 + 아래 작은 라벨
class Stat extends StatelessWidget {
  final String value;
  final String label;
  final double size;
  final CrossAxisAlignment align;

  const Stat(this.value, this.label,
      {super.key, this.size = 40, this.align = CrossAxisAlignment.center});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
            fit: BoxFit.scaleDown, child: Text(value, style: numStyle(size))),
        const SizedBox(height: 6),
        FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, style: labelStyle, maxLines: 1)),
      ],
    );
  }
}

/// 결과 화면 목록 한 줄
class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const InfoRow(this.icon, this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: line))),
      child: Row(children: [
        Icon(icon, size: 26, color: ink),
        const SizedBox(width: 18),
        Text(label,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 17)),
      ]),
    );
  }
}

IconData activityIcon(ActivityType t) =>
    t == ActivityType.running ? Icons.directions_run : Icons.hiking;

final _dateFmt = DateFormat('M월 d일 (E)', 'ko');
final _timeFmt = DateFormat('a h:mm', 'ko');

String dateLabel(DateTime d) => _dateFmt.format(d);
String timeLabel(DateTime d) => _timeFmt.format(d);

String km(double meters, {int digits = 2}) =>
    (meters / 1000).toStringAsFixed(digits);
