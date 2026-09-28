// idr-specialize: specialization on constant-like arguments (ELIM-SPEC-1,
// docs/cutover.md 6.3 and 7.3).
//
// An argument's pattern is its static shape: a constant is itself, an
// `idr.con` or `idr.closure` is built over the patterns of its operands (the
// partially static values of 7.3), and anything else is a hole, a runtime
// leaf. An erased argument is always a hole: erased is not constant. A call
// is specialized when some argument has a static shape and some non-erased
// argument has a runtime leaf; a closed call is left to idr-eval, and is
// never specialized (7.4). The clone for (callee, patterns) substitutes each
// static shape into the callee's body, and its parameters are the runtime
// leaves in order. Clones are shared through that key, named
// `@<origin>$spec$<n>` with n counting the origin's clones in the order they
// are first requested (FE-DET-1), and appended to the module, so the walk
// over the module's functions reaches them and specializes their calls in
// turn, until no call is left to specialize.
//
// In a clone's call of its own origin, a static argument that changed and
// that the callee never takes apart is generalized to a runtime value (an
// accumulator: `run (n - 1) (advance s)`); one it matches on keeps its value
// (a counter). Each clone is canonicalized when it is made, so a chain of
// clones on a counter is made in one run.
//
// Two things stop a specialization. A clone that calls its own origin with
// static arguments that grow, each the clone's own pattern or containing it
// and one strictly (`iter (\y => f (f y))`), would clone forever, so the call
// stays; each clone keeps the patterns it was made for (idr.spec_key), so
// that later rounds see the growth too. And the clone limit, counted per original callee over the whole
// compilation (the count is kept on the module as idr.clone_counts, so that
// rounds of idr-simplify share it), bounds what growth in other shapes
// makes. A stopped call gets a Missed remark; it and its callee get
// idr.spec_stopped, so that later runs leave the call alone and
// idr-check-profile reports PROF-HEAP-4 for a closure that survives into
// the callee.
//
// Clones can close new cycles of calls; idr-loop-breakers cuts them at the
// start of the next round (OPT-PIPE-3), and clones of a breaker inherit it.
//
// A clone is total if its origin is and so is every function its static
// arguments name; the same holds for purity and, reversed, for "may crash",
// when idr-effects has computed those facts (IDR-FACT-1).

#include "idr/Idr.h"

#include "mlir/AsmParser/AsmParser.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/Remarks.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/Support/FormatVariadic.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRSPECIALIZE
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

constexpr StringLiteral cloneCounts = "idr.clone_counts";
constexpr StringLiteral originAttr = "idr.origin";
constexpr StringLiteral stopped = "idr.spec_stopped";
constexpr StringLiteral keyAttr = "idr.spec_key";

// One argument of a call: its pattern and its runtime leaves, in order.
//
// A pattern is a constant attribute, a hole (`unit`) for a runtime leaf, or,
// for an `idr.con` or `idr.closure` with a runtime leaf below it, a node
// `["con" | "closure", symbol, [parts]]`. An `idr.con` or `idr.closure` of
// constants is the constant it folds to, so it keys the same clone.
struct Shape {
  Attribute pattern;
  SmallVector<Value> leaves;
};

bool isHole(Attribute pattern) { return isa<UnitAttr>(pattern); }
bool isNode(Attribute pattern) { return isa<ArrayAttr>(pattern); }
bool isConstant(Attribute pattern) { return !isHole(pattern) && !isNode(pattern); }

// The ops a static shape is built from; anything else is a runtime leaf.
bool isShapeOp(Value value) {
  Operation *def = value.getDefiningOp();
  return def && (def->hasTrait<OpTrait::ConstantLike>() || isa<idr::ConOp, idr::ClosureOp>(def));
}

Attribute shape(Value value, SmallVectorImpl<Value> &leaves) {
  MLIRContext *ctx = value.getContext();
  if (!isShapeOp(value)) {
    leaves.push_back(value);
    return UnitAttr::get(ctx);
  }
  Operation *def = value.getDefiningOp();
  Attribute constant;
  if (matchPattern(value, m_Constant(&constant)))
    return constant;
  SmallVector<Attribute> parts;
  for (Value operand : def->getOperands())
    parts.push_back(shape(operand, leaves));
  auto array = ArrayAttr::get(ctx, parts);
  bool closed = llvm::all_of(parts, isConstant);
  if (auto con = dyn_cast<idr::ConOp>(def))
    return closed ? Attribute(idr::ConAttr::get(ctx, con.getCtor(), array))
                  : ArrayAttr::get(ctx, {StringAttr::get(ctx, "con"), con.getCtor(), array});
  auto closure = cast<idr::ClosureOp>(def);
  return closed ? Attribute(idr::ClosureAttr::get(ctx, closure.getCalleeAttr(), array))
                : ArrayAttr::get(ctx,
                                 {StringAttr::get(ctx, "closure"), closure.getCalleeAttr(), array});
}

