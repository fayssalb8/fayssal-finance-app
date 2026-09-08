class MonthlySalaryOverride {
  final int id;
  final String workMonth;
  final int workYear;
  final double actualSalary;

  const MonthlySalaryOverride({
    this.id = 0,
    required this.workMonth,
    required this.workYear,
    required this.actualSalary,
  });

  factory MonthlySalaryOverride.fromMap(Map<String, Object?> map) {
    return MonthlySalaryOverride(
      id: map['id'] as int? ?? 0,
      workMonth: map['work_month'] as String? ?? '',
      workYear: map['work_year'] as int? ?? 0,
      actualSalary: (map['actual_salary'] as num?)?.toDouble() ?? 0,
    );
  }
}
