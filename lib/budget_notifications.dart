import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

class BudgetNotifications {
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    timezone_data.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );
    await _plugin.initialize(settings);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> updateThresholdAlert({required bool exceededThreshold}) async {
    await _plugin.cancel(80);
    if (!exceededThreshold) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'budget_alerts',
        'Alertas de presupuesto',
        channelDescription: 'Avisos cuando el gasto se acerca al presupuesto.',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.zonedSchedule(
      80,
      'Presupuesto semanal',
      'Has superado el 80% de tu presupuesto semanal.',
      timezone.TZDateTime.now(timezone.local).add(const Duration(seconds: 5)),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
