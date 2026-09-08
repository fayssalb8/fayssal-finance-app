import 'package:flutter/material.dart';

import '../../core/date_utils.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/app_database.dart';
import '../../models/app_settings.dart';
import '../../models/client.dart';
import '../../models/sale.dart';
import '../../services/finance_service.dart';
import '../common/name_edit_dialog.dart';

class _ShareEntry {
  final String personType;
  final int? colleagueId;
  final String label;
  final TextEditingController percent;

  _ShareEntry({
    required this.personType,
    this.colleagueId,
    required this.label,
    double percent = 0,
  }) : percent = TextEditingController(text: _percentText(percent));

  static String _percentText(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  double get value => Formatters.parseAmount(percent.text) ?? 0;

  void dispose() => percent.dispose();
}

class SaleFormScreen extends StatefulWidget {
  final SaleWithCommission? existing;

  const SaleFormScreen({super.key, this.existing});

  @override
  State<SaleFormScreen> createState() => _SaleFormScreenState();
}

class _SaleFormScreenState extends State<SaleFormScreen> {
  final _db = AppDatabase.instance;
  late final FinanceService _finance = FinanceService(_db);

  final _formKey = GlobalKey<FormState>();
  final _areaController = TextEditingController();

  List<Client> _clients = [];
  List<Colleague> _colleagues = [];
  AppSettings? _settings;
  bool _loading = true;
  bool _saving = false;

  Client? _client;
  late DateTime _date;
  String _orderType = OrderType.kitchen;
  double _rate = 0.015;
  bool _shared = false;
  String _status = SaleStatus.pending;
  final List<_ShareEntry> _shares = [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    _shares.add(
      _ShareEntry(
        personType: SaleShare.personMe,
        label: 'أنا (المستخدم)',
        percent: 100,
      ),
    );
    _load();
  }

  @override
  void dispose() {
    _areaController.dispose();
    for (final s in _shares) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _db.getSettings();
    final clients = await _db.getClients();
    final colleagues = await _db.getColleagues();

    final existing = widget.existing;
    if (existing != null) {
      final sale = existing.sale;
      _date = AppDateUtils.fromStorage(sale.date) ?? DateTime.now();
      _orderType = sale.orderType;
      _rate = sale.commissionRate;
      _shared = sale.isShared;
      _status = sale.status;
      _areaController.text = Formatters.number(sale.area);
      if (sale.clientId != null) {
        _client = clients.where((c) => c.id == sale.clientId).firstOrNull;
      }
      _shares.clear();
      for (final share in existing.shares) {
        final isMe = share.personType == SaleShare.personMe;
        final colleague = isMe
            ? null
            : colleagues.where((c) => c.id == share.colleagueId).firstOrNull;
        _shares.add(
          _ShareEntry(
            personType: share.personType,
            colleagueId: share.colleagueId,
            label: isMe ? 'أنا (المستخدم)' : colleague?.name ?? 'زميل',
            percent: share.sharePercentage,
          ),
        );
      }
      if (_shares.isEmpty) {
        _shares.add(
          _ShareEntry(
            personType: SaleShare.personMe,
            label: 'أنا (المستخدم)',
            percent: 100,
          ),
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _settings = settings;
      _clients = clients;
      _colleagues = colleagues;
      _loading = false;
    });
  }

  double get _area => Formatters.parseAmount(_areaController.text) ?? 0;

  double get _mySharePercent {
    final my = _shares
        .where((s) => s.personType == SaleShare.personMe)
        .firstOrNull;
    return my?.value ?? 0;
  }

  double get _totalSharePercent => _shares.fold(0.0, (sum, s) => sum + s.value);

  double get _commissionPreview {
    final settings = _settings;
    if (settings == null) return 0;
    final commission = _finance.kitchenPrice(settings, _area) * _rate;
    if (!_shared) return commission;
    return commission * _mySharePercent / 100;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickClient() async {
    if (_clients.isEmpty) {
      _addClientDialog();
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'اختر الزبون',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.person_add_alt_outlined,
                color: AppColors.primary,
              ),
              title: const Text('إضافة زبون جديد'),
              onTap: () => Navigator.pop(context, '__add__'),
            ),
            const Divider(),
            for (final client in _clients)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(client.name),
                subtitle: client.phone.isNotEmpty ? Text(client.phone) : null,
                onTap: () => Navigator.pop(context, '${client.id}'),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == '__add__') {
      await _addClientDialog();
      return;
    }
    final id = int.parse(choice);
    setState(() => _client = _clients.where((c) => c.id == id).firstOrNull);
  }

