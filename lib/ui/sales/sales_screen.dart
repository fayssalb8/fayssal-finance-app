import 'package:flutter/material.dart';

import '../../core/date_utils.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/work_month_switcher.dart';
import '../../data/app_database.dart';
import '../../models/app_settings.dart';
import '../../models/sale.dart';
import '../../services/finance_service.dart';
import 'sale_form_screen.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => SalesScreenState();
}

class SalesScreenState extends State<SalesScreen> {
  final _db = AppDatabase.instance;
  late final FinanceService _finance = FinanceService(_db);

  AppSettings? _settings;
  WorkMonthPeriod? _period;
  List<SaleWithCommission> _sales = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// يعيد تحميل البيانات (يُستدعى عند التبديل إلى تبويب المبيعات).
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
    final sales = await _db.getSales(
      workMonth: period.monthName,
      workYear: period.year,
    );
    final items = <SaleWithCommission>[];
    for (final sale in sales) {
      items.add(await _finance.saleWithCommission(sale, settings));
    }
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _period = period;
      _sales = items;
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

  Future<void> _openForm({SaleWithCommission? existing}) async {
    final settings = _settings;
    if (settings == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SaleFormScreen(existing: existing)),
    );
    _reload();
  }

  /// يعيد تحميل الشهر المعروض حالياً (دون العودة لشهر اليوم).
  Future<void> _reload() async {
    final settings = _settings;
    final period = _period;
    if (settings == null || period == null) {
      await _load();
    } else {
      await _loadFor(period, settings);
    }
  }

  Future<void> _deleteSale(SaleWithCommission item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف البيع'),
        content: Text(
          'بيع "${_clientNameOf(item)}" في '
          '${AppDateUtils.display(item.sale.date)}؟\n'
          'سيتم حذف البيع ونصيبه من العمولة نهائياً.',
        ),
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
      await _db.deleteSale(item.sale.id);
      _reload();
    }
  }

  String _clientNameOf(SaleWithCommission item) =>
      item.sale.clientId == null ? 'بدون زبون' : item.clientName ?? '—';

  @override
  Widget build(BuildContext context) {
    final period = _period;
    return Scaffold(
      appBar: AppBar(title: const Text('المبيعات')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        tooltip: 'إضافة بيع',
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (period != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: WorkMonthSwitcher(
                        period: period,
                        onChanged: _changeMonth,
                      ),
                    ),
                  Expanded(
                    child: _sales.isEmpty
                        ? EmptyStateView(
                            icon: Icons.local_mall_outlined,
                            title:
                                'لا توجد مبيعات في هذا الشهر\n'
                                'أضف أول بيع لحساب العمولة',
                            actionLabel: 'إضافة بيع',
                            onAction: () => _openForm(),
                          )
                        : RefreshIndicator(
                            onRefresh: _reload,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(16),
                              itemCount: _sales.length,
                              itemBuilder: (context, i) {
                                final item = _sales[i];
                                return _SaleTile(
                                  item: item,
                                  onTap: () => _openForm(existing: item),
                                  onDelete: () => _deleteSale(item),
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

class _SaleTile extends StatelessWidget {
  final SaleWithCommission item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SaleTile({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  String get _clientName =>
      item.sale.clientId == null ? 'بدون زبون' : item.clientName ?? '—';

  @override
  Widget build(BuildContext context) {
    final sale = item.sale;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.infoLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.local_mall_outlined,
                  color: AppColors.info,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _clientName,
                            style: AppTextStyles.listTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            sale.orderType,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${AppDateUtils.display(sale.date)}  •  '
                      '${Formatters.number(sale.area)} م²',
                      style: AppTextStyles.small,
                    ),
                  ],
                ),
              ),
              if (sale.isShared)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warningLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'مشترك',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                Formatters.money(item.userCommission),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.info,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: onDelete,
                tooltip: 'حذف البيع',
                icon: const Icon(Icons.delete_outline, size: 20),
                color: AppColors.textSecondary,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatusChip(
                label: 'معلّق',
                active: sale.status == SaleStatus.pending,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              _StatusChip(
                label: 'مؤكد',
                active: sale.status == SaleStatus.confirmed,
                color: AppColors.info,
              ),
              const SizedBox(width: 6),
              _StatusChip(
                label: 'مدفوع',
                active: sale.status == SaleStatus.paid,
                color: AppColors.success,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;

  const _StatusChip({
    required this.label,
    required this.active,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.15) : AppColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? color : AppColors.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: active ? color : AppColors.textSecondary,
          fontWeight: active ? FontWeight.w600 : null,
        ),
      ),
    );
  }
}
