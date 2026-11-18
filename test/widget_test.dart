import 'package:flutter_test/flutter_test.dart';
import 'package:soulsync/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('SoulSync basic widget smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: SoulSyncApp(),
      ),
    );

    // Pump through the splash screen 2-second navigation timer and animations
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Verify that the app transitions and renders without crashing
    expect(find.byType(SoulSyncApp), findsOneWidget);
  });
}
