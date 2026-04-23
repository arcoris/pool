# Non-Goals

## Contents

- [Purpose](#purpose)
- [Role of This Document](#role-of-this-document)
- [Core Product Identity](#core-product-identity)
- [Primary Scope Exclusions](#primary-scope-exclusions)
- [1. Not a General Resource Manager](#1-not-a-general-resource-manager)
- [2. Not a Borrow or Lease Tracking Framework](#2-not-a-borrow-or-lease-tracking-framework)
- [3. Not a Stable Object Inventory or Cache](#3-not-a-stable-object-inventory-or-cache)
- [4. Not a Queue, Scheduler, or Coordination Primitive](#4-not-a-queue-scheduler-or-coordination-primitive)
- [5. Not a Validation Framework](#5-not-a-validation-framework)
- [6. Not a Domain-Specific Factory or Object Framework](#6-not-a-domain-specific-factory-or-object-framework)
- [7. Not an Interface-Driven Type Hierarchy](#7-not-an-interface-driven-type-hierarchy)
- [8. Not a Specialized Memory or Buffer Pool](#8-not-a-specialized-memory-or-buffer-pool)
- [9. Not a Rich Pooling Framework](#9-not-a-rich-pooling-framework)
- [10. Not a Promise of Zero Allocations or Public Backend Pluggability](#10-not-a-promise-of-zero-allocations-or-public-backend-pluggability)
- [Allowed Extensions](#allowed-extensions)
- [Scope Changes](#scope-changes)
- [Practical Decision Rule](#practical-decision-rule)
- [Summary](#summary)

## Purpose

This document defines what `arcoris.dev/pool` intentionally does **not** do.

It is the primary repository document for explicit scope boundaries. Proposed
changes that conflict with this file SHOULD be treated as product-level scope
changes, not as routine package evolution.

## Role of This Document

The documentation set is intentionally split by responsibility:

- [Package contract (`doc.go`)](../doc.go) explains the package contract for Go users;
- [Architecture guide](./architecture.md) explains repository structure and layering;
- [Lifecycle guide](./lifecycle.md) defines lifecycle and ownership semantics;
- [Non-goals guide](./non-goals.md) defines the scope boundaries of the product.

This file is therefore the main home of exclusions. Other documents may mention
boundaries briefly for context, but the detailed exclusion logic belongs here.

## Core Product Identity

`arcoris.dev/pool` is a **typed temporary-object reuse runtime**.

Its job is limited to:

1. acquiring a temporary reusable value of type `T`;
2. allowing the caller to use that value for one logical operation;
3. applying explicit lifecycle policy on return;
4. retaining or dropping the value accordingly.

That narrow identity is intentional.

The package is not a general-purpose lifecycle platform, not a general resource
manager, and not a specialized memory product. Every exclusion in this document
exists to preserve that identity.

## Primary Scope Exclusions

The package MUST remain callback-based and policy-driven.

It MUST NOT become:

- a general resource manager;
- a borrow or lease tracking framework;
- a stable object inventory or cache;
- a queue, scheduler, semaphore, or coordination primitive;
- a validation framework;
- a domain-specific factory framework;
- an interface-driven hierarchy for `T`;
- a specialized memory or buffer pool;
- a rich pooling framework with many new coordination semantics.

The sections below explain why those exclusions exist.

## 1. Not a General Resource Manager

The package reuses **values**. It does not manage external resources.

It is not responsible for:

- files;
- sockets;
- network connections;
- transactions;
- OS handles;
- shutdown sequencing;
- context propagation;
- resource health management.

That boundary exists because external resources have failure and lifecycle
requirements that are fundamentally different from temporary object reuse.

Features such as acquisition failure handling, draining, shutdown orchestration,
or health checks would turn the package into a different product.

## 2. Not a Borrow or Lease Tracking Framework

The package does not implement:

- lease objects;
- borrow tokens;
- checked-out handles;
- expiration semantics;
- borrower registries;
- production borrow diagnostics;
- runtime ownership tracking in the default build.

Instead, the package defines a documented ownership contract: after `Get`, the
caller owns the borrowed value; after `Put`, that ownership is over.

This boundary exists because borrow tracking would introduce new public runtime
concepts, new metadata, and new hot path costs that do not fit the current
product identity.

## 3. Not a Stable Object Inventory or Cache

The package does not promise stable residency of returned objects.

It does not provide:

- minimum idle counts;
- maximum idle counts;
- reserve capacity guarantees;
- deterministic retention;
- durable object inventories;
- cache semantics.

The internal backend follows a `sync.Pool`-style model in which retained values
may later disappear without notice.

That behavior is acceptable for temporary reusable values. It is not compatible
with cache-like or inventory-like guarantees, which belong to a different class
of runtime.

## 4. Not a Queue, Scheduler, or Coordination Primitive

The package does not coordinate work.

It is not:

- a queue;
- a worker scheduler;
- a semaphore;
- a dispatcher;
- a fairness mechanism;
- an admission-control subsystem.

Reusable object storage and execution coordination are separate concerns.
Combining them would complicate both the API and the semantics without serving
the core product goal.

## 5. Not a Validation Framework

The package does not provide a validation pipeline around `Get` or `Put`.

It does not define:

- validate-on-borrow hooks;
- validate-on-return hooks;
- quarantine pipelines;
- error-returning lifecycle phases;
- runtime health filtering of pooled values.

This boundary exists because validation changes the execution model. Once
validation enters the public runtime, the package tends to require richer error
semantics, more public surface, and more policy coupling than intended.

If a caller needs validation-like behavior, that logic SHOULD remain in caller
code or be expressed through existing lifecycle policy where appropriate.

## 6. Not a Domain-Specific Factory or Object Framework

The package defines exactly one construction hook: `Options.New`.

It is not a framework for:

- dependency-injected object graphs;
- named constructors;
- construction registries;
- object blueprints;
- domain-specific lifecycle factories.

The miss path only needs one thing: a way to produce a fresh value of type `T`.
Anything beyond that pushes the package toward a broader object framework rather
than a temporary-object reuse runtime.

## 7. Not an Interface-Driven Type Hierarchy

The package MUST NOT require `T` to implement mandatory package-owned
interfaces.

That includes architectures built around types such as:

- `Resetter`;
- `Reusable`;
- `Poolable`;
- `Validatable`.

The callback-based design is deliberate. It keeps domain types decoupled from
the package and allows one type to be pooled under different lifecycle policies
in different contexts.

Small optional adapters could exist in the future, but the package MUST NOT be
redesigned around mandatory type interfaces.

## 8. Not a Specialized Memory or Buffer Pool

This package is about generic typed temporary reusable values.

It is not a specialized memory product for:

- size classes;
- tiered retention by capacity;
- byte-slice-specific ownership rules;
- buffer-view semantics;
- memory-shaping policies as the primary public abstraction.

Specialized memory or buffer pooling has different design pressures from
generic typed reuse. If such semantics are needed, they belong in a separate
package with its own product identity.

## 9. Not a Rich Pooling Framework

The package does not try to become a broad pooling platform.

It therefore does not provide:

- bounded-capacity acquisition;
- blocking borrow semantics;
- borrow timeouts;
- idle eviction policies;
- reference counting;
- lifecycle plug-in chains;
- mandatory instrumentation hooks on the hot path;
- runtime misuse detection as a core feature.

Those features each carry real value in some systems, but together they would
change the package from a small typed temporary-object reuse runtime into a
much larger framework.

## 10. Not a Promise of Zero Allocations or Public Backend Pluggability

The package is performance-oriented, but it does not promise:

- universal zero-allocation behavior;
- fixed allocation counts across workloads;
- a public backend selection API;
- pluggable backend contracts exposed to callers.

The internal backend is an implementation detail. Public semantics are defined
in terms of the public runtime and lifecycle policy, not in terms of backend
selection.

Likewise, the package may reduce allocation pressure, but it MUST NOT be
documented as a universal zero-allocation guarantee.

## Allowed Extensions

The following changes are generally consistent with the current product
identity, provided they preserve the existing public contract:

- clearer documentation;
- stronger tests and benchmarks;
- internal backend refinements;
- internal debug-only checks that remain clearly internal;
- optional internal instrumentation that does not become public runtime policy;
- carefully scoped performance work that preserves the callback-based model.

These are extensions of the existing product, not changes to the product
definition.

## Scope Changes

The following proposals SHOULD be treated as scope changes rather than routine
enhancements:

- adding lease or borrower objects to the public runtime;
- making stable residency part of the contract;
- exposing backend choice publicly;
- introducing mandatory interfaces for `T`;
- adding queue-like or scheduler-like coordination semantics;
- turning the package into a specialized memory or buffer product;
- broadening the public runtime into a general resource-management API.

When in doubt, the key question is not "would this be useful?" but "would this
still be the same product?"

## Practical Decision Rule

Use the following rule when evaluating a proposal:

1. Does the change preserve the identity of the package as a typed
   temporary-object reuse runtime?
2. Does it keep lifecycle policy explicit, callback-based, and caller-owned?
3. Does it avoid turning the public runtime into a broader coordination,
   validation, inventory, or resource-management system?
4. Does it preserve the narrow semantics of `Get` and `Put`?

If any answer is "no", the proposal SHOULD be treated as a scope change.

## Summary

`arcoris.dev/pool` is intentionally small.

It exists to provide:

- typed access to temporary reusable values;
- explicit lifecycle policy;
- a small public runtime;
- an internal backend that remains an implementation detail.

It does not exist to solve every adjacent lifecycle or pooling problem.

The package remains coherent precisely because these boundaries are explicit and
conservative.
