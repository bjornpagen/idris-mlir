// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-expect's properties and --idr-contracts' relations, printed by the
// test runner (runtests --expect-table) from harness/Properties.idr,
// their one list; written again and compared by
// tests/expect-table-current. Each section is read where its first macro
// is defined, and then needs each of its macros: an includer defines
// those of the section it reads before it includes this. The
// properties', (name, argument shape, check):
//   IDR_EXPECT_PROPERTY   a test states it; a fixture makes it fail;
//   IDR_EXPECT_SELF_CHECK a test states it; only a defect makes it fail;
//   IDR_EXPECT_UNIVERSAL  the contracts check it of every compilation.
// The relations', in the order the contracts check them, (name,
// enumerator, check, the test pass's breaker, how that breaks it):
//   IDR_CONTRACT_RELATION the contracts check it after every pass.

#ifdef IDR_EXPECT_PROPERTY
// No op of @f but a call reads or writes a count: no reference is
// counted in it, and none is freed by a test of its count.
IDR_EXPECT_PROPERTY("counts-nothing", Functions, countsNothing)

// @f tests no sharing at run time: no op of it reads a count it does
// not write, every reuse token of it holds its cell, so none is
// tested for null, and some cell is taken apart in it.
IDR_EXPECT_PROPERTY("tests-nothing", Functions, testsNothing)

// Every cell @f fills is made from a reuse token, no heap memory
// acquired for it, and @f fills one.
IDR_EXPECT_PROPERTY("reuses-in-place", Functions, reusesInPlace)

// No op of @f frees the cell a reuse token holds: every cell it takes
// apart is filled again.
IDR_EXPECT_PROPERTY("reuses-every-cell", Functions, reusesEveryCell)

// No value whose sharing is tested at run time, in @f or anywhere, is
// one its function gives another reference: each test finds its cell
// unshared.
IDR_EXPECT_PROPERTY("resets-unshared", Roots, resetsUnshared)

// No op of @f but a call builds a value in memory: none acquires
// memory or writes the contents of a cell, as its declaration says;
// what @f returns or holds is its parameters' or static data.
IDR_EXPECT_PROPERTY("builds-nothing", Functions, buildsNothing)

// No op acquires heap memory, anywhere, or in @f and every function
// it may call, as the effect system's declaration of each op says.
IDR_EXPECT_PROPERTY("no-heap-allocation", Roots, noHeapAllocation)

// Every call of @f, or of a copy of it, calls one function, and there
// is one.
IDR_EXPECT_PROPERTY("one-clone", Symbol, oneClone)

// No call of @f, or of a copy of it, is left; a function the module
// never had is not called either.
IDR_EXPECT_PROPERTY("not-called", Symbol, notCalled)

// Every copy of @f but @f calls, of @f and its copies, only itself
// and @f: a recursion's specializations stop after one step.
IDR_EXPECT_PROPERTY("specialized-once", Functions, specializedOnce)

// In a first-order program, no function is called once, from a
// function it calls back: each continuation is part of what it
// continues.
IDR_EXPECT_PROPERTY("contified", Nothing, contified)

// Every function of the program is reached from its roots, the
// functions its symbol table makes public, by the symbols the bodies
// of the functions reached before it name.
IDR_EXPECT_PROPERTY("reached", Nothing, reached)

// Some call in @f calls @g or a copy of it; after lowering @g may be
// a function of the runtime, named by its symbol.
IDR_EXPECT_PROPERTY("calls", Pair, calls)

// Some call in @f of @g or a copy of it is a tail call, which goes in
// its caller's place: a fact of the program's calls, before lowering.
IDR_EXPECT_PROPERTY("tail-calls", Pair, tailCalls)

// Every call in @f of @g or a copy of it gives each result laid out as
// its callee returns it, and no op after the call re-packs one, where
// @f takes it or on its way to @f's return: none converts it between
// two layouts.
IDR_EXPECT_PROPERTY("results-as-given", Pair, resultsAsGiven)

// No op left in a copy of @f is one a fold would replace: one with
// results, no memory effect, no call and no constant of its own, whose
// operands are constants alone.
IDR_EXPECT_PROPERTY("folded", Functions, folded)

