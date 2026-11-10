import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/link.dart';
import 'package:vpn_control_web/vpn_access.dart';

final current = DateTime.utc(2026, 11, 10);
const account = {
  'state': 'available',
  'expiry': '2027-01-24T00:00:00Z',
  'checkedAt': '2026-11-10T00:00:00Z',
  'stale': false,
};

Widget preview(Map<String, dynamic>? data, {VoidCallback? onOpen}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: VpnAccessNotice(account: data, now: current, onOpen: onOpen),
          ),
        ),
      ),
    );

void main() {
  test('remaining time uses calendar years/months/days in that order', () {
    expect(
      remainingAccess(current, DateTime.utc(2027, 1, 24)),
      '0y / 2m / 14d remaining',
    );
    expect(
      remainingAccess(current, DateTime.utc(2028, 2, 1)),
      '1y / 2m / 22d remaining',
    );
    expect(
      remainingAccess(DateTime.utc(2026, 1, 31), DateTime.utc(2026, 2, 28)),
      '0y / 1m / 0d remaining',
    );
    expect(
      remainingAccess(DateTime.utc(2026, 1, 31), DateTime.utc(2026, 3, 31)),
      '0y / 2m / 0d remaining',
    );
    expect(
      remainingAccess(DateTime.utc(2024, 2, 29), DateTime.utc(2025, 2, 28)),
      '1y / 0m / 0d remaining',
    );
    expect(
      remainingAccess(DateTime.utc(2026, 12, 31), DateTime.utc(2027, 1, 1)),
      '0y / 0m / 1d remaining',
    );
    expect(
      remainingAccess(
        DateTime.parse('2026-11-10T02:00:00+02:00'),
        DateTime.utc(2027, 1, 24),
      ),
      '0y / 2m / 14d remaining',
    );
    expect(
      remainingAccess(current, current.add(const Duration(hours: 1))),
      '0y / 0m / 0d remaining',
    );
    expect(remainingAccess(current, current), 'Expired');
    expect(
      remainingAccess(current, current.subtract(const Duration(days: 1))),
      'Expired',
    );
  });

  testWidgets(
    'shows renewal and y/m/d rather than a guessed monthly duration',
    (tester) async {
      await tester.pumpWidget(preview(account));
      expect(find.text('VPN access'), findsOneWidget);
      expect(find.text('0y / 2m / 14d remaining'), findsOneWidget);
      expect(find.text('Renew by 24 Jan 2027.'), findsOneWidget);
    },
  );

  testWidgets(
    'link goes to the fixed Mullvad account page without credentials',
    (tester) async {
      await tester.pumpWidget(preview(account));
      final link = tester.widget<Link>(find.byType(Link));
      expect(link.uri, Uri.parse('https://mullvad.net/en/account/login'));
      expect(link.target, LinkTarget.blank);
      expect(link.uri!.query, isEmpty);
      expect(link.uri!.userInfo, isEmpty);
    },
  );

  testWidgets('whole info notice is clickable', (tester) async {
    var clicks = 0;
    await tester.pumpWidget(preview(account, onOpen: () => clicks++));
    await tester.tap(find.text('0y / 2m / 14d remaining'));
    expect(clicks, 1);
  });

  testWidgets('expired and unknown values never show remaining access', (
    tester,
  ) async {
    await tester.pumpWidget(
      preview({...account, 'expiry': '2026-11-09T00:00:00Z'}),
    );
    expect(find.text('Expired'), findsOneWidget);
    await tester.pumpWidget(preview({'state': 'unavailable'}));
    expect(find.text('Renewal date unavailable'), findsOneWidget);
    expect(find.textContaining('remaining'), findsNothing);
    await tester.pumpWidget(preview({'state': 'notConfigured'}));
    expect(find.text('Check renewal on Mullvad'), findsOneWidget);
    expect(find.text('Manage on Mullvad'), findsOneWidget);
  });

  testWidgets('stale values and preview values are clearly labelled', (
    tester,
  ) async {
    await tester.pumpWidget(preview({...account, 'stale': true, 'demo': true}));
    expect(
      find.text('Cached estimate; latest expiry check failed.'),
      findsOneWidget,
    );
    expect(find.text('Simulated expiry for this preview.'), findsOneWidget);
  });

  testWidgets('notice fits narrow phones', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(preview(account));
    expect(tester.takeException(), isNull);
  });
}
