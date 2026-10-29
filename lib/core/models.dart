import 'dart:convert';

import 'package:flutter/material.dart';

import 'services/infra.dart';

enum AccentId { turquoise, blue, black, green, pink, teal, custom }

/// Map-backed settings with typed getters; every key has a default.
class AppSettings {
  const AppSettings(this._m);
  final Map<String, dynamic> _m;

  static const _d = <String, dynamic>{
    'theme': 2,
    'accent': 0,
    'custom': 0xFF9B7BFF,
    'blur': true,
    'mtu': 1500,
    'ipv6': false,
    'bypassLan': true,
    'sniffing': true,
    'mux': false,
    'remoteDns': 'https://1.1.1.1/dns-query',
    'geoBypass': 'none',
    'logLevel': 'warning',
    'httpPort': 10809,
    'sshPort': 10808,
    'sshKeepAlive': 15,
    'perApp': false,
    'apps': <String>[],
  };

  dynamic _g(String k) => _m[k] ?? _d[k];
  AppSettings set(String k, dynamic v) => AppSettings({..._m, k: v});

  ThemeMode get themeMode => ThemeMode.values[(_g('theme') as int).clamp(0, 2).toInt()];
  AccentId get accent =>
      AccentId.values[(_g('accent') as int).clamp(0, AccentId.values.length - 1).toInt()];
  int get customAccent => _g('custom') as int;
  bool get blur => _g('blur') as bool;
  int get mtu => _g('mtu') as int;
  bool get ipv6 => _g('ipv6') as bool;
  bool get bypassLan => _g('bypassLan') as bool;
  bool get sniffing => _g('sniffing') as bool;
  bool get mux => _g('mux') as bool;
  String get remoteDns => _g('remoteDns') as String;
  String get geoBypass => _g('geoBypass') as String;
  String get logLevel => _g('logLevel') as String;
  int get httpPort => _g('httpPort') as int;
  int get sshPort => _g('sshPort') as int;
  int get sshKeepAlive => _g('sshKeepAlive') as int;
  bool get perApp => _g('perApp') as bool;
  List<String> get apps => List<String>.from(_g('apps') as List);

  static AppSettings load() {
    final raw = Storage.prefs.getString('settings');
    if (raw == null) return const AppSettings({});
    try {
      return AppSettings(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const AppSettings({});
    }
  }

  Future<void> save() => Storage.prefs.setString('settings', jsonEncode(_m));
}

enum ConfigKind { xray, ssh }

class ServerConfig {
  ServerConfig({
    required this.id,
    required this.name,
    required this.kind,
    this.outbound,
    this.host,
    this.port,
    this.user,
    this.password,
    this.privateKey,
    this.passphrase,
  });

  final String id;
  final String name;
  final ConfigKind kind;
  final Map<String, dynamic>? outbound; // Xray outbound (from libXray share-link parser)
  final String? host; // SSH
  final int? port;
  final String? user;
  final String? password;
  final String? privateKey;
  final String? passphrase;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'outbound': outbound,
        'host': host,
        'port': port,
        'user': user,
        'password': password,
        'privateKey': privateKey,
        'passphrase': passphrase,
      };

  static ServerConfig fromJson(Map<String, dynamic> j) => ServerConfig(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: j['kind'] == 'ssh' ? ConfigKind.ssh : ConfigKind.xray,
        outbound: j['outbound'] == null ? null : Map<String, dynamic>.from(j['outbound'] as Map),
        host: j['host'] as String?,
        port: j['port'] as int?,
        user: j['user'] as String?,
        password: j['password'] as String?,
        privateKey: j['privateKey'] as String?,
        passphrase: j['passphrase'] as String?,
      );

  static ServerConfig fromOutbound(Map<String, dynamic> o, int idx) {
    final probe = ServerConfig(id: '', name: '', kind: ConfigKind.xray, outbound: o);
    final tag = (o['tag'] ?? '').toString();
    final name = (tag.isNotEmpty && tag != 'proxy')
        ? tag
        : '${probe.protocol.toUpperCase()} ${probe.address}';
    return ServerConfig(
      id: '${DateTime.now().microsecondsSinceEpoch}$idx',
      name: name,
      kind: ConfigKind.xray,
      outbound: o,
    );
  }

  Map<String, dynamic>? get _firstServer {
    final s = outbound?['settings'];
    if (s is Map) {
      final v = s['vnext'] ?? s['servers'];
      if (v is List && v.isNotEmpty && v.first is Map) return Map<String, dynamic>.from(v.first as Map);
      return Map<String, dynamic>.from(s);
    }
    return null;
  }

  String get protocol => kind == ConfigKind.ssh ? 'ssh' : (outbound?['protocol'] ?? 'xray').toString();

  String get address =>
      kind == ConfigKind.ssh ? (host ?? '') : (_firstServer?['address'] ?? '').toString();

  int get portNum =>
      kind == ConfigKind.ssh ? (port ?? 22) : int.tryParse('${_firstServer?['port']}') ?? 443;

  String get transport {
    final ss = outbound?['streamSettings'];
    if (ss is Map) {
      final n = ss['network'] ?? 'tcp';
      final sec = ss['security'];
      return sec == null || sec == 'none' ? '$n' : '$n+$sec';
    }
    return kind == ConfigKind.ssh ? 'tunnel' : '';
  }
}
