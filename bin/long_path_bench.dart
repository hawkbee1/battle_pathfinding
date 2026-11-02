import 'dart:io';
import 'dart:math' as math;

import 'package:battle_pathfinding/battle_pathfinding.dart';

/// P-01 (M3 Issue 6): paths across a synthetic 10 × 50 km map, at 10 m
/// cells (1,000 × 5,000) and at 20 m cells (500 × 2,500). For each, it
/// times fast paths between the north and the south edges, times the exact
/// search on some of them, and compares their AP. Prints one
/// machine-readable line per cell size and mover.
///
/// ```sh
/// dart compile exe bin/long_path_bench.dart -o /tmp/long_path_bench
/// /tmp/long_path_bench [fast paths] [exact paths] [span km]
/// ```
///
/// Without a span, paths go from near the north edge to near the south
/// edge; with one, from a random cell to a cell that far south of it.
void main(List<String> arguments) {
  final fastPaths = arguments.isNotEmpty ? int.parse(arguments[0]) : 10;
  final exactPaths = arguments.length > 1 ? int.parse(arguments[1]) : 2;
  final spanKm = arguments.length > 2 ? double.parse(arguments[2]) : null;
  for (final cellSize in const [10.0, 20.0]) {
    final width = (10000 / cellSize).round();
    final depth = (50000 / cellSize).round();
    final build = Stopwatch()..start();
    final map = syntheticMap(
      width: width,
      depth: depth,
      seed: 42,
      cellSizeM: cellSize,
    );
    build.stop();
    for (final mover in const [
      PathMover(apPerM: 1, modes: ['foot']),
      PathMover(apPerM: 0.1, modes: ['wheeled']),
    ]) {
      final prepare = Stopwatch()..start();
      final search = GroundSearch(map: map, cost: _cost, mover: mover);
      prepare.stop();
      final random = math.Random(7);
      final span = spanKm == null ? null : (spanKm * 1000 / cellSize).round();
      final pairs = [
        for (var i = 0; i < fastPaths; i++)
          if (span == null)
            (
              CellRef(random.nextInt(width), random.nextInt(depth ~/ 50)),
              CellRef(
                random.nextInt(width),
                depth - 1 - random.nextInt(depth ~/ 50),
              ),
            )
          else
            _spanPair(random, width, depth, span),
      ];
      final fastTimes = <int>[];
      final fastCosts = <double?>[];
      var settled = 0;
      for (final (from, to) in pairs) {
        final watch = Stopwatch()..start();
        final path = search.fast(from, to);
        watch.stop();
        fastTimes.add(watch.elapsedMilliseconds);
        fastCosts.add(path?.cost);
        settled += search.lastSettled;
      }
      final exactTimes = <int>[];
      var margin = 0.0;
      for (var i = 0; i < math.min(exactPaths, pairs.length); i++) {
        final (from, to) = pairs[i];
        final watch = Stopwatch()..start();
        final exact = search.exact(from, to);
        watch.stop();
        exactTimes.add(watch.elapsedMilliseconds);
        final fast = fastCosts[i];
        if (exact != null && fast != null) {
          margin = math.max(margin, fast / exact.cost - 1);
        }
      }
      fastTimes.sort();
      stdout.writeln(
        'bench=long_path cell_m=${cellSize.round()} cells=${width * depth} '
        'span_km=${spanKm ?? 'edge_to_edge'} '
        'mover=${mover.modes.join('+')} build_ms=${build.elapsedMilliseconds} '
        'prepare_ms=${prepare.elapsedMilliseconds} paths=${pairs.length} '
        'found=${fastCosts.whereType<double>().length} '
        'fast_median_ms=${fastTimes[fastTimes.length ~/ 2]} '
        'fast_max_ms=${fastTimes.last} '
        'fast_settled_mean=${settled ~/ pairs.length} '
        'exact_ms=${exactTimes.join('/')} '
        'max_margin_pct=${(margin * 100).toStringAsFixed(2)} '
        'rss_mb=${ProcessInfo.currentRss ~/ (1024 * 1024)}',
      );
    }
  }
}

(CellRef, CellRef) _spanPair(
  math.Random random,
  int width,
  int depth,
  int span,
) {
  final x = random.nextInt(width);
  final y = random.nextInt(depth - span);
  return (CellRef(x, y), CellRef(random.nextInt(width), y + span));
}

/// A movement cost shaped like the rules core's, with multipliers close to
/// `terrain.yaml`.
double? _cost(double apPerM, String mode, String terrain, double slope) {
  const multipliers = {
    'foot': {
      'grass': 1.0,
      'road': 0.7,
      'mud': 2.0,
      'forest_floor': 1.5,
      'mountain': 3.0,
    },
    'wheeled': {'grass': 1.0, 'road': 0.4, 'mud': 4.0, 'forest_floor': 3.0},
  };
  const slopes = {'foot': (0.05, 45.0), 'wheeled': (0.1, 25.0)};
  final multiplier = multipliers[mode]?[terrain];
  if (multiplier == null) return null;
  final (factor, steepest) = slopes[mode]!;
  if (slope.abs() > steepest) return null;
  return apPerM * multiplier * math.max(0.5, 1 + slope * factor);
}
