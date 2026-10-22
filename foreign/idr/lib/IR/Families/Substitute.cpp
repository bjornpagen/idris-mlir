// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one substitution of index terms: levels mapped to terms or to other
// levels in every type upstream's replacer reaches, data types remade in
// normal form; a function instantiated at a call's terms, its impossible
// regions made unreachable in the same rewrite; and the context-free
// matching of one type against another that a region's entry and a jump
// ask of MLIR's verifier.

#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Families/Unify.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::families {

//===----------------------------------------------------------------------===//
// Level maps
//===----------------------------------------------------------------------===//

void LevelMap::replace(uint32_t level, Term term) {
  replaced.push_back({level, SmallVector<TermNode>(term.nodes())});
}

void LevelMap::renumber(uint32_t level, uint32_t to) { renumbered.push_back({level, to}); }

void LevelMap::shiftFrom(uint32_t from, int64_t by) {
  shiftStart = from;
  shift = by;
}

// Preorder from a stack, so a deep term is mapped with no recursion on its
// depth. A replacing term is of the scope written into, so it is copied as
// it is.
void LevelMap::write(TermWriter &out, Term term) const {
  SmallVector<Term> pending{term};
  while (!pending.empty()) {
    Term t = pending.pop_back_val();
    const TermNode &head = t.head();
    if (head.kind == TermKind::Level || head.kind == TermKind::Successor) {
      auto level = static_cast<uint32_t>(head.kind == TermKind::Level ? head.value
                                                                        : t.child(0).head().value);
      uint64_t plus = head.kind == TermKind::Successor ? head.value : 0;
      const auto *with = llvm::find_if(replaced, [&](const auto &r) { return r.first == level; });
      if (with != replaced.end()) {
        out.copy(Term(with->second), plus);
        continue;
      }
      const auto *to = llvm::find_if(renumbered, [&](const auto &r) { return r.first == level; });
      if (to != renumbered.end())
        out.level(to->second, plus);
      else if (level >= shiftStart && shift != 0)
        out.level(static_cast<uint32_t>(static_cast<int64_t>(level) + shift), plus);
      else
        out.level(level, plus);
      continue;
    }
    if (head.kind == TermKind::Constructor) {
      out.constructor(head.payload, head.member, head.value, head.arity);
      for (Term argument : llvm::reverse(t.arguments()))
        pending.push_back(argument);
      continue;
    }
    out.copy(t);
  }
}

namespace {

SmallVector<TermNode> mapTerms(const LevelMap &map, ArrayRef<TermNode> nodes, size_t count) {
  SmallVector<TermNode> out;
  TermWriter write(out);
  for (Term term : termsOf(nodes, count))
    map.write(write, term);
  return out;
}

size_t countOf(ArrayRef<TermNode> nodes) {
  size_t count = 0;
  for (size_t at = 0; at < nodes.size(); at += extentOf(nodes, at))
    ++count;
  return count;
}

// The replacer that maps every index term `map` reaches: in data types,
// naturals, a call's or a jump's terms, and members of `own` named by
// position, which become its data types. A family's declaration is its own
// scope, and the replacer stays out of it.
void addLevelReplacements(AttrTypeReplacer &replacer, const LevelMap &map, FamilyAttr own) {
  replacer.addReplacement([](FamilyAttr group) -> std::optional<std::pair<Attribute, WalkResult>> {
    return std::make_pair(Attribute(group), WalkResult::skip());
  });
  replacer.addReplacement(
      [&map](IndexArgsAttr args) -> std::optional<std::pair<Attribute, WalkResult>> {
        SmallVector<TermNode> terms = mapTerms(map, args.getTerms(), args.getCount());
        return std::make_pair(Attribute(IndexArgsAttr::get(args.getContext(), terms, args.getCount())),
                              WalkResult::skip());
      });
  replacer.addReplacement([&map](NatType nat) -> std::optional<std::pair<Type, WalkResult>> {
    SmallVector<TermNode> index = mapTerms(map, nat.getIndex(), 1);
    return std::make_pair(Type(NatType::get(nat.getContext(), index)), WalkResult::skip());
  });
  replacer.addReplacement([&map](DataType data) -> std::optional<std::pair<Type, WalkResult>> {
    FamilyAttr group = data.getGroup();
    SmallVector<TermNode> indices =
        mapTerms(map, data.getIndices(), group.indices(data.getMember()).size());
    DataType out = DataType::get(data.getContext(), group, data.getMember(), indices);
    if (data.getRefinement()) {
      const TagSet &tags = data.possibleTags();
      if (tags.size() == 1 && !data.getBinders().empty())
        out = out.refinedTo(tags.front(), mapTerms(map, data.getBinders(),
                                                   countOf(data.getBinders())));
      else
        out = out.refined(SmallVector<Tag>(tags.begin(), tags.end()));
    }
    return std::make_pair(Type(out), WalkResult::skip());
  });
  replacer.addReplacement([&map, own](SelfType self) -> std::optional<std::pair<Type, WalkResult>> {
    SmallVector<TermNode> indices = mapTerms(map, self.getIndices(), countOf(self.getIndices()));
    if (own)
      return std::make_pair(Type(DataType::get(self.getContext(), own, self.getMember(), indices)),
                            WalkResult::skip());
    return std::make_pair(Type(SelfType::get(self.getContext(), self.getMember(), indices)),
                          WalkResult::skip());
  });
}

// The map a call's terms make of its callee's `count` binders: an opaque
// term keeps its binder, renumbered among those kept; any other replaces
// it; the levels past the binders move down by those replaced.
LevelMap mapOfArgs(IndexArgsAttr args, uint32_t &kept) {
  LevelMap map;
  kept = 0;
  auto count = static_cast<uint32_t>(args.getCount());
  for (auto [level, term] : llvm::enumerate(termsOf(args.getTerms(), count))) {
    if (term.kind() == TermKind::Opaque)
      map.renumber(static_cast<uint32_t>(level), kept++);
    else
      map.replace(static_cast<uint32_t>(level), term);
  }
  map.shiftFrom(count, static_cast<int64_t>(kept) - static_cast<int64_t>(count));
  return map;
}

} // namespace

