// The roots a property of loops is checked under.
export module idr.expect:roots;

import idr.mlir;

import :named;

using namespace mlir;

namespace idr::expect {

// The roots a property of loops is checked under: the module, or the
// functions named.
SmallVector<Operation *> rootsOf(ModuleOp module, StringRef function, StringRef property) {
  SmallVector<Operation *> roots;
  if (function.empty()) {
    roots.push_back(module);
    return roots;
  }
  for (func::FuncOp fn : named(module, function, property))
    roots.push_back(fn);
  return roots;
}

} // namespace idr::expect
