# Benchmark results

Machine-readable lines from `bin/long_path_bench.dart` (P-01) and
`bin/world_change_bench.dart` (P-07), compiled with `dart compile exe`, run
on the hawkbee dev container (Docker on the owner's machine), 2026-11-02.
Keep one block per measured commit; a regression is a change of more than
10 % (`performance-tests.md`).

## P-01: long paths on a synthetic 10 × 50 km map (seed 42)

Edge to edge (about 50 km), 8 fast paths, 2 exact:

```text
bench=long_path cell_m=10 cells=5000000 span_km=edge_to_edge mover=foot build_ms=519 prepare_ms=509 paths=8 found=8 fast_median_ms=146 fast_max_ms=319 fast_settled_mean=245780 exact_ms=3001/3059 max_margin_pct=0.07 rss_mb=205
bench=long_path cell_m=10 cells=5000000 span_km=edge_to_edge mover=wheeled build_ms=519 prepare_ms=490 paths=8 found=8 fast_median_ms=156 fast_max_ms=300 fast_settled_mean=244637 exact_ms=3330/3488 max_margin_pct=0.58 rss_mb=206
bench=long_path cell_m=20 cells=1250000 span_km=edge_to_edge mover=foot build_ms=131 prepare_ms=132 paths=8 found=8 fast_median_ms=75 fast_max_ms=117 fast_settled_mean=121530 exact_ms=742/755 max_margin_pct=0.04 rss_mb=65
bench=long_path cell_m=20 cells=1250000 span_km=edge_to_edge mover=wheeled build_ms=131 prepare_ms=133 paths=8 found=8 fast_median_ms=83 fast_max_ms=119 fast_settled_mean=121158 exact_ms=805/796 max_margin_pct=0.01 rss_mb=65
```

2 km paths, 20 fast paths, 3 exact (the first fast path of each mover prices
the blocks once: that is the maximum):

```text
bench=long_path cell_m=10 cells=5000000 span_km=2.0 mover=foot build_ms=465 prepare_ms=521 paths=20 found=20 fast_median_ms=14 fast_max_ms=174 fast_settled_mean=23031 exact_ms=151/209/541 max_margin_pct=0.07 rss_mb=191
bench=long_path cell_m=10 cells=5000000 span_km=2.0 mover=wheeled build_ms=465 prepare_ms=513 paths=20 found=20 fast_median_ms=15 fast_max_ms=172 fast_settled_mean=23331 exact_ms=139/234/676 max_margin_pct=0.07 rss_mb=191
bench=long_path cell_m=20 cells=1250000 span_km=2.0 mover=foot build_ms=129 prepare_ms=144 paths=20 found=20 fast_median_ms=7 fast_max_ms=57 fast_settled_mean=11522 exact_ms=55/128/33 max_margin_pct=0.15 rss_mb=57
bench=long_path cell_m=20 cells=1250000 span_km=2.0 mover=wheeled build_ms=129 prepare_ms=142 paths=20 found=19 fast_median_ms=7 fast_max_ms=43 fast_settled_mean=10697 exact_ms=53/123/36 max_margin_pct=0.00 rss_mb=57
```

## P-07: one world change on a live 256 × 256 map

```text
bench=world_change cells=65536 cached_steps=521080 warm_ms=1971 changes=200 mean_us=19 p50_us=20 p95_us=31 max_us=35
```

## After the review fixes (diagonal corners, link checks, indexes), same day

```text
bench=world_change cells=65536 cached_steps=521080 warm_ms=1797 changes=200 mean_us=18 p50_us=17 p95_us=31 max_us=48
bench=long_path cell_m=10 cells=5000000 span_km=2.0 mover=foot build_ms=490 prepare_ms=770 paths=20 found=20 fast_median_ms=15 fast_max_ms=249 fast_settled_mean=23031 exact_ms=169/218/616 max_margin_pct=0.07 rss_mb=216
bench=long_path cell_m=10 cells=5000000 span_km=2.0 mover=wheeled build_ms=490 prepare_ms=818 paths=20 found=20 fast_median_ms=16 fast_max_ms=179 fast_settled_mean=23331 exact_ms=154/258/653 max_margin_pct=0.07 rss_mb=216
bench=long_path cell_m=20 cells=1250000 span_km=2.0 mover=foot build_ms=138 prepare_ms=220 paths=20 found=20 fast_median_ms=7 fast_max_ms=56 fast_settled_mean=11522 exact_ms=56/131/34 max_margin_pct=0.15 rss_mb=64
bench=long_path cell_m=20 cells=1250000 span_km=2.0 mover=wheeled build_ms=138 prepare_ms=183 paths=20 found=19 fast_median_ms=8 fast_max_ms=47 fast_settled_mean=10696 exact_ms=58/140/39 max_margin_pct=0.00 rss_mb=64
```
