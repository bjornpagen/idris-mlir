// idr-defunctionalize: closures of known labels become sums.
//
// The analysis is a sparse forward dataflow analysis on MLIR's framework,
// interprocedural, whose lattice is the set of labels (functions) a
// `!idr.fn` value may hold, or unknown. Values reach fields through one
// lattice anchor per (data type, constructor, field), written by `idr.con`
// and constants and read by `idr.field` and the regions of `idr.match`.
// The framework follows only calls of symbols, so the pass joins the rest
// itself: the entry arguments of a function get the captures of its closures
// (`idr.closure` ops and `#idr.closure` constants) and the arguments of every
// `idr.apply` that may call it, and an `idr.apply` gets the results of every
// label it may call.
//
// Sums are keyed by (closure type, label set), not by type alone. Every
// slot that holds a closure (a value, a function argument or result, a
// field of a constructor) has the key of its type and the labels the
// analysis found for it; a closure or constant used only where one larger
// set is expected takes that set. A key is converted when its labels are
// known, not empty and fit the type, and it is on no cycle of "a capture
// of one of its labels holds, directly or through unboxed data, a value of
// key K". Only such a cycle makes the sum infinite: a closure of type T
// may capture another closure of type T when the captured one holds other
// labels (a state monad's bind captures a bind of different lambdas).
// A converted key's values belong to a new unboxed sum `@fn$<n>`, numbered
// by first appearance in the module, with one constructor per
// label whose fields are the label's captures, each with the key of that
// capture (the label's entry argument): `idr.closure @f(...)` becomes
// `idr.con @fn$n::@f(...)`, a closure constant the matching constructor
// constant, and `idr.apply` an `idr.match` over the labels the callee may
// hold, each region calling its label.
//
// Where a value flows from a slot into one of another key (call operand to
// argument, return to result, yield to match result, field, capture, and
// through a rewritten apply to and from its labels), a coercion is
// inserted: an `idr.match` that rebuilds each label in the other sum, or as
// an `idr.closure` when the other key stays a closure. A value the analysis
// never reaches (the empty set) becomes `ub.poison`. A key stays a closure
// when a value can reach it only as a closure, and then every label that
// can reach it keeps the closure type's signature: its argument and result
// slots of closure type stay closures too. idr-check-profile rejects the
// closures that remain.

#include "Passes/Scc.h"
#include "idr/Idr.h"

#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Analysis/DataFlow/SparseAnalysis.h"
#include "mlir/Analysis/DataFlow/Utils.h"
#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/SymbolTable.h"

#include "llvm/ADT/MapVector.h"

using namespace mlir;
using namespace mlir::dataflow;
namespace passes = idr::passes;

namespace idr {
#define GEN_PASS_DEF_IDRDEFUNCTIONALIZE
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

//===----------------------------------------------------------------------===//
// The lattice
//===----------------------------------------------------------------------===//

bool byName(StringAttr a, StringAttr b) { return a.getValue() < b.getValue(); }

// The labels a value may hold, sorted by name; `unknown` is the top.
struct Labels {
  bool unknown = false;
  SmallVector<StringAttr> names;

  static Labels of(StringAttr name) {
    Labels out;
    out.names.push_back(name);
    return out;
  }

  static Labels top() {
    Labels out;
    out.unknown = true;
    return out;
  }

  static Labels join(const Labels &a, const Labels &b) {
    if (a.unknown || b.unknown)
      return top();
    Labels out;
    std::set_union(a.names.begin(), a.names.end(), b.names.begin(), b.names.end(),
                   std::back_inserter(out.names), byName);
    return out;
  }

  bool mayHold(StringAttr name) const { return unknown || llvm::is_contained(names, name); }

  bool operator==(const Labels &other) const {
    return unknown == other.unknown && names == other.names;
  }

  void print(raw_ostream &os) const {
    if (unknown) {
      os << "unknown";
      return;
    }
    os << "{";
    llvm::interleaveComma(names, os, [&](StringAttr name) { os << "@" << name.getValue(); });
    os << "}";
  }
};

struct LabelLattice : Lattice<Labels> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(LabelLattice)
  using Lattice::Lattice;
};

// A field of a constructor: (data type, constructor, index).
struct FieldAnchor
    : GenericLatticeAnchorBase<FieldAnchor, std::tuple<StringAttr, StringAttr, unsigned>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(FieldAnchor)
  using Base::Base;
  Location getLoc() const override { return UnknownLoc::get(std::get<0>(getValue()).getContext()); }
  void print(raw_ostream &os) const override {
    auto [data, ctor, index] = getValue();
    os << "@" << data.getValue() << "::@" << ctor.getValue() << "[" << index << "]";
  }
};

struct FieldLabels : AnalysisState {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(FieldLabels)
  using AnalysisState::AnalysisState;

  ChangeResult join(const Labels &other) {
    Labels joined = Labels::join(value, other);
    if (joined == value)
      return ChangeResult::NoChange;
    value = joined;
    return ChangeResult::Change;
  }

