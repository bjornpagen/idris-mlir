// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-deduplicate, once, after idr-knots: on the first-order program, so
// merging two functions never changes a label set acceptance read.
//
// Monomorphization writes one function per instantiation, and erasure
// leaves some of them one function twice over. The classes are found by
// partition refinement over upstream's equivalence (MLton's and lld's
// shape): every function hashed once, its symbol references read as one
// placeholder; an initial partition by that hash; then each round splits a
// class by the classes its members' references name, in the order they name
// them, until no class splits. Each class of two members or more is then
// confirmed op for op, each reference read as its class's first. A class
// whose members differ, which only two unequal functions of one hash make,
// splits by what its members are, and the rounds run again over the finer
// partition, since a reference to it now tells its callers apart; so the
// partition merged is one in which every member is its class's first op
// for op, copies of one recursion included, and a merge never rests on a
// hash. Of each class the first in symbol order stays; every reference to
// the others, in a body, as the program's root or as a label in a family,
// names it, and the others go.
//
// A label names its function wherever it stands: in an op's attributes, and
// in every type a family holds. So every reading (the hash, the rounds, the
// confirmation) reads the references in types with those in attributes:
// two functions whose values' types differ only in which of two equal
// functions a label names are one function.
//
// A function's facts are its type and every inherent fact a merge must not
// lose (its row, Idris's proof, its binders, what it gives back): all but
// its name. The pass runs on one thread, since every reading makes the
// attributes and types its map gives, and the classes are numbered in
// program order.

#include "idr/Transforms/Deduplicate.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Actions.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/OperationSupport.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"

#include <map>
#include <utility>
#include <vector>

namespace idr {
#define GEN_PASS_DEF_IDRDEDUPLICATE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::deduplicate {

namespace {

using MapRef = OperationEquivalence::MapSymbolRefFn;

// A function's facts, every inherent fact but its name.
Attribute factsOf(FuncOp fn) {
  auto properties = cast<DictionaryAttr>(fn->getPropertiesAsAttribute());
  SmallVector<NamedAttribute> facts;
  for (NamedAttribute attr : properties)
    if (attr.getName() != fn.getSymNameAttrName())
      facts.push_back(attr);
  return DictionaryAttr::get(fn.getContext(), facts);
}

// What reads every symbol reference of an attribute or a type, in the types
// it holds too, through `map`, which gives a reference of its own kind, as
// a family's label holds one. Its cache holds each attribute's and type's
// answer, a function of that attribute or type alone, so one serves a whole
// reading.
AttrTypeReplacer readingThrough(MapRef map) {
  AttrTypeReplacer replacer;
  replacer.addReplacement([map](SymbolRefAttr ref) -> std::optional<Attribute> { return map(ref); });
  return replacer;
}

// A value as the hash reads it: where it comes from, by position and never
// by identity, a block's argument by its number, an op's result by the
// op's name and the result's number. Equal functions hash alike; the
// confirmation compares the values themselves.
llvm::hash_code positionOf(Value value) {
  if (auto arg = dyn_cast<BlockArgument>(value))
    return llvm::hash_combine(0, arg.getArgNumber());
  auto result = cast<OpResult>(value);
  return llvm::hash_combine(1, result.getOwner()->getName(), result.getResultNumber());
}

// A function's hash: its facts, then each op and the arguments of each of
// its regions' blocks, every symbol reference read through `map`.
llvm::hash_code hashOf(FuncOp fn, MapRef map) {
  AttrTypeReplacer read = readingThrough(map);
  llvm::hash_code hash = llvm::hash_value(read.replace(factsOf(fn)));
  fn.getBody().walk<WalkOrder::PreOrder>([&](Operation *op) {
    hash = llvm::hash_combine(hash, OperationEquivalence::computeHash(
                                        op, positionOf, OperationEquivalence::ignoreHashValue,
                                        OperationEquivalence::IgnoreLocations, map));
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Type type : block.getArgumentTypes())
          hash = llvm::hash_combine(hash, read.replace(type));
  });
  return hash;
}

// Whether two functions are one when every symbol reference is read
// through `map`: equal facts, and bodies equivalent op for op, as upstream
// compares two regions.
bool sameBody(FuncOp lhs, FuncOp rhs, MapRef map) {
  AttrTypeReplacer read = readingThrough(map);
  if (read.replace(factsOf(lhs)) != read.replace(factsOf(rhs)))
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

// Every reference a function makes to a function of the program, in the
// order one walk meets them: its facts, then each op in pre-order, its
// attributes, its properties, its results' types and its regions'
// arguments' types. Each distinct attribute or type is walked once and its
// references listed again wherever it stands again, so two functions
// alike but for their references list them at the same places.
SmallVector<unsigned> referencesOf(FuncOp fn, const llvm::DenseMap<StringAttr, unsigned> &index) {
  SmallVector<unsigned> out;
  llvm::DenseMap<Attribute, SmallVector<unsigned, 2>> inAttributes;
  llvm::DenseMap<Type, SmallVector<unsigned, 2>> inTypes;
  auto list = [&](auto element, auto &held) {
    if (!element)
      return;
    auto [at, fresh] = held.try_emplace(element);
    if (fresh)
      element.walk([&, &refs = at->second](SymbolRefAttr ref) {
        if (auto found = index.find(ref.getRootReference()); found != index.end())
          refs.push_back(found->second);
      });
    llvm::append_range(out, at->second);
  };
  list(factsOf(fn), inAttributes);
  fn.getBody().walk<WalkOrder::PreOrder>([&](Operation *op) {
    list(Attribute(op->getRawDictionaryAttrs()), inAttributes);
    list(op->getPropertiesAsAttribute(), inAttributes);
    for (Type type : op->getResultTypes())
      list(type, inTypes);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Type type : block.getArgumentTypes())
          list(type, inTypes);
  });
  return out;
}

} // namespace

