# Benchmark Matrix

## Contents

- [Purpose](#purpose)
- [Selection Principles](#selection-principles)
- [Execution Classes](#execution-classes)
- [Benchmark Groups](#benchmark-groups)
- [1. Backend Baselines](#1-backend-baselines)
- [2. Package Baselines](#2-package-baselines)
- [3. Lifecycle Paths](#3-lifecycle-paths)
- [4. Value Shapes](#4-value-shapes)
- [5. Parallel Execution](#5-parallel-execution)
- [6. Comparison Surfaces and Metrics](#6-comparison-surfaces-and-metrics)
- [Canonical Suite](#canonical-suite)
- [Promotion Rules](#promotion-rules)
- [Relationship to Reports](#relationship-to-reports)
- [Package Boundary](#package-boundary)

## Purpose

This document defines the stable benchmark inventory for `arcoris.dev/pool`.

It answers four questions:

- which benchmark groups exist;
- why each group exists;
- which cases are mandatory;
- which execution class each case belongs to, when the case is a direct
  measured workload rather than a grouped comparison surface.

The shell tooling uses the same family vocabulary through suite selectors such
as `backend`, `baselines`, `paths`, `shapes`, `parallel`, `metrics`, and the
cross-family selectors `controlled-serial`, `realistic-serial`, and `compare`.

Execution procedure belongs in [methodology.md](./methodology.md).
Result-reading rules belong in
[interpretation-guide.md](./interpretation-guide.md).

## Selection Principles

Canonical benchmark cases SHOULD satisfy the following rules.

### Contract relevance

A benchmark group MUST map to a real responsibility of the package or its
internal backend.

### Comparative value

A benchmark case SHOULD answer a comparison question, not just emit a number.

### Lifecycle visibility

The suite MUST keep accepted and rejected return paths visible.

### Shape sensitivity

The suite MUST keep the shape of `T` visible.
Pointer-like and value workloads are not interchangeable.

### Execution-class separation

Controlled serial hot path data, realistic serial data, and realistic parallel
data MUST remain distinguishable.

### Stable core

The canonical suite SHOULD stay small and stable enough to support historical
comparison across revisions.

## Execution Classes

| Class | Meaning |
| --- | --- |
| controlled serial hot path | upper-bound microbenchmark for local steady-state reuse |
| realistic serial path | serial benchmark without forced single-P and GC suppression |
| realistic parallel path | `RunParallel` benchmark under the ordinary scheduler and GC |

## Benchmark Groups

### 1. Backend Baselines

Why this group exists:
It isolates the internal backend over `sync.Pool` without public lifecycle
policy on top.

Mandatory cases:

| Case | Class | Why |
| --- | --- | --- |
| `BenchmarkSyncPool_GetMiss` | realistic serial path | pure constructor-miss lower bound |
| `BenchmarkSyncPool_ControlledGetPut_Pointer` | controlled serial hot path | pointer-like backend reuse upper bound |
| `BenchmarkSyncPool_ControlledGetPut_Value` | controlled serial hot path | value-type backend reuse contrast case |
| `BenchmarkSyncPool_RealisticParallel` | realistic parallel path | backend behaviour under concurrent pressure |

Optional cases:

- pointer-like objects with retained slices;
- constructor-heavy backend-only probes;
- explicit backend-only CPU-matrix sweeps.

### 2. Package Baselines

Why this group exists:
It compares the public runtime with the two external baselines that matter most:
plain allocation and direct `sync.Pool` usage.

Mandatory cases:

| Case | Class | Why |
| --- | --- | --- |
| `BenchmarkBaseline_AllocOnly_Pointer` | realistic serial path | fresh-allocation pointer baseline |
| `BenchmarkBaseline_Controlled_RawSyncPool_Pointer` | controlled serial hot path | closest low-level pointer reuse baseline |
| `BenchmarkBaseline_Controlled_ARCORISPool_Pointer` | controlled serial hot path | public-runtime pointer reuse baseline |
| `BenchmarkBaseline_AllocOnly_Value` | realistic serial path | fresh-allocation value baseline |
| `BenchmarkBaseline_Controlled_RawSyncPool_Value` | controlled serial hot path | value-type direct backend baseline |
| `BenchmarkBaseline_Controlled_ARCORISPool_Value` | controlled serial hot path | value-type public-runtime baseline |

Optional cases:

- a second pointer-like construction baseline with retained slices;
- a larger value-type construction baseline.

### 3. Lifecycle Paths

Why this group exists:
The public runtime is defined by return-path policy.
The suite must therefore expose accepted, rejected, reset-heavy, and
drop-observed paths directly.

Mandatory cases:

| Case | Class | Why |
| --- | --- | --- |
| `BenchmarkPaths_ControlledAccepted` | controlled serial hot path | accepted-path upper bound |
| `BenchmarkPaths_RealisticAccepted` | realistic serial path | accepted-path behaviour under the ordinary serial runtime |
| `BenchmarkPaths_RealisticRejected` | realistic serial path | rejected-path serial policy cost |
| `BenchmarkPaths_ControlledResetHeavy` | controlled serial hot path | accepted path dominated by deliberate reset work |
| `BenchmarkPaths_RealisticDropObserved` | realistic serial path | rejected path with visible drop work |

Optional cases:

- mixed accepted/rejected policy paths beyond the canonical accepted and rejected cases;
- accepted paths with different reset-to-work ratios.

### 4. Value Shapes

Why this group exists:
The usefulness and cost profile of pooling depend on the shape of `T`.

Mandatory cases:

| Case | Class | Why |
| --- | --- | --- |
| `BenchmarkShapes_ControlledPointerSmall` | controlled serial hot path | compact pointer-like accepted path |
| `BenchmarkShapes_ControlledPointerWithSlices` | controlled serial hot path | pointer-like accepted path with retained slices |
| `BenchmarkShapes_ControlledValueSmall` | controlled serial hot path | small value-type contrast case |
| `BenchmarkShapes_ControlledValueLarge` | controlled serial hot path | larger value-type contrast case |
| `BenchmarkShapes_AlwaysOversizedRejected` | realistic serial path | explicit always-rejected oversized workload |

Optional cases:

- objects with maps or nested retained slices;
- reset-dominated shapes with many retained references.

### 5. Parallel Execution

Why this group exists:
Concurrent behaviour must be visible separately from serial behaviour.

Mandatory cases:

| Case | Class | Why |
| --- | --- | --- |
| `BenchmarkParallel_RealisticAccepted` | realistic parallel path | accepted-path public runtime under concurrency |
| `BenchmarkParallel_RealisticRejected` | realistic parallel path | rejected-path public runtime under concurrency |
| `BenchmarkParallel_RealisticRawSyncPool` | realistic parallel path | closest low-level concurrent baseline |
| `BenchmarkParallel_RealisticARCORISPool` | realistic parallel path | public-runtime concurrent baseline |

Optional cases:

- explicit `SetParallelism` variants;
- acceptance-ratio sweeps;
- expanded `-cpu` matrices.

### 6. Comparison Surfaces and Metrics

Why this group exists:
Some benchmarks exist to keep report-facing comparisons stable and to emit
package-specific metrics that standard Go benchmark output does not provide.

Two kinds of cases live here:

- grouped comparison surfaces, which organize existing benchmark bodies under
  stable top-level names for reporting and chart work;
- direct metric-emitting workloads, which still belong to one of the ordinary
  runtime classes.

Mandatory cases:

| Case | Role | Why |
| --- | --- | --- |
| `BenchmarkCompare_PointerBaselines` | grouped comparison surface | stable pointer baseline grouping for compare output and charts |
| `BenchmarkCompare_ValueBaselines` | grouped comparison surface | stable value baseline grouping for compare output and charts |
| `BenchmarkCompare_LifecyclePaths` | grouped comparison surface | stable lifecycle grouping across controlled and realistic serial paths |
| `BenchmarkCompare_Shapes` | grouped comparison surface | stable shape grouping for compare output and charts |
| `BenchmarkCompare_Parallel` | grouped comparison surface | stable realistic parallel grouping for compare output and charts |
| `BenchmarkCompare_Metrics` | grouped comparison surface | stable grouping for metric-oriented benchmark output |
| `BenchmarkMetrics_ControlledAcceptedWarmPath` | controlled serial hot path | accepted-path constructor pressure counter |
| `BenchmarkMetrics_RealisticRejectedSteadyState` | realistic serial path | rejected-path event counters |
| `BenchmarkMetrics_RealisticMixedReuse` | realistic serial path | mixed reuse event counters |

Optional cases:

- policy-threshold sweeps;
- report-specific metric probes for one benchmark family.

## Canonical Suite

The canonical suite is the union of all mandatory cases in the six groups
above.

Reports SHOULD state:

- which groups were run;
- which mandatory cases were omitted, if any;
- which execution classes were used for direct workload benchmarks;
- whether any grouped comparison surfaces were used only for presentation;
- which exploratory cases were added beyond the matrix.

## Promotion Rules

A benchmark case SHOULD be promoted into the canonical suite only if at least
one of the following is true:

1. It exposes a lifecycle branch that is otherwise invisible.
2. It exposes a materially different `T` shape.
3. It adds a missing execution class for an important workload.
4. It protects against a known regression class.
5. It is required to support a recurring report claim.

A case SHOULD NOT be promoted if it is only:

- an ad hoc local experiment;
- a one-time tuning probe;
- a duplicate of an existing canonical conclusion;
- a benchmark for features outside package scope.

## Relationship to Reports

This document defines the inventory, not the results.

A performance report SHOULD identify:

- which matrix cases it uses;
- why those cases are sufficient for the question being asked;
- whether any matrix case was intentionally excluded;
- whether the report evidence is controlled serial, realistic serial, realistic
  parallel, or a documented mix.

## Package Boundary

This matrix is specific to `arcoris.dev/pool`.
It MUST NOT be treated as a generic template for unrelated pooling products.

A specialized memory or buffer-oriented package would need a different matrix,
because requested capacity, size classes, and retained-capacity policy are
different performance questions from generic typed temporary-object reuse.
