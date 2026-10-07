// idr.defunctionalize:analysis: the labels each closure value may hold, a
// sparse forward dataflow analysis on MLIR's framework, interprocedural,
// that joins itself what the framework does not follow: the captures of
// closures and the arguments of applies into a function's entry, the
// results of each label an apply may call into the apply's, and the fields
// of constructors.
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
  }

  // Closures stored in constants reach their fields before anything runs.
  LogicalResult initialize(Operation *top) override {
    top->walk([&](idr::ConstantOp constant) {
      constant.getValue().walk([&](idr::ConAttr con) {
        for (auto [i, field] : llvm::enumerate(con.getFields())) {
          auto closure = dyn_cast<idr::ClosureAttr>(field);
          if (!closure)
            continue;
          Type declared = module.fieldType(con.getCtor(), static_cast<unsigned>(i));
          if (declared && isClosureType(declared))
            joinField(con.getCtor(), static_cast<unsigned>(i),
                      Labels::of(closure.getCallee().getAttr()));
        }
      });
    });
    return SparseForwardDataFlowAnalysis::initialize(top);
  }

  LogicalResult visitOperation(Operation *op, ArrayRef<const LabelLattice *> operands,
                               ArrayRef<LabelLattice *> results) override {
    if (auto closure = dyn_cast<idr::ClosureOp>(op))
      return set(results[0], Labels::of(closure.getCalleeAttr().getAttr()));
    if (auto constant = dyn_cast<idr::ConstantOp>(op)) {
      if (auto closure = dyn_cast<idr::ClosureAttr>(constant.getValue());
          closure && isClosureType(constant.getType()))
        return set(results[0], Labels::of(closure.getCallee().getAttr()));
      return success();
    }
    if (auto con = dyn_cast<idr::ConOp>(op)) {
      for (auto [i, field] : llvm::enumerate(operands))
        if (isClosureType(con.getFields()[i].getType()))
          joinField(con.getCtor(), static_cast<unsigned>(i), field->getValue());
      return success();
    }
    // Entering or using a linear value keeps what it holds.
    if (isa<idr::LinEnterOp, idr::LinUseOp>(op)) {
      if (isClosureType(op->getResult(0).getType()))
        return set(results[0], operands[0]->getValue());
      return success();
    }
    if (auto field = dyn_cast<idr::FieldOp>(op)) {
      if (!isClosureType(field.getType()))
        return success();
      auto ref = SymbolRefAttr::get(dataName(field.getValue().getType()),
                                    {field.getCtorAttr()});
      return set(results[0], readField(getProgramPointAfter(op), ref,
                                       static_cast<unsigned>(field.getIndex())));
    }
    for (auto [result, lattice] : llvm::zip(op->getResults(), results))
      if (isClosureType(result.getType()))
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
      if (isClosureType(input.getType()))
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

} // namespace idr::defunctionalize
