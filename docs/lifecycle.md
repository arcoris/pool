# Pool Lifecycle

## Contents

- [Purpose](#purpose)
- [Scope](#scope)
- [Lifecycle Overview](#lifecycle-overview)
- [Acquisition Path](#acquisition-path)
- [Return Path](#return-path)
- [Why Reset Happens on Put](#why-reset-happens-on-put)
- [Why Reuse Is Evaluated Before Reset](#why-reuse-is-evaluated-before-reset)
- [Ownership Model](#ownership-model)
- [Concurrency Implications](#concurrency-implications)
- [Lifecycle Hooks](#lifecycle-hooks)
- [Lifecycle Invariants](#lifecycle-invariants)
- [Summary](#summary)

## Purpose

This document defines the normative lifecycle semantics of
`arcoris.dev/pool`.

It specifies:

- how values move through the public runtime;
- how ownership changes across `Get` and `Put`;
- how the return path applies lifecycle policy;
- which invariants repository changes MUST preserve.

Repository structure belongs in `docs/architecture.md`. Explicit scope
exclusions belong in `docs/non-goals.md`.

## Scope

`arcoris.dev/pool` is a typed temporary-object reuse runtime for temporary
reusable values.

Its lifecycle has two primary transitions:

1. acquisition through the public runtime;
2. return through the public runtime.

Those transitions are intentionally asymmetric.

- Acquisition is designed to stay lean.
- Return is where lifecycle policy is applied.

This asymmetry is part of the package contract.

## Lifecycle Overview

At a high level, the lifecycle is:

1. the caller acquires a value through `Get`;
2. the caller becomes the logical owner of that value;
3. the caller uses the value within one logical operation;
4. the caller returns the value through `Put`;
5. the public runtime decides whether the value is dropped or retained;
6. retained values are reset and passed to the internal backend.

The public runtime therefore operates over two value states:

- borrowed and caller-owned;
- idle and backend-owned.

The package does not define any third state such as checked-out handles,
leases, or stable inventory entries.

## Acquisition Path

On `Get`:

1. the public runtime asks the internal backend for a reusable value;
2. if the backend has none, the configured `New` hook constructs one;
3. the resulting value is returned to the caller.

The acquisition path intentionally does **not**:

- run `Reset`;
- re-evaluate `Reuse`;
- call `OnDrop`;
- attach runtime borrow metadata.

This keeps `Get` lean and preserves a simple mental model: a value returned by
`Get` is either freshly constructed or previously retained and already cleaned.

## Return Path

On `Put(v)`, the public runtime applies lifecycle policy in a fixed order:

1. evaluate `Reuse(v)`;
2. if reuse is denied, invoke `OnDrop(v)` and stop;
3. if reuse is allowed, invoke `Reset(v)`;
4. forward the cleaned value to the internal backend.

This order is canonical.

The public runtime MUST preserve it because each step answers a different
semantic question:

- `Reuse` answers whether the current value should be retained at all;
- `OnDrop` observes explicit rejection-by-policy;
- `Reset` prepares only retained values for future reuse;
- backend storage is the final step for already-clean reusable values.

## Why Reset Happens on Put

Reset happens on `Put`, not on `Get`, for three reasons.

### 1. Retained values remain clean while idle

A value accepted for reuse is cleaned before it re-enters backend storage.

This means the internal backend stores values that are already ready for future
handout, not values that still need lifecycle work.

### 2. References are released earlier

If reset drops transient references, that cleanup happens before the value sits
idle in the backend.

This reduces the lifetime of retained references and keeps the idle backend
state easier to reason about.

### 3. The acquisition path stays lean

If reset ran on `Get`, every acquisition would pay the reset cost.

The current design instead pays reset cost only on accepted return paths, which
keeps the public runtime biased toward a small `Get` hot path.

## Why Reuse Is Evaluated Before Reset

`Reuse` is evaluated before `Reset` so that admission policy can inspect the
actual state accumulated during use.

Typical examples include:

- dropping a value whose internal slice grew too large;
- dropping a value that entered a poisoned or non-reusable state;
- retaining only values that stayed within a desired working set.

If reset ran first, that original post-operation state would be obscured or
destroyed before admission policy could examine it.

The order therefore MUST remain:

1. evaluate reuse;
2. branch into drop or reset;
3. store only after reset has completed.

## Ownership Model

Ownership is explicit and strict.

### During borrow

After `Get` returns, the caller becomes the logical owner of the borrowed value.

During that ownership window, the caller MAY:

- mutate the value;
- populate temporary fields;
- grow or shrink working slices;
- pass the value through the current operation.

### End of ownership

Ownership ends when the caller calls `Put`.

After `Put` returns, the caller MUST treat the value as no longer owned,
regardless of whether the value was:

- retained for reuse; or
- rejected and explicitly dropped.

After `Put`, the caller MUST NOT:

- continue mutating the value;
- continue reading it as if it were still exclusively owned;
- publish it as a live object;
- return the same borrowed instance again.

The default runtime does not perform borrow tracking. The contract is still
normative even without runtime enforcement.

## Concurrency Implications

The public runtime is safe for concurrent `Get` and `Put` calls.

That guarantee applies to the runtime handle, not to the borrowed value itself.

The practical rule is:

- concurrent calls on the same `*Pool` are supported;
- one borrowed value belongs to one logical owner at a time;
- concurrent mutation of the same borrowed value is outside the package's
  guarantees unless the value type provides its own synchronization.

The lifecycle implication is straightforward: concurrency safety of the runtime
MUST NOT be mistaken for concurrency safety of the borrowed object.

## Lifecycle Hooks

The lifecycle policy is expressed through four hooks in `Options[T]`.

### `New`

Creates a fresh value when the internal backend has no reusable value
available.

`New` is mandatory.

### `Reset`

Prepares an accepted value for future reuse.

If omitted, reset defaults to a no-op.

### `Reuse`

Decides whether a returned value is eligible for retention.

If omitted, reuse defaults to unconditional acceptance.

### `OnDrop`

Observes explicit rejection of reuse.

If omitted, drop observation defaults to a no-op.

`OnDrop` is not a finalizer and MUST NOT be treated as a general destruction
guarantee.

## Lifecycle Invariants

The following invariants define the lifecycle contract.

### MUST

- `Get` MUST return either a freshly constructed value or a previously retained
  value that was reset before storage.
- `Put` MUST evaluate reuse before reset.
- Accepted values MUST be reset before they are passed to the internal backend.
- Rejected values MUST NOT be reset before drop observation.
- Ownership MUST transfer to the caller on `Get` and end on `Put`.

### SHOULD

- `Get` SHOULD remain lean and free of return-path lifecycle work.
- `Reset` SHOULD restore a retained value to a state ready for immediate reuse.
- `Reuse` SHOULD inspect the actual post-operation state, not a synthesized one.

### MUST NOT

- The public runtime MUST NOT attach lease, token, or borrow-handle semantics.
- The internal backend MUST NOT decide lifecycle policy.
- Lifecycle semantics MUST NOT depend on stable backend retention.
- Callers MUST NOT use a borrowed value as still-owned after `Put`.

## Summary

The lifecycle model of `arcoris.dev/pool` is intentionally small and explicit.

- `Get` acquires a temporary reusable value.
- The caller owns that value until `Put`.
- `Put` applies `Reuse -> Drop or Reset -> backend Put`.
- Accepted values are reset before storage.
- Rejected values are dropped without entering backend storage.

That model is the semantic core of the package and should remain stable.
