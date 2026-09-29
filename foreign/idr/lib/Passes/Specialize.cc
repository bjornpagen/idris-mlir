// idr-specialize: clones a function for the static parts of its arguments,
// after first moving a call's consumer into its callee (raising, below).
//
// An argument's pattern is its static shape: a constant is itself, an
// `idr.con` or `idr.closure` is built over the patterns of its operands, and
// anything else is a hole, a runtime leaf; so is a machine integer passed as
// an argument itself (isLeaf()). An erased argument is always a
// hole: erased is not constant. A call is specialized when some argument has
// a static shape and some argument that is neither erased nor a world has a
// runtime leaf; a closed call is idr-eval's. The clone substitutes each
// static shape into the callee's body, and its parameters are the runtime
// leaves in order. Its key is the patterns of its origin's parameters: a
// call of a clone composes the clone's key with its own patterns, so the
// keys of all the clones of one origin are comparable. Clones are shared
// through (origin, key), kept on each clone as idr.spec_key, named
// `@<origin>$spec$<n>` in the order they are first requested (so the output
// is deterministic), and appended to the module, so the walk over the
// module's functions reaches them and specializes their calls in turn.
//
// In a clone's call of its own origin, a static argument that changed is
// generalized to a runtime value when the callee never branches on it (an
// accumulator: `run (n - 1) (advance s)`). Each clone is canonicalized when
// it is made, so a chain of clones is made in one run.
//
// Two things stop a specialization. A clone that calls its own origin with
// static arguments that grow, each the clone's own pattern or containing it
// and one strictly (`iter (\y => f (f y))`), would clone forever, so the call
// stays; later rounds see the growth too, through idr.spec_key. And the
// clone limit, counted per origin over the whole compilation (on the module,
// as idr.clone_counts, so the rounds of idr-simplify share it), bounds
// growth in other shapes. A stopped call gets a Missed remark; it and its
// callee get idr.spec_stopped, so that idr-check-profile names the stop when
// a closure survives into the callee, and the call records the key it
// stopped at (idr.spec_stopped_at): later runs leave it alone while its key
// is that one, and check it again once inlining has made it more static.
//
// Clones can close new cycles of calls; idr-loop-breakers cuts them at the
// start of the next round. A clone does not inherit no_inline from a
// breaker: a chain of clones on a static shape is acyclic, and inlining it is
// what exposes the shape to its consumer.
//
// Generalization and the growth stop compare a call with the latest clone of
// its callee's origin on the chain of clones it was made in: each clone
// keeps, per origin, the key of the latest clone before it
// (idr.spec_history, its own included), and its calls record it
// (idr.spec_caller), which survives inlining the clone into a function that
// is no clone, and covers mutual recursion through several origins.
//
// A clone is total if its origin is and so is every function its static
// arguments name; the same holds for purity and, reversed, for "may crash",
// when idr-effects has computed those facts.
//
// Raising comes first, for each call: the single consumer of a call's result
// moves into a clone of the callee. Two consumers move:
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
// clone is keyed by its callee and its consumer (`raise @f`,
// `raise @f[@C, i]` or `write @f` in idr.spec_key), so that later rounds
// share it too: a call of the callee in the clone whose result is consumed
// the same way, which inlining exposes where an action recurs, and output
// fusion where a recursive `show` appends, becomes a self call, and
// idr-tail-loops makes a tail call a loop. Its parameters are the callee's,
// then the consumer's other operands, each numbered by idr.hole, so that a
// call still finds the parameters remove-dead-values leaves. It is named
// `@<origin>$raise$<n>` or `@<origin>$write$<n>`, counted with the origin's
// other clones and bounded by the clone limit, and has idr.origin, so that
// the newest clone breaks a new cycle. Unlike a clone that specializes, it
// keeps no_inline from a loop breaker: it is where the breaker's loop becomes
// a self call. Its parameters are not its callee's, so it is the origin of
// its own clones: it has no key of patterns and takes none (adopt), and a
// clone of it records it in idr.spec_history as a clone of any origin does.
// It keeps the history its callee had, and the raised call keeps the history
// of the call it replaces (idr.spec_caller), so a chain of clones goes on
// through it.
//
// Raising moves the callee's body from the call to its consumer, so nothing
// may run between them: the consumer and the projection are in the call's
// block, and every op between the call and the consumer is free of memory
// effects (a crash, output and an allocation are effects), or the callee is
// total, cannot crash and is pure or performs no IO while it runs (it may
// build actions that do, as a fold of `*>` does), so that when its body
// runs cannot be observed. A callee that takes a world is never raised: its
// body would take part in the world chain. A closed call of a pure, total
// callee is idr-eval's, which runs it to the end, and is not raised; one of
// a partial callee is raised, as idr-eval may leave it to runtime when it
// does not finish within its budget. A clone that applies is total if its
// callee is and every tail applies a known closure of a total function, and
// is pure and may crash as its callee and those functions; a clone that
// writes is total and may crash as its callee, and is effectful.

