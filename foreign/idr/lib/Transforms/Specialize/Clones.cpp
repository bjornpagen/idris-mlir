// Making a clone, the facts it starts with, and the boundary between two
// generations of a run of idr-specialize.
#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Specialize.h"
#include "idr/Transforms/Specialize.h"
#include "idr/Analysis/Effects.h"
#include "idr/Analysis/Holds.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Twine.h"

using namespace mlir;

namespace idr::specialize {

// A copy of `from` for `owner`, named `<owner>.spec<n>` or
// `<owner>.raise<n>` and inserted at the module's end through the table,
// which renames a collision; the error `unsupported (compile-time budget)`
// at `at` once `owner` has had kClonesPerOwner. The copy keeps its origin's
// location, instance and the facts Idris and the loop breakers gave it; an
// origin that is a clone carries its own clone fact, which the copy does
// not.
FailureOr<idr::FuncOp> makeClone(RewriterBase &rewriter, idr::FuncOp from, StringAttr owner,
                                 CloneTable::Kind kind, Operation *at, SymbolTable &symbols,
                                 const CloneTable &clones) {
  if (clones.count(owner) + 1 > CloneTable::kClonesPerOwner)
    return at->emitError() << "unsupported (compile-time budget): specializing @"
                           << owner.getValue() << " made more than "
                           << CloneTable::kClonesPerOwner << " clones of it";
  bool raise = kind == CloneTable::Kind::Raise;
  rewriter.setInsertionPointToEnd(from->getBlock());
  auto clone = cast<idr::FuncOp>(rewriter.clone(*from));
  clone.removeCloneAttr();
  if (raise)
    clone.removeResAttrsAttr();
  unsigned n = clones.count(owner, kind) + 1;
  clone.setSymName((owner.getValue() + (raise ? ".raise" : ".spec") + Twine(n)).str());
  clone.setPrivate();
  // The copy is already at the module's end; the table records it and
  // renames it when the name is taken.
  symbols.insert(clone);
  return clone;
}

// What idr-effects would find of a clone that runs the body of `origin`
// with closures of `labels` in it: what `origin` and `labels` may do
// together (a null label, one not known, may do anything), and IO if it
// takes a world. Its totality is its origin's, which it was copied with:
// its body loops where its origin's does. The full set is no attribute.
void giveFirstFacts(idr::FuncOp clone, idr::FuncOp origin, ArrayRef<idr::FuncOp> labels,
                    const Holds &holds) {
  idr::Effect effects = Effects::declared(origin);
  for (idr::FuncOp label : labels)
    effects = effects | Effects::declared(label);
  if (llvm::any_of(clone.getArgumentTypes(), [&](Type type) { return holds.mayHoldWorld(type); }))
    effects = effects | idr::Effect::io;
  if (effects == anyEffect)
    clone.removeEffectsAttr();
  else
    clone.setEffectsAttr(idr::EffectAttr::get(clone.getContext(), effects));
}

// The boundary's work on one clone, on a worker: the clone is simplified,
// then its calls are read. Its own recursive call folds to its key, which
// the table already holds, so it is a self call when it is processed. The
// worker writes nothing but the clone and its slot, and reads the table and
// other functions' signatures, which nothing writes while it runs.
Slot canonicalizeAndCollect(idr::FuncOp clone, const FrozenRewritePatternSet &patterns,
                            const SymbolTable &symbols) {
  (void)applyPatternsGreedily(clone, patterns);
  Slot slot;
  std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&clone.getBody());
  if (!uses)
    return slot;
  for (const SymbolTable::SymbolUse &use : *uses) {
    auto fn = symbols.lookup<idr::FuncOp>(use.getSymbolRef().getRootReference());
    if (!fn)
      continue;
    slot.refers = true;
    if (auto call = dyn_cast<idr::CallOp>(use.getUser());
        call && use.getSymbolRef() == call.getCalleeAttr())
      slot.calls.push_back({call, fn});
  }
  return slot;
}

// The boundary's serial half, in the order the clones were made. A clone
// runs its callee's loop, so it breaks the loop where its callee does: a
// call of the breaker in it becomes a call of it once inlining, in this
// round or a later one, shows what consumes the call. Inlined before that,
// it would put the call back into its caller, for which it would be made
// again: the loop would unroll once every two rounds, for ever. It keeps
// the no_inline it was copied with, unless no call in it can come back to
// it: it unrolls a decreasing parameter, whose keys shrink along the chain
// of clones and whose chain, inlined, shows the static shape to its
// consumer, or it refers to no function. The calls the slots hold are the
// next generation.
SmallVector<Call> settle(ArrayRef<Entry> made, ArrayRef<Slot> slots) {
  SmallVector<Call> next;
  for (auto [entry, slot] : llvm::zip(made, slots)) {
    if (idr::FuncOp clone = entry.clone; entry.unrolls || !slot.refers)
      clone.setNoInline(false);
    llvm::append_range(next, slot.calls);
  }
  return next;
}

} // namespace idr::specialize
