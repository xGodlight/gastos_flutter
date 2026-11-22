// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'budget_notifications.dart';
import 'cloud_service.dart';
import 'expense_repository.dart';
import 'secure_codec.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await FirebaseConfig.initialize();
    await initializeDateFormatting('es_MX');
    final codec = SecureCodec(const FlutterSecureStorage());
    await codec.initialize();
    final repository = ExpenseRepository(codec);
    await repository.initialize();
    final notifications = BudgetNotifications();
    await notifications.initialize();
    runApp(ExpenseApp(
      repository: repository,
      cloud: CloudService(const FlutterSecureStorage()),
      notifications: notifications,
    ));
  } catch (error) {
    runApp(StartupFailureApp(error: error));
  }
}

class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({required this.error, super.key});

  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('No se pudo iniciar la aplicación.\n$error'),
            ),
          ),
        ),
      );
}
