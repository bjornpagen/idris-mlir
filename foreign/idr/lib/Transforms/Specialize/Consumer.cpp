// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// When a call may be raised, the consumer a raise node takes in as code,
// and the one decision on a call that requests and idr-redirect share.
//
// Raising moves the consumer of a call's result into the callee's tails:
// the dispatch that is all its one use does with it, the match an apply
// became. Nothing may run between the call and the dispatch that could
// tell: the dispatch and its steps are in the call's block, and either the
// call only computes (it performs no IO, cannot crash and returns; building
// actions is no IO), or every op between it and the dispatch only computes.
// A call that passes a world is never raised: the callee's body would take
// part in the world chain.
//
// A raise node is keyed by its callee and its consumer's form: the consumer
// written as a function of the call's result and the values it reads from
// outside, printed. The node is built from that text, so it is a function
// of its key, whichever call asked for it.
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Analysis/Holds.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/OperationSupport.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/Support/raw_ostream.h"

using namespace mlir;

namespace idr::specialize::detail {

std::optional<Consumer> consumerOf(idr::CallOp call, const Holds &holds) {
  if (call->getNumResults() != 1 || !call->getResult(0).hasOneUse())
    return std::nullopt;
  // The operands have the callee's parameter types, so a world one of them
  // may hold is one the callee takes.
  if (llvm::any_of(call.getArgs().getTypes(), [&](Type type) { return holds.mayHoldWorld(type); }))
    return std::nullopt;
  std::optional<Elimination> e = eliminationAt(*call->getResult(0).getUses().begin());
  if (!e || e->dispatch->getBlock() != call->getBlock())
    return std::nullopt;
  // A call that only computes may run later, after anything between it and
  // its consumer; any other only after ops that only compute. A call's
  // effects are its callee's, and every one of them is more than
  // computing. A call without effects may do anything, and the ops between
  // are walked.
  if (!idr::onlyAllocates(call))
    for (Operation *op = call->getNextNode(); op != e->dispatch.getOperation();
         op = op->getNextNode())
      if (!idr::onlyAllocates(op))
        return std::nullopt;
  return e;
}

OwningOpRef<idr::FuncOp> consumerFunction(idr::CallOp call, const Consumer &consumer,
                                          SmallVectorImpl<Value> &free) {
  MLIRContext *ctx = call.getContext();
  // The steps from the call's result to the dispatch, each the one use of
  // the one before, in the order they run.
  SmallVector<Operation *> steps;
  if (consumer.enter) {
    steps.push_back(consumer.enter);
    steps.push_back(consumer.exit);
  }
  if (consumer.field)
    steps.push_back(consumer.field);
  if (consumer.use)
    steps.push_back(consumer.use);
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
  properties.setSymVisibility(b.getStringAttr("private"));
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

// The consumer printed in the generic form, without locations: equal text
// is equal code on equal values, and the parser reads it back. Its own type
// aliases come first, so a data type's body is written once.
std::string formOf(idr::FuncOp consumer) {
  std::string text;
  llvm::raw_string_ostream os(text);
  consumer->print(os, OpPrintingFlags().printGenericOpForm().enableDebugInfo(false));
  return text;
}

std::optional<Want> decide(idr::CallOp call, const Node *requester, idr::FuncOp callee,
                           const Node *calleeNode, const BindingTimes &times,
                           const Holds &holds) {
  MLIRContext *ctx = call.getContext();
  StringAttr name = call.getCalleeAttr().getAttr();

  // A spec node raises nothing; a raise node only with its own consumer,
  // where its callee's tails meet it again; any other function freely. The
  // callee returns from its one block, where the consumer is pushed.
  Attribute own = requester ? requester->key : Attribute();
  Region &body = callee.getBody();
  if (!isa_and_nonnull<SpecKeyAttr>(own) && body.hasOneBlock() &&
      isa<idr::ReturnOp>(body.front().getTerminator()))
    if (std::optional<Consumer> consumer = consumerOf(call, holds)) {
      SmallVector<Value> free;
      OwningOpRef<idr::FuncOp> fn = consumerFunction(call, *consumer, free);
      std::string form = formOf(*fn);
      auto ownRaise = dyn_cast_or_null<KeyRaiseAttr>(own);
      if (!ownRaise || ownRaise.getConsumer().getValue() == form) {
        Want want;
        want.key = KeyRaiseAttr::get(ctx, name, StringAttr::get(ctx, form));
        want.owner = name;
        llvm::append_range(want.operands, call.getArgs());
        llvm::append_range(want.operands, free);
        want.consumer = consumer;
        return want;
      }
    }

  // A call of a spec node is keyed over the node's owner's parameters.
  auto spec = calleeNode ? dyn_cast<SpecKeyAttr>(calleeNode->key) : SpecKeyAttr();
  std::optional<Composed> composed = composeKey(call, spec, times);
  if (!composed)
    return std::nullopt;
  Want want;
  want.key = composed->key;
  want.owner = composed->key.getOrigin();
  want.operands = std::move(composed->values);
  return want;
}

} // namespace idr::specialize::detail
