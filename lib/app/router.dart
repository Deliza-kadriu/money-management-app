import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:money_manager/features/accounts/presentation/accounts_screen.dart';
import 'package:money_manager/features/categories/presentation/categories_screen.dart';
import 'package:money_manager/features/dashboard/presentation/dashboard_screen.dart';
import 'package:money_manager/features/recurring/presentation/recurring_rules_screen.dart';
import 'package:money_manager/features/reports/presentation/reports_screen.dart';
import 'package:money_manager/features/settings/presentation/settings_screen.dart';
import 'package:money_manager/features/transactions/presentation/transactions_screen.dart';
import 'package:money_manager/shared/widgets/app_shell.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/dashboard',
  routes: <RouteBase>[
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return AppShell(navigationShell: navigationShell);
      },
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/dashboard',
              pageBuilder: (context, state) =>
                  const NoTransitionPage<void>(child: DashboardScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/transactions',
              pageBuilder: (context, state) =>
                  const NoTransitionPage<void>(child: TransactionsScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/reports',
              pageBuilder: (context, state) =>
                  const NoTransitionPage<void>(child: ReportsScreen()),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/accounts',
      builder: (context, state) => const AccountsScreen(),
    ),
    GoRoute(
      path: '/categories',
      builder: (context, state) => const CategoriesScreen(),
    ),
    GoRoute(
      path: '/recurring',
      builder: (context, state) => const RecurringRulesScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
