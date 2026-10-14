// The passes of one round of the simplify loop, in order.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Simplify.h"

#include "mlir/Dialect/Arith/Transforms/Passes.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Transforms/Passes.h"

// The round's passes of other areas, from the one declaration of each.
namespace idr {
#define GEN_PASS_DECL_IDREFFECTS
#define GEN_PASS_DECL_IDRIDENTITY
#define GEN_PASS_DECL_IDRREDIRECT
#define GEN_PASS_DECL_IDRINLINE
#define GEN_PASS_DECL_IDRSPECIALIZE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

void idr::buildSimplifyRound(OpPassManager &pm) {
  pm.addPass(createIdrEffects());
  pm.addPass(createIdrLoopBreakers());
  // A nested manager keeps no module analysis alive past it, and a
  // function pass may only read one a module step left cached: the step
  // just before the nest computes what the function passes read.
  pm.addPass(createIdrRoundFacts());
  OpPassManager &fn = pm.nest<idr::FuncOp>();
  // On the effects just computed, which say whether a call it assumes
  // nothing of only computes; and before inlining, so that a call of a
  // function that only rebuilds its argument is gone before the inliner
  // weighs it or copies a level of the rebuild into its caller.
  fn.addPass(createIdrIdentity());
  fn.addPass(createCanonicalizerPass());
  fn.addPass(createCSEPass());
  fn.addPass(createIdrRedirect());
  // idr-inline inlines the calls the size rule allows until an iteration
  // inlines nothing, not a fixed number of times (upstream's default is 4):
  // unfolding a sequence of n actions, as a `do` block of n statements is
  // (each `>>` applies the closure of the rest), takes n iterations, while
  // each round runs every pass on the whole module; with a bound, the loop
  // took a round for every statement or two, each as long as the program is
  // large. A body is inlined as it is. Each function is canonicalized
  // before inlining, and again within an iteration only when the iteration
  // inlined into it. The iterations end as the rounds do: every cycle of
  // references keeps a loop breaker, and inlining only copies references
  // that exist, so no iteration closes a new cycle.
  pm.addPass(createIdrInline());
  // Specialization takes no option: it is finite by construction, and its
  // budget is an assertion of its own.
  pm.addPass(createIdrSpecialize());
  pm.addPass(createSCCPPass());
  // int-range-optimizations nested per function, where it runs in
  // parallel and solves each function on its own: on the stage-0 module
  // one round's module solve took 30 s of wall against 3 s nested, for
  // two changed bodies in 37,386. The ranges it no longer carries across
  // a call are the ones inlining, which ran just before, has already
  // brought inside one function, and a caller-to-callee range the round
  // still needs is found again by the module solves idr-narrow and
  // idr-in-bounds run later (idr::Ranges). SCCP stays on the module: its
  // constants cross calls in both directions, closure constants among
  // them, on which loop-breaker marking and the rounds' end depend.
  pm.nest<idr::FuncOp>().addPass(arith::createIntRangeOptimizationsPass());
  // remove-dead-values without its own canonicalization, which folds
  // region-branch patterns on the matches alone: a field one of them folds
  // leaves the constructor it read dead but in place, still holding a world
  // or a linear value that the fold's user now holds too. The next round's
  // canonicalization runs on everything and erases what is dead.
  RemoveDeadValuesPassOptions dead;
  dead.canonicalize = false;
  pm.addPass(createRemoveDeadValuesPass(dead));
  pm.addPass(createSymbolDCEPass());
}