  Future<void> _addClientDialog() async {
    final result = await showNameDialog(
      context,
      title: 'إضافة زبون جديد',
      label: 'اسم الزبون',
      hasPhone: true,
    );
    if (result == null) return;
    final id = await _db.insertClient(
      Client(name: result.name, phone: result.phone),
    );
    final clients = await _db.getClients();
    if (!mounted) return;
    setState(() {
      _clients = clients;
      _client = _clients.where((c) => c.id == id).firstOrNull;
    });
  }

  Future<void> _addColleagueShare() async {
    if (_colleagues.isEmpty) {
      _addColleagueDialog();
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'أضف زميلاً للمشاركة',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.person_add_alt_outlined,
                color: AppColors.primary,
              ),
              title: const Text('إضافة زميل جديد'),
              onTap: () => Navigator.pop(context, '__add__'),
            ),
            const Divider(),
            for (final colleague in _colleagues)
              ListTile(
                leading: const Icon(Icons.group_outlined),
                title: Text(colleague.name),
                onTap: () => Navigator.pop(context, '${colleague.id}'),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == '__add__') {
      await _addColleagueDialog();
      return;
    }
    final id = int.parse(choice);
    final colleague = _colleagues.where((c) => c.id == id).firstOrNull;
    if (colleague == null) return;
    if (_shares.any((s) => s.colleagueId == id)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذا الزميل مضاف مسبقاً')));
      return;
    }
    setState(() {
      _shares.add(
        _ShareEntry(
          personType: SaleShare.personColleague,
          colleagueId: id,
          label: colleague.name,
        ),
      );
    });
  }

  Future<void> _addColleagueDialog() async {
    final result = await showNameDialog(context, title: 'إضافة زميل جديد');
    if (result == null) return;
    final name = result.name;
    final id = await _db.insertColleague(Colleague(name: name));
    final colleagues = await _db.getColleagues();
    if (!mounted) return;
    setState(() {
      _colleagues = colleagues;
      _shares.add(
        _ShareEntry(
          personType: SaleShare.personColleague,
          colleagueId: id,
          label: name,
        ),
      );
    });
  }

