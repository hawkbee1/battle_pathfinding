import 'dart:math' as math;

import 'package:battle_pathfinding/src/navigation_map.dart';

/// A seeded synthetic map for tests and benchmarks (M3 Issue 6): rolling
/// heights in whole metres, forests, mud and mountains, a grid of roads
/// every [roadEvery] cells, and a river winding across the map with a
/// bridge wherever a road crosses it. It is generated, never committed as
/// data.
///
/// Cells are shared between equal heights and terrains, so a 1,000 × 5,000
/// map stays small in memory.
NavigationMap syntheticMap({
  required int width,
  required int depth,
  required int seed,
  double cellSizeM = 10,
  int roadEvery = 80,
}) {
  final random = math.Random(seed);
  final phases = [
    for (var i = 0; i < 6; i++) random.nextDouble() * 2 * math.pi,
  ];
  // Distances in metres, so a coarser grid keeps the same landscape.
  final unit = cellSizeM / 10;
  final cells = <(int, String), NavCell>{};
  final ground = <NavCell>[];
  final bridges = <CellRef, Set<String>>{};
  for (var y = 0; y < depth; y++) {
    for (var x = 0; x < width; x++) {
      final mx = x * unit;
      final my = y * unit;
      final height =
          (20 +
                  15 *
                      math.sin(mx / 97 + phases[0]) *
                      math.cos(my / 131 + phases[1]) +
                  6 *
                      math.sin(mx / 23 + phases[2]) *
                      math.sin(my / 29 + phases[3]))
              .round();
      final texture =
          math.sin(mx / 13 + phases[4]) * math.cos(my / 17 + phases[0]) +
          random.nextDouble() * 0.3;
      final road =
          (x * unit).round() % roadEvery == 0 ||
          (y * unit).round() % roadEvery == 0;
      // The river winds across the map, around its middle row.
      final riverRow = depth / 2 + 40 / unit * math.sin(mx / 50 + phases[5]);
      final river = (y - riverRow).abs() < 2 / unit + 0.5;
      final terrain = river
          ? 'river'
          : road
          ? 'road'
          : height > 38
          ? 'mountain'
          : texture > 0.85
          ? 'forest_floor'
          : texture < -0.9
          ? 'mud'
          : 'grass';
      if (river && road) bridges[CellRef(x, y)] = const {'bridge'};
      ground.add(
        cells.putIfAbsent((
          height,
          terrain,
        ), () => NavCell(height: height.toDouble(), terrain: terrain)),
      );
    }
  }
  return NavigationMap(
    cellSizeM: cellSizeM,
    width: width,
    depth: depth,
    ground: ground,
    waterTerrains: const {'river', 'lake'},
    constructions: bridges,
  );
}
