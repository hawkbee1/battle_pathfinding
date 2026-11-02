import 'dart:io';
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
legend m mountain
legend t town_street
legend ~ river
legend o lake
legend w grass wall
legend b town_street building
legend T forest_floor tree
''';

/// A map from the shared legend, a terrain block and a heights block.
NavigationMap _map(String terrain, String heights, [String extra = '']) =>
    NavigationFixture.parse(
      '${_legend}terrain\n$terrain\nheights\n$heights\n$extra',
    );

/// A one-row map of [cells] symbols, flat unless [heights] says otherwise.
NavigationMap _row(String cells, {String? heights, String extra = ''}) {
  final symbols = cells.split(' ');
  return _map(
    '  $cells',
    '  ${heights ?? List.filled(symbols.length, '0').join(' ')}',
    extra,
  );
}

Pathfinder _finder(NavigationMap map, {PathRules rules = const PathRules()}) =>
    Pathfinder(map: map, cost: fixtureCost, rules: rules);

const _foot = PathMover(apPerM: 1, modes: ['foot']);
const _wheeled = PathMover(apPerM: 1, modes: ['wheeled']);
const _tracked = PathMover(apPerM: 1, modes: ['tracked']);
const _boat = PathMover(apPerM: 1, modes: ['sail']);
const _amphibious = PathMover(apPerM: 1, modes: ['wheeled', 'sail']);
const _flyer = PathMover(apPerM: 1, modes: ['flying']);

/// The cost of crossing the middle cell of a 3-cell row: 10 m on the end
/// cells and 10 m on the middle one; null when there is no path.
double? _crossing(String middle, PathMover mover) =>
    _finder(_row('g $middle g'))
        .find(mover: mover, from: const CellRef(0, 0), to: const CellRef(2, 0))
        ?.cost;

double _sumOfSamples(List<PathSample> samples, double apPerM) => samples.fold(
  0,
  (sum, sample) =>
      sum +
      fixtureCost(
            apPerM,
            sample.mode,
            sample.terrainType,
            sample.slopeDegrees,
          )! *
          sample.lengthM,
);

void main() {
  group('flat ground, per class and profile', () {
    // AP per metre of the middle cell for 1 AP per metre; null: no path.
    const table = <String, Map<String, double?>>{
      'g': {'foot': 1, 'wheeled': 1, 'tracked': 1, 'flying': 0.5, 'sail': null},
      'r': {'foot': 0.5, 'wheeled': 0.25, 'tracked': 0.5, 'flying': 0.5},
      'f': {'foot': 2, 'wheeled': null, 'tracked': 3, 'flying': 0.5},
      'd': {'foot': 2, 'wheeled': 4, 'tracked': 2, 'flying': 0.5},
      'm': {'foot': 3, 'wheeled': null, 'tracked': null, 'flying': 0.5},
      '~': {'foot': null, 'wheeled': null, 'tracked': null, 'flying': 0.5},
    };
    const movers = {
      'foot': _foot,
      'wheeled': _wheeled,
      'tracked': _tracked,
      'flying': _flyer,
    };
    for (final MapEntry(key: symbol, value: row) in table.entries) {
      for (final MapEntry(key: mode, value: mover) in movers.entries) {
        if (!row.containsKey(mode)) continue;
        final perMetre = row[mode];
        final rule = switch (mode) {
          'foot' => 'MAP-11',
          'wheeled' => 'MAP-12',
          'tracked' => 'MAP-13',
          _ => 'MAP-17',
        };
        test('$rule $mode across $symbol '
            '${perMetre == null ? 'has no path' : 'pays $perMetre AP/m'}', () {
          final ground = mode == 'flying' ? 0.5 : 1;

          expect(
            _crossing(symbol, mover),
            perMetre == null
                ? isNull
                : closeTo(10 * ground + 10 * perMetre, 1e-9),
          );
        });
      }
    }

    test(
      'MAP-41 a step between two terrains pays each for half its length',
      () {
        final path = _finder(_row('g d')).find(
          mover: _foot,
          from: const CellRef(0, 0),
          to: const CellRef(1, 0),
        )!;

        expect(
          [for (final s in path.samples) (s.terrainType, s.lengthM)],
          [('grass', 5.0), ('mud', 5.0)],
        );
        expect(path.cost, closeTo(5 * 1 + 5 * 2, 1e-9));
      },
    );

    test('COMBAT-03 the cost scales with the mover AP per metre', () {
      final path = _finder(_row('g d g')).find(
        mover: const PathMover(apPerM: 0.2, modes: ['tracked']),
        from: const CellRef(0, 0),
        to: const CellRef(2, 0),
      )!;

      expect(path.cost, closeTo(0.2 * (10 + 20), 1e-9));
    });

    test('MAP-15 the cheapest path goes around expensive ground', () {
      final map = _map('  g d g\n  g g g', '  0 0 0\n  0 0 0');
      final path = _finder(map).find(
        mover: _wheeled,
        from: const CellRef(0, 0),
        to: const CellRef(2, 0),
      )!;

      expect(path.cells, isNot(contains(const CellRef(1, 0))));
    });
  });

  group('slopes', () {
    double? across(String heights, PathMover mover) =>
        _finder(_row('g g g', heights: heights))
            .find(
              mover: mover,
              from: const CellRef(0, 0),
              to: const CellRef(2, 0),
            )
            ?.cost;

    test('MAP-16 a slope within the limit passes, up and down', () {
      // 9 m over 10 m: 42°, under the foot limit of 45°.
      expect(across('0 9 0', _foot), isNotNull);
      // 4 m: 21.8°, under the wheeled limit of 25°.
      expect(across('0 4 0', _wheeled), isNotNull);
    });

    test('MAP-16 a slope over the limit is impassable, up or down', () {
      expect(across('0 0 11', _foot), isNull);
      expect(across('11 0 0', _foot), isNull);
      expect(across('0 0 5', _wheeled), isNull);
      expect(across('5 0 0', _wheeled), isNull);
      expect(across('0 0 7.5', _tracked), isNull);
    });

    test('MAP-16 uphill costs more, downhill less, down to the floor', () {
      double cost(String heights) => across(heights, _foot)!;
      final up = math.atan2(2, 10) * 180 / math.pi;

      expect(cost('0 0 2'), closeTo(10 + 10 * (1 + up * 0.05), 1e-9));
      final down = math.atan2(1, 10) * 180 / math.pi;
      expect(cost('1 0 0'), closeTo(10 * (1 - down * 0.05) + 10, 1e-9));
      // 8 m down: 38.7°, 1 − 1.93 is below the floor of 0.5.
      expect(cost('8 0 0'), closeTo(10 * 0.5 + 10, 1e-9));
    });
  });

  group('water, bridges and boats', () {
    test('MAP-22 water stops units on foot, wheels or tracks', () {
      for (final mover in [_foot, _wheeled, _tracked]) {
        expect(_crossing('~', mover), isNull);
      }
    });

    test('MAP-25 MAP-42 a bridge carries ground units over water', () {
      final map = _row('g ~ g', extra: 'build bridge 1,0');
      final path = _finder(map).find(
        mover: _wheeled,
        from: const CellRef(0, 0),
        to: const CellRef(2, 0),
      )!;

      // The deck is priced as road: 0.25 AP per metre over 10 m.
      expect(path.cost, closeTo(10 + 2.5, 1e-9));
      expect(path.samples[1].terrainType, 'road');
    });

    test('MAP-14 a boat sails across water and under a bridge, '
        'and never leaves it', () {
      final map = _row('o ~ o g', extra: 'build bridge 1,0');
      final finder = _finder(map);

      expect(
        finder
            .find(
              mover: _boat,
              from: const CellRef(0, 0),
              to: const CellRef(2, 0),
            )
            ?.cost,
        closeTo(2.5 + 5 + 5 + 2.5, 1e-9),
      );
      expect(
        finder.find(
          mover: _boat,
          from: const CellRef(0, 0),
          to: const CellRef(3, 0),
        ),
        isNull,
      );
    });

    test('MAP-24 a boat reaches the water next to the shore, where units '
        'board', () {
      final map = _map('  o o g\n  o o g', '  0 0 0\n  0 0 0');

      expect(
        _finder(map).find(
          mover: _boat,
          from: const CellRef(0, 0),
          to: const CellRef(1, 1),
        ),
        isNotNull,
      );
    });

    test('MAP-19 an amphibious unit drives, sails and drives again', () {
      final finder = _finder(_row('g ~ o g'));

      FoundPath? cross(PathMover mover) => finder.find(
        mover: mover,
        from: const CellRef(0, 0),
        to: const CellRef(3, 0),
      );

      final path = cross(_amphibious)!;
      expect(cross(_wheeled), isNull);
      expect(cross(_boat), isNull);
      expect(path.samples.map((sample) => sample.mode).toSet(), {
        'wheeled',
        'sail',
      });
    });

    test('UNIT-02 sail alone makes a boat; sail and a ground class make an '
        'amphibious unit', () {
      final finder = _finder(_row('o g'));

      FoundPath? ashore(PathMover mover) => finder.find(
        mover: mover,
        from: const CellRef(0, 0),
        to: const CellRef(1, 0),
      );

      expect(ashore(_boat), isNull);
      expect(ashore(_amphibious), isNotNull);
    });

    test('MAP-23 a flying unit flies over water', () {
      expect(_crossing('~', _flyer), closeTo(5 + 5, 1e-9));
    });
  });

  group('flying', () {
    test('UNIT-01 a flyer crosses a mountain wall no ground unit '
        'crosses', () {
      final map = _map('  g m g\n  g m g', '  0 30 0\n  0 30 0');
      final finder = _finder(map);

      FoundPath? cross(PathMover mover) => finder.find(
        mover: mover,
        from: const CellRef(0, 0),
        to: const CellRef(2, 0),
      );

      expect(cross(_flyer), isNotNull);
      expect(cross(_wheeled), isNull);
      expect(cross(_foot), isNull);
    });

    test('MAP-17 a flyer stays under the altitude limit', () {
      final map = _row('g m g', heights: '0 30 0');

      expect(
        _finder(map, rules: const PathRules(altitudeLimitM: 20)).find(
          mover: _flyer,
          from: const CellRef(0, 0),
          to: const CellRef(2, 0),
        ),
        isNull,
      );
    });

    test('MAP-17 a flyer ignores walls and buildings', () {
      expect(_crossing('w', _flyer), isNotNull);
      expect(_crossing('b', _flyer), isNotNull);
    });

    test('MAP-18 a landed flyer moves with its ground class', () {
      // The same helicopter, landed: its mover lists its ground class.
      expect(
        _crossing('f', const PathMover(apPerM: 1, modes: ['wheeled'])),
        isNull,
      );
    });
  });

  group('objects and islands', () {
    test(
      'MAP-44 intact walls and buildings stop ground units; trees do not',
      () {
        expect(_crossing('w', _foot), isNull);
        expect(_crossing('b', _wheeled), isNull);
        expect(_crossing('T', _foot), closeTo(10 + 20, 1e-9));
      },
    );

    test('MAP-36 MAP-37 MAP-43 foot units climb a ladder of any height to '
        'an island and down again; wheels and tracks cannot', () {
      final map = _row(
        'g g',
        extra:
            'island sky 500 floating_island_ground 5,5\n'
            'link ladder 1,0 sky:5,5',
      );
      final finder = _finder(map);
      const island = CellRef(5, 5, surface: 'sky');

      final climb = finder.find(
        mover: _foot,
        from: const CellRef(0, 0),
        to: island,
      )!;
      expect(climb.cost, closeTo(10 + 500, 1e-9));
      expect(
        finder.find(mover: _foot, from: island, to: const CellRef(0, 0))!.cost,
        closeTo(500 + 10, 1e-9),
      );
      expect(
        finder.find(mover: _wheeled, from: const CellRef(0, 0), to: island),
        isNull,
      );
    });

    test('MAP-36 a bridge to an island carries ground units within their '
        'slope limit', () {
      final map = _row(
        'g g',
        extra:
            'island sky 3 floating_island_ground 4,0\n'
            'link bridge 1,0 sky:4,0',
      );
      final path = _finder(map).find(
        mover: _wheeled,
        from: const CellRef(0, 0),
        to: const CellRef(4, 0, surface: 'sky'),
      )!;
      final slope = math.atan2(3, 30) * 180 / math.pi;

      expect(path.cost, closeTo(10 + 30 * 0.25 * (1 + slope * 0.1), 1e-9));
      expect(path.samples.last.lengthM, 30);
    });

    test('a mover with two ground classes crosses a link with the cheaper '
        'one', () {
      final map = _row(
        'g g',
        extra:
            'island sky 0 floating_island_ground 4,0\n'
            'link bridge 1,0 sky:4,0',
      );
      final path = _finder(map).find(
        mover: const PathMover(apPerM: 1, modes: ['foot', 'wheeled']),
        from: const CellRef(1, 0),
        to: const CellRef(4, 0, surface: 'sky'),
      )!;

      expect(path.samples.single.mode, 'wheeled');
      expect(path.cost, closeTo(30 * 0.25, 1e-9));
    });

    test('MAP-36 MAP-45 a flyer reaches an island; going up is free', () {
      final map = _row(
        'g g',
        extra: 'island sky 40 floating_island_ground 1,0',
      );
      final path = _finder(map).find(
        mover: _flyer,
        from: const CellRef(0, 0),
        to: const CellRef(1, 0, surface: 'sky'),
      )!;

      expect(path.cost, closeTo(5, 1e-9));
    });

    test('MAP-37 without its ladder an island strands its units', () {
      final map = _row(
        'g g',
        extra: 'island sky 50 floating_island_ground 5,5',
      );

      expect(
        _finder(map).find(
          mover: _foot,
          from: const CellRef(5, 5, surface: 'sky'),
          to: const CellRef(0, 0),
        ),
        isNull,
      );
    });
  });

  group('found paths', () {
    late Pathfinder finder;

    setUp(() {
      finder = _finder(
        NavigationFixture.parse(
          File('test/fixtures/valley.map').readAsStringSync(),
        ),
      );
    });

    test('COMBAT-03 a path costs the sum of its samples', () {
      for (final mover in [_foot, _wheeled, _amphibious, _flyer]) {
        final path = finder.find(
          mover: mover,
          from: const CellRef(0, 0),
          to: const CellRef(3, 3),
        )!;

        expect(
          path.cost,
          closeTo(_sumOfSamples(path.samples, mover.apPerM), 1e-9),
        );
        expect(path.cells.first, const CellRef(0, 0));
        expect(path.cells.last, const CellRef(3, 3));
      }
    });

    test('a path to the start is empty', () {
      final path = finder.find(
        mover: _foot,
        from: const CellRef(1, 1),
        to: const CellRef(1, 1),
      )!;

      expect(path.cells, [const CellRef(1, 1)]);
      expect(path.cost, 0);
    });

    test('rejects a start or a goal the map does not have', () {
      expect(
        () => finder.find(
          mover: _foot,
          from: const CellRef(9, 9),
          to: const CellRef(0, 0),
        ),
        throwsArgumentError,
      );
      expect(
        () => finder.find(
          mover: _foot,
          from: const CellRef(0, 0),
          to: const CellRef(9, 9),
        ),
        throwsArgumentError,
      );
    });
  });

  group('path check', () {
    late Pathfinder finder;

    setUp(() {
      finder = _finder(
        NavigationFixture.parse(
          File('test/fixtures/valley.map').readAsStringSync(),
        ),
      );
    });

    test('a path from the search passes the check with the same cost', () {
      for (final mover in [_foot, _amphibious, _flyer]) {
        final path = finder.find(
          mover: mover,
          from: const CellRef(0, 0),
          to: const CellRef(4, 0, surface: 'sky'),
        );
        if (path == null) continue;
        final check =
            finder.check(mover: mover, path: path.cells) as PathPasses;

        expect(check.cost, closeTo(path.cost, 1e-9));
        expect(check.samples, hasLength(path.samples.length));
      }
    });

    test('fails at the step into an impassable cell', () {
      final check = finder.check(
        mover: _wheeled,
        path: const [CellRef(0, 1), CellRef(1, 1), CellRef(2, 1)],
      );

      // (1, 1) is forest: no wheels.
      expect((check as PathFails).step, 1);
      expect(check.reason, StepFailure.impassable);
    });

    test('fails at the step over the slope limit', () {
      final check = finder.check(
        mover: _foot,
        path: const [CellRef(4, 2), CellRef(5, 2)],
      );

      // 17 m over 10 m: 59.5°, over the foot limit.
      expect((check as PathFails).step, 1);
      expect(check.reason, StepFailure.impassable);
    });

    test('fails at a jump between cells that are not connected', () {
      final check = finder.check(
        mover: _foot,
        path: const [CellRef(0, 0), CellRef(0, 2)],
      );

      expect((check as PathFails).reason, StepFailure.notConnected);
    });

    test('fails at a cell the map does not have', () {
      final check = finder.check(
        mover: _foot,
        path: const [CellRef(0, 0), CellRef(-1, 0)],
      );

      expect((check as PathFails).step, 1);
      expect(check.reason, StepFailure.unknownCell);
    });

    test('accepts a ladder climb and a flyer going up to an island', () {
      final climb = finder.check(
        mover: _foot,
        path: const [
          CellRef(3, 0),
          CellRef(4, 0, surface: 'sky'),
        ],
      );
      final flight = finder.check(
        mover: _flyer,
        path: const [
          CellRef(4, 0),
          CellRef(4, 0, surface: 'sky'),
        ],
      );
      final walkUp = finder.check(
        mover: _foot,
        path: const [
          CellRef(4, 0),
          CellRef(4, 0, surface: 'sky'),
        ],
      );

      expect((climb as PathPasses).cost, closeTo(60, 1e-9));
      expect((flight as PathPasses).cost, 0);
      expect((walkUp as PathFails).reason, StepFailure.impassable);
    });
  });
}
