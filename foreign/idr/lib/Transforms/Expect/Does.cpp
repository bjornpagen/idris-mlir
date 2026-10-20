// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a function does when it runs: whether it takes a value apart,
// forces a suspension, builds a value or reads a field, whether it can
// return at all, and whom it calls. A test states what canonicalization
// left a function doing, or no longer doing, instead of matching the ops
// that show it; every copy of the function is asked (`names`).

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"

using namespace mlir;

namespace idr::expect {

namespace {

// One kind of action, and the ops that perform it.
struct Action {
  StringRef doing;
  bool (*performs)(Operation *);
};

// A match on a constructor or on a literal.
bool takesApart(Operation *op) { return isa<MatchOpInterface>(op); }
// A force of a suspension.
bool forces(Operation *op) { return isa<ForceOp>(op); }
// A value built at run time, which its op declares (Idr_BuildsValue).
bool builds(Operation *op) { return op->hasTrait<BuildsValue>(); }
// A read of one field of a constructor value.
bool readsField(Operation *op) { return isa<FieldOp>(op); }
// An application of a closure.
bool appliesClosure(Operation *op) { return isa<ApplyOp>(op); }

constexpr Action matching{"takes a value apart", takesApart};
constexpr Action forcing{"forces a suspension", forces};
constexpr Action building{"builds a value", builds};
constexpr Action reading{"reads a field", readsField};
constexpr Action applying{"applies a closure", appliesClosure};

// The functions the request names do `action` somewhere (`wanted`), or
// nowhere.
LogicalResult performs(const Request<Functions> &request, Action action, bool wanted) {
  ArrayRef<FunctionOpInterface> functions = request.argument.functions;
  bool held = true, found = false;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](Operation *op) {
      if (op == fn.getOperation() || !action.performs(op))
        return;
      found = true;
      if (wanted)
        return;
      fail(op->getLoc(), request.property) << op->getName() << " " << action.doing << " in "
                                           << where(op);
      held = false;
    });
  if (wanted && !found) {
    fail(functions.front()->getLoc(), request.property)
        << "nothing in @" << request.argument.name << " " << action.doing;
    held = false;
  }
  return success(held);
}

// The calls in `fn` of `callee` or of a copy of it: idr.call before
// lowering, a call of the func or LLVM dialect after it, of the program's
// functions or the runtime's.
SmallVector<CallOpInterface> callsOf(SymbolTable &symbols, FunctionOpInterface fn,
                                     const Symbol &callee) {
  SmallVector<CallOpInterface> out;
  fn->walk([&](CallOpInterface call) {
    if (callsNamed(call, callee, symbols))
      out.push_back(call);
  });
  return out;
}

// The symbol a call names, for an error.
StringRef calleeName(CallOpInterface call) {
  auto callee = dyn_cast<SymbolRefAttr>(call.getCallableForCallee());
  return callee ? callee.getRootReference().getValue() : StringRef();
}

} // namespace

LogicalResult matches(const Request<Functions> &request) {
  return performs(request, matching, true);
}
LogicalResult matchesNothing(const Request<Functions> &request) {
  return performs(request, matching, false);
}
LogicalResult forcesSome(const Request<Functions> &request) {
  return performs(request, forcing, true);
}
LogicalResult forcesNothing(const Request<Functions> &request) {
  return performs(request, forcing, false);
}
LogicalResult buildsSome(const Request<Functions> &request) {
  return performs(request, building, true);
}
LogicalResult buildsNothing(const Request<Functions> &request) {
  return performs(request, building, false);
}
LogicalResult readsFields(const Request<Functions> &request) {
  return performs(request, reading, true);
}
LogicalResult readsNoFields(const Request<Functions> &request) {
  return performs(request, reading, false);
}

LogicalResult applies(const Request<Functions> &request) {
  return performs(request, applying, true);
}

// No block of the body ends in a return: every path crashes or never ends.
LogicalResult neverReturns(const Request<Functions> &request) {
  bool held = true;
  for (FunctionOpInterface fn : request.argument.functions)
    for (Block &block : fn.getFunctionBody())
      if (!block.empty() && block.back().hasTrait<OpTrait::ReturnLike>()) {
        fail(block.back().getLoc(), request.property) << where(fn) << " returns";
        held = false;
      }
  return success(held);
}

LogicalResult calls(const Request<Pair> &request) {
  const Pair &pair = request.argument;
  SymbolTable &symbols = symbolsOf(request.module, request.analyses);
  for (FunctionOpInterface fn : pair.caller.functions)
    if (!callsOf(symbols, fn, pair.callee).empty())
      return success();
  return fail(pair.caller.functions.front()->getLoc(), request.property)
         << "@" << pair.caller.name << " calls no @" << pair.callee.name;
}

LogicalResult neverCalls(const Request<Pair> &request) {
  const Pair &pair = request.argument;
  SymbolTable &symbols = symbolsOf(request.module, request.analyses);
  bool held = true;
  for (FunctionOpInterface fn : pair.caller.functions)
    for (CallOpInterface call : callsOf(symbols, fn, pair.callee)) {
      fail(call->getLoc(), request.property) << where(call) << " still calls @"
                                             << pair.callee.name << ", as @" << calleeName(call);
      held = false;
    }
  return success(held);
}

// Every call is closed: compile-time evaluation has all it needs.
LogicalResult callsClosed(const Request<Pair> &request) {
  const Pair &pair = request.argument;
  SymbolTable &symbols = symbolsOf(request.module, request.analyses);
  bool held = true, called = false;
  for (FunctionOpInterface fn : pair.caller.functions)
    for (CallOpInterface call : callsOf(symbols, fn, pair.callee)) {
      called = true;
      for (Value operand : call.getArgOperands())
        if (!matchPattern(operand, m_Constant())) {
          fail(call->getLoc(), request.property) << "a call of @" << pair.callee.name << " in "
                                                 << where(call)
                                                 << " takes an argument that is not a constant";
          held = false;
          break;
        }
    }
  if (!called) {
    fail(pair.caller.functions.front()->getLoc(), request.property)
        << "@" << pair.caller.name << " calls no @" << pair.callee.name;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
