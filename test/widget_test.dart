import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_kitchen_finance/data/app_database.dart';
import 'package:smart_kitchen_finance/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  testWidgets('App boots and shows dashboard shell', (tester) async {
    await tester.runAsync(() async {
      final db = AppDatabase.instance;
      final settings = await db.getSettings();
      await db.updateSettings(
        settings.copyWith(
          hasOnboarded: true,
          compensationMode: 'salary_bonus',
          baseSalary: 50000,
        ),
      );
      await tester.pumpWidget(const SmartKitchenApp());
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      }
    });

    expect(find.text('لوحة التحكم'), findsOneWidget);
    expect(find.text('المزيد'), findsWidgets);
    expect(find.text('الراتب الشهري'), findsOneWidget);
  });
}
