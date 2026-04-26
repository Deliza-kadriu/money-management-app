import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:money_manager/app/router.dart';
import 'package:money_manager/app/theme/app_theme.dart';
import 'package:money_manager/shared/providers/app_providers.dart';

class MoneyManagerApp extends ConsumerStatefulWidget {
  const MoneyManagerApp({super.key});

  @override
  ConsumerState<MoneyManagerApp> createState() => _MoneyManagerAppState();
}

class _MoneyManagerAppState extends ConsumerState<MoneyManagerApp> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_initializeAppServices);
  }

  Future<void> _initializeAppServices() async {
    try {
      final notificationService = ref.read(notificationServiceProvider);
      final recurringProcessor = ref.read(recurringRuleProcessorProvider);

      await notificationService.initialize();
      await recurringProcessor.processDueRules();
    } catch (error) {
      debugPrint('App startup initialization skipped: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Money Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: appRouter,
    );
  }
}
