import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_control_web/relay_map.dart';

const melbourne = GeoPoint(-37.815018, 144.946014);
const london = GeoPoint(51.514125, -0.093689);
const atlas = RelayAtlas(
  locations: {'au-mel': melbourne, 'gb-lon': london},
  land: [
    [GeoPoint(-10, 110), GeoPoint(-40, 110), GeoPoint(-40, 155)],
  ],
);
const relays = [
  {'id': 'configured', 'label': 'Configured default'},
  {'id': 'au-mel', 'label': 'Australia / Melbourne (au-mel-wg-401)'},
  {'id': 'gb-lon', 'label': 'UK / London (gb-lon-wg-001)'},
];

Widget preview({
  String selected = 'configured',
  ValueChanged<String>? onSelected,
  List<Map<String, dynamic>> choices = relays,
  Future<RelayAtlas>? data,
}) => MaterialApp(
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: RelayMap(
        relays: choices,
        selected: selected,
        onSelected: onSelected,
        atlas: data ?? Future.value(atlas),
      ),
    ),
  ),
);

class _PathCanvas implements Canvas {
  final paths = <Path>[];

  @override
  void drawPath(Path path, Paint paint) => paths.add(Path.from(path));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test(
    'geographic projection places known cities in the correct hemisphere',
    () {
      const size = Size(720, 290);
      expect(const GeoPoint(85, -180).project(size), Offset.zero);
      expect(const GeoPoint(-60, 180).project(size), const Offset(720, 290));
      expect(melbourne.project(size).dx, greaterThan(size.width / 2));
      expect(melbourne.project(size).dy, greaterThan(london.project(size).dy));
    },
  );

  testWidgets('bundled atlas includes reviewed cities and real coastlines', (
    tester,
  ) async {
    final data = (await tester.runAsync(RelayAtlas.load))!;
    expect(data.locations.length, 91);
    expect(data.locations['au-mel']!.latitude, closeTo(-37.815018, 0.000001));
    expect(data.locations['configured'], isNull);
    expect(data.land.length, greaterThan(100));
    expect(data.landPolygons!.length, 127);
    expect(
      data.landPolygons!.where((polygon) => polygon.length > 1),
      isNotEmpty,
    );
  });

  testWidgets('land polygons paint independently and preserve interior holes', (
    tester,
  ) async {
    const outer = [
      GeoPoint(60, -120),
      GeoPoint(0, -120),
      GeoPoint(0, -60),
      GeoPoint(60, -60),
    ];
    const hole = [
      GeoPoint(40, -100),
      GeoPoint(20, -100),
      GeoPoint(20, -80),
      GeoPoint(40, -80),
    ];
    const island = [GeoPoint(-10, 110), GeoPoint(-40, 110), GeoPoint(-40, 155)];
    const shapes = RelayAtlas(
      locations: {},
      land: [outer, hole, island],
      landPolygons: [
        [outer, hole],
        [island],
      ],
    );
    await tester.pumpWidget(preview(data: Future.value(shapes)));
    await tester.pumpAndSettle();
    final finder = find.descendant(
      of: find.byKey(const ValueKey('relay-map-surface')),
      matching: find.byType(CustomPaint),
    );
    final painter = tester.widget<CustomPaint>(finder).painter!;
    final size = tester.getSize(finder);
    final canvas = _PathCanvas();
    painter.paint(canvas, size);
    expect(canvas.paths.length, 4); // Separate fill/stroke for each polygon.
    expect(
      canvas.paths.first.contains(const GeoPoint(50, -110).project(size)),
      isTrue,
    );
    expect(
      canvas.paths.first.contains(const GeoPoint(30, -90).project(size)),
      isFalse,
    );
    expect(
      canvas.paths[2].contains(const GeoPoint(-30, 130).project(size)),
      isTrue,
    );
  });

