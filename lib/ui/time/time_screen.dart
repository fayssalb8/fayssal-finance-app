import 'package:flutter/material.dart';

import '../../core/date_utils.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/work_month_switcher.dart';
import '../../data/app_database.dart';
import '../../models/app_settings.dart';
import '../../models/time_record.dart';
import 'time_record_form_screen.dart';

class TimeScreen extends StatefulWidget {
  const TimeScreen({super.key});

  @override
  State<TimeScreen> createState() => TimeScreenState();
}

class TimeScreenState extends State<TimeScreen> {
  final _db = AppDatabase.instance;


  String _view = TimeRecordType.overtime;
  AppSettings? _settings;
  WorkMonthPeriod? _period;
  List<TimeRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// يعيد تحميل البيانات (يُستدعى عند التبديل إلى تبويب الوقت).
  Future<void> refresh() => _reload();

  Future<void> _load() async {
    final settings = await _db.getSettings();
    final period = AppDateUtils.workMonthFor(
      DateTime.now(),
      settings.workMonthStartDay,
    );
    await _loadFor(period, settings);
  }

  Future<void> _loadFor(WorkMonthPeriod period, AppSettings settings) async {
    final records = await _db.getTimeRecords(
      workMonth: period.monthName,
      workYear: period.year,
    );
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _period = period;
      _records = records;
      _loading = false;
    });
  }

  void _changeMonth(int delta) {
    final settings = _settings;
    final period = _period;
    if (settings == null || period == null) return;
    final next = DateTime(period.year, period.month + delta, 1);
    _loadFor(
      AppDateUtils.workMonthPeriod(
        next.month,
        next.year,
        settings.workMonthStartDay,
      ),
      settings,
    );
  }

  List<TimeRecord> get _visibleRecords {
    return switch (_view) {
      TimeRecordType.overtime => _records.where((r) => r.isOvertime).toList(),
      TimeRecordType.bonus => _records.where((r) => r.isBonus).toList(),
      _ => _records.where((r) => r.isAbsenceHours || r.isAbsenceDays).toList(),
    };
  }

  Future<void> _openAdd() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TimeRecordFormScreen(
          initialType: _view == TimeRecordType.bonus
              ? TimeRecordType.bonus
              : _view == TimeRecordType.overtime
              ? TimeRecordType.overtime
              : TimeRecordType.absenceHours,
        ),
      ),
    );
    _reload();
  }

  Future<void> _openEdit(TimeRecord record) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            TimeRecordFormScreen(initialType: record.type, existing: record),
      ),
    );
    _reload();
  }

  /// يعيد تحميل الشهور الحالي المعروض (دون العودة لشهر اليوم).
  Future<void> _reload() async {
    final settings = _settings;
    final period = _period;
    if (settings == null || period == null) {
      await _load();
    } else {
      await _loadFor(period, settings);
    }
  }

  Future<void> _delete(TimeRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف السجل'),
        content: const Text('هل تريد حذف هذا السجل نهائياً؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.deleteTimeRecord(record.id);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final period = _period;
    return Scaffold(
      appBar: AppBar(title: const Text('الوقت')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAdd,
        tooltip: 'إضافة سجل',
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: TimeRecordType.overtime,
                          icon: Icon(Icons.timer_outlined),
                          label: Text('ساعات إضافية'),
                        ),
                        ButtonSegment(
                          value: TimeRecordType.bonus,
                          icon: Icon(Icons.card_giftcard_outlined),
                          label: Text('بونص'),
                        ),
                        ButtonSegment(
                          value: TimeRecordType.absenceHours,
                          icon: Icon(Icons.event_busy_outlined),
                          label: Text('غياب'),
                        ),
                      ],
                      selected: {_view},
                      onSelectionChanged: (s) =>
                          setState(() => _view = s.first),
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: switch (_view) {
                          TimeRecordType.overtime => AppColors.successLight,
                          TimeRecordType.bonus => AppColors.warningLight,
                          _ => AppColors.dangerLight,
                        },
                        selectedForegroundColor: switch (_view) {
                          TimeRecordType.overtime => AppColors.success,
                          TimeRecordType.bonus => AppColors.gold,
                          _ => AppColors.danger,
                        },
                      ),
                    ),
                  ),
                  if (period != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: WorkMonthSwitcher(
                        period: period,
                        onChanged: _changeMonth,
                      ),
                    ),
                  Expanded(
                    child: _visibleRecords.isEmpty
                        ? _EmptyState(view: _view, onAdd: _openAdd)
                        : RefreshIndicator(
                            onRefresh: _reload,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(16),
                              itemCount: _visibleRecords.length,
                              itemBuilder: (context, i) {
                                final record = _visibleRecords[i];
                                return _TimeRecordTile(
                                  record: record,
                                  onTap: () => _openEdit(record),
                                  onDelete: () => _delete(record),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String view;
  final VoidCallback onAdd;

  const _EmptyState({required this.view, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final (icon, title, buttonLabel) = switch (view) {
      TimeRecordType.overtime => (
        Icons.timer_off_outlined,
        'لا توجد ساعات إضافية هذا الشهر',
        'إضافة ساعات إضافية',
      ),
      TimeRecordType.bonus => (
        Icons.card_giftcard_outlined,
        'لا يوجد بونص هذا الشهر',
        'إضافة بونص',
      ),
      _ => (
        Icons.event_available_outlined,
        'لا يوجد غياب هذا الشهر',
        'إضافة غياب',
      ),
    };
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 48),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

class _TimeRecordTile extends StatelessWidget {
  final TimeRecord record;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _TimeRecordTile({
    required this.record,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final (
      Color color,
      Color bg,
      IconData icon,
      String title,
    ) = switch (record.type) {
      TimeRecordType.overtime => (
        AppColors.success,
        AppColors.successLight,
        Icons.timer_outlined,
        'ساعات إضافية',
      ),
      TimeRecordType.bonus => (
        AppColors.gold,
        AppColors.warningLight,
        Icons.card_giftcard_outlined,
        'بونص',
      ),
      TimeRecordType.absenceHours => (
        AppColors.danger,
        AppColors.dangerLight,
        Icons.schedule_outlined,
        'غياب بالساعات',
      ),
      _ => (
        AppColors.warning,
        AppColors.warningLight,
        Icons.event_busy_outlined,
        'غياب بالأيام',
      ),
    };

    final subtitle = switch (record.type) {
      TimeRecordType.overtime ||
      TimeRecordType.absenceHours => '${record.startTime} - ${record.endTime}',
      TimeRecordType.bonus => 'مبلغ محدد',
      _ => '${record.daysCount} يوم',
    };

    final value = switch (record.type) {
      TimeRecordType.overtime => '+ ${Formatters.money(record.totalValue)}',
      TimeRecordType.bonus => '+ ${Formatters.money(record.totalValue)}',
      TimeRecordType.absenceHours => '- ${Formatters.money(record.totalValue)}',
      _ => '${record.daysCount} يوم من العطلة',
    };

    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (record.customRate != null && record.customRate! > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'يدوي: ${Formatters.money(record.customRate!)}/س',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                    if (record.reason != null && record.reason!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '· ${record.reason}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${AppDateUtils.display(record.date)}  •  $subtitle',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
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
          IconButton(
            onPressed: onDelete,
            tooltip: 'حذف السجل',
            icon: const Icon(Icons.delete_outline, size: 20),
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
