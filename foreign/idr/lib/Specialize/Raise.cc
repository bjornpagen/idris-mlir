// Raising: the single consumer of a call's result moves into a clone of the
// callee. Two consumers move:
// - an apply, `idr.apply %r(xs)` or, for an action in a constructor
//   (`MkIO f`), `idr.apply` of `idr.field %r[@C, i]` (arity raising): the
//   clone takes xs too and returns what the apply returns;
// - output, `idr.io.put_str %r, %w`: the clone takes the world, writes what
//   the callee would return, and returns the next world.
// In the clone, the consumer (with its projection) moves to every tail of the
// body: the operand of its return and, through each match whose result
// reaches the return and has no other use, the yields of its regions. There
// an apply meets the `idr.con` and `idr.closure` the body built, and output
// meets the string builders, which canonicalization then takes apart. The
// clone is keyed by its callee and its consumer (a typed key per kind of
// consumer), so that a call of the callee
// in the clone whose result is consumed the same way, which inlining exposes
// where an action recurs, becomes a self call, and idr-tail-loops makes a
// tail call a loop. Its parameters are the callee's, then the consumer's
// other operands. It is counted with the clones of its callee's owner, and it
// keeps no_inline from a loop breaker: it is where the breaker's loop becomes
// a self call. Its parameters are not its callee's, so it is the owner of its
// own clones.
//
// Raising moves the callee's body from the call to its consumer, so nothing
// may run between them that could tell: the consumer and the projection are
// in the call's block, and either the call only computes (it performs no IO,
// cannot crash and returns; building actions is no IO), or every op between
// it and the consumer only computes. A callee that takes a world is never
// raised: its body would take part in the world chain. A closed call that
// idr-eval runs to the end is left to it.

#include "Facts/Facts.h"
#include "Specialize/Specializer.h"

#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Matchers.h"

using namespace mlir;

