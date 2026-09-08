import 'package:intl/intl.dart';

class WorkMonthPeriod {
  final int month;
  final int year;
  final String monthName;
  final DateTime startDate;
  final DateTime endDate;

  const WorkMonthPeriod({
    required this.month,
    required this.year,
    required this.monthName,
    required this.startDate,
    required this.endDate,
  });

  /// مثال: "مارس 2026"
  String get label => '$monthName $year';

  /// مثال: "7 مارس → 6 أفريل"
  String get rangeLabel =>
      '${startDate.day} ${ArabicNames.months[startDate.month - 1]} → '
      '${endDate.day} ${ArabicNames.months[endDate.month - 1]}';
}

class ArabicNames {
  static const months = [
    'جانفي',
    'فيفري',
    'مارس',
    'أفريل',
    'ماي',
    'جوان',
    'جويلية',
    'أوت',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  static const weekdays = [
    'الأحد',
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
  ];
}

class AppDateUtils {
  static final DateFormat _storageFormat = DateFormat('yyyy-MM-dd');

  /// التاريخ يُخزن دائماً بصيغة YYYY-MM-DD
  static String toStorage(DateTime date) => _storageFormat.format(date);

  static DateTime? fromStorage(String value) {
    try {
      return _storageFormat.parseStrict(value);
    } catch (_) {
      return null;
    }
  }

  /// يعرض التاريخ بصيغة مقروءة: "7 مارس 2026"
  static String display(String storageDate) {
    final dt = fromStorage(storageDate);
    if (dt == null) return storageDate;
    return '${dt.day} ${ArabicNames.months[dt.month - 1]} ${dt.year}';
  }

  /// يحدد شهر العمل لسجل معين بناءً على يوم بداية الشهر.
  /// مثال: يوم البداية 7، والتاريخ 5 أفريل → يعود لشهر "مارس".
  static WorkMonthPeriod workMonthFor(DateTime date, int startDay) {
    final actualStartDay = startDay.clamp(1, 28);
    if (date.day >= actualStartDay) {
      return workMonthPeriod(date.month, date.year, actualStartDay);
    }
    final prev = DateTime(date.year, date.month - 1, 1);
    return workMonthPeriod(prev.month, prev.year, actualStartDay);
  }

  static WorkMonthPeriod workMonthPeriod(int month, int year, int startDay) {
    final normalized = DateTime(year, month, 1);
    final normYear = normalized.year;
    final normMonth = normalized.month;
    final actualStartDay = startDay.clamp(1, 28);
    final startDate = DateTime(normYear, normMonth, actualStartDay);
    final endDate = DateTime(normYear, normMonth + 1, actualStartDay - 1);
    return WorkMonthPeriod(
      month: normMonth,
      year: normYear,
      monthName: ArabicNames.months[normMonth - 1],
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// يضيف أياماً بشكل تقويمي دقيق دون تأثر باختلافات التوقيت الصيفي.
  static DateTime addDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);


  /// عدد ساعات العمل بين وقتين بصيغة HH:mm (مع دعم تجاوز منتصف الليل).
  static double hoursBetween(String startTime, String endTime) {
    final start = _timeInMinutes(startTime);
    final end = _timeInMinutes(endTime);
    if (start == null || end == null) return 0;

    var totalMinutes = end - start;
    if (totalMinutes < 0) totalMinutes += 24 * 60;
    return totalMinutes / 60.0;
  }

  static int? _timeInMinutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }
}
