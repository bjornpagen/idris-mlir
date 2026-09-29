// Raising: the single consumer of a call's result, an apply of it (of one
// field of it, `idr.field %r[@C, i]`, for an action in a constructor such as
// `MkIO f`, and through the one use of a linear value; the result may first
// pass a linear position, entered and used at once), moves into a clone
// of the callee that takes the apply's arguments too and returns what the
// apply returns (arity raising). In the clone, the apply (with its
// projection) moves to every tail of the body: the operand of its return
// and, through each match whose result reaches the return and has no other
// use, the yields of its regions. There it meets the `idr.con` and
// `idr.closure` the body built. The clone is keyed by its callee and its
// consumer, so that a call of the callee in the clone whose result is
// consumed the same way, which inlining exposes where an action recurs,
// becomes a self call, and idr-tail-loops makes a tail call a loop. Its
// parameters are the callee's, then the apply's arguments. It is counted
// with the clones of its callee's owner, and it keeps no_inline from a loop
// breaker: it is where the breaker's loop becomes a self call. Its
// parameters are not its callee's, so it is the owner of its own clones.
//
// Raising moves the callee's body from the call to its consumer, so nothing
// may run between them that could tell: the consumer and the projection are
// in the call's block, and either the call only computes (it performs no IO,
// cannot crash and returns; building actions is no IO), or every op between
// it and the consumer only computes. A callee that takes a world is never
// raised: its body would take part in the world chain. A closed call that
// idr-eval runs to the end is left to it.

#include "Support/Actions.h"
#include "Specialize/Specializer.h"

#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Matchers.h"

import idr.facts;

using namespace mlir;

