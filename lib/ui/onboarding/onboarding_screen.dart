import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/app_database.dart';
import '../../models/app_settings.dart';
import '../shell/main_shell.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _db = AppDatabase.instance;
  bool _saving = false;

  Future<void> _choose(String mode) async {
    if (_saving) return;
    setState(() => _saving = true);

    final settings = await _db.getSettings();
    await _db.updateSettings(
      settings.copyWith(compensationMode: mode, hasOnboarded: true),
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => const MainShell(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 20),
            Container(
              width: 88,
              height: 88,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.emoji_food_beverage_outlined,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'مرحباً بك في Smart Kitchen Finance',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'اختر طريقة التعويض التي تناسب عملك.\n'
              'كلتا الطريقتين تشملان: البونص، الساعات الإضافية، والغياب.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 32),
            _ModeCard(
              icon: Icons.payments_outlined,
              accent: AppColors.success,
              background: AppColors.successLight,
              title: 'راتب شهري + عمولة صغيرة',
              description:
                  'راتب ثابت شهري، مع عمولة صغيرة إضافية على المبيعات. '
                  'سعر الساعة يُحسب من الراتب لخصم الغياب ومكافأة الإضافي.',
              onTap: () => _choose(CompensationMode.salaryBonus),
            ),
            const SizedBox(height: 16),
            _ModeCard(
              icon: Icons.trending_up,
              accent: AppColors.info,
              background: AppColors.infoLight,
              title: 'عمولة فقط (بدون راتب)',
              description:
                  'الأجر الأساسي من عمولات المبيعات. الساعات الإضافية تُسلّم '
                  'بسعر متفق عليه لكل ساعة، والغياب يُسجّل فقط ضد العطلة '
                  'دون خصم مالي.',
              onTap: () => _choose(CompensationMode.commissionOnly),
            ),
            const SizedBox(height: 32),
            if (_saving) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final Color background;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.accent,
    required this.background,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
            boxShadow: CardShadow.soft(),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_left, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