  void print(raw_ostream &os) const override { value.print(os); }

  Labels value;
};

//===----------------------------------------------------------------------===//
// The module's closures, gathered once
//===----------------------------------------------------------------------===//

StringAttr dataName(Type type) {
  if (auto data = dyn_cast<idr::DataType>(type))
    return data.getName().getAttr();
  if (auto box = dyn_cast<idr::BoxType>(type))
    return box.getName().getAttr();
  return {};
}

struct Module {
  explicit Module(ModuleOp top) : op(top), symbols(top) {}

  ModuleOp op;
  SymbolTable symbols;
  // The closure ops and closure constants (their captures) of each label.
  llvm::DenseMap<StringAttr, SmallVector<idr::ClosureOp>> closures;
  llvm::DenseMap<StringAttr, SmallVector<ArrayAttr>> constantClosures;
  SmallVector<idr::ApplyOp> applies;
  // Functions referenced other than by a call, closure or constant.
  llvm::DenseSet<StringAttr> escaping;

  idr::CtorOp ctor(StringAttr data, StringAttr name) {
    auto decl = symbols.lookup<idr::DataOp>(data);
    return decl ? decl.lookupSymbol<idr::CtorOp>(name) : idr::CtorOp();
  }

  func::FuncOp function(StringAttr name) { return symbols.lookup<func::FuncOp>(name); }

  // The type of field `index` of `ctor`, whose ref is `@T::@C`.
  Type fieldType(SymbolRefAttr ref, unsigned index) {
    idr::CtorOp decl = ctor(ref.getRootReference(), ref.getLeafReference());
    return decl ? decl.getFieldType(index) : Type();
  }

  // Calls `visit(closure, type)` for each closure attribute inside `attr`, a
  // constant of type `type`.
  void closuresIn(Attribute attr, Type type,
                  function_ref<void(idr::ClosureAttr, Type)> visit) {
    if (auto closure = dyn_cast<idr::ClosureAttr>(attr)) {
      visit(closure, type);
      func::FuncOp fn = function(closure.getCallee().getAttr());
      for (auto [i, capture] : llvm::enumerate(closure.getCaptures()))
        if (fn && i < fn.getNumArguments())
          closuresIn(capture, fn.getArgumentTypes()[i], visit);
      return;
    }
    if (auto con = dyn_cast<idr::ConAttr>(attr))
      for (auto [i, field] : llvm::enumerate(con.getFields()))
        if (Type declared = fieldType(con.getCtor(), static_cast<unsigned>(i)))
          closuresIn(field, declared, visit);
  }

  void gather() {
    op.walk([&](Operation *inner) {
      if (auto closure = dyn_cast<idr::ClosureOp>(inner))
        closures[closure.getCalleeAttr().getAttr()].push_back(closure);
      else if (auto apply = dyn_cast<idr::ApplyOp>(inner))
        applies.push_back(apply);
      else if (auto constant = dyn_cast<idr::ConstantOp>(inner))
        closuresIn(constant.getValue(), constant.getType(), [&](idr::ClosureAttr c, Type) {
          constantClosures[c.getCallee().getAttr()].push_back(c.getCaptures());
        });
    });
    if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(op.getOperation()))
      for (const SymbolTable::SymbolUse &use : *uses)
        if (!isa<func::CallOp, idr::ClosureOp, idr::ConstantOp, idr::ConOp, idr::FieldOp,
                 idr::MatchOp>(use.getUser()))
          escaping.insert(use.getSymbolRef().getRootReference());
  }
};

//===----------------------------------------------------------------------===//
// The analysis
//===----------------------------------------------------------------------===//

