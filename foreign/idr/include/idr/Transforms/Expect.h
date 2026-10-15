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
// A property is stated of the program: the functions the module's
// idr.program holds, under its symbol table, before idr-lower; the
// functions of the module itself after it, which moves them out and erases
// the op. So one property reads a module of either stage.
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
#include "mlir/Interfaces/CallInterfaces.h"
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

// The op whose symbol table holds the program's functions: the module's
// idr.program, or the module once lowering has erased it.
mlir::Operation *programOf(mlir::ModuleOp module);

// The program's functions, in their order.
llvm::SmallVector<mlir::FunctionOpInterface> functionsOf(mlir::ModuleOp module);

// The program's symbol table, built once for every property that asks.
mlir::SymbolTable &symbolsOf(mlir::ModuleOp module, mlir::AnalysisManager &analyses);

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

// An argument `@f:<rest>`: the function, and what follows the first `:`;
// an empty function, after an error of `property`, when either is missing.
std::pair<llvm::StringRef, llvm::StringRef> splitAt(mlir::ModuleOp module, llvm::StringRef argument,
                                                    llvm::StringRef property);

// The functions a list names, `@g` or `[@g, @h, ...]`, in its order and
// without their `@`; `[]` names none.
llvm::SmallVector<llvm::StringRef> symbolList(llvm::StringRef list);

// Whether `call` calls `g`: its callee's symbol is `g`, or it calls a
// function of `symbols` made from the code written as `g` (`names`).
bool callsNamed(mlir::CallOpInterface call, llvm::StringRef g, mlir::SymbolTable &symbols);

