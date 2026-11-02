import 'package:battle_pathfinding/battle_pathfinding.dart';
import 'package:test/test.dart';

import '../helpers/fixture_cost.dart';

const _legend = '''
cell 10
water river lake
legend g grass
legend ~ river
legend o lake
legend w grass wall
''';

/// A flat map of the given rows of symbols, with [extra] fixture lines.
NavigationMap _map(List<String> rows, {String extra = ''}) {
  final heights = [
    for (final row in rows) row.split(' ').map((_) => '0').join(' '),
  ];
  return NavigationFixture.parse(
    '${_legend}terrain\n${rows.map((row) => '  $row').join('\n')}\n'
    'heights\n${heights.map((row) => '  $row').join('\n')}\n$extra',
  );
}

const _foot = PathMover(apPerM: 1, modes: ['foot']);
const _boat = PathMover(apPerM: 1, modes: ['sail']);
const _relic = PathMover(apPerM: 10, modes: ['push']);
const _flyer = PathMover(apPerM: 1, modes: ['flying']);

FoundPath? _find(
  NavigationMap map,
  PathMover mover,
  CellRef from,
  CellRef to,
) => Pathfinder(
  map: map,
  cost: fixtureCost,
).find(mover: mover, from: from, to: to);

FoundPath? _ground(
  NavigationMap map,
  PathMover mover,
  CellRef from,
  CellRef to,
) => GroundSearch(map: map, cost: fixtureCost, mover: mover).exact(from, to);

