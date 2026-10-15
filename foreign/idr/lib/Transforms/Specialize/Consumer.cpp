// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// When a call may be raised, the consumer a raise node takes in as code,
// and the one decision on a call that requests and idr-redirect share.
//
// Raising moves the consumer of a call's result into the callee's tails:
// the dispatch that is all its one use does with it, the match an apply
// became. Nothing may run between the call and the dispatch that could
// tell: the dispatch and its steps are in the call's block, and either the
// call only computes (its callee performs no IO, cannot crash and returns;
// building actions is no IO), or every op between it and the dispatch only
// computes. A call that passes a world is never raised: the callee's body
// would take part in the world chain.
//
// A raise node is keyed by its callee and its consumer's form: the consumer
// written as a function of the call's result and the values it reads from
// outside, in canonical text. The node is built from that text, so it is a
// function of its key, whichever call asked for it.
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Grades.h"
#include "idr/Transforms/Deduplicate.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/IRMapping.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallPtrSet.h"

using namespace mlir;

namespace idr::specialize::detail {

std::optional<Consumer> consumerOf(idr::CallOp call, idr::FuncOp callee,
                                   const CalleeEffects &effects) {
  if (call->getNumResults() != 1 || !call->getResult(0).hasOneUse())
    return std::nullopt;
  // The operands have the callee's parameter types, so a world one of them
  // may hold is one the callee takes.
  if (llvm::any_of(call.getArgs().getTypes(), [](Type type) { return idr::holdsWorld(type); }))
    return std::nullopt;
  std::optional<Elimination> e = eliminationAt(*call->getResult(0).getUses().begin());
  if (!e || e->dispatch->getBlock() != call->getBlock())
    return std::nullopt;
  // A call that only computes may run later, after anything between it and
  // its consumer; any other only after ops that only compute. What a call
  // does is its callee's entry, final here; what one between does is its
  // own callee's.
  if (callee.getEffects() != idr::Effect::none)
    for (Operation *op = call->getNextNode(); op != e->dispatch.getOperation();
         op = op->getNextNode())
      if (!idr::onlyAllocates(op, &effects))
        return std::nullopt;
  return e;
}

OwningOpRef<idr::FuncOp> consumerFunction(idr::CallOp call, const Consumer &consumer,
                                          SmallVectorImpl<Value> &free) {
  MLIRContext *ctx = call.getContext();
  // The steps from the call's result to the dispatch, each the one use of
  // the one before, in the order they run.
  SmallVector<Operation *> steps = consumer.steps();
  MatchOp dispatch = consumer.dispatch;

  // The values the dispatch's regions read from outside it, in the order a
  // pre-order walk first reads them, but the call's result and what the
  // steps make, which the copy makes itself. The steps read only the step
  // before.
  llvm::SmallPtrSet<Operation *, 4> made(steps.begin(), steps.end());
  made.insert(call);
  llvm::SetVector<Value> outside;
  dispatch->walk<WalkOrder::PreOrder>([&](Operation *op) {
    if (op == dispatch.getOperation())
      return;
    for (Value operand : op->getOperands()) {
      if (Operation *def = operand.getDefiningOp(); def && made.contains(def))
        continue;
      Region *region = operand.getParentRegion();
      if (!region || !dispatch->isAncestor(region->getParentOp()))
        outside.insert(operand);
    }
  });
  llvm::append_range(free, outside);

  SmallVector<Type> inputs{call.getResult(0).getType()};
  llvm::append_range(inputs, ValueRange(outside.getArrayRef()).getTypes());
  Location loc = UnknownLoc::get(ctx);
  OpBuilder b(ctx);
  idr::FuncOp::Properties properties;
  properties.setSymName(b.getStringAttr("consumer"));
  properties.setFunctionType(
      TypeAttr::get(FunctionType::get(ctx, inputs, dispatch.getResultTypes())));
  auto fn = idr::FuncOp::create(b, loc, TypeRange(), ValueRange(), properties);
  Block *entry =
      b.createBlock(&fn.getBody(), {}, inputs, SmallVector<Location>(inputs.size(), loc));
  IRMapping map;
  map.map(call.getResult(0), entry->getArgument(0));
  for (auto [value, arg] : llvm::zip_equal(outside, entry->getArguments().drop_front()))
    map.map(value, arg);
  for (Operation *step : steps)
    b.clone(*step, map);
  Operation *copy = b.clone(*dispatch, map);
  idr::ReturnOp::create(b, loc, copy->getResults());
  return fn;
}

// Two consumers have one form exactly when they are one function: equal
// code on equal values, which is what idr-deduplicate compares. So a
// consumer is printed only when no consumer met before is it.
StringAttr Forms::formOf(OwningOpRef<idr::FuncOp> consumer) {
  unsigned hash = static_cast<unsigned>(
      static_cast<size_t>(idr::deduplicate::hashFunction(*consumer)));
  auto known = [&]() -> StringAttr {
    auto bucket = byHash.find(hash);
    if (bucket == byHash.end())
      return {};
    for (auto &[met, form] : bucket->second)
      if (idr::deduplicate::sameFunction(*met, *consumer))
        return form;
    return {};
  };
  {
    std::lock_guard lock(mutex);
    if (StringAttr form = known())
      return form;
  }
  StringAttr form = StringAttr::get(consumer->getContext(), canonicalText(consumer->getOperation()));
  std::lock_guard lock(mutex);
  if (StringAttr met = known())
    return met;
  byHash[hash].emplace_back(std::move(consumer), form);
  return form;
}

std::optional<Want> decide(idr::CallOp call, const Node *requester, idr::FuncOp callee,
                           const Node *calleeNode, ArrayRef<BindingTime> seen,
                           const CalleeEffects &effects, Forms &forms) {
  MLIRContext *ctx = call.getContext();
  StringAttr name = call.getCalleeAttr().getAttr();

  // A spec node raises nothing; a raise node only with its own consumer,
  // where its callee's tails meet it again; any other function freely. The
  // callee returns from its one block, where the consumer is pushed.
  const Key *own = requester ? &requester->key : nullptr;
  Region &body = callee.getBody();
  if (!(own && std::holds_alternative<SpecKeyAttr>(*own)) && body.hasOneBlock() &&
      isa<idr::ReturnOp>(body.front().getTerminator()))
    if (std::optional<Consumer> consumer = consumerOf(call, callee, effects)) {
      SmallVector<Value> free;
      StringAttr form = forms.formOf(consumerFunction(call, *consumer, free));
      const auto *ownRaise = own ? std::get_if<KeyRaiseAttr>(own) : nullptr;
      if (!ownRaise || ownRaise->getConsumer() == form) {
        Want want;
        want.key = KeyRaiseAttr::get(ctx, name, form);
        want.owner = name;
        llvm::append_range(want.operands, call.getArgs());
        llvm::append_range(want.operands, free);
        want.consumer = consumer;
        return want;
      }
    }

  // A call of a spec node is keyed over the node's owner's parameters.
  std::optional<SpecKeyAttr> spec;
  if (const auto *calleeSpec = calleeNode ? std::get_if<SpecKeyAttr>(&calleeNode->key) : nullptr)
    spec = *calleeSpec;
  std::optional<Composed> composed = composeKey(call, spec, seen);
  if (!composed)
    return std::nullopt;
  Want want;
  want.key = composed->key;
  want.owner = composed->key.getOrigin();
  want.operands = std::move(composed->values);
  return want;
}

} // namespace idr::specialize::detail