// No guard is left in @f: every condition its partial primitives need
// is proven where it runs.
IDR_EXPECT_PROPERTY("no-guards", Functions, noGuards)

// Every function of @f, its copies among them, may never end, as its
// row says: the row holds divergence, which a loop Idris did not prove
// to end puts there wherever a pass moves it, as a call of a function
// that may never end does: a fact of the program's functions, before
// lowering.
IDR_EXPECT_PROPERTY("may-diverge", Functions, mayDiverge)

// Some loop of @f computes on words alone: no value defined or bound
// in it is a big or a natural.
IDR_EXPECT_PROPERTY("word-loop", Functions, wordLoop)

// Once arrays are buffers, nothing copies a buffer, in @f or
// anywhere, and a buffer is there.
IDR_EXPECT_PROPERTY("in-place", Roots, inPlace)

// Some element of an array is rebuilt in its place, in @f or
// anywhere, moved out with the reference the array held.
IDR_EXPECT_PROPERTY("moves-out", Roots, movesOut)

// In a program whose references are not yet counted, no read of
// mutable memory, in @f or anywhere, reads the element the write
// right before it wrote, only computation between: the read is the
// value written, unless Idris proved it used once or it cannot stand
// for the read's.
IDR_EXPECT_PROPERTY("writes-forwarded", Roots, writesForwarded)

// In a program whose references are not yet counted, no write of
// mutable memory, in @f or anywhere, is followed by a write of its
// element, only computation between: what nothing read goes, unless
// Idris proved its value used once.
IDR_EXPECT_PROPERTY("overwrites-dropped", Roots, overwritesDropped)

// No op of the arrays' generating set is left, in @f or anywhere,
// and some structured op is there.
IDR_EXPECT_PROPERTY("structured-loops", Roots, structuredLoops)

// Some loop computes on vectors, and no linalg.generic with a
// parallel dimension and a body of words alone is left scalar.
IDR_EXPECT_PROPERTY("vectorized", Roots, vectorized)

// Some loop computes integer lanes in 32 bits or fewer, and every loop
// that computes wider integer lanes, a reduction's accumulator aside,
// and may run more than once is the 64-bit version beside one that
// computes its lanes in 32.
IDR_EXPECT_PROPERTY("narrowed-lanes", Roots, narrowedLanes)

// No recursion from @f grows the stack: every function it may call
// that is on a cycle of references refers to the others of its cycle
// only by guaranteed tail calls (musttail).
IDR_EXPECT_UNIVERSAL("constant-stack", Functions, constantStack)

// The label solve's set at every point is the least the program's
// statements give it, derived again a label at a time from them.
IDR_EXPECT_SELF_CHECK("labels-least", Nothing, labelsLeast)
#endif

#ifdef IDR_CONTRACT_RELATION
// Every binder Idris bound has the uses Idris proved of it, wherever
// a pass carried it: it is known by its identity, which passes copy
// with it.
IDR_CONTRACT_RELATION("quantities-kept", QuantitiesKept, quantitiesKept, breakQuantitiesKept, "trade the identities of two binders of other uses")

// Every parameter and every result of a function the pass kept is
// where its record says, at its uses: each position the function had
// stands for a run of positions after the pass, in order, each at its
// uses, none only where the pass dropped one used many times.
IDR_CONTRACT_RELATION("linear-kept", LinearKept, linearKept, breakLinearKept, "drop each result used many times and give each linear result back unrestricted")

// A function the pass kept whose row could not crash before it has
// no place that may crash after it.
IDR_CONTRACT_RELATION("crash-sites-not-added", CrashSitesNotAdded, crashSitesNotAdded, breakCrashSitesNotAdded, "make every function that could not crash crash")

// Every member of a cycle of calls Idris did not prove holds the
// cycle's divergence in its row, which no function's own check sees.
IDR_CONTRACT_RELATION("cycle-divergence-kept", CycleDivergenceKept, cycleDivergenceKept, breakCycleDivergenceKept, "drop divergence from every member of one cycle Idris did not prove, and from their calls")
#endif
