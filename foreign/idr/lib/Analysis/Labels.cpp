// The labels each closure or suspension may hold, a sparse forward dataflow
// analysis on MLIR's framework, interprocedural, that joins itself what the
// framework does not follow: the captures of closures and suspensions and
// the arguments of applies into a function's entry, the results of each
// label an apply may call into the apply's, and those of each label a force
// may run into the force's, the fields of constructors and the elements of
// arrays of any rank (an IORef's one element among them).

#include "idr/Analysis/Labels.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/Analysis/DataFlow/SparseAnalysis.h"
#include "mlir/Analysis/DataFlow/Utils.h"
#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Support/TypeID.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace mlir::dataflow;

namespace idr {
namespace {

// Calls `visit` for each idr.return of `fn`: the terminators of its body's
// blocks, the only places a function returns from.
void eachReturn(FuncOp fn, function_ref<void(ReturnOp)> visit) {
  for (Block &block : fn.getBody())
    if (auto ret = dyn_cast_or_null<ReturnOp>(block.empty() ? nullptr : &block.back()))
      visit(ret);
}

class LabelAnalysis : public SparseForwardDataFlowAnalysis<LabelLattice> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(LabelAnalysis)

  LabelAnalysis(DataFlowSolver &dataflow, const Labels &sites)
      : SparseForwardDataFlowAnalysis(dataflow), sites(sites) {
    registerAnchorKind<FieldAnchor>();
    registerAnchorKind<ElementsAnchor>();
  }

  // Closures and suspensions stored in constants reach their fields before
  // anything runs.
  LogicalResult initialize(Operation *top) override {
    top->walk([&](ConstantOp constant) {
      constant.getValue().walk([&](ConAttr con) {
        eachField(con, [&](Attribute field, unsigned i) {
          auto closure = dyn_cast<ClosureAttr>(field);
          if (!closure)
            return;
          Type declared = sites.fieldType(con.getCtor(), i);
          if (declared && isKeyed(declared))
            joinField(con.getCtor(), i, LabelSet::of(closure.getCallee().getAttr()));
        });
      });
    });
    return SparseForwardDataFlowAnalysis::initialize(top);
  }

  LogicalResult visitOperation(Operation *op, ArrayRef<const LabelLattice *> operands,
                               ArrayRef<LabelLattice *> results) override {
    if (auto closure = dyn_cast<ClosureOp>(op))
      return set(results[0], LabelSet::of(closure.getCalleeAttr().getAttr()));
    if (auto suspend = dyn_cast<SuspendOp>(op))
      return set(results[0], LabelSet::of(suspend.getCalleeAttr().getAttr()));
    if (auto constant = dyn_cast<ConstantOp>(op)) {
      if (auto closure = dyn_cast<ClosureAttr>(constant.getValue());
          closure && isKeyed(constant.getType()))
        return set(results[0], LabelSet::of(closure.getCallee().getAttr()));
      return success();
    }
    // A poison is no value the program computes, so it holds no label; an
    // evaluated suspension holds its value, which runs no function.
    if (isa<ub::PoisonOp, DelayOp>(op))
      return success();
    if (auto con = dyn_cast<ConOp>(op)) {
      for (auto [i, field] : llvm::enumerate(operands))
        if (isKeyed(con.getFields()[i].getType()))
          joinField(con.getCtor(), static_cast<unsigned>(i), field->getValue());
      return success();
    }
    // Entering or using a linear value keeps what it holds.
    if (isa<LinEnterOp, LinUseOp>(op)) {
      if (isKeyed(op->getResult(0).getType()))
        return set(results[0], operands[0]->getValue());
      return success();
    }
    if (auto field = dyn_cast<FieldOp>(op)) {
      if (!isKeyed(field.getType()))
        return success();
      auto ref = SymbolRefAttr::get(getSumName(field.getValue().getType()).getAttr(),
                                    {field.getCtorAttr()});
      return set(results[0], readField(getProgramPointAfter(op), ref,
                                       static_cast<unsigned>(field.getIndex())));
    }
    if (auto force = dyn_cast<ForceOp>(op))
      return visitForce(force, operands[0]->getValue(), results[0]);
    // The sizes and indices before the fill and the value are one per
    // dimension, so the operand's lattice is found by its number.
    if (auto made = dyn_cast<ArrayNewOp>(op))
      return joinElements(made.getArrayType(), made.getFill().getType(),
                          operands[made.getFillMutable().getOperandNumber()]->getValue());
    if (auto stored = dyn_cast<ArraySetOp>(op))
      return joinElements(stored.getArrayType(), stored.getValue().getType(),
                          operands[stored.getValueMutable().getOperandNumber()]->getValue());
    if (auto read = dyn_cast<ArrayGetOp>(op)) {
      if (!isKeyed(read.getValue().getType()))
        return success();
      return set(results[0], readElements(getProgramPointAfter(op), read.getArrayType()));
    }
    for (auto [result, lattice] : llvm::zip(op->getResults(), results))
      if (isKeyed(result.getType()))
        setToEntryState(lattice);
    return success();
  }

