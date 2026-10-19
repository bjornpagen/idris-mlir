// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-expect: properties of a module that tests state by name, instead of
// matching the ops that happen to show them. Each property is a check that
// reports every place it fails, one error each, and changes nothing. What a
// property needs of the module beyond its ops (the symbol table, the cells'
// layouts) it asks of the analysis manager, so properties that ask the same
// share one answer and the pass keeps nothing between runs. The table of
// properties (Lookup.cpp) is the one list of what idr-expect checks: a row
// holds a property's name once, pairs it with the shape of its argument,
// which the row's type checks, and says what it checks. A request's
// argument is read once, before its check runs, into the typed value of its
// shape (ExpectArguments.h): a function named, a count, a list, a module
// read from a file.
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

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/ExpectArguments.h"

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

// Registers test-idr-facts, the pass that reports what the dialect answers
// about each op of a function's body as a remark, for the effects' tests.
void registerFactsTestPass();
} // namespace idr

namespace idr::expect {

// What a check is given: the module, the pass's analyses, the name it was
// asked by, which its errors carry, and its argument, read.
template <typename A> struct Request {
  mlir::ModuleOp module;
  mlir::AnalysisManager &analyses;
  llvm::StringRef property;
  const A &argument;
};

// A row of the table: a property's name, and what checks a request of it,
// the text after `=` (empty when there is none) read by its argument's
// parser, then its check run. Fails when it reported an error.
struct Property {
  llvm::StringRef name;
  mlir::LogicalResult (*run)(mlir::ModuleOp module, mlir::AnalysisManager &analyses,
                             llvm::StringRef property, llvm::StringRef text);
};

// The row of `Check` under `name`: its argument is of shape A, so a check
// paired with an argument of another shape does not compile.
template <typename A, mlir::LogicalResult (*Check)(const Request<A> &)>
constexpr Property property(llvm::StringRef name) {
  return {name, [](mlir::ModuleOp module, mlir::AnalysisManager &analyses, llvm::StringRef asked,
                   llvm::StringRef text) -> mlir::LogicalResult {
            mlir::FailureOr<A> argument = A::parse(Written{module, asked, text, A::form}, text);
            if (mlir::failed(argument))
              return mlir::failure();
            return Check(Request<A>{module, analyses, asked, *argument});
          }};
}

// The row of the property named `name`, or null when there is none.
const Property *lookup(llvm::StringRef name);

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

// The functions the body of `fn` names by a symbol use (a call, a closure,
// a constant), in the order the walk meets them, each once.
llvm::SmallVector<mlir::Operation *> callees(mlir::SymbolTable &symbols, mlir::Operation *fn);

// The cycles among `nodes` by `edges`, an edge to a node outside `nodes`
// dropped: each strongly connected component of two or more, or of one
// that refers to itself, callees first.
llvm::SmallVector<llvm::SmallVector<mlir::Operation *>>
cycles(llvm::ArrayRef<mlir::Operation *> nodes,
       llvm::function_ref<llvm::SmallVector<mlir::Operation *>(mlir::Operation *)> edges);

// Whether `call` calls `g`: its callee's symbol is g, or it calls a
// function of `symbols` made from the code written as g (`names`).
bool callsNamed(mlir::CallOpInterface call, const Symbol &g, mlir::SymbolTable &symbols);

// How many places of `fn` may crash: an idr op that never returns, a
// guard, or a call of the LLVM dialect that never returns (the call says
// so, or its callee in `symbols`).
unsigned crashSitesOf(mlir::FunctionOpInterface fn, mlir::SymbolTable &symbols);

// The checks, by the shape of their argument; the table says what each
// checks. quantitiesKept and foldsBalanced are the contracts' too, which
// call them with the module before a pass and nothing.
mlir::LogicalResult noClosures(const Request<Roots> &);
mlir::LogicalResult labels(const Request<Labels> &);
mlir::LogicalResult labelsLeast(const Request<Nothing> &);
mlir::LogicalResult noHeapAllocation(const Request<Roots> &);
mlir::LogicalResult oneClone(const Request<Symbol> &);
mlir::LogicalResult specializedOnce(const Request<Functions> &);
mlir::LogicalResult notCalled(const Request<Symbol> &);
mlir::LogicalResult quantitiesKept(const Request<Module> &);
mlir::LogicalResult reusesInPlace(const Request<Functions> &);
mlir::LogicalResult movesOut(const Request<Roots> &);
mlir::LogicalResult countsNothing(const Request<Functions> &);
mlir::LogicalResult noGuards(const Request<Functions> &);
mlir::LogicalResult testsNothing(const Request<Functions> &);
mlir::LogicalResult exclusiveCopy(const Request<Functions> &);
mlir::LogicalResult resetsUnshared(const Request<Roots> &);
mlir::LogicalResult reusesEveryCell(const Request<Functions> &);
mlir::LogicalResult contified(const Request<Nothing> &);
mlir::LogicalResult outputFused(const Request<Roots> &);
mlir::LogicalResult foldsBalanced(const Request<Nothing> &);
mlir::LogicalResult folded(const Request<Functions> &);
mlir::LogicalResult constantStack(const Request<Functions> &);
mlir::LogicalResult tailCalls(const Request<Pair> &);
mlir::LogicalResult countedLoop(const Request<Functions> &);
mlir::LogicalResult wordLoop(const Request<Functions> &);
mlir::LogicalResult structuredLoops(const Request<Roots> &);
mlir::LogicalResult inPlace(const Request<Roots> &);
mlir::LogicalResult fused(const Request<Functions> &);
mlir::LogicalResult largestFunction(const Request<Bound> &);
mlir::LogicalResult vectorized(const Request<Roots> &);
mlir::LogicalResult narrowedLanes(const Request<Roots> &);
mlir::LogicalResult matches(const Request<Functions> &);
mlir::LogicalResult matchesNothing(const Request<Functions> &);
mlir::LogicalResult forcesSome(const Request<Functions> &);
mlir::LogicalResult forcesNothing(const Request<Functions> &);
mlir::LogicalResult buildsSome(const Request<Functions> &);
mlir::LogicalResult buildsNothing(const Request<Functions> &);
mlir::LogicalResult readsFields(const Request<Functions> &);
mlir::LogicalResult readsNoFields(const Request<Functions> &);
mlir::LogicalResult applies(const Request<Functions> &);
mlir::LogicalResult neverReturns(const Request<Functions> &);
mlir::LogicalResult calls(const Request<Pair> &);
mlir::LogicalResult neverCalls(const Request<Pair> &);
mlir::LogicalResult callsClosed(const Request<Pair> &);
mlir::LogicalResult returnsConstants(const Request<ReturnedValues> &);
mlir::LogicalResult returnsOnPaths(const Request<PathValues> &);
mlir::LogicalResult returnsArguments(const Request<ReturnedArguments> &);
mlir::LogicalResult buildsWhereUsed(const Request<Functions> &);
mlir::LogicalResult callsWhereUsed(const Request<Pair> &);
mlir::LogicalResult matchesOnce(const Request<Functions> &);
mlir::LogicalResult crashesBeforeOutput(const Request<Functions> &);
mlir::LogicalResult parametersUsed(const Request<Functions> &);
mlir::LogicalResult resultsUsed(const Request<Functions> &);
mlir::LogicalResult regionsDistinct(const Request<Functions> &);
mlir::LogicalResult checksEveryPath(const Request<Functions> &);
mlir::LogicalResult growsNothing(const Request<FunctionsAndModule> &);
mlir::LogicalResult callOrder(const Request<Listed> &);
mlir::LogicalResult callsDistinct(const Request<Pair> &);
mlir::LogicalResult callsRead(const Request<Pair> &);
mlir::LogicalResult callsOnly(const Request<Listed> &);
mlir::LogicalResult directCalls(const Request<Roots> &);
mlir::LogicalResult crashSites(const Request<CountOf> &);
mlir::LogicalResult lowered(const Request<Roots> &);
mlir::LogicalResult inLLVM(const Request<Nothing> &);
mlir::LogicalResult signature(const Request<TypeOf> &);
mlir::LogicalResult convention(const Request<ConventionOf> &);
mlir::LogicalResult entry(const Request<Nothing> &);
mlir::LogicalResult linkerNames(const Request<Nothing> &);
mlir::LogicalResult loops(const Request<Loops> &);
mlir::LogicalResult straightLine(const Request<Functions> &);
mlir::LogicalResult alignedAccess(const Request<Roots> &);
mlir::LogicalResult readsNothing(const Request<Functions> &);
mlir::LogicalResult writesNothing(const Request<Functions> &);
mlir::LogicalResult solvedEffects(const Request<EffectsOf> &);
mlir::LogicalResult computesNothing(const Request<Functions> &);
mlir::LogicalResult dimsKnown(const Request<Functions> &);
mlir::LogicalResult byName(const Request<Symbol> &);
mlir::LogicalResult notByName(const Request<Symbol> &);
mlir::LogicalResult total(const Request<Functions> &);
mlir::LogicalResult notTotal(const Request<Functions> &);
mlir::LogicalResult apart(const Request<TwoFunctions> &);
mlir::LogicalResult reaches(const Request<Pair> &);
mlir::LogicalResult stage(const Request<StageIs> &);

} // namespace idr::expect

#endif // IDR_TRANSFORMS_EXPECT_H
