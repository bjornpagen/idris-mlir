// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-deduplicate, once, after idr-knots: on the first-order program, so
// merging two functions never changes a label set acceptance read.
//
// Monomorphization writes one function per instantiation, and erasure
// leaves some of them one function twice over. The classes are found by
// partition refinement over upstream's equivalence (MLton's and lld's
// shape): every body hashed once, in parallel, its symbol references read
// as one placeholder; an initial partition by facts and that hash; then
// each round splits a class by the classes its members' references name,
// in the order they name them, and the rounds stop when no class splits.
// A class of two members or more is confirmed op for op, each reference
// read as its class's first, so a class is one function twice over, copies
// of one recursion included. Of each class the first in symbol order
// stays; every reference to the others, in a body, as the program's root
// or as a label in a family, names it, and the others go.
//
// A function's facts are its type and every inherent fact a merge must not
// lose (its row, Idris's proof, its binders, what it gives back): all but
// its name. Nothing reads the order the workers
// hashed in: each hash goes to its function's slot, and the classes are
// numbered in program order.

#include "idr/Transforms/Deduplicate.h"

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Actions.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"

#include <map>
#include <vector>

namespace idr {
#define GEN_PASS_DEF_IDRDEDUPLICATE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::deduplicate {

namespace {

// A function's facts, every inherent fact but its name.
Attribute factsOf(FuncOp fn) {
  auto properties = cast<DictionaryAttr>(fn->getPropertiesAsAttribute());
  SmallVector<NamedAttribute> facts;
  for (NamedAttribute attr : properties)
    if (attr.getName() != fn.getSymNameAttrName())
      facts.push_back(attr);
  return DictionaryAttr::get(fn.getContext(), facts);
}

// A body's hash, its values numbered in the order met, its symbol
// references read through `map`.
llvm::hash_code bodyHash(FuncOp fn, OperationEquivalence::MapSymbolRefFn map) {
  llvm::DenseMap<Value, unsigned> number;
  auto valueHash = [&](Value value) {
    auto [at, fresh] = number.try_emplace(value, number.size());
    return llvm::hash_value(at->second);
  };
  llvm::hash_code hash = llvm::hash_value(0);
  fn.getBody().walk<WalkOrder::PreOrder>([&](Operation *op) {
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Value arg : block.getArguments())
          (void)valueHash(arg);
    hash = llvm::hash_combine(hash, OperationEquivalence::computeHash(
                                        op, valueHash, valueHash,
                                        OperationEquivalence::IgnoreLocations, map));
  });
  for (Value arg : fn.getArguments())
    hash = llvm::hash_combine(hash, arg.getType());
  return hash;
}

// Whether two bodies are equivalent op for op, their references read
// through `map`, as upstream compares two regions.
bool sameBody(FuncOp lhs, FuncOp rhs, OperationEquivalence::MapSymbolRefFn map) {
  if (lhs.getFunctionType() != rhs.getFunctionType() || factsOf(lhs) != factsOf(rhs))
    return false;
  llvm::DenseMap<Value, Value> equivalent;
  auto checkEquivalent = [&](Value l, Value r) -> LogicalResult {
    return success(equivalent.lookup(l) == r || l == r);
  };
  auto markEquivalent = [&](Value l, Value r) { equivalent[l] = r; };
  return OperationEquivalence::isRegionEquivalentTo(
      &lhs.getBody(), &rhs.getBody(), checkEquivalent, markEquivalent,
      OperationEquivalence::IgnoreLocations, nullptr, map);
}

// Every reference a body makes to a function of the program, in the order
// upstream's walk of its symbol uses meets them.
SmallVector<unsigned> referencesOf(FuncOp fn, const llvm::DenseMap<StringAttr, unsigned> &index) {
  SmallVector<unsigned> out;
  if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&fn.getBody()))
    for (SymbolTable::SymbolUse use : *uses)
      if (auto found = index.find(use.getSymbolRef().getRootReference()); found != index.end())
        out.push_back(found->second);
  return out;
}

} // namespace

