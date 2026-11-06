import 'dart:math' as math;
import 'dart:typed_data';

import 'package:battle_pathfinding/src/navigation_map.dart';
import 'package:battle_pathfinding/src/path_search.dart';

/// {@template ground_grid}
/// The ground of one map as typed arrays: heights, blocking objects and
/// the effective terrain of each movement mode, built once and shared by
/// every [GroundSearch] on it (Flyweight, stack decision 7), with the
/// working arrays of one search at a time. Each mover's search keeps only
/// its memoized costs and block prices.
///
/// A host thread runs one search at a time, so the searches of a grid
/// share its working arrays.
/// {@endtemplate}
final class GroundGrid {
  /// {@macro ground_grid}
  new({required NavigationMap map, this.rules = const PathRules()})
    : _map = map,
      _cells = map.width * map.depth {
    _heights = Float64List(_cells);
    _blocked = Uint8List(_cells);
    for (var index = 0; index < _cells; index++) {
      _loadCell(index);
    }
  }

  /// A grid of its own with [grid]'s arrays copied and no search on it:
  /// what a battle takes when its world first changes (copy on write).
  new copy(GroundGrid grid)
    : _map = grid._map,
      rules = grid.rules,
      _cells = grid._cells {
    _heights = Float64List.fromList(grid._heights);
    _blocked = Uint8List.fromList(grid._blocked);
    for (final MapEntry(:key, :value) in grid._terrains.entries) {
      _terrains[key] = Uint16List.fromList(value);
    }
    _terrainNames.addAll(grid._terrainNames);
    _terrainIndex.addAll(grid._terrainIndex);
  }

  NavigationMap _map;

  /// The map, as of the last [apply].
  NavigationMap get map => _map;

  /// The rules for blocking objects and effective terrains.
  final PathRules rules;

  final int _cells;
  late final Float64List _heights;
  late final Uint8List _blocked;
  final _terrains = <String, Uint16List>{};
  final _terrainNames = <String>[];
  final _terrainIndex = <String, int>{};
  final _searches = <GroundSearch>[];

  Float64List? _spent;
  Int32List? _previous;
  Int32List? _stamps;
  var _stamp = 0;

  /// The modes whose effective terrains are built: one array each, shared
  /// by every search whose mover has that mode.
  Iterable<String> get modes => _terrains.keys;

  /// The searches on this grid.
  int get searches => _searches.length;

  /// Takes [changed], [map] after a world change, and reloads only the
  /// ground cells it [touched] and, in every search on this grid, the
  /// block prices around them (M3 Issue 5).
  void apply(NavigationMap changed, Iterable<CellRef> touched) {
    _map = changed;
    final cells = [
      for (final ref in touched)
        if (ref.surface == groundSurface && changed.cellAt(ref) != null)
          ref.y * changed.width + ref.x,
    ]..forEach(_loadCell);
    for (final search in _searches) {
      search._reprice(cells);
    }
  }

  Uint16List _terrainsOf(String mode) => _terrains.putIfAbsent(mode, () {
    final terrains = Uint16List(_cells);
    for (var index = 0; index < _cells; index++) {
      terrains[index] = _terrainAt(index, mode);
    }
    return terrains;
  });

  int _terrainAt(int index, String mode) {
    final ref = CellRef(index % _map.width, index ~/ _map.width);
    final name = rules.terrainFor(_map, ref, _map.cellAt(ref)!, mode);
    return _terrainIndex.putIfAbsent(name, () {
      _terrainNames.add(name);
      return _terrainNames.length - 1;
    });
  }

  void _loadCell(int index) {
    final ref = CellRef(index % _map.width, index ~/ _map.width);
    _heights[index] = _map.cellAt(ref)!.height;
    _blocked[index] = _map.objectsAt(ref).any(rules.blockingObjects.contains)
        ? 1
        : 0;
    for (final MapEntry(key: mode, value: terrains) in _terrains.entries) {
      terrains[index] = _terrainAt(index, mode);
    }
  }
}

/// {@template ground_search}
/// Long paths across the ground of big maps (M3 Issue 6, MAP-04): up to
/// 1,000 × 5,000 cells of 10 m.
///
/// It prices steps exactly as [Pathfinder] does (half a step on each
/// cell's terrain, the cheapest mode per half, no cutting corners: MAP-41,
/// MAP-47), on the typed arrays of a [GroundGrid] and with memoized costs.
/// [exact] searches the whole ground; [fast] first finds a path over
/// blocks of cells, then searches only a corridor around it. Both return
/// paths through [Pathfinder.check], so their cost and samples are the
/// regular ones. Islands and links are not used: long paths stay on the
/// ground.
/// {@endtemplate}
final class GroundSearch {
  /// {@macro ground_search}
  ///
  /// Prepares the search for [mover] on [map]'s ground, on a grid of its
  /// own. Movers of one map share a grid with [GroundSearch.on].
  factory({
    required NavigationMap map,
    required MovementCostFunction cost,
    required PathMover mover,
    PathRules rules = const PathRules(),
  }) => GroundSearch.on(
    GroundGrid(map: map, rules: rules),
    cost: cost,
    mover: mover,
  );

