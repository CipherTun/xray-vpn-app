import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/services/native_vpn.dart';
import '../core/state/providers.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/glass.dart';
import '../core/utils.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = XPalette.of(context);
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);

    Widget sw(bool v, String key) => Switch(value: v, onChanged: (x) => n.set(key, x));

    return GlassPage(
      title: 'Settings',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          SettingsGroup(title: 'Appearance', children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('System'), icon: Icon(Icons.brightness_auto_rounded)),
                  ButtonSegment(value: 1, label: Text('Light'), icon: Icon(Icons.light_mode_rounded)),
                  ButtonSegment(value: 2, label: Text('Dark'), icon: Icon(Icons.dark_mode_rounded)),
                ],
                selected: {s.themeMode.index},
                onSelectionChanged: (v) => n.set('theme', v.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Accent', style: TextStyle(color: p.text, fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 12),
                Wrap(spacing: 14, runSpacing: 12, children: [
                  for (final id in AccentId.values)
                    _Swatch(
                      id: id,
                      custom: s.customAccent,
                      selected: s.accent == id,
                      onTap: () async {
                        if (id == AccentId.custom) {
                          final c = await showDialog<Color>(
                            context: context,
                            builder: (_) => _CustomAccentDialog(initial: Color(s.customAccent)),
                          );
                          if (c != null) {
                            n.set('custom', c.toARGB32());
                            n.set('accent', id.index);
                          }
                        } else {
                          n.set('accent', id.index);
                        }
                      },
                    ),
                ]),
              ]),
            ),
            SettingRow(
              icon: Icons.blur_on_rounded,
              title: 'Glass blur',
              subtitle: 'Frosted backdrop blur on cards and bars',
              trailing: sw(s.blur, 'blur'),
            ),
          ]),
          SettingsGroup(title: 'Tunneling', children: [
            SettingRow(
              icon: Icons.hub_rounded,
              title: 'Routing mode',
              subtitle: 'System TUN via VpnService, handled by Xray-core',
              trailing: _Pill('TUN'),
            ),
            SettingRow(
              icon: Icons.straighten_rounded,
              title: 'MTU',
              trailing: _Pill('${s.mtu}'),
              onTap: () async {
                final v = await _pick<int>(context, 'MTU', const [1280, 1380, 1400, 1450, 1500], s.mtu, (e) => '$e');
                if (v != null) n.set('mtu', v);
              },
            ),
            SettingRow(
              icon: Icons.language_rounded,
              title: 'IPv6 DNS answers',
              subtitle: 'IPv6 traffic is always routed through the tunnel (no leaks)',
              trailing: sw(s.ipv6, 'ipv6'),
            ),
            SettingRow(
              icon: Icons.router_rounded,
              title: 'Bypass LAN',
              subtitle: 'Private ranges go direct',
              trailing: sw(s.bypassLan, 'bypassLan'),
            ),
            SettingRow(
              icon: Icons.manage_search_rounded,
              title: 'Traffic sniffing',
              subtitle: 'Detect domains from HTTP / TLS / QUIC for routing',
              trailing: sw(s.sniffing, 'sniffing'),
            ),
            SettingRow(
              icon: Icons.merge_type_rounded,
              title: 'Mux',
              subtitle: 'Multiplex connections (VMess / VLESS / Trojan / SS)',
              trailing: sw(s.mux, 'mux'),
            ),
            SettingRow(
              icon: Icons.dns_rounded,
              title: 'Remote DNS',
              subtitle: s.remoteDns,
              onTap: () async {
                final v = await _askText(context, 'Remote DNS', s.remoteDns);
                if (v != null && v.isNotEmpty) n.set('remoteDns', v);
              },
            ),
            SettingRow(
              icon: Icons.flag_rounded,
              title: 'Region bypass',
              subtitle: 'Send a country direct. Needs geo files (Tools).',
              trailing: _Pill(s.geoBypass == 'none' ? 'Off' : s.geoBypass.toUpperCase()),
              onTap: () async {
                final v = await _pick<String>(context, 'Region bypass', const ['none', 'cn', 'ir', 'ru'], s.geoBypass,
                    (e) => e == 'none' ? 'Off' : e.toUpperCase());
                if (v != null) n.set('geoBypass', v);
              },
            ),
            SettingRow(
              icon: Icons.apps_rounded,
              title: 'Per-app VPN',
              subtitle: 'Only selected apps use the tunnel',
              trailing: sw(s.perApp, 'perApp'),
            ),
            if (s.perApp)
              SettingRow(
                icon: Icons.checklist_rounded,
                title: 'Select apps',
                subtitle: '${s.apps.length} selected',
                trailing: Icon(Icons.chevron_right_rounded, color: p.dim),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AppPickerPage())),
              ),
          ]),
          SettingsGroup(title: 'SSH tunnel (DartSSH2)', children: [
            SettingRow(
              icon: Icons.favorite_rounded,
              title: 'Keep-alive',
              trailing: _Pill('${s.sshKeepAlive}s'),
              onTap: () async {
                final v = await _pick<int>(context, 'Keep-alive (seconds)', const [10, 15, 30, 60], s.sshKeepAlive, (e) => '${e}s');
                if (v != null) n.set('sshKeepAlive', v);
              },
            ),
            SettingRow(
              icon: Icons.settings_ethernet_rounded,
              title: 'Local SOCKS port',
              trailing: _Pill('${s.sshPort}'),
              onTap: () async {
                final v = await _askText(context, 'Local SOCKS port', '${s.sshPort}');
                final port = int.tryParse(v ?? '');
                if (port != null && port > 1023 && port < 65536) n.set('sshPort', port);
              },
            ),
          ]),
          SettingsGroup(title: 'Core', children: [
            SettingRow(
              icon: Icons.bug_report_rounded,
              title: 'Log level',
              trailing: _Pill(s.logLevel),
              onTap: () async {
                final v = await _pick<String>(context, 'Log level', const ['debug', 'info', 'warning', 'error', 'none'], s.logLevel, (e) => e);
                if (v != null) n.set('logLevel', v);
              },
            ),
            SettingRow(
              icon: Icons.http_rounded,
              title: 'Local HTTP proxy port',
              subtitle: 'Used by Tools while connected (127.0.0.1 only)',
              trailing: _Pill('${s.httpPort}'),
              onTap: () async {
                final v = await _askText(context, 'HTTP port', '${s.httpPort}');
                final port = int.tryParse(v ?? '');
                if (port != null && port > 1023 && port < 65536) n.set('httpPort', port);
              },
            ),
          ]),
          SettingsGroup(title: 'System', children: [
            SettingRow(
              icon: Icons.gpp_good_rounded,
              title: 'Always-on VPN & kill switch',
              subtitle: 'Opens Android VPN settings',
              trailing: Icon(Icons.open_in_new_rounded, color: p.dim, size: 18),
              onTap: () => NativeVpn.openVpnSettings(),
            ),
          ]),
          SettingsGroup(title: 'About', children: [
            const SettingRow(icon: Icons.info_outline_rounded, title: 'XRay VPN', subtitle: 'io.surprise.vpn'),
            SettingRow(
              icon: Icons.memory_rounded,
              title: 'Xray-core',
              trailing: FutureBuilder<dynamic>(
                future: NativeVpn.core('xrayVersion'),
                builder: (_, snap) {
                  final d = snap.data;
                  final text = snap.hasError
                      ? 'unavailable'
                      : d == null
                          ? '...'
                          : (d is Map ? (d['version'] ?? d.toString()).toString() : d.toString());
                  return Text(text, style: TextStyle(color: p.dim, fontSize: 13));
                },
              ),
            ),
            SettingRow(icon: Icons.terminal_rounded, title: 'DartSSH2', trailing: Text('2.18.0', style: TextStyle(color: p.dim, fontSize: 13))),
          ]),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final p = XPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: p.accent.op(0.14), borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(color: p.accent, fontWeight: FontWeight.w700, fontSize: 12.5)),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.id, required this.custom, required this.selected, required this.onTap});
  final AccentId id;
  final int custom;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = XPalette.of(context);
    final c = Accents.swatch(id, custom);
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: id == AccentId.custom
                ? const SweepGradient(colors: [Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Colors.purple, Colors.red])
                : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c, c.op(0.7)]),
            border: Border.all(color: selected ? p.text : p.border, width: selected ? 2.5 : 1),
          ),
          child: selected
              ? Icon(Icons.check_rounded, color: ThemeData.estimateBrightnessForColor(c) == Brightness.dark ? Colors.white : Colors.black, size: 22)
              : (id == AccentId.custom ? const Icon(Icons.colorize_rounded, color: Colors.white, size: 20) : null),
        ),
        const SizedBox(height: 5),
        Text(Accents.names[id]!, style: TextStyle(color: selected ? p.text : p.dim, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _CustomAccentDialog extends StatefulWidget {
  const _CustomAccentDialog({required this.initial});
  final Color initial;
  @override
  State<_CustomAccentDialog> createState() => _CustomAccentDialogState();
}

class _CustomAccentDialogState extends State<_CustomAccentDialog> {
  late HSVColor hsv = HSVColor.fromColor(widget.initial);

  @override
  Widget build(BuildContext context) {
    final color = hsv.toColor();
    return AlertDialog(
      title: const Text('Custom accent'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(colors: [color, color.op(0.65)]),
          ),
        ),
        const SizedBox(height: 12),
        _slider('Hue', hsv.hue, 360, (v) => setState(() => hsv = hsv.withHue(v))),
        _slider('Saturation', hsv.saturation, 1, (v) => setState(() => hsv = hsv.withSaturation(v))),
        _slider('Brightness', hsv.value, 1, (v) => setState(() => hsv = hsv.withValue(v))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, color), child: const Text('Apply')),
      ],
    );
  }

  Widget _slider(String label, double v, double max, ValueChanged<double> cb) => Row(children: [
        SizedBox(width: 82, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(child: Slider(value: v.clamp(0, max).toDouble(), max: max, onChanged: cb)),
      ]);
}