// An erased argument is never specialized on: erased is not constant.
Shape shape(Value value) {
  Shape out;
  if (isa<idr::ErasedType>(value.getType())) {
    out.leaves.push_back(value);
    out.pattern = UnitAttr::get(value.getContext());
    return out;
  }
  out.pattern = shape(value, out.leaves);
  return out;
}

// The functions a pattern names as closure labels.
void labels(Attribute pattern, SmallVectorImpl<FlatSymbolRefAttr> &out) {
  if (isHole(pattern))
    return;
  if (auto node = dyn_cast<ArrayAttr>(pattern)) {
    if (cast<StringAttr>(node[0]).getValue() == "closure")
      out.push_back(cast<FlatSymbolRefAttr>(node[1]));
    for (Attribute part : cast<ArrayAttr>(node[2]))
      labels(part, out);
    return;
  }
  pattern.walk([&](idr::ClosureAttr closure) { out.push_back(closure.getCallee()); });
}

// The facts a clone inherits from its origin and the functions it names.
struct Facts {
  bool total;
  bool known; // idr-effects has run on the function
  bool pure;
  bool mayCrash;

  static Facts of(func::FuncOp fn) {
    auto effect = fn->getAttrOfType<StringAttr>("idr.effect");
    return {fn->hasAttr("idr.total"), bool(effect), effect && effect.getValue() == "pure",
            !effect || fn->hasAttr("idr.may_crash")};
  }

  void meet(const Facts &label) {
    total &= label.total;
    pure &= label.pure;
    mayCrash |= label.mayCrash;
  }

  void apply(func::FuncOp fn) const {
    MLIRContext *ctx = fn.getContext();
    if (total)
      fn->setAttr("idr.total", UnitAttr::get(ctx));
    else
      fn->removeAttr("idr.total");
    if (!known)
      return;
    fn->setAttr("idr.effect", StringAttr::get(ctx, pure ? "pure" : "effectful"));
    if (mayCrash)
      fn->setAttr("idr.may_crash", UnitAttr::get(ctx));
    else
      fn->removeAttr("idr.may_crash");
  }
};

StringAttr quantityOf(Type type) {
  MLIRContext *ctx = type.getContext();
  if (isa<idr::ErasedType>(type))
    return StringAttr::get(ctx, "0");
  if (isa<idr::WorldType>(type))
    return StringAttr::get(ctx, "1");
  return StringAttr::get(ctx, "w");
}

struct Specializer {
  Specializer(ModuleOp root, unsigned cloneLimit)
      : module(root), limit(cloneLimit), symbols(root) {}

  ModuleOp module;
  unsigned limit;
  SymbolTable symbols;
  llvm::DenseMap<std::pair<StringAttr, ArrayAttr>, func::FuncOp> clones;
  llvm::StringMap<int64_t> counts;
  std::optional<FrozenRewritePatternSet> canon;
  SmallVector<func::FuncOp> work;
  bool changed = false;

  void loadCounts() {
    if (auto dict = module->getAttrOfType<DictionaryAttr>(cloneCounts))
      for (NamedAttribute entry : dict)
        counts[entry.getName()] = cast<IntegerAttr>(entry.getValue()).getInt();
  }

  void storeCounts() {
    if (counts.empty())
      return;
    Builder b(module.getContext());
    SmallVector<NamedAttribute> entries;
    for (auto &entry : counts)
      entries.push_back(b.getNamedAttr(entry.getKey(), b.getI64IntegerAttr(entry.getValue())));
    module->setAttr(cloneCounts, b.getDictionaryAttr(entries));
  }

  StringRef origin(func::FuncOp fn) {
    auto attr = fn->getAttrOfType<StringAttr>(originAttr);
    return attr ? attr.getValue() : fn.getSymName();
  }

