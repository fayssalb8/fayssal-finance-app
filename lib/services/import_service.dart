import 'package:sqflite/sqflite.dart';

import '../core/date_utils.dart';
import '../core/formatters.dart';
import '../data/app_database.dart';
import '../models/app_settings.dart';
import '../models/client.dart';
import '../models/sale.dart';
import '../models/time_record.dart';
import 'finance_service.dart';

/// يمثل سطراً تم تحليله مع حالته وبياناته.
class ParsedImportRow<T> {
  final int lineNumber;
  final List<String> rawColumns;
  final T? data;
  final bool isValid;
  final String? error;
  final String? extraInfo;

  const ParsedImportRow({
    required this.lineNumber,
    required this.rawColumns,
    this.data,
    required this.isValid,
    this.error,
    this.extraInfo,
  });
}

/// نتيجة تحليل النص للمعاينة قبل الحفظ.
class ImportPreviewResult<T> {
  final String categoryTitle;
  final List<ParsedImportRow<T>> rows;
  final bool hasHeader;

  const ImportPreviewResult({
    required this.categoryTitle,
    required this.rows,
    required this.hasHeader,
  });

  int get totalCount => rows.length;
  int get validCount => rows.where((r) => r.isValid).length;
  int get errorCount => rows.where((r) => !r.isValid).length;
  bool get canImport => validCount > 0;
  List<T> get validData =>
      rows.where((r) => r.isValid && r.data != null).map((r) => r.data!).toList();
}

/// هيكل مبيعة محتملة مع اسم زبون جديد في حال لم يكن مسجلاً.
class ParsedSaleItem {
  final Sale sale;
  final String clientName;
  final bool isNewClient;

  const ParsedSaleItem({
    required this.sale,
    required this.clientName,
    required this.isNewClient,
  });
}

/// خدمة استيراد البيانات من ملفات Excel و CSV والنصوص.
class ImportService {
  final AppDatabase db;
  late final FinanceService _finance = FinanceService(db);

  ImportService(this.db);

  // ---------------------------------------------------------------------------
  // أدوات التحليل الأساسية (Smart CSV / TSV / Text Parser)
  // ---------------------------------------------------------------------------

