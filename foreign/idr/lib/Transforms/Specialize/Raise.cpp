// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Raising: the single consumer of a call's result, an apply of it (of one
// field of it, `idr.field %r[@C, i]`, for an action in a constructor such
// as `MkIO f`, and through the one use of a linear value; the result may
// first pass a linear position, entered and used at once), moves into a
// clone of the callee that takes the apply's arguments too and returns what
// the apply returns (arity raising). In the clone, the apply (with its
// projection) moves to every tail of the body: the operand of its return
// and, through each match whose result reaches the return and has no other
// use, the yields of its regions. There it meets the `idr.con` and
// `idr.closure` the body built. The clone is keyed by its callee and its
// consumer, and idr-tail-loops makes a tail call of it a loop. Its
// parameters are the callee's, then the apply's arguments. It is counted
// with the clones of its callee's owner, and it breaks its callee's loop
// where its callee does: it is where the breaker's loop becomes a self
// call. Its parameters are not its callee's, so it is the owner of its own
// clones.
#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Specialize.h"
#include "idr/Transforms/Specialize.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Matchers.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::specialize {

namespace {

// The function a tail value applies to after the projection `field` (none
// when null), when the value is a closure built here or a constant, seen
// through its entry into a linear type; null when not known.
FlatSymbolRefAttr labelOf(Value value, FieldOp field) {
  auto seeThrough = [](Value v) {
    auto enter = v.getDefiningOp<LinEnterOp>();
    return enter ? enter.getValue() : v;
  };
  value = seeThrough(value);
  Attribute constant;
  (void)matchPattern(value, m_Constant(&constant));
  if (field) {
    StringAttr ctor = field.getCtorAttr().getAttr();
    uint64_t index = field.getIndex();
    if (auto con = value.getDefiningOp<ConOp>()) {
      if (con.getCtor().getLeafReference() != ctor || index >= con.getFields().size())
        return {};
      value = seeThrough(con.getFields()[static_cast<unsigned>(index)]);
      constant = {};
      (void)matchPattern(value, m_Constant(&constant));
    } else if (auto data = dyn_cast_or_null<ConAttr>(constant)) {
      // A run's cells leave out the spine, so its constructor has one field
      // more than a cell holds. The one field is read on its own, which off
      // the spine builds nothing of the rest of the run.
      size_t arity =
          data.isRun() ? data.getRunCells().front().size() + 1 : data.getFields().size();
      if (data.getCtor().getLeafReference() != ctor || index >= arity)
        return {};
      value = {};
      constant = data.getField(static_cast<unsigned>(index));
    } else {
      return {};
    }
  }
  if (auto closure = value ? value.getDefiningOp<ClosureOp>() : ClosureOp())
    return closure.getCalleeAttr();
  if (auto closure = dyn_cast_or_null<ClosureAttr>(constant))
    return closure.getCallee();
  return {};
}

// A match like `op` whose results have `types`, with `op`'s regions.
template <typename M>
Operation *retyped(RewriterBase &rewriter, M op, TypeRange types) {
  rewriter.setInsertionPoint(op);
  auto fresh = M::create(rewriter, op.getLoc(), types, op.getScrutinee(), op.getCases(),
                         op->getNumRegions());
  fresh->setDiscardableAttrs(op->getDiscardableAttrDictionary());
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

// Makes `c` consume operand `index` of `term`, a return or a yield, where
// that value is made: through a match whose result it is and that has no
// other use, in each region that yields; otherwise right before `term`.
// `result` is the call's result that `c` consumed, and `extra` stands for
// the apply's arguments. `labels` gets the function each tail applies, null
// where that is not known here.
void push(RewriterBase &rewriter, Operation *term, unsigned index, Consumer c,
          Value result, ValueRange extra, SmallVectorImpl<FlatSymbolRefAttr> &labels) {
  Operation *consumer = c.apply;
  Value value = term->getOperand(index);
  auto res = dyn_cast<OpResult>(value);
  Operation *match = res ? res.getOwner() : nullptr;
  if (match && isa<MatchOp, MatchLitOp>(match) && res.hasOneUse()) {
    unsigned k = res.getResultNumber();
    for (Region &region : match->getRegions())
      if (auto yield = dyn_cast<YieldOp>(region.front().getTerminator()))
        push(rewriter, yield, k, c, result, extra, labels);
    TypeRange types = match->getResultTypes();
    SmallVector<Type> fresh(types.take_front(k));
    llvm::append_range(fresh, consumer->getResultTypes());
    llvm::append_range(fresh, types.drop_front(k + 1));
    Operation *made = isa<MatchOp>(match) ? retyped(rewriter, cast<MatchOp>(match), fresh)
                                          : retyped(rewriter, cast<MatchLitOp>(match), fresh);
    unsigned n = consumer->getNumResults();
    for (unsigned i = 0; i < match->getNumResults(); ++i)
      if (i != k)
        rewriter.replaceAllUsesWith(match->getResult(i), made->getResult(i < k ? i : i + n - 1));
    replaceOperand(rewriter, term, index, made->getResults().slice(k, n));
    rewriter.eraseOp(match);
    return;
  }
  rewriter.setInsertionPoint(term);
  IRMapping map;
  map.map(result, value);
  if (c.exit)
    map.map(c.exit.getResult(), value);
  labels.push_back(labelOf(value, c.field));
  if (c.field)
    rewriter.clone(*c.field, map);
  if (c.use)
    rewriter.clone(*c.use, map);
  for (auto [operand, param] : llvm::zip(c.apply.getArgs(), extra))
    map.map(operand, param);
  replaceOperand(rewriter, term, index, rewriter.clone(*consumer, map)->getResults());
}

} // namespace

FailureOr<const Clone *> Specializer::makeRaised(idr::FuncOp callee, idr::CallOp call,
                                                 Consumer c, Attribute key) {
  MLIRContext *ctx = module.getContext();
  FailureOr<idr::FuncOp> copy =
      makeClone(rewriter, callee, clones.ownerOf(callee.getSymNameAttr()), CloneTable::Kind::Raise,
                call, symbols, clones);
  if (failed(copy))
    return failure();
  idr::FuncOp clone = *copy;
  OperandRange extra = c.apply.getArgs();

  // The apply's arguments keep their types, linear ones included.
  unsigned arity = clone.getNumArguments();
  SmallVector<unsigned> positions(extra.size(), arity);
  SmallVector<Type> types(extra.getTypes());
  SmallVector<DictionaryAttr> attrs(positions.size(), DictionaryAttr());
  SmallVector<Location> locs;
  for (Value operand : extra)
    locs.push_back(operand.getLoc());
  (void)clone.insertArguments(positions, types, attrs, locs);
  clone.setFunctionType(FunctionType::get(ctx, clone.getArgumentTypes(), c.apply.getResultTypes()));

  auto ret = cast<idr::ReturnOp>(clone.getBody().front().getTerminator());
  SmallVector<FlatSymbolRefAttr> labels;
  push(rewriter, ret, 0, c, call->getResult(0), clone.getArguments().drop_front(arity), labels);
  SmallVector<idr::FuncOp> functions = llvm::map_to_vector(labels, [&](FlatSymbolRefAttr name) {
    return name ? symbols.lookup<idr::FuncOp>(name.getAttr()) : idr::FuncOp();
  });

  // The clone does what its callee and the labels of its tails do
  // (anything, where a label is not known).
  giveFirstFacts(clone, callee, functions, holds);
  clone.setCloneAttr(CloneAttr::get(ctx, FlatSymbolRefAttr::get(clone.getSymNameAttr()), key));
  const Clone &added = clones.add(clone);
  made.push_back({clone, /*unrolls=*/false});
  ++stats.raised;
  changed = true;
  return &added;
}

FailureOr<Specializer::Raised> Specializer::raise(idr::CallOp call, idr::FuncOp callee) {
  // A callee that never returns has no closure to raise.
  if (!callee || callee.isExternal() || !callee.getBody().hasOneBlock() ||
      !isa<idr::ReturnOp>(callee.getBody().front().getTerminator()))
    return Raised{};
  std::optional<Consumer> c = consumerOf(call, holds);
  if (!c)
    return Raised{};
  // Making the clone and calling it is one action, which a debug counter
  // may skip: then there is no clone and the call and its consumer stay.
  FailureOr<Raised> result = Raised{};
  support::perform<RaiseAction>(call, [&] {
    Attribute key = raiseKey(call, *c);
    const Clone *clone = clones.lookup(key);
    if (!clone) {
      FailureOr<const Clone *> fresh = makeRaised(callee, call, *c, key);
      if (failed(fresh)) {
        result = failure();
        return;
      }
      clone = *fresh;
    }
    SmallVector<Value> operands(call.getArgs());
    llvm::append_range(operands, c->apply.getArgs());
    idr::FuncOp fn = clone->fn;
    if (std::optional<idr::CallOp> replacement = redirect(rewriter, call, *clone, operands, c)) {
      changed = true;
      result = Raised{*replacement, fn};
    }
  });
  return result;
}

} // namespace idr::specialize
