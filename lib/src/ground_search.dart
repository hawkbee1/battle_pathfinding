import 'dart:math' as math;
import 'dart:typed_data';

import 'package:battle_pathfinding/src/navigation_map.dart';
import 'package:battle_pathfinding/src/path_search.dart';

/// {@template ground_search}
/// Long paths across the ground of big maps (M3 Issue 6, MAP-04): up to
/// 1,000 × 5,000 cells of 10 m.
///
/// It prices steps exactly as [Pathfinder] does (half a step on each
/// cell's terrain, the cheapest mode per half), with typed arrays and
/// memoized costs. [exact] searches the whole ground; [fast] first finds a
/// path over blocks of cells, then searches only a corridor around it. Both
/// return paths through [Pathfinder.check], so their cost and samples are
/// the regular ones. Islands and links are not used: long paths stay on the
/// ground.
/// {@endtemplate}
final class GroundSearch {
  /// {@macro ground_search}
  ///
  /// Prepares the search for [mover] on [map]'s ground.
  new({
    required this.map,
    required this.cost,
    required this.mover,
    this.rules = const PathRules(),
  }) : _cells = map.width * map.depth {
    _heights = Float64List(_cells);
    _blocked = Uint8List(_cells);
    _terrains = [for (final _ in mover.modes) Uint16List(_cells)];
    final names = <String, int>{};
    for (var index = 0; index < _cells; index++) {
      final ref = CellRef(index % map.width, index ~/ map.width);
      final cell = map.cellAt(ref)!;
      _heights[index] = cell.height;
      if (map.objectsAt(ref).any(rules.blockingObjects.contains)) {
        _blocked[index] = 1;
      }
      for (final (m, mode) in mover.modes.indexed) {
        final name = rules.terrainFor(map, ref, cell, mode);
        _terrains[m][index] = names.putIfAbsent(name, () => names.length);
      }
    }
    _terrainNames = [
      for (final entry
          in names.entries.toList()..sort((a, b) => a.value.compareTo(b.value)))
        entry.key,
    ];
    _memo = [
      for (final _ in mover.modes)
        [for (final _ in _terrainNames) <double, double>{}],
    ];
  }

  /// The map.
  final NavigationMap map;

  /// The movement cost.
  final MovementCostFunction cost;

  /// What looks for paths.
  final PathMover mover;

  /// How objects and constructions are crossed.
  final PathRules rules;

  final int _cells;
  late final Float64List _heights;
  late final Uint8List _blocked;
  late final List<Uint16List> _terrains;
  late final List<String> _terrainNames;
  late final List<List<Map<double, double>>> _memo;

  final _blockCosts = <int, Float64List>{};

  Float64List? _spent;
  Int32List? _previous;
  Int32List? _stamps;
  var _stamp = 0;

  /// Cells settled by the last search: a measure of its work.
  int lastSettled = 0;

  /// The cheapest path from [from] to [to] over the whole ground; null when
  /// there is none.
  FoundPath? exact(CellRef from, CellRef to) =>
      _search(_index(from), _index(to), null);

  /// A path from [from] to [to] found within a corridor of [corridor]
  /// blocks of [blockSize] × [blockSize] cells around the cheapest path
  /// over blocks. The corridor doubles until a path is found; null when
  /// even the whole ground has none.
  FoundPath? fast(
    CellRef from,
    CellRef to, {
    int blockSize = 16,
    int corridor = 1,
  }) {
    final start = _index(from);
    final goal = _index(to);
    final blocks = _blockPath(start, goal, blockSize);
    final across = (map.width / blockSize).ceil();
    final down = (map.depth / blockSize).ceil();
    var width = corridor;
    while (blocks != null && width < math.max(across, down)) {
      final allowed = Uint8List(across * down);
      for (final block in blocks) {
        final bx = block % across;
        final by = block ~/ across;
        for (
          var y = math.max(0, by - width);
          y <= math.min(down - 1, by + width);
          y++
        ) {
          for (
            var x = math.max(0, bx - width);
            x <= math.min(across - 1, bx + width);
            x++
          ) {
            allowed[y * across + x] = 1;
          }
        }
      }
      final path = _search(start, goal, (cell) {
        final x = (cell % map.width) ~/ blockSize;
        final y = (cell ~/ map.width) ~/ blockSize;
        return allowed[y * across + x] == 1;
      });
      if (path != null) return path;
      width *= 2;
    }
    return _search(start, goal, null);
  }

