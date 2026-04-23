<div align="center">

# Third-Party Notices

**Attribution and notice record for third-party material included in, adapted into, or explicitly pinned by this repository.**

[![Repository License](https://img.shields.io/badge/License-Apache%202.0-0F766E?style=flat)](LICENSE)
[![Contributing](https://img.shields.io/badge/Guide-Contributing-1D4ED8?style=flat)](CONTRIBUTING.md)
[![Docs Index](https://img.shields.io/badge/Docs-Index-0F172A?style=flat)](docs/index.md)

[Scope](#scope) · [Repository Status](#current-repository-status) · [Included Material](#included-or-adapted-material) · [External Tooling](#external-tooling-references) · [Maintenance](#maintenance-rules)

Included material · Pinned tooling references · Current dependency status · Preserved upstream notices

**Start:** [Scope](#scope) · [Included or adapted material](#included-or-adapted-material) · [Go module status](#go-module-dependency-status) · [Python tooling references](#python-chart-tooling-references-not-vendored) · [Maintenance rules](#maintenance-rules)

</div>

This file is the repository notice ledger for third-party material that is
actually present in the source tree, adapted into repository-owned files, or
explicitly pinned as part of the maintained developer tooling surface.

It is meant to answer three questions:

- what upstream material is directly included or adapted in this repository;
- what external tooling is pinned or referenced by maintained files but not
  vendored into the source tree;
- what should be updated when new third-party material is added later.

## Scope

This file distinguishes between three kinds of third-party relationship:

1. included or adapted material
   third-party content copied into, derived into, or materially adapted inside
   a repository file;
2. pinned external tooling references
   external packages or tools named in maintained repository files such as
   `requirements.txt`, scripts, or contributor guidance, but not committed as
   source into this repository;
3. current dependency status
   explicit statements about what the repository does or does not currently
   vendor or declare as module dependencies.

This file does **not** attempt to reproduce notice text for:

- system packages installed outside the repository;
- transient local tools a contributor happens to use;
- upstream packages that are not pinned or referenced by maintained repository
  files;
- GitHub-hosted services or infrastructure integrations that are not shipped as
  source in this tree.

## Current repository status

| Area | Current state |
| --- | --- |
| Repository license | [Apache License 2.0](LICENSE) |
| Go module dependencies in [go.mod](go.mod) | no non-standard-library module requirements are currently declared |
| Included or adapted third-party material | [`.golangci.yml`](.golangci.yml) derived from `maratori/golangci-lint-config` |
| Pinned Python chart tooling | packages listed in [requirements.txt](requirements.txt) for local chart generation |
| External developer tools referenced by maintained files | `benchstat` and `golangci-lint` are referenced, but not vendored |

## Included or adapted material

The following material is directly present in or adapted into the repository
source tree and therefore needs preserved attribution.

| Material | Repository path | Upstream source | Upstream license | Repository status |
| --- | --- | --- | --- | --- |
| maratori golangci-lint config | [`.golangci.yml`](.golangci.yml) | <https://github.com/maratori/golangci-lint-config> | MIT | adapted for repository-specific lint policy |

### maratori/golangci-lint-config

Repository path:

- [`.golangci.yml`](.golangci.yml)

Upstream source:

- <https://github.com/maratori/golangci-lint-config>

Why it appears here:

- the repository lint configuration is based on upstream work by Marat Reimers;
- the repository version has been modified for ARCORIS Pool-specific needs;
- the upstream attribution is preserved both in the file header and in this
  notice record.

Upstream notice as preserved in the adapted file:

```text
This file is licensed under the terms of the MIT license https://opensource.org/license/mit
Copyright (c) 2021-2025 Marat Reimers
Based on https://github.com/maratori/golangci-lint-config
```

Upstream license text:

```text
Copyright (c) 2021-2025 Marat Reimers

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Repository note:

- the repository version contains ARCORIS-specific modifications;
- the upstream MIT notice remains preserved because the current file is derived
  from upstream material;
- if the file is replaced with a wholly original configuration in the future,
  this entry should be revisited rather than silently left stale.

## Go module dependency status

As of the current repository state, [go.mod](go.mod) declares:

- the module path `arcoris.dev/pool`;
- the Go baseline `1.25.0`;
- the preferred toolchain `go1.25.9`;
- no non-standard-library module requirements.

That means the repository does not currently vendor or declare third-party Go
module dependencies in its source-level module manifest.

If `go.mod` later gains third-party requirements that are vendored, copied, or
otherwise redistributed in repository-controlled source form, this file should
be updated accordingly.

## External tooling references

These entries are included for transparency because the repository explicitly
pins or references them in maintained files. They are **not** currently
vendored into the source tree by the repository itself.

### Python chart tooling references (not vendored)

The chart-generation workflow depends on Python packages pinned in
[requirements.txt](requirements.txt). Those packages are installed from their
upstream distributions when a contributor sets up the chart environment. Their
source code and full license texts are not committed into this repository by
current source-tree state.

| Package | Pinned version | Why the repository references it |
| --- | --- | --- |
| `matplotlib` | `3.10.8` | chart rendering for [plot_benchmarks.py](bench/scripts/plot_benchmarks.py) |
| `numpy` | `2.4.4` | numeric support for chart generation |
| `contourpy` | `1.3.3` | transitive plotting support used by the chart stack |
| `cycler` | `0.12.1` | plotting style dependency |
| `fonttools` | `4.62.1` | font handling in the plotting stack |
| `kiwisolver` | `1.5.0` | plotting layout dependency |
| `packaging` | `26.1` | version and packaging helpers in the plotting stack |
| `pillow` | `12.2.0` | imaging support used by plotting dependencies |
| `pyparsing` | `3.3.2` | parser dependency used by plotting dependencies |
| `python-dateutil` | `2.9.0.post0` | date utility dependency used by plotting dependencies |
| `six` | `1.17.0` | compatibility helper dependency used by plotting dependencies |

Practical note:

- these packages are part of the maintained chart workflow because they are
  pinned in a repository file;
- this repository currently references them, but does not embed their source
  code in-tree;
- if a future change vendors, copies, or bundles any of these packages into the
  repository, this file should grow from a reference list into a full notice
  record for the included material.

### Standalone developer tools referenced by maintained files (not vendored)

The repository also refers to third-party developer tools that contributors are
expected to obtain from upstream rather than from repository-committed source.

| Tool | Where it is referenced | Current repository relationship |
| --- | --- | --- |
| `benchstat` | [compare_benchmarks.sh](bench/scripts/compare_benchmarks.sh), [Benchmark methodology](docs/performance/methodology.md), [Interpretation guide](docs/performance/interpretation-guide.md) | referenced for benchmark comparison, not vendored |
| `golangci-lint` | [`.golangci.yml`](.golangci.yml), [Contributing guide](CONTRIBUTING.md) | referenced as the expected lint runner when lint config is present, not vendored |

## Repository-generated outputs

The repository may contain generated benchmark charts under [bench/charts/](bench/charts/).
Those charts are repository-generated outputs derived from repository benchmark
artifacts. They are not copied third-party artwork.

Some generated SVG metadata may record the generating tool, for example
Matplotlib. That metadata does not, by itself, mean the chart contents are
third-party source material bundled into the repository. The third-party
relationship in that workflow is the external charting toolchain documented
above.

## Maintenance rules

Update this file when:

- a third-party file, template, config, or text block is copied or adapted into
  the repository;
- a third-party package or tool becomes pinned in a way that forms part of the
  maintained contributor or release workflow;
- third-party code or assets are vendored, bundled, or committed into the
  repository source tree;
- an existing upstream-derived file is replaced, removed, or no longer carries
  the original third-party material.

Do **not** update this file just to mention every transient local dependency a
contributor might install manually. Keep it scoped to material that is actually
included, adapted, or explicitly pinned by maintained repository files.

When adding a new entry:

1. identify whether the material is included, adapted, or only externally referenced;
2. link the exact repository path that introduces the relationship;
3. preserve the upstream notice text when the upstream license requires it;
4. describe the repository-specific status clearly, such as “vendored”,
   “adapted”, or “referenced but not vendored”;
5. update adjacent navigation docs if contributors or maintainers should be
   able to find the notice more easily.
