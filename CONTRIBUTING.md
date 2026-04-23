<div align="center">

# Contributing to `arcoris.dev/pool`

**Contributor guide for a small, policy-driven Go runtime with benchmark-grade evidence and repository-grade documentation.**

[![Start Here](https://img.shields.io/badge/Start-Docs%20Index-0F766E?style=flat)](docs/index.md)
[![Package Contract](https://img.shields.io/badge/Contract-doc.go-1D4ED8?style=flat)](doc.go)
[![PR Template](https://img.shields.io/badge/Review-PR%20Template-0F172A?style=flat)](.github/PULL_REQUEST_TEMPLATE.md)
[![Performance](https://img.shields.io/badge/Evidence-Benchmark%20Workflow-B45309?style=flat)](docs/performance/README.md)

[Start Here](#start-here) · [Contribution Routes](#contribution-routes) · [Repository Ground Rules](#repository-ground-rules) · [Validation](#validation-by-change-type) · [Performance Evidence](#performance-and-benchmark-evidence) · [Pull Requests](#pull-requests)

Small scope · Explicit lifecycle semantics · Human-readable docs · Evidence-backed performance work

**Read by change type:** [Runtime](docs/lifecycle.md) · [Scope](docs/non-goals.md) · [Architecture](docs/architecture.md) · [Benchmark workflow](docs/performance/methodology.md) · [PR expectations](.github/PULL_REQUEST_TEMPLATE.md)

</div>

`arcoris.dev/pool` is intentionally small. The package exposes a narrow public
runtime, keeps lifecycle policy explicit, treats benchmark artifacts as real
engineering evidence, and expects documentation to stay aligned with code.

That means a strong contribution here is usually focused, well-scoped, and
careful about contracts. A weak contribution usually widens the package into a
larger framework, hides lifecycle behavior behind abstraction, or makes broad
claims without repository evidence.

## Start here

| If you want to... | Read first | Then continue with |
| --- | --- | --- |
| understand the package before changing code | [README](README.md) | [Package contract](doc.go), [Lifecycle guide](docs/lifecycle.md) |
| change runtime or ownership behavior | [Lifecycle guide](docs/lifecycle.md) | [Non-goals guide](docs/non-goals.md), [Architecture guide](docs/architecture.md) |
| propose a scope or contract change | [Non-goals guide](docs/non-goals.md) | [Package contract](doc.go), [design proposal form](.github/ISSUE_TEMPLATE/03-design-proposal.yml) |
| work on benchmarks, charts, or reports | [Performance overview](docs/performance/README.md) | [Benchmark methodology](docs/performance/methodology.md), [Benchmark matrix](docs/performance/benchmark-matrix.md), [Interpretation guide](docs/performance/interpretation-guide.md) |
| improve docs or navigation | [Docs index](docs/index.md) | [README](README.md), this guide |
| prepare a pull request | [PR template](.github/PULL_REQUEST_TEMPLATE.md) | [Validation by change type](#validation-by-change-type) |

## Contribution routes

Choose the smallest route that matches the work.

| Route | Use it for | Reference |
| --- | --- | --- |
| Bug report | reproducible defects in runtime behavior, ownership, docs, or tooling | [01-bug-report.yml](.github/ISSUE_TEMPLATE/01-bug-report.yml) |
| Feature request | scoped improvements that fit the current product boundaries | [02-feature-request.yml](.github/ISSUE_TEMPLATE/02-feature-request.yml) |
| Design proposal | public contract changes, lifecycle changes, benchmark methodology changes, or larger repository structure changes | [03-design-proposal.yml](.github/ISSUE_TEMPLATE/03-design-proposal.yml) |
| Documentation issue | wrong, stale, confusing, or missing docs | [04-docs-issue.yml](.github/ISSUE_TEMPLATE/04-docs-issue.yml) |
| Contract clarification | narrow maintainer questions about semantics, compatibility, or benchmark interpretation | [05-contract-question.yml](.github/ISSUE_TEMPLATE/05-contract-question.yml) |

Open a design proposal before coding if the change would:

- alter `Get` or `Put` semantics;
- change callback ordering or ownership rules;
- introduce new coordination concepts such as leases, borrow tracking, or inventory semantics;
- redefine the benchmark evidence model or stable suite vocabulary;
- materially change the repository documentation architecture.

## Repository ground rules

### 1. Keep the public runtime narrow

The package is intentionally centered on:

- `Pool[T]`;
- explicit `Get` / `Put` ownership transfer;
- callback-based lifecycle policy in `Options[T]`;
- an internal backend that is not part of the public contract.

Contributions should preserve that narrowness unless a design-level change is
explicitly proposed and justified.

### 2. Preserve lifecycle behavior explicitly

The lifecycle contract is not an implementation detail. Contributions must
preserve or clearly document any change to:

- acquisition behavior;
- return-path ordering;
- reset and reuse interaction;
- drop observation semantics;
- ownership transfer at `Get` and `Put`.

The canonical order today is:

1. evaluate `Reuse`;
2. call `OnDrop` and stop when reuse is denied;
3. call `Reset` only for accepted values;
4. store only already-clean retained values.

If your change affects this area, [docs/lifecycle.md](docs/lifecycle.md) and
[doc.go](doc.go) are part of the change.

### 3. Respect the product boundaries

`arcoris.dev/pool` is a typed temporary-object reuse runtime, not a general
resource manager and not a broad pooling framework. Changes are usually out of
scope when they add:

- stable inventory or cache guarantees;
- lease tokens or runtime borrow tracking as a core feature;
- queue, scheduler, semaphore, or coordination semantics;
- mandatory package-owned interfaces on `T`;
- framework-style abstraction layers that do not strengthen the current model.

When in doubt, use [docs/non-goals.md](docs/non-goals.md) as the boundary
document.

### 4. Treat benchmark artifacts as evidence

Performance work in this repository is first-class engineering work, not
presentation-only work. Strong performance claims should be backed by:

- repeated raw benchmark artifacts;
- matching environment capture;
- comparison output when revisions are compared;
- charts only when they help explain evidence;
- a report when the claim is substantial enough to deserve one.

Local exploratory numbers are useful during development, but they are not
repository-grade evidence by themselves.

### 5. Keep documentation synchronized

This repository treats documentation as maintained surface area. If a change
affects semantics, workflow, or navigation, update the affected docs in the
same change or call out the follow-up explicitly in the PR.

At minimum, keep these entry points consistent when navigation changes:

- [README](README.md);
- [Docs index](docs/index.md);
- [Contributing guide](CONTRIBUTING.md);
- [Security policy](SECURITY.md);
- [Code of Conduct](CODE_OF_CONDUCT.md);
- the relevant document inside [docs/](docs/).

## Repository map

| Area | Role |
| --- | --- |
| [README](README.md) | public landing page and first-stop package overview |
| [Package contract (`doc.go`)](doc.go) | Go-facing package contract and runtime model |
| [Contributing guide](CONTRIBUTING.md) | contributor workflow, validation, and repository expectations |
| [Security policy](SECURITY.md) | vulnerability reporting path, supported-version policy, and repo-specific security scope |
| [Code of Conduct](CODE_OF_CONDUCT.md) | repository collaboration standards, reporting expectations, and moderation baseline |
| [Third-Party Notices](THIRD_PARTY_NOTICES.md) | attribution record for adapted upstream material and pinned third-party tooling references |
| [Architecture guide](docs/architecture.md) | structure, layering, and dependency boundaries |
| [Lifecycle guide](docs/lifecycle.md) | normative lifecycle and ownership semantics |
| [Non-goals guide](docs/non-goals.md) | scope boundaries and proposal limits |
| [Performance overview](docs/performance/README.md) | benchmark/report entry point |
| [Benchmark scripts](bench/scripts/) | repeatable benchmark, compare, profile, and chart tooling |
| [Internal backend](internal/backend/) | storage implementation details behind the public runtime |
| [Test utilities](internal/testutil/) | shared helpers for tests and benchmarks |
| [Issue forms](.github/ISSUE_TEMPLATE/) | structured issue intake |
| [PR template](.github/PULL_REQUEST_TEMPLATE.md) | required review and validation shape for pull requests |

## Local setup

### Toolchain baseline

The module baseline is defined in [go.mod](go.mod):

- minimum Go version: `1.25.0`;
- preferred toolchain: `go1.25.9`.

Stay on one Go version when collecting comparison-quality benchmark evidence.

### Python tooling for charts

If you touch [plot_benchmarks.py](bench/scripts/plot_benchmarks.py) or
generate charts locally, use the Python dependencies listed in
[requirements.txt](requirements.txt).

### Local validation baseline

Treat local validation as required even when CI is unavailable, incomplete, or
still being formalized.

For code changes, the practical baseline is:

```bash
go test ./...
go test -race ./...
go vet ./...
```

If lint configuration is part of the repository state you are working against,
run it locally when relevant. When [.golangci.yml](.golangci.yml) is present,
`golangci-lint run` is the expected local lint entrypoint.

## Validation by change type

Use the minimum validation that matches the work. More is welcome when the
change is risky.

| Change type | Minimum validation | Also update when needed |
| --- | --- | --- |
| Runtime, lifecycle, or backend change | `go test ./...`, `go test -race ./...`, `go vet ./...` | [doc.go](doc.go), [README](README.md), [docs/lifecycle.md](docs/lifecycle.md), [docs/architecture.md](docs/architecture.md) |
| Test-only change | run the affected test package plus `go test ./...` when practical | comments or helper docs if test terminology changed |
| Documentation-only change | verify links, anchors, file names, benchmark names, and embedded chart paths | any adjacent nav docs that should still point to the changed file |
| Benchmark source change | ensure the benchmark compiles and the affected case or suite runs | [docs/performance/benchmark-matrix.md](docs/performance/benchmark-matrix.md), possibly [docs/performance/interpretation-guide.md](docs/performance/interpretation-guide.md) |
| Benchmark script change | validate the changed script path, arguments, output naming, and artifact paths | [docs/performance/methodology.md](docs/performance/methodology.md) |
| Chart tooling change | validate the relevant chart mode and rendered output naming | [docs/performance/methodology.md](docs/performance/methodology.md), reports if curated outputs changed |
| Report or benchmark-interpretation change | verify artifact links and factual consistency against raw evidence | [docs/performance/reports/](docs/performance/reports/), [docs/performance/interpretation-guide.md](docs/performance/interpretation-guide.md) |
| Repository metadata change (`.github/`, release/lint config, docs navigation) | validate rendered Markdown or YAML shape and the affected local workflow | [CONTRIBUTING.md](CONTRIBUTING.md), [README](README.md), [docs/index.md](docs/index.md) when contributor routes changed |

### Documentation-specific checks

For docs-only work, explicitly check:

- descriptive link text instead of raw relative-path labels;
- correct file and section names;
- benchmark family names that match the maintained suite vocabulary;
- chart image paths that still resolve from the current document;
- contributor navigation that still reaches the right document.

### Benchmark-script checks

For script changes, validate the exact behavior you touched. Typical checks are:

- `--help` output;
- required vs optional flags;
- output artifact names;
- artifact directory layout;
- interaction with [paths.sh](bench/scripts/paths.sh);
- compatibility with the terminology in
  [docs/performance/methodology.md](docs/performance/methodology.md).

## Performance and benchmark evidence

### Exploratory vs repository-grade work

Use exploratory benchmark runs while shaping code, but do not present them as a
finished repository claim without context.

Repository-grade evidence usually means:

- repeated raw outputs in [bench/raw/](bench/raw/);
- matching environment capture files;
- compare output in [bench/compare/](bench/compare/) when revisions are compared;
- charts in [bench/charts/](bench/charts/) only when they improve readability;
- a curated report in [docs/performance/reports/](docs/performance/reports/)
  when the claim deserves preservation.

### Artifact commit policy

The repository intentionally keeps most benchmark artifacts untracked by
default. See [.gitignore](.gitignore) and the performance docs for the current
policy.

Practical rule:

- throwaway raw outputs, compare outputs, profiles, and generated charts
  usually stay local;
- curated human-authored documentation and reports may be committed;
- performance claims in a PR should still reference the local artifacts used to
  produce the conclusion.

### Canonical workflows

Current-state snapshot:

```bash
bench/scripts/capture_env.sh --output bench/raw/<snapshot>.env.txt
bench/scripts/run_benchmarks.sh --suite all --name <snapshot> --count 10
python3 bench/scripts/plot_benchmarks.py --mode snapshot --input bench/raw/<snapshot>.txt
```

Revision-to-revision comparison:

```bash
bench/scripts/capture_env.sh --output bench/raw/<baseline>.env.txt
bench/scripts/run_benchmarks.sh --suite all --name <baseline> --count 10
bench/scripts/capture_env.sh --output bench/raw/<candidate>.env.txt
bench/scripts/run_benchmarks.sh --suite all --name <candidate> --count 10

bench/scripts/compare_benchmarks.sh \
  --old bench/raw/<baseline>.txt \
  --new bench/raw/<candidate>.txt \
  --name <baseline-vs-candidate>

bench/scripts/compare_benchmarks.sh \
  --old bench/raw/<baseline>.txt \
  --new bench/raw/<candidate>.txt \
  --name <baseline-vs-candidate> \
  --format csv

python3 bench/scripts/plot_benchmarks.py \
  --input bench/compare/<baseline-vs-candidate>.csv
```

Focused profiling:

```bash
bench/scripts/profile_benchmarks.sh \
  --bench '^BenchmarkParallel_' \
  --name <profile-set>
```

For the authoritative workflow and vocabulary, use
[docs/performance/methodology.md](docs/performance/methodology.md).

## Documentation synchronization rules

### Update the right document, not every document

Keep each document responsible for its own job:

- [README](README.md) is the public landing page;
- [doc.go](doc.go) is the package-facing contract;
- [docs/lifecycle.md](docs/lifecycle.md) is the lifecycle authority;
- [docs/non-goals.md](docs/non-goals.md) is the scope-boundary authority;
- [docs/performance/README.md](docs/performance/README.md) and adjacent files
  own the benchmark/report workflow.

Do not fix documentation drift by duplicating the same explanation everywhere.

### Prefer semantic link labels

Good:

- [Lifecycle guide](docs/lifecycle.md)
- [Raw artifacts directory](bench/raw/)
- [Benchmark scripts directory](bench/scripts/)

Avoid visible labels that expose raw path mechanics instead of meaning:

- ``docs/lifecycle.md`` as the only navigation cue;
- `../../../bench/raw/...` as the human-facing label.

### Keep names aligned with the codebase

When docs mention repository entities, keep them synchronized with the actual
files and vocabulary:

- benchmark family names;
- script names and flags;
- report file names;
- chart file names;
- directory names;
- issue or PR workflow labels.

## Pull requests

Use focused pull requests with one logical change whenever possible.

Good PR shapes:

- one runtime fix;
- one documentation pass;
- one benchmark-family refinement;
- one tooling change;
- one report publication;
- one repository metadata change set.

Avoid mixing unrelated runtime, docs, automation, and reporting work unless the
repository would be harder to review if split apart.

When opening a PR:

- use the [PR template](.github/PULL_REQUEST_TEMPLATE.md);
- link the relevant issue or design proposal when one exists;
- name the affected contract or benchmark surface precisely;
- describe what is explicitly out of scope;
- include the exact validation you ran;
- attach performance evidence when the PR makes a performance claim.

## Commit messages

Use concise Conventional Commit style messages with repository-meaningful
scopes.

Examples:

- `fix(pool): preserve reuse denial before reset`
- `docs(lifecycle): clarify post-Put ownership boundary`
- `test(backend): cover sync.Pool miss path invariants`
- `docs(performance): update benchmark matrix naming`
- `refactor(bench): centralize artifact path handling`

Avoid vague messages such as:

- `fix stuff`
- `update files`
- `cleanup`

## Reviewer expectations

Maintainers review for:

- scope alignment;
- lifecycle correctness;
- ownership clarity;
- code and doc consistency;
- benchmark discipline;
- long-term maintainability.

A change may be rejected even when it "works" if it:

- broadens the product without justification;
- weakens lifecycle clarity;
- hides important behavior behind abstraction;
- adds unsupported performance claims;
- leaves documentation more ambiguous than before.

## Security and provenance

Do not open a public bug report first if the issue may be security-sensitive.
Use the repository's private vulnerability reporting route instead of the
public issue forms.

For this package, security-relevant issues can include:

- stale data exposure through reuse;
- ownership confusion after `Put`;
- concurrency misuse caused by incorrect runtime behavior;
- documentation that could lead callers to unsafe assumptions.

If you copy or adapt third-party material:

- state that explicitly in the PR;
- preserve attribution when required;
- make sure the license is compatible;
- do not paste external code or text silently.

## Getting help

When you are unsure where to start:

1. read [README](README.md) and [Docs index](docs/index.md);
2. read the narrow authority document for the area you are changing;
3. choose the smallest issue route from [Issue forms](.github/ISSUE_TEMPLATE/);
4. open a focused PR using the [PR template](.github/PULL_REQUEST_TEMPLATE.md).

## Summary

A strong contribution to `arcoris.dev/pool` is:

- small in scope;
- explicit about behavior and limits;
- validated proportionally to the change;
- synchronized with the relevant documentation;
- and, for performance work, supported by real repository evidence.
