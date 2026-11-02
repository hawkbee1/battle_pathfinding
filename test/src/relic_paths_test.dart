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
legend w grass wall
''';

/// A map from the legend, a terrain block and a heights block.
NavigationMap _map(String terrain, String heights, [String extra = '']) =>
    NavigationFixture.parse(
      '${_legend}terrain\n$terrain\nheights\n$heights\n$extra',
    );

/// A flat one-row map of [cells] symbols.
NavigationMap _row(String cells, {String? heights, String extra = ''}) => _map(
  '  $cells',
  '  ${heights ?? List.filled(cells.split(' ').length, '0').join(' ')}',
  extra,
);

/// A relic: 10 AP per metre from its push pot on flat grass (decision 175).
const _relic = PathMover(apPerM: 10, modes: ['push']);

/// The HQ: 0.2 AP per metre of its own pool on flat grass (decision 177).
const _hq = PathMover(apPerM: 0.2, modes: ['push']);

FoundPath? _find(
  NavigationMap map,
  PathMover mover,
  CellRef from,
  CellRef to,
) => Pathfinder(
  map: map,
  cost: fixtureCost,
).find(mover: mover, from: from, to: to);

FoundPath? _across(NavigationMap map, [PathMover mover = _relic]) =>
    _find(map, mover, const CellRef(0, 0), CellRef(map.width - 1, 0));

void main() {
  test(
    "RELIC-19 a relic's path is priced with its push pot's AP per metre",
    () {
      expect(_across(_row('g g'))?.cost, closeTo(10 * 10, 1e-9));
    },
  );

  test("HQ-14 the HQ's path is priced with its own AP per metre and the push "
      'profile', () {
    expect(_across(_row('g d'), _hq)?.cost, closeTo(0.2 * (5 + 15), 1e-9));
  });

  group('obstacles', () {
    test('RELIC-20 a relic avoids forests and towns', () {
      final forest = _map('  g f g\n  g g g', '  0 0 0\n  0 0 0');
      final path = _across(forest)!;

      expect(path.cells, isNot(contains(const CellRef(1, 0))));
      expect(_across(_row('g t g')), isNull);
      expect(_across(_row('g f g')), isNull);
    });

    test('RELIC-20 a relic crosses no mountain and no water', () {
      expect(_across(_row('g m g')), isNull);
      expect(_across(_row('g ~ g')), isNull);
    });

    test('RELIC-21 a relic takes a road rather than mud', () {
      final map = _map('  g d d d g\n  g r r r g', '  0 0 0 0 0\n  0 0 0 0 0');
      final path = _across(map)!;

      expect(path.cells, containsAll(const [CellRef(1, 1), CellRef(3, 1)]));
      expect(path.cells, isNot(contains(const CellRef(2, 0))));
    });

    test('RELIC-28 a walled-in relic has no path; without the walls it has '
        'one', () {
      const walls = '  w w w\n  w g w\n  w w w';
      const open = '  g g g\n  g g g\n  g g g';
      const flat = '  0 0 0\n  0 0 0\n  0 0 0';

      expect(
        _find(
          _map(walls, flat),
          _relic,
          const CellRef(1, 1),
          const CellRef(0, 0),
        ),
        isNull,
      );
      expect(
        _find(
          _map(open, flat),
          _relic,
          const CellRef(1, 1),
          const CellRef(0, 0),
        ),
        isNotNull,
      );
    });

    test('HQ-11 the HQ has the same obstacles as a relic', () {
      for (final symbol in ['f', 't', 'm', '~', 'w']) {
        expect(_across(_row('g $symbol g'), _hq), isNull, reason: symbol);
      }
    });
  });

  group('slopes', () {
    test('the push profile has its slope limit uphill and downhill', () {
      // 8 m over 10 m: 38.7°, over the push limit of 35°.
      expect(_across(_row('g g g', heights: '0 0 8')), isNull);
      expect(_across(_row('g g g', heights: '8 0 0')), isNull);
      // 6 m: 31°, within it.
      expect(_across(_row('g g g', heights: '0 0 6')), isNotNull);
    });
  });

  group('bridges', () {
    test('RELIC-26 a relic crosses a reinforced bridge, not a normal one', () {
      final normal = _row('g ~ g', extra: 'build bridge 1,0');
      final reinforced = _row('g ~ g', extra: 'build reinforced_bridge 1,0');

      expect(_across(normal), isNull);
      // The deck costs as road: 10 × (10 + 5).
      expect(_across(reinforced)?.cost, closeTo(10 * 15, 1e-9));
    });

    test('RELIC-26 HQ-11 only a reinforced bridge takes a relic or the HQ up '
        'to an island', () {
      NavigationMap linked(String kind) => _row(
        'g g',
        extra:
            'island sky 1 grass 4,0\n'
            'link $kind 1,0 sky:4,0',
      );
      const island = CellRef(4, 0, surface: 'sky');

      for (final mover in [_relic, _hq]) {
        expect(
          _find(linked('bridge'), mover, const CellRef(0, 0), island),
          isNull,
        );
        final path = _find(
          linked('reinforced_bridge'),
          mover,
          const CellRef(0, 0),
          island,
        )!;
        final slope = math.atan2(1, 30) * 180 / math.pi;
        expect(
          path.cost,
          closeTo(mover.apPerM * (10 + 30 * 0.5 * (1 + slope * 0.07)), 1e-9),
        );
      }
    });
  });

  group('falls', () {
    // An island at 20 m over the first two cells of a three-cell row.
    final map = _row('g g g', extra: 'island sky 20 grass 0,0 1,0');
    const top = CellRef(0, 0, surface: 'sky');
    const below = CellRef(2, 0);

    test('RELIC-22 MAP-39 a relic pushed over an island edge falls to the '
        'ground next to it, for free', () {
      final path = _find(map, _relic, top, below)!;

      expect(path.cells, [top, const CellRef(1, 0, surface: 'sky'), below]);
      expect(path.falls, [below]);
      // 10 m on the island; the fall is free.
      expect(path.cost, closeTo(100, 1e-9));
    });

    test('HQ-48 MAP-39 the HQ falls too', () {
      expect(_find(map, _hq, top, below)?.falls, [below]);
    });

    test('a unit does not go over the edge: it is stranded', () {
      expect(
        _find(map, const PathMover(apPerM: 1, modes: ['foot']), top, below),
        isNull,
      );
    });

    test('the path check accepts the fall and reports it', () {
      final check = Pathfinder(map: map, cost: fixtureCost).check(
        mover: _relic,
        path: const [
          top,
          CellRef(1, 0, surface: 'sky'),
          below,
        ],
      ) as PathPasses;

      expect(check.falls, [below]);
      expect(check.cost, closeTo(100, 1e-9));
    });

    test('a path that falls nowhere has no falls', () {
      expect(_across(_row('g g'))?.falls, isEmpty);
    });
  });
}
