import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:money_manager/app/router.dart';
import 'package:money_manager/app/theme/app_theme.dart';
import 'package:money_manager/domain/entities/app_settings.dart';
import 'package:money_manager/shared/providers/app_providers.dart';

class MoneyManagerApp extends ConsumerStatefulWidget {
  const MoneyManagerApp({super.key});

  @override
  ConsumerState<MoneyManagerApp> createState() => _MoneyManagerAppState();
}

class _MoneyManagerAppState extends ConsumerState<MoneyManagerApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future<void>.microtask(_initializeAppServices);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Future<void>.microtask(_refreshRecurringServices);
    }
  }

  Future<void> _initializeAppServices() async {
    try {
      final notificationService = ref.read(notificationServiceProvider);
      final categorySeedService = ref.read(categorySeedServiceProvider);
      final AppSettings settings = await ref
          .read(appSettingsServiceProvider)
          .load();

      await categorySeedService.seedDefaultsIfEmpty();

      if (settings.notificationsEnabled) {
        await notificationService.initialize();
      }
      await _refreshRecurringServices();
    } catch (error) {
      debugPrint('App startup initialization skipped: $error');
    }
  }

  Future<void> _refreshRecurringServices() async {
    try {
      final recurringProcessor = ref.read(recurringRuleProcessorProvider);
      final recurringReminderService = ref.read(
        recurringReminderServiceProvider,
      );
      await recurringProcessor.processDueRules(notifyWhenWorkFound: false);
      await recurringReminderService.syncActiveReminders();
    } catch (error) {
      debugPrint('Recurring refresh skipped: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final appSettingsAsync = ref.watch(appSettingsProvider);
    final AppSettings settings =
        appSettingsAsync.valueOrNull ?? const AppSettings.defaults();

    return MaterialApp.router(
      title: 'Money Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themePreference.toThemeMode(),
      routerConfig: appRouter,
    );
  }
}
