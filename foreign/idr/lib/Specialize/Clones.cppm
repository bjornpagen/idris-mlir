// idr.specialize:clones: the clones of a module by key.
//
// A clone keeps its key as `idr.clone`, a typed attribute that names the
// clone too, and each of its parameters the hole of the key it holds as
// `idr.hole`, so that the next run shares the clone. A clone is parsed
// once, when the table meets it; one whose marks do not parse is no clone
// to the table, only a function.
module;
// assert is a macro, which no import carries.
#include <cassert>

export module idr.specialize:clones;

import idr.mlir;
import idr.dialect;

using namespace mlir;

export namespace idr::specialize {

// The clones of one owner, over the whole compilation, past which the
// construction is broken: every key is drawn from a finite set, and a run
// that makes this many has found a set that is not.
constexpr unsigned kClonesPerOwner = 1024;

inline constexpr llvm::StringLiteral kCloneAttr = "idr.clone";
inline constexpr llvm::StringLiteral kHoleAttr = "idr.hole";

// A clone as the table knows it: its key, and the hole each parameter
// holds, in increasing order.
struct Clone {
  mlir::func::FuncOp fn;
  mlir::Attribute key;
  llvm::SmallVector<unsigned> holes;
};

class CloneTable {
public:
  explicit CloneTable(mlir::ModuleOp module);

  const Clone *lookup(mlir::Attribute key) const;

  // The clone `fn` is, or null for a function that is none (or that shares
  // its key with a clone the table met first).
  const Clone *find(mlir::func::FuncOp fn) const;

  // The clone `fn` is, if it specializes: calls of it are keyed by its
  // owner's parameters.
  const Clone *specialization(mlir::func::FuncOp fn) const;

  // The function whose parameters the keys of calls of `fn` describe: a
  // clone that specializes describes its owner's, any other function its
  // own.
  mlir::StringAttr ownerOf(mlir::func::FuncOp fn) const;

  // A copy of `from` for `owner`, named `<owner>$<kind>$<n>`, in the module
  // but not yet in the table; the error `unsupported (compile-time budget)`
  // at `at` once `owner` has had kClonesPerOwner.
  mlir::FailureOr<mlir::func::FuncOp> copy(mlir::func::FuncOp from, mlir::StringAttr owner,
                                           llvm::StringRef kind, mlir::Operation *at);

  // `fn`, whose parameters hold the holes their `idr.hole` says, as the
  // clone for `key`.
  const Clone &add(mlir::Attribute key, mlir::func::FuncOp fn);

  // Settles whether `clone`, just made from its callee and simplified, is a
  // loop breaker. It runs its callee's loop, so it breaks the loop where its
  // callee does: it keeps the no_inline it was copied with, unless no call
  // in it can come back to it, because it `unrolls` (a decreasing
  // parameter, whose keys shrink along the chain of clones) or because it
  // refers to no function.
  void settleBreaker(mlir::func::FuncOp clone, bool unrolls);

  mlir::SymbolTable &symbols();

private:
  static std::optional<Clone> parse(mlir::func::FuncOp fn);

  mlir::ModuleOp module;
  mlir::SymbolTable table;
  llvm::DenseMap<mlir::Attribute, Clone> byKey;
  llvm::DenseMap<mlir::Operation *, mlir::Attribute> keyOf;
  // The clones of each owner, counted from their names.
  llvm::StringMap<unsigned> counts;
};

} // namespace idr::specialize