  testWidgets('map dot chooses an allowed destination without connecting', (
    tester,
  ) async {
    final selections = <String>[];
    await tester.pumpWidget(preview(onSelected: selections.add));
    await tester.pumpAndSettle();
    final surface = tester.getRect(
      find.byKey(const ValueKey('relay-map-surface')),
    );
    await tester.tapAt(surface.topLeft + melbourne.project(surface.size));
    await tester.pumpAndSettle();
    expect(selections, ['au-mel']);
    expect(
      find.text(
        'City locations only—not live tunnel status. Map selection does not connect.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Configured default has no map pin. Choose a city to explore.'),
      findsOneWidget,
    );
    await tester.pumpWidget(
      preview(selected: 'au-mel', onSelected: selections.add),
    );
    await tester.pumpAndSettle();
    expect(find.text('Australia / Melbourne'), findsOneWidget);
    expect(selections.length, 1);
  });

  testWidgets(
    'disabled map cannot select and unknown coordinates are not guessed',
    (tester) async {
      await tester.pumpWidget(
        preview(
          choices: [
            ...relays,
            {'id': 'custom', 'label': 'Private custom relay'},
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 cities'), findsOneWidget);
      expect(find.textContaining('1 additional relay(s)'), findsOneWidget);
      final surface = tester.getRect(
        find.byKey(const ValueKey('relay-map-surface')),
      );
      await tester.tapAt(surface.topLeft + melbourne.project(surface.size));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Configured default has no map pin. Choose a city to explore.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile layout supports zoom and reset without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(preview(onSelected: (_) {}));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      greaterThan(1),
    );
    await tester.tap(find.byTooltip('Reset map'));
    await tester.pumpAndSettle();
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('map failure leaves an explicit dropdown fallback', (
    tester,
  ) async {
    final loading = Completer<RelayAtlas>();
    await tester.pumpWidget(preview(data: loading.future));
    loading.completeError(StateError('Missing asset'));
    await tester.pumpAndSettle();
    expect(
      find.text('Map unavailable. You can still choose a relay below.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'coastlines stay visible across desktop resizes and pixel ratios',
    (tester) async {
      final data = (await tester.runAsync(RelayAtlas.load))!;
      final capture = GlobalKey();
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const samples = [
        GeoPoint(-25, 134), // Inland Australia.
        GeoPoint(10, 20), // Inland Africa.
        GeoPoint(40, -100), // North America.
        GeoPoint(50, 100), // Inland Asia.
      ];
      for (final ratio in [1.0, 1.25, 2.0]) {
        tester.view.devicePixelRatio = ratio;
        for (final viewport in [
          const Size(1920, 1080),
          const Size(960, 1080),
          const Size(1440, 900),
          const Size(800, 900),
          const Size(1920, 1080),
        ]) {
          tester.view.physicalSize = viewport * ratio;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1080),
                        child: RepaintBoundary(
                          key: capture,
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: RelayMap(
                              relays: relays,
                              selected: 'configured',
                              onSelected: (_) {},
                              atlas: Future.value(data),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final origin = boundary.localToGlobal(Offset.zero);
          final surface = tester.getRect(
            find.byKey(const ValueKey('relay-map-surface')),
          );
          final pixels = (await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: ratio);
            try {
              return (
                width: image.width,
                bytes: (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!,
              );
            } finally {
              image.dispose();
            }
          }))!;
          for (final sample in samples) {
            final point =
                surface.topLeft - origin + sample.project(surface.size);
            final offset =
                ((point.dy * ratio).floor() * pixels.width +
                    (point.dx * ratio).floor()) *
                4;
            expect(
              [
                pixels.bytes.getUint8(offset),
                pixels.bytes.getUint8(offset + 1),
                pixels.bytes.getUint8(offset + 2),
                pixels.bytes.getUint8(offset + 3),
              ],
              [0x27, 0x43, 0x4b, 0xff],
              reason:
                  'Land must render at $viewport, DPR $ratio, '
                  '${sample.latitude}/${sample.longitude}.',
            );
          }
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}
