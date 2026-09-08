import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_kitchen_finance/data/app_database.dart';
import 'package:smart_kitchen_finance/models/app_settings.dart';
import 'package:smart_kitchen_finance/models/client.dart';
import 'package:smart_kitchen_finance/models/sale.dart';
import 'package:smart_kitchen_finance/models/time_record.dart';
import 'package:smart_kitchen_finance/services/import_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    final dir = await getDatabasesPath();
    final file = File('$dir/smart_kitchen_finance.db');
    if (file.existsSync()) file.deleteSync();
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  group('ImportService - أدوات التحليل الأساسية', () {
    test('التعرف على الفواصل المختلفة (فاصلة، فاصلة منقوطة، Tab)', () {
      const csv = 'محمد,0555123456';
      final csvRows = ImportService.splitRows(csv);
      expect(csvRows.first, ['محمد', '0555123456']);

      const semi = 'سفيان;0661223344';
      final semiRows = ImportService.splitRows(semi);
      expect(semiRows.first, ['سفيان', '0661223344']);

      const tab = 'أمين\t0770998877';
      final tabRows = ImportService.splitRows(tab);
      expect(tabRows.first, ['أمين', '0770998877']);
    });

    test('تحليل صيغ التواريخ المختلفة', () {
      final d1 = ImportService.parseDate('2026-03-10');
      expect(d1, DateTime(2026, 3, 10));

      final d2 = ImportService.parseDate('10/03/2026');
      expect(d2, DateTime(2026, 3, 10));

      final d3 = ImportService.parseDate('15-04-2026');
      expect(d3, DateTime(2026, 4, 15));
    });

    test('تحليل صيغ الوقت', () {
      expect(ImportService.parseTime('17:00'), '17:00');
      expect(ImportService.parseTime('17h30'), '17:30');
      expect(ImportService.parseTime('9:15'), '09:15');
      expect(ImportService.parseTime('17'), '17:00');
    });
  });

  group('ImportService - استيراد الزبائن', () {
    test('استيراد قائمة زبائن وتخطي السجلات المكررة', () async {
      final db = AppDatabase.instance;
      await db.insertClient(const Client(name: 'الزبون القديم', phone: '0555000000'));

      final service = ImportService(db);
      const content = '''الاسم,الهاتف
كريم مراد,0555112233
الزبون القديم,0555000000
فايصل بلعيد,0661445566''';

      final preview = await service.parseClients(content);
      expect(preview.hasHeader, isTrue);
      expect(preview.totalCount, 3);
      expect(preview.validCount, 2);
      expect(preview.errorCount, 1); // مكرر

      final imported = await service.executeImportClients(preview.validData);
      expect(imported, 2);

      final allClients = await db.getClients();
      expect(allClients.length, 3);
    });
  });

  group('ImportService - استيراد الساعات الإضافية', () {
    test('استيراد ساعات إضافية مع التسعير اليدوي والتلقائي والوقت الافتراضي', () async {
      final db = AppDatabase.instance;
      const settings = AppSettings(baseSalary: 52200, workMonthStartDay: 1);
      await db.updateSettings(settings);

      final service = ImportService(db);
      const content = '''التاريخ,البداية,النهاية,السعر اليدوي,السبب
2026-03-10,17:00,19:00,600,تسليم مطبخ
2026-03-12,,,,تركيب مفصلات
2026-03-15,19:00,17:00,,خطأ في التوقيت''';

      final preview = service.parseOvertime(content, settings);
      expect(preview.hasHeader, isTrue);
      expect(preview.totalCount, 3);
      expect(preview.validCount, 2);
      expect(preview.errorCount, 1); // وقت النهاية قبل البداية

      final row1 = preview.rows[0].data!;
      expect(row1.startTime, '17:00');
      expect(row1.endTime, '19:00');
      expect(row1.customRate, 600.0);
      expect(row1.totalValue, 1200.0);

      // السطر الثاني استخدم الأوقات الافتراضية 17:00 إلى 19:00 والتسعير التلقائي (450 دج/س)
      final row2 = preview.rows[1].data!;
      expect(row2.startTime, '17:00');
      expect(row2.endTime, '19:00');
      expect(row2.customRate, isNull);
      expect(row2.totalValue, 900.0); // 2 ساعات × 450 دج

      final imported = await service.executeImportTimeRecords(preview.validData);
      expect(imported, 2);

      final records = await db.getTimeRecords(workMonth: 'مارس', workYear: 2026);
      expect(records.length, 2);
    });
  });

  group('ImportService - استيراد الغياب', () {
    test('استيراد غياب بالساعات وغياب بالأيام', () async {
      final db = AppDatabase.instance;
      const settings = AppSettings(baseSalary: 52200, workMonthStartDay: 1);
      await db.updateSettings(settings);

      final service = ImportService(db);
      const content = '''التاريخ,النوع,البداية/الأيام,النهاية,السعر اليدوي,السبب
2026-03-11,ساعات,09:00,12:00,400,موعد طبي
2026-03-14,أيام,2,,,عطلة شخصية''';

      final preview = service.parseAbsence(content, settings);
      expect(preview.validCount, 2);

      final hRecord = preview.rows[0].data!;
      expect(hRecord.type, TimeRecordType.absenceHours);
      expect(hRecord.customRate, 400.0);
      expect(hRecord.totalValue, 1200.0);

      final dRecord = preview.rows[1].data!;
      expect(dRecord.type, TimeRecordType.absenceDays);
      expect(dRecord.daysCount, 2);

      final imported = await service.executeImportTimeRecords(preview.validData);
      expect(imported, 2);
    });
  });

  group('ImportService - استيراد المبيعات', () {
    test('استيراد مبيعات مع إنشاء زبائن جدد تلقائياً وربط الزبائن الحاليين', () async {
      final db = AppDatabase.instance;
      const settings = AppSettings(workMonthStartDay: 1);
      await db.updateSettings(settings);

      // زبون موجود مسبقاً
      await db.insertClient(const Client(name: 'زبون قديم'));

      final service = ImportService(db);
      const content = '''التاريخ,اسم الزبون,المساحة,نسبة العمولة,الحالة
2026-03-10,زبون قديم,10.0,1.5,مؤكد
2026-03-15,زبون جديد عاجل,15.5,2,مدفوع''';

      final preview = await service.parseSales(content, settings);
      expect(preview.validCount, 2);
      expect(preview.rows[0].data!.isNewClient, isFalse);
      expect(preview.rows[1].data!.isNewClient, isTrue);

      final imported = await service.executeImportSales(preview.validData);
      expect(imported, 2);

      final clients = await db.getClients();
      expect(clients.any((c) => c.name == 'زبون جديد عاجل'), isTrue);

      final sales = await db.getSales(workMonth: 'مارس', workYear: 2026);
      expect(sales.length, 2);
      expect(sales[0].area, 10.0);
      expect(sales[0].commissionRate, 0.015);
      expect(sales[1].area, 15.5);
      expect(sales[1].commissionRate, 0.02);
      expect(sales[1].status, SaleStatus.paid);
    });

    test('نفس الزبون يشتري مطبخ ثم دريسنج بأمتار مختلفة', () async {
      final db = AppDatabase.instance;
      const settings = AppSettings(workMonthStartDay: 1);
      await db.updateSettings(settings);

      final service = ImportService(db);
      // فيلا الأبيار اشترت مطبخ (14.5 م²) ثم دريسنج (8.0 م²)
      const content = '''التاريخ,اسم الزبون,نوع الطلب,المساحة,نسبة العمولة,الحالة
2026-03-10,فيلا الأبيار,مطبخ,14.5,1.5,مؤكد
2026-03-12,فيلا الأبيار,دريسنج,8.0,1.5,مؤكد''';

      final preview = await service.parseSales(content, settings);
      expect(preview.validCount, 2);

      final row1 = preview.rows[0].data!;
      expect(row1.clientName, 'فيلا الأبيار');
      expect(row1.sale.orderType, 'مطبخ');
      expect(row1.sale.area, 14.5);

      final row2 = preview.rows[1].data!;
      expect(row2.clientName, 'فيلا الأبيار');
      expect(row2.sale.orderType, 'دريسنج');
      expect(row2.sale.area, 8.0);

      final count = await service.executeImportSales(preview.validData);
      expect(count, 2);

      // يجب أن يتم إنشاء زبون واحد فقط "فيلا الأبيار"
      final clients = await db.getClients();
      final villaClients = clients.where((c) => c.name == 'فيلا الأبيار').toList();
      expect(villaClients.length, 1);

      // ومبيعتان مرتبطتان بنفس الزبون مع نوع الطلب والأمتار المختلفة
      final sales = await db.getSales(workMonth: 'مارس', workYear: 2026);
      expect(sales.length, 2);
      expect(sales[0].clientId, villaClients.first.id);
      expect(sales[1].clientId, villaClients.first.id);
      expect(sales.any((s) => s.orderType == 'مطبخ' && s.area == 14.5), isTrue);
      expect(sales.any((s) => s.orderType == 'دريسنج' && s.area == 8.0), isTrue);
    });
  });
}
