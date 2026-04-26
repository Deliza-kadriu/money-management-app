# Money Manager MVP Plan and Technical Specification

## 1. Product Goal

Build a private, local-first personal money management mobile app with Flutter for Android and iOS.

The app should let a single user manage:

- Multiple accounts
- Income, expenses, and transfers
- Parent and child categories
- Recurring payments
- Reports and filters
- Excel export
- Local notifications

The MVP should feel simple and modern, but the codebase should be structured so cloud sync, login, and multi-currency can be added later without a rewrite.

## 2. MVP Feature Modules

### Core MVP modules

1. Dashboard
- Total balance
- This month income
- This month expenses
- Recent transactions
- Quick actions

2. Accounts
- Create, edit, archive, restore accounts
- View account balances and account details
- Support account types

3. Transactions
- Create income
- Create expense
- Create transfer between accounts
- Edit, delete, restore transactions
- Attach up to 4 local receipt images
- Search and filter transactions

4. Categories
- Create, edit, archive categories
- Parent and child categories only for MVP
- Type-aware categories for income and expense

5. Recurring Payments
- Create recurring rules
- Generate or suggest transactions from rules
- Track next due date
- Trigger local reminders

6. Reports
- Monthly summary
- Custom date range report
- All-time totals
- Income vs expense
- Spending by category
- Account balance overview

7. Export
- Export filtered transactions or reports to Excel

8. Settings
- Base currency
- Notification preferences
- Export preferences
- Backup placeholder settings for future

## 3. Practical Flutter Architecture

Use **feature-first clean-ish architecture**, not heavy enterprise clean architecture.

This is the most beginner-friendly scalable setup:

- `presentation`: screens, widgets, controllers/providers
- `domain`: entities, enums, repository contracts, use cases
- `data`: database tables, models, repositories, mappers, local services
- `core`: shared helpers, theme, routing, constants, result/error wrappers

### Why this structure works well

Coming from Laravel, think of it like this:

- Flutter `screen/widget` = Blade/Vue page + UI layer
- `provider/notifier` = controller + view model
- `repository` = service/repository layer
- `database service/DAO` = Eloquent/data access layer
- `domain entity` = business object

### Recommended rule

Keep business logic **out of widgets**.

Widgets should mostly:

- Render UI
- Read provider state
- Trigger actions like save, update, delete, filter

Providers/notifiers should:

- Load data
- Validate UI actions
- Call repositories/use cases
- Expose loading/error/success state

Repositories should:

- Hide the database implementation
- Make future sync migration easier

## 4. State Management Recommendation

Use **Riverpod**.

### Why Riverpod

- Easier to scale than `setState`
- Cleaner dependency injection
- Great for async state
- Testable
- Widely used in modern Flutter apps
- Works well with feature modules

### Suggested pattern

- `AsyncNotifier` or `Notifier` for screen/business state
- `Provider` for repositories/services
- Separate lightweight form state when needed

Avoid starting with BLoC unless you already prefer it. Riverpod is easier for a solo builder with limited Flutter experience.

## 5. Recommended Packages

### Core

- `flutter_riverpod`: state management
- `go_router`: routing/navigation
- `freezed`: immutable models and unions
- `json_serializable`: JSON/model serialization if needed later
- `intl`: date and currency formatting
- `uuid`: local IDs

### Database

- `drift`: local SQL database
- `sqlite3_flutter_libs`: SQLite native libs
- `path_provider`: database file path
- `path`: safe path building

### Forms and UI

- `flutter_form_builder` or plain `Form` widgets
- `form_builder_validators` if using form builder
- `flex_color_scheme` or manual Material 3 theme setup
- `fl_chart`: charts for reports

### Images and files

- `image_picker`: attach receipt images
- `file_picker`: choose export destination if needed
- `share_plus`: share exported Excel files
- `permission_handler`: only if a package/workflow requires explicit permissions

### Notifications

- `flutter_local_notifications`: recurring reminders and due alerts
- `timezone`: schedule notifications correctly

