import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// تذكير يومي الساعة 18:00 كل الأيام ما عدا الجمعة،
/// لتسجيل الساعات الإضافية أو الغياب.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelId = 'daily_reminder';
  static const _channelName = 'تذكير يومي';
  static const _channelDescription = 'تذكير لتسجيل الساعات الإضافية أو الغياب';

  static const _reminderHour = 18;
  static const _reminderMinute = 0;

  Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // يبقى على المنطقة الافتراضية إن تعذّر تحديدها.
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings: settings);
    _initialized = true;

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
  }

  /// يلغي القديم ويُجدول تذكيراً يومياً الساعة 18:00 لكل أيام الأسبوع
  /// ما عدا الجمعة (الخميس الجمعة = يوم عطلة في هذا النشاط التجاري).
  Future<void> scheduleDailyReminder() async {
    await _plugin.cancelAll();

    final now = tz.TZDateTime.now(tz.local);
    for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++) {
      if (weekday == DateTime.friday) continue;
      final scheduledTime = _nextOccurrence(now, weekday);
      await _plugin.zonedSchedule(
        id: weekday,
        title: 'تذكير يومي',
        body: 'سجّل ساعاتك الإضافية أو غيابك ليوم اليوم',
        scheduledDate: scheduledTime,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  tz.TZDateTime _nextOccurrence(tz.TZDateTime now, int weekday) {
    var candidate = tz.TZDateTime(
      now.location,
      now.year,
      now.month,
      now.day,
      _reminderHour,
      _reminderMinute,
    );
    while (candidate.weekday != weekday || !candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }
}
