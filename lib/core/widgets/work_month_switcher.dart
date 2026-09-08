import 'package:flutter/material.dart';

import '../date_utils.dart';
import '../theme.dart';

/// مبدّل شهر العمل الموحّد.
///
/// يعرض اسم شهر العمل ونطاقه مع زرّي السابق/التالي، مع تصحيح اتجاه
/// الأسهم تلقائيا في واجهات RTL (السابق يمين، والتالي يسار).
class WorkMonthSwitcher extends StatelessWidget {
  final WorkMonthPeriod? period;
  final ValueChanged<int> onChanged;

  const WorkMonthSwitcher({
    super.key,
    required this.period,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final prevIcon = rtl ? Icons.chevron_right : Icons.chevron_left;
    final nextIcon = rtl ? Icons.chevron_left : Icons.chevron_right;
    final period = this.period;

    Widget arrow({
      required IconData icon,
      required String tooltip,
      required int delta,
    }) {
      return IconButton(
        onPressed: period == null ? null : () => onChanged(delta),
        icon: Icon(icon, size: 22),
        tooltip: tooltip,
        color: AppColors.primary,
        visualDensity: VisualDensity.compact,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          arrow(icon: prevIcon, tooltip: 'الشهر السابق', delta: -1),
          Expanded(
            child: Column(
              children: [
                Text(
                  period?.label ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryDark,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  period?.rangeLabel ?? '',
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          arrow(icon: nextIcon, tooltip: 'الشهر التالي', delta: 1),
        ],
      ),
    );
  }
}
