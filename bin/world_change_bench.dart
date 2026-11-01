import 'dart:math' as math;

import 'package:battle_pathfinding/battle_pathfinding.dart';

/// P-07 (M3 Issue 5): the time to apply one world change on a live map of
/// 256 × 256 cells (one tile of stack decision 5) whose step cache holds
/// long paths. Prints one machine-readable line.
///
/// ```sh
/// dart run bin/world_change_bench.dart
/// dart compile exe bin/world_change_bench.dart -o /tmp/bench && /tmp/bench
/// ```
void main() {
  const size = 256;
  final random = math.Random(1);
  const terrains = ['grass', 'grass', 'grass', 'road', 'mud', 'forest_floor'];
  final ground = [
    for (var i = 0; i < size * size; i++)
      NavCell(
        height: random.nextDouble() * 3,
        terrain: terrains[random.nextInt(terrains.length)],
      ),
  ];
  final live = LivePathfinder(
    map: NavigationMap(
      cellSizeM: 10,
      width: size,
      depth: size,
      ground: ground,
      waterTerrains: const {'river', 'lake'},
    ),
    cost: _cost,
  );
  const mover = PathMover(apPerM: 1, modes: ['foot']);
  final warm = Stopwatch()..start();
  for (var path = 0; path < 4; path++) {
    live.find(
      mover: mover,
      from: CellRef(random.nextInt(size), 0),
      to: CellRef(random.nextInt(size), size - 1),
    );
  }
  warm.stop();
  final cached = live.cachedSteps;
  final times = <int>[];
  for (var change = 0; change < 200; change++) {
    final watch = Stopwatch()..start();
    live.apply(switch (change % 3) {
      0 => CraterDug(
        Crater(
          centreXM: random.nextDouble() * size * 10,
          centreYM: random.nextDouble() * size * 10,
          radiusM: 8,
          depthM: 3,
        ),
      ),
      1 => ObjectBuilt(
        CellRef(random.nextInt(size), random.nextInt(size)),
        'wall',
      ),
      _ => ConstructionBuilt(
        CellRef(random.nextInt(size), random.nextInt(size)),
        'road',
      ),
    });
    watch.stop();
    times.add(watch.elapsedMicroseconds);
  }
  times.sort();
  final mean = times.reduce((a, b) => a + b) / times.length;
  // ignore: avoid_print, the benchmark's output.
  print(
    'bench=world_change cells=${size * size} cached_steps=$cached '
    'warm_ms=${warm.elapsedMilliseconds} changes=${times.length} '
    'mean_us=${mean.round()} p50_us=${times[times.length ~/ 2]} '
    'p95_us=${times[times.length * 95 ~/ 100]} max_us=${times.last}',
  );
}

double? _cost(double apPerM, String mode, String terrain, double slope) {
  const multipliers = {
    'grass': 1.0,
    'road': 0.7,
    'mud': 2.0,
    'forest_floor': 1.5,
  };
  final multiplier = multipliers[terrain];
  if (multiplier == null || slope.abs() > 45) return null;
  return apPerM * multiplier * math.max(0.5, 1 + slope * 0.05);
}