Type mapLevels(Type type, const LevelMap &map, FamilyAttr own) {
  if (map.isIdentity() && !own)
    return type;
  AttrTypeReplacer replacer;
  addLevelReplacements(replacer, map, own);
  return replacer.replace(type);
}

SmallVector<Type> instantiateFields(FamilyAttr group, ArrayRef<Type> fields, ArrayRef<Term> binders) {
  LevelMap map;
  for (auto [level, term] : llvm::enumerate(binders))
    map.replace(static_cast<uint32_t>(level), term);
  AttrTypeReplacer replacer;
  addLevelReplacements(replacer, map, group);
  return llvm::map_to_vector(fields, [&](Type field) { return replacer.replace(field); });
}

Type substitute(Type type, IndexArgsAttr args) {
  uint32_t kept;
  return mapLevels(type, mapOfArgs(args, kept));
}

FunctionType substitute(FunctionType type, IndexArgsAttr args) {
  return cast<FunctionType>(substitute(Type(type), args));
}

//===----------------------------------------------------------------------===//
// Rewriting the IR
//===----------------------------------------------------------------------===//

namespace {

// Every type and attribute under `region`, its own blocks' arguments
// included, through `replacer`.
void replaceIn(AttrTypeReplacer &replacer, Region &region) {
  for (Block &block : region) {
    for (BlockArgument arg : block.getArguments())
      arg.setType(replacer.replace(arg.getType()));
    for (Operation &op : block)
      replacer.recursivelyReplaceElementsIn(&op, /*replaceAttrs=*/true, /*replaceLocs=*/false,
                                            /*replaceTypes=*/true);
  }
}

// A region that binds a value no constructor of whose type is possible can
// never be entered (Idris's empty type): its body becomes unreachable, and
// what it held goes with it.
void pruneUninhabited(Operation *root) {
  SmallVector<Region *> dead;
  root->walk([&](Operation *op) {
    for (Region &region : op->getRegions())
      if (!region.empty() && llvm::any_of(region.front().getArguments(), [](BlockArgument arg) {
            auto data = dyn_cast<DataType>(unrestricted(arg.getType()));
            return data && data.possibleTags().empty();
          }))
        dead.push_back(&region);
  });
  for (Region *region : dead) {
    Block &entry = region->front();
    while (region->getBlocks().size() > 1)
      region->back().erase();
    for (Operation &op : llvm::make_early_inc_range(llvm::reverse(entry))) {
      op.dropAllUses();
      op.erase();
    }
    OpBuilder builder = OpBuilder::atBlockEnd(&entry);
    ub::UnreachableOp::create(builder, region->getParentOp()->getLoc());
  }
}

// A cast between two types the substitution made equal is the value.
void foldEqualCasts(Operation *root) {
  root->walk([](DataReindexOp cast) {
    if (cast.getValue().getType() != cast.getType())
      return;
    cast.getResult().replaceAllUsesWith(cast.getValue());
    cast.erase();
  });
}

} // namespace

