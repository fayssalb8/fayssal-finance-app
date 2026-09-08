import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/date_utils.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/app_database.dart';
import '../../models/app_settings.dart';
import '../../models/time_record.dart';
import '../../services/finance_service.dart';

/// شاشة إضافة أو تعديل سجل وقت (إضافي / غياب / بونص).
class TimeRecordFormScreen extends StatefulWidget {
  final String initialType;

  /// سجل موجود للتعديل؛ عند وجوده تُفتح الشاشة وضع "تعديل".
  final TimeRecord? existing;

  const TimeRecordFormScreen({
    super.key,
    required this.initialType,
    this.existing,
  });

  @override
  State<TimeRecordFormScreen> createState() => _TimeRecordFormScreenState();
}

class _TimeRecordFormScreenState extends State<TimeRecordFormScreen> {
  final _db = AppDatabase.instance;
  late final FinanceService _finance = FinanceService(_db);

  late String _type;
  late DateTime _date;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  final _daysController = TextEditingController();
  final _bonusController = TextEditingController();
  final _reasonController = TextEditingController();
  final _rateController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isManualRate = false;
  AppSettings? _settings;
  int _remainingLeave = 0;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;
  bool get _isOvertime => _type == TimeRecordType.overtime;
  bool get _isBonus => _type == TimeRecordType.bonus;
  bool get _isAbsence =>
      _type == TimeRecordType.absenceHours ||
      _type == TimeRecordType.absenceDays;
  bool get _absenceByDays => _type == TimeRecordType.absenceDays;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _type = existing.type;
      _date = AppDateUtils.fromStorage(existing.date) ?? DateTime.now();
      final start = _parseTime(existing.startTime);
      final end = _parseTime(existing.endTime);
      final isOT = existing.isOvertime;
      _startTime = start ??
          (isOT
              ? const TimeOfDay(hour: 17, minute: 0)
              : const TimeOfDay(hour: 9, minute: 0));
      _endTime = end ??
          (isOT
              ? const TimeOfDay(hour: 19, minute: 0)
              : const TimeOfDay(hour: 12, minute: 0));
      if (existing.isBonus) {
        _bonusController.text = _numText(existing.totalValue);
      }
      if (existing.isAbsenceDays) {
        _daysController.text = '${existing.daysCount}';
      }
      if (existing.customRate != null && existing.customRate! > 0) {
        _isManualRate = true;
        _rateController.text = _numText(existing.customRate!);
      }
      _reasonController.text = existing.reason ?? '';
    } else {
      _type = switch (widget.initialType) {
        TimeRecordType.bonus => TimeRecordType.bonus,
        TimeRecordType.absenceDays => TimeRecordType.absenceDays,
        TimeRecordType.absenceHours => TimeRecordType.absenceHours,
        _ => TimeRecordType.overtime,
      };
      _date = DateTime.now();
      final isOT = _type == TimeRecordType.overtime;
      _startTime = isOT
          ? const TimeOfDay(hour: 17, minute: 0)
          : const TimeOfDay(hour: 9, minute: 0);
      _endTime = isOT
          ? const TimeOfDay(hour: 19, minute: 0)
          : const TimeOfDay(hour: 12, minute: 0);
    }
    _load();
  }

  @override
  void dispose() {
    _daysController.dispose();
    _bonusController.dispose();
    _reasonController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  static TimeOfDay? _parseTime(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return TimeOfDay(hour: h, minute: m);
  }

  static String _numText(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  Future<void> _load() async {
    final settings = await _db.getSettings();
    final remaining = await _finance.remainingLeave(settings);
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _remainingLeave = remaining;
    });
  }

  /// رصيد العطلة المتاح لهذا الإدخال:
  /// عند التعديل تُعاد أيام السجل نفسه إلى الرصيد قبل المقارنة.
  int get _availableLeave {
    final ownDays = _isEdit && widget.existing!.isAbsenceDays
        ? widget.existing!.daysCount
        : 0;
    return _remainingLeave + ownDays;
  }

  double get _hours => AppDateUtils.hoursBetween(
    '${_startTime.hour}:${_startTime.minute.toString().padLeft(2, '0')}',
    '${_endTime.hour}:${_endTime.minute.toString().padLeft(2, '0')}',
  );

  double get _computedValue {
    final settings = _settings;
    if (settings == null) return 0;
    if (_isOvertime) {
      if (_isManualRate) {
        final manualRate = Formatters.parseAmount(_rateController.text) ?? 0;
        return manualRate * _hours;
      }
      return _finance.overtimeAmount(settings, _hours);
    }
    if (_type == TimeRecordType.absenceHours) {
      if (_isManualRate) {
        final manualRate = Formatters.parseAmount(_rateController.text) ?? 0;
        return manualRate * _hours;
      }
      if (settings.isCommissionOnly) return 0;
      return _finance.absenceHoursAmount(settings, _hours);
    }
    return 0;
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

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _startTime : _endTime,
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  String _timeLabel(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _save() async {
    final settings = _settings;
    if (settings == null) return;
    if (!_formKey.currentState!.validate()) return;

    if ((_isOvertime || _type == TimeRecordType.absenceHours) && _hours <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب أن يكون وقت النهاية بعد وقت البداية')),
      );
      return;
    }

    if (_absenceByDays) {
      final days = Formatters.parseInt(_daysController.text) ?? 0;
      if (days > _availableLeave) {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('رصيد العطلة غير كافٍ'),
            content: Text(
              'رصيد العطلة المتاح لهذا الإدخال هو $_availableLeave يوم، '
              'وأنت تُدخل $days يوم غياب.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('حسناً'),
              ),
            ],
          ),
        );
        return;
      }
    }

    if ((_isOvertime || _type == TimeRecordType.absenceHours) && _isManualRate) {
      final rate = Formatters.parseAmount(_rateController.text);
      if (rate == null || rate <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى إدخال سعر الساعة اليدوي بشكل صحيح')),
        );
        return;
      }
    }

    final period = AppDateUtils.workMonthFor(_date, settings.workMonthStartDay);
    final usesTime = _isOvertime || _type == TimeRecordType.absenceHours;
    final double? savedCustomRate = _isManualRate
        ? (Formatters.parseAmount(_rateController.text) ?? 0)
        : null;

    final record = TimeRecord(
      id: widget.existing?.id ?? 0,
      date: AppDateUtils.toStorage(_date),
      type: _type,
      startTime: usesTime ? _timeLabel(_startTime) : null,
      endTime: usesTime ? _timeLabel(_endTime) : null,
      totalValue: _isBonus
          ? (Formatters.parseAmount(_bonusController.text) ?? 0)
          : _computedValue,
      daysCount: _absenceByDays
          ? Formatters.parseInt(_daysController.text) ?? 0
          : 0,
      reason: _reasonController.text.trim().isEmpty
          ? null
          : _reasonController.text.trim(),
      customRate: savedCustomRate,
      workMonth: period.monthName,
      workYear: period.year,
    );

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await _db.updateTimeRecord(record);
      } else {
        await _db.insertTimeRecord(record);
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر حفظ السجل، حاول مجدداً')),
      );
    }
  }

  String get _screenTitle {
    final action = _isEdit ? 'تعديل' : 'إضافة';
    return switch (_type) {
      TimeRecordType.overtime => '$action ساعات إضافية',
      TimeRecordType.bonus => '$action بونص',
      _ => '$action غياب',
    };
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return Scaffold(
      appBar: AppBar(title: Text(_screenTitle)),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_isAbsence) _buildAbsenceTypeSelector(),
                  if (_isAbsence) const SizedBox(height: 16),
                  _buildDateField(),
                  const SizedBox(height: 14),
                  if (_isOvertime || _type == TimeRecordType.absenceHours) ...[
                    _buildRateSection(settings),
                    const SizedBox(height: 14),
                  ],
                  if (_isOvertime || _type == TimeRecordType.absenceHours)
                    _buildTimeFields(),
                  if (_absenceByDays) _buildDaysField(settings),
                  if (_isBonus) _buildBonusField(),
                  if (_isBonus || _isOvertime) const SizedBox(height: 14),
                  TextFormField(
                    controller: _reasonController,
                    decoration: const InputDecoration(
                      labelText: 'السبب (اختياري)',
                      prefixIcon: Icon(Icons.notes_outlined, size: 20),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 20),
                  _buildAmountPreview(settings),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.check),
                    label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ السجل'),
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

  Widget _buildAbsenceTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'نوع الغياب',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: TimeRecordType.absenceHours,
                icon: Icon(Icons.schedule_outlined, size: 18),
                label: Text('غياب بالساعات (خصم مالي)'),
              ),
              ButtonSegment(
                value: TimeRecordType.absenceDays,
                icon: Icon(Icons.calendar_today_outlined, size: 18),
                label: Text('غياب بالأيام (خصم عطلة)'),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: AppColors.dangerLight,
              selectedForegroundColor: AppColors.danger,
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRateSection(AppSettings settings) {
    final defaultRate = _isOvertime
        ? _finance.overtimeRatePerHour(settings)
        : _finance.hourlyRate(settings);

    final title = _isOvertime ? 'تسعير الساعة الإضافية' : 'تسعير ساعة الغياب';
    final autoDescription = _isOvertime
        ? (settings.useCustomOvertimeRate
            ? 'سعر ثابت من الإعدادات: ${Formatters.money(settings.customOvertimeRate)}/ساعة'
            : 'تلقائي من الراتب: ${Formatters.money(defaultRate)}/ساعة (معامل ${Formatters.number(settings.overtimeMultiplier)})')
        : (settings.isCommissionOnly
            ? 'وضع "عمولة فقط": بدون خصم تلقائي'
            : 'تلقائي من الراتب: ${Formatters.money(defaultRate)}/ساعة');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: CardShadow.soft(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('تلقائي', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('يدوي', style: TextStyle(fontSize: 12)),
                  ),
                ],
                selected: {_isManualRate},
                onSelectionChanged: (selection) {
                  setState(() {
                    _isManualRate = selection.first;
                    if (_isManualRate && _rateController.text.trim().isEmpty) {
                      final existing = widget.existing;
                      final existingRate = (existing != null &&
                              existing.totalValue > 0 &&
                              _hours > 0)
                          ? (existing.totalValue / _hours)
                          : null;
                      final fillRate = existingRate ??
                          (defaultRate > 0 ? defaultRate : 0);
                      _rateController.text = _numText(fillRate);
                    }
                  });
                },
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  selectedBackgroundColor: _isOvertime
                      ? AppColors.primaryContainer
                      : AppColors.dangerLight,
                  selectedForegroundColor: _isOvertime
                      ? AppColors.primary
                      : AppColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!_isManualRate)
            Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    autoDescription,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            )
          else ...[
            TextFormField(
              controller: _rateController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,٫]')),
              ],
              onChanged: (_) => setState(() {}),
              validator: (v) {
                if (!_isManualRate) return null;
                final parsed = Formatters.parseAmount(v ?? '');
                if (parsed == null || parsed <= 0) {
                  return 'يرجى إدخال سعر ساعة صحيح أكبر من صفر';
                }
                return null;
              },
              decoration: InputDecoration(
                labelText: _isOvertime
                    ? 'سعر الساعة الإضافية اليدوي (دج)'
                    : 'سعر ساعة الغياب للخصم (دج)',
                prefixIcon: const Icon(Icons.payments_outlined, size: 20),
                isDense: true,
                helperText: 'أدخل المبلغ المحسوب لكل ساعة واحدة',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBonusField() {
    return TextFormField(
      controller: _bonusController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,٫]'))],
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(
        labelText: 'قيمة البونص (دج)',
        prefixIcon: Icon(Icons.card_giftcard_outlined, size: 20),
      ),
      validator: (v) {
        final value = Formatters.parseAmount(v ?? '');
        if (value == null || value <= 0) return 'أدخل قيمة البونص';
        return null;
      },
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

  Widget _buildTimeFields() {
    return Row(
      children: [
        Expanded(
          child: ListTile(
            onTap: () => _pickTime(start: true),
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.border),
            ),
            leading: const Icon(Icons.login, color: AppColors.primary),
            title: const Text('البداية'),
            subtitle: Text(_timeLabel(_startTime)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ListTile(
            onTap: () => _pickTime(start: false),
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.border),
            ),
            leading: const Icon(Icons.logout, color: AppColors.primary),
            title: const Text('النهاية'),
            subtitle: Text(_timeLabel(_endTime)),
          ),
        ),
      ],
    );
  }

  Widget _buildDaysField(AppSettings settings) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: CardShadow.soft(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _daysController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'عدد أيام الغياب',
              prefixIcon: Icon(Icons.calendar_today_outlined, size: 20),
            ),
            validator: (v) {
              final days = Formatters.parseInt(v ?? '');
              if (days == null || days <= 0) return 'أدخل عدد أيام صحيح';
              return null;
            },
          ),
          const SizedBox(height: 8),
          Text(
            'رصيد العطلة المتاح: $_availableLeave من '
            '${settings.annualLeaveBalance} يوم',
            style: TextStyle(
              fontSize: 12,
              color: _availableLeave <= 0
                  ? AppColors.danger
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountPreview(AppSettings settings) {
    if (_absenceByDays) return const SizedBox.shrink();

    if (_isBonus) {
      final value = Formatters.parseAmount(_bonusController.text) ?? 0;
      return _previewBox(
        color: AppColors.gold,
        background: AppColors.warningLight,
        lines: ['قيمة البونص: + ${Formatters.money(value)}'],
      );
    }

    if (_isOvertime) {
      final rateLine = _isManualRate
          ? 'سعر يدوي مخصص: ${Formatters.money(Formatters.parseAmount(_rateController.text) ?? 0)}/ساعة'
          : (settings.useCustomOvertimeRate
              ? 'سعر الساعة الثابت: ${Formatters.money(settings.customOvertimeRate)}'
              : 'سعر الساعة: ${Formatters.money(_finance.hourlyRate(settings))} '
                    '× معامل ${Formatters.number(settings.overtimeMultiplier)}');
      return _previewBox(
        color: AppColors.success,
        background: AppColors.successLight,
        lines: [
          'عدد الساعات: ${Formatters.hours(_hours)}',
          'المبلغ المستحق: + ${Formatters.money(_computedValue)}',
          rateLine,
        ],
      );
    }

    // غياب بالساعات
    if (settings.isCommissionOnly && !_isManualRate) {
      return _previewBox(
        color: AppColors.danger,
        background: AppColors.dangerLight,
        lines: [
          'عدد الساعات: ${Formatters.hours(_hours)}',
          'وضع "عمولة فقط": الغياب يُسجَّل فقط بدون خصم مالي',
        ],
      );
    }
    final absenceRateLine = _isManualRate
        ? 'خصم بسعر يدوي: ${Formatters.money(Formatters.parseAmount(_rateController.text) ?? 0)}/ساعة'
        : 'سعر الساعة: ${Formatters.money(_finance.hourlyRate(settings))}';
    return _previewBox(
      color: AppColors.danger,
      background: AppColors.dangerLight,
      lines: [
        'عدد الساعات: ${Formatters.hours(_hours)}',
        'الخصم من الراتب: - ${Formatters.money(_computedValue)}',
        absenceRateLine,
      ],
    );
  }

  Widget _previewBox({
    required Color color,
    required Color background,
    required List<String> lines,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            Text(
              lines[i],
              style: TextStyle(
                fontSize: i == lines.length - 1 && lines.length > 2
                    ? 11
                    : i == 1
                    ? 18
                    : 13,
                fontWeight: i == 1 ? FontWeight.bold : null,
                color: i == lines.length - 1 && lines.length > 2
                    ? AppColors.textSecondary
                    : color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