  // Replaces each argument of `clone` that has a static shape by that
  // shape, rebuilt from the ops that `shapes` came from; its runtime leaves
  // become parameters, in order.
  void substitute(func::FuncOp clone, ArrayRef<Shape> shapes, ValueRange operands) {
    unsigned arity = clone.getNumArguments();
    SmallVector<unsigned> at;
    SmallVector<Type> types;
    SmallVector<DictionaryAttr> attrs;
    SmallVector<Location> locs;
    for (unsigned i = 0; i < shapes.size(); ++i) {
      const Shape &s = shapes[i];
      if (isHole(s.pattern)) {
        at.push_back(arity);
        types.push_back(clone.getArgument(i).getType());
        attrs.push_back(clone.getArgAttrDict(i));
        locs.push_back(clone.getArgument(i).getLoc());
        continue;
      }
      for (Value leaf : s.leaves) {
        at.push_back(arity);
        types.push_back(leaf.getType());
        attrs.push_back(DictionaryAttr::get(
            clone.getContext(),
            {NamedAttribute(StringAttr::get(clone.getContext(), "idr.quantity"),
                            quantityOf(leaf.getType()))}));
        locs.push_back(leaf.getLoc());
      }
    }
    (void)clone.insertArguments(at, types, attrs, locs);

    Block &entry = clone.getBody().front();
    OpBuilder b = OpBuilder::atBlockBegin(&entry);
    auto next = entry.getArguments().drop_front(arity).begin();
    for (unsigned i = 0; i < shapes.size(); ++i) {
      Value value = isHole(shapes[i].pattern) ? Value(*next++) : rebuild(b, operands[i], next);
      entry.getArgument(i).replaceAllUsesWith(value);
    }
    llvm::BitVector originals(clone.getNumArguments());
    originals.set(0, arity);
    (void)clone.eraseArguments(originals);
  }

  // The static shape of `value` rebuilt at `b`, taking its runtime leaves
  // from `next` in the order shape() found them.
  template <typename It> Value rebuild(OpBuilder &b, Value value, It &next) {
    if (!isShapeOp(value))
      return *next++;
    Operation *def = value.getDefiningOp();
    IRMapping map;
    for (Value operand : def->getOperands())
      map.map(operand, rebuild(b, operand, next));
    return b.clone(*def, map)->getResult(0);
  }

  func::FuncOp makeClone(func::FuncOp callee, ArrayRef<Shape> shapes, ValueRange operands) {
    StringRef from = origin(callee);
    int64_t n = ++counts[from];
    func::FuncOp clone = callee.clone();
    clone.setSymName(llvm::formatv("{0}$spec${1}", from, n).str());
    clone.setPrivate();
    clone->removeAttr(stopped);
    clone->setAttr(originAttr, StringAttr::get(module.getContext(), from));
    symbols.insert(clone, module.getBody()->end());

    Facts facts = Facts::of(callee);
    SmallVector<FlatSymbolRefAttr> named;
    for (const Shape &s : shapes)
      labels(s.pattern, named);
    for (FlatSymbolRefAttr name : named)
      if (auto label = symbols.lookup<func::FuncOp>(name.getAttr()))
        facts.meet(Facts::of(label));
    facts.apply(clone);

    substitute(clone, shapes, operands);
    work.push_back(clone);
    return clone;
  }

  // The call and its callee are marked, so later runs neither retry the
  // call nor report it again.
  void stop(func::CallOp call, func::FuncOp callee, const std::string &why) {
    call->setAttr(stopped, UnitAttr::get(module.getContext()));
    callee->setAttr(stopped, UnitAttr::get(module.getContext()));
    remark::missed(call.getLoc(),
                   remark::RemarkOpts::name("idr-specialize").category("idr-specialize"))
        << remark::add("specialization of @{0} stopped: {1}", callee.getSymName(), why);
  }

  // Whether `inner` is `outer` or occurs inside it.
  static bool within(Attribute inner, Attribute outer) {
    if (inner == outer)
      return true;
    bool found = false;
    outer.walk([&](Attribute sub) {
      if (sub == inner)
        found = true;
    });
    return found;
  }

  // The patterns `clone` was made for, kept as text in idr.spec_key: as
  // attributes, the closure labels in them would be symbol uses, and keep
  // functions alive that symbol-dce should remove.
  static ArrayAttr patternsOf(func::FuncOp clone) {
    auto text = clone ? clone->getAttrOfType<StringAttr>(keyAttr) : StringAttr();
    return text ? dyn_cast_or_null<ArrayAttr>(parseAttribute(text.getValue(), clone.getContext()))
                : ArrayAttr();
  }

  // Whether a call in `caller` to the same origin passes static arguments
  // that grow: each is the caller's own pattern or contains it, and one
  // strictly.
  bool grows(func::FuncOp caller, func::FuncOp callee, ArrayRef<Attribute> patterns) {
    if (!caller || origin(caller) != origin(callee))
      return false;
    ArrayAttr own = patternsOf(caller);
    if (!own || own.size() != patterns.size())
      return false;
    bool strictly = false;
    for (auto [before, after] : llvm::zip(own.getValue(), patterns)) {
      if (before == after)
        continue;
      if (isHole(before) || isHole(after) || !within(before, after))
        return false;
      strictly = true;
    }
    return strictly;
  }

  // Whether argument `i` of `fn` is taken apart in its body: the scrutinee
  // of a match, or a closure it applies.
  static bool scrutinized(func::FuncOp fn, unsigned i) {
    return llvm::any_of(fn.getArgument(i).getUses(), [](OpOperand &use) {
      return use.getOperandNumber() == 0 &&
             isa<idr::MatchOp, idr::MatchLitOp, idr::ApplyOp>(use.getOwner());
    });
  }

