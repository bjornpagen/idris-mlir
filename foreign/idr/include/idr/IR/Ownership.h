// What the owned stage's verifier and the ownership passes share: what a
// use does with a reference, which values no count reaches, and whether a
// function is in the owned stage. The grades are the stage: a value of
// grade own or excl exists only after idr-rc gives one, so no attribute
// restates it.
#ifndef IDR_IR_OWNERSHIP_H
#define IDR_IR_OWNERSHIP_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Value.h"
#include "llvm/ADT/STLFunctionalExtras.h"

namespace idr::ownership {

// What a use does with a reference in the owned stage: consumes one, or
// only needs the value to be alive.
enum class Use { Consume, Borrow };

// The op that uses `operand` declares which (idr::consumes): returns, scf's
// yields, a call's owned parameters and the operands ODS names beside each
// idr op consume; everything else borrows, the closure an apply calls
// included. A force is placement's: idr-rc gives it its cell owned where
// the cell dies, and there it takes the cell over; anywhere else it reads a
// view. `symbols` is for the passes that ask before the operands of a call
// take their callee's grades.
Use useOf(mlir::OpOperand &operand, mlir::SymbolTable *symbols = nullptr);

// Whether `value` is static: a constant, poison, or a field read from one.
bool isStatic(mlir::Value value);

// The value a field was read from: the operand of an idr.field, or the
// scrutinee of the match whose region binds it; null for any other value.
mlir::Value readFrom(mlir::Value value);

// The owned value a view was read from: through idr.borrow, idr.field,
// lin.enter, lin.use and the fields a match's region binds.
mlir::Value viewRoot(mlir::Value value);

// Whether `view` is static data that reaches no cell but atoms, which is in
// every exclusive tree. `declaration` finds the declaration a constant
// constructor's type names, from whatever the caller holds.
bool reachesOnlyAtoms(mlir::Value view, llvm::function_ref<DataOp(mlir::Type)> declaration);

// Whether `op`'s region is the body of a loop over an array, which runs
// once per index it covers.
bool isArrayLoop(mlir::Operation *op);

// Whether `fn` is in the owned stage: a value of it, an argument of any of
// its blocks or a result of any of its ops, is owned or exclusive.
bool inOwnedStage(FuncOp fn);

} // namespace idr::ownership

#endif // IDR_IR_OWNERSHIP_H
