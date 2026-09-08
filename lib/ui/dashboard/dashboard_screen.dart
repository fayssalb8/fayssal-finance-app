import 'package:flutter/material.dart';

import '../../core/date_utils.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/work_month_switcher.dart';
import '../../data/app_database.dart';
import '../../models/app_settings.dart';
import '../../services/finance_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  final _db = AppDatabase.instance;
  late final FinanceService _finance = FinanceService(_db);

  AppSettings? _settings;
  MonthSummary? _summary;
  int? _remainingLeave;
  WorkMonthPeriod? _period;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// يعيد تحميل البيانات (يُستدعى عند العودة إلى تبويب الرئيسية).
  Future<void> refresh() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    final settings = await _db.getSettings();
    final now = DateTime.now();
    final period = AppDateUtils.workMonthFor(now, settings.workMonthStartDay);
    await _loadFor(period, settings);
  }

  Future<void> _loadFor(WorkMonthPeriod period, AppSettings settings) async {
    final summary = await _finance.summaryFor(
      month: period.month,
      year: period.year,
      startDay: settings.workMonthStartDay,
      settings: settings,
    );
    final remaining = await _finance.remainingLeave(
      settings,
      workYear: period.year,
    );
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _period = period;
      _summary = summary;
      _remainingLeave = remaining;
      _loading = false;
    });
  }

  void _changeMonth(int delta) {
    final settings = _settings;
    final period = _period;
    if (settings == null || period == null) return;
    final next = DateTime(period.year, period.month + delta, 1);
    final nextPeriod = AppDateUtils.workMonthPeriod(
      next.month,
      next.year,
      settings.workMonthStartDay,
    );
    _loadFor(nextPeriod, settings);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _buildSalaryCard(),
              const SizedBox(height: 16),
              _buildStatsGrid(),
              const SizedBox(height: 16),
              _buildGrandTotalCard(),
              const SizedBox(height: 16),
              _buildTargetCard(),
              const SizedBox(height: 16),
              _buildLeaveBar(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final today = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('لوحة التحكم', style: AppTextStyles.screenTitle),
        const SizedBox(height: 4),
        Text(
          'اليوم: ${ArabicNames.weekdays[today.weekday % 7]} '
          '${today.day} ${ArabicNames.months[today.month - 1]} ${today.year}',
          style: AppTextStyles.bodyMedium,
        ),
        const SizedBox(height: 12),
        WorkMonthSwitcher(period: _summary?.period, onChanged: _changeMonth),
      ],
    );
  }

  Widget _buildSalaryCard() {
    final summary = _summary!;
    final isCommissionOnly = summary.isCommissionOnly;
    final title = isCommissionOnly ? 'وضع عمولة فقط' : 'الراتب الشهري';
    final value = isCommissionOnly
        ? summary.overtimeTotal
        : summary.actualSalary;
    final note = isCommissionOnly
        ? 'لا يوجد راتب ثابت؛ ساعات العمل الإضافية تُسلّم بسعر متفق عليه، '
              'والبونص والعمولات تظهر منفصلة.'
        : 'الراتب الأساسي/الفعلي لهذا الشهر، والبونص والعمولات منفصلة.';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: CardShadow.soft(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              if (!isCommissionOnly)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: Colors.white70,
                    size: 18,
                  ),
                  tooltip: 'تعديل الراتب الفعلي لهذا الشهر',
                  onPressed: _editMonthlySalary,
                )
              else
                const Icon(
                  Icons.trending_up,
                  color: Colors.white70,
                  size: 20,
                ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.1),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              Formatters.money(value),
              key: ValueKey<double>(value),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            note,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    final summary = _summary!;
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _StatCard(
                title: 'الساعات الإضافية',
                value: Formatters.money(summary.overtimeTotal),
                detail: Formatters.hours(summary.overtimeHours),
                icon: Icons.timer_outlined,
                color: AppColors.success,
                background: AppColors.successLight,
              ),
              const SizedBox(height: 12),
              _StatCard(
                title: 'عمولات المبيعات',
                value: Formatters.money(summary.salesRewards),
                detail: '${Formatters.number(summary.salesArea)} متر مربع',
                icon: Icons.local_mall_outlined,
                color: AppColors.info,
                background: AppColors.infoLight,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              _StatCard(
                title: 'البونص',
                value: Formatters.money(summary.bonusTotal),
                detail: 'منفصل عن الراتب',
                icon: Icons.card_giftcard_outlined,
                color: AppColors.gold,
                background: AppColors.warningLight,
              ),
              const SizedBox(height: 12),
              _StatCard(
                title: summary.isCommissionOnly ? 'الغياب' : 'خصم الغياب',
                value: summary.isCommissionOnly
                    ? Formatters.hours(summary.absenceHours)
                    : '- ${Formatters.money(summary.absenceHoursDeduction)}',
                detail: Formatters.hours(summary.absenceHours),
                icon: Icons.event_busy_outlined,
                color: AppColors.danger,
                background: AppColors.dangerLight,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGrandTotalCard() {
    final summary = _summary!;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الإجمالي العام (صافي الراتب + البونص)',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.1),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              Formatters.money(summary.grandTotal),
              key: ValueKey<double>(summary.grandTotal),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 24,
                color: AppColors.gold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _GrandRow(
                  label: 'صافي الراتب',
                  value: Formatters.money(summary.netDue),
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTargetCard() {
    final settings = _settings!;
    final summary = _summary!;
    final target = settings.paymentTarget;
    final current = summary.grandTotal;
    final remaining = target - current;
    final rate = _finance.overtimeRatePerHour(settings);
    final requiredHours = rate <= 0 ? 0.0 : remaining / rate;
    final reached = target <= 0 || remaining <= 0;
    final progress = target <= 0
        ? 0.0
        : (current / target).clamp(0.0, 1.0);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'هدف المبلغ الإجمالي',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              TextButton.icon(
                onPressed: _editTarget,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('تعديل'),
              ),
            ],
          ),
          if (target <= 0)
            const Text(
              'حدّد هدفاً مالياً وسنعرض لك كم ساعة إضافية تحتاج '
              'لبلوغه هذا الشهر.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _GrandRow(
                    label: 'الهدف',
                    value: Formatters.money(target),
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _GrandRow(
                    label: 'المحقق الآن',
                    value: Formatters.money(current),
                    color: reached ? AppColors.success : AppColors.gold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: AppColors.border,
                color: reached ? AppColors.success : AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            if (reached)
              const Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      color: AppColors.success, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'وصلت إلى الهدف. ما زلت أعلاه!',
                      style: TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              )
            else ...[
              _TargetLine(
                icon: Icons.trending_up,
                label: 'المتبقي للهدف',
                value: Formatters.money(remaining),
                color: AppColors.danger,
              ),
              const SizedBox(height: 6),
              _TargetLine(
                icon: Icons.timer_outlined,
                label: 'ساعات إضافية مطلوبة',
                value: Formatters.hours(requiredHours),
                color: AppColors.primary,
              ),
              if (rate <= 0) ...[
                const SizedBox(height: 6),
                const Text(
                  'لا يوجد سعر ساعة إضافية مضبوط؛ اضبطه من الإعدادات.',
                  style: TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _editMonthlySalary() async {
    final settings = _settings;
    final summary = _summary;
    final period = _period;
    if (settings == null || summary == null || period == null) return;

    final override = await _db.getSalaryOverride(period.monthName, period.year);
    final hasOverride = override != null;
    final controller = TextEditingController(
      text: _numText(summary.actualSalary),
    );

    try {
      final result = await showDialog<(bool shouldSave, double? amount)>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('تعديل راتب شهر ${period.label}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'الراتب الأساسي الافتراضي من الإعدادات: ${Formatters.money(settings.baseSalary)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'الراتب الفعلي لهذا الشهر (دج)',
                  prefixIcon: Icon(Icons.payments_outlined, size: 20),
                ),
              ),
            ],
          ),
          actions: [
            if (hasOverride)
              TextButton(
                onPressed: () => Navigator.pop(context, (true, null)),
                child: const Text(
                  'استعادة الافتراضي',
                  style: TextStyle(color: AppColors.danger),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context, (false, null)),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                (true, Formatters.parseAmount(controller.text)),
              ),
              child: const Text('حفظ'),
            ),
          ],
        ),
      );

      if (result == null || !result.$1) return;

      if (result.$2 == null) {
        await _db.deleteSalaryOverride(period.monthName, period.year);
      } else {
        await _db.saveSalaryOverride(
          workMonth: period.monthName,
          workYear: period.year,
          actualSalary: result.$2!,
        );
      }

      await _loadFor(period, settings);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _editTarget() async {
    final settings = _settings;
    final period = _period;
    if (settings == null) return;
    final controller = TextEditingController(
      text: settings.paymentTarget == 0
          ? ''
          : _numText(settings.paymentTarget),
    );
    try {
      final saved = await showDialog<double>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('هدف المبلغ الإجمالي'),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'المبلغ المستهدف (دج)',
              prefixIcon: Icon(Icons.track_changes_outlined, size: 20),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                Formatters.parseAmount(controller.text),
              ),
              child: const Text('حفظ'),
            ),
          ],
        ),
      );
      if (saved == null || saved < 0) return;
      final updated = settings.copyWith(paymentTarget: saved);
      await _db.updateSettings(updated);
      if (!mounted) return;
      if (period != null) {
        await _loadFor(period, updated);
      } else {
        setState(() => _settings = updated);
      }
    } finally {
      controller.dispose();
    }
  }

  static String _numText(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  Widget _buildLeaveBar() {
    final total = _settings?.annualLeaveBalance ?? 0;
    final remaining = _remainingLeave ?? 0;
    final used = total - remaining;
    final progress = total == 0 ? 0.0 : (used / total).clamp(0.0, 1.0);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'رصيد العطلة السنوية المتبقي',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '$remaining من $total يوم',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.border,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _TargetLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _GrandRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _GrandRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? detail;
  final IconData icon;
  final Color color;
  final Color background;

  const _StatCard({
    required this.title,
    required this.value,
    this.detail,
    required this.icon,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (detail != null) ...[
            const SizedBox(height: 2),
            Text(
              detail!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
