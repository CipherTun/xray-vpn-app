import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/models.dart';
import '../core/state/providers.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/glass.dart';
import '../core/utils.dart';

class ConfigsPage extends ConsumerWidget {
  const ConfigsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = XPalette.of(context);
    final cs = ref.watch(configsProvider);
    final n = ref.read(configsProvider.notifier);

    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(children: [
            Expanded(
              child: Text('Configs', style: TextStyle(color: p.text, fontSize: 26, fontWeight: FontWeight.w800)),
            ),
            CircleIcon(icon: Icons.network_ping_rounded, onTap: () => n.pingAll()),
            const SizedBox(width: 10),
            CircleIcon(icon: Icons.add_rounded, onTap: () => showAddSheet(context, ref)),
          ]),
        ),
        Expanded(
          child: cs.items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.dns_rounded, size: 56, color: p.dim),
                      const SizedBox(height: 14),
                      Text('No configs yet', style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text('Import a vless / vmess / trojan / ss / hysteria2 link, a subscription URL, scan a QR code, or add an SSH server.',
                          textAlign: TextAlign.center, style: TextStyle(color: p.dim, fontSize: 13)),
                      const SizedBox(height: 20),
                      AccentButton(label: 'Add config', icon: Icons.add_rounded, onTap: () => showAddSheet(context, ref)),
                    ]),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                  itemCount: cs.items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final c = cs.items[i];
                    final sel = cs.selectedConfig?.id == c.id;
                    final ping = cs.pings[c.id];
                    return Glass(
                      onTap: () => n.select(c.id),
                      tint: sel ? p.accent : null,
                      child: Row(children: [
                        Icon(sel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                            color: sel ? p.accent : p.dim),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.text, fontWeight: FontWeight.w700, fontSize: 15)),
                            const SizedBox(height: 3),
                            Text('${c.protocol.toUpperCase()}${c.transport.isEmpty ? '' : '  -  ${c.transport}'}  -  ${c.address}:${c.portNum}',
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.dim, fontSize: 12)),
                          ]),
                        ),
                        GestureDetector(
                          onTap: () => n.ping(c),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: p.accent.op(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              ping == null ? 'Ping' : (ping < 0 ? 'x' : '$ping ms'),
                              style: TextStyle(
                                  color: ping == null ? p.dim : (ping < 0 ? p.danger : (ping < 300 ? p.ok : p.text)),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline_rounded, color: p.dim, size: 20),
                          onPressed: () => n.remove(c.id),
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

Future<void> showAddSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => UncontrolledProviderScope(
      container: ProviderScope.containerOf(context),
      child: const _AddSheet(),
    ),
  );
}

class _AddSheet extends ConsumerStatefulWidget {
  const _AddSheet();
  @override
  ConsumerState<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<_AddSheet> {
  int tab = 0;
  bool busy = false;
  final link = TextEditingController();
  final name = TextEditingController();
  final host = TextEditingController();
  final port = TextEditingController(text: '22');
  final user = TextEditingController();
  final pass = TextEditingController();
  final key = TextEditingController();
  final phrase = TextEditingController();

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _import() async {
    setState(() => busy = true);
    try {
      final n = await ref.read(configsProvider.notifier).importText(link.text);
      if (!mounted) return;
      Navigator.pop(context);
      _msg('Imported $n config(s)');
    } catch (e) {
      _msg('Import failed: $e');
      if (mounted) setState(() => busy = false);
    }
  }

  void _addSsh() {
    if (host.text.trim().isEmpty || user.text.trim().isEmpty) {
      _msg('Host and username are required');
      return;
    }
    ref.read(configsProvider.notifier).add(ServerConfig(
          id: '${DateTime.now().microsecondsSinceEpoch}',
          name: name.text.trim().isEmpty ? 'SSH ${host.text.trim()}' : name.text.trim(),
          kind: ConfigKind.ssh,
          host: host.text.trim(),
          port: int.tryParse(port.text.trim()) ?? 22,
          user: user.text.trim(),
          password: pass.text,
          privateKey: key.text.trim().isEmpty ? null : key.text,
          passphrase: phrase.text.isEmpty ? null : phrase.text,
        ));
    Navigator.pop(context);
  }

  Widget _field(TextEditingController c, String label, {bool obscure = false, int lines = 1, TextInputType? type}) {
    final p = XPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        obscureText: obscure,
        minLines: lines,
        maxLines: obscure ? 1 : lines,
        keyboardType: type,
        style: TextStyle(color: p.text, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: p.dim),
          filled: true,
          fillColor: p.glass.op(p.dark ? 0.06 : 0.5),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: p.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: p.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: p.accent)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = XPalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, MediaQuery.of(context).viewInsets.bottom + 12),
      child: Glass(
        radius: 30,
        padding: const EdgeInsets.all(18),
        tint: p.dark ? null : Colors.white,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Add config', style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Link / Subscription'), icon: Icon(Icons.link_rounded)),
                ButtonSegment(value: 1, label: Text('SSH'), icon: Icon(Icons.terminal_rounded)),
              ],
              selected: {tab},
              onSelectionChanged: (s) => setState(() => tab = s.first),
            ),
            const SizedBox(height: 14),
            if (tab == 0) ...[
              _field(link, 'Paste link(s), subscription URL or ssh://user:pass@host:22#name', lines: 4),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                    label: const Text('Paste'),
                    onPressed: () async {
                      final d = await Clipboard.getData('text/plain');
                      if (d?.text != null) setState(() => link.text = d!.text!);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Scan QR'),
                    onPressed: () async {
                      final r = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const QrScanPage()));
                      if (r != null) setState(() => link.text = r);
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Center(child: AccentButton(label: 'Import', icon: Icons.download_rounded, busy: busy, onTap: _import)),
            ] else ...[
              _field(name, 'Name (optional)'),
              Row(children: [
                Expanded(flex: 3, child: _field(host, 'Host')),
                const SizedBox(width: 10),
                Expanded(flex: 1, child: _field(port, 'Port', type: TextInputType.number)),
              ]),
              _field(user, 'Username'),
              _field(pass, 'Password', obscure: true),
              _field(key, 'Private key (PEM, optional)', lines: 3),
              _field(phrase, 'Key passphrase (optional)', obscure: true),
              Center(child: AccentButton(label: 'Add SSH server', icon: Icons.add_rounded, onTap: _addSsh)),
            ],
          ]),
        ),
      ),
    );
  }
}

class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});
  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  bool done = false;

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Scan QR code',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: MobileScanner(
          onDetect: (capture) {
            if (done || capture.barcodes.isEmpty) return;
            final v = capture.barcodes.first.rawValue;
            if (v != null && v.isNotEmpty) {
              done = true;
              Navigator.pop(context, v);
            }
          },
        ),
      ),
    );
  }
}