Future<T?> _pick<T>(BuildContext context, String title, List<T> options, T current, String Function(T) label) {
  return showDialog<T>(
    context: context,
    builder: (_) => SimpleDialog(
      title: Text(title),
      children: [
        for (final o in options)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, o),
            child: Row(children: [
              Expanded(child: Text(label(o))),
              if (o == current) const Icon(Icons.check_rounded, size: 18),
            ]),
          ),
      ],
    ),
  );
}

Future<String?> _askText(BuildContext context, String title, String initial) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Save')),
      ],
    ),
  );
}

class AppPickerPage extends ConsumerStatefulWidget {
  const AppPickerPage({super.key});
  @override
  ConsumerState<AppPickerPage> createState() => _AppPickerPageState();
}

class _AppPickerPageState extends ConsumerState<AppPickerPage> {
  late final Future<List<Map<String, dynamic>>> _apps = NativeVpn.apps();
  String q = '';
  bool showSystem = false;

  @override
  Widget build(BuildContext context) {
    final p = XPalette.of(context);
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    return GlassPage(
      title: 'Select apps',
      actions: [
        CircleIcon(icon: showSystem ? Icons.visibility_rounded : Icons.visibility_off_rounded, onTap: () => setState(() => showSystem = !showSystem)),
      ],
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: TextField(
            onChanged: (v) => setState(() => q = v.toLowerCase()),
            style: TextStyle(color: p.text),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search_rounded, color: p.dim),
              hintText: 'Search apps',
              hintStyle: TextStyle(color: p.dim),
              filled: true,
              fillColor: p.glass.op(p.dark ? 0.06 : 0.5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: p.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: p.border)),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _apps,
            builder: (_, snap) {
              if (snap.hasError) return Center(child: Text('${snap.error}', style: TextStyle(color: p.danger)));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final list = snap.data!
                  .where((a) => (showSystem || a['system'] != true) &&
                      ((a['label'] as String).toLowerCase().contains(q) || (a['package'] as String).contains(q)))
                  .toList();
              final selected = s.apps.toSet();
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final a = list[i];
                  final pkg = a['package'] as String;
                  final on = selected.contains(pkg);
                  return CheckboxListTile(
                    value: on,
                    activeColor: p.accent,
                    checkColor: p.onAccent,
                    title: Text(a['label'] as String, style: TextStyle(color: p.text, fontWeight: FontWeight.w600)),
                    subtitle: Text(pkg, style: TextStyle(color: p.dim, fontSize: 11.5)),
                    onChanged: (v) {
                      final next = {...selected};
                      v == true ? next.add(pkg) : next.remove(pkg);
                      n.set('apps', next.toList());
                    },
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
