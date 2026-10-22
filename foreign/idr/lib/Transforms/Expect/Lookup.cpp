// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The properties idr-expect checks: one row each, which holds the
// property's name once and pairs its check with the shape of its argument
// (ExpectArguments.h), the comment above it saying what it checks. `@f` is
// every function made from f's code (`names`); a property of `[@f]` is
// stated of the whole module, or of the functions @f names.

#include "idr/Transforms/Expect.h"

#include "llvm/ADT/STLExtras.h"

#include <iterator>

namespace idr::expect {

namespace {

const Property properties[] = {
    // No closure is built, applied or a constant.
    property<Roots, noClosures>("no-closures"),
    // The type at the position of every copy of @f, a result (`result`,
    // `result<n>`) or a parameter (`arg<n>`), is a sum of labels, of
    // closures or of a memo cell, whose labels run exactly the functions
    // the list names.
    property<Labels, labels>("labels"),
    // Before idr-defunctionalize: the label solve's set at every point is
    // the least the program's flow gives it, every label a source of it
    // reaches along the edges and the dispatches that run what reaches
    // them, and no other.
    property<Nothing, labelsLeast>("labels-least"),
    // Nothing allocates a heap cell, anywhere, or in @f and every function
    // it names.
    property<Roots, noHeapAllocation>("no-heap-allocation"),
    // Every call of @f calls one function, and there is one.
    property<Symbol, oneClone>("one-clone"),
    // Every copy of @f other than @f calls, of @f and its copies, only
    // itself and @f: no specialization was made for a call in another, so a
    // recursion's specializations stop after one step.
    property<Functions, specializedOnce>("specialized-once"),
    // No call of @f is left (a function the module never had is not called
    // either).
    property<Symbol, notCalled>("not-called"),
    // Every binder the module in the file (the emitted module) gives an
    // identity, a function's parameter or a field a match binds, has the
    // uses it has there, once or many.
    property<Module, quantitiesKept>("quantities-kept"),
    // In @f every box is built in a recycled cell (idr.cell.recycle), and
    // at least one is.
    property<Functions, reusesInPlace>("reuses-in-place"),
    // Some element of an array is rebuilt in its place (idr.array.update,
    // idr.element.update), moved out with the reference the array held.
    property<Roots, movesOut>("moves-out"),
    // No idr.dup or idr.drop in @f, other than a dup of static data, which
    // holds no count.
    property<Functions, countsNothing>("counts-nothing"),
    // No guard (`idr.check.*`) is left in @f.
    property<Functions, noGuards>("no-guards"),
    // Every take in @f is of an exclusive value and every recycled cell's
    // token is exclusive, so no count or null is tested; and there is at
    // least one take.
    property<Functions, testsNothing>("tests-nothing"),
    // Some copy of @f takes every parameter that holds references at the
    // exclusive grade: idr-rc gave @f a copy for exclusive arguments.
    property<Functions, exclusiveCopy>("exclusive-copy"),
    // Every take tests a cell that its function never gives a second
    // reference.
    property<Roots, resetsUnshared>("resets-unshared"),
    // Every cell a take in @f yields for a constructor with fields is
    // recycled, and none is freed.
    property<Functions, reusesEveryCell>("reuses-every-cell"),
    // No function is called once, from another function that it calls
    // back, and used nowhere else.
    property<Nothing, contified>("contified"),
    // No string is built only to be written.
    property<Roots, outputFused>("output-fused"),
    // No op is left in any copy of @f that a fold would have replaced: one
    // with results, no memory effect, no call and no constant, whose
    // operands are constants alone.
    property<Functions, folded>("folded"),
    // No recursion from @f grows the stack: every function @f may call that
    // is on a cycle of references refers to the others of its cycle only by
    // guaranteed tail calls (`musttail`), so before idr-tail-calls none may
    // be on a cycle at all.
    property<Functions, constantStack>("constant-stack"),
    // Every copy of @f calls @g or a copy of it, each call a guaranteed tail
    // call (`musttail`, the return right after it).
    property<Pair, tailCalls>("tail-calls"),
    // @f loops, and each of its loops is an `scf.for`.
    property<Functions, countedLoop>("counted-loop"),
    // Some loop of @f computes on words alone: no value defined or bound in
    // it is a big or a natural.
    property<Functions, wordLoop>("word-loop"),
    // No op is left that idr-structure-loops lowers, and some linalg op is
    // there.
    property<Roots, structuredLoops>("structured-loops"),
    // After bufferization, nothing copies a buffer, and a buffer is there.
    property<Roots, inPlace>("in-place"),
    // No result of a linalg op in @f that has one use is used by another
    // linalg op, and @f holds a linalg op.
    property<Functions, fused>("fused"),
    // No function holds more operations than the bound, counted as the
    // inline decisions count them.
    property<Bound, largestFunction>("largest-function"),
    // After the vectorization schedule, some loop computes on vectors, and
    // no `linalg.generic` with a parallel dimension and a body of words
    // alone is left scalar.
    property<Roots, vectorized>("vectorized"),
    // After idr-narrow-lanes, some loop computes integer lanes in 32 bits
    // or fewer, and every loop that computes integer lanes wider than 32
    // bits, other than a reduction's accumulator, and may run more than
    // once is the 64-bit version beside a loop that computes its lanes in
    // 32.
    property<Roots, narrowedLanes>("narrowed-lanes"),
    // @f takes some value apart by a match on a constructor or a literal,
    // or none.
    property<Functions, matches>("matches"),
    property<Functions, matchesNothing>("matches-nothing"),
    // @f forces some suspension, or none.
    property<Functions, forcesSome>("forces"),
    property<Functions, forcesNothing>("forces-nothing"),
    // @f builds some value at run time (a constructor, as a value or into
    // a cell, a closure, a suspension), or none: what it returns or holds
    // is its parameters' or static data.
    property<Functions, buildsSome>("builds"),
    property<Functions, buildsNothing>("builds-nothing"),
    // @f reads some field of a constructor value by idr.field, or none.
    property<Functions, readsFields>("reads-fields"),
    property<Functions, readsNoFields>("reads-no-fields"),
    // @f applies some closure (no-closures=@f says none).
    property<Functions, applies>("applies"),
    // No path of @f returns.
    property<Functions, neverReturns>("never-returns"),
    // Some call in @f calls @g or a copy of it, or none does; before
    // lowering and after it, where @g may be a function of the runtime, by
    // its symbol.
    property<Pair, calls>("calls"),
    property<Pair, neverCalls>("never-calls"),
    // @f calls @g, and every call of it there takes constants alone.
    property<Pair, callsClosed>("calls-closed"),
    // Every return of @f returns, as each result, the value written (Item).
    property<ReturnedValues, returnsConstants>("returns"),
    // Every return of @f returns, as each result, the parameter of that
    // position.
    property<ReturnedArguments, returnsArguments>("returns-argument"),
    // The one result of @f is, on each of its paths through its matches,
    // one of the constants written, and each of them on some path.
    property<PathValues, returnsOnPaths>("returns-on-paths"),
    // Every value @f builds at run time is used in the block that builds
    // it, so none is built on a path that does not use it.
    property<Functions, buildsWhereUsed>("builds-where-used"),
    // Every call of @g or of a copy of it in @f whose results are used is
    // used in the block that makes it, so none runs on a path that does not
    // use it.
    property<Pair, callsWhereUsed>("calls-where-used"),
    // No match in @f tests a value that a match around it on the same value
    // already decided (it sits in one of its cases, or in its default and
    // has no case of its own).
    property<Functions, matchesOnce>("matches-once"),
    // Nothing @f writes may be written before something in @f that may
    // crash, a call's writes and crashes those its effects hold.
    property<Functions, crashesBeforeOutput>("crashes-before-output"),
    // Every parameter of @f is read in its body.
    property<Functions, parametersUsed>("parameters-used"),
    // Every result of every match in @f is used.
    property<Functions, resultsUsed>("results-used"),
    // No match in @f has two regions that do the same.
    property<Functions, regionsDistinct>("regions-distinct"),
    // @f checks something, and every check (`idr.check.*`) runs on every
    // path through @f.
    property<Functions, checksEveryPath>("checks-every-path"),
    // Every copy of @f holds at most as many operations as the function @f
    // of the module in the file held.
    property<FunctionsAndModule, growsNothing>("grows-nothing"),
    // Every copy of @f calls each function the list names, in the list's
    // order as its body is written.
    property<Listed, callOrder>("call-order"),
    // No call of @g or of a copy of it in @f makes a call that dominates it
    // again, the same callee on the same operands.
    property<Pair, callsDistinct>("calls-distinct"),
    // Every call of @g or of a copy of it in @f gives a result that
    // something reads.
    property<Pair, callsRead>("calls-read"),
    // Every call of every copy of @f is of a function the list names; `[]`,
    // none.
    property<Listed, callsOnly>("calls-only"),
    // Every call names its callee: none calls through a value.
    property<Roots, directCalls>("direct-calls"),
    // Every copy of @f may crash at exactly n places: an idr op that never
    // returns, a guard, or a call of a function that never returns.
    property<CountOf, crashSites>("crash-sites"),
    // Nothing of the idr dialect is left: no op, no type of a value, a
    // block argument or a signature, no attribute of it, and no attribute
    // named for a fact an idr.func holds; the program that holds the
    // lowered functions aside.
    property<Roots, lowered>("lowered"),
    // Every op of the program is the LLVM dialect's.
    property<Nothing, inLLVM>("in-llvm"),
    // Every copy of @f has the function type written.
    property<TypeOf, signature>("signature"),
    // Every copy of @f is an llvm.func called by the convention LLVM spells
    // as written (ccc, tailcc, ...).
    property<ConventionOf, convention>("convention"),
    // After idr-entry, the one public function with a body is the process
    // entry, of the C entry's type (i32, !llvm.ptr) -> i32.
    property<Nothing, entry>("entry"),
    // Every symbol the program defines is written in letters, digits, `_`,
    // `.` and `$`.
    property<Nothing, linkerNames>("linker-names"),
    // Every copy of @f has a loop op, or exactly n of them.
    property<Loops, loops>("loops"),
    // Every copy of @f runs one path: no op of it chooses among or repeats
    // its regions, and no block ends in a choice of successors.
    property<Functions, straightLine>("straight-line"),
    // Every LLVM load and store states its alignment.
    property<Roots, alignedAccess>("aligned-access"),
    // No op of any copy of @f but a call reads, or writes, memory outside
    // its own frame.
    property<Functions, readsNothing>("reads-nothing"),
    property<Functions, writesNothing>("writes-nothing"),
    // Every copy of @f is an idr.func whose effects, as idr-effects found
    // them, are exactly those written, of io, crash and diverge; one no
    // pass solved may do all three.
    property<EffectsOf, solvedEffects>("effects"),
    // Every op left in every copy of @f is a guard, an op that never
    // returns, ub.unreachable or a terminator: it computes no value, and
    // only what may crash is kept.
    property<Functions, computesNothing>("computes-nothing"),
    // No copy of @f asks an extent (a dimension op) of an array an op of it
    // made: only of one it was given.
    property<Functions, dimsKnown>("dims-known"),
    // Every memo label of the program whose function is @f or a copy of it
    // runs again at every force (`by_name`), or none does; and there is
    // one.
    property<Symbol, byName>("by-name"),
    property<Symbol, notByName>("not-by-name"),
    // Every copy of @f is an idr.func that holds Idris's proof that its
    // body's loops end, or that does not.
    property<Functions, total>("total"),
    property<Functions, notTotal>("not-total"),
    // The functions written as @f and as @g are still two: some function is
    // made from each, and none from both.
    property<TwoFunctions, apart>("apart"),
    // From every copy of @f, the functions its body names, followed from
    // body to body, include @g or a copy of it.
    property<Pair, reaches>("reaches"),
    // The module's program is at the stage written.
    property<StageIs, stage>("stage"),
};

} // namespace

const Property *lookup(llvm::StringRef name) {
  const Property *at =
      llvm::find_if(properties, [&](const Property &row) { return row.name == name; });
  return at == std::end(properties) ? nullptr : at;
}

} // namespace idr::expect
