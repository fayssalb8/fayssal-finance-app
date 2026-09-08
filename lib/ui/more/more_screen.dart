import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets/app_card.dart';
import '../clients/clients_screen.dart';
import '../colleagues/colleagues_screen.dart';
import '../import/import_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('المزيد', style: AppTextStyles.screenTitle),
          const SizedBox(height: 4),
          const Text(
            'الإعدادات وإدارة بياناتك',
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 16),
          _MoreCard(
            icon: Icons.settings_outlined,
            iconColor: AppColors.primary,
            background: AppColors.primaryContainer,
            title: 'الإعدادات',
            subtitle: 'الراتب، سعر المتر، يوم بداية الشهر، العطل',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _MoreCard(
            icon: Icons.people_outline,
            iconColor: AppColors.info,
            background: AppColors.infoLight,
            title: 'العملاء',
            subtitle: 'إدارة قائمة العملاء',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ClientsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _MoreCard(
            icon: Icons.group_outlined,
            iconColor: AppColors.success,
            background: AppColors.successLight,
            title: 'الزملاء',
            subtitle: 'إدارة قائمة الزملاء للمبيعات المشتركة',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ColleaguesScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _MoreCard(
            icon: Icons.description_outlined,
            iconColor: AppColors.gold,
            background: AppColors.warningLight,
            title: 'التقارير',
            subtitle: 'تصدير تقرير PDF بالمستحقات',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReportsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _MoreCard(
            icon: Icons.file_upload_outlined,
            iconColor: AppColors.primary,
            background: AppColors.primaryContainer,
            title: 'استيراد البيانات (Excel / CSV)',
            subtitle: 'استيراد الزبائن، الساعات الإضافية، الغياب والمبيعات',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ImportScreen()),
            ),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text('Smart Kitchen Finance', style: AppTextStyles.caption),
          ),
        ],
      ),
    );
  }
}

class _MoreCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color background;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MoreCard({
    required this.icon,
    required this.iconColor,
    required this.background,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.listTitle),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTextStyles.small),
              ],
            ),
          ),
          const Icon(Icons.chevron_left, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}