class LabelAnalysis : public SparseForwardDataFlowAnalysis<LabelLattice> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(LabelAnalysis)

  LabelAnalysis(DataFlowSolver &dataflow, Module &closures)
      : SparseForwardDataFlowAnalysis(dataflow), module(closures) {
    registerAnchorKind<FieldAnchor>();
  }

  // Closures stored in constants reach their fields before anything runs.
  LogicalResult initialize(Operation *top) override {
    top->walk([&](idr::ConstantOp constant) {
      constant.getValue().walk([&](idr::ConAttr con) {
        for (auto [i, field] : llvm::enumerate(con.getFields()))
          if (auto closure = dyn_cast<idr::ClosureAttr>(field))
            joinField(con.getCtor(), static_cast<unsigned>(i),
                      Labels::of(closure.getCallee().getAttr()));
      });
    });
    return SparseForwardDataFlowAnalysis::initialize(top);
  }

  LogicalResult visitOperation(Operation *op, ArrayRef<const LabelLattice *> operands,
                               ArrayRef<LabelLattice *> results) override {
    if (auto closure = dyn_cast<idr::ClosureOp>(op))
      return set(results[0], Labels::of(closure.getCalleeAttr().getAttr()));
    if (auto constant = dyn_cast<idr::ConstantOp>(op)) {
      if (auto closure = dyn_cast<idr::ClosureAttr>(constant.getValue()))
        return set(results[0], Labels::of(closure.getCallee().getAttr()));
      return success();
    }
    if (auto con = dyn_cast<idr::ConOp>(op)) {
      for (auto [i, field] : llvm::enumerate(operands))
        if (isa<idr::FnType>(con.getFields()[i].getType()))
          joinField(con.getCtor(), static_cast<unsigned>(i), field->getValue());
      return success();
    }
    if (auto field = dyn_cast<idr::FieldOp>(op)) {
      if (!isa<idr::FnType>(field.getType()))
        return success();
      auto ref = SymbolRefAttr::get(dataName(field.getValue().getType()),
                                    {field.getCtorAttr()});
      return set(results[0], readField(getProgramPointAfter(op), ref,
                                       static_cast<unsigned>(field.getIndex())));
    }
    for (auto [result, lattice] : llvm::zip(op->getResults(), results))
      if (isa<idr::FnType>(result.getType()))
        setToEntryState(lattice);
    return success();
  }

  // An idr.apply calls every label its callee may hold.
  LogicalResult visitCallOperation(CallOpInterface call,
                                   ArrayRef<const AbstractSparseLattice *> operands,
                                   ArrayRef<AbstractSparseLattice *> results) override {
    auto apply = dyn_cast<idr::ApplyOp>(call.getOperation());
    if (!apply)
      return SparseForwardDataFlowAnalysis::visitCallOperation(call, operands, results);
    const Labels &callee = static_cast<const LabelLattice *>(operands[0])->getValue();
    if (callee.unknown) {
      AbstractSparseForwardDataFlowAnalysis::setAllToEntryStates(results);
      return success();
    }
    ProgramPoint *point = getProgramPointAfter(apply);
    for (StringAttr label : callee.names) {
      func::FuncOp fn = module.function(label);
      if (!fn || fn.isExternal()) {
        AbstractSparseForwardDataFlowAnalysis::setAllToEntryStates(results);
        return success();
      }
      fn.walk([&](func::ReturnOp ret) {
        for (auto [operand, result] : llvm::zip(ret.getOperands(), results))
          join(result, *getLatticeElementFor(point, operand));
      });
    }
    return success();
  }

  // The entry arguments of a function: from its calls, its closures, and the
  // idr.apply ops that may call it.
  void visitCallableOperation(CallableOpInterface callable,
                              ArrayRef<AbstractSparseLattice *> arguments) override {
    auto fn = dyn_cast<func::FuncOp>(callable.getOperation());
    if (!fn || fn.isPublic() || module.escaping.contains(fn.getSymNameAttr()))
      return AbstractSparseForwardDataFlowAnalysis::setAllToEntryStates(arguments);
    Block *entry = &fn.getBody().front();
    ProgramPoint *point = getProgramPointBefore(entry);
    const auto *calls = getOrCreateFor<PredecessorState>(point, getProgramPointAfter(fn));
    for (Operation *site : calls->getKnownPredecessors())
      if (auto call = dyn_cast<func::CallOp>(site))
        for (auto [operand, argument] : llvm::zip(call.getArgOperands(), arguments))
          join(argument, *getLatticeElementFor(point, operand));

    StringAttr name = fn.getSymNameAttr();
    for (idr::ClosureOp closure : module.closures.lookup(name))
      for (auto [capture, argument] : llvm::zip(closure.getCaptures(), arguments))
        join(argument, *getLatticeElementFor(point, capture));
    for (ArrayAttr captures : module.constantClosures.lookup(name))
      for (auto [capture, argument] : llvm::zip(captures, arguments))
        if (auto closure = dyn_cast<idr::ClosureAttr>(capture))
          propagateIfChanged(argument, static_cast<LabelLattice *>(argument)->join(
                                           Labels::of(closure.getCallee().getAttr())));

    bool isLabel = module.closures.count(name) || module.constantClosures.count(name);
    for (idr::ApplyOp apply : module.applies) {
      auto type = cast<idr::FnType>(apply.getCallee().getType());
      size_t n = fn.getNumArguments(), k = type.getInputs().size();
      if (!isLabel || k > n || !llvm::equal(fn.getArgumentTypes().drop_front(n - k), type.getInputs()) ||
          !llvm::equal(fn.getResultTypes(), type.getResults()))
        continue;
      if (!getLatticeElementFor(point, apply.getCallee())->getValue().mayHold(name))
        continue;
      for (auto [operand, argument] : llvm::zip(apply.getArgs(), arguments.drop_front(n - k)))
        join(argument, *getLatticeElementFor(point, operand));
    }
  }

  // The arguments of a case region of idr.match are the fields of its
  // constructor.
  void visitNonControlFlowArguments(Operation *op, const RegionSuccessor &successor,
                                    ValueRange inputs,
                                    ArrayRef<LabelLattice *> lattices) override {
    auto match = dyn_cast<idr::MatchOp>(op);
    Region *region = successor.getSuccessor();
    if (!match || !region || region->getRegionNumber() >= match.getCases().size())
      return setAllToEntryStates(lattices);
    auto ctor = cast<FlatSymbolRefAttr>(match.getCases()[region->getRegionNumber()]);
    auto ref = SymbolRefAttr::get(dataName(match.getScrutinee().getType()), {ctor});
    ProgramPoint *point = getProgramPointBefore(&region->front());
    for (auto [input, lattice] : llvm::zip(inputs, lattices))
      if (isa<idr::FnType>(input.getType()))
        propagateIfChanged(lattice, lattice->join(readField(
                                        point, ref, cast<BlockArgument>(input).getArgNumber())));
  }

  void setToEntryState(LabelLattice *lattice) override {
    propagateIfChanged(lattice, lattice->join(Labels::top()));
  }

