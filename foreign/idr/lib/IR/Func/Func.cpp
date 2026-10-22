// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.program and idr.func: the closed program, whose root is its property
// and whose region verifier checks the root and runs the program's rules;
// a function's text, its row before its symbol and no visibility written,
// since its program's root decides it; and the rules of one function, which
// run after the ops of its body are verified and in parallel with every
// other function's: its stage's, its row's and its tail calls'.

#include "idr/Analysis/Effects.h"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Tail.h"
#include "idr/IR/Verify.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/FunctionImplementation.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "llvm/ADT/STLExtras.h"

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

//===----------------------------------------------------------------------===//
// idr.func
//===----------------------------------------------------------------------===//

ProgramOp idr::FuncOp::getProgram() { return cast<ProgramOp>((*this)->getParentOp()); }

bool idr::FuncOp::isRoot() {
  auto program = dyn_cast_or_null<ProgramOp>((*this)->getParentOp());
  return program && program.getRootAttr() &&
         program.getRootAttr().getAttr() == getSymNameAttr();
}

// Symbol's visibility, read off the program's root: public for the root,
// private for every other function. isPublic, isPrivate and
// canDiscardOnUseEmpty all ask this. Setting it changes nothing: the root
// is the program's to name.
SymbolTable::Visibility idr::FuncOp::getVisibility() {
  return isRoot() ? SymbolTable::Visibility::Public : SymbolTable::Visibility::Private;
}
void idr::FuncOp::setVisibility(SymbolTable::Visibility) {}

StringRef idr::FuncOp::getDefaultDialect() { return IdrDialect::getDialectNamespace(); }

Region *idr::FuncOp::getCallableRegion() { return &getBody(); }
ArrayRef<Type> idr::FuncOp::getArgumentTypes() { return getFunctionType().getInputs(); }
ArrayRef<Type> idr::FuncOp::getResultTypes() { return getFunctionType().getResults(); }
Type idr::FuncOp::cloneTypeWith(TypeRange inputs, TypeRange results) {
  return FunctionType::get(getContext(), inputs, results);
}
// Every function of the program is defined in it, its body the one block
// its region holds.
bool idr::FuncOp::isExternal() { return false; }

// The function's body binds its index binders; nothing else of it binds.
ArrayRef<families::Sort> idr::FuncOp::getBoundSorts(Region &) {
  if (IndexBindersAttr binders = getBindersAttr())
    return binders.getSorts();
  return {};
}

namespace {

// The facts the function's text writes before its symbol, as properties
// (`<{row = ...}>`): every inherent attribute the function's own syntax
// writes stays there (its symbol, its type, its parameters' and results'
// attributes in the signature; the rest in `attributes`).
SmallVector<StringRef> writtenElsewhere(OperationName name) {
  return {FuncOp::getSymNameAttrName(name), FuncOp::getFunctionTypeAttrName(name),
          FuncOp::getArgAttrsAttrName(name),  FuncOp::getResAttrsAttrName(name),
          FuncOp::getBindersAttrName(name),   FuncOp::getUntouchedAttrName(name),
          FuncOp::getBoundedAttrName(name),   FuncOp::getTerminatesAttrName(name)};
}

} // namespace

// func.func's syntax without its visibility, which the program's root
// decides, and with its row before its symbol, `idr.func <{row = ...}>
// @f(...)`, written only when it is not every atom. Then the body's ops
// without the dialect's prefix.
ParseResult idr::FuncOp::parse(OpAsmParser &parser, OperationState &result) {
  if (parseProperties(parser, result))
    return failure();
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
  printer << ' ';
  printProperties(getContext(), printer, getProperties(), writtenElsewhere(getOperation()->getName()));
  function_interface_impl::printFunctionOp(printer, *this, /*isVariadic=*/false,
                                           getFunctionTypeAttrName(), getArgAttrsAttrName(),
                                           getResAttrsAttrName());
}

// The interface's own body check has matched the entry block to the type,
// and the ops' verifiers have run: a match's regions and yields are well
// formed. Then the function's rules at its program's stage, its row, which
// covers what its body does, and its tail calls, each where it stands.
LogicalResult idr::FuncOp::verifyRegions() {
  if (failed(verify::function(*this)) || failed(rows::verify(*this)))
    return failure();
  return tail::verify(*this);
}
