import 'dart:ui';

import 'package:flutter/material.dart';

import '../utils.dart';
import 'app_theme.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final p = XPalette.of(context);
    return Stack(children: [
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: p.bg),
          ),
        ),
      ),
      Positioned(top: -120, right: -90, child: _Orb(p.accent.op(p.dark ? 0.22 : 0.24), 340)),
      Positioned(bottom: -150, left: -110, child: _Orb(p.accent2.op(p.dark ? 0.15 : 0.2), 380)),
    ]);
  }
}

class _Orb extends StatelessWidget {
  const _Orb(this.color, this.size);
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.op(0)]),
        ),
      );
}

/// Frosted-glass surface: backdrop blur + translucent gradient + hairline border.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    this.onTap,
    this.tint,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final p = XPalette.of(context);
    final r = BorderRadius.circular(radius);
    final base = tint ?? p.glass;
    Widget box = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: r,
        border: Border.all(color: p.border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base.op(p.dark ? 0.10 : 0.60), base.op(p.dark ? 0.04 : 0.32)],
        ),
      ),
      child: child,
    );
    if (onTap != null) box = GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: box);
    return ClipRRect(
      borderRadius: r,
      child: p.blur ? BackdropFilter(filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22), child: box) : box,
    );
  }
}

class AccentButton extends StatelessWidget {
  const AccentButton({super.key, required this.label, required this.onTap, this.icon, this.busy = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = XPalette.of(context);
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(colors: [p.accent, p.accent2]),
          boxShadow: [BoxShadow(color: p.accent.op(0.35), blurRadius: 22, offset: const Offset(0, 8))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          if (busy)
            SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.onAccent))
          else if (icon != null)
            Icon(icon, size: 20, color: p.onAccent),
          if (icon != null || busy) const SizedBox(width: 8),
          Text(label, style: TextStyle(color: p.onAccent, fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
      ),
    );
  }
}

class CircleIcon extends StatelessWidget {
  const CircleIcon({super.key, required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = XPalette.of(context);
    return Glass(
      radius: 22,
      padding: const EdgeInsets.all(11),
      onTap: onTap,
      child: Icon(icon, size: 22, color: p.text),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = XPalette.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) rows.add(Divider(height: 1, color: p.border));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(title.toUpperCase(),
              style: TextStyle(color: p.accent, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        ),
        Glass(padding: EdgeInsets.zero, radius: 22, child: Column(children: rows)),
      ]),
    );
  }
}

class SettingRow extends StatelessWidget {
  const SettingRow({super.key, required this.icon, required this.title, this.subtitle, this.trailing, this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = XPalette.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: p.accent.op(0.16), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 19, color: p.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w600)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, style: TextStyle(color: p.dim, fontSize: 12.5)),
                ),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
      ),
    );
  }
}

/// Page scaffold with the app background, a glass back button and a title.
class GlassPage extends StatelessWidget {
  const GlassPage({super.key, required this.title, required this.child, this.actions = const []});
  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = XPalette.of(context);
    return Scaffold(
      body: Stack(children: [
        const Positioned.fill(child: AppBackground()),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(children: [
                CircleIcon(icon: Icons.arrow_back_rounded, onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(title,
                      style: TextStyle(color: p.text, fontSize: 22, fontWeight: FontWeight.w800)),
                ),
                ...actions,
              ]),
            ),
            Expanded(child: child),
          ]),
        ),
      ]),
    );
  }
}
