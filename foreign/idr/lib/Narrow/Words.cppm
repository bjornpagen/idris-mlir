// idr.narrow:words: the bigs and naturals integer range analysis proves fit a
// small become plain i64 words, and a loop whose natural only descends is
// versioned so that its copy proves it.
//
// The analysis is MLIR's, seeing our ops through their ranges
// (idr.ranges); this pass only reads it and rewrites. Nothing it
// learns is stored: the rewritten IR is the fact. A narrowed op becomes
// `arith` on the values, which idr.big.to_int and idr.big.from_int convert
// where the web meets a big it does not prove; the pairs they form inside
// a web fold away.
export module idr.narrow:words;

import idr.mlir;
import idr.dialect;
import idr.ownership;

import :carried;
import :facts;
import :naturals;
import :ops;
import :versions;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::narrow {

// What `narrow` changed: the loops versioned, the values carried as words,
// and the ops narrowed.
export struct Narrowed {
  uint64_t versioned = 0;
  uint64_t carried = 0;
  uint64_t narrowed = 0;
};

// Makes the bigs and naturals of `module` the analysis proves fit a small
// words, after versioning the loops whose natural only descends. Fails
// when the analysis fails.
export FailureOr<Narrowed> narrow(ModuleOp module) {
  Narrowed done;
  IRRewriter rewriter(module.getContext());
  // Whether counting ran, which its grades say: one walk, for the pass.
  bool counted = ownership::inOwnedStage(module);
  {
    DataFlowSolver solver(DataFlowConfig().setInterprocedural(true));
    if (failed(runSolver(solver, module)))
      return failure();
    Facts facts(solver, counted);
    SmallVector<std::pair<scf::WhileOp, unsigned>> versions;
    module.walk([&](scf::WhileOp loop) {
      if (std::optional<unsigned> index = descendingArgument(loop, facts))
        versions.emplace_back(loop, *index);
    });
    for (auto [loop, index] : versions)
      version(rewriter, loop, index, counted);
    done.versioned += versions.size();
  }

  DataFlowSolver solver(DataFlowConfig().setInterprocedural(true));
  if (failed(runSolver(solver, module)))
    return failure();
  Facts facts(solver, counted);
  // The joints first, while every value is still the one analysed; then
  // the ops, whose operands may by then be the bigs of words.
  SmallVector<Operation *> joints, ops;
  module.walk([&](Operation *op) {
    if (isa<scf::WhileOp, scf::ForOp, scf::IfOp, scf::IndexSwitchOp, MatchOp, MatchLitOp>(op))
      joints.push_back(op);
    if (isa<MatchLitOp, BigAddOp, BigSubOp, BigMulOp, BigPredOp, BigCmpOp, NatFromBigOp, NatToBigOp,
                 BigToIntOp, CheckNonzeroOp, DupOp, DropOp>(op))
      ops.push_back(op);
  });
  for (Operation *op : joints)
    done.carried += narrowCarried(rewriter, facts, op);
  for (Operation *op : ops)
    if (narrowOp(rewriter, facts, op))
      ++done.narrowed;

  // A word made a big and back is the word; what no one reads goes.
  GreedyRewriteConfig config;
  config.setStrictness(GreedyRewriteStrictness::ExistingAndNewOps);
  (void)applyOpPatternsGreedily(facts.converted(), FrozenRewritePatternSet(), config);
  // A versioned loop's start, once its copy took the word, and a big
  // made of a word that every reader now takes as the word.
  module.walk([&](Operation *op) {
    if (isa<BigSmallOp, BigFromIntOp>(op) && isOpTriviallyDead(op))
      rewriter.eraseOp(op);
  });
  return done;
}

} // namespace idr::narrow