namespace idr::specialize {

namespace {

template <typename... Cases> struct Match : Cases... {
  using Cases::operator()...;
};

// The op that consumes the call's result: the apply or the output.
Operation *opOf(const Consumer &c) {
  return std::visit(Match{[](const Apply &a) -> Operation * { return a.apply; },
                          [](const ApplyField &a) -> Operation * { return a.apply; },
                          [](const Write &w) -> Operation * { return w.write; }},
                    c);
}

// The operands the clone takes after the callee's: the apply's arguments,
// or the world that output takes.
OperandRange extraOf(const Consumer &c) {
  return std::visit(Match{[](Apply a) { return a.apply.getArgs(); },
                          [](ApplyField a) { return a.apply.getArgs(); },
                          [](Write w) { return w.write->getOperands().drop_front(); }},
                    c);
}

Attribute keyOf(const Consumer &c, func::FuncOp callee) {
  MLIRContext *ctx = callee.getContext();
  StringAttr name = callee.getSymNameAttr();
  unsigned arity = callee.getNumArguments();
  return std::visit(
      Match{[&](const Apply &) -> Attribute { return KeyApplyAttr::get(ctx, name, arity); },
            [&](ApplyField a) -> Attribute {
              return KeyApplyFieldAttr::get(ctx, name, arity, a.field.getCtorAttr().getAttr(),
                                            static_cast<unsigned>(a.field.getIndex()));
            },
            [&](const Write &) -> Attribute { return KeyWriteAttr::get(ctx, name, arity); }},
      c);
}

// The function a tail value applies to after the projection `field`, when
// the value is a closure built here or a constant; null when not known.
FlatSymbolRefAttr labelOf(Value value, FieldOp field) {
  Attribute constant;
  (void)matchPattern(value, m_Constant(&constant));
  if (field) {
    StringAttr ctor = field.getCtorAttr().getAttr();
    uint64_t index = field.getIndex();
    if (auto con = value.getDefiningOp<ConOp>()) {
      if (con.getCtor().getLeafReference() != ctor || index >= con.getFields().size())
        return {};
      value = con.getFields()[static_cast<unsigned>(index)];
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
// `extraOf(c)`. An apply appends to `labels` the function each tail
// applies, null where that is not known here.
void push(Operation *term, unsigned index, const Consumer &c, Value result, ValueRange extra,
          SmallVectorImpl<FlatSymbolRefAttr> &labels) {
  Operation *consumer = opOf(c);
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
  std::visit(Match{[&](const Apply &) { labels.push_back(labelOf(value, {})); },
                   [&](const ApplyField &a) {
                     labels.push_back(labelOf(value, a.field));
                     b.clone(*a.field, map);
                   },
                   [](const Write &) {}},
             c);
  for (auto [operand, param] : llvm::zip(extraOf(c), extra))
    map.map(operand, param);
  replaceOperand(term, index, b.clone(*consumer, map)->getResults());
}

// How often a raised clone uses its parameter for the `i`th of `extra`,
// operands of the consumer: output uses its world once; an apply passes its
// argument to the label of each tail, so the quantity is theirs when they
// agree, and any number of uses when a label is not known or they differ.
Quantity extraQuantity(const Consumer &c, unsigned i, Value operand,
                       ArrayRef<func::FuncOp> labels) {
  if (std::holds_alternative<Write>(c) || labels.empty())
    return quantityOf(Attribute(), operand.getType());
  std::optional<Quantity> agreed;
  size_t args = extraOf(c).size();
  for (func::FuncOp label : labels) {
    if (!label || label.getNumArguments() < args)
      return Quantity::Many;
    Quantity q = quantityOf(label, static_cast<unsigned>(label.getNumArguments() - args + i));
    if (agreed && *agreed != q)
      return Quantity::Many;
    agreed = q;
  }
  return *agreed;
}

} // namespace

std::optional<Consumer> Specializer::consumerOf(func::CallOp call, func::FuncOp callee) {
  if (call->getNumResults() != 1 || !call->getResult(0).hasOneUse() || facts::takesWorld(callee))
    return std::nullopt;
  Value value = call->getResult(0);
  Operation *user = *value.user_begin();
  std::optional<Consumer> c;
  if (auto field = dyn_cast<FieldOp>(user)) {
    if (!field.getResult().hasOneUse())
      return std::nullopt;
    auto apply = dyn_cast<ApplyOp>(*field.getResult().user_begin());
    if (apply && apply.getCallee() == field.getResult())
      c = ApplyField{field, apply};
  } else if (auto apply = dyn_cast<ApplyOp>(user); apply && apply.getCallee() == value) {
    c = Apply{apply};
  } else if (auto write = dyn_cast<PutStrOp>(user); write && write.getStr() == value) {
    c = Write{write};
  }
  if (!c || opOf(*c)->getBlock() != call->getBlock())
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
    for (Operation *op = call->getNextNode(); op != opOf(*c); op = op->getNextNode())
      if (!facts::canMoveAcross(op))
        return std::nullopt;
  return c;
}

FailureOr<func::FuncOp> Specializer::makeRaised(func::FuncOp callee, func::CallOp call,
                                                const Consumer &c, Attribute key) {
  MLIRContext *ctx = module.getContext();
  FailureOr<func::FuncOp> made = clones.copy(callee, clones.ownerOf(callee), "raise", call);
  if (failed(made))
    return failure();
  func::FuncOp clone = *made;
  clone.removeResAttrsAttr();
  Operation *consumer = opOf(c);

  unsigned arity = clone.getNumArguments();
  SmallVector<unsigned> positions(extraOf(c).size(), arity);
  SmallVector<Type> types(extraOf(c).getTypes());
  SmallVector<DictionaryAttr> attrs(positions.size(), DictionaryAttr());
  SmallVector<Location> locs;
  for (Value operand : extraOf(c))
    locs.push_back(operand.getLoc());
  (void)clone.insertArguments(positions, types, attrs, locs);
  clone.setFunctionType(FunctionType::get(ctx, clone.getArgumentTypes(), consumer->getResultTypes()));

  auto ret = cast<func::ReturnOp>(clone.getBody().front().getTerminator());
  SmallVector<FlatSymbolRefAttr> labels;
  push(ret, 0, c, call->getResult(0), clone.getArguments().drop_front(arity), labels);
  SmallVector<func::FuncOp> functions = llvm::map_to_vector(labels, [&](FlatSymbolRefAttr name) {
    return name ? clones.symbols().lookup<func::FuncOp>(name.getAttr()) : func::FuncOp();
  });

  for (unsigned i = 0; i < arity; ++i)
    clone.setArgAttrs(i, parameterAttrs(ctx, clone.getArgAttrDict(i), i));
  for (auto [i, operand] : llvm::enumerate(extraOf(c))) {
    unsigned index = static_cast<unsigned>(i);
    clone.setArgAttrs(arity + index,
                      parameterAttrs(ctx, extraQuantity(c, index, operand, functions), arity + index));
  }
  clones.add(key, clone);
  // A clone that applies does what its callee and the labels of its tails
  // do (anything, where a label is not known); one that writes takes a
  // world, so it performs IO.
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
  Attribute key = keyOf(*c, callee);
  const Clone *clone = clones.lookup(key);
  if (!clone) {
    if (failed(makeRaised(callee, call, *c, key)))
      return failure();
    clone = clones.lookup(key);
  }
  SmallVector<std::optional<Value>> all(call.getOperands());
  llvm::append_range(all, extraOf(*c));
  Operation *consumer = opOf(*c);
  func::FuncOp fn = clone->fn;
  std::optional<SmallVector<Value>> operands = operandsFor(*clone, all);
  if (!operands || TypeRange(fn.getResultTypes()) != consumer->getResultTypes())
    return func::CallOp();
  OpBuilder b(consumer);
  auto replacement = func::CallOp::create(b, call.getLoc(), fn, *operands);
  replacement->setDiscardableAttrs(call->getDiscardableAttrDictionary());
  consumer->replaceAllUsesWith(replacement.getResults());
  consumer->erase();
  if (auto *a = std::get_if<ApplyField>(&*c))
    a->field.erase();
  call.erase();
  return replacement;
}

} // namespace idr::specialize
