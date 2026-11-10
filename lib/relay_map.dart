import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// A public city position, never a user's location or a live tunnel observation.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;

  Offset project(Size size) => Offset(
    (longitude + 180) / 360 * size.width,
    (85 - latitude) / 145 * size.height,
  );
}

class RelayAtlas {
  const RelayAtlas({
    required this.locations,
    required this.land,
    this.landPolygons,
  });
  final Map<String, GeoPoint> locations;
  final List<List<GeoPoint>> land;
  // Keep exterior rings and their holes together, but separate distinct islands.
  final List<List<List<GeoPoint>>>? landPolygons;

  static Future<RelayAtlas> load() async {
    final assets = await Future.wait([
      rootBundle.loadString('assets/map/relay_locations.json'),
      rootBundle.loadString('assets/map/world_land.geojson'),
    ]);
    final positions =
        jsonDecode(assets[0])['locations'] as Map<String, dynamic>;
    final features = jsonDecode(assets[1])['features'] as List;
    final locations = <String, GeoPoint>{};
    for (final entry in positions.entries) {
      final values = (entry.value as List).cast<num>();
      final lat = values[0].toDouble();
      final lon = values[1].toDouble();
      if (lat.isFinite && lon.isFinite && lat.abs() <= 90 && lon.abs() <= 180) {
        locations[entry.key] = GeoPoint(lat, lon);
      }
    }
    final land = <List<GeoPoint>>[];
    final landPolygons = <List<List<GeoPoint>>>[];
    for (final feature in features) {
      final geometry = feature['geometry'];
      final coordinates = geometry['coordinates'] as List;
      final polygons = geometry['type'] == 'MultiPolygon'
          ? coordinates
          : [coordinates];
      for (final polygon in polygons) {
        final rings = <List<GeoPoint>>[];
        for (final ring in polygon) {
          rings.add([
            for (final point in ring)
              GeoPoint(
                (point[1] as num).toDouble(),
                (point[0] as num).toDouble(),
              ),
          ]);
        }
        land.addAll(rings);
        landPolygons.add(rings);
      }
    }
    return RelayAtlas(
      locations: locations,
      land: land,
      landPolygons: landPolygons,
    );
  }
}

class _Marker {
  const _Marker(this.id, this.label, this.position);
  final String id;
  final String label;
  final GeoPoint position;
}

/// Offline map that selects from the API allowlist; it never switches a relay.
class RelayMap extends StatefulWidget {
  const RelayMap({
    super.key,
    required this.relays,
    required this.selected,
    required this.onSelected,
    this.atlas,
  });
  final List<Map<String, dynamic>> relays;
  final String selected;
  final ValueChanged<String>? onSelected;
  final Future<RelayAtlas>? atlas;

  @override
  State<RelayMap> createState() => _RelayMapState();
}

class _RelayMapState extends State<RelayMap> {
  late final Future<RelayAtlas> _atlas = widget.atlas ?? RelayAtlas.load();
  final _transform = TransformationController();
  String? _hovered;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  _Marker? _nearest(Offset point, Size size, List<_Marker> markers) {
    _Marker? nearest;
    var distance = math.max(4.0, 14 / _transform.value.getMaxScaleOnAxis());
    for (final marker in markers) {
      final candidate = (marker.position.project(size) - point).distance;
      if (candidate < distance) {
        nearest = marker;
        distance = candidate;
      }
    }
    return nearest;
  }

