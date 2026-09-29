// idr-expect: properties of a module that tests state by name, instead of
// matching the ops that happen to show them. Each property is a function
// that reports every place it fails, one error each, and changes nothing.
#pragma once

#include "idr/Idr.h"

namespace idr::expect {

// The error that a property fails at `loc`, to which the caller adds what
// was found: `expected <property>: <what>`.
mlir::InFlightDiagnostic fail(mlir::Location loc, llvm::StringRef property);

// The name of the function that holds `op`, for an error's text.
std::string where(mlir::Operation *op);

// The function `function` (`@f`) names, or null after the error that
// `property` names none.
mlir::func::FuncOp named(mlir::ModuleOp module, llvm::StringRef function,
                         llvm::StringRef property);

// Every property takes the module and the text after `=` in its request
// (empty when there is none), and fails when it reported an error.
using Check = mlir::LogicalResult (*)(mlir::ModuleOp module, llvm::StringRef argument);

// No closure is built, applied or kept as a constant.
mlir::LogicalResult noClosures(mlir::ModuleOp module, llvm::StringRef);

// Nothing allocates on the heap: in the function the argument names and in
// everything it may call, or, without one, anywhere.
mlir::LogicalResult noHeapAllocation(mlir::ModuleOp module, llvm::StringRef function);

// Every cycle of references among functions has a loop breaker.
mlir::LogicalResult everyCycleHasBreaker(mlir::ModuleOp module, llvm::StringRef);

// Every call of the function the argument names, or of a clone of it, calls
// one and the same function.
mlir::LogicalResult oneClone(mlir::ModuleOp module, llvm::StringRef function);

// The quantities Idris proved are all still there: every parameter carries
// one, and every parameter and constructor field that comes from the
// module in the file the argument names has the quantity it has there.
mlir::LogicalResult quantitiesKept(mlir::ModuleOp module, llvm::StringRef emitted);

// What lib/Facts answers about each op marked `expect.facts = "..."` is
// what the mark says: the questions answered yes, in the order `drop move
// delay evaluate`.
mlir::LogicalResult factsAsMarked(mlir::ModuleOp module, llvm::StringRef);

// In the function the argument names, every box is built in the cell of
// one that died (idr.reuse), and at least one is: no box gets a fresh cell.
mlir::LogicalResult reusesInPlace(mlir::ModuleOp module, llvm::StringRef function);

// The function the argument names counts no reference: no idr.inc, no
// idr.dec.
mlir::LogicalResult countsNothing(mlir::ModuleOp module, llvm::StringRef function);

} // namespace idr::expect
