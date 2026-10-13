// idr-effects: `effects` on every idr.func, from the Effects analysis, and
// on every idr.call, from its callee's and from what the closures it is
// given may do when applied. A call carries its own fact for two reasons.
// What MLIR asks of a call (whether canonicalize may erase it, CSE merge
// it, LICM hoist it) is asked of the op alone, with no symbol table in
// hand, so the callee's fact must already be on it. And a closure's effect
// counts where it is passed as well as where it is made: a call of a total,
// pure function given a closure that crashes may crash, which the callee's
// fact cannot say.
//
// The full set is never written: an absent fact means it. The calls are the
// References' sites, so no body is walked here. The functions separate,
// each written by a worker of its own that reads only the analyses and its
// own ops, so the IR left is the same for every thread count.
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Effects.h"
#include "idr/Analysis/Effects.h"
#include "idr/Analysis/Holds.h"
#include "idr/Analysis/References.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Threading.h"

namespace idr {
#define GEN_PASS_DEF_IDREFFECTS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

// What one worker did to its function.
struct Slot {
  unsigned io = 0;
  unsigned crash = 0;
  unsigned diverge = 0;
  bool changed = false;
};

// Gives `op` the fact `effect`, from the values built before the workers
// started; the full set is the attribute's absence. Whether it changed.
template <typename OpT>
bool record(IRRewriter &rewriter, OpT op, idr::Effect effect, ArrayRef<idr::EffectAttr> values) {
  idr::EffectAttr want =
      effect == idr::anyEffect ? idr::EffectAttr() : values[static_cast<uint32_t>(effect)];
  if (op.getEffectsAttr() == want)
    return false;
  rewriter.modifyOpInPlace(op, [&] {
    if (want)
      op.setEffectsAttr(want);
    else
      op.removeEffectsAttr();
  });
  return true;
}

struct IdrEffectsPass : idr::impl::IdrEffectsBase<IdrEffectsPass> {
  void runOnOperation() override {
    MLIRContext *context = &getContext();
    const idr::Effects &effects = getAnalysis<idr::Effects>();
    const idr::References &references = getAnalysis<idr::References>();

    // Every value below the full set, made here: a worker makes no
    // attribute.
    SmallVector<idr::EffectAttr> values;
    for (uint32_t bits = 0; bits < static_cast<uint32_t>(idr::anyEffect); ++bits)
      values.push_back(idr::EffectAttr::get(context, static_cast<idr::Effect>(bits)));

    ArrayRef<idr::FuncOp> fns = references.functions();
    SmallVector<Slot> slots(fns.size());
    parallelFor(context, 0, fns.size(), [&](size_t at) {
      idr::FuncOp fn = fns[at];
      Slot &slot = slots[at];
      IRRewriter rewriter(context);
      idr::Effect own = effects.of(fn);
      slot.io = idr::bitEnumContainsAny(own, idr::Effect::io);
      slot.crash = idr::bitEnumContainsAny(own, idr::Effect::crash);
      slot.diverge = idr::bitEnumContainsAny(own, idr::Effect::diverge);
      slot.changed |= record(rewriter, fn, own, values);
      // An op's sites are consecutive, and an idr.call's own is its first.
      Operation *previous = nullptr;
      for (const idr::References::Site &site : references.of(fn)) {
        if (site.at == previous)
          continue;
        previous = site.at;
        auto call = dyn_cast<idr::CallOp>(site.at);
        if (!call)
          continue;
        idr::Effect given = effects.of(site.target);
        for (Value arg : call.getArgs()) {
          if (given == idr::anyEffect)
            break;
          given |= effects.passed(arg);
        }
        slot.changed |= record(rewriter, call, given, values);
      }
    });

    bool changed = false;
    for (const Slot &slot : slots) {
      numIO += slot.io;
      numCrash += slot.crash;
      numDiverge += slot.diverge;
      changed |= slot.changed;
    }
    // Every function and call already carried these effects.
    if (!changed)
      return markAllAnalysesPreserved();
    // Only facts on functions and calls changed, which none of these reads.
    markAnalysesPreserved<idr::References, idr::Effects, idr::Holds, idr::TypeGraph, idr::Layouts,
                          SymbolTable>();
  }
};

} // namespace
