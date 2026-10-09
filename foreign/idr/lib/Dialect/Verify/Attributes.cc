// The dialect's attributes on other ops, and on the arguments of functions:
// where each may sit and what its value may be.

#include "idr/Idr.h"

import idr.ownership;
import idr.verify;

using namespace mlir;
using namespace idr;

namespace {

// A rule for one of the dialect's discardable attributes: where it may sit
// and what its value may be.
struct KnownAttr {
  llvm::StringLiteral name;
  LogicalResult (*verify)(Operation *op, NamedAttribute attr);
};

LogicalResult unitOfFunction(Operation *op, NamedAttribute attr) {
  if (!isa<func::FuncOp>(op) || !isa<UnitAttr>(attr.getValue()))
    return op->emitOpError("expects ")
           << attr.getName().getValue() << " as a unit attribute of a function";
  return success();
}

// Where each of the dialect's discardable attributes may sit, and what its
// value may be, by the names its declaration gives them. The verifier asks
// the dialect about every attribute named `idr.*`, so a name missing here is
// rejected, not ignored.
constexpr KnownAttr kKnownAttrs[] = {
    // A whole program: its own rules, and once idr-rc has made every
    // reference explicit, the owned stage's, which its grades say it is in
    // (lib/Ownership).
    {IdrDialect::ProgramAttrHelper::getNameStr(),
     [](Operation *op, NamedAttribute attr) -> LogicalResult {
       if (!isa<ModuleOp>(op) || !isa<UnitAttr>(attr.getValue()))
         return op->emitOpError("expects idr.program as a unit attribute of the module");
       auto module = cast<ModuleOp>(op);
       if (failed(idr::verify::program(module)))
         return failure();
       return ownership::verifyOwned(module);
     }},
    // The facts of a function (lib/Facts): what Idris proves, whether a
    // cycle breaks at it last, and what idr-effects finds.
    {IdrDialect::TotalAttrHelper::getNameStr(), unitOfFunction},
    {IdrDialect::BreakLastAttrHelper::getNameStr(), unitOfFunction},
    {IdrDialect::EffectsAttrHelper::getNameStr(),
     [](Operation *op, NamedAttribute attr) -> LogicalResult {
       if (!isa<func::FuncOp>(op) || !isa<EffectAttr>(attr.getValue()))
         return op->emitOpError("expects idr.effects = #idr.effects<...> on a function");
       return success();
     }},
    // idr-stack's mark of a box whose cell never leaves its frame
    // (lib/Stack/Pass.cc).
    {IdrDialect::StackAttrHelper::getNameStr(),
     [](Operation *op, NamedAttribute attr) -> LogicalResult {
       auto con = dyn_cast<ConOp>(op);
       if (!con || !isa<BoxType>(unrestricted(con.getType())) || !isa<UnitAttr>(attr.getValue()))
         return op->emitOpError("expects idr.stack as a unit attribute of an idr.con of a box");
       return success();
     }},
    // What idr-specialize keeps on a clone between its runs
    // (lib/Specialize): its key, which also says what it was cloned from.
    {IdrDialect::CloneAttrHelper::getNameStr(),
     [](Operation *op, NamedAttribute attr) -> LogicalResult {
       auto fn = dyn_cast<func::FuncOp>(op);
       auto clone = dyn_cast<CloneAttr>(attr.getValue());
       if (!fn || !clone || clone.getFunction().getAttr() != fn.getSymNameAttr() ||
           !isa<SpecKeyAttr, KeyApplyAttr, KeyApplyFieldAttr>(clone.getKey()))
         return op->emitOpError("expects idr.clone to name the function and its key");
       return success();
     }},
};

} // namespace

LogicalResult IdrDialect::verifyOperationAttribute(Operation *op, NamedAttribute attr) {
  for (const KnownAttr &known : kKnownAttrs)
    if (attr.getName().getValue() == known.name)
      return known.verify(op, attr);
  return op->emitOpError("has an unknown idr attribute ") << attr.getName();
}

// A parameter's quantity is its type; the argument attributes are the
// passes' own marks.
LogicalResult IdrDialect::verifyRegionArgAttribute(Operation *op, unsigned, unsigned,
                                                   NamedAttribute attr) {
  auto fn = dyn_cast<FunctionOpInterface>(op);
  // idr-specialize numbers a clone's parameters by the holes of its key.
  if (attr.getName().getValue() == HoleAttrHelper::getNameStr() && fn &&
      isa<IntegerAttr>(attr.getValue()))
    return success();
  return op->emitOpError("has an unknown idr argument attribute ") << attr.getName();
}
