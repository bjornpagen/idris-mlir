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

#include "idr/Analysis/Solver/Extraction.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/Generated/Actions.h.inc"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Tail.h"
#include "idr/Support/Actions.h"
#include "idr/Support/Changed.h"
#include "idr/Support/Footprint.h"

#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/OperationSupport.h"
#include "llvm/ADT/STLExtras.h"

#include <concepts>
#include <map>
#include <utility>
#include <vector>

#define GEN_PASS_DEF_IDRDEDUPLICATE
#include "idr/IR/Generated/PassDialects.h.inc"

namespace idr {
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
  // An attribute's hash is mlir's, found by its argument's namespace.
  llvm::hash_code hash = hash_value(read.replace(factsOf(fn)));
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

// A function's values by its one numbering, in walk order.
struct BodyValue {
  using Minter = solver::Numbering<BodyValue>;
};

// Whether two functions are one when every symbol reference is read
// through `map`: equal facts, and bodies equivalent op for op, as upstream
// compares two regions. Each value of `lhs` holds the value of `rhs` it
// stands for, by its number; a function is isolated, so every value
// compared is one of its own.
bool sameBody(FuncOp lhs, FuncOp rhs, MapRef map) {
  AttrTypeReplacer read = readingThrough(map);
  if (read.replace(factsOf(lhs)) != read.replace(factsOf(rhs)))
    return false;
  solver::Numbering<BodyValue> numbering(lhs);
  IndexVector<BodyValue::Minter::Node, Value> equivalent(numbering.size(), Value());
  auto checkEquivalent = [&](Value l, Value r) -> LogicalResult {
    return success(equivalent[numbering.at(l)] == r);
  };
  auto markEquivalent = [&](Value l, Value r) { equivalent[numbering.at(l)] = r; };
  return OperationEquivalence::isRegionEquivalentTo(
      &lhs.getBody(), &rhs.getBody(), checkEquivalent, markEquivalent,
      OperationEquivalence::IgnoreLocations, nullptr, map);
}

// Every reference a function makes to a function of the program, by the
// position `positionOf` gives the function named, in the order one walk
// meets them: its facts, then each op in pre-order, its attributes, its
// properties, its results' types and its regions' arguments' types. Each
// distinct attribute or type is walked once and its references listed
// again wherever it stands again, so two functions alike but for their
// references list them at the same places.
template <std::invocable<SymbolRefAttr> PositionOf>
SmallVector<unsigned> referencesOf(FuncOp fn, PositionOf &&positionOf) {
  SmallVector<unsigned> out;
  footprint::DenseMap<Attribute, SmallVector<unsigned, 2>> inAttributes;
  footprint::DenseMap<Type, SmallVector<unsigned, 2>> inTypes;
  auto list = [&](auto element, auto &held) {
    if (!element)
      return;
    auto [at, fresh] = held.try_emplace(element);
    if (fresh)
      element.walk([&, &refs = at->second](SymbolRefAttr ref) { refs.push_back(positionOf(ref)); });
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
// every process: each op's name, its operands by their values' numbers in
// the function's one numbering, its results' types and its attributes and
// properties by the content digest each attribute and type keeps, a symbol
// reference by the name it holds. Two consumers that call different
// functions are two forms, and their copies two names.
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
  solver::Numbering<BodyValue> numbering(fn);
  for (Value arg : fn.getArguments())
    digest(stableDigest(arg.getType()));
  attribute(factsOf(fn));
  fn.getBody().walk<WalkOrder::PreOrder>([&](Operation *op) {
    StringRef name = op->getName().getStringRef();
    word(name.size());
    bytes.append(name.bytes_begin(), name.bytes_end());
    word(op->getNumOperands());
    for (Value operand : op->getOperands())
      word(numbering.at(operand).index());
    for (Value result : op->getResults())
      digest(stableDigest(result.getType()));
    attribute(op->getRawDictionaryAttrs());
    attribute(op->getPropertiesAsAttribute());
    word(op->getNumRegions());
    for (Region &region : op->getRegions())
      for (Block &block : region) {
        word(block.getNumArguments());
        for (Value arg : block.getArguments())
          digest(stableDigest(arg.getType()));
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
  static constexpr std::string_view tag = ::idr::actions::deduplicateMerge;
};

struct Deduplicate : idr::impl::IdrDeduplicateBase<Deduplicate> {
  void runOnProgram(idr::ProgramOp program) {
    using namespace idr::deduplicate;
    MLIRContext *context = &getContext();
    auto held = program.getOps<idr::FuncOp>();
    idr::footprint::Vector<idr::FuncOp> fns(held.begin(), held.end());
    auto n = static_cast<unsigned>(fns.size());
    // Each function's position in program order, by the program's one
    // numbering of its functions; every symbol a function names is one of
    // them, the dialect's only symbol.
    const idr::solver::ProgramGraph &graph = getAnalysis<idr::solver::ProgramGraph>();
    idr::IndexVector<idr::solver::FunctionId, unsigned> position = graph.table<unsigned>(0);
    for (auto [at, fn] : llvm::enumerate(fns))
      position[graph.id(fn)] = static_cast<unsigned>(at);
    auto positionOf = [&](SymbolRefAttr ref) {
      return position[graph.id(cast<FlatSymbolRefAttr>(ref))];
    };

    // Each function hashed once, every reference one placeholder of a
    // reference's own kind; its references listed in order.
    idr::footprint::Vector<llvm::hash_code> hashes;
    idr::footprint::Vector<SmallVector<unsigned>> refs;
    auto placeholder = FlatSymbolRefAttr::get(StringAttr::get(context, ""));
    auto anyReference = [&](SymbolRefAttr) -> Attribute { return placeholder; };
    for (idr::FuncOp fn : fns) {
      hashes.push_back(hashOf(fn, anyReference));
      refs.push_back(referencesOf(fn, positionOf));
    }

    // The partition: classes numbered by their first member in program
    // order, refined by the classes each member's references name until
    // their count stops growing.
    idr::footprint::Vector<unsigned> classOf(n);
    unsigned classes = 0;
    auto renumber = [&](auto &&keyOf) {
      using KeyT = std::decay_t<decltype(keyOf(0u))>;
      std::map<KeyT, unsigned, std::less<KeyT>,
               idr::footprint::Allocator<std::pair<const KeyT, unsigned>>>
          numbers;
      idr::footprint::Vector<unsigned> next(n);
      for (unsigned at = 0; at < n; ++at)
        next[at] = numbers.try_emplace(keyOf(at), static_cast<unsigned>(numbers.size())).first->second;
      classOf = std::move(next);
      classes = static_cast<unsigned>(numbers.size());
    };
    // A round's key holds each function's class, so a round only splits
    // classes, and there are never more classes than functions: the rounds
    // end with the first that splits none.
    auto refine = [&] {
      unsigned before;
      do {
        before = classes;
        renumber([&](unsigned at) {
          idr::footprint::Vector<unsigned> key{classOf[at]};
          for (unsigned ref : refs[at])
            key.push_back(classOf[ref]);
          return key;
        });
      } while (classes != before);
    };
    renumber([&](unsigned at) { return static_cast<std::size_t>(hashes[at]); });

    // Each class's members in symbol order, each confirmed against the
    // first of its part, a reference read as its class's first; a class
    // whose members differ splits into its parts and the rounds run again.
    idr::footprint::Vector<SmallVector<unsigned>> members;
    auto representative = [&](SymbolRefAttr ref) -> Attribute {
      idr::FuncOp first = fns[members[classOf[positionOf(ref)]].front()];
      return FlatSymbolRefAttr::get(first.getSymNameAttr());
    };
    // The part of its class each function is confirmed in, and whether any
    // class split.
    struct Parts {
      idr::footprint::Vector<unsigned> of;
      idr::Changed split;
    };
    auto confirm = [&] {
      refine();
      members.assign(classes, {});
      for (unsigned at = 0; at < n; ++at)
        members[classOf[at]].push_back(at);
      for (SmallVector<unsigned> &list : members)
        llvm::sort(list, [&](unsigned a, unsigned b) { return fns[a].getSymName() < fns[b].getSymName(); });
      Parts parts{idr::footprint::Vector<unsigned>(n, 0), idr::Changed::No};
      for (ArrayRef<unsigned> list : members) {
        SmallVector<unsigned, 2> firsts{list.front()};
        for (unsigned at : list.drop_front()) {
          auto same = llvm::find_if(firsts, [&](unsigned first) {
            return sameBody(fns[first], fns[at], representative);
          });
          parts.of[at] = static_cast<unsigned>(same - firsts.begin());
          if (same == firsts.end()) {
            firsts.push_back(at);
            parts.split = idr::Changed::Yes;
          }
        }
      }
      return parts;
    };
    // A split adds a class, and there are never more classes than
    // functions, so the rounds end with the first in which none splits.
    for (Parts parts = confirm(); parts.split == idr::Changed::Yes; parts = confirm())
      renumber([&](unsigned at) { return std::pair(classOf[at], parts.of[at]); });

    // Of each class of two or more, the first in symbol order stays: each
    // other member, by its id, holds the name of the one kept.
    idr::IndexVector<idr::solver::FunctionId, StringAttr> keptAs = graph.table<StringAttr>();
    auto renamed = [&](FlatSymbolRefAttr ref) { return keptAs[graph.id(ref)]; };
    unsigned groups = 0;
    for (ArrayRef<unsigned> list : members) {
      if (list.size() < 2)
        continue;
      idr::FuncOp kept = fns[list.front()];
      (void)idr::support::perform<DeduplicateMergeAction>(kept, [&] {
        SmallVector<Location> places{kept.getLoc()};
        for (unsigned at : list.drop_front()) {
          keptAs[graph.id(fns[at])] = kept.getSymNameAttr();
          places.push_back(fns[at].getLoc());
        }
        kept->setLoc(FusedLoc::get(context, places));
        ++groups;
      });
    }
    if (groups == 0)
      return markAllAnalysesPreserved();

    // A call of a merged function, in a function that stays, calls the one
    // kept, which may be its own function now: each takes the tail fact its
    // place gives it once it names the one kept.
    SmallVector<idr::CallOp> redirected;
    for (idr::FuncOp fn : fns)
      if (!keptAs[graph.id(fn)])
        fn.walk([&](idr::CallOp call) {
          if (renamed(call.getCalleeAttr()))
            redirected.push_back(call);
        });
    // Every reference to a merged function names the one kept: in bodies,
    // in the types and attributes that hold labels, and as the root.
    AttrTypeReplacer replacer;
    replacer.addReplacement([&](FlatSymbolRefAttr ref) -> std::optional<Attribute> {
      if (StringAttr into = renamed(ref))
        return FlatSymbolRefAttr::get(into);
      return std::nullopt;
    });
    replacer.recursivelyReplaceElementsIn(program, /*replaceAttrs=*/true, /*replaceLocs=*/false,
                                          /*replaceTypes=*/true);
    if (StringAttr root = renamed(program.getRootAttr()))
      program.setRootAttr(FlatSymbolRefAttr::get(root));
    for (idr::CallOp call : redirected)
      call.setTailKind(idr::tail::decide(call));
    for (idr::FuncOp fn : fns)
      if (keptAs[graph.id(fn)]) {
        fn->erase();
        ++numMerged;
      }
    numGroups += groups;
  }
};

} // namespace