### Export

- `excel`: generate `.xlsx` files

### Optional helpful packages

- `collection`
- `equatable` if you skip `freezed`
- `device_info_plus`
- `package_info_plus`

## 6. Local Database Choice and Why

Use **Drift + SQLite**.

### Why not Hive/SharedPreferences

- You have relational data: accounts, transactions, categories, recurring rules
- You need filters, joins, reporting, and soft deletes
- SQLite is much better for query-heavy finance features

### Why Drift

- Type-safe query layer
- Great Flutter support
- Easier migrations than raw SQL only
- Strong fit for reports and filtering
- Lets you keep SQL power without managing everything manually

### Future-proofing for sync

Design each table with:

- `id` as UUID string
- timestamps
- `deleted_at`
- optional `sync_status` and `remote_id` later

That lets you add login/cloud sync later with less schema pain.

## 7. Data Model and Database Schema

Use soft deletes for core business tables.

### `accounts`

Fields:

- `id` TEXT PRIMARY KEY
- `name` TEXT NOT NULL
- `type` TEXT NOT NULL
- `opening_balance` REAL NOT NULL DEFAULT 0
- `current_balance` REAL NOT NULL DEFAULT 0
- `currency_code` TEXT NOT NULL
- `color_hex` TEXT NULL
- `icon_key` TEXT NULL
- `is_active` INTEGER NOT NULL DEFAULT 1
- `created_at` TEXT NOT NULL
- `updated_at` TEXT NOT NULL
- `deleted_at` TEXT NULL

Notes:

- `current_balance` can be stored for fast dashboard reads
- also recalculate periodically or on transaction updates for safety

### `categories`

Fields:

- `id` TEXT PRIMARY KEY
- `name` TEXT NOT NULL
- `parent_id` TEXT NULL
- `type` TEXT NOT NULL
- `icon_key` TEXT NULL
- `color_hex` TEXT NULL
- `sort_order` INTEGER NOT NULL DEFAULT 0
- `is_active` INTEGER NOT NULL DEFAULT 1
- `created_at` TEXT NOT NULL
- `updated_at` TEXT NOT NULL
- `deleted_at` TEXT NULL

Constraints:

- `parent_id` references `categories.id`
- MVP validation: only one nesting level in UI/business rules

### `transactions`

Fields:

- `id` TEXT PRIMARY KEY
- `type` TEXT NOT NULL
- `account_id` TEXT NOT NULL
- `destination_account_id` TEXT NULL
- `amount` REAL NOT NULL
- `transaction_date` TEXT NOT NULL
- `category_id` TEXT NULL
- `child_category_id` TEXT NULL
- `note` TEXT NULL
- `recurring_rule_id` TEXT NULL
- `created_at` TEXT NOT NULL
- `updated_at` TEXT NOT NULL
- `deleted_at` TEXT NULL

Rules:

- expense/income uses `account_id`
- transfer uses both `account_id` and `destination_account_id`
- transfer should not require a category for MVP
- `amount` should always be positive
- meaning comes from `type`

### `transaction_attachments`

Fields:

- `id` TEXT PRIMARY KEY
- `transaction_id` TEXT NOT NULL
- `file_path` TEXT NOT NULL
- `sort_order` INTEGER NOT NULL DEFAULT 0
- `created_at` TEXT NOT NULL

Rules:

- max 4 attachments enforced at app layer

### `recurring_rules`

Fields:

- `id` TEXT PRIMARY KEY
- `title` TEXT NOT NULL
- `type` TEXT NOT NULL
- `frequency` TEXT NOT NULL
- `interval_count` INTEGER NOT NULL DEFAULT 1
- `account_id` TEXT NOT NULL
- `destination_account_id` TEXT NULL
- `category_id` TEXT NULL
- `child_category_id` TEXT NULL
- `amount` REAL NOT NULL
- `note` TEXT NULL
- `start_date` TEXT NOT NULL
- `end_date` TEXT NULL
- `next_due_date` TEXT NOT NULL
- `reminder_days_before` INTEGER NOT NULL DEFAULT 0
- `auto_create` INTEGER NOT NULL DEFAULT 0
- `is_active` INTEGER NOT NULL DEFAULT 1
- `last_generated_at` TEXT NULL
- `created_at` TEXT NOT NULL
- `updated_at` TEXT NOT NULL
- `deleted_at` TEXT NULL

