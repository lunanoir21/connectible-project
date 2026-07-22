import 'package:connectible_mobile/src/screens/pair_landing_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_scaffold.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'renders the headline, CTA, and how-it-works steps', (tester) async {
    await tester.pumpWidget(wrapScreen(const PairLandingScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Connect your desktop'), findsOneWidget);
    expect(find.text('Pair Desktop'), findsOneWidget);
    // Eyebrow uppercases its text (see widgets/ui.dart).
    expect(find.text('HOW IT WORKS'), findsOneWidget);
    expect(find.text('Open Connectible on your computer'), findsOneWidget);
    expect(find.text('Scan the code'), findsOneWidget);
    expect(find.text("You're connected"), findsOneWidget);
  });

  testWidgets('tapping "Pair Desktop" navigates to the scan screen',
      (tester) async {
    await tester.pumpWidget(wrapScreen(const PairLandingScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pair Desktop'));
    await tester.pumpAndSettle();

    // pair_scan_screen.dart's own AppBar title -- proof the push actually
    // landed on the scanner, not just that some route changed.
    expect(find.text('Scan to pair'), findsOneWidget);
    // The landing screen's CTA is gone now that it's off the top of the
    // navigation stack.
    expect(find.text('Pair Desktop'), findsNothing);
  });
}
