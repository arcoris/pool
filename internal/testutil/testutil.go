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

// Package testutil contains shared helpers for package-local tests and
// benchmarks.
//
// The package intentionally lives under internal/ so it can be reused across
// arcoris.dev/pool test packages without becoming part of the public module
// API.
package testutil

import (
	"fmt"
	"runtime"
	"runtime/debug"
	"slices"
	"testing"
)

// RecordingSink is a generic Put recorder for tests that need to observe the
// final storage step of a value.
//
// When Events is non-nil, Put appends a literal "put" marker to that event
// log before storing the value in Puts.
type RecordingSink[T any] struct {
	Events *[]string
	Puts   []T
}

// Put records the final storage step of a value.
//
// The method intentionally mirrors the minimal sink contract used by lifecycle
// tests: append an optional "put" event marker first, then retain the value in
// Puts for later inspection.
func (s *RecordingSink[T]) Put(value T) {
	if s.Events != nil {
		*s.Events = append(*s.Events, "put")
	}
	s.Puts = append(s.Puts, value)
}

// AssertPanicMessage verifies that fn panics and that the recovered panic value
// stringifies to the exact expected message.
//
// The helper is used when panic text is part of the contract under test. It
// delegates panic capture to MustPanic so callers can share the same failure
// shape across packages.
func AssertPanicMessage(tb testing.TB, scenario string, fn func(), want string) {
	tb.Helper()

	got := MustPanic(tb, scenario, fn)
	if got != want {
		tb.Fatalf("%s panic message = %q, want %q", scenario, got, want)
	}
}

// MustPanic runs fn and returns the recovered panic value formatted with
// fmt.Sprint.
//
// If fn does not panic, the helper fails the test immediately. This keeps
// panic-based contract checks concise while still preserving the calling
// scenario in the failure output.
func MustPanic(tb testing.TB, scenario string, fn func()) string {
	tb.Helper()

	var panicValue any

	func() {
		defer func() {
			panicValue = recover()
		}()
		fn()
	}()

	if panicValue == nil {
		tb.Fatalf("%s: expected panic, got none", scenario)
	}

	return fmt.Sprint(panicValue)
}

// AssertEventSequence verifies that an observed event log matches the expected
// sequence exactly.
//
// Lifecycle-oriented tests use this helper to keep ordering assertions concise
// and to produce a stable diagnostic message when a semantic step moves or is
// omitted.
func AssertEventSequence(tb testing.TB, scenario string, got []string, want []string) {
	tb.Helper()

	if !slices.Equal(got, want) {
		tb.Fatalf("%s event sequence = %v, want %v", scenario, got, want)
	}
}

// WithSingleP runs fn with GOMAXPROCS forced to 1 and restores the previous
// setting before returning.
//
// The helper is intended for tests and benchmarks that need deterministic
// single-P behaviour, especially around sync.Pool local-cache semantics. The
// restoration is scoped to the callback itself rather than deferred to test
// cleanup so later assertions in the same test see the original runtime state.
func WithSingleP(tb testing.TB, fn func()) {
	tb.Helper()

	previous := runtime.GOMAXPROCS(1)
	defer runtime.GOMAXPROCS(previous)

	fn()
}

// WithGCDisabled runs fn with automatic GC disabled and restores the previous
// GC target before returning.
//
// This helper is useful when a test or benchmark needs to prevent transient GC
// cycles from discarding sync.Pool state between tightly-coupled Put/Get steps.
// As with WithSingleP, restoration happens immediately after fn returns so the
// helper composes safely inside larger tests.
func WithGCDisabled(tb testing.TB, fn func()) {
	tb.Helper()

	previous := debug.SetGCPercent(-1)
	defer debug.SetGCPercent(previous)

	fn()
}

// WithStablePoolRoundTrip makes immediate Put/Get assertions deterministic
// enough for tests and benchmarks that rely on sync.Pool local-cache reuse.
//
// Pinning execution to one P avoids per-P handoff surprises, and disabling GC
// prevents cached values from being discarded between Put and Get. The helper
// restores both runtime settings before it returns to the caller.
func WithStablePoolRoundTrip(tb testing.TB, fn func()) {
	tb.Helper()

	WithGCDisabled(tb, func() {
		WithSingleP(tb, fn)
	})
}
