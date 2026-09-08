import 'package:flutter/material.dart';

import '../theme.dart';

/// بطاقة موحّدة لكل صفوف وشاشات التطبيق.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final List<BoxShadow>? boxShadow;
  final Border? border;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.background = Colors.white,
    this.borderRadius,
    this.onTap,
    this.boxShadow,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(AppRadius.md);
    final shadow = boxShadow ?? CardShadow.soft();

    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        border: border,
        boxShadow: shadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
