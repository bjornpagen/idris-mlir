// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// call-order, calls-only and direct-calls: what a function asks of the
// functions it calls, the program's and the runtime's, stated as the calls
// it makes and not as the ops around them. After lowering, a runtime
// function is a declaration of the module named by the runtime's own
// symbol, so a test that names one names the runtime's interface, which
// the runtime documents; before it, every callee is the program's.

#include "idr/Transforms/Expect.h"

#include "mlir/Interfaces/CallInterfaces.h"

using namespace mlir;

namespace idr::expect {

namespace {

// The calls of `fn`, in the order the walk meets them.
SmallVector<CallOpInterface> callsOf(FunctionOpInterface fn) {
  SmallVector<CallOpInterface> out;
  fn->walk([&](CallOpInterface call) { out.push_back(call); });
  return out;
}

// The name a call calls, for an error.
std::string calleeOf(CallOpInterface call) {
  if (auto callee = dyn_cast<SymbolRefAttr>(call.getCallableForCallee()))
    return ("@" + callee.getRootReference().getValue()).str();
  return "a value";
}

} // namespace

// Every copy of @f calls each function the list names, in the list's
// order: a call of the second comes after a call of the first, in the
// order the body is written. Repeating a name asks for that many calls.
LogicalResult callOrder(ModuleOp module, AnalysisManager &analyses, StringRef argument) {
  constexpr StringRef property = "call-order";
  auto [function, list] = splitAt(module, argument, property);
  if (function.empty())
    return failure();
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  SmallVector<StringRef> wanted = symbolList(list);
  SymbolTable &symbols = symbolsOf(module, analyses);
  bool held = true;
  for (FunctionOpInterface fn : functions) {
    size_t next = 0;
    for (CallOpInterface call : callsOf(fn))
      if (next < wanted.size() && callsNamed(call, wanted[next], symbols))
        ++next;
    if (next == wanted.size())
      continue;
    InFlightDiagnostic error = fail(fn->getLoc(), property) << where(fn) << " makes no call of @"
                                                            << wanted[next];
    if (next > 0)
      error << " after its call of @" << wanted[next - 1];
    held = false;
  }
  return success(held);
}

// Every call of every copy of @f is of a function the list names: so `[]`
// says @f calls nothing.
LogicalResult callsOnly(ModuleOp module, AnalysisManager &analyses, StringRef argument) {
  constexpr StringRef property = "calls-only";
  auto [function, list] = splitAt(module, argument, property);
  if (function.empty())
    return failure();
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  SmallVector<StringRef> allowed = symbolList(list);
  SymbolTable &symbols = symbolsOf(module, analyses);
  bool held = true;
  for (FunctionOpInterface fn : functions)
    for (CallOpInterface call : callsOf(fn)) {
      if (llvm::any_of(allowed, [&](StringRef g) { return callsNamed(call, g, symbols); }))
        continue;
      fail(call->getLoc(), property) << where(fn) << " calls " << calleeOf(call)
                                     << ", which the list does not name";
      held = false;
    }
  return success(held);
}

// Every call, anywhere or in @f, names its callee: no call goes through a
// value, so no cell holds code.
LogicalResult directCalls(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "direct-calls";
  SmallVector<Operation *> roots = rootsOf(module, function, property);
  if (roots.empty())
    return failure();
  bool held = true;
  for (Operation *root : roots)
    root->walk([&](CallOpInterface call) {
      if (isa<SymbolRefAttr>(call.getCallableForCallee()))
        return;
      fail(call->getLoc(), property) << call->getName() << " in " << where(call)
                                     << " calls through a value";
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
