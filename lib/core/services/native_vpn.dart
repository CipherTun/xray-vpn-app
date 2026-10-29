import 'dart:convert';

import 'package:flutter/services.dart';

/// Platform bridge. Android: MainActivity/XrayVpnService. iOS: see native/ios.
class NativeVpn {
  static const _m = MethodChannel('io.surprise.vpn/vpn');
  static const _e = EventChannel('io.surprise.vpn/state');

  static Stream<String> get states => _e.receiveBroadcastStream().map((e) => e.toString());

  static Future<bool> prepare() async => (await _m.invokeMethod<bool>('prepare')) ?? false;

  static Future<void> start(Map<String, dynamic> args) => _m.invokeMethod('start', args);

  static Future<void> stop() => _m.invokeMethod('stop');

  static Future<void> openVpnSettings() => _m.invokeMethod('openVpnSettings');

  static Future<List<Map<String, dynamic>>> apps() async {
    final l = await _m.invokeMethod<List<dynamic>>('apps') ?? [];
    return l.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Calls a libXray method (apiVersion 3). Returns `data`; throws the core's error string.
  static Future<dynamic> core(String method, [Map<String, dynamic> payload = const {}]) async {
    final raw = await _m.invokeMethod<String>(
      'invoke',
      jsonEncode({'apiVersion': 3, 'method': method, 'payload': payload}),
    );
    final j = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
    if (j['success'] != true) throw (j['error'] ?? 'core error').toString();
    return j['data'];
  }
}
