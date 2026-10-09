// idr.defunctionalize:analysis: the labels each closure or suspension may
// hold, a sparse forward dataflow analysis on MLIR's framework,
// interprocedural, that joins itself what the framework does not follow: the
// captures of closures and suspensions and the arguments of applies into a
// function's entry, the results of each label an apply may call into the
// apply's, and those of each label a force may run into the force's, the
// fields of constructors and the elements of arrays of any rank (an
// IORef's one element among them).
export module idr.defunctionalize:analysis;

import idr.mlir;
import idr.dialect;

import :closures;
import :labels;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::defunctionalize {

class LabelAnalysis : public SparseForwardDataFlowAnalysis<LabelLattice> {
public:
  // Its identity, which MLIR's TypeID finds by this name.
  static TypeID resolveTypeID() {
    static SelfOwningTypeID id;
    return id;
  }

  LabelAnalysis(DataFlowSolver &dataflow, Module &closures)
      : SparseForwardDataFlowAnalysis(dataflow), module(closures) {
    registerAnchorKind<FieldAnchor>();
    registerAnchorKind<ElementsAnchor>();
  }

  // Closures and suspensions stored in constants reach their fields before
  // anything runs.
  LogicalResult initialize(Operation *top) override {
    top->walk([&](idr::ConstantOp constant) {
      constant.getValue().walk([&](idr::ConAttr con) {
        eachField(con, [&](Attribute field, unsigned i) {
          auto closure = dyn_cast<idr::ClosureAttr>(field);
          if (!closure)
            return;
          Type declared = module.fieldType(con.getCtor(), i);
          if (declared && isKeyed(declared))
            joinField(con.getCtor(), i, Labels::of(closure.getCallee().getAttr()));
        });
      });
    });
    return SparseForwardDataFlowAnalysis::initialize(top);
  }

  LogicalResult visitOperation(Operation *op, ArrayRef<const LabelLattice *> operands,
                               ArrayRef<LabelLattice *> results) override {
    if (auto closure = dyn_cast<idr::ClosureOp>(op))
      return set(results[0], Labels::of(closure.getCalleeAttr().getAttr()));
    if (auto suspend = dyn_cast<idr::SuspendOp>(op))
      return set(results[0], Labels::of(suspend.getCalleeAttr().getAttr()));
    if (auto constant = dyn_cast<idr::ConstantOp>(op)) {
      if (auto closure = dyn_cast<idr::ClosureAttr>(constant.getValue());
          closure && isKeyed(constant.getType()))
        return set(results[0], Labels::of(closure.getCallee().getAttr()));
      return success();
    }
    // A poison is no value the program computes, so it holds no label.
    if (isa<ub::PoisonOp>(op))
      return success();
    if (auto con = dyn_cast<idr::ConOp>(op)) {
      for (auto [i, field] : llvm::enumerate(operands))
        if (isKeyed(con.getFields()[i].getType()))
          joinField(con.getCtor(), static_cast<unsigned>(i), field->getValue());
      return success();
    }
    // Entering or using a linear value keeps what it holds.
    if (isa<idr::LinEnterOp, idr::LinUseOp>(op)) {
      if (isKeyed(op->getResult(0).getType()))
        return set(results[0], operands[0]->getValue());
      return success();
    }
    if (auto field = dyn_cast<idr::FieldOp>(op)) {
      if (!isKeyed(field.getType()))
        return success();
      auto ref = SymbolRefAttr::get(dataName(field.getValue().getType()),
                                    {field.getCtorAttr()});
      return set(results[0], readField(getProgramPointAfter(op), ref,
                                       static_cast<unsigned>(field.getIndex())));
    }
    if (auto force = dyn_cast<idr::ForceOp>(op))
      return visitForce(force, operands[0]->getValue(), results[0]);
    // The sizes and indices before the fill and the value are one per
    // dimension, so the operand's lattice is found by its number.
    if (auto made = dyn_cast<idr::ArrayNewOp>(op))
      return joinElements(made.getArrayType(), made.getFill().getType(),
                          operands[made.getFillMutable().getOperandNumber()]->getValue());
    if (auto stored = dyn_cast<idr::ArraySetOp>(op))
      return joinElements(stored.getArrayType(), stored.getValue().getType(),
                          operands[stored.getValueMutable().getOperandNumber()]->getValue());
    if (auto read = dyn_cast<idr::ArrayGetOp>(op)) {
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

  // The entry arguments of a function: from its calls, its closures and
  // suspensions, and the idr.apply ops that may call it.
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
    for (idr::SuspendOp suspend : module.suspends.lookup(name))
      for (auto [capture, argument] : llvm::zip(suspend.getCaptures(), arguments))
        join(argument, *getLatticeElementFor(point, capture));
    auto joinCaptures = [&](ArrayAttr captures) {
      for (auto [capture, argument] : llvm::zip(captures, arguments))
        if (auto closure = dyn_cast<idr::ClosureAttr>(capture))
          propagateIfChanged(argument, static_cast<LabelLattice *>(argument)->join(
                                           Labels::of(closure.getCallee().getAttr())));
    };
    for (ArrayAttr captures : module.constantClosures.lookup(name))
      joinCaptures(captures);
    for (ArrayAttr captures : module.suspendConstants.lookup(name))
      joinCaptures(captures);

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
  // constructor, and the element a fold's body takes is one of the array's.
  // A generate stores its fill and what its body yields as elements, which
  // its results, an array and a world, do not carry.
  void visitNonControlFlowArguments(Operation *op, const RegionSuccessor &successor,
                                    ValueRange inputs,
                                    ArrayRef<LabelLattice *> lattices) override {
    if (auto generate = dyn_cast<idr::ArrayGenerateOp>(op)) {
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
    if (auto fold = dyn_cast<idr::ArrayFoldOp>(op); fold && region) {
      ProgramPoint *point = getProgramPointBefore(&region->front());
      for (auto [input, lattice] : llvm::zip(inputs, lattices))
        if (isKeyed(input.getType()) && cast<BlockArgument>(input).getArgNumber() == 1)
          propagateIfChanged(lattice, lattice->join(readElements(point, fold.getArrayType())));
        else
          setToEntryState(lattice);
      return;
    }
    auto match = dyn_cast<idr::MatchOp>(op);
    if (!match || !region || region->getRegionNumber() >= match.getCases().size())
      return setAllToEntryStates(lattices);
    auto ctor = cast<FlatSymbolRefAttr>(match.getCases()[region->getRegionNumber()]);
    auto ref = SymbolRefAttr::get(dataName(match.getScrutinee().getType()), {ctor});
    ProgramPoint *point = getProgramPointBefore(&region->front());
    for (auto [input, lattice] : llvm::zip(inputs, lattices))
      if (isKeyed(input.getType()))
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

  // A force gives what one of the labels its cell may hold returns.
  LogicalResult visitForce(idr::ForceOp force, const Labels &cell, LabelLattice *result) {
    if (!isKeyed(force.getType()))
      return success();
    if (cell.unknown)
      return set(result, Labels::top());
    ProgramPoint *point = getProgramPointAfter(force);
    for (StringAttr label : cell.names) {
      func::FuncOp fn = module.function(label);
      if (!fn || fn.isExternal())
        return set(result, Labels::top());
      fn.walk([&](func::ReturnOp ret) {
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

  void joinField(SymbolRefAttr ctor, unsigned index, const Labels &labels) {
    auto *state = getOrCreate<FieldLabels>(anchor(ctor, index));
    propagateIfChanged(state, state->join(labels));
  }

  const Labels &readField(ProgramPoint *point, SymbolRefAttr ctor, unsigned index) {
    return getOrCreateFor<FieldLabels>(point, anchor(ctor, index))->value;
  }

  // An element of `type` stored in an array of `array`'s element type.
  LogicalResult joinElements(MemRefType array, Type type, const Labels &labels) {
    if (!isKeyed(type))
      return success();
    auto *state = getOrCreate<FieldLabels>(getLatticeAnchor<ElementsAnchor>(array.getElementType()));
    propagateIfChanged(state, state->join(labels));
    return success();
  }

  const Labels &readElements(ProgramPoint *point, MemRefType array) {
    return getOrCreateFor<FieldLabels>(point, getLatticeAnchor<ElementsAnchor>(array.getElementType()))
        ->value;
  }

  Module &module;
};

} // namespace idr::defunctionalize
