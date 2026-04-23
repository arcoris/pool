# Benchmark Methodology

## Contents

- [Purpose](#purpose)
- [Canonical Tooling](#canonical-tooling)
- [Toolchain Baseline](#toolchain-baseline)
- [Runtime Modes](#runtime-modes)
- [Shell Suite Selectors](#shell-suite-selectors)
- [Artifact Layout](#artifact-layout)
- [Scripted Workflow](#scripted-workflow)
- [Run Intents](#run-intents)
- [Environment Control](#environment-control)
- [Comparison Policy](#comparison-policy)
- [Parallel CPU Matrix Policy](#parallel-cpu-matrix-policy)
- [Profile Policy](#profile-policy)
- [Methodology Changes](#methodology-changes)

## Purpose

This document defines the operational procedure for collecting
comparison-quality benchmark data for `arcoris.dev/pool`.

It covers:

- how benchmark runs are executed;
- how artifacts are laid out;
- how repeated raw outputs are compared;
- how profiles are captured;
- how charts are generated from compare-oriented CSV or curated raw snapshots;
- how CPU matrices are selected for parallel work.

Benchmark selection belongs in the [Benchmark Matrix](./benchmark-matrix.md).
Result-reading rules belong in the
[Interpretation Guide](./interpretation-guide.md).

## Canonical Tooling

The canonical toolchain is:

- `go test` for benchmark execution;
- `-benchmem` for allocation metrics;
- `benchstat` for repeated-run comparison;
- `go test -cpuprofile` and `-memprofile` for diagnostic profiles;
- scripts in the [benchmark scripts directory](../../bench/scripts/) for repeatable execution, artifact capture, and chart generation.

If another tool is used, the report MUST explain how its output maps back to
this workflow.

`benchstat` is required only for compare steps. Collection and profiling do not
depend on it.

## Toolchain Baseline

The module minimum is Go `1.25.0`.
The preferred repository toolchain is `go1.25.9`.

Comparison-quality runs SHOULD stay on one Go toolchain version for the entire
campaign.
If a report compares runs collected with different Go versions, that fact MUST
be stated explicitly.

## Runtime Modes

The repository uses three benchmark runtime modes.
Every report MUST name the mode of the cases it cites.

### Controlled serial hot path

Characteristics:

- single P;
- automatic GC disabled for the timed body;
- immediate reuse path primed before timing;
- minimal steady-state local-cache reuse.

Use this mode only when the question is local hot path reuse cost.
It is an upper-bound microbenchmark mode, not a general runtime mode.

### Realistic serial path

Characteristics:

- ordinary serial runtime;
- no forced single-P execution;
- no forced GC suppression;
- optional one-time priming only when it makes the scenario definition clearer.

Use this mode for serial policy paths, mixed reuse workloads, and steady-state
behaviour that should include ordinary runtime effects.

### Realistic parallel path

Characteristics:

- `testing.B.RunParallel`;
- ordinary scheduler and GC;
- optional prefill to avoid measuring a completely cold pool;
- optional `-cpu` matrix exploration.

Use this mode for contention-sensitive behaviour and parallel scaling work.

## Shell Suite Selectors

The shell tooling exposes a stable suite vocabulary through
[`run_benchmarks.sh`](../../bench/scripts/run_benchmarks.sh).

Those suite names are part of the performance-layer contract and SHOULD be
described with the same terminology used in the benchmark docs:

| Suite | Meaning |
| --- | --- |
| `all` | the full maintained benchmark suite |
| `controlled-serial` | controlled serial hot-path cases across benchmark families |
| `realistic-serial` | operational serial scenarios without forced single-P or GC suppression |
| `parallel` | realistic parallel benchmark cases |
| `compare` | grouped compare surfaces used for report-friendly compare output |
| `backend` | backend-only lower-bound benchmark family |
| `baselines` | allocation versus raw `sync.Pool` versus public-runtime baselines |
| `paths` | lifecycle-path family |
| `shapes` | type-shape sensitivity family |
| `metrics` | metric-emitting family for `news/op`, `drops/op`, and `reuse_denials/op` |

Use these shell suite names when describing how artifacts were collected.
Use the execution-class vocabulary above when describing what kind of evidence a
benchmark result represents.

## Artifact Layout

Benchmark artifacts live under the [benchmark workspace (`bench/`)](../../bench/):

- [Raw artifacts directory](../../bench/raw/) for raw benchmark output and matching environment captures;
- [Comparison artifacts directory](../../bench/compare/) for `benchstat` output and optional CSV comparison data;
- [Profiles directory](../../bench/profiles/) for CPU and memory profiles and matching environment captures;
- [Charts directory](../../bench/charts/) for generated chart artifacts, including compare charts and curated snapshot charts;
- [Benchmark scripts directory](../../bench/scripts/) for reproducible entrypoint scripts and shared sourced shell modules.

Reports SHOULD live under the [performance reports directory](./reports/).

Artifact policy:

- the repository keeps directory structure and scripts under version control;
- throwaway raw outputs, comparisons, profiles, and generated charts SHOULD
  stay untracked;
- curated human-authored reports MAY be committed under
  the [performance reports directory](./reports/).

## Scripted Workflow

### 1. Optional orchestration entrypoint

For a multi-step campaign, the orchestration script can compose the narrower
tools in one command:

```bash
bench/scripts/run_performance_pipeline.sh campaign \
  --suite all \
  --name <candidate> \
  --compare-old bench/raw/<baseline>.txt
```

Use the narrower scripts directly when you want only one step of the workflow.

The orchestration script currently composes raw collection, comparison, and
profiling. Chart generation remains an explicit separate step.

### 2. Capture or refresh environment metadata

```bash
bench/scripts/capture_env.sh --output bench/raw/<name>.env.txt
```

### 3. Collect repeated raw outputs

Canonical full-suite run:

```bash
bench/scripts/run_benchmarks.sh --suite all --name <name> --count 10
```

Focused group run:

```bash
bench/scripts/run_benchmarks.sh --suite shapes --name <name> --count 10
```

Focused realistic accepted serial path:

```bash
bench/scripts/run_benchmarks.sh \
  --bench '^BenchmarkPaths_RealisticAccepted$' \
  --name <name> \
  --count 10
```

Parallel CPU-matrix run:

```bash
bench/scripts/run_benchmarks.sh --suite parallel --name <name> --count 10
```

The parallel script default includes more than one CPU count and always
includes the full logical CPU count of the machine.

### 4. Compare repeated runs

Text comparison:

```bash
bench/scripts/compare_benchmarks.sh \
  --old bench/raw/<old>.txt \
  --new bench/raw/<new>.txt \
  --name <comparison>
```

CSV comparison for chart work:

```bash
bench/scripts/compare_benchmarks.sh \
  --old bench/raw/<old>.txt \
  --new bench/raw/<new>.txt \
  --name <comparison> \
  --format csv
```

### 5. Generate charts when needed

```bash
python3 bench/scripts/plot_benchmarks.py \
  --input bench/compare/<comparison>.csv
```

```bash
python3 bench/scripts/plot_benchmarks.py \
  --mode snapshot \
  --input bench/raw/<snapshot>.txt
```

Chart rules:

- chart generation is optional and presentation-oriented;
- [`plot_benchmarks.py`](../../bench/scripts/plot_benchmarks.py) reads either
  compare-oriented CSV or raw snapshot input
  and writes chart artifacts under the [charts directory](../../bench/charts/) by default;
- snapshot charts aggregate repeated raw samples before rendering and group the
  output by family and metric;
- the script loads canonical repository paths from
  [`bench/scripts/paths.sh`](../../bench/scripts/paths.sh),
  so chart output follows the same path model as the shell tooling layer.

### 6. Capture profiles for a focused question

```bash
bench/scripts/profile_benchmarks.sh \
  --bench '^BenchmarkCompare_Parallel/' \
  --name <profile-set>
```

Profile package rules:

- profile runs must target exactly one package;
- when `--packages` is omitted, the script infers
  [the repository root package](../../) for root benchmarks and
  [the internal backend package](../../internal/backend/) for backend-only benchmarks;
- wildcard package patterns such as `./...` are intentionally rejected for
  profiling because `go test -cpuprofile` and `-memprofile` do not support
  multi-package runs.

Script responsibilities:

- [`run_benchmarks.sh`](../../bench/scripts/run_benchmarks.sh) collects raw benchmark output and matching environment captures;
- [`compare_benchmarks.sh`](../../bench/scripts/compare_benchmarks.sh) compares repeated raw runs and can emit chart-ready CSV;
- [`profile_benchmarks.sh`](../../bench/scripts/profile_benchmarks.sh) captures CPU and memory profiles for one benchmark pattern in one package;
- [`capture_env.sh`](../../bench/scripts/capture_env.sh) writes standalone environment metadata without running benchmarks;
- [`run_performance_pipeline.sh`](../../bench/scripts/run_performance_pipeline.sh) orchestrates run, compare, and profile steps without reimplementing them;
- [`plot_benchmarks.py`](../../bench/scripts/plot_benchmarks.py) converts compare-oriented CSV or raw snapshot artifacts into chart artifacts.

## Run Intents

### Exploratory

Use exploratory runs for local investigation and benchmark shaping.
They MAY use low counts and MAY skip archival.
They MUST NOT be treated as report-quality evidence.

### Comparison

Use comparison runs when evaluating revisions, implementations, or policy
changes.
Comparison runs MUST:

- use repeated raw output;
- archive the raw files;
- compare those raw files with `benchstat`;
- archive matching environment data.

### Diagnostic

Use diagnostic runs when a measured change needs explanation.
Diagnostic runs SHOULD reuse the same benchmark pattern as the associated
comparison run and SHOULD capture profiles from the same revision and machine.

## Environment Control

Every comparison-quality run MUST record:

- revision identifier;
- Go version;
- `GOOS` and `GOARCH`;
- CPU model;
- logical CPU count;
- effective `GOMAXPROCS` setting or CPU matrix;
- exact benchmark command line;
- date and time.

Comparison-quality runs SHOULD:

- use the same machine for before and after runs;
- avoid unrelated heavy workloads;
- avoid thermal throttling and unstable power modes;
- state explicitly when a cross-machine comparison was unavoidable.

## Comparison Policy

Comparison-quality runs SHOULD use `-count 10` unless a report explains a
different choice.

Comparison rules:

- compare like with like;
- keep the benchmark pattern unchanged across the comparison unless the pattern
  change is the subject of the work;
- keep the execution class attached to the result;
- keep the Go toolchain version attached to the result;
- do not compare controlled serial hot path data to realistic serial or
  realistic parallel data as if they were the same class of evidence;
- keep raw files next to the comparison artifact that depends on them.
- when generating compare charts, keep the chart linked to the comparison CSV
  that produced it rather than treating the chart as primary evidence;
- when generating snapshot charts, keep the chart linked to the raw snapshot
  artifact and environment capture that produced it.

## Parallel CPU Matrix Policy

Parallel work SHOULD use more than one CPU count when the question is scaling
or scheduler sensitivity.

The default matrix used by the scripts is:

- `1`;
- `2`, when available;
- `4`, when available;
- half of the logical CPUs, when distinct;
- all logical CPUs.

A report MUST record the exact `-cpu` matrix it used.

## Profile Policy

Profiles are explanatory artifacts.
They SHOULD be captured only after benchmark results identify a concrete
question.

Profile rules:

- profile one benchmark family or one report question at a time;
- record the benchmark pattern used for the profile;
- keep CPU and memory profiles as raw artifacts under the [profiles directory](../../bench/profiles/);
- keep profile claims subordinate to the benchmark comparison that motivated
  them.

## Methodology Changes

Methodology changes SHOULD preserve historical comparability.

When changing methodology:

- prefer additive script or artifact changes over silent replacement;
- record substantial methodology changes in the first report that uses them;
- avoid changing multiple experimental variables at once unless that is the
  subject of the investigation;
- keep script entry points and artifact locations stable when possible.
