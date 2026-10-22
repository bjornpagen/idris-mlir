// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one substitution of index terms: levels mapped to terms or to other
// levels in every type upstream's replacer reaches, data types remade in
// normal form; a function instantiated at a call's terms, its impossible
// regions made unreachable in the same rewrite, each bare tensor
// argument's axis whose extent becomes a size made static, and every type
// derived from the parameters inferred again; and the context-free
// matching of one type against another that a region's entry and a jump
// ask of MLIR's verifier.

#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Families/Unify.h"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/InferTypeOpInterface.h"
#include "llvm/ADT/STLExtras.h"

#include <cassert>
#include <limits>
#include <optional>

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
      for (Term argument : llvm::reverse(argumentsOf(t)))
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

// The size an extent's mapped term makes its axis: a natural a dimension
// holds. A dimension is a signed word whose least value is MLIR's `?`, so a
// natural past it is no size, as a natural past a word is opaque; no
// machine holds an array that long, so its axis stays `?` and no program is
// refused for it.
std::optional<int64_t> sizeOf(Term term) {
  if (term.kind() != TermKind::Natural ||
      term.head().value > static_cast<uint64_t>(std::numeric_limits<int64_t>::max()))
    return std::nullopt;
  return static_cast<int64_t>(term.head().value);
}

// What an axis becomes where its term is a size, by the side it is on:
// static on an input; kept on a result, which keeps the callee's type,
// since a cast after a call would take a tail call out of tail position and
// a caller learns no more from a result than its own types say.
enum class AtSize { Static, Kept };

// The array whose axis `at` becomes static once its term is a size: a bare
// tensor argument's, which tensor.cast reaches. A graded array keeps its
// axis `?`, since no cast keeps a grade; that leaves the program less
// optimized and refuses nothing.
RankedTensorType staticArray(ArrayRef<Type> inputs, ExtentAt at) {
  if (onSide(at.side, AtSize::Static, AtSize::Kept) == AtSize::Kept)
    return {};
  return dyn_cast<RankedTensorType>(inputs[at.position]);
}

// A signature and its extents under one level map, read once: what
// substitute gives a call's view and substituteFunction gives the copy, so
// the two cannot disagree on an axis.
struct Signature {
  SmallVector<Type> inputs;
  SmallVector<Type> results;
  // The inputs a size made static, each once and in order.
  SmallVector<uint32_t> fixed;
  // Null where no entry stays, as a function that names none has it.
  ExtentsAttr extents;

  FunctionType type(MLIRContext *context) const {
    return FunctionType::get(context, inputs, results);
  }
};

