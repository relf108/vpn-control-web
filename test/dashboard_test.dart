import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vpn_control_web/api.dart';
import 'package:vpn_control_web/main.dart';

void main() {
  testWidgets('phone layout signs in and confirms a selected bypass', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final actions = <Map<String, dynamic>>[];
    final api = VpnApi(
      client: MockClient((request) async {
        final path = request.url.path.split('/').last;
        if (path == 'session') {
          return http.Response('{"message":"Sign in required."}', 401);
        }
        final data = switch (path) {
          'login' => {'ok': true, 'csrfToken': 'synthetic-csrf'},
          'devices' => {
            'devices': [
              {
                'address': '192.168.0.50',
                'title': 'Living room TV',
                'bypassSeconds': 0,
              },
            ],
          },
          'relays' => {
            'relays': [
              {'id': 'configured', 'label': 'Configured default'},
            ],
          },
          _ => {'ok': true, 'message': 'No active bypasses.'},
        };
        if (path == 'bypass') actions.add(jsonDecode(request.body));
        return http.Response(jsonEncode(data), 200);
      }),
    );
    await tester.pumpWidget(MaterialApp(home: Dashboard(api: api)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'operator');
    await tester.enterText(find.byType(TextField).last, 'synthetic-password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Home VPN'), findsOneWidget);
    expect(find.text('Living room TV'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Bypass selected'));
    await tester.tap(find.text('Bypass selected'));
    await tester.pumpAndSettle();
    expect(find.text('Use your home ISP?'), findsOneWidget);
    expect(actions, isEmpty);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(actions, [
      {
        'targets': ['192.168.0.50'],
        'minutes': 15,
      },
    ]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
