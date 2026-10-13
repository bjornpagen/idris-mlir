// idr-round-facts: the analyses the round's function step reads, computed
// on the module just before it.
//
// A nested manager runs each function's passes with that function's
// analysis manager, and when it ends every analysis of the module is
// dropped, since an adaptor preserves nothing. A function pass may read a
// module analysis only when it is already cached: computing one from a
// function would race with every other function and see the module as
// other threads rewrite it. So the step before the nest computes, once and
// on the pass thread, every module analysis a function of the nest reads,
// and preserves everything, which also spares the verifier after it. The
// function passes then find each with getCachedParentAnalysis, and a
// function asking for one costs a lookup instead of a module walk per
// function.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Simplify.h"
#include "idr/Analysis/Holds.h"
#include "idr/Analysis/Identities.h"
#include "idr/Analysis/Specialize.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"

namespace idr {
#define GEN_PASS_DEF_IDRROUNDFACTS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace {

struct RoundFacts : idr::impl::IdrRoundFactsBase<RoundFacts> {
  void runOnOperation() override {
    // The order is the order of what each reads: Holds reads TypeGraph,
    // BindingTimes reads References and CloneTable. What an earlier step
    // left cached is taken, not computed again.
    (void)getAnalysis<mlir::SymbolTable>();
    (void)getAnalysis<idr::Holds>();
    (void)getAnalysis<idr::Identities>();
    (void)getAnalysis<idr::CloneTable>();
    (void)getAnalysis<idr::BindingTimes>();
    markAllAnalysesPreserved();
  }
};

} // namespace