// The digest names a raise copy, so it reads only content the same in
// every process: each op's name, its operands by the number their values
// were met at, its results' types and its attributes and properties by the
// content digest each attribute and type keeps, a symbol reference by the
// name it holds. Two consumers that call different functions are two
// forms, and their copies two names.
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
  auto attribute = [&](Attribute attr) {
    word(attr ? 1 : 0);
    if (attr)
      digest(stableDigest(attr));
  };
  llvm::DenseMap<Value, unsigned> number;
  auto numbered = [&](Value value) {
    return number.try_emplace(value, static_cast<unsigned>(number.size())).first->second;
  };
  for (Value arg : fn.getArguments()) {
    (void)numbered(arg);
    digest(stableDigest(arg.getType()));
  }
  attribute(factsOf(fn));
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
    attribute(op->getRawDictionaryAttrs());
    attribute(op->getPropertiesAsAttribute());
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
  void runOnProgram(idr::ProgramOp program) {
    using namespace idr::deduplicate;
    MLIRContext *context = &getContext();
    SmallVector<idr::FuncOp> fns(program.getOps<idr::FuncOp>());
    auto n = static_cast<unsigned>(fns.size());
    llvm::DenseMap<StringAttr, unsigned> index;
    for (auto [at, fn] : llvm::enumerate(fns))
      index.try_emplace(fn.getSymNameAttr(), static_cast<unsigned>(at));

    // Each function hashed once, every reference one placeholder of a
    // reference's own kind; its references listed in order.
    SmallVector<llvm::hash_code> hashes;
    SmallVector<SmallVector<unsigned>> refs;
    auto placeholder = FlatSymbolRefAttr::get(StringAttr::get(context, ""));
    auto anyReference = [&](SymbolRefAttr) -> Attribute { return placeholder; };
    for (idr::FuncOp fn : fns) {
      hashes.push_back(hashOf(fn, anyReference));
      refs.push_back(referencesOf(fn, index));
    }

    // The partition: classes numbered by their first member in program
    // order, refined by the classes each member's references name until
    // their count stops growing.
    SmallVector<unsigned> classOf(n);
    unsigned classes = 0;
    auto renumber = [&](auto &&keyOf) {
      using KeyT = std::decay_t<decltype(keyOf(0u))>;
      std::map<KeyT, unsigned> numbers;
      SmallVector<unsigned> next(n);
      for (unsigned at = 0; at < n; ++at)
        next[at] = numbers.try_emplace(keyOf(at), static_cast<unsigned>(numbers.size())).first->second;
      classOf = std::move(next);
      classes = static_cast<unsigned>(numbers.size());
    };
    auto refine = [&] {
      while (true) {
        unsigned before = classes;
        renumber([&](unsigned at) {
          std::vector<unsigned> key{classOf[at]};
          for (unsigned ref : refs[at])
            key.push_back(classOf[ref]);
          return key;
        });
        if (classes == before)
          return;
      }
    };
    renumber([&](unsigned at) { return static_cast<std::size_t>(hashes[at]); });

    // Each class's members in symbol order, each confirmed against the
    // first of its part, a reference read as its class's first; a class
    // whose members differ splits into its parts and the rounds run again.
    SmallVector<SmallVector<unsigned>> members;
    auto representative = [&](SymbolRefAttr ref) -> Attribute {
      auto found = index.find(ref.getRootReference());
      if (found == index.end())
        return ref;
      return FlatSymbolRefAttr::get(fns[members[classOf[found->second]].front()].getSymNameAttr());
    };
    while (true) {
      refine();
      members.assign(classes, {});
      for (unsigned at = 0; at < n; ++at)
        members[classOf[at]].push_back(at);
      for (SmallVector<unsigned> &list : members)
        llvm::sort(list, [&](unsigned a, unsigned b) { return fns[a].getSymName() < fns[b].getSymName(); });
      SmallVector<unsigned> part(n, 0);
      bool split = false;
      for (ArrayRef<unsigned> list : members) {
        SmallVector<unsigned, 2> firsts{list.front()};
        for (unsigned at : list.drop_front()) {
          auto same = llvm::find_if(firsts, [&](unsigned first) {
            return sameBody(fns[first], fns[at], representative);
          });
          part[at] = static_cast<unsigned>(same - firsts.begin());
          if (same == firsts.end()) {
            firsts.push_back(at);
            split = true;
          }
        }
      }
      if (!split)
        break;
      renumber([&](unsigned at) { return std::pair(classOf[at], part[at]); });
    }

    // Of each class of two or more, the first in symbol order stays.
    llvm::DenseMap<StringAttr, StringAttr> renames;
    unsigned groups = 0;
    for (ArrayRef<unsigned> list : members) {
      if (list.size() < 2)
        continue;
      idr::FuncOp kept = fns[list.front()];
      (void)idr::support::perform<DeduplicateMergeAction>(kept, [&] {
        SmallVector<Location> places{kept.getLoc()};
        for (unsigned at : list.drop_front()) {
          renames[fns[at].getSymNameAttr()] = kept.getSymNameAttr();
          places.push_back(fns[at].getLoc());
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
