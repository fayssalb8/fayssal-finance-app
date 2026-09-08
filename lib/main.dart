import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme.dart';
import 'data/app_database.dart';
import 'services/notification_service.dart';
import 'ui/onboarding/onboarding_screen.dart';
import 'ui/shell/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await NotificationService.instance.init();
    await NotificationService.instance.scheduleDailyReminder();
  } catch (_) {
    // فشل إعداد التذكيرات لا يمنع تشغيل التطبيق.
  }
  runApp(const SmartKitchenApp());
}

class SmartKitchenApp extends StatefulWidget {
  const SmartKitchenApp({super.key});

  @override
  State<SmartKitchenApp> createState() => _SmartKitchenAppState();
}

class _SmartKitchenAppState extends State<SmartKitchenApp> {
  late final Future<bool> _onboarded;

  @override
  void initState() {
    super.initState();
    _onboarded = _loadOnboarded();
  }

  Future<bool> _loadOnboarded() async {
    final db = AppDatabase.instance;
    try {
      final settings = await db.getSettings();
      return settings.hasOnboarded;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Kitchen Finance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: FutureBuilder<bool>(
        future: _onboarded,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.data == true) return const MainShell();
          return const OnboardingScreen();
        },
      ),
    );
  }
}
