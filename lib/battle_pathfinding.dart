/// Headless pathfinding of Battle Team: the cheapest path in AP for every
/// movement class and profile, returned as the path samples the rules core
/// takes as input.
///
/// Pure Dart with no I/O: the caller passes the navigation model and the
/// movement cost.
library;

export 'src/navigation_fixture.dart';
export 'src/navigation_map.dart';
export 'src/path_search.dart';
