# Performance Documentation

## Contents

- [Purpose](#purpose)
- [Artifact Layout](#artifact-layout)
- [Initial Snapshot Overview](#initial-snapshot-overview)
- [Document Map](#document-map)
- [Current Reports](#current-reports)
- [Related Package Documentation](#related-package-documentation)

## Purpose

This directory is the entry point for the repository's performance subsystem.

It ties together:

- benchmark source files that live next to the packages they measure;
- raw benchmark artifacts in the [raw artifacts directory](../../bench/raw/);
- comparison artifacts in the [comparison artifacts directory](../../bench/compare/);
- profile artifacts in the [profiles directory](../../bench/profiles/);
- generated chart artifacts in the [charts directory](../../bench/charts/);
- curated human-authored reports in the [reports directory](./reports/).

This README is an overview and navigation file.
Method rules, benchmark inventory, interpretation rules, and report contract
live in the linked reference documents.

## Artifact Layout

| Path | Responsibility |
| --- | --- |
| [Raw artifacts directory](../../bench/raw/) | repeated raw `go test -bench` output and matching environment captures |
| [Comparison artifacts directory](../../bench/compare/) | `benchstat` output and optional compare-oriented CSV |
| [Profiles directory](../../bench/profiles/) | CPU and memory profiles plus matching environment captures |
| [Charts directory](../../bench/charts/) | generated SVG charts from compare CSV and curated raw snapshots |
| [Reports directory](./reports/) | preserved reports that tie the artifacts together |
| [Benchmark scripts directory](../../bench/scripts/) | benchmark automation, environment capture, comparison, profiling, and chart generation |

## Initial Snapshot Overview

The current chart set includes one curated initial baseline snapshot from a
single raw benchmark artifact:

- [Initial baseline report](./reports/2026-04-21-initial-baseline.md)
- [Initial baseline raw artifact](../../bench/raw/initial-baseline.txt) in the [raw artifacts directory](../../bench/raw/)
- [Initial baseline environment capture](../../bench/raw/initial-baseline.env.txt) in the [raw artifacts directory](../../bench/raw/)

This snapshot is a current-state presentation layer.
It does not establish regression or improvement across revisions.
The snapshot charts aggregate repeated raw samples by benchmark family and
metric, using the median as the representative value for each benchmark and
metric pair.

Representative overview charts:

### Backend lower-bound cost surface

![Initial baseline backend time chart](../../bench/charts/initial-baseline-backend-time-op.svg)

Backend charts isolate the internal backend-only surface.
They are useful for understanding storage-layer cost and MUST NOT be read as
full public-runtime results.

### Package baseline surface

![Initial baseline package baseline time chart](../../bench/charts/initial-baseline-baselines-time-op.svg)

Baseline charts show the repository's main baseline surface:
plain allocation, direct `sync.Pool`, and the public runtime.

### Lifecycle-path surface

![Initial baseline lifecycle path time chart](../../bench/charts/initial-baseline-paths-time-op.svg)

Path charts show lifecycle behaviour such as accepted, rejected, reset-heavy,
and drop-observed return paths.

Supporting lifecycle counters are available in the report, for example:

- [Path drop-rate chart](../../bench/charts/initial-baseline-paths-drops-op.svg) in the [charts directory](../../bench/charts/)
- [Metrics reuse-denial chart](../../bench/charts/initial-baseline-metrics-reuse-denials-op.svg) in the [charts directory](../../bench/charts/)

### Realistic parallel surface

![Initial baseline parallel time chart](../../bench/charts/initial-baseline-parallel-time-op.svg)

Parallel charts show realistic concurrent behaviour under the benchmark suite's
parallel cases.

## Document Map

| Document | Role |
| --- | --- |
| [Benchmark Methodology](./methodology.md) | how benchmark artifacts are collected, compared, profiled, and charted |
| [Benchmark Matrix](./benchmark-matrix.md) | stable inventory of benchmark families and execution classes |
| [Benchmark Interpretation Guide](./interpretation-guide.md) | rules for reading benchmark and chart evidence without overclaiming |
| [Reports Contract](./reports/README.md) | what a committed performance report must contain |

## Current Reports

- [2026-04-21 Initial Baseline](./reports/2026-04-21-initial-baseline.md)

## Related Package Documentation

- [Architecture](../architecture.md)
- [Lifecycle](../lifecycle.md)
- [Non-goals](../non-goals.md)
