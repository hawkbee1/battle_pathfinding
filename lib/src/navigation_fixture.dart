import 'package:battle_pathfinding/src/navigation_map.dart';

/// Builds test maps from a small line-based text format (M3 Issue 2). It is
/// a test tool, not the game's map format (stack decision 5).
///
/// ```text
/// # A comment.
/// cell 10                      # cell side in metres
/// water river lake             # the water terrain types
/// legend g grass               # a symbol, its terrain, an optional object
/// legend f forest_floor tree
/// legend ~ river
/// terrain                      # one symbol per cell, row by row
///   g f ~ g
///   g g ~ g
/// heights                      # one height per cell, in metres
///   0 1 0 2
///   0 1 0 3
/// island sky 40 floating_island_ground 3,0 3,1
/// build bridge 2,0             # a construction on cells
/// link ladder 0,1 sky:3,1      # bridge, reinforced_bridge or ladder
/// ```
///
/// A cell is `x,y` on the ground or `island:x,y`.
abstract final class NavigationFixture {
  /// Parses [text]. Throws a [FormatException] naming the line of the first
  /// problem.
  static NavigationMap parse(String text) => _Parser(text).parse();
}

final class _Parser {
  new(String text) : lines = text.split('\n');

  final List<String> lines;
  var _index = 0;

  double? _cellSize;
  final _water = <String>{};
  final _legend = <String, (String, String?)>{};
  List<List<String>>? _terrain;
  List<List<double>>? _heights;
  final _islands = <String, Map<(int, int), NavCell>>{};
  final _objects = <CellRef, Set<String>>{};
  final _constructions = <CellRef, Set<String>>{};
  final _links = <SurfaceLink>[];

  Never _fail(String problem) =>
      throw FormatException('line ${_index + 1}: $problem');

  NavigationMap parse() {
    for (; _index < lines.length; _index++) {
      final words = _words(lines[_index]);
      if (words.isEmpty) continue;
      switch (words.first) {
        case 'cell':
          _cellSize = _number(words, 1);
        case 'water':
          _water.addAll(words.skip(1));
        case 'legend':
          if (words.length < 3 || words.length > 4) {
            _fail('legend <symbol> <terrain> [object]');
          }
          _legend[words[1]] = (words[2], words.length == 4 ? words[3] : null);
        case 'terrain':
          _terrain = _block();
        case 'heights':
          _heights = [
            for (final row in _block()) [for (final word in row) _parse(word)],
          ];
        case 'island':
          _island(words);
        case 'build':
          if (words.length < 3) _fail('build <construction> <cell>...');
          for (final cell in words.skip(2)) {
            _constructions.putIfAbsent(_cell(cell), () => {}).add(words[1]);
          }
        case 'link':
          if (words.length != 4) _fail('link <kind> <cell> <cell>');
          _links.add(
            SurfaceLink(
              kind: _linkKind(words[1]),
              from: _cell(words[2]),
              to: _cell(words[3]),
            ),
          );
        default:
          _fail('unknown keyword ${words.first}');
      }
    }
    return _build();
  }

  /// The indented rows after the current line.
  List<List<String>> _block() {
    final rows = <List<String>>[];
    while (_index + 1 < lines.length && lines[_index + 1].startsWith(' ')) {
      _index++;
      final words = _words(lines[_index]);
      if (words.isNotEmpty) rows.add(words);
    }
    return rows;
  }

  void _island(List<String> words) {
    if (words.length < 5) _fail('island <name> <height> <terrain> <cell>...');
    final name = words[1];
    final cell = NavCell(height: _number(words, 2), terrain: words[3]);
    final cells = _islands.putIfAbsent(name, () => {});
    for (final word in words.skip(4)) {
      final ref = _cell(word);
      if (ref.surface != groundSurface) _fail('island cells are x,y');
      cells[(ref.x, ref.y)] = cell;
    }
  }

  LinkKind _linkKind(String word) => switch (word) {
    'bridge' => LinkKind.bridge,
    'reinforced_bridge' => LinkKind.reinforcedBridge,
    'ladder' => LinkKind.ladder,
    _ => _fail('unknown link $word'),
  };

  CellRef _cell(String word) {
    final parts = word.split(':');
    final position = parts.last.split(',');
    if (parts.length > 2 || position.length != 2) _fail('bad cell $word');
    final x = int.tryParse(position[0]);
    final y = int.tryParse(position[1]);
    if (x == null || y == null) _fail('bad cell $word');
    return CellRef(x, y, surface: parts.length == 2 ? parts[0] : groundSurface);
  }

  double _number(List<String> words, int index) {
    if (words.length <= index) _fail('a number is missing');
    return _parse(words[index]);
  }

  double _parse(String word) =>
      double.tryParse(word) ?? _fail('$word is not a number');

  NavigationMap _build() {
    final cellSize = _cellSize ?? _fail('no cell size');
    final terrain = _terrain ?? _fail('no terrain block');
    final heights = _heights ?? _fail('no heights block');
    final width = terrain.first.length;
    final depth = terrain.length;
    if (terrain.any((row) => row.length != width) ||
        heights.length != depth ||
        heights.any((row) => row.length != width)) {
      _fail('terrain and heights must be rectangles of the same size');
    }
    final ground = <NavCell>[];
    for (var y = 0; y < depth; y++) {
      for (var x = 0; x < width; x++) {
        final symbol = terrain[y][x];
        final (type, object) =
            _legend[symbol] ?? _fail('no legend for $symbol');
        ground.add(NavCell(height: heights[y][x], terrain: type));
        if (object != null) {
          _objects.putIfAbsent(CellRef(x, y), () => {}).add(object);
        }
      }
    }
    return NavigationMap(
      cellSizeM: cellSize,
      width: width,
      depth: depth,
      ground: List.unmodifiable(ground),
      waterTerrains: Set.unmodifiable(_water),
      islands: Map.unmodifiable({
        for (final MapEntry(:key, :value) in _islands.entries)
          key: Map<(int, int), NavCell>.unmodifiable(value),
      }),
      objects: Map.unmodifiable({
        for (final MapEntry(:key, :value) in _objects.entries)
          key: Set<String>.unmodifiable(value),
      }),
      constructions: Map.unmodifiable({
        for (final MapEntry(:key, :value) in _constructions.entries)
          key: Set<String>.unmodifiable(value),
      }),
      links: List.unmodifiable(_links),
    );
  }
}

List<String> _words(String line) {
  final comment = line.indexOf('#');
  final content = comment < 0 ? line : line.substring(0, comment);
  return content
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
}