// `no-closures`, `no-closures=@f`: no closure is built, applied or a
// constant, anywhere or in @f.
mlir::LogicalResult noClosures(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `labels=@f:<position>:[@g, ...]`: the type at that position of every copy
// of @f, a result (`result`, `result<n>`) or a parameter (`arg<n>`), is a
// sum of labels, of closures or of a memo cell, whose labels run exactly
// the functions the list names.
mlir::LogicalResult labels(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `no-heap-allocation`, `no-heap-allocation=@f`: nothing allocates a heap
// cell, anywhere, or in @f and every function it names.
mlir::LogicalResult noHeapAllocation(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `one-clone=@f`: every call of @f calls one function, and there is one.
mlir::LogicalResult oneClone(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `specialized-once=@f`: every copy of @f other than @f calls, of @f and its
// copies, only itself and @f: no specialization was made for a call in
// another, so a recursion's specializations stop after one step.
mlir::LogicalResult specializedOnce(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
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
// `moves-out`, `moves-out=@f`: anywhere or in @f, some element of an
// array is rebuilt in its place (idr.array.update, idr.element.update),
// moved out with the reference the array held.
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
// `exclusive-copy=@f`: some copy of @f takes every parameter that holds
// references at the exclusive grade: idr-rc gave @f a copy for exclusive
// arguments.
mlir::LogicalResult exclusiveCopy(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `resets-unshared`, `resets-unshared=@f`: every take of a box, anywhere or
// in @f, tests a cell that its function never gives a second reference.
mlir::LogicalResult resetsUnshared(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `reuses-every-cell=@f`: every cell a take in @f yields for a constructor
// with fields is reused, and none is freed.
mlir::LogicalResult reusesEveryCell(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `contified`: no function is called once, from another function
// that it calls back, and used nowhere else.
mlir::LogicalResult contified(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `facts-as-marked`: every op marked `expect.facts = "..."` answers the
// questions the mark lists, of `drop move delay merge` in that order, as
// the pass that asks each asks it: `drop` (dead once unused) and `merge`
// (two equal ones are one value) of the op's own effects, as upstream's
// dead code removal and CSE read them; `move` (across anything) and `delay`
// of the effects with a call's its callee's, as the dialect's rewrites read
// them.
mlir::LogicalResult factsAsMarked(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `output-fused`, `output-fused=@f`: no string is built only to be
// written, anywhere or in @f.
mlir::LogicalResult outputFused(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `folds-balanced`: the folders released every reference they took from
// the runtime.
mlir::LogicalResult foldsBalanced(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `constant-stack=@f`: no recursion from @f grows the stack: every function
// @f may call that is on a cycle of references refers to the others of its
// cycle only by guaranteed tail calls (`musttail`), so before
// idr-tail-calls none may be on a cycle at all.
mlir::LogicalResult constantStack(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `tail-calls=@f:@g`: every copy of @f calls @g or a copy of it, each call
// a guaranteed tail call (`musttail`, the return right after it).
mlir::LogicalResult tailCalls(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `counted-loop=@f`: @f loops, and each of its loops is an `scf.for`.
mlir::LogicalResult countedLoop(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `word-loop=@f`: some loop of @f computes on words alone: no value defined
// or bound in it is a big or a natural.
mlir::LogicalResult wordLoop(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `structured-loops`, `structured-loops=@f`: anywhere or in @f, no op is
// left that idr-structure-loops lowers, and some linalg op is there.
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
// `matches=@f`, `matches-nothing=@f`: @f takes some value apart by a
// match on a constructor or a literal, or none.
mlir::LogicalResult matches(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult matchesNothing(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `forces=@f`, `forces-nothing=@f`: @f forces some suspension, or none.
mlir::LogicalResult forcesSome(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult forcesNothing(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `builds=@f`, `builds-nothing=@f`: @f builds some value at run time (a
// constructor, in a fresh cell or a reused one, a closure, a suspension),
// or none: what it returns or holds is its parameters' or static data.
mlir::LogicalResult buildsSome(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult buildsNothing(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `reads-fields=@f`, `reads-no-fields=@f`: @f reads some field of a
// constructor value by idr.field, or none.
mlir::LogicalResult readsFields(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult readsNoFields(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `applies=@f`: @f applies some closure (no-closures=@f says none).
mlir::LogicalResult applies(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `never-returns=@f`: no path of @f returns.
mlir::LogicalResult neverReturns(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `calls=@f:@g`, `never-calls=@f:@g`: some call in @f calls @g or a copy
// of it, or none does; before lowering and after it, where @g may be a
// function of the runtime, by its symbol.
mlir::LogicalResult calls(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult neverCalls(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `calls-closed=@f:@g`: @f calls @g, and every call of it there takes
// constants alone.
mlir::LogicalResult callsClosed(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `returns=@f:<v>/<v>...`: every return of @f returns, as each result,
// the value written: a number (an integer of any width, or a float) by its
// value; `_`, computed at run time, no constant (a fold that must not
// happen); anything else an attribute as MLIR writes it (`#idr.big<-4>`,
// `"abc"`, `true`, `#idr.con<...>`), equal to the constant's. An item is
// read alone, outside the module's text, so a constructor writes its data
// type with its body, not by the module's alias. An item may be wrapped in
// parentheses, which keep the commas in it from splitting the list of
// properties; `/` splits items only outside brackets and quotes.
mlir::LogicalResult returnsConstants(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `returns-on-paths=@f:<v>+<v>...`: the one result of @f is, on each of its
// paths through its matches, one of the constants written (as `returns`
// writes them), and each of them on some path.
mlir::LogicalResult returnsOnPaths(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `returns-argument=@f:<n>/<n>...`: every return of @f returns, as each
// result, the parameter of that position.
mlir::LogicalResult returnsArguments(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `builds-where-used=@f`: every value @f builds at run time is used in the
// block that builds it, so none is built on a path that does not use it.
mlir::LogicalResult buildsWhereUsed(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `calls-where-used=@f:@g`: every call of @g or of a copy of it in @f whose
// results are used is used in the block that makes it, so none runs on a
// path that does not use it.
mlir::LogicalResult callsWhereUsed(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `matches-once=@f`: no match in @f tests a value that a match around it
// on the same value already decided (it sits in one of its cases, or in
// its default and has no case of its own).
mlir::LogicalResult matchesOnce(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `crashes-before-output=@f`: nothing @f writes may be written before
// something in @f that may crash, a call's writes and crashes its callee's.
mlir::LogicalResult crashesBeforeOutput(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `parameters-used=@f`: every parameter of @f is read in its body.
mlir::LogicalResult parametersUsed(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `results-used=@f`: every result of every match in @f is used.
mlir::LogicalResult resultsUsed(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `regions-distinct=@f`: no match in @f has two regions that do the same.
mlir::LogicalResult regionsDistinct(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `checks-every-path=@f`: @f checks something, and every check
// (`idr.check.*`) runs on every path through @f.
mlir::LogicalResult checksEveryPath(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `grows-nothing=@f:<file>`: every copy of @f holds at most as many
// operations as the function @f of the module in <file> held.
mlir::LogicalResult growsNothing(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `call-order=@f:[@g, @h, ...]`: every copy of @f calls each function
// the list names, in the list's order as its body is written.
mlir::LogicalResult callOrder(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `calls-distinct=@f:@g`: no call of @g or of a copy of it in @f makes a
// call that dominates it again, the same callee on the same operands.
mlir::LogicalResult callsDistinct(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `calls-read=@f:@g`: every call of @g or of a copy of it in @f gives a
// result that something reads.
mlir::LogicalResult callsRead(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `calls-only=@f:[@g, ...]`: every call of every copy of @f is of a
// function the list names; `[]`, none.
mlir::LogicalResult callsOnly(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `direct-calls`, `direct-calls=@f`: every call, anywhere or in @f, names
// its callee: none calls through a value.
mlir::LogicalResult directCalls(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `crash-sites=@f:<n>`: every copy of @f may crash at exactly n places:
// an idr op that never returns, a guard, or a call of a function that
// never returns.
mlir::LogicalResult crashSites(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `lowered`, `lowered=@f`: in the program or in @f, nothing of the idr
// dialect is left: no op, no type of a value, a block argument or a
// signature, no attribute of it, and no attribute named for a fact an
// idr.func holds; the program that holds the lowered functions aside.
mlir::LogicalResult lowered(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `in-llvm`: every op of the program is the LLVM dialect's.
mlir::LogicalResult inLLVM(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `signature=@f:<type>`: every copy of @f has that function type.
mlir::LogicalResult signature(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `convention=@f:<cc>`: every copy of @f is an llvm.func called by the
// convention LLVM spells <cc> (ccc, tailcc, ...).
mlir::LogicalResult convention(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `entry`: after idr-entry, the one public function with a body is @main,
// of the C entry's type (i32, !llvm.ptr) -> i32.
mlir::LogicalResult entry(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `linker-names`: every symbol the program defines is written in letters,
// digits, `_`, `.` and `$`.
mlir::LogicalResult linkerNames(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `loops=@f`, `loops=@f:<n>`: every copy of @f has a loop op, or exactly
// n of them.
mlir::LogicalResult loops(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `straight-line=@f`: every copy of @f runs one path: no op of it chooses
// among or repeats its regions, and no block ends in a choice of
// successors.
mlir::LogicalResult straightLine(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `aligned-access`, `aligned-access=@f`: anywhere or in @f, every LLVM
// load and store states its alignment.
mlir::LogicalResult alignedAccess(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `reads-nothing=@f`, `writes-nothing=@f`: no op of any copy of @f but a
// call reads, or writes, memory outside its own frame.
mlir::LogicalResult readsNothing(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult writesNothing(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);

// `effects=@f:<e>+<e>...`, `effects=@f:none`: every copy of @f is an
// idr.func whose effects, as idr-effects found them, are exactly those
// written, of io, crash and diverge; one no pass solved may do all three.
mlir::LogicalResult solvedEffects(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `computes-nothing=@f`: every op left in every copy of @f is a guard, an
// op that never returns, ub.unreachable or a terminator: it computes no
// value, and only what may crash is kept.
mlir::LogicalResult computesNothing(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `dims-known=@f`: no copy of @f asks an extent (a dimension op) of an
// array an op of it made: only of one it was given.
mlir::LogicalResult dimsKnown(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);

// `by-name=@f`, `not-by-name=@f`: every memo label of the program whose
// function is @f or a copy of it runs again at every force (`by_name`),
// or none does; and there is one.
mlir::LogicalResult byName(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult notByName(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `total=@f`, `not-total=@f`: every copy of @f is an idr.func that holds
// Idris's proof that its body's loops end, or that does not.
mlir::LogicalResult total(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult notTotal(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);

// `apart=@f:@g`: the functions written as @f and as @g are still two: some
// function is made from each, and none from both.
mlir::LogicalResult apart(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);

// `reaches=@f:@g`: from every copy of @f, the functions its body names,
// followed from body to body, include @g or a copy of it.
mlir::LogicalResult reaches(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
// `stage=<higher|first|owned|lowered>`: the module's program is at that
// stage.
mlir::LogicalResult stage(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);

} // namespace idr::expect

#endif // IDR_TRANSFORMS_EXPECT_H
