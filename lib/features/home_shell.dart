import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/state/providers.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/glass.dart';
import '../core/utils.dart';
import 'configs_page.dart';
import 'dashboard_page.dart';
import 'logs_page.dart';
import 'tools_page.dart';

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  static const _items = [
    (Icons.dashboard_rounded, 'Dashboard'),
    (Icons.dns_rounded, 'Configs'),
    (Icons.receipt_long_rounded, 'Logs'),
    (Icons.handyman_rounded, 'Tools'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(tabProvider);
    final p = XPalette.of(context);
    return Scaffold(
      extendBody: true,
      body: Stack(children: [
        const Positioned.fill(child: AppBackground()),
        IndexedStack(index: index, children: const [
          DashboardPage(),
          ConfigsPage(),
          LogsPage(),
          ToolsPage(),
        ]),
      ]),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Glass(
            radius: 28,
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => ref.read(tabProvider.notifier).state = i,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          gradient: i == index
                              ? LinearGradient(colors: [p.accent.op(0.95), p.accent2.op(0.95)])
                              : null,
                        ),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_items[i].$1, size: 22, color: i == index ? p.onAccent : p.dim),
                          const SizedBox(height: 3),
                          Text(_items[i].$2,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: i == index ? p.onAccent : p.dim,
                              )),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
