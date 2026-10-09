// idr.facts:passed: what the closures a value holds may do when code given
// it applies them.
export module idr.facts:passed;

import idr.mlir;
import idr.dialect;

import :closurelabel;
import :effects;
import :mayholdclosure;
import :of;

using namespace mlir;
using namespace idr;

namespace {

// What a call of the label `name` may do.
facts::Effects label(Operation *from, StringAttr name) {
  return facts::of(lookupSymbol<func::FuncOp>(from, name));
}

// What the closures in a constant may do, through its captures and fields.
// MLIR's walk reads each sub-attribute once, and a run's cells and its
// tail as its own, one level deep: never its fields along the spine, which
// would rebuild the rest of the run at every step. Every cell of a run is
// its constructor's, so the run's is the one to ask about.
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

export namespace idr::facts {

// What code given `value` may do by applying the closures it holds: what
// their labels do, through captures and fields. A closure whose label is
// not known where `value` is made may do anything.
//
// A value made here, as a constant, a closure or a constructor, holds the
// closures it is made of, and a value moved into or out of a linear type
// the closures of what it moved; any other value may hold any.
Effects passed(Operation *from, Value value) {
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

} // namespace idr::facts