  // An idr.apply calls every label its callee may hold.
  LogicalResult visitCallOperation(CallOpInterface call,
                                   ArrayRef<const AbstractSparseLattice *> operands,
                                   ArrayRef<AbstractSparseLattice *> results) override {
    auto apply = dyn_cast<ApplyOp>(call.getOperation());
    if (!apply)
      return SparseForwardDataFlowAnalysis::visitCallOperation(call, operands, results);
    const LabelSet &callee = static_cast<const LabelLattice *>(operands[0])->getValue();
    if (callee.unknown) {
      AbstractSparseForwardDataFlowAnalysis::setAllToEntryStates(results);
      return success();
    }
    ProgramPoint *point = getProgramPointAfter(apply);
    for (StringAttr label : callee.names) {
      FuncOp fn = sites.function(label);
      if (!fn || fn.isExternal()) {
        AbstractSparseForwardDataFlowAnalysis::setAllToEntryStates(results);
        return success();
      }
      eachReturn(fn, [&](ReturnOp ret) {
        for (auto [operand, result] : llvm::zip(ret.getOperands(), results))
          join(result, *getLatticeElementFor(point, operand));
      });
    }
    return success();
  }

  // The entry arguments of a function: from its calls, its closures and
  // suspensions, and the idr.apply ops that may call it.
  void visitCallableOperation(CallableOpInterface callable,
                              ArrayRef<AbstractSparseLattice *> arguments) override {
    auto fn = dyn_cast<FuncOp>(callable.getOperation());
    if (!fn || sites.escapes(fn))
      return AbstractSparseForwardDataFlowAnalysis::setAllToEntryStates(arguments);
    Block *entry = &fn.getBody().front();
    ProgramPoint *point = getProgramPointBefore(entry);
    const auto *calls = getOrCreateFor<PredecessorState>(point, getProgramPointAfter(fn));
    for (Operation *site : calls->getKnownPredecessors())
      if (auto call = dyn_cast<CallOp>(site))
        for (auto [operand, argument] : llvm::zip(call.getArgOperands(), arguments))
          join(argument, *getLatticeElementFor(point, operand));

    StringAttr name = fn.getSymNameAttr();
    for (ClosureOp closure : sites.closures(name))
      for (auto [capture, argument] : llvm::zip(closure.getCaptures(), arguments))
        join(argument, *getLatticeElementFor(point, capture));
    for (SuspendOp suspend : sites.suspensions(name))
      for (auto [capture, argument] : llvm::zip(suspend.getCaptures(), arguments))
        join(argument, *getLatticeElementFor(point, capture));
    auto joinCaptures = [&](ArrayAttr captures) {
      for (auto [capture, argument] : llvm::zip(captures, arguments))
        if (auto closure = dyn_cast<ClosureAttr>(capture))
          propagateIfChanged(argument, static_cast<LabelLattice *>(argument)->join(
                                           LabelSet::of(closure.getCallee().getAttr())));
    };
    llvm::for_each(sites.closureConstants(name), joinCaptures);
    llvm::for_each(sites.suspensionConstants(name), joinCaptures);

    for (ApplyOp apply : sites.appliesFor(name)) {
      if (!getLatticeElementFor(point, apply.getCallee())->getValue().mayHold(name))
        continue;
      size_t k = apply.getArgs().size();
      for (auto [operand, argument] : llvm::zip(apply.getArgs(), arguments.take_back(k)))
        join(argument, *getLatticeElementFor(point, operand));
    }
  }

  // The arguments of a case region of idr.match are the fields of its
  // constructor, and the element a fold's body takes is one of the array's.
  // A generate stores its fill and what its body yields as elements, which
  // its results, an array and a world, do not carry.
  void visitNonControlFlowArguments(Operation *op, const RegionSuccessor &successor,
                                    ValueRange inputs,
                                    ArrayRef<LabelLattice *> lattices) override {
    if (auto generate = dyn_cast<ArrayGenerateOp>(op)) {
      ProgramPoint *point = getProgramPointAfter(op);
      SmallVector<Value> stored{generate.getFill()};
      if (!generate.getBody().empty())
        llvm::append_range(stored, generate.getBody().front().getTerminator()->getOperands());
      for (Value element : stored)
        (void)joinElements(generate.getArrayType(), element.getType(),
                           getLatticeElementFor(point, element)->getValue());
      return setAllToEntryStates(lattices);
    }
    Region *region = successor.getSuccessor();
    if (auto fold = dyn_cast<ArrayFoldOp>(op); fold && region) {
      ProgramPoint *point = getProgramPointBefore(&region->front());
      for (auto [input, lattice] : llvm::zip(inputs, lattices))
        if (isKeyed(input.getType()) && cast<BlockArgument>(input).getArgNumber() == 1)
          propagateIfChanged(lattice, lattice->join(readElements(point, fold.getArrayType())));
        else
          setToEntryState(lattice);
      return;
    }
    auto match = dyn_cast<MatchOp>(op);
    if (!match || !region || region->getRegionNumber() >= match.getCases().size())
      return setAllToEntryStates(lattices);
    auto ctor = cast<FlatSymbolRefAttr>(match.getCases()[region->getRegionNumber()]);
    auto ref = SymbolRefAttr::get(getSumName(match.getScrutinee().getType()).getAttr(), {ctor});
    ProgramPoint *point = getProgramPointBefore(&region->front());
    for (auto [input, lattice] : llvm::zip(inputs, lattices))
      if (isKeyed(input.getType()))
        propagateIfChanged(lattice, lattice->join(readField(
                                        point, ref, cast<BlockArgument>(input).getArgNumber())));
  }

