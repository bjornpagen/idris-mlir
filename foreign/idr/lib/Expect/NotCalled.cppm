// not-called: no call of a function, or of a clone of it, is left: each
// became what it computes, as a call of a function that gives back its
// argument becomes the argument. Which pass did it, and whether the
// function is still in the module for something else that names it, are
// the passes' business; that no call is left is the property.
export module idr.expect:notCalled;

import idr.mlir;

import :named;
import :report;

using namespace mlir;

namespace idr::expect {

// No call reaches the function the argument names, or a clone of it: a
// function whose location names the definition it was copied from. A
// function the module never had is not called either, so a test states
// the property of a function its emitted module calls.
export LogicalResult notCalled(ModuleOp module, StringRef function) {
  constexpr StringRef property = "not-called";
  StringRef name = function.ltrim('@');
  if (name.empty())
    return fail(module.getLoc(), property) << "name the function, as not-called=@f";
  SymbolTable symbols(module);
  bool held = true;
  module.walk([&](func::CallOp call) {
    auto callee = symbols.lookup<func::FuncOp>(call.getCallee());
    if (call.getCallee() != name && !(callee && locationNames(callee.getLoc(), name)))
      return;
    fail(call.getLoc(), property) << function << " is still called, as @" << call.getCallee()
                                  << ", in " << where(call);
    held = false;
  });
  return success(held);
}

} // namespace idr::expect
