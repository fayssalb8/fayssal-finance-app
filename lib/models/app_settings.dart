/// طرائق التعويض المدعومة.
class CompensationMode {
  static const salaryBonus = 'salary_bonus';
  static const commissionOnly = 'commission_only';

  static String title(String mode) {
    return mode == commissionOnly ? 'عمولة فقط' : 'راتب شهري + عمولة صغيرة';
  }

  static String description(String mode) {
    return mode == commissionOnly
        ? 'لا يوجد راتب شهري؛ الأجر من العمولات، والساعات الإضافية تُسلّم '
              'بسعر متفق عليه، والغياب يُسجّل فقط ضد العطلة.'
        : 'راتب شهري ثابت مع عمولة صغيرة إضافية، ويُحسب سعر الساعة من '
              'الراتب لخصم الغياب ومكافأة الساعات الإضافية.';
  }
}

/// طريقة حساب قيمة الساعة الإضافية (تُضبط من الإعدادات).
class OvertimeRateMode {
  static const auto = 'auto';
  static const custom = 'custom';
}

class AppSettings {
  final int id;
  final double baseSalary;
  final double overtimeMultiplier;
  final double pricePerMeter;
  final int workMonthStartDay;
  final int annualLeaveBalance;
  final String compensationMode;
  final bool hasOnboarded;
  final String overtimeRateMode;
  final double customOvertimeRate;
  final double paymentTarget;

  const AppSettings({
    this.id = 1,
    this.baseSalary = 0,
    this.overtimeMultiplier = 1.5,
    this.pricePerMeter = 30000,
    this.workMonthStartDay = 7,
    this.annualLeaveBalance = 30,
    this.compensationMode = CompensationMode.salaryBonus,
    this.hasOnboarded = false,
    this.overtimeRateMode = OvertimeRateMode.auto,
    this.customOvertimeRate = 0,
    this.paymentTarget = 0,
  });

  bool get isCommissionOnly =>
      compensationMode == CompensationMode.commissionOnly;

  /// في وضع "عمولة فقط" لا يوجد راتب لتحديد سعر تلقائي، لذا يُفرض سعر ثابت.
  bool get useCustomOvertimeRate =>
      isCommissionOnly || overtimeRateMode == OvertimeRateMode.custom;

  AppSettings copyWith({
    int? id,
    double? baseSalary,
    double? overtimeMultiplier,
    double? pricePerMeter,
    int? workMonthStartDay,
    int? annualLeaveBalance,
    String? compensationMode,
    bool? hasOnboarded,
    String? overtimeRateMode,
    double? customOvertimeRate,
    double? paymentTarget,
  }) {
    return AppSettings(
      id: id ?? this.id,
      baseSalary: baseSalary ?? this.baseSalary,
      overtimeMultiplier: overtimeMultiplier ?? this.overtimeMultiplier,
      pricePerMeter: pricePerMeter ?? this.pricePerMeter,
      workMonthStartDay: workMonthStartDay ?? this.workMonthStartDay,
      annualLeaveBalance: annualLeaveBalance ?? this.annualLeaveBalance,
      compensationMode: compensationMode ?? this.compensationMode,
      hasOnboarded: hasOnboarded ?? this.hasOnboarded,
      overtimeRateMode: overtimeRateMode ?? this.overtimeRateMode,
      customOvertimeRate: customOvertimeRate ?? this.customOvertimeRate,
      paymentTarget: paymentTarget ?? this.paymentTarget,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'base_salary': baseSalary,
      'overtime_multiplier': overtimeMultiplier,
      'price_per_meter': pricePerMeter,
      'work_month_start_day': workMonthStartDay,
      'annual_leave_balance': annualLeaveBalance,
      'compensation_mode': compensationMode,
      'has_onboarded': hasOnboarded ? 1 : 0,
      'overtime_rate_mode': overtimeRateMode,
      'custom_overtime_rate': customOvertimeRate,
      'payment_target': paymentTarget,
    };
  }

  factory AppSettings.fromMap(Map<String, Object?> map) {
    return AppSettings(
      id: map['id'] as int? ?? 1,
      baseSalary: (map['base_salary'] as num?)?.toDouble() ?? 0,
      overtimeMultiplier:
          (map['overtime_multiplier'] as num?)?.toDouble() ?? 1.5,
      pricePerMeter: (map['price_per_meter'] as num?)?.toDouble() ?? 30000,
      workMonthStartDay: map['work_month_start_day'] as int? ?? 7,
      annualLeaveBalance: map['annual_leave_balance'] as int? ?? 30,
      compensationMode:
          map['compensation_mode'] as String? ?? CompensationMode.salaryBonus,
      hasOnboarded: (map['has_onboarded'] as int? ?? 0) == 1,
      overtimeRateMode:
          map['overtime_rate_mode'] as String? ?? OvertimeRateMode.auto,
      customOvertimeRate:
          (map['custom_overtime_rate'] as num?)?.toDouble() ?? 0,
      paymentTarget: (map['payment_target'] as num?)?.toDouble() ?? 0,
    );
  }
}
