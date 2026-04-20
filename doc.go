/*
   Copyright 2026 The ARCORIS Authors.

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/

// Package pool provides typed reuse of temporary values.
//
// # Purpose
//
// Package pool exists for code that repeatedly allocates short-lived mutable
// objects and would benefit from reusing them through a small, explicit, and
// type-safe API.
//
// The package is intentionally narrow. It does not try to become a general
// object lifecycle framework, an allocator replacement, or a rich borrow/return
// subsystem. Instead, it focuses on one well-bounded pattern:
//
//  1. acquire a temporary value of type T;
//  2. use that value within one logical operation;
//  3. return the value for possible reuse;
//  4. optionally reject oversized or non-reusable values on the return path.
//
// In code, the intended usage surface is deliberately small:
//
//	v := p.Get()
//	// use v only within the current operation
//	p.Put(v)
//
// This package is therefore best understood as a typed, policy-driven runtime
// layered over sync.Pool-style temporary reuse rather than as a comprehensive
// resource manager.
//
// # Design model
//
// The package is built around three cooperating concepts:
//
//  1. [Options], which describes lifecycle policy declaratively;
//  2. [Pool], which exposes the public Get/Put runtime API;
//  3. an internal backend, currently implemented on top of sync.Pool, which
//     provides low-level storage and retrieval.
//
// These layers intentionally separate concerns:
//
//   - Options answers "how should values be created, reset, retained, or
//     observed when dropped?".
//   - Pool answers "how does the caller interact with the runtime?".
//   - the backend answers "where are already-clean reusable values stored?".
//
// The package also contains an internal lifecycle controller that owns the
// canonical return-path order. That order is stable and central to the package
// contract:
//
//  1. evaluate the reuse admission policy;
//  2. if reuse is denied, invoke the drop callback and stop;
//  3. if reuse is allowed, reset the value into a clean reusable state;
//  4. store the cleaned value in the backend for future acquisition.
//
// This order is deliberate. Reuse admission happens before reset so that a
// policy may inspect the object in the state it actually accumulated during
// use. Reset happens before backend storage so that retained values remain
// clean while idle and callers of Get observe values that are already ready for
// immediate use.
//
// # Why callbacks instead of a mandatory interface on T
//
// The package does not require T to implement Reset, Reusable, or any other
// package-specific interface. Lifecycle policy is instead expressed through
// callbacks in [Options].
//
// This choice is intentional for several reasons:
//
//   - domain types remain decoupled from the pool package;
//   - the same concrete type can be pooled under different reuse policies;
//   - reset and reuse logic stay explicit at the call site that assembles the
//     pool;
//   - callers are not forced to encode pooling semantics into their domain
//     model merely to participate in reuse.
//
// For example, the same Frame type might be pooled under a small-capacity fast
// path and a larger-capacity batch path simply by constructing two pools with
// different [ReuseFunc] values.
//
// # Intended use
//
// Pool is intended for temporary values whose useful lifetime is limited to a
// single logical operation and whose repeated allocation would otherwise create
// avoidable GC pressure.
//
// Typical good fits include:
//
//   - parser or decoder state objects;
//   - request-scoped scratch structures;
//   - reusable builders or envelopes;
//   - mutable helper structs used on hot paths;
//   - temporary work objects that can be restored to a well-defined clean
//     state before reuse.
//
// Typical poor fits include:
//
//   - long-lived domain entities whose ownership escapes the current
//     operation;
//   - values that must remain reachable after Put returns;
//   - objects requiring stable inventory guarantees;
//   - systems that need validation-on-borrow, idle eviction, borrow timeouts,
//     reference counting, or bounded-capacity acquisition semantics;
//   - values whose correctness depends on finalization-like guarantees.
//
// In short: this package is for temporary reuse, not for persistent object
// management.
//
// # Ownership model
//
// The package assumes a strict ownership transfer model.
//
// When [Pool.Get] returns a value, the caller becomes the logical owner of
// that value. The caller keeps that ownership until it calls [Pool.Put]. After
// Put returns, the caller MUST treat the value as no longer owned.
//
// In particular, after Put returns the caller MUST NOT:
//
//   - continue mutating the value;
//   - read from the value as if it were still exclusively owned;
//   - publish the value to other goroutines as a still-live object;
//   - return the same borrowed instance to the pool again.
//
// The default runtime does not attempt to detect double Put or use-after-Put
// misuse. Correct ownership discipline remains the responsibility of the
// caller.
//
// # Acquisition path
//
// The acquisition path is intentionally lean.
//
// On [Pool.Get]:
//
//  1. the backend is asked for a reusable value;
//  2. if the backend has none, [NewFunc] is used to create one;
//  3. the value is returned to the caller as-is.
//
// Get does not reset values, re-run admission logic, or attach ownership
// metadata. The package relies on the invariant that values accepted into the
// backend were already reset before storage. This keeps the hot path short and
// predictable.
//
// A value returned by Get is therefore always one of the following:
//
//   - a freshly constructed value produced by [NewFunc]; or
//   - a previously used value that was accepted for reuse and reset before it
//     re-entered the backend.
//
// # Return path
//
// The return path is where lifecycle policy is applied.
//
// On [Pool.Put]:
//
//  1. [ReuseFunc] decides whether the value should be retained;
//  2. if reuse is denied, [DropFunc] is invoked and the value is not stored;
//  3. if reuse is allowed, [ResetFunc] prepares the value for the next user;
//  4. the clean value is stored in the backend.
//
// [ResetFunc] is therefore paid only on the accepted return path. This is a
// deliberate trade-off: retained values remain clean while idle, references may
// be released as early as possible, and Get remains minimal.
//
// [DropFunc] is best-effort observation of explicit rejection-by-policy. It is
// not a finalizer, and it is not guaranteed to run for every value that ever
// becomes unreachable. Once a value has been accepted into a sync.Pool-style
// backend, that backend may later discard it without further notification.
//
// # Concurrency model
//
// A [Pool] is safe for concurrent use by multiple goroutines. Its lifecycle
// policy becomes immutable after construction, and backend storage is delegated
// to an internal sync.Pool-backed adapter.
//
// However, the borrowed value returned by Get belongs to one logical owner at a
// time. The package does not make the borrowed value itself concurrency-safe.
// If T needs concurrent mutation after acquisition, that synchronization must
// be provided by T or by higher-level code.
//
// The practical rule is:
//
//   - concurrent Get and Put calls on the same *Pool are supported;
//   - concurrent mutation of the same borrowed value is outside the package's
//     guarantees unless the value type provides its own synchronization.
//
// # Zero values and construction
//
// The zero value of [Pool] is not ready for use.
//
// This is intentional. A functioning pool requires:
//
//   - a constructor for slow-path allocation;
//   - a resolved lifecycle policy;
//   - an assembled backend.
//
// As a result, [New] is the only supported public constructor.
//
// The zero value of [Options] is also invalid because [Options.New] is
// required. Optional hooks such as Reset, Reuse, and OnDrop may be omitted;
// they are normalized internally when the pool is constructed.
//
// # Preferred shape of T
//
// T may be any type, but pointer-like temporary values are usually the best
// fit in performance-sensitive code.
//
// Pointer-like T values are generally preferable because they:
//
//   - avoid copying large mutable state;
//   - align naturally with object-pooling usage patterns in Go;
//   - make ownership easier to reason about;
//   - usually interact better with sync.Pool-style reuse than large value
//     objects do.
//
// Value types are supported, but they should be chosen deliberately rather than
// by accident.
//
// # Relationship to sync.Pool
//
// The package intentionally follows the temporary-object model of sync.Pool.
// It does not attempt to hide that heritage.
//
// In particular, callers should assume the same broad operational shape:
//
//   - previously returned values may later disappear from the backend without
//     notice;
//   - the package does not promise stable retention of returned values;
//   - the package is designed for reducing allocation pressure for temporary
//     values, not for maintaining a durable reserve of objects.
//
// What this package adds on top of sync.Pool is not a different storage model,
// but a better public runtime contract:
//
//   - typed access through [Pool[T]];
//   - explicit lifecycle policy through [Options];
//   - a fixed and testable return-path order;
//   - internal separation between policy, semantics, and backend storage.
//
// # Non-goals
//
// Package pool intentionally does not provide:
//
//   - validation-on-borrow or validation-on-return hooks;
//   - idle object eviction policies;
//   - borrow timeouts or blocking acquisition;
//   - reference counting;
//   - stable pool size guarantees;
//   - runtime ownership tracking in the default build;
//   - generic "resource management" abstractions beyond temporary value reuse.
//
// If a caller needs those features, it likely needs a different kind of
// system than a sync.Pool-style temporary object reuse runtime.
//
// # Internal structure
//
// Although callers primarily interact with [Pool] and [Options], the package is
// internally organized around a deliberately simple split:
//
//   - [Options] owns public lifecycle policy;
//   - lifecycle owns canonical return-path semantics;
//   - the internal backend owns only storage and retrieval;
//   - [Pool] owns public orchestration.
//
// This separation keeps the external API small while allowing the internals to
// evolve conservatively without collapsing policy, semantics, and storage into
// one opaque implementation block.
//
// # Example
//
// The following example shows a typical pointer-like temporary object used as
// request-scoped scratch state:
//
//	type ParserState struct {
//		Input  []byte
//		Offset int
//		Tokens []Token
//		Err    error
//	}
//
//	states := pool.New(pool.Options[*ParserState]{
//		New: func() *ParserState {
//			return &ParserState{
//				Tokens: make([]Token, 0, 64),
//			}
//		},
//		Reset: func(s *ParserState) {
//			s.Input = nil
//			s.Offset = 0
//			s.Tokens = s.Tokens[:0]
//			s.Err = nil
//		},
//		Reuse: func(s *ParserState) bool {
//			return cap(s.Tokens) <= 4_096
//		},
//	})
//
//	state := states.Get()
//	defer states.Put(state)
//
//	// use state only within the current operation
//
// The package is intended to change conservatively after stabilization. For
// that reason, its documentation is intentionally explicit and normative.
package pool
