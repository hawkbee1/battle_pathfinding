import 'package:battle_pathfinding/src/navigation_map.dart';

/// A change of the world during a battle: an entry of the delta layer on
/// top of the authored map (MAP-06). There is no change that fills a crater
/// or regrows an object (MAP-09).
sealed class WorldChange {
  const new();
}

/// {@template object_built}
/// An engineer built [object] (a wall) on [cell].
/// {@endtemplate}
final class ObjectBuilt extends WorldChange {
  /// {@macro object_built}
  const new(this.cell, this.object);

  /// Where.
  final CellRef cell;

  /// What, for example `wall`.
  final String object;
}

/// {@template object_destroyed}
/// [object] on [cell] was destroyed: a tree, a building, a wall. It never
/// regrows (MAP-09) and stops blocking (MAP-28).
/// {@endtemplate}
final class ObjectDestroyed extends WorldChange {
  /// {@macro object_destroyed}
  const new(this.cell, this.object);

  /// Where.
  final CellRef cell;

  /// What.
  final String object;
}

/// {@template construction_built}
/// An engineer built [construction] on [cell]: a bridge or a reinforced
/// bridge over water, a road.
/// {@endtemplate}
final class ConstructionBuilt extends WorldChange {
  /// {@macro construction_built}
  const new(this.cell, this.construction);

  /// Where.
  final CellRef cell;

  /// What, for example `bridge`.
  final String construction;
}

/// {@template construction_destroyed}
/// [construction] on [cell] was destroyed (MAP-37).
/// {@endtemplate}
final class ConstructionDestroyed extends WorldChange {
  /// {@macro construction_destroyed}
  const new(this.cell, this.construction);

  /// Where.
  final CellRef cell;

  /// What.
  final String construction;
}

/// {@template link_built}
/// An engineer built [link]: a ladder or a bridge to an island.
/// {@endtemplate}
final class LinkBuilt extends WorldChange {
  /// {@macro link_built}
  const new(this.link);

  /// The new link.
  final SurfaceLink link;
}

/// {@template link_destroyed}
/// The link of [kind] between [from] and [to] was destroyed: units on the
/// far side may be stranded (MAP-37).
/// {@endtemplate}
final class LinkDestroyed extends WorldChange {
  /// {@macro link_destroyed}
  const new({required this.kind, required this.from, required this.to});

  /// Its kind.
  final LinkKind kind;

  /// One end.
  final CellRef from;

  /// The other end.
  final CellRef to;
}

/// {@template crater_dug}
/// A shell dug [crater] into the ground (MAP-07).
/// {@endtemplate}
final class CraterDug extends WorldChange {
  /// {@macro crater_dug}
  const new(this.crater);

  /// The crater.
  final Crater crater;
}

/// [map] with [change] applied, and the cells the change touches: a path
/// step that starts or ends on one of them may cost something else now.
(NavigationMap, Set<CellRef>) applyChange(
  NavigationMap map,
  WorldChange change,
) {
  NavigationMap rebuilt({
    Map<CellRef, Set<String>>? objects,
    Map<CellRef, Set<String>>? constructions,
    List<SurfaceLink>? links,
    List<Crater>? craters,
  }) => NavigationMap(
    cellSizeM: map.cellSizeM,
    width: map.width,
    depth: map.depth,
    ground: map.ground,
    waterTerrains: map.waterTerrains,
    islands: map.islands,
    objects: objects ?? map.objects,
    constructions: constructions ?? map.constructions,
    links: links ?? map.links,
    craters: craters ?? map.craters,
  );
  switch (change) {
    case ObjectBuilt(:final cell, :final object):
      return (rebuilt(objects: _with(map.objects, cell, object)), {cell});
    case ObjectDestroyed(:final cell, :final object):
      return (rebuilt(objects: _without(map.objects, cell, object)), {cell});
    case ConstructionBuilt(:final cell, :final construction):
      return (
        rebuilt(constructions: _with(map.constructions, cell, construction)),
        {cell},
      );
    case ConstructionDestroyed(:final cell, :final construction):
      return (
        rebuilt(constructions: _without(map.constructions, cell, construction)),
        {cell},
      );
    case LinkBuilt(:final link):
      return (
        rebuilt(links: List.unmodifiable([...map.links, link])),
        {link.from, link.to},
      );
    case LinkDestroyed(:final kind, :final from, :final to):
      bool same(SurfaceLink link) =>
          link.kind == kind &&
          ((link.from == from && link.to == to) ||
              (link.from == to && link.to == from));
      return (
        rebuilt(
          links: List.unmodifiable([
            for (final link in map.links)
              if (!same(link)) link,
          ]),
        ),
        {from, to},
      );
    case CraterDug(:final crater):
      return (
        rebuilt(craters: List.unmodifiable([...map.craters, crater])),
        {
          for (final (x, y) in crater.cells(
            map.cellSizeM,
            map.width,
            map.depth,
          ))
            CellRef(x, y),
        },
      );
  }
}

Map<CellRef, Set<String>> _with(
  Map<CellRef, Set<String>> byCell,
  CellRef cell,
  String name,
) => Map.unmodifiable({
  ...byCell,
  cell: Set<String>.unmodifiable({...?byCell[cell], name}),
});

Map<CellRef, Set<String>> _without(
  Map<CellRef, Set<String>> byCell,
  CellRef cell,
  String name,
) {
  final left = {...?byCell[cell]}..remove(name);
  return Map.unmodifiable({
    for (final MapEntry(:key, :value) in byCell.entries)
      if (key != cell) key: value,
    if (left.isNotEmpty) cell: Set<String>.unmodifiable(left),
  });
}
