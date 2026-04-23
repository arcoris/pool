<div align="center">

# Security Policy for `arcoris.dev/pool`

**Security guidance for a small Go library where pooled reuse, lifecycle order, ownership transfer, concurrency assumptions, and repository automation matter more than hosted-service perimeter concerns.**

[![Start Here](https://img.shields.io/badge/Start-README-0F766E?style=flat)](README.md)
[![Lifecycle](https://img.shields.io/badge/Contract-Lifecycle-1D4ED8?style=flat)](docs/lifecycle.md)
[![Report](https://img.shields.io/badge/Report-Private%20Path-0F172A?style=flat)](#reporting-a-vulnerability)
[![Conduct](https://img.shields.io/badge/Community-Code%20of%20Conduct-B45309?style=flat)](CODE_OF_CONDUCT.md)

[What Counts Here](#what-security-means-in-this-repository) · [Supported Versions](#supported-versions) · [Reporting](#reporting-a-vulnerability) · [What To Include](#what-to-include-in-a-report) · [Scope](#repository-specific-security-scope) · [Not Security](#what-is-usually-not-a-security-issue) · [Response](#response-expectations) · [Fixes](#fix-and-release-policy)

Private reporting first · Ownership ends at `Put` · Stale reuse can be security-relevant

**Related paths:** [Docs index](docs/index.md) · [Package contract](doc.go) · [Lifecycle guide](docs/lifecycle.md) · [Contributing](CONTRIBUTING.md) · [Code of Conduct](CODE_OF_CONDUCT.md)

</div>

## What security means in this repository

`arcoris.dev/pool` is a small Go library for typed temporary-object reuse.
Security concerns here are tied less to network exposure or hosted service
operation and more to whether pooled values can carry data or authority across
logical boundaries they should not cross.

That makes the main repository-specific security questions:

- can reused values retain stale data or references;
- can a caller still observe or mutate a value after `Put` should have ended
  ownership;
- does the runtime or its documentation create unsafe concurrency assumptions;
- does lifecycle ordering violate the documented contract in a way that creates
  confidentiality or integrity impact;
- does repository automation, release configuration, or supply-chain tooling
  introduce a direct security risk.

This policy covers both runtime issues in the library and repository-level
issues with direct security impact.

## Supported versions

This repository is still early in public release maturity. Security support is
intentionally conservative.

| Version or state | Security fixes normally considered |
| --- | --- |
| latest released version | Yes |
| current default branch (`main`) | Yes |
| older released versions | Usually no |
| historical unreleased snapshots and old commits | No |

Practical notes:

- if there is no current release at the time of the report, `main` is the
  practical maintained state;
- broad backport support should not be assumed;
- the most likely pre-1.0 fix path is a fix on `main`, a new release from the
  maintained branch, or upgrade guidance to the fixed state.

## Reporting a vulnerability

### Preferred path: private GitHub reporting

If the repository Security tab shows a `Report a vulnerability` action, use
that private GitHub flow first.

Practical path:

1. open the repository Security tab;
2. select `Report a vulnerability` if it is available;
3. submit the report privately with the information listed below.

Do **not** open a public issue first for a suspected vulnerability.

### If private reporting is not available

If the repository UI does not offer private vulnerability reporting at the time
you report:

1. do not publish technical details in a public issue, discussion, or pull
   request;
2. use the repository's documented GitHub security contact path at that time.
   In this repository, that may appear as the `Security report` contact link in
   the issue chooser or another non-public route published by maintainers;
3. if no private path is published, open only a minimal public request for a
   private reporting route, with no vulnerability details.

The important rule is simple: do not disclose the vulnerability details in
public before maintainers have had a chance to review them privately.

## What to include in a report

Please include as much of the following as you can:

- affected version, tag, or commit hash;
- Go version;
- operating system and architecture;
- minimal reproduction code or exact reproduction steps;
- expected behavior and actual behavior;
- whether concurrency, timing, or repeated reuse is required to trigger it;
- whether the issue involves pointer-like pooling, value-type pooling, or both;
- whether stale state, retained data, reuse after `Put`, or ownership confusion
  is involved;
- whether lifecycle ordering is relevant, for example reuse admission, reset,
  drop handling, or backend storage order;
- any stack traces, race output, logs, benchmark artifacts, workflow evidence,
  or reports that help explain the impact;
- your assessment of realistic confidentiality, integrity, or misuse impact, if
  you have one.

For this repository, even a small reproduction is especially helpful if it
shows:

- data surviving reuse when it should not;
- a value still being observable after ownership should have ended;
- behavior that contradicts the documented concurrency model;
- unsafe behavior caused by documented guidance rather than by caller abuse
  alone;
- automation or release behavior that could affect artifact trust or repository
  integrity.

## Repository-specific security scope

The following categories are the most likely security-relevant issue classes
for `arcoris.dev/pool`.

### 1. Stale data retention across reuse

Examples:

- sensitive or logically private state survives reset and is visible on a later
  reuse path;
- retained references make previously used data observable in a later logical
  operation;
- package guidance or examples imply that reused values are clean when the
  runtime does not actually guarantee that outcome.

This matters because the package exists specifically to retain and reuse mutable
values. A defect here can become a confidentiality problem, not just a
correctness problem.

### 2. Ownership confusion after `Put`

Examples:

- runtime behavior makes post-`Put` reads or writes appear safe when ownership
  should already be over;
- examples or guidance encourage callers to inspect or mutate a value after
  returning it;
- one logical operation can observe state that should already belong to another
  reuse path.

For this package, ownership ending at `Put` is part of the contract. Bugs or
unsafe guidance around that boundary can have real integrity and confidentiality
impact.

### 3. Concurrency-related misuse surfaces caused by incorrect behavior or guidance

Examples:

- the library behaves inconsistently with its documented concurrency model;
- documentation overstates safety of borrowed values across goroutines;
- concurrent use exposes reused state in a way the contract says should not
  happen.

Not every race-like misuse is a library vulnerability. The important question
is whether the package behavior or package guidance creates an unsafe surface
beyond ordinary caller misuse.

### 4. Lifecycle ordering defects with realistic confidentiality or integrity impact

Examples:

- values are retained when the documented reuse policy says they should be
  dropped;
- reset occurs in the wrong phase and leaves data visible on a later reuse;
- rejected values are still forwarded into backend storage;
- lifecycle hooks run in an order that violates the documented contract and
  creates unsafe state exposure.

For `arcoris.dev/pool`, lifecycle ordering is part of the public behavioral
model. A defect here can be security-relevant if it makes stale or unsafe state
retention realistic.

### 5. Repository supply-chain or automation issues with direct security impact

Examples:

- vulnerable pinned tooling with direct automation or release impact;
- unsafe workflow, release, dependency-review, or scanning configuration;
- integrity problems in repository automation that could compromise released
  artifacts, repository trust, or maintainer workflow.

This repository includes benchmark and report tooling and is moving toward
stronger automation. Tooling or workflow issues are in scope when they have
direct security consequences, not merely because they exist in CI or docs.

## What is usually not a security issue

The following are usually **not** security reports unless they have a real
confidentiality, integrity, or safety consequence:

- documentation typos or editorial cleanup;
- wording problems with no realistic unsafe-use consequence;
- ordinary performance regressions;
- benchmark methodology disagreements;
- chart or report presentation issues;
- allocation-profile changes with no realistic safety impact;
- ordinary feature requests;
- generic correctness bugs with no realistic security impact.

This distinction matters for this repository because:

- not every misuse after `Put` is a vulnerability if the package contract was
  already clear and the runtime behaved correctly;
- not every concurrency bug report is security-relevant if it is only a caller
  violating the documented model;
- not every benchmark, chart, or tooling complaint belongs in the private
  disclosure channel.

If the issue is not security-relevant, use the normal issue or PR path instead.

## Response expectations

This is a small maintainer-run open-source repository. Response targets are
goals, not guarantees.

| Stage | Target |
| --- | --- |
| acknowledgment | within 7 days |
| initial triage | within 14 days |
| fix and disclosure coordination | depends on complexity, impact, and maintainer availability |

Maintainers will try to:

- acknowledge receipt;
- determine whether the report is in scope;
- assess affected versions or repository states;
- share fix, mitigation, or upgrade guidance where possible;
- coordinate disclosure responsibly once users have a practical path forward.

## Responsible disclosure expectations

Please:

- avoid premature public disclosure;
- allow maintainers a reasonable investigation window;
- avoid duplicate public issues while a private report is active;
- keep exploit details private until maintainers have had a fair chance to
  investigate and prepare a response.

Maintainers, in return, will try to:

- acknowledge the report;
- triage it honestly;
- explain whether it is security-relevant for this repository;
- provide a fix path, mitigation, or upgrade guidance where possible;
- coordinate disclosure without unnecessary delay once a practical response
  exists.

## Fix and release policy

Security fixes in this repository may take one of several forms:

- a code fix on the maintained branch plus a release;
- a fix on `main` with upgrade guidance when `main` is the practical maintained
  state;
- a documentation correction when the problem is unsafe guidance rather than
  runtime behavior;
- a dependency, workflow, or repository-automation update when the issue is in
  tooling rather than runtime code.

Broad backports should not be assumed. The actual path depends on:

- whether the issue affects released code or only current development state;
- whether a stable release line exists at the time;
- severity and exploitability;
- maintainer capacity to cut and support additional releases.

## Credit and attribution

If you want public credit for the report, say so in the private disclosure.
If you prefer to stay private, say that as well.

Public acknowledgment, if any, will depend on:

- whether a fix or mitigation is available;
- whether disclosure is complete;
- whether naming the reporter is explicitly allowed.

## Security tooling and repository settings

This repository may use GitHub security features such as:

- private vulnerability reporting;
- dependency alerts;
- dependency review;
- code scanning;
- secret scanning.

The exact set depends on repository settings and may change over time. These
features can help detection and coordination, but they do not replace direct
maintainer review or the reporting path in this file.

## Summary

For `arcoris.dev/pool`, likely security issues are concentrated around pooled
reuse safety, lifecycle correctness, ownership boundaries, concurrency
assumptions, and repository automation integrity.

If you think you found a real vulnerability:

1. report it privately if the repository offers that path;
2. do not post the technical details publicly first;
3. include a minimal reproduction and affected-version details;
4. explain whether stale reuse, ownership after `Put`, concurrency semantics,
   or automation integrity is involved;
5. allow maintainers time to investigate and coordinate a response.
