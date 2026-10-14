// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-expect: properties of a module that tests state by name, instead of
// matching the ops that happen to show them. Each property is a function
// that reports every place it fails, one error each, and changes nothing.
// What a property needs of the module beyond its ops (the symbol table, the
// references among functions, the cells' layouts) it asks of the analysis
// manager, so properties that ask the same share one answer and the pass
// keeps nothing between runs.
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
class References;

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

// Whether `fn` is the function `f` or a copy of it: its symbol is `f`, it
// is an instance of the Idris definition `f`, or it is a clone whose key
// names `f` or a function that is.
bool names(mlir::FunctionOpInterface fn, llvm::StringRef f, mlir::SymbolTable &symbols);

// The functions `function` (`@f`) names, by `names`; none, after an error
// of `property`, when it names none.
llvm::SmallVector<mlir::FunctionOpInterface> named(mlir::ModuleOp module, mlir::SymbolTable &symbols,
                                                   llvm::StringRef function,
                                                   llvm::StringRef property);

// The roots a property of ops is checked under: the module, without
// `function`, or the functions it names.
llvm::SmallVector<mlir::Operation *> rootsOf(mlir::ModuleOp module, mlir::SymbolTable &symbols,
                                             llvm::StringRef function, llvm::StringRef property);

// The functions the body of `fn` names, by a call, a closure or a closure
// constant, in the order References met them.
llvm::SmallVector<mlir::Operation *> referencedBy(References &references, mlir::Operation *fn);

// The cycles among `nodes` by `edges`, an edge to a node outside `nodes`
// dropped: each strongly connected component of two or more, or of one
// that refers to itself, callees first.
llvm::SmallVector<llvm::SmallVector<mlir::Operation *>>
cycles(llvm::ArrayRef<mlir::Operation *> nodes,
       llvm::function_ref<llvm::SmallVector<mlir::Operation *>(mlir::Operation *)> edges);

// The properties, one per name `lookup` knows.
mlir::LogicalResult noClosures(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult noHeapAllocation(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult everyCycleHasBreaker(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult breaksLast(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult oneClone(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult notCalled(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult quantitiesKept(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult reusesInPlace(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult movesOut(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult countsNothing(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult inBounds(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult boundsChecked(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult noGuards(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult testsNothing(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult resetsUnshared(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult reusesEveryCell(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult contified(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult factsAsMarked(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult outputFused(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult foldsBalanced(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult constantStack(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult countedLoop(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult wordLoop(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult pureArrayLoops(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult vectorized(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult narrowedLanes(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);
mlir::LogicalResult cellsFit(mlir::ModuleOp, mlir::AnalysisManager &, llvm::StringRef);

} // namespace idr::expect

#endif // IDR_TRANSFORMS_EXPECT_H
