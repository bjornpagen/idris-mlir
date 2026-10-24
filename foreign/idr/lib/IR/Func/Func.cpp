// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.func's members that implement its interfaces (a symbol, a callable,
// a function, the binder of its index binders, an op stating its
// parameters' lifetimes) and its text: func.func's, its row before its
// symbol and no visibility written, since its program's root decides it.

#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/FunctionImplementation.h"
#include "mlir/Interfaces/FunctionInterfaces.h"

#include <cstdint>
#include <optional>
#include <string>

using namespace mlir;
using namespace idr;

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
          FuncOp::getBindersAttrName(name),   FuncOp::getExtentsAttrName(name),
          FuncOp::getUntouchedAttrName(name), FuncOp::getBoundedAttrName(name),
          FuncOp::getTerminatesAttrName(name), FuncOp::getLivesInAttrName(name),
          FuncOp::getCopyAttrName(name)};
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

//===----------------------------------------------------------------------===//
// The lifetimes a function states
//===----------------------------------------------------------------------===//

// A scoped parameter lives in the lifetime parameter its signature names,
// one search away; nothing else of the function is stated here.
Value idr::FuncOp::getStatedLifetime(Value made) {
  auto parameter = dyn_cast<BlockArgument>(made);
  LivesInAttr lives = getLivesInAttr();
  if (!parameter || !lives || parameter.getOwner() != &getBody().front())
    return nullptr;
  std::optional<std::uint32_t> lifetime = lives.lifetimeOfParameter(parameter.getArgNumber());
  return lifetime ? getBody().front().getArgument(*lifetime) : Value();
}

// A function states a parameter's lifetime only as one of its own
// parameters; given null, as a copy whose parameter is no longer scoped is
// restated, or anything else, it states none, and its verifier names a
// scoped parameter left without one. One entry per parameter, so stating
// it again replaces it.
void idr::FuncOp::setStatedLifetime(Value made, Value lifetime) {
  Block &entry = getBody().front();
  auto parameter = dyn_cast<BlockArgument>(made);
  if (!parameter || parameter.getOwner() != &entry)
    return;
  auto in = dyn_cast_or_null<BlockArgument>(lifetime);
  std::optional<std::uint32_t> stated;
  if (in && in.getOwner() == &entry)
    stated = in.getArgNumber();
  setLivesInAttr(LivesInAttr::restateParameter(getContext(), getLivesInAttr(),
                                               parameter.getArgNumber(), stated));
}
