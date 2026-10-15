// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 0 of idr-lower: idr.func, idr.call and idr.return become func.func,
// func.call and func.return under the mangled names. What LLVM learns of a
// function's values was read before this; its other facts were for the
// passes that are over, and go with the op.

#include "idr/IR/IdrDialect.h"
#include "idr/Conversion/FuncToFunc.h"
#include "idr/Conversion/Mangle.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"
#include "llvm/ADT/STLExtras.h"

#include <string>

using namespace mlir;

namespace idr::conversion {

namespace {

// The calls and returns of a function's body, in every block of it.
void lowerCallsAndReturns(func::FuncOp fn) {
  fn.walk([](Operation *op) {
    OpBuilder b(op);
    Operation *lowered = nullptr;
    if (auto call = dyn_cast<idr::CallOp>(op))
      lowered = func::CallOp::create(b, call.getLoc(), mangle(call.getCallee()),
                                     call.getResultTypes(), call.getArgs());
    else if (isa<idr::ReturnOp>(op))
      lowered = func::ReturnOp::create(b, op->getLoc(), op->getOperands());
    if (!lowered)
      return;
    op->replaceAllUsesWith(lowered->getResults());
    op->erase();
  });
}

} // namespace

LogicalResult lowerFunctions(ProgramOp program, SymbolTable &symbols) {
  StringRef root = program.getRoot();
  std::string rootName = mangle(root);
  for (auto fn : llvm::make_early_inc_range(program->getRegion(0).getOps<idr::FuncOp>())) {
    OpBuilder b(fn);
    auto lowered =
        func::FuncOp::create(b, fn.getLoc(), mangle(fn.getSymName()), fn.getFunctionType());
    lowered.setVisibility(fn.getSymName() == root ? SymbolTable::Visibility::Public
                                                  : SymbolTable::Visibility::Private);
    lowered.getBody().takeBody(fn.getBody());
    lowerCallsAndReturns(lowered);
    symbols.erase(fn);
    // The mangling is injective, and a symbol the frontend or a pass names
    // never holds a code point's escape, so the name is the function's own;
    // the table would rename a function that met another symbol there.
    if (symbols.lookup(lowered.getSymNameAttr()))
      return lowered.emitError() << "internal error: idr-lower: @" << lowered.getSymName()
                                 << " names another symbol of the program";
    symbols.insert(lowered);
  }
  program.setRootAttr(FlatSymbolRefAttr::get(program.getContext(), rootName));
  return success();
}

} // namespace idr::conversion
