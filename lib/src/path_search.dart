import 'dart:math' as math;

import 'package:battle_pathfinding/src/navigation_map.dart';
import 'package:battle_pathfinding/src/world_change.dart';

/// The AP per metre of a mover whose flat-grass cost is `apPerM`, moving
/// with movement class or profile `mode` over `terrainType` at a signed
/// `slopeDegrees`; null when impassable.
///
/// Injected by the caller: the rules core's `MovementCost.call` has this
/// shape (M4 Issue 4), so the two packages never depend on each other.
typedef MovementCostFunction = double? Function(
  double apPerM,
  String mode,
  String terrainType,
  double slopeDegrees,
);

/// {@template path_sample}
/// One stretch of a path: its terrain type, signed slope in degrees, length
/// in metres, and the mode that priced it. The rules core takes the first
/// three as its own path samples (M4 Issue 4).
/// {@endtemplate}
final class PathSample {
  /// {@macro path_sample}
  const new({
    required this.terrainType,
    required this.slopeDegrees,
    required this.lengthM,
    required this.mode,
  });

  /// A terrain type name.
  final String terrainType;

  /// Signed slope in degrees: positive uphill.
  final double slopeDegrees;

  /// Length in metres.
  final double lengthM;

  /// The movement class or profile that crossed it.
  final String mode;
}

/// {@template path_mover}
/// What looks for a path: its AP per metre on flat grass and the movement
/// classes or profiles it may use (MAP-11 to MAP-19). A boat is
/// `['sail']`, an amphibious unit `['wheeled', 'sail']`, a flying unit in
/// the air `['flying']` (UNIT-01, UNIT-02).
/// {@endtemplate}
final class PathMover {
  /// {@macro path_mover}
  const new({required this.apPerM, required this.modes});

  /// AP per metre on flat grass.
  final double apPerM;

  /// The movement classes or profiles it may use; each step takes the
  /// cheapest one that passes.
  final List<String> modes;
}

/// {@template path_rules}
/// How the map's objects, constructions and links are crossed. The
/// defaults follow the specs and the assumptions recorded in M3.3's
/// session log.
/// {@endtemplate}
final class PathRules {
  /// {@macro path_rules}
  const new({
    this.groundModes = const {'foot', 'wheeled', 'tracked', 'push'},
    this.ladderModes = const {'foot'},
    this.reinforcedOnlyModes = const {'push'},
    this.fallModes = const {'push'},
    this.flyingMode = 'flying',
    this.bridgeConstructions = const {'bridge', 'reinforced_bridge'},
    this.reinforcedBridgeConstruction = 'reinforced_bridge',
    this.bridgeTerrain = 'road',
    this.roadConstruction = 'road',
    this.roadTerrain = 'road',
    this.blockingObjects = const {'building', 'wall'},
    this.altitudeLimitM = double.infinity,
  });

  /// The ground movement classes and the `push` profile: they use bridges
  /// and roads, and are stopped by blocking objects.
  final Set<String> groundModes;

  /// The modes that climb ladders: foot units only.
  final Set<String> ladderModes;

  /// The modes that cross water and reach islands only on reinforced
  /// bridges: pushed relics and the moving HQ (RELIC-26, HQ-11).
  final Set<String> reinforcedOnlyModes;

  /// The modes that can go over a floating island's edge and fall: pushed
  /// relics and the moving HQ (RELIC-22, HQ-48).
  final Set<String> fallModes;

  /// The flying profile: it ignores objects and changes surface freely.
  final String flyingMode;

  /// Constructions that let ground classes cross a water cell (MAP-23).
  final Set<String> bridgeConstructions;

  /// The construction that carries relics and the HQ over water
  /// (decision 99).
  final String reinforcedBridgeConstruction;

  /// The terrain a bridge deck is priced as.
  final String bridgeTerrain;

  /// The construction that makes a cell a road.
  final String roadConstruction;

  /// The terrain a road cell is priced as.
  final String roadTerrain;

  /// Objects ground classes cannot cross.
  final Set<String> blockingObjects;

  /// The highest a flying unit may be: the map's highest point +
  /// `flying_max_above_highest_terrain_m` (MAP-17, decision 142).
  final double altitudeLimitM;
}

