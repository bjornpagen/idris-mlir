// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A raise copy's function: the single consumer of a call's result, the
// dispatch that is all its one use does with it, moves into a copy of the
// callee that takes the values the consumer reads too and returns what the
// consumer returns (arity raising). In the copy the consumer moves to
// every tail of the body: the operand of its return and, through each
// match whose result reaches the return and has no other use, the yields
// of its regions. There it meets the constructor the body built and is a
// case of a known constructor, which the copy's own simplification folds.
// Where a tail is a call whose result the consumer meets again, the copy's
// own redirect makes it a call of the copy for that callee and this
// consumer: the copy itself where the tail is the callee's own recursion.
//
// It is built from the key alone: the consumer is the form the key names,
// read and never written, and each op it adds is placed at the consumer's
// own op called from the tail it is pushed to.

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Remake.h"
#include "idr/Transforms/Specialize/Calls.h"

#include "mlir/IR/IRMapping.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::specialize::detail {

namespace {

void replaceOperand(RewriterBase &rewriter, Operation *op, unsigned index, ValueRange values) {
  SmallVector<Value> operands(op->getOperands());
  operands.erase(operands.begin() + index);
  operands.insert(operands.begin() + index, values.begin(), values.end());
  rewriter.modifyOpInPlace(op, [&] { op->setOperands(operands); });
}

// Every op of `op`, and the block arguments of its regions, at `loc`
// called from `site`.
void placeAt(Operation *op, Location site) {
  op->walk([&](Operation *inner) {
    inner->setLoc(CallSiteLoc::get(inner->getLoc(), site));
    for (Region &region : inner->getRegions())
      for (Block &block : region)
        for (BlockArgument arg : block.getArguments())
          arg.setLoc(CallSiteLoc::get(arg.getLoc(), site));
  });
}

// One step of pushing the consumer: take operand `index` of `term`, a
// return or a yield, where its value is made; or, once every region of a
// match has taken it, remake the match with the consumer's results in
// place of its result `k`.
struct Push {
  Operation *term;
  unsigned index;
};
struct Remake {
  Operation *match;
  unsigned k;
  Operation *term;
  unsigned index;
};
using Step = std::variant<Push, Remake>;

} // namespace

FuncOp buildRaise(FuncOp callee, const RaiseKey &key, StringAttr name, const Forms &forms) {
  MLIRContext *ctx = callee.getContext();
  FuncOp consumer = forms.at(key.form);
  Block &body = consumer.getBody().front();
  Operation *last = body.getTerminator();

  // The copy keeps the callee's location, instance and the facts Idris
  // gave it; its row is derived when its component is final.
  auto clone = cast<FuncOp>(callee->clone());
  clone.setSymName(name.getValue());

  // The consumer's free values keep their types, quantities included. The
  // copy returns what the consumer returns: the callee's results go, with
  // what its signature states of them, and the consumer's take their place.
  ArrayRef<Type> inputs = consumer.getArgumentTypes();
  unsigned arity = clone.getNumArguments();
  SmallVector<unsigned> positions(inputs.size() - 1, arity);
  SmallVector<Type> types(inputs.drop_front());
  SmallVector<DictionaryAttr> attrs(positions.size(), DictionaryAttr());
  SmallVector<Location> locs(positions.size(), clone.getLoc());
  (void)clone.insertArguments(positions, types, attrs, locs);
  (void)clone.eraseResults(llvm::BitVector(clone.getNumResults(), true));
  TypeRange returned = consumer.getResultTypes();
  (void)clone.insertResults(SmallVector<unsigned>(returned.size(), 0), returned,
                            SmallVector<DictionaryAttr>(returned.size(), DictionaryAttr()));
  ValueRange extra = clone.getArguments().drop_front(arity);

  // The callee returns: its raise was asked for only then (decide).
  IRRewriter rewriter(ctx);
  SmallVector<Step> work{Push{clone.getBody().front().getTerminator(), 0}};
  while (!work.empty()) {
    Step step = work.pop_back_val();
    idr::match(
        step,
        [&](const Remake &remake) {
          Operation *match = remake.match;
          TypeRange old = match->getResultTypes();
          TypeRange results = last->getOperandTypes();
          SmallVector<Type> fresh(old.take_front(remake.k));
          llvm::append_range(fresh, results);
          llvm::append_range(fresh, old.drop_front(remake.k + 1));
          Operation *made = idr::remakeOp(rewriter, match, match->getOperands(), fresh);
          auto n = static_cast<unsigned>(results.size());
          for (unsigned i = 0; i < match->getNumResults(); ++i)
            if (i != remake.k)
              rewriter.replaceAllUsesWith(match->getResult(i),
                                          made->getResult(i < remake.k ? i : i + n - 1));
          replaceOperand(rewriter, remake.term, remake.index, made->getResults().slice(remake.k, n));
          rewriter.eraseOp(match);
        },
        [&](const Push &push) {
          Value value = push.term->getOperand(push.index);
          auto result = dyn_cast<OpResult>(value);
          Operation *match = result ? result.getOwner() : nullptr;
          if (match && isa<MatchOpInterface>(match) && result.hasOneUse()) {
            unsigned k = result.getResultNumber();
            work.push_back(Remake{match, k, push.term, push.index});
            for (Region &region : match->getRegions())
              for (Block &block : region)
                if (block.mightHaveTerminator())
                  if (Operation *yield = block.getTerminator();
                      yield->hasTrait<OpTrait::ReturnLike>())
                    work.push_back(Push{yield, k});
            return;
          }
          rewriter.setInsertionPoint(push.term);
          IRMapping map;
          map.map(body.getArgument(0), value);
          for (auto [arg, param] : llvm::zip_equal(body.getArguments().drop_front(), extra))
            map.map(arg, param);
          for (Operation &op : body.without_terminator())
            placeAt(rewriter.clone(op, map), push.term->getLoc());
          replaceOperand(rewriter, push.term, push.index,
                         llvm::map_to_vector(last->getOperands(),
                                             [&](Value v) { return map.lookup(v); }));
        });
  }
  return clone;
}

} // namespace idr::specialize::detail
