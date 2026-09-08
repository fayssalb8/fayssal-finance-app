import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/date_utils.dart';
import '../../core/theme.dart';
import '../../data/app_database.dart';
import '../../services/finance_service.dart';
import '../../services/report_pdf_service.dart';

enum _RangeType { month, year, custom }

enum ReportKind { income, commission }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _db = AppDatabase.instance;
  late final FinanceService _finance = FinanceService(_db);
  late final ReportPdfService _pdf = ReportPdfService(_db, _finance);

  _RangeType _type = _RangeType.month;
  int? _startDay;
  int _month = DateTime.now().month;
  int _year = DateTime.now().year;
  DateTime? _from;
  DateTime? _to;
  bool _ready = false;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final settings = await _db.getSettings();
    final today = DateTime.now();
    final period = AppDateUtils.workMonthFor(today, settings.workMonthStartDay);
    if (!mounted) return;
    setState(() {
      _startDay = settings.workMonthStartDay;
      _month = period.month;
      _year = period.year;
      _from = period.startDate;
      _to = period.endDate;
      _ready = true;
    });
  }

  void _applyType(_RangeType type) {
    setState(() {
      _type = type;
      final today = DateTime.now();
      switch (type) {
        case _RangeType.month:
          final period = AppDateUtils.workMonthPeriod(
            _month,
            _year,
            _startDay ?? 7,
          );
          _from = period.startDate;
          _to = period.endDate;
        case _RangeType.year:
          _from = DateTime(_year, 1, 1);
          _to = DateTime(_year, 12, 31);
        case _RangeType.custom:
          final current = AppDateUtils.workMonthFor(today, _startDay ?? 7);
          _from = current.startDate;
          _to = current.endDate;
      }
      if (_from!.isAfter(_to!)) {
        final tmp = _from;
        _from = _to;
        _to = tmp;
      }
    });
  }

  Future<void> _pickMonth() async {
    final picked = await showDialog<(int, int)>(
      context: context,
      builder: (context) =>
          _MonthYearDialog(initialMonth: _month, initialYear: _year),
    );
    if (picked == null) return;
    setState(() {
      _month = picked.$1;
      _year = picked.$2;
    });
    _applyType(_RangeType.month);
  }

  Future<void> _pickYear() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => _YearDialog(initialYear: _year),
    );
    if (picked == null) return;
    setState(() => _year = picked);
    _applyType(_RangeType.year);
  }

  Future<void> _pickFrom() async {
    final from = await showDatePicker(
      context: context,
      initialDate: _from ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (from != null) {
      setState(() {
        _from = from;
        if (_to != null && _to!.isBefore(from)) _to = from;
      });
    }
  }

  Future<void> _pickTo() async {
    final to = await showDatePicker(
      context: context,
      initialDate: _to ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (to != null) {
      setState(() {
        _to = to;
        if (_from != null && _from!.isAfter(to)) _from = to;
      });
    }
  }

  Future<void> _pickKind() async {
    final picked = await showModalBottomSheet<ReportKind>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'اختر نوع التقرير',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(
                  Icons.request_quote_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('تقرير المستحقات'),
                subtitle: const Text(
                  'الراتب + الإضافي + البونص + الغياب (بدون العمولات)',
                ),
                onTap: () => Navigator.pop(context, ReportKind.income),
              ),
              ListTile(
                leading: const Icon(
                  Icons.workspace_premium_outlined,
                  color: AppColors.gold,
                ),
                title: const Text('تقرير عمولات المبيعات'),
                subtitle: const Text(
                  'كل عملية بيع مع عمولتها وإجمالي العمولات',
                ),
                onTap: () => Navigator.pop(context, ReportKind.commission),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _kind = picked);
  }

  String get _rangeLabel {
    final from = _from;
    final to = _to;
    if (from == null || to == null) return '';
    return '${AppDateUtils.display(AppDateUtils.toStorage(from))} → '
        '${AppDateUtils.display(AppDateUtils.toStorage(to))}';
  }

  ReportKind _kind = ReportKind.income;

  String get _reportTitle => _kind == ReportKind.income
      ? 'tqrir_almustahaqat.pdf'
      : 'tqrir_alumolat.pdf';

  String get _kindLabel => _kind == ReportKind.income
      ? 'تقرير المستحقات (الراتب + الإضافي + البونص + الغياب)'
      : 'تقرير عمولات المبيعات';

  String get _kindHint => _kind == ReportKind.income
      ? 'يعرض الراتب الأساسي، الساعات الإضافية، البونص، الخصومات مع '
            'إجمالي لكل قسم، ثم إجمالياً عاماً بدون العمولات.'
      : 'يعرض كل عملية بيع ومساحتها ونسبة العمولة والعمولة المستحقة، '
            'مع إجمالي العمولات في نهاية التقرير.';

  Future<void> _generate() async {
    final from = _from;
    final to = _to;
    if (from == null || to == null) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'تصدير التقرير',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.ios_share, color: AppColors.info),
                title: const Text('مشاركة / حفظ PDF'),
                subtitle: const Text('افتح نافذة المشاركة وحفظ الملف'),
                onTap: () => Navigator.pop(context, 'share'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.print_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('عرض قبل الطباعة'),
                subtitle: const Text('معاينة ثم طباعة'),
                onTap: () => Navigator.pop(context, 'print'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null) return;

    setState(() => _generating = true);
    try {

      final bytes = _kind == ReportKind.income
          ? await _pdf.generateIncomeReport(from: from, to: to)
          : await _pdf.generateCommissionReport(from: from, to: to);
      if (!mounted) return;

      if (action == 'share') {
        await Printing.sharePdf(bytes: bytes, filename: _reportTitle);
      } else {
        await Printing.layoutPdf(
          onLayout: (_) => bytes,
          name: _kind == ReportKind.income
              ? 'تقرير المستحقات'
              : 'تقرير العمولات',
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذّر إنشاء التقرير: $e')));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التقارير')),
      body: !_ready || _from == null || _to == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SegmentedButton<_RangeType>(
                  segments: const [
                    ButtonSegment(value: _RangeType.month, label: Text('شهر')),
                    ButtonSegment(value: _RangeType.year, label: Text('سنة')),
                    ButtonSegment(
                      value: _RangeType.custom,
                      label: Text('فترة مخصصة'),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => _applyType(s.first),
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: AppColors.primaryContainer,
                    selectedForegroundColor: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 16),
                if (_type == _RangeType.month)
                  _SelectorTile(
                    icon: Icons.calendar_month_outlined,
                    title: 'شهر العمل',
                    subtitle: AppDateUtils.workMonthPeriod(
                      _month,
                      _year,
                      _startDay ?? 7,
                    ).label,
                    onTap: _pickMonth,
                  )
                else if (_type == _RangeType.year)
                  _SelectorTile(
                    icon: Icons.calendar_today_outlined,
                    title: 'السنة',
                    subtitle: 'سنة $_year',
                    onTap: _pickYear,
                  )
                else ...[
                  const Text(
                    'اختر الفترة المطلوبة',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      boxShadow: CardShadow.soft(),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          onTap: _pickFrom,
                          leading: const Icon(
                            Icons.play_arrow_outlined,
                            color: AppColors.primary,
                          ),
                          title: const Text('تاريخ البداية'),
                          subtitle: Text(
                            AppDateUtils.display(
                              AppDateUtils.toStorage(_from!),
                            ),
                          ),
                          trailing: const Icon(Icons.edit_outlined, size: 18),
                        ),
                        const Divider(indent: 16, endIndent: 16),
                        ListTile(
                          onTap: _pickTo,
                          leading: const Icon(
                            Icons.stop_circle_outlined,
                            color: AppColors.danger,
                          ),
                          title: const Text('تاريخ النهاية'),
                          subtitle: Text(
                            AppDateUtils.display(AppDateUtils.toStorage(_to!)),
                          ),
                          trailing: const Icon(Icons.edit_outlined, size: 18),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _SelectorTile(
                  icon: _kind == ReportKind.income
                      ? Icons.request_quote_outlined
                      : Icons.workspace_premium_outlined,
                  title: _kindLabel,
                  subtitle: _kindHint,
                  onTap: _pickKind,
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.date_range_outlined,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'الفترة: $_rangeLabel',
                          style: const TextStyle(
                            color: AppColors.primaryDark,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _generating ? null : _generate,
                  icon: _generating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(
                    _generating ? 'جارٍ إنشاء التقرير...' : 'إنشاء تقرير PDF',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SelectorTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SelectorTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      tileColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.border),
      ),
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title, style: AppTextStyles.listTitle),
      subtitle: Text(subtitle, style: AppTextStyles.small),
      trailing: const Icon(Icons.edit_outlined, size: 18),
    );
  }
}

class _MonthYearDialog extends StatefulWidget {
  final int initialMonth;
  final int initialYear;

  const _MonthYearDialog({
    required this.initialMonth,
    required this.initialYear,
  });

  @override
  State<_MonthYearDialog> createState() => _MonthYearDialogState();
}

class _MonthYearDialogState extends State<_MonthYearDialog> {
  late int _month;
  late int _year;

  @override
  void initState() {
    super.initState();
    _month = widget.initialMonth;
    _year = widget.initialYear;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('اختر شهر العمل'),
      content: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _month,
              decoration: const InputDecoration(labelText: 'الشهر'),
              items: [
                for (var i = 0; i < 12; i++)
                  DropdownMenuItem(
                    value: i + 1,
                    child: Text(ArabicNames.months[i]),
                  ),
              ],
              onChanged: (v) => setState(() => _month = v!),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _year,
              decoration: const InputDecoration(labelText: 'السنة'),
              items: [
                for (var i = 2020; i <= 2035; i++)
                  DropdownMenuItem(value: i, child: Text('$i')),
              ],
              onChanged: (v) => setState(() => _year = v!),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_month, _year)),
          child: const Text('حسناً'),
        ),
      ],
    );
  }
}

class _YearDialog extends StatefulWidget {
  final int initialYear;

  const _YearDialog({required this.initialYear});

  @override
  State<_YearDialog> createState() => _YearDialogState();
}

class _YearDialogState extends State<_YearDialog> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.initialYear;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('اختر السنة'),
      content: DropdownButtonFormField<int>(
        initialValue: _year,
        decoration: const InputDecoration(labelText: 'السنة'),
        items: [
          for (var i = 2020; i <= 2035; i++)
            DropdownMenuItem(value: i, child: Text('$i')),
        ],
        onChanged: (v) => setState(() => _year = v!),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _year),
          child: const Text('حسناً'),
        ),
      ],
    );
  }
}