  int _index(CellRef ref) {
    if (ref.surface != groundSurface || map.cellAt(ref) == null) {
      throw ArgumentError.value(ref, 'cell', 'not on the ground of the map');
    }
    return ref.y * map.width + ref.x;
  }

  /// AP per metre of the cheapest mode over half a step on [cell] at
  /// [slope]; infinity when no mode passes.
  double _half(int cell, double slope, {required bool entering}) {
    var best = double.infinity;
    for (var m = 0; m < mover.modes.length; m++) {
      final mode = mover.modes[m];
      if (entering && _blocked[cell] == 1 && rules.groundModes.contains(mode)) {
        continue;
      }
      if (mode == rules.flyingMode && _heights[cell] > rules.altitudeLimitM) {
        continue;
      }
      final terrain = _terrains[m][cell];
      final perMetre = _memo[m][terrain].putIfAbsent(
        slope,
        () =>
            cost(mover.apPerM, mode, _terrainNames[terrain], slope) ??
            double.infinity,
      );
      if (perMetre < best) best = perMetre;
    }
    return best;
  }

  /// Dijkstra over the ground cells [allowed] keeps (all when null).
  FoundPath? _search(int start, int goal, bool Function(int cell)? allowed) {
    final spent = _spent ??= Float64List(_cells);
    final previous = _previous ??= Int32List(_cells);
    final stamps = _stamps ??= Int32List(_cells);
    final stamp = ++_stamp;
    final heap = _Heap();
    spent[start] = 0;
    previous[start] = -1;
    stamps[start] = stamp;
    heap.push(start, 0);
    final width = map.width;
    final side = map.cellSizeM;
    final diagonal = side * math.sqrt2;
    var settled = 0;
    var found = false;
    while (heap.isNotEmpty) {
      final at = heap.topCost;
      final cell = heap.pop();
      if (at > spent[cell]) continue;
      settled++;
      if (cell == goal) {
        found = true;
        break;
      }
      final x = cell % width;
      final y = cell ~/ width;
      for (var dy = -1; dy <= 1; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= map.depth) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          if ((dx == 0 && dy == 0) || nx < 0 || nx >= width) continue;
          final next = ny * width + nx;
          if (allowed != null && !allowed(next)) continue;
          final length = dx != 0 && dy != 0 ? diagonal : side;
          final slope =
              math.atan2(_heights[next] - _heights[cell], length) *
              180 /
              math.pi;
          final first = _half(cell, slope, entering: false);
          if (first == double.infinity) continue;
          final second = _half(next, slope, entering: true);
          if (second == double.infinity) continue;
          final total = at + (first + second) * length / 2;
          if (stamps[next] != stamp || total < spent[next]) {
            stamps[next] = stamp;
            spent[next] = total;
            previous[next] = cell;
            heap.push(next, total);
          }
        }
      }
    }
    lastSettled = settled;
    if (!found) return null;
    final cells = <CellRef>[];
    for (var cell = goal; cell != -1; cell = previous[cell]) {
      cells.add(CellRef(cell % width, cell ~/ width));
    }
    final check = Pathfinder(
      map: map,
      cost: cost,
      rules: rules,
    ).check(mover: mover, path: cells.reversed.toList()) as PathPasses;
    return FoundPath(
      cells: List.unmodifiable(cells.reversed),
      samples: check.samples,
      cost: check.cost,
    );
  }

  /// The cheapest path over blocks of [blockSize] cells: each block costs
  /// the AP per metre of its cheapest cell on flat ground, so the blocks of
  /// a road are cheap and the block path follows roads; a block with no
  /// passable cell is left out. Null when the blocks give no path.
  List<int>? _blockPath(int start, int goal, int blockSize) {
    final across = (map.width / blockSize).ceil();
    final down = (map.depth / blockSize).ceil();
    final perMetre = _blockCosts.putIfAbsent(
      blockSize,
      () => _priceBlocks(blockSize, across, down),
    );
    int blockOf(int cell) =>
        ((cell ~/ map.width) ~/ blockSize) * across +
        (cell % map.width) ~/ blockSize;
    final first = blockOf(start);
    final last = blockOf(goal);
    // The start and goal blocks always count, even when mostly blocked.
    double blockCost(int block) =>
        (block == first || block == last) && perMetre[block] == double.infinity
        ? 0
        : perMetre[block];
    final spent = Float64List(across * down)
      ..fillRange(0, across * down, double.infinity);
    final previous = Int32List(across * down)..fillRange(0, across * down, -1);
    final heap = _Heap();
    spent[first] = 0;
    heap.push(first, 0);
    while (heap.isNotEmpty) {
      final at = heap.topCost;
      final block = heap.pop();
      if (at > spent[block]) continue;
      if (block == last) break;
      final bx = block % across;
      final by = block ~/ across;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = bx + dx;
          final ny = by + dy;
          if ((dx == 0 && dy == 0) ||
              nx < 0 ||
              ny < 0 ||
              nx >= across ||
              ny >= down) {
            continue;
          }
          final next = ny * across + nx;
          final step = (blockCost(block) + blockCost(next)) / 2;
          if (step == double.infinity) continue;
          final length = (dx != 0 && dy != 0 ? math.sqrt2 : 1.0) * blockSize;
          final total = at + step * length;
          if (total < spent[next]) {
            spent[next] = total;
            previous[next] = block;
            heap.push(next, total);
          }
        }
      }
    }
    if (spent[last] == double.infinity) return null;
    return [for (var block = last; block != -1; block = previous[block]) block];
  }

  /// The AP per metre of each block's cheapest cell on flat ground; kept
  /// per block size, since it depends only on the map and the mover.
  Float64List _priceBlocks(int blockSize, int across, int down) {
    final perMetre = Float64List(across * down);
    for (var by = 0; by < down; by++) {
      for (var bx = 0; bx < across; bx++) {
        var cheapest = double.infinity;
        for (
          var y = by * blockSize;
          y < math.min(map.depth, (by + 1) * blockSize);
          y++
        ) {
          for (
            var x = bx * blockSize;
            x < math.min(map.width, (bx + 1) * blockSize);
            x++
          ) {
            cheapest = math.min(
              cheapest,
              _half(y * map.width + x, 0, entering: true),
            );
          }
        }
        perMetre[by * across + bx] = cheapest;
      }
    }
    return perMetre;
  }
}

