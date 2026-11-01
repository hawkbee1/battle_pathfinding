// Not required for test files
// ignore_for_file: prefer_const_constructors
import 'package:test/test.dart';
import 'package:battle_pathfinding/battle_pathfinding.dart';

void main() {
  group('BattlePathfinding', () {
    test('can be instantiated', () {
      expect(BattlePathfinding(), isNotNull);
    });
  });
}
