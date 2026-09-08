class TimeRecordType {
  static const overtime = 'overtime';
  static const absenceHours = 'absence_hours';
  static const absenceDays = 'absence_days';
  static const bonus = 'bonus';
}

class TimeRecord {
  final int id;
  final String date;
  final String type;
  final String? startTime;
  final String? endTime;
  final double totalValue;
  final int daysCount;
  final String? reason;
  final double? customRate;
  final String workMonth;
  final int workYear;

  const TimeRecord({
    this.id = 0,
    required this.date,
    required this.type,
    this.startTime,
    this.endTime,
    this.totalValue = 0,
    this.daysCount = 0,
    this.reason,
    this.customRate,
    required this.workMonth,
    required this.workYear,
  });

  bool get isOvertime => type == TimeRecordType.overtime;
  bool get isAbsenceHours => type == TimeRecordType.absenceHours;
  bool get isAbsenceDays => type == TimeRecordType.absenceDays;
  bool get isBonus => type == TimeRecordType.bonus;

  Map<String, Object?> toMap() {
    return {
      if (id != 0) 'id': id,
      'date': date,
      'type': type,
      'start_time': startTime,
      'end_time': endTime,
      'total_value': totalValue,
      'days_count': daysCount,
      'reason': reason,
      'custom_rate': customRate,
      'work_month': workMonth,
      'work_year': workYear,
    };
  }

  factory TimeRecord.fromMap(Map<String, Object?> map) {
    return TimeRecord(
      id: map['id'] as int? ?? 0,
      date: map['date'] as String? ?? '',
      type: map['type'] as String? ?? '',
      startTime: map['start_time'] as String?,
      endTime: map['end_time'] as String?,
      totalValue: (map['total_value'] as num?)?.toDouble() ?? 0,
      daysCount: map['days_count'] as int? ?? 0,
      reason: map['reason'] as String?,
      customRate: (map['custom_rate'] as num?)?.toDouble(),
      workMonth: map['work_month'] as String? ?? '',
      workYear: map['work_year'] as int? ?? 0,
    );
  }
}