  Future<void> _save() async {
    final settings = _settings;
    if (settings == null) return;
    if (!_formKey.currentState!.validate()) return;
    if (_client == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('اختر الزبون')));
      return;
    }

    if (_shared && (_totalSharePercent - 100).abs() > 0.001) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.danger,
            size: 34,
          ),
          title: const Text('النسب لا تساوي 100%'),
          content: Text(
            'مجموع نسب المشاركين يجب أن يساوي 100% بالضبط.\n'
            'المجموع الحالي: ${Formatters.number(_totalSharePercent)}%',
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(context),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
      return;
    }

    final period = AppDateUtils.workMonthFor(_date, settings.workMonthStartDay);
    final sale = Sale(
      id: _isEdit ? widget.existing!.sale.id : 0,
      date: AppDateUtils.toStorage(_date),
      clientId: _client!.id,
      orderType: _orderType,
      area: _area,
      commissionRate: _rate,
      isShared: _shared,
      status: _status,
      workMonth: period.monthName,
      workYear: period.year,
    );

    final shares = <SaleShare>[
      if (_shared)
        for (final s in _shares)
          if (s.value > 0)
            SaleShare(
              saleId: sale.id,
              personType: s.personType,
              colleagueId: s.colleagueId,
              sharePercentage: s.value,
            ),
    ];

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await _db.updateSale(sale, shares);
      } else {
        await _db.insertSale(sale, shares);
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر حفظ البيع، حاول مجدداً')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'تعديل البيع' : 'إضافة بيع جديد')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildClientField(),
                  const SizedBox(height: 14),
                  _buildOrderTypeField(),
                  const SizedBox(height: 14),
                  _buildDateField(),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _areaController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'المساحة (متر مربع)',
                      prefixIcon: Icon(Icons.straighten_outlined, size: 20),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final area = Formatters.parseAmount(v ?? '');
                      if (area == null || area <= 0) {
                        return 'أدخل مساحة صحيحة';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'نسبة العمولة',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _RateButton(
                          label: '1.5%',
                          selected: _rate == 0.015,
                          onTap: () => setState(() => _rate = 0.015),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _RateButton(
                          label: '2%',
                          selected: _rate == 0.02,
                          onTap: () => setState(() => _rate = 0.02),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'نوع البيع',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.person_outline),
                        label: Text('فردي'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.group_outlined),
                        label: Text('مشترك'),
                      ),
                    ],
                    selected: {_shared},
                    onSelectionChanged: (s) =>
                        setState(() => _shared = s.first),
                    showSelectedIcon: false,
                  ),
                  if (_shared) ...[
                    const SizedBox(height: 14),
                    _buildSharesEditor(),
                  ],
                  if (_isEdit) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'حالة البيع',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _status,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.flag_outlined, size: 20),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: SaleStatus.pending,
                          child: Text('معلّق'),
                        ),
                        DropdownMenuItem(
                          value: SaleStatus.confirmed,
                          child: Text('مؤكد'),
                        ),
                        DropdownMenuItem(
                          value: SaleStatus.paid,
                          child: Text('مدفوع'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _status = v!),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _buildCommissionPreview(),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.check),
                    label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ البيع'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  Widget _buildClientField() {
    return ListTile(
      onTap: _pickClient,
      tileColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      leading: const Icon(Icons.person_outline, color: AppColors.primary),
      title: const Text('الزبون'),
      subtitle: Text(
        _client?.name ?? 'اختر زبوناً أو أضف زبوناً جديداً',
        style: TextStyle(
          color: _client == null
              ? AppColors.textSecondary
              : AppColors.textPrimary,
          fontWeight: _client == null ? null : FontWeight.w600,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
    );
  }

  Widget _buildOrderTypeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'نوع الطلب / المنتج',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: OrderType.kitchen,
                icon: Icon(Icons.soup_kitchen_outlined, size: 16),
                label: Text('مطبخ'),
              ),
              ButtonSegment(
                value: OrderType.dressing,
                icon: Icon(Icons.checkroom_outlined, size: 16),
                label: Text('دريسنج'),
              ),
              ButtonSegment(
                value: OrderType.closet,
                icon: Icon(Icons.inventory_2_outlined, size: 16),
                label: Text('خزانة'),
              ),
              ButtonSegment(
                value: OrderType.other,
                icon: Icon(Icons.more_horiz, size: 16),
                label: Text('أخرى'),
              ),
            ],
            selected: {_orderType},
            onSelectionChanged: (s) => setState(() => _orderType = s.first),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              selectedBackgroundColor: AppColors.primaryContainer,
              selectedForegroundColor: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField() {
    return ListTile(
      onTap: _pickDate,
      tileColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      leading: const Icon(Icons.event_outlined, color: AppColors.primary),
      title: const Text('التاريخ'),
      subtitle: Text(AppDateUtils.display(AppDateUtils.toStorage(_date))),
      trailing: const Icon(Icons.edit_outlined, size: 18),
    );
  }

  Widget _buildSharesEditor() {
    final total = _totalSharePercent;
    final isFull = (total - 100).abs() <= 0.001;
    final hasOver = total > 100.001;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: CardShadow.soft(),
        border: Border.all(
          color: isFull
              ? AppColors.success
              : hasOver
              ? AppColors.danger
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'توزيع النسب المشتركة',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Text(
                'المجموع: ${Formatters.number(total)}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isFull
                      ? AppColors.success
                      : hasOver
                      ? AppColors.danger
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isFull ? 'النسب مكتملة (100%)' : 'يجب أن يساوي المجموع 100%',
            style: TextStyle(
              fontSize: 12,
              color: isFull ? AppColors.success : AppColors.danger,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < _shares.length; i++) _buildShareRow(i),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _addColleagueShare,
            icon: const Icon(Icons.group_add_outlined, size: 18),
            label: const Text('إضافة زميل للمشاركة'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildShareRow(int index) {
    final entry = _shares[index];
    final isMe = entry.personType == SaleShare.personMe;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isMe ? AppColors.primaryContainer : AppColors.successLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isMe ? Icons.person : Icons.group_outlined,
              size: 18,
              color: isMe ? AppColors.primary : AppColors.success,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.label,
              style: const TextStyle(fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 76,
            child: TextField(
              controller: entry.percent,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                isDense: true,
                suffixText: '%',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (!isMe)
            IconButton(
              onPressed: () {
                setState(() {
                  entry.dispose();
                  _shares.removeAt(index);
                });
              },
              icon: const Icon(Icons.close, size: 18),
              color: AppColors.danger,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _buildCommissionPreview() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.infoLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          if (_shared)
            Text(
              'نصيبي: ${Formatters.number(_mySharePercent)}%',
              style: const TextStyle(fontSize: 13),
            ),
          const SizedBox(height: 6),
          Text(
            'عمولتي المتوقعة: ${Formatters.money(_commissionPreview)}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.info,
            ),
          ),
        ],
      ),
    );
  }
}

class _RateButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RateButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