  /// {@macro ground_search}
  ///
  /// Prepares the search for [mover] on [grid], which it shares with the
  /// other movers of the map.
  new on(this.grid, {required this.cost, required this.mover}) {
    _terrains = [for (final mode in mover.modes) grid._terrainsOf(mode)];
    _memo = [for (final _ in mover.modes) <Map<double, double>>[]];
    _flat = [for (final _ in mover.modes) <int>[]];
    _onGround = [
      for (final mode in mover.modes) rules.groundModes.contains(mode),
    ];
    _flying = [for (final mode in mover.modes) mode == rules.flyingMode];
    grid._searches.add(this);
  }

  /// The shared ground.
  final GroundGrid grid;

  /// The map, as of the last [apply].
  NavigationMap get map => grid.map;

  /// The movement cost the rules core injects.
  final MovementCostFunction cost;

  /// Who moves.
  final PathMover mover;

  /// The rules for blocking objects and effective terrains.
  PathRules get rules => grid.rules;

  late final List<Uint16List> _terrains;
  late final List<List<Map<double, double>>> _memo;

  /// Per mode and terrain: 0 not known yet, 1 passable on flat ground, 2
  /// not.
  late final List<List<int>> _flat;
  late final List<bool> _onGround;
  late final List<bool> _flying;

  final _blockCosts = <int, Float64List>{};

  /// The cells the last search settled: a measure of its work.
  int lastSettled = 0;

  /// The ground's connected parts for this mover, by cell; null until an
  /// unreachable goal needs them, and after a world change.
  Int32List? _labels;

  /// Takes [changed], [map] after a world change, for every search on the
  /// grid (see [GroundGrid.apply]).
  void apply(NavigationMap changed, Iterable<CellRef> touched) =>
      grid.apply(changed, touched);

  void _reprice(List<int> cells) {
    _labels = null;
    for (final MapEntry(key: blockSize, value: prices) in _blockCosts.entries) {
      final across = (map.width / blockSize).ceil();
      final blocks = {
        for (final cell in cells)
          ((cell ~/ map.width) ~/ blockSize) * across +
              (cell % map.width) ~/ blockSize,
      };
      for (final block in blocks) {
        prices[block] = _priceBlock(block % across, block ~/ across, blockSize);
      }
    }
  }

  /// The modes of [mover] that can stand on [cell] (bit m for
  /// `mover.modes[m]`): a diagonal needs both cells it passes between.
  ///
  /// The same test as entering at slope 0 ([_half]), on flat tables of the
  /// modes and terrains instead of the cost memo, since the search asks it
  /// for every diagonal step.
  int _standing(int cell) {
    var stand = 0;
    for (var m = 0; m < mover.modes.length; m++) {
      if (_onGround[m] && grid._blocked[cell] == 1) continue;
      if (_flying[m] && grid._heights[cell] > rules.altitudeLimitM) continue;
      final terrain = _terrains[m][cell];
      final flat = _flat[m];
      while (flat.length <= terrain) {
        flat.add(0);
      }
      if (flat[terrain] == 0) {
        final perMetre = cost(
          mover.apPerM,
          mover.modes[m],
          grid._terrainNames[terrain],
          0,
        );
        flat[terrain] = perMetre == null || perMetre == double.infinity ? 2 : 1;
      }
      if (flat[terrain] == 1) stand |= 1 << m;
    }
    return stand;
  }

  /// The cheapest path from [from] to [to] over the whole ground; null when
  /// there is none.
  FoundPath? exact(CellRef from, CellRef to) =>
      _search(_index(from), _index(to), null);

  /// A path from [from] to [to] found within a corridor of [corridor]
  /// blocks of [blockSize] × [blockSize] cells around the cheapest path
  /// over blocks. The corridor doubles until a path is found, the whole
  /// ground last. Null when there is none: when the blocks give no path,
  /// no cells do either.
  ///
  /// Throws an [ArgumentError] when [blockSize] or [corridor] is below 1.
  FoundPath? fast(
    CellRef from,
    CellRef to, {
    int blockSize = 16,
    int corridor = 1,
  }) {
    if (blockSize < 1) throw ArgumentError.value(blockSize, 'blockSize');
    if (corridor < 1) throw ArgumentError.value(corridor, 'corridor');
    final start = _index(from);
    final goal = _index(to);
    final blocks = _blockPath(start, goal, blockSize);
    if (blocks == null) return null;
    final across = (map.width / blockSize).ceil();
    final down = (map.depth / blockSize).ceil();
    for (var width = corridor; width < math.max(across, down); width *= 2) {
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
      // An unreachable goal answers at once instead of widening the
      // corridor to the whole ground (deferred from M3.6).
      final labels = _labels ??= _label();
      if (labels[start] != labels[goal]) return null;
    }
    return _search(start, goal, null);
  }

