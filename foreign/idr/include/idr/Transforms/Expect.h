// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-expect: properties of a module that tests state by name, instead of
// matching the ops that happen to show them. Each property is a function
// that reports every place it fails, one error each, and changes nothing.
// What a property needs of the module beyond its ops (the symbol table, the
// cells' layouts) it asks of the analysis manager, so properties that ask
// the same share one answer and the pass keeps nothing between runs. The
// comment on each property below is the one list of what idr-expect
// checks; `lookup` knows each by the name it gives.
//
// `@f` names every function made from the code the programmer wrote as f:
// a function whose symbol is f, and a function whose own location names f.
// Emit gives each function, lambdas and delays included, the name of its
// Idris definition; a copy a pass makes keeps its original's location; and
// deduplication fuses the locations of the functions it merges into the
// one it keeps. So a property stated of f holds of every copy of f's code,
// however the passes named it. A hand-written module names a function by
// its symbol, or gives it `loc("f")` where its copies must be found too.
#ifndef IDR_TRANSFORMS_EXPECT_H
#define IDR_TRANSFORMS_EXPECT_H

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include <string>

namespace idr {
#define GEN_PASS_DECL_IDREXPECT
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace idr::expect {

// Every property takes the module, the pass's analysis manager and the
// text after `=` in its request (empty when there is none), and fails
// when it reported an error.
using Check = mlir::LogicalResult (*)(mlir::ModuleOp module, mlir::AnalysisManager &analyses,
                                      llvm::StringRef argument);

// The property named `name`, or null when there is none.
Check lookup(llvm::StringRef name);

// The error that `property` fails at `loc`, to which the caller adds what
// was found: `expected <property>: <what>`.
mlir::InFlightDiagnostic fail(mlir::Location loc, llvm::StringRef property);

// The function that holds `op` (or is it), as `@name`, or "the module".
std::string where(mlir::Operation *op);

// Whether `fn` is made from the code written as `f`: its symbol is `f`, or
// its own location names `f`.
bool names(mlir::FunctionOpInterface fn, llvm::StringRef f);

// The functions `function` (`@f`) names, by `names`; none, after an error
// of `property`, when it names none.
llvm::SmallVector<mlir::FunctionOpInterface> named(mlir::ModuleOp module, llvm::StringRef function,
                                                   llvm::StringRef property);

// The roots a property of ops is checked under: the module, without
// `function`, or the functions it names.
llvm::SmallVector<mlir::Operation *> rootsOf(mlir::ModuleOp module, llvm::StringRef function,
                                             llvm::StringRef property);

// The functions the body of `fn` names by a symbol use (a call, a closure,
// a constant), in the order the walk meets them, each once.
llvm::SmallVector<mlir::Operation *> callees(mlir::SymbolTable &symbols, mlir::Operation *fn);

// The cycles among `nodes` by `edges`, an edge to a node outside `nodes`
// dropped: each strongly connected component of two or more, or of one
// that refers to itself, callees first.
llvm::SmallVector<llvm::SmallVector<mlir::Operation *>>
cycles(llvm::ArrayRef<mlir::Operation *> nodes,
       llvm::function_ref<llvm::SmallVector<mlir::Operation *>(mlir::Operation *)> edges);

// `no-closures`: no closure is built, applied or a constant.
mlir::LogicalResult noClosures(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `no-heap-allocation`, `no-heap-allocation=@f`: nothing allocates a heap
// cell, anywhere, or in @f and every function it names.
mlir::LogicalResult noHeapAllocation(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `one-clone=@f`: every call of @f calls one function, and there is one.
mlir::LogicalResult oneClone(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `not-called=@f`: no call of @f is left (a function the module never had
// is not called either).
mlir::LogicalResult notCalled(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `quantities-kept=<file>`: every parameter of a function, every field a
// match binds and every constructor field that the module in <file> (the
// emitted module) declares has the quantity it has there, one or many.
mlir::LogicalResult quantitiesKept(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `reuses-in-place=@f`: in @f every box is built in a reused cell
// (idr.reuse), and at least one is.
mlir::LogicalResult reusesInPlace(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `moves-out`, `moves-out=@f`: anywhere or in @f, some read of a
// world-ordered array's element moves it out for the write that follows.
mlir::LogicalResult movesOut(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `counts-nothing=@f`: no idr.dup or idr.drop in @f, other than a dup of
// static data, which holds no count.
mlir::LogicalResult countsNothing(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `no-guards=@f`: no guard (`idr.check.*`) is left in @f.
mlir::LogicalResult noGuards(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `tests-nothing=@f`: every take in @f is of an exclusive value and every
// reuse builds in an exclusive cell, so no count or null is tested; and
// there is at least one take.
mlir::LogicalResult testsNothing(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `resets-unshared`, `resets-unshared=@f`: every take of a box, anywhere or
// in @f, tests a cell that its function never gives a second reference.
mlir::LogicalResult resetsUnshared(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `reuses-every-cell=@f`: every cell a take in @f yields for a constructor
// with fields is reused, and none is freed.
mlir::LogicalResult reusesEveryCell(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `contified`: no private function is called once, from another function
// that it calls back, and used nowhere else.
mlir::LogicalResult contified(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `facts-as-marked`: every op marked `expect.facts = "..."` answers,
// through the dialect's effects, the questions the mark lists, of
// `drop move delay` in that order.
mlir::LogicalResult factsAsMarked(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `output-fused`: no string is built only to be written.
mlir::LogicalResult outputFused(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `folds-balanced`: the folders released every reference they took from
// the runtime.
mlir::LogicalResult foldsBalanced(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `constant-stack=@f`: no recursion from @f grows the stack: every function
// @f may call that is on a cycle of references refers to the others of its
// cycle only by guaranteed tail calls (`musttail`), so before
// idr-tail-calls none may be on a cycle at all.
mlir::LogicalResult constantStack(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `counted-loop=@f`: @f loops, and each of its loops is an `scf.for`.
mlir::LogicalResult countedLoop(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `word-loop=@f`: some loop of @f computes on words alone: no value defined
// or bound in it is a big or a natural.
mlir::LogicalResult wordLoop(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `structured-loops`, `structured-loops=@f`: anywhere or in @f, no loop is
// left that idr-structure-loops structures, and some linalg op is there.
mlir::LogicalResult structuredLoops(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `typed-reads=@f`: no index of a tensor access in @f comes from a guard,
// and @f accesses a tensor.
mlir::LogicalResult typedReads(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `in-place`, `in-place=@f`: after bufferization, nothing copies a buffer,
// anywhere or in @f, and a buffer is there.
mlir::LogicalResult inPlace(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `fused=@f`: no result of a linalg op in @f that has one use is used by
// another linalg op, and @f holds a linalg op.
mlir::LogicalResult fused(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `largest-function=<n>`: no function holds more than n operations,
// counted as the inline decisions count them.
mlir::LogicalResult largestFunction(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `vectorized`, `vectorized=@f`: after the vectorization schedule, anywhere
// or in @f, some loop computes on vectors, and no `linalg.generic` with a
// parallel dimension and a body of words alone is left scalar.
mlir::LogicalResult vectorized(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `narrowed-lanes`, `narrowed-lanes=@f`: after idr-narrow-lanes, anywhere
// or in @f, some loop computes integer lanes in 32 bits or fewer, and
// every loop that computes integer lanes wider than 32 bits, other than a
// reduction's accumulator, and may run more than once is the 64-bit
// version beside a loop that computes its lanes in 32.
mlir::LogicalResult narrowedLanes(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `cells-fit`: no box constructor's cell and no array element holds more
// counted references than a header counts.
mlir::LogicalResult cellsFit(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);

} // namespace idr::expect

#endif // IDR_TRANSFORMS_EXPECT_H