#include "idr/Idr.h"

#include "mlir/AsmParser/AsmParser.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/Remarks.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/MapVector.h"
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
constexpr StringLiteral stoppedAt = "idr.spec_stopped_at";
// The start of the idr.spec_key of a clone made by raising: one
// that applies its result, and one that writes it. Such a key is no
// pattern: storedKey() and the history leave it out.
constexpr StringLiteral raiseKey = "raise ";
constexpr StringLiteral writeKey = "write ";
bool isRaiseKey(StringAttr text) {
  return text && (text.getValue().starts_with(raiseKey) || text.getValue().starts_with(writeKey));
}

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

// Whether a constant is a machine integer: of a fixed width (an Int, a Char),
// not a big (a Nat or an Integer).
bool machineInteger(Attribute pattern) {
  auto integer = dyn_cast<IntegerAttr>(pattern);
  return integer && isa<IntegerType>(integer.getType());
}

// Whether `value` is closed: a constant, or a constructor or closure of
// closed values. A call of closed values is idr-eval's.
bool closed(Value value) {
  if (matchPattern(value, m_Constant()))
    return true;
  Operation *def = value.getDefiningOp();
  return isa_and_nonnull<idr::ConOp, idr::ClosureOp>(def) && llvm::all_of(def->getOperands(), closed);
}

// Whether `value` is a runtime leaf of a shape: it is built by no shape op,
// or it is a machine integer passed as an argument itself (`top`): a loop
// counter, which specializing would unroll once per value, and which LLVM's
// own specialization of numeric constants weighs better; what this pass
// removes is structure. A number inside a constructor or a closure is part
// of that structure and stays static (the elements of a static list), and so
// does a Nat or an Integer argument, whose countdown is how a vector's static
// length unrolls, and a Double, an accumulator folded along a static spine.
bool isLeaf(Value value, bool top) {
  Attribute constant;
  return !isShapeOp(value) ||
         (top && matchPattern(value, m_Constant(&constant)) && machineInteger(constant));
}