  /// يفكك النص إلى أسطر وأعمدة مع كشف تلقائي للفاصل (Tab, Semicolon, Comma).
  static List<List<String>> splitRows(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    final result = <List<String>>[];

    for (final rawLine in lines) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;

      // تحديد الفاصل الأكثر ملاءمة للسطر
      String delimiter = ',';
      if (trimmed.contains('\t')) {
        delimiter = '\t';
      } else if (trimmed.contains(';') && !trimmed.contains(',')) {
        delimiter = ';';
      } else if (trimmed.contains(';') && trimmed.contains(',')) {
        final semiCount = ';'.allMatches(trimmed).length;
        final commaCount = ','.allMatches(trimmed).length;
        delimiter = semiCount >= commaCount ? ';' : ',';
      }

      final cols = _parseCsvLine(trimmed, delimiter);
      if (cols.any((c) => c.isNotEmpty)) {
        result.add(cols);
      }
    }
    return result;
  }

  static List<String> _parseCsvLine(String line, String delimiter) {
    final cols = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++; // تخطي الاقتباس المزدوج
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == delimiter && !inQuotes) {
        cols.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    cols.add(buffer.toString().trim());
    return cols;
  }

  /// تحويل النصوص المختلفة إلى تاريخ صحيح.
  static DateTime? parseDate(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;

    final direct = DateTime.tryParse(s);
    if (direct != null) return direct;

    final parts = s.split(RegExp(r'[/.-]'));
    if (parts.length == 3) {
      final p0 = int.tryParse(parts[0]);
      final p1 = int.tryParse(parts[1]);
      final p2 = int.tryParse(parts[2]);
      if (p0 != null && p1 != null && p2 != null) {
        if (p0 >= 1900 && p0 <= 2100) {
          // YYYY-MM-DD
          return DateTime(p0, p1, p2);
        } else if (p2 >= 1900 && p2 <= 2100) {
          // DD/MM/YYYY
          return DateTime(p2, p1, p0);
        }
      }
    }
    return null;
  }

  /// تحويل نص الوقت إلى صيغة HH:mm.
  static String? parseTime(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    s = s.replaceAll('h', ':');

    final parts = s.split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null && h >= 0 && h < 24 && m >= 0 && m < 60) {
        return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
      }
    } else if (parts.length == 1) {
      final h = int.tryParse(parts[0]);
      if (h != null && h >= 0 && h < 24) {
        return '${h.toString().padLeft(2, '0')}:00';
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // استيراد الزبائن (Clients Import)
  // ---------------------------------------------------------------------------

  Future<ImportPreviewResult<Client>> parseClients(
    String content, {
    List<Client>? existingClients,
  }) async {
    final existing = existingClients ?? await db.getClients();
    final existingNames = {for (final c in existing) c.name.trim().toLowerCase()};

    final rawRows = splitRows(content);
    final parsedRows = <ParsedImportRow<Client>>[];
    var hasHeader = false;

    for (var i = 0; i < rawRows.length; i++) {
      final cols = rawRows[i];
      final lineNum = i + 1;

      // فحص هل السطر رأس عمود (Header)
      if (i == 0 && _isClientHeader(cols)) {
        hasHeader = true;
        continue;
      }

      if (cols.isEmpty || cols[0].trim().isEmpty) {
        parsedRows.add(
          ParsedImportRow(
            lineNumber: lineNum,
            rawColumns: cols,
            isValid: false,
            error: 'اسم الزبون مطلوب ولا يمكن تركه فارغاً',
          ),
        );
        continue;
      }

      final name = cols[0].trim();
      final phone = cols.length > 1 && cols[1].trim().isNotEmpty
          ? cols[1].trim()
          : null;

      final isAlreadyKnown = existingNames.contains(name.toLowerCase());
      final duplicateTag = isAlreadyKnown ? ' (زبون مسجل / طلب إضافي)' : '';

      parsedRows.add(
        ParsedImportRow(
          lineNumber: lineNum,
          rawColumns: cols,
          isValid: true,
          data: Client(name: name, phone: phone),
          extraInfo: phone != null ? 'هاتف: $phone$duplicateTag' : 'بدون رقم هاتف$duplicateTag',
        ),
      );
    }

    return ImportPreviewResult(
      categoryTitle: 'الزبائن',
      rows: parsedRows,
      hasHeader: hasHeader,
    );
  }

  static bool _isClientHeader(List<String> cols) {
    if (cols.isEmpty) return false;
    final first = cols[0].toLowerCase();
    return first.contains('اسم') ||
        first.contains('name') ||
        first.contains('client') ||
        first.contains('زبون');
  }

  // ---------------------------------------------------------------------------
  // استيراد الساعات الإضافية (Overtime Import)
  // ---------------------------------------------------------------------------

  ImportPreviewResult<TimeRecord> parseOvertime(
    String content,
    AppSettings settings,
  ) {
    final rawRows = splitRows(content);
    final parsedRows = <ParsedImportRow<TimeRecord>>[];
    var hasHeader = false;

    for (var i = 0; i < rawRows.length; i++) {
      final cols = rawRows[i];
      final lineNum = i + 1;

      if (i == 0 && _isOvertimeHeader(cols)) {
        hasHeader = true;
        continue;
      }

      // الأعمدة المتوقعة: [التاريخ, البداية (اختياري: افتراضي 17:00), النهاية (اختياري: افتراضي 19:00), سعر يدوي (اختياري), السبب (اختياري)]
      if (cols.isEmpty || cols[0].trim().isEmpty) {
        parsedRows.add(
          ParsedImportRow(
            lineNumber: lineNum,
            rawColumns: cols,
            isValid: false,
            error: 'تاريخ الساعات الإضافية مطلوب',
          ),
        );
        continue;
      }

      final date = parseDate(cols[0]);
      if (date == null) {
        parsedRows.add(
          ParsedImportRow(
            lineNumber: lineNum,
            rawColumns: cols,
            isValid: false,
            error: 'صيغة التاريخ غير صالحة: "${cols[0]}" (المطلوب: YYYY-MM-DD أو DD/MM/YYYY)',
          ),
        );
        continue;
      }

      final startStr = cols.length > 1 && cols[1].trim().isNotEmpty
          ? parseTime(cols[1])
          : '17:00';
      final endStr = cols.length > 2 && cols[2].trim().isNotEmpty
          ? parseTime(cols[2])
          : '19:00';

      if (startStr == null) {
        parsedRows.add(
          ParsedImportRow(
            lineNumber: lineNum,
            rawColumns: cols,
            isValid: false,
            error: 'وقت البداية غير صالح: "${cols[1]}"',
          ),
        );
        continue;
      }
      if (endStr == null) {
        parsedRows.add(
          ParsedImportRow(
            lineNumber: lineNum,
            rawColumns: cols,
            isValid: false,
            error: 'وقت النهاية غير صالح: "${cols[2]}"',
          ),
        );
        continue;
      }

      final hours = AppDateUtils.hoursBetween(startStr, endStr);
      if (hours <= 0) {
        parsedRows.add(
          ParsedImportRow(
            lineNumber: lineNum,
            rawColumns: cols,
            isValid: false,
            error: 'يجب أن يكون وقت النهاية ($endStr) بعد وقت البداية ($startStr)',
          ),
        );
        continue;
      }

      // السعر اليدوي (إن وجد)
      double? customRate;
      if (cols.length > 3 && cols[3].trim().isNotEmpty) {
        final parsedRate = Formatters.parseAmount(cols[3]);
        if (parsedRate != null && parsedRate > 0) {
          customRate = parsedRate;
        }
      }

      // السبب (إن وجد)
      final reason = cols.length > 4 && cols[4].trim().isNotEmpty
          ? cols[4].trim()
          : null;

      final period = AppDateUtils.workMonthFor(date, settings.workMonthStartDay);
      final double totalValue = customRate != null
          ? customRate * hours
          : _finance.overtimeAmount(settings, hours);

      final record = TimeRecord(
        date: AppDateUtils.toStorage(date),
        type: TimeRecordType.overtime,
        startTime: startStr,
        endTime: endStr,
        totalValue: totalValue,
        customRate: customRate,
        reason: reason,
        workMonth: period.monthName,
        workYear: period.year,
      );

      final rateText = customRate != null
          ? 'سعر يدوي: ${Formatters.money(customRate)}/س'
          : 'سعر تلقائي';

      parsedRows.add(
        ParsedImportRow(
          lineNumber: lineNum,
          rawColumns: cols,
          isValid: true,
          data: record,
          extraInfo:
              '${Formatters.hours(hours)} ($startStr - $endStr) • +${Formatters.money(totalValue)} • $rateText',
        ),
      );
    }

    return ImportPreviewResult(
      categoryTitle: 'الساعات الإضافية',
      rows: parsedRows,
      hasHeader: hasHeader,
    );
  }

  static bool _isOvertimeHeader(List<String> cols) {
    if (cols.isEmpty) return false;
    final first = cols[0].toLowerCase();
    return first.contains('تاريخ') ||
        first.contains('date') ||
        first.contains('إضافي') ||
        first.contains('overtime');
  }

  // ---------------------------------------------------------------------------
  // استيراد الغياب (Absence Import)
  // ---------------------------------------------------------------------------

  ImportPreviewResult<TimeRecord> parseAbsence(
    String content,
    AppSettings settings,
  ) {
    final rawRows = splitRows(content);
    final parsedRows = <ParsedImportRow<TimeRecord>>[];
    var hasHeader = false;

    for (var i = 0; i < rawRows.length; i++) {
      final cols = rawRows[i];
      final lineNum = i + 1;

      if (i == 0 && _isAbsenceHeader(cols)) {
        hasHeader = true;
        continue;
      }

      // الأعمدة المتوقعة: [التاريخ, النوع (ساعات/أيام), البداية أو عدد الأيام, النهاية (للساعات), سعر يدوي (اختياري), السبب (اختياري)]
      if (cols.isEmpty || cols[0].trim().isEmpty) {
        parsedRows.add(
          ParsedImportRow(
            lineNumber: lineNum,
            rawColumns: cols,
            isValid: false,
            error: 'تاريخ الغياب مطلوب',
          ),
        );
        continue;
      }

      final date = parseDate(cols[0]);
      if (date == null) {
        parsedRows.add(
          ParsedImportRow(
            lineNumber: lineNum,
            rawColumns: cols,
            isValid: false,
            error: 'صيغة التاريخ غير صالحة: "${cols[0]}"',
          ),
        );
        continue;
      }

      final typeStr = cols.length > 1 ? cols[1].trim().toLowerCase() : '';
      final isDays = typeStr.contains('يوم') ||
          typeStr.contains('أيام') ||
          typeStr.contains('day');

      final period = AppDateUtils.workMonthFor(date, settings.workMonthStartDay);

      if (isDays) {
        // غياب بالأيام
        final daysCount = cols.length > 2
            ? (Formatters.parseInt(cols[2]) ?? 1)
            : 1;
        final reason = cols.length > 5 && cols[5].trim().isNotEmpty
            ? cols[5].trim()
            : (cols.length > 3 && cols[3].trim().isNotEmpty ? cols[3].trim() : null);

        final record = TimeRecord(
          date: AppDateUtils.toStorage(date),
          type: TimeRecordType.absenceDays,
          daysCount: daysCount,
          reason: reason,
          workMonth: period.monthName,
          workYear: period.year,
        );

        parsedRows.add(
          ParsedImportRow(
            lineNumber: lineNum,
            rawColumns: cols,
            isValid: true,
            data: record,
            extraInfo: 'غياب $daysCount يوم (خصم من رصيد العطلة)',
          ),
        );
      } else {
        // غياب بالساعات
        final startStr = cols.length > 2 && cols[2].trim().isNotEmpty
            ? parseTime(cols[2])
            : '09:00';
        final endStr = cols.length > 3 && cols[3].trim().isNotEmpty
            ? parseTime(cols[3])
            : '12:00';

        if (startStr == null || endStr == null) {
          parsedRows.add(
            ParsedImportRow(
              lineNumber: lineNum,
              rawColumns: cols,
              isValid: false,
              error: 'أوقات الغياب غير صحيحة (البداية: ${cols.length > 2 ? cols[2] : ""}, النهاية: ${cols.length > 3 ? cols[3] : ""})',
            ),
          );
          continue;
        }

        final hours = AppDateUtils.hoursBetween(startStr, endStr);
        if (hours <= 0) {
          parsedRows.add(
            ParsedImportRow(
              lineNumber: lineNum,
              rawColumns: cols,
              isValid: false,
              error: 'يجب أن يكون وقت النهاية ($endStr) بعد وقت البداية ($startStr)',
            ),
          );
          continue;
        }

        // سعر الخصم اليدوي
        double? customRate;
        if (cols.length > 4 && cols[4].trim().isNotEmpty) {
          final parsedRate = Formatters.parseAmount(cols[4]);
          if (parsedRate != null && parsedRate > 0) {
            customRate = parsedRate;
          }
        }

        final reason = cols.length > 5 && cols[5].trim().isNotEmpty
            ? cols[5].trim()
            : null;

        final double totalValue = customRate != null
            ? customRate * hours
            : (settings.isCommissionOnly
                ? 0.0
                : _finance.absenceHoursAmount(settings, hours));

        final record = TimeRecord(
          date: AppDateUtils.toStorage(date),
          type: TimeRecordType.absenceHours,
          startTime: startStr,
          endTime: endStr,
          totalValue: totalValue,
          customRate: customRate,
          reason: reason,
          workMonth: period.monthName,
          workYear: period.year,
        );

        final rateText = customRate != null
            ? 'خصم يدوي: ${Formatters.money(customRate)}/س'
            : (settings.isCommissionOnly ? 'بدون خصم مالي' : 'خصم تلقائي');

        parsedRows.add(
          ParsedImportRow(
            lineNumber: lineNum,
            rawColumns: cols,
            isValid: true,
            data: record,
            extraInfo:
                '${Formatters.hours(hours)} ($startStr - $endStr) • -${Formatters.money(totalValue)} • $rateText',
          ),
        );
      }
    }

    return ImportPreviewResult(
      categoryTitle: 'الغياب',
      rows: parsedRows,
      hasHeader: hasHeader,
    );
  }

  static bool _isAbsenceHeader(List<String> cols) {
    if (cols.isEmpty) return false;
    final first = cols[0].toLowerCase();
    return first.contains('تاريخ') ||
        first.contains('date') ||
        first.contains('غياب') ||
        first.contains('absence');
  }

  // ---------------------------------------------------------------------------
  // استيراد المبيعات (Sales Import)
  // ---------------------------------------------------------------------------

  Future<ImportPreviewResult<ParsedSaleItem>> parseSales(
    String content,
    AppSettings settings, {
    List<Client>? existingClients,
  }) async {
    final clients = existingClients ?? await db.getClients();
    final clientMap = {
      for (final c in clients) c.name.trim().toLowerCase(): c,
    };

    final rawRows = splitRows(content);
    final parsedRows = <ParsedImportRow<ParsedSaleItem>>[];
    var hasHeader = false;

    for (var i = 0; i < rawRows.length; i++) {
      final cols = rawRows[i];
      final lineNum = i + 1;

      if (i == 0 && _isSalesHeader(cols)) {
        hasHeader = true;
        continue;
      }

      // الأعمدة المتوقعة: [التاريخ, اسم الزبون, المساحة (م²), نسبة العمولة (اختياري), الحالة (اختياري)]
      if (cols.length < 3) {
        parsedRows.add(
          ParsedImportRow(
            lineNumber: lineNum,
            rawColumns: cols,
            isValid: false,
            error: 'الأعمدة غير مكتملة (المطلوب كحد أدنى: التاريخ، اسم الزبون، المساحة)',
          ),
        );
        continue;
      }

      final date = parseDate(cols[0]);
      if (date == null) {
        parsedRows.add(
          ParsedImportRow(
            lineNumber: lineNum,
            rawColumns: cols,
            isValid: false,
            error: 'تاريخ المبيعة غير صالح: "${cols[0]}"',
          ),
        );
        continue;
      }

      final clientName = cols[1].trim();
      if (clientName.isEmpty) {
        parsedRows.add(
          ParsedImportRow(
            lineNumber: lineNum,
            rawColumns: cols,
            isValid: false,
            error: 'اسم الزبون مطلوب',
          ),
        );
        continue;
      }

      // الأعمدة المتوقعة: [التاريخ, اسم الزبون, نوع الطلب (مطبخ/دريسنج/...), المساحة (م²), نسبة العمولة (اختياري), الحالة (اختياري)]
      // أو: [التاريخ, اسم الزبون, المساحة (م²), نسبة العمولة, ...] (افتراضي: مطبخ)
      String orderType = OrderType.kitchen;
      double? area;
      int nextIdx = 2;

      // فحص هل العمود 2 مساحة رقمية أم نوع طلب
      final asNumber = Formatters.parseAmount(cols[2]);
      if (asNumber != null) {
        area = asNumber;
        nextIdx = 3;
      } else {
        orderType = cols[2].trim().isEmpty ? OrderType.kitchen : cols[2].trim();
        if (cols.length > 3) {
          area = Formatters.parseAmount(cols[3]);
          nextIdx = 4;
        }
      }

      if (area == null || area <= 0) {
        parsedRows.add(
          ParsedImportRow(
            lineNumber: lineNum,
            rawColumns: cols,
            isValid: false,
            error: 'مساحة المطبخ/المنتج غير صحيحة أو مفقودة: "${cols.length > 2 ? cols[2] : ""}"',
          ),
        );
        continue;
      }

      // نسبة العمولة: إذا كُتبت 1.5 تصبح 0.015
      double commRate = 0.015;
      if (cols.length > nextIdx && cols[nextIdx].trim().isNotEmpty) {
        final parsedComm = Formatters.parseAmount(cols[nextIdx]);
        if (parsedComm != null && parsedComm > 0) {
          commRate = parsedComm > 1 ? parsedComm / 100.0 : parsedComm;
        }
        nextIdx++;
      }

      // الحالة
      var status = SaleStatus.pending;
      if (cols.length > nextIdx && cols[nextIdx].trim().isNotEmpty) {
        final st = cols[nextIdx].trim().toLowerCase();
        if (st.contains('مدفوع') || st.contains('paid')) {
          status = SaleStatus.paid;
        } else if (st.contains('مؤكد') || st.contains('confirmed')) {
          status = SaleStatus.confirmed;
        }
      }

      final matchedClient = clientMap[clientName.toLowerCase()];
      final isNewClient = matchedClient == null;

      final period = AppDateUtils.workMonthFor(date, settings.workMonthStartDay);
      final sale = Sale(
        date: AppDateUtils.toStorage(date),
        clientId: matchedClient?.id,
        orderType: orderType,
        area: area,
        commissionRate: commRate,
        status: status,
        workMonth: period.monthName,
        workYear: period.year,
      );

      final clientTag = isNewClient
          ? 'زبون جديد'
          : 'زبون مسجل (#${matchedClient.id})';

      parsedRows.add(
        ParsedImportRow(
          lineNumber: lineNum,
          rawColumns: cols,
          isValid: true,
          data: ParsedSaleItem(
            sale: sale,
            clientName: clientName,
            isNewClient: isNewClient,
          ),
          extraInfo:
              '[$orderType] • ${Formatters.number(area)} م² • عمولة ${(commRate * 100).toStringAsFixed(1)}% • $clientTag',
        ),
      );
    }

    return ImportPreviewResult(
      categoryTitle: 'المبيعات',
      rows: parsedRows,
      hasHeader: hasHeader,
    );
  }

  static bool _isSalesHeader(List<String> cols) {
    if (cols.isEmpty) return false;
    final first = cols[0].toLowerCase();
    final second = cols.length > 1 ? cols[1].toLowerCase() : '';
    return first.contains('تاريخ') ||
        first.contains('date') ||
        second.contains('زبون') ||
        second.contains('client');
  }

  // ---------------------------------------------------------------------------
  // تنفيذ الحفظ في قاعدة البيانات (Transaction-Safe Batch Execution)
  // ---------------------------------------------------------------------------

  /// حفظ قائمة الزبائن المستوردين داخل معاملة آمنة.
  Future<int> executeImportClients(List<Client> clients) async {
    if (clients.isEmpty) return 0;
    final database = await db.database;
    return database.transaction((txn) async {
      var count = 0;
      for (final client in clients) {
        await txn.insert('clients', client.toMap());
        count++;
      }
      return count;
    });
  }

  /// حفظ سجلات الوقت (إضافي / غياب) المستوردة داخل معاملة آمنة.
  Future<int> executeImportTimeRecords(List<TimeRecord> records) async {
    if (records.isEmpty) return 0;
    final database = await db.database;
    return database.transaction((txn) async {
      var count = 0;
      for (final record in records) {
        await txn.insert('time_records', record.toMap());
        count++;
      }
      return count;
    });
  }

  /// حفظ المبيعات المستوردة مع إنشاء بطاقات الزبائن الجدد تلقائياً.
  Future<int> executeImportSales(List<ParsedSaleItem> items) async {
    if (items.isEmpty) return 0;
    final database = await db.database;
    return database.transaction((txn) async {
      var count = 0;
      final cachedClientIds = <String, int>{};

      for (final item in items) {
        int? finalClientId = item.sale.clientId;

        if (item.isNewClient) {
          final normalized = item.clientName.trim().toLowerCase();
          if (cachedClientIds.containsKey(normalized)) {
            finalClientId = cachedClientIds[normalized];
          } else {
            final newId = await txn.insert(
              'clients',
              Client(name: item.clientName.trim()).toMap(),
            );
            cachedClientIds[normalized] = newId;
            finalClientId = newId;
          }
        }

        final saleMap = Map<String, Object?>.from(item.sale.toMap());
        saleMap['client_id'] = finalClientId;
        await txn.insert('sales', saleMap);
        count++;
      }
      return count;
    });
  }

  // ---------------------------------------------------------------------------
  // قوالب إرشادية جاهزة للمستخدم (Sample Templates)
  // ---------------------------------------------------------------------------

  static const String clientsTemplate = '''الاسم,الهاتف
سفيان بن علي,0555123456
أمين بلقاسم,0661987654
كريم مراد,0770334455''';

  static const String overtimeTemplate = '''التاريخ,البداية,النهاية,السعر اليدوي,السبب
2026-03-10,17:00,19:00,600,تسليم مطبخ عاجل
2026-03-12,17:00,20:00,,تركيب مفصلات إضافية
2026-03-15,17:30,19:30,700,تعديل مقاسات رخام''';

  static const String absenceTemplate = '''التاريخ,النوع,البداية/الأيام,النهاية,السعر اليدوي,السبب
2026-03-11,ساعات,09:00,12:00,400,موعد طبي
2026-03-14,أيام,1,,,عطلة شخصية
2026-03-18,ساعات,14:00,16:00,,ظرف عائلي''';

  static const String salesTemplate = '''التاريخ,اسم الزبون,نوع الطلب,المساحة,نسبة العمولة,الحالة
2026-03-10,فيلا الأبيار,مطبخ,14.5,1.5,مؤكد
2026-03-12,فيلا الأبيار,دريسنج,8.0,1.5,مؤكد
2026-03-16,مطبخ درارية,خزانة,15.0,2,مدفوع''';
}
