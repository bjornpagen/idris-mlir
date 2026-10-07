// idr.ownership:commit: what exclusivity's solver proved, written into the
// types. Nothing here is exported: inferExclusive runs it.
export module idr.ownership:commit;

import idr.mlir;
import idr.dialect;

import :callee;
import :cells;
import :followed;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::ownership {

// The commit: the values the solver proved exclusive get the grade, and
// where an exclusive value meets a position typed owned (a call's argument,
// a return, a yield), it is shared into it.
class Commit {
public:
  Commit(ModuleOp module, DataFlowSolver &solver) : module(module), solver(solver) {}

  FailureOr<unsigned> run() {
    unsigned exclusive = 0;
    // A call's results join the callee's returns the solver reached, which
    // it records after the call: the callee's results are those returns'.
    SymbolTableCollection symbols;
    llvm::DenseMap<Operation *, func::CallOp> callOf;
    module.walk([&](func::CallOp call) {
      if (func::FuncOp fn = callee(call, symbols))
        callOf.try_emplace(fn, call);
    });
    for (auto fn : module.getOps<func::FuncOp>()) {
      if (fn.isExternal())
        continue;
      // A value before its uses: what follows its operand's type reads
      // the operand already marked.
      fn.walk<WalkOrder::PreOrder>([&](Block *block) {
        for (BlockArgument arg : block->getArguments())
          exclusive += mark(arg);
        for (Operation &op : *block)
          for (Value result : op.getResults())
            exclusive += mark(result);
      });
      SmallVector<Type> results(fn.getResultTypes());
      auto call = callOf.lookup(fn);
      auto *returns =
          call ? solver.lookupState<PredecessorState>(solver.getProgramPointAfter(call)) : nullptr;
      if (returns && returns->allPredecessorsKnown() && !returns->getKnownPredecessors().empty()) {
        for (auto [index, type] : llvm::enumerate(results)) {
          if (!isOwned(type))
            continue;
          bool all = llvm::all_of(returns->getKnownPredecessors(), [&](Operation *ret) {
            return isExclusive(ret->getOperand(static_cast<unsigned>(index)).getType());
          });
          if (all)
            type = graded({gradeOf(type).quantity, Permission::Excl}, unrestricted(type));
        }
      }
      fn.setFunctionType(FunctionType::get(module.getContext(),
                                           llvm::to_vector(fn.getBody().getArgumentTypes()), results));
    }
    // A call's results are its callee's: on a path the solver never
    // reached, a call has no lattice of its own.
    module.walk([&](func::CallOp call) {
      if (func::FuncOp fn = callee(call, symbols))
        for (auto [result, type] : llvm::zip(call.getResults(), fn.getResultTypes()))
          result.setType(type);
    });
    // Every position now says what it takes.
    OpBuilder b(module.getContext());
    WalkResult walked = module.walk([&](Operation *op) -> WalkResult {
      if (auto call = dyn_cast<func::CallOp>(op)) {
        if (func::FuncOp fn = callee(call, symbols))
          for (auto [operand, expected] : llvm::zip(call.getArgOperandsMutable(), fn.getArgumentTypes()))
            if (failed(meet(b, operand, expected)))
              return WalkResult::interrupt();
      } else if (auto ret = dyn_cast<func::ReturnOp>(op)) {
        auto fn = ret->getParentOfType<func::FuncOp>();
        for (auto [operand, expected] : llvm::zip(ret->getOpOperands(), fn.getResultTypes()))
          if (failed(meet(b, operand, expected)))
            return WalkResult::interrupt();
      } else if (auto yield = dyn_cast<YieldOp>(op)) {
        for (auto [operand, expected] :
             llvm::zip(yield->getOpOperands(), yield->getParentOp()->getResultTypes()))
          if (failed(meet(b, operand, expected)))
            return WalkResult::interrupt();
      } else if (auto suspend = dyn_cast<SuspendOp>(op)) {
        // A capture is the function's parameter. An exclusive value is
        // shared into that owned parameter, as a call's argument is.
        auto fn = symbols.lookupNearestSymbolFrom<func::FuncOp>(suspend, suspend.getCalleeAttr());
        if (fn)
          for (auto [operand, expected] :
               llvm::zip(suspend.getCapturesMutable(), fn.getArgumentTypes()))
            if (failed(meet(b, operand, expected)))
              return WalkResult::interrupt();
      }
      return WalkResult::advance();
    });
    if (walked.wasInterrupted())
      return failure();
    // A share of a value that is not exclusive shares nothing.
    module.walk([&](ShareOp share) {
      if (isExclusive(share.getValue().getType()))
        return;
      share.getResult().replaceAllUsesWith(share.getValue());
      share.erase();
    });
    return exclusive;
  }

private:
  // A value whose type its own op derives from its operand's (a change of
  // quantity, a share) follows the operand: a linear value of an exclusive
  // one is exclusive.
  bool live(Block *block) {
    auto *state = solver.lookupState<Executable>(solver.getProgramPointBefore(block));
    return state && state->isLive();
  }

  unsigned mark(Value value) {
    if (!followed(value))
      return 0;
    Operation *def = value.getDefiningOp();
    if (isa_and_nonnull<ShareOp>(def))
      return 0;
    if (isa_and_nonnull<LinEnterOp, LinUseOp>(def)) {
      Type type = atQuantity(def->getOperand(0).getType(), quantityOf(value.getType()));
      bool changed = type != value.getType();
      value.setType(type);
      return changed ? 1 : 0;
    }
    auto *lattice = solver.lookupState<CellsLattice>(value);
    if (!lattice || lattice->getValue().sharing != Sharing::Exclusive)
      return 0;
    value.setType(graded({gradeOf(value.getType()).quantity, Permission::Excl},
                         unrestricted(value.getType())));
    return 1;
  }

  // `operand` where `expected` is taken: an exclusive value is shared into
  // an owned position. An owned one in an exclusive position is on a path
  // the solver never reached (whose values it never graded), where it is
  // poison; anywhere else it is the solver and the commit disagreeing,
  // which is a bug here, never a program to compile.
  LogicalResult meet(OpBuilder &b, OpOperand &operand, Type expected) {
    Type type = operand.get().getType();
    if (type == expected || !isOwned(expected))
      return success();
    Operation *op = operand.getOwner();
    b.setInsertionPoint(op);
    if (isExclusive(type) && !isExclusive(expected)) {
      operand.set(ShareOp::create(b, op->getLoc(), expected, operand.get()));
      return success();
    }
    if (!isExclusive(type) && isExclusive(expected)) {
      auto *live = solver.lookupState<Executable>(solver.getProgramPointBefore(op->getBlock()));
      if (live && live->isLive())
        return op->emitOpError("idr-rc: gives a value of ")
               << type << " where the solver proved " << expected;
      operand.set(ub::PoisonOp::create(b, op->getLoc(), expected));
    }
    return success();
  }

  ModuleOp module;
  DataFlowSolver &solver;
};

} // namespace idr::ownership
