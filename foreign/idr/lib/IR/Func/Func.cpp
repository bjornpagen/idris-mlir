// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.func: its text, the closed program (every function defined, the one
// public function the root), the module's rules, which the root's
// symbol-use verifier runs, and the rules of one function, which run after
// the ops of its body are verified and in parallel with every other
// function's.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Verify.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/Interfaces/FunctionImplementation.h"

using namespace mlir;
using namespace idr;

// func.func's syntax: the facts print as the remaining inherent attributes
// after `attributes`, and the body's ops without the dialect's prefix.
ParseResult idr::FuncOp::parse(OpAsmParser &parser, OperationState &result) {
  auto buildFuncType = [](Builder &builder, ArrayRef<Type> inputs, ArrayRef<Type> results,
                          function_interface_impl::VariadicFlag, std::string &) {
    return FunctionType::get(builder.getContext(), inputs, results);
  };
  if (failed(function_interface_impl::parseFunctionOp(
          parser, result, /*allowVariadic=*/false, getFunctionTypeAttrName(result.name),
          buildFuncType, getArgAttrsAttrName(result.name), getResAttrsAttrName(result.name))))
    return failure();
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

// Every function of the program is defined in it, and a public one is the
// root, which takes a world or returns an i64. Only the op is read.
LogicalResult idr::FuncOp::verify() {
  if (getBody().empty())
    return emitOpError("expects a body: every function of the program is defined in it");
  if (!isPublic())
    return success();
  FunctionType type = getFunctionType();
  Builder b(getContext());
  bool intRoot = type.getInputs().empty() && type.getNumResults() == 1 &&
                 type.getResult(0) == b.getI64Type();
  bool ioRoot = type.getInputs().size() == 1 && isWorld(type.getInput(0));
  if (!intRoot && !ioRoot)
    return emitOpError("is the root, so its type must be () -> i64 or (!idr.world) -> (...), not ")
           << type;
  return success();
}

// The root runs the module's rules once per verification of the module,
// after every op of it is verified: MLIR calls this only from the module's
// own verification, on one thread, so no pass manager verifying one
// function meets the rules, nor reads a sibling another thread rewrites.
LogicalResult idr::FuncOp::verifySymbolUses(SymbolTableCollection &) {
  if (!isPublic())
    return success();
  auto module = dyn_cast_or_null<ModuleOp>((*this)->getParentOp());
  return module ? verify::program(module) : success();
}

// The interface's own body check has matched the entry block to the type,
// and the ops' verifiers have run: a match's regions and yields are well
// formed. Every closure and suspension moves along an edge its op
// declares; the stage is this function's, by its own grades.
LogicalResult idr::FuncOp::verifyRegions() {
  WalkResult flow = getBody().walk([](Operation *op) {
    return failed(verifyFlow(op)) ? WalkResult::interrupt() : WalkResult::advance();
  });
  if (flow.wasInterrupted())
    return failure();
  verify::Numbering numbering(*this);
  if (failed(verify::linearity(numbering)))
    return failure();
  if (!numbering.owned())
    return success();
  return verify::owned(*this);
}
