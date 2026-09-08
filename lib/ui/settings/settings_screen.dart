import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_card.dart';
import '../../data/app_database.dart';
import '../../models/app_settings.dart';
import '../../services/finance_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _db = AppDatabase.instance;
  late final FinanceService _finance = FinanceService(_db);

  final _formKey = GlobalKey<FormState>();
  AppSettings? _settings;
  bool _saving = false;

  late final TextEditingController _salaryController;
  late final TextEditingController _multiplierController;
  late final TextEditingController _pricePerMeterController;
  late final TextEditingController _startDayController;
  late final TextEditingController _leaveController;
  late final TextEditingController _customOvertimeRateController;
  late final TextEditingController _targetController;

  String? _overtimeMode;

  @override
  void initState() {
    super.initState();
    _salaryController = TextEditingController();
    _multiplierController = TextEditingController();
    _pricePerMeterController = TextEditingController();
    _startDayController = TextEditingController();
    _leaveController = TextEditingController();
    _customOvertimeRateController = TextEditingController();
    _targetController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _salaryController.dispose();
    _multiplierController.dispose();
    _pricePerMeterController.dispose();
    _startDayController.dispose();
    _leaveController.dispose();
    _customOvertimeRateController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _db.getSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _salaryController.text = _num(settings.baseSalary);
      _multiplierController.text = _num(settings.overtimeMultiplier);
      _pricePerMeterController.text = _num(settings.pricePerMeter);
      _startDayController.text = '${settings.workMonthStartDay}';
      _leaveController.text = '${settings.annualLeaveBalance}';
      _overtimeMode = settings.overtimeRateMode;
      _customOvertimeRateController.text = _num(settings.customOvertimeRate);
      _targetController.text = _num(settings.paymentTarget);
    });
  }

  String _num(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final settings = _settings;
    if (settings == null) return;

    setState(() => _saving = true);
    final commissionOnly = settings.isCommissionOnly;
    final updated = settings.copyWith(
      baseSalary: commissionOnly
          ? 0
          : Formatters.parseAmount(_salaryController.text) ?? 0,
      overtimeMultiplier: commissionOnly
          ? 1.5
          : Formatters.parseAmount(_multiplierController.text) ?? 1.5,
      pricePerMeter: Formatters.parseAmount(_pricePerMeterController.text) ?? 0,
      workMonthStartDay: int.parse(_startDayController.text),
      annualLeaveBalance: int.parse(_leaveController.text),
      overtimeRateMode: commissionOnly
          ? OvertimeRateMode.custom
          : _overtimeMode ?? OvertimeRateMode.auto,
      customOvertimeRate:
          Formatters.parseAmount(_customOvertimeRateController.text) ?? 0,
      paymentTarget: Formatters.parseAmount(_targetController.text) ?? 0,
    );
    try {
      await _db.updateSettings(updated);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر حفظ الإعدادات، حاول مجدداً')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _settings = updated;
      _saving = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات بنجاح')));
  }

  String? _validateNumber(String? value, {required String label}) {
    final v = Formatters.parseAmount(value ?? '');
    if (v == null || v < 0) return 'أدخل $label بشكل صحيح';
    return null;
  }

  String? _validateDay(String? value) {
    final v = int.tryParse(value ?? '');
    if (v == null || v < 1 || v > 28) {
      return 'يوم بداية الشهر بين 1 و 28';
    }
    return null;
  }

  String? _validateLeave(String? value) {
    final v = int.tryParse(value ?? '');
    if (v == null || v < 0) return 'أدخل رصيد العطلة بشكل صحيح';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final hourly = settings == null ? 0.0 : _finance.hourlyRate(settings);
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildInfoBanner(settings, hourly),
                  const SizedBox(height: 16),
                  _buildModeCard(settings),
                  const SizedBox(height: 16),
                  if (!settings.isCommissionOnly) ...[
                    _SectionCard(
                      title: 'الراتب والسعر',
                      children: [
                        _buildField(
                          label: 'الراتب الأساسي الافتراضي (دج)',
                          controller: _salaryController,
                          icon: Icons.payments_outlined,
                          validator: (v) =>
                              _validateNumber(v, label: 'الراتب الأساسي'),
                        ),
                        _buildField(
                          label: 'معامل الساعات الإضافية',
                          controller: _multiplierController,
                          icon: Icons.timer_outlined,
                          helper: 'مثال: 1.5 = ساعة ونصف لكل ساعة إضافية',
                          validator: (v) =>
                              _validateNumber(v, label: 'معامل الإضافي'),
                        ),
                        _buildField(
                          label: 'سعر المتر المربع (دج)',
                          controller: _pricePerMeterController,
                          icon: Icons.straighten_outlined,
                          validator: (v) =>
                              _validateNumber(v, label: 'سعر المتر'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ] else
                    _SectionCard(
                      title: 'سعر المتر المربع (دج)',
                      children: [
                        _buildField(
                          label: 'سعر المتر المربع (دج)',
                          controller: _pricePerMeterController,
                          icon: Icons.straighten_outlined,
                          validator: (v) =>
                              _validateNumber(v, label: 'سعر المتر'),
                        ),
                      ],
                    ),
                  if (!settings.isCommissionOnly) const SizedBox(height: 16),
                  _buildOvertimeRateCard(settings),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'شهر العمل والعطل',
                    children: [
                      _buildField(
                        label: 'يوم بداية شهر العمل',
                        controller: _startDayController,
                        icon: Icons.event_outlined,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        helper:
                            'مثال: 7 يعني أن الشهر يبدأ يوم 7 وينتهي يوم 6 من الشهر الموالي',
                        validator: _validateDay,
                      ),
                      _buildField(
                        label: 'رصيد العطلة السنوية (أيام)',
                        controller: _leaveController,
                        icon: Icons.beach_access_outlined,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: _validateLeave,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _SectionCard(
                    title: 'هدف المبلغ الإجمالي',
                    children: [
                      _buildField(
                        label: 'المبلغ المستهدف (دج)',
                        controller: _targetController,
                        icon: Icons.track_changes_outlined,
                        helper:
                            'من لوحة التحكم يُحسب المتبقي وساعات العمل '
                            'الإضافية المطلوبة للوصول إلى هذا الهدف كل شهر.',
                        validator: (v) =>
                            _validateNumber(v, label: 'المبلغ المستهدف'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ الإعدادات'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoBanner(AppSettings settings, double hourly) {
    final text = settings.isCommissionOnly
        ? 'وضع "عمولة فقط": لا يوجد راتب شهري، '
              'والساعات الإضافية تُسلّم بسعر ثابت '
              'تضبطه من الأسفل في هذه الشاشة.'
        : 'سعر الساعة يُحسب تلقائيًا: الراتب الأساسي ÷ 174 '
              '(${Formatters.money(hourly)} / ساعة)';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.infoLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.info, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.info, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOvertimeRateCard(AppSettings settings) {
    final selectedMode = settings.isCommissionOnly
        ? OvertimeRateMode.custom
        : _overtimeMode ?? OvertimeRateMode.auto;
    final useCustom = selectedMode == OvertimeRateMode.custom;
    final autoRate =
        _finance.hourlyRate(settings) * settings.overtimeMultiplier;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'حساب الساعات الإضافية',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'بهذه الطريقة تُحسب قيمة كل ساعة إضافية، '
            'ولن يُطلب منك الاختيار كل مرة.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: OvertimeRateMode.auto,
                icon: Icon(Icons.calculate_outlined),
                label: Text('تلقائي من الراتب'),
              ),
              ButtonSegment(
                value: OvertimeRateMode.custom,
                icon: Icon(Icons.payments_outlined),
                label: Text('سعر ثابت'),
              ),
            ],
            selected: {selectedMode},
            onSelectionChanged: settings.isCommissionOnly
                ? null
                : (s) => setState(() => _overtimeMode = s.first),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: AppColors.primaryContainer,
              selectedForegroundColor: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          if (settings.isCommissionOnly)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.infoLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'في وضع "عمولة فقط" لا يوجد راتب، لذا يُفرض سعر ثابت.',
                style: TextStyle(color: AppColors.info, fontSize: 12),
              ),
            ),
          const SizedBox(height: 4),
          if (useCustom)
            _buildField(
              label: 'سعر الساعة الثابت (دج)',
              controller: _customOvertimeRateController,
              icon: Icons.payments_outlined,
              helper: 'يُستخدم هذا السعر لحساب قيمة الساعات الإضافية.',
              validator: (v) => _validateOvertimeRate(v, required: useCustom),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'السعر التلقائي: ${Formatters.money(autoRate)}/ساعة '
                '(الراتب ÷ 174 × معامل '
                '${Formatters.number(settings.overtimeMultiplier)})',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String? _validateOvertimeRate(String? value, {required bool required}) {
    if (required) {
      final v = Formatters.parseAmount(value ?? '');
      if (v == null || v <= 0) return 'أدخل سعر الساعة الثابت';
    }
    return _validateNumber(value, label: 'سعر الساعة الثابت');
  }

  Widget _buildModeCard(AppSettings settings) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: settings.isCommissionOnly
                  ? AppColors.infoLight
                  : AppColors.successLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              settings.isCommissionOnly
                  ? Icons.trending_up
                  : Icons.payments_outlined,
              color: settings.isCommissionOnly
                  ? AppColors.info
                  : AppColors.success,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'طريقة التعويض',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                Text(
                  CompensationMode.title(settings.compensationMode),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => _changeMode(settings),
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('تغيير'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeMode(AppSettings settings) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('اختر طريقة التعويض'),
        children: [
          for (final mode in [
            CompensationMode.salaryBonus,
            CompensationMode.commissionOnly,
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, mode),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      mode == CompensationMode.salaryBonus
                          ? Icons.payments_outlined
                          : Icons.trending_up,
                      color: mode == CompensationMode.salaryBonus
                          ? AppColors.success
                          : AppColors.info,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            CompensationMode.title(mode),
                            style: const TextStyle(fontSize: 15),
                          ),
                          Text(
                            CompensationMode.description(mode),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (selected == null || selected == settings.compensationMode) return;

    final updated = settings.copyWith(compensationMode: selected);
    await _db.updateSettings(updated);
    if (!mounted) return;
    setState(() {
      _settings = updated;
      if (updated.isCommissionOnly) {
        _salaryController.text = '0';
        _multiplierController.text = '1.5';
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم ضبط الوضع على ${CompensationMode.title(selected)}'),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String? Function(String?) validator,
    String? helper,
    bool enabled = true,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType:
            keyboardType ??
            const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: inputFormatters,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          helperText: helper,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