  void _zoom(double factor, Size size) {
    final scale = (_transform.value.getMaxScaleOnAxis() * factor).clamp(
      1.0,
      8.0,
    );
    final focus = _transform.toScene(Offset(size.width / 2, size.height / 2));
    _transform.value = scale == 1
        ? Matrix4.identity()
        : (Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(
            size.width / 2 - focus.dx * scale,
            size.height / 2 - focus.dy * scale,
            0,
          ));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<RelayAtlas>(
    future: _atlas,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('Map unavailable. You can still choose a relay below.'),
        );
      }
      final atlas = snapshot.data;
      if (atlas == null) {
        return const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final markers = [
        for (final relay in widget.relays)
          if (atlas.locations[relay['id']] case final GeoPoint location)
            _Marker(relay['id'] as String, relay['label'] as String, location),
      ];
      _Marker? highlighted;
      for (final marker in markers) {
        if (marker.id == (_hovered ?? widget.selected)) highlighted = marker;
      }
      final unlocated =
          widget.relays.where((relay) => relay['id'] != 'configured').length -
          markers.length;
      final primary = Theme.of(context).colorScheme.primary;
      const gold = Color(0xffffd48a);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.public, size: 18, color: primary),
              const SizedBox(width: 8),
              Text(
                'RELAY ATLAS',
                style: TextStyle(
                  color: primary,
                  letterSpacing: 2,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${markers.length} cities',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 2.35,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest;
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: InteractiveViewer(
                          transformationController: _transform,
                          minScale: 1,
                          maxScale: 8,
                          boundaryMargin: const EdgeInsets.all(40),
                          trackpadScrollCausesScale: true,
                          child: MouseRegion(
                            cursor: widget.onSelected == null
                                ? SystemMouseCursors.basic
                                : SystemMouseCursors.click,
                            onHover: (event) {
                              final id = _nearest(
                                event.localPosition,
                                size,
                                markers,
                              )?.id;
                              if (id != _hovered) setState(() => _hovered = id);
                            },
                            onExit: (_) => setState(() => _hovered = null),
                            child: GestureDetector(
                              key: const ValueKey('relay-map-surface'),
                              behavior: HitTestBehavior.opaque,
                              onTapUp: widget.onSelected == null
                                  ? null
                                  : (event) {
                                      final marker = _nearest(
                                        event.localPosition,
                                        size,
                                        markers,
                                      );
                                      if (marker != null) {
                                        widget.onSelected!(marker.id);
                                      }
                                    },
                              child: TweenAnimationBuilder<double>(
                                key: ValueKey(widget.selected),
                                tween: Tween(begin: 0, end: 1),
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 500),
                                builder: (context, progress, _) => CustomPaint(
                                  size: size,
                                  painter: _AtlasPainter(
                                    atlas,
                                    markers,
                                    widget.selected,
                                    _hovered,
                                    primary,
                                    gold,
                                    progress,
                                    widget.onSelected,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xdd101f26),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Zoom in',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _zoom(1.6, size),
                                icon: const Icon(Icons.add, size: 18),
                              ),
                              IconButton(
                                tooltip: 'Zoom out',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _zoom(1 / 1.6, size),
                                icon: const Icon(Icons.remove, size: 18),
                              ),
                              IconButton(
                                tooltip: 'Reset map',
                                visualDensity: VisualDensity.compact,
                                onPressed: () =>
                                    _transform.value = Matrix4.identity(),
                                icon: const Icon(
                                  Icons.center_focus_weak,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              Text(
                '● Available',
                style: TextStyle(color: primary, fontSize: 12),
              ),
              const Text(
                '◉ Selected destination',
                style: TextStyle(color: gold, fontSize: 12),
              ),
              const Text(
                'Zoom to pick nearby cities · drag to explore',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            highlighted?.label.split(' (').first ??
                (widget.selected == 'configured'
                    ? 'Configured default has no map pin. Choose a city to explore.'
                    : 'Select a dot or use the relay list below.'),
            key: const ValueKey('relay-map-caption'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (unlocated > 0)
            Text(
              '$unlocated additional relay(s) available in the list; map position unknown.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 6),
          Text(
            'City locations only—not live tunnel status. Map selection does not connect.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    },
  );
}

class _AtlasPainter extends CustomPainter {
  _AtlasPainter(
    this.atlas,
    this.markers,
    this.selected,
    this.hovered,
    this.primary,
    this.gold,
    this.progress,
    this.onSelected,
  );
  final RelayAtlas atlas;
  final List<_Marker> markers;
  final String selected;
  final String? hovered;
  final Color primary;
  final Color gold;
  final double progress;
  final ValueChanged<String>? onSelected;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff142933), Color(0xff0a171e)],
        ).createShader(Offset.zero & size),
    );
    final grid = Paint()
      ..color = primary.withValues(alpha: 0.07)
      ..strokeWidth = 0.7;
    for (var lon = -150; lon < 180; lon += 30) {
      canvas.drawLine(
        GeoPoint(85, lon.toDouble()).project(size),
        GeoPoint(-60, lon.toDouble()).project(size),
        grid,
      );
    }
    for (var lat = -60; lat <= 60; lat += 30) {
      canvas.drawLine(
        GeoPoint(lat.toDouble(), -180).project(size),
        GeoPoint(lat.toDouble(), 180).project(size),
        grid,
      );
    }
    final landFill = Paint()..color = const Color(0xff27434b);
    final coastline = Paint()
      ..color = primary.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    final polygons =
        atlas.landPolygons ??
        [
          for (final ring in atlas.land) [ring],
        ];
    // Small, independent paths avoid a single complex world mesh in CanvasKit.
    // Keep holes in the same path as their exterior so inland water stays clear.
    for (final polygon in polygons) {
      final land = Path()..fillType = PathFillType.evenOdd;
      for (final ring in polygon) {
        if (ring.isEmpty) continue;
        final first = ring.first.project(size);
        land.moveTo(first.dx, first.dy);
        for (final coordinate in ring.skip(1)) {
          final point = coordinate.project(size);
          land.lineTo(point.dx, point.dy);
        }
        land.close();
      }
      canvas.drawPath(land, landFill);
      canvas.drawPath(land, coastline);
    }
    // Paint the chosen marker last, keeping it visible in dense city clusters.
    final ordered = [
      ...markers.where((m) => m.id != selected),
      ...markers.where((m) => m.id == selected),
    ];
    for (final marker in ordered) {
      final point = marker.position.project(size);
      final chosen = marker.id == selected;
      final active = chosen || marker.id == hovered;
      final color = chosen ? gold : primary;
      if (active) {
        canvas.drawCircle(
          point,
          9,
          Paint()..color = color.withValues(alpha: 0.16),
        );
        canvas.drawCircle(
          point,
          8,
          Paint()
            ..color = color.withValues(alpha: 0.65)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
      if (chosen && progress < 1) {
        canvas.drawCircle(
          point,
          9 + progress * 12,
          Paint()
            ..color = gold.withValues(alpha: 0.6 * (1 - progress))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
      canvas.drawCircle(point, active ? 4 : 2.8, Paint()..color = color);
      canvas.drawCircle(
        point,
        active ? 1.4 : 0.8,
        Paint()..color = const Color(0xffedfdf8),
      );
    }
    canvas.restore();
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => [
        for (final marker in markers)
          CustomPainterSemantics(
            rect: Rect.fromCircle(
              center: marker.position.project(size),
              radius: 10,
            ),
            properties: SemanticsProperties(
              textDirection: TextDirection.ltr,
              label: 'Select ${marker.label}',
              button: true,
              selected: marker.id == selected,
              onTap: onSelected == null ? null : () => onSelected!(marker.id),
            ),
          ),
      ];

  @override
  bool shouldRepaint(covariant _AtlasPainter oldDelegate) => true;

  @override
  bool shouldRebuildSemantics(covariant _AtlasPainter oldDelegate) => true;
}