/// {@template found_path}
/// A path: the [cells] it visits, from start to goal, its [samples], its
/// [cost] in AP (the sum of its samples under the cost), and the cells
/// where it lands after falling from an island's edge ([falls]).
/// {@endtemplate}
final class FoundPath {
  /// {@macro found_path}
  const new({
    required this.cells,
    required this.samples,
    required this.cost,
    this.falls = const [],
  });

  /// The cells visited, start and goal included.
  final List<CellRef> cells;

  /// The path as samples for the rules core.
  final List<PathSample> samples;

  /// Its AP cost.
  final double cost;

  /// The ground cells it lands on after going over an island's edge
  /// (RELIC-22, HQ-48).
  final List<CellRef> falls;
}

/// Why a step of a path check fails.
enum StepFailure {
  /// The map has no such cell.
  unknownCell,

  /// The two cells are neither neighbours nor linked.
  notConnected,

  /// No mode of the mover can make the step: impassable terrain, a slope
  /// over the limit, a blocking object.
  impassable,
}

/// The outcome of a path check (stack decision 8).
sealed class PathCheck {
  const new();
}

/// {@template path_passes}
/// The path is valid: its [cost], [samples] and [falls].
/// {@endtemplate}
final class PathPasses extends PathCheck {
  /// {@macro path_passes}
  const new({required this.cost, required this.samples, this.falls = const []});

  /// Its AP cost.
  final double cost;

  /// The path as samples.
  final List<PathSample> samples;

  /// The ground cells it lands on after a fall.
  final List<CellRef> falls;
}

/// {@template path_fails}
/// The path is invalid at [step] (the index of the cell it fails to
/// reach), for [reason].
/// {@endtemplate}
final class PathFails extends PathCheck {
  /// {@macro path_fails}
  const new({required this.step, required this.reason});

  /// The index of the first cell that cannot be reached.
  final int step;

  /// Why.
  final StepFailure reason;
}

/// {@template pathfinder}
/// Cheapest paths in AP on a [NavigationMap], with an injected [cost]
/// (M3 Issue 3).
/// {@endtemplate}
final class Pathfinder {
  /// {@macro pathfinder}
  const new({
    required this.map,
    required this.cost,
    this.rules = const PathRules(),
    this.cache,
  });

  /// The map.
  final NavigationMap map;

  /// The movement cost.
  final MovementCostFunction cost;

  /// How objects, constructions and links are crossed.
  final PathRules rules;

  /// Steps already priced on this map; null to price every step again.
  final StepCache? cache;

  /// The cheapest path in AP for [mover] from [from] to [to]; null when
  /// there is none: the mover is stranded (MAP-37).
  FoundPath? find({
    required PathMover mover,
    required CellRef from,
    required CellRef to,
  }) {
    if (map.cellAt(from) == null || map.cellAt(to) == null) return null;
    final best = <CellRef, double>{from: 0};
    final previous = <CellRef, (CellRef, _Step)>{};
    final queue = _Queue()..add(from, 0);
    while (queue.isNotEmpty) {
      final (cell, spent) = queue.removeFirst();
      if (spent > best[cell]!) continue;
      if (cell == to) break;
      for (final (next, step) in _steps(mover, cell)) {
        final total = spent + step.cost;
        if (total < (best[next] ?? double.infinity)) {
          best[next] = total;
          previous[next] = (cell, step);
          queue.add(next, total);
        }
      }
    }
    final total = best[to];
    if (total == null) return null;
    final cells = <CellRef>[to];
    final steps = <_Step>[];
    final falls = <CellRef>[];
    for (var cell = to; cell != from;) {
      final (before, step) = previous[cell]!;
      if (step.fall) falls.add(cell);
      cells.add(before);
      steps.add(step);
      cell = before;
    }
    return FoundPath(
      cells: List.unmodifiable(cells.reversed),
      samples: List.unmodifiable([
        for (final step in steps.reversed) ...step.samples,
      ]),
      cost: total,
      falls: List.unmodifiable(falls.reversed),
    );
  }

