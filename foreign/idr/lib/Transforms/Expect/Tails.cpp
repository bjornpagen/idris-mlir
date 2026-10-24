// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// tail-calls and results-as-given: what follows a call of one function in
// another. A tail call whose result layout differs from its caller's is
// made a tail by a copy of its callee that returns the caller's layout,
// and every other call keeps its callee's result as the callee lays it
// out: the first property states the tail such a copy makes, the second
// that a call pays no re-pack for its result. Both read the calls by
// upstream's call interface, and the tail fact through Tail.h's one
// reading of it, never the attribute; a result's two types are compared
// as the layouts compare them, the comparison by which a reindex between
// them is free or re-packs.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Families/Families.h"
#include "idr/IR/Tail.h"

#include "mlir/Interfaces/CallInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

using namespace mlir;

namespace idr::expect {

namespace {

// The calls in the functions @f names of @g or a copy of it, in the
// functions' order and each one's walk.
SmallVector<CallOpInterface> callsOf(const Pair &pair, SymbolTable &symbols) {
  SmallVector<CallOpInterface> found;
  for (FunctionOpInterface fn : pair.caller.functions)
    fn->walk([&](CallOpInterface call) {
      if (callsNamed(call, pair.callee, symbols))
        found.push_back(call);
    });
  return found;
}

// The first op that re-packs a value `call` gives where its function takes
// it: one that takes the value as the one it gives on and works to do so,
// converting it between two layouts, as it answers through the carrying
// interface. What the call gives is each of its results, and what an op
// that gives one on freely makes of it; such an op gives on only its first
// operand, so each value is met once. Null where no op does. What a
// region's end gives its op is the way to the return, where a re-pack is a
// tail lost to a layout, which the tail verifier refuses once tail calls'
// layouts agree with their callers', before any property reads the module.
Operation *repackOfUse(CallOpInterface call) {
  SmallVector<Value, 4> given(call->result_begin(), call->result_end());
  while (!given.empty()) {
    Value value = given.pop_back_val();
    for (OpOperand &use : value.getUses()) {
      auto carry = dyn_cast<CarriesOnOpInterface>(use.getOwner());
      if (!carry || use.getOperandNumber() != 0)
        continue;
      if (carry.getCarry() == Carry::Works)
        return use.getOwner();
      given.push_back(use.getOwner()->getResult(0));
    }
  }
  return nullptr;
}

} // namespace

// Some call in a function of @f of @g or a copy of it is a tail call, as
// Tail.h reads one. A tail call is a fact of the program's calls, so after
// lowering, where none is left, the property fails. Where it fails, each
// call of @g there is reported, or @f where it calls no @g.
LogicalResult tailCalls(const Request<Pair> &request) {
  const Pair &pair = request.argument;
  SymbolTable &symbols = symbolsOf(request.module, request.analyses);
  SmallVector<CallOpInterface> found = callsOf(pair, symbols);
  if (llvm::any_of(found, [](CallOpInterface call) {
        return static_cast<bool>(tailCallOf(call.getOperation()));
      }))
    return success();
  if (found.empty())
    return fail(pair.caller.functions.front()->getLoc(), request.property)
           << "@" << pair.caller.name << " calls no @" << pair.callee.name;
  for (CallOpInterface call : found)
    fail(call.getLoc(), request.property)
        << "@" << pair.callee.name << " is called, as " << calleeOf(call) << ", in "
        << where(call) << " by no tail call";
  return failure();
}

// Every call in a function of @f of @g or a copy of it gives each result
// laid out as its callee returns it, and no op after it re-packs one where
// its function takes it. Each result laid out otherwise is reported at its
// call, and a call with a re-pack after it once, a re-pack on the way out
// in the call's own block being one its function takes as well.
LogicalResult resultsAsGiven(const Request<Pair> &request) {
  const Pair &pair = request.argument;
  SymbolTable &symbols = symbolsOf(request.module, request.analyses);
  LogicalResult held = success();
  for (CallOpInterface call : callsOf(pair, symbols)) {
    // A callee the module holds as no function (an alias or an ifunc of
    // LLVM's, which llvm.call may name) declares no results of its own: the
    // call's are all there is.
    if (auto callee = symbols.lookup<FunctionOpInterface>(calleeOf(call).getRootReference())) {
      for (auto [index, types] :
           llvm::enumerate(llvm::zip_equal(call->getResultTypes(), callee.getResultTypes()))) {
        auto [given, returned] = types;
        if (families::layoutMatch(given, returned) == LayoutMatch::SameLayout)
          continue;
        fail(call.getLoc(), request.property)
            << "@" << pair.callee.name << ", as " << calleeOf(call) << ", returns " << returned
            << " as result " << index << ", which its call in " << where(call) << " gives as "
            << given << ", laid out otherwise";
        held = failure();
      }
    }
    if (Operation *repack = repackOfUse(call)) {
      fail(call.getLoc(), request.property)
          << "the call of @" << pair.callee.name << ", as " << calleeOf(call) << ", in "
          << where(call) << " gives a result that a re-pack after it converts from "
          << repack->getOperand(0).getType() << " to " << repack->getResult(0).getType();
      held = failure();
    }
  }
  return held;
}

} // namespace idr::expect
