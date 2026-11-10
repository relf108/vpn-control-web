import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_control_web/gateway_status.dart';

const verified = '''IPv4 policy: protected unless listed below. Untunnelled IPv6 stays blocked.
No active bypasses.
Home VPN peers (public keys and allowed addresses):
test-public-key 10.77.0.2/32
Mullvad peer and endpoint:
test-public-key 192.0.2.10:51820
Gateway observed public IPv4: 198.51.100.10; Mullvad verified: True.
Check public IP from each selected client separately; the observation above is for the gateway only.''';

Widget preview(String status) => MaterialApp(
  theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
  home: Scaffold(
    body: SingleChildScrollView(
      child: GatewayStatus(
        status: status,
        updatedAt: DateTime(2026, 11, 10, 12, 34, 56),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows explicit gateway observations and timestamp', (
    tester,
  ) async {
    await tester.pumpWidget(preview(verified));
    expect(find.text('198.51.100.10'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Snapshot 12:34:56'), findsOneWidget);
    expect(
      find.textContaining('Check exit IP and DNS from each client'),
      findsOneWidget,
    );
  });

  testWidgets('failed verification is never displayed as verified', (
    tester,
  ) async {
    await tester.pumpWidget(
      preview(verified.replaceFirst('verified: True', 'verified: False')),
    );
    expect(find.text('Not verified'), findsOneWidget);
    expect(find.text('Verified'), findsNothing);
  });

  testWidgets('missing or unrecognized observations stay unknown', (
    tester,
  ) async {
    await tester.pumpWidget(preview('Controller observation unavailable.'));
    expect(find.text('Not observed'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('Not reported'), findsOneWidget);
    expect(find.text('Verified'), findsNothing);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('counts bypass entries rather than claiming a device count', (
    tester,
  ) async {
    await tester.pumpWidget(
      preview('''  192.168.0.0/24: bypass for at most 900s
  10.77.0.0/24: bypass for at most 900s
  127.0.0.1: bypass for at most 900s'''),
    );
    expect(find.text('3'), findsOneWidget);
    expect(
      find.text('Active kernel entries, not device count'),
      findsOneWidget,
    );
  });

  testWidgets('preview data remains clearly simulated', (tester) async {
    await tester.pumpWidget(
      preview(
        '''LOCAL DEMO — simulated state; no real network changes.
  all: ≤900s remaining
Gateway public IPv4: 203.0.113.10 (documentation address, not your real IP).''',
      ),
    );
    expect(find.text('203.0.113.10'), findsOneWidget);
    expect(find.text('Demo data'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.textContaining('LOCAL PREVIEW'), findsOneWidget);
    expect(find.text('Verified'), findsNothing);
  });

  testWidgets('full diagnostics stay selectable behind the expander', (
    tester,
  ) async {
    await tester.pumpWidget(preview(verified));
    await tester.ensureVisible(find.text('Gateway diagnostics'));
    await tester.tap(find.text('Gateway diagnostics'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == verified,
      ),
      findsOneWidget,
    );
  });

  testWidgets('summary and diagnostics fit a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(preview(verified));
    await tester.ensureVisible(find.text('Gateway diagnostics'));
    await tester.tap(find.text('Gateway diagnostics'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
