// The closures a value may hold, and what running them may do.

#include "Facts/Facts.h"

#include "mlir/IR/Matchers.h"

using namespace mlir;
using namespace idr;

namespace {

// idr-defunctionalize names each sum it makes of closures `fn$<n>`, with
// one constructor per label, named after the label's function; a value of
// one is a closure.
bool isClosureSum(StringRef name) { return name.starts_with("fn$"); }

bool holdsClosure(Operation *from, Type type, llvm::SmallDenseSet<Type> &seen) {
  if (isa<FnType>(type))
    return true;
  FlatSymbolRefAttr name = getSumName(type);
  if (!name)
    return false;
  if (isClosureSum(name.getValue()))
    return true;
  DataOp data = lookupData(from, type);
  if (!data || !seen.insert(type).second)
    return false;
  return llvm::any_of(data.getCtors(), [&](CtorOp ctor) {
    return llvm::any_of(ctor.getFieldTypes().getAsValueRange<TypeAttr>(),
                        [&](Type field) { return holdsClosure(from, field, seen); });
  });
}

// What a call of the label `name` may do.
facts::Effects label(Operation *from, StringAttr name) {
  auto fn = SymbolTable::lookupNearestSymbolFrom<func::FuncOp>(from, name);
  return fn ? facts::of(fn) : facts::Effects::all();
}

// What the closures in a constant may do, through its captures and fields.
facts::Effects inConstant(Operation *from, Attribute constant) {
  facts::Effects out;
  constant.walk([&](Attribute nested) {
    if (auto closure = dyn_cast<ClosureAttr>(nested))
      out |= label(from, closure.getCallee().getAttr());
    else if (auto con = dyn_cast<ConAttr>(nested))
      if (StringAttr name = facts::closureLabel(con.getCtor()))
        out |= label(from, name);
  });
  return out;
}

} // namespace

StringAttr facts::closureLabel(SymbolRefAttr ctor) {
  return isClosureSum(ctor.getRootReference().getValue()) ? ctor.getLeafReference()
                                                          : StringAttr();
}

bool facts::mayHoldClosure(Operation *from, Type type) {
  llvm::SmallDenseSet<Type> seen;
  return holdsClosure(from, type, seen);
}

// A value made here, as a constant, a closure or a constructor, holds the
// closures it is made of; any other value may hold any.
facts::Effects facts::passed(Operation *from, Value value) {
  Effects out;
  SmallVector<Value> work{value};
  llvm::DenseSet<Value> seen;
  while (!work.empty()) {
    Value next = work.pop_back_val();
    if (!seen.insert(next).second || !mayHoldClosure(from, next.getType()))
      continue;
    Attribute constant;
    if (matchPattern(next, m_Constant(&constant))) {
      out |= inConstant(from, constant);
      continue;
    }
    Operation *def = next.getDefiningOp();
    if (auto closure = dyn_cast_or_null<ClosureOp>(def)) {
      out |= label(from, closure.getCalleeAttr().getAttr());
      llvm::append_range(work, closure.getCaptures());
      continue;
    }
    if (auto con = dyn_cast_or_null<ConOp>(def)) {
      if (StringAttr name = closureLabel(con.getCtor()))
        out |= label(from, name);
      llvm::append_range(work, con.getFields());
      continue;
    }
    return Effects::all();
  }
  return out;
}
