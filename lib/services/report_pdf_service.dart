import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/date_utils.dart';
import '../core/formatters.dart';
import '../data/app_database.dart';
import '../models/app_settings.dart';
import '../models/sale.dart';
import '../models/time_record.dart';
import '../services/finance_service.dart';

/// ملخص شهري واحد داخل تقرير يغطي عدة شهور عمل.
class MonthlyReportRow {
  final String monthName;
  final int year;
  final bool isCommissionOnly;
  final double actualSalary;
  final double overtime;
  final double bonus;
  final double absenceDeduction;
  final double netDue;
  final double grandTotal;

  const MonthlyReportRow({
    required this.monthName,
    required this.year,
    required this.isCommissionOnly,
    required this.actualSalary,
    required this.overtime,
    required this.bonus,
    required this.absenceDeduction,
    required this.netDue,
    required this.grandTotal,
  });
}

/// بيانات تقرير الدخل (الراتب + الإضافي + البونص + الغياب).
/// العمولات تُدار في تقرير منفصل ([CommissionReportData]).
class IncomeReportData {
  final AppSettings settings;
  final String periodTitle;
  final double actualSalary;
  final List<TimeRecord> overtimeRecords;
  final List<TimeRecord> absenceHoursRecords;
  final List<TimeRecord> absenceDaysRecords;
  final List<TimeRecord> bonusRecords;
  final List<MonthlyReportRow> monthlyBreakdown;

  const IncomeReportData({
    required this.settings,
    required this.periodTitle,
    required this.actualSalary,
    required this.overtimeRecords,
    required this.absenceHoursRecords,
    required this.absenceDaysRecords,
    required this.bonusRecords,
    required this.monthlyBreakdown,
  });

  bool get isCommissionOnly => settings.isCommissionOnly;

  double get overtimeTotal =>
      overtimeRecords.fold(0, (sum, r) => sum + r.totalValue);

  double get overtimeHoursTotal => overtimeRecords.fold(
    0,
    (sum, r) =>
        sum + AppDateUtils.hoursBetween(r.startTime ?? '', r.endTime ?? ''),
  );

  double get bonusTotal => bonusRecords.fold(0, (sum, r) => sum + r.totalValue);

  double get absenceHoursTotal =>
      absenceHoursRecords.fold(0, (sum, r) => sum + r.totalValue);

  double get absenceHoursCount => absenceHoursRecords.fold(
    0,
    (sum, r) =>
        sum + AppDateUtils.hoursBetween(r.startTime ?? '', r.endTime ?? ''),
  );

  int get absenceDaysCount =>
      absenceDaysRecords.fold(0, (sum, r) => sum + r.daysCount);

  double get absenceHoursDeduction => isCommissionOnly ? 0 : absenceHoursTotal;

  /// صافي الراتب (بدون عمولات وبدون البونص).
  double get netDue => actualSalary - absenceHoursDeduction + overtimeTotal;

  /// الإجمالي العام = صافي الراتب + البونص؛ يطابق لوحة التحكم.
  double get grandTotal => netDue + bonusTotal;
}

/// بيانات تقرير عمولات المبيعات (منفصل تماما عن تقرير الدخل).
class CommissionReportData {
  final AppSettings settings;
  final String periodTitle;
  final List<SaleWithCommission> sales;

  const CommissionReportData({
    required this.settings,
    required this.periodTitle,
    required this.sales,
  });

  double get totalCommission =>
      sales.fold(0, (sum, s) => sum + s.userCommission);

  double get totalArea => sales.fold(0, (sum, s) => sum + s.sale.area);
}

/// إنشاء تقارير PDF:
///
/// * [generateIncomeReport]: الراتب، الإضافي، البونص، الغياب، والخلاصة —
///   مع إجمالي بعد كل قسم. العمولات لا تظهر هنا.
/// * [generateCommissionReport]: تقرير مستقل لعمولات المبيعات بإجمالي خاص.
class ReportPdfService {
  static const _fontAsset = 'assets/fonts/NotoNaskhArabic.ttf';

