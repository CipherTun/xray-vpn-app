import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/state/providers.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/glass.dart';
import '../core/utils.dart';
import 'settings_page.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = XPalette.of(context);
    final v = ref.watch(vpnProvider);
    final cs = ref.watch(configsProvider);
    final s = ref.watch(settingsProvider);
    final cfg = cs.selectedConfig;

    final on = v.status == VpnStatus.connected;
    final busy = v.status == VpnStatus.connecting || v.status == VpnStatus.disconnecting;
    final label = switch (v.status) {
      VpnStatus.connected => 'Protected',
      VpnStatus.connecting => 'Connecting...',
      VpnStatus.disconnecting => 'Disconnecting...',
      VpnStatus.error => 'Connection failed',
      VpnStatus.disconnected => 'Not connected',
    };

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          Row(children: [
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: 'XRay ', style: TextStyle(color: p.text)),
                TextSpan(text: 'VPN', style: TextStyle(color: p.accent)),
              ]), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
            ),
            CircleIcon(
              icon: Icons.settings_rounded,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
            ),
          ]),
          const SizedBox(height: 34),
          Center(
            child: _PowerButton(
              on: on,
              busy: busy,
              onTap: () {
                final c = ref.read(vpnProvider.notifier);
                if (v.status == VpnStatus.connected) {
                  c.disconnect();
                } else if (v.status == VpnStatus.disconnected || v.status == VpnStatus.error) {
                  c.connect();
                }
              },
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: Text(label,
                style: TextStyle(
                    color: on ? p.ok : (v.status == VpnStatus.error ? p.danger : p.text),
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 4),
          Center(
            child: on && v.since != null
                ? _Uptime(since: v.since!)
                : Text(v.error ?? 'Tap to connect', textAlign: TextAlign.center, style: TextStyle(color: p.dim, fontSize: 13)),
          ),
          const SizedBox(height: 28),
          Row(children: [
            Expanded(child: _Stat(icon: Icons.south_rounded, label: 'Download', speed: fmtSpeed(v.downSpeed), total: fmtBytes(v.down))),
            const SizedBox(width: 12),
            Expanded(child: _Stat(icon: Icons.north_rounded, label: 'Upload', speed: fmtSpeed(v.upSpeed), total: fmtBytes(v.up))),
          ]),
          const SizedBox(height: 12),
          Glass(
            onTap: () => ref.read(tabProvider.notifier).state = 1,
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: p.accent.op(0.16), borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.shield_rounded, color: p.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(cfg?.name ?? 'No config selected',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.text, fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(cfg == null ? 'Open Configs to add one' : '${cfg.protocol.toUpperCase()}  -  ${cfg.address}:${cfg.portNum}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.dim, fontSize: 12.5)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: p.dim),
            ]),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Chip(Icons.hub_rounded, 'TUN mode'),
            _Chip(Icons.alt_route_rounded, s.perApp ? 'Per-app (${s.apps.length})' : 'All apps'),
            _Chip(Icons.dns_rounded, s.ipv6 ? 'IPv4 + IPv6' : 'IPv4 DNS'),
            if (cfg != null && cfg.transport.isNotEmpty) _Chip(Icons.lock_rounded, cfg.transport),
          ]),
        ],
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({required this.on, required this.busy, required this.onTap});
  final bool on, busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = XPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        width: 212,
        height: 212,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: on ? [p.accent, p.accent2] : [p.border, p.border.op(0.25)],
          ),
          boxShadow: on ? [BoxShadow(color: p.accent.op(0.45), blurRadius: 56, spreadRadius: 2)] : const [],
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [p.bg[2], p.bg[0]],
            ),
          ),
          child: Stack(alignment: Alignment.center, children: [
            if (busy)
              SizedBox(width: 150, height: 150, child: CircularProgressIndicator(strokeWidth: 3, color: p.accent)),
            Icon(Icons.power_settings_new_rounded, size: 76, color: on ? p.accent : p.dim),
          ]),
        ),
      ),
    );
  }
}

class _Uptime extends StatefulWidget {
  const _Uptime({required this.since});
  final DateTime since;
  @override
  State<_Uptime> createState() => _UptimeState();
}

class _UptimeState extends State<_Uptime> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = XPalette.of(context);
    return Text(fmtDuration(DateTime.now().difference(widget.since)),
        style: TextStyle(color: p.dim, fontSize: 15, fontFeatures: const [FontFeature.tabularFigures()]));
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.speed, required this.total});
  final IconData icon;
  final String label, speed, total;

  @override
  Widget build(BuildContext context) {
    final p = XPalette.of(context);
    return Glass(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: p.accent),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: p.dim, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        Text(speed, style: TextStyle(color: p.text, fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text('Total $total', style: TextStyle(color: p.dim, fontSize: 12)),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = XPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: p.accent.op(0.12),
        border: Border.all(color: p.accent.op(0.28)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: p.accent),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: p.text, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
