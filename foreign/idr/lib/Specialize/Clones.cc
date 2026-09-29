// The clone table: parsing the clones of earlier runs, naming, counting.

#include "Specialize/Clones.h"

using namespace mlir;

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
  Attribute key = fn->getAttr(kKeyAttr);
  if (!isa_and_nonnull<SpecKeyAttr, KeyApplyAttr, KeyApplyFieldAttr, KeyWriteAttr>(key))
    return std::nullopt;
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
    if (fn->hasAttr(kKeyAttr))
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
  // What the other passes know a clone by: the loop breakers pick the
  // newest in a cycle.
  clone->setAttr("idr.origin", owner);
  table.insert(clone, module.getBody()->end());
  return clone;
}

const Clone &CloneTable::add(Attribute key, func::FuncOp fn) {
  fn->setAttr(kKeyAttr, key);
  std::optional<Clone> clone = parse(fn);
  assert(clone && "idr-specialize: a clone whose parameters hold no holes in order");
  keyOf[fn.getOperation()] = key;
  return byKey.insert_or_assign(key, std::move(*clone)).first->second;
}

std::optional<SmallVector<Value>> operandsFor(const Clone &clone,
                                              ArrayRef<std::optional<Value>> holes) {
  func::FuncOp fn = clone.fn;
  SmallVector<Value> out;
  for (auto [hole, type] : llvm::zip(clone.holes, fn.getArgumentTypes())) {
    if (hole >= holes.size() || !holes[hole] || holes[hole]->getType() != type)
      return std::nullopt;
    out.push_back(*holes[hole]);
  }
  return out;
}

DictionaryAttr parameterAttrs(MLIRContext *ctx, unsigned hole, DictionaryAttr from) {
  NamedAttrList list(from);
  list.set(kHoleAttr, IntegerAttr::get(IntegerType::get(ctx, 64), hole));
  return list.getDictionary(ctx);
}

} // namespace idr::specialize
