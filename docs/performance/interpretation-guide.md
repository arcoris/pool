# Benchmark Interpretation Guide

## Contents

- [Purpose](#purpose)
- [Interpretation Principles](#interpretation-principles)
- [Reading Execution Classes](#reading-execution-classes)
- [Reading Core Metrics](#reading-core-metrics)
- [Reading Benchmark Categories](#reading-benchmark-categories)
- [Backend Baselines Versus Package Baselines](#backend-baselines-versus-package-baselines)
- [Discussing Regressions](#discussing-regressions)
- [Discussing Improvements](#discussing-improvements)
- [What Reports Must Not Claim](#what-reports-must-not-claim)
- [Combining Benchmarks and Profiles](#combining-benchmarks-and-profiles)
- [Reporting Language](#reporting-language)
- [Report Author Checklist](#report-author-checklist)

## Purpose

This document defines how finished benchmark results for `arcoris.dev/pool`
must be read, explained, and reported.

Execution procedure belongs in [methodology.md](./methodology.md).
Benchmark inventory belongs in [benchmark-matrix.md](./benchmark-matrix.md).

## Interpretation Principles

All performance conclusions SHOULD follow these rules.

### Interpret comparisons, not isolated numbers

A benchmark number without a baseline is weak evidence.
Meaningful claims come from comparison:

- revision versus revision;
- `Pool[T]` versus plain allocation;
- `Pool[T]` versus direct `sync.Pool`;
- accepted path versus rejected path;
- controlled serial versus realistic serial;
- serial versus parallel.

Single-snapshot charts are still useful, but they answer a narrower question:
what does the current benchmark surface look like right now?
They do not establish revision-to-revision movement by themselves.

### Keep benchmark class attached to the result

Every result is conditioned by:

- the benchmark class;
- the shape of `T`;
- the lifecycle path;
- the configured hooks.

If that context is omitted, the claim is incomplete.

### Separate measurement from explanation

Benchmarks show that a result changed.
Profiles help explain why.
Profiles do not replace repeated benchmark comparison.

### Report the narrowest justified claim

If evidence is local, the conclusion MUST stay local.
The repository does not support universal performance claims from one benchmark
family.

## Reading Execution Classes

| Class | Supports claims about | Does not support claims about |
| --- | --- | --- |
| controlled serial hot path | local steady-state reuse cost under an idealized harness | general serial behaviour or production-wide performance |
| realistic serial path | serial policy-path behaviour under the ordinary runtime | contention, scheduler scaling, or upper-bound hot path cost |
| realistic parallel path | concurrent behaviour and CPU-scaling sensitivity | serial steady-state cost |

Interpretation rules:

- controlled serial hot path results are upper-bound microbenchmark evidence;
- realistic serial results may still be narrow, but they include ordinary
  runtime effects;
- realistic parallel results MUST be read together with the CPU matrix that
  produced them;
- benchmark families whose names begin with `Controlled` and `Realistic`
  SHOULD be reported with those class labels intact;
- do not rank results from different execution classes as if they were the same
  kind of evidence.

## Reading Core Metrics

| Metric | Useful for | Not sufficient for |
| --- | --- | --- |
| `ns/op` | per-operation time cost and before/after comparison | allocation pressure or causal explanation |
| `B/op` | allocated bytes per iteration | end-to-end speed |
| `allocs/op` | allocation count and steady-state reuse visibility | cost of each allocation |
| `news/op` | constructor pressure during the measured path | general package speed claims |
| `drops/op` | explicit drop frequency | steady-state accepted-path claims |
| `reuse_denials/op` | policy rejection frequency | backend or allocation-only claims |

Metric rules:

- read `ns/op`, `B/op`, and `allocs/op` together;
- quote custom metrics only with the benchmark path that generated them;
- do not treat fewer allocations as automatic proof of a better outcome;
- do not treat `news/op == 0` from a controlled serial benchmark as proof that
  real workloads never construct.

## Reading Benchmark Categories

Use the benchmark matrix for the full inventory.
For interpretation, the categories mean the following:

| Category | Supports claims about | Does not support claims about |
| --- | --- | --- |
| backend baselines | internal backend miss and reuse cost | full public runtime cost |
| package baselines | public runtime cost relative to allocation and raw `sync.Pool` | universal benefit for all workloads |
| lifecycle-path benchmarks | accepted, rejected, reset-heavy, and drop-observed path cost | package-wide claims without naming the path |
| shape benchmarks | sensitivity to the shape of `T` | conclusions that apply equally to all `T` |
| parallel benchmarks | concurrency behaviour and scaling sensitivity | serial reuse cost |
| compare surfaces | report-friendly grouped output | new behavioural evidence beyond the underlying cases |
| metrics benchmarks | path-specific event counters | broad performance claims without the companion time and allocation metrics |

## Backend Baselines Versus Package Baselines

Backend baselines define a lower bound for the internal storage layer.
Package baselines include lifecycle orchestration on top of that layer.

Interpretation rules:

- use backend baselines to localize storage-layer cost;
- use package baselines for public-runtime claims;
- do not substitute backend results for package-level conclusions;
- treat snapshot charts as presentation summaries over raw artifacts rather than
  standalone statistical comparisons;
- treat compare surfaces such as `BenchmarkCompare_LifecyclePaths` or
  `BenchmarkCompare_Parallel` as presentation helpers over existing evidence,
  not as an additional runtime class;
- when package overhead moves and backend baselines do not, investigate
  lifecycle or orchestration work first.

## Discussing Regressions

When a result gets worse, interpret it in this order:

1. Confirm that the change is real with repeated runs and `benchstat`.
2. Confirm that the benchmark case, execution class, and command line did not change.
3. Identify which metrics moved.
4. Map the movement to the most likely layer or policy path.
5. Use profiles only after the benchmark comparison is established.

Useful first checks:

- backend-only movement suggests backend work;
- controlled accepted-path movement with stable allocations suggests local
  orchestration or reset cost;
- realistic accepted-path movement, such as
  `BenchmarkPaths_RealisticAccepted`, suggests ordinary serial reuse behaviour
  or incidental constructor pressure under the normal runtime;
- rejected-path movement suggests reuse or drop-path work;
- realistic parallel-only movement suggests contention or scheduling effects.

## Discussing Improvements

An improvement statement SHOULD name:

- the benchmark category;
- the execution class;
- the workload shape;
- the metrics that changed.

Example of an acceptable claim:

`Pool[T]` stayed close to raw `sync.Pool` on the controlled pointer-like reuse
path for this benchmark shape while reducing allocation pressure relative to
plain allocation.

Example of an unacceptable claim:

The package is now universally high-performance.

## What Reports Must Not Claim

Reports based on this suite MUST NOT claim:

- that pooling is always beneficial;
- that one benchmark shape applies to all `T`;
- that controlled serial hot path data describes general runtime behaviour;
- that serial results imply parallel results;
- that lower allocations automatically justify higher runtime;
- that profile output alone proves superiority;
- that backend-only results describe the full public runtime.

## Combining Benchmarks and Profiles

Use this order:

1. benchmark output;
2. `benchstat` comparison;
3. changed metrics;
4. profile evidence;
5. narrow conclusion.

This order prevents profile-first narratives that are not anchored to measured
changes.

## Reporting Language

Prefer language such as:

- on the controlled accepted path;
- on `BenchmarkPaths_RealisticAccepted`;
- on the realistic rejected serial path;
- under the realistic parallel CPU matrix;
- for this benchmark shape;
- relative to plain allocation;
- relative to raw `sync.Pool`.

Avoid language such as:

- always faster;
- universally better;
- zero-cost abstraction;
- no overhead;
- production faster without workload evidence.

## Report Author Checklist

- Name the benchmark category from the matrix.
- Name the execution class.
- Name the workload shape.
- Name the lifecycle path when applicable.
- Show which metrics changed.
- Distinguish measurement from explanation.
- Keep conclusions no broader than the evidence.