FailureOr<SmallVector<Sort>> substituteFunction(Operation *function, IndexArgsAttr args) {
  auto binderOp = dyn_cast<ErasedBinderOpInterface>(function);
  if (!binderOp || function->getNumRegions() != 1)
    return function->emitOpError("binds no index variables to instantiate");
  ArrayRef<Sort> binders = binderOp.getBoundSorts(function->getRegion(0));
  if (args.getCount() != binders.size())
    return function->emitOpError("is instantiated at ")
           << args.getCount() << " terms for its " << binders.size() << " index variables";
  uint32_t kept;
  LevelMap map = mapOfArgs(args, kept);
  AttrTypeReplacer replacer;
  addLevelReplacements(replacer, map, FamilyAttr());
  replacer.replaceElementsIn(function, /*replaceAttrs=*/true, /*replaceLocs=*/false,
                             /*replaceTypes=*/true);
  replaceIn(replacer, function->getRegion(0));
  pruneUninhabited(function);
  foldEqualCasts(function);
  SmallVector<Sort> stay;
  for (auto [sort, term] : llvm::zip_equal(binders, termsOf(args.getTerms(), args.getCount())))
    if (term.kind() == TermKind::Opaque)
      stay.push_back(sort);
  return stay;
}

void renumber(Region &region, uint32_t from, uint32_t count, uint32_t to) {
  LevelMap map;
  for (uint32_t i = 0; i < count; ++i)
    map.renumber(from + i, to + i);
  map.shiftFrom(from + count, static_cast<int64_t>(to) - static_cast<int64_t>(from));
  AttrTypeReplacer replacer;
  addLevelReplacements(replacer, map, FamilyAttr());
  replaceIn(replacer, region);
}

IndexArgsAttr levelArgs(MLIRContext *context, uint32_t first, uint32_t count) {
  SmallVector<TermNode> nodes;
  TermWriter write(nodes);
  for (uint32_t i = 0; i < count; ++i)
    write.level(first + i);
  return IndexArgsAttr::get(context, nodes, count);
}

IndexArgsAttr opaqueArgs(MLIRContext *context, uint32_t count) {
  SmallVector<TermNode> nodes;
  TermWriter write(nodes);
  for (uint32_t i = 0; i < count; ++i)
    write.opaque();
  return IndexArgsAttr::get(context, nodes, count);
}

// A binder's term is kept where it makes a data type of the signature
// whose class is unknown one whose class is closed: there its layout
// changes, so the call reaches a copy at that class.
std::optional<IndexArgsAttr> classesUnder(FunctionType signature, IndexArgsAttr args) {
  auto count = static_cast<uint32_t>(args.getCount());
  SmallVector<Term> terms = termsOf(args.getTerms(), count);
  LevelMap closed;
  for (auto [level, term] : llvm::enumerate(terms))
    if (term.isClosed())
      closed.replace(static_cast<uint32_t>(level), term);
  SmallVector<bool> keep(count, false);
  AttrTypeWalker walker;
  walker.addWalk([](FamilyAttr) { return WalkResult::skip(); });
  walker.addWalk([&](DataType data) {
    if (data.cls() != Class::Unknown)
      return WalkResult::advance();
    auto mapped = cast<DataType>(mapLevels(data, closed));
    if (mapped.cls() == Class::Closed)
      for (const TermNode &node : data.getIndices())
        if (node.kind == TermKind::Level && node.value < count && terms[node.value].isClosed())
          keep[node.value] = true;
    return WalkResult::advance();
  });
  walker.walk(signature);
  if (llvm::none_of(keep, [](bool k) { return k; }))
    return std::nullopt;
  SmallVector<TermNode> nodes;
  TermWriter write(nodes);
  for (auto [level, term] : llvm::enumerate(terms)) {
    if (keep[level])
      write.copy(term);
    else
      write.opaque();
  }
  return IndexArgsAttr::get(signature.getContext(), nodes, count);
}

} // namespace idr::families
