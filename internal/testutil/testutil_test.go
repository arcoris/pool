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

package testutil

import (
	"runtime"
	"runtime/debug"
	"sync"
	"testing"
)

func TestRecordingSinkPut(t *testing.T) {
	t.Run("records event and stored values", func(t *testing.T) {
		events := []string{}
		sink := &RecordingSink[int]{Events: &events}

		sink.Put(1)
		sink.Put(2)

		AssertEventSequence(t, "RecordingSink event log", events, []string{"put", "put"})
		if len(sink.Puts) != 2 || sink.Puts[0] != 1 || sink.Puts[1] != 2 {
			t.Fatalf("RecordingSink stored values = %v, want [1 2]", sink.Puts)
		}
	})

	t.Run("stores values without event log", func(t *testing.T) {
		sink := &RecordingSink[string]{}

		sink.Put("a")

		if len(sink.Puts) != 1 || sink.Puts[0] != "a" {
			t.Fatalf("RecordingSink stored values without event log = %v, want [a]", sink.Puts)
		}
	})
}

func TestMustPanic(t *testing.T) {
	t.Run("returns panic message", func(t *testing.T) {
		got := MustPanic(t, "panic case", func() {
			panic("boom")
		})

		if got != "boom" {
			t.Fatalf("MustPanic returned %q, want %q", got, "boom")
		}
	})
}

func TestAssertPanicMessage(t *testing.T) {
	t.Run("accepts exact message", func(t *testing.T) {
		AssertPanicMessage(t, "exact match", func() {
			panic("boom")
		}, "boom")
	})
}

func TestAssertEventSequence(t *testing.T) {
	t.Run("accepts equal slices", func(t *testing.T) {
		AssertEventSequence(t, "equal sequence", []string{"a", "b"}, []string{"a", "b"})
	})
}

func TestWithSingleP(t *testing.T) {
	original := runtime.GOMAXPROCS(0)
	restoreTarget := original
	if restoreTarget == 1 {
		restoreTarget = 2
	}
	runtime.GOMAXPROCS(restoreTarget)
	t.Cleanup(func() {
		runtime.GOMAXPROCS(original)
	})

	inside := 0
	mutated := 0
	insideMutation := 2
	if insideMutation == restoreTarget {
		insideMutation = 3
	}

	WithSingleP(t, func() {
		// The helper contract is twofold: force one P inside the callback and
		// restore the previous setting immediately after the callback returns.
		inside = runtime.GOMAXPROCS(0)
		mutated = runtime.GOMAXPROCS(insideMutation)
	})

	if inside != 1 {
		t.Fatalf("GOMAXPROCS inside WithSingleP = %d, want 1", inside)
	}
	if mutated != 1 {
		t.Fatalf("previous GOMAXPROCS returned by in-body mutation = %d, want 1", mutated)
	}
	if got := runtime.GOMAXPROCS(0); got != restoreTarget {
		t.Fatalf("GOMAXPROCS after WithSingleP returned = %d, want %d", got, restoreTarget)
	}
}

func TestWithGCDisabled(t *testing.T) {
	original := debug.SetGCPercent(100)
	restoreTarget := 100
	t.Cleanup(func() {
		debug.SetGCPercent(original)
	})

	insidePrevious := 0

	WithGCDisabled(t, func() {
		// Calling SetGCPercent inside the callback reveals the current value by
		// returning the previous setting. A return value of -1 proves that GC
		// was disabled for the callback body.
		insidePrevious = debug.SetGCPercent(250)
	})

	if insidePrevious != -1 {
		t.Fatalf("GC percent observed inside WithGCDisabled = %d, want -1", insidePrevious)
	}
	if restored := debug.SetGCPercent(300); restored != restoreTarget {
		t.Fatalf("GC percent after WithGCDisabled returned = %d, want %d", restored, restoreTarget)
	}
	debug.SetGCPercent(restoreTarget)
}

func TestWithStablePoolRoundTrip(t *testing.T) {
	originalP := runtime.GOMAXPROCS(0)
	restoreP := originalP
	if restoreP == 1 {
		restoreP = 2
	}
	runtime.GOMAXPROCS(restoreP)
	t.Cleanup(func() {
		runtime.GOMAXPROCS(originalP)
	})

	originalGC := debug.SetGCPercent(100)
	restoreGC := 100
	t.Cleanup(func() {
		debug.SetGCPercent(originalGC)
	})

	insideP := 0
	insideGC := 0

	WithStablePoolRoundTrip(t, func() {
		// The combined helper should apply both single-P execution and GC
		// suppression at once because backend round-trip tests rely on both.
		insideP = runtime.GOMAXPROCS(0)
		insideGC = debug.SetGCPercent(250)

		var pool sync.Pool
		stored := &struct{ ID int }{ID: 42}
		pool.Put(stored)

		// A direct sync.Pool immediate round trip is the behavioural reason this
		// helper exists. If this ever stops working under the scoped runtime
		// changes, backend tests and benchmarks lose their stability contract.
		got := pool.Get()
		if got != stored {
			t.Fatalf("sync.Pool round-trip inside WithStablePoolRoundTrip returned %v, want %v", got, stored)
		}
	})

	if insideP != 1 {
		t.Fatalf("GOMAXPROCS inside WithStablePoolRoundTrip = %d, want 1", insideP)
	}
	if insideGC != -1 {
		t.Fatalf("GC percent inside WithStablePoolRoundTrip = %d, want -1", insideGC)
	}
	if got := runtime.GOMAXPROCS(0); got != restoreP {
		t.Fatalf("GOMAXPROCS after WithStablePoolRoundTrip returned = %d, want %d", got, restoreP)
	}
	if restored := debug.SetGCPercent(300); restored != restoreGC {
		t.Fatalf("GC percent after WithStablePoolRoundTrip returned = %d, want %d", restored, restoreGC)
	}
	debug.SetGCPercent(restoreGC)
}