### `recurring_rule_runs`

Fields:

- `id` TEXT PRIMARY KEY
- `recurring_rule_id` TEXT NOT NULL
- `scheduled_for` TEXT NOT NULL
- `transaction_id` TEXT NULL
- `status` TEXT NOT NULL
- `created_at` TEXT NOT NULL

Purpose:

- Prevent duplicate generation
- Track whether due item was generated, skipped, or completed

### `app_settings`

Fields:

- `id` INTEGER PRIMARY KEY CHECK (`id` = 1)
- `base_currency_code` TEXT NOT NULL
- `notifications_enabled` INTEGER NOT NULL DEFAULT 1
- `default_reminder_days_before` INTEGER NOT NULL DEFAULT 0
- `created_at` TEXT NOT NULL
- `updated_at` TEXT NOT NULL

## 8. Domain Enums

- `AccountType`: cash, bankAccount, creditCard, savings, other
- `TransactionType`: expense, income, transfer
- `CategoryType`: expense, income, both
- `RecurringFrequency`: daily, weekly, monthly, yearly
- `RecurringRunStatus`: pending, generated, completed, skipped

## 9. Balance Logic

Use this rule everywhere:

- Income increases account balance
- Expense decreases account balance
- Transfer decreases source account and increases destination account

### Recommended implementation

When a transaction is created, updated, restored, or soft deleted:

1. reverse previous balance impact if editing/deleting
2. apply new balance impact
3. wrap in one database transaction

This is critical to avoid incorrect balances.

## 10. Main Screens / Pages

### 1. Onboarding / Empty State

- Welcome screen
- Explain local private storage
- Set base currency
- Create first account

### 2. Dashboard

- Total balance card
- Income/expense summary for current month
- Account balance chips/cards
- Recent transactions list
- Quick actions:
  - Add expense
  - Add income
  - Add transfer
  - Add account

### 3. Accounts List

- All active accounts
- Current balance by account
- Filter active/archived
- Floating action button to add account

### 4. Account Form

- Name
- Type
- Opening balance
- Currency
- Color
- Icon
- Active toggle

### 5. Account Detail

- Account info
- Current balance
- Transaction list for that account
- Edit/archive actions

### 6. Transactions List

- Search bar
- Filter chips
- Date range selector
- List grouped by date
- Empty state when no transactions match

### 7. Transaction Form

- Type selector
- Source account
- Destination account if transfer
- Amount
- Date
- Category
- Child category
- Note
- Attach receipts
- Optional recurring reference display

### 8. Categories List

- Parent categories grouped by type
- Expand child categories
- Add/edit/archive

### 9. Category Form

- Name
- Parent category optional
- Type
- Icon
- Color
- Sort order
- Active toggle

### 10. Recurring Rules List

- Upcoming due items
- Active/inactive tabs
- Next due date
- Frequency label

### 11. Recurring Rule Form

- Title
- Type
- Frequency
- Start date
- End date
- Amount
- Account
- Category
- Reminder days before
- Auto-create toggle

### 12. Reports

- Period selector
- Totals summary cards
- Category pie/bar chart
- Income vs expense chart
- Account balance overview
- Export button

### 13. Settings

- Base currency
- Notifications toggle
- Reminder defaults
- Export options
- Future backup/sync placeholders

## 11. User Flows

### First-time setup

1. Open app
2. Choose base currency
3. Create first account
4. Land on dashboard

### Add expense

1. Tap add expense
2. Select account
3. Enter amount/date/category
4. Optional note and attachments
5. Save
6. Balance updates and dashboard refreshes

### Add income