  /// The parts of the ground this mover connects: two cells it can stand
  /// on, joined by a step it passes one way or the other, share a label.
  /// Cells with different labels have no path between them; a cell it
  /// cannot stand on is a part of its own.
  Int32List _label() {
    final width = map.width;
    final labels = Int32List(grid._cells)..fillRange(0, grid._cells, -1);
    final stack = <int>[];
    var next = 0;
    for (var seed = 0; seed < grid._cells; seed++) {
      if (labels[seed] != -1) continue;
      labels[seed] = next;
      if (_standing(seed) != 0) stack.add(seed);
      while (stack.isNotEmpty) {
        final cell = stack.removeLast();
        final x = cell % width;
        final y = cell ~/ width;
        for (var dy = -1; dy <= 1; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= map.depth) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            if ((dx == 0 && dy == 0) || nx < 0 || nx >= width) continue;
            final other = ny * width + nx;
            if (labels[other] != -1 || _standing(other) == 0) continue;
            if (_steps(cell, other, dx != 0 && dy != 0) ||
                _steps(other, cell, dx != 0 && dy != 0)) {
              labels[other] = next;
              stack.add(other);
            }
          }
        }
      }
      next++;
    }
    return labels;
  }

  /// Whether this mover passes the step from [cell] to its neighbour
  /// [next], as [_search] prices it.
  bool _steps(int cell, int next, bool diagonal) {
    final width = map.width;
    final modes = diagonal
        ? _standing((next ~/ width) * width + cell % width) &
              _standing((cell ~/ width) * width + next % width)
        : 0xFFFFFFFF;
    if (modes == 0) return false;
    final length = diagonal ? map.cellSizeM * math.sqrt2 : map.cellSizeM;
    final slope =
        math.atan2(grid._heights[next] - grid._heights[cell], length) *
        180 /
        math.pi;
    return _half(cell, slope, entering: false, modes: modes) !=
            double.infinity &&
        _half(next, slope, entering: true, modes: modes) != double.infinity;
  }

  int _index(CellRef ref) {
    if (ref.surface != groundSurface || map.cellAt(ref) == null) {
      throw ArgumentError.value(ref, 'cell', 'not on the ground of the map');
    }
    return ref.y * map.width + ref.x;
  }

  /// AP per metre of the cheapest of [modes] (bit m for `mover.modes[m]`)
  /// over half a step on [cell] at [slope]; infinity when none passes.
  double _half(
    int cell,
    double slope, {
    required bool entering,
    int modes = 0xFFFFFFFF,
  }) {
    var best = double.infinity;
    for (var m = 0; m < mover.modes.length; m++) {
      if (modes & (1 << m) == 0) continue;
      final mode = mover.modes[m];
      if (entering &&
          grid._blocked[cell] == 1 &&
          rules.groundModes.contains(mode)) {
        continue;
      }
      if (mode == rules.flyingMode &&
          grid._heights[cell] > rules.altitudeLimitM) {
        continue;
      }
      final terrain = _terrains[m][cell];
      final memo = _memo[m];
      while (memo.length <= terrain) {
        memo.add(<double, double>{});
      }
      final perMetre = memo[terrain].putIfAbsent(
        slope,
        () =>
            cost(mover.apPerM, mode, grid._terrainNames[terrain], slope) ??
            double.infinity,
      );
      if (perMetre < best) best = perMetre;
    }
    return best;
  }

  /// Dijkstra over the ground cells [allowed] keeps (all when null).
  FoundPath? _search(int start, int goal, bool Function(int cell)? allowed) {
    final spent = grid._spent ??= Float64List(grid._cells);
    final previous = grid._previous ??= Int32List(grid._cells);
    final stamps = grid._stamps ??= Int32List(grid._cells);
    final stamp = ++grid._stamp;
    final heights = grid._heights;
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
          final isDiagonal = dx != 0 && dy != 0;
          final modes = isDiagonal
              ? _standing(ny * width + x) & _standing(y * width + nx)
              : 0xFFFFFFFF;
          if (modes == 0) continue;
          final length = isDiagonal ? diagonal : side;
          final slope =
              math.atan2(heights[next] - heights[cell], length) * 180 / math.pi;
          final first = _half(cell, slope, entering: false, modes: modes);
          if (first == double.infinity) continue;
          final second = _half(next, slope, entering: true, modes: modes);
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
  Float64List _priceBlocks(int blockSize, int across, int down) =>
      Float64List.fromList([
        for (var by = 0; by < down; by++)
          for (var bx = 0; bx < across; bx++) _priceBlock(bx, by, blockSize),
      ]);

  double _priceBlock(int bx, int by, int blockSize) {
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
    return cheapest;
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