void main() {
  group('diagonal steps', () {
    test('RELIC-28 MAP-47 a relic in a diamond of walls cannot slip between '
        'corners', () {
      final map = _map(['g w g', 'w g w', 'g w g']);

      expect(
        _find(map, _relic, const CellRef(1, 1), const CellRef(0, 0)),
        isNull,
      );
      expect(
        _ground(map, _relic, const CellRef(1, 1), const CellRef(0, 0)),
        isNull,
      );
    });

    test(
      'MAP-22 MAP-47 a foot unit does not cross a river at a diagonal bend',
      () {
        final map = _map(['g ~', '~ g']);

        expect(
          _find(map, _foot, const CellRef(0, 0), const CellRef(1, 1)),
          isNull,
        );
        expect(
          _ground(map, _foot, const CellRef(0, 0), const CellRef(1, 1)),
          isNull,
        );
      },
    );

    test('MAP-19 MAP-47 a boat does not cross a diagonal strip of land', () {
      final map = _map(['o g', 'g o']);

      expect(
        _find(map, _boat, const CellRef(0, 0), const CellRef(1, 1)),
        isNull,
      );
      expect(
        _ground(map, _boat, const CellRef(0, 0), const CellRef(1, 1)),
        isNull,
      );
    });

    test('a live map forgets a diagonal step when a wall rises at its '
        'corner', () {
      final live = LivePathfinder(map: _map(['g g', 'g g']), cost: fixtureCost);
      FoundPath? across() => live.find(
        mover: _foot,
        from: const CellRef(0, 0),
        to: const CellRef(1, 1),
      );

      expect(across()?.cells, hasLength(2));
      live
        ..apply(const ObjectBuilt(CellRef(1, 0), 'wall'))
        ..apply(const ObjectBuilt(CellRef(0, 1), 'wall'));
      expect(across(), isNull);
    });
  });

  group('the path check agrees with the search', () {
    test('a flyer goes up where a ladder also stands', () {
      final map = _map([
        'g g',
      ], extra: 'island sky 20 grass 1,0\nlink ladder 1,0 sky:1,0');
      final finder = Pathfinder(map: map, cost: fixtureCost);
      const path = [CellRef(1, 0), CellRef(1, 0, surface: 'sky')];

      expect(
        finder.find(mover: _flyer, from: path.first, to: path.last)?.cost,
        0,
      );
      expect((finder.check(mover: _flyer, path: path) as PathPasses).cost, 0);
    });

    test('RELIC-26 a relic crosses the reinforced bridge next to a plain '
        'one', () {
      final map = _map(
        ['g g'],
        extra:
            'island sky 0 grass 4,0\n'
            'link bridge 1,0 sky:4,0\n'
            'link reinforced_bridge 1,0 sky:4,0',
      );

      expect(
        Pathfinder(map: map, cost: fixtureCost).check(
          mover: _relic,
          path: const [
            CellRef(1, 0),
            CellRef(4, 0, surface: 'sky'),
          ],
        ),
        isA<PathPasses>(),
      );
    });

    test('takes the cheaper of two ways between the same cells', () {
      final map = _map(
        ['g g'],
        extra:
            'island sky 0 grass 4,0\n'
            'link bridge 1,0 sky:4,0\n'
            'link reinforced_bridge 1,0 sky:4,0',
      );
      final check = Pathfinder(map: map, cost: fixtureCost).check(
        mover: _foot,
        path: const [
          CellRef(1, 0),
          CellRef(4, 0, surface: 'sky'),
        ],
      ) as PathPasses;

      expect(check.cost, closeTo(30 * 0.5, 1e-9));
    });

    test('an empty path fails', () {
      expect(
        (Pathfinder(
          map: _map(['g']),
          cost: fixtureCost,
        ).check(mover: _foot, path: const []) as PathFails).reason,
        StepFailure.emptyPath,
      );
    });
  });

  group('links and falls meet blocking objects', () {
    test('MAP-44 a wall at the top of a ladder stops the climb', () {
      final live = LivePathfinder(
        map: _map([
          'g g',
        ], extra: 'island sky 30 grass 5,5\nlink ladder 1,0 sky:5,5'),
        cost: fixtureCost,
      );
      const top = CellRef(5, 5, surface: 'sky');

      expect(
        live.find(mover: _foot, from: const CellRef(0, 0), to: top),
        isNotNull,
      );
      live.apply(const ObjectBuilt(top, 'wall'));
      expect(
        live.find(mover: _foot, from: const CellRef(0, 0), to: top),
        isNull,
      );
    });

    test('MAP-39 a relic does not fall onto a wall', () {
      final live = LivePathfinder(
        map: _map(['g g g'], extra: 'island sky 20 grass 0,0 1,0'),
        cost: fixtureCost,
      );
      const top = CellRef(0, 0, surface: 'sky');

      expect(
        live.find(mover: _relic, from: top, to: const CellRef(2, 0)),
        isNotNull,
      );
      live.apply(const ObjectBuilt(CellRef(2, 0), 'wall'));
      expect(
        live.find(mover: _relic, from: top, to: const CellRef(2, 0)),
        isNull,
      );
    });
  });

  group('GroundSearch.apply', () {
    test('MAP-06 follows world changes like a search from scratch', () {
      var map = _map([
        for (var y = 0; y < 30; y++) List.filled(20, 'g').join(' '),
      ]);
      final search = GroundSearch(map: map, cost: fixtureCost, mover: _foot);
      const from = CellRef(2, 2);
      const to = CellRef(17, 27);
      search.fast(from, to);
      final changes = <WorldChange>[
        const CraterDug(
          Crater(centreXM: 100, centreYM: 150, radiusM: 40, depthM: 15),
        ),
        for (var x = 0; x < 20; x++) ObjectBuilt(CellRef(x, 10), 'wall'),
        const ObjectDestroyed(CellRef(15, 10), 'wall'),
        const ConstructionBuilt(CellRef(10, 10), 'road'),
      ];
      for (final change in changes) {
        final (next, touched) = applyChange(map, change);
        map = next;
        search.apply(map, touched);
      }
      final reference = Pathfinder(
        map: map,
        cost: fixtureCost,
      ).find(mover: _foot, from: from, to: to)!;

      expect(search.map, same(map));
      expect(search.exact(from, to)?.cost, closeTo(reference.cost, 1e-6));
      expect(search.fast(from, to)!.cells, contains(const CellRef(15, 10)));
    });

    test('fast rejects a block size or a corridor below 1', () {
      final search = GroundSearch(
        map: _map(['g g']),
        cost: fixtureCost,
        mover: _foot,
      );

      expect(
        () =>
            search.fast(const CellRef(0, 0), const CellRef(1, 0), blockSize: 0),
        throwsArgumentError,
      );
      expect(
        () =>
            search.fast(const CellRef(0, 0), const CellRef(1, 0), corridor: 0),
        throwsArgumentError,
      );
    });
  });

  group(NavigationMap, () {
    test('rejects a link with an end off the map', () {
      expect(
        () => _map(['g g'], extra: 'link ladder 1,0 sky:5,5'),
        throwsArgumentError,
      );
    });

    test('keeps unmodifiable copies of its objects, constructions and '
        'links', () {
      final map = _map(['g w'], extra: 'build road 0,0');

      expect(
        () => map.objects[const CellRef(0, 0)] = {},
        throwsUnsupportedError,
      );
      expect(map.constructions.clear, throwsUnsupportedError);
      expect(
        () => map.links.add(
          const SurfaceLink(
            kind: LinkKind.ladder,
            from: CellRef(0, 0),
            to: CellRef(1, 0),
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('a map built with craters samples them', () {
      final map = NavigationMap(
        cellSizeM: 10,
        width: 3,
        depth: 1,
        ground: List.filled(3, const NavCell(height: 0, terrain: 'grass')),
        waterTerrains: const {},
        craters: const [
          Crater(centreXM: 15, centreYM: 5, radiusM: 6, depthM: 2),
          Crater(centreXM: 15, centreYM: 5, radiusM: 6, depthM: 3),
        ],
      );

      expect(map.cellAt(const CellRef(1, 0))?.height, -3);
    });

    test('copyWith keeps the craters; withCrater adds one', () {
      final dug = _map(['g g g']).withCrater(
        const Crater(centreXM: 15, centreYM: 5, radiusM: 6, depthM: 2),
      );
      final copy = dug.copyWith(objects: const {});

      expect(copy.craters, hasLength(1));
      expect(copy.cellAt(const CellRef(1, 0))?.height, -2);
    });
  });
}