private:
  LogicalResult set(LabelLattice *lattice, const Labels &labels) {
    propagateIfChanged(lattice, lattice->join(labels));
    return success();
  }

  FieldAnchor *anchor(SymbolRefAttr ctor, unsigned index) {
    return getLatticeAnchor<FieldAnchor>(
        std::make_tuple(ctor.getRootReference(), ctor.getLeafReference(), index));
  }

  void joinField(SymbolRefAttr ctor, unsigned index, const Labels &labels) {
    auto *state = getOrCreate<FieldLabels>(anchor(ctor, index));
    propagateIfChanged(state, state->join(labels));
  }

  const Labels &readField(ProgramPoint *point, SymbolRefAttr ctor, unsigned index) {
    return getOrCreateFor<FieldLabels>(point, anchor(ctor, index))->value;
  }

  Module &module;
};

//===----------------------------------------------------------------------===//
// The conversion
//===----------------------------------------------------------------------===//

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

struct Converter {
  Converter(Module &closures, DataFlowSolver &dataflow)
      : module(closures), solver(dataflow), ctx(closures.op.getContext()) {}

  Module &module;
  DataFlowSolver &solver;
  MLIRContext *ctx;

  // The keys of closure values (entry arguments included), of function
  // results and of fields.
  llvm::DenseMap<Value, Key> values;
  llvm::DenseMap<Operation *, SmallVector<Key>> results;
  llvm::DenseMap<std::tuple<StringAttr, StringAttr, unsigned>, Key> fields;
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

  //===--------------------------------------------------------------------===//
  // Keys
  //===--------------------------------------------------------------------===//

  Key keyOf(Type type, const Labels &labels) {
    auto fnType = cast<idr::FnType>(type);
    if (labels.unknown)
      return {fnType, ArrayAttr()};
    return {fnType, ArrayAttr::get(ctx, SmallVector<Attribute>(labels.names.begin(),
                                                               labels.names.end()))};
  }