1. Tap add income
2. Choose account
3. Enter amount/date/category
4. Save
5. Balance updates

### Transfer between accounts

1. Tap add transfer
2. Select source and destination account
3. Enter amount/date/note
4. Save
5. Source decreases and destination increases in one atomic action

### Create recurring rent rule

1. Open recurring section
2. Create monthly expense rule
3. Set due date and reminder
4. App schedules local notification
5. On due date, app suggests or auto-creates transaction

### Export report

1. Open reports or transactions
2. Apply filters
3. Tap export
4. Generate Excel
5. Save/share file

## 12. Search and Filtering Design

The transaction list and export flow should share the same filter object.

### `TransactionFilter`

Fields:

- `dateFrom`
- `dateTo`
- `accountIds`
- `categoryIds`
- `childCategoryIds`
- `minAmount`
- `maxAmount`
- `transactionTypes`
- `searchQuery`
- `includeArchived`

Why:

- One filter model keeps UI, reports, and export consistent
- Much easier to test

## 13. Folder Structure

```text
lib/
  main.dart
  app/
    app.dart
    router.dart
    theme/
      app_theme.dart
      app_colors.dart
  core/
    constants/
    utils/
    errors/
    extensions/
    services/
      notification_service.dart
      excel_export_service.dart
      image_storage_service.dart
  data/
    local/
      db/
        app_database.dart
        tables/
          accounts_table.dart
          categories_table.dart
          transactions_table.dart
          transaction_attachments_table.dart
          recurring_rules_table.dart
          recurring_rule_runs_table.dart
          app_settings_table.dart
        daos/
          accounts_dao.dart
          categories_dao.dart
          transactions_dao.dart
          recurring_rules_dao.dart
          reports_dao.dart
    models/
      account_model.dart
      category_model.dart
      transaction_model.dart
      recurring_rule_model.dart
    repositories/
      account_repository_impl.dart
      category_repository_impl.dart
      transaction_repository_impl.dart
      recurring_repository_impl.dart
      report_repository_impl.dart
  domain/
    entities/
      account.dart
      category.dart
      money_transaction.dart
      recurring_rule.dart
      report_summary.dart
    enums/
      account_type.dart
      transaction_type.dart
      category_type.dart
      recurring_frequency.dart
    repositories/
      account_repository.dart
      category_repository.dart
      transaction_repository.dart
      recurring_repository.dart
      report_repository.dart
    usecases/
      create_transaction.dart
      update_transaction.dart
      delete_transaction.dart
      create_account.dart
      generate_due_recurring_transactions.dart
  features/
    dashboard/
      presentation/
    accounts/
      presentation/
      providers/
    transactions/
      presentation/
      providers/
    categories/
      presentation/
      providers/
    recurring/
      presentation/
      providers/
    reports/
      presentation/
      providers/
    settings/
      presentation/
      providers/
  shared/
    widgets/
    providers/
```

## 14. Routing Recommendation

Use `go_router`.

Suggested route groups:

- `/`
- `/dashboard`
- `/accounts`
- `/accounts/new`
- `/accounts/:id`
- `/accounts/:id/edit`
- `/transactions`
- `/transactions/new`
- `/transactions/:id/edit`
- `/categories`
- `/categories/new`
- `/recurring`
- `/recurring/new`
- `/reports`
- `/settings`

## 15. Excel Export Approach

Use the `excel` package to generate `.xlsx`.

### Export options for MVP

1. Export filtered transaction list
2. Export report summary

### Transaction export columns

- Date
- Type
- Account
- Destination account
- Parent category
- Child category
- Amount
- Note
- Recurring rule
- Created at

### Export workflow

1. User applies filters
2. Fetch matching rows from local DB
3. Map rows to worksheet data
4. Generate workbook
5. Save to app documents/download location
6. Share with `share_plus`

### Important design choice

The exporter should accept the same filter object used by the transaction list and reports. That keeps data consistent.

## 16. Local Notification Approach

Use `flutter_local_notifications` with `timezone`.