  /// Checks a path a client sent (stack decision 8): walks it cell by cell
  /// with the same rules and cost, without searching again, and returns its
  /// cost or the first step that fails.
  PathCheck check({required PathMover mover, required List<CellRef> path}) {
    for (final (index, cell) in path.indexed) {
      if (map.cellAt(cell) == null) {
        return PathFails(step: index, reason: StepFailure.unknownCell);
      }
    }
    var total = 0.0;
    final samples = <PathSample>[];
    final falls = <CellRef>[];
    for (var index = 1; index < path.length; index++) {
      final from = path[index - 1];
      final to = path[index];
      final link = _linkBetween(from, to);
      if (link == null && !_adjacent(from, to)) {
        return PathFails(step: index, reason: StepFailure.notConnected);
      }
      final step = _cheapestStep(mover, from, to, link);
      if (step == null) {
        return PathFails(step: index, reason: StepFailure.impassable);
      }
      total += step.cost;
      samples.addAll(step.samples);
      if (step.fall) falls.add(to);
    }
    return PathPasses(
      cost: total,
      samples: List.unmodifiable(samples),
      falls: List.unmodifiable(falls),
    );
  }

  /// Every step [mover] can make from [cell].
  Iterable<(CellRef, _Step)> _steps(PathMover mover, CellRef cell) sync* {
    final targets = <(CellRef, SurfaceLink?)>[
      for (final next in map.neighbours(cell)) (next, null),
      for (final link in map.linksFrom(cell)) (link.to, link),
      for (final next in _otherSurfaces(cell)) (next, null),
      for (final next in _edgesBelow(cell)) (next, null),
    ];
    for (final (next, link) in targets) {
      final step = _cheapestStep(mover, cell, next, link);
      if (step != null) yield (next, step);
    }
  }

  /// The cells at the same column and row on the other surfaces: a flying
  /// unit goes up to or down from an island there.
  Iterable<CellRef> _otherSurfaces(CellRef cell) => [
    for (final surface in [groundSurface, ...map.islands.keys])
      if (surface != cell.surface) CellRef(cell.x, cell.y, surface: surface),
  ].where((other) => map.cellAt(other) != null);

