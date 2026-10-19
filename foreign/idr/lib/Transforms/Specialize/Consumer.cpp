// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// When a call may be raised, the consumer a raise node takes in as code,
// the run's table of consumer forms, and the one decision on a call that
// requests and idr-redirect share.
//
// Raising moves the consumer of a call's result into the callee's tails:
// the dispatch that is all its one use does with it, the match an apply
// became, or the output of a string (idr::eliminationAt). Nothing may run
// between the call and the dispatch that could tell: the dispatch and its
// steps are in the call's block, and the call may run at the dispatch
// (idr::mayRunAt, the rule idr-trmc moves a call by; building actions is
// no IO). A call that passes a world is never raised: the callee's body
// would take part in the world chain.
//
// A raise node is keyed by its callee and its consumer's form: the consumer
// written as a function of the call's result and the values it reads from
// outside, held once in the run's table and named there by the digest of
// its canonical text. The node is built from that form, so it is a function
// of its key, whichever call asked for it.
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Grades.h"
#include "idr/Transforms/Deduplicate.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/IRMapping.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/Support/raw_ostream.h"

#include <string>

using namespace mlir;

namespace idr::specialize::detail {

std::optional<Consumer> consumerOf(idr::CallOp call) {
  if (call->getNumResults() != 1 || !call->getResult(0).hasOneUse())
    return std::nullopt;
  // The operands have the callee's parameter types, so a world one of them
  // may hold is one the callee takes.
  if (llvm::any_of(call.getArgs().getTypes(), [](Type type) { return idr::holdsWorld(type); }))
    return std::nullopt;
  std::optional<Elimination> e = eliminationAt(*call->getResult(0).getUses().begin());
  if (!e || e->dispatch->getBlock() != call->getBlock())
    return std::nullopt;
  // The call runs where its consumer is.
  if (!idr::mayRunAt(call, e->dispatch))
    return std::nullopt;
  return e;
}

OwningOpRef<idr::FuncOp> consumerFunction(idr::CallOp call, const Consumer &consumer,
                                          SmallVectorImpl<Value> &free) {
  MLIRContext *ctx = call.getContext();
  // The steps from the call's result to the dispatch, each the one use of
  // the one before, in the order they run.
  SmallVector<Operation *> steps = consumer.steps();
  Operation *dispatch = consumer.dispatch;

  // The values the dispatch and its regions read from outside it (the
  // world an output writes, what a case reads), in the order a pre-order
  // walk first reads them, but the call's result and what the steps make,
  // which the copy makes itself. The steps read only the step before.
  llvm::SmallPtrSet<Operation *, 4> made(steps.begin(), steps.end());
  made.insert(call);
  llvm::SetVector<Value> outside;
  dispatch->walk<WalkOrder::PreOrder>([&](Operation *op) {
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
      TypeAttr::get(FunctionType::get(ctx, inputs, dispatch->getResultTypes())));
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
// consumer is printed, for the digest that names its form, only when no
// form met before is it; the print is outside the lock.
FailureOr<StringAttr> Forms::intern(Location at, OwningOpRef<idr::FuncOp> consumer) {
  unsigned hash = static_cast<unsigned>(
      static_cast<size_t>(idr::deduplicate::hashFunction(*consumer)));
  // Under the lock: the form interned before that `consumer` is, if one is.
  auto met = [&]() -> std::optional<StringAttr> {
    for (StringAttr form : byHash[hash])
      if (idr::deduplicate::sameFunction(byForm.at(form).get(), *consumer))
        return form;
    return std::nullopt;
  };
  {
    std::lock_guard lock(mutex);
    if (std::optional<StringAttr> form = met())
      return *form;
  }
  std::string digest;
  llvm::raw_string_ostream(digest) << digestOf(canonicalText(consumer->getOperation()));
  StringAttr name = StringAttr::get(consumer->getContext(), digest);
  std::lock_guard lock(mutex);
  // Another worker may have interned it since.
  if (std::optional<StringAttr> form = met())
    return *form;
  if (!byForm.try_emplace(name, std::move(consumer)).second)
    return emitError(at) << "internal error: two consumer forms have the digest " << digest;
  byHash[hash].push_back(name);
  return name;
}

idr::FuncOp Forms::at(StringAttr form) const {
  std::lock_guard lock(mutex);
  return byForm.at(form).get();
}

FailureOr<std::optional<Want>> decide(idr::CallOp call, const Node *requester,
                                      idr::FuncOp callee, const Node *calleeNode,
                                      ArrayRef<BindingTime> seen, Forms &forms) {
  MLIRContext *ctx = call.getContext();
  StringAttr name = call.getCalleeAttr().getAttr();

  // A spec node raises nothing; a raise node only with its own consumer,
  // where its callee's tails meet it again; any other function freely. The
  // callee returns from its one block, where the consumer is pushed; one
  // that never returns has no tail to push it to.
  const Key *own = requester ? &requester->key : nullptr;
  if (!(own && std::holds_alternative<SpecKeyAttr>(*own)) &&
      isa<idr::ReturnOp>(callee.getBody().front().getTerminator()))
    if (std::optional<Consumer> consumer = consumerOf(call)) {
      SmallVector<Value> free;
      FailureOr<StringAttr> form =
          forms.intern(call.getLoc(), consumerFunction(call, *consumer, free));
      if (failed(form))
        return failure();
      const auto *ownRaise = own ? std::get_if<RaiseKey>(own) : nullptr;
      if (!ownRaise || ownRaise->getForm() == *form) {
        RaiseWant want{KeyRaiseAttr::get(ctx, name, *form), *consumer, {}};
        llvm::append_range(want.operands, call.getArgs());
        llvm::append_range(want.operands, free);
        return std::optional<Want>(std::move(want));
      }
    }

  // A call of a spec node is keyed over the node's owner's parameters.
  std::optional<SpecKeyAttr> spec;
  if (const auto *calleeSpec = calleeNode ? std::get_if<SpecKeyAttr>(&calleeNode->key) : nullptr)
    spec = *calleeSpec;
  std::optional<Composed> composed = composeKey(call, spec, seen);
  if (!composed)
    return std::optional<Want>();
  return std::optional<Want>(SpecWant{composed->key, std::move(composed->values)});
}

} // namespace idr::specialize::detail
