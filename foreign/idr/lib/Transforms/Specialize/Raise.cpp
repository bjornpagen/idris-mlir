// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A raise node's function: the single consumer of a call's result, the
// dispatch that is all its one use does with it (through one field of it,
// `idr.field %r[@C, i]`, for an action in a constructor such as `MkIO f`,
// and through the one use of a linear value; the result may first pass a
// linear position, entered and used at once), moves into a copy of the
// callee that takes the values the consumer reads too and returns what the
// consumer returns (arity raising). In the copy, the consumer moves to
// every tail of the body: the operand of its return and, through each match
// whose result reaches the return and has no other use, the yields of its
// regions. There it meets the constructor the body built and is case of a
// known constructor, which the copy's own pipeline folds. Its parameters
// are the callee's, then the consumer's free values. Where a tail is a call
// whose result the consumer meets again, the node's own redirect walk, run
// when it is built, makes it a call of the node for that callee and this
// consumer: the node itself, where the tail is the callee's own recursion,
// which idr-tail-loops makes a loop.
//
// It is built from the key alone: the consumer is read back from the form
// the key holds, and each op it adds takes the location of the terminator
// it is pushed to.
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Parser/Parser.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::specialize::detail {

namespace {

// A match like `op` whose results have `types`, with `op`'s regions.
template <typename M>
Operation *retyped(RewriterBase &rewriter, M op, TypeRange types) {
  rewriter.setInsertionPoint(op);
  auto fresh = M::create(rewriter, op.getLoc(), types, op.getScrutinee(), op.getCases(),
                         op->getNumRegions());
  for (auto [to, from] : llvm::zip(fresh->getRegions(), op->getRegions()))
    rewriter.inlineRegionBefore(from, to, to.end());
  return fresh;
}

void replaceOperand(RewriterBase &rewriter, Operation *op, unsigned index, ValueRange values) {
  SmallVector<Value> operands(op->getOperands());
  operands.erase(operands.begin() + index);
  operands.insert(operands.begin() + index, values.begin(), values.end());
  rewriter.modifyOpInPlace(op, [&] { op->setOperands(operands); });
}

// Every op, region argument and nested op of `op` at `loc`.
void locate(Operation *op, Location loc) {
  op->walk([&](Operation *inner) {
    inner->setLoc(loc);
    for (Region &region : inner->getRegions())
      for (Block &block : region)
        for (BlockArgument arg : block.getArguments())
          arg.setLoc(loc);
  });
}

// Makes the consumer `consumer` take operand `index` of `term`, a return or
// a yield, where that value is made: through a match whose result it is
// and that has no other use, in each region that yields; otherwise right
// before `term`. `extra` stands for the consumer's free values.
void push(RewriterBase &rewriter, Operation *term, unsigned index, idr::FuncOp consumer,
          ValueRange extra) {
  Block &body = consumer.getBody().front();
  Operation *last = body.getTerminator();
  Value value = term->getOperand(index);
  auto res = dyn_cast<OpResult>(value);
  Operation *match = res ? res.getOwner() : nullptr;
  if (match && isa<MatchOp, MatchLitOp>(match) && res.hasOneUse()) {
    unsigned k = res.getResultNumber();
    for (Region &region : match->getRegions())
      if (auto yield = dyn_cast<YieldOp>(region.front().getTerminator()))
        push(rewriter, yield, k, consumer, extra);
    TypeRange types = match->getResultTypes();
    TypeRange results = last->getOperandTypes();
    SmallVector<Type> fresh(types.take_front(k));
    llvm::append_range(fresh, results);
    llvm::append_range(fresh, types.drop_front(k + 1));
    Operation *made = isa<MatchOp>(match) ? retyped(rewriter, cast<MatchOp>(match), fresh)
                                          : retyped(rewriter, cast<MatchLitOp>(match), fresh);
    unsigned n = static_cast<unsigned>(results.size());
    for (unsigned i = 0; i < match->getNumResults(); ++i)
      if (i != k)
        rewriter.replaceAllUsesWith(match->getResult(i), made->getResult(i < k ? i : i + n - 1));
    replaceOperand(rewriter, term, index, made->getResults().slice(k, n));
    rewriter.eraseOp(match);
    return;
  }
  rewriter.setInsertionPoint(term);
  IRMapping map;
  map.map(body.getArgument(0), value);
  for (auto [arg, param] : llvm::zip_equal(body.getArguments().drop_front(), extra))
    map.map(arg, param);
  for (Operation &op : body.without_terminator())
    locate(rewriter.clone(op, map), term->getLoc());
  replaceOperand(rewriter, term, index,
                 llvm::map_to_vector(last->getOperands(), [&](Value v) { return map.lookup(v); }));
}

} // namespace

FailureOr<idr::FuncOp> buildRaise(idr::FuncOp callee, KeyRaiseAttr key, StringAttr name) {
  MLIRContext *ctx = callee.getContext();
  // The form is one function, read without the verifier: it is a copy of
  // ops a verified function held, and only its ops are taken.
  ParserConfig config(ctx, /*verifyAfterParse=*/false);
  Block parsed;
  OwningOpRef<idr::FuncOp> consumer;
  if (succeeded(parseSourceString(key.getConsumer().getValue(), &parsed, config)) &&
      llvm::hasSingleElement(parsed))
    if (auto fn = dyn_cast<idr::FuncOp>(parsed.front())) {
      fn->remove();
      consumer = fn;
    }
  Region &region = callee.getBody();
  if (!consumer || !region.hasOneBlock() || !isa<idr::ReturnOp>(region.front().getTerminator()))
    return callee.emitError() << "internal error: the raise key of @" << callee.getSymName()
                              << " does not read back as a consumer of its one block";

  // The copy keeps the callee's location, instance and the facts Idris gave
  // it; what it may do is written once its component is final.
  auto clone = cast<idr::FuncOp>(callee->clone());
  clone.setSymName(name.getValue());
  clone.setPrivate();
  clone.removeEffectsAttr();
  clone.removeResAttrsAttr();

  // The consumer's free values keep their types, linear ones included.
  ArrayRef<Type> inputs = consumer->getArgumentTypes();
  unsigned arity = clone.getNumArguments();
  SmallVector<unsigned> positions(inputs.size() - 1, arity);
  SmallVector<Type> types(inputs.drop_front());
  SmallVector<DictionaryAttr> attrs(positions.size(), DictionaryAttr());
  SmallVector<Location> locs(positions.size(), clone.getLoc());
  (void)clone.insertArguments(positions, types, attrs, locs);
  clone.setFunctionType(
      FunctionType::get(ctx, clone.getArgumentTypes(), consumer->getResultTypes()));

  IRRewriter rewriter(ctx);
  auto ret = cast<idr::ReturnOp>(clone.getBody().front().getTerminator());
  push(rewriter, ret, 0, *consumer, clone.getArguments().drop_front(arity));
  return clone;
}

} // namespace idr::specialize::detail