  // In a clone's call of its own origin, a static argument that is not the
  // clone's own pattern, and that the callee never takes apart, only varies
  // (an accumulator): specializing on it would clone once per value, and
  // gain nothing the callee could fold. It becomes a runtime value, as in
  // the generalization of an offline partial evaluator. An argument the
  // callee matches on (a counter, `ack`'s m) keeps its value.
  void generalize(func::FuncOp caller, func::FuncOp callee, MutableArrayRef<Shape> shapes,
                  ValueRange operands) {
    if (!caller || origin(caller) != origin(callee))
      return;
    ArrayAttr own = patternsOf(caller);
    if (!own || own.size() != shapes.size())
      return;
    for (unsigned i = 0; i < shapes.size(); ++i) {
      Shape &s = shapes[i];
      if (isHole(s.pattern) || s.pattern == own[i] || scrutinized(callee, i))
        continue;
      s.pattern = UnitAttr::get(module.getContext());
      s.leaves.assign({operands[i]});
    }
  }

  // The canonicalization patterns of every loaded dialect and op, as the
  // canonicalize pass collects them.
  const FrozenRewritePatternSet &canonicalization() {
    if (!canon) {
      MLIRContext *ctx = module.getContext();
      RewritePatternSet set(ctx);
      for (Dialect *dialect : ctx->getLoadedDialects())
        dialect->getCanonicalizationPatterns(set);
      for (RegisteredOperationName op : ctx->getRegisteredOperations())
        op.getCanonicalizationPatterns(set, ctx);
      canon.emplace(std::move(set));
    }
    return *canon;
  }

  // Whether the call now calls a clone.
  bool specialize(func::CallOp call) {
    auto callee = symbols.lookup<func::FuncOp>(call.getCallee());
    if (!callee || callee.isExternal() || call->hasAttr(stopped))
      return false;
    SmallVector<Shape> shapes = llvm::map_to_vector(call.getOperands(), [](Value v) {
      return shape(v);
    });
    auto caller = call->getParentOfType<func::FuncOp>();
    generalize(caller, callee, shapes, call.getOperands());
    bool isStatic = false, open = false;
    for (auto [s, operand] : llvm::zip(shapes, call.getOperands())) {
      isStatic |= !isHole(s.pattern);
      open |= !isa<idr::ErasedType>(operand.getType()) && !isConstant(s.pattern);
    }
    if (!isStatic || !open)
      return false;

    SmallVector<Attribute> patterns =
        llvm::map_to_vector(shapes, [](const Shape &s) { return s.pattern; });
    auto key = std::make_pair(call.getCalleeAttr().getAttr(),
                              ArrayAttr::get(module.getContext(), patterns));
    func::FuncOp clone = clones.lookup(key);
    if (!clone) {
      if (grows(caller, callee, patterns)) {
        stop(call, callee,
             llvm::formatv("@{0} passes itself a static value that grows", origin(callee)).str());
        return false;
      }
      if (counts.lookup(origin(callee)) >= limit) {
        stop(call, callee,
             llvm::formatv("the clone limit of {0} clones of @{1} is reached", limit,
                           origin(callee))
                 .str());
        return false;
      }
      clone = makeClone(callee, shapes, call.getOperands());
      clones[key] = clone;
      std::string text;
      llvm::raw_string_ostream os(text);
      key.second.print(os);
      clone->setAttr(keyAttr, StringAttr::get(module.getContext(), text));
      // Folded now, so that the calls it makes are as static as they will
      // be, and a chain of clones is made in one run, not one per round.
      (void)applyPatternsGreedily(clone, canonicalization());
    }

    SmallVector<Value> operands;
    for (auto [s, operand] : llvm::zip(shapes, call.getOperands())) {
      if (isHole(s.pattern))
        operands.push_back(operand);
      else
        llvm::append_range(operands, s.leaves);
    }
    OpBuilder b(call);
    auto replacement = func::CallOp::create(b, call.getLoc(), clone, operands);
    replacement->setDiscardableAttrs(call->getDiscardableAttrDictionary());
    call.replaceAllUsesWith(replacement.getResults());
    call.erase();
    return true;
  }

  void run() {
    loadCounts();
    llvm::append_range(work, module.getOps<func::FuncOp>());
    for (size_t i = 0; i < work.size(); ++i) {
      SmallVector<func::CallOp> calls;
      work[i].walk([&](func::CallOp call) { calls.push_back(call); });
      for (func::CallOp call : calls)
        changed |= specialize(call);
    }
    storeCounts();
  }
};

struct Specialize : idr::impl::IdrSpecializeBase<Specialize> {
  using IdrSpecializeBase::IdrSpecializeBase;
  void runOnOperation() override { Specializer(getOperation(), cloneLimit).run(); }
};

} // namespace
