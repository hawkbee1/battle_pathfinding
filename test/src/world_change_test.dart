import 'dart:math' as math;

import 'package:battle_pathfinding/battle_pathfinding.dart';
import 'package:test/test.dart';

import '../helpers/fixture_cost.dart';

const _legend = '''
cell 10
water river lake
legend g grass
legend r road
legend f forest_floor
legend d mud
legend ~ river
legend w grass wall
legend T forest_floor tree
''';

NavigationMap _row(String cells, {String extra = ''}) =>
    NavigationFixture.parse(
      '${_legend}terrain\n  $cells\nheights\n'
      '  ${List.filled(cells.split(' ').length, '0').join(' ')}\n$extra',
    );

const _foot = PathMover(apPerM: 1, modes: ['foot']);
const _wheeled = PathMover(apPerM: 1, modes: ['wheeled']);
const _relic = PathMover(apPerM: 10, modes: ['push']);

LivePathfinder _live(NavigationMap map) =>
    LivePathfinder(map: map, cost: fixtureCost);

double? _across(LivePathfinder live, PathMover mover) => live
    .find(
      mover: mover,
      from: const CellRef(0, 0),
      to: CellRef(live.map.width - 1, 0),
    )
    ?.cost;

void main() {
  group('bridges and ladders', () {
    test('MAP-23 building a bridge opens a path; MAP-37 destroying it strands '
        'the units on the far side', () {
      final live = _live(_row('g ~ g'));

      expect(_across(live, _foot), isNull);
      live.apply(const ConstructionBuilt(CellRef(1, 0), 'bridge'));
      expect(_across(live, _foot), closeTo(5 + 2.5 + 2.5 + 5, 1e-9));
      live.apply(const ConstructionDestroyed(CellRef(1, 0), 'bridge'));
      expect(_across(live, _foot), isNull);
      expect(live.map.constructionsAt(const CellRef(1, 0)), isEmpty);
    });

    test('MAP-37 destroying a ladder strands the units on an island; '
        'building one frees them', () {
      final live = _live(
        _row('g g', extra: 'island sky 30 grass 5,5\nlink ladder 1,0 sky:5,5'),
      );
      const top = CellRef(5, 5, surface: 'sky');

      FoundPath? down() =>
          live.find(mover: _foot, from: top, to: const CellRef(0, 0));

      expect(down(), isNotNull);
      final touched = live.apply(
        const LinkDestroyed(
          kind: LinkKind.ladder,
          from: top,
          to: CellRef(1, 0),
        ),
      );
      expect(touched, {top, const CellRef(1, 0)});
      expect(down(), isNull);
      live.apply(
        const LinkBuilt(
          SurfaceLink(kind: LinkKind.ladder, from: CellRef(0, 0), to: top),
        ),
      );
      expect(down(), isNotNull);
    });
  });

  group('objects', () {
    test('MAP-28 RELIC-28 destroying a wall opens the path; building one '
        'closes it', () {
      final live = _live(_row('g w g'));

      expect(_across(live, _relic), isNull);
      live.apply(const ObjectDestroyed(CellRef(1, 0), 'wall'));
      expect(_across(live, _relic), closeTo(10 * 20, 1e-9));
      live.apply(const ObjectBuilt(CellRef(1, 0), 'wall'));
      expect(_across(live, _relic), isNull);
    });

    test('MAP-09 a destroyed tree is gone and never regrows', () {
      final live = _live(_row('g T g'))
        ..apply(const ObjectDestroyed(CellRef(1, 0), 'tree'));

      expect(live.map.objectsAt(const CellRef(1, 0)), isEmpty);
      expect(live.map.objects, isEmpty);
    });

    test('destroying one of two objects on a cell keeps the other', () {
      final live = _live(_row('g T g'))
        ..apply(const ObjectBuilt(CellRef(1, 0), 'wall'))
        ..apply(const ObjectDestroyed(CellRef(1, 0), 'tree'));

      expect(live.map.objectsAt(const CellRef(1, 0)), {'wall'});
    });
  });

  group('craters', () {
    test('MAP-07 a crater changes the slope, and so the cost, of a path', () {
      final live = _live(_row('g g g'));
      final flat = _across(live, _foot)!;

      // 3 m deep under (1, 0), whose centre is 15 m east, 5 m south.
      live.apply(
        const CraterDug(
          Crater(centreXM: 15, centreYM: 5, radiusM: 6, depthM: 3),
        ),
      );
      final down = math.atan(0.3) * 180 / math.pi;
      expect(
        _across(live, _foot),
        // Down 16.7° hits the floor of 0.5; up costs 1 + 16.7 × 0.05.
        closeTo(10 * 0.5 + 10 * (1 + down * 0.05), 1e-9),
      );
      expect(_across(live, _foot), isNot(flat));
    });

    test('MAP-07 a deep crater makes a step too steep', () {
      final live = _live(_row('g g g'))
        ..apply(
          const CraterDug(
            Crater(centreXM: 15, centreYM: 5, radiusM: 6, depthM: 15),
          ),
        );

      expect(_across(live, _foot), isNull);
    });

    test('MAP-46 a crater is a bowl sampled on the cells it covers; the '
        'deepest crater counts', () {
      const crater = Crater(centreXM: 15, centreYM: 5, radiusM: 10, depthM: 4);

      expect(crater.depthAt(1, 0, 10), 4);
      // The next cell's centre is 10 m away: on the rim.
      expect(crater.depthAt(2, 0, 10), 0);
      expect(crater.cells(10, 3, 1).toList(), [(1, 0)]);
      expect(
        const Crater(
          centreXM: 0,
          centreYM: 0,
          radiusM: 30,
          depthM: 1,
        ).cells(10, 2, 2).toList(),
        [(0, 0), (1, 0), (0, 1), (1, 1)],
      );

      final live = _live(_row('g g g'))
        ..apply(const CraterDug(crater))
        ..apply(
          const CraterDug(
            Crater(centreXM: 15, centreYM: 5, radiusM: 10, depthM: 2),
          ),
        );
      expect(live.map.cellAt(const CellRef(1, 0))?.height, -4);
      expect(live.map.craters, hasLength(2));
    });

    test('MAP-46 a crater digs the ground, never a floating island', () {
      final live = _live(_row('g g', extra: 'island sky 30 grass 1,0'))
        ..apply(
          const CraterDug(
            Crater(centreXM: 15, centreYM: 5, radiusM: 10, depthM: 4),
          ),
        );

      expect(live.map.cellAt(const CellRef(1, 0))?.height, -4);
      expect(live.map.cellAt(const CellRef(1, 0, surface: 'sky'))?.height, 30);
    });

    test('MAP-06 MAP-09 changes sit on top of the authored map: the base '
        'heights never change and no change fills a crater', () {
      final map = _row('g g g');
      final live = _live(map)
        ..apply(
          const CraterDug(
            Crater(centreXM: 15, centreYM: 5, radiusM: 6, depthM: 3),
          ),
        );

      expect(live.map.ground, same(map.ground));
      expect(live.map.ground[1].height, 0);
      expect(live.map.cellAt(const CellRef(1, 0))?.height, -3);
    });
  });

  group('incremental updates', () {
    test('MAP-06 paths after updates equal paths from scratch, for seeded '
        'random changes', () {
      for (var seed = 0; seed < 12; seed++) {
        final random = math.Random(seed);
        const symbols = ['g', 'g', 'g', 'r', 'd', 'f', '~'];
        const size = 9;
        final rows = [
          for (var y = 0; y < size; y++)
            [
              for (var x = 0; x < size; x++)
                symbols[random.nextInt(symbols.length)],
            ].join(' '),
        ];
        final heights = [
          for (var y = 0; y < size; y++)
            [for (var x = 0; x < size; x++) random.nextInt(4)].join(' '),
        ];
        final live = _live(
          NavigationFixture.parse(
            '${_legend}terrain\n${rows.map((r) => '  $r').join('\n')}\n'
            'heights\n${heights.map((h) => '  $h').join('\n')}\n',
          ),
        );
        CellRef cell() => CellRef(random.nextInt(size), random.nextInt(size));

        for (var change = 0; change < 15; change++) {
          final target = cell();
          live.apply(switch (random.nextInt(5)) {
            0 => ObjectBuilt(target, 'wall'),
            1 => ObjectDestroyed(target, 'wall'),
            2 => ConstructionBuilt(target, 'bridge'),
            3 => ConstructionDestroyed(target, 'bridge'),
            _ => CraterDug(
              Crater(
                centreXM: random.nextDouble() * size * 10,
                centreYM: random.nextDouble() * size * 10,
                radiusM: 5 + random.nextDouble() * 15,
                depthM: random.nextDouble() * 8,
              ),
            ),
          });
          final scratch = Pathfinder(map: live.map, cost: fixtureCost);
          for (var pair = 0; pair < 3; pair++) {
            final from = cell();
            final to = cell();
            for (final mover in [_foot, _wheeled, _relic]) {
              final incremental = live.find(mover: mover, from: from, to: to);
              final fresh = scratch.find(mover: mover, from: from, to: to);

              expect(
                incremental?.cost,
                fresh == null ? isNull : closeTo(fresh.cost, 1e-9),
                reason: 'seed $seed change $change $from → $to',
              );
            }
          }
        }
        expect(live.cachedSteps, greaterThan(0));
      }
    });

    test('a change forgets only the steps that touch its cells', () {
      final live = _live(_row('g g g g g g'));
      _across(live, _foot);
      final before = live.cachedSteps;

      live.apply(const ObjectBuilt(CellRef(5, 0), 'wall'));

      expect(live.cachedSteps, lessThan(before));
      expect(live.cachedSteps, greaterThan(0));
    });

    test('a live path check uses the changed map', () {
      final live = _live(_row('g ~ g'));
      const path = [CellRef(0, 0), CellRef(1, 0), CellRef(2, 0)];

      expect(live.check(mover: _foot, path: path), isA<PathFails>());
      live.apply(const ConstructionBuilt(CellRef(1, 0), 'bridge'));
      expect(live.check(mover: _foot, path: path), isA<PathPasses>());
    });
  });
}