// `type` and its `extents` under `map`: every family type mapped, and each
// entry's term written through the same map. A term that still names a
// level stays an entry. One that names none is a size or opaque, and an
// entry's term names a binder, so its entry goes: a bare tensor argument's
// axis is static at a size, and every other axis stays `?`.
Signature mapSignature(FunctionType type, ExtentsAttr extents, const LevelMap &map) {
  auto mapped = cast<FunctionType>(mapLevels(type, map));
  Signature at{SmallVector<Type>(mapped.getInputs()), SmallVector<Type>(mapped.getResults()), {},
               ExtentsAttr()};
  if (!extents)
    return at;
  // The terms that stay, one after another, written whole before any view
  // of them is taken, so no view outlives a reallocation.
  SmallVector<TermNode> nodes;
  SmallVector<std::pair<ExtentAt, size_t>> named;
  TermWriter write(nodes);
  for (ExtentAttr attr : extents.getEntries()) {
    Extent entry = attr.extent();
    size_t begin = nodes.size();
    map.write(write, entry.term);
    Term term(ArrayRef<TermNode>(nodes).drop_front(begin));
    if (term.freeLevels() != 0) {
      named.push_back({entry.at, begin});
      continue;
    }
    std::optional<int64_t> size = sizeOf(term);
    nodes.resize(begin);
    RankedTensorType array = staticArray(at.inputs, entry.at);
    if (!array || !size)
      continue;
    assert(array.isDynamicDim(entry.at.axis) && "an extent names an axis whose size is no constant");
    SmallVector<int64_t> shape(array.getShape());
    shape[entry.at.axis] = *size;
    at.inputs[entry.at.position] = array.clone(shape);
    // Entries come in (side, position, axis) order, so an input's axes are
    // one run, and the input is recorded at the first of them.
    if (at.fixed.empty() || at.fixed.back() != entry.at.position)
      at.fixed.push_back(entry.at.position);
  }
  if (named.empty())
    return at;
  SmallVector<Extent> entries = llvm::map_to_vector(named, [&](const auto &stays) {
    return Extent{stays.first, Term(ArrayRef<TermNode>(nodes).drop_front(stays.second))};
  });
  at.extents = ExtentsAttr::get(type.getContext(), entries);
  return at;
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

FunctionType substitute(FunctionType type, ExtentsAttr extents, IndexArgsAttr args) {
  uint32_t kept;
  return mapSignature(type, extents, mapOfArgs(args, kept)).type(type.getContext());
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

// A value the walk made more static where a tensor.cast reaches the type it
// had, and that type.
struct Refined {
  Value value;
  Type had;
};

// The uses of `refined` whose type is fixed elsewhere, through one
// tensor.cast back to the type it had, placed where the value is defined: a
// use by an op whose results do not follow from its operands (a block
// argument's, a yield to its parent's result, a return, an op that states
// its results), or by one whose inference refused the new operand. Every
// other use took the new type with the op's inferred results.
void castBack(const Refined &refined, ArrayRef<Operation *> refused) {
  SmallVector<OpOperand *> fixed;
  for (OpOperand &use : refined.value.getUses())
    if (!isa<InferTypeOpInterface>(use.getOwner()) || llvm::is_contained(refused, use.getOwner()))
      fixed.push_back(&use);
  if (fixed.empty())
    return;
  OpBuilder builder(refined.value.getContext());
  if (Operation *def = refined.value.getDefiningOp())
    builder.setInsertionPointAfter(def);
  else
    builder.setInsertionPointToStart(refined.value.getParentBlock());
  auto back = tensor::CastOp::create(builder, refined.value.getLoc(), refined.had, refined.value);
  for (OpOperand *use : fixed)
    use->set(back.getResult());
}

// The body under the copy's signature. Each argument a size made static
// takes its static type, and every type derived from the parameters follows
// in one walk in program order: each op whose results follow from its
// operands (upstream's InferTypeOpInterface) has them inferred again from
// its operands as they now are, a hold the caller set on a parameter as
// much as an axis made static. Where its results no longer agree with that
// inference by the op's own compatibility, an operand's type differs from
// the one the op was built with, and the op takes the inferred types; where
// they still agree it keeps its own, which may be more precise. The caller
// sets the holds before this runs, so the op's own agreement is the test,
// not a remembered type. Each op is met after every op whose results it
// reads, so one walk needs no fixpoint. A value made more static is cast
// back only for its uses whose type is fixed elsewhere; a cast left where
// nothing refines past it is the less optimized form, never wrong. A change
// of grade has no cast, and its uses read the new grade. Upstream's
// tensor.cast says what the Idris type proves, that the extent is the size.
void followOperands(FuncOp function, const Signature &at) {
  Block &entry = function.getBody().front();
  SmallVector<Refined> refined;
  for (uint32_t position : at.fixed) {
    BlockArgument arg = entry.getArgument(position);
    refined.push_back({arg, arg.getType()});
    arg.setType(at.inputs[position]);
  }
  // Inference is asked with no location, so a refusal reports nothing: the
  // op keeps the types it had through the casts back.
  SmallVector<Operation *> refused;
  function.walk([&](InferTypeOpInterface infer) {
    Operation *op = infer.getOperation();
    SmallVector<Type> inferred;
    if (failed(infer.inferReturnTypes(op->getContext(), std::nullopt, op->getOperands(),
                                      op->getRawDictionaryAttrs(), op->getPropertiesStorage(),
                                      op->getRegions(), inferred))) {
      refused.push_back(op);
      return;
    }
    if (infer.isCompatibleReturnTypes(inferred, op->getResultTypes()))
      return;
    for (auto [result, type] : llvm::zip_equal(op->getResults(), inferred)) {
      Type had = result.getType();
      result.setType(type);
      if (had != type &&
          tensor::CastOp::areCastCompatible(ArrayRef<Type>(type), ArrayRef<Type>(had)))
        refined.push_back({result, had});
    }
  });
  for (const Refined &value : refined)
    castBack(value, refused);
}

} // namespace

FailureOr<SmallVector<Sort>> substituteFunction(FuncOp function, IndexArgsAttr args) {
  ArrayRef<Sort> binders = function.getBinders().getSorts();
  if (args.getCount() != binders.size())
    return function.emitOpError("is instantiated at ")
           << args.getCount() << " terms for its " << binders.size() << " index variables";
  uint32_t kept;
  LevelMap map = mapOfArgs(args, kept);
  // The signature from the function's own, through the map the body takes:
  // the replacer reaches its family types but not what its extents make of
  // its axes, so the signature and the extents are set from this one
  // reading, the one substitute gives a call's view.
  Signature at = mapSignature(function.getFunctionType(), function.getExtentsAttr(), map);
  AttrTypeReplacer replacer;
  addLevelReplacements(replacer, map, FamilyAttr());
  replacer.replaceElementsIn(function, /*replaceAttrs=*/true, /*replaceLocs=*/false,
                             /*replaceTypes=*/true);
  replaceIn(replacer, function.getBody());
  pruneUninhabited(function);
  foldEqualCasts(function);
  function.setFunctionType(at.type(function.getContext()));
  function.setExtentsAttr(at.extents);
  followOperands(function, at);
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
// changes, so the call reaches a copy at that class. It is kept too where
// it makes an axis of a bare tensor argument a size, by the same test the
// signature's mapping makes, so the copy has that axis static as the
// call's view of it does.
std::optional<IndexArgsAttr> classesUnder(FunctionType signature, ExtentsAttr extents,
                                          IndexArgsAttr args) {
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
  if (extents)
    for (ExtentAttr attr : extents.getEntries()) {
      Extent entry = attr.extent();
      if (!staticArray(signature.getInputs(), entry.at))
        continue;
      SmallVector<TermNode> nodes;
      TermWriter write(nodes);
      closed.write(write, entry.term);
      if (!sizeOf(Term(nodes)))
        continue;
      for (const TermNode &node : entry.term.nodes())
        if (node.kind == TermKind::Level) {
          assert(node.value < count && "an extent's term names a binder of its function");
          keep[node.value] = true;
        }
    }
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