### MVP behavior

- Schedule reminder for recurring rules
- Optional reminder before due date
- Show notification title/body
- Tapping notification opens recurring detail or transaction form

### Notification examples

- "Rent due tomorrow"
- "Spotify subscription due today"
- "Salary expected today"

### Important note

On iOS, notification permissions and scheduling behavior need extra care. Build the notification service early so platform differences are handled once.

## 17. Suggested MVP Behavior for Recurring Payments

Use **suggest + optional auto-create**.

### MVP-safe version

- By default, recurring rules create a due reminder
- User confirms transaction generation
- Optional `auto_create` can be enabled later in MVP or post-MVP

Why:

- Safer than silent automatic finance entries
- Easier to debug
- Better for a first release

## 18. Reports for MVP

### Must-have reports

1. Monthly overview
- income total
- expense total
- net total

2. Custom period summary
- date range totals
- filtered by account/category/type

3. All-time totals

4. Category spending chart

5. Account balance overview

### Report query strategy

Build report queries straight from SQLite/Drift rather than loading every transaction into memory.

This will stay faster and cleaner as data grows.

## 19. Example UI Layout Descriptions

### Dashboard

Top area:

- Large balance card with total net balance
- Small segmented cards for month income and month expense

Middle:

- Horizontal list of account cards with color/icon accents

Bottom:

- Recent transactions list
- Floating add button with 3 quick options: expense, income, transfer

### Transaction form

- Top segmented selector: Expense / Income / Transfer
- Amount input as the primary focus
- Account and category selectors in card-style pickers
- Date and note below
- Receipts section with image thumbnails
- Sticky save button at bottom

### Reports screen

- Sticky date filter bar
- Summary cards
- Chart area
- Category breakdown list
- Export button at top right

### Accounts screen

- Clean list or card grid
- Each card shows icon, account name, type, current balance
- Archived accounts hidden behind a filter

## 20. Important Edge Cases

1. Editing a transaction must reverse the previous balance impact before applying the new one.
2. Deleting a transfer must revert both source and destination balances.
3. Prevent transfer to the same account.
4. Prevent using archived accounts in new transactions unless editing historical data.
5. If a category is archived, historical transactions should still display its name.
6. If a parent category changes, child category relations must remain valid.
7. Prevent child category selection when parent category does not match.
8. Recurring rule generation must not create duplicates for the same due date.
9. Transfers should not appear as both income and expense in summary reports unless intentionally modeled that way.
10. Opening balance should not be double-counted together with imported initial transactions.
11. Attachment paths can break if files are moved or permissions change.
12. Timezone/date boundaries can affect daily/monthly reports.
13. Soft-deleted items must be excluded from normal queries but remain available for restore/history.
14. Account deletion should be blocked or handled carefully if transactions exist. For MVP, prefer archive instead of hard delete.
15. Amount should be stored as a decimal-safe strategy. If using SQLite `REAL` for MVP, document rounding rules. Long term, integer minor units is safer.

## 21. Recommendation on Amount Storage

For a quick MVP, `REAL` is acceptable.

For a more robust finance app, prefer:

- `amount_minor` INTEGER
- Example: 12.34 USD becomes 1234

### Practical recommendation

If you want the cleanest long-term base, start with integer minor units now.

That means:

- no floating point surprises
- easier reporting accuracy
- better multi-currency future support

## 22. Beginner-Friendly Implementation Strategy

Since you have backend experience but limited Flutter experience, build it in layers:

### Step 1

Set up:

- app theme
- routing
- database
- Riverpod
- reusable UI shell

### Step 2

Build accounts first.

Why:

- simple CRUD
- teaches forms, list screens, detail screens, local DB flow
- becomes the foundation for transactions

### Step 3

Build categories.

Why:

- also simple CRUD
- needed before transaction UX feels complete

### Step 4

Build transaction engine and balance logic.

This is the most important business layer.

### Step 5

Add dashboard and reports.

### Step 6

Add recurring rules and notifications.

### Step 7

