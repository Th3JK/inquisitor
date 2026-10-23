import 'package:flutter_test/flutter_test.dart';
import 'package:inquisitor_example/main.dart';

void main() {
  testWidgets('demo starts on the staggered rollout scenario', (tester) async {
    await tester.pumpWidget(const InquisitorDemoApp());
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // iOS is on 2.4.0 while the demo app runs 2.3.0, so the update prompt is up.
    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Staggered rollout'), findsOneWidget);
  });
}
