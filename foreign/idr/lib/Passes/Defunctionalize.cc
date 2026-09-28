// idr-defunctionalize: closures of known labels become sums (ELIM-CLOS-1,
// docs/cutover.md 6.3).
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
// A closure type is converted when every value of it has known labels and
// the captures of those labels do not contain the type again through
// unboxed data or other converted closure types (the sum would be infinite).
// Its values then belong to a new unboxed sum `@fn$<n>`, numbered by first
// appearance, with one constructor per label whose fields are the captures:
// `idr.closure @f(...)` becomes `idr.con @fn$n::@f(...)`, a closure constant
// the matching constructor constant, and `idr.apply` an `idr.match` over
// the labels the callee may hold, each region calling its label. Other
// closure types are left alone, and idr-check-profile rejects their closures.

#include "Passes/Scc.h"
#include "idr/Idr.h"

#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Analysis/DataFlow/SparseAnalysis.h"
#include "mlir/Analysis/DataFlow/Utils.h"
#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/IR/AttrTypeSubElements.h"
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
  explicit Module(ModuleOp op) : op(op), symbols(op) {}

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
        if (Type fieldType = this->fieldType(con.getCtor(), i))
          closuresIn(field, fieldType, visit);
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

  LabelAnalysis(DataFlowSolver &solver, Module &module)
      : SparseForwardDataFlowAnalysis(solver), module(module) {
    registerAnchorKind<FieldAnchor>();
  }

  // Closures stored in constants reach their fields before anything runs.
  LogicalResult initialize(Operation *top) override {
    top->walk([&](idr::ConstantOp constant) {
      constant.getValue().walk([&](idr::ConAttr con) {
        for (auto [i, field] : llvm::enumerate(con.getFields()))
          if (auto closure = dyn_cast<idr::ClosureAttr>(field))
            joinField(con.getCtor(), i, Labels::of(closure.getCallee().getAttr()));
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
          joinField(con.getCtor(), i, field->getValue());
      return success();
    }
    if (auto field = dyn_cast<idr::FieldOp>(op)) {
      if (!isa<idr::FnType>(field.getType()))
        return success();
      auto ref = SymbolRefAttr::get(dataName(field.getValue().getType()),
                                    {field.getCtorAttr()});
      return set(results[0], readField(getProgramPointAfter(op), ref, field.getIndex()));
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
      unsigned n = fn.getNumArguments(), k = type.getInputs().size();
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

// What the analysis found about one closure type.
struct Closures {
  bool unknown = false;
  SmallVector<StringAttr> labels;
  idr::DataType sum;

  void add(const Labels &more) {
    Labels all = Labels::join(Labels{unknown, labels}, more);
    unknown = all.unknown;
    labels = all.names;
  }
};

struct Converter {
  Converter(Module &module, DataFlowSolver &solver) : module(module), solver(solver) {}

  Module &module;
  DataFlowSolver &solver;
  llvm::MapVector<idr::FnType, Closures> types;

  Labels labelsOf(Value value) {
    if (const auto *lattice = solver.lookupState<LabelLattice>(value))
      return lattice->getValue();
    return {};
  }

  void collect() {
    auto note = [&](Value value) {
      if (auto type = dyn_cast<idr::FnType>(value.getType()))
        types[type].add(labelsOf(value));
    };
    module.op.walk([&](Operation *op) {
      for (Region &region : op->getRegions())
        for (Block &block : region)
          llvm::for_each(block.getArguments(), note);
      llvm::for_each(op->getResults(), note);
      if (auto closure = dyn_cast<idr::ClosureOp>(op))
        types[closure.getType()].add(Labels::of(closure.getCalleeAttr().getAttr()));
      if (auto constant = dyn_cast<idr::ConstantOp>(op))
        module.closuresIn(constant.getValue(), constant.getType(),
                          [&](idr::ClosureAttr closure, Type type) {
                            if (auto fnType = dyn_cast<idr::FnType>(type))
                              types[fnType].add(Labels::of(closure.getCallee().getAttr()));
                          });
    });
    module.op.walk([&](idr::CtorOp ctor) {
      auto data = ctor->getParentOfType<idr::DataOp>().getSymNameAttr();
      for (auto [i, type] : llvm::enumerate(ctor.getFieldTypes().getAsValueRange<TypeAttr>()))
        if (auto fnType = dyn_cast<idr::FnType>(type)) {
          const auto *field = solver.lookupState<FieldLabels>(solver.getLatticeAnchor<FieldAnchor>(
              std::make_tuple(data, ctor.getSymNameAttr(), unsigned(i))));
          types[fnType].add(field ? field->value : Labels{});
        }
    });
  }

  // The closure types a value of `type` holds without a box in between.
  void holds(Type type, SmallVectorImpl<idr::FnType> &out, llvm::DenseSet<StringAttr> &seen) {
    if (auto fnType = dyn_cast<idr::FnType>(type)) {
      out.push_back(fnType);
      return;
    }
    auto data = dyn_cast<idr::DataType>(type);
    if (!data || !seen.insert(data.getName().getAttr()).second)
      return;
    auto decl = module.symbols.lookup<idr::DataOp>(data.getName().getAttr());
    if (!decl)
      return;
    for (idr::CtorOp ctor : decl.getCtors())
      for (Type field : ctor.getFieldTypes().getAsValueRange<TypeAttr>())
        holds(field, out, seen);
  }

  unsigned arity(idr::FnType type) { return type.getInputs().size(); }

  // The captures of `label` as a closure of `type`.
  ArrayRef<Type> captures(StringAttr label, idr::FnType type) {
    func::FuncOp fn = module.function(label);
    return fn.getArgumentTypes().drop_back(arity(type));
  }

  // A type is convertible if its labels are known and fit it, and it is on
  // no cycle of "a capture holds" among such types.
  void decide() {
    llvm::DenseMap<idr::FnType, SmallVector<idr::FnType>> edges;
    SmallVector<idr::FnType> candidates;
    for (auto &[type, closures] : types) {
      bool fits = !closures.unknown && !closures.labels.empty() &&
                  llvm::all_of(closures.labels, [&](StringAttr label) {
                    func::FuncOp fn = module.function(label);
                    return fn && !fn.isExternal() && fn.getNumArguments() >= arity(type) &&
                           llvm::equal(fn.getArgumentTypes().take_back(arity(type)),
                                       type.getInputs()) &&
                           llvm::equal(fn.getResultTypes(), type.getResults());
                  });
      if (!fits)
        continue;
      candidates.push_back(type);
      for (StringAttr label : closures.labels)
        for (Type capture : captures(label, type)) {
          llvm::DenseSet<StringAttr> seen;
          holds(capture, edges[type], seen);
        }
    }
    llvm::DenseSet<idr::FnType> cyclic;
    for (const SmallVector<idr::FnType> &component : passes::stronglyConnected<idr::FnType>(
             candidates, [&](idr::FnType type) { return edges.lookup(type); }))
      if (component.size() > 1 || llvm::is_contained(edges.lookup(component.front()),
                                                      component.front()))
        cyclic.insert(component.begin(), component.end());

    MLIRContext *ctx = module.op.getContext();
    unsigned n = 0;
    for (idr::FnType type : candidates)
      if (!cyclic.contains(type))
        types[type].sum = idr::DataType::get(
            ctx, FlatSymbolRefAttr::get(ctx, ("fn$" + Twine(n++)).str()));
  }

  idr::DataType sumOf(Type type) {
    auto fnType = dyn_cast<idr::FnType>(type);
    return fnType ? types.lookup(fnType).sum : idr::DataType();
  }

  Type convert(Type type) {
    auto fnType = dyn_cast<idr::FnType>(type);
    if (!fnType)
      return type;
    if (idr::DataType sum = sumOf(fnType))
      return sum;
    auto map = [&](ArrayRef<Type> in) {
      return llvm::map_to_vector(in, [&](Type t) { return convert(t); });
    };
    return idr::FnType::get(type.getContext(), map(fnType.getInputs()), map(fnType.getResults()));
  }

  // A constant of type `type` with its closures of converted types as
  // constructors.
  Attribute convert(Attribute attr, Type type) {
    MLIRContext *ctx = attr.getContext();
    if (auto closure = dyn_cast<idr::ClosureAttr>(attr)) {
      func::FuncOp fn = module.function(closure.getCallee().getAttr());
      SmallVector<Attribute> captures;
      for (auto [i, capture] : llvm::enumerate(closure.getCaptures()))
        captures.push_back(convert(capture, fn.getArgumentTypes()[i]));
      auto array = ArrayAttr::get(ctx, captures);
      if (idr::DataType sum = sumOf(type))
        return idr::ConAttr::get(ctx, SymbolRefAttr::get(sum.getName().getAttr(), {closure.getCallee()}),
                                 array);
      return idr::ClosureAttr::get(ctx, closure.getCallee(), array);
    }
    if (auto con = dyn_cast<idr::ConAttr>(attr)) {
      SmallVector<Attribute> fields;
      for (auto [i, field] : llvm::enumerate(con.getFields()))
        fields.push_back(convert(field, module.fieldType(con.getCtor(), i)));
      return idr::ConAttr::get(ctx, con.getCtor(), ArrayAttr::get(ctx, fields));
    }
    return attr;
  }

  void declareSums(OpBuilder &b) {
    b.setInsertionPointToStart(module.op.getBody());
    for (auto &[type, closures] : types) {
      if (!closures.sum)
        continue;
      auto data = idr::DataOp::create(b, module.op.getLoc(), closures.sum.getName().getAttr(),
                                      UnitAttr());
      OpBuilder inner = OpBuilder::atBlockEnd(&data.getBody().emplaceBlock());
      for (auto [tag, label] : llvm::enumerate(closures.labels)) {
        func::FuncOp fn = module.function(label);
        ArrayRef<Type> fields = captures(label, type);
        SmallVector<Type> converted = llvm::map_to_vector(fields, [&](Type t) { return convert(t); });
        SmallVector<StringRef> quantities;
        for (unsigned i = 0; i < fields.size(); ++i) {
          auto quantity = fn.getArgAttrOfType<StringAttr>(i, "idr.quantity");
          quantities.push_back(quantity ? quantity.getValue() : "w");
        }
        idr::CtorOp::create(inner, fn.getLoc(), label, b.getI64IntegerAttr(tag),
                            b.getTypeArrayAttr(converted), b.getStrArrayAttr(quantities));
      }
    }
  }

  // An idr.apply of a converted type, with the labels its callee may hold
  // (all of the type's for an apply the analysis found dead).
  struct Apply {
    idr::ApplyOp op;
    idr::FnType type;
    SmallVector<StringAttr> labels;
  };

  // The apply becomes a match over those labels, each region calling its
  // label with the captures, then the arguments.
  void rewrite(const Apply &site, OpBuilder &b) {
    auto [apply, type, labels] = site;
    SmallVector<Attribute> cases = llvm::map_to_vector(labels, [](StringAttr label) -> Attribute {
      return FlatSymbolRefAttr::get(label);
    });
    b.setInsertionPoint(apply);
    auto match = idr::MatchOp::create(b, apply.getLoc(), apply.getResultTypes(), apply.getCallee(),
                                      b.getArrayAttr(cases), unsigned(labels.size()));
    for (auto [label, region] : llvm::zip(labels, match.getRegions())) {
      func::FuncOp fn = module.function(label);
      SmallVector<Type> fields =
          llvm::map_to_vector(captures(label, type), [&](Type t) { return convert(t); });
      Block *block = b.createBlock(&region, region.end(), fields,
                                   SmallVector<Location>(fields.size(), apply.getLoc()));
      SmallVector<Value> operands(block->getArguments());
      llvm::append_range(operands, apply.getArgs());
      auto call = func::CallOp::create(b, apply.getLoc(), fn, operands);
      idr::YieldOp::create(b, apply.getLoc(), call.getResults());
    }
    apply.replaceAllUsesWith(match.getResults());
    apply.erase();
  }

  void run() {
    collect();
    decide();
    OpBuilder b(module.op.getContext());
    declareSums(b);
    SmallVector<Apply> applies;
    for (idr::ApplyOp apply : module.applies) {
      auto type = cast<idr::FnType>(apply.getCallee().getType());
      if (!sumOf(type))
        continue;
      Labels callee = labelsOf(apply.getCallee());
      applies.push_back(
          {apply, type, callee.names.empty() ? types.lookup(type).labels : callee.names});
    }

    module.op.walk([&](idr::ConstantOp constant) {
      Attribute value = convert(constant.getValue(), constant.getType());
      Type type = convert(constant.getType());
      if (value == constant.getValue() && type == constant.getType())
        return;
      b.setInsertionPoint(constant);
      auto replacement = idr::ConstantOp::create(b, constant.getLoc(), type, value);
      constant.replaceAllUsesWith(replacement.getResult());
      constant.erase();
    });
    module.op.walk([&](idr::ClosureOp closure) {
      idr::DataType sum = sumOf(closure.getType());
      if (!sum)
        return;
      b.setInsertionPoint(closure);
      auto con = idr::ConOp::create(
          b, closure.getLoc(), sum,
          SymbolRefAttr::get(sum.getName().getAttr(), {closure.getCalleeAttr()}),
          closure.getCaptures());
      closure.replaceAllUsesWith(con.getResult());
      closure.erase();
    });
    for (const Apply &apply : applies)
      rewrite(apply, b);

    AttrTypeReplacer replacer;
    replacer.addReplacement([&](idr::FnType type) -> std::pair<Type, WalkResult> {
      return {convert(type), WalkResult::skip()};
    });
    replacer.recursivelyReplaceElementsIn(module.op, /*replaceAttrs=*/true,
                                          /*replaceLocs=*/false, /*replaceTypes=*/true);
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
    Converter(module, solver).run();
  }
};

} // namespace
