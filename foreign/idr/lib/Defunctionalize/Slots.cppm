// idr.defunctionalize:slots: the key of every slot that holds a closure or
// a suspension (its type and the labels the analysis found for it), in the
// order the module shows them.
export module idr.defunctionalize:slots;

import idr.mlir;
import idr.dialect;

import :closures;
import :labels;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::defunctionalize {

// The key of a slot: its closure or lazy type and the labels it may hold,
// sorted by name, or null labels when they are unknown. A null type means
// the slot holds neither.
using Key = std::pair<Type, ArrayAttr>;

bool isEmpty(const Key &key) { return key.second && key.second.empty(); }

bool isLazy(const Key &key) { return key.first && isa<idr::LazyType>(key.first); }

// Whether every label of `a` is one of `b`'s.
bool within(const Key &a, const Key &b) {
  return a.second && b.second && llvm::all_of(a.second, [&](Attribute label) {
           return llvm::is_contained(b.second, label);
         });
}

// The arguments a label of `type` is called with besides its captures: a
// closure's, or none, since every parameter of a suspended function is a
// capture.
size_t arity(Type type) {
  auto fn = dyn_cast<idr::FnType>(type);
  return fn ? fn.getInputs().size() : 0;
}

// The slots of the module that hold closures or suspensions, each with its
// key: of values (entry arguments included), of function results, of fields
// and of the elements of arrays.
struct Slots {
  Slots(Module &closures, DataFlowSolver &dataflow)
      : module(closures), solver(dataflow), ctx(closures.op.getContext()) {}

  Module &module;
  DataFlowSolver &solver;
  MLIRContext *ctx;

  llvm::DenseMap<Value, Key> values;
  llvm::DenseMap<Operation *, SmallVector<Key>> results;
  llvm::DenseMap<std::tuple<StringAttr, StringAttr, unsigned>, Key> fields;
  // By element type.
  llvm::DenseMap<Type, Key> arrays;
  // Every key by first appearance, with its sum once numbered, and the op
  // it first appears at. The sum of each converted key: unboxed, or boxed
  // when the key is on a cycle of captures, which only a heap cell can end,
  // or when it is a suspension's, whose cell has one memo.
  llvm::MapVector<Key, Type> keys;
  llvm::DenseMap<Key, Operation *> firstSeen;

  Key keyOf(Type type, const Labels &labels) {
    Type carrier = idr::unrestricted(type);
    if (labels.unknown)
      return {carrier, ArrayAttr()};
    return {carrier, ArrayAttr::get(ctx, SmallVector<Attribute>(labels.names.begin(),
                                                                labels.names.end()))};
  }

  Key unknown(Type type) { return {idr::unrestricted(type), ArrayAttr()}; }

  // What the analysis found for `value`, with the label of the closure,
  // suspension or constant that defines it.
  Labels labelsOf(Value value) {
    Labels out;
    if (const auto *lattice = solver.lookupState<LabelLattice>(value))
      out = lattice->getValue();
    if (auto closure = value.getDefiningOp<idr::ClosureOp>())
      out = Labels::join(out, Labels::of(closure.getCalleeAttr().getAttr()));
    if (auto suspend = value.getDefiningOp<idr::SuspendOp>())
      out = Labels::join(out, Labels::of(suspend.getCalleeAttr().getAttr()));
    if (auto constant = value.getDefiningOp<idr::ConstantOp>())
      if (auto closure = dyn_cast<idr::ClosureAttr>(constant.getValue()))
        out = Labels::join(out, Labels::of(closure.getCallee().getAttr()));
    return out;
  }

  Key field(SymbolRefAttr ctor, unsigned index) {
    return fields.lookup({ctor.getRootReference(), ctor.getLeafReference(), index});
  }

  Key elements(MemRefType array) { return arrays.lookup(array.getElementType()); }

  Key argument(func::FuncOp fn, unsigned index) {
    if (!fn || index >= fn.getNumArguments())
      return {};
    Type type = fn.getArgumentTypes()[index];
    if (fn.isExternal())
      return isKeyed(type) ? unknown(type) : Key();
    return values.lookup(fn.getArgument(index));
  }

  Key argument(StringAttr label, unsigned index) {
    return argument(module.function(label), index);
  }

  Key result(func::FuncOp fn, unsigned index) {
    auto it = results.find(fn.getOperation());
    return it == results.end() ? Key() : it->second[index];
  }

  // Whether `label` is a function whose signature ends in `type`'s: the
  // closure type's arguments and results, or for a suspension of a value,
  // that value alone.
  bool fits(StringAttr label, Type type) {
    func::FuncOp fn = module.function(label);
    if (!fn || fn.isExternal())
      return false;
    if (auto lazy = dyn_cast<idr::LazyType>(type))
      return fn.getNumResults() == 1 &&
             idr::unrestricted(fn.getResultTypes()[0]) == idr::unrestricted(lazy.getValue());
    auto closure = cast<idr::FnType>(type);
    return fn.getNumArguments() >= arity(type) &&
           llvm::equal(fn.getArgumentTypes().take_back(arity(type)), closure.getInputs()) &&
           llvm::equal(fn.getResultTypes(), closure.getResults());
  }

  // The number of captures of `label` as a closure or suspension of `type`.
  size_t captures(StringAttr label, Type type) {
    return module.function(label).getNumArguments() - arity(type);
  }

  // The slot of what a cell of lazy key `key` holds once forced: what its
  // labels return, which is one slot when the key converts. Without a
  // label, no value reaches it.
  Key forced(const Key &key) {
    Type value = cast<idr::LazyType>(key.first).getValue();
    if (key.second && !key.second.empty())
      if (func::FuncOp fn = module.function(cast<StringAttr>(key.second[0]));
          fn && fn.getNumResults() == 1)
        return result(fn, 0);
    return isKeyed(value) ? keyOf(value, Labels{}) : Key();
  }

  void keyFields() {
    module.op.walk([&](idr::CtorOp ctor) {
      auto data = ctor->getParentOfType<idr::DataOp>().getSymNameAttr();
      for (auto [i, type] : llvm::enumerate(ctor.getFieldTypes().getAsValueRange<TypeAttr>())) {
        if (!isKeyed(type))
          continue;
        auto index = std::make_tuple(data, ctor.getSymNameAttr(), unsigned(i));
        const auto *state =
            solver.lookupState<FieldLabels>(solver.getLatticeAnchor<FieldAnchor>(index));
        fields[index] = keyOf(type, state ? state->value : Labels{});
      }
    });
  }

  // Every element type of an array the module names anywhere, in a value, a
  // signature or a field, nested in another array too.
  void keyArrays() {
    auto scan = [&](Type type) {
      type.walk([&](MemRefType array) {
        Type element = array.getElementType();
        if (!idr::isArray(array) || !isKeyed(element) || arrays.count(element))
          return;
        const auto *state =
            solver.lookupState<FieldLabels>(solver.getLatticeAnchor<ElementsAnchor>(element));
        arrays[element] = keyOf(element, state ? state->value : Labels{});
      });
    };
    module.op->walk([&](Operation *op) {
      if (auto fn = dyn_cast<func::FuncOp>(op))
        scan(fn.getFunctionType());
      if (auto ctor = dyn_cast<idr::CtorOp>(op))
        for (Type type : ctor.getFieldTypes().getAsValueRange<TypeAttr>())
          scan(type);
      for (Type type : op->getResultTypes())
        scan(type);
      for (Region &region : op->getRegions())
        for (Block &block : region)
          for (Type type : block.getArgumentTypes())
            scan(type);
    });
  }

  void keyFunctions() {
    for (func::FuncOp fn : module.op.getOps<func::FuncOp>()) {
      SmallVector<Labels> joined(fn.getNumResults());
      if (fn.isExternal())
        llvm::for_each(joined, [](Labels &labels) { labels.unknown = true; });
      else
        for (BlockArgument arg : fn.getArguments())
          if (isKeyed(arg.getType()))
            values[arg] = keyOf(arg.getType(), labelsOf(arg));
      fn.walk([&](func::ReturnOp ret) {
        for (auto [operand, labels] : llvm::zip(ret.getOperands(), joined))
          labels = Labels::join(labels, labelsOf(operand));
      });
      SmallVector<Key> &out = results[fn.getOperation()];
      for (auto [type, labels] : llvm::zip(fn.getResultTypes(), joined))
        out.push_back(isKeyed(type) ? keyOf(type, labels) : Key());
    }
  }

  // The keys of values, from what the analysis found for each.
  void keyValues() {
    module.op.walk([&](Operation *op) {
      auto match = dyn_cast<idr::MatchOp>(op);
      auto fold = dyn_cast<idr::ArrayFoldOp>(op);
      for (Region &region : op->getRegions())
        for (Block &block : region)
          for (BlockArgument arg : block.getArguments()) {
            if (!isKeyed(arg.getType()) || (isa<func::FuncOp>(op) && block.isEntryBlock()))
              continue;
            // The arguments of a case are the fields of its constructor, and
            // a fold's element is one of its array's.
            if (match) {
              auto ctor = cast<FlatSymbolRefAttr>(match.getCases()[region.getRegionNumber()]);
              values[arg] = field(
                  SymbolRefAttr::get(dataName(match.getScrutinee().getType()), {ctor}),
                  arg.getArgNumber());
            } else if (fold && arg.getArgNumber() == 1) {
              values[arg] = elements(fold.getArrayType());
            } else {
              values[arg] = keyOf(arg.getType(), labelsOf(arg));
            }
          }
      for (OpResult result : op->getResults()) {
        if (!isKeyed(result.getType()))
          continue;
        if (auto read = dyn_cast<idr::FieldOp>(op))
          values[result] = field(
              SymbolRefAttr::get(dataName(read.getValue().getType()), {read.getCtorAttr()}),
              static_cast<unsigned>(read.getIndex()));
        else if (auto get = dyn_cast<idr::ArrayGetOp>(op))
          values[result] = elements(get.getArrayType());
        else
          values[result] = keyOf(result.getType(), labelsOf(result));
      }
    });
  }

  // A force's value is in the one slot its cell's labels return into, where
  // the cell's labels are known: what the force gives is what the cell's
  // `forced` state holds.
  void keyForces() {
    module.op.walk([&](idr::ForceOp force) {
      Key cell = values.lookup(force.getSuspension());
      if (isKeyed(force.getType()) && isLazy(cell) && cell.second)
        values[force.getResult()] = forced(cell);
    });
  }

  void note(const Key &key, Operation *at) {
    if (!key.first || !keys.insert({key, Type()}).second)
      return;
    firstSeen.try_emplace(key, at);
    // No label returns into the value of a cell no label reaches, so no
    // function notes its key.
    if (isLazy(key) && isEmpty(key))
      note(forced(key), at);
  }

  // The keys of the elements of every array in `type`.
  void noteArrays(Type type, Operation *at) {
    type.walk([&](MemRefType array) { note(elements(array), at); });
  }

  // Every slot's key in the order the module shows it.
  void order() {
    module.op->walk<WalkOrder::PreOrder>([&](Operation *op) {
      if (auto ctor = dyn_cast<idr::CtorOp>(op)) {
        auto data = ctor->getParentOfType<idr::DataOp>().getSymNameAttr();
        for (auto [i, type] : llvm::enumerate(ctor.getFieldTypes().getAsValueRange<TypeAttr>())) {
          note(fields.lookup({data, ctor.getSymNameAttr(), unsigned(i)}), op);
          noteArrays(type, op);
        }
        return;
      }
      if (auto fn = dyn_cast<func::FuncOp>(op)) {
        for (unsigned i = 0; i < fn.getNumArguments(); ++i)
          note(argument(fn, i), op);
        for (const Key &key : results.lookup(fn.getOperation()))
          note(key, op);
        noteArrays(fn.getFunctionType(), op);
        return;
      }
      for (Value result : op->getResults()) {
        note(values.lookup(result), op);
        noteArrays(result.getType(), op);
      }
      for (Region &region : op->getRegions())
        for (Block &block : region)
          for (Value arg : block.getArguments()) {
            note(values.lookup(arg), op);
            noteArrays(arg.getType(), op);
          }
    });
  }
};

} // namespace idr::defunctionalize
