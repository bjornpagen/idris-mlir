// idr-specialize: specialization on constant-like arguments (ELIM-SPEC-1,
// ELIM-SPEC-2).
//
// An argument's pattern is its static shape: a constant is itself, an
// `idr.con` or `idr.closure` is built over the patterns of its operands (the
// partially static values of ELIM-SPEC-1), and anything else is a hole, a
// runtime leaf. An erased argument is always a hole: erased is not constant.
// A call is specialized when some argument has a static shape and some
// non-erased argument has a runtime leaf; a closed call is left to idr-eval,
// and is never specialized (SEM-EVAL-6). The clone substitutes each static
// shape into the callee's body, and its parameters are the runtime leaves in
// order. Its key is the patterns of its origin's parameters: a call of a
// clone composes the clone's key with its own patterns, so keys of all the
// clones of one origin are comparable. Clones are shared through (origin,
// key), kept on each clone as idr.spec_key, and named `@<origin>$spec$<n>`
// with n counting the origin's clones in the order they are first requested
// (FE-DET-1), and appended to the module, so the walk over the module's
// functions reaches them and specializes their calls in turn, until no call
// is left to specialize.
//
// In a clone's call of its own origin, a static argument that changed and
// that the callee never branches on is generalized to a runtime value (an
// accumulator: `run (n - 1) (advance s)`); one it matches on keeps its value
// (a counter). Each clone is canonicalized when it is made, so a chain of
// clones on a counter is made in one run.
//
// Two things stop a specialization. A clone that calls its own origin with
// static arguments that grow, each the clone's own pattern or containing it
// and one strictly (`iter (\y => f (f y))`), would clone forever, so the call
// stays; later rounds see the growth too, through idr.spec_key. And the
// clone limit, counted per original callee over the whole
// compilation (the count is kept on the module as idr.clone_counts, so that
// rounds of idr-simplify share it), bounds what growth in other shapes
// makes. A stopped call gets a Missed remark; it and its callee get
// idr.spec_stopped, so that later runs leave the call alone and
// idr-check-profile reports PROF-HEAP-4 for a closure that survives into
// the callee.
//
// Clones can close new cycles of calls; idr-loop-breakers cuts them at the
// start of the next round (OPT-PIPE-3). A clone does not inherit no_inline
// from a breaker: a chain of clones on a static shape is acyclic, and
// inlining it is what exposes the shape to its consumer.
//
// Generalization and the growth stop compare a call with the latest clone
// of its callee's origin on the chain of clones it was made in: each clone
// keeps, per origin, the key of the latest clone before it
// (idr.spec_history, its own included), and its calls record it
// (idr.spec_caller), which survives inlining the clone into a function that
// is no clone, and covers mutual recursion through several origins.
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
constexpr StringLiteral holeAttr = "idr.hole";
constexpr StringLiteral callerAttr = "idr.spec_caller";
constexpr StringLiteral historyAttr = "idr.spec_history";

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
// In a clone's key, a hole whose parameter remove-dead-values erased: the
// clone never reads that value.
bool isUnused(Attribute pattern) {
  auto ref = dyn_cast<FlatSymbolRefAttr>(pattern);
  return ref && ref.getValue() == "idr.unused";
}
bool isConstant(Attribute pattern) {
  return !isHole(pattern) && !isNode(pattern) && !isUnused(pattern);
}

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
  // idr.spec_key texts, parsed.
  llvm::DenseMap<StringAttr, ArrayAttr> parsed;
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
    // Each parameter records which hole of the key it is (idr.hole), so the
    // key still holds after remove-dead-values erases some of them.
    for (auto [hole, dict] : llvm::enumerate(attrs)) {
      NamedAttrList list(dict);
      list.set(holeAttr, IntegerAttr::get(IntegerType::get(clone.getContext(), 64),
                                          static_cast<int64_t>(hole)));
      dict = list.getDictionary(clone.getContext());
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
    clone.setNoInline(false);
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

  // The patterns of `fn`'s parameters as values of its origin's: a clone's
  // key, kept as text in idr.spec_key (as attributes, the closure labels in
  // them would be symbol uses, and keep functions alive that symbol-dce
  // should remove), or a hole per parameter for a function that is no clone.
  // The key `fn` was made for, if it still holds: once remove-dead-values
  // erases parameters of a clone, its key has more holes than the clone has
  // parameters, and says nothing about the rest.
  std::optional<ArrayAttr> storedKey(func::FuncOp fn) {
    auto text = fn->getAttrOfType<StringAttr>(keyAttr);
    if (!text)
      return std::nullopt;
    ArrayAttr &key = parsed[text];
    if (!key)
      key = dyn_cast_or_null<ArrayAttr>(parseAttribute(text.getValue(), fn.getContext()));
    if (!key)
      return std::nullopt;
    // The holes whose parameters remain, in order.
    llvm::DenseSet<int64_t> live;
    int64_t last = -1;
    for (unsigned i = 0; i < fn.getNumArguments(); ++i) {
      auto hole = fn.getArgAttrOfType<IntegerAttr>(i, holeAttr);
      if (!hole || hole.getInt() <= last)
        return std::nullopt;
      last = hole.getInt();
      live.insert(last);
    }
    int64_t next = 0;
    SmallVector<Attribute> parts;
    for (Attribute part : key)
      parts.push_back(retire(part, live, next));
    if (last >= next)
      return std::nullopt;
    return ArrayAttr::get(fn.getContext(), parts);
  }

  // `part` with each hole whose number is not in `live` marked unused.
  static Attribute retire(Attribute part, const llvm::DenseSet<int64_t> &live, int64_t &next) {
    if (isHole(part))
      return live.contains(next++) ? part
                                   : FlatSymbolRefAttr::get(part.getContext(), "idr.unused");
    auto node = dyn_cast<ArrayAttr>(part);
    if (!node)
      return part;
    SmallVector<Attribute> parts;
    for (Attribute inner : cast<ArrayAttr>(node[2]))
      parts.push_back(retire(inner, live, next));
    return ArrayAttr::get(part.getContext(), {node[0], node[1], ArrayAttr::get(part.getContext(), parts)});
  }

  // The patterns of `fn`'s parameters as values of its origin's, or a hole
  // per parameter for a function that is no clone.
  ArrayAttr keyOf(func::FuncOp fn) {
    if (std::optional<ArrayAttr> key = storedKey(fn))
      return *key;
    MLIRContext *ctx = fn.getContext();
    return ArrayAttr::get(ctx, SmallVector<Attribute>(fn.getNumArguments(), UnitAttr::get(ctx)));
  }

  // Whether calls of `fn` are keyed by its origin: it is no clone, or a
  // clone whose key holds.
  bool keyed(func::FuncOp fn) { return !fn->hasAttr(originAttr) || storedKey(fn); }

  // An original function takes a key of its own, a hole per parameter, the
  // first time a call of it is specialized: remove-dead-values may later
  // erase its dead parameters, and the keys composed through it must keep
  // the positions its clones' keys have.
  void adopt(func::FuncOp fn) {
    if (fn->hasAttr(originAttr) || fn->hasAttr(keyAttr))
      return;
    MLIRContext *ctx = fn.getContext();
    for (unsigned i = 0; i < fn.getNumArguments(); ++i)
      fn.setArgAttr(i, holeAttr, IntegerAttr::get(IntegerType::get(ctx, 64), i));
    std::string text;
    llvm::raw_string_ostream os(text);
    ArrayAttr::get(ctx, SmallVector<Attribute>(fn.getNumArguments(), UnitAttr::get(ctx))).print(os);
    fn->setAttr(keyAttr, StringAttr::get(ctx, text));
  }

  // The runtime leaves of a pattern.
  static unsigned holes(Attribute pattern) {
    if (isHole(pattern))
      return 1;
    auto node = dyn_cast<ArrayAttr>(pattern);
    unsigned n = 0;
    if (node)
      for (Attribute part : cast<ArrayAttr>(node[2]))
        n += holes(part);
    return n;
  }

  // `part`, a pattern of a callee's key, with its holes filled in order by
  // `args`, the patterns of a call of it; a node whose parts all become
  // constants is the constant it folds to, as shape() makes it.
  static Attribute fill(Attribute part, ArrayRef<Attribute> args, size_t &next) {
    if (isHole(part))
      return args[next++];
    auto node = dyn_cast<ArrayAttr>(part);
    if (!node)
      return part;
    MLIRContext *ctx = part.getContext();
    SmallVector<Attribute> parts;
    for (Attribute inner : cast<ArrayAttr>(node[2]))
      parts.push_back(fill(inner, args, next));
    auto array = ArrayAttr::get(ctx, parts);
    if (!llvm::all_of(parts, isConstant))
      return ArrayAttr::get(ctx, {node[0], node[1], array});
    if (cast<StringAttr>(node[0]).getValue() == "con")
      return idr::ConAttr::get(ctx, cast<SymbolRefAttr>(node[1]), array);
    return idr::ClosureAttr::get(ctx, cast<FlatSymbolRefAttr>(node[1]), array);
  }

  // The key of a call of `callee` with `patterns`: the patterns of its
  // origin's parameters. Keys of calls of an origin and of its clones are
  // comparable, and a clone made for one is shared by the other.
  ArrayAttr compose(func::FuncOp callee, ArrayRef<Attribute> patterns) {
    size_t next = 0;
    SmallVector<Attribute> out;
    for (Attribute part : keyOf(callee))
      out.push_back(fill(part, patterns, next));
    return ArrayAttr::get(callee.getContext(), out);
  }

  // The history of a call: for each origin on the chain of clones the call
  // was made in, the key of the latest such clone. A call in a clone records
  // it (idr.spec_caller), since inlining the clone moves the call into a
  // function that is no clone; otherwise it is the enclosing clone's
  // (idr.spec_history), if any.
  static DictionaryAttr historyOf(func::CallOp call) {
    if (auto history = call->getAttrOfType<DictionaryAttr>(callerAttr))
      return history;
    auto caller = call->getParentOfType<func::FuncOp>();
    return caller ? caller->getAttrOfType<DictionaryAttr>(historyAttr) : DictionaryAttr();
  }

  // The key of the latest clone of the callee's origin on the call's chain,
  // as the patterns of the origin's parameters, or null. Mutual recursion
  // goes through clones of several origins, so a call is compared with the
  // latest clone of its callee's origin, not only with the clone it is in.
  ArrayAttr ownKey(func::CallOp call, func::FuncOp callee) {
    DictionaryAttr history = historyOf(call);
    auto text = history ? history.getAs<StringAttr>(origin(callee)) : StringAttr();
    if (!text)
      return {};
    ArrayAttr &key = parsed[text];
    if (!key)
      key = dyn_cast_or_null<ArrayAttr>(parseAttribute(text.getValue(), call.getContext()));
    return key;
  }

  // Whether the call passes static arguments that grow over `own`, the key
  // of the clone it was made in: each is that clone's own pattern or
  // contains it, and one strictly.
  static bool grows(ArrayAttr own, ArrayAttr key) {
    if (!own || own.size() != key.size())
      return false;
    bool strictly = false;
    for (auto [before, after] : llvm::zip(own.getValue(), key.getValue())) {
      if (before == after)
        continue;
      if (isHole(before) || isUnused(before) || isHole(after) || !within(before, after))
        return false;
      strictly = true;
    }
    return strictly;
  }

  // Whether `fn` branches on argument `i` in its body: the scrutinee of a
  // match with more than one region, or a closure it applies. (A match of
  // one region only takes a record apart.)
  static bool scrutinized(func::FuncOp fn, unsigned i) {
    return llvm::any_of(fn.getArgument(i).getUses(), [](OpOperand &use) {
      Operation *user = use.getOwner();
      if (use.getOperandNumber() != 0)
        return false;
      if (isa<idr::ApplyOp>(user))
        return true;
      return isa<idr::MatchOp, idr::MatchLitOp>(user) && user->getNumRegions() > 1;
    });
  }

  // In a clone's call of its own origin, a static argument that is not the
  // clone's own pattern, and that the callee never branches on, only varies
  // (an accumulator): specializing on it would clone once per value, and
  // gain nothing the callee could fold. It becomes a runtime value, as in
  // the generalization of an offline partial evaluator. An argument the
  // callee matches on (a counter, `ack`'s m) keeps its value.
  void generalize(ArrayAttr own, func::FuncOp callee, MutableArrayRef<Shape> shapes,
                  ValueRange operands) {
    if (!own || !keyed(callee))
      return;
    ArrayAttr calleeKey = keyOf(callee);
    if (own.size() != calleeKey.size())
      return;
    // Each position of the origin covers a run of the callee's parameters:
    // one where the callee's key has a hole, the holes of a node otherwise.
    SmallVector<Attribute> patterns =
        llvm::map_to_vector(shapes, [](const Shape &s) { return s.pattern; });
    unsigned first = 0;
    for (auto [part, before] : llvm::zip(calleeKey.getValue(), own.getValue())) {
      unsigned n = holes(part);
      size_t next = first;
      Attribute after = fill(part, patterns, next);
      bool varies = after != before && after != part;
      for (unsigned p = first; varies && p < first + n; ++p)
        varies = !scrutinized(callee, p);
      for (unsigned p = first; varies && p < first + n; ++p) {
        shapes[p].pattern = UnitAttr::get(module.getContext());
        shapes[p].leaves.assign({operands[p]});
      }
      first += n;
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
    adopt(callee);
    ArrayAttr own = ownKey(call, callee);
    generalize(own, callee, shapes, call.getOperands());
    bool isStatic = false, open = false;
    for (auto [s, operand] : llvm::zip(shapes, call.getOperands())) {
      isStatic |= !isHole(s.pattern);
      open |= !isa<idr::ErasedType>(operand.getType()) && !isConstant(s.pattern);
    }
    if (!isStatic || !open)
      return false;

    SmallVector<Attribute> patterns =
        llvm::map_to_vector(shapes, [](const Shape &s) { return s.pattern; });
    // Keyed by the origin, or, for a clone whose key no longer holds, by the
    // clone itself, whose parameters the patterns are.
    auto key = keyed(callee)
                   ? std::make_pair(StringAttr::get(module.getContext(), origin(callee)),
                                    compose(callee, patterns))
                   : std::make_pair(callee.getSymNameAttr(),
                                    ArrayAttr::get(module.getContext(), patterns));
    func::FuncOp clone = clones.lookup(key);
    if (!clone) {
      if (grows(own, key.second)) {
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
      clone->removeAttr(keyAttr);
      clone->removeAttr(historyAttr);
      MLIRContext *ctx = module.getContext();
      NamedAttrList history(historyOf(call));
      if (keyed(callee)) {
        std::string text;
        llvm::raw_string_ostream os(text);
        key.second.print(os);
        clone->setAttr(keyAttr, StringAttr::get(ctx, text));
        history.set(origin(callee), StringAttr::get(ctx, text));
      }
      DictionaryAttr chain = history.getDictionary(ctx);
      if (!chain.empty())
        clone->setAttr(historyAttr, chain);
      // Folded now, so that the calls it makes are as static as they will
      // be, and a chain of clones is made in one run, not one per round.
      (void)applyPatternsGreedily(clone, canonicalization());
      // Its calls record its history, for when it is inlined.
      if (!chain.empty())
        clone.walk([&](func::CallOp inner) { inner->setAttr(callerAttr, chain); });
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
    for (auto fn : module.getOps<func::FuncOp>())
      if (std::optional<ArrayAttr> key = storedKey(fn))
        clones[{StringAttr::get(module.getContext(), origin(fn)), *key}] = fn;
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
