import 'dart:math' as math;

import 'package:meta/meta.dart';

/// The name of the ground surface; floating islands have their own names.
const groundSurface = 'ground';

/// {@template cell_ref}
/// A cell of a surface: the ground or a floating island, column [x] and
/// row [y] of the map grid.
/// {@endtemplate}
@immutable
final class CellRef {
  /// {@macro cell_ref}
  const new(this.x, this.y, {this.surface = groundSurface});

  /// The surface: [groundSurface] or a floating island's name.
  final String surface;

  /// The column, from 0 (west).
  final int x;

  /// The row, from 0 (north).
  final int y;

  @override
  bool operator ==(Object other) =>
      other is CellRef &&
      other.surface == surface &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(surface, x, y);

  @override
  String toString() =>
      surface == groundSurface ? '($x, $y)' : '$surface($x, $y)';
}

/// {@template nav_cell}
/// One cell: its ground height in metres and its terrain type, a key of
/// `terrain.yaml` given by the map (the package reads no data).
/// {@endtemplate}
final class NavCell {
  /// {@macro nav_cell}
  const new({required this.height, required this.terrain});

  /// Height of its surface, in metres above the map's base.
  final double height;

  /// Its terrain type, for example `grass` or `river`.
  final String terrain;
}

/// What links two cells that are not plain neighbours (MAP-23, MAP-36).
enum LinkKind {
  /// A bridge, over water or from the ground to a floating island.
  bridge,

  /// A reinforced bridge, which relics and HQs can cross (decision 99).
  reinforcedBridge,

  /// A ladder, from the ground to a floating island; no height limit
  /// (MAP-37).
  ladder,
}

/// {@template surface_link}
/// A bridge or a ladder between two cells, used both ways.
/// {@endtemplate}
final class SurfaceLink {
  /// {@macro surface_link}
  const new({required this.kind, required this.from, required this.to});

  /// Bridge, reinforced bridge or ladder.
  final LinkKind kind;

  /// One end.
  final CellRef from;

  /// The other end.
  final CellRef to;
}

/// {@template navigation_map}
/// The navigation model of a battle map (M3 Issue 2, MAP-02): a grid of
/// cells of [cellSizeM] metres, each with a ground height and a terrain
/// type; floating islands as separate surfaces above it, linked to the
/// rest only by bridges and ladders (MAP-36); objects on cells (trees,
/// buildings, walls); constructions on cells (bridges over water, roads);
/// and links between cells (bridges, reinforced bridges, ladders).
///
/// Built from the map format of stack decision 5 by M5's loader; tests
/// build it from `NavigationFixture`.
/// {@endtemplate}
final class NavigationMap {
  /// {@macro navigation_map}
  ///
  /// Throws an [ArgumentError] when [ground] does not hold [width] ×
  /// [depth] cells.
  new({
    required this.cellSizeM,
    required this.width,
    required this.depth,
    required this.ground,
    required this.waterTerrains,
    this.islands = const {},
    this.objects = const {},
    this.constructions = const {},
    this.links = const [],
  }) {
    if (ground.length != width * depth) {
      throw ArgumentError.value(
        ground.length,
        'ground',
        'must hold width × depth = ${width * depth} cells',
      );
    }
  }

  /// The side of a cell, in metres (10 m in stack decision 5).
  final double cellSizeM;

  /// Columns, west to east.
  final int width;

  /// Rows, north to south.
  final int depth;

  /// The ground cells, row by row.
  final List<NavCell> ground;

  /// The terrain types that are water: rivers and lakes (MAP-22).
  final Set<String> waterTerrains;

  /// The floating islands' cells, by island name, then by column and row.
  final Map<String, Map<(int, int), NavCell>> islands;

  /// Objects on cells (trees, buildings, walls), by cell.
  final Map<CellRef, Set<String>> objects;

  /// Constructions on cells (a bridge over water, a road), by cell.
  final Map<CellRef, Set<String>> constructions;

  /// Bridges and ladders between cells.
  final List<SurfaceLink> links;

  /// The cell [ref]; null when the map has no such cell.
  NavCell? cellAt(CellRef ref) {
    if (ref.surface != groundSurface) {
      return islands[ref.surface]?[(ref.x, ref.y)];
    }
    if (ref.x < 0 || ref.y < 0 || ref.x >= width || ref.y >= depth) {
      return null;
    }
    return ground[ref.y * width + ref.x];
  }

  /// Whether [ref] is a water cell: a river or a lake (MAP-22).
  bool isWater(CellRef ref) {
    final cell = cellAt(ref);
    return cell != null && waterTerrains.contains(cell.terrain);
  }

  /// The objects on [ref].
  Set<String> objectsAt(CellRef ref) => objects[ref] ?? const {};

  /// The constructions on [ref].
  Set<String> constructionsAt(CellRef ref) => constructions[ref] ?? const {};

  /// The horizontal distance between the centres of two neighbour cells:
  /// one cell side, or its diagonal.
  double stepLengthM(CellRef from, CellRef to) =>
      from.x != to.x && from.y != to.y ? cellSizeM * math.sqrt2 : cellSizeM;

  /// The signed slope from [from] to its neighbour [to], in degrees:
  /// positive uphill, negative downhill (MAP-16, decision 133).
  double slopeDegrees(CellRef from, CellRef to) {
    final rise = cellAt(to)!.height - cellAt(from)!.height;
    return math.atan2(rise, stepLengthM(from, to)) * 180 / math.pi;
  }

  /// The neighbours of [ref] on its own surface, diagonals included.
  Iterable<CellRef> neighbours(CellRef ref) sync* {
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final next = CellRef(ref.x + dx, ref.y + dy, surface: ref.surface);
        if (cellAt(next) != null) {
          yield next;
        }
      }
    }
  }

  /// The links that start or end at [ref], each as seen from [ref].
  Iterable<SurfaceLink> linksFrom(CellRef ref) sync* {
    for (final link in links) {
      if (link.from == ref) yield link;
      if (link.to == ref) {
        yield SurfaceLink(kind: link.kind, from: ref, to: link.from);
      }
    }
  }
}
