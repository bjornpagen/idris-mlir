// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.program and idr.func: the closed program, whose root is its property
// and whose symbol-use verifier runs the program's rules; a function's
// text, with no visibility written, since its program's root decides it;
// and the rules of one function at its program's stage, which run after the
// ops of its body are verified and in parallel with every other
// function's.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Verify.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/FunctionImplementation.h"
#include "mlir/Interfaces/FunctionInterfaces.h"

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// idr.program
//===----------------------------------------------------------------------===//

void idr::ProgramOp::build(OpBuilder &builder, OperationState &state, StringRef name,
                           StringRef root, Stage stage) {
  Properties &properties = state.getOrAddProperties<Properties>();
  properties.sym_name = builder.getStringAttr(name);
  properties.root = FlatSymbolRefAttr::get(builder.getContext(), root);
  properties.stage = StageAttr::get(builder.getContext(), stage);
  state.addRegion()->emplaceBlock();
}

FuncOp idr::ProgramOp::lookupRoot() {
  return dyn_cast_or_null<FuncOp>(
      mlir::SymbolTable::lookupSymbolIn(getOperation(), getRootAttr().getAttr()));
}

// The root is a function of the program, an idr.func until the program
// is lowered and upstream's function after: every idr.func's visibility is
// read from it. Only the op and its block are read, after its ops are
// verified.
LogicalResult idr::ProgramOp::verifyRegions() {
  if (!isa_and_nonnull<FunctionOpInterface>(
          mlir::SymbolTable::lookupSymbolIn(getOperation(), getRootAttr().getAttr())))
    return emitOpError("has root ") << getRootAttr() << ", which is no function of the program";
  return success();
}

// The program's rules run once per verification of the module that holds
// it, after every op of it is verified: MLIR calls this only from the
// module's own verification, on one thread, so no pass manager verifying
// the program or one function meets the rules, nor reads a function
// another thread rewrites.
LogicalResult idr::ProgramOp::verifySymbolUses(SymbolTableCollection &) {
  return verify::program(*this);
}

//===----------------------------------------------------------------------===//
// idr.func
//===----------------------------------------------------------------------===//

ProgramOp idr::FuncOp::getProgram() { return cast<ProgramOp>((*this)->getParentOp()); }

bool idr::FuncOp::isRoot() {
  auto program = dyn_cast_or_null<ProgramOp>((*this)->getParentOp());
  return program && program.getRootAttr() &&
         program.getRootAttr().getAttr() == getSymNameAttr();
}

// func.func's syntax without its visibility, which the program's root
// decides: the facts print as the remaining inherent attributes after
// `attributes`, and the body's ops without the dialect's prefix.
ParseResult idr::FuncOp::parse(OpAsmParser &parser, OperationState &result) {
  auto buildFuncType = [](Builder &builder, ArrayRef<Type> inputs, ArrayRef<Type> results,
                          function_interface_impl::VariadicFlag, std::string &) {
    return FunctionType::get(builder.getContext(), inputs, results);
  };
  SMLoc loc = parser.getCurrentLocation();
  if (failed(function_interface_impl::parseFunctionOp(
          parser, result, /*allowVariadic=*/false, getFunctionTypeAttrName(result.name),
          buildFuncType, getArgAttrsAttrName(result.name), getResAttrsAttrName(result.name))))
    return failure();
  if (result.attributes.get(SymbolOpInterface::getDefaultVisibilityAttrName()))
    return parser.emitError(loc, "a function's visibility is not written: its program's root is "
                                 "public, and every other function private");
  // The facts arrive in `result.attributes` and become properties when
  // the op is created, which silently drops one of the wrong kind; the
  // generic parser checks them first, and a custom one must too.
  return verifyInherentAttrs(result.name, result.attributes, [&]() {
    return mlir::emitError(result.location) << "'" << result.name.getStringRef() << "' op ";
  });
}

void idr::FuncOp::print(OpAsmPrinter &printer) {
  function_interface_impl::printFunctionOp(printer, *this, /*isVariadic=*/false,
                                           getFunctionTypeAttrName(), getArgAttrsAttrName(),
                                           getResAttrsAttrName());
}

// Every function of the program is defined in it. Only the op is read.
LogicalResult idr::FuncOp::verify() {
  if (getBody().empty())
    return emitOpError("expects a body: every function of the program is defined in it");
  return success();
}

// The interface's own body check has matched the entry block to the type,
// and the ops' verifiers have run: a match's regions and yields are well
// formed. The rest is the function's rules at its program's stage.
LogicalResult idr::FuncOp::verifyRegions() { return verify::function(*this); }