  final AppDatabase db;
  final FinanceService finance;

  ReportPdfService(this.db, this.finance);

  // ---------------------------------------------------------------------------
  // تحميل البيانات
  // ---------------------------------------------------------------------------

  Future<(IncomeReportData, CommissionReportData)> _loadData({
    required DateTime from,
    required DateTime to,
  }) async {
    final settings = await db.getSettings();
    final period = AppDateUtils.workMonthFor(from, settings.workMonthStartDay);
    final override = await db.getSalaryOverride(period.monthName, period.year);
    final actualSalary = override?.actualSalary ?? settings.baseSalary;

    final fromS = AppDateUtils.toStorage(from);
    final toS = AppDateUtils.toStorage(to);
    final periodTitle =
        'من ${AppDateUtils.display(fromS)} إلى ${AppDateUtils.display(toS)}';

    final timeRecords = await db.getTimeRecordsBetween(fromS, toS);
    List<TimeRecord> timeByType(String type) =>
        timeRecords.where((r) => r.type == type).toList();

    final sales = await db.getSalesBetween(fromS, toS);
    final salesWithCommission = <SaleWithCommission>[];
    for (final sale in sales) {
      salesWithCommission.add(await finance.saleWithCommission(sale, settings));
    }

    final breakdown = <MonthlyReportRow>[];
    final periods = _workMonthsBetween(from, to, settings.workMonthStartDay);
    for (final p in periods) {
      final s = await finance.summaryFor(
        month: p.month,
        year: p.year,
        startDay: settings.workMonthStartDay,
        settings: settings,
      );
      breakdown.add(
        MonthlyReportRow(
          monthName: p.monthName,
          year: p.year,
          isCommissionOnly: s.isCommissionOnly,
          actualSalary: s.actualSalary,
          overtime: s.overtimeTotal,
          bonus: s.bonusTotal,
          absenceDeduction: s.absenceHoursDeduction,
          netDue: s.netDue,
          grandTotal: s.grandTotal,
        ),
      );
    }

    final effectiveSalary = breakdown.isNotEmpty
        ? breakdown.fold<double>(0, (sum, b) => sum + b.actualSalary)
        : actualSalary;

    final income = IncomeReportData(
      settings: settings,
      periodTitle: periodTitle,
      actualSalary: effectiveSalary,
      overtimeRecords: timeByType(TimeRecordType.overtime),
      absenceHoursRecords: timeByType(TimeRecordType.absenceHours),
      absenceDaysRecords: timeByType(TimeRecordType.absenceDays),
      bonusRecords: timeByType(TimeRecordType.bonus),
      monthlyBreakdown: breakdown,
    );

    final commission = CommissionReportData(
      settings: settings,
      periodTitle: periodTitle,
      sales: salesWithCommission,
    );

    return (income, commission);
  }

