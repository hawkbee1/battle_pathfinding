import 'dart:math' as math;

/// AP multipliers per terrain and mode; a missing mode is impassable.
const fixtureMultipliers = <String, Map<String, double>>{
  'grass': {'foot': 1, 'wheeled': 1, 'tracked': 1, 'flying': 0.5},
  'road': {'foot': 0.5, 'wheeled': 0.25, 'tracked': 0.5, 'flying': 0.5},
  'forest_floor': {'foot': 2, 'tracked': 3, 'flying': 0.5},
  'mud': {'foot': 2, 'wheeled': 4, 'tracked': 2, 'flying': 0.5},
  'mountain': {'foot': 3, 'flying': 0.5},
  'town_street': {'foot': 1, 'wheeled': 1, 'tracked': 1, 'flying': 0.5},
  'river': {'sail': 1, 'flying': 0.5},
  'lake': {'sail': 0.5, 'flying': 0.5},
  'floating_island_ground': {
    'foot': 1,
    'wheeled': 1,
    'tracked': 1,
    'flying': 0.5,
  },
};

/// Slope rule per mode: factor, steepest slope, downhill floor.
const fixtureSlopes = <String, (double, double, double)>{
  'foot': (0.05, 45, 0.5),
  'wheeled': (0.1, 25, 0.5),
  'tracked': (0.07, 35, 0.5),
  'flying': (0, 90, 1),
  'sail': (0, 90, 1),
};

/// A fixture movement cost with the shape of the rules core's (M4 Issue
/// 4): `apPerM × multiplier × max(floor, 1 + slope × factor)`, null when
/// the table has no multiplier or the slope is too steep, up or down.
double? fixtureCost(
  double apPerM,
  String mode,
  String terrainType,
  double slopeDegrees,
) {
  final multiplier = fixtureMultipliers[terrainType]?[mode];
  if (multiplier == null) return null;
  final (factor, steepest, floor) = fixtureSlopes[mode]!;
  if (slopeDegrees.abs() > steepest) return null;
  return apPerM * multiplier * math.max(floor, 1 + slopeDegrees * factor);
}
