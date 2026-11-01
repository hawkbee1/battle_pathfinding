// A runtime instance, so coverage sees the constructor run.
// ignore_for_file: prefer_const_constructors
import 'package:battle_pathfinding/battle_pathfinding.dart';
import 'package:test/test.dart';

void main() {
  group(BattlePathfinding, () {
    test('can be instantiated', () {
      expect(BattlePathfinding(), isA<BattlePathfinding>());
    });
  });
}
