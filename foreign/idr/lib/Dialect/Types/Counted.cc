// Whether a value of a type holds a reference a count accounts for.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

namespace {

// `visited`: the unboxed sums already asked about. Containment through
// them is acyclic, so one met again is one the verifier has yet to reject,
// or one whose answer is no (a yes ends the walk).
bool holds(Type type, SymbolTableCollection &symbols, Operation *scope,
           llvm::SmallPtrSetImpl<Operation *> &visited) {
  // A linear value holds what the value it is holds: its quantity decides
  // only how it is used.
  type = unrestricted(type);
  if (isa<StrType, BigType, NatType, BoxType, FnType, LazyType, idr::TokenType>(type) ||
      isArray(type))
    return true;
  // An unboxed sum has no cell: it holds what its slots hold, which only
  // its declaration says, since the type is a name.
  auto data = dyn_cast<DataType>(type);
  if (!data)
    return false;
  auto decl = symbols.lookupNearestSymbolFrom<DataOp>(scope, data.getName());
  if (!decl || !visited.insert(decl).second)
    return false;
  for (CtorOp ctor : decl.getCtors())
    for (Type field : ctor.getFieldTypes().getAsValueRange<TypeAttr>())
      if (holds(field, symbols, scope, visited))
        return true;
  return false;
}

} // namespace

bool idr::holdsReferences(Type type, SymbolTableCollection &symbols, Operation *scope) {
  llvm::SmallPtrSet<Operation *, 4> visited;
  return holds(type, symbols, scope, visited);
}