namespace idr::specialize {

namespace {

// `<owner>$<kind>$<n>`: the owner and n of a clone's name.
std::optional<std::pair<StringRef, unsigned>> parseName(StringRef name) {
  size_t dollar = name.rfind('$');
  unsigned n = 0;
  if (dollar == StringRef::npos || name.drop_front(dollar + 1).getAsInteger(10, n))
    return std::nullopt;
  StringRef rest = name.take_front(dollar);
  for (StringRef kind : {"$spec", "$raise"})
    if (rest.consume_back(kind))
      return std::make_pair(rest, n);
  return std::nullopt;
}

// The number of holes of a key's patterns.
unsigned holesOf(ArrayAttr patterns) {
  unsigned n = 0;
  for (Attribute pattern : patterns)
    pattern.walk([&](KeyHoleAttr) { ++n; });
  return n;
}

} // namespace

std::optional<Clone> CloneTable::parse(func::FuncOp fn) {
  auto clone = fn->getAttrOfType<CloneAttr>(kCloneAttr);
  if (!clone)
    return std::nullopt;
  Attribute key = clone.getKey();
  Clone out{fn, key, {}};
  for (unsigned i = 0; i < fn.getNumArguments(); ++i) {
    auto hole = fn.getArgAttrOfType<IntegerAttr>(i, kHoleAttr);
    if (!hole || hole.getInt() < 0 ||
        (!out.holes.empty() && hole.getInt() <= static_cast<int64_t>(out.holes.back())))
      return std::nullopt;
    out.holes.push_back(static_cast<unsigned>(hole.getInt()));
  }
  // A specialization's parameters hold holes of its key; a raised clone's
  // are checked where it is called, against the operands at hand.
  if (auto spec = dyn_cast<SpecKeyAttr>(key);
      spec && !out.holes.empty() && out.holes.back() >= holesOf(spec.getPatterns()))
    return std::nullopt;
  return out;
}

CloneTable::CloneTable(ModuleOp root) : module(root), table(root) {
  for (auto fn : module.getOps<func::FuncOp>()) {
    if (std::optional<Clone> clone = parse(fn)) {
      keyOf.try_emplace(fn.getOperation(), clone->key);
      byKey.try_emplace(clone->key, std::move(*clone));
    }
    if (fn->hasAttr(kCloneAttr))
      if (auto named = parseName(fn.getSymName())) {
        unsigned &count = counts[named->first];
        count = std::max(count, named->second);
      }
  }
}

const Clone *CloneTable::lookup(Attribute key) const {
  auto it = byKey.find(key);
  return it == byKey.end() ? nullptr : &it->second;
}

const Clone *CloneTable::find(func::FuncOp fn) const {
  Attribute key = keyOf.lookup(fn.getOperation());
  const Clone *clone = key ? lookup(key) : nullptr;
  return clone && clone->fn == fn ? clone : nullptr;
}

const Clone *CloneTable::specialization(func::FuncOp fn) const {
  Attribute key = keyOf.lookup(fn.getOperation());
  return isa_and_nonnull<SpecKeyAttr>(key) ? lookup(key) : nullptr;
}

StringAttr CloneTable::ownerOf(func::FuncOp fn) const {
  if (const Clone *clone = specialization(fn))
    return cast<SpecKeyAttr>(clone->key).getOrigin();
  return fn.getSymNameAttr();
}

FailureOr<func::FuncOp> CloneTable::copy(func::FuncOp from, StringAttr owner, StringRef kind,
                                         Operation *at) {
  unsigned n = ++counts[owner.getValue()];
  if (n > kClonesPerOwner)
    return at->emitError() << "unsupported (compile-time budget): specializing @"
                           << owner.getValue() << " made more than " << kClonesPerOwner
                           << " clones of it";
  func::FuncOp clone = from.clone();
  clone.setSymName((owner.getValue() + "$" + kind + "$" + Twine(n)).str());
  clone.setPrivate();
  table.insert(clone, module.getBody()->end());
  return clone;
}

const Clone &CloneTable::add(Attribute key, func::FuncOp fn) {
  fn->setAttr(kCloneAttr, CloneAttr::get(fn.getContext(), FlatSymbolRefAttr::get(fn.getSymNameAttr()), key));
  std::optional<Clone> clone = parse(fn);
  assert(clone && "idr-specialize: a clone whose parameters hold no holes in order");
  keyOf[fn.getOperation()] = key;
  return byKey.insert_or_assign(key, std::move(*clone)).first->second;
}

void CloneTable::settleBreaker(func::FuncOp clone, bool unrolls) {
  std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&clone.getBody());
  bool refers = uses && llvm::any_of(*uses, [&](const SymbolTable::SymbolUse &use) {
    return table.lookup<func::FuncOp>(use.getSymbolRef().getRootReference());
  });
  if (unrolls || !refers)
    clone.setNoInline(false);
}

SymbolTable &CloneTable::symbols() { return table; }

} // namespace idr::specialize
