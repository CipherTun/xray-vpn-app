import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/services/infra.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/glass.dart';
import '../core/utils.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});
  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  int tab = 0; // 0 app, 1 core
  List<String> core = [];
  Timer? _t;

  @override
  void initState() {
    super.initState();
    AppLog.I.addListener(_refresh);
    _t = Timer.periodic(const Duration(seconds: 2), (_) => _readCore());
    _readCore();
  }

  @override
  void dispose() {
    AppLog.I.removeListener(_refresh);
    _t?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _readCore() async {
    if (tab != 1) return;
    try {
      final f = File(AppPaths.coreLog);
      if (!await f.exists()) {
        if (mounted) setState(() => core = []);
        return;
      }
      final lines = await f.readAsLines();
      if (mounted) setState(() => core = lines.length > 400 ? lines.sublist(lines.length - 400) : lines);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = XPalette.of(context);
    final lines = tab == 0 ? AppLog.I.lines : core;
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: Row(children: [
            Expanded(child: Text('Logs', style: TextStyle(color: p.text, fontSize: 26, fontWeight: FontWeight.w800))),
            CircleIcon(
              icon: Icons.copy_rounded,
              onTap: () {
                Clipboard.setData(ClipboardData(text: lines.join('\n')));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logs copied')));
              },
            ),
            const SizedBox(width: 10),
            CircleIcon(
              icon: Icons.delete_sweep_rounded,
              onTap: () async {
                if (tab == 0) {
                  AppLog.I.clear();
                } else {
                  try {
                    await File(AppPaths.coreLog).writeAsString('');
                  } catch (_) {}
                  setState(() => core = []);
                }
              },
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('App')),
              ButtonSegment(value: 1, label: Text('Xray core')),
            ],
            selected: {tab},
            onSelectionChanged: (s) {
              setState(() => tab = s.first);
              _readCore();
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 112),
            child: Glass(
              padding: const EdgeInsets.all(12),
              child: lines.isEmpty
                  ? Center(child: Text('No log lines yet', style: TextStyle(color: p.dim)))
                  : ListView.builder(
                      reverse: true,
                      itemCount: lines.length,
                      itemBuilder: (_, i) {
                        final l = lines[lines.length - 1 - i];
                        final bad = l.contains('[E]') || l.toLowerCase().contains('error') || l.contains('failed');
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(l,
                              style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11.5,
                                  height: 1.35,
                                  color: bad ? p.danger : p.text.op(0.9))),
                        );
                      },
                    ),
            ),
          ),
        ),
      ]),
    );
  }
}
