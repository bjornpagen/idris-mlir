// The dialect's attributes on other ops and on the arguments of functions.
// What a function is known to be is idr.func's own, inherent and verified
// with it; what is left are the module's mark of a whole program and
// idr-stack's mark of a box whose cell never leaves its frame. MLIR asks
// the dialect about every attribute named `idr.*`, so any other such name
// is refused, not ignored; a name of no dialect is no business of ours.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Verify.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"

using namespace mlir;
using namespace idr;

LogicalResult idr::IdrDialect::verifyOperationAttribute(Operation *op, NamedAttribute attr) {
  StringRef name = attr.getName().getValue();
  // A whole program: its own rules, which run before the ops inside are
  // verified.
  if (name == ProgramAttrHelper::getNameStr()) {
    auto module = dyn_cast<ModuleOp>(op);
    if (!module || !isa<UnitAttr>(attr.getValue()))
      return op->emitOpError("expects idr.program as a unit attribute of the module");
    return verify::program(module);
  }
  if (name == StackAttrHelper::getNameStr()) {
    auto con = dyn_cast<ConOp>(op);
    if (!con || !isa<BoxType>(unrestricted(con.getType())) || !isa<UnitAttr>(attr.getValue()))
      return op->emitOpError("expects idr.stack as a unit attribute of an idr.con of a box");
    return success();
  }
  return op->emitOpError("has an unknown idr attribute ") << attr.getName();
}

// A parameter's quantity and ownership are its type, and a clone's hole is
// its parameter's position: the dialect marks no argument.
LogicalResult idr::IdrDialect::verifyRegionArgAttribute(Operation *op, unsigned, unsigned,
                                                        NamedAttribute attr) {
  return op->emitOpError("has an unknown idr argument attribute ") << attr.getName();
}
