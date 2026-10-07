// idr.defunctionalize:slots: the key of every slot that holds a closure (its
// closure type and the labels the analysis found for it), and the moves of
// values between slots.
export module idr.defunctionalize:slots;

import idr.mlir;
import idr.dialect;

import :closures;
import :labels;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::defunctionalize {

// The key of a slot: its closure type and the labels it may hold, sorted by
// name, or null labels when they are unknown. A null type means the slot
// holds no closure.
using Key = std::pair<idr::FnType, ArrayAttr>;

bool isEmpty(const Key &key) { return key.second && key.second.empty(); }

// Whether every label of `a` is one of `b`'s.
bool within(const Key &a, const Key &b) {
  return a.second && b.second && llvm::all_of(a.second, [&](Attribute label) {
           return llvm::is_contained(b.second, label);
         });
}

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

size_t arity(idr::FnType type) { return type.getInputs().size(); }

// The slots of the module that hold closures, each with its key: of values
// (entry arguments included), of function results and of fields; and how
// values move between them.
struct Slots {
  Slots(Module &closures, DataFlowSolver &dataflow)
      : module(closures), solver(dataflow), ctx(closures.op.getContext()) {}

  Module &module;
  DataFlowSolver &solver;
  MLIRContext *ctx;

  // The keys of closure values (entry arguments included), of function
  // results and of fields.
  llvm::DenseMap<Value, Key> values;
  llvm::DenseMap<Operation *, SmallVector<Key>> results;
  llvm::DenseMap<std::tuple<StringAttr, StringAttr, unsigned>, Key> fields;
  // A shared part of a constant, in a slot, is sourced and converted once.
  llvm::DenseSet<std::pair<Attribute, Key>> sourced;
  llvm::DenseMap<std::pair<Attribute, Key>, Attribute> convertedParts;
  // Every key by first appearance, with its sum once numbered.
  // The sum of each converted key: unboxed, or boxed when the key is on a
  // cycle of captures, which only a heap cell can end.
  llvm::MapVector<Key, Type> keys;
  llvm::DenseSet<Key> converted;
  llvm::DenseSet<Key> cyclic;

  SmallVector<Sink> sinks;
  SmallVector<Flow> flows;
  // A closure op or constant of a label in a slot of a key.
  SmallVector<std::pair<StringAttr, Key>> sources;

  Key keyOf(Type type, const Labels &labels) {
    auto fnType = cast<idr::FnType>(idr::unrestricted(type));
    if (labels.unknown)
      return {fnType, ArrayAttr()};
    return {fnType, ArrayAttr::get(ctx, SmallVector<Attribute>(labels.names.begin(),
                                                               labels.names.end()))};
  }

  Key unknown(Type type) { return {cast<idr::FnType>(idr::unrestricted(type)), ArrayAttr()}; }

  // What the analysis found for `value`, with the label of the closure or
  // closure constant that defines it.
  Labels labelsOf(Value value) {
    Labels out;
    if (const auto *lattice = solver.lookupState<LabelLattice>(value))
      out = lattice->getValue();
    if (auto closure = value.getDefiningOp<idr::ClosureOp>())
      out = Labels::join(out, Labels::of(closure.getCalleeAttr().getAttr()));
    if (auto constant = value.getDefiningOp<idr::ConstantOp>())
      if (auto closure = dyn_cast<idr::ClosureAttr>(constant.getValue()))
        out = Labels::join(out, Labels::of(closure.getCallee().getAttr()));
    return out;
  }

  Key field(SymbolRefAttr ctor, unsigned index) {
    return fields.lookup({ctor.getRootReference(), ctor.getLeafReference(), index});
  }

  Key argument(func::FuncOp fn, unsigned index) {
    if (!fn || index >= fn.getNumArguments())
      return {};
    Type type = fn.getArgumentTypes()[index];
    if (fn.isExternal())
      return isClosureType(type) ? unknown(type) : Key();
    return values.lookup(fn.getArgument(index));
  }

  Key argument(StringAttr label, unsigned index) {
    return argument(module.function(label), index);
  }

  Key result(func::FuncOp fn, unsigned index) {
    auto it = results.find(fn.getOperation());
    return it == results.end() ? Key() : it->second[index];
  }

  // Whether `label` is a function whose signature ends in `type`'s.
  bool fits(StringAttr label, idr::FnType type) {
    func::FuncOp fn = module.function(label);
    return fn && !fn.isExternal() && fn.getNumArguments() >= arity(type) &&
           llvm::equal(fn.getArgumentTypes().take_back(arity(type)), type.getInputs()) &&
           llvm::equal(fn.getResultTypes(), type.getResults());
  }

  // The number of captures of `label` as a closure of `type`.
  size_t captures(StringAttr label, idr::FnType type) {
    return module.function(label).getNumArguments() - arity(type);
  }

  // The slot a use moves its value into, or a null key.
  Key sinkOf(OpOperand &use) {
    Operation *user = use.getOwner();
    unsigned index = use.getOperandNumber();
    if (isa<func::ReturnOp>(user))
      return result(user->getParentOfType<func::FuncOp>(), index);
    if (isa<idr::YieldOp>(user))
      return values.lookup(user->getParentOp()->getResult(index));
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
    return {};
  }

  // Ops whose closure operands, results and region arguments the pass
  // follows. Those of any other op stay closures. A force's result is the
  // closure its suspension returns, already keyed, so it is not an unknown
  // incoming closure.
  static bool isFollowed(Operation *op) {
    return isa<func::FuncOp, func::CallOp, func::ReturnOp, idr::YieldOp, idr::ConOp,
               idr::ClosureOp, idr::SuspendOp, idr::ForceOp, idr::ApplyOp, idr::FieldOp,
               idr::MatchOp, idr::MatchLitOp, idr::LinEnterOp, idr::LinUseOp,
               idr::ConstantOp>(op);
  }

  void keyFields() {
    module.op.walk([&](idr::CtorOp ctor) {
      auto data = ctor->getParentOfType<idr::DataOp>().getSymNameAttr();
      for (auto [i, type] : llvm::enumerate(ctor.getFieldTypes().getAsValueRange<TypeAttr>())) {
        if (!isClosureType(type))
          continue;
        auto index = std::make_tuple(data, ctor.getSymNameAttr(), unsigned(i));
        const auto *state =
            solver.lookupState<FieldLabels>(solver.getLatticeAnchor<FieldAnchor>(index));
        fields[index] = keyOf(type, state ? state->value : Labels{});
      }
    });
  }

  void keyFunctions() {
    for (func::FuncOp fn : module.op.getOps<func::FuncOp>()) {
      SmallVector<Labels> joined(fn.getNumResults());
      if (fn.isExternal())
        llvm::for_each(joined, [](Labels &labels) { labels.unknown = true; });
      else
        for (BlockArgument arg : fn.getArguments())
          if (isClosureType(arg.getType()))
            values[arg] = keyOf(arg.getType(), labelsOf(arg));
      fn.walk([&](func::ReturnOp ret) {
        for (auto [operand, labels] : llvm::zip(ret.getOperands(), joined))
          labels = Labels::join(labels, labelsOf(operand));
      });
      SmallVector<Key> &out = results[fn.getOperation()];
      for (auto [type, labels] : llvm::zip(fn.getResultTypes(), joined))
        out.push_back(isClosureType(type) ? keyOf(type, labels) : Key());
    }
  }

  void keyValues() {
    module.op.walk([&](Operation *op) {
      auto match = dyn_cast<idr::MatchOp>(op);
      for (Region &region : op->getRegions())
        for (Block &block : region)
          for (BlockArgument arg : block.getArguments()) {
            if (!isClosureType(arg.getType()) ||
                (isa<func::FuncOp>(op) && block.isEntryBlock()))
              continue;
            // The arguments of a case are the fields of its constructor.
            if (match) {
              auto ctor = cast<FlatSymbolRefAttr>(match.getCases()[region.getRegionNumber()]);
              values[arg] = field(
                  SymbolRefAttr::get(dataName(match.getScrutinee().getType()), {ctor}),
                  arg.getArgNumber());
            } else {
              values[arg] = keyOf(arg.getType(), labelsOf(arg));
            }
          }
      for (OpResult result : op->getResults()) {
        if (!isClosureType(result.getType()))
          continue;
        if (auto read = dyn_cast<idr::FieldOp>(op))
          values[result] = field(
              SymbolRefAttr::get(dataName(read.getValue().getType()), {read.getCtorAttr()}),
              static_cast<unsigned>(read.getIndex()));
        else if (auto force = dyn_cast<idr::ForceOp>(op)) {
          // The value is what the suspension's function returns. The force
          // does not name that function, so the labels would otherwise be
          // unknown and the lazy type and the value would part.
          Key produced;
          Value suspension = force.getSuspension();
          StringAttr name;
          if (auto suspend = suspension.getDefiningOp<idr::SuspendOp>())
            name = suspend.getCalleeAttr().getAttr();
          else if (auto constant = suspension.getDefiningOp<idr::ConstantOp>())
            if (auto closure = dyn_cast<idr::ClosureAttr>(constant.getValue()))
              name = closure.getCallee().getAttr();
          if (name)
            produced = this->result(module.function(name), 0);
          auto fnType = cast<idr::FnType>(idr::unrestricted(result.getType()));
          values[result] = produced.first == fnType ? produced
                                                    : keyOf(result.getType(), labelsOf(result));
        } else
          values[result] = keyOf(result.getType(), labelsOf(result));
      }
    });
    // A closure or constant whose every use moves it into slots of one key
    // with more labels takes that key, so that it needs no coercion.
    module.op.walk([&](Operation *op) {
      if (!isa<idr::ClosureOp, idr::ConstantOp>(op) || !isClosureType(op->getResultTypes()[0]))
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

  // Every slot's key in the order the module shows it.
  void order() {
    auto note = [&](const Key &key) {
      if (key.first)
        keys.insert({key, Type()});
    };
    module.op->walk<WalkOrder::PreOrder>([&](Operation *op) {
      if (auto ctor = dyn_cast<idr::CtorOp>(op)) {
        auto data = ctor->getParentOfType<idr::DataOp>().getSymNameAttr();
        for (unsigned i = 0; i < ctor.getFieldTypes().size(); ++i)
          note(fields.lookup({data, ctor.getSymNameAttr(), i}));
        return;
      }
      if (auto fn = dyn_cast<func::FuncOp>(op)) {
        for (unsigned i = 0; i < fn.getNumArguments(); ++i)
          note(argument(fn, i));
        llvm::for_each(results.lookup(fn.getOperation()), note);
        return;
      }
      for (Value result : op->getResults())
        note(values.lookup(result));
      for (Region &region : op->getRegions())
        for (Block &block : region)
          for (Value arg : block.getArguments())
            note(values.lookup(arg));
    });
  }

  // The labels of the closures stored in constant `attr`, in a slot of
  // `slot` (a null key where the slot is not a closure).
  void constantSources(Attribute attr, const Key &slot) {
    if (!module.holdsClosure(attr) || !sourced.insert({attr, slot}).second)
      return;
    if (auto closure = dyn_cast<idr::ClosureAttr>(attr)) {
      StringAttr label = closure.getCallee().getAttr();
      // A suspension's slot is not a closure. Recording the function as a
      // source would build a sum for it.
      if (slot.first)
        sources.push_back({label, slot});
      for (auto [i, capture] : llvm::enumerate(closure.getCaptures()))
        constantSources(capture, argument(label, static_cast<unsigned>(i)));
      return;
    }
    if (auto con = dyn_cast<idr::ConAttr>(attr))
      for (auto [i, value] : llvm::enumerate(con.getFields()))
        constantSources(value, field(con.getCtor(), static_cast<unsigned>(i)));
  }

  // The moves between slots, and the labels each closure puts in a slot.
  void connect() {
    module.op.walk([&](Operation *op) {
      if (auto closure = dyn_cast<idr::ClosureOp>(op))
        sources.push_back({closure.getCalleeAttr().getAttr(), values.lookup(closure.getResult())});
      if (auto constant = dyn_cast<idr::ConstantOp>(op))
        constantSources(constant.getValue(), values.lookup(constant.getResult()));
      if (auto call = dyn_cast<func::CallOp>(op)) {
        func::FuncOp fn = module.function(call.getCalleeAttr().getAttr());
        for (OpResult value : call.getResults())
          if (isClosureType(value.getType()))
            flows.push_back({fn ? result(fn, value.getResultNumber()) : unknown(value.getType()),
                             values.lookup(value)});
      }
      if (auto apply = dyn_cast<idr::ApplyOp>(op)) {
        connect(apply);
        return;
      }
      for (OpOperand &use : op->getOpOperands()) {
        if (!isClosureType(use.get().getType()))
          continue;
        Key to = isFollowed(op) ? sinkOf(use) : Key();
        if (!to.first)
          to = unknown(use.get().getType());
        sinks.push_back({op, use.getOperandNumber(), to});
        flows.push_back({values.lookup(use.get()), to});
      }
      if (!isFollowed(op))
        for (OpResult value : op->getResults())
          if (isClosureType(value.getType()))
            flows.push_back({unknown(value.getType()), values.lookup(value)});
      // Arguments of blocks the pass does not follow the branches to.
      if (!isFollowed(op) || isa<func::FuncOp>(op))
        for (Region &region : op->getRegions())
          for (Block &block : region)
            for (BlockArgument arg : block.getArguments())
              if (isClosureType(arg.getType()) &&
                  !(isa<func::FuncOp>(op) && block.isEntryBlock()))
                flows.push_back({unknown(arg.getType()), values.lookup(arg)});
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
        if (isClosureType(arg.getType()))
          flows.push_back({values.lookup(arg), argument(fn, static_cast<unsigned>(first + i))});
      for (OpResult value : apply.getResults())
        if (isClosureType(value.getType()))
          flows.push_back({result(fn, value.getResultNumber()), values.lookup(value)});
    }
  }
};

} // namespace idr::defunctionalize
