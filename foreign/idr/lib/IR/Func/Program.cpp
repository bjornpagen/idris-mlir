// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.program: the closed program, whose root is its property and whose
// region verifier checks the root and runs the program's rules.

#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Verify.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

void idr::ProgramOp::build(OpBuilder &builder, OperationState &state, StringRef name,
                           StringRef root, Stage stage) {
  Properties &properties = state.getOrAddProperties<Properties>();
  properties.sym_name = builder.getStringAttr(name);
  properties.root = FlatSymbolRefAttr::get(builder.getContext(), root);
  properties.stage = stage;
  state.addRegion()->emplaceBlock();
}

// A module holds one program, the closed world every pass reads: the first
// in its module's block, and none after it. Only that block's ops are
// read, which no pass on a program changes.
LogicalResult idr::ProgramOp::verify() {
  ProgramOp first = *(*this)->getBlock()->getOps<ProgramOp>().begin();
  if (first != *this)
    return emitOpError("@") << getSymName() << " is a second program beside @"
                            << first.getSymName() << ", and a module holds one program";
  return success();
}

FuncOp idr::ProgramOp::lookupRoot() {
  return dyn_cast_or_null<FuncOp>(
      mlir::SymbolTable::lookupSymbolIn(getOperation(), getRootAttr().getAttr()));
}

// A program is the whole of what runs: nothing outside it discards it.
SymbolTable::Visibility idr::ProgramOp::getVisibility() { return SymbolTable::Visibility::Public; }
void idr::ProgramOp::setVisibility(SymbolTable::Visibility) {}

// The root, checked once: a function of the program that takes nothing.
// Before the program is lowered it is an idr.func whose every result holds
// no runtime value (a unit, an IO result of a unit); lowered, upstream's
// function, which gives nothing back. Which kind of function a stage holds
// is each op's legal stages, not this rule's: the root is whichever is
// there. Then the program's rules. MLIR runs this after every op of the
// program is verified and, by the program's symbol table, every call's
// symbol uses; on one thread; when the module is read and after every pass
// on the program, so a program pass that breaks a rule fails where it
// breaks it.
LogicalResult idr::ProgramOp::verifyRegions() {
  Operation *root = mlir::SymbolTable::lookupSymbolIn(getOperation(), getRootAttr().getAttr());
  auto function = dyn_cast_or_null<FunctionOpInterface>(root);
  if (!function)
    return emitOpError("has root ") << getRootAttr() << ", which is no function of the program";
  if (!function.getArgumentTypes().empty())
    return root->emitOpError("is the root, so it takes nothing; it takes ")
           << function.getArgumentTypes().size() << " arguments";
  if (isa<FuncOp>(root)) {
    if (!llvm::all_of(function.getResultTypes(),
                      [](Type result) { return layout::holdsNoComponent(result); }))
      return root->emitOpError("is the root, so its results hold no runtime value");
  } else if (!function.getResultTypes().empty()) {
    return root->emitOpError("is the root of a lowered program, so it gives nothing back");
  }
  return verify::program(*this);
}
