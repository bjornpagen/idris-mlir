// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a function does when it runs: whether it takes a value apart,
// forces a suspension, builds a value or reads a field, whether it can
// return at all, and whom it calls. A test states what canonicalization
// left a function doing, or no longer doing, instead of matching the ops
// that show it; every copy of the function is asked (`named`).

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
bool takesApart(Operation *op) { return isa<MatchOp, MatchLitOp>(op); }
// A force of a suspension.
bool forces(Operation *op) { return isa<ForceOp>(op); }
// A value built at run time: a constructor, in a fresh cell or a reused
// one, a closure, a suspension, an evaluated suspension. A constant is
// static data and is built by no one.
bool builds(Operation *op) { return isa<ConOp, ReuseOp, ClosureOp, SuspendOp, DelayOp>(op); }
// A read of one field of a constructor value.
bool readsField(Operation *op) { return isa<FieldOp>(op); }
// An application of a closure.
bool appliesClosure(Operation *op) { return isa<ApplyOp>(op); }

constexpr Action matching{"takes a value apart", takesApart};
constexpr Action forcing{"forces a suspension", forces};
constexpr Action building{"builds a value", builds};
constexpr Action reading{"reads a field", readsField};
constexpr Action applying{"applies a closure", appliesClosure};

// The functions `function` names do `action` somewhere (`wanted`), or
// nowhere.
LogicalResult performs(ModuleOp module, StringRef function, StringRef property, Action action,
                       bool wanted) {
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true, found = false;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](Operation *op) {
      if (op == fn.getOperation() || !action.performs(op))
        return;
      found = true;
      if (wanted)
        return;
      fail(op->getLoc(), property) << op->getName() << " " << action.doing << " in " << where(op);
      held = false;
    });
  if (wanted && !found) {
    fail(functions.front()->getLoc(), property) << "nothing in " << function << " "
                                                << action.doing;
    held = false;
  }
  return success(held);
}

// `@f:@g`, split; an error of `property` when either is missing.
std::optional<std::pair<StringRef, StringRef>> callerAndCallee(ModuleOp module, StringRef argument,
                                                               StringRef property) {
  auto [caller, callee] = argument.split(':');
  if (caller.ltrim('@').empty() || callee.ltrim('@').empty()) {
    fail(module.getLoc(), property) << "name the caller and the callee, as " << property << "=@f:@g";
    return std::nullopt;
  }
  return std::make_pair(caller, callee.ltrim('@'));
}

// The calls in `fn` of `callee` or of a copy of it: idr.call before
// lowering, a call of the func or LLVM dialect after it, of the program's
// functions or the runtime's.
SmallVector<CallOpInterface> callsOf(SymbolTable &symbols, FunctionOpInterface fn,
                                     StringRef callee) {
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

LogicalResult matches(ModuleOp module, AnalysisManager &, StringRef function) {
  return performs(module, function, "matches", matching, true);
}
LogicalResult matchesNothing(ModuleOp module, AnalysisManager &, StringRef function) {
  return performs(module, function, "matches-nothing", matching, false);
}
LogicalResult forcesSome(ModuleOp module, AnalysisManager &, StringRef function) {
  return performs(module, function, "forces", forcing, true);
}
LogicalResult forcesNothing(ModuleOp module, AnalysisManager &, StringRef function) {
  return performs(module, function, "forces-nothing", forcing, false);
}
LogicalResult buildsSome(ModuleOp module, AnalysisManager &, StringRef function) {
  return performs(module, function, "builds", building, true);
}
LogicalResult buildsNothing(ModuleOp module, AnalysisManager &, StringRef function) {
  return performs(module, function, "builds-nothing", building, false);
}
LogicalResult readsFields(ModuleOp module, AnalysisManager &, StringRef function) {
  return performs(module, function, "reads-fields", reading, true);
}
LogicalResult readsNoFields(ModuleOp module, AnalysisManager &, StringRef function) {
  return performs(module, function, "reads-no-fields", reading, false);
}

LogicalResult applies(ModuleOp module, AnalysisManager &, StringRef function) {
  return performs(module, function, "applies", applying, true);
}

// No block of the body ends in a return: every path crashes or never ends.
LogicalResult neverReturns(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "never-returns";
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface fn : functions)
    for (Block &block : fn.getFunctionBody())
      if (!block.empty() && block.back().hasTrait<OpTrait::ReturnLike>()) {
        fail(block.back().getLoc(), property) << where(fn) << " returns";
        held = false;
      }
  return success(held);
}

LogicalResult calls(ModuleOp module, AnalysisManager &analyses, StringRef argument) {
  constexpr StringRef property = "calls";
  auto pair = callerAndCallee(module, argument, property);
  if (!pair)
    return failure();
  SmallVector<FunctionOpInterface> functions = named(module, pair->first, property);
  if (functions.empty())
    return failure();
  SymbolTable &symbols = symbolsOf(module, analyses);
  for (FunctionOpInterface fn : functions)
    if (!callsOf(symbols, fn, pair->second).empty())
      return success();
  return fail(functions.front()->getLoc(), property) << pair->first << " calls no @" << pair->second;
}

LogicalResult neverCalls(ModuleOp module, AnalysisManager &analyses, StringRef argument) {
  constexpr StringRef property = "never-calls";
  auto pair = callerAndCallee(module, argument, property);
  if (!pair)
    return failure();
  SmallVector<FunctionOpInterface> functions = named(module, pair->first, property);
  if (functions.empty())
    return failure();
  SymbolTable &symbols = symbolsOf(module, analyses);
  bool held = true;
  for (FunctionOpInterface fn : functions)
    for (CallOpInterface call : callsOf(symbols, fn, pair->second)) {
      fail(call->getLoc(), property) << where(call) << " still calls @" << pair->second << ", as @"
                                     << calleeName(call);
      held = false;
    }
  return success(held);
}

// Every call is closed: compile-time evaluation has all it needs.
LogicalResult callsClosed(ModuleOp module, AnalysisManager &analyses, StringRef argument) {
  constexpr StringRef property = "calls-closed";
  auto pair = callerAndCallee(module, argument, property);
  if (!pair)
    return failure();
  SmallVector<FunctionOpInterface> functions = named(module, pair->first, property);
  if (functions.empty())
    return failure();
  SymbolTable &symbols = symbolsOf(module, analyses);
  bool held = true, called = false;
  for (FunctionOpInterface fn : functions)
    for (CallOpInterface call : callsOf(symbols, fn, pair->second)) {
      called = true;
      for (Value operand : call.getArgOperands())
        if (!matchPattern(operand, m_Constant())) {
          fail(call->getLoc(), property) << "a call of @" << pair->second << " in " << where(call)
                                        << " takes an argument that is not a constant";
          held = false;
          break;
        }
    }
  if (!called) {
    fail(functions.front()->getLoc(), property) << pair->first << " calls no @" << pair->second;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