  /// The ground cells next to an island cell that the island does not
  /// cover: going there is going over the island's edge.
  Iterable<CellRef> _edgesBelow(CellRef cell) sync* {
    if (cell.surface == groundSurface) return;
    final island = map.islands[cell.surface]!;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final x = cell.x + dx;
        final y = cell.y + dy;
        final below = CellRef(x, y);
        if (!island.containsKey((x, y)) && map.cellAt(below) != null) {
          yield below;
        }
      }
    }
  }

  bool _adjacent(CellRef from, CellRef to) =>
      (from.x - to.x).abs() <= 1 && (from.y - to.y).abs() <= 1 && from != to;

  SurfaceLink? _linkBetween(CellRef from, CellRef to) {
    for (final link in map.linksFrom(from)) {
      if (link.to == to) return link;
    }
    return null;
  }

  /// The cheapest way for [mover] to step from [from] to [to]: one mode
  /// for a link or a change of surface; between neighbours, each half-step
  /// takes its own cheapest mode, so an amphibious unit drives onto the
  /// shore and sails off it.
  _Step? _cheapestStep(
    PathMover mover,
    CellRef from,
    CellRef to,
    SurfaceLink? link,
  ) {
    final cache = this.cache;
    if (cache == null) return _priceStep(mover, from, to, link);
    final key = (
      '${mover.apPerM}|${mover.modes.join(',')}',
      from,
      to,
      link?.kind,
    );
    if (cache._steps.containsKey(key)) return cache._steps[key];
    final step = _priceStep(mover, from, to, link);
    cache._store(key, step);
    return step;
  }

  _Step? _priceStep(
    PathMover mover,
    CellRef from,
    CellRef to,
    SurfaceLink? link,
  ) {
    if (link == null &&
        from.surface != to.surface &&
        (from.x != to.x || from.y != to.y)) {
      return _fall(mover, from, to);
    }
    if (link != null || from.surface != to.surface) {
      _Step? cheapest;
      for (final mode in mover.modes) {
        final step = link != null
            ? _linkStep(mover.apPerM, mode, from, to, link)
            : _surfaceStep(mode, from, to);
        if (step != null && (cheapest == null || step.cost < cheapest.cost)) {
          cheapest = step;
        }
      }
      return cheapest;
    }
    final slope = map.slopeDegrees(from, to);
    final half = map.stepLengthM(from, to) / 2;
    final first = _cheapestHalf(mover, from, slope, half, entering: false);
    final second = _cheapestHalf(mover, to, slope, half, entering: true);
    if (first == null || second == null) return null;
    return _Step(
      cost: first.cost + second.cost,
      samples: [...first.samples, ...second.samples],
    );
  }

  /// The cheapest mode of [mover] over half a step on [ref]. A ground
  /// class cannot enter a cell with a blocking object; a flyer cannot pass
  /// over the altitude limit.
  _Step? _cheapestHalf(
    PathMover mover,
    CellRef ref,
    double slope,
    double length, {
    required bool entering,
  }) {
    final cell = map.cellAt(ref)!;
    _Step? cheapest;
    for (final mode in mover.modes) {
      if (rules.groundModes.contains(mode) && entering && _blocked(ref)) {
        continue;
      }
      if (mode == rules.flyingMode && cell.height > rules.altitudeLimitM) {
        continue;
      }
      final step = _priced(mover.apPerM, mode, [
        (_terrain(ref, cell, mode), slope, length),
      ]);
      if (step != null && (cheapest == null || step.cost < cheapest.cost)) {
        cheapest = step;
      }
    }
    return cheapest;
  }

  /// A bridge or a ladder, crossed with [mode].
  _Step? _linkStep(
    double apPerM,
    String mode,
    CellRef from,
    CellRef to,
    SurfaceLink link,
  ) {
    final start = map.cellAt(from)!;
    final end = map.cellAt(to)!;
    if (link.kind == LinkKind.ladder) {
      if (!rules.ladderModes.contains(mode)) return null;
      return _priced(apPerM, mode, [
        (end.terrain, 0.0, (end.height - start.height).abs()),
      ]);
    }
    if (!rules.groundModes.contains(mode)) return null;
    if (rules.reinforcedOnlyModes.contains(mode) &&
        link.kind != LinkKind.reinforcedBridge) {
      return null;
    }
    final run =
        math.sqrt(math.pow(to.x - from.x, 2) + math.pow(to.y - from.y, 2)) *
        map.cellSizeM;
    final slope = math.atan2(end.height - start.height, run) * 180 / math.pi;
    return _priced(apPerM, mode, [(rules.bridgeTerrain, slope, run)]);
  }

  /// Going over an island's edge from [from] onto the ground cell [to]:
  /// only a mode that can fall does it; the fall is free (Q-MAP-16).
  _Step? _fall(PathMover mover, CellRef from, CellRef to) {
    final edge =
        from.surface != groundSurface &&
        to.surface == groundSurface &&
        !map.islands[from.surface]!.containsKey((to.x, to.y));
    return edge && mover.modes.any(rules.fallModes.contains)
        ? const _Step(cost: 0, samples: [], fall: true)
        : null;
  }

  /// A flyer going up to or down from an island at the same column and
  /// row: free, under the altitude limit. Other modes cannot.
  _Step? _surfaceStep(String mode, CellRef from, CellRef to) {
    if (mode != rules.flyingMode) return null;
    final highest = math.max(map.cellAt(from)!.height, map.cellAt(to)!.height);
    return highest > rules.altitudeLimitM
        ? null
        : const _Step(cost: 0, samples: []);
  }

  _Step? _priced(
    double apPerM,
    String mode,
    List<(String, double, double)> stretches,
  ) {
    var total = 0.0;
    final samples = <PathSample>[];
    for (final (terrain, slope, length) in stretches) {
      final perMetre = cost(apPerM, mode, terrain, slope);
      if (perMetre == null) return null;
      total += perMetre * length;
      samples.add(
        PathSample(
          terrainType: terrain,
          slopeDegrees: slope,
          lengthM: length,
          mode: mode,
        ),
      );
    }
    return _Step(cost: total, samples: samples);
  }

  bool _blocked(CellRef ref) =>
      map.objectsAt(ref).any(rules.blockingObjects.contains);

  /// The terrain [mode] pays on [cell]: a bridge deck over water and a road
  /// for ground classes, else the cell's own terrain.
  String _terrain(CellRef ref, NavCell cell, String mode) {
    if (!rules.groundModes.contains(mode)) return cell.terrain;
    final built = map.constructionsAt(ref);
    if (map.isWater(ref)) {
      final bridged = rules.reinforcedOnlyModes.contains(mode)
          ? built.contains(rules.reinforcedBridgeConstruction)
          : built.any(rules.bridgeConstructions.contains);
      return bridged ? rules.bridgeTerrain : cell.terrain;
    }
    if (built.contains(rules.roadConstruction)) return rules.roadTerrain;
    return cell.terrain;
  }
}