  Key unknown(Type type) { return {cast<idr::FnType>(type), ArrayAttr()}; }

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
      return isa<idr::FnType>(type) ? unknown(type) : Key();
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
    return {};
  }

  // Ops whose closure operands, results and region arguments the pass
  // follows. Those of any other op stay closures.
  static bool isFollowed(Operation *op) {
    return isa<func::FuncOp, func::CallOp, func::ReturnOp, idr::YieldOp, idr::ConOp,
               idr::ClosureOp, idr::ApplyOp, idr::FieldOp, idr::MatchOp, idr::MatchLitOp,
               idr::ConstantOp>(op);
  }

  void keyFields() {
    module.op.walk([&](idr::CtorOp ctor) {
      auto data = ctor->getParentOfType<idr::DataOp>().getSymNameAttr();
      for (auto [i, type] : llvm::enumerate(ctor.getFieldTypes().getAsValueRange<TypeAttr>())) {
        if (!isa<idr::FnType>(type))
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
          if (isa<idr::FnType>(arg.getType()))
            values[arg] = keyOf(arg.getType(), labelsOf(arg));
      fn.walk([&](func::ReturnOp ret) {
        for (auto [operand, labels] : llvm::zip(ret.getOperands(), joined))
          labels = Labels::join(labels, labelsOf(operand));
      });
      SmallVector<Key> &out = results[fn.getOperation()];
      for (auto [type, labels] : llvm::zip(fn.getResultTypes(), joined))
        out.push_back(isa<idr::FnType>(type) ? keyOf(type, labels) : Key());
    }
  }

  void keyValues() {
    module.op.walk([&](Operation *op) {
      auto match = dyn_cast<idr::MatchOp>(op);
      for (Region &region : op->getRegions())
        for (Block &block : region)
          for (BlockArgument arg : block.getArguments()) {
            if (!isa<idr::FnType>(arg.getType()) ||
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
        if (!isa<idr::FnType>(result.getType()))
          continue;
        if (auto read = dyn_cast<idr::FieldOp>(op))
          values[result] = field(
              SymbolRefAttr::get(dataName(read.getValue().getType()), {read.getCtorAttr()}),
              static_cast<unsigned>(read.getIndex()));
        else
          values[result] = keyOf(result.getType(), labelsOf(result));
      }
    });
    // A closure or constant whose every use moves it into slots of one key
    // with more labels takes that key, so that it needs no coercion.
    module.op.walk([&](Operation *op) {
      if (!isa<idr::ClosureOp, idr::ConstantOp>(op) || !isa<idr::FnType>(op->getResultTypes()[0]))
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
    if (auto closure = dyn_cast<idr::ClosureAttr>(attr)) {
      StringAttr label = closure.getCallee().getAttr();
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
          if (isa<idr::FnType>(value.getType()))
            flows.push_back({fn ? result(fn, value.getResultNumber()) : unknown(value.getType()),
                             values.lookup(value)});
      }
      if (auto apply = dyn_cast<idr::ApplyOp>(op)) {
        connect(apply);
        return;
      }
      for (OpOperand &use : op->getOpOperands()) {
        if (!isa<idr::FnType>(use.get().getType()))
          continue;
        Key to = isFollowed(op) ? sinkOf(use) : Key();
        if (!to.first)
          to = unknown(use.get().getType());
        sinks.push_back({op, use.getOperandNumber(), to});
        flows.push_back({values.lookup(use.get()), to});
      }
      if (!isFollowed(op))
        for (OpResult value : op->getResults())
          if (isa<idr::FnType>(value.getType()))
            flows.push_back({unknown(value.getType()), values.lookup(value)});
      // Arguments of blocks the pass does not follow the branches to.
      if (!isFollowed(op) || isa<func::FuncOp>(op))
        for (Region &region : op->getRegions())
          for (Block &block : region)
            for (BlockArgument arg : block.getArguments())
              if (isa<idr::FnType>(arg.getType()) &&
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
        if (isa<idr::FnType>(arg.getType()))
          flows.push_back({values.lookup(arg), argument(fn, static_cast<unsigned>(first + i))});
      for (OpResult value : apply.getResults())
        if (isa<idr::FnType>(value.getType()))
          flows.push_back({result(fn, value.getResultNumber()), values.lookup(value)});
    }
  }

  //===--------------------------------------------------------------------===//
  // Deciding
  //===--------------------------------------------------------------------===//

  bool isConverted(const Key &key) { return converted.contains(key); }

  // Whether a value of `from` can be rebuilt as one of `to`.
  bool canCoerce(const Key &from, const Key &to) {
    return from == to || !isConverted(to) || isEmpty(from) ||
           (isConverted(from) && within(from, to));
  }

  // The keys a value of `type`, in a slot of `key`, holds without a box in
  // between.
  void holds(Type type, const Key &key, SmallVectorImpl<Key> &out,
             llvm::DenseSet<StringAttr> &seen) {
    if (isa<idr::FnType>(type)) {
      out.push_back(key);
      return;
    }
    auto data = dyn_cast<idr::DataType>(type);
    if (!data || !seen.insert(data.getName().getAttr()).second)
      return;
    auto decl = module.symbols.lookup<idr::DataOp>(data.getName().getAttr());
    if (!decl)
      return;
    for (idr::CtorOp ctor : decl.getCtors())
      for (auto [i, field] : llvm::enumerate(ctor.getFieldTypes().getAsValueRange<TypeAttr>()))
        holds(field, fields.lookup({data.getName().getAttr(), ctor.getSymNameAttr(), unsigned(i)}),
              out, seen);
  }

  // A key is converted if its labels are known, not empty and fit its
  // type, and it is on no cycle of "a capture holds". Then, to a fixpoint,
  // a key stays a closure where a value can only come to it as a closure,
  // and the labels of a closure keep its type's signature.
  void decide() {
    llvm::DenseMap<Key, SmallVector<Key>> edges;
    SmallVector<Key> candidates;
    for (auto &[key, sum] : keys) {
      if (!key.second || key.second.empty() ||
          !llvm::all_of(key.second.getAsRange<StringAttr>(),
                        [&](StringAttr label) { return fits(label, key.first); }))
        continue;
      candidates.push_back(key);
      for (StringAttr label : key.second.getAsRange<StringAttr>()) {
        func::FuncOp fn = module.function(label);
        for (unsigned i = 0; i < captures(label, key.first); ++i) {
          llvm::DenseSet<StringAttr> seen;
          holds(fn.getArgumentTypes()[i], argument(fn, i), edges[key], seen);
        }
      }
    }
    for (const SmallVector<Key> &component : passes::stronglyConnected<Key>(
             candidates, [&](Key key) { return edges.lookup(key); }))
      if (component.size() > 1 || llvm::is_contained(edges.lookup(component.front()),
                                                      component.front()))
        cyclic.insert(component.begin(), component.end());
    converted.insert(candidates.begin(), candidates.end());

    bool changed = true;
    auto keep = [&](const Key &key) {
      if (key.first && converted.erase(key))
        changed = true;
    };
    // A closure of `label` of `type` calls it with the type's arguments.
    auto seal = [&](StringAttr label, idr::FnType type) {
      func::FuncOp fn = module.function(label);
      if (!type || !fn || fn.isExternal() || fn.getNumArguments() < arity(type))
        return;
      for (size_t i = fn.getNumArguments() - arity(type); i < fn.getNumArguments(); ++i)
        keep(argument(fn, static_cast<unsigned>(i)));
      llvm::for_each(results.lookup(fn.getOperation()), keep);
    };
    auto sealAll = [&](const Key &key) {
      if (key.second)
        for (StringAttr label : key.second.getAsRange<StringAttr>())
          seal(label, key.first);
    };
    // Functions that others may call keep their signatures.
    for (func::FuncOp fn : module.op.getOps<func::FuncOp>())
      if (!fn.isExternal() && (fn.isPublic() || module.escaping.contains(fn.getSymNameAttr()))) {
        for (unsigned i = 0; i < fn.getNumArguments(); ++i)
          keep(argument(fn, i));
        llvm::for_each(results.lookup(fn.getOperation()), keep);
      }
    while (changed) {
      changed = false;
      for (const Flow &flow : flows) {
        if (isConverted(flow.to) && !canCoerce(flow.from, flow.to))
          keep(flow.to);
        if (!isConverted(flow.to) && isConverted(flow.from))
          sealAll(flow.from);
      }
      for (auto &[label, slot] : sources) {
        if (isConverted(slot) && !llvm::is_contained(slot.second, label))
          keep(slot);
        if (!isConverted(slot))
          seal(label, slot.first);
      }
      for (auto &[key, sum] : keys)
        if (!isConverted(key))
          sealAll(key);
      // An apply of a closure passes closures and returns closures.
      for (idr::ApplyOp apply : module.applies) {
        if (isConverted(values.lookup(apply.getCallee())))
          continue;
        for (Value arg : apply.getArgs())
          if (isa<idr::FnType>(arg.getType()) && isConverted(values.lookup(arg)))
            sealAll(values.lookup(arg));
        for (Value value : apply.getResults())
          if (isa<idr::FnType>(value.getType()))
            keep(values.lookup(value));
      }
    }

    unsigned n = 0;
    for (auto &[key, sum] : keys)
      if (isConverted(key)) {
        auto name = FlatSymbolRefAttr::get(ctx, ("fn$" + Twine(n++)).str());
        sum = cyclic.contains(key) ? Type(idr::BoxType::get(ctx, name))
                                   : Type(idr::DataType::get(ctx, name));
      }
  }

  //===--------------------------------------------------------------------===//
  // Rewriting
  //===--------------------------------------------------------------------===//

  Type sumOf(const Key &key) {
    return isConverted(key) ? keys.lookup(key) : Type();
  }

  // The type of a slot of `key`: its sum, or the closure type unchanged.
  Type typeOf(const Key &key) {
    if (Type sum = sumOf(key))
      return sum;
    return key.first;
  }

  Type typeOf(Type type, const Key &key) { return key.first ? typeOf(key) : type; }

  // The types of the captures of `label` as a closure of `type`, as
  // converted.
  ArrayRef<Type> captureTypes(StringAttr label, idr::FnType type) {
    return module.function(label).getArgumentTypes().drop_back(arity(type));
  }

  void retype() {
    for (func::FuncOp fn : module.op.getOps<func::FuncOp>()) {
      SmallVector<Type> inputs, outputs;
      for (auto [i, type] : llvm::enumerate(fn.getArgumentTypes()))
        inputs.push_back(typeOf(type, argument(fn, static_cast<unsigned>(i))));
      for (auto [i, type] : llvm::enumerate(fn.getResultTypes()))
        outputs.push_back(typeOf(type, result(fn, static_cast<unsigned>(i))));
      fn.setFunctionType(FunctionType::get(ctx, inputs, outputs));
    }
    for (auto &[value, key] : values)
      value.setType(typeOf(key));
    module.op.walk([&](idr::CtorOp ctor) {
      auto data = ctor->getParentOfType<idr::DataOp>().getSymNameAttr();
      SmallVector<Type> types;
      for (auto [i, type] : llvm::enumerate(ctor.getFieldTypes().getAsValueRange<TypeAttr>()))
        types.push_back(typeOf(type, fields.lookup({data, ctor.getSymNameAttr(), unsigned(i)})));
      ctor.setFieldTypesAttr(Builder(ctx).getTypeArrayAttr(types));
    });
  }

  void declareSums(OpBuilder &b) {
    b.setInsertionPointToStart(module.op.getBody());
    for (auto &[key, sum] : keys) {
      if (!sum)
        continue;
      auto data = idr::DataOp::create(b, module.op.getLoc(), idr::getSumName(sum).getAttr(),
                                      isa<idr::BoxType>(sum) ? b.getUnitAttr() : UnitAttr());
      OpBuilder inner = OpBuilder::atBlockEnd(&data.getBody().emplaceBlock());
      for (auto [tag, label] : llvm::enumerate(key.second.getAsRange<StringAttr>())) {
        func::FuncOp fn = module.function(label);
        ArrayRef<Type> types = captureTypes(label, key.first);
        SmallVector<StringRef> quantities;
        for (unsigned i = 0; i < types.size(); ++i) {
          auto quantity = fn.getArgAttrOfType<StringAttr>(i, "idr.quantity");
          quantities.push_back(quantity ? quantity.getValue() : "w");
        }
        idr::CtorOp::create(inner, fn.getLoc(), label, b.getI64IntegerAttr(static_cast<int64_t>(tag)),
                            b.getTypeArrayAttr(types), b.getStrArrayAttr(quantities));
      }
    }
  }

  // `label` with `captures` as a value of `key`.
  Value build(OpBuilder &b, Location loc, StringAttr label, const Key &key, ValueRange captures) {
    auto callee = FlatSymbolRefAttr::get(label);
    if (Type sum = sumOf(key))
      return idr::ConOp::create(b, loc, sum,
                                SymbolRefAttr::get(idr::getSumName(sum).getAttr(), {callee}),
                                captures);
    return idr::ClosureOp::create(b, loc, key.first, callee, captures);
  }

  // Where the program builds a closure of `label`: a closure a coercion
  // rebuilds is reported there.
  Location closureLoc(StringAttr label, Location fallback) {
    auto it = module.closures.find(label);
    return it == module.closures.end() || it->second.empty() ? fallback
                                                              : it->second.front().getLoc();
  }

  bool needsCoercion(const Key &from, const Key &to) {
    return from != to && (isConverted(from) || isConverted(to));
  }

  // `value` of `from` as a value of `to`: a match that rebuilds each label,
  // or poison for a value the analysis never reaches.
  Value coerce(OpBuilder &b, Location loc, Value value, const Key &from, const Key &to) {
    if (!needsCoercion(from, to))
      return value;
    assert(canCoerce(from, to) && "idr-defunctionalize: a move it did not decide");
    if (isEmpty(from))
      return ub::PoisonOp::create(b, loc, typeOf(to));
    SmallVector<Attribute> cases;
    for (StringAttr label : from.second.getAsRange<StringAttr>())
      cases.push_back(FlatSymbolRefAttr::get(label));
    OpBuilder::InsertionGuard guard(b);
    auto match = idr::MatchOp::create(b, loc, TypeRange{typeOf(to)}, value, b.getArrayAttr(cases),
                                      unsigned(cases.size()));
    for (auto [label, region] :
         llvm::zip(from.second.getAsRange<StringAttr>(), match.getRegions())) {
      ArrayRef<Type> types = captureTypes(label, from.first);
      Block *block = b.createBlock(&region, region.end(), types,
                                   SmallVector<Location>(types.size(), loc));
      Location at = isConverted(to) ? loc : closureLoc(label, loc);
      idr::YieldOp::create(b, loc, build(b, at, label, to, block->getArguments()));
    }
    return match.getResult(0);
  }

  // A call returns its callee's result, then moves it into its own slot.
  void coerceCalls(OpBuilder &b) {
    SmallVector<func::CallOp> calls;
    module.op.walk([&](func::CallOp call) { calls.push_back(call); });
    for (func::CallOp call : calls) {
      func::FuncOp fn = module.function(call.getCalleeAttr().getAttr());
      for (OpResult value : call.getResults()) {
        auto it = values.find(value);
        if (it == values.end())
          continue;
        Key to = it->second;
        Key from = fn ? result(fn, value.getResultNumber()) : unknown(to.first);
        value.setType(typeOf(from));
        values[value] = from;
        b.setInsertionPointAfter(call);
        Value moved = coerce(b, call.getLoc(), value, from, to);
        if (moved == value)
          continue;
        value.replaceAllUsesExcept(moved, moved.getDefiningOp());
        values[moved] = to;
      }
    }
  }

  void coerceSinks(OpBuilder &b) {
    for (const Sink &sink : sinks) {
      Value value = sink.user->getOperand(sink.index);
      b.setInsertionPoint(sink.user);
      Value moved = coerce(b, sink.user->getLoc(), value, values.lookup(value), sink.to);
      sink.user->setOperand(sink.index, moved);
    }
  }

  // Constant `attr` in a slot of `slot`, with its closures of converted
  // keys as constructors.
  Attribute convert(Attribute attr, const Key &slot) {
    if (auto closure = dyn_cast<idr::ClosureAttr>(attr)) {
      StringAttr label = closure.getCallee().getAttr();
      SmallVector<Attribute> captures;
      for (auto [i, capture] : llvm::enumerate(closure.getCaptures()))
        captures.push_back(convert(capture, argument(label, static_cast<unsigned>(i))));
      auto array = ArrayAttr::get(ctx, captures);
      if (Type sum = sumOf(slot))
        return idr::ConAttr::get(
            ctx, SymbolRefAttr::get(idr::getSumName(sum).getAttr(), {closure.getCallee()}), array);
      return idr::ClosureAttr::get(ctx, closure.getCallee(), array);
    }
    if (auto con = dyn_cast<idr::ConAttr>(attr)) {
      SmallVector<Attribute> parts;
      for (auto [i, value] : llvm::enumerate(con.getFields()))
        parts.push_back(convert(value, field(con.getCtor(), static_cast<unsigned>(i))));
      return idr::ConAttr::get(ctx, con.getCtor(), ArrayAttr::get(ctx, parts));
    }
    return attr;
  }

  // An apply of a converted key becomes a match over its labels, each
  // region calling its label with the captures, then the arguments. An
  // apply of a closure gets closures.
  void rewrite(idr::ApplyOp apply, OpBuilder &b) {
    // The callee is retyped by now, so not getCallee(), which casts it.
    Value closure = apply->getOperand(0);
    Key callee = values.lookup(closure);
    ArrayRef<Type> inputs = callee.first.getInputs();
    b.setInsertionPoint(apply);
    if (!isConverted(callee)) {
      for (auto [i, type] : llvm::enumerate(inputs)) {
        if (!isa<idr::FnType>(type))
          continue;
        OpOperand &arg = apply.getArgsMutable()[static_cast<unsigned>(i)];
        arg.set(coerce(b, apply.getLoc(), arg.get(), values.lookup(arg.get()), unknown(type)));
      }
      return;
    }
    SmallVector<Attribute> cases;
    for (StringAttr label : callee.second.getAsRange<StringAttr>())
      cases.push_back(FlatSymbolRefAttr::get(label));
    auto match = idr::MatchOp::create(b, apply.getLoc(), apply.getResultTypes(), closure,
                                      b.getArrayAttr(cases), unsigned(cases.size()));
    for (auto [label, region] :
         llvm::zip(callee.second.getAsRange<StringAttr>(), match.getRegions())) {
      func::FuncOp fn = module.function(label);
      ArrayRef<Type> types = captureTypes(label, callee.first);
      Block *block = b.createBlock(&region, region.end(), types,
                                   SmallVector<Location>(types.size(), apply.getLoc()));
      SmallVector<Value> operands(block->getArguments());
      for (auto [i, arg] : llvm::enumerate(apply.getArgs()))
        operands.push_back(isa<idr::FnType>(inputs[i])
                               ? coerce(b, apply.getLoc(), arg, values.lookup(arg),
                                        argument(fn, static_cast<unsigned>(types.size() + i)))
                               : arg);
      auto call = func::CallOp::create(b, apply.getLoc(), fn, operands);
      SmallVector<Value> yields;
      for (auto [value, own] : llvm::zip(call.getResults(), apply.getResults()))
        yields.push_back(values.count(own)
                             ? coerce(b, apply.getLoc(), value,
                                      result(fn, cast<OpResult>(value).getResultNumber()),
                                      values.lookup(own))
                             : value);
      idr::YieldOp::create(b, apply.getLoc(), yields);
    }
    for (auto [own, value] : llvm::zip(apply.getResults(), match.getResults()))
      if (values.count(own))
        values[value] = values.lookup(own);
    apply.replaceAllUsesWith(match.getResults());
    apply.erase();
  }

  void run() {
    keyFields();
    keyFunctions();
    keyValues();
    order();
    connect();
    decide();

    OpBuilder b(ctx);
    retype();
    declareSums(b);
    coerceCalls(b);
    coerceSinks(b);
    module.op.walk([&](idr::ConstantOp constant) {
      constant.setValueAttr(convert(constant.getValue(), values.lookup(constant.getResult())));
    });
    for (idr::ApplyOp apply : module.applies)
      rewrite(apply, b);
    module.op.walk([&](idr::ClosureOp closure) {
      Key key = values.lookup(closure->getResult(0));
      if (!sumOf(key))
        return;
      b.setInsertionPoint(closure);
      Value con = build(b, closure.getLoc(), closure.getCalleeAttr().getAttr(), key,
                        closure.getCaptures());
      closure.replaceAllUsesWith(con);
      closure.erase();
    });
  }
};

struct Defunctionalize : idr::impl::IdrDefunctionalizeBase<Defunctionalize> {
  void runOnOperation() override {
    Module module(getOperation());
    module.gather();
    DataFlowSolver solver(DataFlowConfig().setInterprocedural(true));
    loadBaselineAnalyses(solver);
    solver.load<LabelAnalysis>(module);
    if (failed(solver.initializeAndRun(getOperation())))
      return signalPassFailure();
    Converter converter(module, solver);
    converter.run();
    numSums += converter.converted.size();
    numClosures += converter.keys.size() - converter.converted.size();
  }
};

} // namespace
