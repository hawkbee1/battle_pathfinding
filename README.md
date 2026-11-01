# battle_pathfinding

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]

The headless **pathfinding** of Battle Team, a 3D, massive, persistent, real-time team
battle game. It finds the cheapest path in AP for every movement class and profile,
and for pushed relics and the moving HQ, on the battle map. It returns each path as
the samples the rules core ([battle_rules](https://github.com/hawkbee1/battle_rules))
takes as input: terrain type, signed slope in degrees, length in metres.

- **Pure Dart**: no Flutter, no rendering, no network.
- **No I/O in `lib/`**: the caller passes the navigation model and the movement
  cost. Only command-line tools in `bin/` may read files.
- **Injected movement cost**: a function of the unit's AP per metre, the movement
  class or profile, the terrain type and the signed slope. Tests use fixture maps
  and fixture costs; this package never reads the game data. A caller wires in the
  real cost from `battle_rules`, so the two packages do not depend on each other.
- **Deterministic**: no wall clock, no unseeded randomness, no global state.

## Part of hawkbee

This repository is a git submodule of the
[hawkbee](https://github.com/hawkbee1/hawkbee) monorepo and **only builds inside
it** (pub workspace, `resolution: workspace`):

```sh
git clone --recurse-submodules https://github.com/hawkbee1/hawkbee.git
cd hawkbee && flutter pub get
```

## Specification

The rules live in the Battle Team app repository, mounted in hawkbee at
`apps/battle_team/plan/`:

| Path | Content |
|---|---|
| [`plan/milestones/m3-pathfinding.md`](https://github.com/hawkbee1/battle_team/blob/main/plan/milestones/m3-pathfinding.md) | The milestone this package implements, one issue per work session. |
| [`plan/specs/`](https://github.com/hawkbee1/battle_team/tree/main/plan/specs) | The rules, each with a stable ID (`MAP-16`, `MAP-22`, ...). Code and tests cite these IDs. |
| [`plan/stack/05-map-format.md`](https://github.com/hawkbee1/battle_team/blob/main/plan/stack/05-map-format.md) | The map format the navigation model is built from. |
| [`plan/stack/07-engineering-principles.md`](https://github.com/hawkbee1/battle_team/blob/main/plan/stack/07-engineering-principles.md) | Principles, patterns and package layout. |

Work sessions: hawkbee's [docs/battle_team](https://github.com/hawkbee1/hawkbee/tree/main/docs/battle_team).

## Running tests

From the package folder, inside a hawkbee checkout:

```sh
very_good test --coverage
```

The target is 100 % line coverage. Static analysis:

```sh
dart analyze --fatal-infos
```

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