// The digest names a raise copy, so it reads only content the same in
// every process: each op's name, its operands by the number their values
// were met at, its results' types and its attributes and properties by the
// content digest each attribute and type keeps, every symbol reference in
// them read as one placeholder.
llvm::XXH128_hash_t structuralDigest(FuncOp fn) {
  SmallVector<std::uint8_t, 256> bytes;
  auto word = [&](std::uint64_t value) {
    for (unsigned i = 0; i < 8; ++i)
      bytes.push_back(static_cast<std::uint8_t>(value >> (8 * i)));
  };
  auto digest = [&](llvm::XXH128_hash_t value) {
    word(value.low64);
    word(value.high64);
  };
  Attribute placeholder = StringAttr::get(fn.getContext(), "");
  AttrTypeReplacer symbols;
  symbols.addReplacement([&](SymbolRefAttr) -> std::optional<Attribute> { return placeholder; });
  llvm::DenseMap<Value, unsigned> number;
  auto numbered = [&](Value value) {
    return number.try_emplace(value, static_cast<unsigned>(number.size())).first->second;
  };
  for (Value arg : fn.getArguments()) {
    (void)numbered(arg);
    digest(stableDigest(arg.getType()));
  }
  digest(stableDigest(symbols.replace(factsOf(fn))));
  fn.getBody().walk<WalkOrder::PreOrder>([&](Operation *op) {
    StringRef name = op->getName().getStringRef();
    word(name.size());
    bytes.append(name.bytes_begin(), name.bytes_end());
    word(op->getNumOperands());
    for (Value operand : op->getOperands())
      word(numbered(operand));
    for (Value result : op->getResults()) {
      (void)numbered(result);
      digest(stableDigest(result.getType()));
    }
    digest(stableDigest(symbols.replace(op->getRawDictionaryAttrs())));
    digest(stableDigest(symbols.replace(op->getPropertiesAsAttribute())));
    word(op->getNumRegions());
    for (Region &region : op->getRegions())
      for (Block &block : region) {
        word(block.getNumArguments());
        for (Value arg : block.getArguments()) {
          (void)numbered(arg);
          digest(stableDigest(arg.getType()));
        }
      }
  });
  return llvm::xxh3_128bits(bytes);
}

bool equivalent(FuncOp lhs, FuncOp rhs) {
  StringAttr self = lhs.getSymNameAttr(), other = rhs.getSymNameAttr();
  auto map = [&](SymbolRefAttr ref) -> Attribute {
    return ref.getRootReference() == other ? FlatSymbolRefAttr::get(self) : Attribute(ref);
  };
  return sameBody(lhs, rhs, map);
}

} // namespace idr::deduplicate

namespace {

// The merge of one class into its first; the unit is the function kept.
struct DeduplicateMergeAction : idr::support::TaggedAction<DeduplicateMergeAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-deduplicate-merge";
};

