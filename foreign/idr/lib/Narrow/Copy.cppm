// idr.narrow:copy: the copy of a vectorized loop in a scratch module, where
// the bound on its sizes is tried and its integer ops narrowed.
export module idr.narrow:copy;

import idr.mlir;

import :widths;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::narrow {

// The copy of a loop in a scratch module: a function of the values the
// loop reads from outside, each testable one behind arith.minui of itself
// and the bound, a constant the trials set.
class Copy {
public:
  Copy(Location loc, scf::ForOp loop, const SetVector<Value> &inputs) : module(ModuleOp::create(loc)) {
    MLIRContext *ctx = loc.getContext();
    SmallVector<Type> argTypes;
    for (Value input : inputs)
      if (!matchPattern(input, m_Constant()))
        argTypes.push_back(input.getType());
    function = func::FuncOp::create(loc, "copy", FunctionType::get(ctx, argTypes, {}));
    module.push_back(function);
    Block *entry = function.addEntryBlock();
    OpBuilder b = OpBuilder::atBlockEnd(entry);
    IRMapping into;
    unsigned next = 0;
    for (Value input : inputs) {
      if (matchPattern(input, m_Constant())) {
        into.map(input, b.clone(*input.getDefiningOp())->getResult(0));
        continue;
      }
      Value arg = entry->getArgument(next++);
      if (testable(input)) {
        Value &bound = bounds[input.getType()];
        if (!bound)
          bound = arith::ConstantOp::create(b, loc, IntegerAttr::get(input.getType(), 0));
        arg = arith::MinUIOp::create(b, loc, arg, bound);
      }
      into.map(input, arg);
    }
    copy = b.clone(*loop, into);
    func::ReturnOp::create(b, loc);
  }
  ~Copy() { module.erase(); }
  Copy(const Copy &) = delete;
  Copy &operator=(const Copy &) = delete;

  // The analysis of the copy with the bound 2^exponent; none when the
  // solver fails, which is an internal error.
  std::unique_ptr<DataFlowSolver> analyse(unsigned exponent) {
    for (auto [type, bound] : bounds)
      cast<arith::ConstantOp>(bound.getDefiningOp())
          .setValueAttr(IntegerAttr::get(type, int64_t{1} << exponent));
    auto solver = std::make_unique<DataFlowSolver>(DataFlowConfig().setInterprocedural(false));
    loadBaselineAnalyses(*solver);
    solver->load<IntegerRangeAnalysis>();
    if (failed(solver->initializeAndRun(module)))
      return nullptr;
    return solver;
  }

  // Whether, under `solver`'s analysis, every op of the copied loop that
  // computes on integers wider than 32 bits fits 32 bits (the stand-ins
  // before it read the inputs, which fit nothing). Whether its 32-bit form
  // computes the same is the narrowing's to decide: it leaves wide an op
  // whose 32-bit form would compute something else.
  bool fits(DataFlowSolver &solver) {
    auto fit = [&](Value value) {
      if (ConstantIntRanges::getStorageBitwidth(value.getType()) == 0)
        return true;
      std::optional<ConstantIntRanges> range = rangeOf(solver, value);
      return range && fits32(*range);
    };
    return !copy
                ->walk([&](Operation *op) {
                  if (!widthOf(op).wide ||
                      (llvm::all_of(op->getOperands(), fit) && llvm::all_of(op->getResults(), fit)))
                    return WalkResult::advance();
                  return WalkResult::interrupt();
                })
                .wasInterrupted();
  }

  // Narrows the copy under `solver`'s analysis: upstream's patterns, in
  // upstream's order (bottom-up, so that a comparison still finds the
  // ranges of its operands), the solver told of the ops they erase. No
  // folding and no region simplification, as in upstream's own
  // int-range-optimizations: those can erase a block argument without a
  // word to the solver, and a new one at its address would take its range.
  // Failure when the patterns do not converge.
  LogicalResult narrow(DataFlowSolver &solver) {
    struct Listener : RewriterBase::Listener {
      explicit Listener(DataFlowSolver &s) : solver(s) {}
      void notifyOperationErased(Operation *op) override {
        solver.eraseState(solver.getProgramPointAfter(op));
        for (Value result : op->getResults())
          solver.eraseState(result);
      }
      DataFlowSolver &solver;
    } listener(solver);
    RewritePatternSet patterns(module.getContext());
    arith::populateIntRangeNarrowingPatterns(patterns, solver, {32});
    if (failed(applyPatternsGreedily(function.getBody(), FrozenRewritePatternSet(std::move(patterns)),
                                     GreedyRewriteConfig()
                                         .setUseTopDownTraversal(false)
                                         .enableFolding(false)
                                         .setRegionSimplificationLevel(GreedySimplifyRegionLevel::Disabled)
                                         .setListener(&listener))))
      return failure();
    // The narrowing widens a result back with arith.extui, and knows the
    // word it widens is non-negative (its range, kept on the cast); the
    // flag says so where LLVM reads it, so that the conversion to double
    // of such a word is the signed one (uitofp nneg, after the
    // canonicalization of sitofp of it), which the target has for 32-bit
    // lanes where it has no unsigned one.
    function.walk([&](arith::ExtUIOp widen) {
      std::optional<ConstantIntRanges> range = rangeOf(solver, widen.getResult());
      if (range && range->smin().isNonNegative() && fits32(*range))
        widen.setNonNeg(true);
    });
    return success();
  }

  // Clones the copy's body at `b`, its arguments standing for `inputs`
  // again.
  void cloneInto(OpBuilder &b, const SetVector<Value> &inputs) {
    Block &entry = function.getBody().front();
    IRMapping back;
    unsigned next = 0;
    for (Value input : inputs)
      if (!matchPattern(input, m_Constant()))
        back.map(entry.getArgument(next++), input);
    for (Operation &op : entry.without_terminator())
      b.clone(op, back);
  }

private:
  ModuleOp module;
  func::FuncOp function;
  // The copied loop, after the stand-ins.
  Operation *copy = nullptr;
  // The bound: one constant per type of input tested.
  llvm::MapVector<Type, Value> bounds;
};

} // namespace idr::narrow
