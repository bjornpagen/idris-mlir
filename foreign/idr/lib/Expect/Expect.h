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

// Whether the function named `name` is `origin` or a clone of it: a
// specialization or a raised copy whose chain of keys (idr.clone) leads to
// `origin`.
bool isCloneOf(mlir::SymbolTable &symbols, llvm::StringRef name, llvm::StringRef origin);

// The functions `function` (`@f`) names: @f itself, when the module still
// has it, and every clone of it (a specialization, a raised copy), which
// keeps the location that names the definition it was copied from; or
// none, after the error that `property` names no function. A property
// stated of @f holds of all of them.
llvm::SmallVector<mlir::func::FuncOp> named(mlir::ModuleOp module, llvm::StringRef function,
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

// No string is built only to be written: idr.io.put_str never writes what
// idr.str.append, cons, from_char or show made.
mlir::LogicalResult outputFused(mlir::ModuleOp module, llvm::StringRef);

// The folders released every reference they took from the runtime: it holds
// no live cell (on the calling thread).
mlir::LogicalResult foldsBalanced(mlir::ModuleOp module, llvm::StringRef);

// In the function the argument names, every box is built in the cell of
// one that died (idr.reuse), and at least one is: no box gets a fresh cell.
mlir::LogicalResult reusesInPlace(mlir::ModuleOp module, llvm::StringRef function);

// The function the argument names counts no reference: no idr.dup, no
// idr.drop.
mlir::LogicalResult countsNothing(mlir::ModuleOp module, llvm::StringRef function);

// The function the argument names tests no count and no null: every take
// in it is of an exclusive value, every reuse builds in an exclusive
// cell, and there is at least one take.
mlir::LogicalResult testsNothing(mlir::ModuleOp module, llvm::StringRef function);

// Every take of a box, in the function the argument names or
// in every function, tests a cell that its function never gives a second
// reference: no idr.dup of a view of the box or of a value it was read from.
mlir::LogicalResult resetsUnshared(mlir::ModuleOp module, llvm::StringRef function) noexcept;

// In the function the argument names, every cell a take yields
// for a constructor with fields is reused: no idr.drop frees one.
mlir::LogicalResult reusesEveryCell(mlir::ModuleOp module, llvm::StringRef function) noexcept;

// No private function is called once, from another function, and nothing
// else: every continuation was inlined into the function it continues.
mlir::LogicalResult contified(mlir::ModuleOp module, llvm::StringRef) noexcept;

// Every recursion reachable from the function the argument names became a
// loop: none of the functions it may call is on a cycle of references.
mlir::LogicalResult constantStack(mlir::ModuleOp module, llvm::StringRef function);

// The function the argument names loops, and each of its loops is an
// scf.for, whose trip count is known before it starts.
mlir::LogicalResult countedLoop(mlir::ModuleOp module, llvm::StringRef function);

// Some loop of the function the argument names computes on words alone: no
// value in it is a big or a natural (idr-narrow).
mlir::LogicalResult wordLoop(mlir::ModuleOp module, llvm::StringRef function);

} // namespace idr::expect
