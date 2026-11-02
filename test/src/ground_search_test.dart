import 'dart:io';
import 'dart:math' as math;

import 'package:battle_pathfinding/battle_pathfinding.dart';
import 'package:test/test.dart';

import '../helpers/fixture_cost.dart';

const _foot = PathMover(apPerM: 1, modes: ['foot']);
const _wheeled = PathMover(apPerM: 1, modes: ['wheeled']);
const _amphibious = PathMover(apPerM: 1, modes: ['wheeled', 'sail']);

GroundSearch _search(NavigationMap map, PathMover mover) =>
    GroundSearch(map: map, cost: fixtureCost, mover: mover);

/// A flat map of [width] × [depth] cells whose symbols come from [symbol],
/// with the fixture lines of [header] (legend, water) and [extra].
NavigationMap _flat(
  int width,
  int depth,
  String Function(int x, int y) symbol, {
  required String header,
  String extra = '',
}) {
  final terrain = [
    for (var y = 0; y < depth; y++)
      '  ${[for (var x = 0; x < width; x++) symbol(x, y)].join(' ')}',
  ];
  final heights = [
    for (var y = 0; y < depth; y++) '  ${List.filled(width, '0').join(' ')}',
  ];
  return NavigationFixture.parse(
    'cell 10\n$header\nterrain\n${terrain.join('\n')}\n'
    'heights\n${heights.join('\n')}\n$extra',
  );
}

String _wallOrGrass(int x, int y) => y == 24 && x < 62 ? 'w' : 'g';

void main() {
  group('exact', () {
    test('MAP-04 finds the paths Pathfinder finds, at the same cost', () {
      final valley = NavigationFixture.parse(
        File('test/fixtures/valley.map').readAsStringSync(),
      );
      final finder = Pathfinder(map: valley, cost: fixtureCost);
      for (final mover in [_foot, _wheeled, _amphibious]) {
        final search = _search(valley, mover);
        for (final (from, to) in const [
          (CellRef(0, 0), CellRef(3, 3)),
          (CellRef(0, 3), CellRef(5, 0)),
          (CellRef(1, 1), CellRef(4, 1)),
        ]) {
          final reference = finder.find(mover: mover, from: from, to: to);
          final found = search.exact(from, to);

          expect(
            found?.cost,
            reference == null ? isNull : closeTo(reference.cost, 1e-9),
            reason: '${mover.modes} $from → $to',
          );
        }
      }
    });

    test('rejects a cell off the ground', () {
      final search = _search(syntheticMap(width: 8, depth: 8, seed: 1), _foot);

      expect(
        () => search.exact(
          const CellRef(0, 0, surface: 'sky'),
          const CellRef(1, 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => search.exact(const CellRef(0, 0), const CellRef(8, 8)),
        throwsArgumentError,
      );
    });
  });

  group('fast', () {
    test('MAP-04 costs at most 10 % more AP than the exact search on test '
        'maps', () {
      for (var seed = 0; seed < 4; seed++) {
        final map = syntheticMap(width: 120, depth: 300, seed: seed);
        final random = math.Random(seed);
        for (final mover in [_foot, _wheeled]) {
          final search = _search(map, mover);
          for (var pair = 0; pair < 3; pair++) {
            final from = CellRef(random.nextInt(120), random.nextInt(40));
            final to = CellRef(random.nextInt(120), 260 + random.nextInt(40));
            final exact = search.exact(from, to);
            final exactSettled = search.lastSettled;
            final fast = search.fast(from, to);

            if (exact == null) {
              expect(fast, isNull);
              continue;
            }
            expect(
              fast!.cost,
              lessThanOrEqualTo(exact.cost * 1.1),
              reason: 'seed $seed ${mover.modes} $from → $to',
            );
            expect(fast.cost, greaterThanOrEqualTo(exact.cost - 1e-6));
            expect(search.lastSettled, lessThanOrEqualTo(exactSettled));
          }
        }
      }
    });

    test('widens its corridor when the block path misses the only way '
        'through', () {
      // A wall across the map, with one gap at its far east end.
      final map = _flat(
        64,
        48,
        _wallOrGrass,
        header: 'legend g grass\nlegend w grass wall',
      );
      final search = _search(map, _foot);
      final fast = search.fast(
        const CellRef(2, 2),
        const CellRef(2, 46),
        blockSize: 8,
      )!;

      expect(fast.cells, contains(const CellRef(62, 24)));
      expect(
        fast.cost,
        closeTo(
          search.exact(const CellRef(2, 2), const CellRef(2, 46))!.cost,
          1e-6,
        ),
      );
    });

    test('there is no path across water a mover cannot cross', () {
      // A lake band three cells wide: foot units cannot cross it.
      final map = _flat(
        12,
        12,
        (x, y) => y >= 5 && y <= 7 ? 'o' : 'g',
        header: 'water lake\nlegend g grass\nlegend o lake',
      );
      final search = _search(map, _foot);

      expect(search.exact(const CellRef(1, 1), const CellRef(1, 10)), isNull);
      expect(
        search.fast(const CellRef(1, 1), const CellRef(1, 10), blockSize: 3),
        isNull,
      );
    });

    test('falls back to the whole ground when the blocks give no path', () {
      // The lake covers most of its blocks; one column of bridges crosses
      // it, too thin for the block search but enough for foot units.
      final map = _flat(
        12,
        12,
        (x, y) => y >= 3 && y <= 8 ? 'o' : 'g',
        header: 'water lake\nlegend g grass\nlegend o lake',
        extra: 'build bridge 6,3 6,4 6,5 6,6 6,7 6,8\n',
      );
      final search = _search(map, _foot);
      final fast = search.fast(
        const CellRef(1, 1),
        const CellRef(1, 10),
        blockSize: 3,
      )!;

      expect(fast.cells, contains(const CellRef(6, 5)));
      expect(
        fast.cost,
        closeTo(
          search.exact(const CellRef(1, 1), const CellRef(1, 10))!.cost,
          1e-6,
        ),
      );
    });
  });

  group('syntheticMap', () {
    test('is the same for the same seed, with roads, a river and bridges', () {
      final first = syntheticMap(width: 100, depth: 200, seed: 7);
      final second = syntheticMap(width: 100, depth: 200, seed: 7);
      final terrains = first.ground.map((cell) => cell.terrain).toSet();

      expect((first.width, first.depth), (100, 200));
      expect(
        [for (final cell in first.ground) cell.height],
        [for (final cell in second.ground) cell.height],
      );
      expect(terrains, containsAll(['grass', 'road', 'river']));
      expect(first.constructions.values, everyElement({'bridge'}));
      expect(first.constructions, isNotEmpty);
    });

    test('a coarser grid keeps the same landscape', () {
      final fine = syntheticMap(width: 40, depth: 40, seed: 3);
      final coarse = syntheticMap(width: 20, depth: 20, seed: 3, cellSizeM: 20);

      expect(coarse.cellSizeM, 20);
      expect(
        coarse.cellAt(const CellRef(5, 5))?.height,
        closeTo(fine.cellAt(const CellRef(10, 10))!.height, 2),
      );
    });
  });
}
