// The closures a value may hold, and what running them may do.

#include "Facts/Facts.h"

#include "mlir/IR/Matchers.h"

using namespace mlir;
using namespace idr;

namespace {

bool holdsClosure(Operation *from, Type type, llvm::SmallDenseSet<Type> &seen) {
  type = unrestricted(type);
  if (isa<FnType>(type))
    return true;
  DataOp data = lookupData(from, type);
  if (data && data.getClosures())
    return true;
  if (!data || !seen.insert(type).second)
    return false;
  return llvm::any_of(data.getCtors(), [&](CtorOp ctor) {
    return llvm::any_of(ctor.getFieldTypes().getAsValueRange<TypeAttr>(),
                        [&](Type field) { return holdsClosure(from, field, seen); });
  });
}

// What a call of the label `name` may do.
facts::Effects label(Operation *from, StringAttr name) {
  return facts::of(SymbolTable::lookupNearestSymbolFrom<func::FuncOp>(from, name));
}

// What the closures in a constant may do, through its captures and fields.
facts::Effects inConstant(Operation *from, Attribute constant) {
  facts::Effects out;
  constant.walk([&](Attribute nested) {
    if (auto closure = dyn_cast<ClosureAttr>(nested))
      out |= label(from, closure.getCallee().getAttr());
    else if (auto con = dyn_cast<ConAttr>(nested))
      if (StringAttr name = facts::closureLabel(from, con.getCtor()))
        out |= label(from, name);
  });
  return out;
}

} // namespace

StringAttr facts::closureLabel(Operation *from, SymbolRefAttr ctor) {
  auto data = SymbolTable::lookupNearestSymbolFrom<DataOp>(
      from, FlatSymbolRefAttr::get(ctor.getRootReference()));
  return data && data.getClosures() ? ctor.getLeafReference() : StringAttr();
}

bool facts::mayHoldClosure(Operation *from, Type type) {
  llvm::SmallDenseSet<Type> seen;
  return holdsClosure(from, type, seen);
}

// A value made here, as a constant, a closure or a constructor, holds the
// closures it is made of, and a value moved into or out of a linear type
// the closures of what it moved; any other value may hold any.
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
    if (auto enter = dyn_cast_or_null<LinEnterOp>(def)) {
      work.push_back(enter.getValue());
      continue;
    }
    if (auto use = dyn_cast_or_null<LinUseOp>(def)) {
      work.push_back(use.getLinear());
      continue;
    }
    if (auto con = dyn_cast_or_null<ConOp>(def)) {
      if (StringAttr name = closureLabel(from, con.getCtor()))
        out |= label(from, name);
      llvm::append_range(work, con.getFields());
      continue;
    }
    return Effects::all();
  }
  return out;
}