/// A binary min-heap of indices by cost, on typed lists.
final class _Heap {
  var _costs = Float64List(1024);
  var _items = Int32List(1024);
  var _length = 0;

  bool get isNotEmpty => _length > 0;

  double get topCost => _costs[0];

  void push(int item, double cost) {
    if (_length == _items.length) {
      _costs = Float64List(_length * 2)..setRange(0, _length, _costs);
      _items = Int32List(_length * 2)..setRange(0, _length, _items);
    }
    var index = _length++;
    while (index > 0) {
      final parent = (index - 1) >> 1;
      if (_costs[parent] <= cost) break;
      _costs[index] = _costs[parent];
      _items[index] = _items[parent];
      index = parent;
    }
    _costs[index] = cost;
    _items[index] = item;
  }

  int pop() {
    final top = _items[0];
    final lastCost = _costs[--_length];
    final lastItem = _items[_length];
    var index = 0;
    while (true) {
      var child = 2 * index + 1;
      if (child >= _length) break;
      if (child + 1 < _length && _costs[child + 1] < _costs[child]) child++;
      if (_costs[child] >= lastCost) break;
      _costs[index] = _costs[child];
      _items[index] = _items[child];
      index = child;
    }
    _costs[index] = lastCost;
    _items[index] = lastItem;
    return top;
  }
}