Add Excel export and polish.

## 23. MVP Development Phases

### Phase 1: Project foundation

- Create Flutter app
- Add Riverpod, go_router, Drift, theme
- Create base folder structure
- Set up database and migrations
- Add seed/default data support

### Phase 2: Accounts

- Accounts schema
- Account CRUD UI
- Archive/restore
- Dashboard account summary card

### Phase 3: Categories

- Category schema
- Parent/child category CRUD
- Type-aware categories
- Archive/restore

### Phase 4: Transactions

- Expense/income/transfer flows
- Attachment support
- Search/filter
- Atomic balance updates
- Soft delete and restore

### Phase 5: Dashboard and reports

- Dashboard summaries
- Monthly/custom/all-time reports
- Charts
- Filter integration

### Phase 6: Recurring and notifications

- Recurring rules CRUD
- Due transaction suggestions
- Notification scheduling
- Duplicate protection

### Phase 7: Export and QA

- Excel export
- Sharing flow
- Edge-case testing
- Performance review
- UX polish

## 24. Testing Strategy

### Unit tests

- Balance calculation
- Transfer logic
- Recurring next due date calculation
- Report aggregation
- Filter object behavior

### Widget tests

- Transaction form validation
- Account creation flow
- Category picker logic

### Integration tests

- Create account -> add expense -> dashboard updates
- Create transfer -> both balances update
- Generate recurring -> suggested transaction appears

## 25. Future Enhancements After MVP

1. Cloud sync and user login
2. Real backup/restore
3. Multi-currency support with exchange rates
4. Budgeting by category
5. Financial goals / savings goals
6. Transaction templates
7. Receipt OCR
8. Recurring auto-post with approval workflows
9. Import from CSV/Excel/bank statements
10. Deeper nested categories
11. Home screen widgets
12. PIN/biometric lock
13. Dark mode and theme personalization
14. Advanced analytics and trends
15. Debt/loan tracking
16. Shared household accounts

## 26. Clean MVP Scope Recommendation

To keep the MVP realistic, prioritize:

- Local-only
- Single currency
- Manual transaction entry
- Parent/child categories only
- Reports with essential charts
- Recurring reminders with suggestion flow
- Excel export for filtered data

Do not expand MVP yet with:

- login
- cloud sync
- OCR
- bank integrations
- budgeting
- advanced forecasting

## 27. Final Technical Recommendation

### Best stack for this app

- Flutter
- Riverpod
- Drift + SQLite
- go_router
- flutter_local_notifications
- fl_chart
- excel

### Best architecture for you

Use a **feature-first structure with repository + provider layers**.

This gives you:

- beginner-friendly development
- clear business logic boundaries
- testability
- future sync readiness

## 27A. Docker Recommendation

Use Docker as a **development environment helper**, not as the full mobile runtime strategy.

### Best use of Docker for this app

- standardize Flutter SDK setup
- run `flutter pub get`
- run static analysis and tests
- run code generation
- support future CI pipelines

### Important limitations

- iOS builds still require Xcode on a Mac host
- iOS simulator does not run meaningfully inside Docker
- Android emulator is usually best on the host machine
- release signing should stay outside the container

### Practical recommendation

Use a hybrid workflow:

- Docker for CLI consistency
- host machine for simulators, emulators, and release builds

This gives you Laravel-like environment consistency without fighting native mobile tooling.

## 28. Suggested First Build Order

1. Project setup and app shell
2. Accounts CRUD
3. Categories CRUD
4. Transactions CRUD with balance engine
5. Dashboard
6. Reports
7. Recurring rules
8. Notifications
9. Excel export
10. Polish and testing

## 29. If You Want the Best MVP Shape

If I were building this as a first solid Flutter finance MVP, I would choose:

- Material 3
- Riverpod
- Drift
- UUID primary keys
- soft deletes
- integer minor units for money
- feature-first folder structure
- recurring suggestion flow instead of forced auto-create

That combination keeps the app private, clean, maintainable, and ready for future sync.
