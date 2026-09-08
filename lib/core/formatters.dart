import 'package:intl/intl.dart';

class Formatters {
  static final NumberFormat _currency = NumberFormat.currency(
    locale: 'ar',
    symbol: 'دج',
    decimalDigits: 0,
  );

  static final NumberFormat _number = NumberFormat('#,##0.##', 'ar');

  /// مثال: 1,250,000 دج
  static String money(double value) => _currency.format(value);

  /// مثال: 250,000
  static String number(num value) => _number.format(value);

  /// مثال: "3.5 ساعات"
  static String hours(double value) {
    final formatted = value == value.roundToDouble()
        ? _number.format(value.toInt())
        : _number.format(value);
    return '$formatted ساعة';
  }

  /// يحول نص إدخال (قد يحتوي فواصل أو أرقاماً عربية/فارسية أو فواصل عشرية مختلفة) إلى رقم.
  static double? parseAmount(String raw) {
    var s = raw
        .replaceAll(' ', '')
        .replaceAll('\u00A0', '')
        .replaceAll('\u202F', '')
        .replaceAll('\u200B', '')
        .replaceAll('دج', '')
        .replaceAll('DA', '')
        .replaceAll('DZD', '')
        .trim();

    if (s.isEmpty) return null;

    // تحويل الأرقام العربية المشرقية والفارسية
    const easternArabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const western = '0123456789';
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(easternArabic[i], western[i]);
      s = s.replaceAll(persian[i], western[i]);
    }

    // فاصلة الألوف العربية ٬ وفاصلة الأعداد العشرية العربية ٫
    s = s.replaceAll('٬', '');
    s = s.replaceAll('٫', '.');

    // معالجة الفواصل والنقاط
    if (s.contains(',') && s.contains('.')) {
      if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
        // نمط أوروبي: 1.250,50
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else {
        // نمط أنجلوسكسوني: 1,250.50
        s = s.replaceAll(',', '');
      }
    } else if (s.contains(',')) {
      final parts = s.split(',');
      if (parts.length == 2 && parts[1].length != 3) {
        // فاصلة عشرية مثل 12,5 أو 1,75
        s = '${parts[0]}.${parts[1]}';
      } else {
        // فاصلة ألوف مثل 50,000 أو 1,000,000
        s = s.replaceAll(',', '');
      }
    }

    return double.tryParse(s);
  }

  static int? parseInt(String raw) {
    return parseAmount(raw)?.round();
  }
}
