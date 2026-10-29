import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Storage {
  static late SharedPreferences prefs;
  static Future<void> init() async => prefs = await SharedPreferences.getInstance();
}

class AppPaths {
  static late String support;
  static String get geoDir => '$support/geo';
  static String get coreLog => '$support/core.log';

  static Future<void> init() async {
    final d = await getApplicationSupportDirectory();
    support = d.path;
    await Directory(geoDir).create(recursive: true);
  }

  static bool get hasGeo =>
      File('$geoDir/geoip.dat').existsSync() && File('$geoDir/geosite.dat').existsSync();
}

/// In-app log ring buffer (shown on the Logs page, "App" tab).
class AppLog extends ChangeNotifier {
  AppLog._();
  static final AppLog I = AppLog._();

  final List<String> lines = [];

  void _add(String level, String msg) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    lines.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)} [$level] $msg');
    if (lines.length > 600) lines.removeRange(0, lines.length - 600);
    notifyListeners();
  }

  static void i(String m) => I._add('I', m);
  static void e(String m) => I._add('E', m);

  void clear() {
    lines.clear();
    notifyListeners();
  }
}
