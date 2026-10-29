import 'package:flutter/material.dart';

String fmtBytes(num b) {
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  double v = b.toDouble();
  int i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  final digits = i == 0 ? 0 : (v < 10 ? 2 : 1);
  return '${v.toStringAsFixed(digits)} ${u[i]}';
}

String fmtSpeed(num bytesPerSec) => '${fmtBytes(bytesPerSec)}/s';

String fmtDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  return '${two(h)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

extension ColorOpacity on Color {
  /// Alpha-scaled copy (o in 0..1). Named `op` to avoid clashing with Color.a.
  Color op(double o) => withAlpha((o * 255).round().clamp(0, 255));
}