struct Deduplicate : idr::impl::IdrDeduplicateBase<Deduplicate> {
  void runOnOperation() override {
    using namespace idr::deduplicate;
    idr::ProgramOp program = getOperation();
    MLIRContext *context = &getContext();
    SmallVector<idr::FuncOp> fns(program.getOps<idr::FuncOp>());
    unsigned n = static_cast<unsigned>(fns.size());
    llvm::DenseMap<StringAttr, unsigned> index;
    for (auto [at, fn] : llvm::enumerate(fns))
      index.try_emplace(fn.getSymNameAttr(), static_cast<unsigned>(at));

    // Each body hashed once, in parallel, its references a placeholder;
    // its references listed in order.
    SmallVector<llvm::hash_code> hashes(n);
    SmallVector<SmallVector<unsigned>> refs(n);
    Attribute placeholder = StringAttr::get(context, "");
    parallelFor(context, 0, n, [&](size_t at) {
      auto map = [&](SymbolRefAttr) -> Attribute { return placeholder; };
      hashes[at] = llvm::hash_combine(bodyHash(fns[at], map), factsOf(fns[at]),
                                      fns[at].getFunctionType());
      refs[at] = referencesOf(fns[at], index);
    });

    // The partition: classes numbered by their first member in program
    // order, refined by the classes each member's references name until
    // their count stops growing.
    SmallVector<unsigned> classOf(n);
    auto renumber = [&](auto &&keyOf) {
      using KeyT = std::decay_t<decltype(keyOf(0u))>;
      std::map<KeyT, unsigned> numbers;
      SmallVector<unsigned> next(n);
      for (unsigned at = 0; at < n; ++at)
        next[at] = numbers.try_emplace(keyOf(at), static_cast<unsigned>(numbers.size())).first->second;
      classOf = std::move(next);
      return static_cast<unsigned>(numbers.size());
    };
    unsigned classes = renumber([&](unsigned at) { return static_cast<size_t>(hashes[at]); });
    while (true) {
      unsigned before = classes;
      classes = renumber([&](unsigned at) {
        std::vector<unsigned> key{classOf[at]};
        for (unsigned ref : refs[at])
          key.push_back(classOf[ref]);
        return key;
      });
      if (classes == before)
        break;
    }

    // Each class of two or more, its first in symbol order, every member
    // confirmed against it op for op, a reference read as its class's first.
    SmallVector<SmallVector<unsigned>> members(classes);
    for (unsigned at = 0; at < n; ++at)
      members[classOf[at]].push_back(at);
    SmallVector<unsigned> first(classes);
    for (auto [c, list] : llvm::enumerate(members)) {
      llvm::sort(list, [&](unsigned a, unsigned b) { return fns[a].getSymName() < fns[b].getSymName(); });
      first[c] = list.front();
    }
    auto representative = [&](SymbolRefAttr ref) -> Attribute {
      auto found = index.find(ref.getRootReference());
      if (found == index.end())
        return ref;
      return FlatSymbolRefAttr::get(fns[first[classOf[found->second]]].getSymNameAttr());
    };
    llvm::DenseMap<StringAttr, StringAttr> renames;
    unsigned groups = 0;
    for (ArrayRef<unsigned> list : members) {
      if (list.size() < 2)
        continue;
      idr::FuncOp kept = fns[list.front()];
      SmallVector<idr::FuncOp> merged;
      for (unsigned at : list.drop_front())
        if (sameBody(kept, fns[at], representative))
          merged.push_back(fns[at]);
      if (merged.empty())
        continue;
      (void)idr::support::perform<DeduplicateMergeAction>(kept, [&] {
        SmallVector<Location> places{kept.getLoc()};
        for (idr::FuncOp fn : merged) {
          renames[fn.getSymNameAttr()] = kept.getSymNameAttr();
          places.push_back(fn.getLoc());
        }
        kept->setLoc(FusedLoc::get(context, places));
        ++groups;
      });
    }
    if (renames.empty())
      return markAllAnalysesPreserved();

    // Every reference to a merged function names the one kept: in bodies,
    // in the types and attributes that hold labels, and as the root.
    AttrTypeReplacer replacer;
    replacer.addReplacement([&](FlatSymbolRefAttr ref) -> std::optional<Attribute> {
      if (StringAttr into = renames.lookup(ref.getAttr()))
        return FlatSymbolRefAttr::get(into);
      return std::nullopt;
    });
    replacer.recursivelyReplaceElementsIn(program, /*replaceAttrs=*/true, /*replaceLocs=*/false,
                                          /*replaceTypes=*/true);
    if (StringAttr root = renames.lookup(program.getRootAttr().getAttr()))
      program.setRootAttr(FlatSymbolRefAttr::get(root));
    for (idr::FuncOp fn : fns)
      if (renames.contains(fn.getSymNameAttr())) {
        fn->erase();
        ++numMerged;
      }
    numGroups += groups;
  }
};

} // namespace
