import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_kitchen_finance/data/app_database.dart';
import 'package:smart_kitchen_finance/models/app_settings.dart';
import 'package:smart_kitchen_finance/models/client.dart';
import 'package:smart_kitchen_finance/models/sale.dart';
import 'package:smart_kitchen_finance/models/time_record.dart';
import 'package:smart_kitchen_finance/services/finance_service.dart';
import 'package:smart_kitchen_finance/services/report_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('توليد تقرير PDF ببيانات حقيقية', () async {
    final db = AppDatabase.instance;
    await db.updateSettings(
      const AppSettings(
        baseSalary: 52200,
        overtimeMultiplier: 1.5,
        pricePerMeter: 30000,
        workMonthStartDay: 7,
        annualLeaveBalance: 30,
      ),
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
        date: '2026-03-11',
        type: TimeRecordType.absenceHours,
        startTime: '09:00',
        endTime: '11:00',
        totalValue: 600,
        workMonth: 'مارس',
        workYear: 2026,
      ),
    );
    await db.insertTimeRecord(
      const TimeRecord(
        date: '2026-03-12',
        type: TimeRecordType.bonus,
        totalValue: 2000,
        reason: 'مكافأة',
        workMonth: 'مارس',
        workYear: 2026,
      ),
    );
    final clientId = await db.insertClient(const Client(name: 'حمو'));
    final saleId = await db.insertSale(
      Sale(
        date: '2026-03-15',
        clientId: clientId,
        area: 12,
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
          sharePercentage: 40,
        ),
      ],
    );
    expect(saleId, greaterThan(0));

    final service = ReportPdfService(
      AppDatabase.instance,
      FinanceService(AppDatabase.instance),
    );
    final incomeBytes = await service.generateIncomeReport(
      from: DateTime(2026, 3, 7),
      to: DateTime(2026, 4, 6),
    );
    final commissionBytes = await service.generateCommissionReport(
      from: DateTime(2026, 3, 7),
      to: DateTime(2026, 4, 6),
    );

    expect(incomeBytes.isNotEmpty, isTrue);
    expect(commissionBytes.isNotEmpty, isTrue);
    expect(String.fromCharCodes(incomeBytes.take(5)), '%PDF-');
    expect(String.fromCharCodes(commissionBytes.take(5)), '%PDF-');
    // التقريران منفصلان.
    expect(incomeBytes, isNot(equals(commissionBytes)));
  });

  test('الإجمالي العام في التقرير = صافي الراتب + البونص فقط', () async {
    const settings = AppSettings(
      baseSalary: 50000,
      overtimeMultiplier: 1.5,
      pricePerMeter: 30000,
      workMonthStartDay: 7,
      annualLeaveBalance: 30,
    );
    final data = IncomeReportData(
      settings: settings,
      periodTitle: 'من 7 مارس إلى 6 أفريل',
      actualSalary: 50000,
      overtimeRecords: const [],
      absenceHoursRecords: const [],
      absenceDaysRecords: const [],
      bonusRecords: const [
        TimeRecord(
          date: '2026-03-12',
          type: TimeRecordType.bonus,
          totalValue: 2000,
          workMonth: 'مارس',
          workYear: 2026,
        ),
      ],
      monthlyBreakdown: const [],
    );
    final commission = CommissionReportData(
      settings: settings,
      periodTitle: 'من 7 مارس إلى 6 أفريل',
      sales: const [
        SaleWithCommission(
          sale: Sale(
            date: '2026-03-15',
            clientId: 1,
            area: 10,
            commissionRate: 0.015,
            workMonth: 'مارس',
            workYear: 2026,
          ),
          userCommission: 4500,
          shares: [],
        ),
      ],
    );

    // صافي = 50000 − 0 + 0 = 50000؛ العمولات 4500 منفصلة تماما.
    expect(data.netDue, closeTo(50000, 0.001));
    expect(data.grandTotal, closeTo(50000 + 2000, 0.001));
    // العمولات في تقريرها الخاص ولا تدخل في الإجمالي العام.
    expect(commission.totalCommission, closeTo(4500, 0.001));
    expect(data.grandTotal, isNot(closeTo(50000 + 2000 + 4500, 0.001)));
  });

  test('تقارير الغياب والساعات الإضافية تُجمَّع في تقرير المستحقات', () async {
    const settings = AppSettings(
      baseSalary: 52200,
      overtimeMultiplier: 1.5,
      pricePerMeter: 30000,
      workMonthStartDay: 7,
      annualLeaveBalance: 30,
    );
    final data = IncomeReportData(
      settings: settings,
      periodTitle: 'شهر مارس',
      actualSalary: 52200,
      overtimeRecords: const [
        TimeRecord(
          date: '2026-03-10',
          type: TimeRecordType.overtime,
          startTime: '18:00',
          endTime: '20:00',
          totalValue: 900,
          workMonth: 'مارس',
          workYear: 2026,
        ),
      ],
      absenceHoursRecords: const [
        TimeRecord(
          date: '2026-03-11',
          type: TimeRecordType.absenceHours,
          startTime: '09:00',
          endTime: '11:00',
          totalValue: 600,
          workMonth: 'مارس',
          workYear: 2026,
        ),
      ],
      absenceDaysRecords: const [
        TimeRecord(
          date: '2026-03-13',
          type: TimeRecordType.absenceDays,
          daysCount: 2,
          workMonth: 'مارس',
          workYear: 2026,
        ),
      ],
      bonusRecords: const [],
      monthlyBreakdown: const [],
    );

    expect(data.overtimeTotal, closeTo(900, 0.001));
    expect(data.overtimeHoursTotal, closeTo(2, 0.001));
    expect(data.absenceHoursTotal, closeTo(600, 0.001));
    expect(data.absenceHoursCount, closeTo(2, 0.001));
    expect(data.absenceDaysCount, 2);
    expect(data.absenceHoursDeduction, closeTo(600, 0.001));
    // صافي = 52200 − 600 + 900 = 52500
    expect(data.netDue, closeTo(52500, 0.001));
    expect(data.grandTotal, closeTo(52500, 0.001));
  });

  test('توليد تقرير PDF يغطي عدة أشهر مع سجلات متعددة وتقسيم صفحات ناجح', () async {
    final db = AppDatabase.instance;
    await db.updateSettings(
      const AppSettings(
        baseSalary: 60000,
        overtimeMultiplier: 1.5,
        pricePerMeter: 30000,
        workMonthStartDay: 7,
        annualLeaveBalance: 30,
      ),
    );

    // إضافة عدة سجلات لتوليد صفحات متعددة والتأكد من عدم حدوث تجاوز الارتفاع
    for (var i = 1; i <= 25; i++) {
      await db.insertTimeRecord(
        TimeRecord(
          date: '2026-03-${i.toString().padLeft(2, '0')}',
          type: TimeRecordType.overtime,
          startTime: '18:00',
          endTime: '20:00',
          totalValue: 900,
          workMonth: 'مارس',
          workYear: 2026,
        ),
      );
    }

    final service = ReportPdfService(
      AppDatabase.instance,
      FinanceService(AppDatabase.instance),
    );

    // تقرير لشهرين: من 7 مارس إلى 6 ماي
    final multiMonthBytes = await service.generateIncomeReport(
      from: DateTime(2026, 3, 7),
      to: DateTime(2026, 5, 6),
    );

    expect(multiMonthBytes.isNotEmpty, isTrue);
    expect(String.fromCharCodes(multiMonthBytes.take(5)), '%PDF-');
  });
}

