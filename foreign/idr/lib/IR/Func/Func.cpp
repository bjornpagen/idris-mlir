// idr.func: its text, the shape of its clone fact, and the rules of one
// function, which run after the ops of its body are verified and in
// parallel with every other function's.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Verify.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/Interfaces/FunctionImplementation.h"
#include "llvm/ADT/BitVector.h"

#include <optional>

using namespace mlir;
using namespace idr;

// func.func's syntax: the facts print as the remaining inherent attributes
// after `attributes`, and the body's ops without the dialect's prefix.
ParseResult idr::FuncOp::parse(OpAsmParser &parser, OperationState &result) {
  auto buildFuncType = [](Builder &builder, ArrayRef<Type> inputs, ArrayRef<Type> results,
                          function_interface_impl::VariadicFlag, std::string &) {
    return FunctionType::get(builder.getContext(), inputs, results);
  };
  return function_interface_impl::parseFunctionOp(
      parser, result, /*allowVariadic=*/false, getFunctionTypeAttrName(result.name),
      buildFuncType, getArgAttrsAttrName(result.name), getResAttrsAttrName(result.name));
}

void idr::FuncOp::print(OpAsmPrinter &printer) {
  function_interface_impl::printFunctionOp(printer, *this, /*isVariadic=*/false,
                                           getFunctionTypeAttrName(), getArgAttrsAttrName(),
                                           getResAttrsAttrName());
}

// A clone names itself, by the key every call of it was made for; a key
// that specializes has one hole per parameter, since the hole of a
// parameter is its position: its holes are 0 to n-1 for n parameters.
// Only the op's own attributes are read.
LogicalResult idr::FuncOp::verify() {
  CloneAttr clone = getCloneAttr();
  if (!clone)
    return success();
  Attribute key = clone.getKey();
  if (clone.getFunction().getAttr() != getSymNameAttr() ||
      !isa<SpecKeyAttr, KeyApplyAttr, KeyApplyFieldAttr>(key))
    return emitOpError("expects clone to name the function and its key");
  auto spec = dyn_cast<SpecKeyAttr>(key);
  if (!spec)
    return success();
  unsigned parameters = getNumArguments();
  llvm::BitVector seen(parameters);
  std::optional<unsigned> outside;
  for (Attribute pattern : spec.getPatterns())
    pattern.walk([&](KeyHoleAttr hole) {
      if (hole.getIndex() < parameters)
        seen.set(hole.getIndex());
      else
        outside = hole.getIndex();
    });
  if (outside)
    return emitOpError("has a clone key with hole ")
           << *outside << ", but takes " << parameters << " parameters";
  if (!seen.all())
    return emitOpError("has a clone key with no hole ")
           << seen.find_first_unset() << ", but takes " << parameters << " parameters";
  return success();
}

// The interface's own body check has matched the entry block to the type,
// and the ops' verifiers have run: a match's regions and yields are well
// formed. The stage is this function's, by its own grades.
LogicalResult idr::FuncOp::verifyRegions() {
  if (isExternal())
    return success();
  verify::Numbering numbering(*this);
  if (failed(verify::linearity(numbering)))
    return failure();
  if (!numbering.owned())
    return success();
  return verify::owned(*this);
}