Attribute shape(Value value, SmallVectorImpl<Value> &leaves, bool top) {
  MLIRContext *ctx = value.getContext();
  if (isLeaf(value, top)) {
    leaves.push_back(value);
    return UnitAttr::get(ctx);
  }
  Operation *def = value.getDefiningOp();
  Attribute constant;
  if (matchPattern(value, m_Constant(&constant)))
    return constant;
  SmallVector<Attribute> parts;
  for (Value operand : def->getOperands())
    parts.push_back(shape(operand, leaves, /*top=*/false));
  auto array = ArrayAttr::get(ctx, parts);
  bool whole = llvm::all_of(parts, isConstant);
  if (auto con = dyn_cast<idr::ConOp>(def))
    return whole ? Attribute(idr::ConAttr::get(ctx, con.getCtor(), array))
                  : ArrayAttr::get(ctx, {StringAttr::get(ctx, "con"), con.getCtor(), array});
  auto closure = cast<idr::ClosureOp>(def);
  return whole ? Attribute(idr::ClosureAttr::get(ctx, closure.getCalleeAttr(), array))
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
  out.pattern = shape(value, out.leaves, /*top=*/true);
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
  // The clones made by arity raising, by their idr.spec_key.
  llvm::DenseMap<StringAttr, func::FuncOp> raised;
  // Whether a call of each function may perform IO (runsIO()).
  llvm::DenseMap<func::FuncOp, bool> performsIO;
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

  // The function whose clones `fn` counts with and whose parameters keys
  // are patterns of. A clone made by raising has parameters its callee does
  // not have, so it is an origin of its own: its own clones are keyed by
  // its parameters, and a clone's call of it generalizes as a call of any
  // origin does.
  StringRef origin(func::FuncOp fn) {
    if (isRaiseKey(fn->getAttrOfType<StringAttr>(keyAttr)))
      return fn.getSymName();
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
    if (isLeaf(value, /*top=*/false))
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

  // The call and its callee are marked, and the call records the key it
  // stopped at, so later runs neither retry it nor report it again while
  // its key stays the same.
  void stop(func::CallOp call, func::FuncOp callee, StringRef key, const std::string &why) {
    call->setAttr(stopped, UnitAttr::get(module.getContext()));
    call->setAttr(stoppedAt, StringAttr::get(module.getContext(), key));
    callee->setAttr(stopped, UnitAttr::get(module.getContext()));
    remark::missed(call.getLoc(),
                   remark::RemarkOpts::name("idr-specialize").category("idr-specialize"))
        << remark::add("specialization of @{0} stopped: {1}", callee.getSymName(), why);
  }

  // The label and parts of a pattern that is a node or a constructor or
  // closure constant, or nothing.
  static std::optional<std::pair<Attribute, ArrayRef<Attribute>>> split(Attribute pattern) {
    if (auto node = dyn_cast<ArrayAttr>(pattern))
      return std::make_pair(node[1], cast<ArrayAttr>(node[2]).getValue());
    if (auto con = dyn_cast<idr::ConAttr>(pattern))
      return std::make_pair(Attribute(con.getCtor()), con.getFields().getValue());
    if (auto closure = dyn_cast<idr::ClosureAttr>(pattern))
      return std::make_pair(Attribute(closure.getCallee()), closure.getCaptures().getValue());
    return std::nullopt;
  }

  // Whether `value` is an instance of `pattern`, whose holes (and unused
  // positions) match anything.
  static bool instance(Attribute pattern, Attribute value) {
    if (isHole(pattern) || isUnused(pattern) || pattern == value)
      return true;
    auto p = split(pattern), v = split(value);
    if (!p || !v || p->first != v->first || p->second.size() != v->second.size())
      return false;
    return llvm::all_of(llvm::zip(p->second, v->second),
                        [](auto pair) { return instance(std::get<0>(pair), std::get<1>(pair)); });
  }

  // Whether a proper part of `value` is an instance of `pattern`: the
  // embedding a whistle looks for (`f (f x)` after `f x`).
  static bool embedsStrictly(Attribute pattern, Attribute value) {
    auto v = split(value);
    return v && llvm::any_of(v->second, [&](Attribute part) {
             return instance(pattern, part) || embedsStrictly(pattern, part);
           });
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
    if (!text || isRaiseKey(text))
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

  // Whether calls of `fn` are keyed by its origin: it is no clone, a clone
  // made by raising (its own origin), or a clone whose key holds.
  bool keyed(func::FuncOp fn) {
    return !fn->hasAttr(originAttr) || isRaiseKey(fn->getAttrOfType<StringAttr>(keyAttr)) ||
           storedKey(fn);
  }

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
  // of the latest clone of its callee's origin on its chain: each is that
  // clone's own pattern or strictly contains an instance of it (holes match
  // anything), and one differs.
  static bool grows(ArrayAttr own, ArrayAttr key) {
    if (!own || own.size() != key.size())
      return false;
    bool strictly = false;
    for (auto [before, after] : llvm::zip(own.getValue(), key.getValue())) {
      // A position one of the clones never reads says nothing either way.
      if (before == after || isUnused(before) || isUnused(after))
        continue;
      if (isHole(before) || isHole(after) || !embedsStrictly(before, after))
        return false;
      strictly = true;
    }
    return strictly;
  }

  // Whether `fn` branches on argument `i`: it is the scrutinee of a match
  // with more than one region, or a closure the function applies, in `fn`
  // or in a function `fn` passes it to (a wrapper). A match of one region
  // only takes a record apart.
  bool scrutinized(func::FuncOp fn, unsigned i) {
    llvm::DenseSet<std::pair<Operation *, unsigned>> seen;
    return scrutinized(fn, i, seen);
  }

  bool scrutinized(func::FuncOp fn, unsigned i,
                   llvm::DenseSet<std::pair<Operation *, unsigned>> &seen) {
    if (fn.isExternal() || !seen.insert({fn.getOperation(), i}).second)
      return false;
    return llvm::any_of(fn.getArgument(i).getUses(), [&](OpOperand &use) {
      Operation *user = use.getOwner();
      if (auto call = dyn_cast<func::CallOp>(user)) {
        auto target = symbols.lookup<func::FuncOp>(call.getCallee());
        return target && scrutinized(target, use.getOperandNumber(), seen);
      }
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
  // callee matches on keeps its value.
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

  //===--------------------------------------------------------------------===//
  // Raising
  //===--------------------------------------------------------------------===//

  // The single consumer of a call's result that moves into a clone of the
  // callee: an apply of the result or of one field of it, or output of it.
  struct Consumer {
    idr::FieldOp field; // an apply's projection, or null
    Operation *op;      // the idr.apply or the idr.io.put_str

    bool writes() const { return isa<idr::PutStrOp>(op); }
    // The operands the clone takes after the callee's: the apply's
    // arguments, or the world that output takes.
    OperandRange extra() const {
      return writes() ? op->getOperands().drop_front() : cast<idr::ApplyOp>(op).getArgs();
    }
  };

  // Whether a call of `fn` may perform IO while it runs. idr.effect cannot
  // say: idr-effects counts the effects of a closure where it is created,
  // so a function that only builds IO actions (a fold that makes `a *> b`
  // of each element, `pure ()` at the end) is effectful, although calling
  // it performs nothing, and nothing its caller does can be reordered with
  // it. Here a closure counts where it is applied instead: a function runs
  // IO if it has an IO op, calls a function that runs IO, or applies a
  // closure that is not built here or whose function runs IO. A function
  // that does none of these performs no IO whatever its arguments are.
  //
  // The facts of the functions `fn` reaches are found together, as a
  // greatest fixpoint, so that a cycle of calls none of which does IO
  // does none. A fact stays true for the rest of the run: specialization
  // and raising only make an applied closure more known.
  bool runsIO(func::FuncOp fn) {
    if (auto known = performsIO.find(fn); known != performsIO.end())
      return known->second;
    struct Local {
      bool io = false;
      SmallVector<func::FuncOp> reaches;
    };
    llvm::MapVector<func::FuncOp, Local> found;
    SmallVector<func::FuncOp> stack{fn};
    while (!stack.empty()) {
      func::FuncOp f = stack.pop_back_val();
      if (performsIO.count(f) || found.count(f))
        continue;
      Local &local = found[f];
      auto reach = [&](FlatSymbolRefAttr name) {
        auto target = symbols.lookup<func::FuncOp>(name.getAttr());
        if (!target) {
          local.io = true;
          return;
        }
        local.reaches.push_back(target);
        stack.push_back(target);
      };
      if (f.isExternal()) {
        local.io = true;
        continue;
      }
      f.getBody().walk([&](Operation *op) {
        if (op->hasTrait<idr::PerformsIO>()) {
          local.io = true;
        } else if (auto call = dyn_cast<func::CallOp>(op)) {
          reach(call.getCalleeAttr());
        } else if (auto apply = dyn_cast<idr::ApplyOp>(op)) {
          idr::ClosureAttr constant;
          if (auto closure = apply.getCallee().getDefiningOp<idr::ClosureOp>())
            reach(closure.getCalleeAttr());
          else if (matchPattern(apply.getCallee(), m_Constant(&constant)))
            reach(constant.getCallee());
          else
            local.io = true;
        } else if (isa<CallOpInterface>(op)) {
          local.io = true;
        }
      });
    }
    // The facts spread from the functions that run IO to those that reach
    // them, until nothing changes.
    auto io = [&](func::FuncOp f) {
      auto known = performsIO.find(f);
      return known != performsIO.end() ? known->second : found.find(f)->second.io;
    };
    for (bool grew = true; grew;) {
      grew = false;
      for (auto &[f, local] : found)
        if (!local.io && llvm::any_of(local.reaches, io))
          local.io = grew = true;
    }
    for (auto &[f, local] : found)
      performsIO[f] = local.io;
    return performsIO.lookup(fn);
  }

  // The consumer of `call`'s result, if moving the callee's body from the
  // call to it cannot be observed.
  std::optional<Consumer> consumer(func::CallOp call, func::FuncOp callee) {
    if (call->getNumResults() != 1 || !call->getResult(0).hasOneUse() ||
        llvm::any_of(callee.getArgumentTypes(), llvm::IsaPred<idr::WorldType>))
      return std::nullopt;
    Value value = call->getResult(0);
    Operation *user = *value.user_begin();
    auto field = dyn_cast<idr::FieldOp>(user);
    if (field) {
      if (!field.getResult().hasOneUse())
        return std::nullopt;
      value = field.getResult();
      user = *value.user_begin();
    }
    bool applies = isa<idr::ApplyOp>(user) && cast<idr::ApplyOp>(user).getCallee() == value;
    bool writes = !field && isa<idr::PutStrOp>(user) && cast<idr::PutStrOp>(user).getStr() == value;
    if ((!applies && !writes) || user->getBlock() != call->getBlock())
      return std::nullopt;
    bool finishes = idr::isPure(callee) && idr::isTotal(callee);
    // idr-eval evaluates this call to the end, and its consumer then folds.
    // A closed call of partial code it evaluates only within a budget, so
    // that call is raised like any other; the raised call is closed too when
    // the consumer's operands are, and idr-eval evaluates it instead.
    if (finishes &&
        llvm::all_of(call.getOperands(), [](Value v) { return matchPattern(v, m_Constant()); }))
      return std::nullopt;
    // A callee that always returns, cannot crash and performs no IO of its
    // own may run later, after output between the call and its consumer.
    bool unobservable = idr::isTotal(callee) && !idr::mayCrash(callee) &&
                        (idr::isPure(callee) || !runsIO(callee));
    if (!unobservable)
      for (Operation *op = call->getNextNode(); op != user; op = op->getNextNode())
        if (!isMemoryEffectFree(op))
          return std::nullopt;
    return Consumer{field, user};
  }

  // The key of the clone that moves `c` into `callee`.
  static StringAttr consumerKey(func::FuncOp callee, Consumer c) {
    std::string text =
        llvm::formatv("{0}@{1}", c.writes() ? writeKey : raiseKey, callee.getSymName()).str();
    if (c.field)
      text += llvm::formatv("[@{0}, {1}]", c.field.getCtor(), c.field.getIndex()).str();
    return StringAttr::get(callee.getContext(), text);
  }

  // The function a value applies to after the projection of `c`, when the
  // value is a closure built here or a constant: the label of a tail.
  static FlatSymbolRefAttr label(Value value, Consumer c) {
    Attribute constant;
    (void)matchPattern(value, m_Constant(&constant));
    if (c.field) {
      StringAttr ctor = c.field.getCtorAttr().getAttr();
      uint64_t index = c.field.getIndex();
      if (auto con = value.getDefiningOp<idr::ConOp>()) {
        if (con.getCtor().getLeafReference() != ctor || index >= con.getFields().size())
          return {};
        value = con.getFields()[static_cast<unsigned>(index)];
        constant = {};
        (void)matchPattern(value, m_Constant(&constant));
      } else if (auto data = dyn_cast_or_null<idr::ConAttr>(constant)) {
        if (data.getCtor().getLeafReference() != ctor || index >= data.getFields().size())
          return {};
        value = {};
        constant = data.getFields()[static_cast<unsigned>(index)];
      } else {
        return {};
      }
    }
    if (auto closure = value ? value.getDefiningOp<idr::ClosureOp>() : idr::ClosureOp())
      return closure.getCalleeAttr();
    if (auto closure = dyn_cast_or_null<idr::ClosureAttr>(constant))
      return closure.getCallee();
    return {};
  }

  // A match like `op` whose results have `types`, with `op`'s regions.
  template <typename Match>
  static Operation *retyped(OpBuilder &b, Match op, TypeRange types) {
    auto fresh = Match::create(b, op.getLoc(), types, op.getScrutinee(), op.getCases(),
                               op->getNumRegions());
    fresh->setDiscardableAttrs(op->getDiscardableAttrDictionary());
    for (auto [to, from] : llvm::zip(fresh->getRegions(), op->getRegions()))
      to.takeBody(from);
    return fresh;
  }

  static void replaceOperand(Operation *op, unsigned index, ValueRange values) {
    SmallVector<Value> operands(op->getOperands());
    operands.erase(operands.begin() + index);
    operands.insert(operands.begin() + index, values.begin(), values.end());
    op->setOperands(operands);
  }

  // Makes `c` consume operand `index` of `term`, a return or a yield, where
  // that value is made: through a match whose result it is and that has no
  // other use, in each region that yields; otherwise right before `term`.
  // `result` is the call's result that `c` consumed, and `extra` stands for
  // `c.extra()`. For an apply, `labels` collects the function each tail
  // applies, and `known` becomes false for a tail whose function is not
  // known here.
  void push(Operation *term, unsigned index, Consumer c, Value result, ValueRange extra,
            SmallVectorImpl<FlatSymbolRefAttr> &labels, bool &known) {
    Value value = term->getOperand(index);
    auto res = dyn_cast<OpResult>(value);
    Operation *match = res ? res.getOwner() : nullptr;
    if (match && isa<idr::MatchOp, idr::MatchLitOp>(match) && res.hasOneUse()) {
      unsigned k = res.getResultNumber();
      for (Region &region : match->getRegions())
        if (auto yield = dyn_cast<idr::YieldOp>(region.front().getTerminator()))
          push(yield, k, c, result, extra, labels, known);
      TypeRange types = match->getResultTypes();
      SmallVector<Type> fresh(types.take_front(k));
      llvm::append_range(fresh, c.op->getResultTypes());
      llvm::append_range(fresh, types.drop_front(k + 1));
      OpBuilder b(match);
      Operation *made = isa<idr::MatchOp>(match)
                            ? retyped(b, cast<idr::MatchOp>(match), fresh)
                            : retyped(b, cast<idr::MatchLitOp>(match), fresh);
      unsigned n = c.op->getNumResults();
      for (unsigned i = 0; i < match->getNumResults(); ++i)
        if (i != k)
          match->getResult(i).replaceAllUsesWith(made->getResult(i < k ? i : i + n - 1));
      replaceOperand(term, index, made->getResults().slice(k, n));
      match->erase();
      return;
    }
    if (!c.writes()) {
      if (FlatSymbolRefAttr fn = label(value, c))
        labels.push_back(fn);
      else
        known = false;
    }
    OpBuilder b(term);
    IRMapping map;
    map.map(result, value);
    if (c.field)
      b.clone(*c.field, map);
    for (auto [operand, param] : llvm::zip(c.extra(), extra))
      map.map(operand, param);
    Operation *consumed = b.clone(*c.op, map);
    replaceOperand(term, index, consumed->getResults());
  }

  // The clone of `callee` that consumes its result as `c` does.
  func::FuncOp makeRaised(func::FuncOp callee, Value result, Consumer c, StringAttr key) {
    MLIRContext *ctx = module.getContext();
    StringRef from = origin(callee);
    int64_t n = ++counts[from];
    func::FuncOp clone = callee.clone();
    clone.setSymName(llvm::formatv("{0}${1}${2}", from, c.writes() ? "write" : "raise", n).str());
    clone.setPrivate();
    clone->setAttr(originAttr, StringAttr::get(ctx, from));
    clone->setAttr(keyAttr, key);
    clone.removeResAttrsAttr();
    symbols.insert(clone, module.getBody()->end());

    unsigned arity = clone.getNumArguments();
    SmallVector<unsigned> at(c.extra().size(), arity);
    SmallVector<Type> types(c.extra().getTypes());
    SmallVector<DictionaryAttr> attrs;
    SmallVector<Location> locs;
    for (Value operand : c.extra()) {
      attrs.push_back(DictionaryAttr::get(
          ctx,
          {NamedAttribute(StringAttr::get(ctx, "idr.quantity"), quantityOf(operand.getType()))}));
      locs.push_back(c.op->getLoc());
    }
    (void)clone.insertArguments(at, types, attrs, locs);
    for (unsigned i = 0; i < clone.getNumArguments(); ++i)
      clone.setArgAttr(i, holeAttr, IntegerAttr::get(IntegerType::get(ctx, 64), i));
    clone.setFunctionType(FunctionType::get(ctx, clone.getArgumentTypes(), c.op->getResultTypes()));

    auto ret = cast<func::ReturnOp>(clone.getBody().front().getTerminator());
    SmallVector<FlatSymbolRefAttr> labels;
    bool known = true;
    push(ret, 0, c, result, clone.getArguments().drop_front(arity), labels, known);

    Facts facts = Facts::of(callee);
    facts.total &= known;
    for (FlatSymbolRefAttr name : labels) {
      if (auto fn = symbols.lookup<func::FuncOp>(name.getAttr()))
        facts.meet(Facts::of(fn));
      else
        facts.total = false;
    }
    if (c.writes())
      facts.pure = false;
    facts.apply(clone);
    (void)applyPatternsGreedily(clone, canonicalization());
    work.push_back(clone);
    return clone;
  }

  // The operands of a call of `clone`, a clone made by raising, from `all`,
  // the callee's operands and the consumer's others: those of the
  // parameters it has left, or nothing if they no longer fit.
  static std::optional<SmallVector<Value>> raisedOperands(func::FuncOp clone, ValueRange all,
                                                          TypeRange results) {
    if (TypeRange(clone.getResultTypes()) != results)
      return std::nullopt;
    SmallVector<Value> operands;
    int64_t last = -1;
    for (BlockArgument param : clone.getArguments()) {
      auto hole = clone.getArgAttrOfType<IntegerAttr>(param.getArgNumber(), holeAttr);
      if (!hole || hole.getInt() <= last || hole.getInt() >= static_cast<int64_t>(all.size()) ||
          all[static_cast<size_t>(hole.getInt())].getType() != param.getType())
        return std::nullopt;
      last = hole.getInt();
      operands.push_back(all[static_cast<size_t>(last)]);
    }
    return operands;
  }

  // The call of a clone that replaces `call` and the consumer of its
  // result, or null.
  func::CallOp raise(func::CallOp call) {
    auto callee = symbols.lookup<func::FuncOp>(call.getCallee());
    if (!callee || callee.isExternal())
      return {};
    std::optional<Consumer> c = consumer(call, callee);
    if (!c)
      return {};
    StringAttr key = consumerKey(callee, *c);
    func::FuncOp clone = raised.lookup(key);
    if (!clone) {
      if (counts.lookup(origin(callee)) >= limit) {
        remark::missed(call.getLoc(),
                       remark::RemarkOpts::name("idr-specialize").category("idr-specialize"))
            << remark::add("{0} of @{1} stopped: the clone limit of {2} clones of @{3} is reached",
                           c->writes() ? "output into" : "arity raising", callee.getSymName(),
                           limit, origin(callee));
        return {};
      }
      clone = makeRaised(callee, call->getResult(0), *c, key);
      raised[key] = clone;
    }
    SmallVector<Value> all(call.getOperands());
    llvm::append_range(all, c->extra());
    std::optional<SmallVector<Value>> operands =
        raisedOperands(clone, all, c->op->getResultTypes());
    if (!operands)
      return {};
    OpBuilder b(c->op);
    auto replacement = func::CallOp::create(b, call.getLoc(), clone, *operands);
    replacement->setDiscardableAttrs(call->getDiscardableAttrDictionary());
    c->op->replaceAllUsesWith(replacement.getResults());
    c->op->erase();
    if (c->field)
      c->field->erase();
    call.erase();
    return replacement;
  }

  //===--------------------------------------------------------------------===//
  // Specialization
  //===--------------------------------------------------------------------===//

  // Whether the call now calls a clone.
  bool specialize(func::CallOp call) {
    auto callee = symbols.lookup<func::FuncOp>(call.getCallee());
    if (!callee || callee.isExternal())
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
      // The world is no runtime value to specialize around: a call whose
      // other operands are constants is closed, as the call that raising
      // gave the world was.
      open |= !isa<idr::ErasedType, idr::WorldType>(operand.getType()) && !closed(operand);
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
    // A stopped call stays stopped while its key is the one it stopped at.
    // Inlining may since have made it more static (a clone chain that built
    // a vector's spine inlined into its caller); then it is checked again.
    std::string keyText;
    llvm::raw_string_ostream keyStream(keyText);
    key.second.print(keyStream);
    if (auto at = call->getAttrOfType<StringAttr>(stoppedAt)) {
      if (at.getValue() == keyText)
        return false;
      call->removeAttr(stopped);
      call->removeAttr(stoppedAt);
    }
    func::FuncOp clone = clones.lookup(key);
    if (!clone) {
      if (grows(own, key.second)) {
        stop(call, callee, keyText,
             llvm::formatv("@{0} passes itself a static value that grows", origin(callee)).str());
        return false;
      }
      if (counts.lookup(origin(callee)) >= limit) {
        stop(call, callee, keyText,
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
    replacement->removeAttr(stopped);
    replacement->removeAttr(stoppedAt);
    call.replaceAllUsesWith(replacement.getResults());
    call.erase();
    return true;
  }

  void run() {
    loadCounts();
    for (auto fn : module.getOps<func::FuncOp>()) {
      if (std::optional<ArrayAttr> key = storedKey(fn))
        clones[{StringAttr::get(module.getContext(), origin(fn)), *key}] = fn;
      else if (auto text = fn->getAttrOfType<StringAttr>(keyAttr); isRaiseKey(text))
        raised.try_emplace(text, fn);
    }
    llvm::append_range(work, module.getOps<func::FuncOp>());
    for (size_t i = 0; i < work.size(); ++i) {
      SmallVector<func::CallOp> calls;
      work[i].walk([&](func::CallOp call) { calls.push_back(call); });
      for (func::CallOp call : calls) {
        // The raised call, if any, is the one to specialize.
        if (func::CallOp raisedCall = raise(call)) {
          changed = true;
          call = raisedCall;
        }
        changed |= specialize(call);
      }
    }
    storeCounts();
  }
};

struct Specialize : idr::impl::IdrSpecializeBase<Specialize> {
  using IdrSpecializeBase::IdrSpecializeBase;
  void runOnOperation() override { Specializer(getOperation(), cloneLimit).run(); }
};

} // namespace
