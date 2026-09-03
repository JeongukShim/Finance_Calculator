// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fixed_cost_household_book/main.dart';

void main() {
  testWidgets('Payday onboarding renders', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const FixedCostApp());
    await tester.pumpAndSettle();

    expect(find.text('월급날 설정'), findsOneWidget);
    expect(find.text('저장하고 시작'), findsOneWidget);
  });
}