typedef _StepKey = (String, CellRef, CellRef, LinkKind?);

/// {@template step_cache}
/// The steps a [Pathfinder] has priced, kept between searches on a map that
/// changes (M3 Issue 5): a change forgets only the steps that start or end
/// on a cell it touches.
/// {@endtemplate}
final class StepCache {
  final _steps = <_StepKey, _Step?>{};
  final _byCell = <CellRef, Set<_StepKey>>{};

  /// How many steps it holds.
  int get length => _steps.length;

  void _store(_StepKey key, _Step? step) {
    _steps[key] = step;
    _byCell.putIfAbsent(key.$2, () => {}).add(key);
    _byCell.putIfAbsent(key.$3, () => {}).add(key);
  }

  /// Forgets every step that starts or ends on one of [cells].
  void forget(Iterable<CellRef> cells) {
    for (final cell in cells) {
      (_byCell.remove(cell) ?? const <_StepKey>{}).forEach(_steps.remove);
    }
  }
}

/// {@template live_pathfinder}
/// Paths that follow the changes of a battle (M3 Issue 5, MAP-06): it holds
/// the current [map] and the steps it has priced, and each change forgets
/// only the steps it touches. Paths after a change are those a search from
/// scratch on the changed map finds.
/// {@endtemplate}
final class LivePathfinder {
  /// {@macro live_pathfinder}
  new({required this._map, required this.cost, this.rules = const PathRules()});

  /// The movement cost.
  final MovementCostFunction cost;

  /// How objects, constructions and links are crossed.
  final PathRules rules;

  NavigationMap _map;
  final _cache = StepCache();

  /// The map with every change applied so far.
  NavigationMap get map => _map;

  /// The steps priced and kept.
  int get cachedSteps => _cache.length;

  Pathfinder get _finder =>
      Pathfinder(map: _map, cost: cost, rules: rules, cache: _cache);

  /// See [Pathfinder.find].
  FoundPath? find({
    required PathMover mover,
    required CellRef from,
    required CellRef to,
  }) => _finder.find(mover: mover, from: from, to: to);

  /// See [Pathfinder.check].
  PathCheck check({required PathMover mover, required List<CellRef> path}) =>
      _finder.check(mover: mover, path: path);

  /// Applies [change] and forgets the steps it touches; returns the cells
  /// it touched.
  Set<CellRef> apply(WorldChange change) {
    final (map, touched) = applyChange(_map, change);
    _map = map;
    _cache.forget(touched);
    return touched;
  }
}

/// One step: its AP cost and its samples.
final class _Step {
  const new({required this.cost, required this.samples, this.fall = false});

  final double cost;
  final List<PathSample> samples;
  final bool fall;
}

/// A binary min-heap of cells by AP spent.
final class _Queue {
  final _items = <(CellRef, double)>[];

  bool get isNotEmpty => _items.isNotEmpty;

  void add(CellRef cell, double spent) {
    _items.add((cell, spent));
    var index = _items.length - 1;
    while (index > 0) {
      final parent = (index - 1) ~/ 2;
      if (_items[parent].$2 <= _items[index].$2) break;
      _swap(index, parent);
      index = parent;
    }
  }

  (CellRef, double) removeFirst() {
    final first = _items.first;
    final last = _items.removeLast();
    if (_items.isNotEmpty) {
      _items[0] = last;
      var index = 0;
      while (true) {
        final left = 2 * index + 1;
        final right = left + 1;
        var smallest = index;
        if (left < _items.length && _items[left].$2 < _items[smallest].$2) {
          smallest = left;
        }
        if (right < _items.length && _items[right].$2 < _items[smallest].$2) {
          smallest = right;
        }
        if (smallest == index) break;
        _swap(index, smallest);
        index = smallest;
      }
    }
    return first;
  }

  void _swap(int a, int b) {
    final item = _items[a];
    _items[a] = _items[b];
    _items[b] = item;
  }
}
