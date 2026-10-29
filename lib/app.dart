import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/state/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/home_shell.dart';

class XrayApp extends ConsumerWidget {
  const XrayApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return MaterialApp(
      title: 'XRay VPN',
      debugShowCheckedModeBanner: false,
      themeMode: s.themeMode,
      theme: AppTheme.build(Brightness.light, s.accent, s.customAccent, s.blur),
      darkTheme: AppTheme.build(Brightness.dark, s.accent, s.customAccent, s.blur),
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        ));
        return child!;
      },
      home: const HomeShell(),
    );
  }
}
