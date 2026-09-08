import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_kitchen_finance/core/date_utils.dart';
import 'package:smart_kitchen_finance/core/formatters.dart';
import 'package:smart_kitchen_finance/data/app_database.dart';
import 'package:smart_kitchen_finance/models/app_settings.dart';
import 'package:smart_kitchen_finance/models/client.dart';
import 'package:smart_kitchen_finance/models/sale.dart';
import 'package:smart_kitchen_finance/models/time_record.dart';
import 'package:smart_kitchen_finance/services/finance_service.dart';

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

  group('شهر العمل', () {
    test('5 أفريل ينتمي لشهر مارس عندما تبدأ الشهور يوم 7', () {
      final period = AppDateUtils.workMonthFor(DateTime(2026, 4, 5), 7);
      expect(period.month, 3);
      expect(period.year, 2026);
      expect(period.monthName, 'مارس');
    });

    test('يوم 7 مارس يبدأ شهر مارس', () {
      final period = AppDateUtils.workMonthFor(DateTime(2026, 3, 7), 7);
      expect(period.monthName, 'مارس');
    });

    test('6 مارس ينتمي لفيفري', () {
      final period = AppDateUtils.workMonthFor(DateTime(2026, 3, 6), 7);
      expect(period.monthName, 'فيفري');
      expect(period.year, 2026);
    });

    test('نطاق شهر مارس هو 7 مارس إلى 6 أفريل', () {
      final period = AppDateUtils.workMonthPeriod(3, 2026, 7);
      expect(AppDateUtils.toStorage(period.startDate), '2026-03-07');
      expect(AppDateUtils.toStorage(period.endDate), '2026-04-06');
    });
  });

  group('الحسابات الأساسية', () {
    const settings = AppSettings(baseSalary: 52200);

    test('سعر الساعة = الراتب ÷ 174', () {
      final finance = FinanceService(AppDatabase.instance);
      expect(finance.hourlyRate(settings), closeTo(300, 0.0001));
    });

    test('ساعة إضافية = سعر الساعة × المعامل × الساعات', () {
      final finance = FinanceService(AppDatabase.instance);
      final amount = finance.overtimeAmount(settings, 2);
      expect(amount, closeTo(900, 0.0001)); // 300 × 1.5 × 2
    });

    test('سعر الساعة الإضافية: تلقائي أو ثابت', () {
      final finance = FinanceService(AppDatabase.instance);
      expect(finance.overtimeRatePerHour(settings), closeTo(450, 0.0001));

      const custom = AppSettings(
        baseSalary: 0,
        overtimeRateMode: OvertimeRateMode.custom,
        customOvertimeRate: 750,
      );
      expect(finance.overtimeRatePerHour(custom), closeTo(750, 0.0001));
    });

    test('خصم غياب بالساعات بدون معامل', () {
      final finance = FinanceService(AppDatabase.instance);
      final amount = finance.absenceHoursAmount(settings, 3);
      expect(amount, closeTo(900, 0.0001)); // 300 × 3
    });

    test('عمولة المطبخ = المساحة × سعر المتر × النسبة', () {
      final finance = FinanceService(AppDatabase.instance);
      const settings = AppSettings(pricePerMeter: 30000);
      final sale = Sale(
        date: '2026-03-10',
        clientId: 1,
        area: 10,
        commissionRate: 0.015,
        workMonth: 'مارس',
        workYear: 2026,
      );
      expect(finance.kitchenPrice(settings, 10), 300000);
      expect(finance.commissionFor(sale, settings), closeTo(4500, 0.001));
    });
  });

  group('التجميع الشهري', () {
    test('يلخّص الراتب والخصم والإضافات والمبيعات', () async {
      final db = AppDatabase.instance;
      await db.updateSettings(
        const AppSettings(
          baseSalary: 50000,
          overtimeMultiplier: 1.5,
          pricePerMeter: 30000,
          workMonthStartDay: 7,
          annualLeaveBalance: 30,
        ),
      );
      await db.saveSalaryOverride(
        workMonth: 'مارس',
        workYear: 2026,
        actualSalary: 55000,
      );
      await db.insertTimeRecord(
        const TimeRecord(
          date: '2026-03-10',
          type: TimeRecordType.overtime,
          startTime: '18:00',
          endTime: '20:00',
          totalValue: 900,
          workMonth: 'مارس',
          workYear: 2026,
        ),
      );
      await db.insertTimeRecord(
        const TimeRecord(
          date: '2026-03-12',
          type: TimeRecordType.absenceHours,
          startTime: '09:00',
          endTime: '12:00',
          totalValue: 900,
          workMonth: 'مارس',
          workYear: 2026,
        ),
      );
      await db.insertTimeRecord(
        const TimeRecord(
          date: '2026-03-13',
          type: TimeRecordType.bonus,
          totalValue: 2000,
          workMonth: 'مارس',
          workYear: 2026,
        ),
      );
      await db.insertTimeRecord(
        const TimeRecord(
          date: '2026-03-13',
          type: TimeRecordType.absenceDays,
          daysCount: 2,
          workMonth: 'مارس',
          workYear: 2026,
        ),
      );
      final clientId = await db.insertClient(const Client(name: 'زبون 1'));
      await db.insertSale(
        Sale(
          date: '2026-03-15',
          clientId: clientId,
          area: 10,
          commissionRate: 0.015,
          isShared: true,
          workMonth: 'مارس',
          workYear: 2026,
        ),
        const [
          SaleShare(
            saleId: 0,
            personType: SaleShare.personMe,
            sharePercentage: 60,
          ),
          SaleShare(
            saleId: 0,
            personType: SaleShare.personColleague,
            colleagueId: null,
            sharePercentage: 40,
          ),
        ],
      );

      final settings = await db.getSettings();
      final finance = FinanceService(db);
      final summary = await finance.summaryFor(
        month: 3,
        year: 2026,
        startDay: settings.workMonthStartDay,
        settings: settings,
      );

      expect(summary.actualSalary, 55000);
      expect(summary.overtimeTotal, closeTo(900, 0.001));
      expect(summary.overtimeHours, closeTo(2, 0.001));
      expect(summary.bonusTotal, closeTo(2000, 0.001));
      expect(summary.absenceHoursDeduction, closeTo(900, 0.001));
      expect(summary.absenceHours, closeTo(3, 0.001));
      expect(summary.absenceDaysUsed, 2);
      // عمولة = 300000 × 0.015 = 4500، ونصيب المستخدم 60% = 2700
      expect(summary.salesRewards, closeTo(2700, 0.001));
      expect(summary.salesArea, closeTo(10, 0.001));
      // صافي الراتب = راتب − غياب + إضافي (بدون البونص)
      expect(summary.netDue, closeTo(55000 - 900 + 900, 0.001));
      // الإجمالي العام = الصافي + البونص (العمولات منفصلة تماماً)
      expect(summary.grandTotal, closeTo(summary.netDue + 2000, 0.001));

      final remaining = await finance.remainingLeave(settings);
      expect(remaining, 28);
    });

    test('وضع "عمولة فقط": لا راتب ولا خصم غياب، والعمولات منفصلة', () async {
      final db = AppDatabase.instance;
      await db.updateSettings(
        const AppSettings(
          baseSalary: 0,
          pricePerMeter: 30000,
          workMonthStartDay: 7,
          annualLeaveBalance: 30,
          compensationMode: CompensationMode.commissionOnly,
        ),
      );
      await db.insertTimeRecord(
        const TimeRecord(
          date: '2026-03-10',
          type: TimeRecordType.overtime,
          startTime: '18:00',
          endTime: '20:00',
          totalValue: 1500,
          customRate: 750,
          workMonth: 'مارس',
          workYear: 2026,
        ),
      );
      await db.insertTimeRecord(
        const TimeRecord(
          date: '2026-03-12',
          type: TimeRecordType.absenceHours,
          startTime: '09:00',
          endTime: '12:00',
          totalValue: 900,
          workMonth: 'مارس',
          workYear: 2026,
        ),
      );
      final clientId = await db.insertClient(const Client(name: 'زبون 2'));
      await db.insertSale(
        Sale(
          date: '2026-03-15',
          clientId: clientId,
          area: 10,
          commissionRate: 0.015,
          workMonth: 'مارس',
          workYear: 2026,
        ),
        const [
          SaleShare(
            saleId: 0,
            personType: SaleShare.personMe,
            sharePercentage: 100,
          ),
        ],
      );

      final settings = await db.getSettings();
      final finance = FinanceService(db);
      final summary = await finance.summaryFor(
        month: 3,
        year: 2026,
        startDay: settings.workMonthStartDay,
        settings: settings,
      );

      expect(summary.isCommissionOnly, isTrue);
      expect(summary.actualSalary, 0);
      // الغياب مسجّل لكنه لا يُخصم
      expect(summary.absenceHoursTotal, closeTo(900, 0.001));
      expect(summary.absenceHoursDeduction, 0);
      expect(summary.overtimeTotal, closeTo(1500, 0.001));
      // صافي الراتب = إضافي فقط
      expect(summary.netDue, closeTo(1500, 0.001));
      // العمولات منفصلة تماماً (لا تدخل في الإجمالي العام)
      expect(summary.salesRewards, closeTo(4500, 0.001));
      // الإجمالي العام = الصافي + البونص (بلا عمولات)
      expect(summary.grandTotal, closeTo(1500, 0.001));
    });

    test('رصيد العطلة السنوية يُحسب لسنة العمل المعينة دون تراكم السنوات السابقة', () async {
      final db = AppDatabase.instance;
      const settings = AppSettings(annualLeaveBalance: 30);
      await db.updateSettings(settings);

      // غياب 5 أيام في سنة 2025
      await db.insertTimeRecord(
        const TimeRecord(
          date: '2025-08-10',
          type: TimeRecordType.absenceDays,
          daysCount: 5,
          workMonth: 'أوت',
          workYear: 2025,
        ),
      );

      // غياب 3 أيام في سنة 2026
      await db.insertTimeRecord(
        const TimeRecord(
          date: '2026-03-10',
          type: TimeRecordType.absenceDays,
          daysCount: 3,
          workMonth: 'مارس',
          workYear: 2026,
        ),
      );

      final finance = FinanceService(db);
      // رصيد 2026 يجب أن يخصم فقط 3 أيام (المتبقي 27)
      expect(await finance.remainingLeave(settings, workYear: 2026), 27);
      // رصيد 2025 يجب أن يخصم فقط 5 أيام (المتبقي 25)
      expect(await finance.remainingLeave(settings, workYear: 2025), 25);
    });

    test('حذف تعديل الراتب الفعلي واستعادة الأساسي', () async {
      final db = AppDatabase.instance;
      await db.saveSalaryOverride(
        workMonth: 'مارس',
        workYear: 2026,
        actualSalary: 70000,
      );
      expect((await db.getSalaryOverride('مارس', 2026))?.actualSalary, 70000);

      await db.deleteSalaryOverride('مارس', 2026);
      expect(await db.getSalaryOverride('مارس', 2026), isNull);
    });

    test('تسعير يدوي للساعات الإضافية ولساعات الغياب', () async {
      final db = AppDatabase.instance;
      const settings = AppSettings(baseSalary: 52200, workMonthStartDay: 1);
      await db.updateSettings(settings);

      // ساعات إضافية بسعر يدوي 600 دج/ساعة تبدأ 17:00 إلى 19:00 (2 ساعات = 1200 دج)
      await db.insertTimeRecord(
        const TimeRecord(
          date: '2026-03-10',
          type: TimeRecordType.overtime,
          startTime: '17:00',
          endTime: '19:00',
          customRate: 600,
          totalValue: 1200,
          workMonth: 'مارس',
          workYear: 2026,
        ),
      );

      // غياب بالساعات بسعر يدوي مخصص 400 دج/ساعة (3 ساعات = 1200 دج)
      await db.insertTimeRecord(
        const TimeRecord(
          date: '2026-03-11',
          type: TimeRecordType.absenceHours,
          startTime: '09:00',
          endTime: '12:00',
          customRate: 400,
          totalValue: 1200,
          workMonth: 'مارس',
          workYear: 2026,
        ),
      );

      final finance = FinanceService(db);
      final summary = await finance.summaryFor(
        month: 3,
        year: 2026,
        startDay: 1,
        settings: settings,
      );

      expect(summary.overtimeHours, 2.0);
      expect(summary.overtimeTotal, 1200.0);
      expect(summary.absenceHours, 3.0);
      expect(summary.absenceHoursDeduction, 1200.0);
      // صافي الراتب: 52200 - 1200 + 1200 = 52200
      expect(summary.netDue, 52200.0);
    });
  });

  group('معالجة وتنسيق الأرقام', () {
    test('تحويل الأرقام بالفاصلة الفرنسية والعربية', () {
      expect(Formatters.parseAmount('12,5'), 12.5);
      expect(Formatters.parseAmount('1.5'), 1.5);
      expect(Formatters.parseAmount('١٢٫٥'), 12.5);
      expect(Formatters.parseAmount('٥٠٠٠٠'), 50000);
      expect(Formatters.parseAmount('50,000 دج'), 50000);
      expect(Formatters.parseAmount('1,250,000'), 1250000);
      expect(Formatters.parseAmount('1.250,50'), 1250.5);
      expect(Formatters.parseAmount('  12,75  '), 12.75);
      expect(Formatters.parseAmount(''), isNull);
    });
  });
}

