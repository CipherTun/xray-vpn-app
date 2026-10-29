import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models.dart';
import '../services/infra.dart';
import '../services/native_vpn.dart';
import '../services/ssh_tunnel.dart';
import '../services/xray_config.dart';

final tabProvider = StateProvider<int>((ref) => 0);

// ---------------------------------------------------------------- settings

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) => SettingsNotifier());

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(AppSettings.load());

  void set(String key, dynamic value) {
    state = state.set(key, value);
    state.save();
  }
}

// ----------------------------------------------------------------- configs

class ConfigsState {
  const ConfigsState({this.items = const [], this.selected, this.pings = const {}});
  final List<ServerConfig> items;
  final String? selected;
  final Map<String, int> pings;

  ServerConfig? get selectedConfig {
    for (final c in items) {
      if (c.id == selected) return c;
    }
    return items.isEmpty ? null : items.first;
  }

  ConfigsState copyWith({List<ServerConfig>? items, String? selected, Map<String, int>? pings}) =>
      ConfigsState(
        items: items ?? this.items,
        selected: selected ?? this.selected,
        pings: pings ?? this.pings,
      );
}

Future<int> tcpPing(String host, int port) async {
  final sw = Stopwatch()..start();
  try {
    final s = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
    s.destroy();
    return sw.elapsedMilliseconds;
  } catch (_) {
    return -1;
  }
}

final configsProvider =
    StateNotifierProvider<ConfigsNotifier, ConfigsState>((ref) => ConfigsNotifier());

class ConfigsNotifier extends StateNotifier<ConfigsState> {
  ConfigsNotifier() : super(_load());

  static ConfigsState _load() {
    final raw = Storage.prefs.getString('configs');
    if (raw == null) return const ConfigsState();
    try {
      final l = (jsonDecode(raw) as List)
          .map((e) => ServerConfig.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      return ConfigsState(items: l, selected: Storage.prefs.getString('selected'));
    } catch (_) {
      return const ConfigsState();
    }
  }

  void _save() {
    Storage.prefs.setString('configs', jsonEncode(state.items.map((e) => e.toJson()).toList()));
    final sel = state.selected;
    if (sel != null) Storage.prefs.setString('selected', sel);
  }

  void select(String id) {
    state = state.copyWith(selected: id);
    _save();
  }

  void add(ServerConfig c) {
    state = state.copyWith(items: [...state.items, c], selected: state.selected ?? c.id);
    _save();
  }

  void remove(String id) {
    final items = state.items.where((e) => e.id != id).toList();
    final sel = state.selected == id ? (items.isEmpty ? null : items.first.id) : state.selected;
    state = ConfigsState(items: items, selected: sel, pings: state.pings);
    _save();
  }

  Future<void> ping(ServerConfig c) async {
    final ms = await tcpPing(c.address, c.portNum);
    state = state.copyWith(pings: {...state.pings, c.id: ms});
  }

  Future<void> pingAll() async {
    await Future.wait(state.items.map(ping));
  }

  /// Accepts share links (vless/vmess/trojan/ss/socks/hysteria2), base64 or plain subscription
  /// text, a subscription URL, Xray JSON nodes, or an ssh://user:pass@host:port#name URI.
  Future<int> importText(String raw) async {
    var text = raw.trim();
    if (text.isEmpty) throw 'Nothing to import';
    final added = <ServerConfig>[];

    if (text.toLowerCase().startsWith('ssh://')) {
      final u = Uri.parse(text);
      if (u.host.isEmpty) throw 'Invalid ssh:// link';
      final ui = u.userInfo.split(':');
      added.add(ServerConfig(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        name: u.fragment.isEmpty ? 'SSH ${u.host}' : Uri.decodeComponent(u.fragment),
        kind: ConfigKind.ssh,
        host: u.host,
        port: u.hasPort ? u.port : 22,
        user: Uri.decodeComponent(ui.first),
        password: ui.length > 1 ? Uri.decodeComponent(ui.sublist(1).join(':')) : '',
      ));
    } else {
      if (RegExp(r'^https?://', caseSensitive: false).hasMatch(text) && !text.contains('\n')) {
        text = await _fetch(text);
      }
      final data = await NativeVpn.core('convertShareLinksToXrayJson', {'text': text});
      final outs = data is Map ? data['outbounds'] : null;
      if (outs is! List || outs.isEmpty) throw 'No usable servers found';
      for (var i = 0; i < outs.length; i++) {
        added.add(ServerConfig.fromOutbound(Map<String, dynamic>.from(outs[i] as Map), i));
      }
    }

    state = state.copyWith(items: [...state.items, ...added], selected: state.selected ?? added.first.id);
    _save();
    AppLog.i('Imported ${added.length} config(s)');
    return added.length;
  }

  Future<String> _fetch(String url) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await c.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'XRayVPN/1.0');
      final res = await req.close();
      if (res.statusCode != 200) throw 'Subscription HTTP ${res.statusCode}';
      return await utf8.decodeStream(res);
    } finally {
      c.close(force: true);
    }
  }
}

