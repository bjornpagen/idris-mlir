// pure-array-loops: the bodies of the loops over arrays only compute.
export module idr.expect:pureArrayLoops;

import idr.mlir;
import idr.dialect;

import :named;
import :report;

using namespace mlir;

namespace idr::expect {

// Every loop over an array (idr.array.generate, idr.array.fold), in the
// function the argument names or anywhere, has a body that only computes:
// no count changes, nothing is allocated, nothing is called; and there is
// at least one.
//
// The body of a loop over an array runs once per element as one linalg
// operation after lowering, which the vectorizer can give lanes only when
// it holds words alone: a dup or a drop, an allocation or a call in it is
// a count, a cell or a function per element.
export LogicalResult pureArrayLoops(ModuleOp module, StringRef function) {
  constexpr StringRef property = "pure-array-loops";
  SmallVector<Operation *> roots;
  if (function.empty()) {
    roots.push_back(module);
  } else {
    for (func::FuncOp fn : named(module, function, property))
      roots.push_back(fn);
    if (roots.empty())
      return failure();
  }
  bool held = true, found = false;
  auto impure = [](Operation *op) -> std::optional<StringRef> {
    if (isa<DupOp, DropOp>(op))
      return "changes a count";
    if (isa<CallOpInterface>(op))
      return "calls";
    auto effects = dyn_cast<MemoryEffectOpInterface>(op);
    if (!effects)
      return std::nullopt;
    SmallVector<MemoryEffects::EffectInstance> instances;
    effects.getEffects(instances);
    for (const MemoryEffects::EffectInstance &effect : instances)
      if (isa<MemoryEffects::Allocate>(effect.getEffect()) &&
          effect.getResource()->getResourceID() != LinResource::getResourceID())
        return "allocates";
    return std::nullopt;
  };
  for (Operation *root : roots)
    root->walk([&](Operation *loop) {
      if (!isa<ArrayGenerateOp, ArrayFoldOp>(loop))
        return;
      found = true;
      loop->getRegion(0).walk([&](Operation *op) {
        if (std::optional<StringRef> why = impure(op)) {
          fail(op->getLoc(), property) << op->getName() << " " << *why << " in the body of a "
                                       << loop->getName() << " in " << where(op);
          held = false;
        }
      });
    });
  if (!found) {
    fail(roots.front()->getLoc(), property) << "no loop over an array"
                                            << (function.empty() ? "" : " in ") << function;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
