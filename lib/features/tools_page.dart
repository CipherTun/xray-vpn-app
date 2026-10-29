import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/infra.dart';
import '../core/services/native_vpn.dart';
import '../core/state/providers.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/glass.dart';
import '../core/utils.dart';

class ToolsPage extends ConsumerStatefulWidget {
  const ToolsPage({super.key});
  @override
  ConsumerState<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends ConsumerState<ToolsPage> {
  String? ipResult;
  bool ipBusy = false;
  String? speedResult;
  bool speedBusy = false;
  String? geoResult;
  bool geoBusy = false;

  /// HTTP client that goes through the tunnel (Xray's local HTTP inbound) when connected.
  HttpClient _client() {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    if (ref.read(vpnProvider).status == VpnStatus.connected) {
      final port = ref.read(settingsProvider).httpPort;
      c.findProxy = (_) => 'PROXY 127.0.0.1:$port';
    }
    return c;
  }

  Future<void> _ip() async {
    setState(() => ipBusy = true);
    final c = _client();
    try {
      final req = await c.getUrl(Uri.parse('https://ipwho.is/'));
      final res = await req.close();
      final j = jsonDecode(await utf8.decodeStream(res)) as Map<String, dynamic>;
      final isp = (j['connection'] is Map) ? (j['connection']['isp'] ?? '') : '';
      ipResult = '${j['ip']}\n${j['city'] ?? ''}, ${j['country'] ?? ''}\n$isp';
    } catch (e) {
      ipResult = 'Failed: $e';
    } finally {
      c.close(force: true);
    }
    if (mounted) setState(() => ipBusy = false);
  }

  Future<void> _speed() async {
    setState(() {
      speedBusy = true;
      speedResult = 'Running...';
    });
    final c = _client();
    try {
      final req = await c.getUrl(Uri.parse('https://speed.cloudflare.com/__down?bytes=50000000'));
      final res = await req.close();
      final sw = Stopwatch()..start();
      var bytes = 0;
      await for (final chunk in res) {
        bytes += chunk.length;
        if (sw.elapsedMilliseconds > 8000) break;
      }
      final secs = sw.elapsedMilliseconds / 1000;
      final mbps = bytes * 8 / secs / 1e6;
      speedResult = '${mbps.toStringAsFixed(1)} Mbit/s  (${fmtBytes(bytes)} in ${secs.toStringAsFixed(1)} s)';
    } catch (e) {
      speedResult = 'Failed: $e';
    } finally {
      c.close(force: true);
    }
    if (mounted) setState(() => speedBusy = false);
  }

  Future<void> _geo() async {
    setState(() {
      geoBusy = true;
      geoResult = 'Downloading...';
    });
    final c = _client();
    try {
      for (final name in ['geoip.dat', 'geosite.dat']) {
        final url = 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/$name';
        final req = await c.getUrl(Uri.parse(url));
        final res = await req.close();
        if (res.statusCode != 200) throw '$name: HTTP ${res.statusCode}';
        final tmp = File('${AppPaths.geoDir}/$name.part');
        await res.pipe(tmp.openWrite());
        await tmp.rename('${AppPaths.geoDir}/$name');
      }
      final a = File('${AppPaths.geoDir}/geoip.dat').lengthSync();
      final b = File('${AppPaths.geoDir}/geosite.dat').lengthSync();
      geoResult = 'Updated: geoip ${fmtBytes(a)}, geosite ${fmtBytes(b)}';
      AppLog.i('Geo files updated');
    } catch (e) {
      geoResult = 'Failed: $e';
    } finally {
      c.close(force: true);
    }
    if (mounted) setState(() => geoBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = XPalette.of(context);
    final n = ref.read(configsProvider.notifier);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text('Tools', style: TextStyle(color: p.text, fontSize: 26, fontWeight: FontWeight.w800)),
          ),
          _Tool(
            icon: Icons.public_rounded,
            title: 'IP & location',
            subtitle: 'Checks the address websites see (through the tunnel when connected).',
            result: ipResult,
            busy: ipBusy,
            action: 'Check',
            onTap: _ip,
          ),
          _Tool(
            icon: Icons.speed_rounded,
            title: 'Speed test',
            subtitle: 'Downloads from Cloudflare for up to 8 seconds.',
            result: speedResult,
            busy: speedBusy,
            action: 'Start',
            onTap: _speed,
          ),
          _Tool(
            icon: Icons.network_ping_rounded,
            title: 'Latency (all configs)',
            subtitle: 'TCP connect time to every saved server.',
            action: 'Test',
            onTap: () async {
              await n.pingAll();
              if (context.mounted) ref.read(tabProvider.notifier).state = 1;
            },
          ),
          _Tool(
            icon: Icons.travel_explore_rounded,
            title: 'Update geo files',
            subtitle: 'geoip.dat / geosite.dat for region bypass (Settings > Tunneling).',
            result: geoResult ?? (AppPaths.hasGeo ? 'Geo files installed' : 'Not installed'),
            busy: geoBusy,
            action: 'Update',
            onTap: _geo,
          ),
          _Tool(
            icon: Icons.gpp_good_rounded,
            title: 'Always-on VPN / Block without VPN',
            subtitle: 'Opens Android VPN settings. Enable "Always-on VPN" and "Block connections without VPN" on XRay VPN for a kill switch.',
            action: 'Open',
            onTap: () => NativeVpn.openVpnSettings(),
          ),
        ],
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
    this.result,
    this.busy = false,
  });
  final IconData icon;
  final String title, subtitle, action;
  final String? result;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = XPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Glass(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: p.accent.op(0.16), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: p.accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(color: p.text, fontWeight: FontWeight.w700, fontSize: 15.5)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: p.dim, fontSize: 12.5)),
              ]),
            ),
          ]),
          if (result != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.accent.op(0.08), borderRadius: BorderRadius.circular(14)),
              child: Text(result!, style: TextStyle(color: p.text, fontSize: 13, height: 1.4)),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: AccentButton(label: action, busy: busy, onTap: onTap),
          ),
        ]),
      ),
    );
  }
}