  List<WorkMonthPeriod> _workMonthsBetween(
    DateTime from,
    DateTime to,
    int startDay,
  ) {
    final result = <WorkMonthPeriod>[];
    var cursor = AppDateUtils.workMonthFor(from, startDay);
    var guard = 0;
    while (!cursor.startDate.isAfter(to) && guard < 200) {
      result.add(cursor);
      cursor = AppDateUtils.workMonthFor(
        AppDateUtils.addDays(cursor.endDate, 1),
        startDay,
      );
      guard++;
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // إنشاء تقرير الدخل
  // ---------------------------------------------------------------------------

  Future<Uint8List> generateIncomeReport({
    required DateTime from,
    required DateTime to,
    PdfPageFormat format = PdfPageFormat.a4,
  }) async {
    final (data, _) = await _loadData(from: from, to: to);
    final doc = await _newDocument('تقرير المستحقات');

    doc.addPage(
      _newPage(format, [
        _header(
          title: 'تقرير المستحقات',
          subtitle: data.periodTitle,
          note: data.isCommissionOnly
              ? 'طريقة التعويض: عمولة فقط (بدون راتب شهري)'
              : 'طريقة التعويض: راتب شهري + عمولة صغيرة',
        ),
        pw.SizedBox(height: 18),

        _section(
          'أولاً: الراتب',
          _rowsTable(
            headers: const ['البند', 'المبلغ'],
            rows: [
              if (!data.isCommissionOnly)
                [
                  data.monthlyBreakdown.length > 1
                      ? 'إجمالي الراتب الأساسي (${data.monthlyBreakdown.length} أشهر)'
                      : 'الراتب الأساسي / الفعلي',
                  Formatters.money(data.actualSalary),
                ],
            ],
            totals: data.isCommissionOnly
                ? null
                : ('قيمة الراتب', Formatters.money(data.actualSalary)),
          ),
          footnote: data.isCommissionOnly
              ? 'وضع "عمولة فقط": لا يوجد راتب شهري؛ الأجر من '
                    'العمولات (تقرير منفصل)، والغياب يُسجَّل فقط ضد '
                    'العطلة بدون خصم مالي.'
              : null,
        ),

            _section(
              'ثانياً: الساعات الإضافية',
              data.overtimeRecords.isEmpty
                  ? _emptyHint('لا توجد ساعات إضافية في هذه الفترة.')
                  : _rowsTable(
                      headers: const ['التاريخ', 'الوقت', 'الساعات', 'المبلغ'],
                      rows: [
                        for (final r in data.overtimeRecords)
                          [
                            AppDateUtils.display(r.date),
                            '${r.startTime} - ${r.endTime}',
                            Formatters.hours(
                              AppDateUtils.hoursBetween(
                                r.startTime ?? '',
                                r.endTime ?? '',
                              ),
                            ),
                            Formatters.money(r.totalValue),
                          ],
                      ],
                      totals: (
                        'الإجمالي: ${Formatters.hours(data.overtimeHoursTotal)}',
                        Formatters.money(data.overtimeTotal),
                      ),
                    ),
            ),

            _section(
              'ثالثاً: البونص',
              data.bonusRecords.isEmpty
                  ? _emptyHint('لا يوجد بونص في هذه الفترة.')
                  : _rowsTable(
                      headers: const ['التاريخ', 'السبب', 'المبلغ'],
                      rows: [
                        for (final r in data.bonusRecords)
                          [
                            AppDateUtils.display(r.date),
                            r.reason ?? '—',
                            Formatters.money(r.totalValue),
                          ],
                      ],
                      totals: (
                        'إجمالي البونص',
                        Formatters.money(data.bonusTotal),
                      ),
                    ),
            ),

            _section(
              'رابعاً: الغياب',
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  if (data.absenceHoursRecords.isEmpty &&
                      data.absenceDaysRecords.isEmpty)
                    _emptyHint('لا يوجد غياب في هذه الفترة.')
                  else ...[
                    if (data.absenceHoursRecords.isNotEmpty) ...[
                      _miniTitle('غياب بالساعات'),
                      _rowsTable(
                        headers: const ['التاريخ', 'الوقت', 'الساعات', 'الخصم'],
                        rows: [
                          for (final r in data.absenceHoursRecords)
                            [
                              AppDateUtils.display(r.date),
                              '${r.startTime} - ${r.endTime}',
                              Formatters.hours(
                                AppDateUtils.hoursBetween(
                                  r.startTime ?? '',
                                  r.endTime ?? '',
                                ),
                              ),
                              data.isCommissionOnly
                                  ? '—'
                                  : Formatters.money(r.totalValue),
                            ],
                        ],
                        totals: (
                          'الإجمالي: ${Formatters.hours(data.absenceHoursCount)}',
                          data.isCommissionOnly
                              ? 'بدون خصم'
                              : Formatters.money(data.absenceHoursTotal),
                        ),
                      ),
                    ],
                    if (data.absenceDaysRecords.isNotEmpty) ...[
                      pw.SizedBox(height: 10),
                      _miniTitle('غياب بالأيام (يُخصم من رصيد العطلة)'),
                      _rowsTable(
                        headers: const ['التاريخ', 'الأيام', 'السبب'],
                        rows: [
                          for (final r in data.absenceDaysRecords)
                            [
                              AppDateUtils.display(r.date),
                              '${r.daysCount} يوم',
                              r.reason ?? '—',
                            ],
                        ],
                        totals: (
                          'الأيام المستهلكة من العطلة',
                          '${data.absenceDaysCount} يوم',
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),

            _section(
              'خامساً: الخلاصة النهائية',
              pw.Column(
                children: [
                  if (!data.isCommissionOnly)
                    _summaryRow(
                      data.monthlyBreakdown.length > 1
                          ? 'إجمالي الراتب الأساسي (${data.monthlyBreakdown.length} أشهر)'
                          : 'الراتب الأساسي / الفعلي',
                      Formatters.money(data.actualSalary),
                    ),
                  _summaryRow(
                    'الساعات الإضافية',
                    '+ ${Formatters.money(data.overtimeTotal)}',
                  ),
                  _summaryRow(
                    data.isCommissionOnly ? 'الغياب (مسجّل فقط)' : 'خصم الغياب',
                    data.isCommissionOnly
                        ? '0 دج'
                        : '- ${Formatters.money(data.absenceHoursDeduction)}',
                  ),
                  _highlightRow(
                    'صافي الراتب (بدون بونص وعمولات)',
                    Formatters.money(data.netDue),
                    background: PdfColors.teal50,
                    textColor: PdfColors.teal800,
                  ),
                  pw.SizedBox(height: 6),
                  _summaryRow(
                    'البونص',
                    '+ ${Formatters.money(data.bonusTotal)}',
                  ),
                  _highlightRow(
                    'الإجمالي العام (صافي الراتب + البونص)',
                    Formatters.money(data.grandTotal),
                    background: PdfColors.amber,
                    textColor: PdfColors.black,
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'عمولات المبيعات منفصلة: راجع "تقرير عمولات المبيعات" '
                    'لنفس الفترة.',
                    style: pw.TextStyle(fontSize: 9, color: _muted),
                  ),
                ],
              ),
            ),

            if (data.monthlyBreakdown.length > 1)
              _section(
                'سادساً: الملخص الشهري',
                pw.TableHelper.fromTextArray(
                  headers: const [
                    'الشهر',
                    'الراتب',
                    'إضافي',
                    'بونص',
                    'غياب',
                    'صافي',
                    'الإجمالي',
                  ],
                  data: [
                    for (final row in data.monthlyBreakdown)
                      [
                        '${row.monthName} ${row.year}',
                        row.isCommissionOnly
                            ? 'بدون'
                            : Formatters.money(row.actualSalary),
                        Formatters.money(row.overtime),
                        Formatters.money(row.bonus),
                        Formatters.money(row.absenceDeduction),
                        Formatters.money(row.netDue),
                        Formatters.money(row.grandTotal),
                      ],
                  ],
                  headerStyle: _headerStyle(fontSize: 8),
                  headerDecoration: pw.BoxDecoration(color: _accent),
                  cellAlignment: pw.Alignment.center,
                  cellStyle: pw.TextStyle(color: _text, fontSize: 8),
                  border: pw.TableBorder.all(
                    color: PdfColors.grey300,
                    width: 0.5,
                  ),
                ),
              ),

        pw.SizedBox(height: 24),
        _signatures(),
        _footer(),
      ]),
    );

    return doc.save();
  }

  // ---------------------------------------------------------------------------
  // إنشاء تقرير العمولات (منفصل)
  // ---------------------------------------------------------------------------

  Future<Uint8List> generateCommissionReport({
    required DateTime from,
    required DateTime to,
    PdfPageFormat format = PdfPageFormat.a4,
  }) async {
    final (_, data) = await _loadData(from: from, to: to);
    final doc = await _newDocument('تقرير عمولات المبيعات');

    doc.addPage(
      _newPage(format, [
        _header(
          title: 'تقرير عمولات المبيعات',
          subtitle: data.periodTitle,
          note:
              'تقرير مستقل عن المستحقات الشهرية؛ العمولات لا تدخل في '
              'حساب الإجمالي العام للراتب.',
        ),
        pw.SizedBox(height: 18),

            _section(
              'أولاً: المبيعات والعمولات',
              data.sales.isEmpty
                  ? _emptyHint('لا توجد مبيعات في هذه الفترة.')
                  : _rowsTable(
                      headers: const [
                        'الزبون',
                        'الطلب',
                        'التاريخ',
                        'المساحة',
                        'النسبة',
                        'العمولة',
                        'النوع',
                      ],
                      rows: [
                        for (final s in data.sales)
                          [
                            s.sale.clientId != null
                                ? (s.clientName ?? '—')
                                : '—',
                            s.sale.orderType,
                            AppDateUtils.display(s.sale.date),
                            '${Formatters.number(s.sale.area)} م²',
                            '${Formatters.number(s.sale.commissionRate * 100)}%',
                            Formatters.money(s.userCommission),
                            s.sale.isShared ? 'مشترك (${_myShare(s)})' : 'فردي',
                          ],
                      ],
                      totals: (
                        'الإجمالي: ${Formatters.number(data.totalArea)} متر مربع',
                        Formatters.money(data.totalCommission),
                      ),
                    ),
            ),

            _section(
              'ثانياً: خلاصة العمولات',
              pw.Column(
                children: [
                  _summaryRow('عدد المبيعات', '${data.sales.length}'),
                  _summaryRow(
                    'إجمالي المساحة المباعة',
                    '${Formatters.number(data.totalArea)} متر مربع',
                  ),
                  _highlightRow(
                    'إجمالي عمولاتي',
                    Formatters.money(data.totalCommission),
                    background: PdfColors.amber,
                    textColor: PdfColors.black,
                  ),
                ],
              ),
            ),

        pw.SizedBox(height: 24),
        _signatures(),
        _footer(),
      ]),
    );

    return doc.save();
  }

  // ---------------------------------------------------------------------------
  // مكوّنات المستند المشتركة
  // ---------------------------------------------------------------------------

  static const _accent = PdfColors.teal800;
  static const _text = PdfColors.grey900;
  static const _muted = PdfColors.grey700;

  Future<pw.Document> _newDocument(String title) async {
    final fontData = await rootBundle.load(_fontAsset);
    final font = pw.Font.ttf(fontData);
    return pw.Document(
      theme: pw.ThemeData.withFont(
        base: font,
        bold: font,
        italic: font,
        boldItalic: font,
      ),
      title: title,
      author: 'Smart Kitchen Finance',
    );
  }

  pw.MultiPage _newPage(PdfPageFormat format, List<pw.Widget> children) =>
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(28),
        textDirection: pw.TextDirection.rtl,
        build: (_) => [for (final child in children) _directional(child)],
      );

  pw.Widget _directional(pw.Widget child) =>
      pw.Directionality(textDirection: pw.TextDirection.rtl, child: child);

  pw.TextStyle _headerStyle({double fontSize = 11}) => pw.TextStyle(
    color: PdfColors.white,
    fontWeight: pw.FontWeight.bold,
    fontSize: fontSize,
  );

  pw.Widget _header({
    required String title,
    required String subtitle,
    required String note,
  }) => pw.Center(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            color: _accent,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(subtitle, style: pw.TextStyle(fontSize: 11, color: _muted)),
        pw.SizedBox(height: 4),
        pw.Text(note, style: pw.TextStyle(fontSize: 10, color: _muted)),
      ],
    ),
  );

  pw.Widget _sectionTitle(String title) => pw.Container(
    width: double.infinity,
    color: _accent,
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    child: pw.Text(
      title,
      style: pw.TextStyle(
        color: PdfColors.white,
        fontWeight: pw.FontWeight.bold,
        fontSize: 12,
      ),
    ),
  );

  pw.Widget _section(String title, pw.Widget body, {String? footnote}) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(title),
          pw.SizedBox(height: 4),
          body,
          if (footnote != null) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              'ملاحظة: $footnote',
              style: pw.TextStyle(fontSize: 9, color: _muted),
            ),
          ],
          pw.SizedBox(height: 14),
        ],
      );

  pw.Widget _miniTitle(String title) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Text(
      title,
      style: pw.TextStyle(
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
        color: _text,
      ),
    ),
  );

  pw.Widget _emptyHint(String text) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 8),
    child: pw.Text(text, style: pw.TextStyle(color: _muted, fontSize: 10)),
  );

  /// جدول صفوف مع صف إجمالي عريض ملوّن في الأسفل.
  /// التسمية في العمود الأول والقيمة في العمود الأخير.
  pw.Widget _rowsTable({
    required List<String> headers,
    required List<List<String>> rows,
    (String, String)? totals,
  }) {
    final hasTotals = totals != null;
    // الصف 0 هو الترويسة، وصف الإجمالي آخر صف.
    final totalRowNum = hasTotals ? rows.length + 1 : -1;

    final data = <List<dynamic>>[
      ...rows,
      if (hasTotals)
        [totals.$1, for (var i = 1; i < headers.length - 1; i++) '', totals.$2],
    ];

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: _headerStyle(),
      headerDecoration: pw.BoxDecoration(color: _accent),
      cellStyle: pw.TextStyle(color: _text, fontSize: 10),
      textStyleBuilder: hasTotals
          ? (index, cell, rowNum) => rowNum == totalRowNum
                ? pw.TextStyle(
                    color: _accent,
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  )
                : null
          : null,
      cellDecoration: hasTotals
          ? (index, cell, rowNum) => rowNum == totalRowNum
                ? pw.BoxDecoration(color: PdfColors.teal50)
                : pw.BoxDecoration()
          : null,
      columnWidths: const {0: pw.FlexColumnWidth(1.6)},
      cellAlignments: {
        for (var i = 0; i < headers.length; i++)
          i: i == 0 ? pw.Alignment.centerRight : pw.Alignment.center,
      },
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    );
  }

  pw.Widget _summaryRow(String label, String value) => pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
      ),
    ),
    padding: const pw.EdgeInsets.symmetric(vertical: 5),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 10.5, color: _text)),
        pw.Text(value, style: pw.TextStyle(fontSize: 10.5, color: _text)),
      ],
    ),
  );

  pw.Widget _highlightRow(
    String label,
    String value, {
    required PdfColor background,
    required PdfColor textColor,
  }) => pw.Container(
    decoration: pw.BoxDecoration(
      color: background,
      borderRadius: pw.BorderRadius.circular(4),
    ),
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 12.5,
            color: textColor,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 12.5,
            color: textColor,
          ),
        ),
      ],
    ),
  );

  pw.Widget _signatures() => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      for (var i = 0; i < 2; i++) ...[
        if (i > 0) pw.SizedBox(width: 40),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                height: 45,
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey600, width: 0.7),
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                i == 0 ? 'توقيع الموظف' : 'توقيع صاحب العمل',
                style: pw.TextStyle(fontSize: 10, color: _muted),
              ),
            ],
          ),
        ),
      ],
    ],
  );

  pw.Widget _footer() => pw.Column(
    children: [
      pw.SizedBox(height: 16),
      pw.Center(
        child: pw.Text(
          'تم الإنشاء بواسطة تطبيق Smart Kitchen Finance',
          style: pw.TextStyle(fontSize: 8, color: _muted),
        ),
      ),
    ],
  );

  String _myShare(SaleWithCommission sale) {
    final my = sale.shares
        .where((s) => s.personType == SaleShare.personMe)
        .firstOrNull;
    return my != null ? '${Formatters.number(my.sharePercentage)}%' : '0%';
  }
}