// --------------------------------------------------------------------- VPN

enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

class VpnState {
  const VpnState({
    this.status = VpnStatus.disconnected,
    this.error,
    this.since,
    this.up = 0,
    this.down = 0,
    this.upSpeed = 0,
    this.downSpeed = 0,
  });
  final VpnStatus status;
  final String? error;
  final DateTime? since;
  final int up, down, upSpeed, downSpeed;
}

final vpnProvider = StateNotifierProvider<VpnController, VpnState>((ref) => VpnController(ref));

class VpnController extends StateNotifier<VpnState> {
  VpnController(this._ref) : super(const VpnState()) {
    _sub = NativeVpn.states.listen(_onEvent, onError: (_) {});
    _ssh.onClosed = () {
      AppLog.e('SSH tunnel dropped - disconnecting');
      disconnect();
    };
  }

  final Ref _ref;
  final SshTunnel _ssh = SshTunnel();
  StreamSubscription<String>? _sub;
  Timer? _timer;
  int _lastUp = 0, _lastDown = 0;

  void _onEvent(String e) {
    if (e == 'connected') {
      state = VpnState(status: VpnStatus.connected, since: DateTime.now());
      _startStats();
      AppLog.i('VPN connected (TUN)');
    } else if (e == 'connecting') {
      if (state.status != VpnStatus.connecting) state = const VpnState(status: VpnStatus.connecting);
    } else if (e == 'disconnected') {
      _cleanup();
      if (state.status != VpnStatus.error) state = const VpnState();
      AppLog.i('VPN disconnected');
    } else if (e.startsWith('error:')) {
      _cleanup();
      final msg = e.substring(6);
      state = VpnState(status: VpnStatus.error, error: msg);
      AppLog.e('VPN error: $msg');
    }
  }

  Future<void> connect() async {
    if (state.status == VpnStatus.connecting || state.status == VpnStatus.connected) return;
    final cfg = _ref.read(configsProvider).selectedConfig;
    if (cfg == null) {
      state = const VpnState(status: VpnStatus.error, error: 'Add or select a config first');
      return;
    }
    final s = _ref.read(settingsProvider);
    state = const VpnState(status: VpnStatus.connecting);
    AppLog.i('Connecting: ${cfg.name} (${cfg.protocol})');
    try {
      try {
        await Permission.notification.request();
      } catch (_) {}
      if (!await NativeVpn.prepare()) throw 'VPN permission was not granted';

      Map<String, dynamic> outbound;
      if (cfg.kind == ConfigKind.ssh) {
        await _ssh.start(cfg, s.sshPort, s.sshKeepAlive);
        outbound = socksOutbound(s.sshPort);
      } else {
        outbound = Map<String, dynamic>.from(cfg.outbound!);
      }

      try {
        await File(AppPaths.coreLog).writeAsString('');
      } catch (_) {}

      final json = buildXrayConfig(outbound: outbound, s: s);
      await NativeVpn.start({
        'config': jsonEncode(json),
        'mtu': s.mtu,
        'dns': '1.1.1.1',
        'perApp': s.perApp,
        'apps': s.apps,
      });
    } catch (e) {
      await _ssh.stop();
      state = VpnState(status: VpnStatus.error, error: '$e');
      AppLog.e('Connect failed: $e');
    }
  }

  Future<void> disconnect() async {
    if (state.status == VpnStatus.disconnected) return;
    state = VpnState(status: VpnStatus.disconnecting, since: state.since);
    try {
      await NativeVpn.stop();
    } catch (e) {
      AppLog.e('$e');
      _cleanup();
      state = const VpnState();
    }
  }

  void _cleanup() {
    _timer?.cancel();
    _timer = null;
    _lastUp = 0;
    _lastDown = 0;
    _ssh.stop();
  }

  void _startStats() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final t = await _readStats();
      if (t == null || state.status != VpnStatus.connected) return;
      final upS = _lastUp == 0 ? 0 : (t[0] - _lastUp).clamp(0, 1 << 40).toInt();
      final dnS = _lastDown == 0 ? 0 : (t[1] - _lastDown).clamp(0, 1 << 40).toInt();
      _lastUp = t[0];
      _lastDown = t[1];
      state = VpnState(
        status: VpnStatus.connected,
        since: state.since,
        up: t[0],
        down: t[1],
        upSpeed: upS,
        downSpeed: dnS,
      );
    });
  }

  /// Reads Xray's expvar metrics: stats.outbound.proxy.{uplink,downlink}. Returns [up, down].
  Future<List<int>?> _readStats() async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final req = await c.getUrl(Uri.parse('http://127.0.0.1:$metricsPort/debug/vars'));
      final res = await req.close();
      final j = jsonDecode(await utf8.decodeStream(res));
      final p = j['stats']?['outbound']?['proxy'];
      if (p is! Map) return null;
      return [(p['uplink'] ?? 0) as int, (p['downlink'] ?? 0) as int];
    } catch (_) {
      return null;
    } finally {
      c.close(force: true);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}
