// idr.defunctionalize:moves: how values move between the slots of the
// module, the labels each closure, suspension or constant puts in a slot,
// and where a value moves somewhere the analysis does not follow.
export module idr.defunctionalize:moves;

import idr.mlir;
import idr.dialect;

import :closures;
import :slots;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::defunctionalize {

// A value moves from a slot of `from` into a slot of `to`.
struct Flow {
  Key from, to;
};

// Operand `index` of `user` moves into a slot of `to`.
struct Sink {
  Operation *user;
  unsigned index;
  Key to;
};

struct Moves : Slots {
  using Slots::Slots;

  SmallVector<Sink> sinks;
  SmallVector<Flow> flows;
  // A closure, suspension or constant of a label in a slot of a key.
  SmallVector<std::pair<StringAttr, Key>> sources;
  // A shared part of a constant, in a slot, is sourced once.
  llvm::DenseSet<std::pair<Attribute, Key>> sourced;
  // The first op where a value of each key meets a slot whose labels the
  // analysis does not know: where it lost that value.
  llvm::DenseMap<Key, Operation *> lost;

  // The slot a use moves its value into, or a null key.
  Key sinkOf(OpOperand &use) {
    Operation *user = use.getOwner();
    unsigned index = use.getOperandNumber();
    if (isa<func::ReturnOp>(user))
      return result(user->getParentOfType<func::FuncOp>(), index);
    if (isa<idr::YieldOp>(user)) {
      // A generate stores what its body yields as an element.
      if (auto generate = dyn_cast<idr::ArrayGenerateOp>(user->getParentOp()))
        return elements(generate.getArrayType());
      return values.lookup(user->getParentOp()->getResult(index));
    }
    if (auto call = dyn_cast<func::CallOp>(user))
      return argument(call.getCalleeAttr().getAttr(), index);
    if (auto con = dyn_cast<idr::ConOp>(user))
      return field(con.getCtor(), index);
    if (auto closure = dyn_cast<idr::ClosureOp>(user))
      return argument(closure.getCalleeAttr().getAttr(), index);
    if (auto suspend = dyn_cast<idr::SuspendOp>(user))
      return argument(suspend.getCalleeAttr().getAttr(), index);
    if (isa<idr::LinEnterOp, idr::LinUseOp>(user))
      return values.lookup(user->getResult(0));
    if (auto made = dyn_cast<idr::ArrayNewOp>(user))
      return &use == &made.getFillMutable() ? elements(made.getArrayType()) : Key();
    if (auto generate = dyn_cast<idr::ArrayGenerateOp>(user))
      return &use == &generate.getFillMutable() ? elements(generate.getArrayType()) : Key();
    if (auto stored = dyn_cast<idr::ArraySetOp>(user))
      return &use == &stored.getValueMutable() ? elements(stored.getArrayType()) : Key();
    // A fold carries its accumulator from the init through each yield to its
    // result, one slot all along, as the body's first argument is.
    if (auto fold = dyn_cast<idr::ArrayFoldOp>(user))
      return &use == &fold.getInitMutable() ? values.lookup(fold.getResult()) : Key();
    return {};
  }

  // Ops whose closure and suspension operands, results and region arguments
  // the pass follows. Those of any other op are lost to the analysis. A
  // force reads its cell where it is, and its result is what its labels
  // return; a poison holds no label.
  static bool isFollowed(Operation *op) {
    return isa<func::FuncOp, func::CallOp, func::ReturnOp, idr::YieldOp, idr::ConOp,
               idr::ClosureOp, idr::SuspendOp, idr::ForceOp, idr::ApplyOp, idr::FieldOp,
               idr::MatchOp, idr::MatchLitOp, idr::LinEnterOp, idr::LinUseOp,
               idr::ConstantOp, ub::PoisonOp, idr::ArrayNewOp, idr::ArrayGetOp,
               idr::ArraySetOp, idr::ArrayGenerateOp, idr::ArrayFoldOp>(op);
  }

  // A closure, suspension or constant whose every use moves it into slots of
  // one key with more labels takes that key, so that it needs no coercion.
  void widen() {
    module.op.walk([&](Operation *op) {
      if (!isa<idr::ClosureOp, idr::SuspendOp, idr::ConstantOp>(op) ||
          !isKeyed(op->getResultTypes()[0]))
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
  void move(Operation *at, const Key &from, const Key &to) {
    flows.push_back({from, to});
    for (const Key &key : {from, to}) {
      note(key, at);
      if (key.first && (!from.second || !to.second))
        lost.try_emplace(key, at);
    }
  }

  // The labels of the closures stored in constant `attr`, in a slot of
  // `slot`.
  void constantSources(Attribute attr, const Key &slot) {
    if (!module.holdsClosure(attr) || !sourced.insert({attr, slot}).second)
      return;
    if (auto closure = dyn_cast<idr::ClosureAttr>(attr)) {
      StringAttr label = closure.getCallee().getAttr();
      if (slot.first)
        sources.push_back({label, slot});
      for (auto [i, capture] : llvm::enumerate(closure.getCaptures()))
        constantSources(capture, argument(label, static_cast<unsigned>(i)));
      return;
    }
    if (auto con = dyn_cast<idr::ConAttr>(attr))
      eachField(con, [&](Attribute value, unsigned i) {
        constantSources(value, field(con.getCtor(), i));
      });
  }

  // The moves between slots, and the labels each closure or suspension puts
  // in a slot.
  void connect() {
    module.op.walk([&](Operation *op) {
      if (auto closure = dyn_cast<idr::ClosureOp>(op))
        sources.push_back({closure.getCalleeAttr().getAttr(), values.lookup(closure.getResult())});
      if (auto suspend = dyn_cast<idr::SuspendOp>(op))
        sources.push_back({suspend.getCalleeAttr().getAttr(), values.lookup(suspend.getResult())});
      if (auto constant = dyn_cast<idr::ConstantOp>(op))
        constantSources(constant.getValue(), values.lookup(constant.getResult()));
      if (auto call = dyn_cast<func::CallOp>(op)) {
        func::FuncOp fn = module.function(call.getCalleeAttr().getAttr());
        for (OpResult value : call.getResults())
          if (isKeyed(value.getType()))
            move(op, fn ? result(fn, value.getResultNumber()) : unknown(value.getType()),
                 values.lookup(value));
      }
      if (auto apply = dyn_cast<idr::ApplyOp>(op)) {
        connect(apply);
        return;
      }
      for (OpOperand &use : op->getOpOperands()) {
        if (!isKeyed(use.get().getType()) || isa<idr::ForceOp>(op))
          continue;
        Key to = isFollowed(op) ? sinkOf(use) : Key();
        if (!to.first)
          to = unknown(use.get().getType());
        sinks.push_back({op, use.getOperandNumber(), to});
        move(op, values.lookup(use.get()), to);
      }
      if (!isFollowed(op))
        for (OpResult value : op->getResults())
          if (isKeyed(value.getType()))
            move(op, unknown(value.getType()), values.lookup(value));
      // Arguments of blocks the pass does not follow the branches to.
      if (!isFollowed(op) || isa<func::FuncOp>(op))
        for (Region &region : op->getRegions())
          for (Block &block : region)
            for (BlockArgument arg : block.getArguments())
              if (isKeyed(arg.getType()) && !(isa<func::FuncOp>(op) && block.isEntryBlock()))
                move(op, unknown(arg.getType()), values.lookup(arg));
    });
  }

  // Through an apply, the arguments move into each label's and the label's
  // results into the apply's.
  void connect(idr::ApplyOp apply) {
    Key callee = values.lookup(apply.getCallee());
    if (!callee.second)
      return;
    for (StringAttr label : callee.second.getAsRange<StringAttr>()) {
      if (!fits(label, callee.first))
        continue;
      func::FuncOp fn = module.function(label);
      size_t first = captures(label, callee.first);
      for (auto [i, arg] : llvm::enumerate(apply.getArgs()))
        if (isKeyed(arg.getType()))
          move(apply, values.lookup(arg), argument(fn, static_cast<unsigned>(first + i)));
      for (OpResult value : apply.getResults())
        if (isKeyed(value.getType()))
          move(apply, result(fn, value.getResultNumber()), values.lookup(value));
    }
  }
};

} // namespace idr::defunctionalize
