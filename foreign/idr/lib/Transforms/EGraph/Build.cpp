// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Building one function's e-graph: the classification by declared effects,
// the walk that puts each op in a class or in its region's skeleton, the
// sweep of what the write-back left unused, and what a skeleton rule reads.
// The tables the walk fills are made in Nodes.cpp.
#include "idr/Transforms/EGraph/Engine.h"

#include "idr/IR/Effects/Query.h"

#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>

using namespace mlir;

namespace idr::egraph::detail {

//===----------------------------------------------------------------------===//
// Classification
//===----------------------------------------------------------------------===//

namespace {

// How an op enters the e-graph, read off its own effects as the one query
// API gives them: an op that only computes its result floats (memory it
// acquires that no value names is only reported); one whose result also
// takes a fresh identity, which an allocation is always of, is a node of
// its own; one that reads and changes nothing may merge with an equal read
// nothing between changes; every other op is ordered, and an op that
// declares nothing it does is among them, since it may do anything. A
// crash and a divergence are writes, so a call whose row carries either is
// ordered and never floats.
//
// An op whose value depends on its parent (DependsOnParent: the iteration
// index of the structured op around it) computes something else under
// another parent, so it is never one node with an equal op elsewhere: it
// stays where it is, under its parent, and is one value only with an equal
// op of the same region, which nothing between can change.
enum class Entry : std::uint8_t { Floats, OwnIdentity, Reads, OfParent, Ordered };

Entry entryOf(Operation *op, const effects::EffectSet &does) {
  using effects::Kind;
  if (!does.byKind[Kind::Write].empty() || !does.byKind[Kind::Free].empty())
    return Entry::Ordered;
  if (!does.byKind[Kind::Read].empty())
    return Entry::Reads;
  Entry alone = does.byKind[Kind::Allocate].empty() ? Entry::Floats : Entry::OwnIdentity;
  if (op->hasTrait<OpTrait::DependsOnParent>())
    return alone == Entry::Floats ? Entry::OfParent : Entry::Ordered;
  return alone;
}

// Whether `op` stays where it is whatever its effects: a terminator, a
// region op, an op of several results, and a call in tail position, whose
// fact a promise reads.
bool staysPut(Operation *op) {
  if (op->hasTrait<OpTrait::IsTerminator>() || op->getNumRegions() != 0 || op->getNumResults() != 1)
    return true;
  if (auto call = dyn_cast<CallOp>(op))
    return call.getTailKind() != TailKind::nontail;
  return false;
}

} // namespace

//===----------------------------------------------------------------------===//
// The walk
//===----------------------------------------------------------------------===//

Function::Function(idr::FuncOp fn, const Kinds &kinds, const CalleeFacts *callees)
    : fn(fn), kinds(kinds), callees(callees), numbering(fn),
      classOf(numbering.size(), std::optional<ClassId>()) {
  std::uint64_t ops = 0;
  fn.getBody().walk([&](Operation *) { ++ops; });
  budget = std::uint64_t(nodesPerOp()) * std::max<std::uint64_t>(ops, 1);
  slots.resize(64);
}

void Function::build() {
  RegionId body = newRegion({std::nullopt, 0, &fn.getBody(), {}});
  for (BlockArgument arg : fn.getBody().getArguments())
    classOf[numbering.at(arg)] = leaf(arg);

  // Each region's skeleton is a run of `skeleton`, gathered in a list per
  // region as the walk meets its ops and laid out once the walk is done.
  footprint::Vector<footprint::Vector<Skeletal>> perRegion(1);
  // An op each region may still merge a later equal op into, a read or an
  // op of the region's parent, with where in the region's list the ops
  // after it start: none of them may change what a read reads, and nothing
  // changes what an op of the parent computes there.
  struct Mergeable {
    Operation *op;
    std::uint32_t since;
  };
  footprint::Vector<footprint::Vector<Mergeable>> mergeable(1);
  // The regions the walk is in, innermost last, and the first region of
  // each region op it is inside.
  footprint::Vector<RegionId> open{body};
  footprint::Vector<RegionId> firstRegions;

  auto classesOf = [&](Operation *op) {
    SmallVector<ClassId, 4> operands;
    for (Value operand : op->getOperands())
      operands.push_back(*classOf[numbering.at(operand)]);
    return operands;
  };

  for (Operation &top : fn.getBody().front())
    top.walk([&](Operation *op, const WalkStage &stage) {
      if (!stage.isAfterAllRegions()) {
        if (stage.getNextRegion() > 0)
          open.pop_back();
        Region &region = op->getRegion(stage.getNextRegion());
        RegionId parent = open.back();
        RegionId id = newRegion({parent, at(parent).depth + 1, &region, {}});
        if (stage.getNextRegion() == 0)
          firstRegions.push_back(id);
        open.push_back(id);
        perRegion.emplace_back();
        mergeable.emplace_back();
        for (Block &block : region)
          for (BlockArgument arg : block.getArguments())
            classOf[numbering.at(arg)] = leaf(arg);
        return;
      }
      std::optional<RegionId> regions;
      if (op->getNumRegions() != 0) {
        open.pop_back();
        regions = firstRegions.back();
        firstRegions.pop_back();
      }
      RegionId region = open.back();
      effects::EffectSet does = effects::own(op);
      Entry entry = entryOf(op, does);
      if (!staysPut(op) && (entry == Entry::Floats || entry == Entry::OwnIdentity)) {
        SmallVector<ClassId, 4> operands = classesOf(op);
        Value result = op->getResult(0);
        Attribute known;
        std::optional<ClassId> cls =
            matchPattern(result, m_Constant(&known))
                ? constant(known, result.getType(), op->getDialect())
                : insert(op->getName(), kinds.kindOf(op), op,
                         entry == Entry::OwnIdentity ? Identity::Own : Identity::Shared,
                         result.getType(), operands, Rules::Run);
        classOf[numbering.at(result)] = *cls;
        return;
      }
      // A skeleton op: its results are leaves. A repeated read with nothing
      // between that may change it is the first read: no op between, with
      // everything in its regions, conflicts with what the read does, which
      // changes nothing. A repeated op of the region's parent is the first.
      footprint::Vector<Skeletal> &list = perRegion[region.index()];
      footprint::Vector<Mergeable> &earlier = mergeable[region.index()];
      Fate fate = Kept{};
      if ((entry == Entry::Reads || entry == Entry::OfParent) && !staysPut(op)) {
        auto unchanged = [&](const Mergeable &first) {
          if (entry == Entry::OfParent)
            return true;
          return llvm::none_of(llvm::ArrayRef<Skeletal>(list).drop_front(first.since),
                               [&](const Skeletal &between) {
                                 ++steps;
                                 return effects::whole(between.op).conflicts(does);
                               });
        };
        for (const Mergeable &first : earlier) {
          ++steps;
          if (first.op->getName() == op->getName() &&
              first.op->getResultTypes() == op->getResultTypes() &&
              classesOf(first.op) == classesOf(op) &&
              first.op->getRawDictionaryAttrs() == op->getRawDictionaryAttrs() &&
              op->getName().compareOpProperties(first.op->getPropertiesStorage(),
                                                op->getPropertiesStorage()) &&
              unchanged(first)) {
            fate = Merged{first.op};
            break;
          }
        }
        if (std::holds_alternative<Kept>(fate))
          earlier.push_back({op, static_cast<std::uint32_t>(list.size() + 1)});
      }
      if (const auto *merged = std::get_if<Merged>(&fate)) {
        for (auto [mine, theirs] : llvm::zip_equal(op->getResults(), merged->into->getResults()))
          classOf[numbering.at(mine)] = *classOf[numbering.at(theirs)];
      } else {
        for (Value result : op->getResults())
          classOf[numbering.at(result)] = leaf(result);
      }
      list.push_back({op, std::move(fate), regions});
    });

  for (auto [at, list] : llvm::enumerate(perRegion)) {
    regions[at].skeleton = {static_cast<std::uint32_t>(skeleton.size()),
                            static_cast<std::uint32_t>(list.size())};
    llvm::append_range(skeleton, list);
  }
}

// What the input's floating ops became: each was made again where it is
// demanded, or is demanded nowhere; and a value the write-back made for an
// op an edit then erased is demanded nowhere either. Every op that floats
// and is unused goes, users before what they use: one that floats has no
// effect to lose, and one with an identity is deletable when unused; so
// does an op of its parent no op uses, which has no effect either. The
// walk meets only ops still in the function, never one an edit erased with
// its region.
void Function::sweep(RewriterBase &rewriter) {
  footprint::Vector<Operation *> ops;
  fn.getBody().walk([&](Operation *op) {
    Entry entry = entryOf(op, effects::own(op));
    if (!staysPut(op) &&
        (entry == Entry::Floats || entry == Entry::OwnIdentity || entry == Entry::OfParent))
      ops.push_back(op);
  });
  for (Operation *op : llvm::reverse(ops))
    if (op->use_empty())
      rewriter.eraseOp(op);
}

//===----------------------------------------------------------------------===//
// What a skeleton rule reads
//===----------------------------------------------------------------------===//

const Class &Function::classOfValue(Value value) const {
  return at(*classOf[numbering.at(value)]);
}

Cost Function::costOf(Value value) const { return cost[classOf[numbering.at(value)]->index()]; }

// The skeleton rules, in the order the specification lists them, each
// asked of every skeleton op its root is, once the e-graph is extracted;
// the first that decides an edit has it. In the second round a Rewrite is
// kept as it is.
void Function::decide(Round round) {
  OperandFacts facts(*this);
  for (Skeletal &entry : skeleton) {
    if (!std::holds_alternative<Kept>(entry.fate))
      continue;
    Fate fate = decideSkeleton(entry.op, facts);
    if (const auto *decided = std::get_if<Decided>(&fate);
        decided && round == Round::Second && std::holds_alternative<Rewrite>(decided->edit))
      continue;
    entry.fate = std::move(fate);
  }
}

footprint::Vector<Function::Pending> Function::rewrites() const {
  footprint::Vector<Pending> out;
  for (const Skeletal &entry : skeleton)
    if (const auto *decided = std::get_if<Decided>(&entry.fate))
      if (const auto *rewrite = std::get_if<Rewrite>(&decided->edit))
        out.push_back({entry.op, decided->rule, *rewrite});
  return out;
}

// The op of the input the value's chosen member is, if it is one.
Operation *Function::originOf(Value value) const {
  const std::optional<NodeId> &chosen = best[classOf[numbering.at(value)]->index()];
  if (const auto *op = std::get_if<node::Op>(&at(*chosen).what))
    return op->origin;
  return nullptr;
}

} // namespace idr::egraph::detail
