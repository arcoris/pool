# Architecture

## Contents

- [Overview](#overview)
- [Document Map](#document-map)
- [Repository Structure](#repository-structure)
- [Dependency Direction](#dependency-direction)
- [Layered Design](#layered-design)
- [Runtime Composition](#runtime-composition)
- [Performance Documentation](#performance-documentation)
- [Why the Backend Is Internal](#why-the-backend-is-internal)
- [File-Level Responsibilities](#file-level-responsibilities)
- [Testing Structure](#testing-structure)
- [Benchmark Source Layout](#benchmark-source-layout)
- [Architectural Change Boundaries](#architectural-change-boundaries)
- [Summary](#summary)

## Overview

`arcoris.dev/pool` is a small, policy-driven, typed temporary-object reuse
runtime.

Its architecture is intentionally narrow:

- the public package exposes a small public runtime;
- lifecycle policy is explicit and callback-based;
- return-path semantics are isolated from storage mechanics;
- the internal backend remains an implementation detail;
- test support is shared without becoming runtime API.

This document explains the structural boundaries of the repository. It does not
serve as the primary lifecycle specification and it does not serve as the
primary scope-boundary document. Those responsibilities belong to
`docs/lifecycle.md` and `docs/non-goals.md`.

## Document Map

Read the documentation in the following order:

- [Package overview](../doc.go) (`doc.go`) — package contract for Go users and pkg.go.dev
- [Architecture guide](./architecture.md) (`docs/architecture.md`) — repository structure, layering, and dependency boundaries
- [Lifecycle guide](./lifecycle.md) (`docs/lifecycle.md`) — value lifecycle, ownership, and return-path semantics
- [Non-goals guide](./non-goals.md) (`docs/non-goals.md`) — explicit scope boundaries and proposal decision rules
- [Performance overview](./performance/README.md) (`docs/performance/README.md`) — entry point for benchmark methodology, matrix, and interpretation rules

## Repository Structure

The repository is intentionally compact.

```text
pool/                               # repository root for the typed pool runtime
├─ doc.go                           # package contract for Go users and pkg.go.dev
├─ go.mod                           # module declaration, minimum Go version, and preferred toolchain
├─ bench/                           # benchmark artifacts and benchmark automation
│  ├─ raw/                          # untracked raw benchmark outputs and environment captures
│  ├─ compare/                      # untracked `benchstat` outputs and comparison artifacts
│  ├─ profiles/                     # untracked CPU and memory profiles for diagnostic runs
│  ├─ charts/                       # untracked generated chart artifacts such as SVG output
│  └─ scripts/                      # benchmark automation, shared shell modules, and chart generation
│     ├─ paths.sh                   # canonical repository and artifact path definitions for tooling
│     ├─ common.sh                  # shared shell helpers for validation, suite resolution, and naming
│     ├─ run_benchmarks.sh          # canonical raw benchmark collection entrypoint
│     ├─ compare_benchmarks.sh      # thin `benchstat` wrapper for text and CSV compare artifacts
│     ├─ profile_benchmarks.sh      # focused CPU and memory profiling entrypoint
│     ├─ capture_env.sh             # standalone environment-capture entrypoint
│     ├─ run_performance_pipeline.sh # orchestration entrypoint for multi-step benchmark campaigns
│     └─ plot_benchmarks.py         # chart generator that reads compare CSV and writes chart artifacts
├─ options.go                       # lifecycle policy definition and option normalization
├─ lifecycle.go                     # canonical return-path semantics and sink boundary
├─ pool.go                          # public runtime assembly and `Get`/`Put` orchestration
│
├─ options_test.go                  # unit tests for option resolution and defaults
├─ lifecycle_test.go                # unit tests for lifecycle ordering and ownership semantics
├─ pool_test.go                     # unit tests for public runtime behavior and integration
├─ pool_baseline_benchmark_test.go  # serial baseline comparisons against allocation and raw `sync.Pool`
├─ pool_paths_benchmark_test.go     # lifecycle-path benchmarks for accepted, rejected, reset, and drop work
├─ pool_shapes_benchmark_test.go    # shape-sensitivity benchmarks across pointer-like and value types
├─ pool_parallel_benchmark_test.go  # realistic parallel public-runtime benchmarks
├─ pool_compare_benchmark_test.go   # grouped compare surfaces for report-friendly benchmark output
├─ pool_metrics_benchmark_test.go   # benchmarks that emit pool-specific per-op metrics
│
├─ internal/                        # implementation details hidden from public API
│  ├─ backend/                      # internal storage layer behind the public runtime
│  │  ├─ syncpool.go                # thin typed backend over `sync.Pool`
│  │  ├─ syncpool_test.go           # backend-specific unit tests and invariant coverage
│  │  └─ syncpool_benchmark_test.go # backend-only lower-bound benchmark view
│  └─ testutil/                     # shared helpers for repository tests and benchmarks
│     ├─ assertions.go              # shared panic and event-sequence assertions
│     ├─ benchmark.go               # generic benchmark warm-up helpers
│     ├─ metrics.go                 # canonical benchmark metric names and reporters
│     ├─ payload.go                 # shared benchmark payload fixtures
│     ├─ recording.go               # lightweight test recording sinks
│     └─ runtime.go                 # scoped runtime controls for deterministic tests and controlled benches
│
└─ docs/                            # repository-facing documentation set
   ├─ architecture.md               # structure, layering, and architectural boundaries
   ├─ lifecycle.md                  # normative lifecycle and ownership rules
   ├─ non-goals.md                  # normative scope boundaries and exclusion rules
   └─ performance/                  # benchmark governance and reporting guidance
      ├─ README.md                  # entry point for the performance documentation set
      ├─ methodology.md             # benchmark execution procedure and artifact workflow
      ├─ benchmark-matrix.md        # benchmark inventory and canonical suite definition
      ├─ interpretation-guide.md    # rules for reading and reporting benchmark results
      └─ reports/                   # curated human-authored performance reports
         └─ README.md               # contract for what committed reports must contain
```

This layout separates:

- public package code at the repository root;
- benchmark artifacts and automation under `bench/`;
- internal implementation details under `internal/`;
- repository documentation under `docs/`;
- package-local tests next to the packages they verify.

## Dependency Direction

The dependency direction is intentionally simple.

- `options.go` defines lifecycle policy and does not depend on runtime or backend code.
- `lifecycle.go` depends on lifecycle policy types and a minimal sink contract.
- `pool.go` assembles policy, lifecycle, and the internal backend into the public runtime.
- `internal/backend/syncpool.go` depends only on `sync.Pool` and its own typed invariant checks.
- `internal/testutil/*.go` supports tests and benchmarks but MUST NOT become a runtime dependency.

In other words:

1. policy is defined first;
2. semantics are built on policy;
3. the public runtime composes semantics and storage;
4. the backend stays below the public runtime, not inside it.

## Layered Design

The package can be understood as four layers.

### 1. Public policy layer

Files:

- `options.go`

Responsibility:

- define lifecycle policy through `New`, `Reset`, `Reuse`, and `OnDrop`;
- validate mandatory policy at construction time;
- normalize optional hooks into stable internal defaults.

This layer answers: what lifecycle policy should the public runtime apply?

### 2. Lifecycle semantics layer

Files:

- `lifecycle.go`

Responsibility:

- define the canonical return-path order;
- separate acceptance, reset, drop observation, and storage concerns;
- expose the minimal semantic steps needed by the public runtime.

This layer answers: how is lifecycle policy applied on the return path?

### 3. Public runtime layer

Files:

- `pool.go`

Responsibility:

- expose `Pool[T]`, `New`, `Get`, and `Put`;
- assemble policy, lifecycle semantics, and internal backend storage;
- provide the package-facing public runtime contract.

This layer answers: how do callers use the package?

### 4. Internal backend layer

Files:

- `internal/backend/syncpool.go`

Responsibility:

- provide typed storage and retrieval over `sync.Pool`;
- keep backend-specific invariants out of the public runtime;
- isolate `any`/`T` bridging to one internal location.

This layer answers: where are already-clean reusable values stored while idle?

## Runtime Composition

Construction and execution follow a fixed composition path.

### Construction

At `New(...)`:

1. `Options[T]` are resolved into a complete lifecycle policy;
2. the internal backend is created from the resolved constructor;
3. the lifecycle controller is created from the resolved hooks;
4. the public runtime is assembled from those internal parts.

### Steady-state execution

At `Get()`:

1. the public runtime delegates to the internal backend;
2. the backend returns either a retained value or a freshly constructed value.

At `Put(v)`:

1. the public runtime delegates to the lifecycle controller;
2. the lifecycle controller applies the return-path policy;
3. if reuse is accepted, the cleaned value is forwarded to the internal backend.

The public runtime therefore owns orchestration, not policy definition and not
storage mechanics.

## Performance Documentation

The performance documentation is intentionally split by responsibility.

- `docs/performance/README.md` is the entry point for the performance document set.
- `docs/performance/methodology.md` defines execution procedure and artifact workflow.
- `docs/performance/benchmark-matrix.md` defines benchmark inventory and canonical cases.
- `docs/performance/interpretation-guide.md` defines result-reading and reporting rules.

This split keeps benchmark governance separate from package contract, lifecycle
semantics, and architectural structure.

## Why the Backend Is Internal

The backend is intentionally hidden under `internal/`.

That boundary exists because:

1. backend choice is not part of the public contract;
2. low-level storage mechanics should not leak into the public runtime API;
3. `sync.Pool`-specific typing and panic paths belong in a tightly scoped implementation layer;
4. the public runtime should depend on a storage capability, not on a backend brand.

Callers should reason in terms of lifecycle policy and the public runtime, not
in terms of backend selection.

## File-Level Responsibilities

### `doc.go`

Package contract for Go users and pkg.go.dev.

### `options.go`

Lifecycle policy definition and normalization.

### `lifecycle.go`

Canonical return-path semantics.

### `pool.go`

Public runtime assembly and public `Get`/`Put` API.

### `pool_*_benchmark_test.go`

Benchmark families for baselines, lifecycle paths, value shapes, parallel
execution, compare surfaces, and metric-oriented runs.

### `internal/backend/syncpool.go`

Thin internal backend over `sync.Pool`.

### `internal/testutil/*.go`

Reusable test and benchmark support shared across repository test packages.

### `docs/architecture.md`

Repository structure and architectural boundaries.

### `docs/lifecycle.md`

Normative lifecycle and ownership semantics.

### `docs/non-goals.md`

Normative scope-boundary document.

### `docs/performance/README.md`

Index for the performance document set.

### `docs/performance/methodology.md`

Procedural benchmark methodology.

### `docs/performance/benchmark-matrix.md`

Benchmark inventory and canonical suite definition.

### `docs/performance/interpretation-guide.md`

Rules for reading and reporting finished results.

### `docs/performance/reports/README.md`

Contract for committed performance reports.

## Testing Structure

The test layout follows the runtime layering.

### Root package tests

Files:

- `options_test.go`
- `lifecycle_test.go`
- `pool_test.go`

These verify:

- policy resolution;
- lifecycle semantics;
- public runtime behavior and integration.

### Internal backend tests

Files:

- `internal/backend/syncpool_test.go`

These verify:

- backend-only behavior;
- constructor miss paths;
- typed storage invariants;
- backend-specific panic conditions.

### Shared test support

Files:

- `internal/testutil/assertions.go`
- `internal/testutil/benchmark.go`
- `internal/testutil/metrics.go`
- `internal/testutil/payload.go`
- `internal/testutil/recording.go`
- `internal/testutil/runtime.go`

This package exists so reusable test and benchmark helpers remain shared
infrastructure instead of being duplicated across packages.

It intentionally remains one internal package with file-level separation rather
than several tiny subpackages. The helpers are usually imported together by
tests and benchmarks, so splitting them further would add import noise without
improving runtime architecture.

## Benchmark Source Layout

Benchmark source files SHOULD live next to the packages they benchmark.

That means:

- benchmarks for the public runtime belong next to `pool.go`;
- benchmarks for the internal backend belong next to `internal/backend/syncpool.go`.

Generated artifacts such as profiles, charts, and reports SHOULD remain outside
package source layout.

- raw artifacts and automation belong under `bench/`;
- performance governance documents belong under `docs/performance/`;
- these files MUST NOT be mixed into the runtime API surface.

## Architectural Change Boundaries

The architecture should evolve conservatively.

Changes that are structurally compatible with the current design include:

- improving tests and benchmarks without changing the public runtime model;
- refining internal backend implementation details while preserving the public contract;
- adding documentation or internal instrumentation that stays below the public API boundary.

Changes that should be treated as architectural scope changes include:

- moving lifecycle policy into the backend;
- making backend selection part of the public API;
- introducing mandatory interfaces for `T`;
- adding public coordination concepts such as leases, tokens, or scheduler semantics;
- turning test support into a runtime dependency.

Detailed product exclusions live in `docs/non-goals.md`. This section exists
only to state the architectural consequence of crossing those boundaries.

## Summary

The architecture of `arcoris.dev/pool` is intentionally small and layered.

- `options.go` defines lifecycle policy.
- `lifecycle.go` defines return-path semantics.
- `pool.go` defines the public runtime.
- `internal/backend/syncpool.go` provides the internal backend.
- `internal/testutil/*.go` supports tests and benchmarks without leaking into runtime.

That separation keeps the package easy to read, easy to test, and easier to
change conservatively over time.