  void setToEntryState(LabelLattice *lattice) override {
    propagateIfChanged(lattice, lattice->join(LabelSet::top()));
  }

private:
  LogicalResult set(LabelLattice *lattice, const LabelSet &labels) {
    propagateIfChanged(lattice, lattice->join(labels));
    return success();
  }

  // A force gives what one of the labels its cell may hold returns.
  LogicalResult visitForce(ForceOp force, const LabelSet &cell, LabelLattice *result) {
    if (!isKeyed(force.getType()))
      return success();
    if (cell.unknown)
      return set(result, LabelSet::top());
    ProgramPoint *point = getProgramPointAfter(force);
    for (StringAttr label : cell.names) {
      FuncOp fn = sites.function(label);
      if (!fn || fn.isExternal())
        return set(result, LabelSet::top());
      eachReturn(fn, [&](ReturnOp ret) {
        if (ret.getNumOperands() == 1)
          join(result, *getLatticeElementFor(point, ret.getOperand(0)));
      });
    }
    return success();
  }

  FieldAnchor *anchor(SymbolRefAttr ctor, unsigned index) {
    return getLatticeAnchor<FieldAnchor>(
        std::make_tuple(ctor.getRootReference(), ctor.getLeafReference(), index));
  }

  void joinField(SymbolRefAttr ctor, unsigned index, const LabelSet &labels) {
    auto *state = getOrCreate<FieldLabels>(anchor(ctor, index));
    propagateIfChanged(state, state->join(labels));
  }

  const LabelSet &readField(ProgramPoint *point, SymbolRefAttr ctor, unsigned index) {
    return getOrCreateFor<FieldLabels>(point, anchor(ctor, index))->value;
  }

  // An element of `type` stored in an array of `array`'s element type.
  LogicalResult joinElements(MemRefType array, Type type, const LabelSet &labels) {
    if (!isKeyed(type))
      return success();
    auto *state =
        getOrCreate<FieldLabels>(getLatticeAnchor<ElementsAnchor>(array.getElementType()));
    propagateIfChanged(state, state->join(labels));
    return success();
  }

  const LabelSet &readElements(ProgramPoint *point, MemRefType array) {
    return getOrCreateFor<FieldLabels>(point,
                                       getLatticeAnchor<ElementsAnchor>(array.getElementType()))
        ->value;
  }

  const Labels &sites;
};

} // namespace

Labels::Labels(Operation *module, AnalysisManager &am)
    : table(am.getAnalysis<SymbolTable>()),
      solver(DataFlowConfig().setInterprocedural(true)) {
  gather(module);
  loadBaselineAnalyses(solver);
  solver.load<LabelAnalysis>(*this);
  diverged = mlir::failed(solver.initializeAndRun(module));
}

LabelSet Labels::labelsOf(Value value) const {
  LabelSet out;
  if (const auto *lattice = solver.lookupState<LabelLattice>(value))
    out = lattice->getValue();
  if (auto closure = value.getDefiningOp<ClosureOp>())
    out = LabelSet::join(out, LabelSet::of(closure.getCalleeAttr().getAttr()));
  if (auto suspend = value.getDefiningOp<SuspendOp>())
    out = LabelSet::join(out, LabelSet::of(suspend.getCalleeAttr().getAttr()));
  if (auto constant = value.getDefiningOp<ConstantOp>())
    if (auto closure = dyn_cast<ClosureAttr>(constant.getValue()))
      out = LabelSet::join(out, LabelSet::of(closure.getCallee().getAttr()));
  return out;
}

LabelSet Labels::fieldLabels(SymbolRefAttr ctor, unsigned index) {
  auto *at = solver.getLatticeAnchor<FieldAnchor>(
      std::make_tuple(ctor.getRootReference(), ctor.getLeafReference(), index));
  const auto *state = solver.lookupState<FieldLabels>(at);
  return state ? state->value : LabelSet();
}

LabelSet Labels::elementLabels(Type element) {
  const auto *state =
      solver.lookupState<FieldLabels>(solver.getLatticeAnchor<ElementsAnchor>(element));
  return state ? state->value : LabelSet();
}

} // namespace idr
