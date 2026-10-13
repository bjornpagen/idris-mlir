// How values move between the slots of the module, the labels each closure,
// suspension or constant puts in a slot, and where a value moves somewhere
// the analysis does not follow.

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Labels.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinOps.h"

#include "llvm/ADT/STLExtras.h"

#include <optional>

using namespace mlir;

namespace idr::defunctionalize {

Key Slots::sinkKey(OpOperand &use) const {
  return sinks.lookup({use.getOwner(), use.getOperandNumber()});
}

// The slot a use moves its value into, or a null key.
Key Slots::sinkOf(OpOperand &use) const {
  Operation *user = use.getOwner();
  unsigned index = use.getOperandNumber();
  if (isa<ReturnOp>(user))
    return resultKey(user->getParentOfType<FuncOp>().getSymNameAttr(), index);
  if (isa<YieldOp>(user)) {
    Operation *parent = user->getParentOp();
    // An evaluated suspension's value is in the forced state of a cell no
    // label reaches, which the keys of its type do not follow: a closure
    // or a suspension there is lost.
    if (isa<DelayOp>(parent))
      return {};
    // A generate stores what its body yields as an element.
    if (auto generate = dyn_cast<ArrayGenerateOp>(parent))
      return elementKey(generate.getArrayType().getElementType());
    return values.lookup(parent->getResult(index));
  }
  if (auto call = dyn_cast<CallOp>(user))
    return argumentKey(call.getCalleeAttr().getAttr(), index);
  if (auto con = dyn_cast<ConOp>(user))
    return fieldKey(con.getCtor(), index);
  if (auto closure = dyn_cast<ClosureOp>(user))
    return argumentKey(closure.getCalleeAttr().getAttr(), index);
  if (auto suspend = dyn_cast<SuspendOp>(user))
    return argumentKey(suspend.getCalleeAttr().getAttr(), index);
  if (isa<LinEnterOp, LinUseOp>(user))
    return values.lookup(user->getResult(0));
  if (auto made = dyn_cast<ArrayNewOp>(user))
    return &use == &made.getFillMutable() ? elementKey(made.getArrayType().getElementType())
                                          : Key();
  if (auto generate = dyn_cast<ArrayGenerateOp>(user))
    return &use == &generate.getFillMutable()
               ? elementKey(generate.getArrayType().getElementType())
               : Key();
  if (auto stored = dyn_cast<ArraySetOp>(user))
    return &use == &stored.getValueMutable() ? elementKey(stored.getArrayType().getElementType())
                                             : Key();
  // A fold carries its accumulator from the init through each yield to its
  // result, one slot all along, as the body's first argument is.
  if (auto fold = dyn_cast<ArrayFoldOp>(user))
    return &use == &fold.getInitMutable() ? values.lookup(fold.getResult()) : Key();
  return {};
}

// Ops whose closure and suspension operands, results and region arguments
// the pass follows. Those of any other op are lost to the analysis. A force
// reads its cell where it is, and its result is what its labels return; a
// poison holds no label, and an evaluated suspension none either.
bool Slots::isFollowed(Operation *op) {
  return isa<FuncOp, CallOp, ReturnOp, YieldOp, ConOp, ClosureOp, SuspendOp, DelayOp, ForceOp,
             ApplyOp, FieldOp, MatchOp, MatchLitOp, LinEnterOp, LinUseOp, ConstantOp,
             ub::PoisonOp, ArrayNewOp, ArrayGetOp, ArraySetOp, ArrayGenerateOp, ArrayFoldOp>(op);
}

// A closure, suspension or constant whose every use moves it into slots of
// one key with more labels takes that key, so that it needs no coercion.
void Slots::widen() {
  module.walk([&](Operation *op) {
    if (!isa<ClosureOp, SuspendOp, ConstantOp>(op) || !isKeyed(op->getResultTypes()[0]))
      return;
    Value value = op->getResult(0);
    std::optional<Key> common;
    for (OpOperand &use : value.getUses()) {
      Key to = sinkOf(use);
      if (!to.first || (common && *common != to))
        return;
      common = to;
    }
    if (common && within(values.lookup(value), *common))
      values[value] = *common;
  });
}

// A move at `at`. Where one side's labels are unknown, the analysis lost
// the value there.
void Slots::move(Operation *at, const Key &from, const Key &to) {
  flows.push_back({from, to});
  for (const Key &key : {from, to}) {
    note(key, at);
    if (key.first && (!from.second || !to.second))
      lost.try_emplace(key, at);
  }
}

// The labels of the closures stored in constant `attr`, in a slot of
// `slot`.
void Slots::constantSources(Attribute attr, const Key &slot) {
  if (!analysis.holdsClosure(attr) || !sourced.insert({attr, slot}).second)
    return;
  if (auto closure = dyn_cast<ClosureAttr>(attr)) {
    StringAttr label = closure.getCallee().getAttr();
    if (slot.first)
      sources.push_back({label, slot});
    for (auto [i, capture] : llvm::enumerate(closure.getCaptures()))
      constantSources(capture, argumentKey(label, static_cast<unsigned>(i)));
    return;
  }
  if (auto con = dyn_cast<ConAttr>(attr))
    eachField(con, [&](Attribute value, unsigned i) {
      constantSources(value, fieldKey(con.getCtor(), i));
    });
}

// The moves between slots, the slot each keyed operand moves into, and the
// labels each closure or suspension puts in a slot.
void Slots::connect() {
  module.walk([&](Operation *op) {
    if (auto closure = dyn_cast<ClosureOp>(op))
      sources.push_back({closure.getCalleeAttr().getAttr(), values.lookup(closure.getResult())});
    if (auto suspend = dyn_cast<SuspendOp>(op))
      sources.push_back({suspend.getCalleeAttr().getAttr(), values.lookup(suspend.getResult())});
    if (auto delay = dyn_cast<DelayOp>(op))
      evaluated.insert(values.lookup(delay.getResult()));
    if (auto constant = dyn_cast<ConstantOp>(op))
      constantSources(constant.getValue(), values.lookup(constant.getResult()));
    if (auto call = dyn_cast<CallOp>(op)) {
      StringAttr callee = call.getCalleeAttr().getAttr();
      for (OpResult value : call.getResults())
        if (isKeyed(value.getType()))
          move(op,
               signature(callee) ? resultKey(callee, value.getResultNumber())
                                 : unknown(value.getType()),
               values.lookup(value));
    }
    if (auto apply = dyn_cast<ApplyOp>(op)) {
      connect(apply);
      return;
    }
    // A value an evaluated suspension holds is lost at the suspension.
    Operation *site = isa<YieldOp>(op) && isa<DelayOp>(op->getParentOp()) ? op->getParentOp() : op;
    for (OpOperand &use : op->getOpOperands()) {
      if (!isKeyed(use.get().getType()) || isa<ForceOp>(op))
        continue;
      Key to = isFollowed(op) ? sinkOf(use) : Key();
      if (!to.first)
        to = unknown(use.get().getType());
      sinks[{op, use.getOperandNumber()}] = to;
      move(site, values.lookup(use.get()), to);
    }
    if (!isFollowed(op))
      for (OpResult value : op->getResults())
        if (isKeyed(value.getType()))
          move(op, unknown(value.getType()), values.lookup(value));
    // Arguments of blocks the pass does not follow the branches to.
    if (!isFollowed(op) || isa<FuncOp>(op))
      for (Region &region : op->getRegions())
        for (Block &block : region)
          for (BlockArgument arg : block.getArguments())
            if (isKeyed(arg.getType()) && !(isa<FuncOp>(op) && block.isEntryBlock()))
              move(op, unknown(arg.getType()), values.lookup(arg));
  });
}

// Through an apply, the arguments move into each label's and the label's
// results into the apply's.
void Slots::connect(ApplyOp apply) {
  Key callee = values.lookup(apply.getCallee());
  if (!callee.second)
    return;
  for (StringAttr label : callee.second.getAsRange<StringAttr>()) {
    if (!fits(label, callee.first))
      continue;
    unsigned first = captures(label, callee.first);
    for (auto [i, arg] : llvm::enumerate(apply.getArgs()))
      if (isKeyed(arg.getType()))
        move(apply, values.lookup(arg), argumentKey(label, first + static_cast<unsigned>(i)));
    for (OpResult value : apply.getResults())
      if (isKeyed(value.getType()))
        move(apply, resultKey(label, value.getResultNumber()), values.lookup(value));
  }
}

} // namespace idr::defunctionalize
