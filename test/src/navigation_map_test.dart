import 'dart:io';
import 'dart:math' as math;

import 'package:battle_pathfinding/battle_pathfinding.dart';
import 'package:test/test.dart';

NavigationMap _valley() => NavigationFixture.parse(
  File('test/fixtures/valley.map').readAsStringSync(),
);

void main() {
  late NavigationMap map;

  setUp(() {
    map = _valley();
  });

  group('the valley fixture', () {
    test('MAP-02 loads a river, a lake, a forest, a town, a mountain, a road '
        'and a floating island', () {
      expect(map.cellSizeM, 10);
      expect((map.width, map.depth), (6, 4));
      expect(map.cellAt(const CellRef(2, 1))?.terrain, 'river');
      expect(map.cellAt(const CellRef(0, 3))?.terrain, 'lake');
      expect(map.objectsAt(const CellRef(1, 1)), {'tree'});
      expect(map.objectsAt(const CellRef(5, 0)), {'building'});
      expect(map.objectsAt(const CellRef(4, 2)), {'wall'});
      expect(map.objectsAt(const CellRef(0, 0)), isEmpty);
      expect(map.cellAt(const CellRef(5, 3))?.terrain, 'mountain');
      expect(map.cellAt(const CellRef(5, 3))?.height, 40);
      expect(map.cellAt(const CellRef(0, 0))?.terrain, 'road');
      expect(map.islands.keys, ['sky']);
      expect(
        map.cellAt(const CellRef(4, 1, surface: 'sky'))?.terrain,
        'floating_island_ground',
      );
    });

    test('MAP-22 rivers and lakes are water', () {
      expect(map.isWater(const CellRef(2, 2)), isTrue);
      expect(map.isWater(const CellRef(1, 3)), isTrue);
      expect(map.isWater(const CellRef(3, 2)), isFalse);
      expect(map.isWater(const CellRef(9, 9)), isFalse);
    });

    test('MAP-23 a bridge stands over the river', () {
      expect(map.constructionsAt(const CellRef(2, 0)), {'bridge'});
      expect(map.constructionsAt(const CellRef(2, 1)), isEmpty);
    });

    test('MAP-36 a floating island is linked to the ground only by its '
        'bridges and ladders', () {
      const island = CellRef(4, 0, surface: 'sky');

      expect(map.neighbours(island).toSet(), {
        const CellRef(5, 0, surface: 'sky'),
        const CellRef(4, 1, surface: 'sky'),
      });
      final fromIsland = map.linksFrom(island).single;
      expect(fromIsland.kind, LinkKind.ladder);
      expect(fromIsland.to, const CellRef(3, 0));
      final fromGround = map.linksFrom(const CellRef(3, 1)).single;
      expect(fromGround.kind, LinkKind.bridge);
      expect(fromGround.to, const CellRef(4, 1, surface: 'sky'));
      expect(map.linksFrom(const CellRef(0, 0)), isEmpty);
    });

    test('MAP-37 a ladder has no height limit', () {
      final high = NavigationFixture.parse(
        File('test/fixtures/valley.map')
            .readAsStringSync()
            .replaceFirst('island sky 60', 'island sky 5000'),
      );

      expect(
        high.linksFrom(const CellRef(3, 0)).single.to,
        const CellRef(4, 0, surface: 'sky'),
      );
      expect(high.cellAt(const CellRef(4, 0, surface: 'sky'))?.height, 5000);
    });
  });

  group('slope', () {
    test('MAP-16 uphill is positive, downhill negative, flat is 0', () {
      // 2 m up over 10 m.
      final uphill = math.atan2(2, 10) * 180 / math.pi;

      expect(
        map.slopeDegrees(const CellRef(2, 2), const CellRef(3, 2)),
        closeTo(uphill, 1e-9),
      );
      expect(
        map.slopeDegrees(const CellRef(3, 2), const CellRef(2, 2)),
        closeTo(-uphill, 1e-9),
      );
      expect(map.slopeDegrees(const CellRef(0, 0), const CellRef(1, 0)), 0);
    });

    test('MAP-16 a diagonal step is a cell diagonal long', () {
      expect(
        map.stepLengthM(const CellRef(0, 0), const CellRef(1, 1)),
        closeTo(10 * math.sqrt2, 1e-9),
      );
      expect(
        map.slopeDegrees(const CellRef(0, 0), const CellRef(1, 1)),
        closeTo(math.atan2(1, 10 * math.sqrt2) * 180 / math.pi, 1e-9),
      );
    });
  });

  group(NavigationMap, () {
    test('neighbours stay inside the map', () {
      expect(map.neighbours(const CellRef(0, 0)).toSet(), {
        const CellRef(1, 0),
        const CellRef(0, 1),
        const CellRef(1, 1),
      });
      expect(map.neighbours(const CellRef(2, 2)), hasLength(8));
    });

    test('has no cell outside the grid or on an unknown island', () {
      expect(map.cellAt(const CellRef(-1, 0)), isNull);
      expect(map.cellAt(const CellRef(0, -1)), isNull);
      expect(map.cellAt(const CellRef(6, 0)), isNull);
      expect(map.cellAt(const CellRef(0, 4)), isNull);
      expect(map.cellAt(const CellRef(0, 0, surface: 'moon')), isNull);
    });

    test('rejects a ground that is not width × depth cells', () {
      expect(
        () => NavigationMap(
          cellSizeM: 10,
          width: 2,
          depth: 2,
          ground: const [NavCell(height: 0, terrain: 'grass')],
          waterTerrains: const {},
        ),
        throwsArgumentError,
      );
    });
  });

  group(CellRef, () {
    test('compares by surface and position', () {
      // Built at run time, so not the same object as the constant.
      final y = int.parse('2');

      expect(const CellRef(1, 2), CellRef(1, y));
      expect(const CellRef(1, 2).hashCode, CellRef(1, y).hashCode);
      expect(const CellRef(1, 2), isNot(const CellRef(1, 2, surface: 'sky')));
      expect(const CellRef(1, 2).toString(), '(1, 2)');
      expect(const CellRef(1, 2, surface: 'sky').toString(), 'sky(1, 2)');
    });
  });

  group(NavigationFixture, () {
    const base = '''
cell 10
legend g grass
terrain
  g g
heights
  0 0
''';

    void rejects(String text, String problem) => expect(
      () => NavigationFixture.parse(text),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains(problem),
        ),
      ),
    );

    test('loads a minimal map with comments and blank lines', () {
      final small = NavigationFixture.parse('# a map\n\n$base');

      expect((small.width, small.depth), (2, 1));
      expect(small.waterTerrains, isEmpty);
      expect(small.links, isEmpty);
    });

    test('names the line of each problem', () {
      rejects('${base}fly 1,1', 'line 7: unknown keyword fly');
      rejects('${base}legend x', 'legend <symbol> <terrain> [object]');
      rejects('${base}build bridge', 'build <construction> <cell>');
      rejects('${base}build road 1;0', 'bad cell 1;0');
      rejects('${base}build road a,0', 'bad cell a,0');
      rejects('${base}build road a:b:1,0', 'bad cell a:b:1,0');
      rejects('${base}link ladder 0,0', 'link <kind> <cell> <cell>');
      rejects('${base}link rope 0,0 1,0', 'unknown link rope');
      rejects('${base}island sky 9 grass', 'island <name> <height>');
      rejects('${base}island sky 9 grass x:1,0', 'island cells are x,y');
      rejects('${base}island sky high grass 1,0', 'high is not a number');
      rejects('cell\n', 'a number is missing');
    });

    test('needs a cell size, terrain and heights of the same size, and a '
        'legend for each symbol', () {
      rejects(base.replaceFirst('cell 10\n', ''), 'no cell size');
      rejects('cell 10\nheights\n  0\n', 'no terrain block');
      rejects('cell 10\nlegend g grass\nterrain\n  g\n', 'no heights block');
      rejects(base.replaceFirst('  0 0', '  0'), 'rectangles of the same size');
      rejects(base.replaceFirst('  g g', '  g x'), 'no legend for x');
    });
  });
}
