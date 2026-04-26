import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:money_manager/app/app.dart';

void main() {
  testWidgets('renders dashboard shell', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MoneyManagerApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Money Manager'), findsOneWidget);
    expect(find.text('Recent transactions'), findsOneWidget);
  });
}