namespace idr::specialize {

namespace {

Attribute keyOf(Consumer c, func::FuncOp callee) {
  MLIRContext *ctx = callee.getContext();
  StringAttr name = callee.getSymNameAttr();
  unsigned arity = callee.getNumArguments();
  // Whether a linear value is used on the way follows from the types, so
  // the key need not say.
  if (!c.field)
    return KeyApplyAttr::get(ctx, name, arity);
  return KeyApplyFieldAttr::get(ctx, name, arity, c.field.getCtorAttr().getAttr(),
                                static_cast<unsigned>(c.field.getIndex()));
}

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
      if (data.getCtor().getLeafReference() != ctor || index >= data.getFields().size())
        return {};
      value = {};
      constant = data.getFields()[static_cast<unsigned>(index)];
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
template <typename M> Operation *retyped(OpBuilder &b, M op, TypeRange types) {
  auto fresh =
      M::create(b, op.getLoc(), types, op.getScrutinee(), op.getCases(), op->getNumRegions());
  fresh->setDiscardableAttrs(op->getDiscardableAttrDictionary());
  for (auto [to, from] : llvm::zip(fresh->getRegions(), op->getRegions()))
    to.takeBody(from);
  return fresh;
}

void replaceOperand(Operation *op, unsigned index, ValueRange values) {
  SmallVector<Value> operands(op->getOperands());
  operands.erase(operands.begin() + index);
  operands.insert(operands.begin() + index, values.begin(), values.end());
  op->setOperands(operands);
}

// Makes `c` consume operand `index` of `term`, a return or a yield, where
// that value is made: through a match whose result it is and that has no
// other use, in each region that yields; otherwise right before `term`.
// `result` is the call's result that `c` consumed, and `extra` stands for
// the apply's arguments. `labels` gets the function each tail applies, null
// where that is not known here.
void push(Operation *term, unsigned index, Consumer c, Value result, ValueRange extra,
          SmallVectorImpl<FlatSymbolRefAttr> &labels) {
  Operation *consumer = c.apply;
  Value value = term->getOperand(index);
  auto res = dyn_cast<OpResult>(value);
  Operation *match = res ? res.getOwner() : nullptr;
  if (match && isa<MatchOp, MatchLitOp>(match) && res.hasOneUse()) {
    unsigned k = res.getResultNumber();
    for (Region &region : match->getRegions())
      if (auto yield = dyn_cast<YieldOp>(region.front().getTerminator()))
        push(yield, k, c, result, extra, labels);
    TypeRange types = match->getResultTypes();
    SmallVector<Type> fresh(types.take_front(k));
    llvm::append_range(fresh, consumer->getResultTypes());
    llvm::append_range(fresh, types.drop_front(k + 1));
    OpBuilder b(match);
    Operation *made = isa<MatchOp>(match) ? retyped(b, cast<MatchOp>(match), fresh)
                                          : retyped(b, cast<MatchLitOp>(match), fresh);
    unsigned n = consumer->getNumResults();
    for (unsigned i = 0; i < match->getNumResults(); ++i)
      if (i != k)
        match->getResult(i).replaceAllUsesWith(made->getResult(i < k ? i : i + n - 1));
    replaceOperand(term, index, made->getResults().slice(k, n));
    match->erase();
    return;
  }
  OpBuilder b(term);
  IRMapping map;
  map.map(result, value);
  if (c.exit)
    map.map(c.exit.getResult(), value);
  labels.push_back(labelOf(value, c.field));
  if (c.field)
    b.clone(*c.field, map);
  if (c.use)
    b.clone(*c.use, map);
  for (auto [operand, param] : llvm::zip(c.apply.getArgs(), extra))
    map.map(operand, param);
  replaceOperand(term, index, b.clone(*consumer, map)->getResults());
}

} // namespace

std::optional<Consumer> Specializer::consumerOf(func::CallOp call, func::FuncOp callee) {
  if (call->getNumResults() != 1 || !call->getResult(0).hasOneUse() || facts::takesWorld(callee))
    return std::nullopt;
  // The only user of `v`, if it has one.
  auto next = [](Value v) { return v.hasOneUse() ? *v.user_begin() : nullptr; };
  Value value = call->getResult(0);
  Operation *user = next(value);
  auto enter = dyn_cast<LinEnterOp>(user);
  auto exit = enter ? dyn_cast_or_null<LinUseOp>(next(enter.getResult())) : LinUseOp();
  if (exit)
    user = next(value = exit.getResult());
  else
    enter = nullptr;
  auto field = dyn_cast_or_null<FieldOp>(user);
  if (field)
    user = next(value = field.getResult());
  auto use = dyn_cast_or_null<LinUseOp>(user);
  if (use)
    user = next(value = use.getResult());
  auto apply = dyn_cast_or_null<ApplyOp>(user);
  if (!apply || apply.getCallee() != value || apply->getBlock() != call->getBlock())
    return std::nullopt;
  // idr-eval evaluates this call to the end, and its consumer then folds. A
  // closed call of partial code it evaluates only within a budget, so that
  // call is raised like any other; the raised call is closed too when the
  // consumer's operands are, and idr-eval evaluates it instead.
  if (std::optional<facts::Evaluation> evaluation = facts::canEvaluate(call, clones.symbols());
      evaluation && evaluation->total)
    return std::nullopt;
  // A call that only computes may run later, after anything between it and
  // its consumer; any other only after ops that only compute.
  if (!facts::canMoveAcross(call))
    for (Operation *op = call->getNextNode(); op != apply; op = op->getNextNode())
      if (!facts::canMoveAcross(op))
        return std::nullopt;
  return Consumer{enter, exit, field, use, apply};
}

FailureOr<func::FuncOp> Specializer::makeRaised(func::FuncOp callee, func::CallOp call,
                                                Consumer c, Attribute key) {
  MLIRContext *ctx = module.getContext();
  FailureOr<func::FuncOp> made = clones.copy(callee, clones.ownerOf(callee), "raise", call);
  if (failed(made))
    return failure();
  func::FuncOp clone = *made;
  clone.removeResAttrsAttr();
  OperandRange extra = c.apply.getArgs();

  unsigned arity = clone.getNumArguments();
  SmallVector<unsigned> positions(extra.size(), arity);
  SmallVector<Type> types(extra.getTypes());
  SmallVector<DictionaryAttr> attrs(positions.size(), DictionaryAttr());
  SmallVector<Location> locs;
  for (Value operand : extra)
    locs.push_back(operand.getLoc());
  (void)clone.insertArguments(positions, types, attrs, locs);
  clone.setFunctionType(FunctionType::get(ctx, clone.getArgumentTypes(), c.apply.getResultTypes()));

  auto ret = cast<func::ReturnOp>(clone.getBody().front().getTerminator());
  SmallVector<FlatSymbolRefAttr> labels;
  push(ret, 0, c, call->getResult(0), clone.getArguments().drop_front(arity), labels);
  SmallVector<func::FuncOp> functions = llvm::map_to_vector(labels, [&](FlatSymbolRefAttr name) {
    return name ? clones.symbols().lookup<func::FuncOp>(name.getAttr()) : func::FuncOp();
  });

  // The apply's arguments keep their types, linear ones included.
  for (unsigned i = 0; i < clone.getNumArguments(); ++i)
    clone.setArgAttrs(i, parameterAttrs(ctx, i, clone.getArgAttrDict(i)));
  clones.add(key, clone);
  // The clone does what its callee and the labels of its tails do
  // (anything, where a label is not known).
  facts::inherit(clone, callee, functions);
  canonicalize(clone);
  work.push_back(clone);
  ++stats.raised;
  return clone;
}

FailureOr<func::CallOp> Specializer::raise(func::CallOp call) {
  auto callee = clones.symbols().lookup<func::FuncOp>(call.getCalleeAttr().getAttr());
  if (!callee || callee.isExternal())
    return func::CallOp();
  std::optional<Consumer> c = consumerOf(call, callee);
  if (!c)
    return func::CallOp();
  // Making the clone and calling it is one action, which a debug counter
  // may skip: then there is no clone and the call and its consumer stay.
  FailureOr<func::CallOp> result = func::CallOp();
  perform<RaiseAction>(call, [&] {
    Attribute key = keyOf(*c, callee);
    const Clone *clone = clones.lookup(key);
    if (!clone) {
      if (failed(makeRaised(callee, call, *c, key))) {
        result = failure();
        return;
      }
      clone = clones.lookup(key);
    }
    SmallVector<std::optional<Value>> all(call.getOperands());
    llvm::append_range(all, c->apply.getArgs());
    func::FuncOp fn = clone->fn;
    std::optional<SmallVector<Value>> operands = operandsFor(*clone, all);
    if (!operands || TypeRange(fn.getResultTypes()) != c->apply.getResultTypes())
      return;
    OpBuilder b(c->apply);
    auto replacement = func::CallOp::create(b, call.getLoc(), fn, *operands);
    replacement->setDiscardableAttrs(call->getDiscardableAttrDictionary());
    c->apply->replaceAllUsesWith(replacement.getResults());
    c->apply->erase();
    if (c->use)
      c->use.erase();
    if (c->field)
      c->field.erase();
    if (c->exit) {
      c->exit.erase();
      c->enter.erase();
    }
    call.erase();
    result = replacement;
  });
  return result;
}

} // namespace idr::specialize
