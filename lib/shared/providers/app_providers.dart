import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:money_manager/core/services/app_settings_service.dart';
import 'package:money_manager/core/services/category_seed_service.dart';
import 'package:money_manager/core/services/data_backup_service.dart';
import 'package:money_manager/core/services/excel_export_service.dart';
import 'package:money_manager/core/services/myfinance_import_service.dart';
import 'package:money_manager/core/services/notification_service.dart';
import 'package:money_manager/core/services/recurring_reminder_service.dart';
import 'package:money_manager/core/services/recurring_rule_processor.dart';
import 'package:money_manager/data/local/db/app_database.dart';
import 'package:money_manager/data/repositories/account_repository_impl.dart';
import 'package:money_manager/data/repositories/category_repository_impl.dart';
import 'package:money_manager/data/repositories/recurring_rule_repository_impl.dart';
import 'package:money_manager/data/repositories/transaction_repository_impl.dart';
import 'package:money_manager/domain/entities/account.dart' as domain;
import 'package:money_manager/domain/entities/app_settings.dart';
import 'package:money_manager/domain/entities/category.dart' as category_domain;
import 'package:money_manager/domain/entities/dashboard_summary.dart';
import 'package:money_manager/domain/entities/money_transaction.dart'
    as transaction_domain;
import 'package:money_manager/domain/entities/recurring_rule.dart'
    as recurring_domain;
import 'package:money_manager/domain/entities/recurring_rule_run.dart'
    as recurring_run_domain;
import 'package:money_manager/domain/repositories/account_repository.dart';
import 'package:money_manager/domain/repositories/category_repository.dart';
import 'package:money_manager/domain/repositories/recurring_rule_repository.dart';
import 'package:money_manager/domain/repositories/transaction_repository.dart';
import 'package:money_manager/shared/providers/app_settings_provider.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final AppDatabase database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final excelExportServiceProvider = Provider<ExcelExportService>((ref) {
  return ExcelExportService();
});

final appSettingsServiceProvider = Provider<AppSettingsService>((ref) {
  return AppSettingsService();
});

final dataBackupServiceProvider = Provider<DataBackupService>((ref) {
  final database = ref.watch(appDatabaseProvider);
  final settingsService = ref.watch(appSettingsServiceProvider);
  return DataBackupService(database, settingsService);
});

final myFinanceImportServiceProvider = Provider<MyFinanceImportService>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return MyFinanceImportService(database);
});

final categorySeedServiceProvider = Provider<CategorySeedService>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return CategorySeedService(database);
});

final appSettingsProvider =
    StateNotifierProvider<AppSettingsController, AsyncValue<AppSettings>>((
      ref,
    ) {
      final service = ref.watch(appSettingsServiceProvider);
      return AppSettingsController(service);
    });

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

final recurringReminderServiceProvider = Provider<RecurringReminderService>((
  ref,
) {
  final notificationService = ref.watch(notificationServiceProvider);
  final settingsService = ref.watch(appSettingsServiceProvider);
  final recurringRuleRepository = ref.watch(recurringRuleRepositoryProvider);

  return RecurringReminderService(
    notificationService,
    settingsService,
    recurringRuleRepository,
  );
});

final recurringRuleProcessorProvider = Provider<RecurringRuleProcessor>((ref) {
  final database = ref.watch(appDatabaseProvider);
  final transactionRepository = ref.watch(transactionRepositoryProvider);
  final notificationService = ref.watch(notificationServiceProvider);

  return RecurringRuleProcessor(
    database,
    transactionRepository,
    notificationService,
  );
});

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return AccountRepositoryImpl(database);
});

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return CategoryRepositoryImpl(database);
});

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return TransactionRepositoryImpl(database);
});

final recurringRuleRepositoryProvider = Provider<RecurringRuleRepository>((
  ref,
) {
  final database = ref.watch(appDatabaseProvider);
  return RecurringRuleRepositoryImpl(database);
});

final accountsProvider = StreamProvider<List<domain.Account>>((ref) {
  final repository = ref.watch(accountRepositoryProvider);
  return repository.watchAccounts();
});

final accountsByModeProvider =
    StreamProvider.family<List<domain.Account>, bool>((ref, archivedOnly) {
      final repository = ref.watch(accountRepositoryProvider);
      return repository.watchAccounts(archivedOnly: archivedOnly);
    });

final categoriesProvider = StreamProvider<List<category_domain.Category>>((
  ref,
) {
  final repository = ref.watch(categoryRepositoryProvider);
  return repository.watchCategories();
});

final categoriesByModeProvider =
    StreamProvider.family<List<category_domain.Category>, bool>((
      ref,
      archivedOnly,
    ) {
      final repository = ref.watch(categoryRepositoryProvider);
      return repository.watchCategories(archivedOnly: archivedOnly);
    });

final transactionsProvider =
    StreamProvider.family<List<transaction_domain.MoneyTransaction>, bool>((
      ref,
      archivedOnly,
    ) {
      final repository = ref.watch(transactionRepositoryProvider);
      return repository.watchTransactions(archivedOnly: archivedOnly);
    });

final recentTransactionsProvider =
    StreamProvider<List<transaction_domain.MoneyTransaction>>((ref) {
      final repository = ref.watch(transactionRepositoryProvider);
      return repository.watchRecentTransactions();
    });

final dashboardSummaryProvider = StreamProvider<DashboardSummary>((ref) {
  final repository = ref.watch(transactionRepositoryProvider);
  return repository.watchDashboardSummary();
});

final recurringRulesProvider =
    StreamProvider.family<List<recurring_domain.RecurringRule>, bool>((
      ref,
      archivedOnly,
    ) {
      final repository = ref.watch(recurringRuleRepositoryProvider);
      return repository.watchRecurringRules(archivedOnly: archivedOnly);
    });

final recurringSuggestionsProvider =
    StreamProvider<List<recurring_run_domain.RecurringRuleRun>>((ref) {
      final processor = ref.watch(recurringRuleProcessorProvider);
      return processor.watchPendingSuggestions();
    });
